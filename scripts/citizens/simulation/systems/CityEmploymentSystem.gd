extends RefCounted
class_name CityEmploymentSystem

# Durable workplace staffing policy, attendance queries, and vacancy
# reconciliation. CityAssignmentSystem owns atomic job relationship mutation;
# CityWorkplaceState owns only settlement-local workplace invalidation.

const STAFFING_MODE_AUTOMATIC := "automatic"
const STAFFING_MODE_MANUAL := "manual"
const WORKPLACE_STAFFING_MODE_FIELD := "staffing_mode"
const WORKPLACE_DESIRED_WORKER_COUNT_FIELD := "desired_worker_count"
const MAX_AUTOMATIC_ASSIGNMENTS_PER_TICK: int = 32


static func get_current_state() -> CityWorkplaceState:
	return WorldPoliticalState.get_current_city_workplace_state()


static func get_city_workplace_version() -> int:
	return get_current_state().workplace_version


static func get_city_workplace_version_for_city_state(
	city_state: CitySettlementSimulationState
) -> int:
	return city_state.workplace_state.workplace_version


static func mark_city_workplaces_changed() -> void:
	get_current_state().workplace_version += 1


static func mark_city_workplaces_changed_for_city_state(
	city_state: CitySettlementSimulationState
) -> void:
	city_state.workplace_state.workplace_version += 1


static func reset_city_workplace_state() -> void:
	# Workplace records remain on CityObjectState. Publish a focused observer
	# invalidation rather than duplicating or clearing those records here.
	mark_city_workplaces_changed()


static func reset_city_workplace_state_for_city_state(
	city_state: CitySettlementSimulationState
) -> void:
	mark_city_workplaces_changed_for_city_state(city_state)


static func _get_city_objects(
	city_state: CitySettlementSimulationState
) -> Array:
	if city_state == null:
		return CityObjectSystem.get_city_objects()
	return CityObjectSystem.get_city_objects_for_city_state(city_state)


static func _get_city_object_by_id(
	city_state: CitySettlementSimulationState,
	object_id: int
) -> Dictionary:
	if city_state == null:
		return CityObjectSystem.get_city_object_by_id(object_id)
	return CityObjectSystem.get_city_object_by_id_for_city_state(
		city_state,
		object_id
	)


static func _get_city_citizen_by_id(
	city_state: CitySettlementSimulationState,
	citizen_id: int
) -> Dictionary:
	if city_state == null:
		return CityCitizenRegistrySystem.get_city_citizen_by_id(citizen_id)
	return CityCitizenRegistrySystem.get_city_citizen_by_id_for_city_state(
		city_state,
		citizen_id
	)


static func _mark_workplaces_changed(
	city_state: CitySettlementSimulationState
) -> void:
	if city_state == null:
		mark_city_workplaces_changed()
	else:
		mark_city_workplaces_changed_for_city_state(city_state)


static func run_tick(
	_tick_index: int,
	minutes_advanced: int
) -> void:
	_run_tick(null, _tick_index, minutes_advanced)


static func run_tick_for_city_state(
	city_state: CitySettlementSimulationState,
	_tick_index: int,
	minutes_advanced: int
) -> void:
	_run_tick(city_state, _tick_index, minutes_advanced)


static func _run_tick(
	city_state: CitySettlementSimulationState,
	_tick_index: int,
	minutes_advanced: int
) -> void:
	var city_world = (
		WorldPoliticalState.get_current_city_world()
		if city_state == null
		else city_state.city_world
	)
	if minutes_advanced <= 0 or city_world == null:
		return

	if city_state == null:
		CityAssignmentSystem.ensure_city_citizen_assignment_state()
		ensure_workplace_staffing_state()
		CityAssignmentSystem.assign_homeless_citizens_to_available_housing()
		reconcile_automatic_workplaces()
	else:
		CityAssignmentSystem.ensure_city_citizen_assignment_state_for_city_state(
			city_state
		)
		ensure_workplace_staffing_state_for_city_state(city_state)
		CityAssignmentSystem.assign_homeless_citizens_to_available_housing_for_city_state(
			city_state
		)
		reconcile_automatic_workplaces_for_city_state(city_state)


static func is_valid_staffing_mode(staffing_mode: String) -> bool:
	# Pass 6 keeps staffing policy automatic-only. The manual constant remains
	# as a compatibility vocabulary value so old saves can be normalized, but
	# it is no longer an accepted runtime policy.
	return staffing_mode == STAFFING_MODE_AUTOMATIC


