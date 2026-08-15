extends Node

const TEST_WORLD_SIZE := Vector2i(32, 32)
const MULTI_DAY_COUNT: int = 2
const WORK_SHIFT_MINUTES: int = 9 * SimulationClock.MINUTES_PER_HOUR

var failure_count: int = 0


func _ready() -> void:
	_test_settlement_local_employment_lifecycle()
	_test_multi_day_fishery_employment()
	WorldData.reset_runtime_session_state()

	if failure_count > 0:
		push_error(
			"City employment lifecycle test failed: "
			+ str(failure_count)
		)
		get_tree().quit(1)
		return

	print("City employment lifecycle test passed.")
	get_tree().quit(0)


func _test_settlement_local_employment_lifecycle() -> void:
	var fixture := _make_two_city_fixture()
	if fixture.is_empty():
		return

	var city_a_id: int = fixture["city_a_id"]
	var city_b_id: int = fixture["city_b_id"]
	var state_a: CitySettlementSimulationState = fixture["state_a"]
	var state_b: CitySettlementSimulationState = fixture["state_b"]
	var fishery_a_id: int = fixture["fishery_a_id"]
	var fishery_b_id: int = fixture["fishery_b_id"]
	var citizen_ids_a: Array = fixture["citizen_ids_a"]
	var citizen_ids_b: Array = fixture["citizen_ids_b"]

	_expect(
		WorldPoliticalState.active_settlement_id == city_b_id,
		"City B must remain the presentation target while City A is simulated."
	)
	var b_before_a_tick := _capture_employment_state(state_b)
	CityEmploymentSystem.run_tick_for_city_state(state_a, 1, 1)

	var initial_worker_ids := _get_worker_ids(state_a, fishery_a_id)
	_expect(
		initial_worker_ids == [1, 2, 3, 4]
		and WorldPoliticalState.active_settlement_id == city_b_id,
		"Explicit City A employment must auto-fill the Fishery in ID order without changing the active City."
	)
	_expect(
		_capture_employment_state(state_b) == b_before_a_tick,
		"Simulating City A while City B is active must leave every City B employment owner unchanged."
	)

	var a_before_foreign_rejections := _capture_employment_state(state_a)
	var b_before_foreign_rejections := _capture_employment_state(state_b)
	var foreign_only_citizen_id := int(citizen_ids_b.back())
	var local_unemployed_citizen_id := int(citizen_ids_a.back())
	_expect(
		foreign_only_citizen_id > int(citizen_ids_a.back())
		and fishery_b_id != fishery_a_id,
		"The cross-settlement fixture must expose foreign-only citizen and workplace IDs."
	)
	_expect(
		not CityAssignmentSystem.assign_city_citizen_job_for_city_state(
			state_a,
			foreign_only_citizen_id,
			fishery_a_id
		)
		and not CityAssignmentSystem.assign_city_citizen_job_for_city_state(
			state_a,
			local_unemployed_citizen_id,
			fishery_b_id
		),
		"Explicit assignment must reject a foreign-only citizen and a foreign-only workplace."
	)
	_expect(
		_capture_employment_state(state_a) == a_before_foreign_rejections
		and _capture_employment_state(state_b) == b_before_foreign_rejections
		and WorldPoliticalState.active_settlement_id == city_b_id,
		"Rejected cross-settlement assignment attempts must be exact A/B no-ops."
	)

	for evicted_worker_id in [3, 4]:
		_expect(
			_prepare_moving_work_task(
				state_a,
				evicted_worker_id,
				fishery_a_id
			),
			"The downscale fixture must give each future eviction a real moving Work task."
		)

	_expect(
		_write_worker_capacity(state_a, fishery_a_id, 2),
		"The Fishery worker capacity must downscale from four to two."
	)
	CityEmploymentSystem.run_tick_for_city_state(state_a, 2, 1)
	_expect(
		_get_worker_ids(state_a, fishery_a_id) == [1, 2],
		"A four-to-two capacity downscale must deterministically retain the lowest citizen IDs."
	)
	for evicted_worker_id in [3, 4]:
		var evicted := (
			CityCitizenRegistrySystem.get_city_citizen_by_id_for_city_state(
				state_a,
				evicted_worker_id
			)
		)
		var evicted_task: Dictionary = evicted.get("current_task", {})
		_expect(
			int(evicted.get("job_object_id", -1)) == -1
			and str(evicted_task.get("kind", ""))
			== CityCitizens.CITY_CITIZEN_TASK_KIND_NONE
			and str(evicted.get("movement_state", ""))
			== CityCitizens.CITY_CITIZEN_MOVEMENT_STATE_IDLE
			and evicted.get("movement_path", []).is_empty(),
			"Capacity eviction must clear the worker's job, Work task, and movement atomically."
		)

	_expect(
		_write_worker_capacity(state_a, fishery_a_id, 4),
		"The Fishery worker capacity must scale back from two to four."
	)
	CityEmploymentSystem.run_tick_for_city_state(state_a, 3, 1)
	_expect(
		_get_worker_ids(state_a, fishery_a_id) == initial_worker_ids,
		"Restoring automatic capacity must refill the same two vacancies deterministically."
	)
	_expect(
		_assignment_links_are_valid(state_a, fishery_a_id)
		and _capture_employment_state(state_b) == b_before_foreign_rejections,
		"Downscale and refill must leave valid local links without mutating City B."
	)

	var assignment_owner_a := state_a.assignment_state
	var workplace_owner_a := state_a.workplace_state
	var registry_owner_a := state_a.citizen_registry_state
	var object_owner_a := state_a.object_state
	var retained_state := _capture_employment_state(state_a)
	_expect(
		WorldPoliticalState.set_active_settlement(city_a_id)
		and WorldPoliticalState.set_active_settlement(city_b_id)
		and WorldPoliticalState.set_active_settlement(city_a_id),
		"The employment retention fixture must complete an A/B/A presentation switch."
	)
	_expect(
		is_same(state_a.assignment_state, assignment_owner_a)
		and is_same(state_a.workplace_state, workplace_owner_a)
		and is_same(state_a.citizen_registry_state, registry_owner_a)
		and is_same(state_a.object_state, object_owner_a)
		and _capture_employment_state(state_a) == retained_state
		and _get_worker_ids(state_a, fishery_a_id) == initial_worker_ids,
		"A/B/A switching must preserve exact City A employment owners and links."
	)


