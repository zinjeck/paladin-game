extends Node

const CitySettlementRuntimeBootstrapScript = preload(
	"res://scripts/city/simulation/CitySettlementRuntimeBootstrap.gd"
)

const TEST_WORLD_SIZE := Vector2i(32, 32)
const KEEP_TOP_LEFT := Vector2i(10, 10)

var failure_count: int = 0


func _ready() -> void:
	_test_explicit_local_migrations_and_idempotence()
	_test_missing_foundation_keep_recovery()
	_test_invalid_foundation_reset_is_target_local()
	_test_starting_population_is_created_once()
	_test_npc_bootstrap_mirror_isolation_and_retry()
	WorldData.reset_runtime_session_state()

	if failure_count > 0:
		push_error(
			"City settlement runtime bootstrap test failed: "
			+ str(failure_count)
		)
		get_tree().quit(1)
		return

	print("City settlement runtime bootstrap test passed.")
	get_tree().quit(0)


func _test_explicit_local_migrations_and_idempotence() -> void:
	_reset_fixture()
	var culture_id := _create_culture("Bootstrap Local Culture")
	var polity_id := _create_polity("Bootstrap Local Realm", culture_id)
	var city_a := _create_founded_city(
		"Bootstrap Local A",
		polity_id,
		culture_id,
		61_001,
		"owner_a"
	)
	var city_b := _create_founded_city(
		"Bootstrap Local B",
		polity_id,
		culture_id,
		61_002,
		"owner_b"
	)
	if city_a.is_empty() or city_b.is_empty():
		_expect(false, "The local migration A/B fixture must be created.")
		return

	var state_a: CitySettlementSimulationState = city_a["state"]
	var state_b: CitySettlementSimulationState = city_b["state"]
	var city_a_id := int(city_a["settlement_id"])
	var city_b_id := int(city_b["settlement_id"])
	_seed_legacy_citizen(state_a, culture_id)
	state_b.citizen_registry_state.starting_population_initialized = true
	var b_snapshot := _capture_state_snapshot(state_b)
	var b_identities := _capture_owner_identities(state_b)

	_expect(
		WorldPoliticalState.set_active_settlement(city_b_id),
		"City B must remain globally selected while City A bootstraps."
	)
	var context_a = WorldPoliticalState.get_settlement_context(city_a_id)
	var result := CitySettlementRuntimeBootstrapScript.ensure_ready(context_a)
	var migrated_citizen: Dictionary = (
		state_a.citizen_registry_state.citizens[0]
		if not state_a.citizen_registry_state.citizens.is_empty()
		else {}
	)

	_expect(
		bool(result.get("success", false))
		and int(result.get("settlement_id", -1)) == city_a_id
		and int(result.get("state_instance_id", 0))
		== state_a.get_instance_id()
		and str(result.get("failure_code", ""))
		== CitySettlementRuntimeBootstrapScript.FAILURE_NONE,
		"The bootstrap result must identify and succeed for explicit City A."
	)
	_expect(
		WorldPoliticalState.active_settlement_id == city_b_id,
		"Bootstrapping City A must not change global presentation selection."
	)
	_expect(
		migrated_citizen is Dictionary
		and CityCitizens.is_valid_city_citizen_sex(
			str(migrated_citizen.get("sex", ""))
		)
		and not str(migrated_citizen.get("name", "")).is_empty()
		and migrated_citizen.has("city_tile_position")
		and migrated_citizen.has("inventory")
		and CityCitizens.has_complete_city_citizen_need_state(
			migrated_citizen
		)
		and CityCitizens.has_complete_city_citizen_task_state(
			migrated_citizen
		)
		and CityCitizens.has_complete_city_citizen_movement_state(
			migrated_citizen
		),
		"Explicit bootstrap must migrate demographics, spatial, inventory, needs, task, and movement state."
	)
	var changed_domains: Dictionary = result.get("changed_domains", {})
	_expect(
		changed_domains.has("citizen_demographics")
		and changed_domains.has("citizen_spatial_state")
		and changed_domains.has("citizen_task_state")
		and changed_domains.has("citizen_movement_state")
		and int(result.get("changed_count", 0)) >= 4,
		"The structured result must report every migrated citizen domain."
	)
	_expect(
		_capture_state_snapshot(state_b) == b_snapshot
		and _owner_identities_match(state_b, b_identities),
		"Bootstrapping City A must preserve every City B owner and value."
	)

	var a_snapshot := _capture_state_snapshot(state_a)
	var a_identities := _capture_owner_identities(state_a)
	var second_result := (
		CitySettlementRuntimeBootstrapScript.ensure_ready(context_a)
	)
	_expect(
		bool(second_result.get("success", false))
		and int(second_result.get("changed_count", -1)) == 0
		and (second_result.get("changed_domains", {}) as Dictionary).is_empty()
		and _capture_state_snapshot(state_a) == a_snapshot
		and _owner_identities_match(state_a, a_identities),
		"A second bootstrap must be an exact idempotent no-op."
	)


