extends RefCounted
class_name CitizenTaskSystem

# File responsibility: Execution of assigned citizen tasks without changing task-selection policy.
# Navigation regions are organizational only; they do not define runtime ownership.

const CityNavigationSystemScript = preload(
	"res://scripts/city/simulation/systems/CityNavigationSystem.gd"
)
const CityActivityLocationResolverScript = preload(
	"res://scripts/city/simulation/systems/CityActivityLocationResolver.gd"
)
const CitizenHaulingSystemScript = preload(
	"res://scripts/citizens/simulation/systems/CitizenHaulingSystem.gd"
)
const CityConstructionSystemScript = preload(
	"res://scripts/city/simulation/systems/CityConstructionSystem.gd"
)
const MAX_TASK_PATH_REQUESTS_PER_TICK: int = 4
const BLOCKED_WORK_TASK_RETRY_DELAY_MINUTES: int = 30
const BLOCKED_RETURN_HOME_TASK_RETRY_DELAY_MINUTES: int = 30
const WORK_ACTIVITY_DWELL_REQUIRED_KEYS := [
	"citizen_id",
	"workplace_id",
	"target_tile",
	"previous_target_tile",
	"choice_sequence",
	"dwell_min_minutes",
	"dwell_max_minutes",
	"relocation_count",
	"maximum_relocations_per_task",
]

static var _work_activity_claim_counts: Dictionary = {}


#region Task Tick Entry Point

static func run_tick(
	tick_index: int,
	minutes_advanced: int
) -> void:
	_work_activity_claim_counts.clear()

	if minutes_advanced <= 0:
		return

	var city_world: WorldData = WorldData.official_city_world

	if city_world == null:
		return

	var active_task_ids := (
		CityCitizenTaskRuntimeSystem.get_city_active_task_ids_snapshot()
	)

	if active_task_ids.is_empty():
		return

	_work_activity_claim_counts = (
		_build_work_activity_claim_counts(
			active_task_ids
		)
	)

	var path_requests_remaining := (
		MAX_TASK_PATH_REQUESTS_PER_TICK
	)
	var ordered_active_task_ids: Array[int] = []
	var task_count := active_task_ids.size()
	var start_index := posmod(tick_index, task_count)

	# The path budget remains bounded, but the starting citizen rotates every
	# tick. This prevents higher-ID citizens from being starved indefinitely by
	# earlier tasks that repeatedly consume the shared path request budget.
	for offset in range(task_count):
		ordered_active_task_ids.append(
			active_task_ids[(start_index + offset) % task_count]
		)

	for citizen_id in ordered_active_task_ids:
		var citizen := CityCitizenRegistrySystem.get_city_citizen_by_id(
			citizen_id
		)

		if citizen.is_empty():
			continue

		if not bool(citizen.get("alive", false)):
			_clear_invalid_task(citizen_id)
			continue

		var current_task := (
			CityCitizenTaskRuntimeSystem.get_city_citizen_current_task(
				citizen_id
			)
		)

		var task_advance_context := {
			"citizen_id": citizen_id,
			"citizen": citizen,
			"current_task": current_task,
			"path_requests_remaining": path_requests_remaining,
			"tick_index": tick_index,
			"minutes_advanced": minutes_advanced,
		}

		match str(current_task.get("kind", "")):
			WorldData.CITY_CITIZEN_TASK_KIND_PLAYER_COMMAND:
				path_requests_remaining = (
					_advance_player_command_task(
						city_world,
						task_advance_context
					)
				)

			WorldData.CITY_CITIZEN_TASK_KIND_WORK:
				path_requests_remaining = (
					_advance_work_task(
						city_world,
						task_advance_context
					)
				)

			WorldData.CITY_CITIZEN_TASK_KIND_ACQUIRE_FOOD:
				path_requests_remaining = (
					_advance_acquire_food_task(
						city_world,
						task_advance_context
					)
				)

			WorldData.CITY_CITIZEN_TASK_KIND_HAUL:
				path_requests_remaining = (
					CitizenHaulingSystemScript.advance_haul_task(
						city_world,
						task_advance_context
					)
				)

			WorldData.CITY_CITIZEN_TASK_KIND_CONSTRUCTION:
				path_requests_remaining = (
					CityConstructionSystemScript.advance_labor_task(
						city_world,
						task_advance_context
					)
				)

			WorldData.CITY_CITIZEN_TASK_KIND_RETURN_HOME:
				path_requests_remaining = (
					_advance_return_home_task(
						city_world,
						task_advance_context
					)
				)

			WorldData.CITY_CITIZEN_TASK_KIND_NONE:
				_clear_invalid_task(citizen_id)

			_:
				_clear_invalid_task(citizen_id)


# Hunger never releases work speculatively. The decision system first finds a
# reachable, unreserved food source, then asks this boundary to release the
# citizen without losing cargo or partial physical work.
#endregion

#region Food Interrupt Boundaries

static func prepare_citizen_for_normal_food_interrupt(
	citizen_id: int
) -> bool:
	var citizen := CityCitizenRegistrySystem.get_city_citizen_by_id(citizen_id)

	if citizen.is_empty() or not bool(citizen.get("alive", false)):
		return false

	var current_task := CityCitizenTaskRuntimeSystem.get_city_citizen_current_task(citizen_id)
	var current_task_kind := str(
		current_task.get(
			"kind",
			WorldData.CITY_CITIZEN_TASK_KIND_NONE
		)
	)

	if current_task_kind == WorldData.CITY_CITIZEN_TASK_KIND_NONE:
		return true

	# A matched food source should end the current haul after its existing
	# physical obligation. Do not let a cargo-bearing citizen chain another
	# pickup while waiting for that safe delivery boundary.
	_disable_additional_haul_pickups_for_food(citizen_id, current_task)

	if not _task_is_at_normal_food_safe_boundary(citizen_id, current_task):
		return false

	return _release_task_for_normal_food(citizen_id, current_task)


static func _task_is_at_normal_food_safe_boundary(
	citizen_id: int,
	current_task: Dictionary
) -> bool:
	if CityCitizenInventorySystem.get_city_citizen_haul_cargo_amount(citizen_id) > 0:
		return false

	var task_kind := str(
		current_task.get("kind", WorldData.CITY_CITIZEN_TASK_KIND_NONE)
	)
	var task_phase := str(
		current_task.get("phase", WorldData.CITY_CITIZEN_TASK_PHASE_NONE)
	)

	match task_kind:
		WorldData.CITY_CITIZEN_TASK_KIND_ACQUIRE_FOOD:
			return false

		WorldData.CITY_CITIZEN_TASK_KIND_HAUL:
			var haul := CityCitizenTaskRuntimeSystem.get_city_citizen_current_haul(citizen_id)
			return (
				str(
					haul.get(
						"phase",
						WorldData.CITY_CITIZEN_HAUL_PHASE_NONE
					)
				)
				!= WorldData.CITY_CITIZEN_HAUL_PHASE_PICKING_UP
			)

		WorldData.CITY_CITIZEN_TASK_KIND_PLAYER_COMMAND:
			return task_phase != WorldData.CITY_CITIZEN_TASK_PHASE_PERFORMING

		WorldData.CITY_CITIZEN_TASK_KIND_WORK:
			return task_phase != WorldData.CITY_CITIZEN_TASK_PHASE_PERFORMING

		WorldData.CITY_CITIZEN_TASK_KIND_CONSTRUCTION:
			return task_phase != WorldData.CITY_CITIZEN_TASK_PHASE_PERFORMING

		WorldData.CITY_CITIZEN_TASK_KIND_RETURN_HOME:
			return true

	return false


static func _disable_additional_haul_pickups_for_food(
	citizen_id: int,
	current_task: Dictionary
) -> void:
	if (
		str(current_task.get("kind", ""))
		!= WorldData.CITY_CITIZEN_TASK_KIND_HAUL
	):
		return

	var haul := CityCitizenTaskRuntimeSystem.get_city_citizen_current_haul(citizen_id)

	if not bool(haul.get("allow_ground_pile_pickup_chaining", false)):
		return

	# Hunger may arrive during the visible pickup pass. Preserve that pickup,
	# but prevent it from expanding into another stop before delivery.
	haul["allow_ground_pile_pickup_chaining"] = false
	CityCitizenTaskRuntimeSystem.set_city_citizen_current_haul(citizen_id, haul)


