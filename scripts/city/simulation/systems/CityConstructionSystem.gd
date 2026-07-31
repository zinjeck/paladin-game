extends RefCounted
class_name CityConstructionSystem

const CityNavigationSystemScript = preload(
	"res://scripts/city/simulation/systems/CityNavigationSystem.gd"
)
const CitizenHaulingSystemScript = preload(
	"res://scripts/citizens/simulation/systems/CitizenHaulingSystem.gd"
)
const CityResourceMatcherScript = preload(
	"res://scripts/city/simulation/systems/CityResourceMatcher.gd"
)

const PLAYER_WORK_KIND_DELIVERY := "construction_delivery"
const PLAYER_WORK_KIND_LABOR := "construction_labor"
const PROGRESS_REQUIRED_CLEARING_WORK_UNITS_KEY := (
	"required_clearing_work_units"
)
const PROGRESS_BASE_WORK_MINUTES := (
	WorldData.CITY_PLAYER_COMMAND_WORK_DURATION_MINUTES
)
const EXACT_PATH_HEURISTIC_WEIGHT: int = 1


static func create_rectangular_site(
	object_type: String,
	top_left: Vector2i,
	size_tiles: Vector2i,
	object_owner: String = "player",
	city_world: WorldData = null
) -> Dictionary:
	var resolved_world := city_world

	if resolved_world == null:
		resolved_world = WorldData.official_city_world

	if not WorldData.can_place_city_object_construction(
		resolved_world,
		top_left,
		size_tiles,
		object_type
	):
		return {}

	var definition := WorldData.get_city_object_definition(object_type)
	var footprint_tiles := (
		WorldData.make_rectangle_city_object_footprint_tiles(
			top_left,
			size_tiles
		)
	)
	var work_positions := _build_external_work_positions(
		resolved_world,
		footprint_tiles
	)

	if work_positions.is_empty():
		return {}

	var site := WorldData.create_city_construction_site({
		"target_kind": WorldData.CITY_CONSTRUCTION_TARGET_NEW,
		"object_type": object_type,
		"shape_mode": WorldData.CITY_OBJECT_SHAPE_RECTANGLE,
		"top_left": top_left,
		"size": size_tiles,
		"footprint_tiles": footprint_tiles,
		"owner": object_owner,
		"material_recipe": _get_scaled_material_recipe(
			definition,
			footprint_tiles.size()
		),
		"required_labor_minutes": _get_scaled_labor_minutes(
			definition,
			footprint_tiles.size()
		),
		"maximum_workers": int(
			definition.get("construction_max_workers", 1)
		),
		"work_positions": work_positions,
		"require_external_access": true,
	})

	if not site.is_empty():
		refresh_city_construction_site(
			int(site.get("id", -1))
		)
		site = WorldData.get_city_construction_site_by_id(
			int(site.get("id", -1))
		)

	return site


static func create_road_site(
	raw_tile_positions: Array,
	object_owner: String = "player",
	city_world: WorldData = null
) -> Dictionary:
	var resolved_world := city_world

	if resolved_world == null:
		resolved_world = WorldData.official_city_world

	if resolved_world == null:
		return {}

	var footprint_tiles: Array[Vector2i] = []
	var tile_lookup: Dictionary = {}

	for raw_tile in raw_tile_positions:
		if not raw_tile is Vector2i:
			continue

		var tile_position: Vector2i = raw_tile

		if (
			tile_lookup.has(tile_position)
			or not WorldData.can_place_city_road_tile(
				resolved_world,
				tile_position
			)
		):
			continue

		tile_lookup[tile_position] = true
		footprint_tiles.append(tile_position)

	footprint_tiles.sort_custom(_sort_tiles_y_then_x)

	if footprint_tiles.is_empty():
		return {}

	if not WorldData.can_place_city_construction_footprint(
		resolved_world,
		footprint_tiles
	):
		return {}

	var top_left := footprint_tiles[0]
	var bottom_right := footprint_tiles[0]

	for tile_position in footprint_tiles:
		top_left.x = mini(top_left.x, tile_position.x)
		top_left.y = mini(top_left.y, tile_position.y)
		bottom_right.x = maxi(bottom_right.x, tile_position.x)
		bottom_right.y = maxi(bottom_right.y, tile_position.y)

	var definition := WorldData.get_city_object_definition(
		WorldData.CITY_OBJECT_ROAD
	)
	var site := WorldData.create_city_construction_site({
		"target_kind": WorldData.CITY_CONSTRUCTION_TARGET_NEW,
		"object_type": WorldData.CITY_OBJECT_ROAD,
		"shape_mode": WorldData.CITY_OBJECT_SHAPE_TILE_AREA,
		"top_left": top_left,
		"size": bottom_right - top_left + Vector2i.ONE,
		"footprint_tiles": footprint_tiles,
		"owner": object_owner,
		"material_recipe": _get_scaled_material_recipe(
			definition,
			footprint_tiles.size()
		),
		"required_labor_minutes": _get_scaled_labor_minutes(
			definition,
			footprint_tiles.size()
		),
		"maximum_workers": int(
			definition.get("construction_max_workers", 1)
		),
		"work_positions": footprint_tiles,
	})

	if not site.is_empty():
		refresh_city_construction_site(
			int(site.get("id", -1))
		)
		site = WorldData.get_city_construction_site_by_id(
			int(site.get("id", -1))
		)

	return site


static func _get_scaled_material_recipe(
	definition: Dictionary,
	footprint_tile_count: int
) -> Dictionary:
	var materials: Dictionary = {}
	var raw_materials = definition.get("construction_materials", {})

	if not raw_materials is Dictionary:
		return materials

	var scale := 1

	if bool(definition.get("construction_materials_per_tile", false)):
		scale = maxi(footprint_tile_count, 1)

	for resource in WorldData.get_city_resource_types():
		var amount := maxi(int(raw_materials.get(resource, 0)), 0)

		if amount > 0:
			materials[resource] = amount * scale

	return materials


static func _get_scaled_labor_minutes(
	definition: Dictionary,
	footprint_tile_count: int
) -> int:
	var labor_minutes := maxi(
		int(definition.get("construction_labor_minutes", 0)),
		1
	)

	if bool(definition.get("construction_labor_per_tile", false)):
		labor_minutes *= maxi(footprint_tile_count, 1)

	return labor_minutes


static func _build_external_work_positions(
	city_world: WorldData,
	footprint_tiles: Array
) -> Array[Vector2i]:
	var positions: Array[Vector2i] = []
	var footprint_lookup: Dictionary = {}
	var position_lookup: Dictionary = {}

	for raw_tile in footprint_tiles:
		if raw_tile is Vector2i:
			footprint_lookup[raw_tile] = true

	for raw_tile in footprint_tiles:
		if not raw_tile is Vector2i:
			continue

		var footprint_tile: Vector2i = raw_tile

		for offset in WorldData.CITY_CARDINAL_TILE_OFFSETS:
			var candidate_tile: Vector2i = (
				footprint_tile + Vector2i(offset)
			)

			if (
				footprint_lookup.has(candidate_tile)
				or position_lookup.has(candidate_tile)
				or not WorldData.is_city_tile_walkable_for_citizen(
					city_world,
					candidate_tile
				)
			):
				continue

			position_lookup[candidate_tile] = true
			positions.append(candidate_tile)

	positions.sort_custom(_sort_tiles_y_then_x)
	return positions


