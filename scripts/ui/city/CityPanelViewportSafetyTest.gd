extends Node

const PANEL_ANCHOR_SCRIPT := preload(
	"res://scripts/ui/city/CityObjectPanelAnchor.gd"
)
const TEST_VIEWPORT_SIZE := Vector2i(1000, 700)
const VIEWPORT_MARGIN: float = 8.0
const DETAILS_GAP: float = 8.0

var failure_count: int = 0


func _ready() -> void:
	await _test_secondary_panel_flips_left_at_right_edge()
	await _test_panel_group_reclamps_after_anchor_and_size_changes()
	WorldData.reset_runtime_session_state()
	if failure_count > 0:
		push_error("City panel viewport safety tests failed: " + str(failure_count))
		get_tree().quit(1)
		return
	print("City panel viewport safety tests passed.")
	get_tree().quit(0)


func _test_secondary_panel_flips_left_at_right_edge() -> void:
	var fixture := await _make_panel_fixture()
	if fixture.is_empty():
		return
	var owner: CityObjectPanelAnchor = fixture["owner"]
	var viewport_size := owner.get_viewport().get_visible_rect().size
	var primary_size := owner.object_info_panel.size
	var object_world_rect: Rect2 = fixture["object_world_rect"]
	var target_primary_x := viewport_size.x - VIEWPORT_MARGIN - primary_size.x
	owner.position.x = target_primary_x - 10.0 - object_world_rect.end.x
	owner.synchronize()
	var expected_details_x := (
		owner.object_info_panel.position.x
		- DETAILS_GAP
		- owner.workplace_details_panel.size.x
	)
	_expect(
		is_equal_approx(owner.workplace_details_panel.position.x, expected_details_x),
		"A visible secondary panel must flip directly left at the right edge."
	)
	_expect(
		_panel_fits_viewport(owner.object_info_panel, viewport_size)
		and _panel_fits_viewport(owner.workplace_details_panel, viewport_size),
		"Both panels must remain fully visible after the right-edge flip."
	)
	(owner.get_viewport() as SubViewport).queue_free()
	await get_tree().process_frame


func _test_panel_group_reclamps_after_anchor_and_size_changes() -> void:
	var fixture := await _make_panel_fixture()
	if fixture.is_empty():
		return
	var owner: CityObjectPanelAnchor = fixture["owner"]
	var viewport_size := owner.get_viewport().get_visible_rect().size
	var object_world_rect: Rect2 = fixture["object_world_rect"]
	owner.position = Vector2(
		-200.0 - object_world_rect.end.x,
		viewport_size.y + 140.0 - object_world_rect.position.y
	)
	owner.synchronize()
	_expect(
		_panel_fits_viewport(owner.object_info_panel, viewport_size)
		and _panel_fits_viewport(owner.workplace_details_panel, viewport_size),
		"Changing inherited canvas coordinates must immediately reclamp the popup group."
	)

	owner.workplace_details_panel.size = Vector2(380.0, 260.0)
	owner.position = Vector2(
		viewport_size.x - 80.0 - object_world_rect.end.x,
		viewport_size.y - 30.0 - object_world_rect.position.y
	)
	owner.synchronize()
	_expect(
		_panel_fits_viewport(owner.object_info_panel, viewport_size)
		and _panel_fits_viewport(owner.workplace_details_panel, viewport_size),
		"Popup placement must be recalculated when secondary-panel content changes size."
	)
	(owner.get_viewport() as SubViewport).queue_free()
	await get_tree().process_frame