static func _release_task_for_normal_food(
	citizen_id: int,
	expected_task: Dictionary
) -> bool:
	if CityCitizenInventorySystem.get_city_citizen_haul_cargo_amount(citizen_id) > 0:
		return false

	var current_task := CityCitizenTaskRuntimeSystem.get_city_citizen_current_task(citizen_id)
	var expected_kind := str(expected_task.get("kind", ""))

	if (
		str(current_task.get("kind", "")) != expected_kind
		or int(current_task.get("target_object_id", -1))
		!= int(expected_task.get("target_object_id", -1))
	):
		return false

	var task_source := str(
		current_task.get(
			"source",
			WorldData.CITY_CITIZEN_TASK_SOURCE_AUTONOMY
		)
	)
	var released := false

	if expected_kind == WorldData.CITY_CITIZEN_TASK_KIND_HAUL:
		released = (
			CitizenHaulingSystemScript
			.drop_citizen_haul_cargo_for_priority_interrupt(
				WorldData.official_city_world,
				citizen_id,
				task_source
			)
		)
	else:
		released = CityCitizenTaskRuntimeSystem.clear_city_citizen_task(
			citizen_id,
			task_source
		)

	if released:
		CityCitizenMovementRuntimeSystem.cancel_city_citizen_movement(citizen_id)

	return released

# Critical hunger is category-independent. It may release an ordinary command
# claim, interrupt construction, or exceptionally spill in-flight cargo through
# the existing atomic no-loss gateway.
#endregion

#region Critical Food Interrupts

static func prepare_citizen_for_critical_food_interrupt(
	citizen_id: int
) -> bool:
	var citizen := CityCitizenRegistrySystem.get_city_citizen_by_id(citizen_id)

	if citizen.is_empty() or not bool(citizen.get("alive", false)):
		return false

	var current_task := CityCitizenTaskRuntimeSystem.get_city_citizen_current_task(citizen_id)
	var current_task_kind := str(
		current_task.get("kind", WorldData.CITY_CITIZEN_TASK_KIND_NONE)
	)

	if current_task_kind == WorldData.CITY_CITIZEN_TASK_KIND_PLAYER_COMMAND:
		var command_id := int(current_task.get("target_object_id", -1))

		CityWorkSystem.release_city_player_command_claim(
			command_id,
			citizen_id
		)
		CityCitizenMovementRuntimeSystem.cancel_city_citizen_movement(citizen_id)
		return CityCitizenTaskRuntimeSystem.clear_city_citizen_task(
			citizen_id,
			WorldData.CITY_CITIZEN_TASK_SOURCE_PLAYER
		)

	if (
		CityConstructionSystemScript
		.citizen_task_is_interruptible_construction(citizen_id)
	):
		return (
			CityConstructionSystemScript
			.interrupt_citizen_construction_for_food(citizen_id)
		)

	return CitizenHaulingSystemScript.drop_citizen_haul_cargo_for_priority_interrupt(
		WorldData.official_city_world,
		citizen_id,
		WorldData.CITY_CITIZEN_TASK_SOURCE_AUTONOMY
	)


#endregion

#region Acquire Food Task

static func _advance_acquire_food_task(
	city_world: WorldData,
	values: Dictionary
) -> int:
	var citizen_id := int(values.get("citizen_id", -1))
	var citizen: Dictionary = values.get("citizen", {})
	var current_task: Dictionary = values.get("current_task", {})
	var path_requests_remaining := maxi(
		int(values.get("path_requests_remaining", 0)),
		0
	)
	var source_endpoint_id := int(current_task.get("target_object_id", -1))
	var source_endpoint_kind := str(
		current_task.get(
			"food_source_endpoint_kind",
			WorldData.CITY_CITIZEN_HAUL_ENDPOINT_KIND_CITY_OBJECT_CONTAINER
		)
	)
	var source_endpoint := {
		"kind": source_endpoint_kind,
		"id": source_endpoint_id,
	}
	var resource := str(
		current_task.get("food_resource_type", WorldData.RESOURCE_NONE)
	)
	var requested_amount := maxi(
		int(current_task.get("food_requested_amount", 0)),
		0
	)
	var access_purpose := str(
		current_task.get(
			"food_source_access_purpose",
			WorldData.CONTAINER_DIRECT_WITHDRAWAL_PURPOSE_NONE
		)
	)
	var raw_target_tile = current_task.get(
		"target_tile",
		WorldData.INVALID_CITY_TILE_POSITION
	)
	var raw_current_tile = citizen.get(
		"city_tile_position",
		WorldData.INVALID_CITY_TILE_POSITION
	)

	if (
		CityResourceCatalog.get_city_food_hunger_restore(resource) <= 0
		or requested_amount <= 0
		or access_purpose
		!= WorldData.CONTAINER_DIRECT_WITHDRAWAL_PURPOSE_PERSONAL_FOOD
		or not raw_target_tile is Vector2i
		or not raw_current_tile is Vector2i
		or not CityCitizens.is_valid_city_citizen_haul_endpoint(
			source_endpoint
		)
		or not CitizenNeedsSystem.get_city_citizen_food_endpoint_target_tiles(
			citizen_id,
			source_endpoint
		).has(raw_target_tile)
		or not CitizenNeedsSystem.city_citizen_can_withdraw_food_from_endpoint(
			citizen_id,
			source_endpoint,
			resource
		)
	):
		_clear_invalid_task(citizen_id)
		return path_requests_remaining

	if CitizenNeedsSystem.get_citizen_food_need_nutrition(citizen_id) <= 0:
		_complete_acquire_food_task(citizen_id)
		return path_requests_remaining

	var target_tile: Vector2i = raw_target_tile
	var current_tile: Vector2i = raw_current_tile
	var movement_state := str(
		citizen.get(
			"movement_state",
			WorldData.CITY_CITIZEN_MOVEMENT_STATE_IDLE
		)
	)

	if current_tile == target_tile:
		var desired_nutrition := CitizenNeedsSystem.get_citizen_food_need_nutrition(
			citizen_id
		)
		var hunger_restore := CityResourceCatalog.get_city_food_hunger_restore(resource)
		var exact_requested_units := mini(
			requested_amount,
			ceili(float(desired_nutrition) / float(hunger_restore))
		)
		var transferred_amount := (
			CitizenNeedsSystem.transfer_city_food_endpoint_to_citizen_inventory(
				citizen_id,
				source_endpoint,
				resource,
				exact_requested_units
			)
		)

		if transferred_amount > 0:
			CitizenNeedsSystem.eat_personal_food_if_hungry(citizen_id)

		_complete_acquire_food_task(citizen_id)
		return path_requests_remaining

	if movement_state == WorldData.CITY_CITIZEN_MOVEMENT_STATE_MOVING:
		return path_requests_remaining

	if movement_state == WorldData.CITY_CITIZEN_MOVEMENT_STATE_BLOCKED:
		_clear_invalid_task(citizen_id)
		return path_requests_remaining

	if path_requests_remaining <= 0:
		return path_requests_remaining

	path_requests_remaining -= 1
	var path_result := CityNavigationSystemScript.find_path_to_any_city_tile({
		"city_world": city_world,
		"start_tile": current_tile,
		"destination_tiles": [target_tile],
		"max_expanded_nodes": CityNavigationSystemScript.get_city_wide_path_expansion_limit(city_world),
		"citizen_id": citizen_id,
		"heuristic_weight": 1,
	})
	if not bool(path_result.get("success", false)):
		_clear_invalid_task(citizen_id)
		return path_requests_remaining

	var raw_path = path_result.get("path", [])
	var raw_destination_tile = path_result.get(
		"destination_tile",
		WorldData.INVALID_CITY_TILE_POSITION
	)

	if (
		not raw_path is Array
		or not raw_destination_tile is Vector2i
		or raw_destination_tile != target_tile
	):
		_clear_invalid_task(citizen_id)
		return path_requests_remaining

	if raw_path.size() <= 1:
		_clear_invalid_task(citizen_id)
		return path_requests_remaining

	if not CityCitizenMovementRuntimeSystem.assign_city_citizen_movement_order(citizen_id, raw_path):
		_clear_invalid_task(citizen_id)
		return path_requests_remaining

	CityCitizenTaskRuntimeSystem.set_city_citizen_task_phase(
		citizen_id,
		WorldData.CITY_CITIZEN_TASK_PHASE_TRAVELING
	)
	return path_requests_remaining


static func _complete_acquire_food_task(citizen_id: int) -> void:
	var current_task := CityCitizenTaskRuntimeSystem.get_city_citizen_current_task(citizen_id)
	var task_source := str(
		current_task.get(
			"source",
			WorldData.CITY_CITIZEN_TASK_SOURCE_AUTONOMY
		)
	)

	CityCitizenMovementRuntimeSystem.cancel_city_citizen_movement(citizen_id)
	CityCitizenTaskRuntimeSystem.clear_city_citizen_task(citizen_id, task_source)


