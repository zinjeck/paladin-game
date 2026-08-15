extends RefCounted
class_name CityAssignmentSystem

# Authoritative behavior/API for settlement-local housing and employment
# relationships. Citizen and object records retain the physical relationship
# fields; this system is the only ordinary mutation boundary that may change
# both sides together. CityAssignmentState owns only invalidation, never a
# duplicate relationship ledger.


static func get_current_state() -> CityAssignmentState:
	return WorldPoliticalState.get_current_city_assignment_state()


static func get_city_assignment_version() -> int:
	return get_current_state().assignment_version


static func get_city_assignment_version_for_city_state(
	city_state: CitySettlementSimulationState
) -> int:
	return city_state.assignment_state.assignment_version


static func mark_city_assignments_changed() -> void:
	get_current_state().assignment_version += 1


static func mark_city_assignments_changed_for_city_state(
	city_state: CitySettlementSimulationState
) -> void:
	city_state.assignment_state.assignment_version += 1


static func reset_city_assignment_state() -> void:
	# Relationship records are reset by their citizen/object owners. Publish one
	# focused invalidation without manufacturing a second copy here.
	mark_city_assignments_changed()


static func reset_city_assignment_state_for_city_state(
	city_state: CitySettlementSimulationState
) -> void:
	mark_city_assignments_changed_for_city_state(city_state)


static func _get_registry_state(
	city_state: CitySettlementSimulationState
) -> CityCitizenRegistryState:
	if city_state == null:
		return CityCitizenRegistrySystem.get_current_state()
	return city_state.citizen_registry_state


static func _get_city_objects(
	city_state: CitySettlementSimulationState
) -> Array:
	if city_state == null:
		return CityObjectSystem.get_city_objects()
	return CityObjectSystem.get_city_objects_for_city_state(city_state)


static func _get_city_citizen_index_by_id(
	city_state: CitySettlementSimulationState,
	citizen_id: int
) -> int:
	if city_state == null:
		return CityCitizenRegistrySystem.get_city_citizen_index_by_id(citizen_id)
	return CityCitizenRegistrySystem.get_city_citizen_index_by_id_for_city_state(
		city_state,
		citizen_id
	)


static func _mark_assignments_changed(
	city_state: CitySettlementSimulationState
) -> void:
	if city_state == null:
		mark_city_assignments_changed()
	else:
		mark_city_assignments_changed_for_city_state(city_state)


static func get_city_housed_citizen_count() -> int:
	return _get_city_housed_citizen_count(null)


static func get_city_housed_citizen_count_for_city_state(
	city_state: CitySettlementSimulationState
) -> int:
	return _get_city_housed_citizen_count(city_state)


static func _get_city_housed_citizen_count(
	city_state: CitySettlementSimulationState
) -> int:
	var housed_count := 0

	for raw_citizen in _get_registry_state(city_state).citizens:
		if not raw_citizen is Dictionary:
			continue
		if not bool(raw_citizen.get("alive", true)):
			continue
		if int(raw_citizen.get("home_object_id", -1)) > 0:
			housed_count += 1

	return housed_count


static func get_city_unemployed_citizen_count() -> int:
	return _get_city_unemployed_citizen_count(null)


static func get_city_unemployed_citizen_count_for_city_state(
	city_state: CitySettlementSimulationState
) -> int:
	return _get_city_unemployed_citizen_count(city_state)


static func _get_city_unemployed_citizen_count(
	city_state: CitySettlementSimulationState
) -> int:
	var unemployed_count := 0

	for raw_citizen in _get_registry_state(city_state).citizens:
		if not raw_citizen is Dictionary:
			continue
		if not bool(raw_citizen.get("alive", true)):
			continue
		if int(raw_citizen.get("job_object_id", -1)) <= 0:
			unemployed_count += 1

	return unemployed_count


static func get_city_object_resident_count(city_object: Dictionary) -> int:
	return _get_city_object_resident_ids(null, city_object).size()


static func get_city_object_resident_count_for_city_state(
	city_state: CitySettlementSimulationState,
	city_object: Dictionary
) -> int:
	return _get_city_object_resident_ids(city_state, city_object).size()


static func get_city_object_resident_ids(city_object: Dictionary) -> Array:
	return _get_city_object_resident_ids(null, city_object)


static func get_city_object_resident_ids_for_city_state(
	city_state: CitySettlementSimulationState,
	city_object: Dictionary
) -> Array:
	return _get_city_object_resident_ids(city_state, city_object)