static func ensure_workplace_staffing_state() -> int:
	return _ensure_workplace_staffing_state(null)


static func ensure_workplace_staffing_state_for_city_state(
	city_state: CitySettlementSimulationState
) -> int:
	return _ensure_workplace_staffing_state(city_state)


static func _ensure_workplace_staffing_state(
	city_state: CitySettlementSimulationState
) -> int:
	var normalized_count := 0
	var city_objects := _get_city_objects(city_state)

	for object_index in range(city_objects.size()):
		var raw_city_object = city_objects[object_index]

		if not raw_city_object is Dictionary:
			continue

		var city_object: Dictionary = raw_city_object

		if not CityObjectCatalog.city_object_is_workplace(city_object):
			continue

		var normalized := city_object.duplicate(false)
		var worker_capacity := maxi(
			CityObjectCatalog.get_city_object_worker_capacity(city_object),
			0
		)

		# Automatic staffing always targets the current hard capacity. This also
		# migrates legacy manual/partial targets and allows 4 -> 2 -> 4 capacity
		# changes to recover all four vacancies instead of preserving a lossy 2.
		normalized[WORKPLACE_STAFFING_MODE_FIELD] = STAFFING_MODE_AUTOMATIC
		normalized[WORKPLACE_DESIRED_WORKER_COUNT_FIELD] = worker_capacity

		if normalized == city_object:
			continue

		var wrote_object := (
			CityObjectSystem.patch_city_object_workplace_fields(
				int(city_object.get("id", -1)),
				{
					WORKPLACE_STAFFING_MODE_FIELD: (
						normalized[WORKPLACE_STAFFING_MODE_FIELD]
					),
					WORKPLACE_DESIRED_WORKER_COUNT_FIELD: (
						normalized[WORKPLACE_DESIRED_WORKER_COUNT_FIELD]
					),
				}
			)
			if city_state == null
			else CityObjectSystem.patch_city_object_workplace_fields_for_city_state(
				city_state,
				int(city_object.get("id", -1)),
				{
					WORKPLACE_STAFFING_MODE_FIELD: (
						normalized[WORKPLACE_STAFFING_MODE_FIELD]
					),
					WORKPLACE_DESIRED_WORKER_COUNT_FIELD: (
						normalized[WORKPLACE_DESIRED_WORKER_COUNT_FIELD]
					),
				}
			)
		)
		if not wrote_object:
			continue

		normalized_count += 1

	if normalized_count > 0:
		_mark_workplaces_changed(city_state)

	return normalized_count


static func get_workplace_staffing_mode(workplace: Dictionary) -> String:
	if workplace.is_empty() or not CityObjectCatalog.city_object_is_workplace(workplace):
		return ""

	return STAFFING_MODE_AUTOMATIC


static func get_workplace_desired_worker_count(workplace: Dictionary) -> int:
	if workplace.is_empty() or not CityObjectCatalog.city_object_is_workplace(workplace):
		return 0

	var worker_capacity := maxi(
		CityObjectCatalog.get_city_object_worker_capacity(workplace),
		0
	)
	return worker_capacity


static func set_city_workplace_worker_capacity(
	workplace_id: int,
	worker_capacity: int
) -> bool:
	return _set_city_workplace_worker_capacity(
		null,
		workplace_id,
		worker_capacity
	)


static func set_city_workplace_worker_capacity_for_city_state(
	city_state: CitySettlementSimulationState,
	workplace_id: int,
	worker_capacity: int
) -> bool:
	return _set_city_workplace_worker_capacity(
		city_state,
		workplace_id,
		worker_capacity
	)


static func _set_city_workplace_worker_capacity(
	city_state: CitySettlementSimulationState,
	workplace_id: int,
	worker_capacity: int
) -> bool:
	if workplace_id <= 0 or worker_capacity < 0:
		return false

	var workplace := _get_city_object_by_id(city_state, workplace_id)

	if (
		workplace.is_empty()
		or not CityObjectCatalog.city_object_is_workplace(workplace)
	):
		return false

	if int(workplace.get("worker_capacity", 0)) == worker_capacity:
		return true

	var changed := (
		CityObjectSystem.patch_city_object_workplace_fields(
			workplace_id,
			{"worker_capacity": worker_capacity}
		)
		if city_state == null
		else CityObjectSystem.patch_city_object_workplace_fields_for_city_state(
			city_state,
			workplace_id,
			{"worker_capacity": worker_capacity}
		)
	)

	if not changed:
		return false

	_mark_workplaces_changed(city_state)
	return true


