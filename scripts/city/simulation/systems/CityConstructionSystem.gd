extends RefCounted
class_name CityConstructionSystem

# File responsibility: Authoritative construction behavior/API for one active city settlement. Mutable construction registries live in CityConstructionState.
# Navigation regions are organizational only; they do not define runtime ownership.

const CityObjectCatalogScript = preload(
	"res://scripts/city/data/CityObjectCatalog.gd"
)
const CityNavigationSystemScript = preload(
	"res://scripts/city/simulation/systems/CityNavigationSystem.gd"
)
const CitizenHaulingSystemScript = preload(
	"res://scripts/citizens/simulation/systems/CitizenHaulingSystem.gd"
)
const CitizenNeedsSystemScript = preload(
	"res://scripts/citizens/simulation/systems/CitizenNeedsSystem.gd"
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
	CityWorkSystem.CITY_PLAYER_COMMAND_WORK_DURATION_MINUTES
)
const EXACT_PATH_HEURISTIC_WEIGHT: int = 1
const REBALANCE_MINIMUM_PATH_SAVINGS_TILES: int = 3
const REBALANCE_MINIMUM_RELATIVE_SAVINGS_PERCENT: int = 25


const CITY_CONSTRUCTION_PHASE_CLEARING := "clearing"
const CITY_CONSTRUCTION_PHASE_GATHERING := "gathering"
const CITY_CONSTRUCTION_PHASE_LABOR := "labor"
const CITY_CONSTRUCTION_FINALIZATION_STATE_NONE := "none"
const CITY_CONSTRUCTION_FINALIZATION_STATE_AWAITING_CLEARANCE := (
	"awaiting_clearance"
)
const CITY_CONSTRUCTION_TARGET_NEW := "new"
const CITY_CONSTRUCTION_TARGET_MODIFICATION := "modification"
const CITY_CONSTRUCTION_TASK_PRIORITY: int = 1000
const CITY_CONSTRUCTION_FAIRNESS_BONUS_PER_MINUTE: int = 100
const CITY_CONSTRUCTION_MAX_FAIRNESS_BONUS: int = 20_000
# A construction labor task contributes at most this many continuous world
# minutes before releasing its concrete claim and returning to the parent-order
# scheduler. This is the shared safe boundary for fairness and hunger policy.
const CITY_CONSTRUCTION_LABOR_ATOMIC_MINUTES: int = 30


static func get_current_state() -> CityConstructionState:
	return WorldPoliticalState.get_current_city_construction_state()


static func get_state_for_city_state(
	city_state: CitySettlementSimulationState
) -> CityConstructionState:
	if city_state == null:
		return null

	return city_state.construction_state


static func _get_state(
	city_state: CitySettlementSimulationState = null
) -> CityConstructionState:
	return (
		get_current_state()
		if city_state == null
		else get_state_for_city_state(city_state)
	)


static func _get_city_world(
	city_state: CitySettlementSimulationState = null
) -> WorldData:
	return (
		WorldPoliticalState.get_current_city_world()
		if city_state == null
		else city_state.city_world
	)


static func get_city_object_construction_materials(
	object_type: String
) -> Dictionary:
	return (
		CityObjectCatalogScript
		.get_city_object_construction_materials(object_type)
	)

static func city_object_type_uses_construction(
	object_type: String
) -> bool:
	return (
		CityObjectCatalogScript
		.city_object_type_uses_construction(object_type)
	)


static func can_place_city_road_tile(
	city_world: WorldData,
	tile_position: Vector2i
) -> bool:
	return (
		city_object_type_uses_construction(CityObjectCatalog.CITY_OBJECT_ROAD)
		and can_place_city_construction_footprint(
			city_world,
			[tile_position]
		)
	)

static func mark_city_construction_changed() -> void:
	get_current_state().construction_version += 1


static func mark_city_construction_changed_for_city_state(
	city_state: CitySettlementSimulationState
) -> void:
	var construction_state := get_state_for_city_state(city_state)

	if construction_state != null:
		construction_state.construction_version += 1


static func get_city_construction_site_index_by_id(
	site_id: int
) -> int:
	return _get_city_construction_site_index_by_id(null, site_id)


static func get_city_construction_site_index_by_id_for_city_state(
	city_state: CitySettlementSimulationState,
	site_id: int
) -> int:
	return _get_city_construction_site_index_by_id(city_state, site_id)


static func _get_city_construction_site_index_by_id(
	city_state: CitySettlementSimulationState,
	site_id: int
) -> int:
	var construction_state := _get_state(city_state)

	if construction_state == null or site_id <= 0:
		return -1

	if not construction_state.construction_site_index_by_id.has(site_id):
		return -1

	var site_index := int(
		construction_state.construction_site_index_by_id[site_id]
	)

	if site_index < 0 or site_index >= construction_state.construction_sites.size():
		return -1

	var raw_site = construction_state.construction_sites[site_index]

	if (
		not raw_site is Dictionary
		or int(raw_site.get("id", -1)) != site_id
	):
		return -1

	return site_index

static func get_city_construction_site_by_id(
	site_id: int
) -> Dictionary:
	return _get_city_construction_site_by_id(null, site_id)


static func get_city_construction_site_by_id_for_city_state(
	city_state: CitySettlementSimulationState,
	site_id: int
) -> Dictionary:
	return _get_city_construction_site_by_id(city_state, site_id)


static func _get_city_construction_site_by_id(
	city_state: CitySettlementSimulationState,
	site_id: int
) -> Dictionary:
	var construction_state := _get_state(city_state)
	var site_index := _get_city_construction_site_index_by_id(
		city_state,
		site_id
	)

	if construction_state == null or site_index < 0:
		return {}

	return construction_state.construction_sites[site_index].duplicate(true)

static func can_place_city_construction_footprint(
	city_world: WorldData,
	raw_footprint_tiles: Array,
	require_external_access: bool = false,
	allowed_occupied_object_id: int = -1
) -> bool:
	if city_world == null or raw_footprint_tiles.is_empty():
		return false

	var clean_tiles: Array[Vector2i] = []
	var tile_lookup: Dictionary = {}

	for raw_tile in raw_footprint_tiles:
		if not raw_tile is Vector2i:
			return false

		var tile_position: Vector2i = raw_tile

		if tile_lookup.has(tile_position):
			continue

		if not city_world.is_in_bounds(tile_position.x, tile_position.y):
			return false

		if get_current_state().construction_site_id_by_tile.has(tile_position):
			return false

		var occupied_object_id := (
			CityObjectSystem.get_city_object_id_at_tile(tile_position)
		)

		if (
			occupied_object_id > 0
			and occupied_object_id != allowed_occupied_object_id
		):
			return false

		var tile := city_world.get_tile_for_internal_read(
			tile_position.x,
			tile_position.y
		)
		var terrain := str(tile.get("terrain", CityObjectCatalog.TERRAIN_WATER))

		if (
			terrain == CityObjectCatalog.TERRAIN_WATER
			or terrain == WorldData.TERRAIN_MOUNTAIN
			or not bool(tile.get("is_land", false))
		):
			return false

		tile_lookup[tile_position] = true
		clean_tiles.append(tile_position)

	if not require_external_access:
		return true

	for footprint_tile in clean_tiles:
		for offset in CityNavigationSystem.CITY_CARDINAL_TILE_OFFSETS:
			var candidate_tile: Vector2i = (
				footprint_tile + Vector2i(offset)
			)

			if tile_lookup.has(candidate_tile):
				continue

			if CityNavigationSystem.is_city_tile_walkable_for_citizen(
				city_world,
				candidate_tile
			):
				return true

	return false

static func reset_city_construction_state() -> void:
	get_current_state().construction_sites.clear()
	get_current_state().construction_site_index_by_id.clear()
	get_current_state().construction_site_id_by_tile.clear()
	get_current_state().next_construction_site_id = 1
	mark_city_construction_changed()

static func get_city_construction_site_work_positions(
	site: Dictionary
) -> Array[Vector2i]:
	var positions: Array[Vector2i] = []
	var raw_positions = site.get("work_positions", [])

	if not raw_positions is Array:
		return positions

	for raw_position in raw_positions:
		if raw_position is Vector2i:
			positions.append(raw_position)

	return positions

static func get_city_construction_site_reserved_resource_amount(
	site_id: int,
	resource: String
) -> int:
	return _get_city_construction_site_reserved_resource_amount(
		null,
		site_id,
		resource
	)


static func get_city_construction_site_reserved_resource_amount_for_city_state(
	city_state: CitySettlementSimulationState,
	site_id: int,
	resource: String
) -> int:
	return _get_city_construction_site_reserved_resource_amount(
		city_state,
		site_id,
		resource
	)


static func _get_city_construction_site_reserved_resource_amount(
	city_state: CitySettlementSimulationState,
	site_id: int,
	resource: String
) -> int:
	var total_amount := 0
	var logistics_state: CityLogisticsState = (
		CityLogisticsSystem.get_current_state()
		if city_state == null
		else city_state.logistics_state
	)

	if logistics_state == null:
		return 0

	for raw_ground_pile in logistics_state.ground_piles:
		if not raw_ground_pile is Dictionary:
			continue

		var ground_pile: Dictionary = raw_ground_pile

		if (
			CityLogisticsSystem.get_city_ground_pile_construction_site_id(ground_pile)
			!= site_id
		):
			continue

		total_amount += CityLogisticsSystem.get_city_ground_pile_resource_amount(
			ground_pile,
			resource
		)

	return total_amount

static func get_city_construction_site_remaining_resource_amount(
	site_id: int,
	resource: String
) -> int:
	return _get_city_construction_site_remaining_resource_amount(
		null,
		site_id,
		resource
	)


static func get_city_construction_site_remaining_resource_amount_for_city_state(
	city_state: CitySettlementSimulationState,
	site_id: int,
	resource: String
) -> int:
	return _get_city_construction_site_remaining_resource_amount(
		city_state,
		site_id,
		resource
	)


static func _get_city_construction_site_remaining_resource_amount(
	city_state: CitySettlementSimulationState,
	site_id: int,
	resource: String
) -> int:
	var site := _get_city_construction_site_by_id(city_state, site_id)

	if site.is_empty():
		return 0

	var raw_recipe = site.get("material_recipe", {})

	if not raw_recipe is Dictionary:
		return 0

	return maxi(
		int(raw_recipe.get(resource, 0))
		- _get_city_construction_site_reserved_resource_amount(
			city_state,
			site_id,
			resource
		),
		0
	)

static func get_city_construction_site_destination_reserved_resource_amount(
	site_id: int,
	resource: String,
	excluding_reservation_id: int = (
		CityCitizens.INVALID_CITY_CITIZEN_HAUL_RESERVATION_ID
	)
) -> int:
	return _get_city_construction_site_destination_reserved_resource_amount(
		null,
		site_id,
		resource,
		excluding_reservation_id
	)


static func get_city_construction_site_destination_reserved_resource_amount_for_city_state(
	city_state: CitySettlementSimulationState,
	site_id: int,
	resource: String,
	excluding_reservation_id: int = (
		CityCitizens.INVALID_CITY_CITIZEN_HAUL_RESERVATION_ID
	)
) -> int:
	return _get_city_construction_site_destination_reserved_resource_amount(
		city_state,
		site_id,
		resource,
		excluding_reservation_id
	)


static func _get_city_construction_site_destination_reserved_resource_amount(
	city_state: CitySettlementSimulationState,
	site_id: int,
	resource: String,
	excluding_reservation_id: int
) -> int:
	var site_endpoint := CityLogisticsSystem.make_city_construction_site_haul_endpoint(
		site_id
	)
	var reserved_amount := 0
	var logistics_state: CityLogisticsState = (
		CityLogisticsSystem.get_current_state()
		if city_state == null
		else city_state.logistics_state
	)

	if logistics_state == null:
		return 0

	for raw_reservation_id in logistics_state.haul_reservations.keys():
		var reservation_id := int(raw_reservation_id)

		if reservation_id == excluding_reservation_id:
			continue

		var reservation: Dictionary = (
			CityLogisticsSystem.get_city_haul_reservation(reservation_id)
			if city_state == null
			else CityLogisticsSystem.get_city_haul_reservation_for_city_state(
				city_state,
				reservation_id
			)
		)

		if (
			reservation.is_empty()
			or not CityLogisticsSystem.city_citizen_haul_endpoints_match(
				reservation.get("destination", {}),
				site_endpoint
			)
		):
			continue

		var destination_resources: Dictionary = (
			CityLogisticsSystem.get_city_haul_reservation_destination_resources(
				reservation_id
			)
			if city_state == null
			else CityLogisticsSystem.get_city_haul_reservation_destination_resources_for_city_state(
				city_state,
				reservation_id
			)
		)
		reserved_amount += maxi(
			int(destination_resources.get(resource, 0)),
			0
		)

	return reserved_amount

static func get_city_construction_site_unreserved_resource_space(
	site_id: int,
	resource: String,
	excluding_reservation_id: int = (
		CityCitizens.INVALID_CITY_CITIZEN_HAUL_RESERVATION_ID
	)
) -> int:
	return _get_city_construction_site_unreserved_resource_space(
		null,
		site_id,
		resource,
		excluding_reservation_id
	)


static func get_city_construction_site_unreserved_resource_space_for_city_state(
	city_state: CitySettlementSimulationState,
	site_id: int,
	resource: String,
	excluding_reservation_id: int = (
		CityCitizens.INVALID_CITY_CITIZEN_HAUL_RESERVATION_ID
	)
) -> int:
	return _get_city_construction_site_unreserved_resource_space(
		city_state,
		site_id,
		resource,
		excluding_reservation_id
	)


static func _get_city_construction_site_unreserved_resource_space(
	city_state: CitySettlementSimulationState,
	site_id: int,
	resource: String,
	excluding_reservation_id: int
) -> int:
	return maxi(
		_get_city_construction_site_remaining_resource_amount(
			city_state,
			site_id,
			resource
		)
		- _get_city_construction_site_destination_reserved_resource_amount(
			city_state,
			site_id,
			resource,
			excluding_reservation_id
		),
		0
	)

static func get_city_construction_site_unreserved_total_space(
	site_id: int,
	excluding_reservation_id: int = (
		CityCitizens.INVALID_CITY_CITIZEN_HAUL_RESERVATION_ID
	)
) -> int:
	return _get_city_construction_site_unreserved_total_space(
		null,
		site_id,
		excluding_reservation_id
	)


static func get_city_construction_site_unreserved_total_space_for_city_state(
	city_state: CitySettlementSimulationState,
	site_id: int,
	excluding_reservation_id: int = (
		CityCitizens.INVALID_CITY_CITIZEN_HAUL_RESERVATION_ID
	)
) -> int:
	return _get_city_construction_site_unreserved_total_space(
		city_state,
		site_id,
		excluding_reservation_id
	)


static func _get_city_construction_site_unreserved_total_space(
	city_state: CitySettlementSimulationState,
	site_id: int,
	excluding_reservation_id: int
) -> int:
	var total_space := 0

	for resource in CityResourceCatalog.get_city_resource_types():
		total_space += _get_city_construction_site_unreserved_resource_space(
			city_state,
			site_id,
			resource,
			excluding_reservation_id
		)

	return total_space

static func prepare_city_construction_task_assignment(
	assignment: Dictionary
) -> bool:
	return _prepare_city_construction_task_assignment(null, assignment)


static func prepare_city_construction_task_assignment_for_city_state(
	city_state: CitySettlementSimulationState,
	assignment: Dictionary
) -> bool:
	return _prepare_city_construction_task_assignment(city_state, assignment)


static func _prepare_city_construction_task_assignment(
	city_state: CitySettlementSimulationState,
	assignment: Dictionary
) -> bool:
	var target_object_id := int(assignment.get("target_object_id", -1))
	var task_source := str(assignment.get("task_source", ""))
	var task_values: Dictionary = assignment.get("task_values", {})
	var construction_site := _get_city_construction_site_by_id(
		city_state,
		target_object_id
	)
	var raw_target_tile = task_values.get(
		"target_tile",
		CityCitizens.INVALID_CITY_TILE_POSITION
	)

	if (
		task_source != CityCitizens.CITY_CITIZEN_TASK_SOURCE_PLAYER
		or bool(assignment.get("player_locked", false))
		or construction_site.is_empty()
		or str(construction_site.get("phase", ""))
		!= CITY_CONSTRUCTION_PHASE_LABOR
		or not raw_target_tile is Vector2i
		or not get_city_construction_site_work_positions(
			construction_site
		).has(raw_target_tile)
	):
		return false

	assignment["assigned_target_tile"] = raw_target_tile
	return true

