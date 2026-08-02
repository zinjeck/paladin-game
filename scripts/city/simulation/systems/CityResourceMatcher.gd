extends RefCounted
class_name CityResourceMatcher

# File responsibility: Food-demand accounting plus central resource supply, demand, endpoint, and reachability matching. Authoritative inventories remain in WorldData.
# Matching policy lives here; hauling executes the selected physical transfer.

const CityNavigationSystemScript = preload(
	"res://scripts/city/simulation/systems/CityNavigationSystem.gd"
)

const PURPOSE_SURVIVAL_FOOD := "survival_food"
const PURPOSE_HOUSEHOLD_FOOD := "household_food"
const PURPOSE_CONSTRUCTION_SUPPLY := "construction_supply"
const EXACT_PATH_HEURISTIC_WEIGHT: int = 1
const PATH_COST_PERCENT_BASE: int = 100
const NORMAL_HOME_PATH_COST_PERCENT: int = 125
const SURVIVAL_SOURCE_PREFERENCE_HOME: int = 0
const SURVIVAL_SOURCE_PREFERENCE_STOCKPILE: int = 1
const SURVIVAL_SOURCE_PREFERENCE_KEEP: int = 2
const SURVIVAL_SOURCE_PREFERENCE_WORKPLACE: int = 3
const SURVIVAL_SOURCE_PREFERENCE_GROUND_PILE: int = 4

# Resource destinations are scored through one configurable policy boundary.
# The future priority UI can alter these values without rewriting hauling,
# construction, or reservation correctness rules.
const RESOURCE_DEMAND_CATEGORY_PLAYER_COMMAND := "player_command"
const RESOURCE_DEMAND_CATEGORY_HOUSEHOLD := "household"
const RESOURCE_DEMAND_CATEGORY_STORAGE := "storage"
const RESOURCE_DEMAND_CATEGORY_NONE := "none"
const RESOURCE_DEMAND_PRIORITY_MIN: int = -100
const RESOURCE_DEMAND_PRIORITY_MAX: int = 100
const RESOURCE_DEMAND_CATEGORY_SCORE_SCALE: int = 100_000
const RESOURCE_DEMAND_ORDER_RANK_SCORE: int = 250_000
const RESOURCE_DEMAND_FULFILLMENT_SCORE_PER_UNIT: int = 5_000
const RESOURCE_DEMAND_CARGO_READY_BONUS: int = 100_000
const RESOURCE_DEMAND_EXISTING_COMMITMENT_BONUS: int = 75_000
const RESOURCE_DEMAND_PATH_COST_CAP: int = 4_000_000
const MAX_CARGO_DEMAND_PATH_REQUESTS_PER_DECISION: int = 8
const CITY_CARDINAL_PATH_COST: int = 10_000
const CITY_DIAGONAL_PATH_COST: int = 14_142

static var _resource_demand_category_priorities: Dictionary = {
	RESOURCE_DEMAND_CATEGORY_PLAYER_COMMAND: 80,
	RESOURCE_DEMAND_CATEGORY_HOUSEHOLD: 60,
	RESOURCE_DEMAND_CATEGORY_STORAGE: 40,
}


#region Food Supply and Household Demand Accounting



static func city_object_is_household_home(
	city_object: Dictionary
) -> bool:
	return (
		not city_object.is_empty()
		and WorldData.get_city_object_container_type(city_object)
		== WorldData.CONTAINER_TYPE_PRIVATE_HOME_STORAGE
		and WorldData.get_city_object_resident_capacity(city_object) > 0
	)

static func get_city_home_food_target_nutrition(
	home: Dictionary
) -> int:
	if not city_object_is_household_home(home):
		return 0

	return ceili(
		float(
			WorldData.get_city_object_resident_count(home)
			* WorldData.CITIZEN_HUNGER_LOSS_PER_DAY
			* WorldData.HOUSEHOLD_FOOD_TARGET_DAY_NUMERATOR
		)
		/ float(WorldData.HOUSEHOLD_FOOD_TARGET_DAY_DENOMINATOR)
	)


# Compatibility name retained for existing UI/debug callers. The household
# policy now genuinely targets one full citizen-day of food per resident.

static func get_city_home_one_day_food_target_nutrition(
	home: Dictionary
) -> int:
	return get_city_home_food_target_nutrition(home)

static func get_living_city_citizen_count() -> int:
	var living_count := 0

	for raw_citizen in WorldData.city_citizens:
		if not raw_citizen is Dictionary:
			continue

		var citizen: Dictionary = raw_citizen

		if bool(citizen.get("alive", false)):
			living_count += 1

	return living_count

static func get_city_public_food_reserve_target_nutrition() -> int:
	return ceili(
		float(
			get_living_city_citizen_count()
			* WorldData.CITIZEN_HUNGER_LOSS_PER_DAY
			* WorldData.PUBLIC_FOOD_RESERVE_TARGET_DAY_NUMERATOR
		)
		/ float(WorldData.PUBLIC_FOOD_RESERVE_TARGET_DAY_DENOMINATOR)
	)

static func get_city_food_task_reserved_source_amount(
	object_id: int,
	resource: String,
	excluding_citizen_id: int = -1
) -> int:
	return WorldData.get_city_food_task_reserved_endpoint_amount(
		WorldData.CITY_CITIZEN_HAUL_ENDPOINT_KIND_CITY_OBJECT_CONTAINER,
		object_id,
		resource,
		excluding_citizen_id
	)


static func get_city_object_unreserved_food_amount(
	city_object: Dictionary,
	resource: String,
	excluding_citizen_id: int = -1
) -> int:
	if city_object.is_empty() or WorldData.get_city_food_hunger_restore(resource) <= 0:
		return 0

	var object_id := int(city_object.get("id", -1))
	var endpoint := WorldData.make_city_citizen_haul_endpoint(object_id)

	return maxi(
		WorldData.get_city_object_stored_resource_amount(city_object, resource)
		- WorldData.get_city_haul_endpoint_source_reserved_amount(endpoint, resource)
		- get_city_food_task_reserved_source_amount(
			object_id,
			resource,
			excluding_citizen_id
		),
		0
	)

static func get_city_public_unreserved_food_nutrition() -> int:
	var total_nutrition := 0

	for raw_city_object in WorldData.city_objects:
		if not raw_city_object is Dictionary:
			continue

		var city_object: Dictionary = raw_city_object

		if (
			WorldData.get_city_object_public_storage_tier(city_object)
			== WorldData.PUBLIC_CITY_STORAGE_TIER_NONE
			or not WorldData.city_object_container_is_publicly_usable(city_object)
		):
			continue

		for resource in WorldData.get_city_food_resource_types():
			total_nutrition += (
				get_city_object_unreserved_food_amount(city_object, resource)
				* WorldData.get_city_food_hunger_restore(resource)
			)

	return total_nutrition

static func get_city_public_food_surplus_nutrition() -> int:
	return maxi(
		get_city_public_unreserved_food_nutrition()
		- get_city_public_food_reserve_target_nutrition(),
		0
	)

static func get_city_home_stored_food_nutrition(
	home: Dictionary
) -> int:
	if not city_object_is_household_home(home):
		return 0

	return WorldData.get_food_nutrition_in_resource_container(
		home.get("stored_resources", {})
	)

static func get_city_home_incoming_food_nutrition(
	home: Dictionary,
	excluding_reservation_id: int = (
		WorldData.INVALID_CITY_CITIZEN_HAUL_RESERVATION_ID
	)
) -> int:
	if not city_object_is_household_home(home):
		return 0

	var home_endpoint := WorldData.make_city_citizen_haul_endpoint(
		int(home.get("id", -1))
	)
	var incoming_nutrition := 0

	for raw_reservation in WorldData.city_haul_reservations.values():
		if not raw_reservation is Dictionary:
			continue

		var reservation: Dictionary = raw_reservation
		var reservation_id := int(reservation.get("id", -1))

		if reservation_id == excluding_reservation_id:
			continue

		if (
			str(
				reservation.get(
					"destination_access_purpose",
					WorldData.CONTAINER_HAUL_PURPOSE_NONE
				)
			)
			!= WorldData.CONTAINER_HAUL_PURPOSE_HOME_DELIVERY
			or not WorldData.city_citizen_haul_endpoints_match(
				reservation.get("destination", {}),
				home_endpoint
			)
		):
			continue

		var resource := str(
			reservation.get("resource_type", WorldData.RESOURCE_NONE)
		)
		incoming_nutrition += (
			maxi(
				int(
					reservation.get(
						"destination_reserved_amount",
						0
					)
				),
				0
			)
			* WorldData.get_city_food_hunger_restore(resource)
		)

	return incoming_nutrition

static func get_city_home_unfulfilled_food_nutrition(
	home: Dictionary,
	excluding_reservation_id: int = (
		WorldData.INVALID_CITY_CITIZEN_HAUL_RESERVATION_ID
	)
) -> int:
	return maxi(
		get_city_home_food_target_nutrition(home)
		- get_city_home_stored_food_nutrition(home)
		- get_city_home_incoming_food_nutrition(
			home,
			excluding_reservation_id
		),
		0
	)

