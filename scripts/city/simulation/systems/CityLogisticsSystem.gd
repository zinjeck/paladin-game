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
	return WorldPoliticalState.get_current_city_logistics_state()


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
		return CityCitizensScript.make_city_citizen_haul_endpoint()

	return CityCitizensScript.make_city_citizen_haul_endpoint({
		"kind": WorldData.CITY_CITIZEN_HAUL_ENDPOINT_KIND_CONSTRUCTION_SITE,
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
		return CityCitizensScript.make_city_citizen_haul_endpoint()

	return CityCitizensScript.make_city_citizen_haul_endpoint({
		"kind": (
			WorldData.CITY_CITIZEN_HAUL_ENDPOINT_KIND_CITY_OBJECT_CONTAINER
		),
		"id": object_id,
	})

static func make_city_ground_pile_haul_endpoint(
	ground_pile_id: int
) -> Dictionary:
	if ground_pile_id <= 0:
		return CityCitizensScript.make_city_citizen_haul_endpoint()

	return CityCitizensScript.make_city_citizen_haul_endpoint({
		"kind": WorldData.CITY_CITIZEN_HAUL_ENDPOINT_KIND_GROUND_PILE,
		"id": ground_pile_id,
	})

static func make_city_ground_tile_haul_endpoint(
	tile_position: Vector2i,
	excluded_ground_pile_ids: Array[int] = []
) -> Dictionary:
	if (
		tile_position == WorldData.INVALID_CITY_TILE_POSITION
		or not can_city_ground_pile_exist_at_tile(
			WorldData.official_city_world,
			tile_position
		)
	):
		return CityCitizensScript.make_city_citizen_haul_endpoint()

	return CityCitizensScript.make_city_citizen_haul_endpoint({
		"kind": WorldData.CITY_CITIZEN_HAUL_ENDPOINT_KIND_GROUND_TILE,
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
				WorldData.CITY_CITIZEN_HAUL_ENDPOINT_KIND_NONE
			)
		)
	var kind_b := str(
			endpoint_b.get(
				"kind",
				WorldData.CITY_CITIZEN_HAUL_ENDPOINT_KIND_NONE
			)
		)

	if kind_a != kind_b:
		return false

	if kind_a == WorldData.CITY_CITIZEN_HAUL_ENDPOINT_KIND_GROUND_TILE:
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
	var pile_index := get_city_ground_pile_index_by_id(
		ground_pile_id
	)

	if pile_index < 0:
		return {}

	var raw_ground_pile = _state().ground_piles[pile_index]

	if not raw_ground_pile is Dictionary:
		return {}

	return raw_ground_pile.duplicate(true)

static func get_city_ground_pile_snapshot() -> Array:
	return _state().ground_piles.duplicate(true)

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
				WorldData.INVALID_CITY_TILE_POSITION
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
	for raw_ground_pile in _state().ground_piles:
		if not raw_ground_pile is Dictionary:
			continue

		var ground_pile: Dictionary = raw_ground_pile

		if (
			ground_pile.get(
				"tile_position",
				WorldData.INVALID_CITY_TILE_POSITION
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
	if city_world == null:
		return false

	if not city_world.is_in_bounds(tile_position.x, tile_position.y):
		return false

	if CityObjectSystem.has_city_object_at_tile(tile_position):
		return false

	var tile := city_world.get_tile(tile_position.x, tile_position.y)

	return (
		bool(tile.get("is_land", false))
		and str(tile.get("terrain", WorldData.TERRAIN_WATER))
		!= WorldData.TERRAIN_WATER
		and str(tile.get("terrain", WorldData.TERRAIN_WATER))
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
			WorldData.INVALID_CITY_TILE_POSITION
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
	var tile_position: Vector2i = values.get(
		"tile_position",
		WorldData.INVALID_CITY_TILE_POSITION
	)
	var resource := str(values.get("resource", WorldData.RESOURCE_NONE))
	var amount_delta := int(values.get("amount_delta", 0))
	var construction_site_id := int(values.get("construction_site_id", -1))
	var excluded_ground_pile_ids: Array[int] = []
	excluded_ground_pile_ids.assign(
		values.get("excluded_ground_pile_ids", [])
	)
	var result := {
		"added_amount": 0,
		"placements": [],
	}

	if amount_delta <= 0:
		return result

	if not WorldData.is_city_resource_type(resource):
		return result

	if (
		construction_site_id > 0
		and CityConstructionSystem.get_city_construction_site_by_id(
			construction_site_id
		).is_empty()
	):
		return result

	if not can_city_ground_pile_exist_at_tile(
		WorldData.official_city_world,
		tile_position
	):
		return result

	var remaining_amount := amount_delta
	var placements: Array = []
	var merge_target_index := (
		_find_city_ground_pile_merge_target_index(
			tile_position,
			resource,
			construction_site_id,
			excluded_ground_pile_ids
		)
	)

	if merge_target_index >= 0:
		var merge_target: Dictionary = (
			_state().ground_piles[merge_target_index]
		)
		var merged_amount := mini(
			remaining_amount,
			get_city_ground_pile_free_space(merge_target)
		)

		if merged_amount > 0:
			merge_target["amount"] = (
				maxi(int(merge_target.get("amount", 0)), 0)
				+ merged_amount
			)
			_state().ground_piles[merge_target_index] = merge_target
			placements.append({
				"ground_pile_id": int(
					merge_target.get("id", -1)
				),
				"amount": merged_amount,
			})
			remaining_amount -= merged_amount

	while remaining_amount > 0:
		var pile_amount := mini(
			remaining_amount,
			CITY_GROUND_PILE_CAPACITY
		)
		var ground_pile := {
			"id": _state().next_ground_pile_id,
			"tile_position": tile_position,
			"resource_type": resource,
			"amount": pile_amount,
		}

		if construction_site_id > 0:
			ground_pile["construction_site_id"] = (
				construction_site_id
			)

		_state().next_ground_pile_id += 1
		_state().ground_piles.append(ground_pile)
		_state().ground_pile_index_by_id[int(ground_pile["id"])] = (
			_state().ground_piles.size() - 1
		)
		placements.append({
			"ground_pile_id": int(ground_pile["id"]),
			"amount": pile_amount,
		})
		remaining_amount -= pile_amount

	result["added_amount"] = amount_delta
	result["placements"] = placements
	_mark_city_ground_piles_changed()
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
	if not WorldData.is_city_resource_type(resource):
		return false

	if not raw_placements is Array:
		return false

	var placements: Array = raw_placements

	for placement_index in range(
		placements.size() - 1,
		-1,
		-1
	):
		var raw_placement = placements[placement_index]

		if not raw_placement is Dictionary:
			return false

		var placement: Dictionary = raw_placement
		var ground_pile_id := int(
			placement.get("ground_pile_id", -1)
		)
		var amount := maxi(
			int(placement.get("amount", 0)),
			0
		)

		if ground_pile_id <= 0 or amount <= 0:
			return false

		if remove_resource_from_city_ground_pile(
			ground_pile_id,
			resource,
			amount
		) != amount:
			return false

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
	reservation_id: int = WorldData.INVALID_CITY_CITIZEN_HAUL_RESERVATION_ID
) -> int:
	if requested_amount <= 0:
		return 0

	var pile_index := get_city_ground_pile_index_by_id(
		ground_pile_id
	)

	if pile_index < 0:
		return 0

	var raw_ground_pile = _state().ground_piles[pile_index]

	if not raw_ground_pile is Dictionary:
		return 0

	var ground_pile: Dictionary = raw_ground_pile
	var current_amount := get_city_ground_pile_resource_amount(
		ground_pile,
		resource
	)

	if current_amount <= 0:
		return 0

	var endpoint := make_city_ground_pile_haul_endpoint(
		ground_pile_id
	)
	var other_reserved_amount := (
		get_city_haul_endpoint_source_reserved_amount(
			endpoint,
			resource,
			reservation_id
		)
	)
	var removable_amount := maxi(
		current_amount - other_reserved_amount,
		0
	)

	if reservation_id > 0:
		var reservation := get_city_haul_reservation(
			reservation_id
		)

		if (
			reservation.is_empty()
			or not city_citizen_haul_endpoints_match(
				reservation.get("source", {}),
				endpoint
			)
			or str(
				reservation.get("resource_type", WorldData.RESOURCE_NONE)
			)
			!= resource
		):
			return 0

		removable_amount = mini(
			removable_amount,
			maxi(
				int(
					reservation.get(
						"source_reserved_amount",
						0
					)
				),
				0
			)
		)

	var removed_amount := mini(
		requested_amount,
		removable_amount
	)

	if removed_amount <= 0:
		return 0

	var final_amount := current_amount - removed_amount

	if final_amount > 0:
		ground_pile["amount"] = final_amount
		_state().ground_piles[pile_index] = ground_pile
	else:
		_state().ground_piles.remove_at(pile_index)
		rebuild_city_ground_pile_index()

	_mark_city_ground_piles_changed()
	return removed_amount

static func reserve_city_ground_pile_for_construction(
	ground_pile_id: int,
	site_id: int,
	requested_amount: int
) -> int:
	var site := CityConstructionSystem.get_city_construction_site_by_id(site_id)
	var pile_index := get_city_ground_pile_index_by_id(ground_pile_id)

	if site.is_empty() or pile_index < 0 or requested_amount <= 0:
		return 0

	var ground_pile: Dictionary = _state().ground_piles[pile_index]

	if city_ground_pile_is_construction_reserved(ground_pile):
		return 0

	var raw_tile_position = ground_pile.get(
		"tile_position",
		WorldData.INVALID_CITY_TILE_POSITION
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
	var endpoint := make_city_ground_pile_haul_endpoint(
		ground_pile_id
	)
	var source_reserved_amount := (
		get_city_haul_endpoint_source_reserved_amount(
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
		_state().ground_piles[pile_index] = ground_pile
		_mark_city_ground_piles_changed()
		return reservable_amount

	ground_pile["amount"] = current_amount - reservable_amount
	_state().ground_piles[pile_index] = ground_pile

	var add_result := add_resource_to_city_ground_piles_with_result({
		"tile_position": raw_tile_position,
		"resource": resource,
		"amount_delta": reservable_amount,
		"construction_site_id": site_id,
	})

	if int(add_result.get("added_amount", 0)) != reservable_amount:
		ground_pile["amount"] = current_amount
		_state().ground_piles[pile_index] = ground_pile
		_mark_city_ground_piles_changed()
		return 0

	_mark_city_ground_piles_changed()
	return reservable_amount

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
		endpoint.get("kind", WorldData.CITY_CITIZEN_HAUL_ENDPOINT_KIND_NONE)
	)

	if endpoint_kind == WorldData.CITY_CITIZEN_HAUL_ENDPOINT_KIND_GROUND_TILE:
		var raw_tile = endpoint.get(
			"tile_position",
			WorldData.INVALID_CITY_TILE_POSITION
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
	if amount_delta == 0:
		return

	var key := _get_city_haul_source_reservation_key(
		endpoint,
		resource
	)
	var final_amount := (
		int(_state().haul_source_reserved_amount_by_key.get(key, 0))
		+ amount_delta
	)

	if final_amount > 0:
		_state().haul_source_reserved_amount_by_key[key] = final_amount
	else:
		_state().haul_source_reserved_amount_by_key.erase(key)

static func _change_city_haul_reserved_destination_amount(
	endpoint: Dictionary,
	amount_delta: int
) -> void:
	if amount_delta == 0:
		return

	var key := _get_city_haul_endpoint_key(endpoint)
	var final_amount := (
		int(
			_state().haul_destination_reserved_amount_by_key.get(
				key,
				0
			)
		)
		+ amount_delta
	)

	if final_amount > 0:
		_state().haul_destination_reserved_amount_by_key[key] = (
			final_amount
		)
	else:
		_state().haul_destination_reserved_amount_by_key.erase(key)

static func get_city_haul_reservation(
	reservation_id: int
) -> Dictionary:
	if reservation_id <= 0:
		return {}

	var raw_reservation = _state().haul_reservations.get(
		reservation_id,
		{}
	)

	if not raw_reservation is Dictionary:
		return {}

	return raw_reservation.duplicate(true)

static func get_city_haul_reservation_snapshot() -> Array:
	var reservation_snapshot: Array = []
	var reservation_ids: Array = _state().haul_reservations.keys()
	reservation_ids.sort()

	for raw_reservation_id in reservation_ids:
		var reservation := get_city_haul_reservation(
			int(raw_reservation_id)
		)

		if reservation.is_empty():
			continue

		reservation_snapshot.append(reservation)

	return reservation_snapshot

static func city_haul_reservation_is_soft(
	reservation_id: int
) -> bool:
	var reservation := get_city_haul_reservation(reservation_id)

	if reservation.is_empty():
		return false

	var citizen_id := int(reservation.get("citizen_id", -1))

	# A reservation remains transferable until its owner has physically picked
	# up any cargo. Source claims and travel plans are promises; cargo in hand is
	# the hard commitment boundary.
	return (
		citizen_id > 0
		and WorldData.get_city_citizen_haul_cargo_amount(citizen_id) <= 0
		and int(reservation.get("source_reserved_amount", 0)) > 0
		and int(reservation.get("destination_reserved_amount", 0)) > 0
	)

static func get_city_soft_haul_reservation_ids_for_destination_resource(
	destination: Dictionary,
	resource: String,
	excluding_citizen_id: int = -1
) -> Array[int]:
	var reservation_ids: Array[int] = []

	if not WorldData.is_city_resource_type(resource):
		return reservation_ids

	for raw_reservation_id in _state().haul_reservations.keys():
		var reservation_id := int(raw_reservation_id)

		if not city_haul_reservation_is_soft(reservation_id):
			continue

		var reservation := get_city_haul_reservation(reservation_id)

		if (
			int(reservation.get("citizen_id", -1)) == excluding_citizen_id
			or not city_citizen_haul_endpoints_match(
				reservation.get("destination", {}),
				destination
			)
			or get_city_haul_reservation_destination_resource_amount(
				reservation_id,
				resource
			) <= 0
		):
			continue

		reservation_ids.append(reservation_id)

	# Newer, still-unpicked assignments yield first. Older soft claims retain a
	# small fairness advantage without becoming stronger than physical cargo.
	reservation_ids.sort()
	reservation_ids.reverse()
	return reservation_ids

static func get_city_soft_haul_destination_reserved_resource_amount(
	destination: Dictionary,
	resource: String,
	excluding_citizen_id: int = -1
) -> int:
	var reserved_amount := 0

	for reservation_id in (
		get_city_soft_haul_reservation_ids_for_destination_resource(
			destination,
			resource,
			excluding_citizen_id
		)
	):
		reserved_amount += (
			get_city_haul_reservation_destination_resource_amount(
				reservation_id,
				resource
			)
		)

	return reserved_amount

static func release_soft_city_haul_reservation_for_reassignment(
	reservation_id: int
) -> bool:
	if not city_haul_reservation_is_soft(reservation_id):
		return false

	var reservation := get_city_haul_reservation(reservation_id)
	var citizen_id := int(reservation.get("citizen_id", -1))
	var current_task := CityCitizenTaskRuntimeSystem.get_city_citizen_current_task(citizen_id)
	var current_haul := CityCitizenTaskRuntimeSystem.get_city_citizen_current_haul(citizen_id)
	var task_source := str(
		current_task.get(
			"source",
			WorldData.CITY_CITIZEN_TASK_SOURCE_AUTONOMY
		)
	)
	var owns_task := (
		str(current_task.get("kind", ""))
		== WorldData.CITY_CITIZEN_TASK_KIND_HAUL
		and int(current_haul.get("reservation_id", -1)) == reservation_id
	)

	if not release_city_haul_reservation(reservation_id):
		return false

	if owns_task:
		CityCitizenMovementRuntimeSystem.cancel_city_citizen_movement(citizen_id)
		CityCitizenTaskRuntimeSystem.clear_city_citizen_task(citizen_id, task_source)

	return true

static func reduce_soft_city_haul_reservation_for_reassignment(
	reservation_id: int,
	resource: String,
	requested_amount: int
) -> int:
	if (
		requested_amount <= 0
		or not WorldData.is_city_resource_type(resource)
		or not city_haul_reservation_is_soft(reservation_id)
	):
		return 0

	var reservation := get_city_haul_reservation(reservation_id)
	var reserved_resource := str(
		reservation.get("resource_type", WorldData.RESOURCE_NONE)
	)
	var source_reserved_amount := maxi(
		int(reservation.get("source_reserved_amount", 0)),
		0
	)
	var destination_resources := (
		get_city_haul_reservation_destination_resources(reservation_id)
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
			if release_soft_city_haul_reservation_for_reassignment(
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
		destination_resources[resource] = (
			remaining_destination_resource_amount
		)
	else:
		destination_resources.erase(resource)

	reservation["source_reserved_amount"] = remaining_source_amount
	reservation["destination_reserved_resources"] = destination_resources
	reservation["destination_reserved_amount"] = (
		_get_city_haul_resource_manifest_total(destination_resources)
	)
	reservation["last_reduced_world_minute"] = (
		SimulationClock.absolute_world_minutes
	)
	_state().haul_reservations[reservation_id] = reservation
	_change_city_haul_reserved_source_amount(
		source,
		resource,
		-released_amount
	)
	_change_city_haul_reserved_destination_amount(
		destination,
		-released_amount
	)

	var current_haul := CityCitizenTaskRuntimeSystem.get_city_citizen_current_haul(citizen_id)

	if int(current_haul.get("reservation_id", -1)) == reservation_id:
		current_haul["requested_amount"] = remaining_source_amount
		CityCitizenTaskRuntimeSystem.set_city_citizen_current_haul(citizen_id, current_haul)

	_mark_city_haul_reservations_changed()
	return released_amount

static func preempt_soft_city_haul_reservations_for_destination_resource(
	destination: Dictionary,
	resource: String,
	requested_amount: int,
	excluding_citizen_id: int = -1
) -> Dictionary:
	var released_amount := 0
	var released_reservation_ids: Array[int] = []
	var reduced_reservation_ids: Array[int] = []
	var target_amount := maxi(requested_amount, 0)

	if target_amount <= 0 or not WorldData.is_city_resource_type(resource):
		return {
			"released_amount": 0,
			"released_reservation_ids": released_reservation_ids,
			"reduced_reservation_ids": reduced_reservation_ids,
		}

	for reservation_id in (
		get_city_soft_haul_reservation_ids_for_destination_resource(
			destination,
			resource,
			excluding_citizen_id
		)
	):
		var amount_still_needed := target_amount - released_amount

		if amount_still_needed <= 0:
			break

		var original_reserved_amount := (
			get_city_haul_reservation_destination_resource_amount(
				reservation_id,
				resource
			)
		)

		if original_reserved_amount <= 0:
			continue

		var released_from_reservation := (
			reduce_soft_city_haul_reservation_for_reassignment(
				reservation_id,
				resource,
				amount_still_needed
			)
		)

		if released_from_reservation <= 0:
			continue

		released_amount += released_from_reservation

		if get_city_haul_reservation(reservation_id).is_empty():
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
	return int(
		_state().haul_reservation_id_by_citizen_id.get(
			citizen_id,
			WorldData.INVALID_CITY_CITIZEN_HAUL_RESERVATION_ID
		)
	)

static func get_city_haul_endpoint_source_reserved_amount(
	endpoint: Dictionary,
	resource: String,
	excluding_reservation_id: int = (
		WorldData.INVALID_CITY_CITIZEN_HAUL_RESERVATION_ID
	)
) -> int:
	var key := _get_city_haul_source_reservation_key(
		endpoint,
		resource
	)
	var reserved_amount := maxi(
		int(_state().haul_source_reserved_amount_by_key.get(key, 0)),
		0
	)

	if excluding_reservation_id <= 0:
		return reserved_amount

	var reservation := get_city_haul_reservation(
		excluding_reservation_id
	)

	if (
		not reservation.is_empty()
		and city_citizen_haul_endpoints_match(
			reservation.get("source", {}),
			endpoint
		)
		and str(
			reservation.get("resource_type", WorldData.RESOURCE_NONE)
		)
		== resource
	):
		reserved_amount -= maxi(
			int(
				reservation.get(
					"source_reserved_amount",
					0
				)
			),
			0
		)

	return maxi(reserved_amount, 0)

static func get_city_haul_endpoint_destination_reserved_amount(
	endpoint: Dictionary,
	excluding_reservation_id: int = (
		WorldData.INVALID_CITY_CITIZEN_HAUL_RESERVATION_ID
	)
) -> int:
	var key := _get_city_haul_endpoint_key(endpoint)
	var reserved_amount := maxi(
		int(
			_state().haul_destination_reserved_amount_by_key.get(
				key,
				0
			)
		),
		0
	)

	if excluding_reservation_id <= 0:
		return reserved_amount

	var reservation := get_city_haul_reservation(
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
			int(
				reservation.get(
					"destination_reserved_amount",
					0
				)
			),
			0
		)

	return maxi(reserved_amount, 0)

static func get_city_haul_endpoint_resource_amount(
	endpoint: Dictionary,
	resource: String
) -> int:
	var endpoint_kind := str(
		endpoint.get(
			"kind",
			WorldData.CITY_CITIZEN_HAUL_ENDPOINT_KIND_NONE
		)
	)
	var endpoint_id := int(endpoint.get("id", -1))

	match endpoint_kind:
		WorldData.CITY_CITIZEN_HAUL_ENDPOINT_KIND_CITY_OBJECT_CONTAINER:
			return CityResourceContainerSystem.get_city_object_stored_resource_amount(
				CityObjectSystem.get_city_object_by_id(endpoint_id),
				resource
			)

		WorldData.CITY_CITIZEN_HAUL_ENDPOINT_KIND_GROUND_PILE:
			return get_city_ground_pile_resource_amount(
				get_city_ground_pile_by_id(endpoint_id),
				resource
			)

	return 0

static func get_city_haul_endpoint_unreserved_resource_amount(
	endpoint: Dictionary,
	resource: String,
	excluding_reservation_id: int = (
		WorldData.INVALID_CITY_CITIZEN_HAUL_RESERVATION_ID
	),
	excluding_food_citizen_id: int = -1
) -> int:
	var food_task_reserved_amount := (
		CityCitizenTaskRuntimeSystem.get_city_food_task_reserved_endpoint_amount(
			str(
				endpoint.get(
					"kind",
					WorldData.CITY_CITIZEN_HAUL_ENDPOINT_KIND_NONE
				)
			),
			int(endpoint.get("id", -1)),
			resource,
			excluding_food_citizen_id
		)
	)

	return maxi(
		get_city_haul_endpoint_resource_amount(endpoint, resource)
		- get_city_haul_endpoint_source_reserved_amount(
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
		WorldData.INVALID_CITY_CITIZEN_HAUL_RESERVATION_ID
	)
) -> int:
	var endpoint_kind := str(
		endpoint.get(
			"kind",
			WorldData.CITY_CITIZEN_HAUL_ENDPOINT_KIND_NONE
		)
	)
	var endpoint_id := int(endpoint.get("id", -1))

	if endpoint_kind == WorldData.CITY_CITIZEN_HAUL_ENDPOINT_KIND_CONSTRUCTION_SITE:
		return CityConstructionSystem.get_city_construction_site_unreserved_total_space(
			endpoint_id,
			excluding_reservation_id
		)

	if endpoint_kind == WorldData.CITY_CITIZEN_HAUL_ENDPOINT_KIND_GROUND_TILE:
		var raw_tile = endpoint.get(
			"tile_position",
			WorldData.INVALID_CITY_TILE_POSITION
		)

		if (
			not raw_tile is Vector2i
			or not can_city_ground_pile_exist_at_tile(
				WorldData.official_city_world,
				raw_tile
			)
		):
			return 0

		return maxi(
			CITY_GROUND_DROP_RESERVATION_CAPACITY
			- get_city_haul_endpoint_destination_reserved_amount(
				endpoint,
				excluding_reservation_id
			),
			0
		)

	if (
		endpoint_kind
		!= WorldData.CITY_CITIZEN_HAUL_ENDPOINT_KIND_CITY_OBJECT_CONTAINER
	):
		return 0

	var city_object := CityObjectSystem.get_city_object_by_id(endpoint_id)

	if city_object.is_empty():
		return 0

	return maxi(
		CityResourceContainerSystem.get_city_object_storage_free_space(city_object)
		- get_city_haul_endpoint_destination_reserved_amount(
			endpoint,
			excluding_reservation_id
		),
		0
	)

static func get_city_haul_endpoint_unreserved_destination_resource_space(
	endpoint: Dictionary,
	resource: String,
	excluding_reservation_id: int = (
		WorldData.INVALID_CITY_CITIZEN_HAUL_RESERVATION_ID
	)
) -> int:
	if (
		str(
			endpoint.get(
				"kind",
				WorldData.CITY_CITIZEN_HAUL_ENDPOINT_KIND_NONE
			)
		)
		== WorldData.CITY_CITIZEN_HAUL_ENDPOINT_KIND_CONSTRUCTION_SITE
	):
		return CityConstructionSystem.get_city_construction_site_unreserved_resource_space(
			int(endpoint.get("id", -1)),
			resource,
			excluding_reservation_id
		)

	return get_city_haul_endpoint_unreserved_destination_space(
		endpoint,
		excluding_reservation_id
	)

static func city_haul_endpoint_can_provide_resource(
	values: Dictionary
) -> bool:
	var endpoint: Dictionary = values.get("endpoint", {})
	var resource := str(values.get("resource", WorldData.RESOURCE_NONE))
	var withdrawal_purpose := str(
		values.get("withdrawal_purpose", WorldData.CONTAINER_HAUL_PURPOSE_NONE)
	)
	var require_unreserved_amount := bool(
		values.get("require_unreserved_amount", true)
	)
	var excluding_reservation_id := int(
		values.get(
			"excluding_reservation_id",
			WorldData.INVALID_CITY_CITIZEN_HAUL_RESERVATION_ID
		)
	)
	var endpoint_kind := str(
		endpoint.get(
			"kind",
			WorldData.CITY_CITIZEN_HAUL_ENDPOINT_KIND_NONE
		)
	)
	var endpoint_id := int(endpoint.get("id", -1))

	if endpoint_id <= 0:
		return false

	match endpoint_kind:
		WorldData.CITY_CITIZEN_HAUL_ENDPOINT_KIND_CITY_OBJECT_CONTAINER:
			if not CityResourceContainerSystem.city_object_can_provide_haul_resource(
				CityObjectSystem.get_city_object_by_id(endpoint_id),
				resource,
				withdrawal_purpose
			):
				return false

		WorldData.CITY_CITIZEN_HAUL_ENDPOINT_KIND_GROUND_PILE:
			var ground_pile := get_city_ground_pile_by_id(
				endpoint_id
			)

			if (
				not [
					WorldData.CONTAINER_HAUL_PURPOSE_GROUND_PILE_CLEANUP,
					WorldData.CONTAINER_HAUL_PURPOSE_CONSTRUCTION,
					WorldData.CONTAINER_HAUL_PURPOSE_HOUSEHOLD_FOOD_SOURCE,
				].has(withdrawal_purpose)
				or city_ground_pile_is_construction_reserved(
					ground_pile
				)
				or get_city_ground_pile_resource_amount(
					ground_pile,
					resource
				) <= 0
			):
				return false

		_:
			return false

	return (
		not require_unreserved_amount
		or get_city_haul_endpoint_unreserved_resource_amount(
			endpoint,
			resource,
			excluding_reservation_id
		) > 0
	)

static func city_haul_endpoint_can_accept_resource(
	values: Dictionary
) -> bool:
	var endpoint: Dictionary = values.get("endpoint", {})
	var resource := str(values.get("resource", WorldData.RESOURCE_NONE))
	var deposit_purpose := str(
		values.get("deposit_purpose", WorldData.CONTAINER_HAUL_PURPOSE_NONE)
	)
	var require_unreserved_space := bool(
		values.get("require_unreserved_space", true)
	)
	var excluding_reservation_id := int(
		values.get(
			"excluding_reservation_id",
			WorldData.INVALID_CITY_CITIZEN_HAUL_RESERVATION_ID
		)
	)
	var endpoint_kind := str(
		endpoint.get(
			"kind",
			WorldData.CITY_CITIZEN_HAUL_ENDPOINT_KIND_NONE
		)
	)
	var endpoint_id := int(endpoint.get("id", -1))

	if endpoint_kind == WorldData.CITY_CITIZEN_HAUL_ENDPOINT_KIND_GROUND_TILE:
		var raw_tile = endpoint.get(
			"tile_position",
			WorldData.INVALID_CITY_TILE_POSITION
		)

		if (
			deposit_purpose
			!= WorldData.CONTAINER_HAUL_PURPOSE_GROUND_PILE_CLEANUP
			or not raw_tile is Vector2i
			or not can_city_ground_pile_exist_at_tile(
				WorldData.official_city_world,
				raw_tile
			)
		):
			return false

		return (
			not require_unreserved_space
			or get_city_haul_endpoint_unreserved_destination_space(
				endpoint,
				excluding_reservation_id
			) > 0
		)

	if endpoint_kind == WorldData.CITY_CITIZEN_HAUL_ENDPOINT_KIND_CONSTRUCTION_SITE:
		var site := CityConstructionSystem.get_city_construction_site_by_id(endpoint_id)

		if (
			site.is_empty()
			or deposit_purpose != WorldData.CONTAINER_HAUL_PURPOSE_CONSTRUCTION
			or str(site.get("phase", ""))
			!= CityConstructionSystem.CITY_CONSTRUCTION_PHASE_GATHERING
		):
			return false

		return (
			not require_unreserved_space
			or CityConstructionSystem.get_city_construction_site_unreserved_resource_space(
				endpoint_id,
				resource,
				excluding_reservation_id
			) > 0
		)

	if (
		endpoint_kind
		!= WorldData.CITY_CITIZEN_HAUL_ENDPOINT_KIND_CITY_OBJECT_CONTAINER
	):
		return false

	var city_object := CityObjectSystem.get_city_object_by_id(
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
		or get_city_haul_endpoint_unreserved_destination_space(
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

		if amount <= 0 or not WorldData.is_city_resource_type(resource):
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
	var reservation := get_city_haul_reservation(reservation_id)

	if reservation.is_empty():
		return {}

	var raw_resources = reservation.get(
		"destination_reserved_resources",
		{}
	)

	if raw_resources is Dictionary and not raw_resources.is_empty():
		return _normalize_city_haul_resource_manifest(raw_resources)

	# Backward compatibility for reservations created by an older snapshot.
	var legacy_resource := str(
		reservation.get("resource_type", WorldData.RESOURCE_NONE)
	)
	var legacy_amount := maxi(
		int(
			reservation.get(
				"destination_reserved_amount",
				0
			)
		),
		0
	)

	if WorldData.is_city_resource_type(legacy_resource) and legacy_amount > 0:
		return {legacy_resource: legacy_amount}

	return {}

static func get_city_haul_reservation_destination_resource_amount(
	reservation_id: int,
	resource: String
) -> int:
	return maxi(
		int(
			get_city_haul_reservation_destination_resources(
				reservation_id
			).get(resource, 0)
		),
		0
	)

static func create_city_haul_reservation(
	values: Dictionary
) -> Dictionary:
	var context := _make_city_haul_reservation_context(values)

	if context.is_empty():
		return {}

	if not _prepare_city_haul_reservation_amounts(context):
		return {}

	return _commit_city_haul_reservation(context)

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

	var source := CityCitizensScript.make_city_citizen_haul_endpoint(
		raw_source
	)
	var destination := CityCitizensScript.make_city_citizen_haul_endpoint(
		raw_destination
	)
	var resource := str(values.get("resource_type", WorldData.RESOURCE_NONE))
	var requested_amount := maxi(int(values.get("requested_amount", 0)), 0)
	var source_access_purpose := str(
		values.get(
			"source_access_purpose",
			WorldData.CONTAINER_HAUL_PURPOSE_NONE
		)
	)
	var destination_access_purpose := str(
		values.get(
			"destination_access_purpose",
			WorldData.CONTAINER_HAUL_PURPOSE_NONE
		)
	)

	if (
		requested_amount <= 0
		or not WorldData.is_city_resource_type(resource)
		or not CityCitizensScript.is_valid_city_citizen_haul_endpoint(source)
		or not CityCitizensScript.is_valid_city_citizen_haul_endpoint(
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
		"cargo_resources": WorldData.get_city_citizen_haul_cargo_resources(citizen_id),
		"cargo_amount": WorldData.get_city_citizen_haul_cargo_amount(citizen_id),
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
				WorldData.CITY_CITIZEN_HAUL_ENDPOINT_KIND_NONE
			)
		)
		== WorldData.CITY_CITIZEN_HAUL_ENDPOINT_KIND_CONSTRUCTION_SITE
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
		context.get("source_access_purpose", WorldData.CONTAINER_HAUL_PURPOSE_NONE)
	)
	var destination_access_purpose := str(
		context.get(
			"destination_access_purpose",
			WorldData.CONTAINER_HAUL_PURPOSE_NONE
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
			WorldData.get_city_citizen_available_haul_capacity(citizen_id),
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
			context.get("source_access_purpose", WorldData.CONTAINER_HAUL_PURPOSE_NONE)
		),
		"destination_access_purpose": str(
			context.get(
				"destination_access_purpose",
				WorldData.CONTAINER_HAUL_PURPOSE_NONE
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
				WorldData.CONTAINER_HAUL_PURPOSE_NONE
			)
		)
		!= WorldData.CONTAINER_HAUL_PURPOSE_PUBLIC_STORAGE
	):
		return 0

	var citizen_id := int(reservation.get("citizen_id", -1))
	var citizen := CityCitizenRegistrySystem.get_city_citizen_by_id(citizen_id)
	var current_task := CityCitizenTaskRuntimeSystem.get_city_citizen_current_task(citizen_id)
	var current_haul := CityCitizenTaskRuntimeSystem.get_city_citizen_current_haul(citizen_id)
	var haul_phase := str(
		current_haul.get(
			"phase",
			WorldData.CITY_CITIZEN_HAUL_PHASE_NONE
		)
	)
	var pre_pickup_phases := [
		WorldData.CITY_CITIZEN_HAUL_PHASE_PENDING_SOURCE,
		WorldData.CITY_CITIZEN_HAUL_PHASE_TRAVELING_TO_SOURCE,
		WorldData.CITY_CITIZEN_HAUL_PHASE_PICKING_UP,
	]

	if (
		citizen.is_empty()
		or not bool(citizen.get("alive", false))
		or str(current_task.get("kind", ""))
		!= WorldData.CITY_CITIZEN_TASK_KIND_HAUL
		or int(
			current_haul.get(
				"reservation_id",
				WorldData.INVALID_CITY_CITIZEN_HAUL_RESERVATION_ID
			)
		) != reservation_id
		or not pre_pickup_phases.has(haul_phase)
		or WorldData.get_city_citizen_haul_cargo_amount(citizen_id) > 0
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
			WorldData.CONTAINER_HAUL_PURPOSE_NONE
		)
	)
	var destination_access_purpose := str(
		reservation.get(
			"destination_access_purpose",
			WorldData.CONTAINER_HAUL_PURPOSE_NONE
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
		WorldData.get_city_citizen_available_haul_capacity(citizen_id),
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
	var expanded_amount := 0

	# Reservation IDs are monotonic, so ascending order is creation order.
	# Older approaching haulers fill their next physical load before a newer
	# citizen can claim newly produced units.
	for reservation in get_city_haul_reservation_snapshot():
		expanded_amount += expand_pending_city_haul_reservation(
			int(reservation.get("id", -1))
		)

	return expanded_amount

static func retarget_city_haul_reservation_source(
	values: Dictionary
) -> int:
	var reservation_id := int(values.get("reservation_id", -1))
	var source: Dictionary = values.get("source", {})
	var resource := str(values.get("resource", WorldData.RESOURCE_NONE))
	var requested_amount := int(values.get("requested_amount", 0))
	var source_access_purpose := str(
		values.get("source_access_purpose", WorldData.CONTAINER_HAUL_PURPOSE_NONE)
	)
	var reservation := get_city_haul_reservation(reservation_id)

	if (
		reservation.is_empty()
		or requested_amount <= 0
		or not WorldData.is_city_resource_type(resource)
		or int(reservation.get("source_reserved_amount", 0)) > 0
	):
		return 0

	var citizen_id := int(reservation.get("citizen_id", -1))
	var normalized_source := (
		CityCitizensScript.make_city_citizen_haul_endpoint(source)
	)
	var destination: Dictionary = reservation.get("destination", {})
	var destination_access_purpose := str(
		reservation.get(
			"destination_access_purpose",
			WorldData.CONTAINER_HAUL_PURPOSE_NONE
		)
	)

	if (
		not city_haul_endpoint_can_provide_resource({
			"endpoint": normalized_source,
			"resource": resource,
			"withdrawal_purpose": source_access_purpose,
			"require_unreserved_amount": true,
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

	# Retargeting adds a new source claim to the destination manifest already
	# held for loaded cargo. Include that existing claim when measuring the
	# remaining space so it cannot be counted a second time.
	var reserved_amount := mini(
		requested_amount,
		mini(
			WorldData.get_city_citizen_available_haul_capacity(citizen_id),
			mini(
			get_city_haul_endpoint_unreserved_resource_amount(
				normalized_source,
				resource
			),
			mini(
				get_city_haul_endpoint_unreserved_destination_space(
					destination
				),
				get_city_haul_endpoint_unreserved_destination_resource_space(
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
		get_city_haul_reservation_destination_resources(
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
		_get_city_haul_resource_manifest_total(
			destination_resources
		)
	)
	reservation["last_retargeted_world_minute"] = (
		SimulationClock.absolute_world_minutes
	)
	_state().haul_reservations[reservation_id] = reservation
	_change_city_haul_reserved_source_amount(
		normalized_source,
		resource,
		reserved_amount
	)
	_change_city_haul_reserved_destination_amount(
		destination,
		reserved_amount
	)
	_mark_city_haul_reservations_changed()
	return reserved_amount

static func release_city_haul_reservation(
	reservation_id: int
) -> bool:
	var reservation := get_city_haul_reservation(reservation_id)

	if reservation.is_empty():
		return false

	var citizen_id := int(reservation.get("citizen_id", -1))
	var resource := str(
		reservation.get("resource_type", WorldData.RESOURCE_NONE)
	)
	var source: Dictionary = reservation.get("source", {})
	var destination: Dictionary = reservation.get(
		"destination",
		{}
	)

	_change_city_haul_reserved_source_amount(
		source,
		resource,
		-maxi(
			int(reservation.get("source_reserved_amount", 0)),
			0
		)
	)
	_change_city_haul_reserved_destination_amount(
		destination,
		-maxi(
			int(
				reservation.get(
					"destination_reserved_amount",
					0
				)
			),
			0
		)
	)
	_state().haul_reservations.erase(reservation_id)

	if (
		int(
			_state().haul_reservation_id_by_citizen_id.get(
				citizen_id,
				WorldData.INVALID_CITY_CITIZEN_HAUL_RESERVATION_ID
			)
		)
		== reservation_id
	):
		_state().haul_reservation_id_by_citizen_id.erase(citizen_id)

	_mark_city_haul_reservations_changed()
	return true

static func release_city_haul_reservation_for_citizen(
	citizen_id: int
) -> bool:
	return release_city_haul_reservation(
		get_city_haul_reservation_id_for_citizen(citizen_id)
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
