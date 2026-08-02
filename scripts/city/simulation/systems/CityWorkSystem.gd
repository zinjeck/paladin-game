extends RefCounted
class_name CityWorkSystem

# File responsibility: Player-command and work-order operations, scheduling, job generation, assignment, and diagnostics. Authoritative collections remain in WorldData.
# Navigation regions are organizational only; they do not define runtime ownership.

const CityConstructionSystemScript = preload(
	"res://scripts/city/simulation/systems/CityConstructionSystem.gd"
)
const CityResourceMatcherScript = preload(
	"res://scripts/city/simulation/systems/CityResourceMatcher.gd"
)
const CityNavigationSystemScript = preload(
	"res://scripts/city/simulation/systems/CityNavigationSystem.gd"
)

# Parent work orders are selected before their individual jobs. This keeps a
# large drag designation from receiving more scheduler weight merely because
# it contains more tiles than a building or road order.
const ORDER_TYPE_COMMAND_GROUP := "command_group"
const ORDER_TYPE_CONSTRUCTION_SITE := "construction_site"

const ORDER_STATE_ACTIVE := "active"
const ORDER_STATE_BLOCKED := "blocked"
const ORDER_STATE_CANCELLED := "cancelled"

const PRIORITY_LOW: int = 0
const PRIORITY_NORMAL: int = 1
const PRIORITY_HIGH: int = 2
const PRIORITY_URGENT: int = 3

const JOB_KIND_CHOP_TREE := "chop_tree"
const JOB_KIND_COLLECT_ROCK := "collect_rock"
const JOB_KIND_CLEARING_RELOCATION := "clearing_relocation"
const JOB_KIND_CONSTRUCTION_DELIVERY := "construction_delivery"
const JOB_KIND_CONSTRUCTION_LABOR := "construction_labor"

const JOB_STATE_ACTIONABLE := "actionable"
const JOB_STATE_ACTIVE := "active"
const JOB_STATE_BLOCKED := "blocked"

const ORDER_PHASE_COMMANDS := "commands"

const BLOCKED_REASON_NONE := ""
const BLOCKED_REASON_NO_ELIGIBLE_WORKER := "NO_ELIGIBLE_WORKER"
const BLOCKED_REASON_NO_REACHABLE_WORK_POSITION := (
	"NO_REACHABLE_WORK_POSITION"
)
const BLOCKED_REASON_SOURCE_EMPTY := "SOURCE_EMPTY"
const BLOCKED_REASON_SOURCE_FULLY_RESERVED := "SOURCE_FULLY_RESERVED"
const BLOCKED_REASON_NO_LEGAL_SOURCE := "NO_LEGAL_SOURCE"
const BLOCKED_REASON_DESTINATION_FULL := "DESTINATION_FULL"
const BLOCKED_REASON_NO_LEGAL_DESTINATION := "NO_LEGAL_DESTINATION"
const BLOCKED_REASON_WAITING_FOR_CLEARING := "WAITING_FOR_CLEARING"
const BLOCKED_REASON_WAITING_FOR_MATERIALS := "WAITING_FOR_MATERIALS"
const BLOCKED_REASON_WAITING_FOR_SAFE_BOUNDARY := (
	"WAITING_FOR_SAFE_BOUNDARY"
)
const BLOCKED_REASON_MAX_USEFUL_WORKERS := "MAX_USEFUL_WORKERS"
const BLOCKED_REASON_CLAIMED := "CLAIMED"
const BLOCKED_REASON_CANCELLED := "CANCELLED"
const BLOCKED_REASON_INVALIDATED := "INVALIDATED"

# Level-A scheduler constants. Priority ranks are deliberately separated by a
# margin larger than every bounded secondary term. Distance can make nearby
# work attractive, but neglect can eventually overcome the entire locality
# benefit without growing without limit.
const PRIORITY_RANK_SCORE: int = 1_000_000
const NEGLECT_SCORE_PER_MINUTE: int = 1_000
const MAX_NEGLECT_SCORE: int = 120_000
const AGE_SCORE_PER_MINUTE: int = 100
const MAX_AGE_SCORE: int = 20_000
const MAX_LOCALITY_SCORE: int = 40_000
const LOCALITY_PATH_COST_CAP: int = 160_000
const MAX_ACTIVE_WORKER_PENALTY: int = 100_000
const PROGRESS_UNLOCK_SCORE: int = 35_000
const EXACT_COMMAND_PATH_HEURISTIC_WEIGHT: int = 1


#region Player Command and Work Order Operations



static func get_city_player_command_display_name(
	command_type: String
) -> String:
	match command_type:
		WorldData.CITY_PLAYER_COMMAND_TYPE_CHOP_TREE:
			return "Chop Tree"

		WorldData.CITY_PLAYER_COMMAND_TYPE_COLLECT_ROCK:
			return "Collect Rock"

	return "Player Command"


static func get_city_player_command_resource_type(
	command_type: String
) -> String:
	return WorldData.get_city_surface_feature_resource_type(
		WorldData.get_city_player_command_surface_feature(command_type)
	)



static func get_city_work_order_by_id(order_id: int) -> Dictionary:
	if order_id <= 0 or not WorldData.city_work_orders.has(order_id):
		return {}

	var raw_order = WorldData.city_work_orders.get(order_id, {})

	if not raw_order is Dictionary:
		return {}

	return raw_order.duplicate(true)

static func get_city_work_order_snapshot() -> Array:
	var snapshot: Array = []
	var order_ids: Array = WorldData.city_work_orders.keys()
	order_ids.sort()

	for raw_order_id in order_ids:
		var order := get_city_work_order_by_id(int(raw_order_id))

		if not order.is_empty():
			snapshot.append(order)

	return snapshot


static func rebuild_city_player_command_index() -> void:
	WorldData.city_player_command_index_by_id.clear()
	WorldData.city_player_command_id_by_tile.clear()

	for command_index in range(WorldData.city_player_commands.size()):
		var raw_command = WorldData.city_player_commands[command_index]

		if not raw_command is Dictionary:
			continue

		var command: Dictionary = raw_command
		var command_id := int(command.get("id", -1))
		var raw_tile_position = command.get(
			"tile_position",
			WorldData.INVALID_CITY_TILE_POSITION
		)

		if command_id <= 0 or not raw_tile_position is Vector2i:
			continue

		WorldData.city_player_command_index_by_id[command_id] = command_index
		WorldData.city_player_command_id_by_tile[raw_tile_position] = command_id



static func get_city_player_command_snapshot() -> Array:
	return WorldData.city_player_commands.duplicate(true)

static func get_city_player_command_at_tile(
	tile_position: Vector2i
) -> Dictionary:
	if not WorldData.city_player_command_id_by_tile.has(tile_position):
		return {}

	return WorldData.get_city_player_command_by_id(
		int(WorldData.city_player_command_id_by_tile[tile_position])
	)

static func can_designate_city_player_command_at_tile(
	command_type: String,
	tile_position: Vector2i
) -> bool:
	var city_world: WorldData = WorldData.official_city_world

	if (
		city_world == null
		or not WorldData.is_valid_city_player_command_type(command_type)
		or not city_world.is_in_bounds(tile_position.x, tile_position.y)
		or WorldData.city_player_command_id_by_tile.has(tile_position)
	):
		return false

	var tile := city_world.get_tile(tile_position.x, tile_position.y)

	return (
		WorldData.get_city_surface_feature(tile)
		== WorldData.get_city_player_command_surface_feature(command_type)
	)

static func add_city_player_command_targets(
	command_type: String,
	raw_tile_positions: Array
) -> int:
	if (
		WorldData.official_city_world == null
		or not WorldData.is_valid_city_player_command_type(command_type)
	):
		return 0

	var clean_tiles: Array[Vector2i] = []
	var visited_tiles: Dictionary = {}

	for raw_tile_position in raw_tile_positions:
		if not raw_tile_position is Vector2i:
			continue

		var tile_position: Vector2i = raw_tile_position

		if visited_tiles.has(tile_position):
			continue

		visited_tiles[tile_position] = true

		if can_designate_city_player_command_at_tile(
			command_type,
			tile_position
		):
			clean_tiles.append(tile_position)

	if clean_tiles.is_empty():
		return 0

	clean_tiles.sort_custom(WorldData._sort_city_tiles_y_then_x)

	var group_id := WorldData.next_city_player_command_group_id
	WorldData.next_city_player_command_group_id += 1

	for tile_position in clean_tiles:
		var command_id := WorldData.next_city_player_command_id
		WorldData.next_city_player_command_id += 1

		var command := {
			"id": command_id,
			"group_id": group_id,
			"type": command_type,
			"tile_position": tile_position,
			"status": WorldData.CITY_PLAYER_COMMAND_STATUS_PENDING,
			"claimed_citizen_id": -1,
			"issued_world_minute": SimulationClock.absolute_world_minutes,
			"next_retry_world_minute": -1,
			"work_duration_minutes": (
				WorldData.CITY_PLAYER_COMMAND_WORK_DURATION_MINUTES
			),
			"resource_yield": WorldData.CITY_PLAYER_COMMAND_RESOURCE_YIELD,
			"construction_site_id": -1,
			"created_by_construction": false,
		}

		WorldData.city_player_commands.append(command)
		WorldData.city_player_command_index_by_id[command_id] = (
			WorldData.city_player_commands.size() - 1
		)
		WorldData.city_player_command_id_by_tile[tile_position] = command_id

	WorldData._mark_city_player_commands_changed()
	return clean_tiles.size()

static func ensure_city_construction_clearing_command(
	site_id: int,
	command_type: String,
	tile_position: Vector2i
) -> int:
	var site := WorldData.get_city_construction_site_by_id(site_id)

	if (
		site.is_empty()
		or not site.get("footprint_tiles", []).has(tile_position)
		or not can_designate_city_player_command_at_tile(
			command_type,
			tile_position
		)
		and get_city_player_command_at_tile(tile_position).is_empty()
	):
		return -1

	var existing_command := get_city_player_command_at_tile(
		tile_position
	)

	if not existing_command.is_empty():
		if (
			str(existing_command.get("type", ""))
			!= command_type
			or int(
				existing_command.get(
					"construction_site_id",
					-1
				)
			) not in [-1, site_id]
		):
			return -1

		var command_id := int(existing_command.get("id", -1))
		var command_index := WorldData.get_city_player_command_index_by_id(
			command_id
		)

		if command_index < 0:
			return -1

		existing_command["construction_site_id"] = site_id
		existing_command["created_by_construction"] = bool(
			existing_command.get(
				"created_by_construction",
				false
			)
		)
		WorldData.city_player_commands[command_index] = existing_command
		WorldData._mark_city_player_commands_changed()
		return command_id

	if add_city_player_command_targets(
		command_type,
		[tile_position]
	) != 1:
		return -1

	var command := get_city_player_command_at_tile(tile_position)
	var command_id := int(command.get("id", -1))
	var command_index := WorldData.get_city_player_command_index_by_id(command_id)

	if command_index < 0:
		return -1

	command["construction_site_id"] = site_id
	command["created_by_construction"] = true
	WorldData.city_player_commands[command_index] = command
	WorldData._mark_city_player_commands_changed()
	return command_id

