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
	var source_density_for_full_productivity_basis_points := int(
		policy.get("source_density_for_full_productivity_basis_points", 0)
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

	evaluation["source_density_for_full_productivity_basis_points"] = (
		source_density_for_full_productivity_basis_points
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

	if source_density_for_full_productivity_basis_points <= 0:
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

	if _resource_source_cache_matches({
		"cache_entry": cache_entry,
		"world_instance_id": world_instance_id,
		"tile_data_version": tile_data_version,
		"object_type": object_type,
		"footprint_tiles": footprint_tiles,
		"resource_type": resource_type,
		"reach_tiles": reach_tiles,
		"source_density_for_full_productivity_basis_points": (
			source_density_for_full_productivity_basis_points
		),
	}):
		var raw_cached_evaluation = cache_entry.get(
			"evaluation",
			{}
		)

		if raw_cached_evaluation is Dictionary:
			return raw_cached_evaluation

	var zone_result := _build_footprint_reach_zone({
		"source_world": active_world,
		"footprint_tiles": footprint_tiles,
		"reach_tiles": reach_tiles,
		"resource_type": resource_type,
	})
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
				float(density_basis_points)
				* float(WorldData.PRODUCTIVITY_BASIS_POINTS_SCALE)
				/ float(
					source_density_for_full_productivity_basis_points
				)
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
		"source_density_for_full_productivity_basis_points": (
			source_density_for_full_productivity_basis_points
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
		"source_density_for_full_productivity_basis_points": 0,
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
	values: Dictionary
) -> Dictionary:
	var source_world = values.get("source_world")
	var footprint_tiles: Array = values.get("footprint_tiles", [])
	var reach_tiles := maxi(int(values.get("reach_tiles", 0)), 0)
	var resource_type := str(
		values.get("resource_type", WorldData.RESOURCE_NONE)
	)
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
	values: Dictionary
) -> bool:
	var cache_entry: Dictionary = values.get("cache_entry", {})
	var world_instance_id := int(values.get("world_instance_id", -1))
	var tile_data_version := int(values.get("tile_data_version", -1))
	var object_type := str(values.get("object_type", ""))
	var footprint_tiles: Array = values.get("footprint_tiles", [])
	var resource_type := str(values.get("resource_type", ""))
	var reach_tiles := int(values.get("reach_tiles", -1))
	var source_density_for_full_productivity_basis_points := int(
		values.get(
			"source_density_for_full_productivity_basis_points",
			-1
		)
	)

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
				"source_density_for_full_productivity_basis_points",
				-1
			)
		)
		== source_density_for_full_productivity_basis_points
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
	var tick_context := _make_workplace_tick_context({
		"city_object": city_object,
		"recipe": recipe,
		"minutes_advanced": minutes_advanced,
	})

	if tick_context.is_empty():
		return

	if not _prepare_workplace_tick_recipe(tick_context):
		return

	if _workplace_tick_is_blocked(tick_context):
		return

	if not _prepare_workplace_tick_output(tick_context):
		return

	_commit_workplace_tick_output(tick_context)