# Normal player work may preempt an unemployed citizen before pickup. Once the
# citizen carries cargo, the current short delivery is the safe boundary and is
# allowed to finish; an ordinary player order never causes a cargo spill.
#endregion

#region Priority and Player Command Interrupts

static func prepare_unemployed_citizen_for_priority_interrupt(
	citizen_id: int
) -> bool:
	var citizen := CityCitizenRegistrySystem.get_city_citizen_by_id(citizen_id)

	if (
		citizen.is_empty()
		or not bool(citizen.get("alive", false))
		or int(citizen.get("job_object_id", -1)) > 0
	):
		return false

	var current_task := CityCitizenTaskRuntimeSystem.get_city_citizen_current_task(citizen_id)

	if (
		str(current_task.get("kind", ""))
		== WorldData.CITY_CITIZEN_TASK_KIND_ACQUIRE_FOOD
		or CityCitizenInventorySystem.get_city_citizen_haul_cargo_amount(citizen_id) > 0
	):
		return false

	return (
		CitizenHaulingSystemScript
		.drop_citizen_haul_cargo_for_priority_interrupt(
			WorldData.official_city_world,
			citizen_id,
			WorldData.CITY_CITIZEN_TASK_SOURCE_PLAYER
		)
	)


# Compatibility gateway for the existing player-command decision path.
static func prepare_unemployed_citizen_for_player_command(
	citizen_id: int
) -> bool:
	return prepare_unemployed_citizen_for_priority_interrupt(citizen_id)


#endregion

#region Player Command Task

static func _advance_player_command_task(
	city_world: WorldData,
	values: Dictionary
) -> int:
	var context := _make_player_command_task_context(city_world, values)
	var path_requests_remaining := maxi(
		int(values.get("path_requests_remaining", 0)),
		0
	)

	if context.is_empty():
		return path_requests_remaining

	match str(
		context.get(
			"task_phase",
			WorldData.CITY_CITIZEN_TASK_PHASE_NONE
		)
	):
		WorldData.CITY_CITIZEN_TASK_PHASE_PENDING:
			return _advance_pending_player_command_task(context)

		WorldData.CITY_CITIZEN_TASK_PHASE_TRAVELING:
			return _advance_traveling_player_command_task(context)

		WorldData.CITY_CITIZEN_TASK_PHASE_PERFORMING:
			return _advance_performing_player_command_task(context)

		WorldData.CITY_CITIZEN_TASK_PHASE_BLOCKED:
			_release_player_command_task(
				int(context.get("citizen_id", -1)),
				int(context.get("command_id", -1)),
				true
			)

		_:
			_clear_invalid_task(int(context.get("citizen_id", -1)))

	return int(context.get("path_requests_remaining", 0))


static func _make_player_command_task_context(
	city_world: WorldData,
	values: Dictionary
) -> Dictionary:
	var citizen_id := int(values.get("citizen_id", -1))
	var citizen: Dictionary = values.get("citizen", {})
	var current_task: Dictionary = values.get("current_task", {})
	var path_requests_remaining := maxi(
		int(values.get("path_requests_remaining", 0)),
		0
	)
	var command_id := int(current_task.get("target_object_id", -1))
	var command := CityWorkSystem.get_city_player_command_by_id(command_id)

	if (
		command.is_empty()
		or int(command.get("claimed_citizen_id", -1)) != citizen_id
		or int(citizen.get("job_object_id", -1)) > 0
	):
		_clear_invalid_task(citizen_id)
		return {}

	if not CityWorkSystem.is_city_player_command_target_valid(command):
		CityWorkSystem.cancel_city_player_command(command_id)
		return {}

	var raw_command_tile = command.get(
		"tile_position",
		WorldData.INVALID_CITY_TILE_POSITION
	)
	var raw_current_tile = citizen.get(
		"city_tile_position",
		WorldData.INVALID_CITY_TILE_POSITION
	)

	if not raw_command_tile is Vector2i or not raw_current_tile is Vector2i:
		_release_player_command_task(citizen_id, command_id, true)
		return {}

	var work_tiles := CityWorkSystem.get_city_player_command_work_tiles(
		command,
		citizen_id
	)

	if work_tiles.is_empty():
		_release_player_command_task(citizen_id, command_id, true)
		return {}

	var raw_task_target_tile = current_task.get(
		"target_tile",
		WorldData.INVALID_CITY_TILE_POSITION
	)
	var target_tile: Vector2i = raw_command_tile

	if raw_task_target_tile is Vector2i and work_tiles.has(raw_task_target_tile):
		target_tile = raw_task_target_tile

	return {
		"city_world": city_world,
		"citizen_id": citizen_id,
		"citizen": citizen,
		"current_task": current_task,
		"path_requests_remaining": path_requests_remaining,
		"command_id": command_id,
		"command": command,
		"current_tile": raw_current_tile,
		"work_tiles": work_tiles,
		"target_tile": target_tile,
		"task_phase": str(
			current_task.get(
				"phase",
				WorldData.CITY_CITIZEN_TASK_PHASE_NONE
			)
		),
		"movement_state": str(
			citizen.get(
				"movement_state",
				WorldData.CITY_CITIZEN_MOVEMENT_STATE_IDLE
			)
		),
	}


static func _advance_pending_player_command_task(
	context: Dictionary
) -> int:
	var city_world: WorldData = context.get("city_world")
	var citizen_id := int(context.get("citizen_id", -1))
	var command_id := int(context.get("command_id", -1))
	var command: Dictionary = context.get("command", {})
	var current_tile: Vector2i = context.get(
		"current_tile",
		WorldData.INVALID_CITY_TILE_POSITION
	)
	var work_tiles: Array = context.get("work_tiles", [])
	var movement_state := str(context.get("movement_state", ""))
	var path_requests_remaining := int(
		context.get("path_requests_remaining", 0)
	)

	if work_tiles.has(current_tile):
		if not _begin_player_command_work(citizen_id, current_tile, command):
			_release_player_command_task(citizen_id, command_id, true)
		return path_requests_remaining

	if movement_state == WorldData.CITY_CITIZEN_MOVEMENT_STATE_MOVING:
		return path_requests_remaining

	if path_requests_remaining <= 0:
		return path_requests_remaining

	path_requests_remaining -= 1
	var path_result := CityNavigationSystemScript.find_path_to_any_city_tile({
		"city_world": city_world,
		"start_tile": current_tile,
		"destination_tiles": work_tiles,
		"max_expanded_nodes": CityNavigationSystemScript.get_city_wide_path_expansion_limit(city_world),
		"citizen_id": citizen_id,
		"heuristic_weight": 1,
	})
	if not bool(path_result.get("success", false)):
		_release_player_command_task(citizen_id, command_id, true)
		return path_requests_remaining

	var raw_path = path_result.get("path", [])
	var raw_destination_tile = path_result.get(
		"destination_tile",
		WorldData.INVALID_CITY_TILE_POSITION
	)

	if (
		not raw_path is Array
		or not raw_destination_tile is Vector2i
		or not work_tiles.has(raw_destination_tile)
		or not CityCitizenTaskRuntimeSystem.set_city_citizen_task_activity_state({
			"citizen_id": citizen_id,
			"target_tile": raw_destination_tile,
			"next_action_world_minute": (
				WorldData.INVALID_CITY_CITIZEN_TASK_ACTION_WORLD_MINUTE
			),
		})
		or not CityCitizenMovementRuntimeSystem.assign_city_citizen_movement_order(
			citizen_id,
			raw_path
		)
	):
		_release_player_command_task(citizen_id, command_id, true)
		return path_requests_remaining

	CityCitizenTaskRuntimeSystem.set_city_citizen_task_phase(
		citizen_id,
		WorldData.CITY_CITIZEN_TASK_PHASE_TRAVELING
	)
	return path_requests_remaining


static func _advance_traveling_player_command_task(
	context: Dictionary
) -> int:
	var citizen_id := int(context.get("citizen_id", -1))
	var command_id := int(context.get("command_id", -1))
	var command: Dictionary = context.get("command", {})
	var current_tile: Vector2i = context.get(
		"current_tile",
		WorldData.INVALID_CITY_TILE_POSITION
	)
	var target_tile: Vector2i = context.get(
		"target_tile",
		WorldData.INVALID_CITY_TILE_POSITION
	)
	var work_tiles: Array = context.get("work_tiles", [])
	var movement_state := str(context.get("movement_state", ""))
	var path_requests_remaining := int(
		context.get("path_requests_remaining", 0)
	)

	if work_tiles.has(current_tile) and current_tile == target_tile:
		if not _begin_player_command_work(citizen_id, target_tile, command):
			_release_player_command_task(citizen_id, command_id, true)
		return path_requests_remaining

	if movement_state == WorldData.CITY_CITIZEN_MOVEMENT_STATE_MOVING:
		return path_requests_remaining

	if movement_state == WorldData.CITY_CITIZEN_MOVEMENT_STATE_BLOCKED:
		_release_player_command_task(citizen_id, command_id, true)
		return path_requests_remaining

	CityCitizenTaskRuntimeSystem.set_city_citizen_task_phase(
		citizen_id,
		WorldData.CITY_CITIZEN_TASK_PHASE_PENDING
	)
	return path_requests_remaining