static func detach_city_player_command_from_construction(
	command_id: int,
	site_id: int
) -> bool:
	var command_index := WorldData.get_city_player_command_index_by_id(command_id)

	if command_index < 0:
		return false

	var command: Dictionary = WorldData.city_player_commands[command_index]

	if int(command.get("construction_site_id", -1)) != site_id:
		return false

	command["construction_site_id"] = -1
	command["created_by_construction"] = false
	WorldData.city_player_commands[command_index] = command
	WorldData._mark_city_player_commands_changed()
	return true

static func city_player_command_is_for_construction(
	command: Dictionary
) -> bool:
	return int(command.get("construction_site_id", -1)) > 0

static func _remove_city_player_command_record(
	command_id: int
) -> bool:
	var command_index := WorldData.get_city_player_command_index_by_id(command_id)

	if command_index < 0:
		return false

	var command: Dictionary = WorldData.city_player_commands[command_index]
	var independent_group_id := -1

	if int(command.get("construction_site_id", -1)) <= 0:
		independent_group_id = int(command.get("group_id", -1))

	WorldData.city_player_commands.remove_at(command_index)
	rebuild_city_player_command_index()
	WorldData._mark_city_player_commands_changed()
	_remove_empty_command_group_order(independent_group_id)
	return true

static func _remove_empty_command_group_order(group_id: int) -> void:
	if group_id <= 0:
		return

	for raw_command in WorldData.city_player_commands:
		if (
			raw_command is Dictionary
			and int(raw_command.get("group_id", -1)) == group_id
			and int(raw_command.get("construction_site_id", -1)) <= 0
		):
			return

	var source_key := _make_command_group_source_key(group_id)
	var order_id := int(
		WorldData.city_work_order_id_by_source_key.get(source_key, -1)
	)

	if order_id > 0:
		_remove_order_record(order_id)

static func cancel_city_player_command(command_id: int) -> bool:
	var command := WorldData.get_city_player_command_by_id(command_id)

	if command.is_empty():
		return false

	var claimed_citizen_id := int(
		command.get("claimed_citizen_id", -1)
	)

	if claimed_citizen_id > 0:
		var current_task := WorldData.get_city_citizen_current_task(
			claimed_citizen_id
		)

		if (
			str(current_task.get("kind", ""))
			== WorldData.CITY_CITIZEN_TASK_KIND_PLAYER_COMMAND
			and int(current_task.get("target_object_id", -1))
			== command_id
		):
			WorldData.clear_city_citizen_task(
				claimed_citizen_id,
				WorldData.CITY_CITIZEN_TASK_SOURCE_PLAYER
			)
			WorldData.cancel_city_citizen_movement(claimed_citizen_id)

	return _remove_city_player_command_record(command_id)

static func remove_city_player_commands_at_tiles(
	command_type: String,
	raw_tile_positions: Array
) -> int:
	var command_ids: Array[int] = []
	var visited_command_ids: Dictionary = {}

	for raw_tile_position in raw_tile_positions:
		if not raw_tile_position is Vector2i:
			continue

		var command := get_city_player_command_at_tile(raw_tile_position)

		if command.is_empty():
			continue

		if (
			command_type != WorldData.CITY_PLAYER_COMMAND_TYPE_NONE
			and str(command.get("type", "")) != command_type
		):
			continue

		var command_id := int(command.get("id", -1))

		if command_id <= 0 or visited_command_ids.has(command_id):
			continue

		visited_command_ids[command_id] = true
		command_ids.append(command_id)

	command_ids.sort()
	var removed_count := 0

	for command_id in command_ids:
		if cancel_city_player_command(command_id):
			removed_count += 1

	return removed_count


static func prune_invalid_city_player_commands() -> int:
	var invalid_command_ids: Array[int] = []

	for raw_command in WorldData.city_player_commands:
		if not raw_command is Dictionary:
			continue

		var command: Dictionary = raw_command

		if WorldData.is_city_player_command_target_valid(command):
			continue

		invalid_command_ids.append(int(command.get("id", -1)))

	var removed_count := 0

	for command_id in invalid_command_ids:
		if cancel_city_player_command(command_id):
			removed_count += 1

	return removed_count

static func repair_stale_city_player_command_claims() -> int:
	var repaired_count := 0

	for command_index in range(WorldData.city_player_commands.size()):
		var raw_command = WorldData.city_player_commands[command_index]

		if not raw_command is Dictionary:
			continue

		var command: Dictionary = raw_command
		var command_id := int(command.get("id", -1))
		var claimed_citizen_id := int(
			command.get("claimed_citizen_id", -1)
		)
		var status := str(command.get("status", ""))
		var claim_is_live := false

		if (
			command_id > 0
			and claimed_citizen_id > 0
			and status == WorldData.CITY_PLAYER_COMMAND_STATUS_CLAIMED
		):
			var citizen := WorldData.get_city_citizen_by_id(claimed_citizen_id)
			var current_task := WorldData.get_city_citizen_current_task(
				claimed_citizen_id
			)

			claim_is_live = (
				not citizen.is_empty()
				and bool(citizen.get("alive", false))
				and int(citizen.get("job_object_id", -1)) <= 0
				and str(current_task.get("kind", ""))
				== WorldData.CITY_CITIZEN_TASK_KIND_PLAYER_COMMAND
				and str(current_task.get("source", ""))
				== WorldData.CITY_CITIZEN_TASK_SOURCE_PLAYER
				and int(current_task.get("target_object_id", -1))
				== command_id
			)

		if claim_is_live:
			continue

		var has_stale_claim := (
			claimed_citizen_id > 0
			or status == WorldData.CITY_PLAYER_COMMAND_STATUS_CLAIMED
		)

		if not has_stale_claim:
			continue

		command["claimed_citizen_id"] = -1
		command["status"] = WorldData.CITY_PLAYER_COMMAND_STATUS_PENDING
		command["next_retry_world_minute"] = -1
		WorldData.city_player_commands[command_index] = command
		repaired_count += 1

	if repaired_count > 0:
		WorldData._mark_city_player_commands_changed()

	return repaired_count

static func city_player_command_is_assignable(
	command: Dictionary
) -> bool:
	if not WorldData.is_city_player_command_target_valid(command):
		return false

	if int(command.get("claimed_citizen_id", -1)) > 0:
		return false

	var status := str(command.get("status", ""))

	if status == WorldData.CITY_PLAYER_COMMAND_STATUS_PENDING:
		return true

	return (
		status == WorldData.CITY_PLAYER_COMMAND_STATUS_BLOCKED
		and int(command.get("next_retry_world_minute", -1))
		<= SimulationClock.absolute_world_minutes
	)

static func get_city_player_command_work_tiles(
	command: Dictionary,
	citizen_id: int
) -> Array[Vector2i]:
	var work_tiles: Array[Vector2i] = []
	var raw_command_tile = command.get(
		"tile_position",
		WorldData.INVALID_CITY_TILE_POSITION
	)

	if WorldData.official_city_world == null or not raw_command_tile is Vector2i:
		return work_tiles

	var command_tile: Vector2i = raw_command_tile

	for offset_y in range(-1, 2):
		for offset_x in range(-1, 2):
			var candidate_tile := (
				command_tile + Vector2i(offset_x, offset_y)
			)

			if WorldData.is_city_tile_walkable_for_citizen(
				WorldData.official_city_world,
				candidate_tile,
				citizen_id
			):
				work_tiles.append(candidate_tile)

	work_tiles.sort_custom(WorldData._sort_city_tiles_y_then_x)
	return work_tiles

static func get_best_assignable_city_player_command_for_citizen(
	citizen_id: int
) -> Dictionary:
	var citizen := WorldData.get_city_citizen_by_id(citizen_id)
	var raw_citizen_tile = citizen.get(
		"city_tile_position",
		WorldData.INVALID_CITY_TILE_POSITION
	)

	if (
		citizen.is_empty()
		or not bool(citizen.get("alive", false))
		or int(citizen.get("job_object_id", -1)) > 0
		or not raw_citizen_tile is Vector2i
	):
		return {}

	var citizen_tile: Vector2i = raw_citizen_tile
	var best_command: Dictionary = {}
	var best_cost := 0
	var best_command_id := 0

	for raw_command in WorldData.city_player_commands:
		if not raw_command is Dictionary:
			continue

		var command: Dictionary = raw_command

		if not city_player_command_is_assignable(command):
			continue

		var target_tile: Vector2i = command["tile_position"]
		var distance_x := absi(target_tile.x - citizen_tile.x)
		var distance_y := absi(target_tile.y - citizen_tile.y)
		var diagonal_steps := mini(distance_x, distance_y)
		var straight_steps := maxi(distance_x, distance_y) - diagonal_steps
		var estimated_cost := (
			diagonal_steps * 14_142
			+ straight_steps * 10_000
		)
		var command_age_minutes := maxi(
			SimulationClock.absolute_world_minutes
			- int(command.get("issued_world_minute", 0)),
			0
		)
		var fairness_bonus := mini(
			command_age_minutes
			* WorldData.CITY_CONSTRUCTION_FAIRNESS_BONUS_PER_MINUTE,
			WorldData.CITY_CONSTRUCTION_MAX_FAIRNESS_BONUS
		)
		var selection_score := estimated_cost - fairness_bonus
		var command_id := int(command.get("id", -1))

		if (
			best_command.is_empty()
			or selection_score < best_cost
			or (
				selection_score == best_cost
				and command_id < best_command_id
			)
		):
			best_command = command.duplicate(true)
			best_command["player_work_kind"] = "command"
			best_command["estimated_path_cost"] = estimated_cost
			best_command["selection_score"] = selection_score
			best_cost = selection_score
			best_command_id = command_id

	return best_command

static func claim_city_player_command(
	command_id: int,
	citizen_id: int
) -> bool:
	var command_index := WorldData.get_city_player_command_index_by_id(command_id)
	var citizen := WorldData.get_city_citizen_by_id(citizen_id)

	if (
		command_index < 0
		or citizen.is_empty()
		or not bool(citizen.get("alive", false))
		or int(citizen.get("job_object_id", -1)) > 0
	):
		return false

	var command: Dictionary = WorldData.city_player_commands[command_index]

	if not city_player_command_is_assignable(command):
		return false

	command["status"] = WorldData.CITY_PLAYER_COMMAND_STATUS_CLAIMED
	command["claimed_citizen_id"] = citizen_id
	command["next_retry_world_minute"] = -1
	WorldData.city_player_commands[command_index] = command
	WorldData._mark_city_player_commands_changed()
	return true


