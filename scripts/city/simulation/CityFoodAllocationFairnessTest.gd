extends Node

# Protects the scarcity rules that distinguish total nutritional deficit from
# the next one-item allocation and keep pantry stocking behind immediate meals.

const CitizenDecisionSystemScript = preload(
	"res://scripts/citizens/simulation/systems/CitizenDecisionSystem.gd"
)
const CitizenNeedsSystemScript = preload(
	"res://scripts/citizens/simulation/systems/CitizenNeedsSystem.gd"
)
const CityResourceMatcherScript = preload(
	"res://scripts/city/simulation/systems/CityResourceMatcher.gd"
)

const TEST_WORLD_SIZE := Vector2i(32, 24)
const TEST_WORLD_SEED: int = 91_407

var failure_count: int = 0
var test_culture_id: int = -1


func _ready() -> void:
	_test_current_source_allocates_one_immediate_meal()
	_test_hungry_citizens_reserve_before_household_stocking()
	WorldData.reset_runtime_session_state()

	if failure_count > 0:
		push_error(
			"City food allocation fairness tests failed: "
			+ str(failure_count)
		)
		get_tree().quit(1)
		return

	print("City food allocation fairness tests passed.")
	get_tree().quit(0)


func _test_current_source_allocates_one_immediate_meal() -> void:
	var city_world := _reset_fixture()
	var house := CityObjectSystem.add_city_object({
		"object_type": WorldData.CITY_OBJECT_HOUSE,
		"top_left": Vector2i(8, 8),
		"size_tiles": WorldData.get_city_object_size_for_type(
			WorldData.CITY_OBJECT_HOUSE
		),
		"object_owner": "player",
		"city_world": city_world,
	})
	var house_id := int(house.get("id", -1))
	var citizen := _add_citizen(Vector2i(8, 8))
	var citizen_id := int(citizen.get("id", -1))

	_expect(house_id > 0, "The one-meal fixture must create a House.")
	_expect(citizen_id > 0, "The one-meal fixture must create a citizen.")
	_expect(
		WorldData.assign_city_citizen_home(citizen_id, house_id),
		"The one-meal fixture citizen must own the pantry they are standing in."
	)
	_expect(
		CityResourceContainerSystem.add_resource_to_city_object_storage(
			house_id,
			WorldData.RESOURCE_FISH,
			2
		) == 2,
		"The one-meal fixture pantry must begin with two fish."
	)
	CitizenNeedsSystem.set_city_citizen_hunger_state(citizen_id, 70, 0)
	_expect(
		CitizenNeedsSystemScript.get_citizen_food_need_nutrition(
			citizen_id
		) == 30,
		"Total nutritional deficit must remain distinct from allocation size."
	)
	_expect(
		CitizenNeedsSystemScript.get_citizen_next_food_allocation_nutrition(
			citizen_id
		) == 20,
		"The next allocation must be capped to one ordinary whole food item."
	)

	CitizenNeedsSystemScript.run_tick(1, 1)

	_expect(
		CitizenNeedsSystem.get_city_citizen_hunger(citizen_id) == 90,
		"A hungry citizen at a legal source must eat one 20-point fish."
	)
	_expect(
		CityCitizenInventorySystem.get_city_citizen_inventory_resource_amount(
			citizen_id,
			WorldData.RESOURCE_FISH
		) == 0,
		"Immediate eating must not leave a second scarce fish pocketed as a personal reserve."
	)
	_expect(
		CityResourceContainerSystem.get_city_object_stored_resource_amount(
			CityObjectSystem.get_city_object_by_id(house_id),
			WorldData.RESOURCE_FISH
		) == 1,
		"One Needs tick must withdraw only one whole food item from any legal source."
	)