func _test_missing_foundation_keep_recovery() -> void:
	_reset_fixture()
	var culture_id := _create_culture("Bootstrap Recovery Culture")
	var polity_id := _create_polity("Bootstrap Recovery Realm", culture_id)
	var city_a := _create_founded_city(
		"Bootstrap Recovery A",
		polity_id,
		culture_id,
		62_001,
		"recovery_a"
	)
	var city_b := _create_founded_city(
		"Bootstrap Recovery B",
		polity_id,
		culture_id,
		62_002,
		"recovery_b"
	)
	if city_a.is_empty() or city_b.is_empty():
		_expect(false, "The foundation recovery A/B fixture must be created.")
		return

	var state_a: CitySettlementSimulationState = city_a["state"]
	var state_b: CitySettlementSimulationState = city_b["state"]
	state_a.citizen_registry_state.starting_population_initialized = true
	state_b.citizen_registry_state.starting_population_initialized = true
	state_a.object_state.objects.clear()
	state_a.object_state.object_index_by_id.clear()
	state_a.object_state.occupied_tiles.clear()
	var b_snapshot := _capture_state_snapshot(state_b)
	var b_identities := _capture_owner_identities(state_b)
	var city_b_id := int(city_b["settlement_id"])
	WorldPoliticalState.set_active_settlement(city_b_id)

	var context_a = WorldPoliticalState.get_settlement_context(
		int(city_a["settlement_id"])
	)
	var result := CitySettlementRuntimeBootstrapScript.ensure_ready(context_a)
	var recovered_keeps := _get_city_keeps(state_a)
	_expect(
		bool(result.get("success", false))
		and int((result.get("changed_domains", {}) as Dictionary).get(
			"foundation_object_recovered",
			0
		)) == 1
		and recovered_keeps.size() == 1
		and int(state_a.city_runtime_data.get("foundation_object_id", -1))
		== int(recovered_keeps[0].get("id", -1)),
		"A missing valid foundation Keep must be recovered only in the explicit target."
	)
	_expect(
		_capture_state_snapshot(state_b) == b_snapshot
		and _owner_identities_match(state_b, b_identities),
		"Foundation recovery in A must not touch B."
	)

	var second_result := (
		CitySettlementRuntimeBootstrapScript.ensure_ready(context_a)
	)
	_expect(
		bool(second_result.get("success", false))
		and int(second_result.get("changed_count", -1)) == 0
		and _get_city_keeps(state_a).size() == 1,
		"Foundation recovery retry must never duplicate the Keep."
	)


