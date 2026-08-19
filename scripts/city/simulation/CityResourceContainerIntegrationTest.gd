extends Node

const CityConstructionSystemScript = preload(
	"res://scripts/city/simulation/systems/CityConstructionSystem.gd"
)
const CityResourceMatcherScript = preload(
	"res://scripts/city/simulation/systems/CityResourceMatcher.gd"
)
const CitizenDecisionSystemScript = preload(
	"res://scripts/citizens/simulation/systems/CitizenDecisionSystem.gd"
)
const CitizenHaulingSystemScript = preload(
	"res://scripts/citizens/simulation/systems/CitizenHaulingSystem.gd"
)
const CitizenMovementSystemScript = preload(
	"res://scripts/citizens/simulation/systems/CitizenMovementSystem.gd"
)

const TEST_WORLD_SIZE := Vector2i(40, 30)

var failure_count: int = 0
var test_culture_id: int = -1


func _ready() -> void:
	_test_scheduled_home_delivery_accounting()
	_test_construction_supply_and_delivery()
	_test_reserved_stockpile_falls_back_to_keep()
	WorldData.reset_runtime_session_state()

	if failure_count > 0:
		push_error(
			"City resource-container integration test failed: "
			+ str(failure_count)
		)
		get_tree().quit(1)
		return

	print("City resource-container integration test passed.")
	get_tree().quit(0)


