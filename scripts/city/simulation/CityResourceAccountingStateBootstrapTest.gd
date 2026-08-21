extends Node

const CitySettlementTestFixtureScript = preload(
	"res://scripts/city/simulation/test_support/CitySettlementTestFixture.gd"
)

var failure_count: int = 0


func _ready() -> void:
	_test_state_defaults()
	_test_registered_context_owns_accounting_state()
	WorldData.reset_runtime_session_state()

	if failure_count > 0:
		push_error(
			"City resource-accounting bootstrap test failed: "
			+ str(failure_count)
		)
		get_tree().quit(1)
		return

	print("City resource-accounting bootstrap test passed.")
	get_tree().quit(0)


func _test_state_defaults() -> void:
	var state := CityResourceAccountingState.new()
	_expect(
		state.owned_resource_amount_cache.is_empty()
		and state.owned_resource_amount_cache_container_version == -1
		and state.container_version == 0
		and state.public_storage_version == 0,
		"A new accounting state must have clean cache and version defaults."
	)


func _test_registered_context_owns_accounting_state() -> void:
	var fixture = CitySettlementTestFixtureScript.create({
		"label": "Resource Bootstrap",
	})
	_expect(fixture != null, "Fixture must register an explicit City context.")
	if fixture == null:
		return

	var bootstrap_cache: Dictionary = {
		WorldData.RESOURCE_FISH: 12,
		WorldData.RESOURCE_LUMBER: 4,
	}
	var city_state: CitySettlementSimulationState = fixture.city_state
	var accounting_state: CityResourceAccountingState = (
		city_state.resource_accounting_state
	)
	accounting_state.owned_resource_amount_cache = bootstrap_cache
	accounting_state.owned_resource_amount_cache_container_version = 7
	accounting_state.container_version = 7
	accounting_state.public_storage_version = 5
	_expect(
		fixture.is_registered()
		and is_same(
			accounting_state.owned_resource_amount_cache,
			bootstrap_cache
		)
		and is_same(
			CityResourceAccountingSystem.get_state_for_city_state(city_state),
			accounting_state
		),
		"Explicit accounting access must retain the registered cache owner."
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
			rebound_context.get_city_resource_accounting_state(),
			accounting_state
		)
		and is_same(
			accounting_state.owned_resource_amount_cache,
			bootstrap_cache
		),
		"Settlement lookup must preserve the exact registered accounting owner."
	)
	_expect(
		accounting_state.owned_resource_amount_cache_container_version == 7
		and accounting_state.container_version == 7
		and accounting_state.public_storage_version == 5,
		"Accounting versions must remain on the explicit settlement owner."
	)

	var stale_context: SettlementSimulationContext = fixture.settlement_context
	var settlement_id: int = fixture.settlement_id
	fixture.cleanup()
	_expect(
		not WorldPoliticalState.is_registered_settlement_context(stale_context)
		and WorldPoliticalState.get_city_simulation_state(settlement_id) == null,
		"Registry reset must invalidate every accounting fixture binding."
	)


func _expect(condition: bool, message: String) -> void:
	if condition:
		return

	failure_count += 1
	push_error("City resource-accounting bootstrap test: " + message)