static func _get_city_object_resident_ids(
	city_state: CitySettlementSimulationState,
	city_object: Dictionary
) -> Array:
	var resident_ids: Array = []

	if city_object.is_empty():
		return resident_ids

	var object_id := int(city_object.get("id", -1))

	if object_id <= 0:
		return resident_ids

	return _get_clean_city_object_assignment_ids(
		city_state,
		city_object,
		object_id,
		"resident_ids",
		"home_object_id"
	)


static func get_city_object_resident_names(city_object: Dictionary) -> Array:
	var resident_names: Array = []

	for raw_resident_id in get_city_object_resident_ids(city_object):
		resident_names.append(
			CityCitizenRegistrySystem.get_city_citizen_display_name(
				int(raw_resident_id)
			)
		)

	return resident_names


static func get_total_city_resident_capacity() -> int:
	return _get_total_city_resident_capacity(null)


static func get_total_city_resident_capacity_for_city_state(
	city_state: CitySettlementSimulationState
) -> int:
	return _get_total_city_resident_capacity(city_state)


static func set_city_object_resident_capacity(
	object_id: int,
	resident_capacity: int
) -> bool:
	return _set_city_object_resident_capacity(
		null,
		object_id,
		resident_capacity
	)


static func set_city_object_resident_capacity_for_city_state(
	city_state: CitySettlementSimulationState,
	object_id: int,
	resident_capacity: int
) -> bool:
	return _set_city_object_resident_capacity(
		city_state,
		object_id,
		resident_capacity
	)


static func _set_city_object_resident_capacity(
	city_state: CitySettlementSimulationState,
	object_id: int,
	resident_capacity: int
) -> bool:
	if object_id <= 0 or resident_capacity < 0:
		return false

	var city_object := (
		CityObjectSystem.get_city_object_by_id(object_id)
		if city_state == null
		else CityObjectSystem.get_city_object_by_id_for_city_state(
			city_state,
			object_id
		)
	)

	if (
		city_object.is_empty()
		or (
			not city_object.has("resident_capacity")
			and CityObjectCatalog.get_city_object_resident_capacity(
				city_object
			) <= 0
		)
	):
		return false

	if int(city_object.get("resident_capacity", 0)) == resident_capacity:
		return true

	var changed := (
		CityObjectSystem.patch_city_object_assignment_fields(
			object_id,
			{"resident_capacity": resident_capacity}
		)
		if city_state == null
		else CityObjectSystem.patch_city_object_assignment_fields_for_city_state(
			city_state,
			object_id,
			{"resident_capacity": resident_capacity}
		)
	)

	if not changed:
		return false

	_mark_assignments_changed(city_state)
	return true


static func _get_total_city_resident_capacity(
	city_state: CitySettlementSimulationState
) -> int:
	var total_capacity := 0

	for raw_city_object in _get_city_objects(city_state):
		if not raw_city_object is Dictionary:
			continue
		total_capacity += CityObjectCatalog.get_city_object_resident_capacity(
			raw_city_object
		)

	return total_capacity


static func get_city_object_worker_ids(city_object: Dictionary) -> Array:
	return _get_city_object_worker_ids(null, city_object)


static func get_city_object_worker_ids_for_city_state(
	city_state: CitySettlementSimulationState,
	city_object: Dictionary
) -> Array:
	return _get_city_object_worker_ids(city_state, city_object)


static func _get_city_object_worker_ids(
	city_state: CitySettlementSimulationState,
	city_object: Dictionary
) -> Array:
	var worker_ids: Array = []

	if city_object.is_empty():
		return worker_ids

	var object_id := int(city_object.get("id", -1))

	if object_id <= 0:
		return worker_ids

	return _get_clean_city_object_assignment_ids(
		city_state,
		city_object,
		object_id,
		"assigned_worker_ids",
		"job_object_id"
	)


static func get_city_object_worker_count(city_object: Dictionary) -> int:
	return _get_city_object_worker_ids(null, city_object).size()


static func get_city_object_worker_count_for_city_state(
	city_state: CitySettlementSimulationState,
	city_object: Dictionary
) -> int:
	return _get_city_object_worker_ids(city_state, city_object).size()