func _test_multi_day_fishery_employment() -> void:
	WorldData.reset_runtime_session_state()
	SimulationClock.start_new_game(1, 8, 0)
	WorkplaceProductionSystem.clear_resource_source_evaluation_cache()

	var culture := WorldData.create_culture("Employment Multi-day Culture")
	var culture_id := int(culture.get("id", -1))
	var polity := _create_polity("Employment Multi-day Realm", culture_id)
	var city := _create_city(
		"Employment Multi-day City",
		int(polity.get("id", -1)),
		Vector2i(20, 20)
	)
	var city_id := int(city.get("id", -1))
	var state = WorldPoliticalState.get_city_simulation_state(city_id)
	_expect(
		culture_id > 0
		and city_id > 0
		and state is CitySettlementSimulationState,
		"The multi-day fixture must create one settlement-owned City."
	)
	if not state is CitySettlementSimulationState:
		return

	var city_state: CitySettlementSimulationState = state
	_configure_city_state(
		city_state,
		city_id,
		"Employment Multi-day City",
		culture_id,
		_make_world(73_001, true)
	)
	var fishery := _register_object(
		city_state,
		CityObjectCatalog.CITY_OBJECT_FISHING_GROUNDS,
		Vector2i(14, 14)
	)
	var stockpile := _register_object(
		city_state,
		CityObjectCatalog.CITY_OBJECT_STOCKPILE,
		Vector2i(8, 14)
	)
	var fishery_id := int(fishery.get("id", -1))
	var stockpile_id := int(stockpile.get("id", -1))
	var access_tiles := (
		CityNavigationSystem.get_city_object_access_tiles_for_city_state(
			city_state,
			city_state.city_world,
			fishery
		)
	)
	var stockpile_access_tiles := (
		CityNavigationSystem.get_city_object_access_tiles_for_city_state(
			city_state,
			city_state.city_world,
			stockpile
		)
	)
	_expect(
		fishery_id > 0
		and stockpile_id > 0
		and access_tiles.size() >= 8
		and stockpile_access_tiles.size() >= 4,
		"The multi-day fixture must create an accessible Fishery and public storage on fish-bearing terrain."
	)
	if (
		fishery_id <= 0
		or stockpile_id <= 0
		or access_tiles.size() < 8
		or stockpile_access_tiles.size() < 4
	):
		return

	var citizen_ids := _add_citizens_at_tiles(
		city_state,
		culture_id,
		access_tiles,
		8
	)
	_expect(
		citizen_ids.size() == 8,
		"The multi-day fixture must create eight local citizens."
	)
	if citizen_ids.size() != 8:
		return

	CityEmploymentSystem.run_tick_for_city_state(city_state, 1, 1)
	var stable_worker_ids := _get_worker_ids(city_state, fishery_id)
	_expect(
		stable_worker_ids == [1, 2, 3, 4]
		and _get_stored_fish(city_state, fishery_id) == 0,
		"The multi-day Fishery must begin automatically staffed with no preloaded physical fish."
	)

	var produced_fish := 0
	var consumed_fish := 0
	for day_offset in range(MULTI_DAY_COUNT):
		SimulationClock.absolute_world_minutes = (
			day_offset * SimulationClock.MINUTES_PER_DAY
			+ 8 * SimulationClock.MINUTES_PER_HOUR
		)
		CityEmploymentSystem.run_tick_for_city_state(
			city_state,
			10 + day_offset,
			1
		)
		_expect(
			_get_worker_ids(city_state, fishery_id) == stable_worker_ids,
			"Automatic Fishery employment must remain stable at each workday boundary."
		)

		for worker_index in range(stable_worker_ids.size()):
			var worker_id := int(stable_worker_ids[worker_index])
			_expect(
				_prepare_attending_work_task(
					city_state,
					worker_id,
					fishery_id,
					access_tiles[worker_index]
				),
				"Each stable Fishery worker must begin the day physically attending Work."
			)

		var fish_before_production := _get_stored_fish(
			city_state,
			fishery_id
		)
		WorkplaceProductionSystem.run_tick_for_city_state(
			city_state,
			20 + day_offset,
			WORK_SHIFT_MINUTES
		)
		var produced_this_day := (
			_get_stored_fish(city_state, fishery_id)
			- fish_before_production
		)
		produced_fish += produced_this_day
		fishery = CityObjectSystem.get_city_object_by_id_for_city_state(
			city_state,
			fishery_id
		)
		_expect(
			produced_this_day > 0
			and CityObjectCatalog.get_city_object_productive_worker_count(
				fishery
			) == 4,
			"Each simulated workday must produce new physical fish with all four workers productive."
		)
		var withdrawn_for_public_storage := (
			CityResourceContainerSystem.remove_resource_from_city_object_storage_for_city_state(
				city_state,
				fishery_id,
				WorldData.RESOURCE_FISH,
				produced_this_day
			)
		)
		var deposited_in_public_storage := (
			CityResourceContainerSystem.add_resource_to_city_object_storage_for_city_state(
				city_state,
				stockpile_id,
				WorldData.RESOURCE_FISH,
				withdrawn_for_public_storage
			)
		)
		_expect(
			withdrawn_for_public_storage == produced_this_day
			and deposited_in_public_storage == produced_this_day,
			"Each day's newly produced Fishery output must enter public storage before consumption."
		)
		_set_world_resource(city_state.city_world, WorldData.RESOURCE_NONE)

		SimulationClock.absolute_world_minutes = (
			day_offset * SimulationClock.MINUTES_PER_DAY
			+ 18 * SimulationClock.MINUTES_PER_HOUR
		)
		for hungry_index in range(4, 8):
			var hungry_id := int(citizen_ids[hungry_index])
			CityCitizenTaskRuntimeSystem.clear_city_citizen_task_for_city_state(
				city_state,
				hungry_id,
				CityCitizens.CITY_CITIZEN_TASK_SOURCE_PLAYER
			)
			CityCitizenMovementRuntimeSystem.cancel_city_citizen_movement_for_city_state(
				city_state,
				hungry_id
			)
			CityCitizenSpatialSystem.set_city_citizen_tile_position_for_city_state(
				city_state,
				city_state.city_world,
				hungry_id,
				stockpile_access_tiles[hungry_index - 4]
			)
			CitizenNeedsSystem.set_city_citizen_hunger_state_for_city_state(
				city_state,
				hungry_id,
				60,
				0
			)

		var fish_before_food := _get_stored_fish(city_state, stockpile_id)
		CitizenNeedsSystem.run_tick_for_city_state(
			city_state,
			30 + day_offset,
			1
		)
		for food_pass in range(4):
			CitizenDecisionSystem.run_tick_for_city_state(
				city_state,
				40 + day_offset * 4 + food_pass,
				1
			)
			CitizenTaskSystem.run_tick_for_city_state(
				city_state,
				40 + day_offset * 4 + food_pass,
				1
			)
		var consumed_this_day := (
			fish_before_food - _get_stored_fish(city_state, stockpile_id)
		)
		consumed_fish += consumed_this_day
		_expect(
			consumed_this_day > 0,
			"Each simulated day must consume at least one Fishery-produced fish through real need handling."
		)
		_expect(
			_get_worker_ids(city_state, fishery_id) == stable_worker_ids
			and _assignment_links_are_valid(city_state, fishery_id),
			"Daily production and local food consumption must preserve the same four Fishery jobs and valid bidirectional links."
		)
		_set_world_resource(city_state.city_world, WorldData.RESOURCE_FISH)

	_expect(
		produced_fish > 0
		and consumed_fish > 0
		and _get_worker_ids(city_state, fishery_id) == stable_worker_ids
		and CityAssignmentSystem.ensure_city_citizen_assignment_state_for_city_state(
			city_state
		) == 0,
		"Multi-day operation must produce and consume real fish without employment drift or repair."
	)


