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


static func mark_city_workplaces_changed() -> void:
	get_current_state().workplace_version += 1


static func reset_city_workplace_state() -> void:
	# Workplace records remain on CityObjectState. Publish a focused observer
	# invalidation rather than duplicating or clearing those records here.
	mark_city_workplaces_changed()


static func run_tick(
	_tick_index: int,
	minutes_advanced: int
) -> void:
	if minutes_advanced <= 0 or WorldData.official_city_world == null:
		return

	CityAssignmentSystem.ensure_city_citizen_assignment_state()
	ensure_workplace_staffing_state()
	CityAssignmentSystem.assign_homeless_citizens_to_available_housing()
	reconcile_automatic_workplaces()


static func is_valid_staffing_mode(staffing_mode: String) -> bool:
	return staffing_mode in [
		STAFFING_MODE_AUTOMATIC,
		STAFFING_MODE_MANUAL,
	]


static func ensure_workplace_staffing_state() -> int:
	var normalized_count := 0
	var city_objects := CityObjectSystem.get_city_objects()

	for object_index in range(city_objects.size()):
		var raw_city_object = city_objects[object_index]

		if not raw_city_object is Dictionary:
			continue

		var city_object: Dictionary = raw_city_object

		if not WorldData.city_object_is_workplace(city_object):
			continue

		var normalized := city_object.duplicate(false)
		var worker_capacity := maxi(
			WorldData.get_city_object_worker_capacity(city_object),
			0
		)
		var staffing_mode := str(
			normalized.get(
				WORKPLACE_STAFFING_MODE_FIELD,
				STAFFING_MODE_AUTOMATIC
			)
		)

		if not is_valid_staffing_mode(staffing_mode):
			staffing_mode = STAFFING_MODE_AUTOMATIC

		normalized[WORKPLACE_STAFFING_MODE_FIELD] = staffing_mode
		normalized[WORKPLACE_DESIRED_WORKER_COUNT_FIELD] = clampi(
			int(
				normalized.get(
					WORKPLACE_DESIRED_WORKER_COUNT_FIELD,
					worker_capacity
				)
			),
			0,
			worker_capacity
		)

		if normalized == city_object:
			continue

		if not CityObjectSystem.write_city_object_at_index(
			object_index,
			normalized
		):
			continue

		normalized_count += 1

	if normalized_count > 0:
		mark_city_workplaces_changed()

	return normalized_count


static func get_workplace_staffing_mode(workplace: Dictionary) -> String:
	if workplace.is_empty() or not WorldData.city_object_is_workplace(workplace):
		return ""

	var staffing_mode := str(
		workplace.get(
			WORKPLACE_STAFFING_MODE_FIELD,
			STAFFING_MODE_AUTOMATIC
		)
	)

	if not is_valid_staffing_mode(staffing_mode):
		return STAFFING_MODE_AUTOMATIC

	return staffing_mode


static func get_workplace_desired_worker_count(workplace: Dictionary) -> int:
	if workplace.is_empty() or not WorldData.city_object_is_workplace(workplace):
		return 0

	var worker_capacity := maxi(
		WorldData.get_city_object_worker_capacity(workplace),
		0
	)
	return clampi(
		int(
			workplace.get(
				WORKPLACE_DESIRED_WORKER_COUNT_FIELD,
				worker_capacity
			)
		),
		0,
		worker_capacity
	)


static func set_workplace_staffing_mode(
	workplace_id: int,
	staffing_mode: String
) -> bool:
	if workplace_id <= 0 or not is_valid_staffing_mode(staffing_mode):
		return false

	var object_index := CityObjectSystem.get_city_object_index_by_id(workplace_id)

	if object_index < 0:
		return false

	var raw_workplace = CityObjectSystem.get_city_objects()[object_index]

	if not raw_workplace is Dictionary:
		return false

	var workplace: Dictionary = raw_workplace

	if not WorldData.city_object_is_workplace(workplace):
		return false

	if get_workplace_staffing_mode(workplace) == staffing_mode:
		return true

	var updated_workplace: Dictionary = workplace.duplicate(false)
	updated_workplace[WORKPLACE_STAFFING_MODE_FIELD] = staffing_mode

	if not CityObjectSystem.write_city_object_at_index(
		object_index,
		updated_workplace
	):
		return false

	mark_city_workplaces_changed()
	return true


