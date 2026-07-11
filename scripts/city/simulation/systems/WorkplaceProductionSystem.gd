extends RefCounted
class_name WorkplaceProductionSystem

const WORK_UNITS_PER_WORKER_MINUTE: int = 1_000
static var _resource_source_evaluation_cache: Dictionary = {}
static var _preview_resource_source_evaluation_cache: Dictionary = {}


static func clear_resource_source_evaluation_cache() -> void:
	_resource_source_evaluation_cache.clear()
	_preview_resource_source_evaluation_cache.clear()


static func get_resource_source_evaluation(
	city_object: Dictionary,
	source_world = null
) -> Dictionary:
	var evaluation := _make_empty_resource_source_evaluation(
		city_object
	)
	var policy := WorldData.get_city_object_resource_source_policy(
		city_object
	)
	var mode := str(
		policy.get(
			"mode",
			WorldData.WORKPLACE_RESOURCE_SOURCE_MODE_NONE
		)
	)

	if (
		mode
		!= WorldData.WORKPLACE_RESOURCE_SOURCE_MODE_FOOTPRINT_REACH
	):
		return evaluation

	var resource_type := str(
		policy.get("resource_type", WorldData.RESOURCE_NONE)
	)
	var reach_tiles := int(policy.get("reach_tiles", 0))
	var source_tiles_for_full_productivity := int(
		policy.get("source_tiles_for_full_productivity", 0)
	)

	evaluation["is_configured"] = true
	evaluation["is_supported"] = true
	evaluation["uses_environmental_source"] = true
	evaluation["mode"] = mode
	evaluation["resource_type"] = resource_type
	evaluation["source_resource"] = resource_type
	evaluation["reach_tiles"] = reach_tiles

	# Temporary compatibility alias for the earlier diagnostic panel.
	evaluation["radius_tiles"] = reach_tiles

	evaluation["source_tiles_for_full_productivity"] = (
		source_tiles_for_full_productivity
	)
	evaluation["site_productivity_basis_points"] = 0

	var active_world = source_world

	if active_world == null:
		active_world = WorldData.official_city_world

	if active_world == null:
		return evaluation

	if resource_type == WorldData.RESOURCE_NONE:
		return evaluation

	if reach_tiles < 0:
		return evaluation

	if source_tiles_for_full_productivity <= 0:
		return evaluation

	var footprint_tiles := _get_unique_footprint_tiles(
		city_object
	)

	if footprint_tiles.is_empty():
		return evaluation

	var world_instance_id := int(active_world.get_instance_id())
	var tile_data_version := int(active_world.tile_data_version)
	var object_id := int(city_object.get("id", -1))
	var object_type := str(city_object.get("type", ""))
	var cache_entry: Dictionary = {}

	if object_id > 0:
		var raw_cache_entry = _resource_source_evaluation_cache.get(
			object_id,
			{}
		)

		if raw_cache_entry is Dictionary:
			cache_entry = raw_cache_entry
	else:
		cache_entry = _preview_resource_source_evaluation_cache

	if _resource_source_cache_matches(
		cache_entry,
		world_instance_id,
		tile_data_version,
		object_type,
		footprint_tiles,
		resource_type,
		reach_tiles,
		source_tiles_for_full_productivity
	):
		var raw_cached_evaluation = cache_entry.get(
			"evaluation",
			{}
		)

		if raw_cached_evaluation is Dictionary:
			return raw_cached_evaluation

	var zone_result := _build_footprint_reach_zone(
		active_world,
		footprint_tiles,
		reach_tiles,
		resource_type
	)
	var zone_tiles: Array = zone_result.get("zone_tiles", [])
	var resource_tiles: Array = zone_result.get(
		"resource_tiles",
		[]
	)
	var zone_tile_count := zone_tiles.size()
	var resource_tile_count := resource_tiles.size()
	var density_basis_points := 0

	if zone_tile_count > 0:
		density_basis_points = int(
			round(
				float(resource_tile_count)
				* float(WorldData.PRODUCTIVITY_BASIS_POINTS_SCALE)
				/ float(zone_tile_count)
			)
		)

	var site_productivity_basis_points := mini(
		int(
			round(
				float(resource_tile_count)
				* float(WorldData.PRODUCTIVITY_BASIS_POINTS_SCALE)
				/ float(source_tiles_for_full_productivity)
			)
		),
		WorldData.PRODUCTIVITY_BASIS_POINTS_SCALE
	)

	evaluation["zone_tiles"] = zone_tiles
	evaluation["candidate_tiles"] = zone_tiles
	evaluation["zone_tile_lookup"] = zone_result.get(
		"zone_tile_lookup",
		{}
	)
	evaluation["resource_tiles"] = resource_tiles
	evaluation["valid_source_tiles"] = resource_tiles
	evaluation["resource_tile_lookup"] = zone_result.get(
		"resource_tile_lookup",
		{}
	)
	evaluation["zone_tile_count"] = zone_tile_count
	evaluation["candidate_tile_count"] = zone_tile_count
	evaluation["resource_tile_count"] = resource_tile_count
	evaluation["valid_tile_count"] = resource_tile_count
	evaluation["valid_source_tile_count"] = resource_tile_count
	evaluation["density_basis_points"] = density_basis_points
	evaluation["source_density_basis_points"] = density_basis_points
	evaluation["site_productivity_basis_points"] = (
		site_productivity_basis_points
	)
	evaluation["has_resource"] = resource_tile_count > 0

	var new_cache_entry := {
		"world_instance_id": world_instance_id,
		"tile_data_version": tile_data_version,
		"object_type": object_type,
		"footprint_tiles": footprint_tiles.duplicate(),
		"resource_type": resource_type,
		"reach_tiles": reach_tiles,
		"source_tiles_for_full_productivity": (
			source_tiles_for_full_productivity
		),
		"evaluation": evaluation
	}

	if object_id > 0:
		_resource_source_evaluation_cache[object_id] = (
			new_cache_entry
		)
	else:
		_preview_resource_source_evaluation_cache = (
			new_cache_entry
		)

	return evaluation