static func complete_city_player_command(
	command_id: int,
	citizen_id: int
) -> bool:
	var command := WorldData.get_city_player_command_by_id(command_id)

	if (
		command.is_empty()
		or int(command.get("claimed_citizen_id", -1)) != citizen_id
		or not WorldData.is_city_player_command_target_valid(command)
	):
		return false

	var city_world: WorldData = WorldData.official_city_world
	var command_type := str(command.get("type", ""))
	var tile_position: Vector2i = command["tile_position"]
	var expected_feature := WorldData.get_city_player_command_surface_feature(
		command_type
	)
	var resource := get_city_player_command_resource_type(command_type)
	var resource_yield := maxi(
		int(
			command.get(
				"resource_yield",
				WorldData.CITY_PLAYER_COMMAND_RESOURCE_YIELD
			)
		),
		0
	)
	var tile := city_world.get_tile(tile_position.x, tile_position.y)

	if (
		expected_feature == WorldData.CITY_SURFACE_FEATURE_NONE
		or not WorldData.is_city_resource_type(resource)
		or resource_yield <= 0
		or WorldData.get_city_surface_feature(tile) != expected_feature
	):
		return false

	# Remove the feature first so tree tiles become valid ground-pile tiles.
	# If physical output cannot be created, restore the feature atomically.
	tile.erase("surface_feature")

	var construction_site_id := int(
		command.get("construction_site_id", -1)
	)
	var reserved_amount := 0

	if (
		construction_site_id > 0
		and not WorldData.get_city_construction_site_by_id(
			construction_site_id
		).is_empty()
	):
		reserved_amount = mini(
			resource_yield,
			WorldData.get_city_construction_site_unreserved_resource_space(
				construction_site_id,
				resource
			)
		)

	var reserved_result := {
		"added_amount": 0,
		"placements": [],
	}

	if reserved_amount > 0:
		reserved_result = WorldData.add_resource_to_city_ground_piles_with_result({
			"tile_position": tile_position,
			"resource": resource,
			"amount_delta": reserved_amount,
			"construction_site_id": construction_site_id,
		})

	var ordinary_amount := resource_yield - reserved_amount
	var ordinary_result := {
		"added_amount": 0,
		"placements": [],
	}

	if ordinary_amount > 0:
		ordinary_result = WorldData.add_resource_to_city_ground_piles_with_result({
			"tile_position": tile_position,
			"resource": resource,
			"amount_delta": ordinary_amount,
		})

	if (
		int(reserved_result.get("added_amount", 0))
		!= reserved_amount
		or int(ordinary_result.get("added_amount", 0))
		!= ordinary_amount
	):
		WorldData.rollback_city_ground_pile_additions(
			resource,
			ordinary_result.get("placements", [])
		)
		WorldData.rollback_city_ground_pile_additions(
			resource,
			reserved_result.get("placements", [])
		)
		tile["surface_feature"] = expected_feature
		return false

	city_world.mark_city_surface_feature_changed(
		tile_position,
		expected_feature,
		WorldData.CITY_SURFACE_FEATURE_NONE
	)
	return _remove_city_player_command_record(command_id)


static func synchronize_player_work_board() -> void:
	# Capture immutable read snapshots once for the complete synchronization pass.
	# Previously, each work order rebuilt deep snapshots of the same command and
	# ground-pile registries, multiplying allocations by the number of orders.
	var command_snapshot := get_city_player_command_snapshot()
	var construction_site_snapshot := (
		CityConstructionSystem.get_city_construction_site_snapshot()
	)
	var ground_pile_snapshot := WorldData.get_city_ground_pile_snapshot()
	var desired_sources: Dictionary = {}

	for raw_command in command_snapshot:
		if not raw_command is Dictionary:
			continue

		var command: Dictionary = raw_command
		var construction_site_id := int(
			command.get("construction_site_id", -1)
		)

		if construction_site_id > 0:
			# Clearing commands are child jobs of their construction site.
			continue

		var group_id := int(command.get("group_id", -1))

		if group_id <= 0:
			continue

		var source_key := _make_command_group_source_key(group_id)
		desired_sources[source_key] = {
			"source_key": source_key,
			"order_type": ORDER_TYPE_COMMAND_GROUP,
			"source_id": group_id,
			"created_world_minute": int(
				command.get("issued_world_minute", 0)
			),
		}

	for raw_site in construction_site_snapshot:
		if not raw_site is Dictionary:
			continue

		var site: Dictionary = raw_site
		var site_id := int(site.get("id", -1))

		if site_id <= 0:
			continue

		var source_key := _make_construction_source_key(site_id)
		desired_sources[source_key] = {
			"source_key": source_key,
			"order_type": ORDER_TYPE_CONSTRUCTION_SITE,
			"source_id": site_id,
			"created_world_minute": int(
				site.get("issued_world_minute", 0)
			),
		}

	var source_keys: Array = desired_sources.keys()
	source_keys.sort()

	for raw_source_key in source_keys:
		var source_key := str(raw_source_key)
		var descriptor = desired_sources.get(source_key, {})

		if descriptor is Dictionary:
			_ensure_order_for_source(descriptor)

	var stale_order_ids: Array[int] = []

	for raw_order_id in WorldData.city_work_orders.keys():
		var order_id := int(raw_order_id)
		var raw_order = WorldData.city_work_orders.get(order_id, {})

		if not raw_order is Dictionary:
			stale_order_ids.append(order_id)
			continue

		var order: Dictionary = raw_order

		if not desired_sources.has(str(order.get("source_key", ""))):
			stale_order_ids.append(order_id)

	stale_order_ids.sort()

	for order_id in stale_order_ids:
		_remove_order_record(order_id)

	var order_ids: Array = WorldData.city_work_orders.keys()
	order_ids.sort()

	for raw_order_id in order_ids:
		_refresh_order_runtime(
			int(raw_order_id),
			command_snapshot,
			ground_pile_snapshot
		)


static func synchronize_construction_work_order(site_id: int) -> Dictionary:
	var site := WorldData.get_city_construction_site_by_id(site_id)

	if site.is_empty():
		return {}

	var source_key := _make_construction_source_key(site_id)
	var order_id := _ensure_order_for_source({
		"source_key": source_key,
		"order_type": ORDER_TYPE_CONSTRUCTION_SITE,
		"source_id": site_id,
		"created_world_minute": int(site.get("issued_world_minute", 0)),
	})

	if order_id <= 0:
		return {}

	refresh_work_order_runtimes([order_id])
	return get_city_work_order_by_id(order_id)


# Construction-site removal is an atomic lifecycle boundary. Removing the
# matching parent order here prevents validators and schedulers from ever
# observing a dangling order between site completion/cancellation and the
# next broad work-board synchronization.
static func remove_construction_work_order_for_site(site_id: int) -> void:
	if site_id <= 0:
		return

	var source_key := _make_construction_source_key(site_id)
	var order_id := int(
		WorldData.city_work_order_id_by_source_key.get(source_key, -1)
	)

	if order_id > 0:
		_remove_order_record(order_id)


static func refresh_work_order_runtimes(raw_order_ids: Array) -> void:
	var order_id_lookup: Dictionary = {}

	for raw_order_id in raw_order_ids:
		var order_id := int(raw_order_id)

		if order_id > 0 and WorldData.city_work_orders.has(order_id):
			order_id_lookup[order_id] = true

	if order_id_lookup.is_empty():
		return

	var command_snapshot := get_city_player_command_snapshot()
	var ground_pile_snapshot := WorldData.get_city_ground_pile_snapshot()
	var order_ids: Array = order_id_lookup.keys()
	order_ids.sort()

	for raw_order_id in order_ids:
		_refresh_order_runtime(
			int(raw_order_id),
			command_snapshot,
			ground_pile_snapshot
		)


static func get_best_player_job_for_citizen(citizen_id: int) -> Dictionary:
	return get_best_player_job_for_citizen_and_orders(
		citizen_id,
		WorldData.city_work_orders.keys()
	)


# Independent road tiles retain independent construction sites and work-order
# IDs, but route evaluation is batched. A long painted road therefore costs one
# road-candidate search per citizen rather than one A* search per tile.
static func get_best_player_job_for_citizen_and_orders(
	citizen_id: int,
	raw_order_ids: Array
) -> Dictionary:
	var citizen := WorldData.get_city_citizen_by_id(citizen_id)

	if (
		citizen.is_empty()
		or not bool(citizen.get("alive", false))
		or int(citizen.get("job_object_id", -1)) > 0
	):
		return {}

	var order_id_lookup: Dictionary = {}

	for raw_order_id in raw_order_ids:
		var order_id := int(raw_order_id)

		if order_id > 0 and WorldData.city_work_orders.has(order_id):
			order_id_lookup[order_id] = true

	var order_ids: Array = order_id_lookup.keys()
	order_ids.sort()
	var best_selection: Dictionary = {}
	var batchable_road_order_id_by_site_id: Dictionary = {}

	for raw_order_id in order_ids:
		var order_id := int(raw_order_id)
		var order := get_city_work_order_by_id(order_id)

		if (
			order.is_empty()
			or str(order.get("state", "")) == ORDER_STATE_CANCELLED
		):
			continue

		if _construction_order_uses_batchable_road_site(order):
			batchable_road_order_id_by_site_id[
				int(order.get("source_id", -1))
			] = order_id
			continue

		var candidate := _get_best_job_candidate_for_order(
			citizen_id,
			order
		)

		if candidate.is_empty():
			continue

		candidate = _decorate_candidate_for_order(
			candidate,
			order
		)

		if _selection_is_better(candidate, best_selection):
			best_selection = candidate

	var road_candidate := _get_best_batchable_road_candidate(
		citizen_id,
		batchable_road_order_id_by_site_id
	)

	if _selection_is_better(road_candidate, best_selection):
		best_selection = road_candidate

	return best_selection


static func _decorate_candidate_for_order(
	candidate: Dictionary,
	order: Dictionary
) -> Dictionary:
	if candidate.is_empty() or order.is_empty():
		return {}

	var decorated := candidate.duplicate(true)
	decorated["work_order_id"] = int(order.get("id", -1))
	decorated["priority_rank"] = int(
		order.get("priority_rank", PRIORITY_NORMAL)
	)
	decorated["parent_attention_score"] = (
		_get_parent_attention_score(order, decorated)
	)
	return decorated


static func _construction_order_uses_batchable_road_site(
	order: Dictionary
) -> bool:
	if (
		order.is_empty()
		or str(order.get("order_type", ""))
		!= ORDER_TYPE_CONSTRUCTION_SITE
	):
		return false

	var site := WorldData.get_city_construction_site_by_id(
		int(order.get("source_id", -1))
	)
	var raw_recipe = site.get("material_recipe", {})

	return (
		not site.is_empty()
		and str(site.get("object_type", ""))
		== WorldData.CITY_OBJECT_ROAD
		and raw_recipe is Dictionary
		and raw_recipe.is_empty()
	)


