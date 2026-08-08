# File responsibility: Coordinate read-only invariant validation for authoritative city simulation state.
# Domain-specific validation lives in the dedicated validators preloaded below.
extends RefCounted

const CityLogisticsStateValidator := preload("res://scripts/city/simulation/validators/CityLogisticsStateValidator.gd")
const CityCitizenStateValidator := preload("res://scripts/city/simulation/validators/CityCitizenStateValidator.gd")
const CityObjectStateValidator := preload("res://scripts/city/simulation/validators/CityObjectStateValidator.gd")

const MAX_REPORTED_PROBLEMS: int = 24

static var _cached_result: Dictionary = {}


#region Validation Entry Point and Cache
static func validate(
	force_rebuild: bool = false,
	report_problems: bool = true
) -> Dictionary:
	if (
		not force_rebuild
		and _validation_cache_matches_current_state()
	):
		return _cached_result

	var validation_start_usec := Time.get_ticks_usec()

	var errors: Array[String] = []
	var warnings: Array[String] = []

	var object_lookup := _validate_city_object_index(errors)
	var citizen_lookup := _validate_city_citizen_index(errors)
	var construction_site_lookup := (
		CityLogisticsStateValidator._validate_city_construction_state(
			errors,
			object_lookup
		)
	)
	var ground_pile_lookup := CityLogisticsStateValidator._validate_city_ground_pile_state(
		errors,
		construction_site_lookup
	)

	CityObjectStateValidator._validate_city_foundation_state(
		errors,
		warnings,
		object_lookup
	)

	CityObjectStateValidator._validate_city_occupancy(
		errors,
		object_lookup
	)

	CityCitizenStateValidator._validate_city_citizen_spatial_state(
		errors,
		citizen_lookup
	)

	CityCitizenStateValidator._validate_city_citizen_demographics(
		errors,
		citizen_lookup
	)
	CityCitizenStateValidator._validate_city_citizen_need_state(
		errors,
		citizen_lookup
	)
	var checked_work_order_count := CityLogisticsStateValidator._validate_city_work_orders(
		errors,
		citizen_lookup,
		construction_site_lookup
	)
	CityCitizenStateValidator._validate_city_citizen_task_state(
		errors,
		citizen_lookup,
		object_lookup
	)
	var checked_haul_reservation_count := (
		CityLogisticsStateValidator._validate_city_haul_reservations(
			errors,
			citizen_lookup,
			ground_pile_lookup
		)
	)
	CityCitizenStateValidator._validate_city_citizen_movement_state(
		errors,
		citizen_lookup
	)

	var checked_container_count := CityObjectStateValidator._validate_city_containers(
		errors,
		object_lookup
	)

	CityObjectStateValidator._validate_city_assignments(
		errors,
		object_lookup,
		citizen_lookup
	)

	CityObjectStateValidator._validate_city_workplace_production({
		"errors": errors,
		"warnings": warnings,
		"object_lookup": object_lookup,
		"citizen_lookup": citizen_lookup,
	})

	var checked_inventory_count := CityObjectStateValidator._validate_citizen_inventories(
		errors,
		warnings,
		citizen_lookup
	)

	var validation_duration_usec := (
		Time.get_ticks_usec()
		- validation_start_usec
	)

	var result := {
		"valid": errors.is_empty(),
		"errors": errors,
		"warnings": warnings,
		"checked_objects": object_lookup.size(),
		"checked_citizens": citizen_lookup.size(),
		"checked_occupied_tiles": WorldData.city_occupied_tiles.size(),
		"checked_containers": checked_container_count,
		"checked_inventories": checked_inventory_count,
		"checked_ground_piles": ground_pile_lookup.size(),
		"checked_haul_reservations": checked_haul_reservation_count,
		"checked_work_orders": checked_work_order_count,
		"checked_construction_sites": construction_site_lookup.size(),
		"duration_usec": validation_duration_usec,
		"object_version": WorldData.city_object_version,
		"container_version": WorldData.city_container_version,
		"citizen_version": WorldData.city_citizen_version,
		"citizen_spatial_version": (
			WorldData.city_citizen_spatial_version
		),
		"citizen_movement_version": (
			WorldData.city_citizen_movement_version
		),
		"citizen_task_version": (
			WorldData.city_citizen_task_version
		),
		"assignment_version": WorldData.city_assignment_version,
		"workplace_version": WorldData.city_workplace_version,
		"ground_pile_version": CityLogisticsSystem.get_current_state().ground_pile_version,
		"player_command_version": CityWorkSystem.get_current_work_state().player_command_version,
		"work_order_version": CityWorkSystem.get_current_work_state().work_order_version,
		"haul_reservation_version": (
			CityLogisticsSystem.get_current_state().haul_reservation_version
		),
		"construction_version": CityConstructionSystem.get_current_state().construction_version,
	}

	_cached_result = result

	if report_problems:
		_report_validation_problems(result)

	return _cached_result


