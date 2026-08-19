extends RefCounted
class_name CityLogisticsSystem

# File responsibility: Physical city logistics for the active CITY settlement.
# CityLogisticsState owns pile/reservation data; this system owns ground-pile
# mutation, haul endpoint accounting, reservation lifecycle, and related rules.
# Construction, citizens, food, and object storage remain owned by their current
# systems and are consulted through their existing APIs rather than absorbed here.

const CityCitizensScript = preload(
	"res://scripts/citizens/simulation/CityCitizens.gd"
)

const CITY_GROUND_PILE_CAPACITY: int = 20
const CITY_GROUND_PILE_MERGE_RADIUS_TILES: int = 2
const CITY_GROUND_DROP_RESERVATION_CAPACITY: int = 1_000_000


static func get_current_state() -> CityLogisticsState:
	return CityCitizenUnboundCompatibility.get_city_state().logistics_state


static func get_state_for_city_state(
	city_state: CitySettlementSimulationState
) -> CityLogisticsState:
	if city_state == null:
		return null

	return city_state.logistics_state


static func _state() -> CityLogisticsState:
	return get_current_state()


static func city_surface_feature_blocks_ground_pile(
	surface_feature: String
) -> bool:
	return surface_feature == WorldData.CITY_SURFACE_FEATURE_TREE

static func _mark_city_ground_piles_changed() -> void:
	_state().ground_pile_version += 1

static func _mark_city_haul_reservations_changed() -> void:
	_state().haul_reservation_version += 1
	CityCitizenTaskRuntimeSystem.mark_city_citizen_task_changed()

static func make_city_construction_site_haul_endpoint(
	site_id: int
) -> Dictionary:
	if site_id <= 0:
		return CityCitizens.make_city_citizen_haul_endpoint()

	return CityCitizens.make_city_citizen_haul_endpoint({
		"kind": CityCitizens.CITY_CITIZEN_HAUL_ENDPOINT_KIND_CONSTRUCTION_SITE,
		"id": site_id,
	})

static func get_city_ground_pile_construction_site_id(
	ground_pile: Dictionary
) -> int:
	return maxi(
		int(ground_pile.get("construction_site_id", -1)),
		-1
	)

static func city_ground_pile_is_construction_reserved(
	ground_pile: Dictionary
) -> bool:
	return get_city_ground_pile_construction_site_id(ground_pile) > 0

static func make_city_citizen_haul_endpoint(
	object_id: int
) -> Dictionary:
	if object_id <= 0:
		return CityCitizens.make_city_citizen_haul_endpoint()

	return CityCitizens.make_city_citizen_haul_endpoint({
		"kind": (
			CityCitizens.CITY_CITIZEN_HAUL_ENDPOINT_KIND_CITY_OBJECT_CONTAINER
		),
		"id": object_id,
	})

static func make_city_ground_pile_haul_endpoint(
	ground_pile_id: int
) -> Dictionary:
	if ground_pile_id <= 0:
		return CityCitizens.make_city_citizen_haul_endpoint()

	return CityCitizens.make_city_citizen_haul_endpoint({
		"kind": CityCitizens.CITY_CITIZEN_HAUL_ENDPOINT_KIND_GROUND_PILE,
		"id": ground_pile_id,
	})

static func make_city_ground_tile_haul_endpoint(
	tile_position: Vector2i,
	excluded_ground_pile_ids: Array[int] = []
) -> Dictionary:
	if (
		tile_position == CityCitizens.INVALID_CITY_TILE_POSITION
		or not can_city_ground_pile_exist_at_tile(
			CityCitizenUnboundCompatibility.get_city_state().city_world,
			tile_position
		)
	):
		return CityCitizens.make_city_citizen_haul_endpoint()

	return CityCitizens.make_city_citizen_haul_endpoint({
		"kind": CityCitizens.CITY_CITIZEN_HAUL_ENDPOINT_KIND_GROUND_TILE,
		"id": -1,
		"tile_position": tile_position,
		"excluded_ground_pile_ids": excluded_ground_pile_ids,
	})

static func city_citizen_haul_endpoints_match(
	endpoint_a: Dictionary,
	endpoint_b: Dictionary
) -> bool:
	var kind_a := str(
			endpoint_a.get(
				"kind",
				CityCitizens.CITY_CITIZEN_HAUL_ENDPOINT_KIND_NONE
			)
		)
	var kind_b := str(
			endpoint_b.get(
				"kind",
				CityCitizens.CITY_CITIZEN_HAUL_ENDPOINT_KIND_NONE
			)
		)

	if kind_a != kind_b:
		return false

	if kind_a == CityCitizens.CITY_CITIZEN_HAUL_ENDPOINT_KIND_GROUND_TILE:
		return endpoint_a.get("tile_position") == endpoint_b.get(
			"tile_position"
		)

	return int(endpoint_a.get("id", -1)) == int(
		endpoint_b.get("id", -1)
	)

static func rebuild_city_ground_pile_index() -> void:
	_state().ground_pile_index_by_id.clear()

	for pile_index in range(_state().ground_piles.size()):
		var raw_ground_pile = _state().ground_piles[pile_index]

		if not raw_ground_pile is Dictionary:
			continue

		var ground_pile: Dictionary = raw_ground_pile
		var ground_pile_id := int(ground_pile.get("id", -1))

		if ground_pile_id <= 0:
			continue

		_state().ground_pile_index_by_id[ground_pile_id] = pile_index

static func get_city_ground_pile_index_by_id(
	ground_pile_id: int
) -> int:
	if ground_pile_id <= 0:
		return -1

	if not _state().ground_pile_index_by_id.has(ground_pile_id):
		return -1

	var pile_index := int(
		_state().ground_pile_index_by_id[ground_pile_id]
	)

	if pile_index < 0 or pile_index >= _state().ground_piles.size():
		return -1

	var raw_ground_pile = _state().ground_piles[pile_index]

	if not raw_ground_pile is Dictionary:
		return -1

	if int(raw_ground_pile.get("id", -1)) != ground_pile_id:
		return -1

	return pile_index

static func get_city_ground_pile_by_id(
	ground_pile_id: int
) -> Dictionary:
	return get_city_ground_pile_by_id_for_city_state(
		_get_compatibility_city_state(),
		ground_pile_id
	)


static func get_city_ground_pile_by_id_for_city_state(
	city_state: CitySettlementSimulationState,
	ground_pile_id: int
) -> Dictionary:
	var logistics_state := get_state_for_city_state(city_state)

	if logistics_state == null or ground_pile_id <= 0:
		return {}

	var pile_index := int(
		logistics_state.ground_pile_index_by_id.get(ground_pile_id, -1)
	)

	if pile_index < 0 or pile_index >= logistics_state.ground_piles.size():
		return {}

	var raw_ground_pile = logistics_state.ground_piles[pile_index]

	if (
		not raw_ground_pile is Dictionary
		or int(raw_ground_pile.get("id", -1)) != ground_pile_id
	):
		return {}

	return raw_ground_pile.duplicate(true)

static func get_city_ground_pile_snapshot() -> Array:
	return get_city_ground_pile_snapshot_for_city_state(
		_get_compatibility_city_state()
	)


static func get_city_ground_pile_snapshot_for_city_state(
	city_state: CitySettlementSimulationState
) -> Array:
	var logistics_state := get_state_for_city_state(city_state)
	return (
		logistics_state.ground_piles.duplicate(true)
		if logistics_state != null
		else []
	)

static func get_city_ground_piles_at_tile(
	tile_position: Vector2i
) -> Array:
	var matching_piles: Array = []

	for raw_ground_pile in _state().ground_piles:
		if not raw_ground_pile is Dictionary:
			continue

		var ground_pile: Dictionary = raw_ground_pile

		if (
			ground_pile.get(
				"tile_position",
				CityCitizens.INVALID_CITY_TILE_POSITION
			)
			!= tile_position
		):
			continue

		matching_piles.append(ground_pile.duplicate(true))

	matching_piles.sort_custom(
		func(pile_a: Dictionary, pile_b: Dictionary) -> bool:
			return int(pile_a.get("id", -1)) < int(
				pile_b.get("id", -1)
			)
	)
	return matching_piles

static func has_city_ground_pile_at_tile(
	tile_position: Vector2i
) -> bool:
	return has_city_ground_pile_at_tile_for_city_state(
		_get_compatibility_city_state(),
		tile_position
	)


static func has_city_ground_pile_at_tile_for_city_state(
	city_state: CitySettlementSimulationState,
	tile_position: Vector2i
) -> bool:
	return _has_city_ground_pile_at_tile(
		get_state_for_city_state(city_state),
		tile_position
	)


static func _has_city_ground_pile_at_tile(
	logistics_state: CityLogisticsState,
	tile_position: Vector2i
) -> bool:
	if logistics_state == null:
		return false

	for raw_ground_pile in logistics_state.ground_piles:
		if not raw_ground_pile is Dictionary:
			continue

		var ground_pile: Dictionary = raw_ground_pile

		if (
			ground_pile.get(
				"tile_position",
				CityCitizens.INVALID_CITY_TILE_POSITION
			)
			== tile_position
			and int(ground_pile.get("amount", 0)) > 0
		):
			return true

	return false

static func can_city_ground_pile_exist_at_tile(
	city_world: WorldData,
	tile_position: Vector2i
) -> bool:
	return can_city_ground_pile_exist_at_tile_for_city_state(
		_get_compatibility_city_state(),
		city_world,
		tile_position
	)


static func can_city_ground_pile_exist_at_tile_for_city_state(
	city_state: CitySettlementSimulationState,
	city_world: WorldData,
	tile_position: Vector2i
) -> bool:
	return _can_city_ground_pile_exist_at_tile(
		city_world,
		tile_position,
		city_state
	)


static func _can_city_ground_pile_exist_at_tile(
	city_world: WorldData,
	tile_position: Vector2i,
	city_state
) -> bool:
	if city_world == null:
		return false

	if not city_world.is_in_bounds(tile_position.x, tile_position.y):
		return false

	var has_object := (
		CityObjectSystem.has_city_object_at_tile(tile_position)
		if city_state == null
		else CityObjectSystem.has_city_object_at_tile_for_city_state(
			city_state,
			tile_position
		)
	)

	if has_object:
		return false

	var tile := city_world.get_tile_for_internal_read(
		tile_position.x,
		tile_position.y
	)

	return (
		bool(tile.get("is_land", false))
		and str(tile.get("terrain", CityObjectCatalog.TERRAIN_WATER))
		!= CityObjectCatalog.TERRAIN_WATER
		and str(tile.get("terrain", CityObjectCatalog.TERRAIN_WATER))
		!= WorldData.TERRAIN_MOUNTAIN
		and not city_surface_feature_blocks_ground_pile(
			WorldData.get_city_surface_feature(tile)
		)
	)

static func get_city_ground_pile_free_space(
	ground_pile: Dictionary
) -> int:
	if ground_pile.is_empty():
		return 0

	return maxi(
		CITY_GROUND_PILE_CAPACITY
		- maxi(int(ground_pile.get("amount", 0)), 0),
		0
	)

static func get_city_ground_pile_tile_distance_squared(
	first_tile: Vector2i,
	second_tile: Vector2i
) -> int:
	var offset := first_tile - second_tile
	return offset.x * offset.x + offset.y * offset.y

static func _find_city_ground_pile_merge_target_index(
	tile_position: Vector2i,
	resource: String,
	construction_site_id: int = -1,
	excluded_ground_pile_ids: Array[int] = []
) -> int:
	var best_index := -1
	var merge_radius_squared := (
		CITY_GROUND_PILE_MERGE_RADIUS_TILES
		* CITY_GROUND_PILE_MERGE_RADIUS_TILES
	)
	var best_distance_squared := merge_radius_squared + 1
	var best_id := 2147483647

	for pile_index in range(_state().ground_piles.size()):
		var raw_ground_pile = _state().ground_piles[pile_index]

		if not raw_ground_pile is Dictionary:
			continue

		var ground_pile: Dictionary = raw_ground_pile
		var ground_pile_id := int(ground_pile.get("id", -1))

		if (
			excluded_ground_pile_ids.has(ground_pile_id)
			or
			str(
				ground_pile.get("resource_type", WorldData.RESOURCE_NONE)
			)
			!= resource
			or get_city_ground_pile_construction_site_id(
				ground_pile
			) != construction_site_id
			or get_city_ground_pile_free_space(ground_pile) <= 0
		):
			continue

		var raw_pile_tile = ground_pile.get(
			"tile_position",
			CityCitizens.INVALID_CITY_TILE_POSITION
		)

		if not raw_pile_tile is Vector2i:
			continue

		var pile_tile: Vector2i = raw_pile_tile
		var distance_squared := (
			get_city_ground_pile_tile_distance_squared(
				tile_position,
				pile_tile
			)
		)

		if distance_squared > merge_radius_squared:
			continue

		if (
			distance_squared < best_distance_squared
			or (
				distance_squared == best_distance_squared
				and ground_pile_id < best_id
			)
		):
			best_index = pile_index
			best_distance_squared = distance_squared
			best_id = ground_pile_id

	return best_index

static func add_resource_to_city_ground_piles_with_result(
	values: Dictionary
) -> Dictionary:
	return add_resource_to_city_ground_piles_with_result_for_city_state(
		_get_compatibility_city_state(),
		values
	)