static func get_city_home_requested_food_units(
	home: Dictionary,
	resource: String,
	excluding_reservation_id: int = (
		WorldData.INVALID_CITY_CITIZEN_HAUL_RESERVATION_ID
	)
) -> int:
	var hunger_restore := WorldData.get_city_food_hunger_restore(resource)

	if hunger_restore <= 0:
		return 0

	var unfulfilled_nutrition := (
		get_city_home_unfulfilled_food_nutrition(
			home,
			excluding_reservation_id
		)
	)

	if unfulfilled_nutrition <= 0:
		return 0

	var pantry_requested_units := ceili(
		float(unfulfilled_nutrition) / float(hunger_restore)
	)
	return pantry_requested_units

static func get_city_home_food_supply_status(
	home: Dictionary
) -> Dictionary:
	return {
		"target_nutrition": (
			get_city_home_food_target_nutrition(home)
		),
		"stored_nutrition": get_city_home_stored_food_nutrition(home),
		"incoming_nutrition": get_city_home_incoming_food_nutrition(home),
		"unfulfilled_nutrition": (
			get_city_home_unfulfilled_food_nutrition(home)
		),
	}

#endregion

#region Resource Demand Policy and Cargo Matching

static func set_resource_demand_category_priority(
	category: String,
	priority_value: int
) -> bool:
	if (
		not _resource_demand_category_priorities.has(category)
		or priority_value < RESOURCE_DEMAND_PRIORITY_MIN
		or priority_value > RESOURCE_DEMAND_PRIORITY_MAX
	):
		return false

	_resource_demand_category_priorities[category] = priority_value
	return true


static func get_resource_demand_category_priority(
	category: String
) -> int:
	return int(
		_resource_demand_category_priorities.get(
			category,
			RESOURCE_DEMAND_PRIORITY_MIN
		)
	)


static func get_resource_demand_category_priorities() -> Dictionary:
	return _resource_demand_category_priorities.duplicate(true)


static func reset_resource_demand_category_priorities() -> void:
	_resource_demand_category_priorities = {
		RESOURCE_DEMAND_CATEGORY_PLAYER_COMMAND: 80,
		RESOURCE_DEMAND_CATEGORY_HOUSEHOLD: 60,
		RESOURCE_DEMAND_CATEGORY_STORAGE: 40,
	}


static func get_resource_demand_category_for_destination(
	destination: Dictionary,
	destination_access_purpose: String
) -> String:
	if (
		str(destination.get("kind", ""))
		== WorldData.CITY_CITIZEN_HAUL_ENDPOINT_KIND_CONSTRUCTION_SITE
	):
		return RESOURCE_DEMAND_CATEGORY_PLAYER_COMMAND

	if (
		destination_access_purpose
		== WorldData.CONTAINER_HAUL_PURPOSE_HOME_DELIVERY
	):
		return RESOURCE_DEMAND_CATEGORY_HOUSEHOLD

	if destination_access_purpose != WorldData.CONTAINER_HAUL_PURPOSE_NONE:
		return RESOURCE_DEMAND_CATEGORY_STORAGE

	return RESOURCE_DEMAND_CATEGORY_NONE


static func get_resource_demand_order_priority_rank_for_destination(
	destination: Dictionary
) -> int:
	if (
		str(destination.get("kind", ""))
		== WorldData.CITY_CITIZEN_HAUL_ENDPOINT_KIND_CONSTRUCTION_SITE
	):
		return _get_construction_order_priority_rank(
			int(destination.get("id", -1))
		)

	return 0


static func score_resource_destination(values: Dictionary) -> int:
	var category := str(
		values.get(
			"category",
			RESOURCE_DEMAND_CATEGORY_NONE
		)
	)
	var category_priority := get_resource_demand_category_priority(category)
	var order_priority_rank := clampi(
		int(values.get("order_priority_rank", 0)),
		0,
		3
	)
	var path_cost := clampi(
		int(values.get("path_cost", RESOURCE_DEMAND_PATH_COST_CAP)),
		0,
		RESOURCE_DEMAND_PATH_COST_CAP
	)
	var fulfillment_amount := maxi(
		int(values.get("fulfillment_amount", 0)),
		0
	)
	var cargo_ready_bonus := (
		RESOURCE_DEMAND_CARGO_READY_BONUS
		if bool(values.get("cargo_ready", false))
		else 0
	)
	var commitment_bonus := (
		RESOURCE_DEMAND_EXISTING_COMMITMENT_BONUS
		if bool(values.get("existing_commitment", false))
		else 0
	)

	return (
		category_priority * RESOURCE_DEMAND_CATEGORY_SCORE_SCALE
		+ order_priority_rank * RESOURCE_DEMAND_ORDER_RANK_SCORE
		+ fulfillment_amount
		* RESOURCE_DEMAND_FULFILLMENT_SCORE_PER_UNIT
		+ cargo_ready_bonus
		+ commitment_bonus
		- path_cost
	)


static func get_best_cargo_resource_demand(
	values: Dictionary
) -> Dictionary:
	var match_result := find_best_cargo_resource_demand(values)
	var candidate = match_result.get("candidate", {})

	if candidate is Dictionary:
		return candidate

	return {}


static func find_best_cargo_resource_demand(
	values: Dictionary
) -> Dictionary:
	# Demand providers stay independent from the hauling executor. Construction
	# is the first command-backed provider; repairs, roads, military supply, or
	# other systems can join this boundary without adding branches to citizen
	# task logic. The shared path budget keeps matching bounded as providers grow.
	var maximum_path_requests := clampi(
		int(
			values.get(
				"max_path_requests",
				MAX_CARGO_DEMAND_PATH_REQUESTS_PER_DECISION
			)
		),
		0,
		MAX_CARGO_DEMAND_PATH_REQUESTS_PER_DECISION
	)
	var provider_values := values.duplicate(false)
	provider_values["max_path_requests"] = maximum_path_requests
	var construction_result := _find_best_cargo_construction_demand(
		provider_values
	)
	var best_candidate = construction_result.get("candidate", {})

	if not best_candidate is Dictionary:
		best_candidate = {}

	return {
		"candidate": best_candidate,
		"path_requests_used": clampi(
			int(construction_result.get("path_requests_used", 0)),
			0,
			maximum_path_requests
		),
	}


