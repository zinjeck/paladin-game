extends Node

const CityStateValidatorScript := preload(
	"res://scripts/city/simulation/CityStateValidator.gd"
)

var failure_count: int = 0


func _ready() -> void:
	_test_explicit_target_and_cache_isolation()
	CityStateValidatorScript.clear_all_validation_caches()
	WorldData.reset_runtime_session_state()

	if failure_count > 0:
		push_error(
			"City state validator explicit-context test failed: "
			+ str(failure_count)
		)
		get_tree().quit(1)
		return

	print("City state validator explicit-context test passed.")
	get_tree().quit(0)


func _test_explicit_target_and_cache_isolation() -> void:
	WorldData.reset_runtime_session_state()
	CityStateValidatorScript.clear_all_validation_caches()

	var culture := WorldData.create_culture(
		"Validator Explicit Context Culture"
	)
	var culture_id := int(culture.get("id", -1))
	var polity := WorldPoliticalState.create_polity({
		"name": "Validator Explicit Context Realm",
		"polity_type": PolityData.POLITY_TYPE_KINGDOM,
		"primary_culture_id": culture_id,
	})
	var polity_id := int(polity.get("id", -1))
	var city_a := _create_city("Validator City A", polity_id)
	var city_b := _create_city("Validator City B", polity_id)
	var city_a_id := int(city_a.get("id", -1))
	var city_b_id := int(city_b.get("id", -1))

	if culture_id <= 0 or city_a_id <= 0 or city_b_id <= 0:
		_expect(false, "The validator A/B fixture must be created.")
		return

	var state_a := _seed_city(
		city_a_id,
		culture_id,
		"Validator City A",
		131_001,
		"owner_a"
	)
	var state_b := _seed_city(
		city_b_id,
		culture_id,
		"Validator City B",
		131_002,
		"owner_b"
	)
	if state_a == null or state_b == null:
		_expect(false, "Both validator settlement states must be seeded.")
		return

	var context_a = WorldPoliticalState.get_settlement_context(city_a_id)
	var context_b = WorldPoliticalState.get_settlement_context(city_b_id)
	_expect(
		context_a != null and context_b != null,
		"Both explicit validation targets must expose registered contexts."
	)
	if context_a == null or context_b == null:
		return

	# Deliberately preserve matching local IDs and numeric versions. Only exact
	# target and owner identities may separate the two cache entries.
	_expect(
		int(state_a.object_state.objects[0].get("id", -1))
		== int(state_b.object_state.objects[0].get("id", -2))
		and int(state_a.citizen_registry_state.citizens[0].get("id", -1))
		== int(state_b.citizen_registry_state.citizens[0].get("id", -2))
		and state_a.object_state.object_version
		== state_b.object_state.object_version
		and state_a.citizen_registry_state.citizen_version
		== state_b.citizen_registry_state.citizen_version,
		"The validator fixture must overlap IDs and versions across settlements."
	)

	_expect(
		WorldPoliticalState.set_active_settlement(city_b_id),
		"Settlement B must remain globally selected while validating A."
	)
	var snapshot_a := _capture_state_snapshot(state_a)
	var snapshot_b := _capture_state_snapshot(state_b)
	var result_a := CityStateValidatorScript.validate_for_settlement(
		context_a,
		true,
		false
	)
	var result_b := CityStateValidatorScript.validate_for_settlement(
		context_b,
		true,
		false
	)
	_expect(
		bool(result_a.get("valid", false))
		and bool(result_b.get("valid", false))
		and int(result_a.get("settlement_id", -1)) == city_a_id
		and int(result_b.get("settlement_id", -1)) == city_b_id
		and int(result_a.get("city_state_instance_id", -1))
		== int(state_a.get_instance_id())
		and int(result_b.get("city_state_instance_id", -1))
		== int(state_b.get_instance_id())
		and WorldPoliticalState.active_settlement_id == city_b_id,
		"Explicit validation must inspect its supplied target without redirecting global selection."
	)
	_expect(
		_capture_state_snapshot(state_a) == snapshot_a
		and _capture_state_snapshot(state_b) == snapshot_b,
		"Validation must remain read-only for both the target and selected settlement."
	)
	var summary_a := (
		CityStateValidatorScript.get_summary_text_for_settlement(context_a)
	)
	_expect(
		("Settlement: " + str(city_a_id)) in summary_a
		and WorldPoliticalState.active_settlement_id == city_b_id,
		"Explicit summary text must identify A while presentation remains on B."
	)

	var cached_a := CityStateValidatorScript.validate_for_settlement(
		WorldPoliticalState.get_settlement_context(city_a_id),
		false,
		false
	)
	_expect(
		bool(cached_a.get("cache_hit", false))
		and int(cached_a.get("object_state_instance_id", -1))
		== int(state_a.object_state.get_instance_id()),
		"Repeated unchanged A validation must hit only A's identity-aware cache."
	)

	# Corrupt A without changing its numeric object version. The debug
	# fingerprint must invalidate A while B retains its valid cached result.
	state_a.object_state.object_index_by_id[99] = 0
	var corrupted_a := CityStateValidatorScript.validate_for_settlement(
		WorldPoliticalState.get_settlement_context(city_a_id),
		false,
		false
	)
	var untouched_b := CityStateValidatorScript.validate_for_settlement(
		WorldPoliticalState.get_settlement_context(city_b_id),
		false,
		false
	)
	_expect(
		not bool(corrupted_a.get("valid", true))
		and not bool(corrupted_a.get("cache_hit", true))
		and _contains_error(corrupted_a, "orphan object ID 99")
		and bool(untouched_b.get("valid", false))
		and bool(untouched_b.get("cache_hit", false))
		and int(untouched_b.get("object_state_instance_id", -1))
		== int(state_b.object_state.get_instance_id()),
		"A-only corruption must invalidate A and never poison B's equal-version cache."
	)
	state_a.object_state.object_index_by_id.erase(99)
	var repaired_a := CityStateValidatorScript.validate_for_settlement(
		WorldPoliticalState.get_settlement_context(city_a_id),
		false,
		false
	)
	_expect(
		bool(repaired_a.get("valid", false))
		and not bool(repaired_a.get("cache_hit", true)),
		"Repairing A must rebuild only A's cache entry."
	)

	state_b.object_state.object_index_by_id[77] = 0
	var corrupted_b := CityStateValidatorScript.validate_for_settlement(
		WorldPoliticalState.get_settlement_context(city_b_id),
		false,
		false
	)
	var still_valid_a := CityStateValidatorScript.validate_for_settlement(
		WorldPoliticalState.get_settlement_context(city_a_id),
		false,
		false
	)
	_expect(
		not bool(corrupted_b.get("valid", true))
		and _contains_error(corrupted_b, "orphan object ID 77")
		and bool(still_valid_a.get("valid", false))
		and bool(still_valid_a.get("cache_hit", false)),
		"B-only corruption must fail B while A retains its own valid cache."
	)
	state_b.object_state.object_index_by_id.erase(77)
	CityStateValidatorScript.validate_for_settlement(
		WorldPoliticalState.get_settlement_context(city_b_id),
		false,
		false
	)

	# Deliberately create a fresh aggregate owner, then register it under A's
	# existing settlement ID. The former context is now a required stale input.
	var replacement_a := CitySettlementSimulationState.new()
	WorldPoliticalState.settlement_city_state_by_id[city_a_id] = replacement_a
	_seed_existing_state(
		replacement_a,
		city_a_id,
		culture_id,
		"Validator City A Replacement",
		131_003,
		"owner_a_replacement"
	)
	var replacement_context_a = (
		WorldPoliticalState.get_settlement_context(city_a_id)
	)
	var stale_context_result := (
		CityStateValidatorScript.validate_for_settlement(
			context_a,
			false,
			false
		)
	)
	_expect(
		not bool(stale_context_result.get("valid", true))
		and _contains_error(
			stale_context_result,
			"registered city settlement context"
		),
		"A stale context must become invalid when its registered state is replaced."
	)
	var replacement_result := (
		CityStateValidatorScript.validate_for_settlement(
			replacement_context_a,
			false,
			false
		)
	)
	_expect(
		bool(replacement_result.get("valid", false))
		and not bool(replacement_result.get("cache_hit", true))
		and int(replacement_result.get("city_state_instance_id", -1))
		== int(replacement_a.get_instance_id())
		and int(replacement_result.get("city_state_instance_id", -1))
		!= int(state_a.get_instance_id()),
		"Replacing A under the same ID must invalidate every old owner reference."
	)

	# Force rebuilding A must not evict or rebuild B's independent cache entry.
	var cached_b_before_force := CityStateValidatorScript.validate_for_settlement(
		WorldPoliticalState.get_settlement_context(city_b_id),
		false,
		false
	)
	var forced_replacement_a := (
		CityStateValidatorScript.validate_for_settlement(
			replacement_context_a,
			true,
			false
		)
	)
	var cached_b_after_force := CityStateValidatorScript.validate_for_settlement(
		WorldPoliticalState.get_settlement_context(city_b_id),
		false,
		false
	)
	_expect(
		bool(cached_b_before_force.get("cache_hit", false))
		and not bool(forced_replacement_a.get("cache_hit", true))
		and bool(cached_b_after_force.get("cache_hit", false)),
		"Force rebuild must bypass only the explicitly targeted settlement cache."
	)

	CityStateValidatorScript.clear_all_validation_caches()
	var first_bounded_cache_id := SettlementData.INVALID_SETTLEMENT_ID
	for cache_index in range(
		CityStateValidatorScript.MAX_CACHED_SETTLEMENTS + 3
	):
		var cache_city := _create_city(
			"Validator Cache City " + str(cache_index + 1),
			polity_id
		)
		var cache_city_id := int(
			cache_city.get("id", SettlementData.INVALID_SETTLEMENT_ID)
		)
		var cache_context: SettlementSimulationContext = (
			WorldPoliticalState.get_settlement_context(cache_city_id)
		)
		if first_bounded_cache_id <= 0:
			first_bounded_cache_id = cache_city_id
		var cache_result := (
			CityStateValidatorScript.validate_for_settlement(
				cache_context,
				true,
				false
			)
		)
		_expect(
			cache_context != null
			and WorldPoliticalState.is_registered_settlement_context(
				cache_context
			)
			and bool(cache_result.get("valid", false)),
			"Every cache-bounds target must be a valid registered City."
		)
	_expect(
		CityStateValidatorScript._cache_by_settlement_id.size()
		== CityStateValidatorScript.MAX_CACHED_SETTLEMENTS
		and not CityStateValidatorScript._cache_by_settlement_id.has(
			first_bounded_cache_id
		),
		"Validator cache history must remain bounded and evict the least-recent target."
	)
	_expect(
		WorldPoliticalState.active_settlement_id == city_b_id,
		"Explicit validation and cache maintenance must never redirect presentation."
	)


