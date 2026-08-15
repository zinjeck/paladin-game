extends Node

var failure_count: int = 0


func _ready() -> void:
	_test_explicit_target_migrations_and_idempotence()
	_test_missing_keep_recovery_is_target_local()
	_test_invalid_player_capital_is_reset_locally()
	_test_invalid_nonplayer_foundation_fails_without_mutation()
	_test_legacy_starting_population_is_created_once()
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


func _test_explicit_target_migrations_and_idempotence() -> void:
	var fixture := _make_two_city_fixture(121_001)
	if not _fixture_is_valid(fixture):
		return

	var state_a: CitySettlementSimulationState = fixture["state_a"]
	var state_b: CitySettlementSimulationState = fixture["state_b"]
	var city_a_id := int(fixture["city_a_id"])
	var city_b_id := int(fixture["city_b_id"])
	if (
		not _found_city(
			state_a,
			city_a_id,
			int(fixture["culture_a_id"]),
			Vector2i(4, 4),
			"player"
		)
		or not _found_city(
			state_b,
			city_b_id,
			int(fixture["culture_b_id"]),
			Vector2i(5, 5),
			"npc"
		)
	):
		_expect(false, "The explicit-target fixture must found both Cities.")
		return

	WorldPoliticalState.set_active_settlement(city_b_id)
	var citizen: Dictionary = state_a.citizen_registry_state.citizens[0]
	var citizen_id := int(citizen.get("id", -1))
	for field_name in [
		"sex",
		"city_tile_position",
		"carry_capacity",
		"inventory",
		"haul_cargo",
		"hunger",
		"hunger_decay_remainder",
		"happiness",
		"current_task",
		"movement_state",
		"movement_path",
		"movement_path_index",
		"movement_progress_basis_points",
		"movement_destination_tile",
		"movement_speed_basis_points_per_minute",
		"movement_repath_attempt_count",
		"movement_failure_reason",
	]:
		citizen.erase(field_name)
	citizen["name"] = "Invalid Legacy Name"
	citizen["home_object_id"] = 999_001
	citizen["job_object_id"] = 999_002
	state_a.citizen_registry_state.citizens[0] = citizen
	state_a.citizen_spatial_state.citizen_ids_by_tile.clear()

	var b_values_before := _capture_city_values(state_b)
	var b_identities_before := _capture_city_owner_identities(state_b)
	var context_a = WorldPoliticalState.get_settlement_context(city_a_id)
	var result := CitySettlementRuntimeBootstrap.ensure_ready(context_a)

	_expect(
		bool(result.get("success", false))
		and int(result.get("settlement_id", -1)) == city_a_id
		and int(result.get("state_instance_id", 0))
		== state_a.get_instance_id(),
		"Bootstrap must report success and the exact explicit target identity."
	)
	_expect(
		WorldPoliticalState.active_settlement_id == city_b_id,
		"Bootstrapping A must not switch presentation away from B."
	)
	_expect(
		_city_matches_capture(state_b, b_values_before, b_identities_before),
		"Bootstrapping A must leave every City B owner and value unchanged."
	)

	var changed_domains: Dictionary = result.get("changed_domains", {})
	for required_domain in [
		"citizen_spatial",
		"citizen_demographics",
		"citizen_inventory",
		"citizen_needs",
		"citizen_tasks",
		"citizen_movement",
		"citizen_assignments",
	]:
		_expect(
			changed_domains.has(required_domain),
			"Bootstrap must report the " + required_domain + " repair."
		)

	var repaired: Dictionary = state_a.citizen_registry_state.citizens[0]
	var repaired_position = repaired.get("city_tile_position")
	var spatial_ids = state_a.citizen_spatial_state.citizen_ids_by_tile.get(
		repaired_position,
		[]
	)
	_expect(
		CityCitizens.is_valid_city_citizen_sex(
			str(repaired.get("sex", ""))
		)
		and not str(repaired.get("name", "")).strip_edges().is_empty()
		and repaired_position is Vector2i
		and spatial_ids is Array
		and spatial_ids.has(citizen_id)
		and CityCitizens.has_complete_city_citizen_haul_cargo_state(repaired)
		and CityCitizens.has_complete_city_citizen_need_state(repaired)
		and CityCitizens.has_complete_city_citizen_task_state(repaired)
		and CityCitizens.has_complete_city_citizen_movement_state(repaired)
		and int(repaired.get("home_object_id", 0)) == -1
		and int(repaired.get("job_object_id", 0)) == -1,
		"Explicit migrations must repair A's complete citizen-local runtime in place."
	)

	var a_values_after := _capture_city_values(state_a)
	var a_identities_after := _capture_city_owner_identities(state_a)
	var second_result := CitySettlementRuntimeBootstrap.ensure_ready(context_a)
	_expect(
		bool(second_result.get("success", false))
		and int(second_result.get("changed_count", -1)) == 0
		and (second_result.get("changed_domains", {}) as Dictionary).is_empty()
		and _city_matches_capture(
			state_a,
			a_values_after,
			a_identities_after
		),
		"A second bootstrap must be an exact idempotent no-op."
	)