static func _get_best_batchable_road_candidate(
	citizen_id: int,
	order_id_by_site_id: Dictionary
) -> Dictionary:
	if order_id_by_site_id.is_empty():
		return {}

	var site_ids: Array = order_id_by_site_id.keys()
	site_ids.sort()
	var best_candidate := (
		_get_best_command_candidate_for_construction_sites(
			citizen_id,
			order_id_by_site_id
		)
	)
	var construction_candidate := (
		CityConstructionSystemScript
		.get_best_assignable_batchable_road_work_for_citizen(
			citizen_id,
			site_ids
		)
	)

	if not construction_candidate.is_empty():
		var kind := str(
			construction_candidate.get("player_work_kind", "")
		)
		var tie_break_key := str(
			construction_candidate.get("tie_break_key", "")
		)
		construction_candidate["job_id"] = (
			kind + ":" + tie_break_key
		)

		if _job_candidate_is_better(
			construction_candidate,
			best_candidate
		):
			best_candidate = construction_candidate

	if best_candidate.is_empty():
		return {}

	var selected_site_id := int(
		best_candidate.get("construction_site_id", -1)
	)
	var selected_order_id := int(
		order_id_by_site_id.get(selected_site_id, -1)
	)
	var selected_order := get_city_work_order_by_id(selected_order_id)

	if selected_order.is_empty():
		return {}

	best_candidate["progress_unlocking"] = (
		_candidate_unlocks_progress(selected_order, best_candidate)
	)
	return _decorate_candidate_for_order(
		best_candidate,
		selected_order
	)


# Clearing commands for independent road tiles are routed as one destination
# set. The returned command still carries its exact construction_site_id, so
# assignment, cancellation, claims, and completion remain tile-local.
static func _get_best_command_candidate_for_construction_sites(
	citizen_id: int,
	order_id_by_site_id: Dictionary
) -> Dictionary:
	var citizen := WorldData.get_city_citizen_by_id(citizen_id)
	var raw_citizen_tile = citizen.get(
		"city_tile_position",
		WorldData.INVALID_CITY_TILE_POSITION
	)

	if citizen.is_empty() or not raw_citizen_tile is Vector2i:
		return {}

	var citizen_tile: Vector2i = raw_citizen_tile
	var command_by_id: Dictionary = {}
	var command_ids_by_work_tile: Dictionary = {}
	var work_tile_lookup: Dictionary = {}

	for raw_command in get_city_player_command_snapshot():
		if not raw_command is Dictionary:
			continue

		var command: Dictionary = raw_command
		var construction_site_id := int(
			command.get("construction_site_id", -1)
		)

		if (
			not order_id_by_site_id.has(construction_site_id)
			or not city_player_command_is_assignable(command)
		):
			continue

		var command_id := int(command.get("id", -1))
		var work_tiles := get_city_player_command_work_tiles(
			command,
			citizen_id
		)

		if command_id <= 0 or work_tiles.is_empty():
			continue

		command_by_id[command_id] = command

		for work_tile in work_tiles:
			work_tile_lookup[work_tile] = true
			var command_ids: Array = command_ids_by_work_tile.get(
				work_tile,
				[]
			)

			if not command_ids.has(command_id):
				command_ids.append(command_id)
				command_ids.sort()
				command_ids_by_work_tile[work_tile] = command_ids

	if work_tile_lookup.is_empty():
		return {}

	var work_tiles: Array = work_tile_lookup.keys()
	work_tiles.sort_custom(WorldData._sort_city_tiles_y_then_x)
	var path_result := CityNavigationSystemScript.find_path_to_any_city_tile({
		"city_world": WorldData.official_city_world,
		"start_tile": citizen_tile,
		"destination_tiles": work_tiles,
		"max_expanded_nodes": CityNavigationSystemScript.get_city_wide_path_expansion_limit(
			WorldData.official_city_world
		),
		"citizen_id": citizen_id,
		"heuristic_weight": EXACT_COMMAND_PATH_HEURISTIC_WEIGHT,
	})

	if not bool(path_result.get("success", false)):
		return {}

	var raw_destination_tile = path_result.get(
		"destination_tile",
		WorldData.INVALID_CITY_TILE_POSITION
	)

	if not raw_destination_tile is Vector2i:
		return {}

	var matching_command_ids: Array = command_ids_by_work_tile.get(
		raw_destination_tile,
		[]
	)

	if matching_command_ids.is_empty():
		return {}

	matching_command_ids.sort()
	var selected_command_id := int(matching_command_ids[0])
	var raw_selected_command = command_by_id.get(selected_command_id, {})

	if not raw_selected_command is Dictionary:
		return {}

	var candidate: Dictionary = raw_selected_command.duplicate(true)
	candidate["player_work_kind"] = "command"
	candidate["job_id"] = "command:" + str(selected_command_id)
	candidate["estimated_path_cost"] = maxi(
		int(path_result.get("path_cost", 0)),
		0
	)
	candidate["target_tile"] = raw_destination_tile
	candidate["assignment_path"] = path_result.get("path", []).duplicate()
	candidate["tie_break_key"] = str(selected_command_id)
	return candidate


static func get_player_job_for_citizen_and_order(
	citizen_id: int,
	order_id: int
) -> Dictionary:
	var citizen := WorldData.get_city_citizen_by_id(citizen_id)

	if (
		citizen.is_empty()
		or not bool(citizen.get("alive", false))
		or int(citizen.get("job_object_id", -1)) > 0
	):
		return {}

	var order := get_city_work_order_by_id(order_id)

	if (
		order.is_empty()
		or str(order.get("state", "")) == ORDER_STATE_CANCELLED
	):
		return {}

	var candidate := _get_best_job_candidate_for_order(citizen_id, order)

	if candidate.is_empty():
		return {}

	return _decorate_candidate_for_order(candidate, order)


static func get_best_construction_job_for_citizen_excluding_order(
	citizen_id: int,
	excluded_order_id: int
) -> Dictionary:
	var construction_order_ids: Array[int] = []
	var order_ids: Array = WorldData.city_work_orders.keys()
	order_ids.sort()

	for raw_order_id in order_ids:
		var order_id := int(raw_order_id)

		if order_id == excluded_order_id:
			continue

		var order := get_city_work_order_by_id(order_id)

		if (
			not order.is_empty()
			and str(order.get("order_type", ""))
			== ORDER_TYPE_CONSTRUCTION_SITE
			and str(order.get("state", "")) != ORDER_STATE_CANCELLED
		):
			construction_order_ids.append(order_id)

	return get_best_player_job_for_citizen_and_orders(
		citizen_id,
		construction_order_ids
	)


static func assign_player_job(
	citizen_id: int,
	candidate: Dictionary
) -> bool:
	var order_id := int(candidate.get("work_order_id", -1))
	var order := get_city_work_order_by_id(order_id)

	if order.is_empty():
		return false

	var job_id := str(candidate.get("job_id", ""))
	var assigned := false

	if str(candidate.get("player_work_kind", "")) == "command":
		var command_id := int(candidate.get("id", -1))

		if not claim_city_player_command(command_id, citizen_id):
			return false

		assigned = WorldData.assign_city_citizen_task(
			citizen_id,
			{
				"kind": WorldData.CITY_CITIZEN_TASK_KIND_PLAYER_COMMAND,
				"source": WorldData.CITY_CITIZEN_TASK_SOURCE_PLAYER,
				"priority": WorldData.CITY_PLAYER_COMMAND_TASK_PRIORITY,
				"target_object_id": command_id,
				"player_locked": false,
				"work_order_id": order_id,
				"job_id": job_id,
			}
		)

		if not assigned:
			WorldData.release_city_player_command_claim(
				command_id,
				citizen_id
			)
	else:
		var prepared_candidate := candidate.duplicate(true)
		var raw_task_request = prepared_candidate.get("task_request", {})

		if raw_task_request is Dictionary:
			var task_request: Dictionary = raw_task_request
			task_request["work_order_id"] = order_id
			task_request["job_id"] = job_id
			prepared_candidate["task_request"] = task_request

		assigned = (
			CityConstructionSystemScript.assign_player_work_candidate(
				citizen_id,
				prepared_candidate
			)
		)

	if assigned:
		_note_order_attention(order_id)

	return assigned


static func set_order_priority(order_id: int, priority_rank: int) -> bool:
	if (
		not WorldData.city_work_orders.has(order_id)
		or priority_rank < PRIORITY_LOW
		or priority_rank > PRIORITY_URGENT
	):
		return false

	var raw_order = WorldData.city_work_orders.get(order_id, {})

	if not raw_order is Dictionary:
		return false

	var order: Dictionary = raw_order.duplicate(true)

	if int(order.get("priority_rank", PRIORITY_NORMAL)) == priority_rank:
		return true

	order["priority_rank"] = priority_rank
	WorldData.city_work_orders[order_id] = order
	WorldData.mark_city_work_orders_changed()
	return true


static func cancel_work_order(order_id: int) -> bool:
	var order := get_city_work_order_by_id(order_id)

	if order.is_empty():
		return false

	var cancelled := false

	match str(order.get("order_type", "")):
		ORDER_TYPE_COMMAND_GROUP:
			var command_ids: Array[int] = []
			var group_id := int(order.get("source_id", -1))

			for raw_command in get_city_player_command_snapshot():
				if (
					raw_command is Dictionary
					and int(raw_command.get("group_id", -1)) == group_id
					and int(raw_command.get("construction_site_id", -1)) <= 0
				):
					command_ids.append(int(raw_command.get("id", -1)))

			command_ids.sort()

			for command_id in command_ids:
				if cancel_city_player_command(command_id):
					cancelled = true

		ORDER_TYPE_CONSTRUCTION_SITE:
			cancelled = (
				CityConstructionSystemScript.cancel_city_construction_site(
					int(order.get("source_id", -1))
				)
			)

	if cancelled:
		_remove_order_record(order_id)

	return cancelled


static func cancel_player_targets_at_tiles(raw_tiles: Array) -> int:
	var site_ids: Dictionary = {}
	var command_ids: Dictionary = {}

	for raw_tile in raw_tiles:
		if not raw_tile is Vector2i:
			continue

		var tile: Vector2i = raw_tile
		var site := CityConstructionSystem.get_city_construction_site_at_tile(tile)

		if not site.is_empty():
			site_ids[int(site.get("id", -1))] = true

		var command := get_city_player_command_at_tile(tile)

		if (
			not command.is_empty()
			and int(command.get("construction_site_id", -1)) <= 0
		):
			command_ids[int(command.get("id", -1))] = true

	var cancelled_count := 0
	var ordered_site_ids: Array = site_ids.keys()
	ordered_site_ids.sort()

	for raw_site_id in ordered_site_ids:
		if CityConstructionSystemScript.cancel_city_construction_site(
			int(raw_site_id)
		):
			cancelled_count += 1

	var ordered_command_ids: Array = command_ids.keys()
	ordered_command_ids.sort()

	for raw_command_id in ordered_command_ids:
		if cancel_city_player_command(int(raw_command_id)):
			cancelled_count += 1

	synchronize_player_work_board()
	return cancelled_count


