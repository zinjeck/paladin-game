extends RefCounted

const MAX_REPORTED_PROBLEMS: int = 24

static var _cached_result: Dictionary = {}


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

	_validate_city_foundation_state(
		errors,
		warnings,
		object_lookup
	)

	_validate_city_occupancy(
		errors,
		object_lookup
	)

	var checked_container_count := _validate_city_containers(
		errors,
		object_lookup
	)

	_validate_city_assignments(
		errors,
		object_lookup,
		citizen_lookup
	)

	_validate_city_workplace_production(
		errors,
		warnings,
		object_lookup,
		citizen_lookup
	)

	var checked_inventory_count := _validate_citizen_inventories(
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
		"duration_usec": validation_duration_usec,
		"object_version": WorldData.city_object_version,
		"container_version": WorldData.city_container_version,
		"citizen_version": WorldData.city_citizen_version,
		"assignment_version": WorldData.city_assignment_version,
		"workplace_version": WorldData.city_workplace_version
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
		+ "Validation Cost: "
		+ "%.3f ms" % duration_msec
	)


static func _validation_cache_matches_current_state() -> bool:
	if _cached_result.is_empty():
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
		int(_cached_result.get("assignment_version", -1))
		!= WorldData.city_assignment_version
	):
		return false

	if (
		int(_cached_result.get("workplace_version", -1))
		!= WorldData.city_workplace_version
	):
		return false

	return true


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


static func _validate_city_foundation_state(
	errors: Array[String],
	warnings: Array[String],
	object_lookup: Dictionary
) -> void:
	var city_center_count := 0

	for object_id in object_lookup.keys():
		var object_index := int(
			object_lookup[object_id]
		)

		var city_object: Dictionary = (
			WorldData.city_objects[object_index]
		)

		if (
			str(city_object.get("type", ""))
			== WorldData.CITY_OBJECT_CITY_CENTER
		):
			city_center_count += 1

	if not WorldData.player_city_founded:
		if not WorldData.city_citizens.is_empty():
			errors.append(
				"Citizens exist before the player city is founded."
			)

		if city_center_count > 0:
			errors.append(
				"A City Keep exists while player_city_founded is false."
			)

		return

	if city_center_count != 1:
		errors.append(
			"Founded city must have exactly one City Keep, but "
				+ str(city_center_count)
				+ " exist."
		)

	if WorldData.city_citizens.is_empty():
		warnings.append(
			"The city is founded but currently has no citizens."
		)


static func _validate_city_occupancy(
	errors: Array[String],
	object_lookup: Dictionary
) -> void:
	var expected_occupancy: Dictionary = {}

	for object_id in object_lookup.keys():
		var object_index := int(
			object_lookup[object_id]
		)

		var city_object: Dictionary = (
			WorldData.city_objects[object_index]
		)

		var footprint_tiles := (
			WorldData.get_city_object_footprint_tiles(
				city_object
			)
		)

		if footprint_tiles.is_empty():
			errors.append(
				"City object "
					+ str(object_id)
					+ " has an empty footprint."
			)

			continue

		for raw_tile_position in footprint_tiles:
			if not raw_tile_position is Vector2i:
				errors.append(
					"City object "
						+ str(object_id)
						+ " has a non-Vector2i footprint entry."
				)

				continue

			var tile_position: Vector2i = (
				raw_tile_position
			)

			if expected_occupancy.has(tile_position):
				errors.append(
					"Tile "
						+ str(tile_position)
						+ " belongs to footprints of both object "
						+ str(expected_occupancy[tile_position])
						+ " and object "
						+ str(object_id)
						+ "."
				)
			else:
				expected_occupancy[tile_position] = object_id

			if not WorldData.city_occupied_tiles.has(
				tile_position
			):
				errors.append(
					"Object "
						+ str(object_id)
						+ " footprint tile "
						+ str(tile_position)
						+ " is missing from city_occupied_tiles."
				)

				continue

			var occupied_object_id := int(
				WorldData.city_occupied_tiles[
					tile_position
				]
			)

			if occupied_object_id != int(object_id):
				errors.append(
					"Tile "
						+ str(tile_position)
						+ " belongs to object "
						+ str(object_id)
						+ " by footprint, but occupancy points to "
						+ str(occupied_object_id)
						+ "."
				)

	for raw_tile_position in (
		WorldData.city_occupied_tiles.keys()
	):
		if not raw_tile_position is Vector2i:
			errors.append(
				"city_occupied_tiles contains a non-Vector2i key."
			)

			continue

		var tile_position: Vector2i = raw_tile_position
		var object_id := int(
			WorldData.city_occupied_tiles[tile_position]
		)

		if not object_lookup.has(object_id):
			errors.append(
				"Occupied tile "
					+ str(tile_position)
					+ " points to missing object ID "
					+ str(object_id)
					+ "."
			)

		if not expected_occupancy.has(tile_position):
			errors.append(
				"Occupied tile "
					+ str(tile_position)
					+ " is not present in its object's footprint."
			)