static func get_current_site_productivity_basis_points(
	city_object: Dictionary,
	source_world = null
) -> int:
	var evaluation := get_resource_source_evaluation(
		city_object,
		source_world
	)

	if bool(
		evaluation.get(
			"uses_environmental_source",
			false
		)
	):
		return maxi(
			int(
				evaluation.get(
					"site_productivity_basis_points",
					0
				)
			),
			0
		)

	return WorldData.get_city_object_site_productivity_basis_points(
		city_object
	)


static func _make_empty_resource_source_evaluation(
	city_object: Dictionary
) -> Dictionary:
	return {
		"is_configured": false,
		"is_supported": false,
		"uses_environmental_source": false,
		"mode": WorldData.WORKPLACE_RESOURCE_SOURCE_MODE_NONE,
		"resource_type": WorldData.RESOURCE_NONE,
		"source_resource": WorldData.RESOURCE_NONE,
		"reach_tiles": 0,
		"radius_tiles": 0,
		"source_tiles_for_full_productivity": 0,
		"zone_tiles": [],
		"candidate_tiles": [],
		"zone_tile_lookup": {},
		"resource_tiles": [],
		"valid_source_tiles": [],
		"resource_tile_lookup": {},
		"zone_tile_count": 0,
		"candidate_tile_count": 0,
		"resource_tile_count": 0,
		"valid_tile_count": 0,
		"valid_source_tile_count": 0,
		"density_basis_points": 0,
		"source_density_basis_points": 0,
		"site_productivity_basis_points": (
			WorldData.get_city_object_site_productivity_basis_points(
				city_object
			)
		),
		"has_resource": false
	}


static func _get_unique_footprint_tiles(
	city_object: Dictionary
) -> Array:
	var unique_tiles: Array = []
	var tile_lookup: Dictionary = {}

	for raw_tile in WorldData.get_city_object_footprint_tiles(
		city_object
	):
		if not raw_tile is Vector2i:
			continue

		var tile: Vector2i = raw_tile

		if tile_lookup.has(tile):
			continue

		tile_lookup[tile] = true
		unique_tiles.append(tile)

	return unique_tiles


static func _build_footprint_reach_zone(
	source_world,
	footprint_tiles: Array,
	reach_tiles: int,
	resource_type: String
) -> Dictionary:
	var zone_tile_lookup: Dictionary = {}
	var reach_squared := reach_tiles * reach_tiles

	for raw_footprint_tile in footprint_tiles:
		if not raw_footprint_tile is Vector2i:
			continue

		var footprint_tile: Vector2i = raw_footprint_tile

		for offset_y in range(-reach_tiles, reach_tiles + 1):
			for offset_x in range(-reach_tiles, reach_tiles + 1):
				var distance_squared := (
					offset_x * offset_x
					+ offset_y * offset_y
				)

				if distance_squared > reach_squared:
					continue

				var candidate_tile := (
					footprint_tile
					+ Vector2i(offset_x, offset_y)
				)

				if not source_world.is_in_bounds(
					candidate_tile.x,
					candidate_tile.y
				):
					continue

				zone_tile_lookup[candidate_tile] = true

	var zone_tiles: Array = zone_tile_lookup.keys()
	var resource_tiles: Array = []
	var resource_tile_lookup: Dictionary = {}

	for raw_zone_tile in zone_tiles:
		if not raw_zone_tile is Vector2i:
			continue

		var zone_tile: Vector2i = raw_zone_tile
		var tile_data: Dictionary = source_world.get_tile(
			zone_tile.x,
			zone_tile.y
		)

		if (
			str(
				tile_data.get(
					"resource",
					WorldData.RESOURCE_NONE
				)
			)
			!= resource_type
		):
			continue

		resource_tiles.append(zone_tile)
		resource_tile_lookup[zone_tile] = true

	return {
		"zone_tiles": zone_tiles,
		"zone_tile_lookup": zone_tile_lookup,
		"resource_tiles": resource_tiles,
		"resource_tile_lookup": resource_tile_lookup
	}