func _test_invalid_foundation_reset_is_target_local() -> void:
	_reset_fixture()
	var culture_id := _create_culture("Bootstrap Reset Culture")
	var player_polity_id := _create_polity(
		"Bootstrap Reset Player Realm",
		culture_id
	)
	WorldPoliticalState.player_polity_id = player_polity_id
	var city_a := _create_unfounded_city(
		"Bootstrap Reset A",
		player_polity_id,
		63_001
	)
	var npc_polity_id := _create_polity("Bootstrap Reset NPC Realm", culture_id)
	var city_b := _create_founded_city(
		"Bootstrap Reset B",
		npc_polity_id,
		culture_id,
		63_002,
		"reset_b"
	)
	if city_a.is_empty() or city_b.is_empty():
		_expect(false, "The invalid foundation reset fixture must be created.")
		return

	var city_a_id := int(city_a["settlement_id"])
	var city_b_id := int(city_b["settlement_id"])
	WorldPoliticalState.set_polity_capital(player_polity_id, city_a_id)
	var state_a: CitySettlementSimulationState = city_a["state"]
	var state_b: CitySettlementSimulationState = city_b["state"]
	state_b.citizen_registry_state.starting_population_initialized = true
	state_a.city_runtime_data = {
		"id": city_a_id,
		"name": "Bootstrap Reset A",
		"primary_culture_id": culture_id,
		"founded": true,
		"can_build": true,
	}
	state_a.object_state.objects = [{"id": 77, "test_owner": "a"}]
	state_a.object_state.object_version = 9
	state_a.citizen_registry_state.citizens = [{"id": 88, "test_owner": "a"}]
	state_a.citizen_registry_state.citizen_version = 10
	state_a.work_state.player_commands = [{"id": 99, "test_owner": "a"}]
	state_a.logistics_state.ground_piles = [{"id": 111, "test_owner": "a"}]
	var a_world: WorldData = state_a.city_world
	var a_seed := state_a.city_seed
	var a_old_owners := _capture_owner_identities(state_a)
	var b_snapshot := _capture_state_snapshot(state_b)
	var b_identities := _capture_owner_identities(state_b)
	WorldData.player_city_founded = true
	WorldData.player_city_foundation_top_left = Vector2i(1, 1)
	WorldData.player_city_foundation_size = Vector2i.ONE
	WorldPoliticalState.set_active_settlement(city_b_id)

	var context_a = WorldPoliticalState.get_settlement_context(city_a_id)
	var result := CitySettlementRuntimeBootstrapScript.ensure_ready(context_a)
	_expect(
		bool(result.get("success", false))
		and int((result.get("changed_domains", {}) as Dictionary).get(
			"foundation_runtime_reset",
			0
		)) == 1
		and not (result.get("warnings", []) as Array).is_empty()
		and state_a.city_runtime_data.is_empty()
		and is_same(state_a.city_world, a_world)
		and state_a.city_seed == a_seed
		and _all_runtime_owners_replaced(state_a, a_old_owners),
		"Invalid founded state must reset the exact target while preserving its world and seed."
	)
	_expect(
		not WorldData.player_city_founded
		and WorldData.player_city_foundation_top_left == Vector2i(-1, -1)
		and WorldData.player_city_foundation_size == Vector2i.ZERO,
		"Player-capital mirrors must synchronize only after the explicit capital reset."
	)
	_expect(
		WorldPoliticalState.active_settlement_id == city_b_id
		and _capture_state_snapshot(state_b) == b_snapshot
		and _owner_identities_match(state_b, b_identities),
		"Invalid foundation repair in A must preserve globally selected City B exactly."
	)

	var reset_identities := _capture_owner_identities(state_a)
	var second_result := (
		CitySettlementRuntimeBootstrapScript.ensure_ready(context_a)
	)
	_expect(
		bool(second_result.get("success", false))
		and int(second_result.get("changed_count", -1)) == 0
		and _owner_identities_match(state_a, reset_identities),
		"A completed targeted reset must be idempotent on retry."
	)


