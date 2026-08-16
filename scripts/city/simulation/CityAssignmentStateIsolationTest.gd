extends Node

const CityStateValidator := preload(
	"res://scripts/city/simulation/CityStateValidator.gd"
)
const SHARED_HOUSE_TOP_LEFT := Vector2i(3, 3)
const SHARED_FISHERY_TOP_LEFT := Vector2i(10, 10)
const SHARED_CITIZEN_TILE := Vector2i(20, 20)

var failure_count: int = 0


func _ready() -> void:
	_test_equal_version_assignment_and_workplace_isolation()
	WorldData.reset_runtime_session_state()

	if failure_count > 0:
		push_error(
			"City assignment state isolation test failed: "
			+ str(failure_count)
		)
		get_tree().quit(1)
		return

	print("City assignment state isolation test passed.")
	get_tree().quit(0)


func _test_equal_version_assignment_and_workplace_isolation() -> void:
	WorldData.reset_runtime_session_state()
	var culture := WorldData.create_culture("Assignment Isolation Culture")
	var culture_id := int(culture.get("id", -1))
	var polity := WorldPoliticalState.create_polity({
		"name": "Assignment Isolation Realm",
		"polity_type": PolityData.POLITY_TYPE_KINGDOM,
		"primary_culture_id": culture_id,
	})
	var polity_id := int(polity.get("id", -1))
	var city_a := _create_city(
		"Assignment Isolation City A",
		polity_id,
		Vector2i(1, 1)
	)
	var city_b := _create_city(
		"Assignment Isolation City B",
		polity_id,
		Vector2i(8, 8)
	)

	_expect(
		culture_id > 0 and not city_a.is_empty() and not city_b.is_empty(),
		"The isolation fixture must create two instance-owned Cities."
	)
	if city_a.is_empty() or city_b.is_empty():
		return

	var city_a_id := int(city_a.get("id", -1))
	var city_b_id := int(city_b.get("id", -1))
	var state_a := _exercise_city(city_a_id, culture_id, 99_111)
	var state_b := _exercise_city(city_b_id, culture_id, 99_112)
	if state_a.is_empty() or state_b.is_empty():
		return

	# Equalize numeric versions deliberately. State identity must still separate
	# the Cities even when every local ID and invalidation counter can collide.
	var assignment_state_a: CityAssignmentState = state_a.get(
		"assignment_state"
	)
	var assignment_state_b: CityAssignmentState = state_b.get(
		"assignment_state"
	)
	var workplace_state_a: CityWorkplaceState = state_a.get(
		"workplace_state"
	)
	var workplace_state_b: CityWorkplaceState = state_b.get(
		"workplace_state"
	)
	assignment_state_a.assignment_version = 7
	assignment_state_b.assignment_version = 7
	workplace_state_a.workplace_version = 11
	workplace_state_b.workplace_version = 11

	_expect(
		int(state_a.get("citizen_id", -1)) == 1
		and int(state_b.get("citizen_id", -1)) == 1
		and int(state_a.get("house_id", -1)) == 2
		and int(state_b.get("house_id", -1)) == 2
		and int(state_a.get("fishery_id", -1)) == 3
		and int(state_b.get("fishery_id", -1)) == 3,
		"Both Cities must independently reuse settlement-local citizen and object IDs."
	)
	_expect(
		not is_same(
			state_a.get("assignment_state"),
			state_b.get("assignment_state")
		)
		and not is_same(
			state_a.get("workplace_state"),
			state_b.get("workplace_state")
		)
		and not is_same(
			state_a.get("registry_state"),
			state_b.get("registry_state")
		)
		and not is_same(
			state_a.get("object_state"),
			state_b.get("object_state")
		),
		"Equal IDs and versions must never alias assignment, workplace, citizen, or object owners."
	)

	_expect(
		WorldPoliticalState.set_active_settlement(city_a_id),
		"City A must become active for isolated mutation."
	)
	var validator_a := CityStateValidator.validate_for_settlement(
		WorldPoliticalState.get_settlement_context(city_a_id),
		true,
		false
	)
	var citizen_id := int(state_a.get("citizen_id", -1))
	_expect(
		CityAssignmentSystem.remove_city_citizen_home(citizen_id)
		and CityAssignmentSystem.remove_city_citizen_job(citizen_id),
		"City A must accept focused home and job removals."
	)
	CityAssignmentSystem.get_current_state().assignment_version = 7
	CityEmploymentSystem.get_current_state().workplace_version = 11

	_expect(
		WorldPoliticalState.set_active_settlement(city_b_id)
		and _active_city_matches_assigned_state(state_b),
		"A -> B must restore City B's own bidirectional relationships."
	)
	var validator_b := CityStateValidator.validate_for_settlement(
		WorldPoliticalState.get_settlement_context(city_b_id),
		false,
		false
	)
	_expect(
		int(validator_a.get("assignment_state_instance_id", 0))
		!= int(validator_b.get("assignment_state_instance_id", 0))
		and int(validator_b.get("assignment_state_instance_id", 0))
		== int(state_b.get("assignment_state").get_instance_id())
		and int(validator_b.get("workplace_state_instance_id", 0))
		== int(state_b.get("workplace_state").get_instance_id()),
		"Validator caches must reject equal-version results owned by another settlement."
	)

	_expect(
		WorldPoliticalState.set_active_settlement(city_a_id)
		and _active_city_matches_unassigned_state(state_a),
		"B -> A must restore City A's independent removals."
	)
	_expect(
		WorldPoliticalState.set_active_settlement(city_b_id)
		and _active_city_matches_assigned_state(state_b),
		"A -> B -> A -> B must preserve City B without cross-settlement references."
	)