static func can_place_city_object_construction(
	city_world: WorldData,
	top_left: Vector2i,
	size_tiles: Vector2i,
	object_type: String
) -> bool:
	if (
		not city_object_type_uses_construction(object_type)
		or size_tiles.x <= 0
		or size_tiles.y <= 0
	):
		return false
	var city_state = WorldPoliticalState.get_current_city_simulation_state()
	if (
		not city_state is CitySettlementSimulationState
		or not CityObjectSystem.can_use_city_object_definition_for_city_state(
			city_state,
			object_type
		)
	):
		return false

	return can_place_city_construction_footprint(
		city_world,
		CityObjectSystem.make_rectangle_city_object_footprint_tiles(
			top_left,
			size_tiles
		),
		true
	)

#region Construction Site Registry Operations

static func rebuild_city_construction_site_index() -> void:
	_rebuild_city_construction_site_index(null)


static func rebuild_city_construction_site_index_for_city_state(
	city_state: CitySettlementSimulationState
) -> void:
	_rebuild_city_construction_site_index(city_state)


static func _rebuild_city_construction_site_index(
	city_state: CitySettlementSimulationState
) -> void:
	var construction_state := _get_state(city_state)

	if construction_state == null:
		return

	construction_state.construction_site_index_by_id.clear()
	construction_state.construction_site_id_by_tile.clear()

	for site_index in range(construction_state.construction_sites.size()):
		var raw_site = construction_state.construction_sites[site_index]

		if not raw_site is Dictionary:
			continue

		var site: Dictionary = raw_site
		var site_id := int(site.get("id", -1))

		if site_id <= 0:
			continue

		construction_state.construction_site_index_by_id[site_id] = site_index

		for raw_tile in site.get("footprint_tiles", []):
			if raw_tile is Vector2i:
				construction_state.construction_site_id_by_tile[raw_tile] = site_id



static func get_city_construction_site_snapshot() -> Array:
	return get_current_state().construction_sites.duplicate(true)


static func get_city_construction_site_snapshot_for_city_state(
	city_state: CitySettlementSimulationState
) -> Array:
	var construction_state := get_state_for_city_state(city_state)
	return (
		construction_state.construction_sites.duplicate(true)
		if construction_state != null
		else []
	)


static func get_city_construction_site_at_tile(
	tile_position: Vector2i
) -> Dictionary:
	return _get_city_construction_site_at_tile(null, tile_position)


static func get_city_construction_site_at_tile_for_city_state(
	city_state: CitySettlementSimulationState,
	tile_position: Vector2i
) -> Dictionary:
	return _get_city_construction_site_at_tile(city_state, tile_position)


static func _get_city_construction_site_at_tile(
	city_state: CitySettlementSimulationState,
	tile_position: Vector2i
) -> Dictionary:
	var construction_state := _get_state(city_state)

	if (
		construction_state == null
		or not construction_state.construction_site_id_by_tile.has(tile_position)
	):
		return {}

	return _get_city_construction_site_by_id(
		city_state,
		int(construction_state.construction_site_id_by_tile[tile_position])
	)


static func create_city_construction_site(
	values: Dictionary
) -> Dictionary:
	var raw_footprint_tiles = values.get("footprint_tiles", [])

	if not raw_footprint_tiles is Array:
		return {}

	var footprint_tiles: Array[Vector2i] = []
	var footprint_lookup: Dictionary = {}

	for raw_tile in raw_footprint_tiles:
		if not raw_tile is Vector2i:
			continue

		var tile_position: Vector2i = raw_tile

		if footprint_lookup.has(tile_position):
			continue

		footprint_lookup[tile_position] = true
		footprint_tiles.append(tile_position)

	footprint_tiles.sort_custom(CityObjectSystem._sort_city_tiles_y_then_x)

	var target_kind := str(
		values.get(
			"target_kind",
			CITY_CONSTRUCTION_TARGET_NEW
		)
	)
	var target_object_id := int(
		values.get("target_object_id", -1)
	)
	var allowed_occupied_object_id := -1

	if target_kind == CITY_CONSTRUCTION_TARGET_MODIFICATION:
		var target_object := CityObjectSystem.get_city_object_by_id(
			target_object_id
		)

		if target_object.is_empty():
			return {}

		allowed_occupied_object_id = target_object_id
	elif target_kind != CITY_CONSTRUCTION_TARGET_NEW:
		return {}

	if not can_place_city_construction_footprint(
		WorldPoliticalState.get_current_city_world(),
		footprint_tiles,
		bool(values.get("require_external_access", false)),
		allowed_occupied_object_id
	):
		return {}

	var object_type := str(values.get("object_type", ""))

	if not city_object_type_uses_construction(object_type):
		return {}

	if (
		target_kind == CITY_CONSTRUCTION_TARGET_MODIFICATION
		and str(
			CityObjectSystem.get_city_object_by_id(target_object_id).get(
				"type",
				""
			)
		) != object_type
	):
		return {}

	var raw_recipe = values.get("material_recipe", {})

	if not raw_recipe is Dictionary:
		return {}

	var material_recipe: Dictionary = {}

	for resource in CityResourceCatalog.get_city_resource_types():
		var amount := maxi(int(raw_recipe.get(resource, 0)), 0)

		if amount > 0:
			material_recipe[resource] = amount

	var required_labor_minutes := maxi(
		int(values.get("required_labor_minutes", 0)),
		1
	)
	var work_positions: Array[Vector2i] = []
	var work_position_lookup: Dictionary = {}
	var raw_work_positions = values.get("work_positions", [])

	if raw_work_positions is Array:
		for raw_work_position in raw_work_positions:
			if not raw_work_position is Vector2i:
				continue

			var work_position: Vector2i = raw_work_position

			if work_position_lookup.has(work_position):
				continue

			work_position_lookup[work_position] = true
			work_positions.append(work_position)

	work_positions.sort_custom(CityObjectSystem._sort_city_tiles_y_then_x)

	if work_positions.is_empty():
		return {}

	var site_id := get_current_state().next_construction_site_id
	var site := {
		"id": site_id,
		"target_kind": target_kind,
		"target_object_id": target_object_id,
		"object_type": object_type,
		"shape_mode": str(
			values.get(
				"shape_mode",
				CityObjectCatalog.CITY_OBJECT_SHAPE_RECTANGLE
			)
		),
		"top_left": values.get(
			"top_left",
			CityCitizens.INVALID_CITY_TILE_POSITION
		),
		"size": values.get("size", Vector2i.ZERO),
		"tiles": footprint_tiles.duplicate(),
		"footprint_tiles": footprint_tiles.duplicate(),
		"owner": str(values.get("owner", "player")),
		"phase": CITY_CONSTRUCTION_PHASE_CLEARING,
		"material_recipe": material_recipe,
		"required_clearing_work_units": -1.0,
		"required_labor_minutes": required_labor_minutes,
		"completed_labor_minutes": 0,
		"finalization_state": CITY_CONSTRUCTION_FINALIZATION_STATE_NONE,
		"maximum_workers": maxi(
			int(values.get("maximum_workers", 1)),
			1
		),
		"work_positions": work_positions,
		"issued_world_minute": (
			SimulationClock.absolute_world_minutes
		),
	}

	get_current_state().next_construction_site_id += 1
	get_current_state().construction_sites.append(site)
	get_current_state().construction_site_index_by_id[site_id] = (
		get_current_state().construction_sites.size() - 1
	)

	for tile_position in footprint_tiles:
		get_current_state().construction_site_id_by_tile[tile_position] = site_id

	mark_city_construction_changed()
	return site.duplicate(true)

static func update_city_construction_site(
	site: Dictionary
) -> bool:
	return _update_city_construction_site(null, site)


static func update_city_construction_site_for_city_state(
	city_state: CitySettlementSimulationState,
	site: Dictionary
) -> bool:
	return _update_city_construction_site(city_state, site)


static func _update_city_construction_site(
	city_state: CitySettlementSimulationState,
	site: Dictionary
) -> bool:
	var construction_state := _get_state(city_state)
	var site_id := int(site.get("id", -1))
	var site_index := _get_city_construction_site_index_by_id(
		city_state,
		site_id
	)

	if construction_state == null or site_index < 0:
		return false

	var current_site: Dictionary = construction_state.construction_sites[site_index]
	var raw_updated_footprint = site.get("footprint_tiles", [])

	if not raw_updated_footprint is Array:
		return false

	var updated_footprint: Array[Vector2i] = []
	var updated_footprint_lookup: Dictionary = {}

	for raw_tile in raw_updated_footprint:
		if not raw_tile is Vector2i:
			return false

		var tile_position: Vector2i = raw_tile

		if updated_footprint_lookup.has(tile_position):
			continue

		updated_footprint_lookup[tile_position] = true
		updated_footprint.append(tile_position)

	updated_footprint.sort_custom(CityObjectSystem._sort_city_tiles_y_then_x)

	if updated_footprint.is_empty():
		return false

	var current_footprint: Array = current_site.get(
		"footprint_tiles",
		[]
	)
	var footprint_changed := current_footprint != updated_footprint

	if (
		footprint_changed
		and not _can_update_city_construction_site_footprint(
			city_state,
			site_id,
			site,
			updated_footprint
		)
	):
		return false

	site["footprint_tiles"] = updated_footprint.duplicate()
	site["tiles"] = updated_footprint.duplicate()

	if current_site == site:
		return true

	if footprint_changed:
		for raw_tile in current_footprint:
			if (
				raw_tile is Vector2i
				and int(
					construction_state.construction_site_id_by_tile.get(
						raw_tile,
						-1
					)
				) == site_id
			):
				construction_state.construction_site_id_by_tile.erase(raw_tile)

		for tile_position in updated_footprint:
			construction_state.construction_site_id_by_tile[tile_position] = site_id

	construction_state.construction_sites[site_index] = site.duplicate(true)
	if city_state == null:
		mark_city_construction_changed()
	else:
		mark_city_construction_changed_for_city_state(city_state)
	return true

static func _can_update_city_construction_site_footprint(
	city_state: CitySettlementSimulationState,
	site_id: int,
	site: Dictionary,
	updated_footprint: Array[Vector2i]
) -> bool:
	var construction_state := _get_state(city_state)
	var city_world := _get_city_world(city_state)
	var logistics_state: CityLogisticsState = (
		CityLogisticsSystem.get_current_state()
		if city_state == null
		else city_state.logistics_state
	)

	if construction_state == null or city_world == null or logistics_state == null:
		return false

	var target_kind := str(
		site.get(
			"target_kind",
			CITY_CONSTRUCTION_TARGET_NEW
		)
	)
	var target_object_id := int(
		site.get("target_object_id", -1)
	)

	if target_kind not in [
		CITY_CONSTRUCTION_TARGET_NEW,
		CITY_CONSTRUCTION_TARGET_MODIFICATION,
	]:
		return false

	for tile_position in updated_footprint:
		if not city_world.is_in_bounds(
			tile_position.x,
			tile_position.y
		):
			return false

		var other_site_id := int(
			construction_state.construction_site_id_by_tile.get(
				tile_position,
				-1
			)
		)

		if other_site_id > 0 and other_site_id != site_id:
			return false

		var occupied_object_id := (
			CityObjectSystem.get_city_object_id_at_tile(tile_position)
			if city_state == null
			else CityObjectSystem.get_city_object_id_at_tile_for_city_state(
				city_state,
				tile_position
			)
		)

		if occupied_object_id > 0:

			if (
				target_kind != CITY_CONSTRUCTION_TARGET_MODIFICATION
				or target_object_id <= 0
				or occupied_object_id != target_object_id
			):
				return false

		var tile: Dictionary = city_world.get_tile_for_internal_read(
			tile_position.x,
			tile_position.y
		)
		var terrain := str(tile.get("terrain", CityObjectCatalog.TERRAIN_WATER))

		if (
			terrain == CityObjectCatalog.TERRAIN_WATER
			or terrain == WorldData.TERRAIN_MOUNTAIN
			or not bool(tile.get("is_land", false))
		):
			return false

	for raw_ground_pile in logistics_state.ground_piles:
		if (
			raw_ground_pile is Dictionary
			and CityLogisticsSystem.get_city_ground_pile_construction_site_id(
				raw_ground_pile
			) == site_id
			and not updated_footprint.has(
				raw_ground_pile.get(
					"tile_position",
					CityCitizens.INVALID_CITY_TILE_POSITION
				)
			)
		):
			return false

	return true

static func remove_city_construction_site_record(
	site_id: int
) -> bool:
	return _remove_city_construction_site_record(null, site_id)


static func remove_city_construction_site_record_for_city_state(
	city_state: CitySettlementSimulationState,
	site_id: int
) -> bool:
	return _remove_city_construction_site_record(city_state, site_id)


static func _remove_city_construction_site_record(
	city_state: CitySettlementSimulationState,
	site_id: int
) -> bool:
	var construction_state := _get_state(city_state)
	var site_index := _get_city_construction_site_index_by_id(
		city_state,
		site_id
	)

	if construction_state == null or site_index < 0:
		return false

	var site: Dictionary = construction_state.construction_sites[site_index]

	# The site and its parent order are one logical record. Remove the order
	# in the same operation so completion and direct cancellation leave a
	# valid state even before the next work-board synchronization.
	if city_state == null:
		CityWorkSystem.remove_construction_work_order_for_site(site_id)
	else:
		CityWorkSystem.remove_construction_work_order_for_site_for_city_state(
			city_state,
			site_id
		)

	for raw_tile in site.get("footprint_tiles", []):
		if (
			raw_tile is Vector2i
			and int(
				construction_state.construction_site_id_by_tile.get(
					raw_tile,
					-1
				)
			) == site_id
		):
			construction_state.construction_site_id_by_tile.erase(raw_tile)

	construction_state.construction_sites.remove_at(site_index)
	_rebuild_city_construction_site_index(city_state)
	if city_state == null:
		mark_city_construction_changed()
	else:
		mark_city_construction_changed_for_city_state(city_state)
	return true




static func get_city_construction_site_access_tiles(
	city_world: WorldData,
	site: Dictionary,
	citizen_id: int = -1
) -> Array[Vector2i]:
	return _get_city_construction_site_access_tiles(
		null,
		city_world,
		site,
		citizen_id
	)


static func get_city_construction_site_access_tiles_for_city_state(
	city_state: CitySettlementSimulationState,
	city_world: WorldData,
	site: Dictionary,
	citizen_id: int = -1
) -> Array[Vector2i]:
	return _get_city_construction_site_access_tiles(
		city_state,
		city_world,
		site,
		citizen_id
	)


static func _get_city_construction_site_access_tiles(
	city_state: CitySettlementSimulationState,
	city_world: WorldData,
	site: Dictionary,
	citizen_id: int
) -> Array[Vector2i]:
	var access_tiles: Array[Vector2i] = []

	if city_world == null or site.is_empty():
		return access_tiles

	for raw_tile in site.get("footprint_tiles", []):
		if (
			raw_tile is Vector2i
			and (
				CityNavigationSystem.is_city_tile_walkable_for_citizen(
					city_world,
					raw_tile,
					citizen_id
				)
				if city_state == null
				else CityNavigationSystem.is_city_tile_walkable_for_citizen_for_city_state(
					city_state,
					city_world,
					raw_tile,
					citizen_id
				)
			)
		):
			access_tiles.append(raw_tile)

	access_tiles.sort_custom(CityObjectSystem._sort_city_tiles_y_then_x)
	return access_tiles








static func city_construction_site_has_all_materials(
	site_id: int
) -> bool:
	return _city_construction_site_has_all_materials(null, site_id)


static func city_construction_site_has_all_materials_for_city_state(
	city_state: CitySettlementSimulationState,
	site_id: int
) -> bool:
	return _city_construction_site_has_all_materials(city_state, site_id)


static func _city_construction_site_has_all_materials(
	city_state: CitySettlementSimulationState,
	site_id: int
) -> bool:
	var site := _get_city_construction_site_by_id(city_state, site_id)

	if site.is_empty():
		return false

	for resource in CityResourceCatalog.get_city_resource_types():
		if (
			_get_city_construction_site_remaining_resource_amount(
				city_state,
				site_id,
				resource
			) > 0
		):
			return false

	return true

static func _get_city_construction_material_deposit_tile(
	city_state: CitySettlementSimulationState,
	site: Dictionary
) -> Vector2i:
	for raw_tile in site.get("footprint_tiles", []):
		if (
			raw_tile is Vector2i
			and (
				CityLogisticsSystem.can_city_ground_pile_exist_at_tile(
					_get_city_world(city_state),
					raw_tile
				)
				if city_state == null
				else CityLogisticsSystem.can_city_ground_pile_exist_at_tile_for_city_state(
					city_state,
					city_state.city_world,
					raw_tile
				)
			)
		):
			return raw_tile

	return CityCitizens.INVALID_CITY_TILE_POSITION

static func add_resource_to_city_construction_site(
	site_id: int,
	resource: String,
	requested_amount: int
) -> int:
	return _add_resource_to_city_construction_site(
		null,
		site_id,
		resource,
		requested_amount
	)