static func _find_best_cargo_construction_demand(
	values: Dictionary
) -> Dictionary:
	var raw_city_world = values.get("city_world")
	var raw_start_tile = values.get(
		"start_tile",
		WorldData.INVALID_CITY_TILE_POSITION
	)
	var raw_resources = values.get("resources", {})

	if (
		not raw_city_world is WorldData
		or not raw_start_tile is Vector2i
		or not raw_resources is Dictionary
	):
		return {"candidate": {}, "path_requests_used": 0}

	var city_world: WorldData = raw_city_world
	var start_tile: Vector2i = raw_start_tile
	var resources: Dictionary = raw_resources
	var citizen_id := int(values.get("citizen_id", -1))
	var max_path_requests := clampi(
		int(
			values.get(
				"max_path_requests",
				MAX_CARGO_DEMAND_PATH_REQUESTS_PER_DECISION
			)
		),
		0,
		MAX_CARGO_DEMAND_PATH_REQUESTS_PER_DECISION
	)
	var preliminary_candidates: Array[Dictionary] = []
	var best_candidate: Dictionary = {}

	if (
		citizen_id <= 0
		or resources.is_empty()
		or max_path_requests <= 0
	):
		return {"candidate": best_candidate, "path_requests_used": 0}

	# Build cheap demand descriptors first. Exact route searches are reserved for
	# the strongest bounded candidates, preventing a city with many blueprints
	# from performing one full-city pathfind per site at every cargo boundary.
	for raw_site in CityConstructionSystem.get_city_construction_site_snapshot():
		if not raw_site is Dictionary:
			continue

		var site: Dictionary = raw_site
		var site_id := int(site.get("id", -1))

		if (
			site_id <= 0
			or str(site.get("phase", ""))
			!= WorldData.CITY_CONSTRUCTION_PHASE_GATHERING
		):
			continue

		var destination := (
			WorldData.make_city_construction_site_haul_endpoint(site_id)
		)
		var compatible_resources: Dictionary = {}
		var soft_preemption_amounts: Dictionary = {}
		var compatible_total := 0

		for raw_resource in resources.keys():
			var resource := str(raw_resource)
			var cargo_amount := maxi(
				int(resources.get(raw_resource, 0)),
				0
			)

			if (
				cargo_amount <= 0
				or not WorldData.is_city_resource_type(resource)
			):
				continue

			var unreserved_space := (
				WorldData.get_city_construction_site_unreserved_resource_space(
					site_id,
					resource
				)
			)
			var soft_reserved_space := (
				WorldData.get_city_soft_haul_destination_reserved_resource_amount(
					destination,
					resource,
					citizen_id
				)
			)
			var compatible_amount := mini(
				cargo_amount,
				unreserved_space + soft_reserved_space
			)

			if compatible_amount <= 0:
				continue

			compatible_resources[resource] = compatible_amount
			compatible_total += compatible_amount

			var required_preemption := maxi(
				compatible_amount - unreserved_space,
				0
			)

			if required_preemption > 0:
				soft_preemption_amounts[resource] = required_preemption

		if compatible_total <= 0:
			continue

		var access_tiles := (
			CityConstructionSystem.get_city_construction_site_access_tiles(
				city_world,
				site,
				citizen_id
			)
		)

		if access_tiles.is_empty():
			continue

		var approximate_path_cost := (
			_get_minimum_octile_path_cost(
				start_tile,
				access_tiles
			)
		)
		var order_priority_rank := (
			_get_construction_order_priority_rank(site_id)
		)
		var preliminary_score := score_resource_destination({
			"category": RESOURCE_DEMAND_CATEGORY_PLAYER_COMMAND,
			"order_priority_rank": order_priority_rank,
			"path_cost": approximate_path_cost,
			"fulfillment_amount": compatible_total,
			"cargo_ready": true,
		})
		preliminary_candidates.append({
			"endpoint": destination,
			"access_tiles": access_tiles,
			"available_amount": compatible_total,
			"compatible_resources": compatible_resources,
			"soft_preemption_amounts": soft_preemption_amounts,
			"destination_access_purpose": (
				WorldData.CONTAINER_HAUL_PURPOSE_CONSTRUCTION
			),
			"reason": (
				WorldData.CITY_CITIZEN_HAUL_REASON_CONSTRUCTION_DELIVERY
			),
			"requester": destination,
			"category": RESOURCE_DEMAND_CATEGORY_PLAYER_COMMAND,
			"order_priority_rank": order_priority_rank,
			"preliminary_score": preliminary_score,
			"site_id": site_id,
		})

	preliminary_candidates.sort_custom(
		_sort_preliminary_resource_demand_candidates
	)

	var candidate_count := mini(
		preliminary_candidates.size(),
		max_path_requests
	)
	var path_requests_used := 0

	for candidate_index in range(candidate_count):
		var candidate := preliminary_candidates[
			candidate_index
		].duplicate(true)
		var access_tiles = candidate.get("access_tiles", [])

		if not access_tiles is Array or access_tiles.is_empty():
			continue

		path_requests_used += 1
		var path_result := (
			CityNavigationSystemScript.find_path_to_any_city_tile({
				"city_world": city_world,
				"start_tile": start_tile,
				"destination_tiles": access_tiles,
				"max_expanded_nodes": CityNavigationSystemScript.get_city_wide_path_expansion_limit(city_world),
				"citizen_id": citizen_id,
				"heuristic_weight": EXACT_PATH_HEURISTIC_WEIGHT
			})
		)

		if not bool(path_result.get("success", false)):
			continue

		var raw_destination_tile = path_result.get(
			"destination_tile",
			WorldData.INVALID_CITY_TILE_POSITION
		)
		var raw_path = path_result.get("path", [])

		if not raw_destination_tile is Vector2i or not raw_path is Array:
			continue

		var path_cost := maxi(int(path_result.get("path_cost", 0)), 0)
		candidate.erase("access_tiles")
		candidate.erase("preliminary_score")
		candidate["destination_tile"] = raw_destination_tile
		candidate["path"] = raw_path.duplicate()
		candidate["path_cost"] = path_cost
		candidate["score"] = score_resource_destination({
			"category": candidate.get(
				"category",
				RESOURCE_DEMAND_CATEGORY_PLAYER_COMMAND
			),
			"order_priority_rank": int(
				candidate.get("order_priority_rank", 1)
			),
			"path_cost": path_cost,
			"fulfillment_amount": int(
				candidate.get("available_amount", 0)
			),
			"cargo_ready": true,
		})

		if _resource_demand_candidate_is_better(
			candidate,
			best_candidate
		):
			best_candidate = candidate

	return {
		"candidate": best_candidate,
		"path_requests_used": path_requests_used,
	}

static func _get_minimum_octile_path_cost(
	start_tile: Vector2i,
	destination_tiles: Array
) -> int:
	var best_cost := RESOURCE_DEMAND_PATH_COST_CAP

	for raw_destination_tile in destination_tiles:
		if not raw_destination_tile is Vector2i:
			continue

		var destination_tile: Vector2i = raw_destination_tile
		var delta_x := absi(destination_tile.x - start_tile.x)
		var delta_y := absi(destination_tile.y - start_tile.y)
		var diagonal_steps := mini(delta_x, delta_y)
		var cardinal_steps := maxi(delta_x, delta_y) - diagonal_steps
		var path_cost := (
			diagonal_steps * CITY_DIAGONAL_PATH_COST
			+ cardinal_steps * CITY_CARDINAL_PATH_COST
		)
		best_cost = mini(best_cost, path_cost)

	return best_cost


static func _sort_preliminary_resource_demand_candidates(
	a: Dictionary,
	b: Dictionary
) -> bool:
	var a_score := int(a.get("preliminary_score", -2147483648))
	var b_score := int(b.get("preliminary_score", -2147483648))

	if a_score != b_score:
		return a_score > b_score

	return int(a.get("site_id", -1)) < int(b.get("site_id", -1))


static func _get_construction_order_priority_rank(site_id: int) -> int:
	for raw_order in CityWorkSystem.get_city_work_order_snapshot():
		if (
			raw_order is Dictionary
			and str(raw_order.get("order_type", ""))
			== "construction_site"
			and int(raw_order.get("source_id", -1)) == site_id
		):
			return clampi(int(raw_order.get("priority_rank", 1)), 0, 3)

	return 1


static func _resource_demand_candidate_is_better(
	candidate: Dictionary,
	current_best: Dictionary
) -> bool:
	if candidate.is_empty():
		return false

	if current_best.is_empty():
		return true

	var candidate_score := int(candidate.get("score", 0))
	var best_score := int(current_best.get("score", 0))

	if candidate_score != best_score:
		return candidate_score > best_score

	return int(candidate.get("site_id", -1)) < int(
		current_best.get("site_id", -1)
	)


# Shared supply enumeration for work that still uses the established generic
# haul request/executor. Callers receive legal, unreserved physical endpoints;
# they remain responsible for citizen-specific source-to-destination routing.
#endregion

#region Source Selection

static func find_nearest_eligible_public_storage_source(
	values: Dictionary
) -> Dictionary:
	for storage_tier in WorldData.get_public_city_storage_tiers():
		var source_result := (
			_find_nearest_eligible_public_storage_source_in_tier(
				values,
				storage_tier
			)
		)

		if not source_result.is_empty():
			return source_result

	return {}


static func _find_nearest_eligible_public_storage_source_in_tier(
	values: Dictionary,
	storage_tier: int
) -> Dictionary:
	var raw_city_world = values.get("city_world")
	var raw_start_tile = values.get(
		"start_tile",
		WorldData.INVALID_CITY_TILE_POSITION
	)

	if not raw_city_world is WorldData or not raw_start_tile is Vector2i:
		return {}

	var city_world: WorldData = raw_city_world
	var start_tile: Vector2i = raw_start_tile
	var citizen_id := int(values.get("citizen_id", -1))
	var resource := str(
		values.get("resource_type", WorldData.RESOURCE_NONE)
	)
	var source_access_purpose := str(
		values.get(
			"source_access_purpose",
			WorldData.CONTAINER_HAUL_PURPOSE_NONE
		)
	)
	var requested_amount := maxi(
		int(values.get("requested_amount", 0)),
		0
	)

	if (
		citizen_id <= 0
		or not WorldData.is_city_resource_type(resource)
		or source_access_purpose
		== WorldData.CONTAINER_HAUL_PURPOSE_NONE
	):
		return {}

	var endpoint_ids_by_access_tile: Dictionary = {}
	var source_tiles: Array = []

	for raw_city_object in WorldData.city_objects:
		if not raw_city_object is Dictionary:
			continue

		var city_object: Dictionary = raw_city_object

		if (
			WorldData.get_city_object_public_storage_tier(city_object)
			!= storage_tier
		):
			continue

		var object_id := int(city_object.get("id", -1))
		var endpoint := WorldData.make_city_citizen_haul_endpoint(
			object_id
		)

		if not WorldData.city_haul_endpoint_can_provide_resource({
			"endpoint": endpoint,
			"resource": resource,
			"withdrawal_purpose": source_access_purpose,
			"require_unreserved_amount": true,
		}):
			continue

		for access_tile in get_haul_endpoint_access_tiles(city_world, endpoint):
			if not endpoint_ids_by_access_tile.has(access_tile):
				endpoint_ids_by_access_tile[access_tile] = []
				source_tiles.append(access_tile)

			var endpoint_ids: Array = endpoint_ids_by_access_tile[access_tile]
			endpoint_ids.append(object_id)
			endpoint_ids_by_access_tile[access_tile] = endpoint_ids

	if source_tiles.is_empty():
		return {}

	var path_result := (
		CityNavigationSystemScript.find_path_to_any_city_tile({
			"city_world": city_world,
			"start_tile": start_tile,
			"destination_tiles": source_tiles,
			"max_expanded_nodes": CityNavigationSystemScript.get_city_wide_path_expansion_limit(city_world),
			"citizen_id": citizen_id,
			"heuristic_weight": EXACT_PATH_HEURISTIC_WEIGHT
		})
	)

	if not bool(path_result.get("success", false)):
		return {}

	var raw_source_tile = path_result.get(
		"destination_tile",
		WorldData.INVALID_CITY_TILE_POSITION
	)
	var raw_path = path_result.get("path", [])

	if not raw_source_tile is Vector2i or not raw_path is Array:
		return {}

	var source_tile: Vector2i = raw_source_tile
	var raw_endpoint_ids = endpoint_ids_by_access_tile.get(source_tile, [])

	if not raw_endpoint_ids is Array:
		return {}

	var endpoint_ids: Array = raw_endpoint_ids
	endpoint_ids.sort()

	for raw_endpoint_id in endpoint_ids:
		var endpoint := WorldData.make_city_citizen_haul_endpoint(
			int(raw_endpoint_id)
		)

		if not WorldData.city_haul_endpoint_can_provide_resource({
			"endpoint": endpoint,
			"resource": resource,
			"withdrawal_purpose": source_access_purpose,
			"require_unreserved_amount": true,
		}):
			continue

		var available_amount := (
			WorldData.get_city_haul_endpoint_unreserved_resource_amount(
				endpoint,
				resource
			)
		)

		if requested_amount > 0:
			available_amount = mini(available_amount, requested_amount)

		if available_amount <= 0:
			continue

		return {
			"endpoint": endpoint,
			"source_tile": source_tile,
			"path": raw_path.duplicate(),
			"path_cost": int(path_result.get("path_cost", 0)),
			"available_amount": available_amount,
			"storage_tier": storage_tier,
		}

	return {}