func _test_scheduled_home_delivery_accounting() -> void:
	var city_world := _reset_fixture(97_101)
	var keep := _add_completed_object(
		CityObjectCatalog.CITY_OBJECT_CITY_CENTER,
		Vector2i(30, 20),
		city_world
	)
	_mark_fixture_city_founded(keep)
	var house := _add_completed_object(
		CityObjectCatalog.CITY_OBJECT_HOUSE,
		Vector2i(4, 12),
		city_world
	)
	var stockpile := _add_completed_object(
		CityObjectCatalog.CITY_OBJECT_STOCKPILE,
		Vector2i(5, 4),
		city_world
	)
	var house_id := int(house.get("id", -1))
	var stockpile_id := int(stockpile.get("id", -1))
	var source_tile := _get_object_access_tile(city_world, stockpile)
	var citizen := _add_citizen(source_tile)
	var citizen_id := int(citizen.get("id", -1))

	_expect(
		house_id > 0
		and stockpile_id > 0
		and citizen_id > 0
		and source_tile != CityCitizens.INVALID_CITY_TILE_POSITION
		and CityAssignmentSystem.assign_city_citizen_home(citizen_id, house_id),
		"The home-delivery fixture must create one healthy resident, House, and Stockpile."
	)
	if house_id <= 0 or stockpile_id <= 0 or citizen_id <= 0:
		return

	_expect(
		CityResourceContainerSystem.add_resource_to_city_object_storage(
			stockpile_id,
			WorldData.RESOURCE_FISH,
			3
		) == 3,
		"The home-delivery Stockpile must begin with exactly three fish."
	)
	var accounting_state := CityResourceAccountingSystem.get_current_state()
	var container_before_haul := accounting_state.container_version
	var public_before_haul := accounting_state.public_storage_version
	var task_request := (
		CitizenDecisionSystemScript
		._get_scheduled_home_food_delivery_task_request(
			CityCitizenRegistrySystem.get_city_citizen_by_id(citizen_id)
		)
	)
	var requested_haul: Dictionary = task_request.get("haul", {})

	_expect(
		str(task_request.get("kind", ""))
		== CityCitizens.CITY_CITIZEN_TASK_KIND_HAUL
		and str(requested_haul.get("reason", ""))
		== CityCitizens.CITY_CITIZEN_HAUL_REASON_SCHEDULED_HOME_FOOD_DELIVERY
		and int(requested_haul.get("requested_amount", 0)) == 2
		and int(requested_haul.get("source", {}).get("id", -1))
		== stockpile_id
		and int(requested_haul.get("destination", {}).get("id", -1))
		== house_id,
		"The schedule must generate a two-fish Stockpile-to-home delivery above the protected reserve."
	)
	if task_request.is_empty():
		return

	_expect(
		CityCitizenTaskRuntimeSystem.assign_city_citizen_task(citizen_id, task_request),
		"The generated home-delivery request must create a real haul assignment."
	)
	var reservation_id := (
		CityLogisticsSystem.get_city_haul_reservation_id_for_citizen(
			citizen_id
		)
	)
	var reservation := CityLogisticsSystem.get_city_haul_reservation(
		reservation_id
	)
	_expect(
		reservation_id > 0
		and int(reservation.get("source_reserved_amount", 0)) == 2
		and int(reservation.get("destination_reserved_amount", 0)) == 2,
		"The home-delivery assignment must reserve both physical source fish and pantry capacity."
	)

	_advance_single_haul_tick(city_world, citizen_id, 1)
	_advance_single_haul_tick(city_world, citizen_id, 2)
	stockpile = CityObjectSystem.get_city_object_by_id(stockpile_id)
	reservation = CityLogisticsSystem.get_city_haul_reservation(reservation_id)
	_expect(
		CityResourceContainerSystem.get_city_object_stored_resource_amount(
			stockpile,
			WorldData.RESOURCE_FISH
		) == 1
		and CityCitizenInventorySystem.get_city_citizen_haul_cargo_resource_amount(
			citizen_id,
			WorldData.RESOURCE_FISH
		) == 2
		and int(reservation.get("source_reserved_amount", -1)) == 0
		and int(reservation.get("destination_reserved_amount", 0)) == 2
		and accounting_state.container_version == container_before_haul + 1
		and accounting_state.public_storage_version == public_before_haul + 1,
		"Pickup must remove two public fish, preserve the pantry reservation, and publish one public-container write."
	)

	var completed := _run_single_haul_to_completion(
		city_world,
		citizen_id,
		3,
		80
	)
	house = CityObjectSystem.get_city_object_by_id(house_id)
	stockpile = CityObjectSystem.get_city_object_by_id(stockpile_id)
	_expect(
		completed
		and CityResourceContainerSystem.get_city_object_stored_resource_amount(
			stockpile,
			WorldData.RESOURCE_FISH
		) == 1
		and CityResourceContainerSystem.get_city_object_stored_resource_amount(
			house,
			WorldData.RESOURCE_FISH
		) == 2
		and CityCitizenInventorySystem.get_city_citizen_haul_cargo_amount(citizen_id) == 0
		and CityResourceContainerSystem.get_resource_container_total_amount(
			CityCitizenInventorySystem.get_city_citizen_inventory(citizen_id)
		) == 0,
		"The real haul must finish with Stockpile 1, House 2, and no citizen inventory or cargo."
	)
	_expect(
		CityResourceAccountingSystem.get_total_physical_city_resource_amount(
			WorldData.RESOURCE_FISH
		) == 3
		and CityResourceAccountingSystem.get_total_public_city_resource_amount(
			WorldData.RESOURCE_FISH
		) == 1
		and CityResourceAccountingSystem.get_total_owned_city_resource_amount(
			WorldData.RESOURCE_FISH
		) == 1,
		"Home delivery must conserve three physical fish while public and owned UI totals exclude the pantry."
	)
	_expect(
		accounting_state.container_version == container_before_haul + 2
		and accounting_state.public_storage_version == public_before_haul + 1,
		"Source removal and pantry deposit must publish two container writes, with only the public source changing the public version."
	)