func _make_two_city_fixture() -> Dictionary:
	WorldData.reset_runtime_session_state()
	SimulationClock.start_new_game(1, 8, 0)
	var culture_a := WorldData.create_culture("Employment Lifecycle Culture A")
	var culture_b := WorldData.create_culture("Employment Lifecycle Culture B")
	var culture_a_id := int(culture_a.get("id", -1))
	var culture_b_id := int(culture_b.get("id", -1))
	var polity_a := _create_polity("Employment Lifecycle Realm A", culture_a_id)
	var polity_b := _create_polity("Employment Lifecycle Realm B", culture_b_id)
	var city_a := _create_city(
		"Employment Lifecycle City A",
		int(polity_a.get("id", -1)),
		Vector2i(2, 2)
	)
	var city_b := _create_city(
		"Employment Lifecycle City B",
		int(polity_b.get("id", -1)),
		Vector2i(10, 10)
	)
	var city_a_id := int(city_a.get("id", -1))
	var city_b_id := int(city_b.get("id", -1))
	var state_a = WorldPoliticalState.get_city_simulation_state(city_a_id)
	var state_b = WorldPoliticalState.get_city_simulation_state(city_b_id)
	_expect(
		culture_a_id > 0
		and culture_b_id > 0
		and state_a is CitySettlementSimulationState
		and state_b is CitySettlementSimulationState,
		"The lifecycle fixture must create two settlement-owned Cities."
	)
	if (
		not state_a is CitySettlementSimulationState
		or not state_b is CitySettlementSimulationState
	):
		return {}

	_configure_city_state(
		state_a,
		city_a_id,
		"Employment Lifecycle City A",
		culture_a_id,
		_make_world(72_001, false)
	)
	_configure_city_state(
		state_b,
		city_b_id,
		"Employment Lifecycle City B",
		culture_b_id,
		_make_world(72_002, false)
	)
	var fishery_a := _register_object(
		state_a,
		CityObjectCatalog.CITY_OBJECT_FISHING_GROUNDS,
		Vector2i(12, 12)
	)
	var house_b := _register_object(
		state_b,
		CityObjectCatalog.CITY_OBJECT_HOUSE,
		Vector2i(3, 12)
	)
	var fishery_b := _register_object(
		state_b,
		CityObjectCatalog.CITY_OBJECT_FISHING_GROUNDS,
		Vector2i(12, 12)
	)
	var citizen_ids_a := _add_citizens_in_row(
		state_a,
		culture_a_id,
		6,
		Vector2i(2, 2)
	)
	var citizen_ids_b := _add_citizens_in_row(
		state_b,
		culture_b_id,
		7,
		Vector2i(2, 2)
	)
	_expect(
		int(fishery_a.get("id", -1)) == 1
		and int(house_b.get("id", -1)) == 1
		and int(fishery_b.get("id", -1)) == 2
		and citizen_ids_a.size() == 6
		and citizen_ids_b.size() == 7
		and WorldPoliticalState.set_active_settlement(city_b_id),
		"The lifecycle fixture must establish distinct foreign-only IDs with City B active."
	)
	if (
		fishery_a.is_empty()
		or house_b.is_empty()
		or fishery_b.is_empty()
		or citizen_ids_a.size() != 6
		or citizen_ids_b.size() != 7
	):
		return {}

	return {
		"city_a_id": city_a_id,
		"city_b_id": city_b_id,
		"state_a": state_a,
		"state_b": state_b,
		"fishery_a_id": int(fishery_a.get("id", -1)),
		"fishery_b_id": int(fishery_b.get("id", -1)),
		"citizen_ids_a": citizen_ids_a,
		"citizen_ids_b": citizen_ids_b,
	}