#endregion

#region Single-Resource Destination Selection

static func find_nearest_eligible_destination(
	values: Dictionary
) -> Dictionary:
	# Storage tiers are absolute policy boundaries. A reachable Stockpile wins
	# before the City Keep is even considered, regardless of distance.
	for storage_tier in WorldData.get_public_city_storage_tiers():
		var destination_result := (
			_find_nearest_eligible_destination_in_tier(
				values,
				storage_tier
			)
		)

		if not destination_result.is_empty():
			return destination_result

	return {}


static func _find_nearest_eligible_destination_in_tier(
	values: Dictionary,
	storage_tier: int
) -> Dictionary:
	var raw_city_world = values.get("city_world")
	var raw_start_tile = values.get(
		"start_tile",
		WorldData.INVALID_CITY_TILE_POSITION
	)

	if not raw_city_world is WorldData:
		return {}

	if not raw_start_tile is Vector2i:
		return {}

	var city_world: WorldData = raw_city_world
	var start_tile: Vector2i = raw_start_tile
	var citizen_id := int(values.get("citizen_id", -1))
	var resource := str(
		values.get("resource_type", WorldData.RESOURCE_NONE)
	)
	var destination_access_purpose := str(
		values.get(
			"destination_access_purpose",
			WorldData.CONTAINER_HAUL_PURPOSE_NONE
		)
	)
	var reservation_id := int(
		values.get(
			"reservation_id",
			WorldData.INVALID_CITY_CITIZEN_HAUL_RESERVATION_ID
		)
	)
	var requested_amount := maxi(
		int(values.get("requested_amount", 0)),
		0
	)

	if (
		citizen_id <= 0
		or not WorldData.is_city_resource_type(resource)
		or destination_access_purpose
		== WorldData.CONTAINER_HAUL_PURPOSE_NONE
	):
		return {}

	var endpoint_ids_by_access_tile: Dictionary = {}
	var destination_tiles: Array = []

	# This is the replaceable destination-eligibility policy boundary. The
	# current policy deliberately scans every compatible public container in
	# the city; later radii, priorities, filters, and preferences belong here.
	for raw_city_object in WorldData.city_objects:
		if not raw_city_object is Dictionary:
			continue

		var city_object: Dictionary = raw_city_object

		if (
			WorldData.get_city_object_public_storage_tier(
				city_object
			)
			!= storage_tier
		):
			continue

		var object_id := int(city_object.get("id", -1))

		if object_id <= 0:
			continue

		var endpoint := WorldData.make_city_citizen_haul_endpoint(
			object_id
		)

		if not WorldData.city_haul_endpoint_can_accept_resource({
			"endpoint": endpoint,
			"resource": resource,
			"deposit_purpose": destination_access_purpose,
			"require_unreserved_space": true,
			"excluding_reservation_id": reservation_id,
		}):
			continue

		for access_tile in get_haul_endpoint_access_tiles(
			city_world,
			endpoint
		):
			if not endpoint_ids_by_access_tile.has(access_tile):
				endpoint_ids_by_access_tile[access_tile] = []
				destination_tiles.append(access_tile)

			var endpoint_ids: Array = (
				endpoint_ids_by_access_tile[access_tile]
			)
			endpoint_ids.append(object_id)
			endpoint_ids_by_access_tile[access_tile] = endpoint_ids

	if destination_tiles.is_empty():
		return {}

	var path_result := (
		CityNavigationSystemScript.find_path_to_any_city_tile({
			"city_world": city_world,
			"start_tile": start_tile,
			"destination_tiles": destination_tiles,
			"max_expanded_nodes": CityNavigationSystemScript.get_city_wide_path_expansion_limit(city_world),
			"citizen_id": citizen_id,
			"heuristic_weight": EXACT_PATH_HEURISTIC_WEIGHT
		})
	)

	if not bool(path_result.get("success", false)):
		return {}

	var raw_destination_tile = path_result.get(
		"destination_tile",
		WorldData.INVALID_CITY_TILE_POSITION
	)
	var raw_path = path_result.get("path", [])

	if not raw_destination_tile is Vector2i:
		return {}

	if not raw_path is Array:
		return {}

	var destination_tile: Vector2i = raw_destination_tile
	var raw_endpoint_ids = endpoint_ids_by_access_tile.get(
		destination_tile,
		[]
	)

	if not raw_endpoint_ids is Array:
		return {}

	var endpoint_ids: Array = raw_endpoint_ids
	endpoint_ids.sort()

	for raw_endpoint_id in endpoint_ids:
		var endpoint_id := int(raw_endpoint_id)
		var endpoint := WorldData.make_city_citizen_haul_endpoint(
			endpoint_id
		)

		if not WorldData.city_haul_endpoint_can_accept_resource({
			"endpoint": endpoint,
			"resource": resource,
			"deposit_purpose": destination_access_purpose,
			"require_unreserved_space": true,
			"excluding_reservation_id": reservation_id,
		}):
			continue

		var available_amount := (
			WorldData.get_city_haul_endpoint_unreserved_destination_space(
				endpoint,
				reservation_id
			)
		)

		if requested_amount > 0:
			available_amount = mini(
				available_amount,
				requested_amount
			)

		if available_amount <= 0:
			continue

		return {
			"endpoint": endpoint,
			"destination_tile": destination_tile,
			"path": raw_path.duplicate(),
			"path_cost": int(path_result.get("path_cost", 0)),
			"available_amount": available_amount,
			"storage_tier": storage_tier,
		}

	return {}


#endregion

#region Multi-Resource Destination Selection

static func find_nearest_eligible_destination_for_resources(
	values: Dictionary
) -> Dictionary:
	for storage_tier in WorldData.get_public_city_storage_tiers():
		var destination_result := (
			_find_nearest_eligible_destination_for_resources_in_tier(
				values,
				storage_tier
			)
		)

		if not destination_result.is_empty():
			return destination_result

	return {}