func _test_starting_population_is_created_once() -> void:
	_reset_fixture()
	var culture_id := _create_culture("Bootstrap Population Culture")
	var polity_id := _create_polity("Bootstrap Population Realm", culture_id)
	var city_a := _create_founded_city(
		"Bootstrap Population A",
		polity_id,
		culture_id,
		64_001,
		"population_a"
	)
	var city_b := _create_unfounded_city(
		"Bootstrap Population B",
		polity_id,
		64_002
	)
	if city_a.is_empty() or city_b.is_empty():
		_expect(false, "The starting population fixture must be created.")
		return

	var state_a: CitySettlementSimulationState = city_a["state"]
	state_a.citizen_registry_state.starting_population_initialized = false
	state_a.citizen_registry_state.citizens.clear()
	state_a.citizen_registry_state.citizen_index_by_id.clear()
	state_a.citizen_registry_state.next_citizen_id = 1
	state_a.citizen_spatial_state.citizen_ids_by_tile.clear()
	WorldPoliticalState.set_active_settlement(int(city_b["settlement_id"]))
	var context_a = WorldPoliticalState.get_settlement_context(
		int(city_a["settlement_id"])
	)

	var result := CitySettlementRuntimeBootstrapScript.ensure_ready(context_a)
	var registry_state := state_a.citizen_registry_state
	_expect(
		bool(result.get("success", false))
		and int((result.get("changed_domains", {}) as Dictionary).get(
			"starting_population",
			0
		)) == CityCitizenRegistrySystem.STARTING_CITY_POPULATION
		and registry_state.starting_population_initialized
		and registry_state.citizens.size()
		== CityCitizenRegistrySystem.STARTING_CITY_POPULATION
		and CityCitizenRegistrySystem.get_city_citizen_count_by_sex_for_city_state(
			state_a,
			CityCitizens.CITY_CITIZEN_SEX_MALE
		) == CityCitizenRegistrySystem.STARTING_CITY_MALE_POPULATION
		and CityCitizenRegistrySystem.get_city_citizen_count_by_sex_for_city_state(
			state_a,
			CityCitizens.CITY_CITIZEN_SEX_FEMALE
		) == CityCitizenRegistrySystem.STARTING_CITY_FEMALE_POPULATION,
		"A founded empty settlement must receive the exact balanced starting population."
	)

	var population_snapshot := registry_state.citizens.duplicate(true)
	var citizen_version := registry_state.citizen_version
	var spatial_snapshot := (
		state_a.citizen_spatial_state.citizen_ids_by_tile.duplicate(true)
	)
	var second_result := (
		CitySettlementRuntimeBootstrapScript.ensure_ready(context_a)
	)
	_expect(
		bool(second_result.get("success", false))
		and int(second_result.get("changed_count", -1)) == 0
		and registry_state.citizens == population_snapshot
		and registry_state.citizen_version == citizen_version
		and state_a.citizen_spatial_state.citizen_ids_by_tile
		== spatial_snapshot,
		"Starting population initialization must occur at most once."
	)


func _test_npc_bootstrap_mirror_isolation_and_retry() -> void:
	_reset_fixture()
	var culture_id := _create_culture("Bootstrap Retry Culture")
	var player_polity_id := _create_polity(
		"Bootstrap Retry Player Realm",
		culture_id
	)
	WorldPoliticalState.player_polity_id = player_polity_id
	var player_city := _create_unfounded_city(
		"Bootstrap Retry Capital",
		player_polity_id,
		65_001
	)
	var npc_polity_id := _create_polity("Bootstrap Retry NPC Realm", culture_id)
	var npc_city := _create_unprepared_city(
		"Bootstrap Retry NPC",
		npc_polity_id
	)
	if player_city.is_empty() or npc_city.is_empty():
		_expect(false, "The retry and NPC mirror fixture must be created.")
		return

	var player_city_id := int(player_city["settlement_id"])
	var npc_city_id := int(npc_city["settlement_id"])
	WorldPoliticalState.set_polity_capital(player_polity_id, player_city_id)
	WorldPoliticalState.set_active_settlement(player_city_id)
	var npc_state: CitySettlementSimulationState = npc_city["state"]
	var npc_context = WorldPoliticalState.get_settlement_context(npc_city_id)
	var npc_identities := _capture_owner_identities(npc_state)
	WorldData.player_city_founded = true
	WorldData.player_city_foundation_top_left = Vector2i(3, 3)
	WorldData.player_city_foundation_size = Vector2i(4, 4)

	var failed_result := (
		CitySettlementRuntimeBootstrapScript.ensure_ready(npc_context)
	)
	_expect(
		not bool(failed_result.get("success", true))
		and str(failed_result.get("failure_code", ""))
		== CitySettlementRuntimeBootstrapScript.FAILURE_MISSING_CITY_WORLD
		and _owner_identities_match(npc_state, npc_identities),
		"A missing-world failure must leave the explicit target retryable."
	)
	_expect(
		WorldData.player_city_founded
		and WorldData.player_city_foundation_top_left == Vector2i(3, 3)
		and WorldData.player_city_foundation_size == Vector2i(4, 4),
		"Bootstrapping an NPC settlement must not touch player-capital mirrors."
	)

	npc_state.city_world = _make_world(TEST_WORLD_SIZE, 65_002)
	npc_state.city_seed = 65_002
	npc_state.city_runtime_data = {
		"id": npc_city_id,
		"name": "Bootstrap Retry NPC",
		"primary_culture_id": culture_id,
		"founded": false,
		"can_build": false,
	}
	var retry_result := (
		CitySettlementRuntimeBootstrapScript.ensure_ready(npc_context)
	)
	_expect(
		bool(retry_result.get("success", false))
		and not npc_context.is_player_polity
		and not npc_context.is_capital
		and WorldPoliticalState.active_settlement_id == player_city_id,
		"A corrected NPC settlement must bootstrap without player-capital flags or selection changes."
	)
	_expect(
		WorldData.player_city_founded
		and WorldData.player_city_foundation_top_left == Vector2i(3, 3)
		and WorldData.player_city_foundation_size == Vector2i(4, 4),
		"Successful NPC bootstrap must also leave player mirrors untouched."
	)

	var npc_snapshot := _capture_state_snapshot(npc_state)
	var npc_ready_identities := _capture_owner_identities(npc_state)
	WorldPoliticalState.set_active_settlement(npc_city_id)
	WorldPoliticalState.set_active_settlement(player_city_id)
	var selection_independent_result := (
		CitySettlementRuntimeBootstrapScript.ensure_ready(npc_context)
	)
	_expect(
		bool(selection_independent_result.get("success", false))
		and int(selection_independent_result.get("changed_count", -1)) == 0
		and _capture_state_snapshot(npc_state) == npc_snapshot
		and _owner_identities_match(npc_state, npc_ready_identities),
		"Changing global selection must not alter an explicit bootstrap result."
	)