static func _resource_source_cache_matches(
	cache_entry: Dictionary,
	world_instance_id: int,
	tile_data_version: int,
	object_type: String,
	footprint_tiles: Array,
	resource_type: String,
	reach_tiles: int,
	source_tiles_for_full_productivity: int
) -> bool:
	if cache_entry.is_empty():
		return false

	return (
		int(cache_entry.get("world_instance_id", -1))
		== world_instance_id
		and int(cache_entry.get("tile_data_version", -1))
		== tile_data_version
		and str(cache_entry.get("object_type", ""))
		== object_type
		and cache_entry.get("footprint_tiles", [])
		== footprint_tiles
		and str(cache_entry.get("resource_type", ""))
		== resource_type
		and int(cache_entry.get("reach_tiles", -1))
		== reach_tiles
		and int(
			cache_entry.get(
				"source_tiles_for_full_productivity",
				-1
			)
		)
		== source_tiles_for_full_productivity
	)

static func get_estimated_output_per_hour(
	city_object: Dictionary,
	resource: String
) -> float:
	if city_object.is_empty():
		return 0.0

	if resource == WorldData.RESOURCE_NONE:
		return 0.0

	var recipe := WorldData.get_city_object_production_recipe(
		city_object
	)
	var raw_work_units_per_batch = recipe.get(
		"work_units_per_batch",
		0
	)
	var raw_outputs = recipe.get("outputs", {})

	if not raw_work_units_per_batch is int:
		return 0.0

	if int(raw_work_units_per_batch) <= 0:
		return 0.0

	if not raw_outputs is Dictionary:
		return 0.0

	var outputs: Dictionary = raw_outputs
	var raw_output_amount = outputs.get(resource, 0)

	if not raw_output_amount is int:
		return 0.0

	var output_amount_per_batch := int(raw_output_amount)

	if output_amount_per_batch <= 0:
		return 0.0

	var productive_worker_count := (
		WorldData.get_city_object_productive_worker_count(
			city_object
		)
	)
	var site_productivity := (
		get_current_site_productivity_basis_points(
			city_object
		)
	)

	if productive_worker_count <= 0:
		return 0.0

	if site_productivity <= 0:
		return 0.0

	var effective_work_units_per_hour := (
		float(
			SimulationClock.MINUTES_PER_HOUR
			* productive_worker_count
			* WORK_UNITS_PER_WORKER_MINUTE
		)
		* float(site_productivity)
		/ float(WorldData.PRODUCTIVITY_BASIS_POINTS_SCALE)
	)

	var completed_batches_per_hour := (
		effective_work_units_per_hour
		/ float(raw_work_units_per_batch)
	)

	return (
		completed_batches_per_hour
		* float(output_amount_per_batch)
	)

static func run_tick(
	_tick_index: int,
	minutes_advanced: int
) -> void:
	if minutes_advanced <= 0:
		return

	if not WorldData.has_player_city():
		return

	for raw_city_object in WorldData.city_objects:
		if not raw_city_object is Dictionary:
			continue

		var city_object: Dictionary = raw_city_object

		if not WorldData.city_object_is_workplace(city_object):
			continue

		var recipe := WorldData.get_city_object_production_recipe(
			city_object
		)

		if recipe.is_empty():
			continue

		_run_workplace_tick(
			city_object,
			recipe,
			minutes_advanced
		)