static func _advance_performing_player_command_task(
	context: Dictionary
) -> int:
	var citizen_id := int(context.get("citizen_id", -1))
	var command_id := int(context.get("command_id", -1))
	var current_task: Dictionary = context.get("current_task", {})
	var current_tile: Vector2i = context.get(
		"current_tile",
		WorldData.INVALID_CITY_TILE_POSITION
	)
	var target_tile: Vector2i = context.get(
		"target_tile",
		WorldData.INVALID_CITY_TILE_POSITION
	)
	var path_requests_remaining := int(
		context.get("path_requests_remaining", 0)
	)

	if current_tile != target_tile:
		CityCitizenTaskRuntimeSystem.set_city_citizen_task_activity_state({
			"citizen_id": citizen_id,
			"target_tile": target_tile,
			"next_action_world_minute": (
				WorldData.INVALID_CITY_CITIZEN_TASK_ACTION_WORLD_MINUTE
			),
		})
		CityCitizenTaskRuntimeSystem.set_city_citizen_task_phase(
			citizen_id,
			WorldData.CITY_CITIZEN_TASK_PHASE_PENDING
		)
		return path_requests_remaining

	var completion_minute := int(
		current_task.get(
			"next_action_world_minute",
			WorldData.INVALID_CITY_CITIZEN_TASK_ACTION_WORLD_MINUTE
		)
	)

	if (
		completion_minute < 0
		or SimulationClock.absolute_world_minutes < completion_minute
	):
		return path_requests_remaining

	if CityWorkSystem.complete_city_player_command(command_id, citizen_id):
		CityCitizenTaskRuntimeSystem.clear_city_citizen_task(
			citizen_id,
			WorldData.CITY_CITIZEN_TASK_SOURCE_PLAYER
		)
		CityCitizenMovementRuntimeSystem.cancel_city_citizen_movement(citizen_id)
	else:
		_release_player_command_task(citizen_id, command_id, true)

	return path_requests_remaining


static func _begin_player_command_work(
	citizen_id: int,
	target_tile: Vector2i,
	command: Dictionary
) -> bool:
	CityCitizenMovementRuntimeSystem.cancel_city_citizen_movement(citizen_id)

	var work_duration_minutes := maxi(
		int(
			command.get(
				"work_duration_minutes",
				CityWorkSystem.CITY_PLAYER_COMMAND_WORK_DURATION_MINUTES
			)
		),
		1
	)

	if not CityCitizenTaskRuntimeSystem.set_city_citizen_task_activity_state({
		"citizen_id": citizen_id,
		"target_tile": target_tile,
		"next_action_world_minute": (
			SimulationClock.absolute_world_minutes
			+ work_duration_minutes
		),
	}):
		return false

	return CityCitizenTaskRuntimeSystem.set_city_citizen_task_phase(
		citizen_id,
		WorldData.CITY_CITIZEN_TASK_PHASE_PERFORMING
	)


static func _release_player_command_task(
	citizen_id: int,
	command_id: int,
	blocked: bool
) -> void:
	var retry_minute := -1

	if blocked:
		retry_minute = (
			SimulationClock.absolute_world_minutes
			+ CityWorkSystem.CITY_PLAYER_COMMAND_BLOCKED_RETRY_DELAY_MINUTES
		)

	CityWorkSystem.release_city_player_command_claim(
		command_id,
		citizen_id,
		retry_minute
	)
	CityCitizenTaskRuntimeSystem.clear_city_citizen_task(
		citizen_id,
		WorldData.CITY_CITIZEN_TASK_SOURCE_PLAYER
	)
	CityCitizenMovementRuntimeSystem.cancel_city_citizen_movement(citizen_id)


#endregion

#region Work Task

static func _advance_work_task(
	city_world: WorldData,
	values: Dictionary
) -> int:
	var context := _make_work_task_advance_context(city_world, values)
	var path_requests_remaining := maxi(
		int(values.get("path_requests_remaining", 0)),
		0
	)

	if context.is_empty():
		return path_requests_remaining

	match str(
		context.get(
			"task_phase",
			WorldData.CITY_CITIZEN_TASK_PHASE_NONE
		)
	):
		WorldData.CITY_CITIZEN_TASK_PHASE_PENDING:
			return _advance_pending_work_task(context)

		WorldData.CITY_CITIZEN_TASK_PHASE_TRAVELING:
			return _advance_traveling_work_task(context)

		WorldData.CITY_CITIZEN_TASK_PHASE_PERFORMING:
			return _advance_performing_work_task(context)

		WorldData.CITY_CITIZEN_TASK_PHASE_BLOCKED:
			return _advance_blocked_work_task(context)

		_:
			_set_work_task_blocked(int(context.get("citizen_id", -1)))
			return int(context.get("path_requests_remaining", 0))


static func _make_work_task_advance_context(
	city_world: WorldData,
	values: Dictionary
) -> Dictionary:
	var citizen_id := int(values.get("citizen_id", -1))
	var citizen: Dictionary = values.get("citizen", {})
	var current_task: Dictionary = values.get("current_task", {})
	var path_requests_remaining := maxi(
		int(values.get("path_requests_remaining", 0)),
		0
	)
	var workplace_id := int(current_task.get("target_object_id", -1))
	var workplace := CityObjectSystem.get_city_object_by_id(workplace_id)

	if (
		workplace_id <= 0
		or workplace.is_empty()
		or not WorldData.city_object_is_workplace(workplace)
		or int(citizen.get("job_object_id", -1)) != workplace_id
	):
		_clear_invalid_task(citizen_id)
		return {}

	var movement_policy := WorldData.get_city_object_work_movement_policy(
		workplace
	)
	var dwell_min_minutes := maxi(
		int(movement_policy.get("dwell_min_minutes", 0)),
		0
	)
	var dwell_max_minutes := maxi(
		int(movement_policy.get("dwell_max_minutes", dwell_min_minutes)),
		dwell_min_minutes
	)
	var activity_tiles := (
		CityActivityLocationResolverScript.get_work_activity_tiles(
			city_world,
			workplace
		)
	)
	var preferred_activity_tiles := _get_preferred_work_activity_tiles(
		activity_tiles,
		citizen_id
	)
	var raw_current_tile = citizen.get(
		"city_tile_position",
		WorldData.INVALID_CITY_TILE_POSITION
	)

	if not raw_current_tile is Vector2i:
		_set_work_task_blocked(citizen_id)
		return {}

	return {
		"city_world": city_world,
		"citizen_id": citizen_id,
		"citizen": citizen,
		"current_task": current_task,
		"path_requests_remaining": path_requests_remaining,
		"tick_index": int(values.get("tick_index", 0)),
		"workplace_id": workplace_id,
		"workplace": workplace,
		"workplace_movement_mode": str(
			movement_policy.get(
				"mode",
				WorldData.WORKPLACE_MOVEMENT_MODE_NONE
			)
		),
		"dwell_min_minutes": dwell_min_minutes,
		"dwell_max_minutes": dwell_max_minutes,
		"maximum_relocations_per_task": maxi(
			int(
				movement_policy.get(
					"maximum_relocations_per_task",
					0
				)
			),
			0
		),
		"minimum_relocation_distance": maxi(
			int(movement_policy.get("minimum_relocation_distance", 0)),
			0
		),
		"avoid_previous_target": bool(
			movement_policy.get("avoid_previous_target", false)
		),
		"activity_tiles": activity_tiles,
		"preferred_activity_tiles": preferred_activity_tiles,
		"current_tile": raw_current_tile,
		"task_phase": str(
			current_task.get(
				"phase",
				WorldData.CITY_CITIZEN_TASK_PHASE_NONE
			)
		),
		"relocation_count": maxi(
			int(current_task.get("relocation_count", 0)),
			0
		),
		"movement_state": str(
			citizen.get(
				"movement_state",
				WorldData.CITY_CITIZEN_MOVEMENT_STATE_IDLE
			)
		),
	}


