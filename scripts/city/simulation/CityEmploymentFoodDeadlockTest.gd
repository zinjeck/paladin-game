extends Node

const CityConstructionSystemScript = preload(
	"res://scripts/city/simulation/systems/CityConstructionSystem.gd"
)
const CityEmploymentSystemScript = preload(
	"res://scripts/citizens/simulation/systems/CityEmploymentSystem.gd"
)
const CityWorkSystemScript = preload(
	"res://scripts/city/simulation/systems/CityWorkSystem.gd"
)
const CitizenDecisionSystemScript = preload(
	"res://scripts/citizens/simulation/systems/CitizenDecisionSystem.gd"
)
const CitizenTaskSystemScript = preload(
	"res://scripts/citizens/simulation/systems/CitizenTaskSystem.gd"
)

const TEST_WORLD_SIZE := Vector2i(32, 24)
const TEST_WORLD_SEED: int = 84_221

var failure_count: int = 0
var test_culture_id: int = -1


func _ready() -> void:
	_test_hunger_waits_for_real_food_opportunity()
	_test_persistent_workplace_staffing_policy()
	WorldData.reset_runtime_session_state()

	if failure_count > 0:
		push_error(
			"Employment and food deadlock tests failed: "
			+ str(failure_count)
		)
		get_tree().quit(1)
		return

	print("Employment and food deadlock tests passed.")
	get_tree().quit(0)


func _test_hunger_waits_for_real_food_opportunity() -> void:
	var city_world := _reset_fixture()
	var normal_citizen := _add_citizen(Vector2i(3, 4))
	var critical_citizen := _add_citizen(Vector2i(3, 6))
	var normal_id := int(normal_citizen.get("id", -1))
	var critical_id := int(critical_citizen.get("id", -1))

	WorldData.set_city_citizen_hunger_state(normal_id, 60, 0)
	WorldData.set_city_citizen_hunger_state(critical_id, 0, 0)

	var road_sites := CityConstructionSystemScript.create_road_sites(
		[Vector2i(9, 4), Vector2i(9, 6)],
		"player",
		city_world
	)
	_expect(
		road_sites.size() == 2,
		"The hunger deadlock fixture must create two independent road sites."
	)

	CityWorkSystemScript.synchronize_player_work_board()
	CitizenDecisionSystemScript._process_player_commands()

	_expect(
		_task_kind(normal_id) == WorldData.CITY_CITIZEN_TASK_KIND_CONSTRUCTION
		and _task_kind(critical_id)
		== WorldData.CITY_CITIZEN_TASK_KIND_CONSTRUCTION,
		"Hungry citizens without obtainable food must remain eligible for road and construction work."
	)

	CitizenTaskSystemScript.run_tick(1, 2)
	_expect(
		_task_kind(normal_id) == WorldData.CITY_CITIZEN_TASK_KIND_CONSTRUCTION,
		"Normal hunger must not speculatively release work before a food source exists."
	)

	var stockpile := WorldData.add_city_object({
		"object_type": WorldData.CITY_OBJECT_STOCKPILE,
		"top_left": Vector2i(4, 10),
		"size_tiles": WorldData.get_city_object_size_for_type(
			WorldData.CITY_OBJECT_STOCKPILE
		),
		"object_owner": "player",
		"city_world": city_world,
	})
	var stockpile_id := int(stockpile.get("id", -1))
	_expect(stockpile_id > 0, "The food fixture must create public storage.")

	WorldData.add_resource_to_city_object_storage(
		stockpile_id,
		WorldData.RESOURCE_FISH,
		1
	)
	CitizenDecisionSystemScript._process_food_needs(true)

	_expect(
		_task_kind(critical_id) == WorldData.CITY_CITIZEN_TASK_KIND_ACQUIRE_FOOD
		and _task_kind(normal_id)
		== WorldData.CITY_CITIZEN_TASK_KIND_CONSTRUCTION,
		"One available fish must interrupt the critical citizen only after the source is matched and reserved."
	)

	WorldData.add_resource_to_city_object_storage(
		stockpile_id,
		WorldData.RESOURCE_FISH,
		1
	)
	CitizenDecisionSystemScript._process_food_needs(false)

	_expect(
		_task_kind(normal_id) == WorldData.CITY_CITIZEN_TASK_KIND_ACQUIRE_FOOD,
		"Normal hunger must yield construction at a safe boundary as soon as a real food opportunity exists."
	)