func _reset_fixture() -> void:
	WorldData.reset_runtime_session_state()
	SimulationClock.set_simulation_paused(true)


func _create_culture(culture_name: String) -> int:
	return int(WorldData.create_culture(culture_name).get("id", -1))


func _create_polity(polity_name: String, culture_id: int) -> int:
	return int(WorldPoliticalState.create_polity({
		"name": polity_name,
		"polity_type": PolityData.POLITY_TYPE_KINGDOM,
		"primary_culture_id": culture_id,
	}).get("id", -1))


func _create_unprepared_city(city_name: String, polity_id: int) -> Dictionary:
	var settlement := WorldPoliticalState.create_settlement({
		"name": city_name,
		"settlement_type": SettlementData.SETTLEMENT_TYPE_CITY,
		"polity_id": polity_id,
		"world_region_top_left": Vector2i.ZERO,
		"world_region_center": Vector2i.ZERO,
		"world_region_size": 1,
		"simulation_backend_kind": (
			SettlementSimulationContext.BACKEND_CITY_SETTLEMENT_STATE
		),
	})
	var settlement_id := int(settlement.get("id", -1))
	var state = WorldPoliticalState.get_city_simulation_state(settlement_id)
	if not state is CitySettlementSimulationState:
		return {}
	return {"settlement_id": settlement_id, "state": state}


func _create_unfounded_city(
	city_name: String,
	polity_id: int,
	seed_value: int
) -> Dictionary:
	var fixture := _create_unprepared_city(city_name, polity_id)
	if fixture.is_empty():
		return {}
	var state: CitySettlementSimulationState = fixture["state"]
	state.city_world = _make_world(TEST_WORLD_SIZE, seed_value)
	state.city_seed = seed_value
	state.city_runtime_data = {
		"id": int(fixture["settlement_id"]),
		"name": city_name,
		"founded": false,
		"can_build": false,
	}
	return fixture