static func _make_work_activity_dwell_values(
	context: Dictionary,
	values: Dictionary = {}
) -> Dictionary:
	var current_task: Dictionary = context.get("current_task", {})
	var dwell_values := {
		"citizen_id": int(context.get("citizen_id", -1)),
		"workplace_id": int(context.get("workplace_id", -1)),
		"target_tile": context.get(
			"current_tile",
			WorldData.INVALID_CITY_TILE_POSITION
		),
		"previous_target_tile": current_task.get(
			"previous_target_tile",
			WorldData.INVALID_CITY_TILE_POSITION
		),
		"choice_sequence": int(context.get("tick_index", 0)),
		"dwell_min_minutes": int(context.get("dwell_min_minutes", 0)),
		"dwell_max_minutes": int(context.get("dwell_max_minutes", 0)),
		"relocation_count": int(context.get("relocation_count", 0)),
		"maximum_relocations_per_task": int(
			context.get("maximum_relocations_per_task", 0)
		),
	}

	for key in values.keys():
		dwell_values[key] = values[key]

	return dwell_values


static func _advance_pending_work_task(context: Dictionary) -> int:
	var city_world: WorldData = context.get("city_world")
	var citizen_id := int(context.get("citizen_id", -1))
	var workplace_id := int(context.get("workplace_id", -1))
	var current_task: Dictionary = context.get("current_task", {})
	var current_tile: Vector2i = context.get(
		"current_tile",
		WorldData.INVALID_CITY_TILE_POSITION
	)
	var activity_tiles: Array = context.get("activity_tiles", [])
	var preferred_activity_tiles: Array = context.get(
		"preferred_activity_tiles",
		[]
	)
	var movement_state := str(context.get("movement_state", ""))
	var path_requests_remaining := int(
		context.get("path_requests_remaining", 0)
	)

	if activity_tiles.is_empty():
		_set_work_task_blocked(citizen_id)
		return path_requests_remaining

	if preferred_activity_tiles.has(current_tile):
		if movement_state != WorldData.CITY_CITIZEN_MOVEMENT_STATE_IDLE:
			CityCitizenMovementRuntimeSystem.cancel_city_citizen_movement(citizen_id)

		if not _begin_work_activity_dwell(
			_make_work_activity_dwell_values(context)
		):
			_set_work_task_blocked(citizen_id)

		return path_requests_remaining

	if movement_state == WorldData.CITY_CITIZEN_MOVEMENT_STATE_MOVING:
		return path_requests_remaining

	if movement_state == WorldData.CITY_CITIZEN_MOVEMENT_STATE_BLOCKED:
		_set_work_task_blocked(citizen_id)
		return path_requests_remaining

	if path_requests_remaining <= 0:
		return path_requests_remaining

	path_requests_remaining -= 1
	var path_result := CityNavigationSystemScript.find_path_to_any_city_tile({
		"city_world": city_world,
		"start_tile": current_tile,
		"destination_tiles": preferred_activity_tiles,
		"max_expanded_nodes": CityNavigationSystemScript.get_city_wide_path_expansion_limit(city_world),
		"citizen_id": citizen_id,
		"heuristic_weight": CityNavigationSystem.HEURISTIC_WEIGHT,
	})
	if not bool(path_result.get("success", false)):
		_set_work_task_blocked(citizen_id)
		push_warning(
			"Citizen "
			+ str(citizen_id)
			+ " could not reach workplace "
			+ str(workplace_id)
			+ ": "
			+ str(path_result.get("status", "unknown"))
		)
		return path_requests_remaining

	var raw_path = path_result.get("path", [])

	if not raw_path is Array:
		_set_work_task_blocked(citizen_id)
		return path_requests_remaining

	var movement_path: Array = raw_path
	var raw_selected_destination = path_result.get(
		"destination_tile",
		WorldData.INVALID_CITY_TILE_POSITION
	)

	if not raw_selected_destination is Vector2i:
		_set_work_task_blocked(citizen_id)
		return path_requests_remaining

	var selected_destination: Vector2i = raw_selected_destination

	if not preferred_activity_tiles.has(selected_destination):
		_set_work_task_blocked(citizen_id)
		return path_requests_remaining

	if not _set_work_task_activity_state({
		"citizen_id": citizen_id,
		"target_tile": selected_destination,
	}):
		_set_work_task_blocked(citizen_id)
		return path_requests_remaining

	if movement_path.size() <= 1:
		CityCitizenTaskRuntimeSystem.set_city_citizen_task_phase(
			citizen_id,
			WorldData.CITY_CITIZEN_TASK_PHASE_PERFORMING
		)
		return path_requests_remaining

	if not CityCitizenMovementRuntimeSystem.assign_city_citizen_movement_order(
		citizen_id,
		movement_path
	):
		_set_work_task_blocked(citizen_id)
		return path_requests_remaining

	CityCitizenTaskRuntimeSystem.set_city_citizen_task_phase(
		citizen_id,
		WorldData.CITY_CITIZEN_TASK_PHASE_TRAVELING
	)
	return path_requests_remaining


static func _advance_traveling_work_task(context: Dictionary) -> int:
	var citizen_id := int(context.get("citizen_id", -1))
	var workplace_id := int(context.get("workplace_id", -1))
	var current_task: Dictionary = context.get("current_task", {})
	var current_tile: Vector2i = context.get(
		"current_tile",
		WorldData.INVALID_CITY_TILE_POSITION
	)
	var activity_tiles: Array = context.get("activity_tiles", [])
	var movement_state := str(context.get("movement_state", ""))
	var path_requests_remaining := int(
		context.get("path_requests_remaining", 0)
	)

	if movement_state == WorldData.CITY_CITIZEN_MOVEMENT_STATE_BLOCKED:
		_set_work_task_blocked(citizen_id)
	elif movement_state == WorldData.CITY_CITIZEN_MOVEMENT_STATE_IDLE:
		var target_tile: Vector2i = current_task.get(
			"target_tile",
			WorldData.INVALID_CITY_TILE_POSITION
		)

		if activity_tiles.has(current_tile) and current_tile == target_tile:
			if not _begin_work_activity_dwell(
				_make_work_activity_dwell_values(context)
			):
				_set_work_task_blocked(citizen_id)
		else:
			_set_work_task_blocked(citizen_id)

	return path_requests_remaining