func _test_missing_keep_recovery_is_target_local() -> void:
	var fixture := _make_two_city_fixture(122_001)
	if not _fixture_is_valid(fixture):
		return

	var state_a: CitySettlementSimulationState = fixture["state_a"]
	var state_b: CitySettlementSimulationState = fixture["state_b"]
	var city_a_id := int(fixture["city_a_id"])
	var city_b_id := int(fixture["city_b_id"])
	if (
		not _found_city(
			state_a,
			city_a_id,
			int(fixture["culture_a_id"]),
			Vector2i(4, 4),
			"player"
		)
		or not _found_city(
			state_b,
			city_b_id,
			int(fixture["culture_b_id"]),
			Vector2i(5, 5),
			"npc"
		)
	):
		_expect(false, "The Keep-recovery fixture must found both Cities.")
		return

	state_a.object_state.objects.clear()
	state_a.object_state.object_index_by_id.clear()
	state_a.object_state.occupied_tiles.clear()
	WorldPoliticalState.set_active_settlement(city_b_id)

	var b_values_before := _capture_city_values(state_b)
	var b_identities_before := _capture_city_owner_identities(state_b)
	var context_a = WorldPoliticalState.get_settlement_context(city_a_id)
	var result := CitySettlementRuntimeBootstrap.ensure_ready(context_a)
	var keeps := _get_city_keeps(state_a)
	var foundation_object_id := int(
		state_a.city_runtime_data.get("foundation_object_id", -1)
	)

	_expect(
		bool(result.get("success", false))
		and int(
			(result.get("changed_domains", {}) as Dictionary).get(
				"foundation_keep",
				0
			)
		) == 1
		and keeps.size() == 1
		and int(keeps[0].get("id", -1)) == foundation_object_id,
		"A missing target-local Keep must be recovered exactly once."
	)
	_expect(
		WorldPoliticalState.active_settlement_id == city_b_id
		and _city_matches_capture(
			state_b,
			b_values_before,
			b_identities_before
		),
		"Recovering A's Keep must not switch or mutate B."
	)

	var second_result := CitySettlementRuntimeBootstrap.ensure_ready(context_a)
	_expect(
		bool(second_result.get("success", false))
		and _get_city_keeps(state_a).size() == 1
		and int(second_result.get("changed_count", -1)) == 0,
		"Retrying Keep recovery must never duplicate the foundation object."
	)