static func set_workplace_desired_worker_count(
	workplace_id: int,
	desired_worker_count: int
) -> bool:
	var object_index := CityObjectSystem.get_city_object_index_by_id(workplace_id)

	if object_index < 0:
		return false

	var raw_workplace = CityObjectSystem.get_city_objects()[object_index]

	if not raw_workplace is Dictionary:
		return false

	var workplace: Dictionary = raw_workplace

	if not WorldData.city_object_is_workplace(workplace):
		return false

	var worker_capacity := maxi(
		WorldData.get_city_object_worker_capacity(workplace),
		0
	)

	if desired_worker_count < 0 or desired_worker_count > worker_capacity:
		return false

	if get_workplace_desired_worker_count(workplace) == desired_worker_count:
		return true

	var updated_workplace: Dictionary = workplace.duplicate(false)
	updated_workplace[WORKPLACE_DESIRED_WORKER_COUNT_FIELD] = (
		desired_worker_count
	)

	if not CityObjectSystem.write_city_object_at_index(
		object_index,
		updated_workplace
	):
		return false

	mark_city_workplaces_changed()
	return true


# Future manual workplace UI should call this boundary rather than mutating
# citizen or workplace dictionaries directly. A busy citizen may reject an
# immediate transition; the UI can retain that pending intent in its own pass.
static func assign_citizen_to_workplace(
	citizen_id: int,
	workplace_id: int,
	manual_assignment: bool = true
) -> bool:
	if manual_assignment and not set_workplace_staffing_mode(
		workplace_id,
		STAFFING_MODE_MANUAL
	):
		return false

	return CityAssignmentSystem.assign_city_citizen_job(
		citizen_id,
		workplace_id
	)


static func remove_citizen_job(citizen_id: int) -> bool:
	return CityAssignmentSystem.remove_city_citizen_job(citizen_id)


static func get_city_unemployed_citizen_count() -> int:
	return CityAssignmentSystem.get_city_unemployed_citizen_count()


static func get_city_object_worker_ids(city_object: Dictionary) -> Array:
	return CityAssignmentSystem.get_city_object_worker_ids(city_object)


static func get_city_object_worker_count(city_object: Dictionary) -> int:
	return CityAssignmentSystem.get_city_object_worker_count(city_object)


static func get_city_object_worker_names(city_object: Dictionary) -> Array:
	return CityAssignmentSystem.get_city_object_worker_names(city_object)


static func is_city_citizen_attending_workplace(
	citizen_id: int,
	workplace_id: int,
	source_world = null
) -> bool:
	if citizen_id <= 0 or workplace_id <= 0:
		return false

	var workplace := CityObjectSystem.get_city_object_by_id(workplace_id)

	if workplace.is_empty() or not WorldData.city_object_is_workplace(workplace):
		return false

	var city_world: WorldData = source_world

	if city_world == null:
		city_world = WorldData.official_city_world

	if city_world == null:
		return false

	var access_tiles := WorldData.get_city_object_access_tiles(
		city_world,
		workplace
	)
	return _city_citizen_matches_workplace_attendance(
		CityCitizenRegistrySystem.get_city_citizen_by_id(citizen_id),
		workplace_id,
		access_tiles
	)


