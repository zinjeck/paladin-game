extends RefCounted
class_name CityWorkState

# Mutable player-command and parent work-order state for one CITY settlement.
# CityWorkSystem owns scheduling and public work APIs. This object owns the
# records, indexes, counters, versions, and record-level invariants/mutations.
# It deliberately has no WorldData dependency.

const PLAYER_COMMAND_TYPE_NONE := "none"
const PLAYER_COMMAND_TYPE_CHOP_TREE := "chop_tree"
const PLAYER_COMMAND_TYPE_COLLECT_ROCK := "collect_rock"
const PLAYER_COMMAND_STATUS_PENDING := "pending"
const PLAYER_COMMAND_STATUS_BLOCKED := "blocked"
const SURFACE_FEATURE_NONE := "none"
const SURFACE_FEATURE_TREE := "tree"
const SURFACE_FEATURE_ROCK := "rock"

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


func get_player_command_surface_feature(command_type: String) -> String:
	match command_type:
		PLAYER_COMMAND_TYPE_CHOP_TREE:
			return SURFACE_FEATURE_TREE
		PLAYER_COMMAND_TYPE_COLLECT_ROCK:
			return SURFACE_FEATURE_ROCK
	return SURFACE_FEATURE_NONE


func is_player_command_target_valid(
	command: Dictionary,
	city_world,
	invalid_tile_position: Vector2i
) -> bool:
	var command_type := str(
		command.get("type", PLAYER_COMMAND_TYPE_NONE)
	)
	var raw_tile_position = command.get(
		"tile_position",
		invalid_tile_position
	)
	var expected_surface_feature := get_player_command_surface_feature(
		command_type
	)

	if (
		city_world == null
		or expected_surface_feature == SURFACE_FEATURE_NONE
		or not raw_tile_position is Vector2i
	):
		return false

	var tile_position: Vector2i = raw_tile_position
	if not city_world.is_in_bounds(tile_position.x, tile_position.y):
		return false

	var tile = city_world.get_tile(tile_position.x, tile_position.y)
	if not tile is Dictionary:
		return false

	return str(tile.get("surface_feature", SURFACE_FEATURE_NONE)) == expected_surface_feature


func release_player_command_claim(
	command_id: int,
	citizen_id: int,
	blocked_retry_minute: int = -1
) -> bool:
	var command_index := get_player_command_index_by_id(command_id)
	if command_index < 0:
		return false

	var command: Dictionary = player_commands[command_index]
	if int(command.get("claimed_citizen_id", -1)) != citizen_id:
		return false

	command["claimed_citizen_id"] = -1
	if blocked_retry_minute >= 0:
		command["status"] = PLAYER_COMMAND_STATUS_BLOCKED
		command["next_retry_world_minute"] = blocked_retry_minute
	else:
		command["status"] = PLAYER_COMMAND_STATUS_PENDING
		command["next_retry_world_minute"] = -1

	player_commands[command_index] = command
	mark_player_commands_changed()
	return true


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