static func _find_nearest_eligible_destination_for_resources_in_tier(
	values: Dictionary,
	storage_tier: int
) -> Dictionary:
	var raw_city_world = values.get("city_world")
	var raw_start_tile = values.get(
		"start_tile",
		WorldData.INVALID_CITY_TILE_POSITION
	)
	var raw_resources = values.get("resources", {})

	if (
		not raw_city_world is WorldData
		or not raw_start_tile is Vector2i
		or not raw_resources is Dictionary
	):
		return {}

	var city_world: WorldData = raw_city_world
	var start_tile: Vector2i = raw_start_tile
	var resources: Dictionary = raw_resources
	var citizen_id := int(values.get("citizen_id", -1))
	var destination_access_purpose := str(
		values.get(
			"destination_access_purpose",
			WorldData.CONTAINER_HAUL_PURPOSE_NONE
		)
	)
	var reservation_id := int(
		values.get(
			"reservation_id",
			WorldData.INVALID_CITY_CITIZEN_HAUL_RESERVATION_ID
		)
	)
	var requested_amount := maxi(
		int(values.get("requested_amount", 0)),
		0
	)

	if (
		citizen_id <= 0
		or resources.is_empty()
		or destination_access_purpose
		== WorldData.CONTAINER_HAUL_PURPOSE_NONE
	):
		return {}

	var endpoint_ids_by_access_tile: Dictionary = {}
	var destination_tiles: Array = []

	for raw_city_object in WorldData.city_objects:
		if not raw_city_object is Dictionary:
			continue

		var city_object: Dictionary = raw_city_object

		if (
			WorldData.get_city_object_public_storage_tier(
				city_object
			)
			!= storage_tier
		):
			continue

		var object_id := int(city_object.get("id", -1))

		if object_id <= 0:
			continue

		var endpoint := WorldData.make_city_citizen_haul_endpoint(
			object_id
		)

		if not _destination_accepts_resource_manifest({
			"destination": endpoint,
			"resources": resources,
			"destination_access_purpose": destination_access_purpose,
			"reservation_id": reservation_id,
		}):
			continue

		for access_tile in get_haul_endpoint_access_tiles(
			city_world,
			endpoint
		):
			if not endpoint_ids_by_access_tile.has(access_tile):
				endpoint_ids_by_access_tile[access_tile] = []
				destination_tiles.append(access_tile)

			var endpoint_ids: Array = (
				endpoint_ids_by_access_tile[access_tile]
			)
			endpoint_ids.append(object_id)
			endpoint_ids_by_access_tile[access_tile] = endpoint_ids

	if destination_tiles.is_empty():
		return {}

	var path_result := (
		CityNavigationSystemScript.find_path_to_any_city_tile({
			"city_world": city_world,
			"start_tile": start_tile,
			"destination_tiles": destination_tiles,
			"max_expanded_nodes": CityNavigationSystemScript.get_city_wide_path_expansion_limit(city_world),
			"citizen_id": citizen_id,
			"heuristic_weight": EXACT_PATH_HEURISTIC_WEIGHT
		})
	)

	if not bool(path_result.get("success", false)):
		return {}

	var raw_destination_tile = path_result.get(
		"destination_tile",
		WorldData.INVALID_CITY_TILE_POSITION
	)
	var raw_path = path_result.get("path", [])

	if not raw_destination_tile is Vector2i or not raw_path is Array:
		return {}

	var destination_tile: Vector2i = raw_destination_tile
	var raw_endpoint_ids = endpoint_ids_by_access_tile.get(
		destination_tile,
		[]
	)

	if not raw_endpoint_ids is Array:
		return {}

	var endpoint_ids: Array = raw_endpoint_ids
	endpoint_ids.sort()

	for raw_endpoint_id in endpoint_ids:
		var endpoint_id := int(raw_endpoint_id)
		var endpoint := WorldData.make_city_citizen_haul_endpoint(
			endpoint_id
		)

		if not _destination_accepts_resource_manifest({
			"destination": endpoint,
			"resources": resources,
			"destination_access_purpose": destination_access_purpose,
			"reservation_id": reservation_id,
		}):
			continue

		var available_amount := (
			WorldData.get_city_haul_endpoint_unreserved_destination_space(
				endpoint,
				reservation_id
			)
		)

		if requested_amount > 0:
			available_amount = mini(
				available_amount,
				requested_amount
			)

		if available_amount <= 0:
			continue

		return {
			"endpoint": endpoint,
			"destination_tile": destination_tile,
			"path": raw_path.duplicate(),
			"path_cost": int(path_result.get("path_cost", 0)),
			"available_amount": available_amount,
			"storage_tier": storage_tier,
		}

	return {}


static func _destination_accepts_resource_manifest(
	values: Dictionary
) -> bool:
	var destination: Dictionary = values.get("destination", {})
	var resources: Dictionary = values.get("resources", {})
	var destination_access_purpose := str(
		values.get(
			"destination_access_purpose",
			WorldData.CONTAINER_HAUL_PURPOSE_NONE
		)
	)
	var reservation_id := int(
		values.get(
			"reservation_id",
			WorldData.INVALID_CITY_CITIZEN_HAUL_RESERVATION_ID
		)
	)
	if resources.is_empty():
		return false

	for raw_resource in resources.keys():
		var resource := str(raw_resource)
		var amount := maxi(int(resources.get(raw_resource, 0)), 0)

		if (
			amount <= 0
			or not WorldData.is_city_resource_type(resource)
			or not WorldData.city_haul_endpoint_can_accept_resource({
				"endpoint": destination,
				"resource": resource,
				"deposit_purpose": destination_access_purpose,
				"require_unreserved_space": true,
				"excluding_reservation_id": reservation_id,
			})
		):
			return false

	return true


static func make_destination_result_for_endpoint_resources(
	values: Dictionary
) -> Dictionary:
	var raw_city_world = values.get("city_world")
	var raw_start_tile = values.get(
		"start_tile",
		WorldData.INVALID_CITY_TILE_POSITION
	)
	var raw_destination = values.get("destination", {})
	var raw_resources = values.get("resources", {})

	if (
		not raw_city_world is WorldData
		or not raw_start_tile is Vector2i
		or not raw_destination is Dictionary
		or not raw_resources is Dictionary
	):
		return {}

	var city_world: WorldData = raw_city_world
	var start_tile: Vector2i = raw_start_tile
	var destination := CityCitizens.make_city_citizen_haul_endpoint(
		raw_destination
	)
	var resources: Dictionary = raw_resources
	var citizen_id := int(values.get("citizen_id", -1))
	var destination_access_purpose := str(
		values.get(
			"destination_access_purpose",
			WorldData.CONTAINER_HAUL_PURPOSE_NONE
		)
	)
	var reservation_id := int(
		values.get(
			"reservation_id",
			WorldData.INVALID_CITY_CITIZEN_HAUL_RESERVATION_ID
		)
	)
	var requested_amount := maxi(
		int(values.get("requested_amount", 0)),
		0
	)

	if not _destination_accepts_resource_manifest({
		"destination": destination,
		"resources": resources,
		"destination_access_purpose": destination_access_purpose,
		"reservation_id": reservation_id,
	}):
		return {}

	var available_amount := (
		WorldData.get_city_haul_endpoint_unreserved_destination_space(
			destination,
			reservation_id
		)
	)

	if reservation_id > 0:
		var reservation := WorldData.get_city_haul_reservation(
			reservation_id
		)

		if (
			reservation.is_empty()
			or int(reservation.get("citizen_id", -1)) != citizen_id
			or not WorldData.city_citizen_haul_endpoints_match(
				reservation.get("destination", {}),
				destination
			)
		):
			return {}

		available_amount = mini(
			available_amount,
			maxi(
				int(
					reservation.get(
						"destination_reserved_amount",
						0
					)
				),
				0
			)
		)

	if requested_amount > 0:
		available_amount = mini(available_amount, requested_amount)

	if available_amount <= 0:
		return {}

	var destination_tiles := get_haul_endpoint_access_tiles(
		city_world,
		destination
	)

	if destination_tiles.is_empty():
		return {}

	var path_result := (
		CityNavigationSystemScript.find_path_to_any_city_tile({
			"city_world": city_world,
			"start_tile": start_tile,
			"destination_tiles": destination_tiles,
			"max_expanded_nodes": CityNavigationSystemScript.get_city_wide_path_expansion_limit(city_world),
			"citizen_id": citizen_id,
			"heuristic_weight": EXACT_PATH_HEURISTIC_WEIGHT
		})
	)

	if not bool(path_result.get("success", false)):
		return {}

	var raw_destination_tile = path_result.get(
		"destination_tile",
		WorldData.INVALID_CITY_TILE_POSITION
	)
	var raw_path = path_result.get("path", [])

	if not raw_destination_tile is Vector2i or not raw_path is Array:
		return {}

	return {
		"endpoint": destination,
		"destination_tile": raw_destination_tile,
		"path": raw_path.duplicate(),
		"path_cost": int(path_result.get("path_cost", 0)),
		"available_amount": available_amount,
		"storage_tier": WorldData.get_city_object_public_storage_tier(
			_get_container_object_for_endpoint(destination)
		),
	}


static func make_destination_result_for_endpoint(
	values: Dictionary
) -> Dictionary:
	var raw_city_world = values.get("city_world")
	var raw_start_tile = values.get(
		"start_tile",
		WorldData.INVALID_CITY_TILE_POSITION
	)
	var raw_destination = values.get("destination", {})

	if (
		not raw_city_world is WorldData
		or not raw_start_tile is Vector2i
		or not raw_destination is Dictionary
	):
		return {}

	var city_world: WorldData = raw_city_world
	var start_tile: Vector2i = raw_start_tile
	var destination := CityCitizens.make_city_citizen_haul_endpoint(
		raw_destination
	)
	var citizen_id := int(values.get("citizen_id", -1))
	var resource := str(
		values.get("resource_type", WorldData.RESOURCE_NONE)
	)
	var destination_access_purpose := str(
		values.get(
			"destination_access_purpose",
			WorldData.CONTAINER_HAUL_PURPOSE_NONE
		)
	)
	var reservation_id := int(
		values.get(
			"reservation_id",
			WorldData.INVALID_CITY_CITIZEN_HAUL_RESERVATION_ID
		)
	)
	var requested_amount := maxi(
		int(values.get("requested_amount", 0)),
		0
	)

	if not WorldData.city_haul_endpoint_can_accept_resource({
		"endpoint": destination,
		"resource": resource,
		"deposit_purpose": destination_access_purpose,
		"require_unreserved_space": true,
		"excluding_reservation_id": reservation_id,
	}):
		return {}

	var available_amount := (
		WorldData.get_city_haul_endpoint_unreserved_destination_space(
			destination,
			reservation_id
		)
	)

	if reservation_id > 0:
		var reservation := WorldData.get_city_haul_reservation(
			reservation_id
		)

		if (
			reservation.is_empty()
			or int(reservation.get("citizen_id", -1)) != citizen_id
			or not WorldData.city_citizen_haul_endpoints_match(
				reservation.get("destination", {}),
				destination
			)
		):
			return {}

		available_amount = mini(
			available_amount,
			maxi(
				int(
					reservation.get(
						"destination_reserved_amount",
						0
					)
				),
				0
			)
		)

	if requested_amount > 0:
		available_amount = mini(available_amount, requested_amount)

	if available_amount <= 0:
		return {}

	var destination_tiles := get_haul_endpoint_access_tiles(
		city_world,
		destination
	)

	if destination_tiles.is_empty():
		return {}

	var path_result := (
		CityNavigationSystemScript.find_path_to_any_city_tile({
			"city_world": city_world,
			"start_tile": start_tile,
			"destination_tiles": destination_tiles,
			"max_expanded_nodes": CityNavigationSystemScript.get_city_wide_path_expansion_limit(city_world),
			"citizen_id": citizen_id,
			"heuristic_weight": EXACT_PATH_HEURISTIC_WEIGHT
		})
	)

	if not bool(path_result.get("success", false)):
		return {}

	var raw_destination_tile = path_result.get(
		"destination_tile",
		WorldData.INVALID_CITY_TILE_POSITION
	)
	var raw_path = path_result.get("path", [])

	if not raw_destination_tile is Vector2i or not raw_path is Array:
		return {}

	return {
		"endpoint": destination,
		"destination_tile": raw_destination_tile,
		"path": raw_path.duplicate(),
		"path_cost": int(path_result.get("path_cost", 0)),
		"available_amount": available_amount,
		"storage_tier": WorldData.get_city_object_public_storage_tier(
			_get_container_object_for_endpoint(destination)
		),
	}