static func add_resource_to_city_ground_piles_with_result_for_city_state(
	city_state: CitySettlementSimulationState,
	values: Dictionary
) -> Dictionary:
	var result := {
		"added_amount": 0,
		"placements": [],
	}
	var logistics_state := get_state_for_city_state(city_state)

	if logistics_state == null or city_state.city_world == null:
		return result

	var tile_position: Vector2i = values.get(
		"tile_position",
		CityCitizens.INVALID_CITY_TILE_POSITION
	)
	var resource := str(values.get("resource", WorldData.RESOURCE_NONE))
	var amount_delta := int(values.get("amount_delta", 0))
	var construction_site_id := int(values.get("construction_site_id", -1))
	var excluded_ground_pile_ids: Array[int] = []
	excluded_ground_pile_ids.assign(values.get("excluded_ground_pile_ids", []))

	if amount_delta <= 0 or not CityResourceCatalog.is_city_resource_type(resource):
		return result

	if (
		construction_site_id > 0
		and CityConstructionSystem.get_city_construction_site_by_id_for_city_state(
			city_state,
			construction_site_id
		).is_empty()
	):
		return result

	if not can_city_ground_pile_exist_at_tile_for_city_state(
		city_state,
		city_state.city_world,
		tile_position
	):
		return result

	var remaining_amount := amount_delta
	var placements: Array = []
	var merge_target_index := -1
	var merge_radius_squared := (
		CITY_GROUND_PILE_MERGE_RADIUS_TILES
		* CITY_GROUND_PILE_MERGE_RADIUS_TILES
	)
	var best_distance_squared := merge_radius_squared + 1
	var best_id := 2147483647

	for pile_index in range(logistics_state.ground_piles.size()):
		var raw_ground_pile = logistics_state.ground_piles[pile_index]

		if not raw_ground_pile is Dictionary:
			continue

		var ground_pile: Dictionary = raw_ground_pile
		var ground_pile_id := int(ground_pile.get("id", -1))

		if (
			excluded_ground_pile_ids.has(ground_pile_id)
			or str(ground_pile.get("resource_type", WorldData.RESOURCE_NONE))
			!= resource
			or get_city_ground_pile_construction_site_id(ground_pile)
			!= construction_site_id
			or get_city_ground_pile_free_space(ground_pile) <= 0
		):
			continue

		var raw_pile_tile = ground_pile.get(
			"tile_position",
			CityCitizens.INVALID_CITY_TILE_POSITION
		)

		if not raw_pile_tile is Vector2i:
			continue

		var distance_squared := get_city_ground_pile_tile_distance_squared(
			tile_position,
			raw_pile_tile
		)

		if distance_squared > merge_radius_squared:
			continue

		if (
			distance_squared < best_distance_squared
			or (
				distance_squared == best_distance_squared
				and ground_pile_id < best_id
			)
		):
			merge_target_index = pile_index
			best_distance_squared = distance_squared
			best_id = ground_pile_id

	if merge_target_index >= 0:
		var merge_target: Dictionary = logistics_state.ground_piles[
			merge_target_index
		]
		var merged_amount := mini(
			remaining_amount,
			get_city_ground_pile_free_space(merge_target)
		)

		if merged_amount > 0:
			merge_target["amount"] = (
				maxi(int(merge_target.get("amount", 0)), 0)
				+ merged_amount
			)
			logistics_state.ground_piles[merge_target_index] = merge_target
			placements.append({
				"ground_pile_id": int(merge_target.get("id", -1)),
				"amount": merged_amount,
			})
			remaining_amount -= merged_amount

	while remaining_amount > 0:
		var pile_amount := mini(remaining_amount, CITY_GROUND_PILE_CAPACITY)
		var ground_pile := {
			"id": logistics_state.next_ground_pile_id,
			"tile_position": tile_position,
			"resource_type": resource,
			"amount": pile_amount,
		}

		if construction_site_id > 0:
			ground_pile["construction_site_id"] = construction_site_id

		logistics_state.next_ground_pile_id += 1
		logistics_state.ground_piles.append(ground_pile)
		logistics_state.ground_pile_index_by_id[int(ground_pile["id"])] = (
			logistics_state.ground_piles.size() - 1
		)
		placements.append({
			"ground_pile_id": int(ground_pile["id"]),
			"amount": pile_amount,
		})
		remaining_amount -= pile_amount

	result["added_amount"] = amount_delta
	result["placements"] = placements
	logistics_state.ground_pile_version += 1
	return result

static func add_resource_to_city_ground_pile(
	tile_position: Vector2i,
	resource: String,
	amount_delta: int,
	construction_site_id: int = -1
) -> int:
	var result := add_resource_to_city_ground_piles_with_result({
		"tile_position": tile_position,
		"resource": resource,
		"amount_delta": amount_delta,
		"construction_site_id": construction_site_id,
	})
	return int(result.get("added_amount", 0))

static func rollback_city_ground_pile_additions(
	resource: String,
	raw_placements
) -> bool:
	return rollback_city_ground_pile_additions_for_city_state(
		_get_compatibility_city_state(),
		resource,
		raw_placements
	)


static func rollback_city_ground_pile_additions_for_city_state(
	city_state: CitySettlementSimulationState,
	resource: String,
	raw_placements
) -> bool:
	var logistics_state := get_state_for_city_state(city_state)

	if (
		logistics_state == null
		or not CityResourceCatalog.is_city_resource_type(resource)
		or not raw_placements is Array
	):
		return false

	var placements: Array = raw_placements

	for placement_index in range(placements.size() - 1, -1, -1):
		var raw_placement = placements[placement_index]

		if not raw_placement is Dictionary:
			return false

		var ground_pile_id := int(raw_placement.get("ground_pile_id", -1))
		var amount := maxi(int(raw_placement.get("amount", 0)), 0)
		var pile_index := int(
			logistics_state.ground_pile_index_by_id.get(ground_pile_id, -1)
		)

		if (
			ground_pile_id <= 0
			or amount <= 0
			or pile_index < 0
			or pile_index >= logistics_state.ground_piles.size()
		):
			return false

		var raw_ground_pile = logistics_state.ground_piles[pile_index]

		if (
			not raw_ground_pile is Dictionary
			or str(
				raw_ground_pile.get(
					"resource_type",
					WorldData.RESOURCE_NONE
				)
			) != resource
			or int(raw_ground_pile.get("amount", 0)) < amount
		):
			return false

		var remaining_amount := int(raw_ground_pile.get("amount", 0)) - amount

		if remaining_amount > 0:
			raw_ground_pile["amount"] = remaining_amount
			logistics_state.ground_piles[pile_index] = raw_ground_pile
		else:
			logistics_state.ground_piles.remove_at(pile_index)
			logistics_state.ground_pile_index_by_id.clear()

			for rebuild_index in range(logistics_state.ground_piles.size()):
				var raw_remaining = logistics_state.ground_piles[rebuild_index]
				if raw_remaining is Dictionary:
					logistics_state.ground_pile_index_by_id[
						int(raw_remaining.get("id", -1))
					] = rebuild_index

		logistics_state.ground_pile_version += 1

	return true

static func get_city_ground_pile_resource_amount(
	ground_pile: Dictionary,
	resource: String
) -> int:
	if ground_pile.is_empty():
		return 0

	if str(
		ground_pile.get("resource_type", WorldData.RESOURCE_NONE)
	) != resource:
		return 0

	return maxi(int(ground_pile.get("amount", 0)), 0)

static func remove_resource_from_city_ground_pile(
	ground_pile_id: int,
	resource: String,
	requested_amount: int,
	reservation_id: int = CityCitizens.INVALID_CITY_CITIZEN_HAUL_RESERVATION_ID
) -> int:
	return remove_resource_from_city_ground_pile_for_city_state(
		_get_compatibility_city_state(),
		ground_pile_id,
		resource,
		requested_amount,
		reservation_id
	)


static func remove_resource_from_city_ground_pile_for_city_state(
	city_state: CitySettlementSimulationState,
	ground_pile_id: int,
	resource: String,
	requested_amount: int,
	reservation_id: int = CityCitizens.INVALID_CITY_CITIZEN_HAUL_RESERVATION_ID
) -> int:
	var logistics_state := get_state_for_city_state(city_state)

	if logistics_state == null or requested_amount <= 0:
		return 0

	var pile_index := int(
		logistics_state.ground_pile_index_by_id.get(ground_pile_id, -1)
	)

	if pile_index < 0 or pile_index >= logistics_state.ground_piles.size():
		return 0

	var raw_ground_pile = logistics_state.ground_piles[pile_index]

	if not raw_ground_pile is Dictionary:
		return 0

	var ground_pile: Dictionary = raw_ground_pile
	var current_amount := get_city_ground_pile_resource_amount(
		ground_pile,
		resource
	)

	if current_amount <= 0:
		return 0

	var endpoint := make_city_ground_pile_haul_endpoint(ground_pile_id)
	var other_reserved_amount := (
		get_city_haul_endpoint_source_reserved_amount_for_city_state(
			city_state,
			endpoint,
			resource,
			reservation_id
		)
	)
	var removable_amount := maxi(current_amount - other_reserved_amount, 0)

	if reservation_id > 0:
		var reservation := get_city_haul_reservation_for_city_state(
			city_state,
			reservation_id
		)

		if (
			reservation.is_empty()
			or not city_citizen_haul_endpoints_match(
				reservation.get("source", {}),
				endpoint
			)
			or str(reservation.get("resource_type", WorldData.RESOURCE_NONE))
			!= resource
		):
			return 0

		removable_amount = mini(
			removable_amount,
			maxi(int(reservation.get("source_reserved_amount", 0)), 0)
		)

	var removed_amount := mini(requested_amount, removable_amount)

	if removed_amount <= 0:
		return 0

	var final_amount := current_amount - removed_amount

	if final_amount > 0:
		ground_pile["amount"] = final_amount
		logistics_state.ground_piles[pile_index] = ground_pile
	else:
		logistics_state.ground_piles.remove_at(pile_index)
		logistics_state.ground_pile_index_by_id.clear()

		for rebuild_index in range(logistics_state.ground_piles.size()):
			var raw_remaining = logistics_state.ground_piles[rebuild_index]
			if raw_remaining is Dictionary:
				logistics_state.ground_pile_index_by_id[
					int(raw_remaining.get("id", -1))
				] = rebuild_index

	logistics_state.ground_pile_version += 1
	return removed_amount

static func reserve_city_ground_pile_for_construction(
	ground_pile_id: int,
	site_id: int,
	requested_amount: int
) -> int:
	return reserve_city_ground_pile_for_construction_for_city_state(
		_get_compatibility_city_state(),
		ground_pile_id,
		site_id,
		requested_amount
	)


static func reserve_city_ground_pile_for_construction_for_city_state(
	city_state: CitySettlementSimulationState,
	ground_pile_id: int,
	site_id: int,
	requested_amount: int
) -> int:
	var logistics_state := get_state_for_city_state(city_state)
	var site := CityConstructionSystem.get_city_construction_site_by_id_for_city_state(
		city_state,
		site_id
	)
	var pile_index := int(
		logistics_state.ground_pile_index_by_id.get(ground_pile_id, -1)
	) if logistics_state != null else -1

	if (
		logistics_state == null
		or site.is_empty()
		or pile_index < 0
		or pile_index >= logistics_state.ground_piles.size()
		or requested_amount <= 0
	):
		return 0

	var ground_pile: Dictionary = logistics_state.ground_piles[pile_index]

	if city_ground_pile_is_construction_reserved(ground_pile):
		return 0

	var raw_tile_position = ground_pile.get(
		"tile_position",
		CityCitizens.INVALID_CITY_TILE_POSITION
	)

	if (
		not raw_tile_position is Vector2i
		or not site.get("footprint_tiles", []).has(raw_tile_position)
	):
		return 0

	var resource := str(
		ground_pile.get("resource_type", WorldData.RESOURCE_NONE)
	)
	var current_amount := get_city_ground_pile_resource_amount(
		ground_pile,
		resource
	)
	var endpoint := make_city_ground_pile_haul_endpoint(ground_pile_id)
	var source_reserved_amount := (
		get_city_haul_endpoint_source_reserved_amount_for_city_state(
			city_state,
			endpoint,
			resource
		)
	)
	var reservable_amount := mini(
		requested_amount,
		maxi(current_amount - source_reserved_amount, 0)
	)

	if reservable_amount <= 0:
		return 0

	if reservable_amount == current_amount:
		ground_pile["construction_site_id"] = site_id
		logistics_state.ground_piles[pile_index] = ground_pile
		logistics_state.ground_pile_version += 1
		return reservable_amount

	ground_pile["amount"] = current_amount - reservable_amount
	logistics_state.ground_piles[pile_index] = ground_pile
	var add_result := add_resource_to_city_ground_piles_with_result_for_city_state(
		city_state,
		{
			"tile_position": raw_tile_position,
			"resource": resource,
			"amount_delta": reservable_amount,
			"construction_site_id": site_id,
		}
	)

	if int(add_result.get("added_amount", 0)) != reservable_amount:
		ground_pile["amount"] = current_amount
		logistics_state.ground_piles[pile_index] = ground_pile
		logistics_state.ground_pile_version += 1
		return 0

	logistics_state.ground_pile_version += 1
	return reservable_amount


static func release_city_construction_site_materials(site_id: int) -> int:
	return release_city_construction_site_materials_for_city_state(
		_get_compatibility_city_state(),
		site_id
	)


static func release_city_construction_site_materials_for_city_state(
	city_state: CitySettlementSimulationState,
	site_id: int
) -> int:
	return _release_construction_site_materials(city_state, site_id)


static func _release_construction_site_materials(
	city_state: CitySettlementSimulationState,
	site_id: int
) -> int:
	var logistics_state: CityLogisticsState = (
		_state()
		if city_state == null
		else get_state_for_city_state(city_state)
	)

	if logistics_state == null or site_id <= 0:
		return 0

	var released_amount := 0
	var released_pile_ids: Array[int] = []
	var released_pile_id_lookup: Dictionary = {}

	for pile_index in range(logistics_state.ground_piles.size()):
		var raw_ground_pile = logistics_state.ground_piles[pile_index]

		if not raw_ground_pile is Dictionary:
			continue

		var ground_pile: Dictionary = raw_ground_pile

		if get_city_ground_pile_construction_site_id(ground_pile) != site_id:
			continue

		var ground_pile_id := int(ground_pile.get("id", -1))

		if ground_pile_id <= 0:
			continue

		released_amount += maxi(int(ground_pile.get("amount", 0)), 0)
		ground_pile.erase("construction_site_id")
		logistics_state.ground_piles[pile_index] = ground_pile
		released_pile_ids.append(ground_pile_id)
		released_pile_id_lookup[ground_pile_id] = true

	_release_construction_material_reservations(
		city_state,
		site_id,
		released_pile_id_lookup
	)

	if released_pile_ids.is_empty():
		return 0

	released_pile_ids.sort()
	_coalesce_released_construction_piles(
		logistics_state,
		released_pile_ids,
		released_pile_id_lookup
	)
	_rebuild_city_ground_pile_index_for_state(logistics_state)
	logistics_state.ground_pile_version += 1
	return released_amount