static func _run_workplace_tick(
	city_object: Dictionary,
	recipe: Dictionary,
	minutes_advanced: int
) -> void:
	var object_id := int(city_object.get("id", -1))

	if object_id <= 0:
		return

	var current_progress := (
		WorldData.get_city_object_production_progress_work_units(
			city_object
		)
	)
	var source_evaluation := get_resource_source_evaluation(
		city_object
	)
	var uses_environmental_resource_source := bool(
		source_evaluation.get(
			"uses_environmental_source",
			false
		)
	)
	var site_productivity := (
		WorldData.get_city_object_site_productivity_basis_points(
			city_object
		)
	)

	if uses_environmental_resource_source:
		site_productivity = maxi(
			int(
				source_evaluation.get(
					"site_productivity_basis_points",
					0
				)
			),
			0
		)
	var productive_worker_count := _get_productive_worker_count(
		city_object
	)

	var raw_work_units_per_batch = recipe.get(
		"work_units_per_batch",
		0
	)
	var outputs := _get_recipe_outputs(recipe)
	var raw_inputs = recipe.get("inputs", {})

	if (
		not raw_work_units_per_batch is int
		or int(raw_work_units_per_batch) <= 0
		or outputs.is_empty()
		or not raw_inputs is Dictionary
		or not _outputs_are_valid_for_workplace(
			city_object,
			outputs
		)
	):
		_write_workplace_state(
			object_id,
			0,
			WorldData.WORKPLACE_PRODUCTION_STATUS_INACTIVE,
			productive_worker_count,
			site_productivity
		)
		return

	var work_units_per_batch: int = raw_work_units_per_batch
	var inputs: Dictionary = raw_inputs

	if productive_worker_count <= 0:
		_write_workplace_state(
			object_id,
			current_progress,
			WorldData.WORKPLACE_PRODUCTION_STATUS_IDLE_NO_WORKERS,
			0,
			site_productivity
		)
		return
		
	if (
		uses_environmental_resource_source
		and site_productivity <= 0
	):
		_write_workplace_state(
			object_id,
			current_progress,
			WorldData.WORKPLACE_PRODUCTION_STATUS_BLOCKED_NO_RESOURCE_SOURCE,
			productive_worker_count,
			0
		)
		return
	# Input-consuming recipes fail closed until stored-input processing
	# is implemented. This prevents future recipes from creating free goods.
	if not inputs.is_empty():
		_write_workplace_state(
			object_id,
			current_progress,
			WorldData.WORKPLACE_PRODUCTION_STATUS_BLOCKED_MISSING_INPUT,
			productive_worker_count,
			site_productivity
		)
		return

	var output_capacity_in_batches := (
		_get_output_capacity_in_batches(
			city_object,
			outputs
		)
	)

	if output_capacity_in_batches <= 0:
		_write_workplace_state(
			object_id,
			current_progress,
			WorldData.WORKPLACE_PRODUCTION_STATUS_BLOCKED_OUTPUT_FULL,
			productive_worker_count,
			site_productivity
		)
		return

	var work_units_added := _calculate_work_units(
		minutes_advanced,
		productive_worker_count,
		site_productivity
	)

	if work_units_added <= 0:
		_write_workplace_state(
			object_id,
			current_progress,
			WorldData.WORKPLACE_PRODUCTION_STATUS_WORKING,
			productive_worker_count,
			site_productivity
		)
		return

	var total_progress := current_progress + work_units_added
	var potential_completed_batches := int(
		total_progress / work_units_per_batch
	)

	if potential_completed_batches <= 0:
		_write_workplace_state(
			object_id,
			total_progress,
			WorldData.WORKPLACE_PRODUCTION_STATUS_WORKING,
			productive_worker_count,
			site_productivity
		)
		return

	var batches_to_produce := mini(
		potential_completed_batches,
		output_capacity_in_batches
	)

	if not _store_recipe_outputs(
		object_id,
		outputs,
		batches_to_produce
	):
		push_error(
			"Workplace "
			+ str(object_id)
			+ " could not store its prevalidated production output."
		)

		_write_workplace_state(
			object_id,
			current_progress,
			WorldData.WORKPLACE_PRODUCTION_STATUS_BLOCKED_OUTPUT_FULL,
			productive_worker_count,
			site_productivity
		)
		return

	var new_progress := (
		total_progress
		- batches_to_produce * work_units_per_batch
	)

	# If this tick exhausted the available output capacity, workers stop
	# at that moment. Extra work from the rest of the tick is not banked
	# as an invisible completed-output backlog.
	if batches_to_produce >= output_capacity_in_batches:
		new_progress = 0

	var updated_city_object := WorldData.get_city_object_by_id(
		object_id
	)
	var remaining_output_capacity := (
		_get_output_capacity_in_batches(
			updated_city_object,
			outputs
		)
	)

	var new_status := (
		WorldData.WORKPLACE_PRODUCTION_STATUS_WORKING
	)

	if remaining_output_capacity <= 0:
		new_status = (
			WorldData.WORKPLACE_PRODUCTION_STATUS_BLOCKED_OUTPUT_FULL
		)

	_write_workplace_state(
		object_id,
		new_progress,
		new_status,
		productive_worker_count,
		site_productivity
	)