func _test_construction_supply_and_delivery() -> void:
	var city_world := _reset_fixture(97_202)
	var keep := _add_completed_object(
		CityObjectCatalog.CITY_OBJECT_CITY_CENTER,
		Vector2i(27, 2),
		city_world
	)
	_mark_fixture_city_founded(keep)
	var stockpile := _add_completed_object(
		CityObjectCatalog.CITY_OBJECT_STOCKPILE,
		Vector2i(3, 3),
		city_world
	)
	var house := _add_completed_object(
		CityObjectCatalog.CITY_OBJECT_HOUSE,
		Vector2i(3, 14),
		city_world
	)
	var fishery := _add_completed_object(
		CityObjectCatalog.CITY_OBJECT_FISHING_GROUNDS,
		Vector2i(13, 3),
		city_world
	)
	var stockpile_id := int(stockpile.get("id", -1))
	var keep_id := int(keep.get("id", -1))
	var house_id := int(house.get("id", -1))
	var fishery_id := int(fishery.get("id", -1))

	_expect(
		stockpile_id > 0 and keep_id > 0 and house_id > 0 and fishery_id > 0,
		"The construction-supply fixture must create all four object-container classes."
	)
	if stockpile_id <= 0 or keep_id <= 0 or house_id <= 0 or fishery_id <= 0:
		return

	for storage_fixture in [
		[stockpile_id, 1],
		[keep_id, 1],
		[house_id, 1],
		[fishery_id, 1],
	]:
		_expect(
			CityResourceContainerSystem.add_resource_to_city_object_storage(
				int(storage_fixture[0]),
				WorldData.RESOURCE_FISH,
				int(storage_fixture[1])
			) == int(storage_fixture[1]),
			"Every construction-source classification container must hold its fixture fish."
		)
	_expect(
		CityResourceContainerSystem.add_resource_to_city_object_storage(
			stockpile_id,
			WorldData.RESOURCE_LUMBER,
			8
		) == 8,
		"The real construction delivery must begin with eight Stockpile lumber."
	)

	var pile_result := CityLogisticsSystem.add_resource_to_city_ground_piles_with_result({
		"tile_position": Vector2i(31, 23),
		"resource": WorldData.RESOURCE_FISH,
		"amount_delta": 4,
	})
	var pile_id := _first_ground_pile_id(pile_result)
	var candidates := CityResourceMatcherScript.get_resource_supply_candidates(
		CityResourceMatcherScript.PURPOSE_CONSTRUCTION_SUPPLY,
		WorldData.RESOURCE_FISH,
		99
	)
	var signatures: Array[String] = []
	var contains_private_source := false

	for candidate in candidates:
		var endpoint: Dictionary = candidate.get("endpoint", {})
		var endpoint_id := int(endpoint.get("id", -1))
		signatures.append(
			str(endpoint.get("kind", ""))
			+ ":"
			+ str(endpoint_id)
			+ ":"
			+ str(int(candidate.get("source_tier", -1)))
		)

		if endpoint_id == house_id or endpoint_id == fishery_id:
			contains_private_source = true

	var expected_signatures: Array[String] = [
		CityCitizens.CITY_CITIZEN_HAUL_ENDPOINT_KIND_CITY_OBJECT_CONTAINER
			+ ":" + str(stockpile_id) + ":0",
		CityCitizens.CITY_CITIZEN_HAUL_ENDPOINT_KIND_CITY_OBJECT_CONTAINER
			+ ":" + str(keep_id) + ":1",
		CityCitizens.CITY_CITIZEN_HAUL_ENDPOINT_KIND_GROUND_PILE
			+ ":" + str(pile_id) + ":2",
	]
	_expect(
		pile_id > 0
		and signatures == expected_signatures
		and not contains_private_source,
		"Construction supply candidates must order Stockpile tier 0, Keep tier 1, ordinary pile tier 2, and exclude House/Fishery storage."
	)

	var site_top_left := Vector2i(20, 14)
	var site := CityConstructionSystemScript.create_rectangular_site({
		"object_type": CityObjectCatalog.CITY_OBJECT_HOUSE,
		"top_left": site_top_left,
		"size_tiles": CityObjectCatalog.get_city_object_size_for_type(
			CityObjectCatalog.CITY_OBJECT_HOUSE
		),
		"object_owner": "player",
		"city_world": city_world,
	})
	var site_id := int(site.get("id", -1))
	var source_tile := _get_object_access_tile(city_world, stockpile)
	var citizen := _add_citizen(source_tile)
	var citizen_id := int(citizen.get("id", -1))
	var physical_before := CityResourceAccountingSystem.get_total_physical_city_resource_amount(
		WorldData.RESOURCE_LUMBER
	)
	var candidate := (
		CityConstructionSystemScript
		.get_best_assignable_player_work_for_citizen_and_site(
			citizen_id,
			site_id
		)
	)
	var candidate_task: Dictionary = candidate.get("task_request", {})
	var candidate_haul: Dictionary = candidate_task.get("haul", {})

	_expect(
		site_id > 0
		and str(site.get("phase", ""))
		== CityConstructionSystem.CITY_CONSTRUCTION_PHASE_GATHERING
		and str(candidate.get("player_work_kind", ""))
		== CityConstructionSystem.PLAYER_WORK_KIND_DELIVERY
		and int(candidate_haul.get("source", {}).get("id", -1))
		== stockpile_id
		and int(candidate_haul.get("requested_amount", 0)) == 8,
		"A real House site must select the adjacent Stockpile for its exact eight-lumber delivery."
	)
	if site_id <= 0 or candidate.is_empty():
		return

	_expect(
		CityConstructionSystemScript.assign_player_work_candidate(
			citizen_id,
			candidate
		),
		"The selected object-container construction delivery must assign through the production API."
	)
	var reservation_id := (
		CityLogisticsSystem.get_city_haul_reservation_id_for_citizen(
			citizen_id
		)
	)
	var reservation := CityLogisticsSystem.get_city_haul_reservation(
		reservation_id
	)
	var stockpile_endpoint := (
		CityLogisticsSystem.make_city_citizen_haul_endpoint(stockpile_id)
	)
	_expect(
		reservation_id > 0
		and int(reservation.get("source_reserved_amount", 0)) == 8
		and int(reservation.get("destination_reserved_amount", 0)) == 8
		and CityLogisticsSystem.get_city_haul_endpoint_source_reserved_amount(
			stockpile_endpoint,
			WorldData.RESOURCE_LUMBER
		) == 8
		and CityConstructionSystemScript
		.get_city_construction_site_destination_reserved_resource_amount(
			site_id,
			WorldData.RESOURCE_LUMBER
		) == 8,
		"Construction assignment must reserve exactly eight source units and eight units of House-site demand."
	)

	_advance_single_haul_tick(city_world, citizen_id, 1)
	_advance_single_haul_tick(city_world, citizen_id, 2)
	reservation = CityLogisticsSystem.get_city_haul_reservation(reservation_id)
	_expect(
		CityResourceContainerSystem.get_city_object_stored_resource_amount(
			CityObjectSystem.get_city_object_by_id(stockpile_id),
			WorldData.RESOURCE_LUMBER
		) == 0
		and CityCitizenInventorySystem.get_city_citizen_haul_cargo_resource_amount(
			citizen_id,
			WorldData.RESOURCE_LUMBER
		) == 8
		and int(reservation.get("source_reserved_amount", -1)) == 0
		and int(reservation.get("destination_reserved_amount", 0)) == 8
		and CityConstructionSystemScript
		.get_city_construction_site_destination_reserved_resource_amount(
			site_id,
			WorldData.RESOURCE_LUMBER
		) == 8
		and CityResourceAccountingSystem.get_total_physical_city_resource_amount(
			WorldData.RESOURCE_LUMBER
		) == physical_before,
		"Construction pickup must hard-commit the source, retain exact site capacity, and conserve physical lumber in cargo."
	)

	var completed := _run_single_haul_to_completion(
		city_world,
		citizen_id,
		3,
		100
	)
	site = CityConstructionSystemScript.get_city_construction_site_by_id(site_id)
	_expect(
		completed
		and CityLogisticsSystem.get_city_haul_reservation(
			reservation_id
		).is_empty()
		and CityConstructionSystemScript
		.get_city_construction_site_reserved_resource_amount(
			site_id,
			WorldData.RESOURCE_LUMBER
		) == 8
		and CityConstructionSystemScript
		.get_city_construction_site_remaining_resource_amount(
			site_id,
			WorldData.RESOURCE_LUMBER
		) == 0
		and CityCitizenInventorySystem.get_city_citizen_haul_cargo_amount(citizen_id) == 0
		and CityResourceAccountingSystem.get_total_physical_city_resource_amount(
			WorldData.RESOURCE_LUMBER
		) == physical_before,
		"The real Stockpile-to-House-site haul must release reservations, deliver eight lumber, and conserve every physical unit."
	)


