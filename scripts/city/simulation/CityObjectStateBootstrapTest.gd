extends Node

const CitySettlementTestFixtureScript = preload(
	"res://scripts/city/simulation/test_support/CitySettlementTestFixture.gd"
)

var failure_count: int = 0


func _ready() -> void:
	_test_state_defaults()
	_test_registered_context_owns_bootstrap_state()
	WorldData.reset_runtime_session_state()

	if failure_count > 0:
		push_error(
			"City object-state bootstrap test failed: "
			+ str(failure_count)
		)
		get_tree().quit(1)
		return

	print("City object-state bootstrap test passed.")
	get_tree().quit(0)


func _test_state_defaults() -> void:
	var state := CityObjectState.new()
	_expect(
		state.objects.is_empty()
		and state.object_index_by_id.is_empty()
		and state.occupied_tiles.is_empty()
		and state.next_object_id == 1
		and state.object_version == 0,
		"A new CityObjectState must have clean registry defaults."
	)


func _test_registered_context_owns_bootstrap_state() -> void:
	var fixture = CitySettlementTestFixtureScript.create({
		"label": "Object Bootstrap",
	})
	_expect(fixture != null, "Fixture must register an explicit City context.")
	if fixture == null:
		return

	var tile := Vector2i(3, 3)
	var objects: Array = [{
		"id": 17,
		"type": CityObjectCatalog.CITY_OBJECT_ROAD,
		"tiles": [tile],
		"owner": "bootstrap",
	}]
	var object_index_by_id: Dictionary = {17: 0}
	var occupied_tiles: Dictionary = {tile: 17}
	var city_state: CitySettlementSimulationState = fixture.city_state
	var bootstrap_state: CityObjectState = city_state.object_state
	bootstrap_state.objects = objects
	bootstrap_state.object_index_by_id = object_index_by_id
	bootstrap_state.occupied_tiles = occupied_tiles
	bootstrap_state.next_object_id = 18
	bootstrap_state.object_version = 5

	_expect(
		fixture.is_registered()
		and is_same(
			CityObjectSystem.get_state_for_city_state(city_state),
			bootstrap_state
		)
		and is_same(bootstrap_state.objects, objects)
		and is_same(
			bootstrap_state.object_index_by_id,
			object_index_by_id
		)
		and is_same(
			bootstrap_state.occupied_tiles,
			occupied_tiles
		)
		and bootstrap_state.next_object_id == 18
		and bootstrap_state.object_version == 5,
		"Explicit object access must preserve the registered owner's exact state."
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
		and is_same(rebound_context.get_city_object_state(), bootstrap_state)
		and is_same(
			CityObjectSystem.get_state_for_city_state(city_state),
			bootstrap_state
		)
		and bootstrap_state.objects.size() == 1,
		"Rebinding by settlement ID must retain the registered object owner."
	)

	var stale_context: SettlementSimulationContext = fixture.settlement_context
	var settlement_id: int = fixture.settlement_id
	fixture.cleanup()
	_expect(
		not WorldPoliticalState.is_registered_settlement_context(stale_context)
		and WorldPoliticalState.get_city_simulation_state(settlement_id) == null,
		"Registry reset must invalidate every object fixture binding."
	)


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	failure_count += 1
	push_error("City object-state bootstrap test: " + message)
