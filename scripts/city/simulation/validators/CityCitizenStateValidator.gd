# File responsibility: Validate citizen identity, needs, tasks, and movement state.
extends RefCounted

const CityWorkSystemScript := preload(
	"res://scripts/city/simulation/systems/CityWorkSystem.gd"
)


const CityLogisticsStateValidator := preload("res://scripts/city/simulation/validators/CityLogisticsStateValidator.gd")

#region Citizen Spatial Identity and Needs
static func _validate_city_citizen_spatial_state(
	errors: Array[String],
	citizen_lookup: Dictionary
) -> void:
	if citizen_lookup.is_empty():
		if not (
			CityCitizenSpatialSystem.get_current_state()
			.citizen_ids_by_tile
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
			CityCitizenRegistrySystem.get_current_state().citizens[
				citizen_index
			]
		)
		if not bool(citizen.get("alive", false)):
			continue

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
				CityNavigationSystem
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
			CityCitizenSpatialSystem.get_current_state().citizen_ids_by_tile.has(
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
			CityCitizenSpatialSystem.get_current_state().citizen_ids_by_tile[
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
		CityCitizenSpatialSystem.get_current_state().citizen_ids_by_tile.keys()
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
			CityCitizenSpatialSystem.get_current_state().citizen_ids_by_tile[
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
				CityCitizenRegistrySystem.get_current_state().citizens[
					citizen_index
				]
			)
			if not bool(citizen.get("alive", false)):
				errors.append(
					"Citizen spatial index at "
						+ str(tile_position)
						+ " references non-living citizen "
						+ str(citizen_id)
						+ "."
				)
				continue
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
	values: Dictionary
) -> void:
	var errors: Array[String] = values.get("errors", [])
	var pool_display_name := str(values.get("pool_display_name", ""))
	var expected_sex := str(values.get("expected_sex", ""))
	var name_pool: Array = values.get("name_pool", [])
	var global_name_owners: Dictionary = values.get(
		"global_name_owners",
		{}
	)
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
	_validate_city_citizen_culture_state(
		errors,
		citizen_lookup
	)

	var global_name_owners: Dictionary = {}

	_validate_city_citizen_name_pool({
		"errors": errors,
		"pool_display_name": "Male",
		"expected_sex": WorldData.CITY_CITIZEN_SEX_MALE,
		"name_pool": CityCitizens.city_citizen_male_name_pool,
		"global_name_owners": global_name_owners,
	})

	_validate_city_citizen_name_pool({
		"errors": errors,
		"pool_display_name": "Female",
		"expected_sex": WorldData.CITY_CITIZEN_SEX_FEMALE,
		"name_pool": CityCitizens.city_citizen_female_name_pool,
		"global_name_owners": global_name_owners,
	})

	if not (
		CityCitizens
		.city_citizen_unassigned_name_pool
		.is_empty()
	):
		errors.append(
			"Citizen unassigned-name pool still contains "
			+ str(
				CityCitizens
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
			CityCitizenRegistrySystem.get_current_state().citizens[
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
			CityCitizens.normalize_city_citizen_sex(
				raw_sex
			)
		)

		if not CityCitizens.is_valid_city_citizen_sex(
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
			CityCitizens.get_city_citizen_name_pool_for_sex(
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
			CityCitizenRegistrySystem.get_current_state().citizens.size()
			== WorldData.STARTING_CITY_POPULATION
		)
		and (
			CityCitizenRegistrySystem.get_current_state().next_citizen_id
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


static func _validate_city_citizen_culture_state(
	errors: Array[String],
	citizen_lookup: Dictionary
) -> void:
	for citizen_id in citizen_lookup.keys():
		var citizen_index := int(citizen_lookup[citizen_id])
		var citizen: Dictionary = CityCitizenRegistrySystem.get_current_state().citizens[citizen_index]

		if not citizen.has("culture_id"):
			errors.append(
				"Citizen "
				+ str(citizen_id)
				+ " is missing culture_id."
			)
			continue

		var raw_culture_id = citizen.get("culture_id")

		if typeof(raw_culture_id) != TYPE_INT:
			errors.append(
				"Citizen "
				+ str(citizen_id)
				+ " has a non-integer culture_id."
			)
			continue

		var culture_id: int = raw_culture_id

		if culture_id <= 0:
			errors.append(
				"Citizen "
				+ str(citizen_id)
				+ " has a nonpositive culture_id."
			)
			continue

		if not WorldData.has_culture_id(culture_id):
			errors.append(
				"Citizen "
				+ str(citizen_id)
				+ " references nonexistent culture "
				+ str(culture_id)
				+ "."
			)

	if not WorldData.player_city_founded:
		return

	var primary_culture_id := WorldData.INVALID_CULTURE_ID

	if not WorldData.player_city_data.has("primary_culture_id"):
		errors.append(
			"Founded player city is missing primary_culture_id."
		)
	elif (
		typeof(
			WorldData.player_city_data.get("primary_culture_id")
		)
		!= TYPE_INT
	):
		errors.append(
			"Founded player city has a non-integer primary_culture_id."
		)
	else:
		primary_culture_id = int(
			WorldData.player_city_data.get("primary_culture_id")
		)

		if primary_culture_id <= 0:
			errors.append(
				"Founded player city has a nonpositive primary_culture_id."
			)
		elif not WorldData.has_culture_id(primary_culture_id):
			errors.append(
				"Founded player city references nonexistent culture "
				+ str(primary_culture_id)
				+ "."
			)

	if not WorldData.has_official_founding_identity():
		errors.append(
			"Founded player city has no official founding identity."
		)
	else:
		var player_city_name := str(
			WorldData.player_city_data.get("name", "")
		)

		if player_city_name != WorldData.get_official_city_name():
			errors.append(
				"Founded player city name disagrees with the official city name."
			)

		if (
			primary_culture_id > 0
			and WorldData.get_official_founding_culture_id()
			!= primary_culture_id
		):
			errors.append(
				"Founded player city culture disagrees with the official founding culture."
			)

		if (
			primary_culture_id > 0
			and WorldData.has_culture_id(primary_culture_id)
			and WorldData.get_culture_name_by_id(primary_culture_id)
			!= WorldData.get_official_founding_culture_name()
		):
			errors.append(
				"Founded player city culture name disagrees with the official founding culture name."
			)

	if not (
		primary_culture_id > 0
		and CityCitizenRegistrySystem.get_current_state().next_citizen_id
		> WorldData.STARTING_CITY_POPULATION
	):
		return

	for citizen_id in range(1, WorldData.STARTING_CITY_POPULATION + 1):
		if not citizen_lookup.has(citizen_id):
			errors.append(
				"Founding citizen "
				+ str(citizen_id)
				+ " is missing from the citizen registry."
			)
			continue

		var citizen_index := int(citizen_lookup[citizen_id])
		var citizen: Dictionary = CityCitizenRegistrySystem.get_current_state().citizens[citizen_index]

		if citizen.get("culture_id") == primary_culture_id:
			continue

		errors.append(
			"Founding citizen "
			+ str(citizen_id)
			+ " does not reference the city's primary culture."
		)


static func _validate_city_citizen_need_state(
	errors: Array[String],
	citizen_lookup: Dictionary
) -> void:
	for citizen_id in citizen_lookup.keys():
		var citizen_index := int(citizen_lookup[citizen_id])
		var citizen: Dictionary = CityCitizenRegistrySystem.get_current_state().citizens[citizen_index]

		if not CityCitizens.has_complete_city_citizen_need_state(citizen):
			errors.append(
				"Citizen "
				+ str(citizen_id)
				+ " has incomplete need state."
			)
			continue

		var raw_hunger = citizen.get("hunger")
		var raw_hunger_remainder = citizen.get("hunger_decay_remainder")
		var raw_happiness = citizen.get("happiness")

		if (
			typeof(raw_hunger) != TYPE_INT
			or int(raw_hunger) < 0
			or int(raw_hunger) > CityCitizens.MAX_CITIZEN_HUNGER
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
			>= CityCitizens.CITIZEN_HUNGER_DECAY_DENOMINATOR_MINUTES
		):
			errors.append(
				"Citizen "
				+ str(citizen_id)
				+ " has invalid hunger-decay remainder."
			)

		if (
			typeof(raw_happiness) != TYPE_INT
			or int(raw_happiness) < 0
			or int(raw_happiness) > 100
		):
			errors.append(
				"Citizen "
				+ str(citizen_id)
				+ " has out-of-range happiness state."
			)

	for resource in CityResourceCatalog.get_city_food_resource_types():
		if (
			not WorldData.is_city_resource_type(resource)
			or CityResourceCatalog.get_city_food_hunger_restore(resource) <= 0
		):
			errors.append(
				"Food configuration contains invalid resource '"
				+ resource
				+ "'."
			)




#endregion

#region Citizen Tasks
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
		"work_order_id",
		"job_id",
		"start_world_minute",
		"target_tile",
		"previous_target_tile",
		"next_action_world_minute",
		"relocation_count",
		"player_locked",
		"food_resource_type",
		"food_requested_amount",
		"food_source_endpoint_kind",
		"food_source_access_purpose"
	]
	var expected_active_task_ids: Array[int] = []

	for raw_citizen_id in citizen_lookup.keys():
		_validate_city_citizen_task_entry({
			"errors": errors,
			"citizen_lookup": citizen_lookup,
			"object_lookup": object_lookup,
			"required_task_fields": required_task_fields,
			"expected_active_task_ids": expected_active_task_ids,
			"raw_citizen_id": raw_citizen_id,
		})

	expected_active_task_ids.sort()

	_validate_city_active_task_registry(
		errors,
		citizen_lookup,
		expected_active_task_ids
	)


static func _validate_city_citizen_task_entry(
	values: Dictionary
) -> void:
	var errors: Array[String] = values.get("errors", [])
	var citizen_lookup: Dictionary = values.get("citizen_lookup", {})
	var object_lookup: Dictionary = values.get("object_lookup", {})
	var required_task_fields: Array[String] = values.get(
		"required_task_fields",
		[]
	)
	var expected_active_task_ids: Array[int] = values.get(
		"expected_active_task_ids",
		[]
	)
	var raw_citizen_id = values.get("raw_citizen_id")
	var citizen_id: int = raw_citizen_id
	var citizen_index := int(citizen_lookup[citizen_id])
	var citizen: Dictionary = CityCitizenRegistrySystem.get_current_state().citizens[citizen_index]

	if not citizen.has("current_task"):
		errors.append(
			"Citizen "
			+ str(citizen_id)
			+ " is missing current_task."
		)
		return

	var raw_current_task = citizen.get("current_task")

	if not raw_current_task is Dictionary:
		errors.append(
			"Citizen "
			+ str(citizen_id)
			+ " has a non-Dictionary current_task."
		)
		return

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
		return

	var task_field_context := {
		"errors": errors,
		"citizen_id": citizen_id,
		"raw_task_kind": current_task.get("kind"),
		"raw_task_source": current_task.get("source"),
		"raw_task_phase": current_task.get("phase"),
		"raw_task_priority": current_task.get("priority"),
		"raw_target_object_id": current_task.get("target_object_id"),
		"raw_work_order_id": current_task.get("work_order_id"),
		"raw_job_id": current_task.get("job_id"),
		"raw_start_world_minute": current_task.get("start_world_minute"),
		"raw_target_tile": current_task.get("target_tile"),
		"raw_previous_target_tile": current_task.get("previous_target_tile"),
		"raw_next_action_world_minute": current_task.get(
			"next_action_world_minute"
		),
		"raw_relocation_count": current_task.get("relocation_count"),
		"raw_player_locked": current_task.get("player_locked"),
		"raw_food_resource_type": current_task.get("food_resource_type"),
		"raw_food_requested_amount": current_task.get("food_requested_amount"),
		"raw_food_source_endpoint_kind": current_task.get(
			"food_source_endpoint_kind"
		),
		"raw_food_source_access_purpose": current_task.get(
			"food_source_access_purpose"
		),
	}

	if not _city_citizen_task_fields_have_valid_types(task_field_context):
		return

	var task_kind := str(task_field_context.get("raw_task_kind", ""))
	var task_source := str(task_field_context.get("raw_task_source", ""))
	var task_phase := str(task_field_context.get("raw_task_phase", ""))

	if not _city_citizen_task_enums_are_valid({
		"errors": errors,
		"citizen_id": citizen_id,
		"task_kind": task_kind,
		"task_source": task_source,
		"task_phase": task_phase,
	}):
		return

	var task_context := {
		"errors": errors,
		"citizen_id": citizen_id,
		"citizen": citizen,
		"object_lookup": object_lookup,
		"expected_active_task_ids": expected_active_task_ids,
		"current_task": current_task,
		"task_kind": task_kind,
		"task_source": task_source,
		"task_phase": task_phase,
		"task_priority": int(task_field_context.get("raw_task_priority", 0)),
		"target_object_id": int(
			task_field_context.get("raw_target_object_id", -1)
		),
		"work_order_id": int(task_field_context.get("raw_work_order_id", -1)),
		"job_id": str(task_field_context.get("raw_job_id", "")),
		"start_world_minute": int(
			task_field_context.get("raw_start_world_minute", -1)
		),
		"player_locked": bool(
			task_field_context.get("raw_player_locked", false)
		),
		"raw_target_tile": task_field_context.get(
			"raw_target_tile",
			WorldData.INVALID_CITY_TILE_POSITION
		),
		"food_resource_type": task_field_context.get(
			"raw_food_resource_type",
			""
		),
		"food_requested_amount": task_field_context.get(
			"raw_food_requested_amount",
			0
		),
		"food_source_endpoint_kind": task_field_context.get(
			"raw_food_source_endpoint_kind",
			""
		),
		"food_source_access_purpose": task_field_context.get(
			"raw_food_source_access_purpose",
			""
		),
	}

	if task_kind == WorldData.CITY_CITIZEN_TASK_KIND_NONE:
		_validate_empty_city_citizen_task_state(task_context)
		return

	_validate_active_city_citizen_task_state(task_context)


static func _city_citizen_task_fields_have_valid_types(
	values: Dictionary
) -> bool:
	var errors: Array[String] = values.get("errors", [])
	var citizen_id := int(values.get("citizen_id", -1))
	var raw_target_tile = values.get("raw_target_tile")
	var raw_previous_target_tile = values.get("raw_previous_target_tile")
	var task_types_are_valid := true

	if typeof(values.get("raw_task_kind")) != TYPE_STRING:
		errors.append(
			"Citizen " + str(citizen_id) + " has a non-string task kind."
		)
		task_types_are_valid = false

	if typeof(values.get("raw_task_source")) != TYPE_STRING:
		errors.append(
			"Citizen " + str(citizen_id) + " has a non-string task source."
		)
		task_types_are_valid = false

	if typeof(values.get("raw_task_phase")) != TYPE_STRING:
		errors.append(
			"Citizen " + str(citizen_id) + " has a non-string task phase."
		)
		task_types_are_valid = false

	if typeof(values.get("raw_task_priority")) != TYPE_INT:
		errors.append(
			"Citizen " + str(citizen_id) + " has a non-integer task priority."
		)
		task_types_are_valid = false

	if typeof(values.get("raw_target_object_id")) != TYPE_INT:
		errors.append(
			"Citizen "
			+ str(citizen_id)
			+ " has a non-integer task target object ID."
		)
		task_types_are_valid = false

	if typeof(values.get("raw_work_order_id")) != TYPE_INT:
		errors.append(
			"Citizen " + str(citizen_id) + " has a non-integer work-order ID."
		)
		task_types_are_valid = false

	if typeof(values.get("raw_job_id")) != TYPE_STRING:
		errors.append(
			"Citizen " + str(citizen_id) + " has a non-string job ID."
		)
		task_types_are_valid = false

	if typeof(values.get("raw_start_world_minute")) != TYPE_INT:
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

	if typeof(values.get("raw_next_action_world_minute")) != TYPE_INT:
		errors.append(
			"Citizen "
			+ str(citizen_id)
			+ " has a non-integer next task action minute."
		)
		task_types_are_valid = false

	if typeof(values.get("raw_relocation_count")) != TYPE_INT:
		errors.append(
			"Citizen "
			+ str(citizen_id)
			+ " has a non-integer task relocation count."
		)
		task_types_are_valid = false

	if typeof(values.get("raw_player_locked")) != TYPE_BOOL:
		errors.append(
			"Citizen " + str(citizen_id) + " has a non-boolean task player lock."
		)
		task_types_are_valid = false

	if typeof(values.get("raw_food_resource_type")) != TYPE_STRING:
		errors.append(
			"Citizen " + str(citizen_id) + " has a non-string food task resource."
		)
		task_types_are_valid = false

	if typeof(values.get("raw_food_requested_amount")) != TYPE_INT:
		errors.append(
			"Citizen " + str(citizen_id) + " has a non-integer food task amount."
		)
		task_types_are_valid = false

	if typeof(values.get("raw_food_source_endpoint_kind")) != TYPE_STRING:
		errors.append(
			"Citizen "
			+ str(citizen_id)
			+ " has a non-string food source endpoint kind."
		)
		task_types_are_valid = false

	if typeof(values.get("raw_food_source_access_purpose")) != TYPE_STRING:
		errors.append(
			"Citizen "
			+ str(citizen_id)
			+ " has a non-string food source access purpose."
		)
		task_types_are_valid = false

	return task_types_are_valid


static func _city_citizen_task_enums_are_valid(
	values: Dictionary
) -> bool:
	var errors: Array[String] = values.get("errors", [])
	var citizen_id := int(values.get("citizen_id", -1))
	var task_kind := str(values.get("task_kind", ""))
	var task_source := str(values.get("task_source", ""))
	var task_phase := str(values.get("task_phase", ""))
	var task_values_are_valid := true

	if not CityCitizens.is_valid_city_citizen_task_kind(task_kind):
		errors.append(
			"Citizen "
			+ str(citizen_id)
			+ " has invalid task kind '"
			+ task_kind
			+ "'."
		)
		task_values_are_valid = false

	if not CityCitizens.is_valid_city_citizen_task_source(task_source):
		errors.append(
			"Citizen "
			+ str(citizen_id)
			+ " has invalid task source '"
			+ task_source
			+ "'."
		)
		task_values_are_valid = false

	if not CityCitizens.is_valid_city_citizen_task_phase(task_phase):
		errors.append(
			"Citizen "
			+ str(citizen_id)
			+ " has invalid task phase '"
			+ task_phase
			+ "'."
		)
		task_values_are_valid = false

	return task_values_are_valid


static func _validate_empty_city_citizen_task_state(
	values: Dictionary
) -> void:
	var errors: Array[String] = values.get("errors", [])
	var citizen_id := int(values.get("citizen_id", -1))
	var task_source := str(values.get("task_source", ""))
	var task_phase := str(values.get("task_phase", ""))
	var task_priority := int(values.get("task_priority", 0))
	var target_object_id := int(values.get("target_object_id", -1))
	var work_order_id := int(values.get("work_order_id", -1))
	var job_id := str(values.get("job_id", ""))
	var start_world_minute := int(values.get("start_world_minute", -1))
	var player_locked := bool(values.get("player_locked", false))
	if work_order_id != -1 or not job_id.is_empty():
		errors.append(
			"Citizen "
			+ str(citizen_id)
			+ " has no task but retains a work-order reference."
		)

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

	return


static func _validate_active_city_citizen_task_state(
	values: Dictionary
) -> void:
	var errors: Array[String] = values.get("errors", [])
	var citizen_id := int(values.get("citizen_id", -1))
	var citizen: Dictionary = values.get("citizen", {})
	var object_lookup: Dictionary = values.get("object_lookup", {})
	var expected_active_task_ids: Array[int] = values.get(
		"expected_active_task_ids",
		[]
	)
	var current_task: Dictionary = values.get("current_task", {})
	var task_kind := str(values.get("task_kind", ""))
	var task_source := str(values.get("task_source", ""))
	var task_phase := str(values.get("task_phase", ""))
	var task_priority := int(values.get("task_priority", 0))
	var target_object_id := int(values.get("target_object_id", -1))
	var work_order_id := int(values.get("work_order_id", -1))
	var job_id := str(values.get("job_id", ""))
	var start_world_minute := int(values.get("start_world_minute", -1))
	var player_locked := bool(values.get("player_locked", false))
	var raw_target_tile = values.get(
		"raw_target_tile",
		WorldData.INVALID_CITY_TILE_POSITION
	)
	var raw_food_resource_type = values.get("food_resource_type", "")
	var raw_food_requested_amount = values.get("food_requested_amount", 0)
	var raw_food_source_endpoint_kind = values.get(
		"food_source_endpoint_kind",
		""
	)
	var raw_food_source_access_purpose = values.get(
		"food_source_access_purpose",
		""
	)
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
		and task_kind != WorldData.CITY_CITIZEN_TASK_KIND_ACQUIRE_FOOD
	):
		errors.append(
			"Employed citizen "
			+ str(citizen_id)
			+ " has ineligible task source '"
			+ task_source
			+ "'."
		)

	var task_requires_work_order := (
		task_kind == WorldData.CITY_CITIZEN_TASK_KIND_PLAYER_COMMAND
		or task_kind == WorldData.CITY_CITIZEN_TASK_KIND_CONSTRUCTION
		or (
			task_kind == WorldData.CITY_CITIZEN_TASK_KIND_HAUL
			and task_source
			== WorldData.CITY_CITIZEN_TASK_SOURCE_PLAYER
		)
	)

	if work_order_id < -1 or work_order_id == 0:
		errors.append(
			"Citizen "
			+ str(citizen_id)
			+ " has invalid work-order reference "
			+ str(work_order_id)
			+ "."
		)
	elif work_order_id < 0:
		if not job_id.is_empty():
			errors.append(
				"Citizen "
				+ str(citizen_id)
				+ " has a job ID without a work order."
			)

		if task_requires_work_order:
			errors.append(
				"Citizen "
				+ str(citizen_id)
				+ " has unified player work without a work order."
			)
	else:
		_validate_city_task_work_order_reference({
			"errors": errors,
			"citizen_id": citizen_id,
			"citizen": citizen,
			"task_kind": task_kind,
			"task_source": task_source,
			"target_object_id": target_object_id,
			"work_order_id": work_order_id,
			"job_id": job_id,
		})

	_validate_city_citizen_task_kind_state({
		"errors": errors,
		"citizen_id": citizen_id,
		"citizen": citizen,
		"object_lookup": object_lookup,
		"task_kind": task_kind,
		"task_source": task_source,
		"task_phase": task_phase,
		"target_object_id": target_object_id,
		"work_order_id": work_order_id,
		"job_id": job_id,
		"food_resource_type": raw_food_resource_type,
		"food_requested_amount": raw_food_requested_amount,
		"food_source_endpoint_kind": raw_food_source_endpoint_kind,
		"food_source_access_purpose": raw_food_source_access_purpose,
		"current_task": current_task,
		"player_locked": player_locked,
		"raw_target_tile": raw_target_tile,
	})


static func _validate_city_citizen_task_kind_state(
	values: Dictionary
) -> void:
	var task_kind: String = str(values.get("task_kind", ""))

	match task_kind:
		WorldData.CITY_CITIZEN_TASK_KIND_WORK:
			_validate_work_task_kind_state(values)
		WorldData.CITY_CITIZEN_TASK_KIND_ACQUIRE_FOOD:
			_validate_acquire_food_task_kind_state(values)
		WorldData.CITY_CITIZEN_TASK_KIND_HAUL:
			_validate_haul_task_kind_state(values)
		WorldData.CITY_CITIZEN_TASK_KIND_CONSTRUCTION:
			_validate_construction_task_kind_state(values)
		WorldData.CITY_CITIZEN_TASK_KIND_PLAYER_COMMAND:
			_validate_player_command_task_kind_state(values)
		WorldData.CITY_CITIZEN_TASK_KIND_RETURN_HOME:
			_validate_return_home_task_kind_state(values)

static func _validate_work_task_kind_state(values: Dictionary) -> void:
	var errors: Array[String] = values.get("errors", [])
	var citizen_id := int(values.get("citizen_id", -1))
	var citizen: Dictionary = values.get("citizen", {})
	var object_lookup: Dictionary = values.get("object_lookup", {})
	var task_source := str(values.get("task_source", ""))
	var task_phase := str(values.get("task_phase", ""))
	var target_object_id := int(values.get("target_object_id", -1))
	var current_task: Dictionary = values.get("current_task", {})
	var player_locked := bool(values.get("player_locked", false))
	var raw_target_tile = values.get(
		"raw_target_tile",
		WorldData.INVALID_CITY_TILE_POSITION
	)
	var raw_food_resource_type = values.get("food_resource_type", "")
	var raw_food_requested_amount = values.get("food_requested_amount", 0)
	var raw_food_source_endpoint_kind = values.get(
		"food_source_endpoint_kind",
		""
	)
	var raw_food_source_access_purpose = values.get(
		"food_source_access_purpose",
		""
	)
	if target_object_id <= 0:
		errors.append(
			"Citizen "
			+ str(citizen_id)
			+ " work task has invalid target object ID "
			+ str(target_object_id)
			+ "."
		)
		return

	if not object_lookup.has(target_object_id):
		errors.append(
			"Citizen "
			+ str(citizen_id)
			+ " work task targets missing object "
			+ str(target_object_id)
			+ "."
		)
		return

	var target_object := (
		CityObjectSystem.get_city_object_by_id(
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
		and not CityEmploymentSystem.is_city_citizen_attending_workplace(
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


static func _validate_acquire_food_task_kind_state(values: Dictionary) -> void:
	var errors: Array[String] = values.get("errors", [])
	var citizen_id := int(values.get("citizen_id", -1))
	var citizen: Dictionary = values.get("citizen", {})
	var object_lookup: Dictionary = values.get("object_lookup", {})
	var task_source := str(values.get("task_source", ""))
	var task_phase := str(values.get("task_phase", ""))
	var target_object_id := int(values.get("target_object_id", -1))
	var current_task: Dictionary = values.get("current_task", {})
	var player_locked := bool(values.get("player_locked", false))
	var raw_target_tile = values.get(
		"raw_target_tile",
		WorldData.INVALID_CITY_TILE_POSITION
	)
	var raw_food_resource_type = values.get("food_resource_type", "")
	var raw_food_requested_amount = values.get("food_requested_amount", 0)
	var raw_food_source_endpoint_kind = values.get(
		"food_source_endpoint_kind",
		""
	)
	var raw_food_source_access_purpose = values.get(
		"food_source_access_purpose",
		""
	)
	var food_endpoint_kind: String = raw_food_source_endpoint_kind
	var food_endpoint := (
		CityCitizens.make_city_citizen_haul_endpoint({
		"kind": food_endpoint_kind,
		"id": target_object_id,
		})
	)

	if (
		target_object_id <= 0
		or food_endpoint_kind not in [
			WorldData
			.CITY_CITIZEN_HAUL_ENDPOINT_KIND_CITY_OBJECT_CONTAINER,
			WorldData.CITY_CITIZEN_HAUL_ENDPOINT_KIND_GROUND_PILE,
		]
		or not CityCitizens.is_valid_city_citizen_haul_endpoint(
			food_endpoint
		)
		or not CityLogisticsStateValidator._city_haul_endpoint_schema_is_valid(food_endpoint)
	):
		errors.append(
			"Citizen "
			+ str(citizen_id)
			+ " food task targets invalid endpoint "
			+ str(target_object_id)
			+ "."
		)
		return

	var food_resource: String = raw_food_resource_type
	var food_requested_amount: int = raw_food_requested_amount
	var food_access_purpose: String = raw_food_source_access_purpose

	if CityResourceCatalog.get_city_food_hunger_restore(food_resource) <= 0:
		errors.append(
			"Citizen "
			+ str(citizen_id)
			+ " food task has non-food resource '"
			+ food_resource
			+ "'."
		)

	if food_requested_amount <= 0:
		errors.append(
			"Citizen "
			+ str(citizen_id)
			+ " food task has no requested amount."
		)

	if (
		food_access_purpose
		!= WorldData.CONTAINER_DIRECT_WITHDRAWAL_PURPOSE_PERSONAL_FOOD
	):
		errors.append(
			"Citizen "
			+ str(citizen_id)
			+ " food task has invalid source access purpose '"
			+ food_access_purpose
			+ "'."
		)

	var raw_food_target_tile = current_task.get(
		"target_tile",
		WorldData.INVALID_CITY_TILE_POSITION
	)

	if (
		not raw_food_target_tile is Vector2i
		or not CitizenNeedsSystem.get_city_citizen_food_endpoint_target_tiles(
			citizen_id,
			food_endpoint
		).has(raw_food_target_tile)
	):
		errors.append(
			"Citizen "
			+ str(citizen_id)
			+ " food task has an invalid withdrawal target tile."
		)

	if not CitizenNeedsSystem.city_citizen_can_withdraw_food_from_endpoint(
		citizen_id,
		food_endpoint,
		food_resource
	):
		errors.append(
			"Citizen "
			+ str(citizen_id)
			+ " cannot withdraw its reserved food from endpoint "
			+ str(target_object_id)
			+ "."
		)


static func _validate_haul_task_kind_state(values: Dictionary) -> void:
	var errors: Array[String] = values.get("errors", [])
	var citizen_id := int(values.get("citizen_id", -1))
	var citizen: Dictionary = values.get("citizen", {})
	var object_lookup: Dictionary = values.get("object_lookup", {})
	var task_source := str(values.get("task_source", ""))
	var task_phase := str(values.get("task_phase", ""))
	var target_object_id := int(values.get("target_object_id", -1))
	var current_task: Dictionary = values.get("current_task", {})
	var player_locked := bool(values.get("player_locked", false))
	var raw_target_tile = values.get(
		"raw_target_tile",
		WorldData.INVALID_CITY_TILE_POSITION
	)
	var raw_food_resource_type = values.get("food_resource_type", "")
	var raw_food_requested_amount = values.get("food_requested_amount", 0)
	var raw_food_source_endpoint_kind = values.get(
		"food_source_endpoint_kind",
		""
	)
	var raw_food_source_access_purpose = values.get(
		"food_source_access_purpose",
		""
	)
	if not CityCitizens.has_complete_city_citizen_haul_state(
		citizen
	):
		errors.append(
			"Citizen "
				+ str(citizen_id)
				+ " has an active haul task with incomplete haul state."
		)
		return

	var raw_haul = citizen.get("current_haul", {})
	var raw_cargo = citizen.get("haul_cargo", {})

	if not raw_haul is Dictionary:
		return

	if not raw_cargo is Dictionary:
		return

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

		if (
			not CityCitizens.is_valid_city_citizen_haul_endpoint(
				haul_source
			)
			or not CityLogisticsStateValidator._city_haul_endpoint_schema_is_valid(
				haul_source
			)
			or str(haul_source.get("kind", ""))
			== WorldData
			.CITY_CITIZEN_HAUL_ENDPOINT_KIND_GROUND_TILE
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
	elif (
		not CityCitizens.is_valid_city_citizen_haul_endpoint(
			raw_haul_requester
		)
		or not CityLogisticsStateValidator._city_haul_endpoint_schema_is_valid(
			raw_haul_requester
		)
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

		if (
			not CityCitizens.is_valid_city_citizen_haul_endpoint(
				haul_destination,
				cargo_amount > 0
			)
			or not CityLogisticsStateValidator._city_haul_endpoint_schema_is_valid(
				haul_destination,
				cargo_amount > 0
			)
		):
			errors.append(
				"Citizen "
					+ str(citizen_id)
					+ " haul task has invalid destination endpoint."
			)
		elif (
			str(haul_destination.get("kind", ""))
			== WorldData
			.CITY_CITIZEN_HAUL_ENDPOINT_KIND_GROUND_TILE
			and haul.get(
				"destination_tile",
				WorldData.INVALID_CITY_TILE_POSITION
			) != haul_destination.get(
				"tile_position",
				WorldData.INVALID_CITY_TILE_POSITION
			)
		):
			errors.append(
				"Citizen "
				+ str(citizen_id)
				+ " ground-drop endpoint and destination tile disagree."
			)


static func _validate_construction_task_kind_state(values: Dictionary) -> void:
	var errors: Array[String] = values.get("errors", [])
	var citizen_id := int(values.get("citizen_id", -1))
	var citizen: Dictionary = values.get("citizen", {})
	var object_lookup: Dictionary = values.get("object_lookup", {})
	var task_source := str(values.get("task_source", ""))
	var task_phase := str(values.get("task_phase", ""))
	var target_object_id := int(values.get("target_object_id", -1))
	var current_task: Dictionary = values.get("current_task", {})
	var player_locked := bool(values.get("player_locked", false))
	var raw_target_tile = values.get(
		"raw_target_tile",
		WorldData.INVALID_CITY_TILE_POSITION
	)
	var raw_food_resource_type = values.get("food_resource_type", "")
	var raw_food_requested_amount = values.get("food_requested_amount", 0)
	var raw_food_source_endpoint_kind = values.get(
		"food_source_endpoint_kind",
		""
	)
	var raw_food_source_access_purpose = values.get(
		"food_source_access_purpose",
		""
	)
	var construction_site := (
		CityConstructionSystem.get_city_construction_site_by_id(
			target_object_id
		)
	)

	if construction_site.is_empty():
		errors.append(
			"Citizen "
			+ str(citizen_id)
			+ " targets missing construction site "
			+ str(target_object_id)
			+ "."
		)
		return

	if (
		task_source
		!= WorldData.CITY_CITIZEN_TASK_SOURCE_PLAYER
		or player_locked
	):
		errors.append(
			"Citizen "
			+ str(citizen_id)
			+ " has invalid construction task ownership."
		)

	if (
		str(construction_site.get("phase", ""))
		!= CityConstructionSystem.CITY_CONSTRUCTION_PHASE_LABOR
	):
		errors.append(
			"Citizen "
			+ str(citizen_id)
			+ " performs labor outside a site's labor phase."
		)

	if (
		not construction_site.get(
			"work_positions",
			[]
		).has(raw_target_tile)
	):
		errors.append(
			"Citizen "
			+ str(citizen_id)
			+ " has an invalid construction work position."
		)


static func _validate_player_command_task_kind_state(values: Dictionary) -> void:
	var errors: Array[String] = values.get("errors", [])
	var citizen_id := int(values.get("citizen_id", -1))
	var citizen: Dictionary = values.get("citizen", {})
	var object_lookup: Dictionary = values.get("object_lookup", {})
	var task_source := str(values.get("task_source", ""))
	var task_phase := str(values.get("task_phase", ""))
	var target_object_id := int(values.get("target_object_id", -1))
	var current_task: Dictionary = values.get("current_task", {})
	var player_locked := bool(values.get("player_locked", false))
	var raw_target_tile = values.get(
		"raw_target_tile",
		WorldData.INVALID_CITY_TILE_POSITION
	)
	var raw_food_resource_type = values.get("food_resource_type", "")
	var raw_food_requested_amount = values.get("food_requested_amount", 0)
	var raw_food_source_endpoint_kind = values.get(
		"food_source_endpoint_kind",
		""
	)
	var raw_food_source_access_purpose = values.get(
		"food_source_access_purpose",
		""
	)
	if target_object_id <= 0:
		errors.append(
			"Citizen "
			+ str(citizen_id)
			+ " player command has invalid command ID "
			+ str(target_object_id)
			+ "."
		)
		return

	var player_command := (
		CityWorkSystem.get_city_player_command_by_id(
			target_object_id
		)
	)

	if player_command.is_empty():
		errors.append(
			"Citizen "
			+ str(citizen_id)
			+ " targets missing player command "
			+ str(target_object_id)
			+ "."
		)
		return

	if (
		task_source
		!= WorldData.CITY_CITIZEN_TASK_SOURCE_PLAYER
	):
		errors.append(
			"Citizen "
			+ str(citizen_id)
			+ " has a player command without player ownership."
		)

	if int(
		player_command.get("claimed_citizen_id", -1)
	) != citizen_id:
		errors.append(
			"Citizen "
			+ str(citizen_id)
			+ " does not own player command claim "
			+ str(target_object_id)
			+ "."
		)

	if (
		not CityWorkSystem.get_city_player_command_work_tiles(
			player_command,
			citizen_id
		).has(raw_target_tile)
	):
		errors.append(
			"Citizen "
				+ str(citizen_id)
				+ " has an invalid work tile for command "
			+ str(target_object_id)
			+ "."
		)


static func _validate_return_home_task_kind_state(values: Dictionary) -> void:
	var errors: Array[String] = values.get("errors", [])
	var citizen_id := int(values.get("citizen_id", -1))
	var citizen: Dictionary = values.get("citizen", {})
	var object_lookup: Dictionary = values.get("object_lookup", {})
	var task_source := str(values.get("task_source", ""))
	var task_phase := str(values.get("task_phase", ""))
	var target_object_id := int(values.get("target_object_id", -1))
	var current_task: Dictionary = values.get("current_task", {})
	var player_locked := bool(values.get("player_locked", false))
	var raw_target_tile = values.get(
		"raw_target_tile",
		WorldData.INVALID_CITY_TILE_POSITION
	)
	var raw_food_resource_type = values.get("food_resource_type", "")
	var raw_food_requested_amount = values.get("food_requested_amount", 0)
	var raw_food_source_endpoint_kind = values.get(
		"food_source_endpoint_kind",
		""
	)
	var raw_food_source_access_purpose = values.get(
		"food_source_access_purpose",
		""
	)
	if target_object_id <= 0:
		errors.append(
			"Citizen "
			+ str(citizen_id)
			+ " return-home task has invalid target object ID "
			+ str(target_object_id)
			+ "."
		)
		return

	if not object_lookup.has(target_object_id):
		errors.append(
			"Citizen "
			+ str(citizen_id)
			+ " return-home task targets missing object "
			+ str(target_object_id)
			+ "."
		)
		return

	var target_home := CityObjectSystem.get_city_object_by_id(
		target_object_id
	)

	if (
		WorldData.get_city_object_resident_capacity(
			target_home
		) <= 0
		or not CityObjectSystem.city_object_supports_citizen_interior(
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

	if not CityAssignmentSystem.get_city_object_resident_ids(
		target_home
	).has(citizen_id):
		errors.append(
			"Citizen "
			+ str(citizen_id)
			+ " return-home task lacks resident membership in "
			+ str(target_object_id)
			+ "."
		)

	if not CityNavigationSystem.city_citizen_can_access_object_interior(
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


static func _validate_city_active_task_registry(
	errors: Array[String],
	citizen_lookup: Dictionary,
	expected_active_task_ids: Array[int]
) -> void:
	if CityCitizenTaskRuntimeSystem.get_current_state().active_task_ids != expected_active_task_ids:
		errors.append(
			"Active task registry does not match living citizens "
				+ "with active tasks. Expected "
				+ str(expected_active_task_ids)
				+ ", found "
				+ str(CityCitizenTaskRuntimeSystem.get_current_state().active_task_ids)
				+ "."
		)

	var seen_active_task_ids: Dictionary = {}

	for raw_active_task_id in CityCitizenTaskRuntimeSystem.get_current_state().active_task_ids:
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

		if not CityCitizenTaskRuntimeSystem.get_current_state().active_task_id_lookup.has(
			active_task_id
		):
			errors.append(
				"Active task lookup is missing citizen ID "
					+ str(active_task_id)
					+ "."
			)
		elif not bool(
			CityCitizenTaskRuntimeSystem.get_current_state().active_task_id_lookup[active_task_id]
		):
			errors.append(
				"Active task lookup is false for citizen ID "
					+ str(active_task_id)
					+ "."
			)

	for raw_lookup_id in CityCitizenTaskRuntimeSystem.get_current_state().active_task_id_lookup.keys():
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
		CityCitizenTaskRuntimeSystem.get_current_state().active_task_id_lookup.size()
		!= CityCitizenTaskRuntimeSystem.get_current_state().active_task_ids.size()
	):
		errors.append(
			"Active task registry array and lookup have different sizes."
		)


static func _validate_city_task_work_order_reference(
	values: Dictionary
) -> void:
	var errors: Array[String] = values.get("errors", [])
	var citizen_id := int(values.get("citizen_id", -1))
	var citizen: Dictionary = values.get("citizen", {})
	var task_kind := str(values.get("task_kind", ""))
	var task_source := str(values.get("task_source", ""))
	var target_object_id := int(values.get("target_object_id", -1))
	var work_order_id := int(values.get("work_order_id", -1))
	var job_id := str(values.get("job_id", ""))
	var order := CityWorkSystem.get_city_work_order_by_id(work_order_id)

	if order.is_empty():
		errors.append(
			"Citizen "
			+ str(citizen_id)
			+ " references missing work order "
			+ str(work_order_id)
			+ "."
		)
		return

	if job_id.is_empty():
		errors.append(
			"Citizen "
			+ str(citizen_id)
			+ " references work order "
			+ str(work_order_id)
			+ " without a job ID."
		)

	if (
		task_source != WorldData.CITY_CITIZEN_TASK_SOURCE_PLAYER
		or str(order.get("state", ""))
		== CityWorkSystemScript.ORDER_STATE_CANCELLED
	):
		errors.append(
			"Citizen "
			+ str(citizen_id)
			+ " has an inactive or non-player work-order task."
		)

	var order_type := str(order.get("order_type", ""))
	var source_id := int(order.get("source_id", -1))
	var source_matches_task := false

	if order_type == CityWorkSystemScript.ORDER_TYPE_COMMAND_GROUP:
		var command := CityWorkSystem.get_city_player_command_by_id(
			target_object_id
		)
		source_matches_task = (
			task_kind == WorldData.CITY_CITIZEN_TASK_KIND_PLAYER_COMMAND
			and not command.is_empty()
			and int(command.get("group_id", -1)) == source_id
			and int(command.get("construction_site_id", -1)) <= 0
		)
	elif order_type == CityWorkSystemScript.ORDER_TYPE_CONSTRUCTION_SITE:
		match task_kind:
			WorldData.CITY_CITIZEN_TASK_KIND_PLAYER_COMMAND:
				var command := CityWorkSystem.get_city_player_command_by_id(
					target_object_id
				)
				source_matches_task = (
					not command.is_empty()
					and int(command.get("construction_site_id", -1))
					== source_id
				)

			WorldData.CITY_CITIZEN_TASK_KIND_CONSTRUCTION:
				source_matches_task = target_object_id == source_id

			WorldData.CITY_CITIZEN_TASK_KIND_HAUL:
				var raw_haul = citizen.get("current_haul", {})

				if raw_haul is Dictionary:
					var raw_requester = raw_haul.get("requester", {})

					if raw_requester is Dictionary:
						source_matches_task = (
							str(raw_requester.get("kind", ""))
							== WorldData
							.CITY_CITIZEN_HAUL_ENDPOINT_KIND_CONSTRUCTION_SITE
							and int(raw_requester.get("id", -1))
							== source_id
						)

	if not source_matches_task:
		errors.append(
			"Citizen "
			+ str(citizen_id)
			+ " task does not belong to referenced work order "
			+ str(work_order_id)
			+ "."
		)




#endregion

#region Citizen Movement
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
		_validate_city_citizen_movement_entry({
			"errors": errors,
			"citizen_lookup": citizen_lookup,
			"city_world": city_world,
			"required_fields": required_fields,
			"expected_active_ids": expected_active_ids,
			"citizen_id": citizen_id,
		})

	_validate_city_active_mover_registry(
		errors,
		citizen_lookup,
		expected_active_ids
	)


static func _validate_city_citizen_movement_entry(
	values: Dictionary
) -> void:
	var errors: Array[String] = values.get("errors", [])
	var citizen_lookup: Dictionary = values.get("citizen_lookup", {})
	var city_world: WorldData = values.get("city_world")
	var required_fields: Array = values.get("required_fields", [])
	var expected_active_ids: Dictionary = values.get(
		"expected_active_ids",
		{}
	)
	var citizen_id := int(values.get("citizen_id", -1))
	var citizen_index := int(
		citizen_lookup[citizen_id]
	)
	var citizen: Dictionary = (
		CityCitizenRegistrySystem.get_current_state().citizens[citizen_index]
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
		return

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
		return

	var movement_state: String = raw_state

	if not CityCitizens.is_valid_city_citizen_movement_state(
		movement_state
	):
		errors.append(
			"Citizen "
				+ str(citizen_id)
				+ " has invalid movement state '"
				+ movement_state
				+ "'."
		)
		return

	if not raw_path is Array:
		errors.append(
			"Citizen "
				+ str(citizen_id)
				+ " has non-Array movement path."
		)
		return

	if typeof(raw_index) != TYPE_INT:
		errors.append(
			"Citizen "
				+ str(citizen_id)
				+ " has non-integer movement path index."
		)
		return

	if typeof(raw_progress) != TYPE_INT:
		errors.append(
			"Citizen "
				+ str(citizen_id)
				+ " has non-integer movement progress."
		)
		return

	if not raw_destination is Vector2i:
		errors.append(
			"Citizen "
				+ str(citizen_id)
				+ " has non-Vector2i movement destination."
		)
		return

	if typeof(raw_speed) != TYPE_INT or int(raw_speed) <= 0:
		errors.append(
			"Citizen "
				+ str(citizen_id)
				+ " has invalid movement speed."
		)
		return

	if typeof(raw_repath_attempt_count) != TYPE_INT:
		errors.append(
			"Citizen "
				+ str(citizen_id)
				+ " has non-integer movement repath attempt count."
		)
		return

	if typeof(raw_failure) != TYPE_STRING:
		errors.append(
			"Citizen "
				+ str(citizen_id)
				+ " has non-string movement failure reason."
		)
		return

	if not CityCitizens.is_valid_city_citizen_movement_failure(
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
	var movement_context := {
		"errors": errors,
		"citizen_id": citizen_id,
		"citizen": citizen,
		"city_world": city_world,
		"expected_active_ids": expected_active_ids,
		"movement_state": movement_state,
		"movement_path": movement_path,
		"movement_index": movement_index,
		"movement_progress": movement_progress,
		"movement_destination": movement_destination,
		"movement_repath_attempt_count": movement_repath_attempt_count,
		"raw_failure": raw_failure,
	}
	var path_entries_valid := _validate_city_citizen_movement_path(
		movement_context
	)
	movement_context["path_entries_valid"] = path_entries_valid
	_validate_city_citizen_movement_state_details(movement_context)


static func _validate_city_citizen_movement_path(
	values: Dictionary
) -> bool:
	var errors: Array[String] = values.get("errors", [])
	var citizen_id := int(values.get("citizen_id", -1))
	var city_world: WorldData = values.get("city_world")
	var movement_path: Array = values.get("movement_path", [])
	var movement_progress := int(values.get("movement_progress", 0))
	var movement_repath_attempt_count := int(
		values.get("movement_repath_attempt_count", 0)
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
				CityNavigationSystem.get_city_citizen_movement_step_cost(
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
				and not CityNavigationSystem.can_city_citizen_traverse_step(
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

	return path_entries_valid


static func _validate_city_citizen_movement_state_details(
	values: Dictionary
) -> void:
	var errors: Array[String] = values.get("errors", [])
	var citizen_id := int(values.get("citizen_id", -1))
	var citizen: Dictionary = values.get("citizen", {})
	var expected_active_ids: Dictionary = values.get(
		"expected_active_ids",
		{}
	)
	var movement_state := str(values.get("movement_state", ""))
	var movement_path: Array = values.get("movement_path", [])
	var movement_index := int(values.get("movement_index", 0))
	var movement_progress := int(values.get("movement_progress", 0))
	var movement_destination: Vector2i = values.get(
		"movement_destination",
		WorldData.INVALID_CITY_TILE_POSITION
	)
	var movement_repath_attempt_count := int(
		values.get("movement_repath_attempt_count", 0)
	)
	var raw_failure = values.get(
		"raw_failure",
		WorldData.CITY_CITIZEN_MOVEMENT_FAILURE_NONE
	)
	var path_entries_valid := bool(values.get("path_entries_valid", false))
	var citizen_is_active := (
		CityCitizenMovementRuntimeSystem.get_current_state().active_mover_id_lookup.has(
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
					CityNavigationSystem.get_city_citizen_movement_step_cost(
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


static func _validate_city_active_mover_registry(
	errors: Array[String],
	citizen_lookup: Dictionary,
	expected_active_ids: Dictionary
) -> void:
	var active_array_lookup: Dictionary = {}
	var previous_active_id := -1

	for active_citizen_id in CityCitizenMovementRuntimeSystem.get_current_state().active_mover_ids:
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
			CityCitizenRegistrySystem.get_current_state().citizens[
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

		if not CityCitizenMovementRuntimeSystem.get_current_state().active_mover_id_lookup.has(
			active_citizen_id
		):
			errors.append(
				"Active-mover lookup is missing citizen "
					+ str(active_citizen_id)
					+ "."
			)

	for lookup_id in CityCitizenMovementRuntimeSystem.get_current_state().active_mover_id_lookup.keys():
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



#endregion