func _create_founded_city(
	city_name: String,
	polity_id: int,
	culture_id: int,
	seed_value: int,
	object_owner: String
) -> Dictionary:
	var fixture := _create_unfounded_city(city_name, polity_id, seed_value)
	if fixture.is_empty():
		return {}

	var state: CitySettlementSimulationState = fixture["state"]
	var keep := CityObjectSystem.register_completed_city_object_for_city_state(
		state,
		{
			"object_type": CityObjectCatalog.CITY_OBJECT_CITY_CENTER,
			"top_left": KEEP_TOP_LEFT,
			"size_tiles": CityObjectCatalog.get_city_object_size_for_type(
				CityObjectCatalog.CITY_OBJECT_CITY_CENTER
			),
			"object_owner": object_owner,
		}
	)
	if keep.is_empty():
		return {}

	state.city_runtime_data.merge({
		"primary_culture_id": culture_id,
		"city_world_seed": seed_value,
		"city_map_size": TEST_WORLD_SIZE,
		"foundation_top_left": keep.get("top_left", Vector2i(-1, -1)),
		"foundation_size": keep.get("size", Vector2i.ZERO),
		"foundation_object_id": int(keep.get("id", -1)),
		"foundation_object_owner": str(keep.get("owner", "")),
		"founded": true,
		"can_build": true,
	}, true)
	return fixture


func _make_world(size: Vector2i, seed_value: int) -> WorldData:
	var world := WorldData.new()
	world.setup(size.x, size.y, seed_value)
	for y in range(size.y):
		for x in range(size.x):
			world.tiles[y][x] = {
				"fertility": 50.0,
				"elevation": 10.0,
				"temperature": 50.0,
				"precipitation": 50.0,
				"terrain": WorldData.TERRAIN_LAND,
				"biome": WorldData.BIOME_PLAIN,
				"resource": WorldData.RESOURCE_NONE,
				"is_land": true,
			}
	world.mark_tile_data_changed()
	return world


func _seed_legacy_citizen(
	state: CitySettlementSimulationState,
	culture_id: int
) -> void:
	var citizen := CityCitizenRegistrySystem.add_city_citizen_for_city_state(
		state,
		"",
		Vector2i(2, 2),
		CityCitizens.CITY_CITIZEN_SEX_MALE,
		culture_id
	)
	if citizen.is_empty():
		return

	var citizen_id := int(citizen.get("id", -1))
	var citizen_index := (
		CityCitizenRegistrySystem.get_city_citizen_index_by_id_for_city_state(
			state,
			citizen_id
		)
	)
	if citizen_index < 0:
		return

	citizen["sex"] = ""
	citizen["name"] = "Legacy Citizen"
	citizen.erase("city_tile_position")
	citizen.erase("current_task")
	citizen.erase("movement_path")
	state.citizen_registry_state.citizens[citizen_index] = citizen
	state.citizen_registry_state.starting_population_initialized = true
	state.citizen_spatial_state.citizen_ids_by_tile.clear()


func _get_city_keeps(state: CitySettlementSimulationState) -> Array:
	var keeps: Array = []
	for raw_object in state.object_state.objects:
		if (
			raw_object is Dictionary
			and str(raw_object.get("type", ""))
			== CityObjectCatalog.CITY_OBJECT_CITY_CENTER
		):
			keeps.append(raw_object)
	return keeps


func _capture_state_snapshot(
	state: CitySettlementSimulationState
) -> Dictionary:
	return {
		"city_world_identity": state.city_world,
		"city_world_values": _capture_data_owner_values(state.city_world),
		"city_seed": state.city_seed,
		"city_runtime_data": state.city_runtime_data.duplicate(true),
		"object_state": _capture_data_owner_values(state.object_state),
		"resource_accounting_state": _capture_data_owner_values(
			state.resource_accounting_state
		),
		"citizen_registry_state": _capture_data_owner_values(
			state.citizen_registry_state
		),
		"assignment_state": _capture_data_owner_values(
			state.assignment_state
		),
		"workplace_state": _capture_data_owner_values(
			state.workplace_state
		),
		"citizen_spatial_state": _capture_data_owner_values(
			state.citizen_spatial_state
		),
		"citizen_movement_runtime_state": _capture_data_owner_values(
			state.citizen_movement_runtime_state
		),
		"citizen_task_runtime_state": _capture_data_owner_values(
			state.citizen_task_runtime_state
		),
		"citizen_decision_runtime_state": _capture_data_owner_values(
			state.citizen_decision_runtime_state
		),
		"work_state": _capture_data_owner_values(state.work_state),
		"logistics_state": _capture_data_owner_values(state.logistics_state),
		"construction_state": _capture_data_owner_values(
			state.construction_state
		),
		"navigation_state": _capture_data_owner_values(
			state.navigation_state
		),
	}


