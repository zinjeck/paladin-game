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
			"City work-state bootstrap test failed: "
			+ str(failure_count)
		)
		get_tree().quit(1)
		return

	print("City work-state bootstrap test passed.")
	get_tree().quit(0)


func _run_bootstrap_test() -> void:
	var fixture = CitySettlementTestFixtureScript.create({
		"label": "Work Bootstrap",
	})
	_expect(fixture != null, "Fixture must register an explicit City context.")
	if fixture == null:
		return

	var city_state: CitySettlementSimulationState = fixture.city_state
	var work_state: CityWorkState = city_state.work_state
	work_state.player_commands = [
		{"id": 7, "test_owner": "bootstrap"},
	]
	work_state.player_command_index_by_id = {7: 0}
	work_state.next_player_command_id = 8
	work_state.player_command_version = 4
	work_state.work_orders = {
		11: {"id": 11, "source_key": "test:bootstrap"},
	}
	work_state.work_order_id_by_source_key = {"test:bootstrap": 11}
	work_state.next_work_order_id = 12
	work_state.work_order_version = 6

	_expect(
		fixture.is_registered()
		and is_same(
			CityWorkSystem.get_state_for_city_state(city_state),
			work_state
		)
		and str(work_state.player_commands[0].get("test_owner", ""))
		== "bootstrap"
		and work_state.next_player_command_id == 8
		and work_state.player_command_version == 4,
		"Explicit work access must retain the registered command owner."
	)
	_expect(
		work_state.work_orders.has(11)
		and work_state.next_work_order_id == 12
		and work_state.work_order_version == 6,
		"Explicit work access must retain the registered work-order owner."
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
		and is_same(city_state.work_state, work_state),
		"Settlement lookup must preserve the exact registered work owner."
	)

	var stale_context: SettlementSimulationContext = fixture.settlement_context
	var settlement_id: int = fixture.settlement_id
	fixture.cleanup()
	_expect(
		not WorldPoliticalState.is_registered_settlement_context(stale_context)
		and WorldPoliticalState.get_city_simulation_state(settlement_id) == null,
		"Registry reset must invalidate every work fixture binding."
	)


func _expect(condition: bool, message: String) -> void:
	if condition:
		return

	failure_count += 1
	push_error("City work-state bootstrap test: " + message)
