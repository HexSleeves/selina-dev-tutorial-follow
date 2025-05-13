class_name ItemAction
extends Action

var item: Entity
var target_position: Vector2i


func _init(ent: Entity, item_entity: Entity, target_pos = null) -> void:
	super._init(ent)
	self.item = item_entity
	if not target_pos is Vector2i:
		target_pos = ent.grid_position
	self.target_position = target_pos


func get_target_actor() -> Entity:
	return get_map_data().get_actor_at_location(target_position)


func perform() -> bool:
	if item == null:
		return false
	return item.consumable_component.activate(self)
