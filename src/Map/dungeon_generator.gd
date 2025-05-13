class_name DungeonGenerator
extends Node

const entity_types = {
	"orc": preload("res://assets/definitions/entities/actors/entity_definition_orc.tres"),
	"troll": preload("res://assets/definitions/entities/actors/entity_definition_troll.tres"),
}

@export_category("Map Dimensions")
@export var map_width: int = 80
@export var map_height: int = 45

@export_category("Rooms RNG")
@export var max_rooms: int = 30
@export var room_max_size: int = 10
@export var room_min_size: int = 6

@export_category("Monsters RNG")
@export var max_monsters_per_room = 2

@export_category("Generation Steps")
@export_enum("BSP", "CellularAutomata", "Drunkard") var algorithm_steps: Array[int] = [0]

@export_category("Cellular Automata")
@export var ca_fill_chance: float = 0.45
@export var ca_steps: int = 5

@export_category("Drunkard's Walk")
@export var drunkard_steps: int = 2000

var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.randomize()

func generate_dungeon(player: Entity) -> MapData:
	var dungeon := MapData.new(map_width, map_height)
	dungeon.entities.append(player)

	for step in algorithm_steps:
		match step:
			# BSP
			0:
				_step_bsp(dungeon)
			# Cellular Automata
			1:
				_step_cellular_automata(dungeon)
			# Drunkard
			2:
				_step_drunkard(dungeon)

	# If no algorithm placed the player, put them at first floor tile
	for y in range(dungeon.height):
		for x in range(dungeon.width):
			if dungeon.get_tile(Vector2i(x, y)).tile_type == dungeon.tile_types.floor:
				player.grid_position = Vector2i(x, y)
				return dungeon

	return dungeon

# --- BSP Dungeon Generation (rooms & corridors) ---
func _step_bsp(dungeon: MapData) -> void:
	var rooms: Array[Rect2i] = []
	for _try_room in max_rooms:
		var room_width: int = _rng.randi_range(room_min_size, room_max_size)
		var room_height: int = _rng.randi_range(room_min_size, room_max_size)
		var x: int = _rng.randi_range(0, dungeon.width - room_width - 1)
		var y: int = _rng.randi_range(0, dungeon.height - room_height - 1)
		var new_room := Rect2i(x, y, room_width, room_height)
		var has_intersections := false
		for room in rooms:
			if room.intersects(new_room):
				has_intersections = true
				break
		if has_intersections:
			continue

		_carve_room(dungeon, new_room)

		if not rooms.is_empty():
			_tunnel_between(dungeon, rooms.back().get_center(), new_room.get_center())

		_place_entities(dungeon, new_room)

		rooms.append(new_room)

# --- Cellular Automata Dungeon Generation ---
func _step_cellular_automata(dungeon: MapData) -> void:
	# Fill map randomly
	for y in range(dungeon.height):
		for x in range(dungeon.width):
			var tile_type = dungeon.tile_types.wall
			if _rng.randf() < ca_fill_chance:
				tile_type = dungeon.tile_types.floor
			dungeon.get_tile(Vector2i(x, y)).set_tile_type(tile_type)

	# Run CA steps
	for _step in ca_steps:
		var new_map = []
		for y in range(dungeon.height):
			var row = []
			for x in range(dungeon.width):
				var wall_count = _count_adjacent_walls(dungeon, x, y)
				var tile_type = dungeon.tile_types.floor
				if wall_count >= 5:
					tile_type = dungeon.tile_types.wall
				row.append(tile_type)
			new_map.append(row)
		# Apply new map
		for y in range(dungeon.height):
			for x in range(dungeon.width):
				dungeon.get_tile(Vector2i(x, y)).set_tile_type(new_map[y][x])

	# Remove disconnected caves
	_clean_disconnected_areas(dungeon)

func _count_adjacent_walls(dungeon: MapData, x: int, y: int) -> int:
	var count = 0
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			var nx = x + dx
			var ny = y + dy
			if nx < 0 or ny < 0 or nx >= dungeon.width or ny >= dungeon.height:
				count += 1
			elif dungeon.get_tile(Vector2i(nx, ny)).tile_type == dungeon.tile_types.wall:
				count += 1
	return count