static func refresh_all_city_construction_sites() -> void:
	var site_ids: Array[int] = []

	for raw_site in WorldData.get_city_construction_site_snapshot():
		if raw_site is Dictionary:
			site_ids.append(int(raw_site.get("id", -1)))

	site_ids.sort()

	for site_id in site_ids:
		refresh_city_construction_site(site_id)


static func refresh_city_construction_site(
	site_id: int
) -> bool:
	var site := WorldData.get_city_construction_site_by_id(site_id)

	if site.is_empty():
		return false

	_reserve_needed_footprint_materials(site_id)
	_ensure_progress_baseline(site_id)
	_ensure_clearing_commands(site_id)
	site = WorldData.get_city_construction_site_by_id(site_id)

	if site.is_empty():
		return false

	var next_phase: String = (
		WorldData.CITY_CONSTRUCTION_PHASE_CLEARING
	)

	if (
		not _site_has_surface_obstruction(site)
		and not _site_has_ordinary_ground_pile(site)
	):
		if WorldData.city_construction_site_has_all_materials(site_id):
			next_phase = WorldData.CITY_CONSTRUCTION_PHASE_LABOR
		else:
			next_phase = WorldData.CITY_CONSTRUCTION_PHASE_GATHERING

	if str(site.get("phase", "")) != next_phase:
		site["phase"] = next_phase
		return WorldData.update_city_construction_site(site)

	return true


static func get_city_construction_site_progress_summary(
	site_id: int
) -> Dictionary:
	var site := WorldData.get_city_construction_site_by_id(site_id)

	if site.is_empty():
		return {}

	var remaining_clearing_work_units := (
		_get_remaining_clearing_work_units(site)
	)
	var stored_required_clearing_work_units := maxf(
		float(
			site.get(
				PROGRESS_REQUIRED_CLEARING_WORK_UNITS_KEY,
				0.0
			)
		),
		0.0
	)
	var required_clearing_work_units := maxf(
		stored_required_clearing_work_units,
		remaining_clearing_work_units
	)
	var completed_clearing_work_units := clampf(
		required_clearing_work_units
		- remaining_clearing_work_units,
		0.0,
		required_clearing_work_units
	)
	var required_material_work_units := 0.0
	var completed_material_work_units := 0.0
	var material_recipe = site.get("material_recipe", {})

	if material_recipe is Dictionary:
		for resource in WorldData.get_city_resource_types():
			var required_amount := maxi(
				int(material_recipe.get(resource, 0)),
				0
			)

			if required_amount <= 0:
				continue

			required_material_work_units += float(required_amount)
			completed_material_work_units += float(
				mini(
					WorldData.get_city_construction_site_reserved_resource_amount(
						site_id,
						resource
					),
					required_amount
				)
			)

	var required_labor_minutes := maxi(
		int(site.get("required_labor_minutes", 0)),
		0
	)
	var completed_labor_minutes := clampi(
		int(site.get("completed_labor_minutes", 0)),
		0,
		required_labor_minutes
	)
	var safe_base_minutes := maxf(
		PROGRESS_BASE_WORK_MINUTES,
		1.0
	)
	var required_labor_work_units := (
		float(required_labor_minutes) / safe_base_minutes
	)
	var completed_labor_work_units := (
		float(completed_labor_minutes) / safe_base_minutes
	)
	var total_work_units := (
		required_clearing_work_units
		+ required_material_work_units
		+ required_labor_work_units
	)
	var completed_work_units := clampf(
		completed_clearing_work_units
		+ completed_material_work_units
		+ completed_labor_work_units,
		0.0,
		total_work_units
	)
	var progress_ratio := 0.0

	if total_work_units > 0.0:
		progress_ratio = clampf(
			completed_work_units / total_work_units,
			0.0,
			1.0
		)

	return {
		"progress_ratio": progress_ratio,
		"progress_percent": int(
			floor(progress_ratio * 100.0 + 0.0001)
		),
		"required_clearing_work_units": (
			required_clearing_work_units
		),
		"completed_clearing_work_units": (
			completed_clearing_work_units
		),
		"required_material_work_units": (
			required_material_work_units
		),
		"completed_material_work_units": (
			completed_material_work_units
		),
		"required_labor_work_units": required_labor_work_units,
		"completed_labor_work_units": completed_labor_work_units,
		"total_work_units": total_work_units,
		"completed_work_units": completed_work_units,
	}


static func _ensure_progress_baseline(site_id: int) -> void:
	var site := WorldData.get_city_construction_site_by_id(site_id)

	if site.is_empty():
		return

	if (
		float(
			site.get(
				PROGRESS_REQUIRED_CLEARING_WORK_UNITS_KEY,
				-1.0
			)
		) >= 0.0
	):
		return

	site[PROGRESS_REQUIRED_CLEARING_WORK_UNITS_KEY] = (
		_get_remaining_clearing_work_units(site)
	)
	WorldData.update_city_construction_site(site)


static func _get_remaining_clearing_work_units(
	site: Dictionary
) -> float:
	var city_world: WorldData = WorldData.official_city_world

	if site.is_empty() or city_world == null:
		return 0.0

	var site_id := int(site.get("id", -1))
	var footprint_tiles: Array = site.get("footprint_tiles", [])
	var pending_yield_by_resource: Dictionary = {}
	var remaining_work_units := 0.0
	var safe_base_minutes := maxf(
		PROGRESS_BASE_WORK_MINUTES,
		1.0
	)

	for raw_tile_position in footprint_tiles:
		if not raw_tile_position is Vector2i:
			continue

		var tile_position: Vector2i = raw_tile_position
		var tile := city_world.get_tile(
			tile_position.x,
			tile_position.y
		)
		var surface_feature := WorldData.get_city_surface_feature(tile)

		if not WorldData.is_city_surface_feature(surface_feature):
			continue

		remaining_work_units += (
			float(WorldData.CITY_PLAYER_COMMAND_WORK_DURATION_MINUTES)
			/ safe_base_minutes
		)

		var resource := (
			WorldData.get_city_surface_feature_resource_type(
				surface_feature
			)
		)

		if not WorldData.is_city_resource_type(resource):
			continue

		pending_yield_by_resource[resource] = (
			int(pending_yield_by_resource.get(resource, 0))
			+ WorldData.CITY_PLAYER_COMMAND_RESOURCE_YIELD
		)

	for raw_ground_pile in WorldData.get_city_ground_pile_snapshot():
		if not raw_ground_pile is Dictionary:
			continue

		var ground_pile: Dictionary = raw_ground_pile

		if not footprint_tiles.has(
			ground_pile.get(
				"tile_position",
				WorldData.INVALID_CITY_TILE_POSITION
			)
		):
			continue

		if (
			WorldData.get_city_ground_pile_construction_site_id(
				ground_pile
			) == site_id
		):
			continue

		remaining_work_units += float(
			maxi(int(ground_pile.get("amount", 0)), 0)
		)

	for raw_resource in pending_yield_by_resource.keys():
		var resource := str(raw_resource)
		var pending_yield := maxi(
			int(pending_yield_by_resource.get(raw_resource, 0)),
			0
		)
		var remaining_required_amount := (
			WorldData.get_city_construction_site_remaining_resource_amount(
				site_id,
				resource
			)
		)

		remaining_work_units += float(
			maxi(
				pending_yield - remaining_required_amount,
				0
			)
		)

	return maxf(remaining_work_units, 0.0)