static func get_city_object_attending_worker_ids(
	city_object: Dictionary,
	source_world = null
) -> Array[int]:
	var attending_worker_ids: Array[int] = []

	if (
		city_object.is_empty()
		or not WorldData.city_object_is_workplace(city_object)
	):
		return attending_worker_ids

	var workplace_id := int(city_object.get("id", -1))
	var worker_capacity := WorldData.get_city_object_worker_capacity(city_object)

	if workplace_id <= 0 or worker_capacity <= 0:
		return attending_worker_ids

	var city_world: WorldData = source_world

	if city_world == null:
		city_world = WorldData.official_city_world

	if city_world == null:
		return attending_worker_ids

	var access_tiles := WorldData.get_city_object_access_tiles(
		city_world,
		city_object
	)

	if access_tiles.is_empty():
		return attending_worker_ids

	var counted_worker_ids: Dictionary = {}

	for raw_worker_id in get_city_object_worker_ids(city_object):
		var worker_id := int(raw_worker_id)

		if worker_id <= 0 or counted_worker_ids.has(worker_id):
			continue

		counted_worker_ids[worker_id] = true

		if not _city_citizen_matches_workplace_attendance(
			CityCitizenRegistrySystem.get_city_citizen_by_id(worker_id),
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
	return get_city_object_attending_worker_ids(
		city_object,
		source_world
	).size()


static func reconcile_automatic_workplaces() -> int:
	var workplace_ids: Array[int] = []

	for raw_city_object in CityObjectSystem.get_city_objects():
		if not raw_city_object is Dictionary:
			continue

		var city_object: Dictionary = raw_city_object

		if (
			WorldData.city_object_is_workplace(city_object)
			and get_workplace_staffing_mode(city_object)
			== STAFFING_MODE_AUTOMATIC
		):
			var workplace_id := int(city_object.get("id", -1))
			if workplace_id > 0:
				workplace_ids.append(workplace_id)

	workplace_ids.sort()
	var candidate_ids := _get_unemployed_candidate_ids()
	var assigned_count := 0

	for workplace_id in workplace_ids:
		if assigned_count >= MAX_AUTOMATIC_ASSIGNMENTS_PER_TICK:
			break

		var workplace := CityObjectSystem.get_city_object_by_id(workplace_id)

		if workplace.is_empty():
			continue

		var desired_worker_count := get_workplace_desired_worker_count(workplace)

		while (
			get_city_object_worker_count(workplace) < desired_worker_count
			and assigned_count < MAX_AUTOMATIC_ASSIGNMENTS_PER_TICK
		):
			var filled_one_slot := false

			for citizen_id in candidate_ids:
				var citizen := (
					CityCitizenRegistrySystem.get_city_citizen_by_id(citizen_id)
				)

				if (
					citizen.is_empty()
					or not bool(citizen.get("alive", false))
					or int(citizen.get("job_object_id", -1)) > 0
				):
					continue

				# A temporarily unavailable citizen never blocks later candidates.
				# The persistent vacancy is retried on following simulation ticks.
				if not CityAssignmentSystem.assign_city_citizen_job(
					citizen_id,
					workplace_id
				):
					continue

				assigned_count += 1
				filled_one_slot = true
				workplace = CityObjectSystem.get_city_object_by_id(workplace_id)
				break

			if not filled_one_slot:
				break

	return assigned_count


static func _get_unemployed_candidate_ids() -> Array[int]:
	var candidate_ids: Array[int] = []

	for raw_citizen in CityCitizenRegistrySystem.get_current_state().citizens:
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
		!= WorldData.CITY_CITIZEN_TASK_KIND_WORK
		or str(current_task.get("phase", ""))
		!= WorldData.CITY_CITIZEN_TASK_PHASE_PERFORMING
		or int(current_task.get("target_object_id", -1))
		!= workplace_id
		or str(citizen.get("movement_state", ""))
		!= WorldData.CITY_CITIZEN_MOVEMENT_STATE_IDLE
	):
		return false

	var raw_tile_position = citizen.get(
		"city_tile_position",
		WorldData.INVALID_CITY_TILE_POSITION
	)

	if not raw_tile_position is Vector2i:
		return false

	var citizen_tile: Vector2i = raw_tile_position
	var raw_target_tile = current_task.get(
		"target_tile",
		WorldData.INVALID_CITY_TILE_POSITION
	)

	if raw_target_tile is Vector2i:
		var target_tile: Vector2i = raw_target_tile
		if target_tile != WorldData.INVALID_CITY_TILE_POSITION:
			return citizen_tile == target_tile

	return access_tiles.has(citizen_tile)