static func _release_construction_material_reservations(
	city_state: CitySettlementSimulationState,
	site_id: int,
	released_pile_id_lookup: Dictionary
) -> void:
	var reservation_snapshot: Array = (
		get_city_haul_reservation_snapshot()
		if city_state == null
		else get_city_haul_reservation_snapshot_for_city_state(city_state)
	)
	var reservation_ids: Array[int] = []

	for raw_reservation in reservation_snapshot:
		if not raw_reservation is Dictionary:
			continue

		var reservation: Dictionary = raw_reservation

		if (
			_haul_endpoint_references_construction_release(
				reservation.get("source", {}),
				site_id,
				released_pile_id_lookup
			)
			or _haul_endpoint_references_construction_release(
				reservation.get("destination", {}),
				site_id,
				released_pile_id_lookup
			)
		):
			reservation_ids.append(int(reservation.get("id", -1)))

	reservation_ids.sort()

	for reservation_id in reservation_ids:
		if city_state == null:
			release_city_haul_reservation(reservation_id)
		else:
			release_city_haul_reservation_for_city_state(
				city_state,
				reservation_id
			)


static func _haul_endpoint_references_construction_release(
	raw_endpoint,
	site_id: int,
	released_pile_id_lookup: Dictionary
) -> bool:
	if not raw_endpoint is Dictionary:
		return false

	var endpoint: Dictionary = raw_endpoint
	var endpoint_kind := str(
		endpoint.get(
			"kind",
			CityCitizens.CITY_CITIZEN_HAUL_ENDPOINT_KIND_NONE
		)
	)
	var endpoint_id := int(endpoint.get("id", -1))

	return (
		(
			endpoint_kind
			== CityCitizens.CITY_CITIZEN_HAUL_ENDPOINT_KIND_CONSTRUCTION_SITE
			and endpoint_id == site_id
		)
		or (
			endpoint_kind
			== CityCitizens.CITY_CITIZEN_HAUL_ENDPOINT_KIND_GROUND_PILE
			and released_pile_id_lookup.has(endpoint_id)
		)
	)


static func _coalesce_released_construction_piles(
	logistics_state: CityLogisticsState,
	released_pile_ids: Array[int],
	released_pile_id_lookup: Dictionary
) -> void:
	for source_id in released_pile_ids:
		var source_index := int(
			logistics_state.ground_pile_index_by_id.get(source_id, -1)
		)

		if (
			source_index < 0
			or source_index >= logistics_state.ground_piles.size()
		):
			continue

		var raw_source = logistics_state.ground_piles[source_index]

		if not raw_source is Dictionary:
			continue

		var source: Dictionary = raw_source
		var target_index := _find_released_construction_merge_target_index(
			logistics_state,
			source,
			released_pile_id_lookup
		)

		if target_index < 0:
			continue

		var target: Dictionary = logistics_state.ground_piles[target_index]
		var moved_amount := mini(
			maxi(int(source.get("amount", 0)), 0),
			get_city_ground_pile_free_space(target)
		)

		if moved_amount <= 0:
			continue

		target["amount"] = maxi(int(target.get("amount", 0)), 0) + moved_amount
		source["amount"] = maxi(int(source.get("amount", 0)), 0) - moved_amount
		logistics_state.ground_piles[target_index] = target

		if int(source.get("amount", 0)) > 0:
			logistics_state.ground_piles[source_index] = source
		else:
			logistics_state.ground_piles.remove_at(source_index)
			_rebuild_city_ground_pile_index_for_state(logistics_state)


static func _find_released_construction_merge_target_index(
	logistics_state: CityLogisticsState,
	source: Dictionary,
	released_pile_id_lookup: Dictionary
) -> int:
	var source_id := int(source.get("id", -1))
	var source_resource := str(
		source.get("resource_type", WorldData.RESOURCE_NONE)
	)
	var raw_source_tile = source.get(
		"tile_position",
		CityCitizens.INVALID_CITY_TILE_POSITION
	)

	if (
		source_id <= 0
		or not raw_source_tile is Vector2i
		or not CityResourceCatalog.is_city_resource_type(source_resource)
	):
		return -1

	var merge_radius_squared := (
		CITY_GROUND_PILE_MERGE_RADIUS_TILES
		* CITY_GROUND_PILE_MERGE_RADIUS_TILES
	)
	var best_index := -1
	var best_distance_squared := merge_radius_squared + 1
	var best_id := 2147483647

	for pile_index in range(logistics_state.ground_piles.size()):
		var raw_target = logistics_state.ground_piles[pile_index]

		if not raw_target is Dictionary:
			continue

		var target: Dictionary = raw_target
		var target_id := int(target.get("id", -1))

		if (
			target_id <= 0
			or target_id == source_id
			or city_ground_pile_is_construction_reserved(target)
			or str(target.get("resource_type", WorldData.RESOURCE_NONE))
			!= source_resource
			or get_city_ground_pile_free_space(target) <= 0
			or (
				released_pile_id_lookup.has(target_id)
				and target_id >= source_id
			)
		):
			continue

		var raw_target_tile = target.get(
			"tile_position",
			CityCitizens.INVALID_CITY_TILE_POSITION
		)

		if not raw_target_tile is Vector2i:
			continue

		var distance_squared := get_city_ground_pile_tile_distance_squared(
			raw_source_tile,
			raw_target_tile
		)

		if distance_squared > merge_radius_squared:
			continue

		if (
			distance_squared < best_distance_squared
			or (
				distance_squared == best_distance_squared
				and target_id < best_id
			)
		):
			best_index = pile_index
			best_distance_squared = distance_squared
			best_id = target_id

	return best_index


static func _rebuild_city_ground_pile_index_for_state(
	logistics_state: CityLogisticsState
) -> void:
	logistics_state.ground_pile_index_by_id.clear()

	for pile_index in range(logistics_state.ground_piles.size()):
		var raw_ground_pile = logistics_state.ground_piles[pile_index]

		if not raw_ground_pile is Dictionary:
			continue

		var ground_pile_id := int(raw_ground_pile.get("id", -1))

		if ground_pile_id > 0:
			logistics_state.ground_pile_index_by_id[ground_pile_id] = pile_index

static func get_total_city_ground_pile_resource_amount(
	resource: String
) -> int:
	var total_amount := 0

	for raw_ground_pile in _state().ground_piles:
		if not raw_ground_pile is Dictionary:
			continue

		total_amount += get_city_ground_pile_resource_amount(
			raw_ground_pile,
			resource
		)

	return total_amount

static func _get_city_haul_endpoint_key(
	endpoint: Dictionary
) -> String:
	var endpoint_kind := str(
		endpoint.get("kind", CityCitizens.CITY_CITIZEN_HAUL_ENDPOINT_KIND_NONE)
	)

	if endpoint_kind == CityCitizens.CITY_CITIZEN_HAUL_ENDPOINT_KIND_GROUND_TILE:
		var raw_tile = endpoint.get(
			"tile_position",
			CityCitizens.INVALID_CITY_TILE_POSITION
		)

		if raw_tile is Vector2i:
			return (
				endpoint_kind
				+ ":"
				+ str(raw_tile.x)
				+ ","
				+ str(raw_tile.y)
			)

	return (
		endpoint_kind
		+ ":"
		+ str(int(endpoint.get("id", -1)))
	)

static func _get_city_haul_source_reservation_key(
	endpoint: Dictionary,
	resource: String
) -> String:
	return _get_city_haul_endpoint_key(endpoint) + ":" + resource

static func _change_city_haul_reserved_source_amount(
	endpoint: Dictionary,
	resource: String,
	amount_delta: int
) -> void:
	_change_city_haul_reserved_source_amount_for_city_state(
		_get_compatibility_city_state(),
		endpoint,
		resource,
		amount_delta
	)

static func _change_city_haul_reserved_destination_amount(
	endpoint: Dictionary,
	amount_delta: int
) -> void:
	_change_city_haul_reserved_destination_amount_for_city_state(
		_get_compatibility_city_state(),
		endpoint,
		amount_delta
	)


static func _change_city_haul_reserved_source_amount_for_city_state(
	city_state: CitySettlementSimulationState,
	endpoint: Dictionary,
	resource: String,
	amount_delta: int
) -> void:
	var logistics_state := get_state_for_city_state(city_state)

	if logistics_state == null or amount_delta == 0:
		return

	var key := _get_city_haul_source_reservation_key(endpoint, resource)
	var final_amount := int(
		logistics_state.haul_source_reserved_amount_by_key.get(key, 0)
	) + amount_delta

	if final_amount > 0:
		logistics_state.haul_source_reserved_amount_by_key[key] = final_amount
	else:
		logistics_state.haul_source_reserved_amount_by_key.erase(key)


static func _change_city_haul_reserved_destination_amount_for_city_state(
	city_state: CitySettlementSimulationState,
	endpoint: Dictionary,
	amount_delta: int
) -> void:
	var logistics_state := get_state_for_city_state(city_state)

	if logistics_state == null or amount_delta == 0:
		return

	var key := _get_city_haul_endpoint_key(endpoint)
	var final_amount := int(
		logistics_state.haul_destination_reserved_amount_by_key.get(key, 0)
	) + amount_delta

	if final_amount > 0:
		logistics_state.haul_destination_reserved_amount_by_key[key] = final_amount
	else:
		logistics_state.haul_destination_reserved_amount_by_key.erase(key)

static func get_city_haul_reservation(
	reservation_id: int
) -> Dictionary:
	return get_city_haul_reservation_for_city_state(
		_get_compatibility_city_state(),
		reservation_id
	)


static func get_city_haul_reservation_for_city_state(
	city_state: CitySettlementSimulationState,
	reservation_id: int
) -> Dictionary:
	var logistics_state := get_state_for_city_state(city_state)

	if logistics_state == null or reservation_id <= 0:
		return {}

	var raw_reservation = logistics_state.haul_reservations.get(
		reservation_id,
		{}
	)

	return (
		raw_reservation.duplicate(true)
		if raw_reservation is Dictionary
		else {}
	)

static func get_city_haul_reservation_snapshot() -> Array:
	return get_city_haul_reservation_snapshot_for_city_state(
		_get_compatibility_city_state()
	)


static func get_city_haul_reservation_snapshot_for_city_state(
	city_state: CitySettlementSimulationState
) -> Array:
	var reservation_snapshot: Array = []
	var logistics_state := get_state_for_city_state(city_state)

	if logistics_state == null:
		return reservation_snapshot

	var reservation_ids: Array = logistics_state.haul_reservations.keys()
	reservation_ids.sort()

	for raw_reservation_id in reservation_ids:
		var reservation := get_city_haul_reservation_for_city_state(
			city_state,
			int(raw_reservation_id)
		)
		if not reservation.is_empty():
			reservation_snapshot.append(reservation)

	return reservation_snapshot

static func city_haul_reservation_is_soft(
	reservation_id: int
) -> bool:
	return city_haul_reservation_is_soft_for_city_state(
		_get_compatibility_city_state(),
		reservation_id
	)

static func get_city_soft_haul_reservation_ids_for_destination_resource(
	destination: Dictionary,
	resource: String,
	excluding_citizen_id: int = -1
) -> Array[int]:
	return get_city_soft_haul_reservation_ids_for_destination_resource_for_city_state(
		_get_compatibility_city_state(),
		destination,
		resource,
		excluding_citizen_id
	)

static func get_city_soft_haul_destination_reserved_resource_amount(
	destination: Dictionary,
	resource: String,
	excluding_citizen_id: int = -1
) -> int:
	return get_city_soft_haul_destination_reserved_resource_amount_for_city_state(
		_get_compatibility_city_state(),
		destination,
		resource,
		excluding_citizen_id
	)


static func get_city_soft_haul_destination_reserved_resource_amount_for_city_state(
	city_state: CitySettlementSimulationState,
	destination: Dictionary,
	resource: String,
	excluding_citizen_id: int = -1
) -> int:
	if city_state == null or not CityResourceCatalog.is_city_resource_type(resource):
		return 0

	var reserved_amount := 0

	for reservation in get_city_haul_reservation_snapshot_for_city_state(city_state):
		var citizen_id := int(reservation.get("citizen_id", -1))
		if (
			citizen_id <= 0
			or citizen_id == excluding_citizen_id
			or not city_citizen_haul_endpoints_match(
				reservation.get("destination", {}),
				destination
			)
			or CityCitizenInventorySystem.get_city_citizen_haul_cargo_amount_for_city_state(
				city_state,
				citizen_id
			) > 0
			or int(reservation.get("source_reserved_amount", 0)) <= 0
			or int(reservation.get("destination_reserved_amount", 0)) <= 0
		):
			continue

		reserved_amount += maxi(
			int(
				get_city_haul_reservation_destination_resources_for_city_state(
					city_state,
					int(reservation.get("id", -1))
				).get(resource, 0)
			),
			0
		)

	return reserved_amount


static func city_haul_reservation_is_soft_for_city_state(
	city_state: CitySettlementSimulationState,
	reservation_id: int
) -> bool:
	var reservation := get_city_haul_reservation_for_city_state(
		city_state,
		reservation_id
	)

	if reservation.is_empty():
		return false

	var citizen_id := int(reservation.get("citizen_id", -1))
	return (
		citizen_id > 0
		and CityCitizenInventorySystem.get_city_citizen_haul_cargo_amount_for_city_state(
			city_state,
			citizen_id
		) <= 0
		and int(reservation.get("source_reserved_amount", 0)) > 0
		and int(reservation.get("destination_reserved_amount", 0)) > 0
	)


static func get_city_soft_haul_reservation_ids_for_destination_resource_for_city_state(
	city_state: CitySettlementSimulationState,
	destination: Dictionary,
	resource: String,
	excluding_citizen_id: int = -1
) -> Array[int]:
	var reservation_ids: Array[int] = []
	var logistics_state := get_state_for_city_state(city_state)

	if logistics_state == null or not CityResourceCatalog.is_city_resource_type(resource):
		return reservation_ids

	for raw_reservation_id in logistics_state.haul_reservations.keys():
		var reservation_id := int(raw_reservation_id)

		if not city_haul_reservation_is_soft_for_city_state(
			city_state,
			reservation_id
		):
			continue

		var reservation := get_city_haul_reservation_for_city_state(
			city_state,
			reservation_id
		)

		if (
			int(reservation.get("citizen_id", -1)) == excluding_citizen_id
			or not city_citizen_haul_endpoints_match(
				reservation.get("destination", {}),
				destination
			)
			or get_city_haul_reservation_destination_resource_amount_for_city_state(
				city_state,
				reservation_id,
				resource
			) <= 0
		):
			continue

		reservation_ids.append(reservation_id)

	reservation_ids.sort()
	reservation_ids.reverse()
	return reservation_ids


