extends Node

const WORLD_SIZE := Vector2i(8, 8)
const TILE_SIZE := 2
const SEED_A := 431_001
const SEED_B := 431_002
const SettlementCommandControllerScript := preload(
	"res://scripts/settlements/presentation/SettlementCommandController.gd"
)

var failure_count: int = 0


func _ready() -> void:
	_test_exact_binding_and_command_transactions()
	WorldData.reset_runtime_session_state()
	if failure_count > 0:
		push_error(
			"Settlement command controller test failed: "
			+ str(failure_count)
		)
		get_tree().quit(1)
		return
	print("Settlement command controller test passed.")
	get_tree().quit(0)


func _test_exact_binding_and_command_transactions() -> void:
	WorldData.reset_runtime_session_state()
	var fixture := _create_fixture()
	_expect(not fixture.is_empty(), "The registered A/B fixture must exist.")
	if fixture.is_empty():
		return

	var state_a: CitySettlementSimulationState = fixture["state_a"]
	var state_b: CitySettlementSimulationState = fixture["state_b"]
	var context_a: SettlementSimulationContext = fixture["context_a"]
	var context_b: SettlementSimulationContext = fixture["context_b"]
	var settlement_b_id: int = fixture["settlement_b_id"]
	var binding_a := CityPresentationBinding.new()
	var binding_b_equal_generation := CityPresentationBinding.new()
	var binding_b := CityPresentationBinding.new()
	_expect(
		binding_a.rebind(context_a, 1)
		and binding_b_equal_generation.rebind(context_b, 1)
		and binding_b.rebind(context_b, 2)
		and WorldPoliticalState.set_active_settlement(settlement_b_id),
		"Bindings A1/B1/B2 must be valid while B remains globally active."
	)

	var controller = SettlementCommandControllerScript.new()
	_expect(
		controller.can_bind_settlement_presentation(binding_a, TILE_SIZE)
		and controller.bind_settlement_presentation(binding_a, TILE_SIZE)
		and controller.can_bind_settlement_presentation(binding_a, TILE_SIZE)
		and controller.bind_settlement_presentation(binding_a, TILE_SIZE),
		"The exact A1 binding must support a pure idempotent equal-generation bind."
	)
	_expect(
		not controller.can_bind_settlement_presentation(
			binding_b_equal_generation,
			TILE_SIZE
		)
		and not controller.bind_settlement_presentation(
			binding_b_equal_generation,
			TILE_SIZE
		)
		and controller.is_bound_to_settlement_presentation(binding_a),
		"A different settlement at A's generation must be rejected exactly."
	)

	var command_tile := Vector2i(3, 3)
	_expect(
		state_a.city_world.set_tile_surface_feature(
			command_tile,
			WorldData.CITY_SURFACE_FEATURE_TREE
		),
		"The A fixture must expose one eligible tree tile."
	)
	var pointer_world := _tile_world_center(command_tile)
	var a_commands_before := state_a.work_state.player_commands.duplicate(true)
	var a_version_before := state_a.work_state.player_command_version
	var b_commands_before := state_b.work_state.player_commands.duplicate(true)
	var b_version_before := state_b.work_state.player_command_version
	_expect(
		controller.select_command_type(
			SettlementCommandControllerScript.COMMAND_TYPE_CHOP_TREE
		)
		and not controller.begin_drag(
			Vector2(8.0, 8.0),
			pointer_world,
			true
		)
		and controller.begin_drag(
			Vector2(8.0, 8.0),
			pointer_world,
			false
		)
		and controller.drag_preview_tiles == [command_tile],
		"Command mode must own drag geometry and reject cancel-mode mismatch."
	)
	controller.cancel_drag()
	var no_op_commit := controller.finish_drag(
		Vector2(8.0, 8.0),
		pointer_world
	)
	_expect(
		str(no_op_commit.get("status", ""))
		== SettlementCommandControllerScript.COMMIT_STATUS_NO_OP
		and state_a.work_state.player_commands == a_commands_before
		and state_a.work_state.player_command_version == a_version_before
		and state_b.work_state.player_commands == b_commands_before
		and state_b.work_state.player_command_version == b_version_before,
		"Cancel and finish-without-drag must be authoritative no-ops."
	)

	controller.begin_drag(Vector2(8.0, 8.0), pointer_world, false)
	var add_commit := controller.finish_drag(
		Vector2(8.0, 8.0),
		pointer_world
	)
	_expect(
		str(add_commit.get("status", ""))
		== SettlementCommandControllerScript.COMMIT_STATUS_COMMITTED
		and int(add_commit.get("affected_count", 0)) == 1
		and not CityWorkSystem.get_city_player_command_at_tile_for_city_state(
			state_a,
			command_tile
		).is_empty()
		and state_b.work_state.player_commands == b_commands_before
		and state_b.work_state.player_command_version == b_version_before
		and WorldPoliticalState.active_settlement_id == settlement_b_id,
		"An A-bound add commit must mutate only A while global selection is B."
	)

	_expect(
		controller.toggle_cancel_mode()
		and controller.begin_drag(
			Vector2(8.0, 8.0),
			pointer_world,
			true
		),
		"Cancel mode must preview the exact A-owned command."
	)
	var remove_commit := controller.finish_drag(
		Vector2(8.0, 8.0),
		pointer_world
	)
	_expect(
		str(remove_commit.get("status", ""))
		== SettlementCommandControllerScript.COMMIT_STATUS_COMMITTED
		and int(remove_commit.get("affected_count", 0)) == 1
		and CityWorkSystem.get_city_player_command_at_tile_for_city_state(
			state_a,
			command_tile
		).is_empty()
		and state_b.work_state.player_commands == b_commands_before
		and state_b.work_state.player_command_version == b_version_before,
		"An A-bound remove commit must cancel only the exact A command."
	)

	var a_after_commits := state_a.work_state.player_commands.duplicate(true)
	var a_version_after_commits := state_a.work_state.player_command_version
	_expect(
		controller.bind_settlement_presentation(binding_b, TILE_SIZE)
		and controller.is_interaction_state_clear()
		and not controller.bind_settlement_presentation(binding_a, TILE_SIZE)
		and controller.is_bound_to_settlement_presentation(binding_b)
		and state_a.work_state.player_commands == a_after_commits
		and state_a.work_state.player_command_version
		== a_version_after_commits
		and state_b.work_state.player_commands == b_commands_before
		and state_b.work_state.player_command_version == b_version_before,
		"A-to-B rebind and stale-A rejection must be presentation-pure."
	)
	controller.reset_presentation()
	var binding_a_new := CityPresentationBinding.new()
	_expect(
		not controller.bind_settlement_presentation(binding_b, TILE_SIZE)
		and controller.highest_accepted_binding_generation == 2
		and binding_a_new.rebind(context_a, 3)
		and controller.bind_settlement_presentation(binding_a_new, TILE_SIZE)
		and controller.is_bound_to_settlement_presentation(binding_a_new),
		"Reset must retain the high-water mark and accept only a newer A3 bind."
	)