static func get_summary_text() -> String:
	var result := validate(false, true)

	var error_count := int(
		result.get("errors", []).size()
	)

	var warning_count := int(
		result.get("warnings", []).size()
	)

	var status_text := "VALID"

	if error_count > 0:
		status_text = "INVALID"
	elif warning_count > 0:
		status_text = "VALID WITH WARNINGS"

	var duration_msec := (
		float(result.get("duration_usec", 0))
		/ 1000.0
	)

	return (
		"City State: " + status_text
		+ " | Errors: " + str(error_count)
		+ " | Warnings: " + str(warning_count)
		+ "\n"
		+ "Checked: "
		+ str(result.get("checked_objects", 0))
		+ " objects | "
		+ str(result.get("checked_citizens", 0))
		+ " citizens | "
		+ str(result.get("checked_occupied_tiles", 0))
		+ " occupied tiles"
		+ "\n"
		+ "Logistics: "
		+ str(result.get("checked_ground_piles", 0))
		+ " ground piles | "
		+ str(result.get("checked_haul_reservations", 0))
		+ " reservations"
		+ " | "
		+ str(result.get("checked_work_orders", 0))
		+ " work orders"
		+ " | "
		+ str(result.get("checked_construction_sites", 0))
		+ " construction sites"
		+ "\n"
		+ "Validation Cost: "
		+ "%.3f ms" % duration_msec
	)

static func _validation_cache_matches_current_state() -> bool:
	if _cached_result.is_empty():
		return false
	if (
		int(
			_cached_result.get(
				"citizen_task_version",
				-1
			)
		)
		!= WorldData.city_citizen_task_version
	):
		return false
	if (
		int(_cached_result.get("object_version", -1))
		!= WorldData.city_object_version
	):
		return false

	if (
		int(_cached_result.get("container_version", -1))
		!= WorldData.city_container_version
	):
		return false

	if (
		int(_cached_result.get("citizen_version", -1))
		!= WorldData.city_citizen_version
	):
		return false

	if (
		int(
			_cached_result.get(
				"citizen_spatial_version",
				-1
			)
		)
		!= WorldData.city_citizen_spatial_version
	):
		return false

	if (
		int(
			_cached_result.get(
				"citizen_movement_version",
				-1
			)
		)
		!= WorldData.city_citizen_movement_version
	):
		return false

	if (
		int(_cached_result.get("assignment_version", -1))
		!= WorldData.city_assignment_version
	):
		return false

	if (
		int(_cached_result.get("workplace_version", -1))
		!= WorldData.city_workplace_version
	):
		return false

	if (
		int(_cached_result.get("ground_pile_version", -1))
		!= CityLogisticsSystem.get_current_state().ground_pile_version
	):
		return false

	if (
		int(
			_cached_result.get(
				"player_command_version",
				-1
			)
		)
		!= CityWorkSystem.get_current_work_state().player_command_version
	):
		return false

	if (
		int(
			_cached_result.get(
				"work_order_version",
				-1
			)
		)
		!= CityWorkSystem.get_current_work_state().work_order_version
	):
		return false

	if (
		int(
			_cached_result.get(
				"haul_reservation_version",
				-1
			)
		)
		!= CityLogisticsSystem.get_current_state().haul_reservation_version
	):
		return false

	if (
		int(_cached_result.get("construction_version", -1))
		!= CityConstructionSystem.get_current_state().construction_version
	):
		return false

	return true