static func release_soft_city_haul_reservation_for_reassignment_for_city_state(
	city_state: CitySettlementSimulationState,
	reservation_id: int
) -> bool:
	if not city_haul_reservation_is_soft_for_city_state(city_state, reservation_id):
		return false

	var reservation := get_city_haul_reservation_for_city_state(
		city_state,
		reservation_id
	)
	var citizen_id := int(reservation.get("citizen_id", -1))
	var current_task := (
		CityCitizenTaskRuntimeSystem.get_city_citizen_current_task_for_city_state(
			city_state,
			citizen_id
		)
	)
	var current_haul := (
		CityCitizenTaskRuntimeSystem.get_city_citizen_current_haul_for_city_state(
			city_state,
			citizen_id
		)
	)
	var task_source := str(
		current_task.get(
			"source",
			CityCitizens.CITY_CITIZEN_TASK_SOURCE_AUTONOMY
		)
	)
	var owns_task := (
		str(current_task.get("kind", ""))
		== CityCitizens.CITY_CITIZEN_TASK_KIND_HAUL
		and int(current_haul.get("reservation_id", -1)) == reservation_id
	)

	if not release_city_haul_reservation_for_city_state(city_state, reservation_id):
		return false

	if owns_task:
		CityCitizenMovementRuntimeSystem.cancel_city_citizen_movement_for_city_state(
			city_state,
			citizen_id
		)
		CityCitizenTaskRuntimeSystem.clear_city_citizen_task_for_city_state(
			city_state,
			citizen_id,
			task_source
		)

	return true


static func reduce_soft_city_haul_reservation_for_reassignment_for_city_state(
	city_state: CitySettlementSimulationState,
	reservation_id: int,
	resource: String,
	requested_amount: int
) -> int:
	if (
		requested_amount <= 0
		or not CityResourceCatalog.is_city_resource_type(resource)
		or not city_haul_reservation_is_soft_for_city_state(
			city_state,
			reservation_id
		)
	):
		return 0

	var reservation := get_city_haul_reservation_for_city_state(
		city_state,
		reservation_id
	)
	var reserved_resource := str(
		reservation.get("resource_type", WorldData.RESOURCE_NONE)
	)
	var source_reserved_amount := maxi(
		int(reservation.get("source_reserved_amount", 0)),
		0
	)
	var destination_resources := (
		get_city_haul_reservation_destination_resources_for_city_state(
			city_state,
			reservation_id
		)
	)
	var destination_resource_amount := maxi(
		int(destination_resources.get(resource, 0)),
		0
	)
	var released_amount := mini(
		requested_amount,
		mini(source_reserved_amount, destination_resource_amount)
	)

	if reserved_resource != resource or released_amount <= 0:
		return 0

	if released_amount >= source_reserved_amount:
		return (
			source_reserved_amount
			if release_soft_city_haul_reservation_for_reassignment_for_city_state(
				city_state,
				reservation_id
			)
			else 0
		)

	var citizen_id := int(reservation.get("citizen_id", -1))
	var source: Dictionary = reservation.get("source", {})
	var destination: Dictionary = reservation.get("destination", {})
	var remaining_source_amount := source_reserved_amount - released_amount
	var remaining_destination_resource_amount := (
		destination_resource_amount - released_amount
	)

	if remaining_destination_resource_amount > 0:
		destination_resources[resource] = remaining_destination_resource_amount
	else:
		destination_resources.erase(resource)

	reservation["source_reserved_amount"] = remaining_source_amount
	reservation["destination_reserved_resources"] = destination_resources
	reservation["destination_reserved_amount"] = (
		_get_city_haul_resource_manifest_total(destination_resources)
	)
	reservation["last_reduced_world_minute"] = SimulationClock.absolute_world_minutes
	city_state.logistics_state.haul_reservations[reservation_id] = reservation
	_change_city_haul_reserved_source_amount_for_city_state(
		city_state,
		source,
		resource,
		-released_amount
	)
	_change_city_haul_reserved_destination_amount_for_city_state(
		city_state,
		destination,
		-released_amount
	)

	var current_haul := (
		CityCitizenTaskRuntimeSystem.get_city_citizen_current_haul_for_city_state(
			city_state,
			citizen_id
		)
	)

	if int(current_haul.get("reservation_id", -1)) == reservation_id:
		current_haul["requested_amount"] = remaining_source_amount
		CityCitizenTaskRuntimeSystem.set_city_citizen_current_haul_for_city_state(
			city_state,
			citizen_id,
			current_haul
		)

	city_state.logistics_state.haul_reservation_version += 1
	city_state.citizen_task_runtime_state.citizen_task_version += 1
	return released_amount

static func release_soft_city_haul_reservation_for_reassignment(
	reservation_id: int
) -> bool:
	return release_soft_city_haul_reservation_for_reassignment_for_city_state(
		_get_compatibility_city_state(),
		reservation_id
	)

static func reduce_soft_city_haul_reservation_for_reassignment(
	reservation_id: int,
	resource: String,
	requested_amount: int
) -> int:
	return reduce_soft_city_haul_reservation_for_reassignment_for_city_state(
		_get_compatibility_city_state(),
		reservation_id,
		resource,
		requested_amount
	)

static func preempt_soft_city_haul_reservations_for_destination_resource(
	destination: Dictionary,
	resource: String,
	requested_amount: int,
	excluding_citizen_id: int = -1
) -> Dictionary:
	return preempt_soft_city_haul_reservations_for_destination_resource_for_city_state(
		_get_compatibility_city_state(),
		destination,
		resource,
		requested_amount,
		excluding_citizen_id
	)


static func preempt_soft_city_haul_reservations_for_destination_resource_for_city_state(
	city_state: CitySettlementSimulationState,
	destination: Dictionary,
	resource: String,
	requested_amount: int,
	excluding_citizen_id: int = -1
) -> Dictionary:
	var released_amount := 0
	var released_reservation_ids: Array[int] = []
	var reduced_reservation_ids: Array[int] = []
	var target_amount := maxi(requested_amount, 0)

	if (
		city_state == null
		or target_amount <= 0
		or not CityResourceCatalog.is_city_resource_type(resource)
	):
		return {
			"released_amount": 0,
			"released_reservation_ids": released_reservation_ids,
			"reduced_reservation_ids": reduced_reservation_ids,
		}

	for reservation_id in (
		get_city_soft_haul_reservation_ids_for_destination_resource_for_city_state(
			city_state,
			destination,
			resource,
			excluding_citizen_id
		)
	):
		var amount_still_needed := target_amount - released_amount

		if amount_still_needed <= 0:
			break

		var original_reserved_amount := (
			get_city_haul_reservation_destination_resource_amount_for_city_state(
				city_state,
				reservation_id,
				resource
			)
		)

		if original_reserved_amount <= 0:
			continue

		var released_from_reservation := (
			reduce_soft_city_haul_reservation_for_reassignment_for_city_state(
				city_state,
				reservation_id,
				resource,
				amount_still_needed
			)
		)

		if released_from_reservation <= 0:
			continue

		released_amount += released_from_reservation

		if get_city_haul_reservation_for_city_state(
			city_state,
			reservation_id
		).is_empty():
			released_reservation_ids.append(reservation_id)
		else:
			reduced_reservation_ids.append(reservation_id)

	return {
		"released_amount": released_amount,
		"released_reservation_ids": released_reservation_ids,
		"reduced_reservation_ids": reduced_reservation_ids,
	}

static func get_city_haul_reservation_id_for_citizen(
	citizen_id: int
) -> int:
	return get_city_haul_reservation_id_for_citizen_for_city_state(
		_get_compatibility_city_state(),
		citizen_id
	)


static func get_city_haul_reservation_id_for_citizen_for_city_state(
	city_state: CitySettlementSimulationState,
	citizen_id: int
) -> int:
	var logistics_state := get_state_for_city_state(city_state)

	if logistics_state == null:
		return CityCitizens.INVALID_CITY_CITIZEN_HAUL_RESERVATION_ID

	return int(
		logistics_state.haul_reservation_id_by_citizen_id.get(
			citizen_id,
			CityCitizens.INVALID_CITY_CITIZEN_HAUL_RESERVATION_ID
		)
	)

static func get_city_haul_endpoint_source_reserved_amount(
	endpoint: Dictionary,
	resource: String,
	excluding_reservation_id: int = (
		CityCitizens.INVALID_CITY_CITIZEN_HAUL_RESERVATION_ID
	)
) -> int:
	return get_city_haul_endpoint_source_reserved_amount_for_city_state(
		_get_compatibility_city_state(),
		endpoint,
		resource,
		excluding_reservation_id
	)


static func get_city_haul_endpoint_source_reserved_amount_for_city_state(
	city_state: CitySettlementSimulationState,
	endpoint: Dictionary,
	resource: String,
	excluding_reservation_id: int = (
		CityCitizens.INVALID_CITY_CITIZEN_HAUL_RESERVATION_ID
	)
) -> int:
	var logistics_state := get_state_for_city_state(city_state)

	if logistics_state == null:
		return 0

	var key := _get_city_haul_source_reservation_key(endpoint, resource)
	var reserved_amount := maxi(
		int(logistics_state.haul_source_reserved_amount_by_key.get(key, 0)),
		0
	)

	if excluding_reservation_id <= 0:
		return reserved_amount

	var reservation := get_city_haul_reservation_for_city_state(
		city_state,
		excluding_reservation_id
	)

	if (
		not reservation.is_empty()
		and city_citizen_haul_endpoints_match(
			reservation.get("source", {}),
			endpoint
		)
		and str(reservation.get("resource_type", WorldData.RESOURCE_NONE))
		== resource
	):
		reserved_amount -= maxi(
			int(reservation.get("source_reserved_amount", 0)),
			0
		)

	return maxi(reserved_amount, 0)

static func get_city_haul_endpoint_destination_reserved_amount(
	endpoint: Dictionary,
	excluding_reservation_id: int = (
		CityCitizens.INVALID_CITY_CITIZEN_HAUL_RESERVATION_ID
	)
) -> int:
	return get_city_haul_endpoint_destination_reserved_amount_for_city_state(
		_get_compatibility_city_state(),
		endpoint,
		excluding_reservation_id
	)


static func get_city_haul_endpoint_destination_reserved_amount_for_city_state(
	city_state: CitySettlementSimulationState,
	endpoint: Dictionary,
	excluding_reservation_id: int = (
		CityCitizens.INVALID_CITY_CITIZEN_HAUL_RESERVATION_ID
	)
) -> int:
	var logistics_state := get_state_for_city_state(city_state)

	if logistics_state == null:
		return 0

	var key := _get_city_haul_endpoint_key(endpoint)
	var reserved_amount := maxi(
		int(
			logistics_state.haul_destination_reserved_amount_by_key.get(
				key,
				0
			)
		),
		0
	)

	if excluding_reservation_id <= 0:
		return reserved_amount

	var reservation := get_city_haul_reservation_for_city_state(
		city_state,
		excluding_reservation_id
	)

	if (
		not reservation.is_empty()
		and city_citizen_haul_endpoints_match(
			reservation.get("destination", {}),
			endpoint
		)
	):
		reserved_amount -= maxi(
			int(reservation.get("destination_reserved_amount", 0)),
			0
		)

	return maxi(reserved_amount, 0)

static func get_city_haul_endpoint_resource_amount(
	endpoint: Dictionary,
	resource: String
) -> int:
	return get_city_haul_endpoint_resource_amount_for_city_state(
		_get_compatibility_city_state(),
		endpoint,
		resource
	)


static func get_city_haul_endpoint_resource_amount_for_city_state(
	city_state: CitySettlementSimulationState,
	endpoint: Dictionary,
	resource: String
) -> int:
	var endpoint_kind := str(
		endpoint.get(
			"kind",
			CityCitizens.CITY_CITIZEN_HAUL_ENDPOINT_KIND_NONE
		)
	)
	var endpoint_id := int(endpoint.get("id", -1))

	match endpoint_kind:
		CityCitizens.CITY_CITIZEN_HAUL_ENDPOINT_KIND_CITY_OBJECT_CONTAINER:
			return CityResourceContainerSystem.get_city_object_stored_resource_amount(
				CityObjectSystem.get_city_object_by_id_for_city_state(
					city_state,
					endpoint_id
				),
				resource
			)

		CityCitizens.CITY_CITIZEN_HAUL_ENDPOINT_KIND_GROUND_PILE:
			return get_city_ground_pile_resource_amount(
				get_city_ground_pile_by_id_for_city_state(
					city_state,
					endpoint_id
				),
				resource
			)

	return 0

static func get_city_haul_endpoint_unreserved_resource_amount(
	endpoint: Dictionary,
	resource: String,
	excluding_reservation_id: int = (
		CityCitizens.INVALID_CITY_CITIZEN_HAUL_RESERVATION_ID
	),
	excluding_food_citizen_id: int = -1
) -> int:
	return get_city_haul_endpoint_unreserved_resource_amount_for_city_state(
		_get_compatibility_city_state(),
		endpoint,
		resource,
		excluding_reservation_id,
		excluding_food_citizen_id
	)


static func get_city_haul_endpoint_unreserved_resource_amount_for_city_state(
	city_state: CitySettlementSimulationState,
	endpoint: Dictionary,
	resource: String,
	excluding_reservation_id: int = (
		CityCitizens.INVALID_CITY_CITIZEN_HAUL_RESERVATION_ID
	),
	excluding_food_citizen_id: int = -1
) -> int:
	var food_task_reserved_amount := (
		CityCitizenTaskRuntimeSystem.get_city_food_task_reserved_endpoint_amount_for_city_state(
			city_state,
			str(
				endpoint.get(
					"kind",
					CityCitizens.CITY_CITIZEN_HAUL_ENDPOINT_KIND_NONE
				)
			),
			int(endpoint.get("id", -1)),
			resource,
			excluding_food_citizen_id
		)
	)

	return maxi(
		get_city_haul_endpoint_resource_amount_for_city_state(
			city_state,
			endpoint,
			resource
		)
		- get_city_haul_endpoint_source_reserved_amount_for_city_state(
			city_state,
			endpoint,
			resource,
			excluding_reservation_id
		)
		- food_task_reserved_amount,
		0
	)