static func _advance_performing_work_task(context: Dictionary) -> int:
	var city_world: WorldData = context.get("city_world")
	var citizen_id := int(context.get("citizen_id", -1))
	var workplace_id := int(context.get("workplace_id", -1))
	var current_task: Dictionary = context.get("current_task", {})
	var current_tile: Vector2i = context.get(
		"current_tile",
		WorldData.INVALID_CITY_TILE_POSITION
	)
	var activity_tiles: Array = context.get("activity_tiles", [])
	var preferred_activity_tiles: Array = context.get(
		"preferred_activity_tiles",
		[]
	)
	var path_requests_remaining := int(
		context.get("path_requests_remaining", 0)
	)
	var relocation_count := int(context.get("relocation_count", 0))
	var maximum_relocations_per_task := int(
		context.get("maximum_relocations_per_task", 0)
	)

	if not CityEmploymentSystem.is_city_citizen_attending_workplace(
		citizen_id,
		workplace_id,
		city_world
	):
		_set_work_task_blocked(citizen_id)
		return path_requests_remaining

	if (
		str(context.get("workplace_movement_mode", ""))
		!= WorldData.WORKPLACE_MOVEMENT_MODE_MOVE_BETWEEN_WORK_POINTS
	):
		return path_requests_remaining

	if relocation_count >= maximum_relocations_per_task:
		return path_requests_remaining

	var next_action_world_minute := int(
		current_task.get(
			"next_action_world_minute",
			WorldData.INVALID_CITY_CITIZEN_TASK_ACTION_WORLD_MINUTE
		)
	)

	if (
		next_action_world_minute
		== WorldData.INVALID_CITY_CITIZEN_TASK_ACTION_WORLD_MINUTE
	):
		if not _begin_work_activity_dwell(
			_make_work_activity_dwell_values(context)
		):
			_set_work_task_blocked(citizen_id)
		return path_requests_remaining

	if SimulationClock.absolute_world_minutes < next_action_world_minute:
		return path_requests_remaining

	if path_requests_remaining <= 0:
		return path_requests_remaining

	var previous_target_tile: Vector2i = current_task.get(
		"previous_target_tile",
		WorldData.INVALID_CITY_TILE_POSITION
	)
	var departing_tile := current_tile
	var relocation_candidate_tiles: Array[Vector2i] = []

	for candidate_tile in preferred_activity_tiles:
		if candidate_tile != current_tile:
			relocation_candidate_tiles.append(candidate_tile)

	if relocation_candidate_tiles.is_empty():
		relocation_candidate_tiles = activity_tiles.duplicate()

	var new_target_tile := (
		CityActivityLocationResolverScript.choose_work_activity_tile({
			"activity_tiles": relocation_candidate_tiles,
			"current_tile": current_tile,
			"previous_target_tile": previous_target_tile,
			"citizen_id": citizen_id,
			"workplace_id": workplace_id,
			"choice_sequence": int(context.get("tick_index", 0)),
			"minimum_relocation_distance": int(
				context.get("minimum_relocation_distance", 0)
			),
			"avoid_previous_target": bool(
				context.get("avoid_previous_target", false)
			),
		})
	)

	if new_target_tile == WorldData.INVALID_CITY_TILE_POSITION:
		_set_work_task_blocked(citizen_id)
		return path_requests_remaining

	if new_target_tile == current_tile:
		if not _begin_work_activity_dwell(
			_make_work_activity_dwell_values(context, {
				"relocation_count": relocation_count + 1,
			})
		):
			_set_work_task_blocked(citizen_id)
		return path_requests_remaining

	path_requests_remaining -= 1
	var relocation_path_result := (
		CityNavigationSystemScript.find_path_to_any_city_tile({
			"city_world": city_world,
			"start_tile": current_tile,
			"destination_tiles": [new_target_tile],
			"max_expanded_nodes": CityNavigationSystemScript.get_city_wide_path_expansion_limit(city_world),
			"citizen_id": citizen_id,
			"heuristic_weight": CityNavigationSystem.HEURISTIC_WEIGHT
		})
	)

	if not bool(relocation_path_result.get("success", false)):
		if not _begin_work_activity_dwell(
			_make_work_activity_dwell_values(context)
		):
			_set_work_task_blocked(citizen_id)
		return path_requests_remaining

	var raw_relocation_path = relocation_path_result.get("path", [])

	if not raw_relocation_path is Array:
		_set_work_task_blocked(citizen_id)
		return path_requests_remaining

	var relocation_path: Array = raw_relocation_path

	if relocation_path.size() <= 1:
		if not _begin_work_activity_dwell(
			_make_work_activity_dwell_values(context, {
				"relocation_count": relocation_count + 1,
			})
		):
			_set_work_task_blocked(citizen_id)
		return path_requests_remaining

	if not _set_work_task_activity_state({
		"citizen_id": citizen_id,
		"target_tile": new_target_tile,
		"previous_target_tile": departing_tile,
		"next_action_world_minute": (
			WorldData.INVALID_CITY_CITIZEN_TASK_ACTION_WORLD_MINUTE
		),
		"relocation_count": relocation_count + 1,
	}):
		_set_work_task_blocked(citizen_id)
		return path_requests_remaining

	if not CityCitizenMovementRuntimeSystem.assign_city_citizen_movement_order(
		citizen_id,
		relocation_path
	):
		_set_work_task_blocked(citizen_id)
		return path_requests_remaining

	CityCitizenTaskRuntimeSystem.set_city_citizen_task_phase(
		citizen_id,
		WorldData.CITY_CITIZEN_TASK_PHASE_TRAVELING
	)
	return path_requests_remaining


static func _advance_blocked_work_task(context: Dictionary) -> int:
	_retry_blocked_work_task_if_due(
		int(context.get("citizen_id", -1)),
		context.get("current_task", {}),
		int(context.get("relocation_count", 0))
	)
	return int(context.get("path_requests_remaining", 0))


#endregion

#region Return Home Task

static func _advance_return_home_task(
	city_world: WorldData,
	values: Dictionary
) -> int:
	var context := _make_return_home_task_context(city_world, values)
	var path_requests_remaining := maxi(
		int(values.get("path_requests_remaining", 0)),
		0
	)

	if context.is_empty():
		return path_requests_remaining

	if not _prepare_return_home_task_phase(context):
		return path_requests_remaining

	var citizen_id := int(context.get("citizen_id", -1))
	var current_tile: Vector2i = context.get(
		"current_tile",
		WorldData.INVALID_CITY_TILE_POSITION
	)
	var assigned_home_tile: Vector2i = context.get(
		"assigned_home_tile",
		WorldData.INVALID_CITY_TILE_POSITION
	)
	var movement_state := str(context.get("movement_state", ""))
	var task_phase := str(context.get("task_phase", ""))

	if (
		movement_state == WorldData.CITY_CITIZEN_MOVEMENT_STATE_MOVING
		and task_phase != WorldData.CITY_CITIZEN_TASK_PHASE_TRAVELING
	):
		CityCitizenMovementRuntimeSystem.cancel_city_citizen_movement(citizen_id)
		movement_state = WorldData.CITY_CITIZEN_MOVEMENT_STATE_IDLE
		context["movement_state"] = movement_state

	if (
		current_tile == assigned_home_tile
		and movement_state != WorldData.CITY_CITIZEN_MOVEMENT_STATE_MOVING
	):
		if not _complete_return_home_task(citizen_id):
			_set_return_home_task_blocked(citizen_id)
		return path_requests_remaining

	if (
		task_phase == WorldData.CITY_CITIZEN_TASK_PHASE_TRAVELING
		and movement_state == WorldData.CITY_CITIZEN_MOVEMENT_STATE_MOVING
	):
		return path_requests_remaining

	if movement_state == WorldData.CITY_CITIZEN_MOVEMENT_STATE_BLOCKED:
		_set_return_home_task_blocked(citizen_id)
		return path_requests_remaining

	return _start_return_home_path(context)


static func _make_return_home_task_context(
	city_world: WorldData,
	values: Dictionary
) -> Dictionary:
	var citizen_id := int(values.get("citizen_id", -1))
	var citizen: Dictionary = values.get("citizen", {})
	var current_task: Dictionary = values.get("current_task", {})
	var path_requests_remaining := maxi(
		int(values.get("path_requests_remaining", 0)),
		0
	)
	var home_id := int(current_task.get("target_object_id", -1))
	var home := CityObjectSystem.get_city_object_by_id(home_id)
	var resident_ids := CityAssignmentSystem.get_city_object_resident_ids(home)

	if (
		home_id <= 0
		or home.is_empty()
		or WorldData.get_city_object_resident_capacity(home) <= 0
		or not CityObjectSystem.city_object_supports_citizen_interior(home)
		or int(citizen.get("home_object_id", -1)) != home_id
		or not resident_ids.has(citizen_id)
		or not CityNavigationSystem.city_citizen_can_access_object_interior(
			citizen_id,
			home
		)
	):
		_clear_invalid_task(citizen_id)
		return {}

	var home_tiles := (
		CityActivityLocationResolverScript.get_object_interior_activity_tiles(
			city_world,
			home,
			citizen_id
		)
	)
	var raw_current_tile = citizen.get(
		"city_tile_position",
		WorldData.INVALID_CITY_TILE_POSITION
	)

	if not raw_current_tile is Vector2i or home_tiles.is_empty():
		_set_return_home_task_blocked(citizen_id)
		return {}

	resident_ids.sort()
	var resident_index := resident_ids.find(citizen_id)

	if resident_index < 0:
		_clear_invalid_task(citizen_id)
		return {}

	return {
		"city_world": city_world,
		"citizen_id": citizen_id,
		"current_task": current_task,
		"path_requests_remaining": path_requests_remaining,
		"current_tile": raw_current_tile,
		"assigned_home_tile": home_tiles[
			resident_index % home_tiles.size()
		],
		"task_phase": str(
			current_task.get(
				"phase",
				WorldData.CITY_CITIZEN_TASK_PHASE_NONE
			)
		),
		"movement_state": str(
			citizen.get(
				"movement_state",
				WorldData.CITY_CITIZEN_MOVEMENT_STATE_IDLE
			)
		),
	}


