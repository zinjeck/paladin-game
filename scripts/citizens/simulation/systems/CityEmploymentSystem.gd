extends RefCounted
class_name CityEmploymentSystem

# Durable employment policy and vacancy reconciliation. Job relationships stay
# authoritative in WorldData; this system decides how open workplace slots are
# filled. The same APIs are intended for the future workplace assignment UI.

const STAFFING_MODE_AUTOMATIC := "automatic"
const STAFFING_MODE_MANUAL := "manual"
const WORKPLACE_STAFFING_MODE_FIELD := "staffing_mode"
const WORKPLACE_DESIRED_WORKER_COUNT_FIELD := "desired_worker_count"
const MAX_AUTOMATIC_ASSIGNMENTS_PER_TICK: int = 32


static func run_tick(
	_tick_index: int,
	minutes_advanced: int
) -> void:
	if (
		minutes_advanced <= 0
		or WorldData.official_city_world == null
	):
		return

	ensure_workplace_staffing_state()
	reconcile_automatic_workplaces()


static func is_valid_staffing_mode(staffing_mode: String) -> bool:
	return staffing_mode in [
		STAFFING_MODE_AUTOMATIC,
		STAFFING_MODE_MANUAL,
	]


static func ensure_workplace_staffing_state() -> int:
	var normalized_count := 0

	for object_index in range(WorldData.city_objects.size()):
		var raw_city_object = WorldData.city_objects[object_index]

		if not raw_city_object is Dictionary:
			continue

		var city_object: Dictionary = raw_city_object

		if not WorldData.city_object_is_workplace(city_object):
			continue

		var normalized := city_object.duplicate(true)
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

		WorldData.city_objects[object_index] = normalized
		normalized_count += 1

	if normalized_count > 0:
		WorldData._mark_city_workplaces_changed()

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

	var object_index := WorldData.get_city_object_index_by_id(workplace_id)

	if object_index < 0:
		return false

	var raw_workplace = WorldData.city_objects[object_index]

	if not raw_workplace is Dictionary:
		return false

	var workplace: Dictionary = raw_workplace

	if not WorldData.city_object_is_workplace(workplace):
		return false

	if get_workplace_staffing_mode(workplace) == staffing_mode:
		return true

	workplace[WORKPLACE_STAFFING_MODE_FIELD] = staffing_mode
	WorldData.city_objects[object_index] = workplace
	WorldData._mark_city_workplaces_changed()
	return true


static func set_workplace_desired_worker_count(
	workplace_id: int,
	desired_worker_count: int
) -> bool:
	var object_index := WorldData.get_city_object_index_by_id(workplace_id)

	if object_index < 0:
		return false

	var raw_workplace = WorldData.city_objects[object_index]

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

	workplace[WORKPLACE_DESIRED_WORKER_COUNT_FIELD] = desired_worker_count
	WorldData.city_objects[object_index] = workplace
	WorldData._mark_city_workplaces_changed()
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

	return WorldData.assign_city_citizen_job(citizen_id, workplace_id)


static func remove_citizen_job(citizen_id: int) -> bool:
	return WorldData.remove_city_citizen_job(citizen_id)


static func reconcile_automatic_workplaces() -> int:
	var workplace_ids: Array[int] = []

	for raw_city_object in WorldData.city_objects:
		if not raw_city_object is Dictionary:
			continue

		var city_object: Dictionary = raw_city_object

		if (
			WorldData.city_object_is_workplace(city_object)
			and get_workplace_staffing_mode(city_object)
			== STAFFING_MODE_AUTOMATIC
		):
			workplace_ids.append(int(city_object.get("id", -1)))

	workplace_ids.sort()
	var candidate_ids := _get_unemployed_candidate_ids()
	var assigned_count := 0

	for workplace_id in workplace_ids:
		if assigned_count >= MAX_AUTOMATIC_ASSIGNMENTS_PER_TICK:
			break

		var workplace := WorldData.get_city_object_by_id(workplace_id)

		if workplace.is_empty():
			continue

		var desired_worker_count := get_workplace_desired_worker_count(
			workplace
		)

		while (
			WorldData.get_city_object_worker_count(workplace)
			< desired_worker_count
			and assigned_count < MAX_AUTOMATIC_ASSIGNMENTS_PER_TICK
		):
			var filled_one_slot := false

			for citizen_id in candidate_ids:
				var citizen := WorldData.get_city_citizen_by_id(citizen_id)

				if (
					citizen.is_empty()
					or not bool(citizen.get("alive", false))
					or int(citizen.get("job_object_id", -1)) >= 0
				):
					continue

				# A temporarily unavailable citizen never blocks later candidates.
				# The persistent vacancy is retried on following simulation ticks.
				if not WorldData.assign_city_citizen_job(
					citizen_id,
					workplace_id
				):
					continue

				assigned_count += 1
				filled_one_slot = true
				workplace = WorldData.get_city_object_by_id(workplace_id)
				break

			if not filled_one_slot:
				break

	return assigned_count


static func _get_unemployed_candidate_ids() -> Array[int]:
	var candidate_ids: Array[int] = []

	for raw_citizen in WorldData.city_citizens:
		if not raw_citizen is Dictionary:
			continue

		var citizen: Dictionary = raw_citizen
		var citizen_id := int(citizen.get("id", -1))

		if (
			citizen_id > 0
			and bool(citizen.get("alive", false))
			and int(citizen.get("job_object_id", -1)) < 0
		):
			candidate_ids.append(citizen_id)

	candidate_ids.sort()
	return candidate_ids
