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

	WorldData.ensure_city_object_definitions_ready()

	var checked_workplace_definition_count := (
		_validate_workplace_definitions(
			errors,
			warnings
		)
	)
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

	var checked_workplace_count := (
		_validate_city_workplace_runtime(
			errors,
			object_lookup
		)
	)

	_validate_city_assignments(
		errors,
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
		"checked_workplace_definitions": (
			checked_workplace_definition_count
		),
		"checked_workplaces": checked_workplace_count,
		"checked_inventories": checked_inventory_count,
		"duration_usec": validation_duration_usec,
		"object_version": WorldData.city_object_version,
		"container_version": WorldData.city_container_version,
		"citizen_version": WorldData.city_citizen_version,
		"assignment_version": WorldData.city_assignment_version
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

	# Production progress changes every simulation tick. Runtime writes are
	# guarded by WorldData, so city_workplace_version intentionally does not
	# invalidate this comprehensive validator on every tick. Forced validation
	# still inspects the current production state.
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


static func _validate_workplace_definitions(
	errors: Array[String],
	_warnings: Array[String]
) -> int:
	var checked_workplace_definition_count := 0
	var workplace_policy_fields := [
		"production_recipe",
		"resource_source_policy",
		"work_location_policy",
		"work_movement_policy",
		"break_location_policy",
		"overflow_policy"
	]

	for raw_object_type in WorldData.city_object_definitions.keys():
		var object_type := str(raw_object_type)
		var raw_definition = (
			WorldData.city_object_definitions[raw_object_type]
		)

		if not raw_definition is Dictionary:
			errors.append(
				"City object definition '"
					+ object_type
					+ "' is not a Dictionary."
			)
			continue

		var definition: Dictionary = raw_definition
		var is_workplace := bool(
			definition.get("is_workplace", false)
		)

		for policy_field in workplace_policy_fields:
			var raw_policy = definition.get(
				policy_field,
				{}
			)

			if not raw_policy is Dictionary:
				errors.append(
					"City object definition '"
						+ object_type
						+ "' has non-Dictionary "
						+ str(policy_field)
						+ "."
				)

		if not is_workplace:
			for policy_field in workplace_policy_fields:
				var raw_policy = definition.get(
					policy_field,
					{}
				)

				if (
					raw_policy is Dictionary
					and not raw_policy.is_empty()
				):
					errors.append(
						"Non-workplace definition '"
							+ object_type
							+ "' contains "
							+ str(policy_field)
							+ "."
					)

			continue

		checked_workplace_definition_count += 1

		var raw_worker_capacity = definition.get(
			"worker_capacity",
			0
		)

		if (
			not raw_worker_capacity is int
			or int(raw_worker_capacity) <= 0
		):
			errors.append(
				"Workplace definition '"
					+ object_type
					+ "' has invalid worker_capacity."
			)

		_validate_production_recipe_definition(
			errors,
			object_type,
			definition
		)
		_validate_resource_source_policy_definition(
			errors,
			object_type,
			definition
		)
		_validate_work_location_policy_definition(
			errors,
			object_type,
			definition
		)
		_validate_work_movement_policy_definition(
			errors,
			object_type,
			definition
		)
		_validate_break_location_policy_definition(
			errors,
			object_type,
			definition
		)
		_validate_overflow_policy_definition(
			errors,
			object_type,
			definition
		)

	return checked_workplace_definition_count


static func _validate_production_recipe_definition(
	errors: Array[String],
	object_type: String,
	definition: Dictionary
) -> void:
	var raw_recipe = definition.get("production_recipe", {})

	if not raw_recipe is Dictionary:
		return

	var recipe: Dictionary = raw_recipe

	if recipe.is_empty():
		return

	var raw_inputs = recipe.get("inputs", {})
	var raw_outputs = recipe.get("outputs", {})
	var raw_work_units_per_batch = recipe.get(
		"work_units_per_batch",
		0
	)

	_validate_recipe_resource_amounts(
		errors,
		object_type,
		"inputs",
		raw_inputs,
		false
	)
	_validate_recipe_resource_amounts(
		errors,
		object_type,
		"outputs",
		raw_outputs,
		true
	)

	if (
		not raw_work_units_per_batch is int
		or int(raw_work_units_per_batch) <= 0
	):
		errors.append(
			"Workplace definition '"
				+ object_type
				+ "' has invalid work_units_per_batch."
		)

	if not raw_outputs is Dictionary:
		return

	var outputs: Dictionary = raw_outputs
	var raw_storage_resources = definition.get(
		"storage_resources",
		[]
	)

	if not raw_storage_resources is Array:
		return

	var storage_resources: Array = raw_storage_resources

	for raw_resource in outputs.keys():
		var resource := str(raw_resource)

		if not storage_resources.has(resource):
			errors.append(
				"Workplace definition '"
					+ object_type
					+ "' outputs "
					+ resource
					+ " but its container cannot store it."
			)


static func _validate_recipe_resource_amounts(
	errors: Array[String],
	object_type: String,
	field_name: String,
	raw_resource_amounts,
	require_non_empty: bool
) -> void:
	if not raw_resource_amounts is Dictionary:
		errors.append(
			"Workplace definition '"
				+ object_type
				+ "' has non-Dictionary recipe "
				+ field_name
				+ "."
		)
		return

	var resource_amounts: Dictionary = raw_resource_amounts

	if require_non_empty and resource_amounts.is_empty():
		errors.append(
			"Workplace definition '"
				+ object_type
				+ "' has no production outputs."
		)

	var known_resources := WorldData.get_city_resource_types()

	for raw_resource in resource_amounts.keys():
		var resource := str(raw_resource)
		var raw_amount = resource_amounts[raw_resource]

		if typeof(raw_resource) != TYPE_STRING:
			errors.append(
				"Workplace definition '"
					+ object_type
					+ "' has a non-String resource key in recipe "
					+ field_name
					+ "."
			)

		if not known_resources.has(resource):
			errors.append(
				"Workplace definition '"
					+ object_type
					+ "' uses unknown "
					+ field_name
					+ " resource '"
					+ resource
					+ "'."
			)

		if not raw_amount is int:
			errors.append(
				"Workplace definition '"
					+ object_type
					+ "' has non-integer "
					+ resource
					+ " amount in recipe "
					+ field_name
					+ "."
			)
			continue

		if int(raw_amount) <= 0:
			errors.append(
				"Workplace definition '"
					+ object_type
					+ "' has non-positive "
					+ resource
					+ " amount in recipe "
					+ field_name
					+ "."
			)


static func _validate_resource_source_policy_definition(
	errors: Array[String],
	object_type: String,
	definition: Dictionary
) -> void:
	var raw_policy = definition.get(
		"resource_source_policy",
		{}
	)

	if not raw_policy is Dictionary:
		return

	var policy: Dictionary = raw_policy

	if policy.is_empty():
		return

	var mode := str(policy.get(
		"mode",
		WorldData.WORKPLACE_RESOURCE_SOURCE_MODE_NONE
	))

	if mode == WorldData.WORKPLACE_RESOURCE_SOURCE_MODE_NONE:
		return

	if mode != WorldData.WORKPLACE_RESOURCE_SOURCE_MODE_RADIUS:
		errors.append(
			"Workplace definition '"
				+ object_type
				+ "' has unknown resource source mode '"
				+ mode
				+ "'."
		)
		return

	var resource_type := str(
		policy.get("resource_type", WorldData.RESOURCE_NONE)
	)
	var raw_radius_tiles = policy.get("radius_tiles", 0)
	var anchor_mode := str(policy.get("anchor_mode", ""))

	if not WorldData.get_city_resource_types().has(resource_type):
		errors.append(
			"Workplace definition '"
				+ object_type
				+ "' has unknown source resource '"
				+ resource_type
				+ "'."
		)

	if (
		not raw_radius_tiles is int
		or int(raw_radius_tiles) <= 0
	):
		errors.append(
			"Workplace definition '"
				+ object_type
				+ "' has invalid resource source radius."
		)

	if (
		anchor_mode
		!= WorldData.WORKPLACE_ANCHOR_MODE_FOOTPRINT_CENTER
	):
		errors.append(
			"Workplace definition '"
				+ object_type
				+ "' has unknown gathering anchor mode '"
				+ anchor_mode
				+ "'."
		)


static func _validate_work_location_policy_definition(
	errors: Array[String],
	object_type: String,
	definition: Dictionary
) -> void:
	_validate_simple_policy_mode(
		errors,
		object_type,
		"work_location_policy",
		definition.get("work_location_policy", {}),
		[
			WorldData.WORKPLACE_WORK_LOCATION_MODE_NONE,
			WorldData.WORKPLACE_WORK_LOCATION_MODE_RESOURCE_SOURCE_TILES
		]
	)


static func _validate_work_movement_policy_definition(
	errors: Array[String],
	object_type: String,
	definition: Dictionary
) -> void:
	_validate_simple_policy_mode(
		errors,
		object_type,
		"work_movement_policy",
		definition.get("work_movement_policy", {}),
		[
			WorldData.WORKPLACE_WORK_MOVEMENT_MODE_NONE,
			WorldData.WORKPLACE_WORK_MOVEMENT_MODE_MOVE_BETWEEN_WORK_POINTS
		]
	)


static func _validate_break_location_policy_definition(
	errors: Array[String],
	object_type: String,
	definition: Dictionary
) -> void:
	_validate_radius_policy(
		errors,
		object_type,
		"break_location_policy",
		definition.get("break_location_policy", {}),
		WorldData.WORKPLACE_BREAK_LOCATION_MODE_NONE,
		WorldData.WORKPLACE_BREAK_LOCATION_MODE_FOOTPRINT_RADIUS
	)


static func _validate_overflow_policy_definition(
	errors: Array[String],
	object_type: String,
	definition: Dictionary
) -> void:
	_validate_radius_policy(
		errors,
		object_type,
		"overflow_policy",
		definition.get("overflow_policy", {}),
		WorldData.WORKPLACE_OVERFLOW_MODE_NONE,
		WorldData.WORKPLACE_OVERFLOW_MODE_FOOTPRINT_RADIUS
	)


static func _validate_simple_policy_mode(
	errors: Array[String],
	object_type: String,
	policy_name: String,
	raw_policy,
	valid_modes: Array
) -> void:
	if not raw_policy is Dictionary:
		return

	var policy: Dictionary = raw_policy

	if policy.is_empty():
		return

	var mode := str(policy.get("mode", ""))

	if not valid_modes.has(mode):
		errors.append(
			"Workplace definition '"
				+ object_type
				+ "' has unknown "
				+ policy_name
				+ " mode '"
				+ mode
				+ "'."
		)


static func _validate_radius_policy(
	errors: Array[String],
	object_type: String,
	policy_name: String,
	raw_policy,
	none_mode: String,
	radius_mode: String
) -> void:
	if not raw_policy is Dictionary:
		return

	var policy: Dictionary = raw_policy

	if policy.is_empty():
		return

	var mode := str(policy.get("mode", ""))

	if mode == none_mode:
		return

	if mode != radius_mode:
		errors.append(
			"Workplace definition '"
				+ object_type
				+ "' has unknown "
				+ policy_name
				+ " mode '"
				+ mode
				+ "'."
		)
		return

	var raw_radius_tiles = policy.get("radius_tiles", 0)

	if (
		not raw_radius_tiles is int
		or int(raw_radius_tiles) <= 0
	):
		errors.append(
			"Workplace definition '"
				+ object_type
				+ "' has invalid "
				+ policy_name
				+ " radius."
		)


static func _validate_city_workplace_runtime(
	errors: Array[String],
	object_lookup: Dictionary
) -> int:
	var checked_workplace_count := 0
	var runtime_fields := [
		"production_progress_work_units",
		"production_status",
		"productive_worker_count",
		"site_productivity_basis_points"
	]

	for object_id in object_lookup.keys():
		var object_index := int(object_lookup[object_id])
		var city_object: Dictionary = (
			WorldData.city_objects[object_index]
		)

		if not WorldData.city_object_is_workplace(city_object):
			continue

		var recipe := (
			WorldData.get_city_object_production_recipe(
				city_object
			)
		)

		if recipe.is_empty():
			for runtime_field in runtime_fields:
				if city_object.has(runtime_field):
					errors.append(
						"Non-producing workplace "
							+ str(object_id)
							+ " contains "
							+ str(runtime_field)
							+ "."
					)

			continue

		checked_workplace_count += 1

		for runtime_field in runtime_fields:
			if not city_object.has(runtime_field):
				errors.append(
					"Producing workplace "
						+ str(object_id)
						+ " is missing "
						+ str(runtime_field)
						+ "."
				)

		var raw_progress = city_object.get(
			"production_progress_work_units",
			0
		)
		var raw_status = city_object.get(
			"production_status",
			""
		)
		var raw_productive_worker_count = city_object.get(
			"productive_worker_count",
			0
		)
		var raw_site_productivity = city_object.get(
			"site_productivity_basis_points",
			0
		)

		if not raw_progress is int:
			errors.append(
				"Producing workplace "
					+ str(object_id)
					+ " has non-integer production progress."
			)
		else:
			var progress_work_units: int = raw_progress
			var work_units_per_batch := int(
				recipe.get("work_units_per_batch", 0)
			)

			if progress_work_units < 0:
				errors.append(
					"Producing workplace "
						+ str(object_id)
						+ " has negative production progress."
				)

			if (
				work_units_per_batch > 0
				and progress_work_units
				>= work_units_per_batch
			):
				errors.append(
					"Producing workplace "
						+ str(object_id)
						+ " retains one or more completed batches as progress."
				)

		if typeof(raw_status) != TYPE_STRING:
			errors.append(
				"Producing workplace "
					+ str(object_id)
					+ " has non-String production status."
			)
		elif not WorldData.is_valid_workplace_production_status(
			str(raw_status)
		):
			errors.append(
				"Producing workplace "
					+ str(object_id)
					+ " has unknown production status '"
					+ str(raw_status)
					+ "'."
			)

		if not raw_productive_worker_count is int:
			errors.append(
				"Producing workplace "
					+ str(object_id)
					+ " has non-integer productive worker count."
			)
		else:
			var productive_worker_count: int = (
				raw_productive_worker_count
			)
			var assigned_worker_count := (
				WorldData.get_city_object_worker_count(
					city_object
				)
			)

			if (
				productive_worker_count < 0
				or productive_worker_count
				> assigned_worker_count
			):
				errors.append(
					"Producing workplace "
						+ str(object_id)
						+ " has invalid productive worker count "
						+ str(productive_worker_count)
						+ " for "
						+ str(assigned_worker_count)
						+ " assigned workers."
				)

		if not raw_site_productivity is int:
			errors.append(
				"Producing workplace "
					+ str(object_id)
					+ " has non-integer site productivity."
			)
		elif int(raw_site_productivity) < 0:
			errors.append(
				"Producing workplace "
					+ str(object_id)
					+ " has negative site productivity."
			)

	return checked_workplace_count


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