func _exercise_city(
	city_id: int,
	culture_id: int,
	world_seed: int
) -> Dictionary:
	_expect(
		WorldPoliticalState.set_active_settlement(city_id),
		"The City under test must become active."
	)
	if WorldPoliticalState.active_settlement_id != city_id:
		return {}

	var city_world := _make_world(32, 32, world_seed)
	WorldPoliticalState.set_current_city_world(city_world)
	WorldPoliticalState.set_current_city_seed(world_seed)
	var city_state = WorldPoliticalState.get_city_simulation_state(city_id)
	_expect(
		city_state is CitySettlementSimulationState,
		"The assignment fixture must expose its settlement-owned City state."
	)
	if not city_state is CitySettlementSimulationState:
		return {}
	var settlement := WorldPoliticalState.get_settlement(city_id)
	city_state.city_runtime_data.clear()
	city_state.city_runtime_data.merge({
		"name": str(settlement.get("name", "Assignment Isolation City")),
		"primary_culture_id": culture_id,
		"founded": false,
		"can_build": false,
	}, true)
	var keep_top_left := Vector2i(0, 20)
	var keep := CityObjectSystem.register_completed_city_object({
		"object_type": CityObjectCatalog.CITY_OBJECT_CITY_CENTER,
		"top_left": keep_top_left,
		"size_tiles": CityObjectCatalog.get_city_object_size_for_type(
			CityObjectCatalog.CITY_OBJECT_CITY_CENTER
		),
		"object_owner": "player",
		"city_world": city_world,
	})
	_expect(
		not keep.is_empty(),
		"Each assignment fixture must register its Keep while unfounded."
	)
	if keep.is_empty():
		return {}
	city_state.city_runtime_data.merge({
		"founded": true,
		"can_build": true,
		"foundation_top_left": keep_top_left,
		"foundation_size": keep.get("size", Vector2i.ZERO),
		"foundation_object_id": int(keep.get("id", -1)),
		"foundation_object_owner": str(keep.get("owner", "")),
	}, true)
	var house := CityObjectSystem.register_completed_city_object({
		"object_type": CityObjectCatalog.CITY_OBJECT_HOUSE,
		"top_left": SHARED_HOUSE_TOP_LEFT,
		"size_tiles": CityObjectCatalog.get_city_object_size_for_type(
			CityObjectCatalog.CITY_OBJECT_HOUSE
		),
		"object_owner": "player",
		"city_world": city_world,
	})
	var fishery := CityObjectSystem.register_completed_city_object({
		"object_type": CityObjectCatalog.CITY_OBJECT_FISHING_GROUNDS,
		"top_left": SHARED_FISHERY_TOP_LEFT,
		"size_tiles": CityObjectCatalog.get_city_object_size_for_type(
			CityObjectCatalog.CITY_OBJECT_FISHING_GROUNDS
		),
		"object_owner": "player",
		"city_world": city_world,
	})
	var citizen := CityCitizenRegistrySystem.add_city_citizen(
		"",
		SHARED_CITIZEN_TILE,
		CityCitizens.CITY_CITIZEN_SEX_FEMALE,
		culture_id
	)
	var citizen_id := int(citizen.get("id", -1))
	var house_id := int(house.get("id", -1))
	var fishery_id := int(fishery.get("id", -1))

	_expect(
		citizen_id == 1
		and house_id == 2
		and fishery_id == 3
		and CityAssignmentSystem.assign_city_citizen_home(
			citizen_id,
			house_id
		)
		and CityAssignmentSystem.assign_city_citizen_job(
			citizen_id,
			fishery_id
		),
		"Each City must independently establish matching local relationships."
	)
	if citizen_id <= 0 or house_id <= 0 or fishery_id <= 0:
		return {}

	return {
		"city_id": city_id,
		"citizen_id": citizen_id,
		"house_id": house_id,
		"fishery_id": fishery_id,
		"assignment_state": CityAssignmentSystem.get_current_state(),
		"workplace_state": CityEmploymentSystem.get_current_state(),
		"registry_state": CityCitizenRegistrySystem.get_current_state(),
		"object_state": CityObjectSystem.get_current_state(),
	}