static func get_city_object_worker_names(city_object: Dictionary) -> Array:
	var worker_names: Array = []

	for raw_worker_id in get_city_object_worker_ids(city_object):
		worker_names.append(
			CityCitizenRegistrySystem.get_city_citizen_display_name(
				int(raw_worker_id)
			)
		)

	return worker_names


static func ensure_city_citizen_assignment_state() -> int:
	return _ensure_city_citizen_assignment_state(null)


static func ensure_city_citizen_assignment_state_for_city_state(
	city_state: CitySettlementSimulationState
) -> int:
	return _ensure_city_citizen_assignment_state(city_state)


static func _ensure_city_citizen_assignment_state(
	city_state: CitySettlementSimulationState
) -> int:
	# Citizen links are the canonical relationship intent. Rebuild both object
	# projections deterministically, enforce capacities, and quarantine dead or
	# dangling links. A single version publication covers the complete repair.
	var resident_ids_by_object_id: Dictionary = {}
	var worker_ids_by_object_id: Dictionary = {}
	var resident_capacity_by_object_id: Dictionary = {}
	var worker_capacity_by_object_id: Dictionary = {}
	var object_indexes_by_id: Dictionary = {}
	var changed_record_count := 0
	var city_objects := _get_city_objects(city_state)
	var registry_state := _get_registry_state(city_state)

	for object_index in range(city_objects.size()):
		var raw_city_object = city_objects[object_index]

		if not raw_city_object is Dictionary:
			continue

		var city_object: Dictionary = raw_city_object
		var object_id := int(city_object.get("id", -1))

		if object_id <= 0:
			continue

		object_indexes_by_id[object_id] = object_index
		var resident_capacity := CityObjectCatalog.get_city_object_resident_capacity(
			city_object
		)

		if resident_capacity > 0:
			resident_capacity_by_object_id[object_id] = resident_capacity
			resident_ids_by_object_id[object_id] = []

		if CityObjectCatalog.city_object_is_workplace(city_object):
			var worker_capacity := CityObjectCatalog.get_city_object_worker_capacity(
				city_object
			)

			if worker_capacity > 0:
				worker_capacity_by_object_id[object_id] = worker_capacity
				worker_ids_by_object_id[object_id] = []

	var citizen_ids: Array[int] = []

	for raw_citizen in registry_state.citizens:
		if not raw_citizen is Dictionary:
			continue
		var citizen_id := int(raw_citizen.get("id", -1))
		if citizen_id > 0:
			citizen_ids.append(citizen_id)

	citizen_ids.sort()

	for citizen_id in citizen_ids:
		var citizen_index := _get_city_citizen_index_by_id(
			city_state,
			citizen_id
		)

		if citizen_index < 0:
			continue

		var raw_citizen = registry_state.citizens[citizen_index]

		if not raw_citizen is Dictionary:
			continue

		var citizen: Dictionary = raw_citizen.duplicate(false)
		var citizen_changed := false
		var clear_return_home_task := false
		var clear_work_task := false
		var alive := bool(citizen.get("alive", true))
		var home_id := int(citizen.get("home_object_id", -1))
		var job_id := int(citizen.get("job_object_id", -1))

		if not citizen.has("home_object_id") or home_id == 0:
			home_id = -1
			citizen["home_object_id"] = -1
			citizen_changed = true
			clear_return_home_task = true

		if not citizen.has("job_object_id") or job_id == 0:
			job_id = -1
			citizen["job_object_id"] = -1
			citizen_changed = true
			clear_work_task = true

		if not alive:
			clear_return_home_task = true
			clear_work_task = true
			if home_id > 0:
				citizen["home_object_id"] = -1
				home_id = -1
				citizen_changed = true
				clear_return_home_task = true
			if job_id > 0:
				citizen["job_object_id"] = -1
				job_id = -1
				citizen_changed = true
				clear_work_task = true
		else:
			if home_id > 0:
				if not resident_ids_by_object_id.has(home_id):
					citizen["home_object_id"] = -1
					home_id = -1
					citizen_changed = true
					clear_return_home_task = true
				else:
					var resident_ids: Array = resident_ids_by_object_id[home_id]
					var resident_capacity := int(
						resident_capacity_by_object_id.get(home_id, 0)
					)
					if resident_ids.size() >= resident_capacity:
						citizen["home_object_id"] = -1
						home_id = -1
						citizen_changed = true
						clear_return_home_task = true
					else:
						resident_ids.append(citizen_id)
						resident_ids_by_object_id[home_id] = resident_ids

			if job_id > 0:
				if not worker_ids_by_object_id.has(job_id):
					citizen["job_object_id"] = -1
					job_id = -1
					citizen_changed = true
					clear_work_task = true
				else:
					var worker_ids: Array = worker_ids_by_object_id[job_id]
					var worker_capacity := int(
						worker_capacity_by_object_id.get(job_id, 0)
					)
					if worker_ids.size() >= worker_capacity:
						citizen["job_object_id"] = -1
						job_id = -1
						citizen_changed = true
						clear_work_task = true
					else:
						worker_ids.append(citizen_id)
						worker_ids_by_object_id[job_id] = worker_ids

		if citizen_changed:
			registry_state.citizens[citizen_index] = citizen
			changed_record_count += 1
		# Task/movement owners read and rewrite the canonical citizen record.
		# Clear only after repaired relationship fields are committed so storing
		# this local duplicate cannot restore the retired task. Dead citizens with
		# already-normalized links still need stale home/work behavior retired.
		if clear_return_home_task:
			_clear_city_citizen_return_home_task_after_home_change(
				city_state,
				citizen_id
			)
		if clear_work_task:
			_clear_city_citizen_work_task_after_job_change(
				city_state,
				citizen_id
			)

	for raw_object_id in object_indexes_by_id.keys():
		var object_id := int(raw_object_id)
		var object_index := int(object_indexes_by_id[object_id])
		var raw_city_object = city_objects[object_index]

		if not raw_city_object is Dictionary:
			continue

		var city_object: Dictionary = raw_city_object.duplicate(false)
		var object_changed := false

		if resident_capacity_by_object_id.has(object_id):
			var resident_ids: Array = resident_ids_by_object_id.get(object_id, [])
			var raw_resident_ids = city_object.get("resident_ids", null)
			if not raw_resident_ids is Array or raw_resident_ids != resident_ids:
				city_object["resident_ids"] = resident_ids.duplicate()
				object_changed = true
		elif city_object.has("resident_ids"):
			city_object.erase("resident_ids")
			object_changed = true

		if worker_capacity_by_object_id.has(object_id):
			var worker_ids: Array = worker_ids_by_object_id.get(object_id, [])
			var raw_worker_ids = city_object.get("assigned_worker_ids", null)
			if not raw_worker_ids is Array or raw_worker_ids != worker_ids:
				city_object["assigned_worker_ids"] = worker_ids.duplicate()
				object_changed = true
		elif city_object.has("assigned_worker_ids"):
			city_object.erase("assigned_worker_ids")
			object_changed = true

		if (
			object_changed
			and _patch_city_object_assignment_projection(
				city_state,
				object_id,
				raw_city_object,
				city_object
			)
		):
			changed_record_count += 1

	if changed_record_count > 0:
		_mark_assignments_changed(city_state)

	return changed_record_count


