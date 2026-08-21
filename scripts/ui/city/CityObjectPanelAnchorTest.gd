extends Node

const PANEL_ANCHOR_SCRIPT := preload(
	"res://scripts/ui/city/CityObjectPanelAnchor.gd"
)

var failure_count: int = 0


func _ready() -> void:
	await _test_world_attachment_and_road_exclusion()
	_test_binding_high_water_and_zero_gameplay_mutation()
	WorldData.reset_runtime_session_state()

	if failure_count > 0:
		push_error("City object panel owner test failed: " + str(failure_count))
		get_tree().quit(1)
		return
	print("City object panel owner tests passed.")
	get_tree().quit(0)


func _test_world_attachment_and_road_exclusion() -> void:
	var fixture := _make_two_city_fixture()
	_expect(not fixture.is_empty(), "The panel fixture must be created.")
	if fixture.is_empty():
		return
	var binding: CityPresentationBinding = fixture["binding_a"]
	var state: CitySettlementSimulationState = fixture["state_a"]
	var fishery := _register_object(
		state,
		CityObjectCatalog.CITY_OBJECT_FISHING_GROUNDS,
		Vector2i(10, 5)
	)
	var road := _register_object(
		state,
		CityObjectCatalog.CITY_OBJECT_ROAD,
		Vector2i(4, 8)
	)
	_expect(not fishery.is_empty() and not road.is_empty(), "Panel objects must register.")
	if fishery.is_empty() or road.is_empty():
		return

	var canvas := Node2D.new()
	canvas.position = Vector2(12.0, 18.0)
	canvas.scale = Vector2(2.0, 2.0)
	add_child(canvas)
	var ui_layer := CanvasLayer.new()
	canvas.add_child(ui_layer)
	var ui_root := Control.new()
	ui_layer.add_child(ui_root)
	var owner: CityObjectPanelAnchor = PANEL_ANCHOR_SCRIPT.new()
	canvas.add_child(owner)
	_expect(owner.bind_settlement_presentation(binding, 2), "The owner must accept binding A.")
	_expect(owner.setup(ui_root), "The owner must create its panels from an explicit UI root.")
	owner.object_info_panel.size = Vector2(240.0, 160.0)
	owner.workplace_details_panel.size = Vector2(320.0, 160.0)
	owner.update_selected_entity_panel("object", int(fishery.get("id", -1)))
	owner.workplace_details_open = true
	owner.update_selected_entity_panel("object", int(fishery.get("id", -1)))
	owner.synchronize()

	var object_rect := _object_world_rect(fishery, 2)
	var right_middle_screen := owner.get_global_transform_with_canvas() * Vector2(
		object_rect.end.x,
		object_rect.position.y + object_rect.size.y * 0.5
	)
	var expected_position := Vector2(
		right_middle_screen.x + 10.0,
		right_middle_screen.y - owner.object_info_panel.size.y * 0.5
	)
	_expect(
		owner.object_info_panel.visible
		and owner.object_info_panel.position.is_equal_approx(expected_position),
		"A selected non-road object panel must attach to the inherited canvas transform."
	)
	_expect(
		owner.workplace_details_panel.position.is_equal_approx(Vector2(
			expected_position.x + owner.object_info_panel.size.x + 8.0,
			expected_position.y
		)),
		"The workplace details sidecar must remain attached to the main panel."
	)

	var first_position := owner.object_info_panel.position
	canvas.scale = Vector2(3.0, 3.0)
	canvas.position = Vector2(-25.0, 9.0)
	owner.synchronize()
	right_middle_screen = owner.get_global_transform_with_canvas() * Vector2(
		object_rect.end.x,
		object_rect.position.y + object_rect.size.y * 0.5
	)
	expected_position = Vector2(
		right_middle_screen.x + 10.0,
		right_middle_screen.y - owner.object_info_panel.size.y * 0.5
	)
	_expect(
		not owner.object_info_panel.position.is_equal_approx(first_position)
		and owner.object_info_panel.position.is_equal_approx(expected_position),
		"The owner must track camera-style pan and zoom without retaining its parent."
	)

	owner.update_selected_entity_panel("object", int(road.get("id", -1)))
	owner.object_info_panel.visible = true
	owner.workplace_details_panel.visible = true
	owner.synchronize()
	owner.synchronize()
	_expect(
		not owner.object_info_panel.visible
		and not owner.workplace_details_panel.visible
		and owner.selected_entity_id == int(road.get("id", -1)),
		"Roads must remain selected while their object panels stay suppressed."
	)

	owner.layout(Vector2(1000.0, 700.0), 64.0)
	owner.update_selected_entity_panel("none", -1)
	owner.synchronize()
	_expect(
		owner.object_info_panel.position.is_equal_approx(Vector2(0.0, 70.0)),
		"Leaving object selection must restore the owner's screen-space layout."
	)
	canvas.queue_free()
	await get_tree().process_frame