func _configure_city_state(
	state: CitySettlementSimulationState,
	city_id: int,
	city_name: String,
	culture_id: int,
	city_world: WorldData
) -> void:
	state.city_world = city_world
	state.city_seed = city_world.seed
	state.city_runtime_data.clear()
	state.city_runtime_data.merge({
		"id": city_id,
		"name": city_name,
		"primary_culture_id": culture_id,
		"city_world_seed": city_world.seed,
		"city_map_size": Vector2i(city_world.width, city_world.height),
		"founded": true,
		"can_build": true,
	}, true)


func _create_polity(polity_name: String, culture_id: int) -> Dictionary:
	return WorldPoliticalState.create_polity({
		"name": polity_name,
		"polity_type": PolityData.POLITY_TYPE_KINGDOM,
		"primary_culture_id": culture_id,
	})


func _create_city(
	city_name: String,
	polity_id: int,
	region_center: Vector2i
) -> Dictionary:
	return WorldPoliticalState.create_settlement({
		"name": city_name,
		"settlement_type": SettlementData.SETTLEMENT_TYPE_CITY,
		"polity_id": polity_id,
		"world_region_top_left": region_center,
		"world_region_center": region_center,
		"world_region_size": 1,
		"simulation_backend_kind": (
			SettlementSimulationContext.BACKEND_CITY_SETTLEMENT_STATE
		),
	})