func _create_city(city_name: String, polity_id: int) -> Dictionary:
	return WorldPoliticalState.create_settlement({
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


func _seed_city(
	settlement_id: int,
	culture_id: int,
	city_name: String,
	seed_value: int,
	object_owner: String
) -> CitySettlementSimulationState:
	var state = WorldPoliticalState.get_city_simulation_state(settlement_id)
	if not state is CitySettlementSimulationState:
		return null
	_seed_existing_state(
		state,
		settlement_id,
		culture_id,
		city_name,
		seed_value,
		object_owner
	)
	return state


func _seed_existing_state(
	state: CitySettlementSimulationState,
	settlement_id: int,
	culture_id: int,
	city_name: String,
	seed_value: int,
	object_owner: String
) -> void:
	state.city_world = _make_world(12, 12, seed_value)
	state.city_seed = seed_value
	state.city_runtime_data = {
		"id": settlement_id,
		"name": city_name,
		"primary_culture_id": culture_id,
		"founded": false,
		"can_build": false,
	}
	var city_object := (
		CityObjectSystem.register_completed_city_object_for_city_state(
			state,
			{
				"object_type": CityObjectCatalog.CITY_OBJECT_CITY_CENTER,
				"top_left": Vector2i(2, 2),
				"size_tiles": CityObjectCatalog.get_city_object_size_for_type(
					CityObjectCatalog.CITY_OBJECT_CITY_CENTER
				),
				"object_owner": object_owner,
			}
		)
	)
	var citizen := CityCitizenRegistrySystem.add_city_citizen_for_city_state(
		state,
		"",
		Vector2i(8, 8),
		CityCitizens.CITY_CITIZEN_SEX_FEMALE,
		culture_id
	)
	if not city_object.is_empty():
		state.city_runtime_data.merge({
			"city_world_seed": seed_value,
			"city_map_size": Vector2i(
				state.city_world.width,
				state.city_world.height
			),
			"foundation_top_left": city_object.get(
				"top_left",
				Vector2i(-1, -1)
			),
			"foundation_size": city_object.get("size", Vector2i.ZERO),
			"foundation_object_id": int(city_object.get("id", -1)),
			"foundation_object_owner": str(city_object.get("owner", "")),
			"founded": true,
			"can_build": true,
		}, true)
	_expect(
		not city_object.is_empty() and not citizen.is_empty(),
		"Every validator state fixture must create one object and citizen."
	)


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


func _capture_state_snapshot(
	state: CitySettlementSimulationState
) -> Dictionary:
	return {
		"runtime": state.city_runtime_data.duplicate(true),
		"objects": state.object_state.objects.duplicate(true),
		"object_index": state.object_state.object_index_by_id.duplicate(true),
		"occupied": state.object_state.occupied_tiles.duplicate(true),
		"citizens": state.citizen_registry_state.citizens.duplicate(true),
		"citizen_index": (
			state.citizen_registry_state.citizen_index_by_id.duplicate(true)
		),
		"spatial": state.citizen_spatial_state.citizen_ids_by_tile.duplicate(true),
		"object_version": state.object_state.object_version,
		"citizen_version": state.citizen_registry_state.citizen_version,
		"spatial_version": state.citizen_spatial_state.citizen_spatial_version,
		"assignment_version": state.assignment_state.assignment_version,
		"workplace_version": state.workplace_state.workplace_version,
		"container_version": state.resource_accounting_state.container_version,
		"public_storage_version": (
			state.resource_accounting_state.public_storage_version
		),
		"movement_version": (
			state.citizen_movement_runtime_state.citizen_movement_version
		),
		"task_version": state.citizen_task_runtime_state.citizen_task_version,
		"ground_pile_version": state.logistics_state.ground_pile_version,
		"construction_version": state.construction_state.construction_version,
	}


func _contains_error(result: Dictionary, fragment: String) -> bool:
	for raw_error in result.get("errors", []):
		if fragment in str(raw_error):
			return true
	return false


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	failure_count += 1
	push_error(message)