static func _patch_city_object_assignment_projection(
	city_state: CitySettlementSimulationState,
	object_id: int,
	existing: Dictionary,
	updated: Dictionary
) -> bool:
	var field_values: Dictionary = {}
	var fields_to_erase: Array = []

	for field_name in ["resident_ids", "assigned_worker_ids"]:
		if updated.has(field_name):
			field_values[field_name] = updated[field_name]
		elif existing.has(field_name):
			fields_to_erase.append(field_name)

	return (
		CityObjectSystem.patch_city_object_assignment_fields(
			object_id,
			field_values,
			fields_to_erase
		)
		if city_state == null
		else CityObjectSystem.patch_city_object_assignment_fields_for_city_state(
			city_state,
			object_id,
			field_values,
			fields_to_erase
		)
	)


static func assign_homeless_citizens_to_available_housing() -> int:
	return _assign_homeless_citizens_to_available_housing(null)


static func assign_homeless_citizens_to_available_housing_for_city_state(
	city_state: CitySettlementSimulationState
) -> int:
	return _assign_homeless_citizens_to_available_housing(city_state)


static func _assign_homeless_citizens_to_available_housing(
	city_state: CitySettlementSimulationState
) -> int:
	var assigned_count := 0

	for raw_city_object in _get_city_objects(city_state):
		if not raw_city_object is Dictionary:
			continue

		var city_object: Dictionary = raw_city_object
		var house_id := int(city_object.get("id", -1))
		var resident_capacity := CityObjectCatalog.get_city_object_resident_capacity(
			city_object
		)

		if house_id <= 0 or resident_capacity <= 0:
			continue

		while true:
			var current_house := (
				CityObjectSystem.get_city_object_by_id(house_id)
				if city_state == null
				else CityObjectSystem.get_city_object_by_id_for_city_state(
					city_state,
					house_id
				)
			)

			if (
				current_house.is_empty()
				or _get_city_object_resident_ids(city_state, current_house).size()
				>= resident_capacity
			):
				break

			var homeless_citizen_id := _get_first_homeless_city_citizen_id(
				city_state
			)

			if homeless_citizen_id <= 0:
				break

			if not _assign_city_citizen_home(
				city_state,
				homeless_citizen_id,
				house_id
			):
				push_error(
					"Failed to assign homeless citizen "
					+ str(homeless_citizen_id)
					+ " to housing object "
					+ str(house_id)
				)
				break

			assigned_count += 1

	return assigned_count