func _create_fixture() -> Dictionary:
	var culture := WorldData.create_culture("Command Controller Culture")
	var culture_id := int(culture.get("id", CultureData.INVALID_CULTURE_ID))
	var polity := WorldPoliticalState.create_polity({
		"name": "Command Controller Realm",
		"polity_type": PolityData.POLITY_TYPE_KINGDOM,
		"primary_culture_id": culture_id,
	})
	var polity_id := int(polity.get("id", PolityData.INVALID_POLITY_ID))
	var settlement_a := _create_city("Command A", polity_id, Vector2i(2, 2))
	var settlement_b := _create_city("Command B", polity_id, Vector2i(5, 5))
	var settlement_a_id := int(
		settlement_a.get("id", SettlementData.INVALID_SETTLEMENT_ID)
	)
	var settlement_b_id := int(
		settlement_b.get("id", SettlementData.INVALID_SETTLEMENT_ID)
	)
	if culture_id <= 0 or settlement_a_id <= 0 or settlement_b_id <= 0:
		return {}

	var world_a := _make_world(SEED_A)
	var world_b := _make_world(SEED_B)
	if (
		not WorldPoliticalState.store_city_world_for_settlement(
			settlement_a_id,
			world_a,
			SEED_A
		)
		or not WorldPoliticalState.store_city_world_for_settlement(
			settlement_b_id,
			world_b,
			SEED_B
		)
	):
		return {}
	var state_a: CitySettlementSimulationState = (
		WorldPoliticalState.get_city_simulation_state(settlement_a_id)
	)
	var state_b: CitySettlementSimulationState = (
		WorldPoliticalState.get_city_simulation_state(settlement_b_id)
	)
	var context_a: SettlementSimulationContext = (
		WorldPoliticalState.get_settlement_context(settlement_a_id)
	)
	var context_b: SettlementSimulationContext = (
		WorldPoliticalState.get_settlement_context(settlement_b_id)
	)
	if state_a == null or state_b == null or context_a == null or context_b == null:
		return {}
	return {
		"settlement_b_id": settlement_b_id,
		"state_a": state_a,
		"state_b": state_b,
		"context_a": context_a,
		"context_b": context_b,
	}


func _create_city(
	settlement_name: String,
	polity_id: int,
	region_center: Vector2i
) -> Dictionary:
	return WorldPoliticalState.create_settlement({
		"name": settlement_name,
		"settlement_type": SettlementData.SETTLEMENT_TYPE_CITY,
		"polity_id": polity_id,
		"world_region_top_left": region_center,
		"world_region_center": region_center,
		"world_region_size": 1,
		"simulation_backend_kind": (
			SettlementSimulationContext.BACKEND_CITY_SETTLEMENT_STATE
		),
	})


func _make_world(seed_value: int) -> WorldData:
	var world := WorldData.new()
	world.setup(WORLD_SIZE.x, WORLD_SIZE.y, seed_value)
	return world


func _tile_world_center(tile_position: Vector2i) -> Vector2:
	return (
		Vector2(tile_position) + Vector2(0.5, 0.5)
	) * float(TILE_SIZE)


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	failure_count += 1
	push_error("SettlementCommandControllerTest: " + message)