static func _reserve_needed_footprint_materials(
	site_id: int
) -> void:
	var site := WorldData.get_city_construction_site_by_id(site_id)

	if site.is_empty():
		return

	var footprint_tiles: Array = site.get("footprint_tiles", [])
	var ground_piles := WorldData.get_city_ground_pile_snapshot()

	ground_piles.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return int(a.get("id", -1)) < int(b.get("id", -1))
	)

	for raw_ground_pile in ground_piles:
		if not raw_ground_pile is Dictionary:
			continue

		var ground_pile: Dictionary = raw_ground_pile
		var raw_tile_position = ground_pile.get(
			"tile_position",
			WorldData.INVALID_CITY_TILE_POSITION
		)

		if (
			not raw_tile_position is Vector2i
			or not footprint_tiles.has(raw_tile_position)
			or WorldData.city_ground_pile_is_construction_reserved(
				ground_pile
			)
		):
			continue

		var resource := str(
			ground_pile.get(
				"resource_type",
				WorldData.RESOURCE_NONE
			)
		)
		var needed_amount := (
			WorldData.get_city_construction_site_unreserved_resource_space(
				site_id,
				resource
			)
		)

		if needed_amount <= 0:
			continue

		WorldData.reserve_city_ground_pile_for_construction(
			int(ground_pile.get("id", -1)),
			site_id,
			needed_amount
		)


static func _ensure_clearing_commands(site_id: int) -> void:
	var site := WorldData.get_city_construction_site_by_id(site_id)
	var city_world: WorldData = WorldData.official_city_world

	if site.is_empty() or city_world == null:
		return

	for raw_tile_position in site.get("footprint_tiles", []):
		if not raw_tile_position is Vector2i:
			continue

		var tile_position: Vector2i = raw_tile_position
		var tile := city_world.get_tile(
			tile_position.x,
			tile_position.y
		)
		var surface_feature := WorldData.get_city_surface_feature(tile)
		var command_type: String = (
			WorldData.CITY_PLAYER_COMMAND_TYPE_NONE
		)

		match surface_feature:
			WorldData.CITY_SURFACE_FEATURE_TREE:
				command_type = (
					WorldData.CITY_PLAYER_COMMAND_TYPE_CHOP_TREE
				)

			WorldData.CITY_SURFACE_FEATURE_ROCK:
				command_type = (
					WorldData.CITY_PLAYER_COMMAND_TYPE_COLLECT_ROCK
				)

		if command_type == WorldData.CITY_PLAYER_COMMAND_TYPE_NONE:
			continue

		WorldData.ensure_city_construction_clearing_command(
			site_id,
			command_type,
			tile_position
		)


static func _site_has_surface_obstruction(
	site: Dictionary
) -> bool:
	var city_world: WorldData = WorldData.official_city_world

	if city_world == null:
		return true

	for raw_tile_position in site.get("footprint_tiles", []):
		if not raw_tile_position is Vector2i:
			continue

		var tile_position: Vector2i = raw_tile_position
		var tile := city_world.get_tile(
			tile_position.x,
			tile_position.y
		)

		if WorldData.is_city_surface_feature(
			WorldData.get_city_surface_feature(tile)
		):
			return true

	return false


static func _site_has_ordinary_ground_pile(
	site: Dictionary
) -> bool:
	var site_id := int(site.get("id", -1))
	var footprint_tiles: Array = site.get("footprint_tiles", [])

	for raw_ground_pile in WorldData.city_ground_piles:
		if not raw_ground_pile is Dictionary:
			continue

		var ground_pile: Dictionary = raw_ground_pile

		if not footprint_tiles.has(
			ground_pile.get(
				"tile_position",
				WorldData.INVALID_CITY_TILE_POSITION
			)
		):
			continue

		if (
			WorldData.get_city_ground_pile_construction_site_id(
				ground_pile
			) != site_id
		):
			return true

	return false


static func get_best_assignable_player_work_for_citizen(
	citizen_id: int
) -> Dictionary:
	var citizen := WorldData.get_city_citizen_by_id(citizen_id)

	if (
		citizen.is_empty()
		or not bool(citizen.get("alive", false))
		or int(citizen.get("job_object_id", -1)) > 0
	):
		return {}

	var best_candidate: Dictionary = {}

	for raw_site in WorldData.get_city_construction_site_snapshot():
		if not raw_site is Dictionary:
			continue

		var site: Dictionary = raw_site
		var candidate := (
			get_best_assignable_player_work_for_citizen_and_site(
				citizen_id,
				int(site.get("id", -1))
			)
		)

		if _candidate_is_better(candidate, best_candidate):
			best_candidate = candidate

	return best_candidate


static func get_best_assignable_player_work_for_citizen_and_site(
	citizen_id: int,
	site_id: int
) -> Dictionary:
	var citizen := WorldData.get_city_citizen_by_id(citizen_id)
	var site := WorldData.get_city_construction_site_by_id(site_id)

	if (
		citizen.is_empty()
		or not bool(citizen.get("alive", false))
		or int(citizen.get("job_object_id", -1)) > 0
		or site.is_empty()
	):
		return {}

	match str(site.get("phase", "")):
		WorldData.CITY_CONSTRUCTION_PHASE_CLEARING:
			return _get_best_clearing_cleanup_candidate(citizen, site)

		WorldData.CITY_CONSTRUCTION_PHASE_GATHERING:
			return _get_best_delivery_candidate(citizen, site)

		WorldData.CITY_CONSTRUCTION_PHASE_LABOR:
			return _get_labor_candidate(citizen, site)

	return {}