static func assign_city_citizen_home(
	citizen_id: int,
	house_id: int
) -> bool:
	return _assign_city_citizen_home(null, citizen_id, house_id)


static func assign_city_citizen_home_for_city_state(
	city_state: CitySettlementSimulationState,
	citizen_id: int,
	house_id: int
) -> bool:
	return _assign_city_citizen_home(city_state, citizen_id, house_id)


static func _assign_city_citizen_home(
	city_state: CitySettlementSimulationState,
	citizen_id: int,
	house_id: int
) -> bool:
	var registry_state := _get_registry_state(city_state)
	var city_objects := _get_city_objects(city_state)
	var citizen_index := _get_city_citizen_index_by_id(
		city_state,
		citizen_id
	)

	if citizen_index < 0:
		return false

	var raw_citizen = registry_state.citizens[citizen_index]

	if not raw_citizen is Dictionary:
		return false

	var citizen: Dictionary = raw_citizen.duplicate(false)

	if not bool(citizen.get("alive", true)):
		return false

	var house_index := (
		CityObjectSystem.get_city_object_index_by_id(house_id)
		if city_state == null
		else CityObjectSystem.get_city_object_index_by_id_for_city_state(
			city_state,
			house_id
		)
	)

	if house_index < 0:
		return false

	var raw_house = city_objects[house_index]

	if not raw_house is Dictionary:
		return false

	var house: Dictionary = raw_house
	var resident_capacity := CityObjectCatalog.get_city_object_resident_capacity(house)

	if resident_capacity <= 0:
		return false

	var resident_ids := _get_clean_city_object_assignment_ids(
		city_state,
		house,
		house_id,
		"resident_ids",
		"home_object_id"
	)
	var current_home_id := int(citizen.get("home_object_id", -1))

	if current_home_id == house_id:
		var assignment_changed := false

		if not resident_ids.has(citizen_id):
			if resident_ids.size() >= resident_capacity:
				push_error(
					"Citizen "
					+ str(citizen_id)
					+ " points to full House "
					+ str(house_id)
					+ " but is missing from its resident list."
				)
				return false
			resident_ids.append(citizen_id)
			assignment_changed = true

		if _write_city_object_assignment_ids(
			city_state,
			house_index,
			"resident_ids",
			resident_ids
		):
			assignment_changed = true

		if assignment_changed:
			_mark_assignments_changed(city_state)

		return true

	if resident_ids.size() >= resident_capacity:
		return false

	var assignment_changed := false

	if current_home_id > 0:
		if _remove_citizen_from_city_object_assignment(
			city_state,
			current_home_id,
			citizen_id,
			"resident_ids",
			"home_object_id"
		):
			assignment_changed = true

	citizen["home_object_id"] = house_id
	registry_state.citizens[citizen_index] = citizen
	assignment_changed = true
	_clear_city_citizen_return_home_task_after_home_change(
		city_state,
		citizen_id
	)
	resident_ids.append(citizen_id)

	if _write_city_object_assignment_ids(
		city_state,
		house_index,
		"resident_ids",
		resident_ids
	):
		assignment_changed = true

	if assignment_changed:
		_mark_assignments_changed(city_state)

	return true


static func remove_city_citizen_home(citizen_id: int) -> bool:
	return _remove_city_citizen_home(null, citizen_id)


static func remove_city_citizen_home_for_city_state(
	city_state: CitySettlementSimulationState,
	citizen_id: int
) -> bool:
	return _remove_city_citizen_home(city_state, citizen_id)