static func _validate_city_containers(
	errors: Array[String],
	object_lookup: Dictionary
) -> int:
	var checked_container_count := 0

	for object_id in object_lookup.keys():
		var object_index := int(
			object_lookup[object_id]
		)

		var city_object: Dictionary = (
			WorldData.city_objects[object_index]
		)

		var allowed_resources := (
			WorldData.get_city_object_storage_resources(
				city_object
			)
		)

		var raw_stored_resources = city_object.get(
			"stored_resources",
			{}
		)

		if allowed_resources.is_empty():
			if (
				raw_stored_resources is Dictionary
				and not raw_stored_resources.is_empty()
			):
				errors.append(
					"Object "
						+ str(object_id)
						+ " stores resources despite having no allowed storage resources."
				)
			elif not raw_stored_resources is Dictionary:
				errors.append(
					"Object "
						+ str(object_id)
						+ " has non-Dictionary stored_resources."
				)

			continue

		checked_container_count += 1

		if not raw_stored_resources is Dictionary:
			errors.append(
				"Container object "
					+ str(object_id)
					+ " has non-Dictionary stored_resources."
			)

			continue

		var stored_resources: Dictionary = (
			raw_stored_resources
		)

		for resource in allowed_resources:
			var capacity := (
				WorldData
				.get_city_object_storage_capacity_for_resource(
					city_object,
					resource
				)
			)

			if capacity <= 0:
				errors.append(
					"Container object "
						+ str(object_id)
						+ " allows "
						+ resource
						+ " but has capacity "
						+ str(capacity)
						+ "."
				)

			var raw_amount = stored_resources.get(
				resource,
				0
			)

			if typeof(raw_amount) != TYPE_INT:
				errors.append(
					"Container object "
						+ str(object_id)
						+ " stores non-integer amount for "
						+ resource
						+ "."
				)

				continue

			var amount: int = raw_amount

			if amount < 0:
				errors.append(
					"Container object "
						+ str(object_id)
						+ " has negative "
						+ resource
						+ " amount "
						+ str(amount)
						+ "."
				)

			if capacity >= 0 and amount > capacity:
				errors.append(
					"Container object "
						+ str(object_id)
						+ " stores "
						+ str(amount)
						+ " "
						+ resource
						+ " but capacity is "
						+ str(capacity)
						+ "."
				)

		for raw_resource in stored_resources.keys():
			var resource := str(raw_resource)

			if not allowed_resources.has(resource):
				errors.append(
					"Container object "
						+ str(object_id)
						+ " stores unsupported resource '"
						+ resource
						+ "'."
				)

	return checked_container_count