static func _get_best_clearing_cleanup_candidate(
	citizen: Dictionary,
	site: Dictionary
) -> Dictionary:
	var citizen_id := int(citizen.get("id", -1))

	# Candidate selection happens before the player-work interruption gateway.
	# Let an existing physical load finish or spill through its current owner
	# before planning a footprint-cleanup pickup around it.
	if (
		citizen_id <= 0
		or WorldData.get_city_citizen_haul_cargo_amount(citizen_id) > 0
	):
		return {}

	var site_id := int(site.get("id", -1))
	var footprint_tiles: Array = site.get("footprint_tiles", [])
	var site_endpoint := (
		WorldData.make_city_construction_site_haul_endpoint(site_id)
	)
	var raw_citizen_tile = citizen.get(
		"city_tile_position",
		WorldData.INVALID_CITY_TILE_POSITION
	)
	var best_candidate: Dictionary = {}

	if site_id <= 0 or not raw_citizen_tile is Vector2i:
		return best_candidate

	for raw_ground_pile in WorldData.get_city_ground_pile_snapshot():
		if not raw_ground_pile is Dictionary:
			continue

		var ground_pile: Dictionary = raw_ground_pile
		var raw_pile_tile = ground_pile.get(
			"tile_position",
			WorldData.INVALID_CITY_TILE_POSITION
		)

		if (
			not raw_pile_tile is Vector2i
			or not footprint_tiles.has(raw_pile_tile)
			or WorldData.city_ground_pile_is_construction_reserved(
				ground_pile
			)
		):
			continue

		var ground_pile_id := int(ground_pile.get("id", -1))
		var resource := str(
			ground_pile.get(
				"resource_type",
				WorldData.RESOURCE_NONE
			)
		)
		var source := WorldData.make_city_ground_pile_haul_endpoint(
			ground_pile_id
		)
		var requested_amount := (
			WorldData.get_city_haul_endpoint_unreserved_resource_amount(
				source,
				resource
			)
		)

		if requested_amount <= 0:
			continue

		var task_request := (
			CitizenHaulingSystemScript.make_public_storage_haul_task_request({
				"city_world": WorldData.official_city_world,
				"citizen": citizen,
				"source": source,
				"requester": site_endpoint,
				"resource_type": resource,
				"requested_amount": requested_amount,
				"reason": (
					WorldData
					.CITY_CITIZEN_HAUL_REASON_GROUND_PILE_CLEANUP
				),
				"source_access_purpose": (
					WorldData
					.CONTAINER_HAUL_PURPOSE_GROUND_PILE_CLEANUP
				),
				"destination_access_purpose": (
					WorldData.CONTAINER_HAUL_PURPOSE_PUBLIC_STORAGE
				),
				"task_source": (
					WorldData.CITY_CITIZEN_TASK_SOURCE_PLAYER
				),
				"task_priority": (
					WorldData.CITY_CONSTRUCTION_TASK_PRIORITY
				),
			})
		)

		if task_request.is_empty():
			task_request = _make_ground_relocation_task_request(
				citizen,
				site,
				source,
				resource,
				requested_amount,
				raw_pile_tile
			)

		if task_request.is_empty():
			continue

		# This is one site-owned cleanup action, not the autonomous city-wide
		# pickup chain. It must clear this footprint before choosing new work.
		var raw_haul = task_request.get("haul", {})

		if raw_haul is Dictionary:
			var haul: Dictionary = raw_haul
			haul["allow_ground_pile_pickup_chaining"] = false
			task_request["haul"] = haul

		var haul: Dictionary = task_request.get("haul", {})
		var raw_source_tile = haul.get(
			"source_tile",
			WorldData.INVALID_CITY_TILE_POSITION
		)
		var raw_destination_tile = haul.get(
			"destination_tile",
			WorldData.INVALID_CITY_TILE_POSITION
		)

		if (
			not raw_source_tile is Vector2i
			or not raw_destination_tile is Vector2i
		):
			continue

		var path_cost := (
			_get_octile_path_cost(raw_citizen_tile, raw_source_tile)
			+ _get_octile_path_cost(
				raw_source_tile,
				raw_destination_tile
			)
		)
		var candidate := {
			"player_work_kind": PLAYER_WORK_KIND_DELIVERY,
			"construction_site_id": site_id,
			"issued_world_minute": int(
				site.get("issued_world_minute", 0)
			),
			"estimated_path_cost": path_cost,
			"selection_score": path_cost - _get_fairness_bonus(site),
			"task_request": task_request,
			"tie_break_key": (
				"cleanup:"
				+ str(ground_pile_id)
				+ ":"
				+ resource
			),
		}

		if _candidate_is_better(candidate, best_candidate):
			best_candidate = candidate

	return best_candidate


static func can_relocate_ground_pile_outside_site(
	site_id: int,
	ground_pile_id: int
) -> bool:
	var site := WorldData.get_city_construction_site_by_id(site_id)
	var pile := WorldData.get_city_ground_pile_by_id(ground_pile_id)
	var raw_source_tile = pile.get(
		"tile_position",
		WorldData.INVALID_CITY_TILE_POSITION
	)

	if (
		site.is_empty()
		or not raw_source_tile is Vector2i
		or not site.get("footprint_tiles", []).has(raw_source_tile)
		or WorldData.city_ground_pile_is_construction_reserved(pile)
	):
		return false

	return (
		_find_nearest_ground_relocation_tile(
			site,
			raw_source_tile,
			-1
		)
		!= WorldData.INVALID_CITY_TILE_POSITION
	)


static func _make_ground_relocation_task_request(
	citizen: Dictionary,
	site: Dictionary,
	source: Dictionary,
	resource: String,
	requested_amount: int,
	source_tile: Vector2i
) -> Dictionary:
	var citizen_id := int(citizen.get("id", -1))
	var destination_tile := _find_nearest_ground_relocation_tile(
		site,
		source_tile,
		citizen_id
	)

	if destination_tile == WorldData.INVALID_CITY_TILE_POSITION:
		return {}

	var excluded_pile_ids: Array[int] = []
	var footprint_tiles: Array = site.get("footprint_tiles", [])

	for raw_pile in WorldData.get_city_ground_pile_snapshot():
		if (
			raw_pile is Dictionary
			and footprint_tiles.has(
				raw_pile.get(
					"tile_position",
					WorldData.INVALID_CITY_TILE_POSITION
				)
			)
			and not WorldData.city_ground_pile_is_construction_reserved(
				raw_pile
			)
		):
			excluded_pile_ids.append(int(raw_pile.get("id", -1)))

	excluded_pile_ids.sort()
	var destination := WorldData.make_city_ground_tile_haul_endpoint(
		destination_tile,
		excluded_pile_ids
	)
	var site_endpoint := WorldData.make_city_construction_site_haul_endpoint(
		int(site.get("id", -1))
	)

	return CitizenHaulingSystemScript.make_directed_haul_task_request({
		"city_world": WorldData.official_city_world,
		"citizen": citizen,
		"source": source,
		"destination": destination,
		"requester": site_endpoint,
		"resource_type": resource,
		"requested_amount": requested_amount,
		"reason": (
			WorldData.CITY_CITIZEN_HAUL_REASON_GROUND_PILE_CLEANUP
		),
		"source_access_purpose": (
			WorldData.CONTAINER_HAUL_PURPOSE_GROUND_PILE_CLEANUP
		),
		"destination_access_purpose": (
			WorldData.CONTAINER_HAUL_PURPOSE_GROUND_PILE_CLEANUP
		),
		"task_source": WorldData.CITY_CITIZEN_TASK_SOURCE_PLAYER,
		"task_priority": WorldData.CITY_CONSTRUCTION_TASK_PRIORITY,
	})


