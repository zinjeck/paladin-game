extends RefCounted
class_name CitizenNeedsSystem

# Needs remain independent of the citizen's current activity. Hunger can fall
# and food can be eaten while a citizen works, walks, rests, or hauls. Physical
# food is always removed from personal inventory one whole item at a time.


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
	):
		return

	var personal_food_nutrition := WorldData.get_food_nutrition_in_resource_container(
		WorldData.get_city_citizen_inventory(citizen_id)
	)
	var desired_nutrition := maxi(
		WorldData.CITIZEN_EAT_TARGET_HUNGER
		- WorldData.get_city_citizen_hunger(citizen_id)
		- personal_food_nutrition,
		0
	)

	if desired_nutrition <= 0:
		return

	var source_objects := _get_legal_food_sources_at_citizen(citizen)

	for raw_source_object in source_objects:
		if not raw_source_object is Dictionary:
			continue

		var source_object: Dictionary = raw_source_object
		var source_object_id := int(source_object.get("id", -1))

		for resource in WorldData.get_city_food_resource_types():
			var hunger_restore := WorldData.get_city_food_hunger_restore(resource)

			if hunger_restore <= 0:
				continue

			var requested_units := ceili(
				float(desired_nutrition) / float(hunger_restore)
			)
			var transferred_units := (
				WorldData.transfer_city_object_resource_to_citizen_inventory(
					citizen_id,
					source_object_id,
					resource,
					requested_units,
					WorldData.CONTAINER_DIRECT_WITHDRAWAL_PURPOSE_PERSONAL_FOOD
				)
			)

			if transferred_units <= 0:
				continue

			desired_nutrition = maxi(
				desired_nutrition
				- transferred_units * hunger_restore,
				0
			)

			if (
				desired_nutrition <= 0
				or WorldData.get_city_citizen_inventory_free_space(citizen_id)
				<= 0
			):
				return


static func _get_legal_food_sources_at_citizen(
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
		WorldData.city_object_is_household_home(home)
		and WorldData.get_city_object_footprint_tiles(home).has(citizen_tile)
	):
		sources.append(home)

	# Public containers are a fallback only when the citizen is already at one;
	# this needs pass does not create a separate food-fetch navigation task.
	for storage_tier in WorldData.get_public_city_storage_tiers():
		for raw_city_object in WorldData.city_objects:
			if not raw_city_object is Dictionary:
				continue

			var city_object: Dictionary = raw_city_object

			if (
				WorldData.get_city_object_public_storage_tier(city_object)
				!= storage_tier
				or not WorldData.city_object_allows_direct_resource_withdrawal(
					city_object,
					WorldData.CONTAINER_DIRECT_WITHDRAWAL_PURPOSE_PERSONAL_FOOD
				)
			):
				continue

			var interaction_tiles := WorldData.get_city_object_access_tiles(
				WorldData.official_city_world,
				city_object
			)

			if (
				WorldData.get_city_object_footprint_tiles(city_object).has(
					citizen_tile
				)
				or interaction_tiles.has(citizen_tile)
			):
				sources.append(city_object)

	return sources


static func _eat_personal_food_if_hungry(citizen_id: int) -> void:
	var hunger := WorldData.get_city_citizen_hunger(citizen_id)

	if hunger > WorldData.CITIZEN_EAT_TRIGGER_HUNGER:
		return

	for resource in WorldData.get_city_food_resource_types():
		var hunger_restore := WorldData.get_city_food_hunger_restore(resource)

		if hunger_restore <= 0:
			continue

		while (
			hunger < WorldData.CITIZEN_EAT_TARGET_HUNGER
			and WorldData.get_city_citizen_inventory_resource_amount(
				citizen_id,
				resource
			) > 0
		):
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
			var next_hunger := mini(
				hunger + hunger_restore,
				WorldData.MAX_CITIZEN_HUNGER
			)

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