static func get_city_haul_endpoint_unreserved_destination_space(
	endpoint: Dictionary,
	excluding_reservation_id: int = (
		CityCitizens.INVALID_CITY_CITIZEN_HAUL_RESERVATION_ID
	)
) -> int:
	return get_city_haul_endpoint_unreserved_destination_space_for_city_state(
		_get_compatibility_city_state(),
		endpoint,
		excluding_reservation_id
	)


static func get_city_haul_endpoint_unreserved_destination_space_for_city_state(
	city_state: CitySettlementSimulationState,
	endpoint: Dictionary,
	excluding_reservation_id: int = (
		CityCitizens.INVALID_CITY_CITIZEN_HAUL_RESERVATION_ID
	)
) -> int:
	if city_state == null:
		return 0

	var endpoint_kind := str(
		endpoint.get(
			"kind",
			CityCitizens.CITY_CITIZEN_HAUL_ENDPOINT_KIND_NONE
		)
	)
	var endpoint_id := int(endpoint.get("id", -1))

	if endpoint_kind == CityCitizens.CITY_CITIZEN_HAUL_ENDPOINT_KIND_CONSTRUCTION_SITE:
		return CityConstructionSystem.get_city_construction_site_unreserved_total_space_for_city_state(
			city_state,
			endpoint_id,
			excluding_reservation_id
		)

	if endpoint_kind == CityCitizens.CITY_CITIZEN_HAUL_ENDPOINT_KIND_GROUND_TILE:
		var raw_tile = endpoint.get(
			"tile_position",
			CityCitizens.INVALID_CITY_TILE_POSITION
		)

		if (
			not raw_tile is Vector2i
			or not can_city_ground_pile_exist_at_tile_for_city_state(
				city_state,
				city_state.city_world,
				raw_tile
			)
		):
			return 0

		return maxi(
			CITY_GROUND_DROP_RESERVATION_CAPACITY
			- get_city_haul_endpoint_destination_reserved_amount_for_city_state(
				city_state,
				endpoint,
				excluding_reservation_id
			),
			0
		)

	if (
		endpoint_kind
		!= CityCitizens.CITY_CITIZEN_HAUL_ENDPOINT_KIND_CITY_OBJECT_CONTAINER
	):
		return 0

	var city_object := CityObjectSystem.get_city_object_by_id_for_city_state(
		city_state,
		endpoint_id
	)

	if city_object.is_empty():
		return 0

	return maxi(
		CityResourceContainerSystem.get_city_object_storage_free_space(city_object)
		- get_city_haul_endpoint_destination_reserved_amount_for_city_state(
			city_state,
			endpoint,
			excluding_reservation_id
		),
		0
	)

static func get_city_haul_endpoint_unreserved_destination_resource_space(
	endpoint: Dictionary,
	resource: String,
	excluding_reservation_id: int = (
		CityCitizens.INVALID_CITY_CITIZEN_HAUL_RESERVATION_ID
	)
) -> int:
	return get_city_haul_endpoint_unreserved_destination_resource_space_for_city_state(
		_get_compatibility_city_state(),
		endpoint,
		resource,
		excluding_reservation_id
	)


static func get_city_haul_endpoint_unreserved_destination_resource_space_for_city_state(
	city_state: CitySettlementSimulationState,
	endpoint: Dictionary,
	resource: String,
	excluding_reservation_id: int = (
		CityCitizens.INVALID_CITY_CITIZEN_HAUL_RESERVATION_ID
	)
) -> int:
	if (
		str(
			endpoint.get(
				"kind",
				CityCitizens.CITY_CITIZEN_HAUL_ENDPOINT_KIND_NONE
			)
		)
		== CityCitizens.CITY_CITIZEN_HAUL_ENDPOINT_KIND_CONSTRUCTION_SITE
	):
		return CityConstructionSystem.get_city_construction_site_unreserved_resource_space_for_city_state(
			city_state,
			int(endpoint.get("id", -1)),
			resource,
			excluding_reservation_id
		)

	return get_city_haul_endpoint_unreserved_destination_space_for_city_state(
		city_state,
		endpoint,
		excluding_reservation_id
	)

static func city_haul_endpoint_can_provide_resource(
	values: Dictionary
) -> bool:
	return city_haul_endpoint_can_provide_resource_for_city_state(
		_get_compatibility_city_state(),
		values
	)


static func city_haul_endpoint_can_provide_resource_for_city_state(
	city_state: CitySettlementSimulationState,
	values: Dictionary
) -> bool:
	if city_state == null:
		return false

	var endpoint: Dictionary = values.get("endpoint", {})
	var resource := str(values.get("resource", WorldData.RESOURCE_NONE))
	var withdrawal_purpose := str(
		values.get(
			"withdrawal_purpose",
			CityObjectCatalog.CONTAINER_HAUL_PURPOSE_NONE
		)
	)
	var require_unreserved_amount := bool(
		values.get("require_unreserved_amount", true)
	)
	var excluding_reservation_id := int(
		values.get(
			"excluding_reservation_id",
			CityCitizens.INVALID_CITY_CITIZEN_HAUL_RESERVATION_ID
		)
	)
	var endpoint_kind := str(
		endpoint.get(
			"kind",
			CityCitizens.CITY_CITIZEN_HAUL_ENDPOINT_KIND_NONE
		)
	)
	var endpoint_id := int(endpoint.get("id", -1))

	if endpoint_id <= 0:
		return false

	match endpoint_kind:
		CityCitizens.CITY_CITIZEN_HAUL_ENDPOINT_KIND_CITY_OBJECT_CONTAINER:
			if not CityResourceContainerSystem.city_object_can_provide_haul_resource(
				CityObjectSystem.get_city_object_by_id_for_city_state(
					city_state,
					endpoint_id
				),
				resource,
				withdrawal_purpose
			):
				return false

		CityCitizens.CITY_CITIZEN_HAUL_ENDPOINT_KIND_GROUND_PILE:
			var ground_pile := get_city_ground_pile_by_id_for_city_state(
				city_state,
				endpoint_id
			)

			if (
				not [
					CityObjectCatalog.CONTAINER_HAUL_PURPOSE_GROUND_PILE_CLEANUP,
					CityObjectCatalog.CONTAINER_HAUL_PURPOSE_CONSTRUCTION,
					CityObjectCatalog.CONTAINER_HAUL_PURPOSE_HOUSEHOLD_FOOD_SOURCE,
				].has(withdrawal_purpose)
				or city_ground_pile_is_construction_reserved(ground_pile)
				or get_city_ground_pile_resource_amount(ground_pile, resource) <= 0
			):
				return false

		_:
			return false

	return (
		not require_unreserved_amount
		or get_city_haul_endpoint_unreserved_resource_amount_for_city_state(
			city_state,
			endpoint,
			resource,
			excluding_reservation_id
		) > 0
	)

static func city_haul_endpoint_can_accept_resource(
	values: Dictionary
) -> bool:
	return city_haul_endpoint_can_accept_resource_for_city_state(
		_get_compatibility_city_state(),
		values
	)


static func city_haul_endpoint_can_accept_resource_for_city_state(
	city_state: CitySettlementSimulationState,
	values: Dictionary
) -> bool:
	if city_state == null:
		return false

	var endpoint: Dictionary = values.get("endpoint", {})
	var resource := str(values.get("resource", WorldData.RESOURCE_NONE))
	var deposit_purpose := str(
		values.get(
			"deposit_purpose",
			CityObjectCatalog.CONTAINER_HAUL_PURPOSE_NONE
		)
	)
	var require_unreserved_space := bool(
		values.get("require_unreserved_space", true)
	)
	var excluding_reservation_id := int(
		values.get(
			"excluding_reservation_id",
			CityCitizens.INVALID_CITY_CITIZEN_HAUL_RESERVATION_ID
		)
	)
	var endpoint_kind := str(
		endpoint.get(
			"kind",
			CityCitizens.CITY_CITIZEN_HAUL_ENDPOINT_KIND_NONE
		)
	)
	var endpoint_id := int(endpoint.get("id", -1))

	if endpoint_kind == CityCitizens.CITY_CITIZEN_HAUL_ENDPOINT_KIND_GROUND_TILE:
		var raw_tile = endpoint.get(
			"tile_position",
			CityCitizens.INVALID_CITY_TILE_POSITION
		)

		if (
			deposit_purpose
			!= CityObjectCatalog.CONTAINER_HAUL_PURPOSE_GROUND_PILE_CLEANUP
			or not raw_tile is Vector2i
			or not can_city_ground_pile_exist_at_tile_for_city_state(
				city_state,
				city_state.city_world,
				raw_tile
			)
		):
			return false

		return (
			not require_unreserved_space
			or get_city_haul_endpoint_unreserved_destination_space_for_city_state(
				city_state,
				endpoint,
				excluding_reservation_id
			) > 0
		)

	if endpoint_kind == CityCitizens.CITY_CITIZEN_HAUL_ENDPOINT_KIND_CONSTRUCTION_SITE:
		var site := CityConstructionSystem.get_city_construction_site_by_id_for_city_state(
			city_state,
			endpoint_id
		)

		if (
			site.is_empty()
			or deposit_purpose != CityObjectCatalog.CONTAINER_HAUL_PURPOSE_CONSTRUCTION
			or str(site.get("phase", ""))
			!= CityConstructionSystem.CITY_CONSTRUCTION_PHASE_GATHERING
		):
			return false

		return (
			not require_unreserved_space
			or CityConstructionSystem.get_city_construction_site_unreserved_resource_space_for_city_state(
				city_state,
				endpoint_id,
				resource,
				excluding_reservation_id
			) > 0
		)

	if (
		endpoint_kind
		!= CityCitizens.CITY_CITIZEN_HAUL_ENDPOINT_KIND_CITY_OBJECT_CONTAINER
	):
		return false

	var city_object := CityObjectSystem.get_city_object_by_id_for_city_state(
		city_state,
		endpoint_id
	)

	if not CityResourceContainerSystem.city_object_can_accept_haul_resource(
		city_object,
		resource,
		deposit_purpose,
		false
	):
		return false

	return (
		not require_unreserved_space
		or get_city_haul_endpoint_unreserved_destination_space_for_city_state(
			city_state,
			endpoint,
			excluding_reservation_id
		) > 0
	)

static func _normalize_city_haul_resource_manifest(
	resources: Dictionary,
	maximum_total: int = -1
) -> Dictionary:
	var normalized: Dictionary = {}
	var remaining := maximum_total
	var resource_names: Array = resources.keys()
	resource_names.sort()

	for raw_resource in resource_names:
		if typeof(raw_resource) != TYPE_STRING:
			continue

		var resource: String = raw_resource
		var amount := maxi(int(resources.get(resource, 0)), 0)

		if amount <= 0 or not CityResourceCatalog.is_city_resource_type(resource):
			continue

		if maximum_total >= 0:
			amount = mini(amount, maxi(remaining, 0))

		if amount <= 0:
			break

		normalized[resource] = amount

		if maximum_total >= 0:
			remaining -= amount

	return normalized

static func _get_city_haul_resource_manifest_total(
	resources: Dictionary
) -> int:
	var total := 0

	for raw_amount in resources.values():
		total += maxi(int(raw_amount), 0)

	return total

static func get_city_haul_reservation_destination_resources(
	reservation_id: int
) -> Dictionary:
	return get_city_haul_reservation_destination_resources_for_city_state(
		_get_compatibility_city_state(),
		reservation_id
	)


static func get_city_haul_reservation_destination_resources_for_city_state(
	city_state: CitySettlementSimulationState,
	reservation_id: int
) -> Dictionary:
	var reservation := get_city_haul_reservation_for_city_state(
		city_state,
		reservation_id
	)

	if reservation.is_empty():
		return {}

	var raw_resources = reservation.get("destination_reserved_resources", {})

	if raw_resources is Dictionary and not raw_resources.is_empty():
		return _normalize_city_haul_resource_manifest(raw_resources)

	var legacy_resource := str(
		reservation.get("resource_type", WorldData.RESOURCE_NONE)
	)
	var legacy_amount := maxi(
		int(reservation.get("destination_reserved_amount", 0)),
		0
	)

	if CityResourceCatalog.is_city_resource_type(legacy_resource) and legacy_amount > 0:
		return {legacy_resource: legacy_amount}

	return {}

static func get_city_haul_reservation_destination_resource_amount(
	reservation_id: int,
	resource: String
) -> int:
	return get_city_haul_reservation_destination_resource_amount_for_city_state(
		_get_compatibility_city_state(),
		reservation_id,
		resource
	)


static func get_city_haul_reservation_destination_resource_amount_for_city_state(
	city_state: CitySettlementSimulationState,
	reservation_id: int,
	resource: String
) -> int:
	return maxi(
		int(
			get_city_haul_reservation_destination_resources_for_city_state(
				city_state,
				reservation_id
			).get(resource, 0)
		),
		0
	)

static func create_city_haul_reservation(
	values: Dictionary
) -> Dictionary:
	return create_city_haul_reservation_for_city_state(
		_get_compatibility_city_state(),
		values
	)