static func set_workplace_staffing_mode(
	workplace_id: int,
	staffing_mode: String
) -> bool:
	return _set_workplace_staffing_mode(null, workplace_id, staffing_mode)


static func set_workplace_staffing_mode_for_city_state(
	city_state: CitySettlementSimulationState,
	workplace_id: int,
	staffing_mode: String
) -> bool:
	return _set_workplace_staffing_mode(
		city_state,
		workplace_id,
		staffing_mode
	)


static func _set_workplace_staffing_mode(
	city_state: CitySettlementSimulationState,
	workplace_id: int,
	staffing_mode: String
) -> bool:
	# Manual requests are rejected before any lookup or mutation. Automatic
	# requests double as an explicit legacy-policy normalization boundary.
	if (
		workplace_id <= 0
		or staffing_mode != STAFFING_MODE_AUTOMATIC
	):
		return false

	var object_index := (
		CityObjectSystem.get_city_object_index_by_id(workplace_id)
		if city_state == null
		else CityObjectSystem.get_city_object_index_by_id_for_city_state(
			city_state,
			workplace_id
		)
	)

	if object_index < 0:
		return false

	var raw_workplace = _get_city_objects(city_state)[object_index]

	if not raw_workplace is Dictionary:
		return false

	var workplace: Dictionary = raw_workplace

	if not CityObjectCatalog.city_object_is_workplace(workplace):
		return false

	var updated_workplace: Dictionary = workplace.duplicate(false)
	updated_workplace[WORKPLACE_STAFFING_MODE_FIELD] = STAFFING_MODE_AUTOMATIC
	updated_workplace[WORKPLACE_DESIRED_WORKER_COUNT_FIELD] = maxi(
		CityObjectCatalog.get_city_object_worker_capacity(workplace),
		0
	)

	if updated_workplace == workplace:
		return true

	var workplace_fields := {
		WORKPLACE_STAFFING_MODE_FIELD: (
			updated_workplace[WORKPLACE_STAFFING_MODE_FIELD]
		),
		WORKPLACE_DESIRED_WORKER_COUNT_FIELD: (
			updated_workplace[WORKPLACE_DESIRED_WORKER_COUNT_FIELD]
		),
	}
	var wrote_workplace := (
		CityObjectSystem.patch_city_object_workplace_fields(
			workplace_id,
			workplace_fields
		)
		if city_state == null
		else CityObjectSystem.patch_city_object_workplace_fields_for_city_state(
			city_state,
			workplace_id,
			workplace_fields
		)
	)
	if not wrote_workplace:
		return false

	_mark_workplaces_changed(city_state)
	return true


static func set_workplace_desired_worker_count(
	workplace_id: int,
	desired_worker_count: int
) -> bool:
	return _set_workplace_desired_worker_count(
		null,
		workplace_id,
		desired_worker_count
	)


static func set_workplace_desired_worker_count_for_city_state(
	city_state: CitySettlementSimulationState,
	workplace_id: int,
	desired_worker_count: int
) -> bool:
	return _set_workplace_desired_worker_count(
		city_state,
		workplace_id,
		desired_worker_count
	)


static func _set_workplace_desired_worker_count(
	city_state: CitySettlementSimulationState,
	workplace_id: int,
	desired_worker_count: int
) -> bool:
	var object_index := (
		CityObjectSystem.get_city_object_index_by_id(workplace_id)
		if city_state == null
		else CityObjectSystem.get_city_object_index_by_id_for_city_state(
			city_state,
			workplace_id
		)
	)

	if object_index < 0:
		return false

	var raw_workplace = _get_city_objects(city_state)[object_index]

	if not raw_workplace is Dictionary:
		return false

	var workplace: Dictionary = raw_workplace

	if not CityObjectCatalog.city_object_is_workplace(workplace):
		return false

	var worker_capacity := maxi(
		CityObjectCatalog.get_city_object_worker_capacity(workplace),
		0
	)

	# Partial staffing is not a current gameplay policy. Preserve the old API as
	# a compatibility boundary, accepting only the automatic full-capacity value.
	if desired_worker_count != worker_capacity:
		return false

	return _set_workplace_staffing_mode(
		city_state,
		workplace_id,
		STAFFING_MODE_AUTOMATIC
	)