#endregion

#region Entity Index Validation
static func _validate_city_object_index(
	errors: Array[String]
) -> Dictionary:
	var object_lookup: Dictionary = {}
	var maximum_object_id := 0

	for object_index in range(WorldData.city_objects.size()):
		var raw_city_object = WorldData.city_objects[object_index]

		if not raw_city_object is Dictionary:
			errors.append(
				"city_objects["
				+ str(object_index)
				+ "] is not a Dictionary."
			)

			continue

		var city_object: Dictionary = raw_city_object
		var object_id := int(
			city_object.get("id", -1)
		)

		if object_id <= 0:
			errors.append(
				"City object at array index "
				+ str(object_index)
				+ " has invalid ID "
				+ str(object_id)
				+ "."
			)

			continue

		if object_lookup.has(object_id):
			errors.append(
				"Duplicate city object ID "
				+ str(object_id)
				+ " exists at array indexes "
				+ str(object_lookup[object_id])
				+ " and "
				+ str(object_index)
				+ "."
			)

			continue

		object_lookup[object_id] = object_index
		maximum_object_id = maxi(
			maximum_object_id,
			object_id
		)

		var object_type := str(
			city_object.get("type", "")
		)

		if object_type.is_empty():
			errors.append(
				"City object "
				+ str(object_id)
				+ " has no object type."
			)
		elif (
			object_type != WorldData.CITY_OBJECT_ROAD
			and WorldData.get_city_object_definition(
				object_type
			).is_empty()
		):
			errors.append(
				"City object "
				+ str(object_id)
				+ " uses unknown type '"
				+ object_type
				+ "'."
			)

		if not WorldData.city_object_index_by_id.has(
			object_id
		):
			errors.append(
				"City object index is missing object ID "
				+ str(object_id)
				+ "."
			)
		else:
			var indexed_array_position := int(
				WorldData.city_object_index_by_id[
					object_id
				]
			)

			if indexed_array_position != object_index:
				errors.append(
					"City object index maps object ID "
					+ str(object_id)
					+ " to array index "
					+ str(indexed_array_position)
					+ ", but the object is actually at "
					+ str(object_index)
					+ "."
				)

	for raw_object_id in WorldData.city_object_index_by_id.keys():
		if typeof(raw_object_id) != TYPE_INT:
			errors.append(
				"City object index contains non-integer key "
				+ str(raw_object_id)
				+ "."
			)

			continue

		var object_id: int = raw_object_id

		if not object_lookup.has(object_id):
			errors.append(
				"City object index contains orphan object ID "
				+ str(object_id)
				+ "."
			)

	if (
		WorldData.city_object_index_by_id.size()
		!= object_lookup.size()
	):
		errors.append(
			"City object index contains "
				+ str(
					WorldData.city_object_index_by_id.size()
				)
				+ " entries, but "
				+ str(object_lookup.size())
				+ " valid objects exist."
		)

	if (
		not object_lookup.is_empty()
		and WorldData.next_city_object_id
		<= maximum_object_id
	):
		errors.append(
			"next_city_object_id is "
				+ str(WorldData.next_city_object_id)
				+ ", but existing object ID "
				+ str(maximum_object_id)
				+ " is equal or greater."
		)

	return object_lookup