func _test_reserved_stockpile_falls_back_to_keep() -> void:
	var city_world := _reset_fixture(97_303)
	var keep := _add_completed_object(
		CityObjectCatalog.CITY_OBJECT_CITY_CENTER,
		Vector2i(24, 3),
		city_world
	)
	_mark_fixture_city_founded(keep)
	var stockpile := _add_completed_object(
		CityObjectCatalog.CITY_OBJECT_STOCKPILE,
		Vector2i(3, 3),
		city_world
	)
	var stockpile_id := int(stockpile.get("id", -1))
	var keep_id := int(keep.get("id", -1))
	var stockpile_capacity := (
		CityResourceContainerSystem.get_city_object_storage_capacity(stockpile)
	)

	_expect(
		stockpile_id > 0
		and keep_id > 0
		and CityResourceContainerSystem.add_resource_to_city_object_storage(
			stockpile_id,
			WorldData.RESOURCE_STONE,
			stockpile_capacity - 1
		) == stockpile_capacity - 1,
		"The Keep-fallback fixture must leave exactly one physical Stockpile slot."
	)
	if stockpile_id <= 0 or keep_id <= 0:
		return

	var blocker_pile_result := (
		CityLogisticsSystem.add_resource_to_city_ground_piles_with_result({
			"tile_position": Vector2i(9, 14),
			"resource": WorldData.RESOURCE_LUMBER,
			"amount_delta": 1,
		})
	)
	var cleanup_pile_result := (
		CityLogisticsSystem.add_resource_to_city_ground_piles_with_result({
			"tile_position": Vector2i(12, 14),
			"resource": WorldData.RESOURCE_LUMBER,
			"amount_delta": 2,
		})
	)
	var blocker_pile_id := _first_ground_pile_id(blocker_pile_result)
	var cleanup_pile_id := _first_ground_pile_id(cleanup_pile_result)
	var blocker := _add_citizen(Vector2i(9, 14))
	var cleaner := _add_citizen(Vector2i(12, 14))
	var blocker_id := int(blocker.get("id", -1))
	var cleaner_id := int(cleaner.get("id", -1))
	var stockpile_endpoint := (
		CityLogisticsSystem.make_city_citizen_haul_endpoint(stockpile_id)
	)
	var blocker_source := (
		CityLogisticsSystem.make_city_ground_pile_haul_endpoint(
			blocker_pile_id
		)
	)
	var blocker_request := (
		CitizenHaulingSystemScript.make_directed_haul_task_request({
			"city_world": city_world,
			"citizen": blocker,
			"source": blocker_source,
			"destination": stockpile_endpoint,
			"requester": blocker_source,
			"resource_type": WorldData.RESOURCE_LUMBER,
			"requested_amount": 1,
			"reason": CityCitizens.CITY_CITIZEN_HAUL_REASON_GROUND_PILE_CLEANUP,
			"source_access_purpose": (
				CityObjectCatalog.CONTAINER_HAUL_PURPOSE_GROUND_PILE_CLEANUP
			),
			"destination_access_purpose": (
				CityObjectCatalog.CONTAINER_HAUL_PURPOSE_PUBLIC_STORAGE
			),
			"task_source": CityCitizens.CITY_CITIZEN_TASK_SOURCE_AUTONOMY,
			"task_priority": 90,
		})
	)
	_expect(
		blocker_pile_id > 0
		and cleanup_pile_id > 0
		and not blocker_request.is_empty()
		and CityCitizenTaskRuntimeSystem.assign_city_citizen_task(blocker_id, blocker_request),
		"A first cleanup haul must reserve the Stockpile's final shared slot."
	)
	var blocker_reservation_id := (
		CityLogisticsSystem.get_city_haul_reservation_id_for_citizen(
			blocker_id
		)
	)
	stockpile = CityObjectSystem.get_city_object_by_id(stockpile_id)
	_expect(
		blocker_reservation_id > 0
		and CityResourceContainerSystem
		.get_city_object_unreserved_storage_free_space(stockpile) == 0,
		"The active reservation must make the near-full Stockpile unavailable to later cleanup work."
	)

	var cleanup_source := (
		CityLogisticsSystem.make_city_ground_pile_haul_endpoint(
			cleanup_pile_id
		)
	)
	var cleanup_request := (
		CitizenHaulingSystemScript.make_public_storage_haul_task_request({
			"city_world": city_world,
			"citizen": cleaner,
			"source": cleanup_source,
			"requester": cleanup_source,
			"resource_type": WorldData.RESOURCE_LUMBER,
			"requested_amount": 2,
			"reason": CityCitizens.CITY_CITIZEN_HAUL_REASON_GROUND_PILE_CLEANUP,
			"source_access_purpose": (
				CityObjectCatalog.CONTAINER_HAUL_PURPOSE_GROUND_PILE_CLEANUP
			),
			"destination_access_purpose": (
				CityObjectCatalog.CONTAINER_HAUL_PURPOSE_PUBLIC_STORAGE
			),
			"task_source": CityCitizens.CITY_CITIZEN_TASK_SOURCE_AUTONOMY,
			"task_priority": 90,
		})
	)
	var cleanup_haul: Dictionary = cleanup_request.get("haul", {})
	_expect(
		not cleanup_request.is_empty()
		and int(cleanup_haul.get("destination", {}).get("id", -1))
		== keep_id
		and int(cleanup_haul.get("requested_amount", 0)) == 2,
		"Cleanup matching must fall back from a reservation-full Stockpile to the Keep."
	)
	if cleanup_request.is_empty():
		return

	var physical_before := CityResourceAccountingSystem.get_total_physical_city_resource_amount(
		WorldData.RESOURCE_LUMBER
	)
	var accounting_state := CityResourceAccountingSystem.get_current_state()
	var container_before_cleanup := accounting_state.container_version
	var public_before_cleanup := accounting_state.public_storage_version
	_expect(
		CityCitizenTaskRuntimeSystem.assign_city_citizen_task(cleaner_id, cleanup_request),
		"The Keep-fallback request must become a real cleanup assignment."
	)
	var cleaner_reservation_id := (
		CityLogisticsSystem.get_city_haul_reservation_id_for_citizen(
			cleaner_id
		)
	)
	var cleaner_reservation := CityLogisticsSystem.get_city_haul_reservation(
		cleaner_reservation_id
	)
	_expect(
		cleaner_reservation_id > 0
		and int(cleaner_reservation.get("source_reserved_amount", 0)) == 2
		and int(cleaner_reservation.get("destination_reserved_amount", 0)) == 2
		and int(cleaner_reservation.get("destination", {}).get("id", -1))
		== keep_id,
		"The fallback assignment must reserve its cleanup source and exactly two Keep slots."
	)

	var completed := _run_single_haul_to_completion(
		city_world,
		cleaner_id,
		1,
		100
	)
	keep = CityObjectSystem.get_city_object_by_id(keep_id)
	stockpile = CityObjectSystem.get_city_object_by_id(stockpile_id)
	_expect(
		completed
		and CityResourceContainerSystem.get_city_object_stored_resource_amount(
			keep,
			WorldData.RESOURCE_LUMBER
		) == 2
		and CityLogisticsSystem.get_city_ground_pile_resource_amount(
			CityLogisticsSystem.get_city_ground_pile_by_id(blocker_pile_id),
			WorldData.RESOURCE_LUMBER
		) == 1
		and CityLogisticsSystem.get_city_haul_reservation(
			blocker_reservation_id
		).get("destination_reserved_amount", 0) == 1
		and CityResourceContainerSystem
		.get_city_object_unreserved_storage_free_space(stockpile) == 0,
		"The real fallback haul must fill the Keep while preserving the earlier Stockpile reservation."
	)
	_expect(
		CityResourceAccountingSystem.get_total_physical_city_resource_amount(
			WorldData.RESOURCE_LUMBER
		) == physical_before
		and accounting_state.container_version == container_before_cleanup + 1
		and accounting_state.public_storage_version == public_before_cleanup + 1,
		"Keep fallback must conserve cleanup lumber and publish exactly one public-container deposit."
	)