static func _make_workplace_tick_context(
	values: Dictionary
) -> Dictionary:
	var city_object: Dictionary = values.get("city_object", {})
	var recipe: Dictionary = values.get("recipe", {})
	var minutes_advanced := int(values.get("minutes_advanced", 0))
	var object_id := int(city_object.get("id", -1))

	if object_id <= 0:
		return {}

	var current_progress := (
		WorldData.get_city_object_production_progress_work_units(
			city_object
		)
	)
	var source_evaluation := get_resource_source_evaluation(city_object)
	var uses_environmental_resource_source := bool(
		source_evaluation.get("uses_environmental_source", false)
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

	return {
		"city_object": city_object,
		"recipe": recipe,
		"minutes_advanced": minutes_advanced,
		"object_id": object_id,
		"current_progress": current_progress,
		"uses_environmental_resource_source": (
			uses_environmental_resource_source
		),
		"site_productivity": site_productivity,
		"productive_worker_count": _get_productive_worker_count(city_object),
	}


static func _prepare_workplace_tick_recipe(
	context: Dictionary
) -> bool:
	var city_object: Dictionary = context.get("city_object", {})
	var recipe: Dictionary = context.get("recipe", {})
	var object_id := int(context.get("object_id", -1))
	var productive_worker_count := int(
		context.get("productive_worker_count", 0)
	)
	var site_productivity := int(context.get("site_productivity", 0))
	var raw_work_units_per_batch = recipe.get("work_units_per_batch", 0)
	var outputs := _get_recipe_outputs(recipe)
	var raw_inputs = recipe.get("inputs", {})

	if (
		not raw_work_units_per_batch is int
		or int(raw_work_units_per_batch) <= 0
		or outputs.is_empty()
		or not raw_inputs is Dictionary
		or not _outputs_are_valid_for_workplace(city_object, outputs)
	):
		_write_workplace_state({
			"object_id": object_id,
			"progress_work_units": 0,
			"production_status": (
				WorldData.WORKPLACE_PRODUCTION_STATUS_INACTIVE
			),
			"productive_worker_count": productive_worker_count,
			"site_productivity_basis_points": site_productivity,
		})
		return false

	context["work_units_per_batch"] = int(raw_work_units_per_batch)
	context["outputs"] = outputs
	context["inputs"] = raw_inputs
	return true


static func _workplace_tick_is_blocked(
	context: Dictionary
) -> bool:
	var city_object: Dictionary = context.get("city_object", {})
	var object_id := int(context.get("object_id", -1))
	var current_progress := int(context.get("current_progress", 0))
	var productive_worker_count := int(
		context.get("productive_worker_count", 0)
	)
	var site_productivity := int(context.get("site_productivity", 0))
	var uses_environmental_resource_source := bool(
		context.get("uses_environmental_resource_source", false)
	)
	var inputs: Dictionary = context.get("inputs", {})
	var outputs: Dictionary = context.get("outputs", {})

	if productive_worker_count <= 0:
		_write_workplace_state({
			"object_id": object_id,
			"progress_work_units": current_progress,
			"production_status": (
				WorldData.WORKPLACE_PRODUCTION_STATUS_IDLE_NO_WORKERS
			),
			"productive_worker_count": 0,
			"site_productivity_basis_points": site_productivity,
		})
		return true

	if uses_environmental_resource_source and site_productivity <= 0:
		_write_workplace_state({
			"object_id": object_id,
			"progress_work_units": current_progress,
			"production_status": (
				WorldData
				.WORKPLACE_PRODUCTION_STATUS_BLOCKED_NO_RESOURCE_SOURCE
			),
			"productive_worker_count": productive_worker_count,
			"site_productivity_basis_points": 0,
		})
		return true

	# Input-consuming recipes fail closed until stored-input processing
	# is implemented. This prevents future recipes from creating free goods.
	if not inputs.is_empty():
		_write_workplace_state({
			"object_id": object_id,
			"progress_work_units": current_progress,
			"production_status": (
				WorldData
				.WORKPLACE_PRODUCTION_STATUS_BLOCKED_MISSING_INPUT
			),
			"productive_worker_count": productive_worker_count,
			"site_productivity_basis_points": site_productivity,
		})
		return true

	var output_capacity_in_batches := _get_output_capacity_in_batches(
		city_object,
		outputs
	)
	var overflow_tile := WorldData.INVALID_CITY_TILE_POSITION
	var can_overflow := false

	# Do not search footprint rings or run pathfinding while ordinary output
	# storage can still accept all work. A zero-capacity workplace must resolve
	# overflow before accepting progress, preserving the existing fail-closed
	# behavior.
	if output_capacity_in_batches <= 0:
		overflow_tile = _find_workplace_overflow_tile(city_object)
		can_overflow = (
			overflow_tile != WorldData.INVALID_CITY_TILE_POSITION
		)

	if output_capacity_in_batches <= 0 and not can_overflow:
		_write_workplace_state({
			"object_id": object_id,
			"progress_work_units": current_progress,
			"production_status": (
				WorldData.WORKPLACE_PRODUCTION_STATUS_BLOCKED_OUTPUT_FULL
			),
			"productive_worker_count": productive_worker_count,
			"site_productivity_basis_points": site_productivity,
		})
		return true

	context["output_capacity_in_batches"] = output_capacity_in_batches
	context["overflow_tile"] = overflow_tile
	context["can_overflow"] = can_overflow
	return false


static func _prepare_workplace_tick_output(
	context: Dictionary
) -> bool:
	var city_object: Dictionary = context.get("city_object", {})
	var minutes_advanced := int(context.get("minutes_advanced", 0))
	var object_id := int(context.get("object_id", -1))
	var current_progress := int(context.get("current_progress", 0))
	var productive_worker_count := int(
		context.get("productive_worker_count", 0)
	)
	var site_productivity := int(context.get("site_productivity", 0))
	var work_units_per_batch := int(context.get("work_units_per_batch", 0))
	var output_capacity_in_batches := int(
		context.get("output_capacity_in_batches", 0)
	)
	var overflow_tile: Vector2i = context.get(
		"overflow_tile",
		WorldData.INVALID_CITY_TILE_POSITION
	)
	var can_overflow := bool(context.get("can_overflow", false))
	var work_units_added := _calculate_work_units(
		minutes_advanced,
		productive_worker_count,
		site_productivity
	)

	if work_units_added <= 0:
		_write_workplace_state({
			"object_id": object_id,
			"progress_work_units": current_progress,
			"production_status": (
				WorldData.WORKPLACE_PRODUCTION_STATUS_WORKING
			),
			"productive_worker_count": productive_worker_count,
			"site_productivity_basis_points": site_productivity,
		})
		return false

	var total_progress := current_progress + work_units_added
	var potential_completed_batches := int(
		total_progress / work_units_per_batch
	)

	if potential_completed_batches <= 0:
		_write_workplace_state({
			"object_id": object_id,
			"progress_work_units": total_progress,
			"production_status": (
				WorldData.WORKPLACE_PRODUCTION_STATUS_WORKING
			),
			"productive_worker_count": productive_worker_count,
			"site_productivity_basis_points": site_productivity,
		})
		return false

	var storage_batches_to_produce := mini(
		potential_completed_batches,
		maxi(output_capacity_in_batches, 0)
	)
	var overflow_batches_to_produce := 0

	# Resolve overflow only when this tick reaches the remaining storage
	# capacity. Equality matters: an available overflow tile lets fractional
	# progress survive after the last in-storage batch, matching prior behavior.
	if (
		not can_overflow
		and potential_completed_batches >= output_capacity_in_batches
	):
		overflow_tile = _find_workplace_overflow_tile(city_object)
		can_overflow = (
			overflow_tile != WorldData.INVALID_CITY_TILE_POSITION
		)

	if can_overflow:
		overflow_batches_to_produce = maxi(
			potential_completed_batches - storage_batches_to_produce,
			0
		)

	var batches_to_produce := (
		storage_batches_to_produce + overflow_batches_to_produce
	)

	if batches_to_produce <= 0:
		_write_workplace_state({
			"object_id": object_id,
			"progress_work_units": current_progress,
			"production_status": (
				WorldData.WORKPLACE_PRODUCTION_STATUS_BLOCKED_OUTPUT_FULL
			),
			"productive_worker_count": productive_worker_count,
			"site_productivity_basis_points": site_productivity,
		})
		return false

	context["total_progress"] = total_progress
	context["storage_batches_to_produce"] = storage_batches_to_produce
	context["overflow_batches_to_produce"] = overflow_batches_to_produce
	context["batches_to_produce"] = batches_to_produce
	context["overflow_tile"] = overflow_tile
	context["can_overflow"] = can_overflow
	return true


static func _commit_workplace_tick_output(
	context: Dictionary
) -> void:
	var city_object: Dictionary = context.get("city_object", {})
	var object_id := int(context.get("object_id", -1))
	var current_progress := int(context.get("current_progress", 0))
	var productive_worker_count := int(
		context.get("productive_worker_count", 0)
	)
	var site_productivity := int(context.get("site_productivity", 0))
	var work_units_per_batch := int(context.get("work_units_per_batch", 0))
	var outputs: Dictionary = context.get("outputs", {})
	var output_capacity_in_batches := int(
		context.get("output_capacity_in_batches", 0)
	)
	var total_progress := int(context.get("total_progress", 0))
	var storage_batches_to_produce := int(
		context.get("storage_batches_to_produce", 0)
	)
	var overflow_batches_to_produce := int(
		context.get("overflow_batches_to_produce", 0)
	)
	var batches_to_produce := int(context.get("batches_to_produce", 0))
	var overflow_tile: Vector2i = context.get(
		"overflow_tile",
		WorldData.INVALID_CITY_TILE_POSITION
	)
	var can_overflow := bool(context.get("can_overflow", false))

	if not _store_recipe_output_distribution({
		"object_id": object_id,
		"outputs": outputs,
		"storage_batch_count": storage_batches_to_produce,
		"overflow_batch_count": overflow_batches_to_produce,
		"overflow_tile": overflow_tile,
	}):
		push_error(
			"Workplace "
			+ str(object_id)
			+ " could not store its prevalidated production output."
		)
		_write_workplace_state({
			"object_id": object_id,
			"progress_work_units": current_progress,
			"production_status": (
				WorldData.WORKPLACE_PRODUCTION_STATUS_BLOCKED_OUTPUT_FULL
			),
			"productive_worker_count": productive_worker_count,
			"site_productivity_basis_points": site_productivity,
		})
		return

	var new_progress := (
		total_progress - batches_to_produce * work_units_per_batch
	)

	# If this tick exhausted the available output capacity, workers stop
	# at that moment. Extra work from the rest of the tick is not banked
	# as an invisible completed-output backlog.
	if (
		not can_overflow
		and batches_to_produce >= output_capacity_in_batches
	):
		new_progress = 0

	var updated_city_object := WorldData.get_city_object_by_id(object_id)
	var remaining_output_capacity := _get_output_capacity_in_batches(
		updated_city_object,
		outputs
	)
	var new_status := WorldData.WORKPLACE_PRODUCTION_STATUS_WORKING

	if remaining_output_capacity <= 0 and not can_overflow:
		new_status = (
			WorldData.WORKPLACE_PRODUCTION_STATUS_BLOCKED_OUTPUT_FULL
		)

	_write_workplace_state({
		"object_id": object_id,
		"progress_work_units": new_progress,
		"production_status": new_status,
		"productive_worker_count": productive_worker_count,
		"site_productivity_basis_points": site_productivity,
	})

static func _get_productive_worker_count(
	city_object: Dictionary
) -> int:
	return WorldData.get_city_object_attending_worker_count(
		city_object
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

	var total_output_amount_per_batch := 0

	for raw_resource in outputs:
		var amount_per_batch := int(
			outputs.get(raw_resource, 0)
		)

		if amount_per_batch <= 0:
			return 0

		total_output_amount_per_batch += amount_per_batch

	if total_output_amount_per_batch <= 0:
		return 0

	# Object containers use one shared total capacity. A multi-output batch must
	# fit the sum of every output after incoming haul reservations are removed.
	var shared_free_space := (
		WorldData.get_city_object_unreserved_storage_free_space(
			city_object
		)
	)

	return maxi(
		floori(
			float(shared_free_space)
			/ float(total_output_amount_per_batch)
		),
		0
	)


static func _find_workplace_overflow_tile(
	city_object: Dictionary
) -> Vector2i:
	var active_world = WorldData.official_city_world

	if active_world == null or city_object.is_empty():
		return WorldData.INVALID_CITY_TILE_POSITION

	var overflow_policy := (
		WorldData.get_city_object_overflow_policy(
			city_object
		)
	)
	var mode := str(
		overflow_policy.get(
			"mode",
			WorldData.WORKPLACE_OVERFLOW_MODE_NONE
		)
	)

	if mode != WorldData.WORKPLACE_OVERFLOW_MODE_FOOTPRINT_RADIUS:
		return WorldData.INVALID_CITY_TILE_POSITION

	var radius_tiles := maxi(
		int(overflow_policy.get("radius_tiles", 0)),
		0
	)

	if radius_tiles <= 0:
		return WorldData.INVALID_CITY_TILE_POSITION

	var footprint_tiles := _get_unique_footprint_tiles(
		city_object
	)

	if footprint_tiles.is_empty():
		return WorldData.INVALID_CITY_TILE_POSITION

	var access_tiles := WorldData.get_city_object_access_tiles(
		active_world,
		city_object
	)

	# The ordinary access ring is both the cheapest and most predictable
	# overflow location. It avoids pathfinding in the common case.
	for raw_access_tile in access_tiles:
		if not raw_access_tile is Vector2i:
			continue

		var access_tile: Vector2i = raw_access_tile

		if not _tile_is_within_footprint_radius(
			access_tile,
			footprint_tiles,
			radius_tiles
		):
			continue

		if CityLogisticsSystem.can_city_ground_pile_exist_at_tile(
			active_world,
			access_tile
		):
			return access_tile

	if access_tiles.is_empty() or radius_tiles <= 1:
		return WorldData.INVALID_CITY_TILE_POSITION

	var candidate_lookup: Dictionary = {}

	for raw_footprint_tile in footprint_tiles:
		if not raw_footprint_tile is Vector2i:
			continue

		var footprint_tile: Vector2i = raw_footprint_tile

		for offset_y in range(-radius_tiles, radius_tiles + 1):
			for offset_x in range(-radius_tiles, radius_tiles + 1):
				if abs(offset_x) + abs(offset_y) > radius_tiles:
					continue

				var candidate_tile := (
					footprint_tile
					+ Vector2i(offset_x, offset_y)
				)

				if candidate_lookup.has(candidate_tile):
					continue

				if not CityLogisticsSystem.can_city_ground_pile_exist_at_tile(
					active_world,
					candidate_tile
				):
					continue

				candidate_lookup[candidate_tile] = true

	var candidate_tiles: Array = candidate_lookup.keys()

	if candidate_tiles.is_empty():
		return WorldData.INVALID_CITY_TILE_POSITION

	candidate_tiles.sort_custom(WorldData._sort_city_tiles_y_then_x)

	# If buildings or roads consume the immediate ring, select the cheapest
	# reachable tile inside the configured radius rather than spawning loose
	# resources across an impassable boundary.
	var best_tile := WorldData.INVALID_CITY_TILE_POSITION
	var best_path_cost := CityNavigationSystem.MAXIMUM_PATH_COST

	for raw_access_tile in access_tiles:
		if not raw_access_tile is Vector2i:
			continue

		var access_tile: Vector2i = raw_access_tile
		var path_result := (
			CityNavigationSystem.find_path_to_any_city_tile({
				"city_world": active_world,
				"start_tile": access_tile,
				"destination_tiles": candidate_tiles,
				"max_expanded_nodes": CityNavigationSystem.DEFAULT_MAX_EXPANDED_NODES,
				"citizen_id": -1,
				"heuristic_weight": 1
			})
		)

		if not bool(path_result.get("success", false)):
			continue

		var candidate_tile = path_result.get(
			"destination_tile",
			WorldData.INVALID_CITY_TILE_POSITION
		)

		if not candidate_tile is Vector2i:
			continue

		var path_cost := maxi(
			int(path_result.get("path_cost", 0)),
			0
		)

		if (
			path_cost < best_path_cost
			or (
				path_cost == best_path_cost
				and WorldData._sort_city_tiles_y_then_x(
					candidate_tile,
					best_tile
				)
			)
		):
			best_path_cost = path_cost
			best_tile = candidate_tile

	return best_tile


static func _tile_is_within_footprint_radius(
	tile_position: Vector2i,
	footprint_tiles: Array,
	radius_tiles: int
) -> bool:
	for raw_footprint_tile in footprint_tiles:
		if not raw_footprint_tile is Vector2i:
			continue

		var footprint_tile: Vector2i = raw_footprint_tile
		var manhattan_distance: int = (
			absi(tile_position.x - footprint_tile.x)
			+ absi(tile_position.y - footprint_tile.y)
		)

		if manhattan_distance <= radius_tiles:
			return true

	return false



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

	var requested_resources: Dictionary = {}

	for raw_resource in outputs:
		var resource := str(raw_resource)
		var amount_per_batch := int(
			outputs.get(raw_resource, 0)
		)
		var requested_amount := (
			amount_per_batch
			* batch_count
		)

		if requested_amount <= 0:
			return false

		requested_resources[resource] = requested_amount

	return WorldData.add_resource_bundle_to_city_object_storage(
		object_id,
		requested_resources
	)


static func _store_recipe_output_distribution(
	values: Dictionary
) -> bool:
	var object_id := int(values.get("object_id", -1))
	var outputs: Dictionary = values.get("outputs", {})
	var storage_batch_count := maxi(
		int(values.get("storage_batch_count", 0)),
		0
	)
	var overflow_batch_count := maxi(
		int(values.get("overflow_batch_count", 0)),
		0
	)
	var overflow_tile: Vector2i = values.get(
		"overflow_tile",
		WorldData.INVALID_CITY_TILE_POSITION
	)
	var stored_in_object := false

	if storage_batch_count > 0:
		if not _store_recipe_outputs(
			object_id,
			outputs,
			storage_batch_count
		):
			return false

		stored_in_object = true

	if overflow_batch_count <= 0:
		return stored_in_object

	if _store_recipe_outputs_in_ground_pile(
		overflow_tile,
		outputs,
		overflow_batch_count
	):
		return true

	if stored_in_object:
		_rollback_recipe_outputs_from_city_object(
			object_id,
			outputs,
			storage_batch_count
		)

	return false


static func _store_recipe_outputs_in_ground_pile(
	tile_position: Vector2i,
	outputs: Dictionary,
	batch_count: int
) -> bool:
	if (
		batch_count <= 0
		or tile_position
		== WorldData.INVALID_CITY_TILE_POSITION
	):
		return false

	var added_placements_by_resource: Dictionary = {}

	for raw_resource in outputs:
		var resource := str(raw_resource)
		var requested_amount := (
			int(outputs.get(raw_resource, 0))
			* batch_count
		)
		var add_result := (
			CityLogisticsSystem.add_resource_to_city_ground_piles_with_result({
				"tile_position": tile_position,
				"resource": resource,
				"amount_delta": requested_amount,
			})
		)
		var added_amount := int(
			add_result.get("added_amount", 0)
		)

		if added_amount != requested_amount:
			_rollback_ground_pile_resources(
				added_placements_by_resource
			)
			return false

		added_placements_by_resource[resource] = (
			add_result.get("placements", [])
		)

	return not added_placements_by_resource.is_empty()


static func _rollback_recipe_outputs_from_city_object(
	object_id: int,
	outputs: Dictionary,
	batch_count: int
) -> void:
	for raw_resource in outputs:
		var resource := str(raw_resource)
		var requested_amount := (
			int(outputs.get(raw_resource, 0))
			* batch_count
		)
		var removed_amount := (
			WorldData.remove_resource_from_city_object_storage(
				object_id,
				resource,
				requested_amount
			)
		)

		if removed_amount != requested_amount:
			push_error(
				"Failed to roll back workplace output after an "
				+ "overflow transfer failure."
			)


static func _rollback_ground_pile_resources(
	placements_by_resource: Dictionary
) -> void:
	for raw_resource in placements_by_resource:
		var resource := str(raw_resource)
		var placements = placements_by_resource.get(
			raw_resource,
			[]
		)

		if not CityLogisticsSystem.rollback_city_ground_pile_additions(
			resource,
			placements
		):
			push_error(
				"Failed to roll back ground-pile output after "
				+ "a multi-output transfer failure."
			)


static func _write_workplace_state(
	values: Dictionary
) -> void:
	WorldData.set_city_workplace_production_state(
		values
	)