static func add_resource_to_city_construction_site_for_city_state(
	city_state: CitySettlementSimulationState,
	site_id: int,
	resource: String,
	requested_amount: int
) -> int:
	return _add_resource_to_city_construction_site(
		city_state,
		site_id,
		resource,
		requested_amount
	)


static func _add_resource_to_city_construction_site(
	city_state: CitySettlementSimulationState,
	site_id: int,
	resource: String,
	requested_amount: int
) -> int:
	var site := _get_city_construction_site_by_id(city_state, site_id)

	if (
		site.is_empty()
		or requested_amount <= 0
		or str(site.get("phase", ""))
		!= CITY_CONSTRUCTION_PHASE_GATHERING
	):
		return 0

	var accepted_amount := mini(
		requested_amount,
		_get_city_construction_site_remaining_resource_amount(
			city_state,
			site_id,
			resource
		)
	)
	var deposit_tile := _get_city_construction_material_deposit_tile(
		city_state,
		site
	)

	if accepted_amount <= 0 or deposit_tile == CityCitizens.INVALID_CITY_TILE_POSITION:
		return 0

	var add_values := {
		"tile_position": deposit_tile,
		"resource": resource,
		"amount_delta": accepted_amount,
		"construction_site_id": site_id,
	}
	var add_result: Dictionary = (
		CityLogisticsSystem.add_resource_to_city_ground_piles_with_result(
			add_values
		)
		if city_state == null
		else CityLogisticsSystem.add_resource_to_city_ground_piles_with_result_for_city_state(
			city_state,
			add_values
		)
	)
	return int(add_result.get("added_amount", 0))

static func remove_resource_from_city_construction_site(
	site_id: int,
	resource: String,
	requested_amount: int
) -> int:
	return _remove_resource_from_city_construction_site(
		null,
		site_id,
		resource,
		requested_amount
	)


static func remove_resource_from_city_construction_site_for_city_state(
	city_state: CitySettlementSimulationState,
	site_id: int,
	resource: String,
	requested_amount: int
) -> int:
	return _remove_resource_from_city_construction_site(
		city_state,
		site_id,
		resource,
		requested_amount
	)


static func _remove_resource_from_city_construction_site(
	city_state: CitySettlementSimulationState,
	site_id: int,
	resource: String,
	requested_amount: int
) -> int:
	if requested_amount <= 0:
		return 0

	var remaining_amount := requested_amount
	var pile_ids: Array[int] = []
	var logistics_state: CityLogisticsState = (
		CityLogisticsSystem.get_current_state()
		if city_state == null
		else city_state.logistics_state
	)

	if logistics_state == null:
		return 0

	for raw_ground_pile in logistics_state.ground_piles:
		if not raw_ground_pile is Dictionary:
			continue

		var ground_pile: Dictionary = raw_ground_pile

		if (
			CityLogisticsSystem.get_city_ground_pile_construction_site_id(ground_pile)
			!= site_id
			or CityLogisticsSystem.get_city_ground_pile_resource_amount(
				ground_pile,
				resource
			) <= 0
		):
			continue

		pile_ids.append(int(ground_pile.get("id", -1)))

	pile_ids.sort()

	for pile_id in pile_ids:
		if remaining_amount <= 0:
			break

		var ground_pile: Dictionary = (
			CityLogisticsSystem.get_city_ground_pile_by_id(pile_id)
			if city_state == null
			else CityLogisticsSystem.get_city_ground_pile_by_id_for_city_state(
				city_state,
				pile_id
			)
		)
		var removal_amount := mini(
			remaining_amount,
			CityLogisticsSystem.get_city_ground_pile_resource_amount(
				ground_pile,
				resource
			)
		)
		var removed_amount: int = (
			CityLogisticsSystem.remove_resource_from_city_ground_pile(
				pile_id,
				resource,
				removal_amount
			)
			if city_state == null
			else CityLogisticsSystem.remove_resource_from_city_ground_pile_for_city_state(
				city_state,
				pile_id,
				resource,
				removal_amount
			)
		)
		remaining_amount -= removed_amount

	return requested_amount - remaining_amount

#endregion

#region Construction Site Creation