func _register_object(
	state: CitySettlementSimulationState,
	object_type: String,
	top_left: Vector2i
) -> Dictionary:
	return CityObjectSystem.register_completed_city_object_for_city_state(
		state,
		{
			"object_type": object_type,
			"top_left": top_left,
			"size_tiles": CityObjectCatalog.get_city_object_size_for_type(
				object_type
			),
			"object_owner": "player",
			"city_world": state.city_world,
		}
	)


func _add_citizens_in_row(
	state: CitySettlementSimulationState,
	culture_id: int,
	count: int,
	row_start: Vector2i
) -> Array[int]:
	var citizen_ids: Array[int] = []
	for citizen_index in range(count):
		var citizen := (
			CityCitizenRegistrySystem.add_city_citizen_for_city_state(
				state,
				"",
				row_start + Vector2i(citizen_index, 0),
				(
					CityCitizens.CITY_CITIZEN_SEX_MALE
					if citizen_index % 2 == 0
					else CityCitizens.CITY_CITIZEN_SEX_FEMALE
				),
				culture_id
			)
		)
		var citizen_id := int(citizen.get("id", -1))
		if citizen_id > 0:
			citizen_ids.append(citizen_id)
	return citizen_ids


func _add_citizens_at_tiles(
	state: CitySettlementSimulationState,
	culture_id: int,
	tiles: Array,
	count: int
) -> Array[int]:
	var citizen_ids: Array[int] = []
	for citizen_index in range(count):
		var citizen := (
			CityCitizenRegistrySystem.add_city_citizen_for_city_state(
				state,
				"",
				tiles[citizen_index],
				(
					CityCitizens.CITY_CITIZEN_SEX_MALE
					if citizen_index % 2 == 0
					else CityCitizens.CITY_CITIZEN_SEX_FEMALE
				),
				culture_id
			)
		)
		var citizen_id := int(citizen.get("id", -1))
		if citizen_id > 0:
			citizen_ids.append(citizen_id)
	return citizen_ids