func _test_binding_high_water_and_zero_gameplay_mutation() -> void:
	var fixture := _make_two_city_fixture()
	_expect(not fixture.is_empty(), "The rebind fixture must be created.")
	if fixture.is_empty():
		return
	var binding_a: CityPresentationBinding = fixture["binding_a"]
	var binding_b: CityPresentationBinding = fixture["binding_b"]
	var context_a: SettlementSimulationContext = fixture["context_a"]
	var state_a: CitySettlementSimulationState = fixture["state_a"]
	var state_b: CitySettlementSimulationState = fixture["state_b"]
	var owner: CityObjectPanelAnchor = PANEL_ANCHOR_SCRIPT.new()
	var before_a := _gameplay_fingerprint(state_a)
	var before_b := _gameplay_fingerprint(state_b)

	_expect(owner.can_bind_settlement_presentation(binding_a, 2), "Binding A must preflight.")
	_expect(owner.bind_settlement_presentation(binding_a, 2), "Binding A must commit.")
	_expect(owner.can_bind_settlement_presentation(binding_b, 2), "Binding B must preflight.")
	_expect(owner.bind_settlement_presentation(binding_b, 2), "Binding B must commit.")
	_expect(
		not owner.can_bind_settlement_presentation(binding_a, 2)
		and not owner.bind_settlement_presentation(binding_a, 2)
		and owner.is_bound_to_settlement_presentation(binding_b),
		"A stale A-after-B binding must be rejected without changing the accepted owner."
	)
	owner.reset_presentation()
	_expect(
		not owner.can_bind_settlement_presentation(binding_a, 2)
		and not owner.bind_settlement_presentation(binding_a, 2),
		"Reset must preserve the generation high-water mark."
	)
	var binding_a3 := CityPresentationBinding.new()
	_expect(binding_a3.rebind(context_a, 3), "A fresh generation-three A binding must be valid.")
	_expect(
		owner.bind_settlement_presentation(binding_a3, 2)
		and owner.is_bound_to_settlement_presentation(binding_a3),
		"The owner must support a deliberate A/B/A lifecycle with a newer generation."
	)
	_expect(
		before_a == _gameplay_fingerprint(state_a)
		and before_b == _gameplay_fingerprint(state_b),
		"Panel bind, reject, reset, and A/B/A rebind must perform zero gameplay mutation."
	)
	owner.free()


func _make_two_city_fixture() -> Dictionary:
	WorldData.reset_runtime_session_state()
	var culture := WorldData.create_culture("Panel Culture")
	var culture_id := int(culture.get("id", -1))
	var polity := WorldPoliticalState.create_polity({
		"name": "Panel Polity",
		"polity_type": PolityData.POLITY_TYPE_KINGDOM,
		"primary_culture_id": culture_id,
	})
	var polity_id := int(polity.get("id", -1))
	if culture_id <= 0 or polity_id <= 0:
		return {}
	var result := {}
	for index in range(2):
		var settlement := WorldPoliticalState.create_settlement({
			"name": "Panel Settlement " + str(index),
			"settlement_type": SettlementData.SETTLEMENT_TYPE_CITY,
			"polity_id": polity_id,
			"world_region_top_left": Vector2i(index, 0),
			"world_region_center": Vector2i(index, 0),
			"world_region_size": 1,
			"simulation_backend_kind": SettlementSimulationContext.BACKEND_CITY_SETTLEMENT_STATE,
		})
		var settlement_id := int(settlement.get("id", -1))
		var context: SettlementSimulationContext = (
			WorldPoliticalState.get_settlement_context(settlement_id)
		)
		if context == null:
			return {}
		var state: CitySettlementSimulationState = context.get_city_simulation_state()
		state.city_world = _make_world(100 + index)
		state.city_seed = 100 + index
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
			"id": settlement_id,
			"name": "Panel Settlement " + str(index),
			"city_world_seed": 100 + index,
			"city_map_size": Vector2i(16, 16),
			"foundation_top_left": keep.get("top_left", Vector2i.ZERO),
			"foundation_size": keep.get("size", Vector2i.ZERO),
			"foundation_object_id": int(keep.get("id", -1)),
			"foundation_object_owner": str(keep.get("owner", "")),
			"founded": true,
			"can_build": true,
		}
		var binding := CityPresentationBinding.new()
		if not binding.rebind(context, index + 1):
			return {}
		var suffix := "a" if index == 0 else "b"
		result["context_" + suffix] = context
		result["state_" + suffix] = state
		result["binding_" + suffix] = binding
	return result


func _register_object(
	state: CitySettlementSimulationState,
	object_type: String,
	top_left: Vector2i
) -> Dictionary:
	var values := {
		"object_type": object_type,
		"top_left": top_left,
		"size_tiles": CityObjectCatalog.get_city_object_size_for_type(object_type),
		"object_owner": "player",
	}
	if object_type == CityObjectCatalog.CITY_OBJECT_ROAD:
		values.erase("top_left")
		values.erase("size_tiles")
		values["footprint_tiles"] = [top_left]
	return CityObjectSystem.register_completed_city_object_for_city_state(state, values)


func _object_world_rect(city_object: Dictionary, tile_size: int) -> Rect2:
	return Rect2(
		Vector2(Vector2i(city_object.get("top_left", Vector2i.ZERO)) * tile_size),
		Vector2(Vector2i(city_object.get("size", Vector2i.ZERO)) * tile_size)
	)


func _make_world(seed_value: int) -> WorldData:
	var world := WorldData.new()
	world.setup(16, 16, seed_value)
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


func _gameplay_fingerprint(state: CitySettlementSimulationState) -> String:
	return JSON.stringify({
		"objects": CityObjectSystem.get_city_object_snapshot_for_city_state(state),
		"object_version": state.object_state.object_version,
		"citizen_version": state.citizen_registry_state.citizen_version,
		"construction_version": state.construction_state.construction_version,
	})


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	failure_count += 1
	push_error("City object panel owner test: " + message)
