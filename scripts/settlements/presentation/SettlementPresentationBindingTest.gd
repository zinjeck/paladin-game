extends Node

const SettlementPresentationBindingScript = preload(
	"res://scripts/settlements/presentation/SettlementPresentationBinding.gd"
)
const SettlementPlacementControllerScript = preload(
	"res://scripts/settlements/presentation/SettlementPlacementController.gd"
)
const SettlementSelectionControllerScript = preload(
	"res://scripts/settlements/presentation/SettlementSelectionController.gd"
)
const SettlementCommandControllerScript = preload(
	"res://scripts/settlements/presentation/SettlementCommandController.gd"
)
const SettlementInfrastructurePresenterScript = preload(
	"res://scripts/settlements/presentation/SettlementInfrastructurePresenter.gd"
)
const SettlementUiControllerScript = preload(
	"res://scripts/settlements/presentation/SettlementUiController.gd"
)
const CityCitizenMovementPresentationScript = preload(
	"res://scripts/citizens/rendering/CityCitizenMovementPresentation.gd"
)
const CityInformationPanelScript = preload(
	"res://scripts/ui/city/CityInformationPanel.gd"
)
const CityObjectPanelAnchorScript = preload(
	"res://scripts/ui/city/CityObjectPanelAnchor.gd"
)
const CitizenDebugPanelScript = preload(
	"res://scripts/ui/debug/CitizenDebugPanel.gd"
)

var failure_count: int = 0


func _ready() -> void:
	_test_generic_registered_identity_and_missing_capability()
	_test_city_detail_adapter()
	WorldPoliticalState.reset_state()
	WorldData.reset_runtime_session_state()

	if failure_count > 0:
		push_error(
			"Settlement presentation binding test failed: "
			+ str(failure_count)
		)
		get_tree().quit(1)
		return

	print("Settlement presentation binding test passed.")
	get_tree().quit(0)