func _test_hungry_citizens_reserve_before_household_stocking() -> void:
	var city_world := _reset_fixture()
	var hungry_a := _add_citizen(Vector2i(3, 4))
	var hungry_b := _add_citizen(Vector2i(3, 7))
	var provisioner := _add_citizen(Vector2i(3, 10))
	var hungry_a_id := int(hungry_a.get("id", -1))
	var hungry_b_id := int(hungry_b.get("id", -1))
	var provisioner_id := int(provisioner.get("id", -1))

	CitizenNeedsSystem.set_city_citizen_hunger_state(hungry_a_id, 60, 0)
	CitizenNeedsSystem.set_city_citizen_hunger_state(hungry_b_id, 60, 0)
	CitizenNeedsSystem.set_city_citizen_hunger_state(provisioner_id, 100, 0)

	var stockpile := CityObjectSystem.add_city_object({
		"object_type": WorldData.CITY_OBJECT_STOCKPILE,
		"top_left": Vector2i(10, 8),
		"size_tiles": WorldData.get_city_object_size_for_type(
			WorldData.CITY_OBJECT_STOCKPILE
		),
		"object_owner": "player",
		"city_world": city_world,
	})
	var stockpile_id := int(stockpile.get("id", -1))
	var house := CityObjectSystem.add_city_object({
		"object_type": WorldData.CITY_OBJECT_HOUSE,
		"top_left": Vector2i(22, 8),
		"size_tiles": WorldData.get_city_object_size_for_type(
			WorldData.CITY_OBJECT_HOUSE
		),
		"object_owner": "player",
		"city_world": city_world,
	})
	var house_id := int(house.get("id", -1))

	_expect(stockpile_id > 0, "The fairness fixture must create public storage.")
	_expect(house_id > 0, "The fairness fixture must create a household pantry.")
	_expect(
		WorldData.assign_city_citizen_home(provisioner_id, house_id),
		"The provisioner must be assigned to the household pantry."
	)
	_expect(
		CityResourceContainerSystem.add_resource_to_city_object_storage(
			stockpile_id,
			WorldData.RESOURCE_FISH,
			5
		) == 5,
		"The fairness fixture must begin with five shared fish."
	)
	_expect(
		CityResourceMatcherScript.get_city_public_food_surplus_nutrition() == 40,
		"Before immediate claims, five fish for three citizens must expose two fish of pantry-eligible surplus."
	)

	CitizenDecisionSystemScript._process_food_needs(false)

	var task_a := CityCitizenTaskRuntimeSystem.get_city_citizen_current_task(hungry_a_id)
	var task_b := CityCitizenTaskRuntimeSystem.get_city_citizen_current_task(hungry_b_id)
	_expect(
		str(task_a.get("kind", ""))
		== WorldData.CITY_CITIZEN_TASK_KIND_ACQUIRE_FOOD
		and str(task_b.get("kind", ""))
		== WorldData.CITY_CITIZEN_TASK_KIND_ACQUIRE_FOOD,
		"Both equally hungry citizens must claim one shared meal before pantry stocking begins."
	)
	_expect(
		int(task_a.get("food_requested_amount", 0)) == 1
		and int(task_b.get("food_requested_amount", 0)) == 1,
		"Every survival-food task must reserve one whole item, never a private multi-meal bundle."
	)
	_expect(
		CityResourceMatcherScript.get_city_public_food_surplus_nutrition() == 0,
		"Immediate meal reservations must reduce the pantry-eligible public surplus."
	)

	var provisioner_request := (
		CitizenDecisionSystemScript
		._get_scheduled_home_food_delivery_task_request(
			CityCitizenRegistrySystem.get_city_citizen_by_id(provisioner_id)
		)
	)
	_expect(
		provisioner_request.is_empty(),
		"Household provisioning must pause when hungry citizens have consumed the distributable surplus with meal reservations."
	)


func _reset_fixture() -> WorldData:
	WorldData.reset_runtime_session_state()
	CitizenDecisionSystemScript.reset_runtime_state()
	SimulationClock.start_new_game()
	var city_world := WorldData.new()
	city_world.setup(TEST_WORLD_SIZE.x, TEST_WORLD_SIZE.y, TEST_WORLD_SEED)

	for y in range(city_world.height):
		for x in range(city_world.width):
			var tile := city_world.get_tile(x, y)
			tile["terrain"] = WorldData.TERRAIN_LAND
			tile["biome"] = WorldData.BIOME_PLAIN
			tile["is_land"] = true
			tile["fertility"] = 50.0

	city_world.mark_tile_data_changed()
	WorldData.store_city_world_save(city_world, TEST_WORLD_SEED)
	WorldData.player_city_founded = true
	var culture := WorldData.create_culture("Food Allocation Test Culture")
	test_culture_id = int(culture.get("id", -1))
	return city_world


func _add_citizen(tile_position: Vector2i) -> Dictionary:
	return WorldData.add_city_citizen(
		"",
		tile_position,
		WorldData.CITY_CITIZEN_SEX_FEMALE,
		test_culture_id
	)


func _expect(condition: bool, message: String) -> void:
	if condition:
		return

	failure_count += 1
	push_error(message)
