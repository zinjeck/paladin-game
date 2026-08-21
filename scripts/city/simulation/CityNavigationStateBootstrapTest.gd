extends Node

const CitySettlementTestFixtureScript = preload(
	"res://scripts/city/simulation/test_support/CitySettlementTestFixture.gd"
)

var failure_count: int = 0


func _ready() -> void:
	_test_state_defaults()
	_test_registered_context_owns_navigation_state()
	WorldData.reset_runtime_session_state()

	if failure_count > 0:
		push_error(
			"City navigation state bootstrap test failed: "
			+ str(failure_count)
		)
		get_tree().quit(1)
		return

	print("City navigation state bootstrap test passed.")
	get_tree().quit(0)


func _test_state_defaults() -> void:
	var state_a := CityNavigationState.new()
	var state_b := CityNavigationState.new()
	_expect(
		state_a.object_access_tile_cache.is_empty(),
		"A new navigation owner must start with an empty access cache."
	)
	_expect(
		not is_same(state_a, state_b)
		and not is_same(
			state_a.object_access_tile_cache,
			state_b.object_access_tile_cache
		),
		"Separate navigation owners must never share cache dictionaries."
	)


func _test_registered_context_owns_navigation_state() -> void:
	var fixture = CitySettlementTestFixtureScript.create({
		"label": "Navigation Bootstrap",
	})
	_expect(fixture != null, "Fixture must register an explicit City context.")
	if fixture == null:
		return

	var city_state: CitySettlementSimulationState = fixture.city_state
	var navigation_state: CityNavigationState = city_state.navigation_state
	navigation_state.object_access_tile_cache[77] = {
		"world_instance_id": 123,
		"access_tiles": [Vector2i(1, 2)],
	}

	_expect(
		fixture.is_registered()
		and is_same(
			CityNavigationSystem.get_state_for_city_state(city_state),
			navigation_state
		)
		and navigation_state.object_access_tile_cache.has(77),
		"Explicit navigation access must retain the registered cache owner."
	)

	var rebound_context = WorldPoliticalState.get_settlement_context(
		fixture.settlement_id
	)
	_expect(
		rebound_context != null
		and WorldPoliticalState.is_registered_settlement_context(
			rebound_context
		)
		and is_same(rebound_context.get_city_simulation_state(), city_state)
		and is_same(
			CityNavigationSystem.get_state_for_city_state(city_state),
			navigation_state
		),
		"Settlement lookup must preserve the exact registered navigation owner."
	)

	var stale_context: SettlementSimulationContext = fixture.settlement_context
	var settlement_id: int = fixture.settlement_id
	fixture.cleanup()
	_expect(
		not WorldPoliticalState.is_registered_settlement_context(stale_context)
		and WorldPoliticalState.get_city_simulation_state(settlement_id) == null,
		"Registry reset must invalidate every navigation fixture binding."
	)


func _expect(condition: bool, message: String) -> void:
	if condition:
		return

	failure_count += 1
	push_error("City navigation state bootstrap test: " + message)