# This compatibility boundary follows the current automatic-only gameplay
# policy. A future manual-assignment design needs its own transactional API.
static func assign_citizen_to_workplace(
	citizen_id: int,
	workplace_id: int,
	manual_assignment: bool = false
) -> bool:
	if manual_assignment:
		return false

	return CityAssignmentSystem.assign_city_citizen_job(
		citizen_id,
		workplace_id
	)


static func assign_citizen_to_workplace_for_city_state(
	city_state: CitySettlementSimulationState,
	citizen_id: int,
	workplace_id: int,
	manual_assignment: bool = false
) -> bool:
	if manual_assignment:
		return false
	return CityAssignmentSystem.assign_city_citizen_job_for_city_state(
		city_state,
		citizen_id,
		workplace_id
	)


static func remove_citizen_job(citizen_id: int) -> bool:
	return CityAssignmentSystem.remove_city_citizen_job(citizen_id)


static func remove_citizen_job_for_city_state(
	city_state: CitySettlementSimulationState,
	citizen_id: int
) -> bool:
	return CityAssignmentSystem.remove_city_citizen_job_for_city_state(
		city_state,
		citizen_id
	)


static func get_city_unemployed_citizen_count() -> int:
	return CityAssignmentSystem.get_city_unemployed_citizen_count()


static func get_city_unemployed_citizen_count_for_city_state(
	city_state: CitySettlementSimulationState
) -> int:
	return CityAssignmentSystem.get_city_unemployed_citizen_count_for_city_state(
		city_state
	)


static func get_city_object_worker_ids(city_object: Dictionary) -> Array:
	return CityAssignmentSystem.get_city_object_worker_ids(city_object)


static func get_city_object_worker_ids_for_city_state(
	city_state: CitySettlementSimulationState,
	city_object: Dictionary
) -> Array:
	return CityAssignmentSystem.get_city_object_worker_ids_for_city_state(
		city_state,
		city_object
	)


static func get_city_object_worker_count(city_object: Dictionary) -> int:
	return CityAssignmentSystem.get_city_object_worker_count(city_object)


static func get_city_object_worker_count_for_city_state(
	city_state: CitySettlementSimulationState,
	city_object: Dictionary
) -> int:
	return CityAssignmentSystem.get_city_object_worker_count_for_city_state(
		city_state,
		city_object
	)


static func get_city_object_worker_names(city_object: Dictionary) -> Array:
	return CityAssignmentSystem.get_city_object_worker_names(city_object)


static func is_city_citizen_attending_workplace(
	citizen_id: int,
	workplace_id: int,
	source_world = null
) -> bool:
	return _is_city_citizen_attending_workplace(
		null,
		citizen_id,
		workplace_id,
		source_world
	)


static func is_city_citizen_attending_workplace_for_city_state(
	city_state: CitySettlementSimulationState,
	citizen_id: int,
	workplace_id: int,
	source_world = null
) -> bool:
	return _is_city_citizen_attending_workplace(
		city_state,
		citizen_id,
		workplace_id,
		source_world
	)


static func _is_city_citizen_attending_workplace(
	city_state: CitySettlementSimulationState,
	citizen_id: int,
	workplace_id: int,
	source_world
) -> bool:
	if citizen_id <= 0 or workplace_id <= 0:
		return false

	var workplace := _get_city_object_by_id(city_state, workplace_id)

	if workplace.is_empty() or not CityObjectCatalog.city_object_is_workplace(workplace):
		return false

	var city_world: WorldData = source_world

	if city_world == null:
		city_world = (
			WorldPoliticalState.get_current_city_world()
			if city_state == null
			else city_state.city_world
		)

	if city_world == null:
		return false

	var access_tiles := (
		CityNavigationSystem.get_city_object_access_tiles(city_world, workplace)
		if city_state == null
		else CityNavigationSystem.get_city_object_access_tiles_for_city_state(
			city_state,
			city_world,
			workplace
		)
	)
	return _city_citizen_matches_workplace_attendance(
		_get_city_citizen_by_id(city_state, citizen_id),
		workplace_id,
		access_tiles
	)


static func get_city_object_attending_worker_ids(
	city_object: Dictionary,
	source_world = null
) -> Array[int]:
	return _get_city_object_attending_worker_ids(
		null,
		city_object,
		source_world
	)