func _test_persistent_workplace_staffing_policy() -> void:
	var city_world := _reset_fixture()
	var citizen_ids: Array[int] = []

	for index in range(4):
		var citizen := _add_citizen(Vector2i(3, 3 + index * 2))
		citizen_ids.append(int(citizen.get("id", -1)))

	var blocked_citizen_id := citizen_ids[0]
	_expect(
		WorldData.set_city_citizen_haul_cargo(
			blocked_citizen_id,
			WorldData.RESOURCE_STONE,
			1
		) == 1,
		"The staffing fixture must make the first unemployed candidate temporarily unavailable."
	)

	var fishery := WorldData.add_city_object({
		"object_type": WorldData.CITY_OBJECT_FISHING_GROUNDS,
		"top_left": Vector2i(15, 8),
		"size_tiles": WorldData.get_city_object_size_for_type(
			WorldData.CITY_OBJECT_FISHING_GROUNDS
		),
		"object_owner": "player",
		"city_world": city_world,
	})
	var fishery_id := int(fishery.get("id", -1))
	_expect(fishery_id > 0, "The staffing fixture must create a Fishery.")

	CityEmploymentSystemScript.run_tick(1, 2)
	fishery = WorldData.get_city_object_by_id(fishery_id)

	_expect(
		CityEmploymentSystemScript.get_workplace_staffing_mode(fishery)
		== CityEmploymentSystemScript.STAFFING_MODE_AUTOMATIC
		and CityEmploymentSystemScript.get_workplace_desired_worker_count(fishery) == 4,
		"New workplaces must default to automatic staffing with desired workers equal to capacity."
	)
	_expect(
		WorldData.get_city_object_worker_count(fishery) == 3
		and int(
			WorldData.get_city_citizen_by_id(blocked_citizen_id).get(
				"job_object_id",
				-1
			)
		) < 0,
		"A temporarily unavailable first candidate must not block later unemployed citizens from filling the Fishery."
	)

	WorldData.set_city_citizen_haul_cargo_resources(blocked_citizen_id, {})
	CityEmploymentSystemScript.run_tick(2, 2)
	fishery = WorldData.get_city_object_by_id(fishery_id)
	_expect(
		WorldData.get_city_object_worker_count(fishery) == 4
		and int(
			WorldData.get_city_citizen_by_id(blocked_citizen_id).get(
				"job_object_id",
				-1
			)
		) == fishery_id,
		"The persistent vacancy must fill on a later tick when the deferred citizen becomes available."
	)

	_expect(
		CityEmploymentSystemScript.set_workplace_staffing_mode(
			fishery_id,
			CityEmploymentSystemScript.STAFFING_MODE_MANUAL
		),
		"The employment framework must expose a durable manual staffing mode."
	)
	var removed_worker_id := int(
		WorldData.get_city_object_worker_ids(
			WorldData.get_city_object_by_id(fishery_id)
		)[0]
	)
	_expect(
		CityEmploymentSystemScript.remove_citizen_job(removed_worker_id),
		"The manual staffing fixture must remove one assigned worker."
	)
	CityEmploymentSystemScript.run_tick(3, 2)
	_expect(
		WorldData.get_city_object_worker_count(
			WorldData.get_city_object_by_id(fishery_id)
		) == 3,
		"Manual staffing mode must preserve an intentional vacancy instead of automatically refilling it."
	)

	CityEmploymentSystemScript.set_workplace_staffing_mode(
		fishery_id,
		CityEmploymentSystemScript.STAFFING_MODE_AUTOMATIC
	)
	CityEmploymentSystemScript.run_tick(4, 2)
	_expect(
		WorldData.get_city_object_worker_count(
			WorldData.get_city_object_by_id(fishery_id)
		) == 4,
		"Returning to automatic staffing must reconcile the open vacancy through the same assignment framework."
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
	var culture := WorldData.create_culture("Employment Test Culture")
	test_culture_id = int(culture.get("id", -1))
	return city_world


func _add_citizen(tile_position: Vector2i) -> Dictionary:
	return WorldData.add_city_citizen(
		"",
		tile_position,
		WorldData.CITY_CITIZEN_SEX_FEMALE,
		test_culture_id
	)


func _task_kind(citizen_id: int) -> String:
	return str(
		WorldData.get_city_citizen_current_task(citizen_id).get(
			"kind",
			WorldData.CITY_CITIZEN_TASK_KIND_NONE
		)
	)


func _expect(condition: bool, message: String) -> void:
	if condition:
		return

	failure_count += 1
	push_error(message)