static func _validate_city_assignments(
	errors: Array[String],
	object_lookup: Dictionary,
	citizen_lookup: Dictionary
) -> void:
	var resident_membership: Dictionary = {}
	var worker_membership: Dictionary = {}

	for object_id in object_lookup.keys():
		var object_index := int(
			object_lookup[object_id]
		)

		var city_object: Dictionary = (
			WorldData.city_objects[object_index]
		)

		var resident_capacity := (
			WorldData.get_city_object_resident_capacity(
				city_object
			)
		)

		if resident_capacity > 0:
			if not city_object.has("resident_ids"):
				errors.append(
					"Housing object "
						+ str(object_id)
						+ " is missing resident_ids."
				)
			else:
				_validate_resident_list(
					errors,
					city_object,
					int(object_id),
					resident_capacity,
					citizen_lookup,
					resident_membership
				)
		elif (
			city_object.has("resident_ids")
			and city_object.get("resident_ids", []) is Array
			and not city_object.get(
				"resident_ids",
				[]
			).is_empty()
		):
			errors.append(
				"Non-housing object "
					+ str(object_id)
					+ " contains residents."
			)

		if WorldData.city_object_is_workplace(
			city_object
		):
			var worker_capacity := (
				WorldData.get_city_object_worker_capacity(
					city_object
				)
			)

			if not city_object.has("assigned_worker_ids"):
				errors.append(
					"Workplace "
						+ str(object_id)
						+ " is missing assigned_worker_ids."
				)
			else:
				_validate_worker_list(
					errors,
					city_object,
					int(object_id),
					worker_capacity,
					citizen_lookup,
					worker_membership
				)
		elif (
			city_object.has("assigned_worker_ids")
			and city_object.get(
				"assigned_worker_ids",
				[]
			) is Array
			and not city_object.get(
				"assigned_worker_ids",
				[]
			).is_empty()
		):
			errors.append(
				"Non-workplace object "
					+ str(object_id)
					+ " contains assigned workers."
			)

	for citizen_id in citizen_lookup.keys():
		var citizen_index := int(
			citizen_lookup[citizen_id]
		)

		var citizen: Dictionary = (
			WorldData.city_citizens[citizen_index]
		)

		var is_alive := bool(
			citizen.get("alive", true)
		)

		var home_object_id := int(
			citizen.get("home_object_id", -1)
		)

		var job_object_id := int(
			citizen.get("job_object_id", -1)
		)

		if not is_alive:
			if home_object_id >= 0:
				errors.append(
					"Dead citizen "
						+ str(citizen_id)
						+ " remains assigned to home "
						+ str(home_object_id)
						+ "."
				)

			if job_object_id >= 0:
				errors.append(
					"Dead citizen "
						+ str(citizen_id)
						+ " remains assigned to workplace "
						+ str(job_object_id)
						+ "."
				)

		if home_object_id >= 0:
			if not object_lookup.has(home_object_id):
				errors.append(
					"Citizen "
						+ str(citizen_id)
						+ " points to missing home object "
						+ str(home_object_id)
						+ "."
				)
			else:
				var home_index := int(
					object_lookup[home_object_id]
				)

				var home_object: Dictionary = (
					WorldData.city_objects[home_index]
				)

				if (
					WorldData
					.get_city_object_resident_capacity(
						home_object
					)
					<= 0
				):
					errors.append(
						"Citizen "
							+ str(citizen_id)
							+ " points to non-housing object "
							+ str(home_object_id)
							+ " as a home."
					)

			if not resident_membership.has(citizen_id):
				errors.append(
					"Citizen "
						+ str(citizen_id)
						+ " points to home "
						+ str(home_object_id)
						+ " but is absent from that resident list."
				)
			elif (
				int(resident_membership[citizen_id])
				!= home_object_id
			):
				errors.append(
					"Citizen "
						+ str(citizen_id)
						+ " points to home "
						+ str(home_object_id)
						+ " but appears in House "
						+ str(resident_membership[citizen_id])
						+ "."
				)
		elif resident_membership.has(citizen_id):
			errors.append(
				"Citizen "
					+ str(citizen_id)
					+ " has no home ID but appears in House "
					+ str(resident_membership[citizen_id])
					+ "."
			)

		if job_object_id >= 0:
			if not object_lookup.has(job_object_id):
				errors.append(
					"Citizen "
						+ str(citizen_id)
						+ " points to missing workplace "
						+ str(job_object_id)
						+ "."
				)
			else:
				var workplace_index := int(
					object_lookup[job_object_id]
				)

				var workplace: Dictionary = (
					WorldData.city_objects[
						workplace_index
					]
				)

				if not WorldData.city_object_is_workplace(
					workplace
				):
					errors.append(
						"Citizen "
							+ str(citizen_id)
							+ " points to non-workplace object "
							+ str(job_object_id)
							+ " as a job."
					)

			if not worker_membership.has(citizen_id):
				errors.append(
					"Citizen "
						+ str(citizen_id)
						+ " points to workplace "
						+ str(job_object_id)
						+ " but is absent from its worker list."
				)
			elif (
				int(worker_membership[citizen_id])
				!= job_object_id
			):
				errors.append(
					"Citizen "
						+ str(citizen_id)
						+ " points to workplace "
						+ str(job_object_id)
						+ " but appears in workplace "
						+ str(worker_membership[citizen_id])
						+ "."
				)
		elif worker_membership.has(citizen_id):
			errors.append(
				"Citizen "
					+ str(citizen_id)
					+ " has no job ID but appears in workplace "
					+ str(worker_membership[citizen_id])
					+ "."
			)


static func _validate_resident_list(
	errors: Array[String],
	city_object: Dictionary,
	object_id: int,
	resident_capacity: int,
	citizen_lookup: Dictionary,
	resident_membership: Dictionary
) -> void:
	var raw_resident_ids = city_object.get(
		"resident_ids",
		[]
	)

	if not raw_resident_ids is Array:
		errors.append(
			"Housing object "
				+ str(object_id)
				+ " has non-Array resident_ids."
		)

		return

	var resident_ids: Array = raw_resident_ids

	if resident_ids.size() > resident_capacity:
		errors.append(
			"Housing object "
				+ str(object_id)
				+ " has "
				+ str(resident_ids.size())
				+ " residents but capacity is "
				+ str(resident_capacity)
				+ "."
		)

	var local_residents: Dictionary = {}

	for raw_citizen_id in resident_ids:
		if typeof(raw_citizen_id) != TYPE_INT:
			errors.append(
				"Housing object "
					+ str(object_id)
					+ " contains a non-integer resident ID."
			)

			continue

		var citizen_id: int = raw_citizen_id

		if local_residents.has(citizen_id):
			errors.append(
				"Housing object "
					+ str(object_id)
					+ " lists citizen "
					+ str(citizen_id)
					+ " more than once."
			)

			continue

		local_residents[citizen_id] = true

		if resident_membership.has(citizen_id):
			errors.append(
				"Citizen "
					+ str(citizen_id)
					+ " appears in both House "
					+ str(resident_membership[citizen_id])
					+ " and House "
					+ str(object_id)
					+ "."
			)
		else:
			resident_membership[citizen_id] = object_id

		if not citizen_lookup.has(citizen_id):
			errors.append(
				"Housing object "
					+ str(object_id)
					+ " lists missing citizen "
					+ str(citizen_id)
					+ "."
			)

			continue

		var citizen_index := int(
			citizen_lookup[citizen_id]
		)

		var citizen: Dictionary = (
			WorldData.city_citizens[citizen_index]
		)

		if not bool(citizen.get("alive", true)):
			errors.append(
				"Housing object "
					+ str(object_id)
					+ " lists dead citizen "
					+ str(citizen_id)
					+ "."
			)

		if (
			int(citizen.get("home_object_id", -1))
			!= object_id
		):
			errors.append(
				"Housing object "
					+ str(object_id)
					+ " lists citizen "
					+ str(citizen_id)
					+ ", but the citizen points to home "
					+ str(
						citizen.get(
							"home_object_id",
							-1
						)
					)
					+ "."
			)