static func _get_productive_worker_count(
	city_object: Dictionary
) -> int:
	var workplace_id := int(city_object.get("id", -1))

	if workplace_id <= 0:
		return 0

	var productive_worker_count := 0
	var counted_worker_ids: Dictionary = {}

	for raw_worker_id in WorldData.get_city_object_worker_ids(
		city_object
	):
		var worker_id := int(raw_worker_id)

		if worker_id <= 0:
			continue

		if counted_worker_ids.has(worker_id):
			continue

		counted_worker_ids[worker_id] = true

		var citizen := WorldData.get_city_citizen_by_id(
			worker_id
		)

		if citizen.is_empty():
			continue

		if not bool(citizen.get("alive", false)):
			continue

		if int(citizen.get("job_object_id", -1)) != workplace_id:
			continue

		productive_worker_count += 1

	return mini(
		productive_worker_count,
		WorldData.get_city_object_worker_capacity(city_object)
	)


static func _get_recipe_outputs(
	recipe: Dictionary
) -> Dictionary:
	var raw_outputs = recipe.get("outputs", {})

	if not raw_outputs is Dictionary:
		return {}

	var outputs: Dictionary = raw_outputs
	return outputs


static func _outputs_are_valid_for_workplace(
	city_object: Dictionary,
	outputs: Dictionary
) -> bool:
	if outputs.is_empty():
		return false

	var known_resource_types := WorldData.get_city_resource_types()

	for raw_resource in outputs:
		var resource := str(raw_resource)
		var raw_amount_per_batch = outputs.get(raw_resource, 0)

		if resource == WorldData.RESOURCE_NONE:
			return false

		if not known_resource_types.has(resource):
			return false

		if not raw_amount_per_batch is int:
			return false

		if int(raw_amount_per_batch) <= 0:
			return false

		if not WorldData.can_city_object_store_resource(
			city_object,
			resource
		):
			return false

	return true


static func _get_output_capacity_in_batches(
	city_object: Dictionary,
	outputs: Dictionary
) -> int:
	if city_object.is_empty():
		return 0

	if outputs.is_empty():
		return 0

	var capacity_in_batches := -1

	for raw_resource in outputs:
		var resource := str(raw_resource)
		var amount_per_batch := int(
			outputs.get(raw_resource, 0)
		)

		if amount_per_batch <= 0:
			return 0

		var free_space := (
			WorldData.get_city_object_resource_free_space(
				city_object,
				resource
			)
		)
		var resource_capacity_in_batches := int(
			free_space / amount_per_batch
		)

		if (
			capacity_in_batches < 0
			or resource_capacity_in_batches < capacity_in_batches
		):
			capacity_in_batches = resource_capacity_in_batches

	return maxi(capacity_in_batches, 0)


static func _calculate_work_units(
	minutes_advanced: int,
	productive_worker_count: int,
	site_productivity_basis_points: int
) -> int:
	if minutes_advanced <= 0:
		return 0

	if productive_worker_count <= 0:
		return 0

	if site_productivity_basis_points <= 0:
		return 0

	var base_work_units: int = (
		minutes_advanced
		* productive_worker_count
		* WORK_UNITS_PER_WORKER_MINUTE
	)
	var adjusted_work_units_numerator: int = (
		base_work_units
		* site_productivity_basis_points
	)

	return maxi(
		int(
			adjusted_work_units_numerator
			/ WorldData.PRODUCTIVITY_BASIS_POINTS_SCALE
		),
		0
	)


static func _store_recipe_outputs(
	object_id: int,
	outputs: Dictionary,
	batch_count: int
) -> bool:
	if object_id <= 0:
		return false

	if batch_count <= 0:
		return false

	for raw_resource in outputs:
		var resource := str(raw_resource)
		var amount_per_batch := int(
			outputs.get(raw_resource, 0)
		)
		var requested_amount := (
			amount_per_batch
			* batch_count
		)
		var accepted_amount := (
			WorldData.add_resource_to_city_object_storage(
				object_id,
				resource,
				requested_amount
			)
		)

		if accepted_amount != requested_amount:
			return false

	return true


static func _write_workplace_state(
	object_id: int,
	progress_work_units: int,
	production_status: String,
	productive_worker_count: int,
	site_productivity_basis_points: int
) -> void:
	WorldData.set_city_workplace_production_state(
		object_id,
		progress_work_units,
		production_status,
		productive_worker_count,
		site_productivity_basis_points
	)