static func get_city_object_attending_worker_ids_for_city_state(
	city_state: CitySettlementSimulationState,
	city_object: Dictionary,
	source_world = null
) -> Array[int]:
	return _get_city_object_attending_worker_ids(
		city_state,
		city_object,
		source_world
	)


static func _get_city_object_attending_worker_ids(
	city_state: CitySettlementSimulationState,
	city_object: Dictionary,
	source_world
) -> Array[int]:
	var attending_worker_ids: Array[int] = []

	if (
		city_object.is_empty()
		or not CityObjectCatalog.city_object_is_workplace(city_object)
	):
		return attending_worker_ids

	var workplace_id := int(city_object.get("id", -1))
	var worker_capacity := CityObjectCatalog.get_city_object_worker_capacity(city_object)

	if workplace_id <= 0 or worker_capacity <= 0:
		return attending_worker_ids

	var city_world: WorldData = source_world

	if city_world == null:
		city_world = (
			WorldPoliticalState.get_current_city_world()
			if city_state == null
			else city_state.city_world
		)

	if city_world == null:
		return attending_worker_ids

	var access_tiles := (
		CityNavigationSystem.get_city_object_access_tiles(city_world, city_object)
		if city_state == null
		else CityNavigationSystem.get_city_object_access_tiles_for_city_state(
			city_state,
			city_world,
			city_object
		)
	)

	if access_tiles.is_empty():
		return attending_worker_ids

	var counted_worker_ids: Dictionary = {}

	var worker_ids := (
		get_city_object_worker_ids(city_object)
		if city_state == null
		else CityAssignmentSystem.get_city_object_worker_ids_for_city_state(
			city_state,
			city_object
		)
	)
	for raw_worker_id in worker_ids:
		var worker_id := int(raw_worker_id)

		if worker_id <= 0 or counted_worker_ids.has(worker_id):
			continue

		counted_worker_ids[worker_id] = true

		if not _city_citizen_matches_workplace_attendance(
			_get_city_citizen_by_id(city_state, worker_id),
			workplace_id,
			access_tiles
		):
			continue

		attending_worker_ids.append(worker_id)

	attending_worker_ids.sort()

	if attending_worker_ids.size() > worker_capacity:
		attending_worker_ids.resize(worker_capacity)

	return attending_worker_ids


static func get_city_object_attending_worker_count(
	city_object: Dictionary,
	source_world = null
) -> int:
	return _get_city_object_attending_worker_ids(
		null,
		city_object,
		source_world
	).size()


static func get_city_object_attending_worker_count_for_city_state(
	city_state: CitySettlementSimulationState,
	city_object: Dictionary,
	source_world = null
) -> int:
	return _get_city_object_attending_worker_ids(
		city_state,
		city_object,
		source_world
	).size()


static func reconcile_automatic_workplaces() -> int:
	return _reconcile_automatic_workplaces(null)


static func reconcile_automatic_workplaces_for_city_state(
	city_state: CitySettlementSimulationState
) -> int:
	return _reconcile_automatic_workplaces(city_state)