static func _validate_worker_list(
	errors: Array[String],
	city_object: Dictionary,
	object_id: int,
	worker_capacity: int,
	citizen_lookup: Dictionary,
	worker_membership: Dictionary
) -> void:
	var raw_worker_ids = city_object.get(
		"assigned_worker_ids",
		[]
	)

	if not raw_worker_ids is Array:
		errors.append(
			"Workplace "
				+ str(object_id)
				+ " has non-Array assigned_worker_ids."
		)

		return

	var worker_ids: Array = raw_worker_ids

	if worker_ids.size() > worker_capacity:
		errors.append(
			"Workplace "
				+ str(object_id)
				+ " has "
				+ str(worker_ids.size())
				+ " workers but capacity is "
				+ str(worker_capacity)
				+ "."
		)

	var local_workers: Dictionary = {}

	for raw_citizen_id in worker_ids:
		if typeof(raw_citizen_id) != TYPE_INT:
			errors.append(
				"Workplace "
					+ str(object_id)
					+ " contains a non-integer worker ID."
			)

			continue

		var citizen_id: int = raw_citizen_id

		if local_workers.has(citizen_id):
			errors.append(
				"Workplace "
					+ str(object_id)
					+ " lists citizen "
					+ str(citizen_id)
					+ " more than once."
			)

			continue

		local_workers[citizen_id] = true

		if worker_membership.has(citizen_id):
			errors.append(
				"Citizen "
					+ str(citizen_id)
					+ " appears in both workplace "
					+ str(worker_membership[citizen_id])
					+ " and workplace "
					+ str(object_id)
					+ "."
			)
		else:
			worker_membership[citizen_id] = object_id

		if not citizen_lookup.has(citizen_id):
			errors.append(
				"Workplace "
					+ str(object_id)
					+ " lists missing citizen "
					+ str(citizen_id)
					+ "."
			)

			continue

		var citizen_index := int(
			citizen_lookup[citizen_id]
		)

		var citizen: Dictionary = (
			WorldData.city_citizens[citizen_index]
		)

		if not bool(citizen.get("alive", true)):
			errors.append(
				"Workplace "
					+ str(object_id)
					+ " lists dead citizen "
					+ str(citizen_id)
					+ "."
			)

		if (
			int(citizen.get("job_object_id", -1))
			!= object_id
		):
			errors.append(
				"Workplace "
					+ str(object_id)
					+ " lists citizen "
					+ str(citizen_id)
					+ ", but the citizen points to job "
					+ str(
						citizen.get(
							"job_object_id",
							-1
						)
					)
					+ "."
			)


static func _validate_citizen_inventories(
	errors: Array[String],
	warnings: Array[String],
	citizen_lookup: Dictionary
) -> int:
	var checked_inventory_count := 0
	var valid_resources := (
		WorldData.get_city_resource_types()
	)

	for citizen_id in citizen_lookup.keys():
		var citizen_index := int(
			citizen_lookup[citizen_id]
		)

		var citizen: Dictionary = (
			WorldData.city_citizens[citizen_index]
		)

		var carry_capacity := int(
			citizen.get("carry_capacity", 0)
		)

		if carry_capacity < 0:
			errors.append(
				"Citizen "
					+ str(citizen_id)
					+ " has negative carry capacity "
					+ str(carry_capacity)
					+ "."
			)

		var raw_inventory = citizen.get(
			"inventory",
			{}
		)

		if not raw_inventory is Dictionary:
			errors.append(
				"Citizen "
					+ str(citizen_id)
					+ " has non-Dictionary inventory."
			)

			continue

		checked_inventory_count += 1

		var inventory: Dictionary = raw_inventory
		var total_inventory_amount := 0

		for raw_resource in inventory.keys():
			var resource := str(raw_resource)
			var raw_amount = inventory[raw_resource]

			if typeof(raw_amount) != TYPE_INT:
				errors.append(
					"Citizen "
						+ str(citizen_id)
						+ " has non-integer inventory amount for "
						+ resource
						+ "."
				)

				continue

			var amount: int = raw_amount

			if amount < 0:
				errors.append(
					"Citizen "
						+ str(citizen_id)
						+ " has negative inventory amount for "
						+ resource
						+ "."
				)

			total_inventory_amount += maxi(amount, 0)

			if not valid_resources.has(resource):
				warnings.append(
					"Citizen "
						+ str(citizen_id)
						+ " carries unknown resource '"
						+ resource
						+ "'."
				)

		if total_inventory_amount > carry_capacity:
			errors.append(
				"Citizen "
					+ str(citizen_id)
					+ " carries "
					+ str(total_inventory_amount)
					+ " items but capacity is "
					+ str(carry_capacity)
					+ "."
			)

	return checked_inventory_count