func _make_panel_fixture() -> Dictionary:
	var binding_and_state := _make_binding()
	_expect(not binding_and_state.is_empty(), "The viewport fixture binding must be created.")
	if binding_and_state.is_empty():
		return {}
	var state: CitySettlementSimulationState = binding_and_state["state"]
	var city_object := CityObjectSystem.register_completed_city_object_for_city_state(state, {
		"object_type": CityObjectCatalog.CITY_OBJECT_FISHING_GROUNDS,
		"top_left": Vector2i(20, 20),
		"size_tiles": CityObjectCatalog.get_city_object_size_for_type(
			CityObjectCatalog.CITY_OBJECT_FISHING_GROUNDS
		),
		"object_owner": "player",
	})
	_expect(not city_object.is_empty(), "The viewport fixture object must register.")
	if city_object.is_empty():
		return {}

	var test_viewport := SubViewport.new()
	test_viewport.size = TEST_VIEWPORT_SIZE
	add_child(test_viewport)
	var canvas := Node2D.new()
	test_viewport.add_child(canvas)
	var ui_layer := CanvasLayer.new()
	canvas.add_child(ui_layer)
	var ui_root := Control.new()
	ui_layer.add_child(ui_root)
	var owner: CityObjectPanelAnchor = PANEL_ANCHOR_SCRIPT.new()
	canvas.add_child(owner)
	owner.bind_settlement_presentation(binding_and_state["binding"], 1)
	owner.setup(ui_root)
	owner.object_info_panel.size = Vector2(240.0, 180.0)
	owner.workplace_details_panel.size = Vector2(320.0, 220.0)
	var object_id := int(city_object.get("id", -1))
	owner.update_selected_entity_panel("object", object_id)
	owner.workplace_details_open = true
	owner.update_selected_entity_panel("object", object_id)
	await get_tree().process_frame
	return {
		"owner": owner,
		"object_world_rect": Rect2(
			Vector2(Vector2i(city_object.get("top_left", Vector2i.ZERO))),
			Vector2(Vector2i(city_object.get("size", Vector2i.ZERO)))
		),
	}


func _make_binding() -> Dictionary:
	WorldData.reset_runtime_session_state()
	var culture := WorldData.create_culture("Viewport Culture")
	var culture_id := int(culture.get("id", -1))
	var polity := WorldPoliticalState.create_polity({
		"name": "Viewport Polity",
		"polity_type": PolityData.POLITY_TYPE_KINGDOM,
		"primary_culture_id": culture_id,
	})
	var settlement := WorldPoliticalState.create_settlement({
		"name": "Viewport Settlement",
		"settlement_type": SettlementData.SETTLEMENT_TYPE_CITY,
		"polity_id": int(polity.get("id", -1)),
		"world_region_top_left": Vector2i.ZERO,
		"world_region_center": Vector2i.ZERO,
		"world_region_size": 1,
		"simulation_backend_kind": SettlementSimulationContext.BACKEND_CITY_SETTLEMENT_STATE,
	})
	var context: SettlementSimulationContext = (
		WorldPoliticalState.get_settlement_context(int(settlement.get("id", -1)))
	)
	if context == null:
		return {}
	var state: CitySettlementSimulationState = context.get_city_simulation_state()
	state.city_world = _make_world()
	state.city_seed = 303
	var keep := CityObjectSystem.register_completed_city_object_for_city_state(state, {
		"object_type": CityObjectCatalog.CITY_OBJECT_CITY_CENTER,
		"top_left": Vector2i.ZERO,
		"size_tiles": CityObjectCatalog.get_city_object_size_for_type(
			CityObjectCatalog.CITY_OBJECT_CITY_CENTER
		),
		"object_owner": "player",
	})
	if keep.is_empty():
		return {}
	state.city_runtime_data = {
		"id": int(settlement.get("id", -1)),
		"name": "Viewport Settlement",
		"city_world_seed": 303,
		"city_map_size": Vector2i(32, 32),
		"foundation_top_left": keep.get("top_left", Vector2i.ZERO),
		"foundation_size": keep.get("size", Vector2i.ZERO),
		"foundation_object_id": int(keep.get("id", -1)),
		"foundation_object_owner": str(keep.get("owner", "")),
		"founded": true,
		"can_build": true,
	}
	var binding := CityPresentationBinding.new()
	if not binding.rebind(context, 1):
		return {}
	return {"state": state, "binding": binding}


func _make_world() -> WorldData:
	var world := WorldData.new()
	world.setup(32, 32, 303)
	for y in range(world.height):
		for x in range(world.width):
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


func _panel_fits_viewport(panel: Control, viewport_size: Vector2) -> bool:
	var panel_rect := Rect2(panel.position, panel.size)
	return (
		panel_rect.position.x >= VIEWPORT_MARGIN
		and panel_rect.position.y >= VIEWPORT_MARGIN
		and panel_rect.end.x <= viewport_size.x - VIEWPORT_MARGIN
		and panel_rect.end.y <= viewport_size.y - VIEWPORT_MARGIN
	)


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	failure_count += 1
	push_error("City panel viewport safety test: " + message)