func _test_generic_registered_identity_and_missing_capability() -> void:
	var fixture := _create_registered_fixture()
	if fixture.is_empty():
		_expect(false, "The registered settlement fixture must be created.")
		return

	var village_context: SettlementSimulationContext = fixture["village_context"]
	var outpost_context: SettlementSimulationContext = fixture["outpost_context"]
	var city_context: SettlementSimulationContext = fixture["city_context"]
	var village_id := village_context.settlement_id
	var binding := SettlementPresentationBindingScript.new()
	_expect(
		binding.rebind(village_context, 2)
		and binding.is_valid()
		and binding.matches_context(village_context)
		and binding.settlement_id == village_id
		and binding.polity_id == village_context.polity_id
		and binding.settlement_type == SettlementData.SETTLEMENT_TYPE_VILLAGE
		and binding.backend_kind == SettlementSimulationContext.BACKEND_NONE
		and binding.backend_state == null,
		"The neutral base must bind a generic registered settlement exactly."
	)
	_expect(
		not binding.supports_backend_capability(
			SettlementPresentationBindingScript.CAPABILITY_CITY_DETAIL
		)
		and binding.get_backend_capability(
			SettlementPresentationBindingScript.CAPABILITY_CITY_DETAIL
		) == null,
		"A generic identity token must not invent a city-detail capability."
	)

	# All shared controllers that currently execute city systems make that
	# backend dependency explicit at their settlement-neutral boundary.
	var object_panel := CityObjectPanelAnchorScript.new()
	var object_panel_rejected_missing_capability := (
		not object_panel.can_bind_settlement_presentation(binding, 16)
	)
	object_panel.free()
	_expect(
		not SettlementPlacementControllerScript.new().can_bind_settlement_presentation(
			binding,
			16
		)
		and not SettlementSelectionControllerScript.new().can_bind_settlement_presentation(
			binding,
			16
		)
		and not SettlementCommandControllerScript.new().can_bind_settlement_presentation(
			binding,
			16
		)
		and not SettlementInfrastructurePresenterScript.new().can_bind_settlement_presentation(
			binding,
			16
		)
		and not SettlementUiControllerScript.new().can_bind_settlement_presentation(
			binding
		)
		and not CityCitizenMovementPresentationScript.new().can_bind_settlement_presentation(
			binding,
			16
		)
		and not CityInformationPanelScript.new().can_bind_settlement_presentation(
			binding
		)
		and object_panel_rejected_missing_capability
		and not CitizenDebugPanelScript.new().can_bind_settlement_presentation(
			binding
		),
		"City-detail consumers must reject a valid token with no city capability."
	)

	# The token is immutable after its one successful initialization. Public
	# setters are read-only views and a different context cannot be installed.
	var original_context := binding.settlement_context
	var original_generation := binding.generation
	binding.settlement_context = outpost_context
	binding.settlement_id = outpost_context.settlement_id
	binding.polity_id = outpost_context.polity_id
	binding.settlement_type = SettlementData.SETTLEMENT_TYPE_OUTPOST
	binding.backend_kind = SettlementSimulationContext.BACKEND_CITY_SETTLEMENT_STATE
	binding.backend_state = city_context.local_state
	binding.generation = 9
	binding.highest_accepted_generation = 9
	_expect(
		not binding.rebind(outpost_context, 3)
		and is_same(binding.settlement_context, original_context)
		and binding.settlement_id == village_id
		and binding.generation == original_generation
		and binding.highest_accepted_generation == original_generation
		and binding.is_valid(),
		"A bound identity token must reject both property mutation and rebind."
	)

	var newer_binding := SettlementPresentationBindingScript.new()
	_expect(
		newer_binding.rebind(outpost_context, 4)
		and newer_binding.accepts_generation(4)
		and not newer_binding.accepts_generation(3)
		and not binding.matches_binding(newer_binding),
		"Generation acceptance must be exact and stale generations must fail."
	)
	newer_binding.reset()
	_expect(
		newer_binding.highest_accepted_generation == 4
		and not newer_binding.is_valid()
		and not newer_binding.rebind(outpost_context, 5),
		"Reset must preserve the one-shot token's generation high-water mark."
	)

	var forged_context := SettlementSimulationContext.new({
		"settlement_id": village_context.settlement_id,
		"polity_id": village_context.polity_id,
		"settlement_type": village_context.settlement_type,
		"backend_kind": SettlementSimulationContext.BACKEND_NONE,
		"local_state": CitySettlementSimulationState.new(),
	})
	_expect(
		not SettlementPresentationBindingScript.new().rebind(forged_context, 6),
		"The neutral token must reject an unregistered backend-state identity."
	)


func _test_city_detail_adapter() -> void:
	var fixture := _create_registered_fixture()
	if fixture.is_empty():
		_expect(false, "The city adapter fixture must be created.")
		return

	var village_context: SettlementSimulationContext = fixture["village_context"]
	var city_context: SettlementSimulationContext = fixture["city_context"]
	var city_state: CitySettlementSimulationState = fixture["city_state"]
	var city_world: WorldData = fixture["city_world"]
	var city_binding := CityPresentationBinding.new()
	_expect(
		not city_binding.rebind(village_context, 1),
		"The city adapter must cleanly reject a registered non-city settlement."
	)
	city_state.city_world = null
	city_state.city_seed = 0
	_expect(
		not CityPresentationBinding.new().rebind(city_context, 2),
		"The city adapter must reject a city detail state without a world and seed."
	)
	city_state.city_world = city_world
	city_state.city_seed = 77_501
	_expect(
		city_binding.rebind(city_context, 5)
		and city_binding is SettlementPresentationBindingScript
		and city_binding.is_valid()
		and city_binding.supports_backend_capability(
			SettlementPresentationBindingScript.CAPABILITY_CITY_DETAIL
		)
		and city_binding.supports_backend_capability(
			SettlementPresentationBindingScript.CAPABILITY_SETTLEMENT_WORLD
		)
		and city_binding.supports_backend_capability(
			SettlementPresentationBindingScript.CAPABILITY_DETERMINISTIC_SEED
		)
		and is_same(
			city_binding.get_backend_capability(
				SettlementPresentationBindingScript.CAPABILITY_CITY_DETAIL
			),
			city_state
		)
		and is_same(city_binding.settlement_state, city_state)
		and is_same(city_binding.city_state, city_state)
		and is_same(city_binding.world, city_world)
		and is_same(city_binding.city_world, city_world)
		and city_binding.seed == 77_501
		and city_binding.city_seed == 77_501,
		"The city adapter must expose only the exact validated city detail state."
	)

	var neutral_city_identity := SettlementPresentationBindingScript.new()
	_expect(
		neutral_city_identity.rebind(city_context, 6)
		and neutral_city_identity.is_valid()
		and not neutral_city_identity.supports_backend_capability(
			SettlementPresentationBindingScript.CAPABILITY_CITY_DETAIL
		),
		"A neutral city identity must not gain adapter capabilities implicitly."
	)

	# Replacing the registered backend owner invalidates both the base snapshot
	# and every capability view held by the old adapter.
	WorldPoliticalState.settlement_city_state_by_id[city_context.settlement_id] = (
		CitySettlementSimulationState.new()
	)
	_expect(
		not city_binding.is_valid()
		and city_binding.get_backend_capability(
			SettlementPresentationBindingScript.CAPABILITY_CITY_DETAIL
		) == null,
		"A city adapter must become invalid after exact backend owner replacement."
	)