static func _prepare_return_home_task_phase(
	context: Dictionary
) -> bool:
	var citizen_id := int(context.get("citizen_id", -1))
	var current_task: Dictionary = context.get("current_task", {})
	var task_phase := str(context.get("task_phase", ""))

	if task_phase == WorldData.CITY_CITIZEN_TASK_PHASE_BLOCKED:
		var retry_world_minute := int(
			current_task.get(
				"next_action_world_minute",
				WorldData.INVALID_CITY_CITIZEN_TASK_ACTION_WORLD_MINUTE
			)
		)

		if (
			retry_world_minute
			== WorldData.INVALID_CITY_CITIZEN_TASK_ACTION_WORLD_MINUTE
		):
			_set_return_home_task_blocked(citizen_id)
			return false

		if SimulationClock.absolute_world_minutes < retry_world_minute:
			return false

		CityCitizenMovementRuntimeSystem.cancel_city_citizen_movement(citizen_id)

		if not CityCitizenTaskRuntimeSystem.set_city_citizen_task_activity_state({
			"citizen_id": citizen_id,
			"target_tile": WorldData.INVALID_CITY_TILE_POSITION,
			"previous_target_tile": WorldData.INVALID_CITY_TILE_POSITION,
			"next_action_world_minute": (
				WorldData.INVALID_CITY_CITIZEN_TASK_ACTION_WORLD_MINUTE
			),
			"relocation_count": 0,
		}):
			_set_return_home_task_blocked(citizen_id)
			return false

		if not CityCitizenTaskRuntimeSystem.set_city_citizen_task_phase(
			citizen_id,
			WorldData.CITY_CITIZEN_TASK_PHASE_PENDING
		):
			_set_return_home_task_blocked(citizen_id)
			return false

		context["task_phase"] = WorldData.CITY_CITIZEN_TASK_PHASE_PENDING
		context["movement_state"] = (
			WorldData.CITY_CITIZEN_MOVEMENT_STATE_IDLE
		)
		return true

	if (
		task_phase != WorldData.CITY_CITIZEN_TASK_PHASE_PENDING
		and task_phase != WorldData.CITY_CITIZEN_TASK_PHASE_TRAVELING
		and task_phase != WorldData.CITY_CITIZEN_TASK_PHASE_PERFORMING
	):
		_set_return_home_task_blocked(citizen_id)
		return false

	return true


static func _start_return_home_path(context: Dictionary) -> int:
	var path_requests_remaining := int(
		context.get("path_requests_remaining", 0)
	)

	if path_requests_remaining <= 0:
		return path_requests_remaining

	var city_world: WorldData = context.get("city_world")
	var citizen_id := int(context.get("citizen_id", -1))
	var current_tile: Vector2i = context.get(
		"current_tile",
		WorldData.INVALID_CITY_TILE_POSITION
	)
	var assigned_home_tile: Vector2i = context.get(
		"assigned_home_tile",
		WorldData.INVALID_CITY_TILE_POSITION
	)
	path_requests_remaining -= 1
	var path_result := CityNavigationSystemScript.find_path_to_any_city_tile({
		"city_world": city_world,
		"start_tile": current_tile,
		"destination_tiles": [assigned_home_tile],
		"max_expanded_nodes": CityNavigationSystemScript.get_city_wide_path_expansion_limit(city_world),
		"citizen_id": citizen_id,
		"heuristic_weight": CityNavigationSystem.HEURISTIC_WEIGHT,
	})
	if not bool(path_result.get("success", false)):
		_set_return_home_task_blocked(citizen_id)
		return path_requests_remaining

	var raw_path = path_result.get("path", [])
	var raw_destination_tile = path_result.get(
		"destination_tile",
		WorldData.INVALID_CITY_TILE_POSITION
	)

	if (
		not raw_path is Array
		or not raw_destination_tile is Vector2i
		or raw_destination_tile != assigned_home_tile
	):
		_set_return_home_task_blocked(citizen_id)
		return path_requests_remaining

	var movement_path: Array = raw_path

	if not CityCitizenTaskRuntimeSystem.set_city_citizen_task_activity_state({
		"citizen_id": citizen_id,
		"target_tile": assigned_home_tile,
	}):
		_set_return_home_task_blocked(citizen_id)
		return path_requests_remaining

	if movement_path.size() <= 1:
		if not _complete_return_home_task(citizen_id):
			_set_return_home_task_blocked(citizen_id)
		return path_requests_remaining

	if not CityCitizenMovementRuntimeSystem.assign_city_citizen_movement_order(
		citizen_id,
		movement_path
	):
		_set_return_home_task_blocked(citizen_id)
		return path_requests_remaining

	CityCitizenTaskRuntimeSystem.set_city_citizen_task_phase(
		citizen_id,
		WorldData.CITY_CITIZEN_TASK_PHASE_TRAVELING
	)
	return path_requests_remaining


static func _complete_return_home_task(
	citizen_id: int
) -> bool:
	var current_task := (
		CityCitizenTaskRuntimeSystem.get_city_citizen_current_task(citizen_id)
	)
	var task_source := str(
		current_task.get(
			"source",
			WorldData.CITY_CITIZEN_TASK_SOURCE_NONE
		)
	)

	if task_source == WorldData.CITY_CITIZEN_TASK_SOURCE_NONE:
		return false

	CityCitizenMovementRuntimeSystem.cancel_city_citizen_movement(citizen_id)

	return CityCitizenTaskRuntimeSystem.clear_city_citizen_task(
		citizen_id,
		task_source
	)


static func _set_return_home_task_blocked(
	citizen_id: int
) -> void:
	var current_task := (
		CityCitizenTaskRuntimeSystem.get_city_citizen_current_task(citizen_id)
	)
	var target_tile = current_task.get(
		"target_tile",
		WorldData.INVALID_CITY_TILE_POSITION
	)

	if not target_tile is Vector2i:
		target_tile = WorldData.INVALID_CITY_TILE_POSITION

	CityCitizenMovementRuntimeSystem.cancel_city_citizen_movement(citizen_id)
	CityCitizenTaskRuntimeSystem.set_city_citizen_task_activity_state({
		"citizen_id": citizen_id,
		"target_tile": target_tile,
		"previous_target_tile": (
			WorldData.INVALID_CITY_TILE_POSITION
		),
		"next_action_world_minute": (
			SimulationClock.absolute_world_minutes
			+ BLOCKED_RETURN_HOME_TASK_RETRY_DELAY_MINUTES
		),
		"relocation_count": 0,
	})
	CityCitizenTaskRuntimeSystem.set_city_citizen_task_phase(
		citizen_id,
		WorldData.CITY_CITIZEN_TASK_PHASE_BLOCKED
	)


#endregion

#region Work Activity Placement and Dwell

static func _build_work_activity_claim_counts(
	active_task_ids: Array[int]
) -> Dictionary:
	var claim_counts: Dictionary = {}

	for citizen_id in active_task_ids:
		var citizen := CityCitizenRegistrySystem.get_city_citizen_by_id(
			citizen_id
		)

		if (
			citizen.is_empty()
			or not bool(citizen.get("alive", false))
		):
			continue

		var current_task := (
			CityCitizenTaskRuntimeSystem.get_city_citizen_current_task(
				citizen_id
			)
		)

		if (
			str(current_task.get("kind", ""))
			!= WorldData.CITY_CITIZEN_TASK_KIND_WORK
		):
			continue

		var task_phase := str(
			current_task.get(
				"phase",
				WorldData.CITY_CITIZEN_TASK_PHASE_NONE
			)
		)

		if (
			task_phase != WorldData.CITY_CITIZEN_TASK_PHASE_PENDING
			and task_phase != WorldData.CITY_CITIZEN_TASK_PHASE_TRAVELING
			and task_phase != WorldData.CITY_CITIZEN_TASK_PHASE_PERFORMING
		):
			continue

		var raw_target_tile = current_task.get(
			"target_tile",
			WorldData.INVALID_CITY_TILE_POSITION
		)

		if not raw_target_tile is Vector2i:
			continue

		var target_tile: Vector2i = raw_target_tile

		if target_tile == WorldData.INVALID_CITY_TILE_POSITION:
			continue

		claim_counts[target_tile] = (
			int(claim_counts.get(target_tile, 0))
			+ 1
		)

	return claim_counts


static func _get_preferred_work_activity_tiles(
	activity_tiles: Array[Vector2i],
	citizen_id: int
) -> Array[Vector2i]:
	var unclaimed_tiles: Array[Vector2i] = []
	var current_task := (
		CityCitizenTaskRuntimeSystem.get_city_citizen_current_task(
			citizen_id
		)
	)
	var own_target_tile = current_task.get(
		"target_tile",
		WorldData.INVALID_CITY_TILE_POSITION
	)

	for candidate_tile in activity_tiles:
		var other_claim_count := int(
			_work_activity_claim_counts.get(
				candidate_tile,
				0
			)
		)

		if (
			own_target_tile is Vector2i
			and candidate_tile == own_target_tile
		):
			other_claim_count = maxi(
				other_claim_count - 1,
				0
			)

		if other_claim_count <= 0:
			unclaimed_tiles.append(candidate_tile)

	if not unclaimed_tiles.is_empty():
		return unclaimed_tiles

	return activity_tiles.duplicate()