static func _remove_city_citizen_home(
	city_state: CitySettlementSimulationState,
	citizen_id: int
) -> bool:
	var registry_state := _get_registry_state(city_state)
	var citizen_index := _get_city_citizen_index_by_id(
		city_state,
		citizen_id
	)

	if citizen_index < 0:
		return false

	var raw_citizen = registry_state.citizens[citizen_index]

	if not raw_citizen is Dictionary:
		return false

	var citizen: Dictionary = raw_citizen.duplicate(false)
	var current_home_id := int(citizen.get("home_object_id", -1))

	if current_home_id <= 0:
		return false

	_remove_citizen_from_city_object_assignment(
		city_state,
		current_home_id,
		citizen_id,
		"resident_ids",
		"home_object_id"
	)
	citizen["home_object_id"] = -1
	registry_state.citizens[citizen_index] = citizen
	_clear_city_citizen_return_home_task_after_home_change(
		city_state,
		citizen_id
	)
	_mark_assignments_changed(city_state)
	return true


static func assign_city_citizen_job(
	citizen_id: int,
	workplace_id: int
) -> bool:
	return _assign_city_citizen_job(null, citizen_id, workplace_id)


static func assign_city_citizen_job_for_city_state(
	city_state: CitySettlementSimulationState,
	citizen_id: int,
	workplace_id: int
) -> bool:
	return _assign_city_citizen_job(city_state, citizen_id, workplace_id)


static func _assign_city_citizen_job(
	city_state: CitySettlementSimulationState,
	citizen_id: int,
	workplace_id: int
) -> bool:
	var registry_state := _get_registry_state(city_state)
	var city_objects := _get_city_objects(city_state)
	var citizen_index := _get_city_citizen_index_by_id(
		city_state,
		citizen_id
	)

	if citizen_index < 0:
		return false

	var raw_citizen = registry_state.citizens[citizen_index]

	if not raw_citizen is Dictionary:
		return false

	var citizen: Dictionary = raw_citizen.duplicate(false)

	if not bool(citizen.get("alive", true)):
		return false

	var workplace_index := (
		CityObjectSystem.get_city_object_index_by_id(workplace_id)
		if city_state == null
		else CityObjectSystem.get_city_object_index_by_id_for_city_state(
			city_state,
			workplace_id
		)
	)

	if workplace_index < 0:
		return false

	var raw_workplace = city_objects[workplace_index]

	if not raw_workplace is Dictionary:
		return false

	var workplace: Dictionary = raw_workplace

	if not CityObjectCatalog.city_object_is_workplace(workplace):
		return false

	var worker_capacity := CityObjectCatalog.get_city_object_worker_capacity(workplace)

	if worker_capacity <= 0:
		return false

	var worker_ids := _get_clean_city_object_assignment_ids(
		city_state,
		workplace,
		workplace_id,
		"assigned_worker_ids",
		"job_object_id"
	)
	var current_job_id := int(citizen.get("job_object_id", -1))

	if current_job_id == workplace_id:
		var assignment_changed := false

		if not worker_ids.has(citizen_id):
			if worker_ids.size() >= worker_capacity:
				push_error(
					"Citizen "
					+ str(citizen_id)
					+ " points to full workplace "
					+ str(workplace_id)
					+ " but is missing from its worker list."
				)
				return false
			worker_ids.append(citizen_id)
			assignment_changed = true

		if _write_city_object_assignment_ids(
			city_state,
			workplace_index,
			"assigned_worker_ids",
			worker_ids
		):
			assignment_changed = true

		if assignment_changed:
			_mark_assignments_changed(city_state)
			_clear_city_citizen_work_task_after_job_change(
				city_state,
				citizen_id
			)

		return true

	if worker_ids.size() >= worker_capacity:
		return false

	# Validate capacity before interrupting an unemployed citizen's autonomous
	# action. A rejected assignment must not drop cargo or abandon a valid haul.
	if (
		current_job_id <= 0
		and not (
			CitizenTaskSystem.prepare_unemployed_citizen_for_priority_interrupt(
				citizen_id
			)
			if city_state == null
			else CitizenTaskSystem.prepare_unemployed_citizen_for_priority_interrupt_for_city_state(
				city_state,
				citizen_id
			)
		)
	):
		return false

	if current_job_id <= 0:
		citizen = (
			CityCitizenRegistrySystem.get_city_citizen_by_id(citizen_id)
			if city_state == null
			else CityCitizenRegistrySystem.get_city_citizen_by_id_for_city_state(
				city_state,
				citizen_id
			)
		).duplicate(false)
		if citizen.is_empty():
			return false

	var assignment_changed := false

	if current_job_id > 0:
		if _remove_citizen_from_city_object_assignment(
			city_state,
			current_job_id,
			citizen_id,
			"assigned_worker_ids",
			"job_object_id"
		):
			assignment_changed = true

	citizen["job_object_id"] = workplace_id
	registry_state.citizens[citizen_index] = citizen
	assignment_changed = true
	worker_ids.append(citizen_id)

	if _write_city_object_assignment_ids(
		city_state,
		workplace_index,
		"assigned_worker_ids",
		worker_ids
	):
		assignment_changed = true

	if assignment_changed:
		_mark_assignments_changed(city_state)

	if current_job_id > 0:
		# A successful A -> B reassignment retires any Work task and movement
		# still targeting A after both relationship projections point to B.
		_clear_city_citizen_work_task_after_job_change(
			city_state,
			citizen_id
		)

	return true