#endregion

#region General Supply Candidate Collection

static func get_resource_supply_candidates(
	purpose: String,
	resource: String,
	requested_amount: int
) -> Array[Dictionary]:
	var candidates: Array[Dictionary] = []

	if (
		purpose != PURPOSE_CONSTRUCTION_SUPPLY
		or not WorldData.is_city_resource_type(resource)
		or requested_amount <= 0
	):
		return candidates

	for raw_object in WorldData.city_objects:
		if not raw_object is Dictionary:
			continue

		var city_object: Dictionary = raw_object

		if not WorldData.city_object_container_is_publicly_usable(city_object):
			continue

		var endpoint := WorldData.make_city_citizen_haul_endpoint(
			int(city_object.get("id", -1))
		)
		_append_supply_candidate({
			"candidates": candidates,
			"endpoint": endpoint,
			"resource": resource,
			"requested_amount": requested_amount,
			"source_access_purpose": (
				WorldData.CONTAINER_HAUL_PURPOSE_CONSTRUCTION
			),
			"source_tier": _get_public_storage_source_tier(city_object),
			"protect_public_food": true,
		})

	for raw_pile in WorldData.get_city_ground_pile_snapshot():
		if (
			not raw_pile is Dictionary
			or WorldData.city_ground_pile_is_construction_reserved(raw_pile)
		):
			continue

		_append_supply_candidate({
			"candidates": candidates,
			"endpoint": WorldData.make_city_ground_pile_haul_endpoint(
				int(raw_pile.get("id", -1))
			),
			"resource": resource,
			"requested_amount": requested_amount,
			"source_access_purpose": (
				WorldData.CONTAINER_HAUL_PURPOSE_CONSTRUCTION
			),
			"source_tier": 2,
			"protect_public_food": false,
		})

	candidates.sort_custom(_sort_supply_candidates)
	return candidates


static func _append_supply_candidate(values: Dictionary) -> void:
	var candidates: Array[Dictionary] = values.get("candidates", [])
	var endpoint: Dictionary = values.get("endpoint", {})
	var resource := str(values.get("resource", WorldData.RESOURCE_NONE))
	var requested_amount := maxi(int(values.get("requested_amount", 0)), 0)
	var source_access_purpose := str(
		values.get(
			"source_access_purpose",
			WorldData.CONTAINER_HAUL_PURPOSE_NONE
		)
	)
	var source_tier := int(values.get("source_tier", 0))
	var protect_public_food := bool(
		values.get("protect_public_food", false)
	)

	if not WorldData.city_haul_endpoint_can_provide_resource({
		"endpoint": endpoint,
		"resource": resource,
		"withdrawal_purpose": source_access_purpose,
		"require_unreserved_amount": true,
	}):
		return

	var available_amount := (
		WorldData.get_city_haul_endpoint_unreserved_resource_amount(
			endpoint,
			resource
		)
	)
	var hunger_restore := WorldData.get_city_food_hunger_restore(resource)

	if protect_public_food and hunger_restore > 0:
		available_amount = mini(
			available_amount,
			floori(
				float(get_city_public_food_surplus_nutrition())
				/ float(hunger_restore)
			)
		)

	available_amount = mini(available_amount, requested_amount)

	if available_amount <= 0:
		return

	candidates.append({
		"endpoint": endpoint,
		"available_amount": available_amount,
		"source_access_purpose": source_access_purpose,
		"source_tier": source_tier,
	})


static func _get_public_storage_source_tier(city_object: Dictionary) -> int:
	if (
		WorldData.get_city_object_public_storage_tier(city_object)
		== WorldData.PUBLIC_CITY_STORAGE_TIER_STOCKPILE
	):
		return 0

	return 1


static func _sort_supply_candidates(a: Dictionary, b: Dictionary) -> bool:
	var tier_a := int(a.get("source_tier", 0))
	var tier_b := int(b.get("source_tier", 0))

	if tier_a != tier_b:
		return tier_a < tier_b

	var endpoint_a = a.get("endpoint", {})
	var endpoint_b = b.get("endpoint", {})

	if not endpoint_a is Dictionary or not endpoint_b is Dictionary:
		return str(a) < str(b)

	var kind_a := str(endpoint_a.get("kind", ""))
	var kind_b := str(endpoint_b.get("kind", ""))

	if kind_a != kind_b:
		return kind_a < kind_b

	return int(endpoint_a.get("id", -1)) < int(endpoint_b.get("id", -1))


#endregion

#region Food Source Matching

static func find_best_survival_food_source(
	citizen: Dictionary,
	desired_nutrition: int,
	available_capacity: int,
	maximum_path_requests: int
) -> Dictionary:
	var citizen_id := int(citizen.get("id", -1))
	var raw_current_tile = citizen.get(
		"city_tile_position",
		WorldData.INVALID_CITY_TILE_POSITION
	)

	if (
		citizen_id <= 0
		or not raw_current_tile is Vector2i
		or desired_nutrition <= 0
		or available_capacity <= 0
		or maximum_path_requests <= 0
	):
		return {}

	var home_candidates: Array[Dictionary] = []
	var alternative_candidates: Array[Dictionary] = []
	var source_groups := _get_survival_source_groups(citizen)
	var source_preference_ranks: Array[int] = [
		SURVIVAL_SOURCE_PREFERENCE_HOME,
		SURVIVAL_SOURCE_PREFERENCE_STOCKPILE,
		SURVIVAL_SOURCE_PREFERENCE_KEEP,
		SURVIVAL_SOURCE_PREFERENCE_WORKPLACE,
		SURVIVAL_SOURCE_PREFERENCE_GROUND_PILE,
	]

	for group_index in range(source_groups.size()):
		var raw_source_group = source_groups[group_index]

		if not raw_source_group is Array:
			continue

		var source_preference_rank := (
			source_preference_ranks[group_index]
			if group_index < source_preference_ranks.size()
			else source_preference_ranks.size()
		)

		for raw_endpoint in raw_source_group:
			if not raw_endpoint is Dictionary:
				continue

			var candidate := _make_survival_endpoint_candidate(
				citizen_id,
				raw_endpoint,
				desired_nutrition,
				available_capacity,
				source_preference_rank
			)

			if candidate.is_empty():
				continue

			if source_preference_rank == SURVIVAL_SOURCE_PREFERENCE_HOME:
				home_candidates.append(candidate)
			else:
				alternative_candidates.append(candidate)

	var current_tile: Vector2i = raw_current_tile
	var is_critical := (
		WorldData.get_city_citizen_hunger(citizen_id)
		<= WorldData.CITIZEN_CRITICAL_FOOD_SEEK_TRIGGER_HUNGER
	)

	# Critical hunger ignores routine source preferences and takes the fastest
	# reachable legal food. With only one path request available, normal hunger
	# also falls back to this complete search rather than hiding valid sources.
	if (
		is_critical
		or home_candidates.is_empty()
		or alternative_candidates.is_empty()
		or maximum_path_requests < 2
	):
		var all_candidates: Array[Dictionary] = []
		all_candidates.append_array(home_candidates)
		all_candidates.append_array(alternative_candidates)
		return _find_best_reachable_source_candidate(
			citizen_id,
			current_tile,
			all_candidates
		)

	# Normal hunger compares the resident's pantry against every other legal
	# source. Home wins when its exact route is at most 25% longer, preserving a
	# useful household routine without sending citizens across the city past a
	# much closer stockpile, workplace, or ground pile.
	var alternative_result := _find_best_reachable_source_candidate(
		citizen_id,
		current_tile,
		alternative_candidates
	)
	var path_requests_used := int(
		alternative_result.get("path_requests_used", 0)
	)
	var home_result: Dictionary = {}

	if path_requests_used < maximum_path_requests:
		home_result = _find_best_reachable_source_candidate(
			citizen_id,
			current_tile,
			home_candidates
		)
		path_requests_used += int(home_result.get("path_requests_used", 0))

	var best_result := _choose_normal_survival_food_result(
		home_result,
		alternative_result
	)

	if not best_result.is_empty():
		best_result["path_requests_used"] = path_requests_used
		return best_result

	return {"path_requests_used": path_requests_used}


