extends RefCounted
class_name CitizenNeedsSystem

# Needs remain independent of the citizen's current activity. Hunger can fall
# and food can be eaten while a citizen works, walks, rests, or hauls. Physical
# food is always removed from personal inventory one whole item at a time.
#
# Immediate food allocation is also deliberately one whole item at a time.
# Citizens reassess after each item instead of filling a private pocket toward
# 100 while equally or more hungry citizens are still waiting for shared food.


static func run_tick(
	_tick_index: int,
	minutes_advanced: int
) -> void:
	if (
		minutes_advanced <= 0
		or WorldData.official_city_world == null
		or not WorldData.player_city_founded
		or WorldData.city_citizens.is_empty()
	):
		return

	WorldData.ensure_city_citizen_need_state()
	var citizen_ids: Array[int] = []

	for raw_citizen in WorldData.city_citizens:
		if not raw_citizen is Dictionary:
			continue

		var citizen: Dictionary = raw_citizen
		var citizen_id := int(citizen.get("id", -1))

		if citizen_id > 0 and bool(citizen.get("alive", false)):
			citizen_ids.append(citizen_id)

	for citizen_id in citizen_ids:
		_advance_citizen_hunger(citizen_id, minutes_advanced)
		_take_personal_food_at_current_legal_source(citizen_id)
		_eat_personal_food_if_hungry(citizen_id)


static func get_single_food_allocation_nutrition_cap() -> int:
	var allocation_nutrition_cap := 0

	for resource in WorldData.get_city_food_resource_types():
		var hunger_restore := WorldData.get_city_food_hunger_restore(resource)

		if hunger_restore <= 0:
			continue

		if allocation_nutrition_cap <= 0:
			allocation_nutrition_cap = hunger_restore
		else:
			allocation_nutrition_cap = mini(
				allocation_nutrition_cap,
				hunger_restore
			)

	return allocation_nutrition_cap


static func get_citizen_food_need_nutrition(citizen_id: int) -> int:
	var citizen := WorldData.get_city_citizen_by_id(citizen_id)

	if citizen.is_empty() or not bool(citizen.get("alive", false)):
		return 0

	var personal_food_nutrition := WorldData.get_food_nutrition_in_resource_container(
		WorldData.get_city_citizen_inventory(citizen_id)
	)
	return maxi(
		WorldData.CITIZEN_EAT_TARGET_HUNGER
		- WorldData.get_city_citizen_hunger(citizen_id)
		- personal_food_nutrition,
		0
	)


static func get_citizen_next_food_allocation_nutrition(
	citizen_id: int
) -> int:
	var unmet_nutrition := get_citizen_food_need_nutrition(citizen_id)
	var allocation_nutrition_cap := (
		get_single_food_allocation_nutrition_cap()
	)

	if allocation_nutrition_cap <= 0:
		return 0

	return mini(unmet_nutrition, allocation_nutrition_cap)


static func citizen_should_seek_food(citizen_id: int) -> bool:
	var hunger := WorldData.get_city_citizen_hunger(citizen_id)
	var available_food_capacity := (
		WorldData.get_city_citizen_personal_inventory_free_space(citizen_id)
		if hunger <= WorldData.CITIZEN_CRITICAL_FOOD_SEEK_TRIGGER_HUNGER
		else WorldData.get_city_citizen_inventory_free_space(citizen_id)
	)

	return (
		hunger <= WorldData.CITIZEN_FOOD_SEEK_TRIGGER_HUNGER
		and get_citizen_food_need_nutrition(citizen_id) > 0
		and available_food_capacity > 0
	)


static func citizen_has_critical_food_need(citizen_id: int) -> bool:
	return (
		WorldData.get_city_citizen_hunger(citizen_id)
		<= WorldData.CITIZEN_CRITICAL_FOOD_SEEK_TRIGGER_HUNGER
		and get_citizen_food_need_nutrition(citizen_id) > 0
	)


static func eat_personal_food_if_hungry(citizen_id: int) -> void:
	_eat_personal_food_if_hungry(citizen_id)


static func _advance_citizen_hunger(
	citizen_id: int,
	minutes_advanced: int
) -> void:
	var citizen := WorldData.get_city_citizen_by_id(citizen_id)

	if citizen.is_empty():
		return

	var old_hunger := clampi(
		int(citizen.get("hunger", WorldData.DEFAULT_CITIZEN_HUNGER)),
		0,
		WorldData.MAX_CITIZEN_HUNGER
	)
	var old_remainder := clampi(
		int(citizen.get("hunger_decay_remainder", 0)),
		0,
		WorldData.CITIZEN_HUNGER_DECAY_DENOMINATOR_MINUTES - 1
	)
	var decay_numerator := (
		old_remainder
		+ minutes_advanced * WorldData.CITIZEN_HUNGER_LOSS_PER_DAY
	)
	var hunger_lost := floori(
		float(decay_numerator)
		/ float(WorldData.CITIZEN_HUNGER_DECAY_DENOMINATOR_MINUTES)
	)
	var next_remainder := decay_numerator % (
		WorldData.CITIZEN_HUNGER_DECAY_DENOMINATOR_MINUTES
	)

	WorldData.set_city_citizen_hunger_state(
		citizen_id,
		maxi(old_hunger - hunger_lost, 0),
		next_remainder
	)