static func get_cancel_preview_tiles(raw_tiles: Array) -> Array[Vector2i]:
	var preview_lookup: Dictionary = {}

	for raw_tile in raw_tiles:
		if not raw_tile is Vector2i:
			continue

		var tile: Vector2i = raw_tile
		var site := CityConstructionSystem.get_city_construction_site_at_tile(tile)

		if not site.is_empty():
			for raw_footprint_tile in site.get("footprint_tiles", []):
				if raw_footprint_tile is Vector2i:
					preview_lookup[raw_footprint_tile] = true

		if not get_city_player_command_at_tile(tile).is_empty():
			preview_lookup[tile] = true

	var preview_tiles: Array[Vector2i] = []

	for raw_tile in preview_lookup.keys():
		if raw_tile is Vector2i:
			preview_tiles.append(raw_tile)

	preview_tiles.sort_custom(WorldData._sort_city_tiles_y_then_x)
	return preview_tiles


static func get_order_debug_snapshot() -> Array:
	synchronize_player_work_board()
	var snapshot := get_city_work_order_snapshot()
	var now := SimulationClock.absolute_world_minutes

	for order_index in range(snapshot.size()):
		var raw_order = snapshot[order_index]

		if not raw_order is Dictionary:
			continue

		var order: Dictionary = raw_order
		order["minutes_since_progress"] = maxi(
			now - int(order.get("last_progress_world_minute", now)),
			0
		)
		order["minutes_since_attention"] = maxi(
			now - int(order.get("last_attention_world_minute", now)),
			0
		)
		snapshot[order_index] = order

	return snapshot


#endregion

#region Work Order Runtime Maintenance

static func _ensure_order_for_source(descriptor: Dictionary) -> int:
	var source_key := str(descriptor.get("source_key", ""))

	if source_key.is_empty():
		return -1

	var existing_id := int(
		WorldData.city_work_order_id_by_source_key.get(source_key, -1)
	)

	if existing_id > 0 and WorldData.city_work_orders.has(existing_id):
		return existing_id

	var order_id := WorldData.next_city_work_order_id
	WorldData.next_city_work_order_id += 1
	var created_minute := int(
		descriptor.get(
			"created_world_minute",
			SimulationClock.absolute_world_minutes
		)
	)
	var order := {
		"id": order_id,
		"source_key": source_key,
		"order_type": str(descriptor.get("order_type", "")),
		"source_id": int(descriptor.get("source_id", -1)),
		"creation_sequence": order_id,
		"created_world_minute": created_minute,
		"priority_rank": PRIORITY_NORMAL,
		"state": ORDER_STATE_ACTIVE,
		"phase": "",
		"jobs": [],
		"active_worker_count": 0,
		"active_citizen_ids": [],
		"useful_parallel_capacity": 1,
		"blocked_reason": BLOCKED_REASON_NONE,
		"last_progress_world_minute": created_minute,
		"last_attention_world_minute": created_minute,
		"progress_signature": "",
	}

	WorldData.city_work_orders[order_id] = order
	WorldData.city_work_order_id_by_source_key[source_key] = order_id
	WorldData.mark_city_work_orders_changed()
	return order_id


static func _remove_order_record(order_id: int) -> void:
	if not WorldData.city_work_orders.has(order_id):
		return

	var raw_order = WorldData.city_work_orders.get(order_id, {})

	if raw_order is Dictionary:
		WorldData.city_work_order_id_by_source_key.erase(
			str(raw_order.get("source_key", ""))
		)

	WorldData.city_work_orders.erase(order_id)
	WorldData.mark_city_work_orders_changed()


static func _refresh_order_runtime(
	order_id: int,
	command_snapshot: Array,
	ground_pile_snapshot: Array
) -> void:
	var raw_order = WorldData.city_work_orders.get(order_id, {})

	if not raw_order is Dictionary:
		return

	var order: Dictionary = raw_order.duplicate(true)
	var jobs := _build_jobs_for_order(
		order,
		command_snapshot,
		ground_pile_snapshot
	)
	_apply_runtime_worker_actionability(order, jobs)
	_finalize_job_runtime_diagnostics(order, jobs)
	var progress_signature := _build_progress_signature(
		order,
		command_snapshot
	)
	var previous_signature := str(order.get("progress_signature", ""))

	if (
		not previous_signature.is_empty()
		and progress_signature != previous_signature
	):
		order["last_progress_world_minute"] = (
			SimulationClock.absolute_world_minutes
		)

	order["progress_signature"] = progress_signature
	order["phase"] = _get_order_phase(order)
	order["jobs"] = jobs
	order["active_citizen_ids"] = _get_active_citizen_ids_for_order(order)
	order["active_worker_count"] = order["active_citizen_ids"].size()
	order["useful_parallel_capacity"] = (
		_get_useful_parallel_capacity(order, jobs)
	)
	order["blocked_reason"] = _get_order_blocked_reason(order, jobs)
	order["state"] = (
		ORDER_STATE_ACTIVE
		if str(order.get("blocked_reason", "")).is_empty()
		else ORDER_STATE_BLOCKED
	)

	if order != raw_order:
		WorldData.city_work_orders[order_id] = order
		WorldData.mark_city_work_orders_changed()


# Source validity says that work is physically meaningful; runtime
# actionability additionally requires at least one presently eligible
# unemployed citizen with an exact route to some job in the parent order.
# Candidate selection remains citizen-specific below. This pass only prevents
# diagnostics from advertising unreachable work as actionable/ACTIVE.
static func _apply_runtime_worker_actionability(
	order: Dictionary,
	jobs: Array
) -> void:
	var has_source_actionable_job := false

	for raw_job in jobs:
		if raw_job is Dictionary and bool(raw_job.get("actionable", false)):
			has_source_actionable_job = true
			break

	if not has_source_actionable_job:
		return

	var eligible_citizen_ids := _get_runtime_eligible_worker_ids()

	if eligible_citizen_ids.is_empty():
		_override_actionable_jobs_with_reason(
			jobs,
			BLOCKED_REASON_NO_ELIGIBLE_WORKER
		)
		return

	# Reachability for material-free road sites is evaluated in one batched
	# route search during actual candidate selection. Repeating A* once for
	# every independent tile here would reintroduce the old road-placement hitch.
	if _construction_order_uses_batchable_road_site(order):
		return

	var candidate_order := order.duplicate(true)
	candidate_order["jobs"] = jobs

	for citizen_id in eligible_citizen_ids:
		if not _get_best_job_candidate_for_order(
			citizen_id,
			candidate_order
		).is_empty():
			return

	_override_actionable_jobs_with_reason(
		jobs,
		BLOCKED_REASON_NO_REACHABLE_WORK_POSITION
	)


#endregion

#region Worker Eligibility and Runtime Diagnostics

static func _get_runtime_eligible_worker_ids() -> Array[int]:
	var citizen_ids: Array[int] = []

	for raw_citizen in WorldData.city_citizens:
		if not raw_citizen is Dictionary:
			continue

		var citizen: Dictionary = raw_citizen
		var citizen_id := int(citizen.get("id", -1))

		if (
			citizen_id <= 0
			or not bool(citizen.get("alive", false))
			or int(citizen.get("job_object_id", -1)) > 0
			or WorldData.get_city_citizen_haul_cargo_amount(citizen_id) > 0
		):
			continue

		var current_task := WorldData.get_city_citizen_current_task(
			citizen_id
		)

		if (
			str(current_task.get("source", ""))
			== WorldData.CITY_CITIZEN_TASK_SOURCE_PLAYER
			or str(current_task.get("kind", ""))
			== WorldData.CITY_CITIZEN_TASK_KIND_ACQUIRE_FOOD
		):
			continue

		citizen_ids.append(citizen_id)

	citizen_ids.sort()
	return citizen_ids


static func _override_actionable_jobs_with_reason(
	jobs: Array,
	blocked_reason: String
) -> void:
	for job_index in range(jobs.size()):
		var raw_job = jobs[job_index]

		if not raw_job is Dictionary:
			continue

		var job: Dictionary = raw_job

		if not bool(job.get("actionable", false)):
			continue

		job["actionable"] = false
		job["blocked_reason"] = blocked_reason
		jobs[job_index] = job


static func _finalize_job_runtime_diagnostics(
	order: Dictionary,
	jobs: Array
) -> void:
	for job_index in range(jobs.size()):
		var raw_job = jobs[job_index]

		if not raw_job is Dictionary:
			continue

		var job: Dictionary = raw_job
		var active_citizen_ids := _get_active_citizen_ids_for_job(
			order,
			job
		)
		job["active_citizen_ids"] = active_citizen_ids

		if (
			int(job.get("claimed_citizen_id", -1)) <= 0
			and not active_citizen_ids.is_empty()
		):
			job["claimed_citizen_id"] = active_citizen_ids[0]

		var job_kind := str(job.get("kind", ""))

		if job_kind in [
			JOB_KIND_CLEARING_RELOCATION,
			JOB_KIND_CONSTRUCTION_DELIVERY,
		]:
			var resource := str(
				job.get("resource_type", WorldData.RESOURCE_NONE)
			)
			var reservation_amounts := _get_job_reservation_amounts(
				active_citizen_ids,
				resource
			)
			job["source_reserved_amount"] = int(
				reservation_amounts.get("source_reserved_amount", 0)
			)
			job["destination_reserved_amount"] = maxi(
				int(job.get("destination_reserved_amount", 0)),
				int(
					reservation_amounts.get(
						"destination_reserved_amount",
						0
					)
				)
			)

		# An active job is progressing even when it cannot accept another
		# worker. Its capacity/claim state is expressed by `actionable` and the
		# active IDs, not by advertising the job itself as blocked.
		if (
			bool(job.get("actionable", false))
			or not active_citizen_ids.is_empty()
		):
			job["blocked_reason"] = BLOCKED_REASON_NONE

		if not active_citizen_ids.is_empty():
			job["state"] = JOB_STATE_ACTIVE
		elif bool(job.get("actionable", false)):
			job["state"] = JOB_STATE_ACTIONABLE
		else:
			job["state"] = JOB_STATE_BLOCKED

		jobs[job_index] = job