static func create_city_haul_reservation_for_city_state(
	city_state: CitySettlementSimulationState,
	values: Dictionary
) -> Dictionary:
	if city_state == null:
		return {}

	var citizen_id := int(values.get("citizen_id", -1))
	var citizen := CityCitizenRegistrySystem.get_city_citizen_by_id_for_city_state(
		city_state,
		citizen_id
	)
	var raw_source = values.get("source", {})
	var raw_destination = values.get("destination", {})

	if (
		citizen_id <= 0
		or citizen.is_empty()
		or not bool(citizen.get("alive", false))
		or not raw_source is Dictionary
		or not raw_destination is Dictionary
		or get_city_haul_reservation_id_for_citizen_for_city_state(
			city_state,
			citizen_id
		) > 0
	):
		return {}

	var source := CityCitizens.make_city_citizen_haul_endpoint(raw_source)
	var destination := CityCitizens.make_city_citizen_haul_endpoint(raw_destination)
	var resource := str(values.get("resource_type", WorldData.RESOURCE_NONE))
	var requested_amount := maxi(int(values.get("requested_amount", 0)), 0)
	var source_access_purpose := str(
		values.get(
			"source_access_purpose",
			CityObjectCatalog.CONTAINER_HAUL_PURPOSE_NONE
		)
	)
	var destination_access_purpose := str(
		values.get(
			"destination_access_purpose",
			CityObjectCatalog.CONTAINER_HAUL_PURPOSE_NONE
		)
	)

	if (
		requested_amount <= 0
		or not CityResourceCatalog.is_city_resource_type(resource)
		or not CityCitizens.is_valid_city_citizen_haul_endpoint(source)
		or not CityCitizens.is_valid_city_citizen_haul_endpoint(destination)
	):
		return {}

	var destination_space := (
		get_city_haul_endpoint_unreserved_destination_space_for_city_state(
			city_state,
			destination
		)
	)

	if destination_space <= 0:
		return {}

	var cargo_resources := (
		CityCitizenInventorySystem.get_city_citizen_haul_cargo_resources_for_city_state(
			city_state,
			citizen_id
		)
	)
	var cargo_amount := (
		CityCitizenInventorySystem.get_city_citizen_haul_cargo_amount_for_city_state(
			city_state,
			citizen_id
		)
	)
	var source_reserved_amount := 0
	var destination_resources: Dictionary = {}

	if cargo_amount > 0:
		var maximum_reserved := mini(
			requested_amount,
			mini(cargo_amount, destination_space)
		)
		destination_resources = _normalize_city_haul_resource_manifest(
			cargo_resources,
			maximum_reserved
		)

		if (
			str(
				destination.get(
					"kind",
					CityCitizens.CITY_CITIZEN_HAUL_ENDPOINT_KIND_NONE
				)
			)
			== CityCitizens.CITY_CITIZEN_HAUL_ENDPOINT_KIND_CONSTRUCTION_SITE
		):
			for cargo_resource in destination_resources.keys():
				var resource_space := (
					get_city_haul_endpoint_unreserved_destination_resource_space_for_city_state(
						city_state,
						destination,
						str(cargo_resource)
					)
				)
				var capped_amount := mini(
					int(destination_resources.get(cargo_resource, 0)),
					resource_space
				)
				if capped_amount > 0:
					destination_resources[cargo_resource] = capped_amount
				else:
					destination_resources.erase(cargo_resource)

		for cargo_resource in destination_resources.keys():
			if not city_haul_endpoint_can_accept_resource_for_city_state(
				city_state,
				{
					"endpoint": destination,
					"resource": str(cargo_resource),
					"deposit_purpose": destination_access_purpose,
					"require_unreserved_space": true,
				}
			):
				return {}

		if _get_city_haul_resource_manifest_total(destination_resources) <= 0:
			return {}
	else:
		if not city_haul_endpoint_can_provide_resource_for_city_state(
			city_state,
			{
				"endpoint": source,
				"resource": resource,
				"withdrawal_purpose": source_access_purpose,
				"require_unreserved_amount": true,
			}
		):
			return {}

		if not city_haul_endpoint_can_accept_resource_for_city_state(
			city_state,
			{
				"endpoint": destination,
				"resource": resource,
				"deposit_purpose": destination_access_purpose,
				"require_unreserved_space": true,
			}
		):
			return {}

		source_reserved_amount = mini(
			requested_amount,
			mini(
				CityCitizenInventorySystem.get_city_citizen_available_haul_capacity_for_city_state(
					city_state,
					citizen_id
				),
				mini(
					get_city_haul_endpoint_unreserved_resource_amount_for_city_state(
						city_state,
						source,
						resource
					),
					mini(
						destination_space,
						get_city_haul_endpoint_unreserved_destination_resource_space_for_city_state(
							city_state,
							destination,
							resource
						)
					)
				)
			)
		)

		if source_reserved_amount <= 0:
			return {}

		destination_resources = {resource: source_reserved_amount}

	var destination_reserved_amount := (
		_get_city_haul_resource_manifest_total(destination_resources)
	)

	if destination_reserved_amount <= 0:
		return {}

	var logistics_state := city_state.logistics_state
	var reservation_id := logistics_state.next_haul_reservation_id
	var reservation := {
		"id": reservation_id,
		"citizen_id": citizen_id,
		"resource_type": resource,
		"source": source,
		"destination": destination,
		"source_access_purpose": source_access_purpose,
		"destination_access_purpose": destination_access_purpose,
		"source_reserved_amount": source_reserved_amount,
		"destination_reserved_amount": destination_reserved_amount,
		"destination_reserved_resources": destination_resources,
		"created_world_minute": SimulationClock.absolute_world_minutes,
	}
	logistics_state.next_haul_reservation_id += 1
	logistics_state.haul_reservations[reservation_id] = reservation
	logistics_state.haul_reservation_id_by_citizen_id[citizen_id] = reservation_id
	_change_city_haul_reserved_source_amount_for_city_state(
		city_state,
		source,
		resource,
		source_reserved_amount
	)
	_change_city_haul_reserved_destination_amount_for_city_state(
		city_state,
		destination,
		destination_reserved_amount
	)
	logistics_state.haul_reservation_version += 1
	city_state.citizen_task_runtime_state.citizen_task_version += 1
	return reservation.duplicate(true)

static func _make_city_haul_reservation_context(
	values: Dictionary
) -> Dictionary:
	var citizen_id := int(values.get("citizen_id", -1))
	var citizen := CityCitizenRegistrySystem.get_city_citizen_by_id(citizen_id)
	var raw_source = values.get("source", {})
	var raw_destination = values.get("destination", {})

	if (
		citizen_id <= 0
		or citizen.is_empty()
		or not bool(citizen.get("alive", false))
		or not raw_source is Dictionary
		or not raw_destination is Dictionary
		or get_city_haul_reservation_id_for_citizen(citizen_id) > 0
	):
		return {}

	var source := CityCitizens.make_city_citizen_haul_endpoint(
		raw_source
	)
	var destination := CityCitizens.make_city_citizen_haul_endpoint(
		raw_destination
	)
	var resource := str(values.get("resource_type", WorldData.RESOURCE_NONE))
	var requested_amount := maxi(int(values.get("requested_amount", 0)), 0)
	var source_access_purpose := str(
		values.get(
			"source_access_purpose",
			CityObjectCatalog.CONTAINER_HAUL_PURPOSE_NONE
		)
	)
	var destination_access_purpose := str(
		values.get(
			"destination_access_purpose",
			CityObjectCatalog.CONTAINER_HAUL_PURPOSE_NONE
		)
	)

	if (
		requested_amount <= 0
		or not CityResourceCatalog.is_city_resource_type(resource)
		or not CityCitizens.is_valid_city_citizen_haul_endpoint(source)
		or not CityCitizens.is_valid_city_citizen_haul_endpoint(
			destination
		)
	):
		return {}

	var destination_space := get_city_haul_endpoint_unreserved_destination_space(
		destination
	)

	if destination_space <= 0:
		return {}

	return {
		"citizen_id": citizen_id,
		"source": source,
		"destination": destination,
		"resource": resource,
		"requested_amount": requested_amount,
		"source_access_purpose": source_access_purpose,
		"destination_access_purpose": destination_access_purpose,
		"cargo_resources": CityCitizenInventorySystem.get_city_citizen_haul_cargo_resources(citizen_id),
		"cargo_amount": CityCitizenInventorySystem.get_city_citizen_haul_cargo_amount(citizen_id),
		"destination_space": destination_space,
		"source_reserved_amount": 0,
		"destination_resources": {},
	}

static func _prepare_city_haul_reservation_amounts(
	context: Dictionary
) -> bool:
	if int(context.get("cargo_amount", 0)) > 0:
		return _prepare_loaded_city_haul_reservation(context)

	return _prepare_pending_city_haul_reservation(context)

static func _prepare_loaded_city_haul_reservation(
	context: Dictionary
) -> bool:
	var destination: Dictionary = context.get("destination", {})
	var maximum_reserved := mini(
		int(context.get("requested_amount", 0)),
		mini(
			int(context.get("cargo_amount", 0)),
			int(context.get("destination_space", 0))
		)
	)
	var destination_resources := _normalize_city_haul_resource_manifest(
		context.get("cargo_resources", {}),
		maximum_reserved
	)

	if (
		str(
			destination.get(
				"kind",
				CityCitizens.CITY_CITIZEN_HAUL_ENDPOINT_KIND_NONE
			)
		)
		== CityCitizens.CITY_CITIZEN_HAUL_ENDPOINT_KIND_CONSTRUCTION_SITE
	):
		for cargo_resource in destination_resources.keys():
			var resource_space := (
				get_city_haul_endpoint_unreserved_destination_resource_space(
					destination,
					str(cargo_resource)
				)
			)
			var capped_amount := mini(
				int(destination_resources.get(cargo_resource, 0)),
				resource_space
			)

			if capped_amount > 0:
				destination_resources[cargo_resource] = capped_amount
			else:
				destination_resources.erase(cargo_resource)

	for cargo_resource in destination_resources.keys():
		if not city_haul_endpoint_can_accept_resource({
			"endpoint": destination,
			"resource": str(cargo_resource),
			"deposit_purpose": str(context.get("destination_access_purpose", "")),
			"require_unreserved_space": true,
		}):
			return false

	context["destination_resources"] = destination_resources
	return _get_city_haul_resource_manifest_total(destination_resources) > 0

static func _prepare_pending_city_haul_reservation(
	context: Dictionary
) -> bool:
	var citizen_id := int(context.get("citizen_id", -1))
	var source: Dictionary = context.get("source", {})
	var destination: Dictionary = context.get("destination", {})
	var resource := str(context.get("resource", WorldData.RESOURCE_NONE))
	var source_access_purpose := str(
		context.get("source_access_purpose", CityObjectCatalog.CONTAINER_HAUL_PURPOSE_NONE)
	)
	var destination_access_purpose := str(
		context.get(
			"destination_access_purpose",
			CityObjectCatalog.CONTAINER_HAUL_PURPOSE_NONE
		)
	)

	if not city_haul_endpoint_can_provide_resource({
		"endpoint": source,
		"resource": resource,
		"withdrawal_purpose": source_access_purpose,
		"require_unreserved_amount": true,
	}):
		return false

	if not city_haul_endpoint_can_accept_resource({
		"endpoint": destination,
		"resource": resource,
		"deposit_purpose": destination_access_purpose,
		"require_unreserved_space": true,
	}):
		return false

	var reservable_amount := mini(
		int(context.get("requested_amount", 0)),
		mini(
			CityCitizenInventorySystem.get_city_citizen_available_haul_capacity(citizen_id),
			mini(
				get_city_haul_endpoint_unreserved_resource_amount(
					source,
					resource
				),
				mini(
					int(context.get("destination_space", 0)),
					get_city_haul_endpoint_unreserved_destination_resource_space(
						destination,
						resource
					)
				)
			)
		)
	)

	if reservable_amount <= 0:
		return false

	context["source_reserved_amount"] = reservable_amount
	context["destination_resources"] = {resource: reservable_amount}
	return true

static func _commit_city_haul_reservation(
	context: Dictionary
) -> Dictionary:
	var destination_resources: Dictionary = context.get(
		"destination_resources",
		{}
	)
	var destination_reserved_amount := (
		_get_city_haul_resource_manifest_total(destination_resources)
	)

	if destination_reserved_amount <= 0:
		return {}

	var reservation_id := _state().next_haul_reservation_id
	var citizen_id := int(context.get("citizen_id", -1))
	var source: Dictionary = context.get("source", {})
	var destination: Dictionary = context.get("destination", {})
	var resource := str(context.get("resource", WorldData.RESOURCE_NONE))
	var source_reserved_amount := int(
		context.get("source_reserved_amount", 0)
	)
	var reservation := {
		"id": reservation_id,
		"citizen_id": citizen_id,
		"resource_type": resource,
		"source": source,
		"destination": destination,
		"source_access_purpose": str(
			context.get("source_access_purpose", CityObjectCatalog.CONTAINER_HAUL_PURPOSE_NONE)
		),
		"destination_access_purpose": str(
			context.get(
				"destination_access_purpose",
				CityObjectCatalog.CONTAINER_HAUL_PURPOSE_NONE
			)
		),
		"source_reserved_amount": source_reserved_amount,
		"destination_reserved_amount": destination_reserved_amount,
		"destination_reserved_resources": destination_resources,
		"created_world_minute": SimulationClock.absolute_world_minutes,
	}

	_state().next_haul_reservation_id += 1
	_state().haul_reservations[reservation_id] = reservation
	_state().haul_reservation_id_by_citizen_id[citizen_id] = reservation_id
	_change_city_haul_reserved_source_amount(
		source,
		resource,
		source_reserved_amount
	)
	_change_city_haul_reserved_destination_amount(
		destination,
		destination_reserved_amount
	)
	_mark_city_haul_reservations_changed()
	return reservation.duplicate(true)