static func _set_work_task_activity_state(
	values: Dictionary
) -> bool:
	if not values.has("citizen_id") or not values.has("target_tile"):
		push_error(
			"Work task activity state requires citizen_id and target_tile."
		)
		return false

	var raw_target_tile = values["target_tile"]
	var raw_previous_target_tile = values.get(
		"previous_target_tile",
		WorldData.INVALID_CITY_TILE_POSITION
	)

	if not raw_target_tile is Vector2i:
		push_error("Work task activity target_tile must be Vector2i.")
		return false

	if not raw_previous_target_tile is Vector2i:
		push_error(
			"Work task activity previous_target_tile must be Vector2i."
		)
		return false

	var citizen_id := int(values["citizen_id"])
	var target_tile: Vector2i = raw_target_tile
	var previous_target_tile: Vector2i = raw_previous_target_tile
	var next_action_world_minute := int(
		values.get(
			"next_action_world_minute",
			WorldData
			.INVALID_CITY_CITIZEN_TASK_ACTION_WORLD_MINUTE
		)
	)
	var relocation_count := int(
		values.get("relocation_count", -1)
	)
	var current_task := (
		CityCitizenTaskRuntimeSystem.get_city_citizen_current_task(
			citizen_id
		)
	)
	var raw_old_target_tile = current_task.get(
		"target_tile",
		WorldData.INVALID_CITY_TILE_POSITION
	)
	var old_target_tile := WorldData.INVALID_CITY_TILE_POSITION

	if raw_old_target_tile is Vector2i:
		old_target_tile = raw_old_target_tile

	if not CityCitizenTaskRuntimeSystem.set_city_citizen_task_activity_state({
		"citizen_id": citizen_id,
		"target_tile": target_tile,
		"previous_target_tile": previous_target_tile,
		"next_action_world_minute": next_action_world_minute,
		"relocation_count": relocation_count,
	}):
		return false

	_replace_work_activity_claim(
		old_target_tile,
		target_tile
	)
	return true


static func _replace_work_activity_claim(
	old_target_tile: Vector2i,
	new_target_tile: Vector2i
) -> void:
	if old_target_tile == new_target_tile:
		return

	if old_target_tile != WorldData.INVALID_CITY_TILE_POSITION:
		var old_claim_count := int(
			_work_activity_claim_counts.get(
				old_target_tile,
				0
			)
		)

		if old_claim_count <= 1:
			_work_activity_claim_counts.erase(
				old_target_tile
			)
		else:
			_work_activity_claim_counts[old_target_tile] = (
				old_claim_count - 1
			)

	if new_target_tile != WorldData.INVALID_CITY_TILE_POSITION:
		_work_activity_claim_counts[new_target_tile] = (
			int(
				_work_activity_claim_counts.get(
					new_target_tile,
					0
				)
			)
			+ 1
		)

static func _get_deterministic_dwell_minutes(
	values: Dictionary
) -> int:
	var citizen_id := int(values["citizen_id"])
	var workplace_id := int(values["workplace_id"])
	var choice_sequence := int(values["choice_sequence"])
	var minimum_minutes := int(values["dwell_min_minutes"])
	var maximum_minutes := int(values["dwell_max_minutes"])

	if maximum_minutes <= minimum_minutes:
		return minimum_minutes

	var range_size := maximum_minutes - minimum_minutes + 1
	var deterministic_value := citizen_id * 73_856_093
	deterministic_value ^= workplace_id * 19_349_663
	deterministic_value ^= choice_sequence * 83_492_791
	deterministic_value &= 0x7fffffff

	return (
		minimum_minutes
		+ posmod(deterministic_value, range_size)
	)


static func _begin_work_activity_dwell(
	values: Dictionary
) -> bool:
	if not _has_valid_work_activity_dwell_values(values):
		return false

	var citizen_id := int(values["citizen_id"])
	var target_tile: Vector2i = values["target_tile"]
	var previous_target_tile: Vector2i = (
		values["previous_target_tile"]
	)
	var relocation_count := int(values["relocation_count"])
	var maximum_relocations_per_task := int(
		values["maximum_relocations_per_task"]
	)
	var next_action_world_minute := (
		WorldData.INVALID_CITY_CITIZEN_TASK_ACTION_WORLD_MINUTE
	)

	if relocation_count < maximum_relocations_per_task:
		var dwell_minutes := _get_deterministic_dwell_minutes(
			values
		)
		next_action_world_minute = (
			SimulationClock.absolute_world_minutes
			+ dwell_minutes
		)

	if not _set_work_task_activity_state({
		"citizen_id": citizen_id,
		"target_tile": target_tile,
		"previous_target_tile": previous_target_tile,
		"next_action_world_minute": next_action_world_minute,
		"relocation_count": relocation_count,
	}):
		return false

	return CityCitizenTaskRuntimeSystem.set_city_citizen_task_phase(
		citizen_id,
		WorldData.CITY_CITIZEN_TASK_PHASE_PERFORMING
	)


static func _has_valid_work_activity_dwell_values(
	values: Dictionary
) -> bool:
	for raw_key in WORK_ACTIVITY_DWELL_REQUIRED_KEYS:
		var key := str(raw_key)

		if not values.has(key):
			push_error(
				"Work activity dwell request is missing key: "
				+ key
			)
			return false

	if not values["target_tile"] is Vector2i:
		push_error(
			"Work activity dwell target_tile must be Vector2i."
		)
		return false

	if not values["previous_target_tile"] is Vector2i:
		push_error(
			"Work activity dwell previous_target_tile must be Vector2i."
		)
		return false

	return true

#endregion

#region Blocked Task Recovery and Cleanup

static func _retry_blocked_work_task_if_due(
	citizen_id: int,
	current_task: Dictionary,
	relocation_count: int
) -> void:
	var retry_world_minute := int(
		current_task.get(
			"next_action_world_minute",
			WorldData.INVALID_CITY_CITIZEN_TASK_ACTION_WORLD_MINUTE
		)
	)

	if (
		retry_world_minute
		== WorldData.INVALID_CITY_CITIZEN_TASK_ACTION_WORLD_MINUTE
	):
		_set_work_task_blocked(citizen_id)
		return

	if SimulationClock.absolute_world_minutes < retry_world_minute:
		return

	CityCitizenMovementRuntimeSystem.cancel_city_citizen_movement(citizen_id)

	if not _set_work_task_activity_state({
		"citizen_id": citizen_id,
		"target_tile": WorldData.INVALID_CITY_TILE_POSITION,
		"previous_target_tile": (
			WorldData.INVALID_CITY_TILE_POSITION
		),
		"next_action_world_minute": (
			WorldData.INVALID_CITY_CITIZEN_TASK_ACTION_WORLD_MINUTE
		),
		"relocation_count": relocation_count,
	}):
		_set_work_task_blocked(citizen_id)
		return

	if not CityCitizenTaskRuntimeSystem.set_city_citizen_task_phase(
		citizen_id,
		WorldData.CITY_CITIZEN_TASK_PHASE_PENDING
	):
		_set_work_task_blocked(citizen_id)


static func _set_work_task_blocked(citizen_id: int) -> void:
	var current_task := (
		CityCitizenTaskRuntimeSystem.get_city_citizen_current_task(
			citizen_id
		)
	)
	var target_tile := WorldData.INVALID_CITY_TILE_POSITION
	var previous_target_tile := (
		WorldData.INVALID_CITY_TILE_POSITION
	)
	var raw_target_tile = current_task.get(
		"target_tile",
		WorldData.INVALID_CITY_TILE_POSITION
	)
	var raw_previous_target_tile = current_task.get(
		"previous_target_tile",
		WorldData.INVALID_CITY_TILE_POSITION
	)

	if raw_target_tile is Vector2i:
		target_tile = raw_target_tile

	if raw_previous_target_tile is Vector2i:
		previous_target_tile = raw_previous_target_tile

	var relocation_count := maxi(
		int(current_task.get("relocation_count", 0)),
		0
	)
	var retry_world_minute := (
		SimulationClock.absolute_world_minutes
		+ BLOCKED_WORK_TASK_RETRY_DELAY_MINUTES
	)

	CityCitizenMovementRuntimeSystem.cancel_city_citizen_movement(citizen_id)
	_set_work_task_activity_state({
		"citizen_id": citizen_id,
		"target_tile": target_tile,
		"previous_target_tile": previous_target_tile,
		"next_action_world_minute": retry_world_minute,
		"relocation_count": relocation_count,
	})
	CityCitizenTaskRuntimeSystem.set_city_citizen_task_phase(
		citizen_id,
		WorldData.CITY_CITIZEN_TASK_PHASE_BLOCKED
	)

static func _clear_invalid_task(citizen_id: int) -> void:
	CityCitizenTaskRuntimeSystem.clear_city_citizen_task(
		citizen_id,
		WorldData.CITY_CITIZEN_TASK_SOURCE_PLAYER
	)
	CityCitizenMovementRuntimeSystem.cancel_city_citizen_movement(citizen_id)



#endregion