static func _take_personal_food_at_current_legal_source(
	citizen_id: int
) -> void:
	var citizen := WorldData.get_city_citizen_by_id(citizen_id)

	if (
		citizen.is_empty()
		or WorldData.get_city_citizen_hunger(citizen_id)
		> WorldData.CITIZEN_FOOD_CARRY_TRIGGER_HUNGER
		or WorldData.get_city_citizen_inventory_free_space(citizen_id) <= 0
		or get_citizen_next_food_allocation_nutrition(citizen_id) <= 0
	):
		return

	var source_endpoints := _get_legal_food_source_endpoints_at_citizen(citizen)

	for raw_source_endpoint in source_endpoints:
		if not raw_source_endpoint is Dictionary:
			continue

		var source_endpoint: Dictionary = raw_source_endpoint

		for resource in WorldData.get_city_food_resource_types():
			if WorldData.get_city_food_hunger_restore(resource) <= 0:
				continue

			var transferred_units := (
				WorldData.transfer_city_food_endpoint_to_citizen_inventory(
					citizen_id,
					source_endpoint,
					resource,
					1
				)
			)

			# One successful transfer is the complete immediate allocation. The
			# eating step runs next, then every hungry citizen competes again using
			# current hunger and the source reservations already owned by others.
			if transferred_units > 0:
				return


static func _get_legal_food_source_endpoints_at_citizen(
	citizen: Dictionary
) -> Array:
	var sources: Array = []
	var raw_citizen_tile = citizen.get(
		"city_tile_position",
		WorldData.INVALID_CITY_TILE_POSITION
	)

	if not raw_citizen_tile is Vector2i:
		return sources

	var citizen_tile: Vector2i = raw_citizen_tile
	var citizen_id := int(citizen.get("id", -1))
	var home_id := int(citizen.get("home_object_id", -1))
	var home := WorldData.get_city_object_by_id(home_id)

	# A resident's own home is always their first legal food source. Other homes
	# never enter this list, even if the citizen is standing beside one.
	if (
		CityResourceMatcher.city_object_is_household_home(home)
		and WorldData.get_city_object_footprint_tiles(home).has(citizen_tile)
	):
		sources.append(CityLogisticsSystem.make_city_citizen_haul_endpoint(home_id))

	# Deliberate travel is owned by the decision system. At the current tile,
	# however, every legal survival source participates in the same endpoint
	# policy, including workplace output and ordinary food piles.
	for storage_tier in (
		WorldData.get_public_city_storage_tiers()
		+ [WorldData.PUBLIC_CITY_STORAGE_TIER_NONE]
	):
		for raw_city_object in WorldData.city_objects:
			if not raw_city_object is Dictionary:
				continue

			var city_object: Dictionary = raw_city_object

			if (
				(
					storage_tier != WorldData.PUBLIC_CITY_STORAGE_TIER_NONE
					and WorldData.get_city_object_public_storage_tier(city_object)
					!= storage_tier
				)
				or (
					storage_tier == WorldData.PUBLIC_CITY_STORAGE_TIER_NONE
					and WorldData.get_city_object_container_type(city_object)
					!= WorldData.CONTAINER_TYPE_WORKPLACE_STORAGE
				)
				or not WorldData.city_object_allows_direct_resource_withdrawal(
					city_object,
					WorldData.CONTAINER_DIRECT_WITHDRAWAL_PURPOSE_PERSONAL_FOOD
				)
			):
				continue

			var interaction_tiles := (
				WorldData.get_city_citizen_direct_withdrawal_target_tiles(
					citizen_id,
					city_object,
					WorldData.CONTAINER_DIRECT_WITHDRAWAL_PURPOSE_PERSONAL_FOOD
				)
			)

			if interaction_tiles.has(citizen_tile):
				sources.append(
					CityLogisticsSystem.make_city_citizen_haul_endpoint(
						int(city_object.get("id", -1))
					)
				)

	for raw_pile in CityLogisticsSystem.get_city_ground_pile_snapshot():
		if not raw_pile is Dictionary:
			continue

		var pile: Dictionary = raw_pile
		var endpoint := CityLogisticsSystem.make_city_ground_pile_haul_endpoint(
			int(pile.get("id", -1))
		)

		if (
			pile.get("tile_position", WorldData.INVALID_CITY_TILE_POSITION)
			== citizen_tile
			and not CityLogisticsSystem.city_ground_pile_is_construction_reserved(pile)
		):
			sources.append(endpoint)

	return sources


static func _eat_personal_food_if_hungry(citizen_id: int) -> void:
	var hunger := WorldData.get_city_citizen_hunger(citizen_id)

	for resource in WorldData.get_city_food_resource_types():
		var hunger_restore := WorldData.get_city_food_hunger_restore(resource)

		if hunger_restore <= 0:
			continue

		while WorldData.get_city_citizen_inventory_resource_amount(
			citizen_id,
			resource
		) > 0:
			# Food remains a whole physical item. Citizens only consume it when
			# every point of nutrition fits, so no restoration is discarded by
			# clamping. A citizen at 90 therefore keeps a 20-point item until 80.
			if (
				hunger + hunger_restore
				> WorldData.CITIZEN_EAT_TARGET_HUNGER
			):
				break

			var removed_amount := (
				WorldData.remove_resource_from_city_citizen_inventory(
					citizen_id,
					resource,
					1
				)
			)

			if removed_amount != 1:
				break

			var citizen := WorldData.get_city_citizen_by_id(citizen_id)
			var hunger_remainder := int(
				citizen.get("hunger_decay_remainder", 0)
			)
			var next_hunger := hunger + hunger_restore

			if not WorldData.set_city_citizen_hunger_state(
				citizen_id,
				next_hunger,
				hunger_remainder
			):
				WorldData.add_resource_to_city_citizen_inventory(
					citizen_id,
					resource,
					1
				)
				return

			hunger = next_hunger

			if hunger >= WorldData.CITIZEN_EAT_TARGET_HUNGER:
				return