static func _find_nearest_ground_relocation_tile(
	site: Dictionary,
	source_tile: Vector2i,
	citizen_id: int
) -> Vector2i:
	var city_world: WorldData = WorldData.official_city_world

	if city_world == null:
		return WorldData.INVALID_CITY_TILE_POSITION

	var footprint_tiles: Array = site.get("footprint_tiles", [])
	var maximum_radius := maxi(city_world.width, city_world.height)

	for radius in range(1, maximum_radius + 1):
		var candidate_tiles: Array = []

		for offset_y in range(-radius, radius + 1):
			for offset_x in range(-radius, radius + 1):
				if maxi(absi(offset_x), absi(offset_y)) != radius:
					continue

				var candidate_tile := (
					source_tile + Vector2i(offset_x, offset_y)
				)

				if (
					footprint_tiles.has(candidate_tile)
					or not WorldData.get_city_construction_site_at_tile(
						candidate_tile
					).is_empty()
					or not WorldData.can_city_ground_pile_exist_at_tile(
						city_world,
						candidate_tile
					)
				):
					continue

				candidate_tiles.append(candidate_tile)

		candidate_tiles.sort_custom(_sort_tiles_y_then_x)

		if candidate_tiles.is_empty():
			continue

		if citizen_id <= 0:
			return candidate_tiles[0]

		var path_result := (
			CityNavigationSystemScript.find_path_to_any_city_tile(
				city_world,
				source_tile,
				candidate_tiles,
				_get_city_wide_path_expansion_limit(city_world),
				citizen_id,
				EXACT_PATH_HEURISTIC_WEIGHT
			)
		)

		if not bool(path_result.get("success", false)):
			continue

		var raw_destination_tile = path_result.get(
			"destination_tile",
			WorldData.INVALID_CITY_TILE_POSITION
		)

		if raw_destination_tile is Vector2i:
			return raw_destination_tile

	return WorldData.INVALID_CITY_TILE_POSITION


static func _get_octile_path_cost(
	from_tile: Vector2i,
	to_tile: Vector2i
) -> int:
	var distance_x := absi(to_tile.x - from_tile.x)
	var distance_y := absi(to_tile.y - from_tile.y)
	var diagonal_steps := mini(distance_x, distance_y)
	var straight_steps := maxi(distance_x, distance_y) - diagonal_steps
	return diagonal_steps * 14_142 + straight_steps * 10_000


static func _get_best_delivery_candidate(
	citizen: Dictionary,
	site: Dictionary
) -> Dictionary:
	var site_id := int(site.get("id", -1))
	var destination := (
		WorldData.make_city_construction_site_haul_endpoint(site_id)
	)
	var best_candidate: Dictionary = {}

	for resource in WorldData.get_city_resource_types():
		var requested_amount := (
			WorldData.get_city_construction_site_unreserved_resource_space(
				site_id,
				resource
			)
		)

		if requested_amount <= 0:
			continue

		var supply_candidates := (
			CityResourceMatcherScript.get_resource_supply_candidates(
				CityResourceMatcherScript.PURPOSE_CONSTRUCTION_SUPPLY,
				resource,
				requested_amount
			)
		)

		for supply_candidate in supply_candidates:
			var source: Dictionary = supply_candidate.get("endpoint", {})
			var source_requested_amount := int(
				supply_candidate.get("available_amount", 0)
			)

			if source_requested_amount <= 0:
				continue

			var task_request := (
				CitizenHaulingSystemScript.make_directed_haul_task_request({
					"city_world": WorldData.official_city_world,
					"citizen": citizen,
					"source": source,
					"destination": destination,
					"requester": destination,
					"resource_type": resource,
					"requested_amount": source_requested_amount,
					"reason": (
						WorldData
						.CITY_CITIZEN_HAUL_REASON_CONSTRUCTION_DELIVERY
					),
					"source_access_purpose": (
						WorldData.CONTAINER_HAUL_PURPOSE_CONSTRUCTION
					),
					"destination_access_purpose": (
						WorldData.CONTAINER_HAUL_PURPOSE_CONSTRUCTION
					),
					"task_source": (
						WorldData.CITY_CITIZEN_TASK_SOURCE_PLAYER
					),
					"task_priority": (
						WorldData.CITY_CONSTRUCTION_TASK_PRIORITY
					),
				})
			)

			if task_request.is_empty():
				continue

			var path_cost := maxi(
				int(task_request.get("selection_path_cost", 0)),
				0
			)
			var candidate := {
				"player_work_kind": PLAYER_WORK_KIND_DELIVERY,
				"construction_site_id": site_id,
				"issued_world_minute": int(
					site.get("issued_world_minute", 0)
				),
				"estimated_path_cost": path_cost,
				"selection_score": (
					path_cost - _get_fairness_bonus(site)
				),
				"task_request": task_request,
				"tie_break_key": (
					str(source.get("kind", ""))
					+ ":"
					+ str(int(source.get("id", -1)))
					+ ":"
					+ resource
				),
			}

			if _candidate_is_better(candidate, best_candidate):
				best_candidate = candidate

	return best_candidate

static func _get_labor_candidate(
	citizen: Dictionary,
	site: Dictionary
) -> Dictionary:
	var site_id := int(site.get("id", -1))

	if _get_active_laborer_count(site_id) >= maxi(
		int(site.get("maximum_workers", 1)),
		1
	):
		return {}

	var citizen_id := int(citizen.get("id", -1))
	var raw_current_tile = citizen.get(
		"city_tile_position",
		WorldData.INVALID_CITY_TILE_POSITION
	)

	if not raw_current_tile is Vector2i:
		return {}

	var claimed_positions := _get_claimed_labor_positions(site_id)
	var candidate_positions: Array[Vector2i] = []

	for position in WorldData.get_city_construction_site_work_positions(
		site
	):
		if (
			claimed_positions.has(position)
			or not WorldData.is_city_tile_walkable_for_citizen(
				WorldData.official_city_world,
				position,
				citizen_id
			)
		):
			continue

		candidate_positions.append(position)

	if candidate_positions.is_empty():
		return {}

	var path_result := (
		CityNavigationSystemScript.find_path_to_any_city_tile(
			WorldData.official_city_world,
			raw_current_tile,
			candidate_positions,
			_get_city_wide_path_expansion_limit(
				WorldData.official_city_world
			),
			citizen_id,
			EXACT_PATH_HEURISTIC_WEIGHT
		)
	)

	if not bool(path_result.get("success", false)):
		return {}

	var raw_target_tile = path_result.get(
		"destination_tile",
		WorldData.INVALID_CITY_TILE_POSITION
	)

	if not raw_target_tile is Vector2i:
		return {}

	var path_cost := maxi(int(path_result.get("path_cost", 0)), 0)

	return {
		"player_work_kind": PLAYER_WORK_KIND_LABOR,
		"construction_site_id": site_id,
		"issued_world_minute": int(
			site.get("issued_world_minute", 0)
		),
		"estimated_path_cost": path_cost,
		"selection_score": path_cost - _get_fairness_bonus(site),
		"target_tile": raw_target_tile,
		"tie_break_key": str(raw_target_tile),
	}


static func _get_active_laborer_count(site_id: int) -> int:
	var count := 0

	for raw_citizen in WorldData.city_citizens:
		if not raw_citizen is Dictionary:
			continue

		var current_task = raw_citizen.get("current_task", {})

		if (
			current_task is Dictionary
			and str(current_task.get("kind", ""))
			== WorldData.CITY_CITIZEN_TASK_KIND_CONSTRUCTION
			and int(current_task.get("target_object_id", -1))
			== site_id
		):
			count += 1

	return count


