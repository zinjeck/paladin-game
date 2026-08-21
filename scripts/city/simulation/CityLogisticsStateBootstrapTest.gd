extends Node

const CitySettlementTestFixtureScript = preload(
	"res://scripts/city/simulation/test_support/CitySettlementTestFixture.gd"
)

var failure_count: int = 0


func _ready() -> void:
	_run_bootstrap_test()
	WorldData.reset_runtime_session_state()

	if failure_count > 0:
		push_error(
			"City logistics-state bootstrap test failed: "
			+ str(failure_count)
		)
		get_tree().quit(1)
		return

	print("City logistics-state bootstrap test passed.")
	get_tree().quit(0)


func _run_bootstrap_test() -> void:
	var fixture = CitySettlementTestFixtureScript.create({
		"label": "Logistics Bootstrap",
	})
	_expect(fixture != null, "Fixture must register an explicit City context.")
	if fixture == null:
		return

	var city_state: CitySettlementSimulationState = fixture.city_state
	var logistics_state: CityLogisticsState = city_state.logistics_state
	logistics_state.ground_piles = [
		{
			"id": 17,
			"tile_position": Vector2i(3, 3),
			"resource_type": WorldData.RESOURCE_FISH,
			"amount": 4,
			"test_owner": "bootstrap",
		},
	]
	logistics_state.ground_pile_index_by_id = {17: 0}
	logistics_state.next_ground_pile_id = 18
	logistics_state.ground_pile_version = 5
	logistics_state.haul_reservations = {
		23: {"id": 23, "citizen_id": 3, "test_owner": "bootstrap"},
	}
	logistics_state.haul_reservation_id_by_citizen_id = {3: 23}
	logistics_state.haul_source_reserved_amount_by_key = {"test:source": 2}
	logistics_state.haul_destination_reserved_amount_by_key = {
		"test:destination": 2,
	}
	logistics_state.next_haul_reservation_id = 24
	logistics_state.haul_reservation_version = 7

	_expect(
		fixture.is_registered()
		and is_same(
			CityLogisticsSystem.get_state_for_city_state(city_state),
			logistics_state
		)
		and str(logistics_state.ground_piles[0].get("test_owner", ""))
		== "bootstrap"
		and logistics_state.next_ground_pile_id == 18
		and logistics_state.ground_pile_version == 5,
		"Explicit logistics access must retain the registered ground-pile owner."
	)
	_expect(
		logistics_state.haul_reservations.has(23)
		and logistics_state.next_haul_reservation_id == 24
		and logistics_state.haul_reservation_version == 7,
		"Explicit logistics access must retain the registered reservation owner."
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
		and is_same(city_state.logistics_state, logistics_state),
		"Settlement lookup must preserve the exact registered logistics owner."
	)

	var stale_context: SettlementSimulationContext = fixture.settlement_context
	var settlement_id: int = fixture.settlement_id
	fixture.cleanup()
	_expect(
		not WorldPoliticalState.is_registered_settlement_context(stale_context)
		and WorldPoliticalState.get_city_simulation_state(settlement_id) == null,
		"Registry reset must invalidate every logistics fixture binding."
	)


func _expect(condition: bool, message: String) -> void:
	if condition:
		return

	failure_count += 1
	push_error("City logistics-state bootstrap test: " + message)