static func _choose_normal_survival_food_result(
	home_result: Dictionary,
	alternative_result: Dictionary
) -> Dictionary:
	var home_is_valid := int(home_result.get("source_id", -1)) > 0
	var alternative_is_valid := int(
		alternative_result.get("source_id", -1)
	) > 0

	if not home_is_valid:
		return alternative_result.duplicate(true)

	if not alternative_is_valid:
		return home_result.duplicate(true)

	var home_cost := maxi(int(home_result.get("path_cost", 0)), 0)
	var alternative_cost := maxi(
		int(alternative_result.get("path_cost", 0)),
		0
	)

	if (
		home_cost * PATH_COST_PERCENT_BASE
		<= alternative_cost * NORMAL_HOME_PATH_COST_PERCENT
	):
		return home_result.duplicate(true)

	return alternative_result.duplicate(true)


static func find_best_household_food_source(
	citizen: Dictionary,
	resource: String,
	requested_amount: int,
	maximum_path_requests: int = 32
) -> Dictionary:
	var citizen_id := int(citizen.get("id", -1))
	var raw_current_tile = citizen.get(
		"city_tile_position",
		WorldData.INVALID_CITY_TILE_POSITION
	)

	if (
		citizen_id <= 0
		or not raw_current_tile is Vector2i
		or WorldData.get_city_food_hunger_restore(resource) <= 0
		or requested_amount <= 0
		or maximum_path_requests <= 0
		or get_city_public_food_surplus_nutrition() <= 0
	):
		return {}

	var current_tile: Vector2i = raw_current_tile
	var path_requests_used := 0

	for source_group in _get_household_source_groups():
		if path_requests_used >= maximum_path_requests:
			break

		var candidates: Array[Dictionary] = []

		for raw_source in source_group:
			if not raw_source is Dictionary:
				continue

			var candidate := _make_household_source_candidate(
				citizen_id,
				raw_source,
				resource,
				requested_amount
			)

			if not candidate.is_empty():
				candidates.append(candidate)

		var best_result := _find_best_reachable_source_candidate(
			citizen_id,
			current_tile,
			candidates
		)
		path_requests_used += int(
			best_result.get("path_requests_used", 0)
		)

		if best_result.get("endpoint", {}) is Dictionary and (
			int(best_result.get("available_amount", 0)) > 0
		):
			best_result["path_requests_used"] = path_requests_used
			return best_result

	return {"path_requests_used": path_requests_used}


static func _get_survival_source_groups(
	citizen: Dictionary
) -> Array:
	var own_home_group: Array[Dictionary] = []
	var stockpile_group: Array[Dictionary] = []
	var keep_group: Array[Dictionary] = []
	var workplace_group: Array[Dictionary] = []
	var ground_pile_group: Array[Dictionary] = []
	var home_id := int(citizen.get("home_object_id", -1))
	var home := WorldData.get_city_object_by_id(home_id)

	if city_object_is_household_home(home):
		own_home_group.append(
			WorldData.make_city_citizen_haul_endpoint(home_id)
		)

	for raw_object in WorldData.city_objects:
		if not raw_object is Dictionary:
			continue

		var city_object: Dictionary = raw_object
		var object_id := int(city_object.get("id", -1))
		var endpoint := WorldData.make_city_citizen_haul_endpoint(object_id)
		var storage_tier := WorldData.get_city_object_public_storage_tier(
			city_object
		)

		if storage_tier == WorldData.PUBLIC_CITY_STORAGE_TIER_STOCKPILE:
			stockpile_group.append(endpoint)
		elif storage_tier == WorldData.PUBLIC_CITY_STORAGE_TIER_CITY_KEEP:
			keep_group.append(endpoint)
		elif WorldData.get_city_object_container_type(city_object) == (
			WorldData.CONTAINER_TYPE_WORKPLACE_STORAGE
		):
			workplace_group.append(endpoint)

	for raw_pile in WorldData.get_city_ground_pile_snapshot():
		if (
			not raw_pile is Dictionary
			or WorldData.city_ground_pile_is_construction_reserved(raw_pile)
			or WorldData.get_city_food_hunger_restore(
				str(raw_pile.get("resource_type", WorldData.RESOURCE_NONE))
			) <= 0
		):
			continue

		ground_pile_group.append(
			WorldData.make_city_ground_pile_haul_endpoint(
				int(raw_pile.get("id", -1))
			)
		)

	_sort_endpoint_group(own_home_group)
	_sort_endpoint_group(stockpile_group)
	_sort_endpoint_group(keep_group)
	_sort_endpoint_group(workplace_group)
	_sort_endpoint_group(ground_pile_group)
	return [
		own_home_group,
		stockpile_group,
		keep_group,
		workplace_group,
		ground_pile_group,
	]


static func _get_household_source_groups() -> Array:
	var stockpile_group: Array[Dictionary] = []
	var keep_group: Array[Dictionary] = []
	var workplace_group: Array[Dictionary] = []
	var ground_pile_group: Array[Dictionary] = []

	for raw_object in WorldData.city_objects:
		if not raw_object is Dictionary:
			continue

		var city_object: Dictionary = raw_object
		var endpoint := WorldData.make_city_citizen_haul_endpoint(
			int(city_object.get("id", -1))
		)
		var storage_tier := WorldData.get_city_object_public_storage_tier(
			city_object
		)
		var source := {
			"endpoint": endpoint,
			"source_access_purpose": (
				WorldData.CONTAINER_HAUL_PURPOSE_HOME_DELIVERY
			),
			"protect_public_food": true,
			"source_class": "public_storage",
		}

		if storage_tier == WorldData.PUBLIC_CITY_STORAGE_TIER_STOCKPILE:
			stockpile_group.append(source)
		elif storage_tier == WorldData.PUBLIC_CITY_STORAGE_TIER_CITY_KEEP:
			keep_group.append(source)
		elif WorldData.get_city_object_container_type(city_object) == (
			WorldData.CONTAINER_TYPE_WORKPLACE_STORAGE
		):
			source["source_access_purpose"] = (
				WorldData.CONTAINER_HAUL_PURPOSE_HOUSEHOLD_FOOD_SOURCE
			)
			source["protect_public_food"] = false
			source["source_class"] = "workplace_output"
			workplace_group.append(source)

	for raw_pile in WorldData.get_city_ground_pile_snapshot():
		if (
			not raw_pile is Dictionary
			or WorldData.city_ground_pile_is_construction_reserved(raw_pile)
		):
			continue

		ground_pile_group.append({
			"endpoint": WorldData.make_city_ground_pile_haul_endpoint(
				int(raw_pile.get("id", -1))
			),
			"source_access_purpose": (
				WorldData.CONTAINER_HAUL_PURPOSE_HOUSEHOLD_FOOD_SOURCE
			),
			"protect_public_food": false,
			"source_class": "ground_pile",
		})

	_sort_source_group(stockpile_group)
	_sort_source_group(keep_group)
	_sort_source_group(workplace_group)
	_sort_source_group(ground_pile_group)
	return [
		stockpile_group,
		keep_group,
		workplace_group,
		ground_pile_group,
	]


static func _make_survival_endpoint_candidate(
	citizen_id: int,
	endpoint: Dictionary,
	desired_nutrition: int,
	available_capacity: int,
	source_preference_rank: int
) -> Dictionary:
	var best_resource := WorldData.RESOURCE_NONE
	var requested_amount := 0

	for resource in WorldData.get_city_food_resource_types():
		if not WorldData.city_citizen_can_withdraw_food_from_endpoint(
			citizen_id,
			endpoint,
			resource
		):
			continue

		var hunger_restore := WorldData.get_city_food_hunger_restore(resource)
		var available_amount := (
			WorldData.get_city_food_endpoint_unreserved_amount(
				citizen_id,
				endpoint,
				resource
			)
		)

		if hunger_restore <= 0 or available_amount <= 0:
			continue

		best_resource = resource
		requested_amount = mini(
			available_amount,
			mini(
				available_capacity,
				ceili(float(desired_nutrition) / float(hunger_restore))
			)
		)
		break

	if requested_amount <= 0:
		return {}

	var target_tiles := WorldData.get_city_citizen_food_endpoint_target_tiles(
		citizen_id,
		endpoint
	)

	if target_tiles.is_empty():
		return {}

	return {
		"endpoint": endpoint,
		"source_id": int(endpoint.get("id", -1)),
		"source_kind": str(endpoint.get("kind", "")),
		"object_id": int(endpoint.get("id", -1)),
		"resource_type": best_resource,
		"requested_amount": requested_amount,
		"source_preference_rank": source_preference_rank,
		"candidate_access_tiles": target_tiles,
	}