static func _get_claimed_labor_positions(
	site_id: int,
	excluding_citizen_id: int = -1
) -> Dictionary:
	var claimed_positions: Dictionary = {}

	for raw_citizen in WorldData.city_citizens:
		if not raw_citizen is Dictionary:
			continue

		var citizen: Dictionary = raw_citizen

		if int(citizen.get("id", -1)) == excluding_citizen_id:
			continue

		var current_task = citizen.get("current_task", {})

		if (
			not current_task is Dictionary
			or str(current_task.get("kind", ""))
			!= WorldData.CITY_CITIZEN_TASK_KIND_CONSTRUCTION
			or int(current_task.get("target_object_id", -1))
			!= site_id
		):
			continue

		var raw_target_tile = current_task.get(
			"target_tile",
			WorldData.INVALID_CITY_TILE_POSITION
		)

		if raw_target_tile is Vector2i:
			claimed_positions[raw_target_tile] = true

	return claimed_positions


static func _get_fairness_bonus(site: Dictionary) -> int:
	var age_minutes := maxi(
		SimulationClock.absolute_world_minutes
		- int(site.get("issued_world_minute", 0)),
		0
	)
	return mini(
		age_minutes
		* WorldData.CITY_CONSTRUCTION_FAIRNESS_BONUS_PER_MINUTE,
		WorldData.CITY_CONSTRUCTION_MAX_FAIRNESS_BONUS
	)


static func _candidate_is_better(
	candidate: Dictionary,
	current_best: Dictionary
) -> bool:
	if candidate.is_empty():
		return false

	if current_best.is_empty():
		return true

	var candidate_score := int(
		candidate.get("selection_score", 0)
	)
	var best_score := int(current_best.get("selection_score", 0))

	if candidate_score != best_score:
		return candidate_score < best_score

	var candidate_minute := int(
		candidate.get("issued_world_minute", 0)
	)
	var best_minute := int(
		current_best.get("issued_world_minute", 0)
	)

	if candidate_minute != best_minute:
		return candidate_minute < best_minute

	var candidate_site_id := int(
		candidate.get("construction_site_id", -1)
	)
	var best_site_id := int(
		current_best.get("construction_site_id", -1)
	)

	if candidate_site_id != best_site_id:
		return candidate_site_id < best_site_id

	return (
		str(candidate.get("tie_break_key", ""))
		< str(current_best.get("tie_break_key", ""))
	)


static func assign_player_work_candidate(
	citizen_id: int,
	candidate: Dictionary
) -> bool:
	match str(candidate.get("player_work_kind", "")):
		PLAYER_WORK_KIND_DELIVERY:
			var raw_task_request = candidate.get("task_request", {})

			return (
				raw_task_request is Dictionary
				and WorldData.assign_city_citizen_task(
					citizen_id,
					raw_task_request
				)
			)

		PLAYER_WORK_KIND_LABOR:
			var raw_target_tile = candidate.get(
				"target_tile",
				WorldData.INVALID_CITY_TILE_POSITION
			)

			if not raw_target_tile is Vector2i:
				return false

			return WorldData.assign_city_citizen_task(
				citizen_id,
				{
					"kind": (
						WorldData.CITY_CITIZEN_TASK_KIND_CONSTRUCTION
					),
					"source": (
						WorldData.CITY_CITIZEN_TASK_SOURCE_PLAYER
					),
					"priority": (
						WorldData.CITY_CONSTRUCTION_TASK_PRIORITY
					),
					"target_object_id": int(
						candidate.get(
							"construction_site_id",
							-1
						)
					),
					"target_tile": raw_target_tile,
					"player_locked": false,
					"work_order_id": int(
						candidate.get("work_order_id", -1)
					),
					"job_id": str(candidate.get("job_id", "")),
				}
			)

	return false


static func advance_labor_task(
	city_world: WorldData,
	citizen_id: int,
	citizen: Dictionary,
	current_task: Dictionary,
	path_requests_remaining: int,
	minutes_advanced: int
) -> int:
	var site_id := int(current_task.get("target_object_id", -1))
	var site := WorldData.get_city_construction_site_by_id(site_id)
	var raw_target_tile = current_task.get(
		"target_tile",
		WorldData.INVALID_CITY_TILE_POSITION
	)
	var raw_current_tile = citizen.get(
		"city_tile_position",
		WorldData.INVALID_CITY_TILE_POSITION
	)

	if (
		site.is_empty()
		or str(site.get("phase", ""))
		!= WorldData.CITY_CONSTRUCTION_PHASE_LABOR
		or int(citizen.get("job_object_id", -1)) > 0
		or not raw_target_tile is Vector2i
		or not raw_current_tile is Vector2i
		or not WorldData.get_city_construction_site_work_positions(
			site
		).has(raw_target_tile)
	):
		_release_labor_task(citizen_id)
		return path_requests_remaining

	var target_tile: Vector2i = raw_target_tile
	var current_tile: Vector2i = raw_current_tile
	var task_phase := str(
		current_task.get(
			"phase",
			WorldData.CITY_CITIZEN_TASK_PHASE_NONE
		)
	)
	var movement_state := str(
		citizen.get(
			"movement_state",
			WorldData.CITY_CITIZEN_MOVEMENT_STATE_IDLE
		)
	)

	match task_phase:
		WorldData.CITY_CITIZEN_TASK_PHASE_PENDING:
			if current_tile == target_tile:
				_begin_labor(citizen_id, target_tile)
				return path_requests_remaining

			if movement_state == WorldData.CITY_CITIZEN_MOVEMENT_STATE_MOVING:
				return path_requests_remaining

			if path_requests_remaining <= 0:
				return path_requests_remaining

			path_requests_remaining -= 1
			var path_result := (
				CityNavigationSystemScript.find_path_to_any_city_tile(
					city_world,
					current_tile,
					[target_tile],
					_get_city_wide_path_expansion_limit(city_world),
					citizen_id,
					EXACT_PATH_HEURISTIC_WEIGHT
				)
			)

			if (
				not bool(path_result.get("success", false))
				or not WorldData.assign_city_citizen_movement_order(
					citizen_id,
					path_result.get("path", [])
				)
			):
				_release_labor_task(citizen_id)
				return path_requests_remaining

			WorldData.set_city_citizen_task_phase(
				citizen_id,
				WorldData.CITY_CITIZEN_TASK_PHASE_TRAVELING
			)

		WorldData.CITY_CITIZEN_TASK_PHASE_TRAVELING:
			if current_tile == target_tile:
				_begin_labor(citizen_id, target_tile)
			elif movement_state != WorldData.CITY_CITIZEN_MOVEMENT_STATE_MOVING:
				WorldData.set_city_citizen_task_phase(
					citizen_id,
					WorldData.CITY_CITIZEN_TASK_PHASE_PENDING
				)

		WorldData.CITY_CITIZEN_TASK_PHASE_PERFORMING:
			if current_tile != target_tile:
				WorldData.set_city_citizen_task_phase(
					citizen_id,
					WorldData.CITY_CITIZEN_TASK_PHASE_PENDING
				)
				return path_requests_remaining

			if _add_labor_progress(site_id, minutes_advanced):
				complete_city_construction_site(site_id)
				return path_requests_remaining

			var relocation_minute := int(
				current_task.get(
					"next_action_world_minute",
					WorldData.INVALID_CITY_CITIZEN_TASK_ACTION_WORLD_MINUTE
				)
			)

			if (
				relocation_minute >= 0
				and SimulationClock.absolute_world_minutes
				>= relocation_minute
			):
				# One labor commitment is deliberately bounded. Releasing the
				# concrete task here returns this citizen to the unified parent-
				# order scheduler, where this site may win again or a neglected
				# order may receive attention. The contributed labor above is
				# already physical simulation progress and is never rolled back.
				_release_labor_task(citizen_id)

		_:
			_release_labor_task(citizen_id)

	return path_requests_remaining