func _create_registered_fixture() -> Dictionary:
	WorldPoliticalState.reset_state()
	WorldData.reset_runtime_session_state()
	var culture := WorldData.create_culture("Binding Capability Culture")
	var culture_id := int(culture.get("id", -1))
	var polity := WorldPoliticalState.create_polity({
		"name": "Binding Capability Polity",
		"polity_type": PolityData.POLITY_TYPE_KINGDOM,
		"primary_culture_id": culture_id,
	})
	var polity_id := int(polity.get("id", -1))
	if culture_id <= 0 or polity_id <= 0:
		return {}

	var city := _create_settlement(
		"Binding City",
		SettlementData.SETTLEMENT_TYPE_CITY,
		polity_id,
		Vector2i(3, 3),
		SettlementSimulationContext.BACKEND_CITY_SETTLEMENT_STATE
	)
	var city_id := int(city.get("id", -1))
	var village := _create_settlement(
		"Binding Village",
		SettlementData.SETTLEMENT_TYPE_VILLAGE,
		polity_id,
		Vector2i(1, 1),
		SettlementSimulationContext.BACKEND_NONE,
		city_id
	)
	var outpost := _create_settlement(
		"Binding Outpost",
		SettlementData.SETTLEMENT_TYPE_OUTPOST,
		polity_id,
		Vector2i(2, 2),
		SettlementSimulationContext.BACKEND_NONE
	)
	if village.is_empty() or outpost.is_empty() or city.is_empty():
		return {}

	var raw_city_state = WorldPoliticalState.get_city_simulation_state(city_id)
	if not raw_city_state is CitySettlementSimulationState:
		return {}
	var city_state: CitySettlementSimulationState = raw_city_state
	var city_world := WorldData.new()
	city_world.setup(6, 5, 77_501)
	city_state.city_world = city_world
	city_state.city_seed = 77_501

	var village_context = WorldPoliticalState.get_settlement_context(
		int(village["id"])
	)
	var outpost_context = WorldPoliticalState.get_settlement_context(
		int(outpost["id"])
	)
	var city_context = WorldPoliticalState.get_settlement_context(city_id)
	if (
		not village_context is SettlementSimulationContext
		or not outpost_context is SettlementSimulationContext
		or not city_context is SettlementSimulationContext
	):
		return {}
	return {
		"village_context": village_context,
		"outpost_context": outpost_context,
		"city_context": city_context,
		"city_state": city_state,
		"city_world": city_world,
	}


func _create_settlement(
	settlement_name: String,
	settlement_type: String,
	polity_id: int,
	region_center: Vector2i,
	backend_kind: String,
	parent_city_id: int = SettlementData.INVALID_SETTLEMENT_ID
) -> Dictionary:
	return WorldPoliticalState.create_settlement({
		"name": settlement_name,
		"settlement_type": settlement_type,
		"polity_id": polity_id,
		"world_region_top_left": region_center,
		"world_region_center": region_center,
		"world_region_size": 1,
		"simulation_backend_kind": backend_kind,
		"parent_city_id": parent_city_id,
	})


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	failure_count += 1
	push_error("Settlement presentation binding test: " + message)