static func _get_active_citizen_ids_for_job(
	order: Dictionary,
	job: Dictionary
) -> Array[int]:
	var active_citizen_ids: Array[int] = []
	var order_id := int(order.get("id", -1))
	var source_id := int(order.get("source_id", -1))
	var job_kind := str(job.get("kind", ""))
	var job_id := str(job.get("id", ""))
	var command_id := -1

	if job_id.begins_with("command:"):
		command_id = job_id.trim_prefix("command:").to_int()

	for raw_citizen in WorldData.city_citizens:
		if not raw_citizen is Dictionary:
			continue

		var citizen: Dictionary = raw_citizen
		var citizen_id := int(citizen.get("id", -1))
		var task = citizen.get("current_task", {})

		if (
			citizen_id <= 0
			or not bool(citizen.get("alive", false))
			or not task is Dictionary
		):
			continue

		var task_kind := str(task.get("kind", ""))
		var matches_job := false

		if command_id > 0:
			matches_job = (
				task_kind
				== WorldData.CITY_CITIZEN_TASK_KIND_PLAYER_COMMAND
				and int(task.get("target_object_id", -1)) == command_id
			)
		elif job_kind == JOB_KIND_CONSTRUCTION_LABOR:
			matches_job = (
				task_kind == WorldData.CITY_CITIZEN_TASK_KIND_CONSTRUCTION
				and int(task.get("target_object_id", -1)) == source_id
			)
		elif (
			job_kind == JOB_KIND_CONSTRUCTION_DELIVERY
			or job_kind == JOB_KIND_CLEARING_RELOCATION
		):
			var haul = citizen.get("current_haul", {})

			if haul is Dictionary:
				var requester = haul.get("requester", {})
				var reason := str(haul.get("reason", ""))
				var resource := str(
					haul.get("resource_type", WorldData.RESOURCE_NONE)
				)
				var requester_matches := (
					requester is Dictionary
					and str(requester.get("kind", ""))
					== WorldData.CITY_CITIZEN_HAUL_ENDPOINT_KIND_CONSTRUCTION_SITE
					and int(requester.get("id", -1)) == source_id
				)

				if job_kind == JOB_KIND_CONSTRUCTION_DELIVERY:
					matches_job = (
						task_kind == WorldData.CITY_CITIZEN_TASK_KIND_HAUL
						and requester_matches
						and reason
						== WorldData.CITY_CITIZEN_HAUL_REASON_CONSTRUCTION_DELIVERY
						and resource
						== str(job.get("resource_type", ""))
					)
				else:
					var source = haul.get("source", {})
					var pile_id := job_id.trim_prefix(
						"relocate_pile:"
					).to_int()
					matches_job = (
						task_kind == WorldData.CITY_CITIZEN_TASK_KIND_HAUL
						and requester_matches
						and reason
						== WorldData.CITY_CITIZEN_HAUL_REASON_GROUND_PILE_CLEANUP
						and source is Dictionary
						and str(source.get("kind", ""))
						== WorldData.CITY_CITIZEN_HAUL_ENDPOINT_KIND_GROUND_PILE
						and int(source.get("id", -1)) == pile_id
					)

		if (
			matches_job
			and (
				int(task.get("work_order_id", -1)) in [-1, order_id]
			)
		):
			active_citizen_ids.append(citizen_id)

	active_citizen_ids.sort()
	return active_citizen_ids


static func _get_job_reservation_amounts(
	active_citizen_ids: Array[int],
	resource: String
) -> Dictionary:
	var source_reserved_amount := 0
	var destination_reserved_amount := 0

	for citizen_id in active_citizen_ids:
		var reservation_id := (
			WorldData.get_city_haul_reservation_id_for_citizen(citizen_id)
		)
		var reservation := WorldData.get_city_haul_reservation(
			reservation_id
		)

		if reservation.is_empty():
			continue

		if str(reservation.get("resource_type", "")) == resource:
			source_reserved_amount += maxi(
				int(reservation.get("source_reserved_amount", 0)),
				0
			)

		destination_reserved_amount += (
			WorldData.get_city_haul_reservation_destination_resource_amount(
				reservation_id,
				resource
			)
		)

	return {
		"source_reserved_amount": source_reserved_amount,
		"destination_reserved_amount": destination_reserved_amount,
	}


#endregion

#region Job Construction

static func _get_order_phase(order: Dictionary) -> String:
	if str(order.get("order_type", "")) == ORDER_TYPE_COMMAND_GROUP:
		return ORDER_PHASE_COMMANDS

	if str(order.get("order_type", "")) == ORDER_TYPE_CONSTRUCTION_SITE:
		return str(
			WorldData.get_city_construction_site_by_id(
				int(order.get("source_id", -1))
			).get("phase", "")
		)

	return ""


static func _build_jobs_for_order(
	order: Dictionary,
	command_snapshot: Array,
	ground_pile_snapshot: Array
) -> Array:
	var jobs: Array = []
	var order_type := str(order.get("order_type", ""))
	var source_id := int(order.get("source_id", -1))

	if order_type == ORDER_TYPE_COMMAND_GROUP:
		_append_command_jobs({
			"jobs": jobs,
			"group_id": source_id,
			"construction_site_id": -1,
			"command_snapshot": command_snapshot,
		})
		return jobs

	if order_type != ORDER_TYPE_CONSTRUCTION_SITE:
		return jobs

	var site := WorldData.get_city_construction_site_by_id(source_id)

	if site.is_empty():
		return jobs

	var phase := str(site.get("phase", ""))

	if phase == WorldData.CITY_CONSTRUCTION_PHASE_CLEARING:
		_append_command_jobs({
			"jobs": jobs,
			"group_id": -1,
			"construction_site_id": source_id,
			"command_snapshot": command_snapshot,
		})
		var footprint_tiles: Array = site.get("footprint_tiles", [])

		for raw_pile in ground_pile_snapshot:
			if not raw_pile is Dictionary:
				continue

			var pile: Dictionary = raw_pile
			var pile_tile = pile.get(
				"tile_position",
				WorldData.INVALID_CITY_TILE_POSITION
			)

			if (
				not pile_tile is Vector2i
				or not footprint_tiles.has(pile_tile)
				or WorldData.city_ground_pile_is_construction_reserved(pile)
			):
				continue

			var resource := str(
				pile.get("resource_type", WorldData.RESOURCE_NONE)
			)
			var pile_id := int(pile.get("id", -1))
			var requested_amount := maxi(
				WorldData.get_city_haul_endpoint_resource_amount(
					WorldData.make_city_ground_pile_haul_endpoint(pile_id),
					resource
				),
				0
			)
			var source_available := (
				WorldData.get_city_haul_endpoint_unreserved_resource_amount(
					WorldData.make_city_ground_pile_haul_endpoint(pile_id),
					resource
				)
			)
			var destination_diagnostics := (
				_get_relocation_destination_diagnostics(
					source_id,
					pile_id,
					resource
				)
			)
			var destination_available := bool(
				destination_diagnostics.get("available", false)
			)
			var actionable := (
				source_available > 0 and destination_available
			)
			var blocked_reason := str(
				destination_diagnostics.get(
					"blocked_reason",
					BLOCKED_REASON_NO_LEGAL_DESTINATION
				)
			)

			if source_available <= 0:
				blocked_reason = BLOCKED_REASON_SOURCE_FULLY_RESERVED
			elif destination_available:
				blocked_reason = BLOCKED_REASON_NONE

			jobs.append({
				"id": "relocate_pile:" + str(pile_id),
				"kind": JOB_KIND_CLEARING_RELOCATION,
				"resource_type": resource,
				"source_endpoint": (
					WorldData.make_city_ground_pile_haul_endpoint(pile_id)
				),
				"source_available_amount": source_available,
				"requested_amount": requested_amount,
				"destination_available_amount": int(
					destination_diagnostics.get("available_amount", 0)
				),
				"actionable": actionable,
				"blocked_reason": blocked_reason,
				"claimed_citizen_id": -1,
			})
	elif phase == WorldData.CITY_CONSTRUCTION_PHASE_GATHERING:
		for resource in WorldData.get_city_resource_types():
			var remaining_amount := (
				WorldData.get_city_construction_site_remaining_resource_amount(
					source_id,
					resource
				)
			)

			if remaining_amount <= 0:
				continue

			var destination_reserved_amount := (
				WorldData.get_city_construction_site_destination_reserved_resource_amount(
					source_id,
					resource
				)
			)
			var requested_amount := (
				WorldData.get_city_construction_site_unreserved_resource_space(
					source_id,
					resource
				)
			)
			var source_diagnostics := _get_construction_source_diagnostics(
				resource,
				maxi(requested_amount, 1)
			)
			var actionable := (
				requested_amount > 0
				and bool(source_diagnostics.get("available", false))
			)
			var blocked_reason := str(
				source_diagnostics.get(
					"blocked_reason",
					BLOCKED_REASON_NO_LEGAL_SOURCE
				)
			)

			if requested_amount <= 0 and destination_reserved_amount > 0:
				blocked_reason = BLOCKED_REASON_WAITING_FOR_MATERIALS
			elif actionable:
				blocked_reason = BLOCKED_REASON_NONE

			jobs.append({
				"id": "deliver:" + resource,
				"kind": JOB_KIND_CONSTRUCTION_DELIVERY,
				"resource_type": resource,
				"remaining_amount": remaining_amount,
				"requested_amount": requested_amount,
				"source_available_amount": int(
					source_diagnostics.get("available_amount", 0)
				),
				"destination_reserved_amount": (
					destination_reserved_amount
				),
				"actionable": actionable,
				"blocked_reason": blocked_reason,
				"claimed_citizen_id": -1,
			})
	elif phase == WorldData.CITY_CONSTRUCTION_PHASE_LABOR:
		var maximum_workers := maxi(int(site.get("maximum_workers", 1)), 1)
		var active_workers := _count_construction_workers(source_id)
		var remaining_labor := maxi(
			int(site.get("required_labor_minutes", 0))
			- int(site.get("completed_labor_minutes", 0)),
			0
		)
		jobs.append({
			"id": "labor:" + str(source_id),
			"kind": JOB_KIND_CONSTRUCTION_LABOR,
			"remaining_labor_minutes": remaining_labor,
			"actionable": (
				remaining_labor > 0 and active_workers < maximum_workers
			),
			"blocked_reason": (
				BLOCKED_REASON_MAX_USEFUL_WORKERS
				if active_workers >= maximum_workers
				else (
					BLOCKED_REASON_INVALIDATED
					if remaining_labor <= 0
					else BLOCKED_REASON_NONE
				)
			),
			"claimed_citizen_id": -1,
		})

	return jobs


static func _append_command_jobs(values: Dictionary) -> void:
	var jobs: Array = values.get("jobs", [])
	var group_id := int(values.get("group_id", -1))
	var construction_site_id := int(
		values.get("construction_site_id", -1)
	)
	var command_snapshot: Array = values.get("command_snapshot", [])

	for raw_command in command_snapshot:
		if not raw_command is Dictionary:
			continue

		var command: Dictionary = raw_command

		if (
			group_id > 0
			and (
				int(command.get("group_id", -1)) != group_id
				or int(command.get("construction_site_id", -1)) > 0
			)
		):
			continue

		if (
			construction_site_id > 0
			and int(command.get("construction_site_id", -1))
			!= construction_site_id
		):
			continue

		var command_id := int(command.get("id", -1))
		var claimed_citizen_id := int(
			command.get("claimed_citizen_id", -1)
		)
		var target_valid := WorldData.is_city_player_command_target_valid(
			command
		)
		var assignable := city_player_command_is_assignable(command)
		jobs.append({
			"id": "command:" + str(command_id),
			"kind": str(command.get("type", "")),
			"actionable": assignable,
			"claimed_citizen_id": claimed_citizen_id,
			"blocked_reason": (
				BLOCKED_REASON_INVALIDATED
				if not target_valid
				else (
					BLOCKED_REASON_CLAIMED
					if claimed_citizen_id > 0
					else (
						BLOCKED_REASON_WAITING_FOR_SAFE_BOUNDARY
						if not assignable
						else BLOCKED_REASON_NONE
					)
				)
			),
		})