static func _begin_labor(
	citizen_id: int,
	target_tile: Vector2i
) -> bool:
	WorldData.cancel_city_citizen_movement(citizen_id)

	if not WorldData.set_city_citizen_task_activity_state({
		"citizen_id": citizen_id,
		"target_tile": target_tile,
		"next_action_world_minute": (
			SimulationClock.absolute_world_minutes
			+ WorldData.CITY_CONSTRUCTION_LABOR_ATOMIC_MINUTES
		),
	}):
		return false

	return WorldData.set_city_citizen_task_phase(
		citizen_id,
		WorldData.CITY_CITIZEN_TASK_PHASE_PERFORMING
	)


static func _add_labor_progress(
	site_id: int,
	minutes_advanced: int
) -> bool:
	var site := WorldData.get_city_construction_site_by_id(site_id)

	if (
		site.is_empty()
		or str(site.get("phase", ""))
		!= WorldData.CITY_CONSTRUCTION_PHASE_LABOR
	):
		return false

	site["completed_labor_minutes"] = mini(
		maxi(int(site.get("completed_labor_minutes", 0)), 0)
		+ maxi(minutes_advanced, 0),
		maxi(int(site.get("required_labor_minutes", 1)), 1)
	)

	if not WorldData.update_city_construction_site(site):
		return false

	return (
		int(site.get("completed_labor_minutes", 0))
		>= int(site.get("required_labor_minutes", 1))
	)


static func _relocate_laborer(
	citizen_id: int,
	site_id: int,
	current_target: Vector2i
) -> bool:
	var site := WorldData.get_city_construction_site_by_id(site_id)
	var citizen := WorldData.get_city_citizen_by_id(citizen_id)

	if site.is_empty() or citizen.is_empty():
		return false

	var claimed_positions := _get_claimed_labor_positions(
		site_id,
		citizen_id
	)
	var alternatives: Array[Vector2i] = []

	for position in WorldData.get_city_construction_site_work_positions(
		site
	):
		if (
			position == current_target
			or claimed_positions.has(position)
			or not WorldData.is_city_tile_walkable_for_citizen(
				WorldData.official_city_world,
				position,
				citizen_id
			)
		):
			continue

		alternatives.append(position)

	if alternatives.is_empty():
		return WorldData.set_city_citizen_task_activity_state({
			"citizen_id": citizen_id,
			"target_tile": current_target,
			"next_action_world_minute": (
				SimulationClock.absolute_world_minutes
				+ WorldData.CITY_CONSTRUCTION_LABOR_ATOMIC_MINUTES
			),
		})

	var sequence := maxi(
		int(
			WorldData.get_city_citizen_current_task(
				citizen_id
			).get("relocation_count", 0)
		),
		0
	)
	var next_target := alternatives[
		posmod(citizen_id + site_id + sequence, alternatives.size())
	]

	if not WorldData.set_city_citizen_task_activity_state({
		"citizen_id": citizen_id,
		"target_tile": next_target,
		"previous_target_tile": current_target,
		"next_action_world_minute": (
			WorldData.INVALID_CITY_CITIZEN_TASK_ACTION_WORLD_MINUTE
		),
		"relocation_count": sequence + 1,
	}):
		return false

	return WorldData.set_city_citizen_task_phase(
		citizen_id,
		WorldData.CITY_CITIZEN_TASK_PHASE_PENDING
	)


static func _release_labor_task(citizen_id: int) -> void:
	WorldData.clear_city_citizen_task(
		citizen_id,
		WorldData.CITY_CITIZEN_TASK_SOURCE_PLAYER
	)
	WorldData.cancel_city_citizen_movement(citizen_id)


static func complete_city_construction_site(
	site_id: int
) -> Dictionary:
	refresh_city_construction_site(site_id)
	var site := WorldData.get_city_construction_site_by_id(site_id)

	if (
		site.is_empty()
		or str(site.get("target_kind", ""))
		!= WorldData.CITY_CONSTRUCTION_TARGET_NEW
		or str(site.get("phase", ""))
		!= WorldData.CITY_CONSTRUCTION_PHASE_LABOR
		or int(site.get("completed_labor_minutes", 0))
		< int(site.get("required_labor_minutes", 1))
		or not WorldData.city_construction_site_has_all_materials(
			site_id
		)
	):
		return {}

	if not _release_site_delivery_tasks(site_id):
		return {}

	refresh_city_construction_site(site_id)
	site = WorldData.get_city_construction_site_by_id(site_id)

	if (
		site.is_empty()
		or str(site.get("phase", ""))
		!= WorldData.CITY_CONSTRUCTION_PHASE_LABOR
		or not WorldData.city_construction_site_has_all_materials(
			site_id
		)
	):
		return {}

	var consumed_materials := _consume_site_materials(site)
	var raw_material_recipe = site.get("material_recipe", {})

	if (
		consumed_materials.is_empty()
		and raw_material_recipe is Dictionary
		and not raw_material_recipe.is_empty()
	):
		return {}

	_clear_site_labor_tasks(site_id)
	var completed_object: Dictionary = {}
	var object_type := str(site.get("object_type", ""))

	if (
		str(site.get("shape_mode", ""))
		== WorldData.CITY_OBJECT_SHAPE_TILE_AREA
	):
		completed_object = WorldData.add_city_road_object(
			site.get("footprint_tiles", []),
			str(site.get("owner", "player")),
			WorldData.official_city_world
		)
	else:
		completed_object = WorldData.add_city_object(
			object_type,
			site.get("top_left", WorldData.INVALID_CITY_TILE_POSITION),
			site.get("size", Vector2i.ZERO),
			str(site.get("owner", "player")),
			WorldData.official_city_world
		)

	if completed_object.is_empty():
		_restore_site_materials(site, consumed_materials)
		return {}

	_release_site_clearing_commands(site_id)
	WorldData.remove_city_construction_site_record(site_id)
	return completed_object


static func _consume_site_materials(
	site: Dictionary
) -> Dictionary:
	var site_id := int(site.get("id", -1))
	var raw_recipe = site.get("material_recipe", {})
	var consumed: Dictionary = {}

	if not raw_recipe is Dictionary:
		return consumed

	for resource in WorldData.get_city_resource_types():
		var required_amount := maxi(
			int(raw_recipe.get(resource, 0)),
			0
		)

		if required_amount <= 0:
			continue

		var removed_amount := (
			WorldData.remove_resource_from_city_construction_site(
				site_id,
				resource,
				required_amount
			)
		)

		if removed_amount != required_amount:
			_restore_site_materials(site, consumed)

			if removed_amount > 0:
				_restore_site_materials(
					site,
					{resource: removed_amount}
				)

			return {}

		consumed[resource] = removed_amount

	return consumed


