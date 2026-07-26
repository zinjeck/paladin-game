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
	var ground_pile_lookup := _validate_city_ground_pile_state(errors)

	_validate_city_foundation_state(
		errors,
		warnings,
		object_lookup
	)

	_validate_city_occupancy(
		errors,
		object_lookup
	)

	_validate_city_citizen_spatial_state(
		errors,
		citizen_lookup
	)

	_validate_city_citizen_demographics(
		errors,
		citizen_lookup
	)
	_validate_city_citizen_need_state(
		errors,
		citizen_lookup
	)
	_validate_city_citizen_task_state(
		errors,
		citizen_lookup,
		object_lookup
	)
	var checked_haul_reservation_count := (
		_validate_city_haul_reservations(
			errors,
			citizen_lookup,
			ground_pile_lookup
		)
	)
	_validate_city_citizen_movement_state(
		errors,
		citizen_lookup
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
		"checked_ground_piles": ground_pile_lookup.size(),
		"checked_haul_reservations": checked_haul_reservation_count,
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
		"ground_pile_version": WorldData.city_ground_pile_version,
		"haul_reservation_version": (
			WorldData.city_haul_reservation_version
		)
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
		!= WorldData.city_ground_pile_version
	):
		return false

	if (
		int(
			_cached_result.get(
				"haul_reservation_version",
				-1
			)
		)
		!= WorldData.city_haul_reservation_version
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

static func _validate_city_ground_pile_state(
	errors: Array[String]
) -> Dictionary:
	var ground_pile_lookup: Dictionary = {}
	var tile_resource_lookup: Dictionary = {}
	var maximum_ground_pile_id := 0

	for pile_index in range(WorldData.city_ground_piles.size()):
		var raw_ground_pile = WorldData.city_ground_piles[pile_index]

		if not raw_ground_pile is Dictionary:
			errors.append(
				"city_ground_piles["
				+ str(pile_index)
				+ "] is not a Dictionary."
			)
			continue

		var ground_pile: Dictionary = raw_ground_pile
		var ground_pile_id := int(ground_pile.get("id", -1))
		var raw_tile_position = ground_pile.get(
			"tile_position",
			WorldData.INVALID_CITY_TILE_POSITION
		)
		var resource := str(
			ground_pile.get("resource_type", WorldData.RESOURCE_NONE)
		)
		var raw_amount = ground_pile.get("amount")

		if ground_pile_id <= 0:
			errors.append(
				"Ground pile at index "
				+ str(pile_index)
				+ " has invalid ID "
				+ str(ground_pile_id)
				+ "."
			)
			continue

		if ground_pile_lookup.has(ground_pile_id):
			errors.append(
				"Duplicate ground pile ID "
				+ str(ground_pile_id)
				+ "."
			)
			continue

		ground_pile_lookup[ground_pile_id] = pile_index
		maximum_ground_pile_id = maxi(
			maximum_ground_pile_id,
			ground_pile_id
		)

		if not raw_tile_position is Vector2i:
			errors.append(
				"Ground pile "
				+ str(ground_pile_id)
				+ " has a non-Vector2i tile."
			)
		else:
			var tile_position: Vector2i = raw_tile_position
			var tile_resource_key := (
				str(tile_position) + ":" + resource
			)

			if tile_resource_lookup.has(tile_resource_key):
				errors.append(
					"Ground piles "
					+ str(tile_resource_lookup[tile_resource_key])
					+ " and "
					+ str(ground_pile_id)
					+ " should have merged on tile "
					+ str(tile_position)
					+ " for "
					+ resource
					+ "."
				)
			else:
				tile_resource_lookup[tile_resource_key] = (
					ground_pile_id
				)

			if (
				WorldData.official_city_world != null
				and not WorldData.can_city_ground_pile_exist_at_tile(
					WorldData.official_city_world,
					tile_position
				)
			):
				errors.append(
					"Ground pile "
					+ str(ground_pile_id)
					+ " occupies invalid tile "
					+ str(tile_position)
					+ "."
				)

		if not WorldData.is_city_resource_type(resource):
			errors.append(
				"Ground pile "
				+ str(ground_pile_id)
				+ " has invalid resource '"
				+ resource
				+ "'."
			)

		if typeof(raw_amount) != TYPE_INT or int(raw_amount) <= 0:
			errors.append(
				"Ground pile "
				+ str(ground_pile_id)
				+ " has invalid amount "
				+ str(raw_amount)
				+ "."
			)

		if int(
			WorldData.city_ground_pile_index_by_id.get(
				ground_pile_id,
				-1
			)
		) != pile_index:
			errors.append(
				"Ground pile index lookup disagrees for ID "
				+ str(ground_pile_id)
				+ "."
			)

	if (
		WorldData.city_ground_pile_index_by_id.size()
		!= ground_pile_lookup.size()
	):
		errors.append(
			"Ground pile registry array and ID lookup have different sizes."
		)

	if WorldData.next_city_ground_pile_id <= maximum_ground_pile_id:
		errors.append(
			"next_city_ground_pile_id must be greater than every existing pile ID."
		)

	return ground_pile_lookup


static func _validate_city_haul_reservations(
	errors: Array[String],
	citizen_lookup: Dictionary,
	ground_pile_lookup: Dictionary
) -> int:
	var expected_citizen_lookup: Dictionary = {}
	var expected_source_amount_by_key: Dictionary = {}
	var expected_destination_amount_by_key: Dictionary = {}
	var source_endpoint_by_key: Dictionary = {}
	var source_resource_by_key: Dictionary = {}
	var destination_endpoint_by_key: Dictionary = {}
	var maximum_reservation_id := 0

	for raw_reservation_id in WorldData.city_haul_reservations.keys():
		if typeof(raw_reservation_id) != TYPE_INT:
			errors.append(
				"Haul reservation ledger contains a non-integer key."
			)
			continue

		var reservation_id: int = raw_reservation_id
		var raw_reservation = WorldData.city_haul_reservations[
			reservation_id
		]

		if not raw_reservation is Dictionary:
			errors.append(
				"Haul reservation "
				+ str(reservation_id)
				+ " is not a Dictionary."
			)
			continue

		var reservation: Dictionary = raw_reservation
		var stored_reservation_id := int(
			reservation.get("id", -1)
		)
		var citizen_id := int(reservation.get("citizen_id", -1))
		var resource := str(
			reservation.get("resource_type", WorldData.RESOURCE_NONE)
		)
		var raw_source = reservation.get("source", {})
		var raw_destination = reservation.get("destination", {})
		var raw_source_reserved_amount = reservation.get(
			"source_reserved_amount",
			0
		)
		var raw_destination_reserved_amount = reservation.get(
			"destination_reserved_amount",
			0
		)
		var source_reserved_amount := maxi(
			int(raw_source_reserved_amount),
			0
		)
		var destination_reserved_amount := maxi(
			int(raw_destination_reserved_amount),
			0
		)

		maximum_reservation_id = maxi(
			maximum_reservation_id,
			reservation_id
		)

		if reservation_id <= 0 or stored_reservation_id != reservation_id:
			errors.append(
				"Haul reservation key/ID mismatch for "
				+ str(reservation_id)
				+ "."
			)

		if (
			typeof(raw_source_reserved_amount) != TYPE_INT
			or int(raw_source_reserved_amount) < 0
		):
			errors.append(
				"Haul reservation "
				+ str(reservation_id)
				+ " has invalid source reserved amount."
			)

		if (
			typeof(raw_destination_reserved_amount) != TYPE_INT
			or int(raw_destination_reserved_amount) < 0
		):
			errors.append(
				"Haul reservation "
				+ str(reservation_id)
				+ " has invalid destination reserved amount."
			)

		if not citizen_lookup.has(citizen_id):
			errors.append(
				"Haul reservation "
				+ str(reservation_id)
				+ " references missing citizen "
				+ str(citizen_id)
				+ "."
			)
			continue

		if expected_citizen_lookup.has(citizen_id):
			errors.append(
				"Citizen "
				+ str(citizen_id)
				+ " owns multiple haul reservations."
			)
		else:
			expected_citizen_lookup[citizen_id] = reservation_id

		if not WorldData.is_city_resource_type(resource):
			errors.append(
				"Haul reservation "
				+ str(reservation_id)
				+ " has invalid resource '"
				+ resource
				+ "'."
			)

		if not raw_source is Dictionary or not raw_destination is Dictionary:
			errors.append(
				"Haul reservation "
				+ str(reservation_id)
				+ " has invalid endpoint data."
			)
			continue

		var source: Dictionary = raw_source
		var destination: Dictionary = raw_destination
		var source_is_valid := (
			CityCitizens.is_valid_city_citizen_haul_endpoint(source)
		)
		var destination_is_valid := (
			CityCitizens.is_valid_city_citizen_haul_endpoint(
				destination,
				destination_reserved_amount <= 0
			)
		)

		if not source_is_valid:
			errors.append(
				"Haul reservation "
				+ str(reservation_id)
				+ " has invalid source endpoint."
			)

		if not destination_is_valid:
			errors.append(
				"Haul reservation "
				+ str(reservation_id)
				+ " has invalid destination endpoint."
			)

		var citizen := WorldData.get_city_citizen_by_id(citizen_id)
		var current_task := WorldData.get_city_citizen_current_task(
			citizen_id
		)
		var current_haul := WorldData.get_city_citizen_current_haul(
			citizen_id
		)
		var cargo_amount := WorldData.get_city_citizen_haul_cargo_amount(
			citizen_id
		)

		if not bool(citizen.get("alive", false)):
			errors.append(
				"Dead citizen "
				+ str(citizen_id)
				+ " owns haul reservation "
				+ str(reservation_id)
				+ "."
			)

		if (
			str(current_task.get("kind", ""))
			!= WorldData.CITY_CITIZEN_TASK_KIND_HAUL
		):
			errors.append(
				"Haul reservation "
				+ str(reservation_id)
				+ " exists without an active haul task."
			)

		if int(
			current_haul.get(
				"reservation_id",
				WorldData.INVALID_CITY_CITIZEN_HAUL_RESERVATION_ID
			)
		) != reservation_id:
			errors.append(
				"Citizen "
				+ str(citizen_id)
				+ " haul state does not point to reservation "
				+ str(reservation_id)
				+ "."
			)

		if str(
			current_haul.get(
				"resource_type",
				WorldData.RESOURCE_NONE
			)
		) != resource:
			errors.append(
				"Citizen "
				+ str(citizen_id)
				+ " haul resource does not match reservation "
				+ str(reservation_id)
				+ "."
			)

		var raw_current_source = current_haul.get("source", {})

		if (
			not raw_current_source is Dictionary
			or _get_validation_endpoint_key(raw_current_source)
			!= _get_validation_endpoint_key(source)
		):
			errors.append(
				"Citizen "
				+ str(citizen_id)
				+ " haul source does not match reservation "
				+ str(reservation_id)
				+ "."
			)

		if (
			source_reserved_amount <= 0
			and destination_reserved_amount <= 0
			and (
				cargo_amount <= 0
				or str(
					current_haul.get(
						"phase",
						WorldData.CITY_CITIZEN_HAUL_PHASE_NONE
					)
				) not in [
					WorldData.CITY_CITIZEN_HAUL_PHASE_RETARGETING,
					WorldData.CITY_CITIZEN_HAUL_PHASE_PENDING_DESTINATION,
				]
			)
		):
			errors.append(
				"Haul reservation "
				+ str(reservation_id)
				+ " reserves neither source goods nor destination capacity."
			)

		if source_reserved_amount > 0 and cargo_amount > 0:
			errors.append(
				"Haul reservation "
				+ str(reservation_id)
				+ " reserves source goods after cargo was picked up."
			)

		if (
			source_reserved_amount > 0
			and source_reserved_amount != destination_reserved_amount
		):
			errors.append(
				"Pre-pickup haul reservation "
				+ str(reservation_id)
				+ " has unequal source and destination amounts."
			)

		if (
			source_reserved_amount > 0
			and int(current_haul.get("requested_amount", 0))
			!= source_reserved_amount
		):
			errors.append(
				"Pre-pickup haul reservation "
				+ str(reservation_id)
				+ " disagrees with the haul's requested amount."
			)

		if (
			cargo_amount > 0
			and destination_reserved_amount > cargo_amount
		):
			errors.append(
				"Haul reservation "
				+ str(reservation_id)
				+ " reserves more destination space than citizen cargo."
			)

		if source_reserved_amount > 0:
			if not _city_haul_endpoint_exists(
				source,
				ground_pile_lookup
			):
				errors.append(
					"Haul reservation "
					+ str(reservation_id)
					+ " reserves a missing source endpoint."
				)

			if not WorldData.city_haul_endpoint_can_provide_resource(
				source,
				resource,
				str(
					reservation.get(
						"source_access_purpose",
						WorldData.CONTAINER_HAUL_PURPOSE_NONE
					)
				),
				false,
				reservation_id
			):
				errors.append(
					"Haul reservation "
					+ str(reservation_id)
					+ " has an incompatible source endpoint or purpose."
				)

			var source_key := _get_validation_source_key(
				source,
				resource
			)
			expected_source_amount_by_key[source_key] = (
				int(expected_source_amount_by_key.get(source_key, 0))
				+ source_reserved_amount
			)
			source_endpoint_by_key[source_key] = source
			source_resource_by_key[source_key] = resource

		if destination_reserved_amount > 0:
			if (
				str(
					destination.get(
						"kind",
						WorldData.CITY_CITIZEN_HAUL_ENDPOINT_KIND_NONE
					)
				)
				!= WorldData
				.CITY_CITIZEN_HAUL_ENDPOINT_KIND_CITY_OBJECT_CONTAINER
				or WorldData.get_city_object_by_id(
					int(destination.get("id", -1))
				).is_empty()
			):
				errors.append(
					"Haul reservation "
					+ str(reservation_id)
					+ " reserves missing or non-object destination capacity."
				)

			var raw_current_destination = current_haul.get(
				"destination",
				{}
			)

			if (
				not raw_current_destination is Dictionary
				or _get_validation_endpoint_key(raw_current_destination)
				!= _get_validation_endpoint_key(destination)
			):
				errors.append(
					"Citizen "
					+ str(citizen_id)
					+ " haul destination does not match reservation "
					+ str(reservation_id)
					+ "."
				)

			var destination_object := WorldData.get_city_object_by_id(
				int(destination.get("id", -1))
			)

			var destination_access_purpose := str(
				reservation.get(
					"destination_access_purpose",
					WorldData.CONTAINER_HAUL_PURPOSE_NONE
				)
			)
			var destination_policy_is_valid := (
				WorldData.city_haul_endpoint_can_accept_resource(
					destination,
					resource,
					destination_access_purpose,
					false,
					reservation_id
				)
			)

			if (
				destination_access_purpose
				== WorldData.CONTAINER_HAUL_PURPOSE_PUBLIC_STORAGE
				and WorldData.get_city_object_public_storage_tier(
					destination_object
				)
				== WorldData.PUBLIC_CITY_STORAGE_TIER_NONE
			):
				destination_policy_is_valid = false
			elif (
				destination_access_purpose
				== WorldData.CONTAINER_HAUL_PURPOSE_HOME_DELIVERY
				and not WorldData.city_object_is_household_home(
					destination_object
				)
			):
				destination_policy_is_valid = false

			if not destination_policy_is_valid:
				errors.append(
					"Haul reservation "
					+ str(reservation_id)
					+ " has an incompatible destination or purpose."
				)

			var destination_key := _get_validation_endpoint_key(
				destination
			)
			expected_destination_amount_by_key[destination_key] = (
				int(
					expected_destination_amount_by_key.get(
						destination_key,
						0
					)
				)
				+ destination_reserved_amount
			)
			destination_endpoint_by_key[destination_key] = destination

	for source_key in expected_source_amount_by_key.keys():
		var source: Dictionary = source_endpoint_by_key[source_key]
		var resource: String = source_resource_by_key[source_key]
		var reserved_amount := int(
			expected_source_amount_by_key[source_key]
		)

		if (
			reserved_amount
			> WorldData.get_city_haul_endpoint_resource_amount(
				source,
				resource
			)
		):
			errors.append(
				"Source reservations exceed physical "
				+ resource
				+ " at "
				+ str(source)
				+ "."
			)

	for destination_key in expected_destination_amount_by_key.keys():
		var destination: Dictionary = (
			destination_endpoint_by_key[destination_key]
		)
		var city_object := WorldData.get_city_object_by_id(
			int(destination.get("id", -1))
		)
		var reserved_amount := int(
			expected_destination_amount_by_key[destination_key]
		)

		if (
			not city_object.is_empty()
			and reserved_amount
			> WorldData.get_city_object_storage_free_space(city_object)
		):
			errors.append(
				"Destination reservations exceed shared free capacity at "
				+ str(destination)
				+ "."
			)

	if (
		WorldData.city_haul_reservation_id_by_citizen_id
		!= expected_citizen_lookup
	):
		errors.append(
			"Haul reservation citizen lookup does not match the ledger."
		)

	if (
		WorldData.city_haul_source_reserved_amount_by_key
		!= expected_source_amount_by_key
	):
		errors.append(
			"Haul source reservation aggregate does not match the ledger."
		)

	if (
		WorldData.city_haul_destination_reserved_amount_by_key
		!= expected_destination_amount_by_key
	):
		errors.append(
			"Haul destination reservation aggregate does not match the ledger."
		)

	if WorldData.next_city_haul_reservation_id <= maximum_reservation_id:
		errors.append(
			"next_city_haul_reservation_id must exceed every reservation ID."
		)

	return WorldData.city_haul_reservations.size()


static func _city_haul_endpoint_exists(
	endpoint: Dictionary,
	ground_pile_lookup: Dictionary
) -> bool:
	match str(
		endpoint.get(
			"kind",
			WorldData.CITY_CITIZEN_HAUL_ENDPOINT_KIND_NONE
		)
	):
		WorldData.CITY_CITIZEN_HAUL_ENDPOINT_KIND_CITY_OBJECT_CONTAINER:
			return not WorldData.get_city_object_by_id(
				int(endpoint.get("id", -1))
			).is_empty()

		WorldData.CITY_CITIZEN_HAUL_ENDPOINT_KIND_GROUND_PILE:
			return ground_pile_lookup.has(
				int(endpoint.get("id", -1))
			)

	return false


static func _get_validation_endpoint_key(
	endpoint: Dictionary
) -> String:
	return (
		str(
			endpoint.get(
				"kind",
				WorldData.CITY_CITIZEN_HAUL_ENDPOINT_KIND_NONE
			)
		)
		+ ":"
		+ str(int(endpoint.get("id", -1)))
	)


static func _get_validation_source_key(
	endpoint: Dictionary,
	resource: String
) -> String:
	return _get_validation_endpoint_key(endpoint) + ":" + resource


static func _validate_city_citizen_spatial_state(
	errors: Array[String],
	citizen_lookup: Dictionary
) -> void:
	if citizen_lookup.is_empty():
		if not (
			WorldData
			.city_citizen_ids_by_tile
			.is_empty()
		):
			errors.append(
				"Citizen spatial index contains entries "
				+ "despite the city having no citizens."
			)

		return

	var city_world = WorldData.official_city_world

	if city_world == null:
		errors.append(
			"Citizens exist without an official city world."
		)
		return

	for citizen_id in citizen_lookup.keys():
		var citizen_index := int(
			citizen_lookup[citizen_id]
		)
		var citizen: Dictionary = (
			WorldData.city_citizens[
				citizen_index
			]
		)

		if not citizen.has("city_tile_position"):
			errors.append(
				"Citizen "
				+ str(citizen_id)
				+ " is missing city_tile_position."
			)
			continue

		var raw_position = citizen.get(
			"city_tile_position"
		)

		if not raw_position is Vector2i:
			errors.append(
				"Citizen "
				+ str(citizen_id)
				+ " has a non-Vector2i city position."
			)
			continue

		var tile_position: Vector2i = (
			raw_position
		)

		if (
			tile_position
			== WorldData.INVALID_CITY_TILE_POSITION
		):
			errors.append(
				"Citizen "
				+ str(citizen_id)
				+ " has an invalid city position."
			)
			continue

		if not city_world.is_in_bounds(
			tile_position.x,
			tile_position.y
		):
			errors.append(
				"Citizen "
				+ str(citizen_id)
				+ " is outside the city at "
				+ str(tile_position)
				+ "."
			)
		elif (
			bool(citizen.get("alive", true))
			and not (
				WorldData
				.is_city_tile_walkable_for_citizen(
					city_world,
					tile_position,
					int(citizen_id)
				)
			)
		):
			errors.append(
				"Living citizen "
				+ str(citizen_id)
				+ " occupies non-walkable tile "
				+ str(tile_position)
				+ "."
			)

		if not (
			WorldData.city_citizen_ids_by_tile.has(
				tile_position
			)
		):
			errors.append(
				"Citizen "
				+ str(citizen_id)
				+ " is missing from the spatial index "
				+ "at "
				+ str(tile_position)
				+ "."
			)
			continue

		var raw_indexed_ids = (
			WorldData.city_citizen_ids_by_tile[
				tile_position
			]
		)

		if not raw_indexed_ids is Array:
			errors.append(
				"Citizen spatial index entry at "
				+ str(tile_position)
				+ " is not an Array."
			)
		elif not raw_indexed_ids.has(
			int(citizen_id)
		):
			errors.append(
				"Citizen "
				+ str(citizen_id)
				+ " is absent from its spatial-index tile "
				+ str(tile_position)
				+ "."
			)

	for raw_tile_position in (
		WorldData.city_citizen_ids_by_tile.keys()
	):
		if not raw_tile_position is Vector2i:
			errors.append(
				"Citizen spatial index contains "
				+ "a non-Vector2i tile key."
			)
			continue

		var tile_position: Vector2i = (
			raw_tile_position
		)
		var raw_citizen_ids = (
			WorldData.city_citizen_ids_by_tile[
				tile_position
			]
		)

		if not raw_citizen_ids is Array:
			errors.append(
				"Citizen spatial index entry at "
				+ str(tile_position)
				+ " is not an Array."
			)
			continue

		if raw_citizen_ids.is_empty():
			errors.append(
				"Citizen spatial index contains "
				+ "an empty entry at "
				+ str(tile_position)
				+ "."
			)
			continue

		var local_citizen_ids: Dictionary = {}

		for raw_citizen_id in raw_citizen_ids:
			if typeof(raw_citizen_id) != TYPE_INT:
				errors.append(
					"Citizen spatial index at "
						+ str(tile_position)
						+ " contains a non-integer ID."
				)
				continue

			var citizen_id: int = raw_citizen_id

			if local_citizen_ids.has(citizen_id):
				errors.append(
					"Citizen "
						+ str(citizen_id)
						+ " appears more than once at "
						+ str(tile_position)
						+ " in the spatial index."
				)
				continue

			local_citizen_ids[citizen_id] = true

			if not citizen_lookup.has(citizen_id):
				errors.append(
					"Citizen spatial index at "
						+ str(tile_position)
						+ " references missing citizen "
						+ str(citizen_id)
						+ "."
				)
				continue

			var citizen_index := int(
				citizen_lookup[citizen_id]
			)
			var citizen: Dictionary = (
				WorldData.city_citizens[
					citizen_index
				]
			)
			var indexed_position = citizen.get(
				"city_tile_position",
				WorldData.INVALID_CITY_TILE_POSITION
			)

			if indexed_position != tile_position:
				errors.append(
					"Citizen "
						+ str(citizen_id)
						+ " is indexed at "
						+ str(tile_position)
						+ " but stores position "
						+ str(indexed_position)
						+ "."
				)

static func _validate_city_citizen_name_pool(
	errors: Array[String],
	pool_display_name: String,
	expected_sex: String,
	name_pool: Array,
	global_name_owners: Dictionary
) -> void:
	if name_pool.is_empty():
		errors.append(
			pool_display_name
			+ " name pool is empty."
		)
		return

	var local_name_lookup: Dictionary = {}

	for raw_name in name_pool:
		if typeof(raw_name) != TYPE_STRING:
			errors.append(
				pool_display_name
				+ " name pool contains "
				+ "a non-string entry."
			)
			continue

		var raw_name_string: String = raw_name
		var clean_name := (
			raw_name_string.strip_edges()
		)
		var name_key := clean_name.to_lower()

		if clean_name.is_empty():
			errors.append(
				pool_display_name
				+ " name pool contains "
				+ "an empty name."
			)
			continue

		if clean_name != raw_name_string:
			errors.append(
				pool_display_name
				+ " name '"
				+ raw_name_string
				+ "' contains surrounding whitespace."
			)

		if local_name_lookup.has(name_key):
			errors.append(
				pool_display_name
				+ " name pool contains duplicate name '"
				+ clean_name
				+ "'."
			)
			continue

		local_name_lookup[name_key] = true

		if global_name_owners.has(name_key):
			errors.append(
				"Name '"
				+ clean_name
				+ "' appears in both the "
				+ str(global_name_owners[name_key])
				+ " and "
				+ expected_sex
				+ " name pools."
			)
			continue

		global_name_owners[name_key] = expected_sex


static func _validate_city_citizen_demographics(
	errors: Array[String],
	citizen_lookup: Dictionary
) -> void:
	var global_name_owners: Dictionary = {}

	_validate_city_citizen_name_pool(
		errors,
		"Male",
		WorldData.CITY_CITIZEN_SEX_MALE,
		WorldData.city_citizen_male_name_pool,
		global_name_owners
	)

	_validate_city_citizen_name_pool(
		errors,
		"Female",
		WorldData.CITY_CITIZEN_SEX_FEMALE,
		WorldData.city_citizen_female_name_pool,
		global_name_owners
	)

	if not (
		WorldData
		.city_citizen_unassigned_name_pool
		.is_empty()
	):
		errors.append(
			"Citizen unassigned-name pool still contains "
			+ str(
				WorldData
				.city_citizen_unassigned_name_pool
				.size()
			)
			+ " names."
		)

	var male_count := 0
	var female_count := 0

	for citizen_id in citizen_lookup.keys():
		var citizen_index := int(
			citizen_lookup[citizen_id]
		)
		var citizen: Dictionary = (
			WorldData.city_citizens[
				citizen_index
			]
		)

		if not citizen.has("sex"):
			errors.append(
				"Citizen "
				+ str(citizen_id)
				+ " is missing sex."
			)
			continue

		var raw_sex = citizen.get("sex")

		if typeof(raw_sex) != TYPE_STRING:
			errors.append(
				"Citizen "
				+ str(citizen_id)
				+ " has non-string sex data."
			)
			continue

		var citizen_sex := (
			WorldData.normalize_city_citizen_sex(
				raw_sex
			)
		)

		if not WorldData.is_valid_city_citizen_sex(
			citizen_sex
		):
			errors.append(
				"Citizen "
				+ str(citizen_id)
				+ " has invalid sex '"
				+ str(raw_sex)
				+ "'."
			)
			continue

		if citizen_sex == WorldData.CITY_CITIZEN_SEX_MALE:
			male_count += 1
		else:
			female_count += 1

		var citizen_name := str(
			citizen.get("name", "")
		).strip_edges()
		var expected_name_pool := (
			WorldData.get_city_citizen_name_pool_for_sex(
				citizen_sex
			)
		)

		if citizen_name.is_empty():
			errors.append(
				"Citizen "
					+ str(citizen_id)
					+ " has an empty name."
			)
		elif not expected_name_pool.has(citizen_name):
			errors.append(
				"Citizen "
					+ str(citizen_id)
					+ " named '"
					+ citizen_name
					+ "' is absent from the "
					+ citizen_sex
					+ " name pool."
			)

	if (
		WorldData.player_city_founded
		and (
			WorldData.city_citizens.size()
			== WorldData.STARTING_CITY_POPULATION
		)
		and (
			WorldData.next_city_citizen_id
			== WorldData.STARTING_CITY_POPULATION + 1
		)
	):
		if (
			male_count
			!= WorldData.STARTING_CITY_MALE_POPULATION
			or female_count
			!= WorldData.STARTING_CITY_FEMALE_POPULATION
		):
			errors.append(
				"Founding population must contain "
					+ str(
						WorldData
						.STARTING_CITY_MALE_POPULATION
					)
					+ " male and "
					+ str(
						WorldData
						.STARTING_CITY_FEMALE_POPULATION
					)
					+ " female citizens, but contains "
					+ str(male_count)
					+ " male and "
					+ str(female_count)
					+ " female citizens."
			)


static func _validate_city_citizen_need_state(
	errors: Array[String],
	citizen_lookup: Dictionary
) -> void:
	for citizen_id in citizen_lookup.keys():
		var citizen_index := int(citizen_lookup[citizen_id])
		var citizen: Dictionary = WorldData.city_citizens[citizen_index]

		if not CityCitizens.has_complete_city_citizen_need_state(citizen):
			errors.append(
				"Citizen "
				+ str(citizen_id)
				+ " has incomplete need state."
			)
			continue

		var raw_hunger = citizen.get("hunger")
		var raw_hunger_remainder = citizen.get("hunger_decay_remainder")

		if (
			typeof(raw_hunger) != TYPE_INT
			or int(raw_hunger) < 0
			or int(raw_hunger) > WorldData.MAX_CITIZEN_HUNGER
		):
			errors.append(
				"Citizen "
				+ str(citizen_id)
				+ " has out-of-range hunger state."
			)

		if (
			typeof(raw_hunger_remainder) != TYPE_INT
			or int(raw_hunger_remainder) < 0
			or int(raw_hunger_remainder)
			>= WorldData.CITIZEN_HUNGER_DECAY_DENOMINATOR_MINUTES
		):
			errors.append(
				"Citizen "
				+ str(citizen_id)
				+ " has invalid hunger-decay remainder."
			)

	for resource in WorldData.get_city_food_resource_types():
		if (
			not WorldData.is_city_resource_type(resource)
			or WorldData.get_city_food_hunger_restore(resource) <= 0
		):
			errors.append(
				"Food configuration contains invalid resource '"
				+ resource
				+ "'."
			)


static func _validate_city_citizen_task_state(
	errors: Array[String],
	citizen_lookup: Dictionary,
	object_lookup: Dictionary
) -> void:
	var required_task_fields: Array[String] = [
		"kind",
		"source",
		"phase",
		"priority",
		"target_object_id",
		"start_world_minute",
		"target_tile",
		"previous_target_tile",
		"next_action_world_minute",
		"relocation_count",
		"player_locked"
	]
	var expected_active_task_ids: Array[int] = []

	for raw_citizen_id in citizen_lookup.keys():
		var citizen_id: int = raw_citizen_id
		var citizen_index := int(
			citizen_lookup[citizen_id]
		)
		var citizen: Dictionary = (
			WorldData.city_citizens[citizen_index]
		)

		if not citizen.has("current_task"):
			errors.append(
				"Citizen "
				+ str(citizen_id)
				+ " is missing current_task."
			)
			continue

		var raw_current_task = citizen.get("current_task")

		if not raw_current_task is Dictionary:
			errors.append(
				"Citizen "
				+ str(citizen_id)
				+ " has a non-Dictionary current_task."
			)
			continue

		var current_task: Dictionary = raw_current_task
		var missing_task_field := false

		for task_field in required_task_fields:
			if current_task.has(task_field):
				continue

			errors.append(
				"Citizen "
				+ str(citizen_id)
				+ " current_task is missing '"
				+ task_field
				+ "'."
			)
			missing_task_field = true

		if missing_task_field:
			continue

		var raw_task_kind = current_task.get("kind")
		var raw_task_source = current_task.get("source")
		var raw_task_phase = current_task.get("phase")
		var raw_task_priority = current_task.get("priority")
		var raw_target_object_id = current_task.get(
			"target_object_id"
		)
		var raw_start_world_minute = current_task.get(
			"start_world_minute"
		)
		var raw_target_tile = current_task.get(
			"target_tile"
		)
		var raw_previous_target_tile = current_task.get(
			"previous_target_tile"
		)
		var raw_next_action_world_minute = current_task.get(
			"next_action_world_minute"
		)
		var raw_relocation_count = current_task.get(
			"relocation_count"
		)
		var raw_player_locked = current_task.get(
			"player_locked"
		)
		var task_types_are_valid := true

		if typeof(raw_task_kind) != TYPE_STRING:
			errors.append(
				"Citizen "
				+ str(citizen_id)
				+ " has a non-string task kind."
			)
			task_types_are_valid = false

		if typeof(raw_task_source) != TYPE_STRING:
			errors.append(
				"Citizen "
				+ str(citizen_id)
				+ " has a non-string task source."
			)
			task_types_are_valid = false

		if typeof(raw_task_phase) != TYPE_STRING:
			errors.append(
				"Citizen "
				+ str(citizen_id)
				+ " has a non-string task phase."
			)
			task_types_are_valid = false

		if typeof(raw_task_priority) != TYPE_INT:
			errors.append(
				"Citizen "
				+ str(citizen_id)
				+ " has a non-integer task priority."
			)
			task_types_are_valid = false

		if typeof(raw_target_object_id) != TYPE_INT:
			errors.append(
				"Citizen "
				+ str(citizen_id)
				+ " has a non-integer task target object ID."
			)
			task_types_are_valid = false

		if typeof(raw_start_world_minute) != TYPE_INT:
			errors.append(
				"Citizen "
				+ str(citizen_id)
				+ " has a non-integer task start minute."
			)
			task_types_are_valid = false
		if not raw_target_tile is Vector2i:
			errors.append(
				"Citizen "
				+ str(citizen_id)
				+ " has a non-Vector2i task target tile."
			)
			task_types_are_valid = false

		if not raw_previous_target_tile is Vector2i:
			errors.append(
				"Citizen "
				+ str(citizen_id)
				+ " has a non-Vector2i previous task target tile."
			)
			task_types_are_valid = false

		if typeof(raw_next_action_world_minute) != TYPE_INT:
			errors.append(
				"Citizen "
				+ str(citizen_id)
				+ " has a non-integer next task action minute."
			)
			task_types_are_valid = false
		if typeof(raw_relocation_count) != TYPE_INT:
			errors.append(
				"Citizen "
				+ str(citizen_id)
				+ " has a non-integer task relocation count."
			)
			task_types_are_valid = false
		if typeof(raw_player_locked) != TYPE_BOOL:
			errors.append(
				"Citizen "
				+ str(citizen_id)
				+ " has a non-boolean task player lock."
			)
			task_types_are_valid = false

		if not task_types_are_valid:
			continue

		var task_kind: String = raw_task_kind
		var task_source: String = raw_task_source
		var task_phase: String = raw_task_phase
		var task_priority: int = raw_task_priority
		var target_object_id: int = raw_target_object_id
		var start_world_minute: int = raw_start_world_minute
		var player_locked: bool = raw_player_locked
		var task_values_are_valid := true

		if not WorldData.is_valid_city_citizen_task_kind(
			task_kind
		):
			errors.append(
				"Citizen "
				+ str(citizen_id)
				+ " has invalid task kind '"
				+ task_kind
				+ "'."
			)
			task_values_are_valid = false

		if not WorldData.is_valid_city_citizen_task_source(
			task_source
		):
			errors.append(
				"Citizen "
				+ str(citizen_id)
				+ " has invalid task source '"
				+ task_source
				+ "'."
			)
			task_values_are_valid = false

		if not WorldData.is_valid_city_citizen_task_phase(
			task_phase
		):
			errors.append(
				"Citizen "
				+ str(citizen_id)
				+ " has invalid task phase '"
				+ task_phase
				+ "'."
			)
			task_values_are_valid = false

		if not task_values_are_valid:
			continue

		if task_kind == WorldData.CITY_CITIZEN_TASK_KIND_NONE:
			if task_source != WorldData.CITY_CITIZEN_TASK_SOURCE_NONE:
				errors.append(
					"Citizen "
					+ str(citizen_id)
					+ " has no task but has task source '"
					+ task_source
					+ "'."
				)

			if task_phase != WorldData.CITY_CITIZEN_TASK_PHASE_NONE:
				errors.append(
					"Citizen "
					+ str(citizen_id)
					+ " has no task but has task phase '"
					+ task_phase
					+ "'."
				)

			if task_priority != WorldData.CITY_CITIZEN_TASK_PRIORITY_NONE:
				errors.append(
					"Citizen "
					+ str(citizen_id)
					+ " has no task but has priority "
					+ str(task_priority)
					+ "."
				)

			if target_object_id != -1:
				errors.append(
					"Citizen "
					+ str(citizen_id)
					+ " has no task but targets object "
					+ str(target_object_id)
					+ "."
				)

			if (
				start_world_minute
				!= WorldData.INVALID_CITY_CITIZEN_TASK_START_WORLD_MINUTE
			):
				errors.append(
					"Citizen "
					+ str(citizen_id)
					+ " has no task but has start minute "
					+ str(start_world_minute)
					+ "."
				)

			if player_locked:
				errors.append(
					"Citizen "
					+ str(citizen_id)
					+ " has no task but is player-locked."
				)

			continue

		if not bool(citizen.get("alive", false)):
			errors.append(
				"Dead citizen "
					+ str(citizen_id)
					+ " retains an active task."
			)
		else:
			expected_active_task_ids.append(citizen_id)

		if task_source == WorldData.CITY_CITIZEN_TASK_SOURCE_NONE:
			errors.append(
				"Citizen "
				+ str(citizen_id)
				+ " has active task '"
				+ task_kind
				+ "' with no source."
			)

		if task_phase == WorldData.CITY_CITIZEN_TASK_PHASE_NONE:
			errors.append(
				"Citizen "
				+ str(citizen_id)
				+ " has active task '"
				+ task_kind
				+ "' with no phase."
			)

		if task_priority <= WorldData.CITY_CITIZEN_TASK_PRIORITY_NONE:
			errors.append(
				"Citizen "
				+ str(citizen_id)
				+ " has active task '"
				+ task_kind
				+ "' with non-positive priority "
				+ str(task_priority)
				+ "."
			)

		if start_world_minute < 0:
			errors.append(
				"Citizen "
				+ str(citizen_id)
				+ " has active task '"
				+ task_kind
				+ "' with invalid start minute "
				+ str(start_world_minute)
				+ "."
			)

		if (
			player_locked
			and task_source
			!= WorldData.CITY_CITIZEN_TASK_SOURCE_PLAYER
		):
			errors.append(
				"Citizen "
				+ str(citizen_id)
				+ " has a player lock on non-player task source '"
				+ task_source
				+ "'."
			)

		if (
			(
				task_source == WorldData.CITY_CITIZEN_TASK_SOURCE_PLAYER
				or task_source
				== WorldData.CITY_CITIZEN_TASK_SOURCE_AUTONOMY
			)
			and int(citizen.get("job_object_id", -1)) > 0
		):
			errors.append(
				"Employed citizen "
				+ str(citizen_id)
				+ " has ineligible task source '"
				+ task_source
				+ "'."
			)

		match task_kind:
			WorldData.CITY_CITIZEN_TASK_KIND_WORK:
				if target_object_id <= 0:
					errors.append(
						"Citizen "
						+ str(citizen_id)
						+ " work task has invalid target object ID "
						+ str(target_object_id)
						+ "."
					)
					continue

				if not object_lookup.has(target_object_id):
					errors.append(
						"Citizen "
						+ str(citizen_id)
						+ " work task targets missing object "
						+ str(target_object_id)
						+ "."
					)
					continue

				var target_object := (
					WorldData.get_city_object_by_id(
						target_object_id
					)
				)

				if not WorldData.city_object_is_workplace(
					target_object
				):
					errors.append(
						"Citizen "
						+ str(citizen_id)
						+ " work task targets non-workplace object "
						+ str(target_object_id)
						+ "."
					)

				if (
					int(citizen.get("job_object_id", -1))
					!= target_object_id
				):
					errors.append(
						"Citizen "
						+ str(citizen_id)
						+ " work task targets object "
						+ str(target_object_id)
						+ ", but its assigned workplace is "
						+ str(citizen.get("job_object_id", -1))
						+ "."
					)
				if (
					task_phase
					== WorldData.CITY_CITIZEN_TASK_PHASE_PERFORMING
					and not WorldData.is_city_citizen_attending_workplace(
						citizen_id,
						target_object_id
					)
				):
					errors.append(
						"Citizen "
							+ str(citizen_id)
							+ " has a performing work task but is not "
							+ "physically attending workplace "
							+ str(target_object_id)
							+ "."
					)

			WorldData.CITY_CITIZEN_TASK_KIND_HAUL:
				if not CityCitizens.has_complete_city_citizen_haul_state(
					citizen
				):
					errors.append(
						"Citizen "
							+ str(citizen_id)
							+ " has an active haul task with incomplete haul state."
					)
					continue

				var raw_haul = citizen.get("current_haul", {})
				var raw_cargo = citizen.get("haul_cargo", {})

				if not raw_haul is Dictionary:
					continue

				if not raw_cargo is Dictionary:
					continue

				var haul: Dictionary = raw_haul
				var cargo: Dictionary = raw_cargo
				var haul_resource := str(
					haul.get(
						"resource_type",
						WorldData.RESOURCE_NONE
					)
				)
				var haul_phase := str(
					haul.get(
						"phase",
						WorldData.CITY_CITIZEN_HAUL_PHASE_NONE
					)
				)
				var raw_reservation_id = haul.get("reservation_id")
				var reservation_id := (
					WorldData.INVALID_CITY_CITIZEN_HAUL_RESERVATION_ID
				)

				if typeof(raw_reservation_id) != TYPE_INT:
					errors.append(
						"Citizen "
							+ str(citizen_id)
							+ " haul task has non-integer reservation ID."
					)
				else:
					reservation_id = int(raw_reservation_id)
				var raw_haul_source = haul.get("source", {})
				var raw_haul_destination = haul.get(
					"destination",
					{}
				)
				var raw_haul_requester = haul.get("requester", {})

				if not WorldData.is_city_resource_type(haul_resource):
					errors.append(
						"Citizen "
							+ str(citizen_id)
							+ " haul task has invalid resource '"
							+ haul_resource
							+ "'."
					)

				if (
					not CityCitizens.is_valid_city_citizen_haul_phase(
						haul_phase
					)
					or haul_phase
					== WorldData.CITY_CITIZEN_HAUL_PHASE_NONE
				):
					errors.append(
						"Citizen "
							+ str(citizen_id)
							+ " haul task has invalid phase '"
							+ haul_phase
							+ "'."
					)

				if int(haul.get("requested_amount", 0)) <= 0:
					errors.append(
						"Citizen "
							+ str(citizen_id)
							+ " haul task has no requested amount."
					)

				if str(
					haul.get(
						"reason",
						WorldData.CITY_CITIZEN_HAUL_REASON_NONE
					)
				) == WorldData.CITY_CITIZEN_HAUL_REASON_NONE:
					errors.append(
						"Citizen "
							+ str(citizen_id)
							+ " haul task has no reason."
					)

				if not raw_haul_source is Dictionary:
					errors.append(
						"Citizen "
							+ str(citizen_id)
							+ " haul task has invalid source data."
					)
				else:
					var haul_source: Dictionary = raw_haul_source

					if not CityCitizens.is_valid_city_citizen_haul_endpoint(
						haul_source
					):
						errors.append(
							"Citizen "
								+ str(citizen_id)
								+ " haul task has invalid source endpoint."
						)
					elif int(haul_source.get("id", -1)) != target_object_id:
						errors.append(
							"Citizen "
								+ str(citizen_id)
								+ " haul source does not match task target."
						)

				if not raw_haul_requester is Dictionary:
					errors.append(
						"Citizen "
							+ str(citizen_id)
							+ " haul task has invalid requester data."
					)
				elif not CityCitizens.is_valid_city_citizen_haul_endpoint(
					raw_haul_requester
				):
					errors.append(
						"Citizen "
							+ str(citizen_id)
							+ " haul task has invalid requester endpoint."
					)

				var cargo_amount := maxi(
					int(cargo.get("amount", 0)),
					0
				)

				if cargo_amount <= 0 and reservation_id <= 0:
					errors.append(
						"Citizen "
							+ str(citizen_id)
							+ " has a pre-pickup haul without a reservation."
					)

				if (
					cargo_amount > 0
					and reservation_id <= 0
					and not [
						WorldData.CITY_CITIZEN_HAUL_PHASE_BLOCKED,
						WorldData.CITY_CITIZEN_HAUL_PHASE_RETARGETING,
						WorldData.CITY_CITIZEN_HAUL_PHASE_PENDING_DESTINATION,
					].has(haul_phase)
				):
					errors.append(
						"Citizen "
							+ str(citizen_id)
							+ " carries unreserved cargo outside destination retry."
					)

				if (
					cargo_amount > 0
					and str(
						cargo.get(
							"resource_type",
							WorldData.RESOURCE_NONE
						)
					) != haul_resource
				):
					errors.append(
						"Citizen "
							+ str(citizen_id)
							+ " haul task and cargo resources disagree."
					)

				if not raw_haul_destination is Dictionary:
					errors.append(
						"Citizen "
							+ str(citizen_id)
							+ " haul task has invalid destination data."
					)
				else:
					var haul_destination: Dictionary = (
						raw_haul_destination
					)

					if not CityCitizens.is_valid_city_citizen_haul_endpoint(
						haul_destination,
						cargo_amount > 0
					):
						errors.append(
							"Citizen "
								+ str(citizen_id)
								+ " haul task has invalid destination endpoint."
						)

			WorldData.CITY_CITIZEN_TASK_KIND_RETURN_HOME:
				if target_object_id <= 0:
					errors.append(
						"Citizen "
						+ str(citizen_id)
						+ " return-home task has invalid target object ID "
						+ str(target_object_id)
						+ "."
					)
					continue

				if not object_lookup.has(target_object_id):
					errors.append(
						"Citizen "
						+ str(citizen_id)
						+ " return-home task targets missing object "
						+ str(target_object_id)
						+ "."
					)
					continue

				var target_home := WorldData.get_city_object_by_id(
					target_object_id
				)

				if (
					WorldData.get_city_object_resident_capacity(
						target_home
					) <= 0
					or not WorldData.city_object_supports_citizen_interior(
						target_home
					)
				):
					errors.append(
						"Citizen "
						+ str(citizen_id)
						+ " return-home task targets non-residential "
						+ "or non-interior object "
						+ str(target_object_id)
						+ "."
					)

				if (
					int(citizen.get("home_object_id", -1))
					!= target_object_id
				):
					errors.append(
						"Citizen "
						+ str(citizen_id)
						+ " return-home task targets object "
						+ str(target_object_id)
						+ ", but its assigned home is "
						+ str(citizen.get("home_object_id", -1))
						+ "."
					)

				if not WorldData.get_city_object_resident_ids(
					target_home
				).has(citizen_id):
					errors.append(
						"Citizen "
						+ str(citizen_id)
						+ " return-home task lacks resident membership in "
						+ str(target_object_id)
						+ "."
					)

				if not WorldData.city_citizen_can_access_object_interior(
					citizen_id,
					target_home
				):
					errors.append(
						"Citizen "
						+ str(citizen_id)
						+ " return-home task lacks interior access to "
						+ str(target_object_id)
						+ "."
					)

	expected_active_task_ids.sort()

	if WorldData.city_active_task_ids != expected_active_task_ids:
		errors.append(
			"Active task registry does not match living citizens "
				+ "with active tasks. Expected "
				+ str(expected_active_task_ids)
				+ ", found "
				+ str(WorldData.city_active_task_ids)
				+ "."
		)

	var seen_active_task_ids: Dictionary = {}

	for raw_active_task_id in WorldData.city_active_task_ids:
		if typeof(raw_active_task_id) != TYPE_INT:
			errors.append(
				"Active task registry contains a non-integer ID."
			)
			continue

		var active_task_id: int = raw_active_task_id

		if seen_active_task_ids.has(active_task_id):
			errors.append(
				"Active task registry contains duplicate citizen ID "
					+ str(active_task_id)
					+ "."
			)
			continue

		seen_active_task_ids[active_task_id] = true

		if not citizen_lookup.has(active_task_id):
			errors.append(
				"Active task registry contains missing citizen ID "
					+ str(active_task_id)
					+ "."
			)

		if not WorldData.city_active_task_id_lookup.has(
			active_task_id
		):
			errors.append(
				"Active task lookup is missing citizen ID "
					+ str(active_task_id)
					+ "."
			)

	for raw_lookup_id in WorldData.city_active_task_id_lookup.keys():
		if typeof(raw_lookup_id) != TYPE_INT:
			errors.append(
				"Active task lookup contains a non-integer ID."
			)
			continue

		var lookup_id: int = raw_lookup_id

		if not seen_active_task_ids.has(lookup_id):
			errors.append(
				"Active task lookup contains citizen ID "
					+ str(lookup_id)
					+ " that is absent from the registry array."
			)

	if (
		WorldData.city_active_task_id_lookup.size()
		!= WorldData.city_active_task_ids.size()
	):
		errors.append(
			"Active task registry array and lookup have different sizes."
		)

static func _validate_city_citizen_movement_state(
	errors: Array[String],
	citizen_lookup: Dictionary
) -> void:
	var city_world = WorldData.official_city_world
	var expected_active_ids: Dictionary = {}
	var required_fields := [
		"movement_state",
		"movement_path",
		"movement_path_index",
		"movement_progress_basis_points",
		"movement_destination_tile",
		"movement_speed_basis_points_per_minute",
		"movement_repath_attempt_count",
		"movement_failure_reason"
	]

	for citizen_id in citizen_lookup.keys():
		var citizen_index := int(
			citizen_lookup[citizen_id]
		)
		var citizen: Dictionary = (
			WorldData.city_citizens[citizen_index]
		)
		var missing_field := false

		for field_name in required_fields:
			if citizen.has(field_name):
				continue

			errors.append(
				"Citizen "
				+ str(citizen_id)
				+ " is missing movement field '"
				+ str(field_name)
				+ "'."
			)
			missing_field = true

		if missing_field:
			continue

		var raw_state = citizen.get("movement_state")
		var raw_path = citizen.get("movement_path")
		var raw_index = citizen.get("movement_path_index")
		var raw_progress = citizen.get(
			"movement_progress_basis_points"
		)
		var raw_destination = citizen.get(
			"movement_destination_tile"
		)
		var raw_speed = citizen.get(
			"movement_speed_basis_points_per_minute"
		)
		var raw_repath_attempt_count = citizen.get(
			"movement_repath_attempt_count"
		)
		var raw_failure = citizen.get(
			"movement_failure_reason"
		)

		if typeof(raw_state) != TYPE_STRING:
			errors.append(
				"Citizen "
					+ str(citizen_id)
					+ " has non-string movement state."
			)
			continue

		var movement_state: String = raw_state

		if not WorldData.is_valid_city_citizen_movement_state(
			movement_state
		):
			errors.append(
				"Citizen "
					+ str(citizen_id)
					+ " has invalid movement state '"
					+ movement_state
					+ "'."
			)
			continue

		if not raw_path is Array:
			errors.append(
				"Citizen "
					+ str(citizen_id)
					+ " has non-Array movement path."
			)
			continue

		if typeof(raw_index) != TYPE_INT:
			errors.append(
				"Citizen "
					+ str(citizen_id)
					+ " has non-integer movement path index."
			)
			continue

		if typeof(raw_progress) != TYPE_INT:
			errors.append(
				"Citizen "
					+ str(citizen_id)
					+ " has non-integer movement progress."
			)
			continue

		if not raw_destination is Vector2i:
			errors.append(
				"Citizen "
					+ str(citizen_id)
					+ " has non-Vector2i movement destination."
			)
			continue

		if typeof(raw_speed) != TYPE_INT or int(raw_speed) <= 0:
			errors.append(
				"Citizen "
					+ str(citizen_id)
					+ " has invalid movement speed."
			)
			continue

		if typeof(raw_repath_attempt_count) != TYPE_INT:
			errors.append(
				"Citizen "
					+ str(citizen_id)
					+ " has non-integer movement repath attempt count."
			)
			continue

		if typeof(raw_failure) != TYPE_STRING:
			errors.append(
				"Citizen "
					+ str(citizen_id)
					+ " has non-string movement failure reason."
			)
			continue

		if not WorldData.is_valid_city_citizen_movement_failure(
			str(raw_failure)
		):
			errors.append(
				"Citizen "
					+ str(citizen_id)
					+ " has invalid movement failure reason."
			)

		var movement_path: Array = raw_path
		var movement_index: int = raw_index
		var movement_progress: int = raw_progress
		var movement_destination: Vector2i = raw_destination
		var movement_repath_attempt_count: int = (
			raw_repath_attempt_count
		)
		var previous_path_tile = null
		var path_entries_valid := true

		if movement_progress < 0:
			errors.append(
				"Citizen "
					+ str(citizen_id)
					+ " has out-of-range movement progress."
			)
		if (
			movement_repath_attempt_count < 0
			or movement_repath_attempt_count
			> WorldData.MAX_CITIZEN_MOVEMENT_REPATH_ATTEMPTS
		):
			errors.append(
				"Citizen "
					+ str(citizen_id)
					+ " has out-of-range movement repath attempts."
			)
		for path_index in range(movement_path.size()):
			var raw_path_tile = movement_path[path_index]

			if not raw_path_tile is Vector2i:
				errors.append(
					"Citizen "
						+ str(citizen_id)
						+ " movement path contains non-Vector2i data."
				)
				path_entries_valid = false
				previous_path_tile = null
				continue

			var path_tile: Vector2i = raw_path_tile

			if (
				city_world != null
				and not city_world.is_in_bounds(
					path_tile.x,
					path_tile.y
				)
			):
				errors.append(
					"Citizen "
						+ str(citizen_id)
						+ " movement path leaves city bounds."
				)
				path_entries_valid = false

			if previous_path_tile is Vector2i:
				var step_cost := (
					WorldData.get_city_citizen_movement_step_cost(
						previous_path_tile,
						path_tile
					)
				)

				if step_cost <= 0:
					errors.append(
						"Citizen "
							+ str(citizen_id)
							+ " movement path contains a non-adjacent step."
					)
					path_entries_valid = false
				elif (
					city_world != null
					and not WorldData.can_city_citizen_traverse_step(
						city_world,
						previous_path_tile,
						path_tile,
						int(citizen_id)
					)
				):
					errors.append(
						"Citizen "
							+ str(citizen_id)
							+ " movement path contains a blocked or corner-cutting step."
					)
					path_entries_valid = false

			previous_path_tile = path_tile

		var citizen_is_active := (
			WorldData.city_active_mover_id_lookup.has(
				int(citizen_id)
			)
		)

		match movement_state:
			WorldData.CITY_CITIZEN_MOVEMENT_STATE_IDLE:
				if not movement_path.is_empty():
					errors.append(
						"Idle citizen "
							+ str(citizen_id)
							+ " retains a movement path."
					)

				if movement_index != 0 or movement_progress != 0:
					errors.append(
						"Idle citizen "
							+ str(citizen_id)
							+ " retains movement progress."
					)

				if (
					movement_destination
					!= WorldData.INVALID_CITY_TILE_POSITION
				):
					errors.append(
						"Idle citizen "
							+ str(citizen_id)
							+ " retains a movement destination."
					)

				if (
					str(raw_failure)
					!= WorldData.CITY_CITIZEN_MOVEMENT_FAILURE_NONE
				):
					errors.append(
						"Idle citizen "
							+ str(citizen_id)
							+ " retains a movement failure reason."
					)
				if movement_repath_attempt_count != 0:
					errors.append(
						"Idle citizen "
							+ str(citizen_id)
							+ " retains movement repath attempts."
					)
				if citizen_is_active:
					errors.append(
						"Idle citizen "
							+ str(citizen_id)
							+ " appears in the active-mover registry."
					)

			WorldData.CITY_CITIZEN_MOVEMENT_STATE_MOVING:
				expected_active_ids[int(citizen_id)] = true

				if not bool(citizen.get("alive", false)):
					errors.append(
						"Dead citizen "
							+ str(citizen_id)
							+ " remains in moving state."
					)

				if movement_path.size() < 2:
					errors.append(
						"Moving citizen "
							+ str(citizen_id)
							+ " has an incomplete path."
					)

				if (
					movement_index < 1
					or movement_index >= movement_path.size()
				):
					errors.append(
						"Moving citizen "
							+ str(citizen_id)
							+ " has an out-of-range path index."
					)
				elif (
					path_entries_valid
					and movement_path[movement_index - 1]
					!= citizen.get(
						"city_tile_position",
						WorldData.INVALID_CITY_TILE_POSITION
					)
				):
					errors.append(
						"Moving citizen "
							+ str(citizen_id)
							+ " path anchor disagrees with its position."
					)
				elif path_entries_valid:
					var current_step_cost := (
						WorldData.get_city_citizen_movement_step_cost(
							movement_path[movement_index - 1],
							movement_path[movement_index]
						)
					)

					if (
						current_step_cost <= 0
						or movement_progress >= current_step_cost
					):
						errors.append(
							"Moving citizen "
								+ str(citizen_id)
								+ " has progress outside its current step cost."
						)

				if (
					not movement_path.is_empty()
					and movement_destination
					!= movement_path.back()
				):
					errors.append(
						"Moving citizen "
							+ str(citizen_id)
							+ " destination disagrees with its path."
					)

				if (
					str(raw_failure)
					!= WorldData.CITY_CITIZEN_MOVEMENT_FAILURE_NONE
				):
					errors.append(
						"Moving citizen "
							+ str(citizen_id)
							+ " retains a failure reason."
					)

				if not citizen_is_active:
					errors.append(
						"Moving citizen "
							+ str(citizen_id)
							+ " is absent from the active-mover registry."
					)

			WorldData.CITY_CITIZEN_MOVEMENT_STATE_BLOCKED:
				if citizen_is_active:
					errors.append(
						"Blocked citizen "
							+ str(citizen_id)
							+ " appears in the active-mover registry."
					)

	var active_array_lookup: Dictionary = {}
	var previous_active_id := -1

	for active_citizen_id in WorldData.city_active_mover_ids:
		if active_array_lookup.has(active_citizen_id):
			errors.append(
				"Active-mover registry contains duplicate citizen ID "
					+ str(active_citizen_id)
					+ "."
			)
		else:
			active_array_lookup[active_citizen_id] = true

		if (
			previous_active_id >= 0
			and active_citizen_id <= previous_active_id
		):
			errors.append(
				"Active-mover registry is not strictly sorted."
			)

		previous_active_id = active_citizen_id

		if not citizen_lookup.has(active_citizen_id):
			errors.append(
				"Active-mover registry references missing citizen "
					+ str(active_citizen_id)
					+ "."
			)
			continue

		var active_citizen: Dictionary = (
			WorldData.city_citizens[
				int(citizen_lookup[active_citizen_id])
			]
		)

		if (
			not bool(active_citizen.get("alive", false))
			or str(active_citizen.get("movement_state", ""))
			!= WorldData.CITY_CITIZEN_MOVEMENT_STATE_MOVING
		):
			errors.append(
				"Active-mover registry contains an ineligible citizen."
			)

		if not WorldData.city_active_mover_id_lookup.has(
			active_citizen_id
		):
			errors.append(
				"Active-mover lookup is missing citizen "
					+ str(active_citizen_id)
					+ "."
			)

	for lookup_id in WorldData.city_active_mover_id_lookup.keys():
		if not active_array_lookup.has(lookup_id):
			errors.append(
				"Active-mover lookup contains citizen "
					+ str(lookup_id)
					+ " absent from its array."
			)

	for expected_active_id in expected_active_ids.keys():
		if not active_array_lookup.has(expected_active_id):
			errors.append(
				"Moving citizen "
					+ str(expected_active_id)
					+ " is absent from the active-mover array."
			)

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

		for raw_resource in stored_resources.keys():
			if typeof(raw_resource) != TYPE_STRING:
				errors.append(
					"Container object "
						+ str(object_id)
						+ " has a non-String storage resource key."
				)

				continue

			var resource: String = raw_resource

			if not allowed_resources.has(resource):
				errors.append(
					"Container object "
						+ str(object_id)
						+ " stores unsupported resource '"
						+ resource
						+ "'."
				)

				continue

			var raw_amount = stored_resources[raw_resource]

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

			if amount <= 0:
				errors.append(
					"Container object "
						+ str(object_id)
						+ " has non-positive "
						+ resource
						+ " amount "
						+ str(amount)
						+ "; empty resources must be omitted."
				)

			var capacity := (
				WorldData
				.get_city_object_storage_capacity_for_resource(
					city_object,
					resource
				)
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
		var total_stored_amount := (
			WorldData.get_city_object_storage_used_capacity(
				city_object
			)
		)
		var total_capacity := (
			WorldData.get_city_object_storage_capacity(
				city_object
			)
		)

		if total_stored_amount > total_capacity:
			errors.append(
				"Container object "
					+ str(object_id)
					+ " stores "
					+ str(total_stored_amount)
					+ " total units but capacity is "
					+ str(total_capacity)
					+ "."
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
			if typeof(raw_resource) != TYPE_STRING:
				errors.append(
					"Citizen "
						+ str(citizen_id)
						+ " has a non-String inventory resource key."
				)

				continue

			var resource: String = raw_resource
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

			if amount <= 0:
				errors.append(
					"Citizen "
						+ str(citizen_id)
						+ " has non-positive inventory amount for "
						+ resource
						+ "; empty resources must be omitted."
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

		var haul_cargo_amount := 0

		if not CityCitizens.has_complete_city_citizen_haul_state(
			citizen
		):
			errors.append(
				"Citizen "
					+ str(citizen_id)
					+ " has incomplete haul state."
			)
		else:
			var raw_haul_cargo = citizen.get("haul_cargo", {})

			if not raw_haul_cargo is Dictionary:
				errors.append(
					"Citizen "
						+ str(citizen_id)
						+ " has non-Dictionary haul cargo."
				)
			else:
				var haul_cargo: Dictionary = raw_haul_cargo
				var raw_cargo_resource = haul_cargo.get(
					"resource_type"
				)
				var raw_cargo_amount = haul_cargo.get("amount")

				if typeof(raw_cargo_resource) != TYPE_STRING:
					errors.append(
						"Citizen "
							+ str(citizen_id)
							+ " has non-string haul cargo resource."
					)

				if typeof(raw_cargo_amount) != TYPE_INT:
					errors.append(
						"Citizen "
							+ str(citizen_id)
							+ " has non-integer haul cargo amount."
					)
				else:
					haul_cargo_amount = maxi(
						int(raw_cargo_amount),
						0
					)

					if int(raw_cargo_amount) < 0:
						errors.append(
							"Citizen "
								+ str(citizen_id)
								+ " has negative haul cargo."
						)

				if (
					typeof(raw_cargo_resource) == TYPE_STRING
				):
					var cargo_resource: String = raw_cargo_resource

					if (
						haul_cargo_amount <= 0
						and cargo_resource != WorldData.RESOURCE_NONE
					):
						errors.append(
							"Citizen "
								+ str(citizen_id)
								+ " has empty haul cargo with resource '"
								+ cargo_resource
								+ "'."
						)

					if (
						haul_cargo_amount > 0
						and not valid_resources.has(cargo_resource)
					):
						errors.append(
							"Citizen "
								+ str(citizen_id)
								+ " hauls invalid resource '"
								+ cargo_resource
								+ "'."
						)

		var total_carried_amount := (
			total_inventory_amount + haul_cargo_amount
		)

		if total_carried_amount > carry_capacity:
			errors.append(
				"Citizen "
					+ str(citizen_id)
					+ " carries "
					+ str(total_carried_amount)
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
				or production_status
				== WorldData.WORKPLACE_PRODUCTION_STATUS_BLOCKED_NO_RESOURCE_SOURCE
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
						+ " productive workers, but current attendance state yields "
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

		if not WorldData.is_city_citizen_attending_workplace(
			worker_id,
			workplace_id
		):
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

	if (
		mode
		== WorldData.WORKPLACE_RESOURCE_SOURCE_MODE_FOOTPRINT_REACH
	):
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
			"reach_tiles"
		)

		_validate_positive_workplace_policy_integer(
			errors,
			object_id,
			"resource_source_policy",
			policy,
			"source_tiles_for_full_productivity"
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

	if not WorldData.is_city_resource_type(resource):
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