func _write_worker_capacity(
	state: CitySettlementSimulationState,
	workplace_id: int,
	worker_capacity: int
) -> bool:
	return CityEmploymentSystem.set_city_workplace_worker_capacity_for_city_state(
		state,
		workplace_id,
		worker_capacity
	)


func _prepare_moving_work_task(
	state: CitySettlementSimulationState,
	citizen_id: int,
	workplace_id: int
) -> bool:
	var citizen := (
		CityCitizenRegistrySystem.get_city_citizen_by_id_for_city_state(
			state,
			citizen_id
		)
	)
	var position = citizen.get(
		"city_tile_position",
		CityCitizens.INVALID_CITY_TILE_POSITION
	)
	if not position is Vector2i:
		return false
	return (
		CityCitizenTaskRuntimeSystem.assign_city_citizen_task_for_city_state(
			state,
			citizen_id,
			{
				"kind": CityCitizens.CITY_CITIZEN_TASK_KIND_WORK,
				"source": CityCitizens.CITY_CITIZEN_TASK_SOURCE_SCHEDULE,
				"priority": 50,
				"target_object_id": workplace_id,
			}
		)
		and CityCitizenTaskRuntimeSystem.set_city_citizen_task_phase_for_city_state(
			state,
			citizen_id,
			CityCitizens.CITY_CITIZEN_TASK_PHASE_PERFORMING
		)
		and CityCitizenMovementRuntimeSystem.assign_city_citizen_movement_order_for_city_state(
			state,
			citizen_id,
			[position, position + Vector2i(0, 1)]
		)
	)


func _prepare_attending_work_task(
	state: CitySettlementSimulationState,
	citizen_id: int,
	workplace_id: int,
	access_tile: Vector2i
) -> bool:
	CityCitizenTaskRuntimeSystem.clear_city_citizen_task_for_city_state(
		state,
		citizen_id,
		CityCitizens.CITY_CITIZEN_TASK_SOURCE_PLAYER
	)
	CityCitizenMovementRuntimeSystem.cancel_city_citizen_movement_for_city_state(
		state,
		citizen_id
	)
	return (
		CityCitizenSpatialSystem.set_city_citizen_tile_position_for_city_state(
			state,
			state.city_world,
			citizen_id,
			access_tile
		)
		and CityCitizenTaskRuntimeSystem.assign_city_citizen_task_for_city_state(
			state,
			citizen_id,
			{
				"kind": CityCitizens.CITY_CITIZEN_TASK_KIND_WORK,
				"source": CityCitizens.CITY_CITIZEN_TASK_SOURCE_SCHEDULE,
				"priority": 50,
				"target_object_id": workplace_id,
			}
		)
		and CityCitizenTaskRuntimeSystem.set_city_citizen_task_phase_for_city_state(
			state,
			citizen_id,
			CityCitizens.CITY_CITIZEN_TASK_PHASE_PERFORMING
		)
	)