static func _restore_site_materials(
	site: Dictionary,
	materials: Dictionary
) -> void:
	var site_id := int(site.get("id", -1))
	var raw_footprint_tiles = site.get("footprint_tiles", [])

	if (
		site_id <= 0
		or not raw_footprint_tiles is Array
		or raw_footprint_tiles.is_empty()
	):
		return

	var deposit_tile: Vector2i = raw_footprint_tiles[0]

	for resource in materials.keys():
		var amount := maxi(int(materials.get(resource, 0)), 0)

		if amount <= 0:
			continue

		WorldData.add_resource_to_city_ground_pile(
			deposit_tile,
			str(resource),
			amount,
			site_id
		)


static func cancel_city_construction_site(site_id: int) -> bool:
	var site := WorldData.get_city_construction_site_by_id(site_id)

	if site.is_empty():
		return false

	# Stop deliveries first while every referenced endpoint still exists. A
	# picked-up load remains physical cargo and is converted into an outstanding
	# public-storage obligation; cancellation never spills it merely because its
	# original destination disappeared.
	if not _release_site_delivery_tasks(site_id):
		return false

	_release_site_clearing_commands(site_id)
	_clear_site_labor_tasks(site_id)
	WorldData.release_city_construction_site_materials(site_id)
	return WorldData.remove_city_construction_site_record(site_id)


static func _release_site_delivery_tasks(site_id: int) -> bool:
	for raw_citizen in WorldData.city_citizens.duplicate(true):
		if not raw_citizen is Dictionary:
			continue

		var citizen: Dictionary = raw_citizen
		var citizen_id := int(citizen.get("id", -1))
		var current_task = citizen.get("current_task", {})

		if (
			not current_task is Dictionary
			or str(current_task.get("kind", ""))
			!= WorldData.CITY_CITIZEN_TASK_KIND_HAUL
			or not _haul_references_site(citizen_id, site_id)
		):
			continue

		var cargo_amount := (
			WorldData.get_city_citizen_haul_cargo_amount(citizen_id)
		)

		if cargo_amount > 0:
			var haul := WorldData.get_city_citizen_current_haul(citizen_id)
			var raw_source = haul.get("source", {})

			if not raw_source is Dictionary:
				return false

			var source: Dictionary = raw_source
			haul["destination"] = (
				CityCitizens.make_city_citizen_haul_endpoint()
			)
			haul["requester"] = source
			haul["reason"] = (
				WorldData.CITY_CITIZEN_HAUL_REASON_OUTSTANDING_CARGO
			)
			WorldData.set_city_citizen_current_haul(citizen_id, haul)

		var task_source := str(
			current_task.get(
				"source",
				WorldData.CITY_CITIZEN_TASK_SOURCE_PLAYER
			)
		)

		WorldData.cancel_city_citizen_movement(citizen_id)

		if not WorldData.clear_city_citizen_task(citizen_id, task_source):
			return false

	var site_endpoint := (
		WorldData.make_city_construction_site_haul_endpoint(site_id)
	)

	for reservation in WorldData.get_city_haul_reservation_snapshot():
		if WorldData.city_citizen_haul_endpoints_match(
			reservation.get("destination", {}),
			site_endpoint
		):
			WorldData.release_city_haul_reservation(
				int(reservation.get("id", -1))
			)

	return true


static func _release_site_clearing_commands(site_id: int) -> void:
	var command_snapshot := WorldData.get_city_player_command_snapshot()

	for raw_command in command_snapshot:
		if not raw_command is Dictionary:
			continue

		var command: Dictionary = raw_command

		if int(command.get("construction_site_id", -1)) != site_id:
			continue

		var command_id := int(command.get("id", -1))

		if bool(command.get("created_by_construction", false)):
			WorldData.cancel_city_player_command(command_id)
		else:
			WorldData.detach_city_player_command_from_construction(
				command_id,
				site_id
			)


static func _clear_site_labor_tasks(site_id: int) -> void:
	for raw_citizen in WorldData.city_citizens.duplicate(true):
		if not raw_citizen is Dictionary:
			continue

		var citizen: Dictionary = raw_citizen
		var current_task = citizen.get("current_task", {})

		if (
			current_task is Dictionary
			and str(current_task.get("kind", ""))
			== WorldData.CITY_CITIZEN_TASK_KIND_CONSTRUCTION
			and int(current_task.get("target_object_id", -1))
			== site_id
		):
			_release_labor_task(int(citizen.get("id", -1)))


static func _haul_references_site(
	citizen_id: int,
	site_id: int
) -> bool:
	var haul := WorldData.get_city_citizen_current_haul(citizen_id)
	var site_endpoint := (
		WorldData.make_city_construction_site_haul_endpoint(site_id)
	)

	for endpoint_field in ["source", "destination", "requester"]:
		var raw_endpoint = haul.get(endpoint_field, {})

		if (
			raw_endpoint is Dictionary
			and WorldData.city_citizen_haul_endpoints_match(
				raw_endpoint,
				site_endpoint
			)
		):
			return true

	return false


static func citizen_task_is_interruptible_construction(
	citizen_id: int
) -> bool:
	var current_task := WorldData.get_city_citizen_current_task(
		citizen_id
	)

	match str(current_task.get("kind", "")):
		WorldData.CITY_CITIZEN_TASK_KIND_CONSTRUCTION:
			return true

		WorldData.CITY_CITIZEN_TASK_KIND_PLAYER_COMMAND:
			return WorldData.city_player_command_is_for_construction(
				WorldData.get_city_player_command_by_id(
					int(current_task.get("target_object_id", -1))
				)
			)

		WorldData.CITY_CITIZEN_TASK_KIND_HAUL:
			var haul := WorldData.get_city_citizen_current_haul(
				citizen_id
			)
			var requester: Dictionary = haul.get("requester", {})

			return (
				str(
					haul.get(
						"reason",
						WorldData.CITY_CITIZEN_HAUL_REASON_NONE
					)
				)
				== WorldData
				.CITY_CITIZEN_HAUL_REASON_CONSTRUCTION_DELIVERY
				or str(
					requester.get(
						"kind",
						WorldData.CITY_CITIZEN_HAUL_ENDPOINT_KIND_NONE
					)
				)
				== WorldData
				.CITY_CITIZEN_HAUL_ENDPOINT_KIND_CONSTRUCTION_SITE
			)

	return false


static func interrupt_citizen_construction_for_food(
	citizen_id: int
) -> bool:
	if not citizen_task_is_interruptible_construction(citizen_id):
		return false

	var current_task := WorldData.get_city_citizen_current_task(
		citizen_id
	)

	if (
		str(current_task.get("kind", ""))
		== WorldData.CITY_CITIZEN_TASK_KIND_CONSTRUCTION
	):
		_release_labor_task(citizen_id)
		return true

	return (
		CitizenHaulingSystemScript
		.drop_citizen_haul_cargo_for_priority_interrupt(
			WorldData.official_city_world,
			citizen_id,
			WorldData.CITY_CITIZEN_TASK_SOURCE_PLAYER
		)
	)


static func _sort_tiles_y_then_x(
	tile_a: Vector2i,
	tile_b: Vector2i
) -> bool:
	if tile_a.y == tile_b.y:
		return tile_a.x < tile_b.x

	return tile_a.y < tile_b.y


static func _get_city_wide_path_expansion_limit(
	city_world: WorldData
) -> int:
	if city_world == null:
		return 1

	return maxi(city_world.width * city_world.height, 1)