func _reset_fixture(seed: int) -> WorldData:
	WorldData.reset_runtime_session_state()
	CityResourceMatcherScript.reset_resource_demand_category_priorities()
	SimulationClock.start_new_game()
	var city_world := WorldData.new()
	city_world.setup(TEST_WORLD_SIZE.x, TEST_WORLD_SIZE.y, seed)

	for y in range(city_world.height):
		for x in range(city_world.width):
			var tile := city_world.get_tile_for_internal_read(x, y)
			tile["terrain"] = WorldData.TERRAIN_LAND
			tile["biome"] = WorldData.BIOME_PLAIN
			tile["is_land"] = true
			tile["fertility"] = 50.0
			tile.erase("surface_feature")

	city_world.mark_tile_data_changed()
	var culture := WorldData.create_culture(
		"Resource Container Integration Culture " + str(seed)
	)
	test_culture_id = int(culture.get("id", -1))
	var polity := WorldPoliticalState.create_polity({
		"name": "Resource Container Integration Realm",
		"polity_type": PolityData.POLITY_TYPE_KINGDOM,
		"primary_culture_id": test_culture_id,
	})
	var city := WorldPoliticalState.create_settlement({
		"name": "Resource Container Integration City",
		"settlement_type": SettlementData.SETTLEMENT_TYPE_CITY,
		"polity_id": int(polity.get("id", -1)),
		"world_region_top_left": Vector2i.ZERO,
		"world_region_center": Vector2i.ZERO,
		"world_region_size": 1,
		"simulation_backend_kind": (
			SettlementSimulationContext.BACKEND_CITY_SETTLEMENT_STATE
		),
	})
	var city_id := int(city.get("id", -1))
	var city_state = WorldPoliticalState.get_city_simulation_state(city_id)
	_expect(
		city_state is CitySettlementSimulationState
		and WorldPoliticalState.set_active_settlement(city_id),
		"Fixture must create one settlement-owned city state."
	)
	if city_state is CitySettlementSimulationState:
		city_state.city_runtime_data.merge({
			"id": city_id,
			"name": "Resource Container Integration City",
			"primary_culture_id": test_culture_id,
			"founded": false,
			"can_build": false,
		}, true)
	WorldData.store_city_world_for_city_state(
		CityCitizenUnboundCompatibility.get_city_state(),
		city_world, seed)
	return city_world