func _clean_disconnected_areas(dungeon: MapData) -> void:
	var width = dungeon.width
	var height = dungeon.height
	var visited = {}
	var queue = []
	var found_main = false

	# Find the first floor tile to start the flood fill
	for y in range(height):
		for x in range(width):
			var pos = Vector2i(x, y)
			if dungeon.get_tile(pos).tile_type == dungeon.tile_types.floor:
				queue.append(pos)
				visited[pos] = true
				found_main = true
				break
		if found_main:
			break

	# Flood fill to mark all connected floor tiles
	while not queue.is_empty():
		var current = queue.pop_front()
		for dir in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var neighbor = current + dir
			if neighbor.x < 0 or neighbor.y < 0 or neighbor.x >= width or neighbor.y >= height:
				continue
			if visited.has(neighbor):
				continue
			if dungeon.get_tile(neighbor).tile_type == dungeon.tile_types.floor:
				visited[neighbor] = true
				queue.append(neighbor)

	# Any floor tile not visited is not connected to the main cave, so fill with wall
	for y in range(height):
		for x in range(width):
			var pos = Vector2i(x, y)
			if dungeon.get_tile(pos).tile_type == dungeon.tile_types.floor and not visited.has(pos):
				dungeon.get_tile(pos).set_tile_type(dungeon.tile_types.wall)

# --- Drunkard's Walk Dungeon Generation ---
func _step_drunkard(dungeon: MapData) -> void:
	# If the map is all walls, start from center
	var all_walls := true
	for y in range(dungeon.height):
		for x in range(dungeon.width):
			if dungeon.get_tile(Vector2i(x, y)).tile_type != dungeon.tile_types.wall:
				all_walls = false
				break

	var pos = Vector2i(dungeon.width / 2, dungeon.height / 2)
	if not all_walls:
		# Find a floor tile to start from
		for y in range(dungeon.height):
			for x in range(dungeon.width):
				if dungeon.get_tile(Vector2i(x, y)).tile_type == dungeon.tile_types.floor:
					pos = Vector2i(x, y)
					break

	dungeon.get_tile(pos).set_tile_type(dungeon.tile_types.floor)

	for _step in drunkard_steps:
		var dir = _rng.randi_range(0, 3)
		match dir:
			0: pos.x = clamp(pos.x + 1, 1, dungeon.width - 2)
			1: pos.x = clamp(pos.x - 1, 1, dungeon.width - 2)
			2: pos.y = clamp(pos.y + 1, 1, dungeon.height - 2)
			3: pos.y = clamp(pos.y - 1, 1, dungeon.height - 2)
		dungeon.get_tile(pos).set_tile_type(dungeon.tile_types.floor)

# --- Room/Tile Carving and Tunneling ---
func _carve_room(dungeon: MapData, room: Rect2i) -> void:
	var inner: Rect2i = room.grow(-1)
	for y in range(inner.position.y, inner.end.y + 1):
		for x in range(inner.position.x, inner.end.x + 1):
			_carve_tile(dungeon, x, y)

func _tunnel_horizontal(dungeon: MapData, y: int, x_start: int, x_end: int) -> void:
	var x_min: int = mini(x_start, x_end)
	var x_max: int = maxi(x_start, x_end)
	for x in range(x_min, x_max + 1):
		_carve_tile(dungeon, x, y)

func _tunnel_vertical(dungeon: MapData, x: int, y_start: int, y_end: int) -> void:
	var y_min: int = mini(y_start, y_end)
	var y_max: int = maxi(y_start, y_end)
	for y in range(y_min, y_max + 1):
		_carve_tile(dungeon, x, y)

func _tunnel_between(dungeon: MapData, start: Vector2i, end: Vector2i) -> void:
	if _rng.randf() < 0.5:
		_tunnel_horizontal(dungeon, start.y, start.x, end.x)
		_tunnel_vertical(dungeon, end.x, start.y, end.y)
	else:
		_tunnel_vertical(dungeon, start.x, start.y, end.y)
		_tunnel_horizontal(dungeon, end.y, start.x, end.x)

func _carve_tile(dungeon: MapData, x: int, y: int) -> void:
	var tile_position = Vector2i(x, y)
	var tile: Tile = dungeon.get_tile(tile_position)
	tile.set_tile_type(dungeon.tile_types.floor)

func _place_entities(dungeon: MapData, room: Rect2i) -> void:
	var number_of_monsters: int = _rng.randi_range(0, max_monsters_per_room)

	for _i in number_of_monsters:
		var x: int = _rng.randi_range(room.position.x + 1, room.end.x - 1)
		var y: int = _rng.randi_range(room.position.y + 1, room.end.y - 1)
		var new_entity_position := Vector2i(x, y)

		var can_place = true
		for entity in dungeon.entities:
			if entity.grid_position == new_entity_position:
				can_place = false
				break

		if can_place:
			var new_entity: Entity
			if _rng.randf() < 0.8:
				new_entity = Entity.new(new_entity_position, entity_types.orc)
			else:
				new_entity = Entity.new(new_entity_position, entity_types.troll)
			dungeon.entities.append(new_entity)