static func _reconcile_automatic_workplaces(
	city_state: CitySettlementSimulationState
) -> int:
	var workplace_ids: Array[int] = []

	for raw_city_object in _get_city_objects(city_state):
		if not raw_city_object is Dictionary:
			continue

		var city_object: Dictionary = raw_city_object

		if (
			CityObjectCatalog.city_object_is_workplace(city_object)
			and get_workplace_staffing_mode(city_object)
			== STAFFING_MODE_AUTOMATIC
		):
			var workplace_id := int(city_object.get("id", -1))
			if workplace_id > 0:
				workplace_ids.append(workplace_id)

	workplace_ids.sort()

	# Capacity changes are reconciled before vacancy candidates are captured so
	# newly released workers participate in the same deterministic automatic
	# staffing pass. Keep the lowest citizen IDs and release highest IDs first.
	for workplace_id in workplace_ids:
		var workplace := _get_city_object_by_id(city_state, workplace_id)

		if workplace.is_empty():
			continue

		var desired_worker_count := get_workplace_desired_worker_count(workplace)
		var worker_ids: Array = (
			CityAssignmentSystem.get_city_object_worker_ids(workplace)
			if city_state == null
			else CityAssignmentSystem.get_city_object_worker_ids_for_city_state(
				city_state,
				workplace
			)
		)
		worker_ids.sort()

		while worker_ids.size() > desired_worker_count:
			var worker_id := int(worker_ids.pop_back())
			var removed := (
				CityAssignmentSystem.remove_city_citizen_job(worker_id)
				if city_state == null
				else CityAssignmentSystem.remove_city_citizen_job_for_city_state(
					city_state,
					worker_id
				)
			)
			if not removed:
				break

	var candidate_ids := _get_unemployed_candidate_ids(city_state)
	var assigned_count := 0

	for workplace_id in workplace_ids:
		if assigned_count >= MAX_AUTOMATIC_ASSIGNMENTS_PER_TICK:
			break

		var workplace := _get_city_object_by_id(city_state, workplace_id)

		if workplace.is_empty():
			continue

		var desired_worker_count := get_workplace_desired_worker_count(workplace)

		while (
			(
				CityAssignmentSystem.get_city_object_worker_count(workplace)
				if city_state == null
				else CityAssignmentSystem.get_city_object_worker_count_for_city_state(
					city_state,
					workplace
				)
			) < desired_worker_count
			and assigned_count < MAX_AUTOMATIC_ASSIGNMENTS_PER_TICK
		):
			var filled_one_slot := false

			for citizen_id in candidate_ids:
				var citizen := _get_city_citizen_by_id(
					city_state,
					citizen_id
				)

				if (
					citizen.is_empty()
					or not bool(citizen.get("alive", false))
					or int(citizen.get("job_object_id", -1)) > 0
				):
					continue

				# A temporarily unavailable citizen never blocks later candidates.
				# The persistent vacancy is retried on following simulation ticks.
				var assigned := (
					CityAssignmentSystem.assign_city_citizen_job(
						citizen_id,
						workplace_id
					)
					if city_state == null
					else CityAssignmentSystem.assign_city_citizen_job_for_city_state(
						city_state,
						citizen_id,
						workplace_id
					)
				)
				if not assigned:
					continue

				assigned_count += 1
				filled_one_slot = true
				workplace = _get_city_object_by_id(city_state, workplace_id)
				break

			if not filled_one_slot:
				break

	return assigned_count


static func _get_unemployed_candidate_ids(
	city_state: CitySettlementSimulationState
) -> Array[int]:
	var candidate_ids: Array[int] = []

	var registry_state := (
		CityCitizenRegistrySystem.get_current_state()
		if city_state == null
		else city_state.citizen_registry_state
	)
	for raw_citizen in registry_state.citizens:
		if not raw_citizen is Dictionary:
			continue

		var citizen: Dictionary = raw_citizen
		var citizen_id := int(citizen.get("id", -1))

		if (
			citizen_id > 0
			and bool(citizen.get("alive", false))
			and int(citizen.get("job_object_id", -1)) <= 0
		):
			candidate_ids.append(citizen_id)

	candidate_ids.sort()
	return candidate_ids


static func _city_citizen_matches_workplace_attendance(
	citizen: Dictionary,
	workplace_id: int,
	access_tiles: Array
) -> bool:
	if citizen.is_empty() or not bool(citizen.get("alive", false)):
		return false
	if int(citizen.get("job_object_id", -1)) != workplace_id:
		return false

	var raw_current_task = citizen.get("current_task", {})

	if not raw_current_task is Dictionary:
		return false

	var current_task: Dictionary = raw_current_task

	if (
		str(current_task.get("kind", ""))
		!= CityCitizens.CITY_CITIZEN_TASK_KIND_WORK
		or str(current_task.get("phase", ""))
		!= CityCitizens.CITY_CITIZEN_TASK_PHASE_PERFORMING
		or int(current_task.get("target_object_id", -1))
		!= workplace_id
		or str(citizen.get("movement_state", ""))
		!= CityCitizens.CITY_CITIZEN_MOVEMENT_STATE_IDLE
	):
		return false

	var raw_tile_position = citizen.get(
		"city_tile_position",
		CityCitizens.INVALID_CITY_TILE_POSITION
	)

	if not raw_tile_position is Vector2i:
		return false

	var citizen_tile: Vector2i = raw_tile_position
	var raw_target_tile = current_task.get(
		"target_tile",
		CityCitizens.INVALID_CITY_TILE_POSITION
	)

	if raw_target_tile is Vector2i:
		var target_tile: Vector2i = raw_target_tile
		if target_tile != CityCitizens.INVALID_CITY_TILE_POSITION:
			return citizen_tile == target_tile

	return access_tiles.has(citizen_tile)
