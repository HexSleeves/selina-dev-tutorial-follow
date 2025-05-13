class_name ConsumableComponent
extends Component


func get_action(consumer: Entity) -> Action:
	return ItemAction.new(consumer, entity)


@warning_ignore("unused_parameter")
func activate(action: ItemAction) -> bool:
	return false


func consume(consumer: Entity) -> void:
	var inventory: InventoryComponent = consumer.inventory_component
	inventory.items.erase(entity)
	entity.queue_free()