static func _validate_city_citizen_index(
	errors: Array[String]
) -> Dictionary:
	var citizen_lookup: Dictionary = {}
	var maximum_citizen_id := 0

	for citizen_index in range(
		WorldData.city_citizens.size()
	):
		var raw_citizen = WorldData.city_citizens[
			citizen_index
		]

		if not raw_citizen is Dictionary:
			errors.append(
				"city_citizens["
				+ str(citizen_index)
				+ "] is not a Dictionary."
			)

			continue

		var citizen: Dictionary = raw_citizen
		var citizen_id := int(
			citizen.get("id", -1)
		)

		if citizen_id <= 0:
			errors.append(
				"Citizen at array index "
				+ str(citizen_index)
				+ " has invalid ID "
				+ str(citizen_id)
				+ "."
			)

			continue

		if citizen_lookup.has(citizen_id):
			errors.append(
				"Duplicate citizen ID "
				+ str(citizen_id)
				+ " exists at array indexes "
				+ str(citizen_lookup[citizen_id])
				+ " and "
				+ str(citizen_index)
				+ "."
			)

			continue

		citizen_lookup[citizen_id] = citizen_index
		maximum_citizen_id = maxi(
			maximum_citizen_id,
			citizen_id
		)

		if not WorldData.city_citizen_index_by_id.has(
			citizen_id
		):
			errors.append(
				"Citizen index is missing citizen ID "
				+ str(citizen_id)
				+ "."
			)
		else:
			var indexed_array_position := int(
				WorldData.city_citizen_index_by_id[
					citizen_id
				]
			)

			if indexed_array_position != citizen_index:
				errors.append(
					"Citizen index maps citizen ID "
					+ str(citizen_id)
					+ " to array index "
					+ str(indexed_array_position)
					+ ", but the citizen is actually at "
					+ str(citizen_index)
					+ "."
				)

	for raw_citizen_id in (
		WorldData.city_citizen_index_by_id.keys()
	):
		if typeof(raw_citizen_id) != TYPE_INT:
			errors.append(
				"Citizen index contains non-integer key "
				+ str(raw_citizen_id)
				+ "."
			)

			continue

		var citizen_id: int = raw_citizen_id

		if not citizen_lookup.has(citizen_id):
			errors.append(
				"Citizen index contains orphan citizen ID "
				+ str(citizen_id)
				+ "."
			)

	if (
		WorldData.city_citizen_index_by_id.size()
		!= citizen_lookup.size()
	):
		errors.append(
			"Citizen index contains "
				+ str(
					WorldData.city_citizen_index_by_id.size()
				)
				+ " entries, but "
				+ str(citizen_lookup.size())
				+ " valid citizens exist."
		)

	if (
		not citizen_lookup.is_empty()
		and WorldData.next_city_citizen_id
		<= maximum_citizen_id
	):
		errors.append(
			"next_city_citizen_id is "
				+ str(WorldData.next_city_citizen_id)
				+ ", but existing citizen ID "
				+ str(maximum_citizen_id)
				+ " is equal or greater."
		)

	return citizen_lookup



#endregion

#region Validation Reporting
static func _report_validation_problems(
	result: Dictionary
) -> void:
	var errors: Array = result.get("errors", [])
	var warnings: Array = result.get(
		"warnings",
		[]
	)

	var reported_problem_count := 0

	for error_text in errors:
		if (
			reported_problem_count
			>= MAX_REPORTED_PROBLEMS
		):
			break

		push_error(
			"CITY STATE INVARIANT: "
			+ str(error_text)
		)

		reported_problem_count += 1

	for warning_text in warnings:
		if (
			reported_problem_count
			>= MAX_REPORTED_PROBLEMS
		):
			break

		push_warning(
			"CITY STATE WARNING: "
			+ str(warning_text)
		)

		reported_problem_count += 1

	var total_problem_count := (
		errors.size()
		+ warnings.size()
	)

	if total_problem_count > reported_problem_count:
		push_warning(
			"City validation found "
				+ str(
					total_problem_count
					- reported_problem_count
				)
				+ " additional problems that were not printed."
		)

#endregion