static func _validate_city_workplace_production(
	errors: Array[String],
	warnings: Array[String],
	object_lookup: Dictionary,
	citizen_lookup: Dictionary
) -> void:
	for object_id in object_lookup.keys():
		var object_index := int(object_lookup[object_id])
		var city_object: Dictionary = WorldData.city_objects[object_index]

		if not WorldData.city_object_is_workplace(city_object):
			continue

		var definition := WorldData.get_city_object_definition_from_object(
			city_object
		)

		if definition.is_empty():
			errors.append(
				"Workplace "
					+ str(object_id)
					+ " has no valid city-object definition."
			)
			continue

		var raw_production_recipe = (
			_get_required_workplace_definition_dictionary(
				errors,
				definition,
				int(object_id),
				"production_recipe"
			)
		)

		if raw_production_recipe is Dictionary:
			var production_recipe: Dictionary = raw_production_recipe

			if not production_recipe.is_empty():
				var work_units_per_batch := _validate_workplace_recipe(
					errors,
					city_object,
					int(object_id),
					production_recipe
				)

				_validate_workplace_runtime_production_state(
					errors,
					warnings,
					city_object,
					int(object_id),
					citizen_lookup,
					work_units_per_batch
				)

		var raw_resource_source_policy = (
			_get_required_workplace_definition_dictionary(
				errors,
				definition,
				int(object_id),
				"resource_source_policy"
			)
		)

		if raw_resource_source_policy is Dictionary:
			_validate_workplace_resource_source_policy(
				errors,
				int(object_id),
				raw_resource_source_policy
			)

		var raw_work_location_policy = (
			_get_required_workplace_definition_dictionary(
				errors,
				definition,
				int(object_id),
				"work_location_policy"
			)
		)

		if raw_work_location_policy is Dictionary:
			_validate_workplace_work_location_policy(
				errors,
				int(object_id),
				raw_work_location_policy
			)

		var raw_work_movement_policy = (
			_get_required_workplace_definition_dictionary(
				errors,
				definition,
				int(object_id),
				"work_movement_policy"
			)
		)

		if raw_work_movement_policy is Dictionary:
			_validate_workplace_movement_policy(
				errors,
				int(object_id),
				raw_work_movement_policy
			)

		var raw_break_location_policy = (
			_get_required_workplace_definition_dictionary(
				errors,
				definition,
				int(object_id),
				"break_location_policy"
			)
		)

		if raw_break_location_policy is Dictionary:
			_validate_workplace_break_location_policy(
				errors,
				int(object_id),
				raw_break_location_policy
			)

		var raw_overflow_policy = (
			_get_required_workplace_definition_dictionary(
				errors,
				definition,
				int(object_id),
				"overflow_policy"
			)
		)

		if raw_overflow_policy is Dictionary:
			_validate_workplace_overflow_policy(
				errors,
				int(object_id),
				raw_overflow_policy
			)


static func _get_required_workplace_definition_dictionary(
	errors: Array[String],
	definition: Dictionary,
	object_id: int,
	field_name: String
) -> Variant:
	if not definition.has(field_name):
		errors.append(
			"Workplace "
				+ str(object_id)
				+ " definition is missing "
				+ field_name
				+ "."
		)
		return null

	var raw_value = definition[field_name]

	if not raw_value is Dictionary:
		errors.append(
			"Workplace "
				+ str(object_id)
				+ " definition has non-Dictionary "
				+ field_name
				+ "."
		)
		return null

	return raw_value


static func _validate_workplace_recipe(
	errors: Array[String],
	city_object: Dictionary,
	object_id: int,
	recipe: Dictionary
) -> int:
	var valid_resources := WorldData.get_city_resource_types()
	var raw_inputs = recipe.get("inputs", null)

	if not recipe.has("inputs"):
		errors.append(
			"Workplace "
				+ str(object_id)
				+ " production recipe is missing inputs."
		)
	elif not raw_inputs is Dictionary:
		errors.append(
			"Workplace "
				+ str(object_id)
				+ " production recipe has non-Dictionary inputs."
		)
	else:
		_validate_workplace_recipe_resources(
			errors,
			city_object,
			object_id,
			raw_inputs,
			valid_resources,
			"input",
			false
		)

	var raw_outputs = recipe.get("outputs", null)

	if not recipe.has("outputs"):
		errors.append(
			"Workplace "
				+ str(object_id)
				+ " production recipe is missing outputs."
		)
	elif not raw_outputs is Dictionary:
		errors.append(
			"Workplace "
				+ str(object_id)
				+ " production recipe has non-Dictionary outputs."
		)
	else:
		var outputs: Dictionary = raw_outputs

		if outputs.is_empty():
			errors.append(
				"Workplace "
					+ str(object_id)
					+ " production recipe has no outputs."
			)
		else:
			_validate_workplace_recipe_resources(
				errors,
				city_object,
				object_id,
				outputs,
				valid_resources,
				"output",
				true
			)

	if not recipe.has("work_units_per_batch"):
		errors.append(
			"Workplace "
				+ str(object_id)
				+ " production recipe is missing work_units_per_batch."
		)
		return 0

	var raw_work_units_per_batch = recipe["work_units_per_batch"]

	if typeof(raw_work_units_per_batch) != TYPE_INT:
		errors.append(
			"Workplace "
				+ str(object_id)
				+ " production recipe has non-integer work_units_per_batch."
		)
		return 0

	var work_units_per_batch: int = raw_work_units_per_batch

	if work_units_per_batch <= 0:
		errors.append(
			"Workplace "
				+ str(object_id)
				+ " production recipe has non-positive work_units_per_batch "
				+ str(work_units_per_batch)
				+ "."
		)
		return 0

	return work_units_per_batch