func _test_invalid_player_capital_is_reset_locally() -> void:
	var fixture := _make_two_city_fixture(123_001)
	if not _fixture_is_valid(fixture):
		return

	var state_a: CitySettlementSimulationState = fixture["state_a"]
	var state_b: CitySettlementSimulationState = fixture["state_b"]
	var city_a_id := int(fixture["city_a_id"])
	var city_b_id := int(fixture["city_b_id"])
	if (
		not _found_city(
			state_a,
			city_a_id,
			int(fixture["culture_a_id"]),
			Vector2i(4, 4),
			"player"
		)
		or not _found_city(
			state_b,
			city_b_id,
			int(fixture["culture_b_id"]),
			Vector2i(5, 5),
			"npc"
		)
	):
		_expect(false, "The targeted-reset fixture must found both Cities.")
		return

	var state_a_instance_id := state_a.get_instance_id()
	var world_a = state_a.city_world
	var seed_a := state_a.city_seed
	var a_owner_ids_before := _capture_city_owner_identities(state_a)
	var b_values_before := _capture_city_values(state_b)
	var b_identities_before := _capture_city_owner_identities(state_b)
	state_a.city_runtime_data["foundation_top_left"] = Vector2i(-1, -1)
	state_a.city_runtime_data["foundation_size"] = Vector2i.ZERO
	WorldData.player_city_founded = true
	WorldData.player_city_foundation_top_left = Vector2i(9, 9)
	WorldData.player_city_foundation_size = Vector2i.ONE
	WorldPoliticalState.set_active_settlement(city_b_id)

	var context_a = WorldPoliticalState.get_settlement_context(city_a_id)
	var result := CitySettlementRuntimeBootstrap.ensure_ready(context_a)
	var reset_domains: Dictionary = result.get("changed_domains", {})

	_expect(
		bool(result.get("success", false))
		and int(reset_domains.get("legacy_foundation_reset", 0)) == 1
		and state_a.get_instance_id() == state_a_instance_id
		and is_same(state_a.city_world, world_a)
		and state_a.city_seed == seed_a
		and state_a.city_runtime_data.is_empty()
		and state_a.object_state.objects.is_empty()
		and state_a.citizen_registry_state.citizens.is_empty()
		and not _city_owner_identities_equal(
			_capture_city_owner_identities(state_a),
			a_owner_ids_before
		),
		"Invalid player-capital foundation state must reset only A's local runtime owners."
	)
	_expect(
		WorldPoliticalState.active_settlement_id == city_b_id
		and _city_matches_capture(
			state_b,
			b_values_before,
			b_identities_before
		)
		and not WorldData.player_city_founded
		and WorldData.player_city_foundation_top_left == Vector2i(-1, -1)
		and WorldData.player_city_foundation_size == Vector2i.ZERO,
		"Targeted player-capital repair must leave B exact and clear only capital mirrors."
	)

	var values_after := _capture_city_values(state_a)
	var identities_after := _capture_city_owner_identities(state_a)
	var second_result := CitySettlementRuntimeBootstrap.ensure_ready(context_a)
	_expect(
		bool(second_result.get("success", false))
		and int(second_result.get("changed_count", -1)) == 0
		and _city_matches_capture(
			state_a,
			values_after,
			identities_after
		),
		"The locally reset player capital must remain retryable and idempotent."
	)


func _test_invalid_nonplayer_foundation_fails_without_mutation() -> void:
	var fixture := _make_two_city_fixture(124_001)
	if not _fixture_is_valid(fixture):
		return

	var state_a: CitySettlementSimulationState = fixture["state_a"]
	var state_b: CitySettlementSimulationState = fixture["state_b"]
	var city_a_id := int(fixture["city_a_id"])
	var city_b_id := int(fixture["city_b_id"])
	if (
		not _found_city(
			state_a,
			city_a_id,
			int(fixture["culture_a_id"]),
			Vector2i(4, 4),
			"player"
		)
		or not _found_city(
			state_b,
			city_b_id,
			int(fixture["culture_b_id"]),
			Vector2i(5, 5),
			"npc"
		)
	):
		_expect(false, "The controlled-failure fixture must found both Cities.")
		return

	var valid_runtime := state_b.city_runtime_data.duplicate(true)
	state_b.city_runtime_data["foundation_top_left"] = Vector2i(-1, -1)
	state_b.city_runtime_data["foundation_size"] = Vector2i.ZERO
	WorldData.player_city_founded = true
	WorldData.player_city_foundation_top_left = Vector2i(7, 7)
	WorldData.player_city_foundation_size = Vector2i(2, 2)
	WorldPoliticalState.set_active_settlement(city_a_id)

	var a_values_before := _capture_city_values(state_a)
	var a_identities_before := _capture_city_owner_identities(state_a)
	var b_values_before := _capture_city_values(state_b)
	var b_identities_before := _capture_city_owner_identities(state_b)
	var context_b = WorldPoliticalState.get_settlement_context(city_b_id)
	var failed_result := CitySettlementRuntimeBootstrap.ensure_ready(context_b)

	_expect(
		not bool(failed_result.get("success", true))
		and str(failed_result.get("failure_code", ""))
		== CitySettlementRuntimeBootstrap.FAILURE_INVALID_FOUNDATION_FOOTPRINT
		and _city_matches_capture(
			state_a,
			a_values_before,
			a_identities_before
		)
		and _city_matches_capture(
			state_b,
			b_values_before,
			b_identities_before
		),
		"Invalid NPC foundation state must fail without mutating either settlement."
	)
	_expect(
		WorldData.player_city_founded
		and WorldData.player_city_foundation_top_left == Vector2i(7, 7)
		and WorldData.player_city_foundation_size == Vector2i(2, 2),
		"Non-player bootstrap must not synchronize player-capital mirrors."
	)

	state_b.city_runtime_data.clear()
	state_b.city_runtime_data.merge(valid_runtime, true)
	var retry_result := CitySettlementRuntimeBootstrap.ensure_ready(context_b)
	_expect(
		bool(retry_result.get("success", false))
		and WorldPoliticalState.active_settlement_id == city_a_id
		and WorldData.player_city_founded
		and WorldData.player_city_foundation_top_left == Vector2i(7, 7),
		"Repairing the explicit NPC target must make the same caller retry successfully."
	)