func _mark_fixture_city_founded(keep: Dictionary) -> void:
	var city_state = WorldPoliticalState.get_active_city_simulation_state()
	if not city_state is CitySettlementSimulationState or keep.is_empty():
		return

	city_state.city_runtime_data.merge({
		"city_world_seed": city_state.city_seed,
		"city_map_size": Vector2i(
			city_state.city_world.width,
			city_state.city_world.height
		),
		"foundation_top_left": keep.get("top_left", Vector2i(-1, -1)),
		"foundation_size": keep.get("size", Vector2i.ZERO),
		"foundation_object_id": int(keep.get("id", -1)),
		"foundation_object_owner": str(keep.get("owner", "")),
		"founded": true,
		"can_build": true,
	}, true)


func _add_completed_object(
	object_type: String,
	top_left: Vector2i,
	city_world: WorldData
) -> Dictionary:
	return CityObjectSystem.add_city_object({
		"object_type": object_type,
		"top_left": top_left,
		"size_tiles": CityObjectCatalog.get_city_object_size_for_type(object_type),
		"object_owner": "player",
		"city_world": city_world,
	})


func _add_citizen(tile_position: Vector2i) -> Dictionary:
	if tile_position == CityCitizens.INVALID_CITY_TILE_POSITION:
		return {}

	return CityCitizenRegistrySystem.add_city_citizen(
		"",
		tile_position,
		CityCitizens.CITY_CITIZEN_SEX_FEMALE,
		test_culture_id
	)