static func _validate_workplace_recipe_resources(
	errors: Array[String],
	city_object: Dictionary,
	object_id: int,
	resource_amounts: Dictionary,
	valid_resources: Array[String],
	entry_label: String,
	validate_output_storage: bool
) -> void:
	for raw_resource in resource_amounts.keys():
		var resource := str(raw_resource)
		var resource_is_known := valid_resources.has(resource)

		if not resource_is_known:
			errors.append(
				"Workplace "
					+ str(object_id)
					+ " production recipe has unknown "
					+ entry_label
					+ " resource '"
					+ resource
					+ "'."
			)

		var raw_quantity = resource_amounts[raw_resource]

		if typeof(raw_quantity) != TYPE_INT:
			errors.append(
				"Workplace "
					+ str(object_id)
					+ " production recipe has non-integer quantity for "
					+ entry_label
					+ " resource '"
					+ resource
					+ "'."
			)
		elif int(raw_quantity) <= 0:
			errors.append(
				"Workplace "
					+ str(object_id)
					+ " production recipe has non-positive quantity for "
					+ entry_label
					+ " resource '"
					+ resource
					+ "'."
			)

		if not validate_output_storage or not resource_is_known:
			continue

		if not WorldData.can_city_object_store_resource(
			city_object,
			resource
		):
			errors.append(
				"Workplace "
					+ str(object_id)
					+ " cannot store recipe output resource '"
					+ resource
					+ "'."
			)
			continue

		var output_capacity := (
			WorldData.get_city_object_storage_capacity_for_resource(
				city_object,
				resource
			)
		)

		if output_capacity <= 0:
			errors.append(
				"Workplace "
					+ str(object_id)
					+ " has non-positive storage capacity for recipe output '"
					+ resource
					+ "'."
			)


static func _validate_workplace_runtime_production_state(
	errors: Array[String],
	warnings: Array[String],
	city_object: Dictionary,
	object_id: int,
	citizen_lookup: Dictionary,
	work_units_per_batch: int
) -> void:
	if not city_object.has("production_progress_work_units"):
		errors.append(
			"Workplace "
				+ str(object_id)
				+ " is missing production_progress_work_units."
		)
	else:
		var raw_progress = city_object["production_progress_work_units"]

		if typeof(raw_progress) != TYPE_INT:
			errors.append(
				"Workplace "
					+ str(object_id)
					+ " has non-integer production_progress_work_units."
			)
		else:
			var progress_work_units: int = raw_progress

			if progress_work_units < 0:
				errors.append(
					"Workplace "
						+ str(object_id)
						+ " has negative production progress "
						+ str(progress_work_units)
						+ "."
				)
			elif (
				work_units_per_batch > 0
				and progress_work_units >= work_units_per_batch
			):
				errors.append(
					"Workplace "
						+ str(object_id)
						+ " has production progress "
						+ str(progress_work_units)
						+ ", but one batch requires "
						+ str(work_units_per_batch)
						+ "."
				)

	if not city_object.has("production_status"):
		errors.append(
			"Workplace "
				+ str(object_id)
				+ " is missing production_status."
		)
	else:
		var raw_status = city_object["production_status"]

		if typeof(raw_status) != TYPE_STRING:
			errors.append(
				"Workplace "
					+ str(object_id)
					+ " has non-String production_status."
			)
		elif not WorldData.is_valid_city_workplace_production_status(
			raw_status
		):
			errors.append(
				"Workplace "
					+ str(object_id)
					+ " has unknown production status '"
					+ str(raw_status)
					+ "'."
			)

	if not city_object.has("productive_worker_count"):
		errors.append(
			"Workplace "
				+ str(object_id)
				+ " is missing productive_worker_count."
		)
	else:
		var raw_productive_worker_count = city_object[
			"productive_worker_count"
		]

		if typeof(raw_productive_worker_count) != TYPE_INT:
			errors.append(
				"Workplace "
					+ str(object_id)
					+ " has non-integer productive_worker_count."
			)
		else:
			var productive_worker_count: int = (
				raw_productive_worker_count
			)
			var worker_capacity := (
				WorldData.get_city_object_worker_capacity(city_object)
			)

			if productive_worker_count < 0:
				errors.append(
					"Workplace "
						+ str(object_id)
						+ " has negative productive_worker_count "
						+ str(productive_worker_count)
						+ "."
				)
			elif productive_worker_count > worker_capacity:
				errors.append(
					"Workplace "
						+ str(object_id)
						+ " has productive_worker_count "
						+ str(productive_worker_count)
						+ " but worker capacity is "
						+ str(worker_capacity)
						+ "."
				)

			var expected_productive_worker_count := (
				_get_expected_productive_worker_count(
					city_object,
					citizen_lookup
				)
			)
			var production_status := str(
				city_object.get("production_status", "")
			)

			# A newly staffed workplace can still be idle until the next tick.
			# Compare the derived count only after production has evaluated it.
			var production_has_evaluated_workers := (
				production_status
				== WorldData.WORKPLACE_PRODUCTION_STATUS_WORKING
				or production_status
				== WorldData.WORKPLACE_PRODUCTION_STATUS_BLOCKED_OUTPUT_FULL
				or production_status
				== WorldData.WORKPLACE_PRODUCTION_STATUS_BLOCKED_MISSING_INPUT
			)

			if (
				production_has_evaluated_workers
				and expected_productive_worker_count >= 0
				and productive_worker_count
				!= expected_productive_worker_count
			):
				warnings.append(
					"Workplace "
						+ str(object_id)
						+ " caches "
						+ str(productive_worker_count)
						+ " productive workers, but current assignment data yields "
						+ str(expected_productive_worker_count)
						+ "."
				)

	if not city_object.has("site_productivity_basis_points"):
		errors.append(
			"Workplace "
				+ str(object_id)
				+ " is missing site_productivity_basis_points."
		)
	else:
		var raw_site_productivity = city_object[
			"site_productivity_basis_points"
		]

		if typeof(raw_site_productivity) != TYPE_INT:
			errors.append(
				"Workplace "
					+ str(object_id)
					+ " has non-integer site_productivity_basis_points."
			)
		elif int(raw_site_productivity) < 0:
			errors.append(
				"Workplace "
					+ str(object_id)
					+ " has negative site_productivity_basis_points "
					+ str(raw_site_productivity)
					+ "."
			)