static func remove_city_citizen_job(citizen_id: int) -> bool:
	return _remove_city_citizen_job(null, citizen_id)


static func remove_city_citizen_job_for_city_state(
	city_state: CitySettlementSimulationState,
	citizen_id: int
) -> bool:
	return _remove_city_citizen_job(city_state, citizen_id)


static func _remove_city_citizen_job(
	city_state: CitySettlementSimulationState,
	citizen_id: int
) -> bool:
	var registry_state := _get_registry_state(city_state)
	var citizen_index := _get_city_citizen_index_by_id(
		city_state,
		citizen_id
	)

	if citizen_index < 0:
		return false

	var raw_citizen = registry_state.citizens[citizen_index]

	if not raw_citizen is Dictionary:
		return false

	var citizen: Dictionary = raw_citizen.duplicate(false)
	var current_job_id := int(citizen.get("job_object_id", -1))

	if current_job_id <= 0:
		return false

	_remove_citizen_from_city_object_assignment(
		city_state,
		current_job_id,
		citizen_id,
		"assigned_worker_ids",
		"job_object_id"
	)
	citizen["job_object_id"] = -1
	registry_state.citizens[citizen_index] = citizen
	_mark_assignments_changed(city_state)
	_clear_city_citizen_work_task_after_job_change(city_state, citizen_id)
	return true


static func _get_first_homeless_city_citizen_id(
	city_state: CitySettlementSimulationState
) -> int:
	for raw_citizen in _get_registry_state(city_state).citizens:
		if not raw_citizen is Dictionary:
			continue
		if not bool(raw_citizen.get("alive", true)):
			continue
		if int(raw_citizen.get("home_object_id", -1)) > 0:
			continue
		var citizen_id := int(raw_citizen.get("id", -1))
		if citizen_id > 0:
			return citizen_id

	return -1


static func _get_clean_city_object_assignment_ids(
	city_state: CitySettlementSimulationState,
	city_object: Dictionary,
	object_id: int,
	object_id_list_field: String,
	citizen_object_id_field: String
) -> Array:
	var clean_assignment_ids: Array = []

	if city_object.is_empty():
		return clean_assignment_ids

	var raw_assignment_ids = city_object.get(object_id_list_field, [])

	if not raw_assignment_ids is Array:
		return clean_assignment_ids

	for raw_citizen_id in raw_assignment_ids:
		var citizen_id := int(raw_citizen_id)

		if citizen_id <= 0 or clean_assignment_ids.has(citizen_id):
			continue

		var citizen_index := _get_city_citizen_index_by_id(
			city_state,
			citizen_id
		)

		if citizen_index < 0:
			continue

		var raw_citizen = _get_registry_state(city_state).citizens[citizen_index]

		if not raw_citizen is Dictionary:
			continue
		if not bool(raw_citizen.get("alive", true)):
			continue
		if int(raw_citizen.get(citizen_object_id_field, -1)) != object_id:
			continue

		clean_assignment_ids.append(citizen_id)

	return clean_assignment_ids