func _test_legacy_starting_population_is_created_once() -> void:
	var fixture := _make_two_city_fixture(125_001)
	if not _fixture_is_valid(fixture):
		return

	var state_a: CitySettlementSimulationState = fixture["state_a"]
	var state_b: CitySettlementSimulationState = fixture["state_b"]
	var city_a_id := int(fixture["city_a_id"])
	var city_b_id := int(fixture["city_b_id"])
	if not _found_city(
		state_b,
		city_b_id,
		int(fixture["culture_b_id"]),
		Vector2i(5, 5),
		"npc"
	):
		_expect(false, "The legacy-population fixture must found City B.")
		return

	var keep := _register_keep(state_a, Vector2i(4, 4), "player")
	if keep.is_empty():
		_expect(false, "The legacy-population fixture must register A's Keep.")
		return

	state_a.city_runtime_data = {
		"id": city_a_id,
		"name": "Bootstrap City A",
		"primary_culture_id": int(fixture["culture_a_id"]),
		"city_world_seed": state_a.city_seed,
		"city_map_size": Vector2i(
			state_a.city_world.width,
			state_a.city_world.height
		),
		"foundation_top_left": keep.get("top_left"),
		"foundation_size": keep.get("size"),
		"foundation_object_id": int(keep.get("id", -1)),
		"foundation_object_owner": str(keep.get("owner", "")),
		"founded": true,
		"can_build": true,
	}
	WorldPoliticalState.set_active_settlement(city_b_id)
	var b_values_before := _capture_city_values(state_b)
	var b_identities_before := _capture_city_owner_identities(state_b)
	var context_a = WorldPoliticalState.get_settlement_context(city_a_id)
	var first_result := CitySettlementRuntimeBootstrap.ensure_ready(context_a)

	_expect(
		bool(first_result.get("success", false))
		and int(
			(first_result.get("changed_domains", {}) as Dictionary).get(
				"starting_population",
				0
			)
		== CityCitizenRegistrySystem.STARTING_CITY_POPULATION
		and state_a.citizen_registry_state.starting_population_initialized
		and state_a.citizen_registry_state.citizens.size()
		== CityCitizenRegistrySystem.STARTING_CITY_POPULATION,
		"Headless bootstrap must create the valid legacy starting population once."
	)
	_expect(
		WorldPoliticalState.active_settlement_id == city_b_id
		and _city_matches_capture(
			state_b,
			b_values_before,
			b_identities_before
		),
		"Headless starting-population bootstrap must leave selected City B exact."
	)

	var citizen_snapshot := (
		state_a.citizen_registry_state.citizens.duplicate(true)
	)
	var second_result := CitySettlementRuntimeBootstrap.ensure_ready(context_a)
	_expect(
		bool(second_result.get("success", false))
		and int(second_result.get("changed_count", -1)) == 0
		and state_a.citizen_registry_state.citizens == citizen_snapshot
		and state_a.citizen_registry_state.citizens.size()
		== CityCitizenRegistrySystem.STARTING_CITY_POPULATION,
		"Retrying headless bootstrap must never duplicate starting citizens."
	)


func _make_two_city_fixture(seed_base: int) -> Dictionary:
	WorldData.reset_runtime_session_state()
	var culture_a := WorldData.create_culture("Bootstrap Culture A")
	var culture_b := WorldData.create_culture("Bootstrap Culture B")
	var culture_a_id := int(culture_a.get("id", -1))
	var culture_b_id := int(culture_b.get("id", -1))
	var polity_a := _create_polity("Bootstrap Realm A", culture_a_id)
	var polity_b := _create_polity("Bootstrap Realm B", culture_b_id)
	var polity_a_id := int(polity_a.get("id", -1))
	var polity_b_id := int(polity_b.get("id", -1))
	var city_a := _create_city(
		"Bootstrap City A",
		polity_a_id,
		Vector2i(1, 1)
	)
	var city_b := _create_city(
		"Bootstrap City B",
		polity_b_id,
		Vector2i(2, 2)
	)
	var city_a_id := int(city_a.get("id", -1))
	var city_b_id := int(city_b.get("id", -1))

	if (
		culture_a_id <= 0
		or culture_b_id <= 0
		or polity_a_id <= 0
		or polity_b_id <= 0
		or city_a_id <= 0
		or city_b_id <= 0
	):
		_expect(false, "The two-City bootstrap fixture must create valid IDs.")
		return {}

	WorldPoliticalState.set_polity_capital(polity_a_id, city_a_id)
	WorldPoliticalState.set_polity_capital(polity_b_id, city_b_id)
	WorldPoliticalState.player_polity_id = polity_a_id
	var state_a = WorldPoliticalState.get_city_simulation_state(city_a_id)
	var state_b = WorldPoliticalState.get_city_simulation_state(city_b_id)
	if (
		not state_a is CitySettlementSimulationState
		or not state_b is CitySettlementSimulationState
	):
		_expect(false, "Both bootstrap Cities must own simulation state.")
		return {}

	state_a.city_world = _make_world(24, 24, seed_base)
	state_b.city_world = _make_world(24, 24, seed_base + 1)
	state_a.city_seed = seed_base
	state_b.city_seed = seed_base + 1
	WorldPoliticalState.set_active_settlement(city_b_id)

	return {
		"culture_a_id": culture_a_id,
		"culture_b_id": culture_b_id,
		"polity_a_id": polity_a_id,
		"polity_b_id": polity_b_id,
		"city_a_id": city_a_id,
		"city_b_id": city_b_id,
		"state_a": state_a,
		"state_b": state_b,
	}


func _fixture_is_valid(fixture: Dictionary) -> bool:
	if not fixture.is_empty():
		return true
	_expect(false, "Bootstrap fixture construction failed.")
	return false


func _found_city(
	city_state: CitySettlementSimulationState,
	settlement_id: int,
	culture_id: int,
	top_left: Vector2i,
	owner: String
) -> bool:
	var keep := _register_keep(city_state, top_left, owner)
	if keep.is_empty():
		return false

	return WorldPoliticalState.found_city_settlement(
		settlement_id,
		{
			"city_world_seed": city_state.city_seed,
			"city_map_size": Vector2i(
				city_state.city_world.width,
				city_state.city_world.height
			),
			"foundation_top_left": keep.get(
				"top_left",
				Vector2i(-1, -1)
			),
			"foundation_size": keep.get("size", Vector2i.ZERO),
			"primary_culture_id": culture_id,
			"can_build": true,
		}
	)


func _register_keep(
	city_state: CitySettlementSimulationState,
	top_left: Vector2i,
	owner: String
) -> Dictionary:
	return CityObjectSystem.register_completed_city_object_for_city_state(
		city_state,
		{
			"object_type": CityObjectCatalog.CITY_OBJECT_CITY_CENTER,
			"top_left": top_left,
			"size_tiles": CityObjectCatalog.get_city_object_size_for_type(
				CityObjectCatalog.CITY_OBJECT_CITY_CENTER
			),
			"object_owner": owner,
			"city_world": city_state.city_world,
		}
	)


func _get_city_keeps(
	city_state: CitySettlementSimulationState
) -> Array[Dictionary]:
	var keeps: Array[Dictionary] = []
	for raw_city_object in city_state.object_state.objects:
		if (
			raw_city_object is Dictionary
			and str(raw_city_object.get("type", ""))
			== CityObjectCatalog.CITY_OBJECT_CITY_CENTER
		):
			keeps.append(raw_city_object)
	return keeps


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


func _capture_city_owner_identities(
	city_state: CitySettlementSimulationState
) -> Dictionary:
	var identities := {
		"city_state": city_state.get_instance_id(),
		"city_world": city_state.city_world.get_instance_id(),
	}
	for owner_name in _get_city_owner_map(city_state):
		var owner: Object = _get_city_owner_map(city_state)[owner_name]
		identities[owner_name] = owner.get_instance_id()
	return identities


func _capture_city_values(
	city_state: CitySettlementSimulationState
) -> Dictionary:
	var city_world: WorldData = city_state.city_world
	var values := {
		"city_seed": city_state.city_seed,
		"city_runtime_data": _snapshot_variant(city_state.city_runtime_data),
		"city_world": {
			"width": city_world.width,
			"height": city_world.height,
			"seed": city_world.seed,
			"tile_data_version": city_world.tile_data_version,
			"city_surface_feature_change_version": (
				city_world.city_surface_feature_change_version
			),
			"tiles": _snapshot_variant(city_world.tiles),
			"pending_city_surface_feature_changes": _snapshot_variant(
				city_world.pending_city_surface_feature_changes
			),
		},
	}
	var owner_map := _get_city_owner_map(city_state)
	for owner_name in owner_map:
		values[owner_name] = _capture_script_state(owner_map[owner_name])
	return values


func _get_city_owner_map(
	city_state: CitySettlementSimulationState
) -> Dictionary:
	return {
		"object_state": city_state.object_state,
		"resource_accounting_state": city_state.resource_accounting_state,
		"citizen_registry_state": city_state.citizen_registry_state,
		"assignment_state": city_state.assignment_state,
		"workplace_state": city_state.workplace_state,
		"citizen_spatial_state": city_state.citizen_spatial_state,
		"citizen_movement_runtime_state": (
			city_state.citizen_movement_runtime_state
		),
		"citizen_task_runtime_state": city_state.citizen_task_runtime_state,
		"citizen_decision_runtime_state": (
			city_state.citizen_decision_runtime_state
		),
		"work_state": city_state.work_state,
		"logistics_state": city_state.logistics_state,
		"construction_state": city_state.construction_state,
		"navigation_state": city_state.navigation_state,
	}


func _capture_script_state(owner: Object) -> Dictionary:
	var values: Dictionary = {}
	for property in owner.get_property_list():
		var usage := int(property.get("usage", 0))
		if (usage & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0:
			continue
		var property_name = property.get("name")
		values[property_name] = _snapshot_variant(owner.get(property_name))
	return values


func _snapshot_variant(value):
	if value is Dictionary:
		var dictionary_snapshot: Dictionary = {}
		for key in value:
			dictionary_snapshot[_snapshot_variant(key)] = _snapshot_variant(
				value[key]
			)
		return dictionary_snapshot
	if value is Array:
		var array_snapshot: Array = []
		for item in value:
			array_snapshot.append(_snapshot_variant(item))
		return array_snapshot
	if value is PackedByteArray:
		return value.duplicate()
	if value is PackedInt32Array:
		return value.duplicate()
	if value is Object:
		return {"instance_id": value.get_instance_id()}
	return value


func _city_matches_capture(
	city_state: CitySettlementSimulationState,
	values: Dictionary,
	identities: Dictionary
) -> bool:
	return (
		_capture_city_values(city_state) == values
		and _city_owner_identities_equal(
			_capture_city_owner_identities(city_state),
			identities
		)
	)


func _city_owner_identities_equal(
	left: Dictionary,
	right: Dictionary
) -> bool:
	return left == right


func _expect(condition: bool, message: String) -> void:
	if condition:
		return

	failure_count += 1
	push_error("City settlement runtime bootstrap test: " + message)