static func _get_expected_productive_worker_count(
	city_object: Dictionary,
	citizen_lookup: Dictionary
) -> int:
	var raw_worker_ids = city_object.get("assigned_worker_ids", null)

	if not raw_worker_ids is Array:
		return -1

	var workplace_id := int(city_object.get("id", -1))

	if workplace_id <= 0:
		return -1

	var productive_worker_count := 0
	var counted_worker_ids: Dictionary = {}

	for raw_worker_id in raw_worker_ids:
		if typeof(raw_worker_id) != TYPE_INT:
			continue

		var worker_id: int = raw_worker_id

		if worker_id <= 0 or counted_worker_ids.has(worker_id):
			continue

		counted_worker_ids[worker_id] = true

		if not citizen_lookup.has(worker_id):
			continue

		var citizen_index := int(citizen_lookup[worker_id])
		var citizen: Dictionary = WorldData.city_citizens[citizen_index]

		if not bool(citizen.get("alive", false)):
			continue

		if int(citizen.get("job_object_id", -1)) != workplace_id:
			continue

		productive_worker_count += 1

	return mini(
		productive_worker_count,
		maxi(
			WorldData.get_city_object_worker_capacity(city_object),
			0
		)
	)


static func _validate_workplace_resource_source_policy(
	errors: Array[String],
	object_id: int,
	policy: Dictionary
) -> void:
	var mode := _get_workplace_policy_mode(
		errors,
		object_id,
		"resource_source_policy",
		policy
	)

	if mode.is_empty():
		return

	if not WorldData.is_valid_workplace_resource_source_mode(mode):
		errors.append(
			"Workplace "
				+ str(object_id)
				+ " has unknown resource_source_policy mode '"
				+ mode
				+ "'."
		)
		return

	if mode != WorldData.WORKPLACE_RESOURCE_SOURCE_MODE_RADIUS:
		return

	_validate_known_workplace_policy_resource(
		errors,
		object_id,
		"resource_source_policy",
		policy,
		"resource_type"
	)

	_validate_positive_workplace_policy_integer(
		errors,
		object_id,
		"resource_source_policy",
		policy,
		"radius_tiles"
	)

	if not policy.has("anchor_mode"):
		errors.append(
			"Workplace "
				+ str(object_id)
				+ " resource_source_policy is missing anchor_mode."
		)
		return

	var raw_anchor_mode = policy["anchor_mode"]

	if typeof(raw_anchor_mode) != TYPE_STRING:
		errors.append(
			"Workplace "
				+ str(object_id)
				+ " resource_source_policy has non-String anchor_mode."
		)
		return

	var anchor_mode: String = raw_anchor_mode

	if not WorldData.is_valid_workplace_anchor_mode(anchor_mode):
		errors.append(
			"Workplace "
				+ str(object_id)
				+ " resource_source_policy has unknown anchor_mode '"
				+ anchor_mode
				+ "'."
		)