func _get_object_access_tile(
	city_world: WorldData,
	city_object: Dictionary
) -> Vector2i:
	for raw_tile in CityNavigationSystem.get_city_object_access_tiles(
		city_world,
		city_object
	):
		if raw_tile is Vector2i:
			return raw_tile

	return CityCitizens.INVALID_CITY_TILE_POSITION


func _advance_single_haul_tick(
	city_world: WorldData,
	citizen_id: int,
	tick_index: int
) -> void:
	SimulationClock.absolute_world_minutes += 2
	CitizenMovementSystemScript.run_tick(tick_index, 2)
	var citizen := CityCitizenRegistrySystem.get_city_citizen_by_id(citizen_id)
	var current_task := CityCitizenTaskRuntimeSystem.get_city_citizen_current_task(citizen_id)

	if (
		citizen.is_empty()
		or str(current_task.get("kind", ""))
		!= CityCitizens.CITY_CITIZEN_TASK_KIND_HAUL
	):
		return

	CitizenHaulingSystemScript.advance_haul_task(
		city_world,
		{
			"citizen_id": citizen_id,
			"citizen": citizen,
			"current_task": current_task,
			"path_requests_remaining": 8,
		}
	)


func _run_single_haul_to_completion(
	city_world: WorldData,
	citizen_id: int,
	start_tick: int,
	maximum_ticks: int
) -> bool:
	for tick_offset in range(maximum_ticks):
		_advance_single_haul_tick(
			city_world,
			citizen_id,
			start_tick + tick_offset
		)
		var current_task := CityCitizenTaskRuntimeSystem.get_city_citizen_current_task(citizen_id)
		var reservation_id := (
			CityLogisticsSystem.get_city_haul_reservation_id_for_citizen(
				citizen_id
			)
		)

		if (
			str(current_task.get("kind", ""))
			== CityCitizens.CITY_CITIZEN_TASK_KIND_NONE
			and CityCitizenInventorySystem.get_city_citizen_haul_cargo_amount(citizen_id) == 0
			and reservation_id
			== CityCitizens.INVALID_CITY_CITIZEN_HAUL_RESERVATION_ID
		):
			return true

	return false


func _first_ground_pile_id(add_result: Dictionary) -> int:
	for raw_placement in add_result.get("placements", []):
		if raw_placement is Dictionary:
			return int(raw_placement.get("ground_pile_id", -1))

	return -1


func _expect(condition: bool, message: String) -> void:
	if condition:
		return

	failure_count += 1
	push_error("City resource-container integration test: " + message)