static func expand_pending_city_haul_reservation(
	reservation_id: int
) -> int:
	var reservation := get_city_haul_reservation(reservation_id)

	if reservation.is_empty():
		return 0

	# Household demand is a bounded request. Only ordinary public-storage
	# deliveries absorb newly appearing source output while the hauler is still
	# approaching its first source.
	if (
		str(
			reservation.get(
				"destination_access_purpose",
				CityObjectCatalog.CONTAINER_HAUL_PURPOSE_NONE
			)
		)
		!= CityObjectCatalog.CONTAINER_HAUL_PURPOSE_PUBLIC_STORAGE
	):
		return 0

	var citizen_id := int(reservation.get("citizen_id", -1))
	var citizen := CityCitizenRegistrySystem.get_city_citizen_by_id(citizen_id)
	var current_task := CityCitizenTaskRuntimeSystem.get_city_citizen_current_task(citizen_id)
	var current_haul := CityCitizenTaskRuntimeSystem.get_city_citizen_current_haul(citizen_id)
	var haul_phase := str(
		current_haul.get(
			"phase",
			CityCitizens.CITY_CITIZEN_HAUL_PHASE_NONE
		)
	)
	var pre_pickup_phases := [
		CityCitizens.CITY_CITIZEN_HAUL_PHASE_PENDING_SOURCE,
		CityCitizens.CITY_CITIZEN_HAUL_PHASE_TRAVELING_TO_SOURCE,
		CityCitizens.CITY_CITIZEN_HAUL_PHASE_PICKING_UP,
	]

	if (
		citizen.is_empty()
		or not bool(citizen.get("alive", false))
		or str(current_task.get("kind", ""))
		!= CityCitizens.CITY_CITIZEN_TASK_KIND_HAUL
		or int(
			current_haul.get(
				"reservation_id",
				CityCitizens.INVALID_CITY_CITIZEN_HAUL_RESERVATION_ID
			)
		) != reservation_id
		or not pre_pickup_phases.has(haul_phase)
		or CityCitizenInventorySystem.get_city_citizen_haul_cargo_amount(citizen_id) > 0
	):
		return 0

	var old_source_amount := maxi(
		int(reservation.get("source_reserved_amount", 0)),
		0
	)
	var old_destination_amount := maxi(
		int(
			reservation.get("destination_reserved_amount", 0)
		),
		0
	)

	if (
		old_source_amount <= 0
		or old_source_amount != old_destination_amount
	):
		return 0

	var source: Dictionary = reservation.get("source", {})
	var destination: Dictionary = reservation.get("destination", {})
	var resource := str(
		reservation.get("resource_type", WorldData.RESOURCE_NONE)
	)
	var source_access_purpose := str(
		reservation.get(
			"source_access_purpose",
			CityObjectCatalog.CONTAINER_HAUL_PURPOSE_NONE
		)
	)
	var destination_access_purpose := str(
		reservation.get(
			"destination_access_purpose",
			CityObjectCatalog.CONTAINER_HAUL_PURPOSE_NONE
		)
	)

	if (
		not city_haul_endpoint_can_provide_resource({
			"endpoint": source,
			"resource": resource,
			"withdrawal_purpose": source_access_purpose,
			"require_unreserved_amount": true,
			"excluding_reservation_id": reservation_id,
		})
		or not city_haul_endpoint_can_accept_resource({
			"endpoint": destination,
			"resource": resource,
			"deposit_purpose": destination_access_purpose,
			"require_unreserved_space": true,
			"excluding_reservation_id": reservation_id,
		})
	):
		return 0

	var maximum_claim := mini(
		CityCitizenInventorySystem.get_city_citizen_available_haul_capacity(citizen_id),
		mini(
			get_city_haul_endpoint_unreserved_resource_amount(
				source,
				resource,
				reservation_id
			),
			get_city_haul_endpoint_unreserved_destination_space(
				destination,
				reservation_id
			)
		)
	)
	var expanded_amount := maxi(maximum_claim - old_source_amount, 0)

	if expanded_amount <= 0:
		return 0

	var expanded_haul := current_haul.duplicate(true)
	expanded_haul["requested_amount"] = maximum_claim

	if not CityCitizenTaskRuntimeSystem.set_city_citizen_current_haul(citizen_id, expanded_haul):
		return 0

	var destination_resources := (
		get_city_haul_reservation_destination_resources(
			reservation_id
		)
	)
	destination_resources[resource] = (
		maxi(int(destination_resources.get(resource, 0)), 0)
		+ expanded_amount
	)
	reservation["source_reserved_amount"] = maximum_claim
	reservation["destination_reserved_amount"] = maximum_claim
	reservation["destination_reserved_resources"] = destination_resources
	reservation["last_expanded_world_minute"] = (
		SimulationClock.absolute_world_minutes
	)
	_state().haul_reservations[reservation_id] = reservation
	_change_city_haul_reserved_source_amount(
		source,
		resource,
		expanded_amount
	)
	_change_city_haul_reserved_destination_amount(
		destination,
		expanded_amount
	)
	_mark_city_haul_reservations_changed()
	return expanded_amount

static func expand_pending_city_haul_reservations() -> int:
	return expand_pending_city_haul_reservations_for_city_state(
		_get_compatibility_city_state()
	)


static func expand_pending_city_haul_reservations_for_city_state(
	city_state: CitySettlementSimulationState
) -> int:
	if city_state == null:
		return 0

	var expanded_amount := 0

	for reservation in get_city_haul_reservation_snapshot_for_city_state(city_state):
		expanded_amount += _expand_pending_city_haul_reservation_for_city_state(
			city_state,
			int(reservation.get("id", -1))
		)

	return expanded_amount


static func _expand_pending_city_haul_reservation_for_city_state(
	city_state: CitySettlementSimulationState,
	reservation_id: int
) -> int:
	var reservation := get_city_haul_reservation_for_city_state(
		city_state,
		reservation_id
	)

	if (
		reservation.is_empty()
		or str(
			reservation.get(
				"destination_access_purpose",
				CityObjectCatalog.CONTAINER_HAUL_PURPOSE_NONE
			)
		) != CityObjectCatalog.CONTAINER_HAUL_PURPOSE_PUBLIC_STORAGE
	):
		return 0

	var citizen_id := int(reservation.get("citizen_id", -1))
	var citizen := CityCitizenRegistrySystem.get_city_citizen_by_id_for_city_state(
		city_state,
		citizen_id
	)
	var current_task := CityCitizenTaskRuntimeSystem.get_city_citizen_current_task_for_city_state(
		city_state,
		citizen_id
	)
	var current_haul := CityCitizenTaskRuntimeSystem.get_city_citizen_current_haul_for_city_state(
		city_state,
		citizen_id
	)
	var haul_phase := str(
		current_haul.get(
			"phase",
			CityCitizens.CITY_CITIZEN_HAUL_PHASE_NONE
		)
	)
	var pre_pickup_phases := [
		CityCitizens.CITY_CITIZEN_HAUL_PHASE_PENDING_SOURCE,
		CityCitizens.CITY_CITIZEN_HAUL_PHASE_TRAVELING_TO_SOURCE,
		CityCitizens.CITY_CITIZEN_HAUL_PHASE_PICKING_UP,
	]

	if (
		citizen.is_empty()
		or not bool(citizen.get("alive", false))
		or str(current_task.get("kind", ""))
		!= CityCitizens.CITY_CITIZEN_TASK_KIND_HAUL
		or int(
			current_haul.get(
				"reservation_id",
				CityCitizens.INVALID_CITY_CITIZEN_HAUL_RESERVATION_ID
			)
		) != reservation_id
		or not pre_pickup_phases.has(haul_phase)
		or CityCitizenInventorySystem.get_city_citizen_haul_cargo_amount_for_city_state(
			city_state,
			citizen_id
		) > 0
	):
		return 0

	var old_source_amount := maxi(
		int(reservation.get("source_reserved_amount", 0)),
		0
	)
	var old_destination_amount := maxi(
		int(reservation.get("destination_reserved_amount", 0)),
		0
	)

	if old_source_amount <= 0 or old_source_amount != old_destination_amount:
		return 0

	var source: Dictionary = reservation.get("source", {})
	var destination: Dictionary = reservation.get("destination", {})
	var resource := str(
		reservation.get("resource_type", WorldData.RESOURCE_NONE)
	)
	var source_access_purpose := str(
		reservation.get(
			"source_access_purpose",
			CityObjectCatalog.CONTAINER_HAUL_PURPOSE_NONE
		)
	)
	var destination_access_purpose := str(
		reservation.get(
			"destination_access_purpose",
			CityObjectCatalog.CONTAINER_HAUL_PURPOSE_NONE
		)
	)

	if (
		not city_haul_endpoint_can_provide_resource_for_city_state(
			city_state,
			{
				"endpoint": source,
				"resource": resource,
				"withdrawal_purpose": source_access_purpose,
				"require_unreserved_amount": true,
				"excluding_reservation_id": reservation_id,
			}
		)
		or not city_haul_endpoint_can_accept_resource_for_city_state(
			city_state,
			{
				"endpoint": destination,
				"resource": resource,
				"deposit_purpose": destination_access_purpose,
				"require_unreserved_space": true,
				"excluding_reservation_id": reservation_id,
			}
		)
	):
		return 0

	var maximum_claim := mini(
		CityCitizenInventorySystem.get_city_citizen_available_haul_capacity_for_city_state(
			city_state,
			citizen_id
		),
		mini(
			get_city_haul_endpoint_unreserved_resource_amount_for_city_state(
				city_state,
				source,
				resource,
				reservation_id
			),
			get_city_haul_endpoint_unreserved_destination_space_for_city_state(
				city_state,
				destination,
				reservation_id
			)
		)
	)
	var expanded_amount := maxi(maximum_claim - old_source_amount, 0)

	if expanded_amount <= 0:
		return 0

	var expanded_haul := current_haul.duplicate(true)
	expanded_haul["requested_amount"] = maximum_claim

	if not CityCitizenTaskRuntimeSystem.set_city_citizen_current_haul_for_city_state(
		city_state,
		citizen_id,
		expanded_haul
	):
		return 0

	var destination_resources := (
		get_city_haul_reservation_destination_resources_for_city_state(
			city_state,
			reservation_id
		)
	)
	destination_resources[resource] = (
		maxi(int(destination_resources.get(resource, 0)), 0)
		+ expanded_amount
	)
	reservation["source_reserved_amount"] = maximum_claim
	reservation["destination_reserved_amount"] = maximum_claim
	reservation["destination_reserved_resources"] = destination_resources
	reservation["last_expanded_world_minute"] = SimulationClock.absolute_world_minutes
	city_state.logistics_state.haul_reservations[reservation_id] = reservation
	_change_city_haul_reserved_source_amount_for_city_state(
		city_state,
		source,
		resource,
		expanded_amount
	)
	_change_city_haul_reserved_destination_amount_for_city_state(
		city_state,
		destination,
		expanded_amount
	)
	city_state.logistics_state.haul_reservation_version += 1
	city_state.citizen_task_runtime_state.citizen_task_version += 1
	return expanded_amount

static func retarget_city_haul_reservation_source(
	values: Dictionary
) -> int:
	return retarget_city_haul_reservation_source_for_city_state(
		_get_compatibility_city_state(),
		values
	)


static func retarget_city_haul_reservation_source_for_city_state(
	city_state: CitySettlementSimulationState,
	values: Dictionary
) -> int:
	if city_state == null:
		return 0

	var reservation_id := int(values.get("reservation_id", -1))
	var source: Dictionary = values.get("source", {})
	var resource := str(values.get("resource", WorldData.RESOURCE_NONE))
	var requested_amount := int(values.get("requested_amount", 0))
	var source_access_purpose := str(
		values.get(
			"source_access_purpose",
			CityObjectCatalog.CONTAINER_HAUL_PURPOSE_NONE
		)
	)
	var reservation := get_city_haul_reservation_for_city_state(
		city_state,
		reservation_id
	)

	if (
		reservation.is_empty()
		or requested_amount <= 0
		or not CityResourceCatalog.is_city_resource_type(resource)
		or int(reservation.get("source_reserved_amount", 0)) > 0
	):
		return 0

	var citizen_id := int(reservation.get("citizen_id", -1))
	var normalized_source := CityCitizens.make_city_citizen_haul_endpoint(source)
	var destination: Dictionary = reservation.get("destination", {})
	var destination_access_purpose := str(
		reservation.get(
			"destination_access_purpose",
			CityObjectCatalog.CONTAINER_HAUL_PURPOSE_NONE
		)
	)

	if (
		not city_haul_endpoint_can_provide_resource_for_city_state(
			city_state,
			{
				"endpoint": normalized_source,
				"resource": resource,
				"withdrawal_purpose": source_access_purpose,
				"require_unreserved_amount": true,
			}
		)
		or not city_haul_endpoint_can_accept_resource_for_city_state(
			city_state,
			{
				"endpoint": destination,
				"resource": resource,
				"deposit_purpose": destination_access_purpose,
				"require_unreserved_space": true,
				"excluding_reservation_id": reservation_id,
			}
		)
	):
		return 0

	var reserved_amount := mini(
		requested_amount,
		mini(
			CityCitizenInventorySystem.get_city_citizen_available_haul_capacity_for_city_state(
				city_state,
				citizen_id
			),
			mini(
				get_city_haul_endpoint_unreserved_resource_amount_for_city_state(
					city_state,
					normalized_source,
					resource
				),
				mini(
					get_city_haul_endpoint_unreserved_destination_space_for_city_state(
						city_state,
						destination
					),
					get_city_haul_endpoint_unreserved_destination_resource_space_for_city_state(
						city_state,
						destination,
						resource
					)
				)
			)
		)
	)

	if reserved_amount <= 0:
		return 0

	var destination_resources := (
		get_city_haul_reservation_destination_resources_for_city_state(
			city_state,
			reservation_id
		)
	)
	destination_resources[resource] = (
		maxi(int(destination_resources.get(resource, 0)), 0)
		+ reserved_amount
	)
	reservation["source"] = normalized_source
	reservation["resource_type"] = resource
	reservation["source_access_purpose"] = source_access_purpose
	reservation["source_reserved_amount"] = reserved_amount
	reservation["destination_reserved_resources"] = destination_resources
	reservation["destination_reserved_amount"] = (
		_get_city_haul_resource_manifest_total(destination_resources)
	)
	reservation["last_retargeted_world_minute"] = SimulationClock.absolute_world_minutes
	city_state.logistics_state.haul_reservations[reservation_id] = reservation
	_change_city_haul_reserved_source_amount_for_city_state(
		city_state,
		normalized_source,
		resource,
		reserved_amount
	)
	_change_city_haul_reserved_destination_amount_for_city_state(
		city_state,
		destination,
		reserved_amount
	)
	city_state.logistics_state.haul_reservation_version += 1
	city_state.citizen_task_runtime_state.citizen_task_version += 1
	return reserved_amount

static func release_city_haul_reservation(
	reservation_id: int
) -> bool:
	return release_city_haul_reservation_for_city_state(
		_get_compatibility_city_state(),
		reservation_id
	)


static func release_city_haul_reservation_for_city_state(
	city_state: CitySettlementSimulationState,
	reservation_id: int
) -> bool:
	var reservation := get_city_haul_reservation_for_city_state(
		city_state,
		reservation_id
	)

	if reservation.is_empty():
		return false

	var logistics_state := city_state.logistics_state
	var citizen_id := int(reservation.get("citizen_id", -1))
	var resource := str(
		reservation.get("resource_type", WorldData.RESOURCE_NONE)
	)
	var source: Dictionary = reservation.get("source", {})
	var destination: Dictionary = reservation.get("destination", {})
	_change_city_haul_reserved_source_amount_for_city_state(
		city_state,
		source,
		resource,
		-maxi(int(reservation.get("source_reserved_amount", 0)), 0)
	)
	_change_city_haul_reserved_destination_amount_for_city_state(
		city_state,
		destination,
		-maxi(int(reservation.get("destination_reserved_amount", 0)), 0)
	)
	logistics_state.haul_reservations.erase(reservation_id)

	if (
		int(
			logistics_state.haul_reservation_id_by_citizen_id.get(
				citizen_id,
				CityCitizens.INVALID_CITY_CITIZEN_HAUL_RESERVATION_ID
			)
		) == reservation_id
	):
		logistics_state.haul_reservation_id_by_citizen_id.erase(citizen_id)

	logistics_state.haul_reservation_version += 1
	city_state.citizen_task_runtime_state.citizen_task_version += 1
	return true