static func _build_progress_signature(
	order: Dictionary,
	command_snapshot: Array
) -> String:
	var order_type := str(order.get("order_type", ""))
	var source_id := int(order.get("source_id", -1))

	if order_type == ORDER_TYPE_COMMAND_GROUP:
		var command_ids: Array[int] = []

		for raw_command in command_snapshot:
			if (
				raw_command is Dictionary
				and int(raw_command.get("group_id", -1)) == source_id
				and int(raw_command.get("construction_site_id", -1)) <= 0
			):
				command_ids.append(int(raw_command.get("id", -1)))

		command_ids.sort()
		return "commands:" + ",".join(command_ids)

	if order_type != ORDER_TYPE_CONSTRUCTION_SITE:
		return "invalid"

	var site := WorldData.get_city_construction_site_by_id(source_id)

	if site.is_empty():
		return "missing"

	var parts: Array[String] = [
		"phase=" + str(site.get("phase", "")),
		"labor=" + str(int(site.get("completed_labor_minutes", 0))),
	]

	for resource in WorldData.get_city_resource_types():
		parts.append(
			resource
			+ "="
			+ str(
				WorldData.get_city_construction_site_reserved_resource_amount(
					source_id,
					resource
				)
			)
		)

	var obstruction_count := 0
	var footprint_tiles: Array = site.get("footprint_tiles", [])
	var city_world: WorldData = WorldData.official_city_world

	if city_world != null:
		for raw_tile in footprint_tiles:
			if not raw_tile is Vector2i:
				continue

			var tile: Vector2i = raw_tile

			if WorldData.is_city_surface_feature(
				WorldData.get_city_surface_feature(
					city_world.get_tile(tile.x, tile.y)
				)
			):
				obstruction_count += 1

	var ordinary_pile_amount := 0

	for raw_pile in WorldData.get_city_ground_pile_snapshot():
		if (
			raw_pile is Dictionary
			and footprint_tiles.has(
				raw_pile.get(
					"tile_position",
					WorldData.INVALID_CITY_TILE_POSITION
				)
			)
			and not WorldData.city_ground_pile_is_construction_reserved(
				raw_pile
			)
		):
			ordinary_pile_amount += maxi(int(raw_pile.get("amount", 0)), 0)

	parts.append("obstructions=" + str(obstruction_count))
	parts.append("ordinary_piles=" + str(ordinary_pile_amount))
	return "|".join(parts)


#endregion

#region Job Candidate Selection

static func _get_best_job_candidate_for_order(
	citizen_id: int,
	order: Dictionary
) -> Dictionary:
	var order_type := str(order.get("order_type", ""))
	var source_id := int(order.get("source_id", -1))
	var best_candidate: Dictionary = {}

	if order_type == ORDER_TYPE_COMMAND_GROUP:
		return _get_best_command_candidate(
			citizen_id,
			source_id,
			-1
		)

	if order_type != ORDER_TYPE_CONSTRUCTION_SITE:
		return best_candidate

	var command_candidate := _get_best_command_candidate(
		citizen_id,
		-1,
		source_id
	)

	if not command_candidate.is_empty():
		best_candidate = command_candidate

	var construction_candidate := (
		CityConstructionSystemScript
		.get_best_assignable_player_work_for_citizen_and_site(
			citizen_id,
			source_id
		)
	)

	if not construction_candidate.is_empty():
		var kind := str(
			construction_candidate.get("player_work_kind", "")
		)
		var tie_break_key := str(
			construction_candidate.get("tie_break_key", "")
		)
		construction_candidate["job_id"] = kind + ":" + tie_break_key

		if _job_candidate_is_better(
			construction_candidate,
			best_candidate
		):
			best_candidate = construction_candidate

	if not best_candidate.is_empty():
		best_candidate["progress_unlocking"] = (
			_candidate_unlocks_progress(order, best_candidate)
		)

	return best_candidate


static func _get_best_command_candidate(
	citizen_id: int,
	group_id: int,
	construction_site_id: int
) -> Dictionary:
	var citizen := WorldData.get_city_citizen_by_id(citizen_id)
	var raw_citizen_tile = citizen.get(
		"city_tile_position",
		WorldData.INVALID_CITY_TILE_POSITION
	)

	if citizen.is_empty() or not raw_citizen_tile is Vector2i:
		return {}

	var citizen_tile: Vector2i = raw_citizen_tile
	var command_by_id: Dictionary = {}
	var command_ids_by_work_tile: Dictionary = {}
	var work_tile_lookup: Dictionary = {}

	for raw_command in get_city_player_command_snapshot():
		if not raw_command is Dictionary:
			continue

		var command: Dictionary = raw_command

		if (
			group_id > 0
			and (
				int(command.get("group_id", -1)) != group_id
				or int(command.get("construction_site_id", -1)) > 0
			)
		):
			continue

		if (
			construction_site_id > 0
			and int(command.get("construction_site_id", -1))
			!= construction_site_id
		):
			continue

		if not city_player_command_is_assignable(command):
			continue

		var command_id := int(command.get("id", -1))
		var work_tiles := get_city_player_command_work_tiles(
			command,
			citizen_id
		)

		if command_id <= 0 or work_tiles.is_empty():
			continue

		command_by_id[command_id] = command

		for work_tile in work_tiles:
			work_tile_lookup[work_tile] = true
			var command_ids: Array = command_ids_by_work_tile.get(
				work_tile,
				[]
			)

			if not command_ids.has(command_id):
				command_ids.append(command_id)
				command_ids.sort()
				command_ids_by_work_tile[work_tile] = command_ids

	if work_tile_lookup.is_empty():
		return {}

	var work_tiles: Array = work_tile_lookup.keys()
	work_tiles.sort_custom(WorldData._sort_city_tiles_y_then_x)
	var path_result := CityNavigationSystemScript.find_path_to_any_city_tile({
		"city_world": WorldData.official_city_world,
		"start_tile": citizen_tile,
		"destination_tiles": work_tiles,
		"max_expanded_nodes": CityNavigationSystemScript.get_city_wide_path_expansion_limit(
			WorldData.official_city_world
		),
		"citizen_id": citizen_id,
		"heuristic_weight": EXACT_COMMAND_PATH_HEURISTIC_WEIGHT,
	})
	if not bool(path_result.get("success", false)):
		return {}

	var raw_destination_tile = path_result.get(
		"destination_tile",
		WorldData.INVALID_CITY_TILE_POSITION
	)

	if not raw_destination_tile is Vector2i:
		return {}

	var matching_command_ids: Array = command_ids_by_work_tile.get(
		raw_destination_tile,
		[]
	)

	if matching_command_ids.is_empty():
		return {}

	matching_command_ids.sort()
	var selected_command_id := int(matching_command_ids[0])
	var raw_selected_command = command_by_id.get(selected_command_id, {})

	if not raw_selected_command is Dictionary:
		return {}

	var candidate: Dictionary = raw_selected_command.duplicate(true)
	candidate["player_work_kind"] = "command"
	candidate["job_id"] = "command:" + str(selected_command_id)
	candidate["estimated_path_cost"] = maxi(
		int(path_result.get("path_cost", 0)),
		0
	)
	candidate["target_tile"] = raw_destination_tile
	candidate["assignment_path"] = path_result.get("path", []).duplicate()
	candidate["tie_break_key"] = str(selected_command_id)
	return candidate


static func _get_parent_attention_score(
	order: Dictionary,
	candidate: Dictionary
) -> int:
	var now := SimulationClock.absolute_world_minutes
	var created_minute := int(order.get("created_world_minute", now))
	var last_progress_minute := int(
		order.get("last_progress_world_minute", created_minute)
	)
	var neglect_minutes := maxi(now - last_progress_minute, 0)
	var age_minutes := maxi(now - created_minute, 0)
	var neglect_score := mini(
		neglect_minutes * NEGLECT_SCORE_PER_MINUTE,
		MAX_NEGLECT_SCORE
	)
	var age_score := mini(
		age_minutes * AGE_SCORE_PER_MINUTE,
		MAX_AGE_SCORE
	)
	var path_cost := clampi(
		int(candidate.get("estimated_path_cost", LOCALITY_PATH_COST_CAP)),
		0,
		LOCALITY_PATH_COST_CAP
	)
	var locality_score := (
		MAX_LOCALITY_SCORE
		* (LOCALITY_PATH_COST_CAP - path_cost)
		/ LOCALITY_PATH_COST_CAP
	)
	var active_workers := _count_active_workers_for_order(order)
	var useful_capacity := maxi(
		int(order.get("useful_parallel_capacity", 1)),
		1
	)
	var active_worker_penalty := mini(
		MAX_ACTIVE_WORKER_PENALTY,
		MAX_ACTIVE_WORKER_PENALTY * active_workers / useful_capacity
	)
	var unlock_score := (
		PROGRESS_UNLOCK_SCORE
		if bool(candidate.get("progress_unlocking", false))
		else 0
	)

	return (
		int(order.get("priority_rank", PRIORITY_NORMAL))
		* PRIORITY_RANK_SCORE
		+ neglect_score
		+ age_score
		+ locality_score
		+ unlock_score
		- active_worker_penalty
	)


static func _selection_is_better(
	candidate: Dictionary,
	current_best: Dictionary
) -> bool:
	if candidate.is_empty():
		return false

	if current_best.is_empty():
		return true

	var candidate_score := int(
		candidate.get("parent_attention_score", 0)
	)
	var best_score := int(current_best.get("parent_attention_score", 0))

	if candidate_score != best_score:
		return candidate_score > best_score

	var candidate_order_id := int(candidate.get("work_order_id", -1))
	var best_order_id := int(current_best.get("work_order_id", -1))

	if candidate_order_id != best_order_id:
		return candidate_order_id < best_order_id

	return str(candidate.get("job_id", "")) < str(
		current_best.get("job_id", "")
	)


static func _job_candidate_is_better(
	candidate: Dictionary,
	current_best: Dictionary
) -> bool:
	if candidate.is_empty():
		return false

	if current_best.is_empty():
		return true

	var candidate_cost := maxi(
		int(candidate.get("estimated_path_cost", 0)),
		0
	)
	var best_cost := maxi(
		int(current_best.get("estimated_path_cost", 0)),
		0
	)

	if candidate_cost != best_cost:
		return candidate_cost < best_cost

	return str(candidate.get("job_id", "")) < str(
		current_best.get("job_id", "")
	)