func _active_city_matches_assigned_state(expected: Dictionary) -> bool:
	var citizen_id := int(expected.get("citizen_id", -1))
	var house_id := int(expected.get("house_id", -1))
	var fishery_id := int(expected.get("fishery_id", -1))
	var citizen := CityCitizenRegistrySystem.get_city_citizen_by_id(citizen_id)
	return (
		is_same(
			CityAssignmentSystem.get_current_state(),
			expected.get("assignment_state")
		)
		and is_same(
			CityEmploymentSystem.get_current_state(),
			expected.get("workplace_state")
		)
		and int(citizen.get("home_object_id", -1)) == house_id
		and int(citizen.get("job_object_id", -1)) == fishery_id
		and CityAssignmentSystem.get_city_object_resident_ids(
			CityObjectSystem.get_city_object_by_id(house_id)
		).has(citizen_id)
		and CityEmploymentSystem.get_city_object_worker_ids(
			CityObjectSystem.get_city_object_by_id(fishery_id)
		).has(citizen_id)
	)


func _active_city_matches_unassigned_state(expected: Dictionary) -> bool:
	var citizen_id := int(expected.get("citizen_id", -1))
	var citizen := CityCitizenRegistrySystem.get_city_citizen_by_id(citizen_id)
	return (
		is_same(
			CityAssignmentSystem.get_current_state(),
			expected.get("assignment_state")
		)
		and is_same(
			CityEmploymentSystem.get_current_state(),
			expected.get("workplace_state")
		)
		and int(citizen.get("home_object_id", 0)) == -1
		and int(citizen.get("job_object_id", 0)) == -1
	)


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


func _make_world(width: int, height: int, seed_value: int) -> WorldData:
	var world := WorldData.new()
	world.setup(width, height, seed_value)
	for y in range(height):
		for x in range(width):
			world.tiles[y][x] = {
				"fertility": 50.0,
				"elevation": 0.2,
				"temperature": 0.5,
				"precipitation": 0.5,
				"terrain": WorldData.TERRAIN_LAND,
				"biome": WorldData.BIOME_PLAIN,
				"resource": WorldData.RESOURCE_NONE,
				"is_land": true,
			}
	world.mark_tile_data_changed()
	return world


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	failure_count += 1
	push_error("City assignment state isolation test: " + message)