func _capture_data_owner_values(owner: Object) -> Dictionary:
	var snapshot: Dictionary = {}
	if owner == null:
		return snapshot

	for raw_property_info in owner.get_property_list():
		if not raw_property_info is Dictionary:
			continue

		var property_info: Dictionary = raw_property_info
		var usage := int(property_info.get("usage", 0))
		if (usage & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0:
			continue

		var property_name := str(property_info.get("name", ""))
		if property_name.is_empty():
			continue

		snapshot[property_name] = _copy_snapshot_value(owner.get(property_name))

	return snapshot


func _copy_snapshot_value(value):
	if value is Dictionary:
		return value.duplicate(true)
	if value is Array:
		return value.duplicate(true)
	if value is PackedByteArray:
		return value.slice(0)
	if value is PackedInt32Array:
		return value.slice(0)
	return value


func _capture_owner_identities(
	state: CitySettlementSimulationState
) -> Dictionary:
	return {
		"world": state.city_world,
		"object_state": state.object_state,
		"resource_state": state.resource_accounting_state,
		"registry_state": state.citizen_registry_state,
		"assignment_state": state.assignment_state,
		"workplace_state": state.workplace_state,
		"spatial_state": state.citizen_spatial_state,
		"movement_state": state.citizen_movement_runtime_state,
		"task_state": state.citizen_task_runtime_state,
		"decision_state": state.citizen_decision_runtime_state,
		"work_state": state.work_state,
		"logistics_state": state.logistics_state,
		"construction_state": state.construction_state,
		"navigation_state": state.navigation_state,
	}


func _owner_identities_match(
	state: CitySettlementSimulationState,
	identities: Dictionary
) -> bool:
	return (
		is_same(state.city_world, identities["world"])
		and is_same(state.object_state, identities["object_state"])
		and is_same(
			state.resource_accounting_state,
			identities["resource_state"]
		)
		and is_same(state.citizen_registry_state, identities["registry_state"])
		and is_same(state.assignment_state, identities["assignment_state"])
		and is_same(state.workplace_state, identities["workplace_state"])
		and is_same(state.citizen_spatial_state, identities["spatial_state"])
		and is_same(
			state.citizen_movement_runtime_state,
			identities["movement_state"]
		)
		and is_same(
			state.citizen_task_runtime_state,
			identities["task_state"]
		)
		and is_same(
			state.citizen_decision_runtime_state,
			identities["decision_state"]
		)
		and is_same(state.work_state, identities["work_state"])
		and is_same(state.logistics_state, identities["logistics_state"])
		and is_same(state.construction_state, identities["construction_state"])
		and is_same(state.navigation_state, identities["navigation_state"])
	)


func _all_runtime_owners_replaced(
	state: CitySettlementSimulationState,
	old_identities: Dictionary
) -> bool:
	return (
		not is_same(state.object_state, old_identities["object_state"])
		and not is_same(
			state.resource_accounting_state,
			old_identities["resource_state"]
		)
		and not is_same(
			state.citizen_registry_state,
			old_identities["registry_state"]
		)
		and not is_same(state.assignment_state, old_identities["assignment_state"])
		and not is_same(state.workplace_state, old_identities["workplace_state"])
		and not is_same(state.citizen_spatial_state, old_identities["spatial_state"])
		and not is_same(
			state.citizen_movement_runtime_state,
			old_identities["movement_state"]
		)
		and not is_same(
			state.citizen_task_runtime_state,
			old_identities["task_state"]
		)
		and not is_same(
			state.citizen_decision_runtime_state,
			old_identities["decision_state"]
		)
		and not is_same(state.work_state, old_identities["work_state"])
		and not is_same(state.logistics_state, old_identities["logistics_state"])
		and not is_same(
			state.construction_state,
			old_identities["construction_state"]
		)
		and not is_same(state.navigation_state, old_identities["navigation_state"])
	)


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	failure_count += 1
	push_error("City settlement runtime bootstrap test: " + message)