static func _candidate_unlocks_progress(
	order: Dictionary,
	candidate: Dictionary
) -> bool:
	var actionable_jobs := 0

	for raw_job in order.get("jobs", []):
		if raw_job is Dictionary and bool(raw_job.get("actionable", false)):
			actionable_jobs += 1

	if actionable_jobs == 1:
		return true

	if (
		str(candidate.get("player_work_kind", ""))
		== CityConstructionSystemScript.PLAYER_WORK_KIND_LABOR
	):
		var site := WorldData.get_city_construction_site_by_id(
			int(order.get("source_id", -1))
		)
		return (
			not site.is_empty()
			and int(site.get("required_labor_minutes", 0))
			- int(site.get("completed_labor_minutes", 0))
			<= 6
		)

	return false


#endregion

#region Parallel Capacity and Blocked-State Diagnostics

static func _get_active_citizen_ids_for_order(
	order: Dictionary
) -> Array[int]:
	var active_citizen_lookup: Dictionary = {}
	var order_type := str(order.get("order_type", ""))
	var source_id := int(order.get("source_id", -1))
	var order_id := int(order.get("id", -1))

	for raw_citizen in WorldData.city_citizens:
		if not raw_citizen is Dictionary:
			continue

		var citizen: Dictionary = raw_citizen
		var citizen_id := int(citizen.get("id", -1))
		var task = citizen.get("current_task", {})

		if (
			citizen_id <= 0
			or not bool(citizen.get("alive", false))
			or not task is Dictionary
		):
			continue

		if int(task.get("work_order_id", -1)) == order_id:
			active_citizen_lookup[citizen_id] = true
			continue

		var task_kind := str(task.get("kind", ""))

		if task_kind == WorldData.CITY_CITIZEN_TASK_KIND_PLAYER_COMMAND:
			var command := WorldData.get_city_player_command_by_id(
				int(task.get("target_object_id", -1))
			)

			if command.is_empty():
				continue

			if (
				order_type == ORDER_TYPE_COMMAND_GROUP
				and int(command.get("group_id", -1)) == source_id
				and int(command.get("construction_site_id", -1)) <= 0
			) or (
				order_type == ORDER_TYPE_CONSTRUCTION_SITE
				and int(command.get("construction_site_id", -1)) == source_id
			):
				active_citizen_lookup[citizen_id] = true
		elif (
			order_type == ORDER_TYPE_CONSTRUCTION_SITE
			and task_kind == WorldData.CITY_CITIZEN_TASK_KIND_CONSTRUCTION
			and int(task.get("target_object_id", -1)) == source_id
		):
			active_citizen_lookup[citizen_id] = true
		elif (
			order_type == ORDER_TYPE_CONSTRUCTION_SITE
			and task_kind == WorldData.CITY_CITIZEN_TASK_KIND_HAUL
		):
			var haul = citizen.get("current_haul", {})

			if haul is Dictionary:
				var requester = haul.get("requester", {})

				if (
					requester is Dictionary
					and str(requester.get("kind", ""))
					== WorldData.CITY_CITIZEN_HAUL_ENDPOINT_KIND_CONSTRUCTION_SITE
					and int(requester.get("id", -1)) == source_id
				):
					active_citizen_lookup[citizen_id] = true

	var active_citizen_ids: Array[int] = []

	for raw_citizen_id in active_citizen_lookup.keys():
		active_citizen_ids.append(int(raw_citizen_id))

	active_citizen_ids.sort()
	return active_citizen_ids


static func _count_active_workers_for_order(order: Dictionary) -> int:
	return _get_active_citizen_ids_for_order(order).size()


static func _count_construction_workers(site_id: int) -> int:
	var count := 0

	for raw_citizen in WorldData.city_citizens:
		if not raw_citizen is Dictionary:
			continue

		var task = raw_citizen.get("current_task", {})

		if (
			task is Dictionary
			and str(task.get("kind", ""))
			== WorldData.CITY_CITIZEN_TASK_KIND_CONSTRUCTION
			and int(task.get("target_object_id", -1)) == site_id
		):
			count += 1

	return count


static func _get_useful_parallel_capacity(
	order: Dictionary,
	jobs: Array
) -> int:
	var actionable_job_count := 0

	for raw_job in jobs:
		if raw_job is Dictionary and bool(raw_job.get("actionable", false)):
			actionable_job_count += 1

	if str(order.get("order_type", "")) == ORDER_TYPE_CONSTRUCTION_SITE:
		var site := WorldData.get_city_construction_site_by_id(
			int(order.get("source_id", -1))
		)

		if not site.is_empty():
			return maxi(
				mini(
					maxi(actionable_job_count, 1),
					maxi(int(site.get("maximum_workers", 1)), 1)
				),
				1
			)

	return maxi(actionable_job_count, 1)


static func _get_order_blocked_reason(
	order: Dictionary,
	jobs: Array
) -> String:
	for raw_job in jobs:
		if (
			raw_job is Dictionary
			and (
				bool(raw_job.get("actionable", false))
				or str(raw_job.get("state", "")) == JOB_STATE_ACTIVE
			)
		):
			return BLOCKED_REASON_NONE

	for raw_job in jobs:
		if not raw_job is Dictionary:
			continue

		var blocked_reason := str(raw_job.get("blocked_reason", ""))

		if not blocked_reason.is_empty():
			return blocked_reason

	if jobs.is_empty():
		match _get_order_phase(order):
			WorldData.CITY_CONSTRUCTION_PHASE_CLEARING:
				return BLOCKED_REASON_WAITING_FOR_CLEARING

			WorldData.CITY_CONSTRUCTION_PHASE_GATHERING:
				return BLOCKED_REASON_WAITING_FOR_MATERIALS

	return BLOCKED_REASON_INVALIDATED


static func _get_relocation_destination_diagnostics(
	site_id: int,
	ground_pile_id: int,
	resource: String
) -> Dictionary:
	var compatible_public_destination_exists := false
	var public_available_amount := 0

	for raw_object in WorldData.city_objects:
		if not raw_object is Dictionary:
			continue

		var city_object: Dictionary = raw_object

		if (
			not WorldData.city_object_container_is_publicly_usable(city_object)
			or not WorldData.city_object_can_accept_haul_resource(
				city_object,
				resource,
				WorldData.CONTAINER_HAUL_PURPOSE_PUBLIC_STORAGE,
				false
			)
		):
			continue

		compatible_public_destination_exists = true
		var endpoint := WorldData.make_city_citizen_haul_endpoint(
			int(city_object.get("id", -1))
		)

		if WorldData.city_haul_endpoint_can_accept_resource({
			"endpoint": endpoint,
			"resource": resource,
			"deposit_purpose": WorldData.CONTAINER_HAUL_PURPOSE_PUBLIC_STORAGE,
			"require_unreserved_space": true,
		}):
			public_available_amount += (
				WorldData.get_city_haul_endpoint_unreserved_destination_space(
					endpoint
				)
			)

	var ground_available := (
		CityConstructionSystemScript.can_relocate_ground_pile_outside_site(
			site_id,
			ground_pile_id
		)
	)

	if public_available_amount > 0 or ground_available:
		return {
			"available": true,
			"available_amount": maxi(
				public_available_amount,
				1 if ground_available else 0
			),
			"blocked_reason": BLOCKED_REASON_NONE,
		}

	return {
		"available": false,
		"available_amount": 0,
		"blocked_reason": (
			BLOCKED_REASON_DESTINATION_FULL
			if compatible_public_destination_exists
			else BLOCKED_REASON_NO_LEGAL_DESTINATION
		),
	}


static func _get_construction_source_diagnostics(
	resource: String,
	requested_amount: int
) -> Dictionary:
	var supply_candidates := (
		CityResourceMatcherScript.get_resource_supply_candidates(
		CityResourceMatcherScript.PURPOSE_CONSTRUCTION_SUPPLY,
		resource,
		requested_amount
		)
	)
	var available_amount := 0

	for supply_candidate in supply_candidates:
		available_amount += maxi(
			int(supply_candidate.get("available_amount", 0)),
			0
		)

	available_amount = mini(available_amount, requested_amount)

	if available_amount > 0:
		return {
			"available": true,
			"available_amount": available_amount,
			"blocked_reason": BLOCKED_REASON_NONE,
		}

	var legal_physical_source_exists := false
	var legal_unreserved_amount := 0

	for raw_object in WorldData.city_objects:
		if not raw_object is Dictionary:
			continue

		var city_object: Dictionary = raw_object

		if not WorldData.city_object_container_is_publicly_usable(city_object):
			continue

		var endpoint := WorldData.make_city_citizen_haul_endpoint(
			int(city_object.get("id", -1))
		)

		if not WorldData.city_haul_endpoint_can_provide_resource({
			"endpoint": endpoint,
			"resource": resource,
			"withdrawal_purpose": WorldData.CONTAINER_HAUL_PURPOSE_CONSTRUCTION,
			"require_unreserved_amount": false,
		}):
			continue

		legal_physical_source_exists = true
		legal_unreserved_amount += (
			WorldData.get_city_haul_endpoint_unreserved_resource_amount(
				endpoint,
				resource
			)
		)

	for raw_pile in WorldData.get_city_ground_pile_snapshot():
		if (
			not raw_pile is Dictionary
			or WorldData.city_ground_pile_is_construction_reserved(raw_pile)
		):
			continue

		var endpoint := WorldData.make_city_ground_pile_haul_endpoint(
			int(raw_pile.get("id", -1))
		)

		if not WorldData.city_haul_endpoint_can_provide_resource({
			"endpoint": endpoint,
			"resource": resource,
			"withdrawal_purpose": WorldData.CONTAINER_HAUL_PURPOSE_CONSTRUCTION,
			"require_unreserved_amount": false,
		}):
			continue

		legal_physical_source_exists = true
		legal_unreserved_amount += (
			WorldData.get_city_haul_endpoint_unreserved_resource_amount(
				endpoint,
				resource
			)
		)

	var blocked_reason := BLOCKED_REASON_NO_LEGAL_SOURCE

	if legal_physical_source_exists and legal_unreserved_amount <= 0:
		blocked_reason = BLOCKED_REASON_SOURCE_FULLY_RESERVED
	elif WorldData.get_total_physical_city_resource_amount(resource) <= 0:
		blocked_reason = BLOCKED_REASON_SOURCE_EMPTY

	return {
		"available": false,
		"available_amount": 0,
		"blocked_reason": blocked_reason,
	}


#endregion

#region Attention Tracking and Shared Helpers

static func _note_order_attention(order_id: int) -> void:
	var raw_order = WorldData.city_work_orders.get(order_id, {})

	if not raw_order is Dictionary:
		return

	var order: Dictionary = raw_order
	order["last_attention_world_minute"] = (
		SimulationClock.absolute_world_minutes
	)
	WorldData.city_work_orders[order_id] = order
	WorldData.mark_city_work_orders_changed()


static func _make_command_group_source_key(group_id: int) -> String:
	return "command_group:" + str(group_id)


static func _make_construction_source_key(site_id: int) -> String:
	return "construction_site:" + str(site_id)





#endregion