static func _write_city_object_assignment_ids(
	city_state: CitySettlementSimulationState,
	object_index: int,
	object_id_list_field: String,
	assignment_ids: Array
) -> bool:
	if (
		object_index < 0
		or object_index >= _get_city_objects(city_state).size()
	):
		return false

	var raw_city_object = _get_city_objects(city_state)[object_index]

	if not raw_city_object is Dictionary:
		return false

	var city_object: Dictionary = raw_city_object.duplicate(false)
	var existing_assignment_ids = city_object.get(object_id_list_field, [])

	if existing_assignment_ids is Array and existing_assignment_ids == assignment_ids:
		return false

	return (
		CityObjectSystem.patch_city_object_assignment_fields(
			int(city_object.get("id", -1)),
			{object_id_list_field: assignment_ids.duplicate()}
		)
		if city_state == null
		else CityObjectSystem.patch_city_object_assignment_fields_for_city_state(
			city_state,
			int(city_object.get("id", -1)),
			{object_id_list_field: assignment_ids.duplicate()}
		)
	)


static func _remove_citizen_from_city_object_assignment(
	city_state: CitySettlementSimulationState,
	object_id: int,
	citizen_id: int,
	object_id_list_field: String,
	citizen_object_id_field: String
) -> bool:
	var object_index := (
		CityObjectSystem.get_city_object_index_by_id(object_id)
		if city_state == null
		else CityObjectSystem.get_city_object_index_by_id_for_city_state(
			city_state,
			object_id
		)
	)

	if object_index < 0:
		return false

	var raw_city_object = _get_city_objects(city_state)[object_index]

	if not raw_city_object is Dictionary:
		return false

	var assignment_ids := _get_clean_city_object_assignment_ids(
		city_state,
		raw_city_object,
		object_id,
		object_id_list_field,
		citizen_object_id_field
	)
	var removed_citizen := false

	while assignment_ids.has(citizen_id):
		assignment_ids.erase(citizen_id)
		removed_citizen = true

	var assignment_list_changed := _write_city_object_assignment_ids(
		city_state,
		object_index,
		object_id_list_field,
		assignment_ids
	)
	return removed_citizen or assignment_list_changed


static func _clear_city_citizen_return_home_task_after_home_change(
	city_state: CitySettlementSimulationState,
	citizen_id: int
) -> void:
	var current_task := (
		CityCitizenTaskRuntimeSystem.get_city_citizen_current_task(citizen_id)
		if city_state == null
		else CityCitizenTaskRuntimeSystem.get_city_citizen_current_task_for_city_state(
			city_state,
			citizen_id
		)
	)

	if (
		str(current_task.get("kind", ""))
		!= CityCitizens.CITY_CITIZEN_TASK_KIND_RETURN_HOME
	):
		return

	if city_state == null:
		CityCitizenTaskRuntimeSystem.clear_city_citizen_task(
			citizen_id,
			CityCitizens.CITY_CITIZEN_TASK_SOURCE_PLAYER
		)
		CityCitizenMovementRuntimeSystem.cancel_city_citizen_movement(citizen_id)
	else:
		CityCitizenTaskRuntimeSystem.clear_city_citizen_task_for_city_state(
			city_state,
			citizen_id,
			CityCitizens.CITY_CITIZEN_TASK_SOURCE_PLAYER
		)
		CityCitizenMovementRuntimeSystem.cancel_city_citizen_movement_for_city_state(
			city_state,
			citizen_id
		)


static func _clear_city_citizen_work_task_after_job_change(
	city_state: CitySettlementSimulationState,
	citizen_id: int
) -> void:
	var current_task := (
		CityCitizenTaskRuntimeSystem.get_city_citizen_current_task(citizen_id)
		if city_state == null
		else CityCitizenTaskRuntimeSystem.get_city_citizen_current_task_for_city_state(
			city_state,
			citizen_id
		)
	)

	if (
		str(current_task.get("kind", ""))
		!= CityCitizens.CITY_CITIZEN_TASK_KIND_WORK
	):
		return

	if city_state == null:
		CityCitizenTaskRuntimeSystem.clear_city_citizen_task(
			citizen_id,
			CityCitizens.CITY_CITIZEN_TASK_SOURCE_PLAYER
		)
		CityCitizenMovementRuntimeSystem.cancel_city_citizen_movement(citizen_id)
	else:
		CityCitizenTaskRuntimeSystem.clear_city_citizen_task_for_city_state(
			city_state,
			citizen_id,
			CityCitizens.CITY_CITIZEN_TASK_SOURCE_PLAYER
		)
		CityCitizenMovementRuntimeSystem.cancel_city_citizen_movement_for_city_state(
			city_state,
			citizen_id
		)
