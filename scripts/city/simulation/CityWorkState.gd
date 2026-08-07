extends RefCounted
class_name CityWorkState

# Mutable player-command and parent work-order state for one CITY settlement.
# Scheduling/validation behavior belongs to CityWorkSystem; this object owns
# only the data, indexes, counters, and focused change versions for that system.
# It deliberately has no WorldData dependency.

var player_commands: Array = []
var player_command_index_by_id: Dictionary = {}
var player_command_id_by_tile: Dictionary = {}
var next_player_command_id: int = 1
var next_player_command_group_id: int = 1
var player_command_version: int = 0

var work_orders: Dictionary = {}
var work_order_id_by_source_key: Dictionary = {}
var next_work_order_id: int = 1
var work_order_version: int = 0


func reset_all() -> void:
	reset_player_commands()
	reset_work_orders()


func reset_player_commands() -> void:
	player_commands.clear()
	player_command_index_by_id.clear()
	player_command_id_by_tile.clear()
	next_player_command_id = 1
	next_player_command_group_id = 1
	mark_player_commands_changed()


func reset_work_orders() -> void:
	work_orders.clear()
	work_order_id_by_source_key.clear()
	next_work_order_id = 1
	mark_work_orders_changed()


func mark_player_commands_changed() -> void:
	player_command_version += 1


func mark_work_orders_changed() -> void:
	work_order_version += 1


func rebuild_player_command_index(invalid_tile_position: Vector2i) -> void:
	player_command_index_by_id.clear()
	player_command_id_by_tile.clear()

	for command_index in range(player_commands.size()):
		var raw_command = player_commands[command_index]
		if not raw_command is Dictionary:
			continue

		var command: Dictionary = raw_command
		var command_id := int(command.get("id", -1))
		var raw_tile_position = command.get(
			"tile_position",
			invalid_tile_position
		)
		if command_id <= 0 or not raw_tile_position is Vector2i:
			continue

		player_command_index_by_id[command_id] = command_index
		player_command_id_by_tile[raw_tile_position] = command_id


func get_player_command_index_by_id(command_id: int) -> int:
	if command_id <= 0 or not player_command_index_by_id.has(command_id):
		return -1

	var command_index := int(player_command_index_by_id[command_id])
	if command_index < 0 or command_index >= player_commands.size():
		return -1
	return command_index


func get_player_command_by_id(command_id: int) -> Dictionary:
	var command_index := get_player_command_index_by_id(command_id)
	if command_index < 0:
		return {}

	var raw_command = player_commands[command_index]
	if not raw_command is Dictionary:
		return {}
	return (raw_command as Dictionary).duplicate(true)


func get_player_command_snapshot() -> Array:
	return player_commands.duplicate(true)


func get_work_order_by_id(order_id: int) -> Dictionary:
	if order_id <= 0 or not work_orders.has(order_id):
		return {}

	var raw_order = work_orders.get(order_id, {})
	if not raw_order is Dictionary:
		return {}
	return (raw_order as Dictionary).duplicate(true)


func get_work_order_snapshot() -> Array:
	var snapshot: Array = []
	var order_ids: Array = work_orders.keys()
	order_ids.sort()

	for raw_order_id in order_ids:
		var order := get_work_order_by_id(int(raw_order_id))
		if not order.is_empty():
			snapshot.append(order)

	return snapshot