static func _make_household_source_candidate(
	citizen_id: int,
	source: Dictionary,
	resource: String,
	requested_amount: int
) -> Dictionary:
	var endpoint = source.get("endpoint", {})
	var source_access_purpose := str(
		source.get(
			"source_access_purpose",
			WorldData.CONTAINER_HAUL_PURPOSE_NONE
		)
	)

	if not endpoint is Dictionary:
		return {}

	var available_amount := (
		WorldData.get_city_haul_endpoint_unreserved_resource_amount(
			endpoint,
			resource
		)
	)

	if bool(source.get("protect_public_food", false)):
		available_amount = mini(
			available_amount,
			floori(
				float(get_city_public_food_surplus_nutrition())
				/ float(WorldData.get_city_food_hunger_restore(resource))
			)
		)

	if (
		available_amount <= 0
		or not WorldData.city_haul_endpoint_can_provide_resource({
			"endpoint": endpoint,
			"resource": resource,
			"withdrawal_purpose": source_access_purpose,
			"require_unreserved_amount": true,
		})
	):
		return {}

	var access_tiles := _get_endpoint_access_tiles(endpoint, citizen_id)

	if access_tiles.is_empty():
		return {}

	return {
		"endpoint": endpoint,
		"source_access_purpose": source_access_purpose,
		"available_amount": mini(available_amount, requested_amount),
		"source_class": str(source.get("source_class", "")),
		"candidate_access_tiles": access_tiles,
	}


# One exact multi-destination request resolves an entire strict preference
# tier. Unreachable low-ID endpoints therefore cannot repeatedly consume the
# whole per-tick budget and hide a reachable fallback tier forever.
static func _find_best_reachable_source_candidate(
	citizen_id: int,
	current_tile: Vector2i,
	candidates: Array[Dictionary]
) -> Dictionary:
	var target_tiles: Array = []
	var candidates_by_target_tile: Dictionary = {}

	for candidate in candidates:
		var raw_access_tiles = candidate.get("candidate_access_tiles", [])

		if not raw_access_tiles is Array:
			continue

		for raw_access_tile in raw_access_tiles:
			if not raw_access_tile is Vector2i:
				continue

			var access_tile: Vector2i = raw_access_tile

			if not candidates_by_target_tile.has(access_tile):
				candidates_by_target_tile[access_tile] = []
				target_tiles.append(access_tile)

			var tile_candidates: Array = candidates_by_target_tile[access_tile]
			tile_candidates.append(candidate)
			candidates_by_target_tile[access_tile] = tile_candidates

	if target_tiles.is_empty():
		return {}

	var path_result := CityNavigationSystemScript.find_path_to_any_city_tile({
		"city_world": WorldData.official_city_world,
		"start_tile": current_tile,
		"destination_tiles": target_tiles,
		"max_expanded_nodes": CityNavigationSystemScript.get_city_wide_path_expansion_limit(
			WorldData.official_city_world
		),
		"citizen_id": citizen_id,
		"heuristic_weight": EXACT_PATH_HEURISTIC_WEIGHT,
	})
	if not bool(path_result.get("success", false)):
		return {"path_requests_used": 1}

	var raw_target_tile = path_result.get(
		"destination_tile",
		WorldData.INVALID_CITY_TILE_POSITION
	)

	if (
		not raw_target_tile is Vector2i
		or not candidates_by_target_tile.has(raw_target_tile)
	):
		return {"path_requests_used": 1}

	var best_result: Dictionary = {}
	var path_cost := int(path_result.get("path_cost", 0))

	for raw_candidate in candidates_by_target_tile[raw_target_tile]:
		if not raw_candidate is Dictionary:
			continue

		var result: Dictionary = raw_candidate.duplicate(true)
		result.erase("candidate_access_tiles")
		result["target_tile"] = raw_target_tile
		result["path_cost"] = path_cost
		result["path_requests_used"] = 1

		if _source_result_is_better(result, best_result):
			best_result = result

	return best_result


#endregion

#region Shared Matching Helpers


static func _get_endpoint_access_tiles(
	endpoint: Dictionary,
	citizen_id: int
) -> Array:
	match str(endpoint.get("kind", "")):
		WorldData.CITY_CITIZEN_HAUL_ENDPOINT_KIND_CITY_OBJECT_CONTAINER:
			return WorldData.get_city_object_access_tiles(
				WorldData.official_city_world,
				WorldData.get_city_object_by_id(int(endpoint.get("id", -1)))
			)

		WorldData.CITY_CITIZEN_HAUL_ENDPOINT_KIND_GROUND_PILE:
			var pile := WorldData.get_city_ground_pile_by_id(
				int(endpoint.get("id", -1))
			)
			var raw_tile = pile.get(
				"tile_position",
				WorldData.INVALID_CITY_TILE_POSITION
			)

			if (
				raw_tile is Vector2i
				and WorldData.is_city_tile_walkable_for_citizen(
					WorldData.official_city_world,
					raw_tile,
					citizen_id
				)
			):
				return [raw_tile]

	return []




static func get_haul_endpoint_access_tiles(
	city_world: WorldData,
	endpoint: Dictionary
) -> Array:
	var endpoint_kind := str(
		endpoint.get(
			"kind",
			WorldData.CITY_CITIZEN_HAUL_ENDPOINT_KIND_NONE
		)
	)
	var endpoint_id := int(endpoint.get("id", -1))

	if endpoint_kind == WorldData.CITY_CITIZEN_HAUL_ENDPOINT_KIND_GROUND_PILE:
		var ground_pile := WorldData.get_city_ground_pile_by_id(endpoint_id)
		var raw_tile_position = ground_pile.get(
			"tile_position",
			WorldData.INVALID_CITY_TILE_POSITION
		)

		if raw_tile_position is Vector2i:
			return [raw_tile_position]

		return []

	if endpoint_kind == WorldData.CITY_CITIZEN_HAUL_ENDPOINT_KIND_GROUND_TILE:
		var raw_ground_tile = endpoint.get(
			"tile_position",
			WorldData.INVALID_CITY_TILE_POSITION
		)

		if (
			raw_ground_tile is Vector2i
			and WorldData.can_city_ground_pile_exist_at_tile(
				city_world,
				raw_ground_tile
			)
		):
			return [raw_ground_tile]

		return []

	if (
		endpoint_kind
		== WorldData.CITY_CITIZEN_HAUL_ENDPOINT_KIND_CONSTRUCTION_SITE
	):
		return CityConstructionSystem.get_city_construction_site_access_tiles(
			city_world,
			WorldData.get_city_construction_site_by_id(endpoint_id)
		)

	var city_object := _get_container_object_for_endpoint(endpoint)

	if city_object.is_empty():
		return []

	return WorldData.get_city_object_access_tiles(city_world, city_object)


static func _get_container_object_for_endpoint(
	endpoint: Dictionary
) -> Dictionary:
	if (
		str(
			endpoint.get(
				"kind",
				WorldData.CITY_CITIZEN_HAUL_ENDPOINT_KIND_NONE
			)
		)
		!= WorldData.CITY_CITIZEN_HAUL_ENDPOINT_KIND_CITY_OBJECT_CONTAINER
	):
		return {}

	return WorldData.get_city_object_by_id(int(endpoint.get("id", -1)))


static func _source_result_is_better(
	candidate: Dictionary,
	current_best: Dictionary
) -> bool:
	if candidate.is_empty():
		return false

	if current_best.is_empty():
		return true

	var candidate_cost := int(candidate.get("path_cost", 0))
	var best_cost := int(current_best.get("path_cost", 0))

	if candidate_cost != best_cost:
		return candidate_cost < best_cost

	var candidate_preference := int(
		candidate.get("source_preference_rank", 1_000_000)
	)
	var best_preference := int(
		current_best.get("source_preference_rank", 1_000_000)
	)

	if candidate_preference != best_preference:
		return candidate_preference < best_preference

	var candidate_endpoint = candidate.get("endpoint", {})
	var best_endpoint = current_best.get("endpoint", {})

	if candidate_endpoint is Dictionary and best_endpoint is Dictionary:
		var candidate_kind := str(candidate_endpoint.get("kind", ""))
		var best_kind := str(best_endpoint.get("kind", ""))

		if candidate_kind != best_kind:
			return candidate_kind < best_kind

		return int(candidate_endpoint.get("id", -1)) < int(
			best_endpoint.get("id", -1)
		)

	return false


static func _sort_endpoint_group(group: Array[Dictionary]) -> void:
	group.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			var kind_a := str(a.get("kind", ""))
			var kind_b := str(b.get("kind", ""))

			if kind_a != kind_b:
				return kind_a < kind_b

			return int(a.get("id", -1)) < int(b.get("id", -1))
	)


static func _sort_source_group(group: Array[Dictionary]) -> void:
	group.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			var endpoint_a = a.get("endpoint", {})
			var endpoint_b = b.get("endpoint", {})

			if not endpoint_a is Dictionary or not endpoint_b is Dictionary:
				return str(a) < str(b)

			return int(endpoint_a.get("id", -1)) < int(
				endpoint_b.get("id", -1)
			)
	)

#endregion