static func _validate_workplace_work_location_policy(
	errors: Array[String],
	object_id: int,
	policy: Dictionary
) -> void:
	var mode := _get_workplace_policy_mode(
		errors,
		object_id,
		"work_location_policy",
		policy
	)

	if mode.is_empty():
		return

	if not WorldData.is_valid_workplace_work_location_mode(mode):
		errors.append(
			"Workplace "
				+ str(object_id)
				+ " has unknown work_location_policy mode '"
				+ mode
				+ "'."
		)


static func _validate_workplace_movement_policy(
	errors: Array[String],
	object_id: int,
	policy: Dictionary
) -> void:
	var mode := _get_workplace_policy_mode(
		errors,
		object_id,
		"work_movement_policy",
		policy
	)

	if mode.is_empty():
		return

	if not WorldData.is_valid_workplace_movement_mode(mode):
		errors.append(
			"Workplace "
				+ str(object_id)
				+ " has unknown work_movement_policy mode '"
				+ mode
				+ "'."
		)


static func _validate_workplace_break_location_policy(
	errors: Array[String],
	object_id: int,
	policy: Dictionary
) -> void:
	var mode := _get_workplace_policy_mode(
		errors,
		object_id,
		"break_location_policy",
		policy
	)

	if mode.is_empty():
		return

	if not WorldData.is_valid_workplace_break_location_mode(mode):
		errors.append(
			"Workplace "
				+ str(object_id)
				+ " has unknown break_location_policy mode '"
				+ mode
				+ "'."
		)
		return

	if mode == WorldData.WORKPLACE_BREAK_LOCATION_MODE_FOOTPRINT_RADIUS:
		_validate_positive_workplace_policy_integer(
			errors,
			object_id,
			"break_location_policy",
			policy,
			"radius_tiles"
		)


static func _validate_workplace_overflow_policy(
	errors: Array[String],
	object_id: int,
	policy: Dictionary
) -> void:
	var mode := _get_workplace_policy_mode(
		errors,
		object_id,
		"overflow_policy",
		policy
	)

	if mode.is_empty():
		return

	if not WorldData.is_valid_workplace_overflow_mode(mode):
		errors.append(
			"Workplace "
				+ str(object_id)
				+ " has unknown overflow_policy mode '"
				+ mode
				+ "'."
		)
		return

	if mode == WorldData.WORKPLACE_OVERFLOW_MODE_FOOTPRINT_RADIUS:
		_validate_positive_workplace_policy_integer(
			errors,
			object_id,
			"overflow_policy",
			policy,
			"radius_tiles"
		)


static func _get_workplace_policy_mode(
	errors: Array[String],
	object_id: int,
	policy_name: String,
	policy: Dictionary
) -> String:
	if not policy.has("mode"):
		errors.append(
			"Workplace "
				+ str(object_id)
				+ " "
				+ policy_name
				+ " is missing mode."
		)
		return ""

	var raw_mode = policy["mode"]

	if typeof(raw_mode) != TYPE_STRING:
		errors.append(
			"Workplace "
				+ str(object_id)
				+ " "
				+ policy_name
				+ " has non-String mode."
		)
		return ""

	return str(raw_mode)


static func _validate_known_workplace_policy_resource(
	errors: Array[String],
	object_id: int,
	policy_name: String,
	policy: Dictionary,
	field_name: String
) -> void:
	if not policy.has(field_name):
		errors.append(
			"Workplace "
				+ str(object_id)
				+ " "
				+ policy_name
				+ " is missing "
				+ field_name
				+ "."
		)
		return

	var raw_resource = policy[field_name]

	if typeof(raw_resource) != TYPE_STRING:
		errors.append(
			"Workplace "
				+ str(object_id)
				+ " "
				+ policy_name
				+ " has non-String "
				+ field_name
				+ "."
		)
		return

	var resource: String = raw_resource

	if not WorldData.get_city_resource_types().has(resource):
		errors.append(
			"Workplace "
				+ str(object_id)
				+ " "
				+ policy_name
				+ " has unknown "
				+ field_name
				+ " '"
				+ resource
				+ "'."
		)


static func _validate_positive_workplace_policy_integer(
	errors: Array[String],
	object_id: int,
	policy_name: String,
	policy: Dictionary,
	field_name: String
) -> void:
	if not policy.has(field_name):
		errors.append(
			"Workplace "
				+ str(object_id)
				+ " "
				+ policy_name
				+ " is missing "
				+ field_name
				+ "."
		)
		return

	var raw_value = policy[field_name]

	if typeof(raw_value) != TYPE_INT:
		errors.append(
			"Workplace "
				+ str(object_id)
				+ " "
				+ policy_name
				+ " has non-integer "
				+ field_name
				+ "."
		)
		return

	if int(raw_value) <= 0:
		errors.append(
			"Workplace "
				+ str(object_id)
				+ " "
				+ policy_name
				+ " has non-positive "
				+ field_name
				+ " "
				+ str(raw_value)
				+ "."
		)


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
