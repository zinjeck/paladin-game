extends Node

const CitySettlementTestFixtureScript = preload(
	"res://scripts/city/simulation/test_support/CitySettlementTestFixture.gd"
)
var failure_count: int = 0


func _ready() -> void:
	_test_add_rebuild_remove_and_reset_integrity()
	WorldData.reset_runtime_session_state()

	if failure_count > 0:
		push_error(
			"City citizen-registry regression test failed: "
			+ str(failure_count)
		)
		get_tree().quit(1)
		return

	print("City citizen-registry regression test passed.")
	get_tree().quit(0)


func _test_add_rebuild_remove_and_reset_integrity() -> void:
	var fixture = CitySettlementTestFixtureScript.create({
		"label": "Citizen Registry Integrity",
	})
	_expect(fixture != null, "The registry fixture must be created.")
	if fixture == null:
		return
	var city_state: CitySettlementSimulationState = fixture.city_state
	var culture_id: int = fixture.culture_id
	var state := city_state.citizen_registry_state
	var registry_array: Array = state.citizens
	var registry_index: Dictionary = state.citizen_index_by_id

	var first := _add_citizen(city_state, culture_id)
	var second := _add_citizen(city_state, culture_id)
	var third := _add_citizen(city_state, culture_id)
	_expect(
		int(first.get("id", -1)) == 1
		and int(second.get("id", -1)) == 2
		and int(third.get("id", -1)) == 3
		and registry_array.size() == 3
		and int(registry_index.get(1, -1)) == 0
		and int(registry_index.get(2, -1)) == 1
		and int(registry_index.get(3, -1)) == 2
		and state.next_citizen_id == 4
		and state.citizen_version == 3,
		"Successful adds must allocate monotonic IDs and exact indexes."
	)
	if registry_array.size() < 3:
		return
	_expect(
		is_same(city_state.citizen_registry_state.citizens, registry_array)
		and is_same(
			city_state.citizen_registry_state.citizen_index_by_id,
			registry_index
		),
		"The City state must expose the authoritative registry references."
	)

	# There is no production single-citizen removal API yet. This test-only
	# mutation proves that the existing index rebuild selects and repairs the
	# explicitly supplied owner without introducing cross-domain cleanup behavior.
	registry_array.remove_at(1)
	CityCitizenRegistrySystem.rebuild_city_citizen_index_for_city_state(
		city_state
	)
	state.citizen_version += 1
	_expect(
		registry_array.size() == 2
		and int(registry_array[0].get("id", -1)) == 1
		and int(registry_array[1].get("id", -1)) == 3
		and not registry_index.has(2)
		and int(registry_index.get(1, -1)) == 0
		and int(registry_index.get(3, -1)) == 1
		and CityCitizenRegistrySystem.get_city_citizen_index_by_id_for_city_state(
			city_state,
			2
		) == -1
		and CityCitizenRegistrySystem.get_city_citizen_by_id_for_city_state(
			city_state,
			2
		).is_empty()
		and state.next_citizen_id == 4
		and state.citizen_version == 4,
		"Rebuild must remap survivors without reusing the removed local ID."
	)

	var fourth := _add_citizen(city_state, culture_id)
	_expect(
		int(fourth.get("id", -1)) == 4
		and int(registry_index.get(4, -1)) == 2
		and state.next_citizen_id == 5
		and state.citizen_version == 5,
		"The next add after removal must preserve monotonic ID allocation."
	)

	CityCitizenRegistrySystem.reset_city_citizen_state_for_city_state(city_state)
	_expect(
		is_same(city_state.citizen_registry_state, state)
		and is_same(city_state.citizen_registry_state.citizens, registry_array)
		and is_same(
			city_state.citizen_registry_state.citizen_index_by_id,
			registry_index
		)
		and registry_array.is_empty()
		and registry_index.is_empty()
		and state.next_citizen_id == 1
		and state.citizen_version == 6,
		"Registry reset must clear in place and publish one core change."
	)

	var reused_first := _add_citizen(city_state, culture_id)
	_expect(
		int(reused_first.get("id", -1)) == 1
		and int(registry_index.get(1, -1)) == 0
		and state.next_citizen_id == 2
		and state.citizen_version == 7,
		"A cleared registry must restart its settlement-local ID sequence."
	)

	fixture.cleanup()
	var fresh_fixture = CitySettlementTestFixtureScript.create({
		"label": "Citizen Registry Integrity Fresh",
	})
	_expect(fresh_fixture != null, "The fresh registry fixture must be created.")
	if fresh_fixture == null:
		return
	var fresh_state: CityCitizenRegistryState = (
		fresh_fixture.city_state.citizen_registry_state
	)
	_expect(
		not is_same(fresh_state, state)
		and fresh_state.citizens.is_empty()
		and fresh_state.citizen_index_by_id.is_empty()
		and fresh_state.next_citizen_id == 1
		and fresh_state.citizen_version == 0,
		"A global session reset must replace the registry with clean defaults."
	)
	fresh_fixture.cleanup()


func _add_citizen(
	city_state: CitySettlementSimulationState,
	culture_id: int
) -> Dictionary:
	return CityCitizenRegistrySystem.add_city_citizen_for_city_state(
		city_state,
		"",
		CityCitizens.INVALID_CITY_TILE_POSITION,
		CityCitizens.CITY_CITIZEN_SEX_MALE,
		culture_id
	)


func _expect(condition: bool, message: String) -> void:
	if condition:
		return

	failure_count += 1
	push_error("City citizen-registry regression test: " + message)