func _get_worker_ids(
	state: CitySettlementSimulationState,
	workplace_id: int
) -> Array:
	var workplace := CityObjectSystem.get_city_object_by_id_for_city_state(
		state,
		workplace_id
	)
	return CityAssignmentSystem.get_city_object_worker_ids_for_city_state(
		state,
		workplace
	)


func _get_stored_fish(
	state: CitySettlementSimulationState,
	workplace_id: int
) -> int:
	var workplace := CityObjectSystem.get_city_object_by_id_for_city_state(
		state,
		workplace_id
	)
	return (
		CityResourceContainerSystem
		.get_city_object_stored_resource_amount(
			workplace,
			WorldData.RESOURCE_FISH
		)
	)


func _assignment_links_are_valid(
	state: CitySettlementSimulationState,
	workplace_id: int
) -> bool:
	var worker_ids := _get_worker_ids(state, workplace_id)
	var seen_worker_ids: Dictionary = {}
	for raw_worker_id in worker_ids:
		var worker_id := int(raw_worker_id)
		if worker_id <= 0 or seen_worker_ids.has(worker_id):
			return false
		seen_worker_ids[worker_id] = true
		var citizen := (
			CityCitizenRegistrySystem.get_city_citizen_by_id_for_city_state(
				state,
				worker_id
			)
		)
		if int(citizen.get("job_object_id", -1)) != workplace_id:
			return false

	for raw_citizen in state.citizen_registry_state.citizens:
		if not raw_citizen is Dictionary:
			continue
		var citizen: Dictionary = raw_citizen
		if (
			int(citizen.get("job_object_id", -1)) == workplace_id
			and not seen_worker_ids.has(int(citizen.get("id", -1)))
		):
			return false
	return true


func _capture_employment_state(
	state: CitySettlementSimulationState
) -> Dictionary:
	return {
		"citizens": state.citizen_registry_state.citizens.duplicate(true),
		"citizen_index_by_id": (
			state.citizen_registry_state.citizen_index_by_id.duplicate(true)
		),
		"next_citizen_id": state.citizen_registry_state.next_citizen_id,
		"citizen_version": state.citizen_registry_state.citizen_version,
		"objects": state.object_state.objects.duplicate(true),
		"object_index_by_id": state.object_state.object_index_by_id.duplicate(true),
		"object_version": state.object_state.object_version,
		"assignment_version": state.assignment_state.assignment_version,
		"workplace_version": state.workplace_state.workplace_version,
		"active_task_ids": (
			state.citizen_task_runtime_state.active_task_ids.duplicate()
		),
		"active_task_id_lookup": (
			state.citizen_task_runtime_state.active_task_id_lookup.duplicate(true)
		),
		"citizen_task_version": (
			state.citizen_task_runtime_state.citizen_task_version
		),
		"active_mover_ids": (
			state.citizen_movement_runtime_state.active_mover_ids.duplicate()
		),
		"active_mover_id_lookup": (
			state.citizen_movement_runtime_state.active_mover_id_lookup.duplicate(true)
		),
		"citizen_movement_version": (
			state.citizen_movement_runtime_state.citizen_movement_version
		),
	}


func _make_world(seed_value: int, has_fish: bool) -> WorldData:
	var world := WorldData.new()
	world.setup(TEST_WORLD_SIZE.x, TEST_WORLD_SIZE.y, seed_value)
	for y in range(world.height):
		for x in range(world.width):
			world.tiles[y][x] = {
				"fertility": 50.0,
				"elevation": 0.2,
				"temperature": 0.5,
				"precipitation": 0.5,
				"terrain": WorldData.TERRAIN_LAND,
				"biome": WorldData.BIOME_PLAIN,
				"resource": (
					WorldData.RESOURCE_FISH
					if has_fish
					else WorldData.RESOURCE_NONE
				),
				"is_land": true,
			}
	world.mark_tile_data_changed()
	return world


func _set_world_resource(world: WorldData, resource: String) -> void:
	for y in range(world.height):
		for x in range(world.width):
			world.set_tile_resource_value(Vector2i(x, y), resource)


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	failure_count += 1
	push_error("City employment lifecycle test: " + message)