static func release_city_haul_reservation_for_citizen(
	citizen_id: int
) -> bool:
	return release_city_haul_reservation_for_citizen_for_city_state(
		_get_compatibility_city_state(),
		citizen_id
	)


static func release_city_haul_reservation_for_citizen_for_city_state(
	city_state: CitySettlementSimulationState,
	citizen_id: int
) -> bool:
	return release_city_haul_reservation_for_city_state(
		city_state,
		get_city_haul_reservation_id_for_citizen_for_city_state(
			city_state,
			citizen_id
		)
	)

static func reset_city_ground_pile_state() -> void:
	_state().ground_piles.clear()
	_state().ground_pile_index_by_id.clear()
	_state().next_ground_pile_id = 1
	_mark_city_ground_piles_changed()

static func reset_city_haul_reservation_state() -> void:
	_state().haul_reservations.clear()
	_state().haul_reservation_id_by_citizen_id.clear()
	_state().haul_source_reserved_amount_by_key.clear()
	_state().haul_destination_reserved_amount_by_key.clear()
	_state().next_haul_reservation_id = 1
	_mark_city_haul_reservations_changed()

static func commit_city_haul_source_reservation(
	reservation_id: int,
	picked_up_amount: int
) -> bool:
	return commit_city_haul_source_reservation_for_city_state(
		_get_compatibility_city_state(),
		reservation_id,
		picked_up_amount
	)


static func commit_city_haul_source_reservation_for_city_state(
	city_state: CitySettlementSimulationState,
	reservation_id: int,
	picked_up_amount: int
) -> bool:
	var reservation := get_city_haul_reservation_for_city_state(
		city_state,
		reservation_id
	)

	if reservation.is_empty():
		return false

	var old_source_amount := maxi(
		int(reservation.get("source_reserved_amount", 0)),
		0
	)
	var committed_amount := mini(maxi(picked_up_amount, 0), old_source_amount)
	var source: Dictionary = reservation.get("source", {})
	var destination: Dictionary = reservation.get("destination", {})
	var resource := str(
		reservation.get("resource_type", CityResourceCatalog.RESOURCE_NONE)
	)
	var destination_resources := (
		get_city_haul_reservation_destination_resources_for_city_state(
			city_state,
			reservation_id
		)
	)
	var unpicked_amount := old_source_amount - committed_amount

	_change_city_haul_reserved_source_amount_for_city_state(
		city_state,
		source,
		resource,
		-old_source_amount
	)

	if unpicked_amount > 0:
		var reserved_for_resource := maxi(
			int(destination_resources.get(resource, 0)),
			0
		)
		var final_resource_reservation := maxi(
			reserved_for_resource - unpicked_amount,
			0
		)

		if final_resource_reservation > 0:
			destination_resources[resource] = final_resource_reservation
		else:
			destination_resources.erase(resource)

		_change_city_haul_reserved_destination_amount_for_city_state(
			city_state,
			destination,
			-unpicked_amount
		)

	reservation["source_reserved_amount"] = 0
	reservation["destination_reserved_resources"] = destination_resources
	reservation["destination_reserved_amount"] = (
		_get_city_haul_resource_manifest_total(destination_resources)
	)
	city_state.logistics_state.haul_reservations[reservation_id] = reservation
	city_state.logistics_state.haul_reservation_version += 1
	city_state.citizen_task_runtime_state.citizen_task_version += 1
	return committed_amount > 0

static func release_city_haul_destination_reservation(
	reservation_id: int
) -> bool:
	return release_city_haul_destination_reservation_for_city_state(
		_get_compatibility_city_state(),
		reservation_id
	)


static func release_city_haul_destination_reservation_for_city_state(
	city_state: CitySettlementSimulationState,
	reservation_id: int
) -> bool:
	var reservation := get_city_haul_reservation_for_city_state(
		city_state,
		reservation_id
	)

	if reservation.is_empty():
		return false

	var destination: Dictionary = reservation.get("destination", {})
	var old_destination_amount := maxi(
		int(reservation.get("destination_reserved_amount", 0)),
		0
	)

	_change_city_haul_reserved_destination_amount_for_city_state(
		city_state,
		destination,
		-old_destination_amount
	)
	reservation["destination"] = CityCitizens.make_city_citizen_haul_endpoint()
	reservation["destination_reserved_amount"] = 0
	reservation["destination_reserved_resources"] = {}
	city_state.logistics_state.haul_reservations[reservation_id] = reservation
	city_state.logistics_state.haul_reservation_version += 1
	city_state.citizen_task_runtime_state.citizen_task_version += 1
	return true

static func retarget_city_haul_destination_reservation(
	reservation_id: int,
	destination: Dictionary,
	requested_amount: int,
	destination_access_purpose: String
) -> int:
	return retarget_city_haul_destination_reservation_for_city_state(
		_get_compatibility_city_state(),
		reservation_id,
		destination,
		requested_amount,
		destination_access_purpose
	)


static func retarget_city_haul_destination_reservation_for_city_state(
	city_state: CitySettlementSimulationState,
	reservation_id: int,
	destination: Dictionary,
	requested_amount: int,
	destination_access_purpose: String
) -> int:
	var reservation := get_city_haul_reservation_for_city_state(
		city_state,
		reservation_id
	)

	if (
		reservation.is_empty()
		or requested_amount <= 0
		or destination_access_purpose
		== CityObjectCatalog.CONTAINER_HAUL_PURPOSE_NONE
		or int(reservation.get("source_reserved_amount", 0)) > 0
	):
		return 0

	var citizen_id := int(reservation.get("citizen_id", -1))

	if (
		CityCitizenInventorySystem.get_city_citizen_haul_cargo_amount_for_city_state(
			city_state,
			citizen_id
		) <= 0
	):
		return 0

	var normalized_destination := (
		CityCitizens.make_city_citizen_haul_endpoint(destination)
	)

	if not CityCitizens.is_valid_city_citizen_haul_endpoint(normalized_destination):
		return 0

	var old_destination: Dictionary = reservation.get(
		"destination",
		CityCitizens.make_city_citizen_haul_endpoint()
	)
	var old_destination_amount := maxi(
		int(reservation.get("destination_reserved_amount", 0)),
		0
	)
	var old_destination_resources := (
		get_city_haul_reservation_destination_resources_for_city_state(
			city_state,
			reservation_id
		)
	)
	var old_destination_access_purpose := str(
		reservation.get(
			"destination_access_purpose",
			CityObjectCatalog.CONTAINER_HAUL_PURPOSE_NONE
		)
	)

	if old_destination_amount > 0:
		_change_city_haul_reserved_destination_amount_for_city_state(
			city_state,
			old_destination,
			-old_destination_amount
		)

	reservation["destination"] = CityCitizens.make_city_citizen_haul_endpoint()
	reservation["destination_reserved_amount"] = 0
	reservation["destination_reserved_resources"] = {}
	reservation["destination_access_purpose"] = destination_access_purpose
	city_state.logistics_state.haul_reservations[reservation_id] = reservation

	var reserved_amount := reserve_city_haul_destination_for_city_state(
		city_state,
		reservation_id,
		normalized_destination,
		requested_amount
	)

	if reserved_amount > 0:
		var retargeted_reservation := get_city_haul_reservation_for_city_state(
			city_state,
			reservation_id
		)
		retargeted_reservation["last_retargeted_world_minute"] = (
			SimulationClock.absolute_world_minutes
		)
		city_state.logistics_state.haul_reservations[reservation_id] = (
			retargeted_reservation
		)
		city_state.logistics_state.haul_reservation_version += 1
		city_state.citizen_task_runtime_state.citizen_task_version += 1
		return reserved_amount

	reservation = get_city_haul_reservation_for_city_state(city_state, reservation_id)
	reservation["destination"] = old_destination
	reservation["destination_reserved_amount"] = old_destination_amount
	reservation["destination_reserved_resources"] = old_destination_resources
	reservation["destination_access_purpose"] = old_destination_access_purpose
	city_state.logistics_state.haul_reservations[reservation_id] = reservation

	if old_destination_amount > 0:
		_change_city_haul_reserved_destination_amount_for_city_state(
			city_state,
			old_destination,
			old_destination_amount
		)

	city_state.logistics_state.haul_reservation_version += 1
	city_state.citizen_task_runtime_state.citizen_task_version += 1
	return 0

static func reserve_city_haul_destination(
	reservation_id: int,
	destination: Dictionary,
	requested_amount: int
) -> int:
	return reserve_city_haul_destination_for_city_state(
		_get_compatibility_city_state(),
		reservation_id,
		destination,
		requested_amount
	)


static func reserve_city_haul_destination_for_city_state(
	city_state: CitySettlementSimulationState,
	reservation_id: int,
	destination: Dictionary,
	requested_amount: int
) -> int:
	var reservation := get_city_haul_reservation_for_city_state(
		city_state,
		reservation_id
	)

	if reservation.is_empty() or requested_amount <= 0:
		return 0

	if int(reservation.get("destination_reserved_amount", 0)) > 0:
		return 0

	var normalized_destination := (
		CityCitizens.make_city_citizen_haul_endpoint(destination)
	)
	var citizen_id := int(reservation.get("citizen_id", -1))
	var cargo_resources := (
		CityCitizenInventorySystem.get_city_citizen_haul_cargo_resources_for_city_state(
			city_state,
			citizen_id
		)
	)
	var cargo_amount := (
		CityCitizenInventorySystem.get_city_citizen_haul_cargo_amount_for_city_state(
			city_state,
			citizen_id
		)
	)
	var resources_to_reserve: Dictionary = {}

	if cargo_amount > 0:
		resources_to_reserve = _normalize_city_haul_resource_manifest(
			cargo_resources,
			requested_amount
		)
	else:
		var resource := str(
			reservation.get("resource_type", CityResourceCatalog.RESOURCE_NONE)
		)

		if CityResourceCatalog.is_city_resource_type(resource):
			resources_to_reserve[resource] = requested_amount

	var destination_access_purpose := str(
		reservation.get(
			"destination_access_purpose",
			CityObjectCatalog.CONTAINER_HAUL_PURPOSE_NONE
		)
	)

	for resource in resources_to_reserve.keys():
		if not city_haul_endpoint_can_accept_resource_for_city_state(
			city_state,
			{
				"endpoint": normalized_destination,
				"resource": str(resource),
				"deposit_purpose": destination_access_purpose,
				"require_unreserved_space": true,
				"excluding_reservation_id": reservation_id,
			}
		):
			return 0

	if (
		str(
			normalized_destination.get(
				"kind",
				CityCitizens.CITY_CITIZEN_HAUL_ENDPOINT_KIND_NONE
			)
		)
		== CityCitizens.CITY_CITIZEN_HAUL_ENDPOINT_KIND_CONSTRUCTION_SITE
	):
		for resource in resources_to_reserve.keys():
			var resource_space := (
				get_city_haul_endpoint_unreserved_destination_resource_space_for_city_state(
					city_state,
					normalized_destination,
					str(resource),
					reservation_id
				)
			)
			var capped_amount := mini(
				int(resources_to_reserve.get(resource, 0)),
				resource_space
			)

			if capped_amount > 0:
				resources_to_reserve[resource] = capped_amount
			else:
				resources_to_reserve.erase(resource)

	var reservable_total := mini(
		_get_city_haul_resource_manifest_total(resources_to_reserve),
		get_city_haul_endpoint_unreserved_destination_space_for_city_state(
			city_state,
			normalized_destination,
			reservation_id
		)
	)
	resources_to_reserve = _normalize_city_haul_resource_manifest(
		resources_to_reserve,
		reservable_total
	)
	var reserved_amount := _get_city_haul_resource_manifest_total(
		resources_to_reserve
	)

	if reserved_amount <= 0:
		return 0

	reservation["destination"] = normalized_destination
	reservation["destination_reserved_amount"] = reserved_amount
	reservation["destination_reserved_resources"] = resources_to_reserve
	city_state.logistics_state.haul_reservations[reservation_id] = reservation
	_change_city_haul_reserved_destination_amount_for_city_state(
		city_state,
		normalized_destination,
		reserved_amount
	)
	city_state.logistics_state.haul_reservation_version += 1
	city_state.citizen_task_runtime_state.citizen_task_version += 1
	return reserved_amount

static func commit_city_haul_destination_reservation(
	reservation_id: int,
	resource: String,
	deposited_amount: int
) -> bool:
	return commit_city_haul_destination_reservation_for_city_state(
		_get_compatibility_city_state(),
		reservation_id,
		resource,
		deposited_amount
	)


static func commit_city_haul_destination_reservation_for_city_state(
	city_state: CitySettlementSimulationState,
	reservation_id: int,
	resource: String,
	deposited_amount: int
) -> bool:
	var reservation := get_city_haul_reservation_for_city_state(
		city_state,
		reservation_id
	)

	if reservation.is_empty():
		return false

	var destination: Dictionary = reservation.get("destination", {})
	var destination_resources := (
		get_city_haul_reservation_destination_resources_for_city_state(
			city_state,
			reservation_id
		)
	)
	var old_resource_amount := maxi(
		int(destination_resources.get(resource, 0)),
		0
	)
	var committed_amount := mini(maxi(deposited_amount, 0), old_resource_amount)

	if committed_amount <= 0:
		return false

	var remaining_resource_amount := old_resource_amount - committed_amount

	if remaining_resource_amount > 0:
		destination_resources[resource] = remaining_resource_amount
	else:
		destination_resources.erase(resource)

	_change_city_haul_reserved_destination_amount_for_city_state(
		city_state,
		destination,
		-committed_amount
	)
	var remaining_reserved_amount := (
		_get_city_haul_resource_manifest_total(destination_resources)
	)
	reservation["destination_reserved_amount"] = remaining_reserved_amount
	reservation["destination_reserved_resources"] = destination_resources

	if remaining_reserved_amount <= 0:
		reservation["destination"] = CityCitizens.make_city_citizen_haul_endpoint()

	city_state.logistics_state.haul_reservations[reservation_id] = reservation
	city_state.logistics_state.haul_reservation_version += 1
	city_state.citizen_task_runtime_state.citizen_task_version += 1
	return true


#endregion

#region Citizen Identity and Population Creation