static func create_rectangular_site(values: Dictionary) -> Dictionary:
	var object_type := str(values.get("object_type", ""))
	var top_left: Vector2i = values.get(
		"top_left",
		CityCitizens.INVALID_CITY_TILE_POSITION
	)
	var size_tiles: Vector2i = values.get("size_tiles", Vector2i.ZERO)
	var object_owner := str(values.get("object_owner", "player"))
	var city_world: WorldData = values.get("city_world")
	var resolved_world := city_world

	if resolved_world == null:
		resolved_world = WorldPoliticalState.get_current_city_world()

	if not can_place_city_object_construction(
		resolved_world,
		top_left,
		size_tiles,
		object_type
	):
		return {}

	var definition := CityObjectCatalog.get_city_object_definition(object_type)
	var footprint_tiles := (
		CityObjectSystem.make_rectangle_city_object_footprint_tiles(
			top_left,
			size_tiles
		)
	)
	var work_positions := _build_external_work_positions(
		null,
		resolved_world,
		footprint_tiles
	)

	if work_positions.is_empty():
		return {}

	var site := create_city_construction_site({
		"target_kind": CITY_CONSTRUCTION_TARGET_NEW,
		"object_type": object_type,
		"shape_mode": CityObjectCatalog.CITY_OBJECT_SHAPE_RECTANGLE,
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
		site = get_city_construction_site_by_id(
			int(site.get("id", -1))
		)
		rebalance_uncommitted_construction_workers(
			int(site.get("id", -1))
		)

	return site


static func create_road_sites(
	raw_tile_positions: Array,
	object_owner: String = "player",
	city_world: WorldData = null
) -> Array[Dictionary]:
	var city_state = WorldPoliticalState.get_current_city_simulation_state()
	if (
		not city_state is CitySettlementSimulationState
		or not CityObjectSystem.can_use_city_object_definition_for_city_state(
			city_state,
			CityObjectCatalog.CITY_OBJECT_ROAD
		)
	):
		return []
	var resolved_world := city_world

	if resolved_world == null:
		resolved_world = WorldPoliticalState.get_current_city_world()

	if resolved_world == null:
		return []

	var clean_tiles: Array[Vector2i] = []
	var tile_lookup: Dictionary = {}

	for raw_tile in raw_tile_positions:
		if not raw_tile is Vector2i:
			continue

		var tile_position: Vector2i = raw_tile

		if (
			tile_lookup.has(tile_position)
			or not can_place_city_road_tile(
				resolved_world,
				tile_position
			)
		):
			continue

		tile_lookup[tile_position] = true
		clean_tiles.append(tile_position)

	clean_tiles.sort_custom(CityObjectSystem._sort_city_tiles_y_then_x)

	if clean_tiles.is_empty():
		return []

	var definition := CityObjectCatalog.get_city_object_definition(
		CityObjectCatalog.CITY_OBJECT_ROAD
	)
	var created_sites: Array[Dictionary] = []
	var created_site_ids: Array[int] = []

	# The drag rectangle is only an input gesture. Once confirmed, every tile
	# becomes a fully independent construction site with its own claim,
	# progress, cancellation state, and eventual completed road object.
	for tile_position in clean_tiles:
		var site := create_city_construction_site({
			"target_kind": CITY_CONSTRUCTION_TARGET_NEW,
			"object_type": CityObjectCatalog.CITY_OBJECT_ROAD,
			"shape_mode": CityObjectCatalog.CITY_OBJECT_SHAPE_TILE_AREA,
			"top_left": tile_position,
			"size": Vector2i.ONE,
			"footprint_tiles": [tile_position],
			"owner": object_owner,
			"material_recipe": _get_scaled_material_recipe(
				definition,
				1
			),
			"required_labor_minutes": _get_scaled_labor_minutes(
				definition,
				1
			),
			"maximum_workers": int(
				definition.get("construction_max_workers", 1)
			),
			"work_positions": [tile_position],
		})

		if site.is_empty():
			continue

		var site_id := int(site.get("id", -1))
		refresh_city_construction_site(site_id)
		site = get_city_construction_site_by_id(site_id)

		if site.is_empty():
			continue

		created_sites.append(site)
		created_site_ids.append(site_id)

	if created_sites.is_empty():
		return []

	# Publish this batch's work orders in one focused pass, then compare existing
	# uncommitted builders against the complete set of newly painted road tiles.
	# Unrelated orders are not refreshed on the placement frame, and road routing
	# remains batched rather than running A* per tile.
	CityWorkSystem.synchronize_construction_work_orders(created_site_ids)
	rebalance_uncommitted_construction_workers_for_sites(created_site_ids)

	var refreshed_sites: Array[Dictionary] = []

	for site_id in created_site_ids:
		var refreshed_site := (
			get_city_construction_site_by_id(site_id)
		)

		if not refreshed_site.is_empty():
			refreshed_sites.append(refreshed_site)

	return refreshed_sites


# Compatibility wrapper for callers that intentionally create one road tile.
# Multi-tile placement must use create_road_sites() so no caller accidentally
# recreates a shared, stroke-sized road construction object.
static func create_road_site(
	raw_tile_positions: Array,
	object_owner: String = "player",
	city_world: WorldData = null
) -> Dictionary:
	var clean_tile_count := 0

	for raw_tile in raw_tile_positions:
		if raw_tile is Vector2i:
			clean_tile_count += 1

	if clean_tile_count != 1:
		return {}

	var created_sites := create_road_sites(
		raw_tile_positions,
		object_owner,
		city_world
	)

	if created_sites.size() != 1:
		return {}

	return created_sites[0]


#endregion

#region Construction Recipe and Footprint Helpers

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

	for resource in CityResourceCatalog.get_city_resource_types():
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
	city_state: CitySettlementSimulationState,
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

		for offset in CityNavigationSystem.CITY_CARDINAL_TILE_OFFSETS:
			var candidate_tile: Vector2i = (
				footprint_tile + Vector2i(offset)
			)

			if (
				footprint_lookup.has(candidate_tile)
				or position_lookup.has(candidate_tile)
				or not (
					CityNavigationSystem.is_city_tile_walkable_for_citizen(
						city_world,
						candidate_tile
					)
					if city_state == null
					else CityNavigationSystem.is_city_tile_walkable_for_citizen_for_city_state(
						city_state,
						city_world,
						candidate_tile
					)
				)
			):
				continue

			position_lookup[candidate_tile] = true
			positions.append(candidate_tile)

	positions.sort_custom(CityObjectSystem._sort_city_tiles_y_then_x)
	return positions


#endregion

#region Construction Site Refresh and Progress

static func refresh_all_city_construction_sites() -> void:
	_refresh_all_city_construction_sites(null)


static func refresh_all_city_construction_sites_for_city_state(
	city_state: CitySettlementSimulationState
) -> void:
	_refresh_all_city_construction_sites(city_state)


static func _refresh_all_city_construction_sites(
	city_state: CitySettlementSimulationState
) -> void:
	var site_ids: Array[int] = []
	var site_snapshot: Array = (
		get_city_construction_site_snapshot()
		if city_state == null
		else get_city_construction_site_snapshot_for_city_state(city_state)
	)

	for raw_site in site_snapshot:
		if raw_site is Dictionary:
			site_ids.append(int(raw_site.get("id", -1)))

	site_ids.sort()

	for site_id in site_ids:
		_refresh_city_construction_site(city_state, site_id)


static func refresh_city_construction_site(
	site_id: int
) -> bool:
	return _refresh_city_construction_site(null, site_id)


static func refresh_city_construction_site_for_city_state(
	city_state: CitySettlementSimulationState,
	site_id: int
) -> bool:
	return _refresh_city_construction_site(city_state, site_id)


static func _refresh_city_construction_site(
	city_state: CitySettlementSimulationState,
	site_id: int
) -> bool:
	var site := _get_city_construction_site_by_id(city_state, site_id)
	if site.is_empty():
		return false

	if (
		str(site.get("finalization_state", CITY_CONSTRUCTION_FINALIZATION_STATE_NONE))
		== CITY_CONSTRUCTION_FINALIZATION_STATE_AWAITING_CLEARANCE
	):
		_advance_city_construction_finalization(city_state, site_id)
		return true

	_reserve_needed_footprint_materials(city_state, site_id)
	_ensure_progress_baseline(city_state, site_id)
	_ensure_clearing_commands(city_state, site_id)
	site = _get_city_construction_site_by_id(city_state, site_id)

	if site.is_empty():
		return false

	var next_phase: String = (
		CITY_CONSTRUCTION_PHASE_CLEARING
	)

	if (
		not _site_has_surface_obstruction(city_state, site)
		and not _site_has_ordinary_ground_pile(city_state, site)
	):
		if _city_construction_site_has_all_materials(city_state, site_id):
			next_phase = CITY_CONSTRUCTION_PHASE_LABOR
		else:
			next_phase = CITY_CONSTRUCTION_PHASE_GATHERING

	if str(site.get("phase", "")) != next_phase:
		site["phase"] = next_phase
		return _update_city_construction_site(city_state, site)

	return true


static func get_city_construction_site_progress_summary(
	site_id: int
) -> Dictionary:
	var site := get_city_construction_site_by_id(site_id)
	if site.is_empty():
		return {}

	var remaining_clearing_work_units := (
		_get_remaining_clearing_work_units(null, site)
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
		for resource in CityResourceCatalog.get_city_resource_types():
			var required_amount := maxi(
				int(material_recipe.get(resource, 0)),
				0
			)

			if required_amount <= 0:
				continue

			required_material_work_units += float(required_amount)
			completed_material_work_units += float(
				mini(
					get_city_construction_site_reserved_resource_amount(
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


static func _ensure_progress_baseline(
	city_state: CitySettlementSimulationState,
	site_id: int
) -> void:
	var site := _get_city_construction_site_by_id(city_state, site_id)
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
		_get_remaining_clearing_work_units(city_state, site)
	)
	_update_city_construction_site(city_state, site)


static func _get_remaining_clearing_work_units(
	city_state: CitySettlementSimulationState,
	site: Dictionary
) -> float:
	var city_world: WorldData = _get_city_world(city_state)

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
		var tile := city_world.get_tile_for_internal_read(
			tile_position.x,
			tile_position.y
		)
		var surface_feature := WorldData.get_city_surface_feature(tile)

		if not WorldData.is_city_surface_feature(surface_feature):
			continue

		remaining_work_units += (
			float(CityWorkSystem.CITY_PLAYER_COMMAND_WORK_DURATION_MINUTES)
			/ safe_base_minutes
		)

		var resource := (
			WorldData.get_city_surface_feature_resource_type(
				surface_feature
			)
		)

		if not CityResourceCatalog.is_city_resource_type(resource):
			continue

		pending_yield_by_resource[resource] = (
			int(pending_yield_by_resource.get(resource, 0))
			+ CityWorkSystem.CITY_PLAYER_COMMAND_RESOURCE_YIELD
		)

	var ground_pile_snapshot: Array = (
		CityLogisticsSystem.get_city_ground_pile_snapshot()
		if city_state == null
		else CityLogisticsSystem.get_city_ground_pile_snapshot_for_city_state(
			city_state
		)
	)

	for raw_ground_pile in ground_pile_snapshot:
		if not raw_ground_pile is Dictionary:
			continue

		var ground_pile: Dictionary = raw_ground_pile

		if not footprint_tiles.has(
			ground_pile.get(
				"tile_position",
				CityCitizens.INVALID_CITY_TILE_POSITION
			)
		):
			continue

		if (
			CityLogisticsSystem.get_city_ground_pile_construction_site_id(
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
			_get_city_construction_site_remaining_resource_amount(
				city_state,
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


#endregion

#region Clearing and Material Reservation

static func _reserve_needed_footprint_materials(
	city_state: CitySettlementSimulationState,
	site_id: int
) -> void:
	var site := _get_city_construction_site_by_id(city_state, site_id)
	if site.is_empty():
		return

	var footprint_tiles: Array = site.get("footprint_tiles", [])
	var ground_piles: Array = (
		CityLogisticsSystem.get_city_ground_pile_snapshot()
		if city_state == null
		else CityLogisticsSystem.get_city_ground_pile_snapshot_for_city_state(
			city_state
		)
	)

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
			CityCitizens.INVALID_CITY_TILE_POSITION
		)

		if (
			not raw_tile_position is Vector2i
			or not footprint_tiles.has(raw_tile_position)
			or CityLogisticsSystem.city_ground_pile_is_construction_reserved(
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
			_get_city_construction_site_unreserved_resource_space(
				city_state,
				site_id,
				resource,
				CityCitizens.INVALID_CITY_CITIZEN_HAUL_RESERVATION_ID
			)
		)

		if needed_amount <= 0:
			continue

		if city_state == null:
			CityLogisticsSystem.reserve_city_ground_pile_for_construction(
				int(ground_pile.get("id", -1)),
				site_id,
				needed_amount
			)
		else:
			CityLogisticsSystem.reserve_city_ground_pile_for_construction_for_city_state(
				city_state,
				int(ground_pile.get("id", -1)),
				site_id,
				needed_amount
			)


static func _ensure_clearing_commands(
	city_state: CitySettlementSimulationState,
	site_id: int
) -> void:
	var site := _get_city_construction_site_by_id(city_state, site_id)
	var city_world: WorldData = _get_city_world(city_state)

	if site.is_empty() or city_world == null:
		return

	for raw_tile_position in site.get("footprint_tiles", []):
		if not raw_tile_position is Vector2i:
			continue

		var tile_position: Vector2i = raw_tile_position
		var tile := city_world.get_tile_for_internal_read(
			tile_position.x,
			tile_position.y
		)
		var surface_feature := WorldData.get_city_surface_feature(tile)
		var command_type: String = (
			CityWorkSystem.CITY_PLAYER_COMMAND_TYPE_NONE
		)

		match surface_feature:
			WorldData.CITY_SURFACE_FEATURE_TREE:
				command_type = (
					CityWorkSystem.CITY_PLAYER_COMMAND_TYPE_CHOP_TREE
				)

			WorldData.CITY_SURFACE_FEATURE_ROCK:
				command_type = (
					CityWorkSystem.CITY_PLAYER_COMMAND_TYPE_COLLECT_ROCK
				)

		if command_type == CityWorkSystem.CITY_PLAYER_COMMAND_TYPE_NONE:
			continue

		if city_state == null:
			CityWorkSystem.ensure_city_construction_clearing_command(
				site_id,
				command_type,
				tile_position
			)
		else:
			CityWorkSystem.ensure_city_construction_clearing_command_for_city_state(
				city_state,
				site_id,
				command_type,
				tile_position
			)


static func _site_has_surface_obstruction(
	city_state: CitySettlementSimulationState,
	site: Dictionary
) -> bool:
	var city_world: WorldData = _get_city_world(city_state)

	if city_world == null:
		return true

	for raw_tile_position in site.get("footprint_tiles", []):
		if not raw_tile_position is Vector2i:
			continue

		var tile_position: Vector2i = raw_tile_position
		var tile := city_world.get_tile_for_internal_read(
			tile_position.x,
			tile_position.y
		)

		if WorldData.is_city_surface_feature(
			WorldData.get_city_surface_feature(tile)
		):
			return true

	return false


static func _site_has_ordinary_ground_pile(
	city_state: CitySettlementSimulationState,
	site: Dictionary
) -> bool:
	var site_id := int(site.get("id", -1))
	var footprint_tiles: Array = site.get("footprint_tiles", [])
	var logistics_state: CityLogisticsState = (
		CityLogisticsSystem.get_current_state()
		if city_state == null
		else city_state.logistics_state
	)

	if logistics_state == null:
		return false

	for raw_ground_pile in logistics_state.ground_piles:
		if not raw_ground_pile is Dictionary:
			continue

		var ground_pile: Dictionary = raw_ground_pile

		if not footprint_tiles.has(
			ground_pile.get(
				"tile_position",
				CityCitizens.INVALID_CITY_TILE_POSITION
			)
		):
			continue

		if (
			CityLogisticsSystem.get_city_ground_pile_construction_site_id(
				ground_pile
			) != site_id
		):
			return true

	return false


#endregion

#region Construction Work Candidate Selection

static func get_best_assignable_player_work_for_citizen(
	citizen_id: int
) -> Dictionary:
	var citizen := CityCitizenRegistrySystem.get_city_citizen_by_id(citizen_id)

	if (
		citizen.is_empty()
		or not bool(citizen.get("alive", false))
		or int(citizen.get("job_object_id", -1)) > 0
	):
		return {}

	var best_candidate: Dictionary = {}

	for raw_site in get_city_construction_site_snapshot():
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
	return _get_best_assignable_player_work_for_citizen_and_site(
		null,
		citizen_id,
		site_id
	)


static func get_best_assignable_player_work_for_citizen_and_site_for_city_state(
	city_state: CitySettlementSimulationState,
	citizen_id: int,
	site_id: int
) -> Dictionary:
	return _get_best_assignable_player_work_for_citizen_and_site(
		city_state,
		citizen_id,
		site_id
	)


static func _get_best_assignable_player_work_for_citizen_and_site(
	city_state: CitySettlementSimulationState,
	citizen_id: int,
	site_id: int
) -> Dictionary:
	var citizen: Dictionary = (
		CityCitizenRegistrySystem.get_city_citizen_by_id(citizen_id)
		if city_state == null
		else CityCitizenRegistrySystem.get_city_citizen_by_id_for_city_state(
			city_state,
			citizen_id
		)
	)
	var site := _get_city_construction_site_by_id(city_state, site_id)
	if (
		citizen.is_empty()
		or not bool(citizen.get("alive", false))
		or int(citizen.get("job_object_id", -1)) > 0
		or site.is_empty()
		or str(
			site.get("finalization_state", CITY_CONSTRUCTION_FINALIZATION_STATE_NONE)
		) != CITY_CONSTRUCTION_FINALIZATION_STATE_NONE
	):
		return {}

	match str(site.get("phase", "")):
		CITY_CONSTRUCTION_PHASE_CLEARING:
			return _get_best_clearing_cleanup_candidate(city_state, citizen, site)

		CITY_CONSTRUCTION_PHASE_GATHERING:
			return _get_best_delivery_candidate(city_state, citizen, site)

		CITY_CONSTRUCTION_PHASE_LABOR:
			return _get_labor_candidate(city_state, citizen, site)

	return {}


# Production roads have no material-delivery phase, which lets every active
# road tile share one exact route search while retaining independent site IDs,
# claims, progress, and completion. Synthetic/materialized road fixtures fall
# back to ordinary per-site selection.
static func get_best_assignable_batchable_road_work_for_citizen(
	citizen_id: int,
	raw_site_ids: Array
) -> Dictionary:
	return _get_best_assignable_batchable_road_work_for_citizen(
		null,
		citizen_id,
		raw_site_ids
	)


static func get_best_assignable_batchable_road_work_for_citizen_for_city_state(
	city_state: CitySettlementSimulationState,
	citizen_id: int,
	raw_site_ids: Array
) -> Dictionary:
	return _get_best_assignable_batchable_road_work_for_citizen(
		city_state,
		citizen_id,
		raw_site_ids
	)


static func _get_best_assignable_batchable_road_work_for_citizen(
	city_state: CitySettlementSimulationState,
	citizen_id: int,
	raw_site_ids: Array
) -> Dictionary:
	var citizen: Dictionary = (
		CityCitizenRegistrySystem.get_city_citizen_by_id(citizen_id)
		if city_state == null
		else CityCitizenRegistrySystem.get_city_citizen_by_id_for_city_state(
			city_state,
			citizen_id
		)
	)

	if (
		citizen.is_empty()
		or not bool(citizen.get("alive", false))
		or int(citizen.get("job_object_id", -1)) > 0
	):
		return {}

	var raw_current_tile = citizen.get(
		"city_tile_position",
		CityCitizens.INVALID_CITY_TILE_POSITION
	)

	if not raw_current_tile is Vector2i:
		return {}

	var site_id_lookup: Dictionary = {}

	for raw_site_id in raw_site_ids:
		var site_id := int(raw_site_id)

		if site_id > 0:
			site_id_lookup[site_id] = true

	var site_ids: Array = site_id_lookup.keys()
	site_ids.sort()
	var best_candidate: Dictionary = {}
	var labor_site_id_by_position: Dictionary = {}
	var labor_positions: Array[Vector2i] = []

	for raw_site_id in site_ids:
		var site_id := int(raw_site_id)
		var site := _get_city_construction_site_by_id(city_state, site_id)
		var raw_recipe = site.get("material_recipe", {})

		if (
			site.is_empty()
			or str(site.get("object_type", ""))
			!= CityObjectCatalog.CITY_OBJECT_ROAD
			or not raw_recipe is Dictionary
			or not raw_recipe.is_empty()
		):
			continue

		match str(site.get("phase", "")):
			CITY_CONSTRUCTION_PHASE_CLEARING:
				var cleanup_candidate := (
					_get_best_clearing_cleanup_candidate(
						city_state,
						citizen,
						site
					)
				)

				if _candidate_is_better(
					cleanup_candidate,
					best_candidate
				):
					best_candidate = cleanup_candidate

			CITY_CONSTRUCTION_PHASE_LABOR:
				if _get_active_laborer_count(city_state, site_id) >= maxi(
					int(site.get("maximum_workers", 1)),
					1
				):
					continue

				var claimed_positions := (
					_get_claimed_labor_positions(city_state, site_id)
				)

				for position in (
					get_city_construction_site_work_positions(
						site
					)
				):
					if (
						claimed_positions.has(position)
						or not (
							CityNavigationSystem.is_city_tile_walkable_for_citizen(
								WorldPoliticalState.get_current_city_world(),
								position,
								citizen_id
							)
							if city_state == null
							else CityNavigationSystem.is_city_tile_walkable_for_citizen_for_city_state(
								city_state,
								city_state.city_world,
								position,
								citizen_id
							)
						)
					):
						continue

					if not labor_site_id_by_position.has(position):
						labor_site_id_by_position[position] = site_id
						labor_positions.append(position)

	if labor_positions.is_empty():
		return best_candidate

	labor_positions.sort_custom(CityObjectSystem._sort_city_tiles_y_then_x)
	var city_world := _get_city_world(city_state)
	var path_values := {
		"city_world": city_world,
		"start_tile": raw_current_tile,
		"destination_tiles": labor_positions,
		"max_expanded_nodes": CityNavigationSystemScript.get_city_wide_path_expansion_limit(
			city_world
		),
		"citizen_id": citizen_id,
		"heuristic_weight": EXACT_PATH_HEURISTIC_WEIGHT,
	}
	var path_result: Dictionary = (
		CityNavigationSystemScript.find_path_to_any_city_tile(path_values)
		if city_state == null
		else CityNavigationSystemScript.find_path_to_any_city_tile_for_city_state(
			city_state,
			path_values
		)
	)

	if not bool(path_result.get("success", false)):
		return best_candidate

	var raw_target_tile = path_result.get(
		"destination_tile",
		CityCitizens.INVALID_CITY_TILE_POSITION
	)

	if (
		not raw_target_tile is Vector2i
		or not labor_site_id_by_position.has(raw_target_tile)
	):
		return best_candidate

	var target_tile: Vector2i = raw_target_tile
	var selected_site_id := int(
		labor_site_id_by_position.get(target_tile, -1)
	)
	var selected_site := _get_city_construction_site_by_id(
		city_state,
		selected_site_id
	)
	var path_cost := maxi(int(path_result.get("path_cost", 0)), 0)
	var labor_candidate := {
		"player_work_kind": PLAYER_WORK_KIND_LABOR,
		"construction_site_id": selected_site_id,
		"issued_world_minute": int(
			selected_site.get("issued_world_minute", 0)
		),
		"estimated_path_cost": path_cost,
		"selection_score": (
			path_cost - _get_fairness_bonus(selected_site)
		),
		"target_tile": target_tile,
		"assignment_path": path_result.get("path", []).duplicate(),
		"tie_break_key": str(target_tile),
	}

	if _candidate_is_better(labor_candidate, best_candidate):
		best_candidate = labor_candidate

	return best_candidate


static func _get_best_clearing_cleanup_candidate(
	city_state: CitySettlementSimulationState,
	citizen: Dictionary,
	site: Dictionary
) -> Dictionary:
	var citizen_id := int(citizen.get("id", -1))

	# Candidate selection happens before the player-work interruption gateway.
	# Let an existing physical load finish or spill through its current owner
	# before planning a footprint-cleanup pickup around it.
	if (
		citizen_id <= 0
		or (
			CityCitizenInventorySystem.get_city_citizen_haul_cargo_amount(citizen_id)
			if city_state == null
			else CityCitizenInventorySystem.get_city_citizen_haul_cargo_amount_for_city_state(
				city_state,
				citizen_id
			)
		) > 0
	):
		return {}

	var site_id := int(site.get("id", -1))
	var footprint_tiles: Array = site.get("footprint_tiles", [])
	var site_endpoint := (
		CityLogisticsSystem.make_city_construction_site_haul_endpoint(site_id)
	)
	var raw_citizen_tile = citizen.get(
		"city_tile_position",
		CityCitizens.INVALID_CITY_TILE_POSITION
	)
	var best_candidate: Dictionary = {}

	if site_id <= 0 or not raw_citizen_tile is Vector2i:
		return best_candidate

	var ground_pile_snapshot: Array = (
		CityLogisticsSystem.get_city_ground_pile_snapshot()
		if city_state == null
		else CityLogisticsSystem.get_city_ground_pile_snapshot_for_city_state(
			city_state
		)
	)

	for raw_ground_pile in ground_pile_snapshot:
		if not raw_ground_pile is Dictionary:
			continue

		var ground_pile: Dictionary = raw_ground_pile
		var raw_pile_tile = ground_pile.get(
			"tile_position",
			CityCitizens.INVALID_CITY_TILE_POSITION
		)

		if (
			not raw_pile_tile is Vector2i
			or not footprint_tiles.has(raw_pile_tile)
			or CityLogisticsSystem.city_ground_pile_is_construction_reserved(
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
		var source := CityLogisticsSystem.make_city_ground_pile_haul_endpoint(
			ground_pile_id
		)
		var requested_amount: int = (
			CityLogisticsSystem.get_city_haul_endpoint_unreserved_resource_amount(
				source,
				resource
			)
			if city_state == null
			else CityLogisticsSystem.get_city_haul_endpoint_unreserved_resource_amount_for_city_state(
				city_state,
				source,
				resource
			)
		)

		if requested_amount <= 0:
			continue

		var task_values := {
				"city_world": _get_city_world(city_state),
				"citizen": citizen,
				"source": source,
				"requester": site_endpoint,
				"resource_type": resource,
				"requested_amount": requested_amount,
				"reason": (
					CityCitizens.CITY_CITIZEN_HAUL_REASON_GROUND_PILE_CLEANUP
				),
				"source_access_purpose": (
					CityObjectCatalog.CONTAINER_HAUL_PURPOSE_GROUND_PILE_CLEANUP
				),
				"destination_access_purpose": (
					CityObjectCatalog.CONTAINER_HAUL_PURPOSE_PUBLIC_STORAGE
				),
				"task_source": (
					CityCitizens.CITY_CITIZEN_TASK_SOURCE_PLAYER
				),
				"task_priority": (
					CITY_CONSTRUCTION_TASK_PRIORITY
				),
			}
		var task_request: Dictionary = (
			CitizenHaulingSystemScript.make_public_storage_haul_task_request(
				task_values
			)
			if city_state == null
			else CitizenHaulingSystemScript.make_public_storage_haul_task_request_for_city_state(
				city_state,
				task_values
			)
		)

		if task_request.is_empty():
			task_request = _make_ground_relocation_task_request(city_state, {
				"citizen": citizen,
				"site": site,
				"source": source,
				"resource": resource,
				"requested_amount": requested_amount,
				"source_tile": raw_pile_tile,
			})

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
			CityCitizens.INVALID_CITY_TILE_POSITION
		)
		var raw_destination_tile = haul.get(
			"destination_tile",
			CityCitizens.INVALID_CITY_TILE_POSITION
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
			"assignment_path": task_request.get(
				"selection_path",
				[]
			).duplicate(),
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


#endregion

#region Ground Pile Relocation

static func can_relocate_ground_pile_outside_site(
	site_id: int,
	ground_pile_id: int
) -> bool:
	return _can_relocate_ground_pile_outside_site(
		null,
		site_id,
		ground_pile_id
	)


static func can_relocate_ground_pile_outside_site_for_city_state(
	city_state: CitySettlementSimulationState,
	site_id: int,
	ground_pile_id: int
) -> bool:
	return _can_relocate_ground_pile_outside_site(
		city_state,
		site_id,
		ground_pile_id
	)


static func _can_relocate_ground_pile_outside_site(
	city_state: CitySettlementSimulationState,
	site_id: int,
	ground_pile_id: int
) -> bool:
	var site := _get_city_construction_site_by_id(city_state, site_id)
	var pile: Dictionary = (
		CityLogisticsSystem.get_city_ground_pile_by_id(ground_pile_id)
		if city_state == null
		else CityLogisticsSystem.get_city_ground_pile_by_id_for_city_state(
			city_state,
			ground_pile_id
		)
	)
	var raw_source_tile = pile.get(
		"tile_position",
		CityCitizens.INVALID_CITY_TILE_POSITION
	)

	if (
		site.is_empty()
		or not raw_source_tile is Vector2i
		or not site.get("footprint_tiles", []).has(raw_source_tile)
		or CityLogisticsSystem.city_ground_pile_is_construction_reserved(pile)
	):
		return false

	return (
		_find_nearest_ground_relocation_tile(
			city_state,
			site,
			raw_source_tile,
			-1
		)
		!= CityCitizens.INVALID_CITY_TILE_POSITION
	)


static func _make_ground_relocation_task_request(
	city_state: CitySettlementSimulationState,
	values: Dictionary
) -> Dictionary:
	var citizen: Dictionary = values.get("citizen", {})
	var site: Dictionary = values.get("site", {})
	var source: Dictionary = values.get("source", {})
	var resource := str(values.get("resource", WorldData.RESOURCE_NONE))
	var requested_amount := maxi(
		int(values.get("requested_amount", 0)),
		0
	)
	var source_tile: Vector2i = values.get(
		"source_tile",
		CityCitizens.INVALID_CITY_TILE_POSITION
	)
	var citizen_id := int(citizen.get("id", -1))
	var destination_tile := _find_nearest_ground_relocation_tile(
		city_state,
		site,
		source_tile,
		citizen_id
	)

	if destination_tile == CityCitizens.INVALID_CITY_TILE_POSITION:
		return {}

	var excluded_pile_ids: Array[int] = []
	var footprint_tiles: Array = site.get("footprint_tiles", [])

	var ground_pile_snapshot: Array = (
		CityLogisticsSystem.get_city_ground_pile_snapshot()
		if city_state == null
		else CityLogisticsSystem.get_city_ground_pile_snapshot_for_city_state(
			city_state
		)
	)

	for raw_pile in ground_pile_snapshot:
		if (
			raw_pile is Dictionary
			and footprint_tiles.has(
				raw_pile.get(
					"tile_position",
					CityCitizens.INVALID_CITY_TILE_POSITION
				)
			)
			and not CityLogisticsSystem.city_ground_pile_is_construction_reserved(
				raw_pile
			)
		):
			excluded_pile_ids.append(int(raw_pile.get("id", -1)))

	excluded_pile_ids.sort()
	var destination: Dictionary

	if city_state == null:
		destination = CityLogisticsSystem.make_city_ground_tile_haul_endpoint(
			destination_tile,
			excluded_pile_ids
		)
	else:
		destination = CityCitizens.make_city_citizen_haul_endpoint({
			"kind": CityCitizens.CITY_CITIZEN_HAUL_ENDPOINT_KIND_GROUND_TILE,
			"id": -1,
			"tile_position": destination_tile,
			"excluded_ground_pile_ids": excluded_pile_ids,
		})
	var site_endpoint := CityLogisticsSystem.make_city_construction_site_haul_endpoint(
		int(site.get("id", -1))
	)

	var task_values := {
		"city_world": _get_city_world(city_state),
		"citizen": citizen,
		"source": source,
		"destination": destination,
		"requester": site_endpoint,
		"resource_type": resource,
		"requested_amount": requested_amount,
		"reason": (
			CityCitizens.CITY_CITIZEN_HAUL_REASON_GROUND_PILE_CLEANUP
		),
		"source_access_purpose": (
			CityObjectCatalog.CONTAINER_HAUL_PURPOSE_GROUND_PILE_CLEANUP
		),
		"destination_access_purpose": (
			CityObjectCatalog.CONTAINER_HAUL_PURPOSE_GROUND_PILE_CLEANUP
		),
		"task_source": CityCitizens.CITY_CITIZEN_TASK_SOURCE_PLAYER,
		"task_priority": CITY_CONSTRUCTION_TASK_PRIORITY,
	}
	return (
		CitizenHaulingSystemScript.make_directed_haul_task_request(task_values)
		if city_state == null
		else CitizenHaulingSystemScript.make_directed_haul_task_request_for_city_state(
			city_state,
			task_values
		)
	)


static func _find_nearest_ground_relocation_tile(
	city_state: CitySettlementSimulationState,
	site: Dictionary,
	source_tile: Vector2i,
	citizen_id: int
) -> Vector2i:
	var city_world: WorldData = _get_city_world(city_state)

	if city_world == null:
		return CityCitizens.INVALID_CITY_TILE_POSITION

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
					or not _get_city_construction_site_at_tile(
						city_state,
						candidate_tile
					).is_empty()
					or not (
						CityLogisticsSystem.can_city_ground_pile_exist_at_tile(
							city_world,
							candidate_tile
						)
						if city_state == null
						else CityLogisticsSystem.can_city_ground_pile_exist_at_tile_for_city_state(
							city_state,
							city_world,
							candidate_tile
						)
					)
				):
					continue

				candidate_tiles.append(candidate_tile)

		candidate_tiles.sort_custom(CityObjectSystem._sort_city_tiles_y_then_x)

		if candidate_tiles.is_empty():
			continue

		if citizen_id <= 0:
			return candidate_tiles[0]

		var path_values := {
				"city_world": city_world,
				"start_tile": source_tile,
				"destination_tiles": candidate_tiles,
				"max_expanded_nodes": CityNavigationSystemScript.get_city_wide_path_expansion_limit(city_world),
				"citizen_id": citizen_id,
				"heuristic_weight": EXACT_PATH_HEURISTIC_WEIGHT,
			}
		var path_result: Dictionary = (
			CityNavigationSystemScript.find_path_to_any_city_tile(path_values)
			if city_state == null
			else CityNavigationSystemScript.find_path_to_any_city_tile_for_city_state(
				city_state,
				path_values
			)
		)

		if not bool(path_result.get("success", false)):
			continue

		var raw_destination_tile = path_result.get(
			"destination_tile",
			CityCitizens.INVALID_CITY_TILE_POSITION
		)

		if raw_destination_tile is Vector2i:
			return raw_destination_tile

	return CityCitizens.INVALID_CITY_TILE_POSITION


static func _get_octile_path_cost(
	from_tile: Vector2i,
	to_tile: Vector2i
) -> int:
	var distance_x := absi(to_tile.x - from_tile.x)
	var distance_y := absi(to_tile.y - from_tile.y)
	var diagonal_steps := mini(distance_x, distance_y)
	var straight_steps := maxi(distance_x, distance_y) - diagonal_steps
	return diagonal_steps * 14_142 + straight_steps * 10_000


#endregion

#region Delivery and Labor Candidate Scoring

static func _get_best_delivery_candidate(
	city_state: CitySettlementSimulationState,
	citizen: Dictionary,
	site: Dictionary
) -> Dictionary:
	var site_id := int(site.get("id", -1))
	var destination := (
		CityLogisticsSystem.make_city_construction_site_haul_endpoint(site_id)
	)
	var best_candidate: Dictionary = {}

	for resource in CityResourceCatalog.get_city_resource_types():
		var requested_amount := (
			_get_city_construction_site_unreserved_resource_space(
				city_state,
				site_id,
				resource,
				CityCitizens.INVALID_CITY_CITIZEN_HAUL_RESERVATION_ID
			)
		)

		if requested_amount <= 0:
			continue

		var supply_candidates: Array = (
			CityResourceMatcherScript.get_resource_supply_candidates(
				CityResourceMatcherScript.PURPOSE_CONSTRUCTION_SUPPLY,
				resource,
				requested_amount
			)
			if city_state == null
			else CityResourceMatcherScript.get_resource_supply_candidates_for_city_state(
				city_state,
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

			var task_values := {
					"city_world": _get_city_world(city_state),
					"citizen": citizen,
					"source": source,
					"destination": destination,
					"requester": destination,
					"resource_type": resource,
					"requested_amount": source_requested_amount,
					"reason": (
						CityCitizens.CITY_CITIZEN_HAUL_REASON_CONSTRUCTION_DELIVERY
					),
					"source_access_purpose": (
						CityObjectCatalog.CONTAINER_HAUL_PURPOSE_CONSTRUCTION
					),
					"destination_access_purpose": (
						CityObjectCatalog.CONTAINER_HAUL_PURPOSE_CONSTRUCTION
					),
					"task_source": (
						CityCitizens.CITY_CITIZEN_TASK_SOURCE_PLAYER
					),
					"task_priority": (
						CITY_CONSTRUCTION_TASK_PRIORITY
					),
				}
			var task_request: Dictionary = (
				CitizenHaulingSystemScript.make_directed_haul_task_request(
					task_values
				)
				if city_state == null
				else CitizenHaulingSystemScript.make_directed_haul_task_request_for_city_state(
					city_state,
					task_values
				)
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
				"assignment_path": task_request.get(
					"selection_path",
					[]
				).duplicate(),
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
	city_state: CitySettlementSimulationState,
	citizen: Dictionary,
	site: Dictionary
) -> Dictionary:
	var site_id := int(site.get("id", -1))

	if _get_active_laborer_count(city_state, site_id) >= maxi(
		int(site.get("maximum_workers", 1)),
		1
	):
		return {}

	var citizen_id := int(citizen.get("id", -1))
	var raw_current_tile = citizen.get(
		"city_tile_position",
		CityCitizens.INVALID_CITY_TILE_POSITION
	)

	if not raw_current_tile is Vector2i:
		return {}

	var claimed_positions := _get_claimed_labor_positions(city_state, site_id)
	var candidate_positions: Array[Vector2i] = []

	for position in get_city_construction_site_work_positions(
		site
	):
		if (
			claimed_positions.has(position)
			or not (
				CityNavigationSystem.is_city_tile_walkable_for_citizen(
					WorldPoliticalState.get_current_city_world(),
					position,
					citizen_id
				)
				if city_state == null
				else CityNavigationSystem.is_city_tile_walkable_for_citizen_for_city_state(
					city_state,
					city_state.city_world,
					position,
					citizen_id
				)
			)
		):
			continue

		candidate_positions.append(position)

	if candidate_positions.is_empty():
		return {}

	var city_world := _get_city_world(city_state)
	var path_values := {
			"city_world": city_world,
			"start_tile": raw_current_tile,
			"destination_tiles": candidate_positions,
			"max_expanded_nodes": CityNavigationSystemScript.get_city_wide_path_expansion_limit(
				city_world
			),
			"citizen_id": citizen_id,
			"heuristic_weight": EXACT_PATH_HEURISTIC_WEIGHT,
		}
	var path_result: Dictionary = (
		CityNavigationSystemScript.find_path_to_any_city_tile(path_values)
		if city_state == null
		else CityNavigationSystemScript.find_path_to_any_city_tile_for_city_state(
			city_state,
			path_values
		)
	)

	if not bool(path_result.get("success", false)):
		return {}

	var raw_target_tile = path_result.get(
		"destination_tile",
		CityCitizens.INVALID_CITY_TILE_POSITION
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
		"assignment_path": path_result.get("path", []).duplicate(),
		"tie_break_key": str(raw_target_tile),
	}


static func _get_active_laborer_count(
	city_state: CitySettlementSimulationState,
	site_id: int
) -> int:
	var count := 0
	var registry_state: CityCitizenRegistryState = (
		CityCitizenRegistrySystem.get_current_state()
		if city_state == null
		else city_state.citizen_registry_state
	)

	if registry_state == null:
		return 0

	for raw_citizen in registry_state.citizens:
		if not raw_citizen is Dictionary:
			continue

		var current_task = raw_citizen.get("current_task", {})

		if (
			current_task is Dictionary
			and str(current_task.get("kind", ""))
			== CityCitizens.CITY_CITIZEN_TASK_KIND_CONSTRUCTION
			and int(current_task.get("target_object_id", -1))
			== site_id
		):
			count += 1

	return count


static func _get_claimed_labor_positions(
	city_state: CitySettlementSimulationState,
	site_id: int,
	excluding_citizen_id: int = -1
) -> Dictionary:
	var claimed_positions: Dictionary = {}
	var registry_state: CityCitizenRegistryState = (
		CityCitizenRegistrySystem.get_current_state()
		if city_state == null
		else city_state.citizen_registry_state
	)

	if registry_state == null:
		return claimed_positions

	for raw_citizen in registry_state.citizens:
		if not raw_citizen is Dictionary:
			continue

		var citizen: Dictionary = raw_citizen

		if int(citizen.get("id", -1)) == excluding_citizen_id:
			continue

		var current_task = citizen.get("current_task", {})

		if (
			not current_task is Dictionary
			or str(current_task.get("kind", ""))
			!= CityCitizens.CITY_CITIZEN_TASK_KIND_CONSTRUCTION
			or int(current_task.get("target_object_id", -1))
			!= site_id
		):
			continue

		var raw_target_tile = current_task.get(
			"target_tile",
			CityCitizens.INVALID_CITY_TILE_POSITION
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
		* CITY_CONSTRUCTION_FAIRNESS_BONUS_PER_MINUTE,
		CITY_CONSTRUCTION_MAX_FAIRNESS_BONUS
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


#endregion

#region Construction Work Assignment

static func assign_player_work_candidate(
	citizen_id: int,
	candidate: Dictionary
) -> bool:
	return _assign_player_work_candidate(null, citizen_id, candidate)


static func assign_player_work_candidate_for_city_state(
	city_state: CitySettlementSimulationState,
	citizen_id: int,
	candidate: Dictionary
) -> bool:
	return _assign_player_work_candidate(city_state, citizen_id, candidate)


static func _assign_player_work_candidate(
	city_state: CitySettlementSimulationState,
	citizen_id: int,
	candidate: Dictionary
) -> bool:
	match str(candidate.get("player_work_kind", "")):
		PLAYER_WORK_KIND_DELIVERY:
			var raw_task_request = candidate.get("task_request", {})

			if not raw_task_request is Dictionary:
				return false

			return (
				CityCitizenTaskRuntimeSystem.assign_city_citizen_task(
					citizen_id,
					raw_task_request
				)
				if city_state == null
				else CityCitizenTaskRuntimeSystem.assign_city_citizen_task_for_city_state(
					city_state,
					citizen_id,
					raw_task_request
				)
			)

		PLAYER_WORK_KIND_LABOR:
			var raw_target_tile = candidate.get(
				"target_tile",
				CityCitizens.INVALID_CITY_TILE_POSITION
			)

			if not raw_target_tile is Vector2i:
				return false

			var task_values := {
					"kind": (
						CityCitizens.CITY_CITIZEN_TASK_KIND_CONSTRUCTION
					),
					"source": (
						CityCitizens.CITY_CITIZEN_TASK_SOURCE_PLAYER
					),
					"priority": (
						CITY_CONSTRUCTION_TASK_PRIORITY
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
			return (
				CityCitizenTaskRuntimeSystem.assign_city_citizen_task(
					citizen_id,
					task_values
				)
				if city_state == null
				else CityCitizenTaskRuntimeSystem.assign_city_citizen_task_for_city_state(
					city_state,
					citizen_id,
					task_values
				)
			)

	return false


#endregion

#region Construction Labor State Machine

static func advance_labor_task(
	city_world: WorldData,
	values: Dictionary
) -> int:
	return _advance_labor_task(null, city_world, values)


static func advance_labor_task_for_city_state(
	city_state: CitySettlementSimulationState,
	city_world: WorldData,
	values: Dictionary
) -> int:
	return _advance_labor_task(city_state, city_world, values)


static func _advance_labor_task(
	city_state: CitySettlementSimulationState,
	city_world: WorldData,
	values: Dictionary
) -> int:
	var citizen_id := int(values.get("citizen_id", -1))
	var citizen: Dictionary = values.get("citizen", {})
	var current_task: Dictionary = values.get("current_task", {})
	var path_requests_remaining := maxi(
		int(values.get("path_requests_remaining", 0)),
		0
	)
	var minutes_advanced := maxi(
		int(values.get("minutes_advanced", 0)),
		0
	)
	var site_id := int(current_task.get("target_object_id", -1))
	var site := _get_city_construction_site_by_id(city_state, site_id)
	var raw_target_tile = current_task.get(
		"target_tile",
		CityCitizens.INVALID_CITY_TILE_POSITION
	)
	var raw_current_tile = citizen.get(
		"city_tile_position",
		CityCitizens.INVALID_CITY_TILE_POSITION
	)

	if (
		site.is_empty()
		or str(
			site.get("finalization_state", CITY_CONSTRUCTION_FINALIZATION_STATE_NONE)
		) != CITY_CONSTRUCTION_FINALIZATION_STATE_NONE
		or str(site.get("phase", ""))
		!= CITY_CONSTRUCTION_PHASE_LABOR
		or int(citizen.get("job_object_id", -1)) > 0
		or not raw_target_tile is Vector2i
		or not raw_current_tile is Vector2i
		or not get_city_construction_site_work_positions(
			site
		).has(raw_target_tile)
	):
		_release_labor_task(city_state, citizen_id)
		return path_requests_remaining

	var target_tile: Vector2i = raw_target_tile
	var current_tile: Vector2i = raw_current_tile
	var task_phase := str(
		current_task.get(
			"phase",
			CityCitizens.CITY_CITIZEN_TASK_PHASE_NONE
		)
	)
	var movement_state := str(
		citizen.get(
			"movement_state",
			CityCitizens.CITY_CITIZEN_MOVEMENT_STATE_IDLE
		)
	)

	match task_phase:
		CityCitizens.CITY_CITIZEN_TASK_PHASE_PENDING:
			if current_tile == target_tile:
				_begin_labor(city_state, citizen_id, target_tile)
				return path_requests_remaining

			if movement_state == CityCitizens.CITY_CITIZEN_MOVEMENT_STATE_MOVING:
				return path_requests_remaining

			if path_requests_remaining <= 0:
				return path_requests_remaining

			path_requests_remaining -= 1
			var path_values := {
				"city_world": city_world,
				"start_tile": current_tile,
				"destination_tiles": [target_tile],
				"max_expanded_nodes": CityNavigationSystemScript.get_city_wide_path_expansion_limit(city_world),
				"citizen_id": citizen_id,
				"heuristic_weight": EXACT_PATH_HEURISTIC_WEIGHT,
			}
			var path_result: Dictionary = (
				CityNavigationSystemScript.find_path_to_any_city_tile(path_values)
				if city_state == null
				else CityNavigationSystemScript.find_path_to_any_city_tile_for_city_state(
					city_state,
					path_values
				)
			)
			var movement_assigned := false

			if bool(path_result.get("success", false)):
				movement_assigned = (
					CityCitizenMovementRuntimeSystem.assign_city_citizen_movement_order(
						citizen_id,
						path_result.get("path", [])
					)
					if city_state == null
					else CityCitizenMovementRuntimeSystem.assign_city_citizen_movement_order_for_city_state(
						city_state,
						citizen_id,
						path_result.get("path", [])
					)
				)

			if (
				not bool(path_result.get("success", false))
				or not movement_assigned
			):
				_release_labor_task(city_state, citizen_id)
				return path_requests_remaining

			_set_labor_task_phase(
				city_state,
				citizen_id,
				CityCitizens.CITY_CITIZEN_TASK_PHASE_TRAVELING
			)

		CityCitizens.CITY_CITIZEN_TASK_PHASE_TRAVELING:
			if current_tile == target_tile:
				_begin_labor(city_state, citizen_id, target_tile)
			elif movement_state != CityCitizens.CITY_CITIZEN_MOVEMENT_STATE_MOVING:
				_set_labor_task_phase(
					city_state,
					citizen_id,
					CityCitizens.CITY_CITIZEN_TASK_PHASE_PENDING
				)

		CityCitizens.CITY_CITIZEN_TASK_PHASE_PERFORMING:
			if current_tile != target_tile:
				_set_labor_task_phase(
					city_state,
					citizen_id,
					CityCitizens.CITY_CITIZEN_TASK_PHASE_PENDING
				)
				return path_requests_remaining

			if _add_labor_progress(city_state, site_id, minutes_advanced):
				_complete_city_construction_site(city_state, site_id)
				return path_requests_remaining

			var relocation_minute := int(
				current_task.get(
					"next_action_world_minute",
					CityCitizens.INVALID_CITY_CITIZEN_TASK_ACTION_WORLD_MINUTE
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
				_release_labor_task(city_state, citizen_id)

		_:
			_release_labor_task(city_state, citizen_id)

	return path_requests_remaining


static func _begin_labor(
	city_state: CitySettlementSimulationState,
	citizen_id: int,
	target_tile: Vector2i
) -> bool:
	if city_state == null:
		CityCitizenMovementRuntimeSystem.cancel_city_citizen_movement(citizen_id)
	else:
		CityCitizenMovementRuntimeSystem.cancel_city_citizen_movement_for_city_state(
			city_state,
			citizen_id
		)

	var activity_values := {
		"citizen_id": citizen_id,
		"target_tile": target_tile,
		"next_action_world_minute": (
			SimulationClock.absolute_world_minutes
			+ CITY_CONSTRUCTION_LABOR_ATOMIC_MINUTES
		),
	}
	var activity_set: bool = (
		CityCitizenTaskRuntimeSystem.set_city_citizen_task_activity_state(
			activity_values
		)
		if city_state == null
		else CityCitizenTaskRuntimeSystem.set_city_citizen_task_activity_state_for_city_state(
			city_state,
			activity_values
		)
	)

	if not activity_set:
		return false

	return _set_labor_task_phase(
		city_state,
		citizen_id,
		CityCitizens.CITY_CITIZEN_TASK_PHASE_PERFORMING
	)


static func _add_labor_progress(
	city_state: CitySettlementSimulationState,
	site_id: int,
	minutes_advanced: int
) -> bool:
	var site := _get_city_construction_site_by_id(city_state, site_id)
	if (
		site.is_empty()
		or str(site.get("phase", ""))
		!= CITY_CONSTRUCTION_PHASE_LABOR
	):
		return false

	site["completed_labor_minutes"] = mini(
		maxi(int(site.get("completed_labor_minutes", 0)), 0)
		+ maxi(minutes_advanced, 0),
		maxi(int(site.get("required_labor_minutes", 1)), 1)
	)

	if not _update_city_construction_site(city_state, site):
		return false

	return (
		int(site.get("completed_labor_minutes", 0))
		>= int(site.get("required_labor_minutes", 1))
	)



static func _set_labor_task_phase(
	city_state: CitySettlementSimulationState,
	citizen_id: int,
	task_phase: String
) -> bool:
	return (
		CityCitizenTaskRuntimeSystem.set_city_citizen_task_phase(
			citizen_id,
			task_phase
		)
		if city_state == null
		else CityCitizenTaskRuntimeSystem.set_city_citizen_task_phase_for_city_state(
			city_state,
			citizen_id,
			task_phase
		)
	)


static func _release_labor_task(
	city_state: CitySettlementSimulationState,
	citizen_id: int
) -> void:
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


#endregion

#region Construction Completion and Cancellation

static func complete_city_construction_site(
	site_id: int
) -> Dictionary:
	return _complete_city_construction_site(null, site_id)


static func complete_city_construction_site_for_city_state(
	city_state: CitySettlementSimulationState,
	site_id: int
) -> Dictionary:
	return _complete_city_construction_site(city_state, site_id)


static func _complete_city_construction_site(
	city_state: CitySettlementSimulationState,
	site_id: int
) -> Dictionary:
	var site := _get_city_construction_site_by_id(city_state, site_id)

	if site.is_empty():
		return {}

	if (
		str(site.get("finalization_state", CITY_CONSTRUCTION_FINALIZATION_STATE_NONE))
		== CITY_CONSTRUCTION_FINALIZATION_STATE_AWAITING_CLEARANCE
	):
		return _advance_city_construction_finalization(city_state, site_id)

	_refresh_city_construction_site(city_state, site_id)
	site = _get_city_construction_site_by_id(city_state, site_id)

	if (
		site.is_empty()
		or str(site.get("target_kind", ""))
		!= CITY_CONSTRUCTION_TARGET_NEW
		or str(site.get("phase", ""))
		!= CITY_CONSTRUCTION_PHASE_LABOR
		or int(site.get("completed_labor_minutes", 0))
		< int(site.get("required_labor_minutes", 1))
		or not _city_construction_site_has_all_materials(city_state, site_id)
	):
		return {}

	if not _release_site_delivery_tasks(city_state, site_id):
		return {}

	_refresh_city_construction_site(city_state, site_id)
	site = _get_city_construction_site_by_id(city_state, site_id)

	if (
		site.is_empty()
		or str(site.get("phase", ""))
		!= CITY_CONSTRUCTION_PHASE_LABOR
		or not _city_construction_site_has_all_materials(city_state, site_id)
	):
		return {}

	# Labor completion is not the same operation as changing navigation. First
	# close the work claims and enter a durable finalization state. The site then
	# owns clearance and retries until the authoritative footprint is safe.
	_clear_site_labor_tasks(city_state, site_id)
	site = _get_city_construction_site_by_id(city_state, site_id)

	if site.is_empty():
		return {}

	site["finalization_state"] = CITY_CONSTRUCTION_FINALIZATION_STATE_AWAITING_CLEARANCE

	if not _update_city_construction_site(city_state, site):
		return {}

	return _advance_city_construction_finalization(city_state, site_id)


static func _advance_city_construction_finalization(
	city_state: CitySettlementSimulationState,
	site_id: int
) -> Dictionary:
	var site := _get_city_construction_site_by_id(city_state, site_id)
	var city_world: WorldData = _get_city_world(city_state)

	if (
		site.is_empty()
		or city_world == null
		or str(site.get("finalization_state", CITY_CONSTRUCTION_FINALIZATION_STATE_NONE))
		!= CITY_CONSTRUCTION_FINALIZATION_STATE_AWAITING_CLEARANCE
	):
		return {}

	var object_type := str(site.get("object_type", ""))
	var footprint_tiles: Array = site.get("footprint_tiles", [])
	var blocking_citizen_ids: Array[int] = (
		CityObjectSystem.get_city_object_topology_blocking_citizen_ids(
			object_type,
			footprint_tiles
		)
		if city_state == null
		else CityObjectSystem.get_city_object_topology_blocking_citizen_ids_for_city_state(
			city_state,
			object_type,
			footprint_tiles
		)
	)

	if not blocking_citizen_ids.is_empty():
		_evacuate_city_construction_footprint(
			city_state,
			site,
			blocking_citizen_ids
		)
		return {}

	# Resources remain physical and reserved until this exact point. If the
	# authoritative topology gate rejects the object for any late change, the
	# materials are restored and the durable site remains available to retry.
	var consumed_materials := _consume_site_materials(city_state, site)
	var raw_material_recipe = site.get("material_recipe", {})

	if (
		consumed_materials.is_empty()
		and raw_material_recipe is Dictionary
		and not raw_material_recipe.is_empty()
	):
		return {}

	var registration_values := {
		"object_type": object_type,
		"top_left": site.get(
			"top_left",
			CityCitizens.INVALID_CITY_TILE_POSITION
		),
		"size_tiles": site.get("size", Vector2i.ZERO),
		"footprint_tiles": footprint_tiles,
		"object_owner": str(site.get("owner", "player")),
		"city_world": city_world,
	}
	var completed_object: Dictionary = (
		CityObjectSystem.register_completed_city_object_from_construction_site(
			site_id,
			registration_values
		)
		if city_state == null
		else CityObjectSystem.register_completed_city_object_from_construction_site_for_city_state(
			city_state,
			site_id,
			registration_values
		)
	)

	if completed_object.is_empty():
		_restore_site_materials(city_state, site, consumed_materials)
		return {}

	_release_site_clearing_commands(city_state, site_id)
	_remove_city_construction_site_record(city_state, site_id)
	return completed_object


static func _evacuate_city_construction_footprint(
	city_state: CitySettlementSimulationState,
	site: Dictionary,
	citizen_ids: Array[int]
) -> void:
	var city_world: WorldData = _get_city_world(city_state)

	if city_world == null or site.is_empty():
		return

	var footprint_tiles: Array = site.get("footprint_tiles", [])
	var destination_tiles := _build_external_work_positions(
		city_state,
		city_world,
		footprint_tiles
	)

	if destination_tiles.is_empty():
		push_warning(
			"Construction site "
				+ str(site.get("id", -1))
				+ " is ready to finalize but has no reachable exterior "
				+ "clearance tile."
		)
		return

	for citizen_id in citizen_ids:
		var citizen: Dictionary = (
			CityCitizenRegistrySystem.get_city_citizen_by_id(citizen_id)
			if city_state == null
			else CityCitizenRegistrySystem.get_city_citizen_by_id_for_city_state(
				city_state,
				citizen_id
			)
		)
		var raw_current_tile = citizen.get(
			"city_tile_position",
			CityCitizens.INVALID_CITY_TILE_POSITION
		)

		if (
			citizen.is_empty()
			or not bool(citizen.get("alive", false))
			or not raw_current_tile is Vector2i
			or not footprint_tiles.has(raw_current_tile)
		):
			continue

		var raw_destination = citizen.get(
			"movement_destination_tile",
			CityCitizens.INVALID_CITY_TILE_POSITION
		)

		if (
			str(citizen.get("movement_state", ""))
			== CityCitizens.CITY_CITIZEN_MOVEMENT_STATE_MOVING
			and raw_destination is Vector2i
			and not footprint_tiles.has(raw_destination)
		):
			continue

		var path_values := {
			"city_world": city_world,
			"start_tile": raw_current_tile,
			"destination_tiles": destination_tiles,
			"max_expanded_nodes": (
				CityNavigationSystemScript
				.get_city_wide_path_expansion_limit(city_world)
			),
			"citizen_id": citizen_id,
			"heuristic_weight": EXACT_PATH_HEURISTIC_WEIGHT,
		}
		var path_result: Dictionary = (
			CityNavigationSystemScript.find_path_to_any_city_tile(path_values)
			if city_state == null
			else CityNavigationSystemScript.find_path_to_any_city_tile_for_city_state(
				city_state,
				path_values
			)
		)

		if not bool(path_result.get("success", false)):
			push_warning(
				"Could not route citizen "
					+ str(citizen_id)
					+ " out of finalizing construction site "
					+ str(site.get("id", -1))
			)
			continue

		if city_state == null:
			CityCitizenMovementRuntimeSystem.cancel_city_citizen_movement(citizen_id)
		else:
			CityCitizenMovementRuntimeSystem.cancel_city_citizen_movement_for_city_state(
				city_state,
				citizen_id
			)

		var movement_assigned: bool = (
			CityCitizenMovementRuntimeSystem.assign_city_citizen_movement_order(
				citizen_id,
				path_result.get("path", [])
			)
			if city_state == null
			else CityCitizenMovementRuntimeSystem.assign_city_citizen_movement_order_for_city_state(
				city_state,
				citizen_id,
				path_result.get("path", [])
			)
		)

		if not movement_assigned:
			push_warning(
				"Could not install topology-clearance movement for citizen "
					+ str(citizen_id)
			)


static func _consume_site_materials(
	city_state: CitySettlementSimulationState,
	site: Dictionary
) -> Dictionary:
	var site_id := int(site.get("id", -1))
	var raw_recipe = site.get("material_recipe", {})
	var consumed: Dictionary = {}

	if not raw_recipe is Dictionary:
		return consumed

	for resource in CityResourceCatalog.get_city_resource_types():
		var required_amount := maxi(
			int(raw_recipe.get(resource, 0)),
			0
		)

		if required_amount <= 0:
			continue

		var removed_amount := (
			_remove_resource_from_city_construction_site(
				city_state,
				site_id,
				resource,
				required_amount
			)
		)

		if removed_amount != required_amount:
			_restore_site_materials(city_state, site, consumed)

			if removed_amount > 0:
				_restore_site_materials(
					city_state,
					site,
					{resource: removed_amount}
				)

			return {}

		consumed[resource] = removed_amount

	return consumed


static func _restore_site_materials(
	city_state: CitySettlementSimulationState,
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

		if city_state == null:
			CityLogisticsSystem.add_resource_to_city_ground_pile(
				deposit_tile,
				str(resource),
				amount,
				site_id
			)
		else:
			CityLogisticsSystem.add_resource_to_city_ground_piles_with_result_for_city_state(
				city_state,
				{
					"tile_position": deposit_tile,
					"resource": str(resource),
					"amount_delta": amount,
					"construction_site_id": site_id,
				}
			)


static func cancel_city_construction_site(site_id: int) -> bool:
	return _cancel_city_construction_site(null, site_id)


static func cancel_city_construction_site_for_city_state(
	city_state: CitySettlementSimulationState,
	site_id: int
) -> bool:
	return _cancel_city_construction_site(city_state, site_id)


static func _cancel_city_construction_site(
	city_state: CitySettlementSimulationState,
	site_id: int
) -> bool:
	var site := (
		get_city_construction_site_by_id(site_id)
		if city_state == null
		else get_city_construction_site_by_id_for_city_state(city_state, site_id)
	)
	if site.is_empty():
		return false

	# Stop deliveries first while every referenced endpoint still exists. A
	# picked-up load remains physical cargo and is converted into an outstanding
	# public-storage obligation; cancellation never spills it merely because its
	# original destination disappeared.
	if not _release_site_delivery_tasks(city_state, site_id):
		return false

	_release_site_clearing_commands(city_state, site_id)
	_clear_site_labor_tasks(city_state, site_id)
	if city_state == null:
		CityLogisticsSystem.release_city_construction_site_materials(site_id)
		return remove_city_construction_site_record(site_id)

	CityLogisticsSystem.release_city_construction_site_materials_for_city_state(
		city_state,
		site_id
	)
	return remove_city_construction_site_record_for_city_state(city_state, site_id)


static func _release_site_delivery_tasks(
	city_state: CitySettlementSimulationState,
	site_id: int
) -> bool:
	var registry_state: CityCitizenRegistryState = (
		CityCitizenRegistrySystem.get_current_state()
		if city_state == null
		else city_state.citizen_registry_state
	)

	if registry_state == null:
		return false

	for raw_citizen in registry_state.citizens.duplicate():
		if not raw_citizen is Dictionary:
			continue

		var citizen: Dictionary = raw_citizen
		var citizen_id := int(citizen.get("id", -1))
		var current_task = citizen.get("current_task", {})

		if (
			not current_task is Dictionary
			or str(current_task.get("kind", ""))
			!= CityCitizens.CITY_CITIZEN_TASK_KIND_HAUL
			or not _haul_references_site(city_state, citizen_id, site_id)
		):
			continue

		var cargo_amount: int = (
			CityCitizenInventorySystem.get_city_citizen_haul_cargo_amount(citizen_id)
			if city_state == null
			else CityCitizenInventorySystem.get_city_citizen_haul_cargo_amount_for_city_state(
				city_state,
				citizen_id
			)
		)

		if cargo_amount > 0:
			var haul: Dictionary = (
				CityCitizenTaskRuntimeSystem.get_city_citizen_current_haul(citizen_id)
				if city_state == null
				else CityCitizenTaskRuntimeSystem.get_city_citizen_current_haul_for_city_state(
					city_state,
					citizen_id
				)
			)
			var raw_source = haul.get("source", {})

			if not raw_source is Dictionary:
				return false

			var source: Dictionary = raw_source
			haul["destination"] = (
				CityCitizens.make_city_citizen_haul_endpoint()
			)
			haul["requester"] = source
			haul["reason"] = (
				CityCitizens.CITY_CITIZEN_HAUL_REASON_OUTSTANDING_CARGO
			)
			if city_state == null:
				CityCitizenTaskRuntimeSystem.set_city_citizen_current_haul(
					citizen_id,
					haul
				)
			else:
				CityCitizenTaskRuntimeSystem.set_city_citizen_current_haul_for_city_state(
					city_state,
					citizen_id,
					haul
				)

		var task_source := str(
			current_task.get(
				"source",
				CityCitizens.CITY_CITIZEN_TASK_SOURCE_PLAYER
			)
		)

		if city_state == null:
			CityCitizenMovementRuntimeSystem.cancel_city_citizen_movement(citizen_id)
		else:
			CityCitizenMovementRuntimeSystem.cancel_city_citizen_movement_for_city_state(
				city_state,
				citizen_id
			)

		var task_cleared: bool = (
			CityCitizenTaskRuntimeSystem.clear_city_citizen_task(
				citizen_id,
				task_source
			)
			if city_state == null
			else CityCitizenTaskRuntimeSystem.clear_city_citizen_task_for_city_state(
				city_state,
				citizen_id,
				task_source
			)
		)

		if not task_cleared:
			return false

	return true


static func _release_site_clearing_commands(
	city_state: CitySettlementSimulationState,
	site_id: int
) -> void:
	var command_snapshot: Array = (
		CityWorkSystem.get_city_player_command_snapshot()
		if city_state == null
		else CityWorkSystem.get_city_player_command_snapshot_for_city_state(
			city_state
		)
	)

	for raw_command in command_snapshot:
		if not raw_command is Dictionary:
			continue

		var command: Dictionary = raw_command

		if int(command.get("construction_site_id", -1)) != site_id:
			continue

		var command_id := int(command.get("id", -1))

		if bool(command.get("created_by_construction", false)):
			if city_state == null:
				CityWorkSystem.cancel_city_player_command(command_id)
			else:
				CityWorkSystem.cancel_city_player_command_for_city_state(
					city_state,
					command_id
				)
		else:
			if city_state == null:
				CityWorkSystem.detach_city_player_command_from_construction(
					command_id,
					site_id
				)
			else:
				CityWorkSystem.detach_city_player_command_from_construction_for_city_state(
					city_state,
					command_id,
					site_id
				)


static func _clear_site_labor_tasks(
	city_state: CitySettlementSimulationState,
	site_id: int
) -> void:
	var registry_state: CityCitizenRegistryState = (
		CityCitizenRegistrySystem.get_current_state()
		if city_state == null
		else city_state.citizen_registry_state
	)

	if registry_state == null:
		return

	for raw_citizen in registry_state.citizens.duplicate():
		if not raw_citizen is Dictionary:
			continue

		var citizen: Dictionary = raw_citizen
		var current_task = citizen.get("current_task", {})

		if (
			current_task is Dictionary
			and str(current_task.get("kind", ""))
			== CityCitizens.CITY_CITIZEN_TASK_KIND_CONSTRUCTION
			and int(current_task.get("target_object_id", -1))
			== site_id
		):
			_release_labor_task(
				city_state,
				int(citizen.get("id", -1))
			)


static func _haul_references_site(
	city_state: CitySettlementSimulationState,
	citizen_id: int,
	site_id: int
) -> bool:
	var haul: Dictionary = (
		CityCitizenTaskRuntimeSystem.get_city_citizen_current_haul(citizen_id)
		if city_state == null
		else CityCitizenTaskRuntimeSystem.get_city_citizen_current_haul_for_city_state(
			city_state,
			citizen_id
		)
	)
	var site_endpoint := (
		CityLogisticsSystem.make_city_construction_site_haul_endpoint(site_id)
	)

	for endpoint_field in ["source", "destination", "requester"]:
		var raw_endpoint = haul.get(endpoint_field, {})

		if (
			raw_endpoint is Dictionary
			and CityLogisticsSystem.city_citizen_haul_endpoints_match(
				raw_endpoint,
				site_endpoint
			)
		):
			return true

	return false


#endregion

#region Construction Interrupts and Shared Helpers


# A newly placed blueprint can improve an uncommitted construction trip, but
# it must never erase every assignment merely to ask the scheduler again.
# Workers are compared and switched one at a time so live claims, delivery
# reservations, and useful parallel capacity shape every following choice.
static func rebalance_uncommitted_construction_workers(
	triggering_site_id: int
) -> int:
	return rebalance_uncommitted_construction_workers_for_sites(
		[triggering_site_id]
	)


# A painted road creates many independent sites at once. Rebalancing accepts
# the whole batch so a worker can compare against the nearest useful tile while
# still receiving a task owned by exactly one construction site.
static func rebalance_uncommitted_construction_workers_for_sites(
	raw_triggering_site_ids: Array
) -> int:
	var triggering_site_id_lookup: Dictionary = {}

	for raw_site_id in raw_triggering_site_ids:
		var site_id := int(raw_site_id)

		if (
			site_id > 0
			and not get_city_construction_site_by_id(
				site_id
			).is_empty()
		):
			triggering_site_id_lookup[site_id] = true

	if (
		triggering_site_id_lookup.is_empty()
		or get_current_state().construction_sites.size() <= 1
	):
		return 0

	# Do not create or refresh work orders merely because a blueprint was
	# placed. Rebalancing is meaningful only when an existing, uncommitted
	# construction worker can actually be reconsidered. This prefilter stays
	# ahead of every work-board synchronization and path search on the placement
	# frame, while preserving the immediate redirect behavior for real workers.
	var citizen_ids: Array[int] = []

	for raw_citizen in CityCitizenRegistrySystem.get_current_state().citizens:
		if not raw_citizen is Dictionary:
			continue

		var citizen: Dictionary = raw_citizen
		var citizen_id := int(citizen.get("id", -1))

		if (
			citizen_id <= 0
			or not bool(citizen.get("alive", false))
			or int(citizen.get("job_object_id", -1)) > 0
			or CityCitizenInventorySystem.get_city_citizen_haul_cargo_amount(
				citizen_id
			) > 0
			or not citizen_task_is_interruptible_construction(citizen_id)
		):
			continue

		var current_task := (
			CityCitizenTaskRuntimeSystem.get_city_citizen_current_task(
				citizen_id
			)
		)

		if (
			str(current_task.get("kind", ""))
			== CityCitizens.CITY_CITIZEN_TASK_KIND_HAUL
			or str(current_task.get("phase", "")) not in [
				CityCitizens.CITY_CITIZEN_TASK_PHASE_PENDING,
				CityCitizens.CITY_CITIZEN_TASK_PHASE_TRAVELING,
				CityCitizens.CITY_CITIZEN_TASK_PHASE_BLOCKED,
			]
		):
			continue

		citizen_ids.append(citizen_id)

	if citizen_ids.is_empty():
		return 0

	citizen_ids.sort()
	var triggering_site_ids: Array = triggering_site_id_lookup.keys()
	triggering_site_ids.sort()
	var triggering_order_ids: Array[int] = []
	var triggering_order_id_lookup: Dictionary = {}
	var existing_order_by_site_id: Dictionary = {}

	for raw_order_id in CityWorkSystem.get_current_work_state().work_orders.keys():
		var existing_order := CityWorkSystem.get_city_work_order_by_id(
			int(raw_order_id)
		)

		if (
			not existing_order.is_empty()
			and str(existing_order.get("order_type", ""))
			== CityWorkSystem.ORDER_TYPE_CONSTRUCTION_SITE
		):
			existing_order_by_site_id[
				int(existing_order.get("source_id", -1))
			] = existing_order

	for raw_site_id in triggering_site_ids:
		var site_id := int(raw_site_id)
		var raw_triggering_order = existing_order_by_site_id.get(
			site_id,
			{}
		)
		var triggering_order: Dictionary = (
			raw_triggering_order
			if raw_triggering_order is Dictionary
			else {}
		)

		if triggering_order.is_empty():
			triggering_order = (
				CityWorkSystem.synchronize_construction_work_order(
					site_id
				)
			)

		if triggering_order.is_empty():
			continue

		var triggering_order_id := int(
			triggering_order.get("id", -1)
		)

		if triggering_order_id > 0:
			triggering_order_ids.append(triggering_order_id)
			triggering_order_id_lookup[triggering_order_id] = true

	if triggering_order_ids.is_empty():
		return 0

	var affected_order_ids: Dictionary = (
		triggering_order_id_lookup.duplicate()
	)
	var switched_count := 0

	for citizen_id in citizen_ids:
		var citizen := CityCitizenRegistrySystem.get_city_citizen_by_id(citizen_id)

		if (
			citizen.is_empty()
			or not bool(citizen.get("alive", false))
			or int(citizen.get("job_object_id", -1)) > 0
			or CityCitizenInventorySystem.get_city_citizen_haul_cargo_amount(citizen_id) > 0
			or not citizen_task_is_interruptible_construction(citizen_id)
		):
			continue

		var current_task := CityCitizenTaskRuntimeSystem.get_city_citizen_current_task(
			citizen_id
		)
		var task_kind := str(current_task.get("kind", ""))

		# A delivery owns a real source/destination reservation even before
		# pickup. Clearing or spilling it here would recreate the very churn
		# this comparison pass is meant to prevent.
		if task_kind == CityCitizens.CITY_CITIZEN_TASK_KIND_HAUL:
			continue

		var task_phase := str(
			current_task.get(
				"phase",
				CityCitizens.CITY_CITIZEN_TASK_PHASE_NONE
			)
		)

		# Performing commands are actively clearing and performing
		# construction is inside its bounded labor unit. Both are physical
		# commitment boundaries.
		if task_phase == CityCitizens.CITY_CITIZEN_TASK_PHASE_PERFORMING:
			continue

		if task_phase not in [
			CityCitizens.CITY_CITIZEN_TASK_PHASE_PENDING,
			CityCitizens.CITY_CITIZEN_TASK_PHASE_TRAVELING,
			CityCitizens.CITY_CITIZEN_TASK_PHASE_BLOCKED,
		]:
			continue

		var current_order_id := int(
			current_task.get("work_order_id", -1)
		)

		if triggering_order_id_lookup.has(current_order_id):
			continue

		var current_order := CityWorkSystem.get_city_work_order_by_id(
			current_order_id
		)

		if (
			current_order.is_empty()
			or str(current_order.get("order_type", ""))
			!= CityWorkSystem.ORDER_TYPE_CONSTRUCTION_SITE
		):
			continue

		var current_is_blocked := (
			task_phase == CityCitizens.CITY_CITIZEN_TASK_PHASE_BLOCKED
			or str(citizen.get("movement_state", ""))
			== CityCitizens.CITY_CITIZEN_MOVEMENT_STATE_BLOCKED
		)
		var current_path_cost := -1

		if not current_is_blocked:
			current_path_cost = _get_current_construction_path_cost(
				citizen_id,
				current_task
			)
			current_is_blocked = current_path_cost < 0

		var candidate := {}

		if current_is_blocked:
			# Blocked citizens reconsider all other reachable construction work.
			candidate = (
				CityWorkSystem
				.get_best_construction_job_for_citizen_excluding_order(
					citizen_id,
					current_order_id
				)
			)
		else:
			# Healthy assignments compare only against this newly introduced
			# batch, preventing unrelated old sites from causing a global shuffle.
			candidate = (
				CityWorkSystem.get_best_player_job_for_citizen_and_orders(
					citizen_id,
					triggering_order_ids
				)
			)

		if not _construction_reassignment_is_worthwhile(
			current_order,
			current_path_cost,
			current_is_blocked,
			candidate
		):
			continue

		var restore_state := (
			_make_construction_rebalance_restore_state(
				current_task,
				citizen
			)
		)

		if (
			restore_state.is_empty()
			or not CityCitizenTaskRuntimeSystem.clear_city_citizen_task(
				citizen_id,
				CityCitizens.CITY_CITIZEN_TASK_SOURCE_PLAYER
			)
		):
			continue

		CityCitizenMovementRuntimeSystem.cancel_city_citizen_movement(citizen_id)

		if (
			# Rebalance owns strict route installation and rollback, so suppress
			# the normal best-effort start performed by assign_player_job.
			CityWorkSystem.assign_player_job(citizen_id, candidate, false)
			and start_assigned_player_work_candidate(
				citizen_id,
				candidate
			)
		):
			switched_count += 1
			affected_order_ids[current_order_id] = true
			affected_order_ids[int(candidate.get("work_order_id", -1))] = true
			continue

		# Release any partially installed replacement claim or reservation,
		# then continue the previous trip from the citizen's current tile.
		CityCitizenTaskRuntimeSystem.clear_city_citizen_task(
			citizen_id,
			CityCitizens.CITY_CITIZEN_TASK_SOURCE_PLAYER
		)
		CityCitizenMovementRuntimeSystem.cancel_city_citizen_movement(citizen_id)

		if not _restore_construction_rebalance_assignment(
			citizen_id,
			restore_state
		):
			push_warning(
				"Construction rebalance could not restore citizen "
				+ str(citizen_id)
				+ " after the replacement assignment became invalid."
			)

	if switched_count > 0:
		CityWorkSystem.refresh_work_order_runtimes(
			affected_order_ids.keys()
		)

	return switched_count


static func _get_current_construction_path_cost(
	citizen_id: int,
	current_task: Dictionary
) -> int:
	var citizen := CityCitizenRegistrySystem.get_city_citizen_by_id(citizen_id)
	var raw_current_tile = citizen.get(
		"city_tile_position",
		CityCitizens.INVALID_CITY_TILE_POSITION
	)

	if (
		citizen.is_empty()
		or not raw_current_tile is Vector2i
		or WorldPoliticalState.get_current_city_world() == null
	):
		return -1

	var remaining_movement_path := _get_remaining_citizen_movement_path(
		citizen
	)
	var raw_task_target_tile = current_task.get(
		"target_tile",
		CityCitizens.INVALID_CITY_TILE_POSITION
	)

	# A live route is already an exact measurement from the citizen's current
	# position. Reuse it instead of asking navigation to solve the same trip
	# again for every blueprint placement.
	if (
		str(current_task.get("phase", ""))
		== CityCitizens.CITY_CITIZEN_TASK_PHASE_TRAVELING
		and raw_task_target_tile is Vector2i
		and not remaining_movement_path.is_empty()
		and remaining_movement_path.back() == raw_task_target_tile
	):
		return _get_city_movement_path_cost(remaining_movement_path)

	var destination_tiles: Array = []
	var raw_target_tile = raw_task_target_tile

	match str(current_task.get("kind", "")):
		CityCitizens.CITY_CITIZEN_TASK_KIND_CONSTRUCTION:
			var site := get_city_construction_site_by_id(
				int(current_task.get("target_object_id", -1))
			)
			var work_positions := (
				get_city_construction_site_work_positions(site)
			)

			if raw_target_tile is Vector2i and work_positions.has(
				raw_target_tile
			):
				destination_tiles.append(raw_target_tile)
			else:
				destination_tiles = work_positions

		CityCitizens.CITY_CITIZEN_TASK_KIND_PLAYER_COMMAND:
			var command := CityWorkSystem.get_city_player_command_by_id(
				int(current_task.get("target_object_id", -1))
			)
			var work_tiles := CityWorkSystem.get_city_player_command_work_tiles(
				command,
				citizen_id
			)

			if raw_target_tile is Vector2i and work_tiles.has(raw_target_tile):
				destination_tiles.append(raw_target_tile)
			else:
				destination_tiles = work_tiles

	if destination_tiles.is_empty():
		return -1

	var path_result := CityNavigationSystemScript.find_path_to_any_city_tile({
		"city_world": WorldPoliticalState.get_current_city_world(),
		"start_tile": raw_current_tile,
		"destination_tiles": destination_tiles,
		"max_expanded_nodes": CityNavigationSystemScript.get_city_wide_path_expansion_limit(
			WorldPoliticalState.get_current_city_world()
		),
		"citizen_id": citizen_id,
		"heuristic_weight": EXACT_PATH_HEURISTIC_WEIGHT,
	})

	if not bool(path_result.get("success", false)):
		return -1

	return maxi(int(path_result.get("path_cost", 0)), 0)


static func _get_remaining_citizen_movement_path(
	citizen: Dictionary
) -> Array:
	if (
		str(citizen.get("movement_state", ""))
		!= CityCitizens.CITY_CITIZEN_MOVEMENT_STATE_MOVING
	):
		return []

	var raw_path = citizen.get("movement_path", [])
	var raw_current_tile = citizen.get(
		"city_tile_position",
		CityCitizens.INVALID_CITY_TILE_POSITION
	)

	if not raw_path is Array or not raw_current_tile is Vector2i:
		return []

	var path: Array = raw_path
	var path_index := int(citizen.get("movement_path_index", 0))

	if (
		path_index <= 0
		or path_index >= path.size()
		or path[path_index - 1] != raw_current_tile
	):
		return []

	var remaining_path: Array = [raw_current_tile]

	for index in range(path_index, path.size()):
		if not path[index] is Vector2i:
			return []

		remaining_path.append(path[index])

	return remaining_path


static func _get_city_movement_path_cost(path: Array) -> int:
	if path.is_empty():
		return -1

	var path_cost := 0

	for index in range(1, path.size()):
		if not path[index - 1] is Vector2i or not path[index] is Vector2i:
			return -1

		var step_cost := CityNavigationSystem.get_city_citizen_movement_step_cost(
			path[index - 1],
			path[index]
		)

		if step_cost <= 0:
			return -1

		path_cost += step_cost

	return path_cost


static func _construction_reassignment_is_worthwhile(
	current_order: Dictionary,
	current_path_cost: int,
	current_is_blocked: bool,
	candidate: Dictionary
) -> bool:
	if candidate.is_empty():
		return false

	if current_is_blocked:
		return true

	var current_priority := int(
		current_order.get("priority_rank", CityWorkSystem.PRIORITY_NORMAL)
	)
	var candidate_priority := int(
		candidate.get("priority_rank", CityWorkSystem.PRIORITY_NORMAL)
	)

	if candidate_priority != current_priority:
		return candidate_priority > current_priority

	var candidate_path_cost := maxi(
		int(candidate.get("estimated_path_cost", 0)),
		0
	)

	if current_path_cost <= 0 or candidate_path_cost >= current_path_cost:
		return false

	var path_savings := current_path_cost - candidate_path_cost
	var minimum_absolute_savings := (
		REBALANCE_MINIMUM_PATH_SAVINGS_TILES
		* CityCitizens.CITY_CITIZEN_CARDINAL_MOVEMENT_COST
	)
	var clears_absolute_dead_band := (
		path_savings >= minimum_absolute_savings
	)
	var clears_relative_dead_band := (
		path_savings * 100
		>= current_path_cost
		* REBALANCE_MINIMUM_RELATIVE_SAVINGS_PERCENT
	)

	# This dead band is the hysteresis: fairness/age cannot reverse a switch,
	# and repeated placements cannot bounce equal-priority workers unless a
	# route has become materially better from their new current position.
	return clears_absolute_dead_band and clears_relative_dead_band


# Candidate selection has already paid for and tie-resolved this exact route.
# Install it immediately after the task is assigned so the Task phase does not
# synchronously solve the same city-wide path again on the next tick. Every
# field is revalidated; a stale witness simply returns false and the normal
# pending-task fallback retains its established behavior.
static func start_assigned_player_work_candidate(
	citizen_id: int,
	candidate: Dictionary
) -> bool:
	return _start_assigned_player_work_candidate(null, citizen_id, candidate)


static func start_assigned_player_work_candidate_for_city_state(
	city_state: CitySettlementSimulationState,
	citizen_id: int,
	candidate: Dictionary
) -> bool:
	return _start_assigned_player_work_candidate(
		city_state,
		citizen_id,
		candidate
	)


static func _start_assigned_player_work_candidate(
	city_state: CitySettlementSimulationState,
	citizen_id: int,
	candidate: Dictionary
) -> bool:
	var raw_assignment_path = candidate.get("assignment_path", [])
	var citizen: Dictionary = (
		CityCitizenRegistrySystem.get_city_citizen_by_id(citizen_id)
		if city_state == null
		else CityCitizenRegistrySystem.get_city_citizen_by_id_for_city_state(
			city_state,
			citizen_id
		)
	)
	var raw_current_tile = citizen.get(
		"city_tile_position",
		CityCitizens.INVALID_CITY_TILE_POSITION
	)

	if (
		not raw_assignment_path is Array
		or raw_assignment_path.is_empty()
		or citizen.is_empty()
		or not raw_current_tile is Vector2i
	):
		return false

	var assignment_path: Array = raw_assignment_path

	if assignment_path[0] != raw_current_tile:
		return false

	var work_kind := str(candidate.get("player_work_kind", ""))
	var raw_target_tile = candidate.get(
		"target_tile",
		CityCitizens.INVALID_CITY_TILE_POSITION
	)
	var haul: Dictionary = {}

	if work_kind == PLAYER_WORK_KIND_DELIVERY:
		haul = (
			CityCitizenTaskRuntimeSystem.get_city_citizen_current_haul(citizen_id)
			if city_state == null
			else CityCitizenTaskRuntimeSystem.get_city_citizen_current_haul_for_city_state(
				city_state,
				citizen_id
			)
		)
		raw_target_tile = haul.get(
			"source_tile",
			CityCitizens.INVALID_CITY_TILE_POSITION
		)

	if not raw_target_tile is Vector2i or assignment_path.back() != raw_target_tile:
		return false

	var activity_values := {
		"citizen_id": citizen_id,
		"target_tile": raw_target_tile,
	}
	var activity_set: bool = (
		CityCitizenTaskRuntimeSystem.set_city_citizen_task_activity_state(
			activity_values
		)
		if city_state == null
		else CityCitizenTaskRuntimeSystem.set_city_citizen_task_activity_state_for_city_state(
			city_state,
			activity_values
		)
	)

	if not activity_set:
		return false

	if assignment_path.size() <= 1:
		if city_state == null:
			CityCitizenMovementRuntimeSystem.cancel_city_citizen_movement(citizen_id)
		else:
			CityCitizenMovementRuntimeSystem.cancel_city_citizen_movement_for_city_state(
				city_state,
				citizen_id
			)

		if work_kind == PLAYER_WORK_KIND_DELIVERY:
			haul["phase"] = CityCitizens.CITY_CITIZEN_HAUL_PHASE_PICKING_UP
			haul["source_tile"] = raw_target_tile

			var haul_set: bool = (
				CityCitizenTaskRuntimeSystem.set_city_citizen_current_haul(
					citizen_id,
					haul
				)
				if city_state == null
				else CityCitizenTaskRuntimeSystem.set_city_citizen_current_haul_for_city_state(
					city_state,
					citizen_id,
					haul
				)
			)
			return (
				haul_set
				and _set_labor_task_phase(
					city_state,
					citizen_id,
					CityCitizens.CITY_CITIZEN_TASK_PHASE_PERFORMING
				)
			)

		# Labor and commands are already at their work tile. Their normal task
		# state machine begins the bounded physical action on the next clock tick.
		return true

	var movement_assigned: bool = (
		CityCitizenMovementRuntimeSystem.assign_city_citizen_movement_order(
			citizen_id,
			assignment_path
		)
		if city_state == null
		else CityCitizenMovementRuntimeSystem.assign_city_citizen_movement_order_for_city_state(
			city_state,
			citizen_id,
			assignment_path
		)
	)

	if not movement_assigned:
		return false

	if work_kind == PLAYER_WORK_KIND_DELIVERY:
		haul["phase"] = (
			CityCitizens.CITY_CITIZEN_HAUL_PHASE_TRAVELING_TO_SOURCE
		)
		haul["source_tile"] = raw_target_tile

		var haul_set: bool = (
			CityCitizenTaskRuntimeSystem.set_city_citizen_current_haul(
				citizen_id,
				haul
			)
			if city_state == null
			else CityCitizenTaskRuntimeSystem.set_city_citizen_current_haul_for_city_state(
				city_state,
				citizen_id,
				haul
			)
		)

		if not haul_set:
			return false

	return _set_labor_task_phase(
		city_state,
		citizen_id,
		CityCitizens.CITY_CITIZEN_TASK_PHASE_TRAVELING
	)


static func _make_construction_rebalance_restore_state(
	current_task: Dictionary,
	citizen: Dictionary
) -> Dictionary:
	var restore_candidate := (
		_make_construction_rebalance_restore_candidate(current_task)
	)

	if restore_candidate.is_empty():
		return {}

	return {
		"candidate": restore_candidate,
		"task": current_task.duplicate(true),
		"remaining_movement_path": (
			_get_remaining_citizen_movement_path(citizen)
		),
	}


static func _restore_construction_rebalance_assignment(
	citizen_id: int,
	restore_state: Dictionary
) -> bool:
	var raw_candidate = restore_state.get("candidate", {})
	var raw_task = restore_state.get("task", {})

	if not raw_candidate is Dictionary or not raw_task is Dictionary:
		return false

	var restore_candidate: Dictionary = raw_candidate
	var task: Dictionary = raw_task

	if (
		restore_candidate.is_empty()
		or task.is_empty()
		or not CityWorkSystem.assign_player_job(
			citizen_id,
			restore_candidate
		)
	):
		return false

	var raw_target_tile = task.get(
		"target_tile",
		CityCitizens.INVALID_CITY_TILE_POSITION
	)

	if (
		raw_target_tile is Vector2i
		and not CityCitizenTaskRuntimeSystem.set_city_citizen_task_activity_state({
			"citizen_id": citizen_id,
			"target_tile": raw_target_tile,
			"previous_target_tile": task.get(
				"previous_target_tile",
				CityCitizens.INVALID_CITY_TILE_POSITION
			),
			"next_action_world_minute": int(
				task.get(
					"next_action_world_minute",
					CityCitizens.INVALID_CITY_CITIZEN_TASK_ACTION_WORLD_MINUTE
				)
			),
			"relocation_count": int(task.get("relocation_count", 0)),
		})
	):
		return false

	var raw_remaining_path = restore_state.get(
		"remaining_movement_path",
		[]
	)

	if (
		raw_remaining_path is Array
		and raw_remaining_path.size() > 1
		and not CityCitizenMovementRuntimeSystem.assign_city_citizen_movement_order(
			citizen_id,
			raw_remaining_path
		)
	):
		CityCitizenTaskRuntimeSystem.set_city_citizen_task_phase(
			citizen_id,
			CityCitizens.CITY_CITIZEN_TASK_PHASE_PENDING
		)
		return false

	var restored_phase := str(
		task.get(
			"phase",
			CityCitizens.CITY_CITIZEN_TASK_PHASE_PENDING
		)
	)

	if (
		restored_phase == CityCitizens.CITY_CITIZEN_TASK_PHASE_TRAVELING
		and (
			not raw_remaining_path is Array
			or raw_remaining_path.size() <= 1
		)
	):
		restored_phase = CityCitizens.CITY_CITIZEN_TASK_PHASE_PENDING

	return CityCitizenTaskRuntimeSystem.set_city_citizen_task_phase(
		citizen_id,
		restored_phase
	)


static func _make_construction_rebalance_restore_candidate(
	current_task: Dictionary
) -> Dictionary:
	var work_order_id := int(current_task.get("work_order_id", -1))
	var job_id := str(current_task.get("job_id", ""))

	if work_order_id <= 0 or job_id.is_empty():
		return {}

	match str(current_task.get("kind", "")):
		CityCitizens.CITY_CITIZEN_TASK_KIND_CONSTRUCTION:
			var raw_target_tile = current_task.get(
				"target_tile",
				CityCitizens.INVALID_CITY_TILE_POSITION
			)

			if not raw_target_tile is Vector2i:
				return {}

			return {
				"player_work_kind": PLAYER_WORK_KIND_LABOR,
				"construction_site_id": int(
					current_task.get("target_object_id", -1)
				),
				"target_tile": raw_target_tile,
				"work_order_id": work_order_id,
				"job_id": job_id,
			}

		CityCitizens.CITY_CITIZEN_TASK_KIND_PLAYER_COMMAND:
			var command := CityWorkSystem.get_city_player_command_by_id(
				int(current_task.get("target_object_id", -1))
			)

			if command.is_empty():
				return {}

			return {
				"player_work_kind": "command",
				"id": int(command.get("id", -1)),
				"work_order_id": work_order_id,
				"job_id": job_id,
			}

	return {}


static func citizen_task_is_interruptible_construction(
	citizen_id: int
) -> bool:
	return _citizen_task_is_interruptible_construction(null, citizen_id)


static func citizen_task_is_interruptible_construction_for_city_state(
	city_state: CitySettlementSimulationState,
	citizen_id: int
) -> bool:
	return _citizen_task_is_interruptible_construction(city_state, citizen_id)


static func _citizen_task_is_interruptible_construction(
	city_state: CitySettlementSimulationState,
	citizen_id: int
) -> bool:
	var current_task: Dictionary = (
		CityCitizenTaskRuntimeSystem.get_city_citizen_current_task(citizen_id)
		if city_state == null
		else CityCitizenTaskRuntimeSystem.get_city_citizen_current_task_for_city_state(
			city_state,
			citizen_id
		)
	)

	match str(current_task.get("kind", "")):
		CityCitizens.CITY_CITIZEN_TASK_KIND_CONSTRUCTION:
			return true

		CityCitizens.CITY_CITIZEN_TASK_KIND_PLAYER_COMMAND:
			return CityWorkSystem.city_player_command_is_for_construction(
				(
					CityWorkSystem.get_city_player_command_by_id(
						int(current_task.get("target_object_id", -1))
					)
					if city_state == null
					else CityWorkSystem.get_city_player_command_by_id_for_city_state(
						city_state,
						int(current_task.get("target_object_id", -1))
					)
				)
			)

		CityCitizens.CITY_CITIZEN_TASK_KIND_HAUL:
			var haul: Dictionary = (
				CityCitizenTaskRuntimeSystem.get_city_citizen_current_haul(citizen_id)
				if city_state == null
				else CityCitizenTaskRuntimeSystem.get_city_citizen_current_haul_for_city_state(
					city_state,
					citizen_id
				)
			)
			var requester: Dictionary = haul.get("requester", {})

			return (
				str(
					haul.get(
						"reason",
						CityCitizens.CITY_CITIZEN_HAUL_REASON_NONE
					)
				)
				== CityCitizens.CITY_CITIZEN_HAUL_REASON_CONSTRUCTION_DELIVERY
				or str(
					requester.get(
						"kind",
						CityCitizens.CITY_CITIZEN_HAUL_ENDPOINT_KIND_NONE
					)
				)
				== CityCitizens.CITY_CITIZEN_HAUL_ENDPOINT_KIND_CONSTRUCTION_SITE
			)

	return false


static func interrupt_citizen_construction_for_food(
	citizen_id: int
) -> bool:
	return _interrupt_citizen_construction_for_food(null, citizen_id)


static func interrupt_citizen_construction_for_food_for_city_state(
	city_state: CitySettlementSimulationState,
	citizen_id: int
) -> bool:
	return _interrupt_citizen_construction_for_food(city_state, citizen_id)


static func _interrupt_citizen_construction_for_food(
	city_state: CitySettlementSimulationState,
	citizen_id: int
) -> bool:
	if not _citizen_task_is_interruptible_construction(city_state, citizen_id):
		return false

	var current_task: Dictionary = (
		CityCitizenTaskRuntimeSystem.get_city_citizen_current_task(citizen_id)
		if city_state == null
		else CityCitizenTaskRuntimeSystem.get_city_citizen_current_task_for_city_state(
			city_state,
			citizen_id
		)
	)

	if (
		str(current_task.get("kind", ""))
		== CityCitizens.CITY_CITIZEN_TASK_KIND_CONSTRUCTION
	):
		_release_labor_task(city_state, citizen_id)
		return true

	return (
		CitizenHaulingSystemScript
		.drop_citizen_haul_cargo_for_priority_interrupt(
			WorldPoliticalState.get_current_city_world(),
			citizen_id,
			CityCitizens.CITY_CITIZEN_TASK_SOURCE_PLAYER
		)
		if city_state == null
		else CitizenHaulingSystemScript.drop_citizen_haul_cargo_for_priority_interrupt_for_city_state(
			city_state,
			city_state.city_world,
			citizen_id,
			CityCitizens.CITY_CITIZEN_TASK_SOURCE_PLAYER
		)
	)



#endregion
