extends RefCounted
class_name CityRendererBindingSupport


static func prepare_player_capital_renderer(
	renderer: CityRenderer
) -> Dictionary:
	if (
		renderer == null
		or not WorldPoliticalState.synchronize_foundation_with_world_data()
		or not WorldPoliticalState.validate_registry_integrity()
	):
		return {}

	var settlement_id := WorldPoliticalState.get_player_capital_settlement_id()
	var settlement_context = WorldPoliticalState.get_settlement_context(
		settlement_id
	)
	if settlement_context == null:
		return {}

	var city_state: CitySettlementSimulationState = (
		settlement_context.get_city_simulation_state()
	)
	if city_state == null:
		return {}

	var prepared_payload: Dictionary = {}
	if city_state.city_world == null or city_state.city_seed <= 0:
		var city_seed := CityWorldGenerator.calculate_city_seed()
		var generator := CityWorldGenerator.new()
		var city_world := generator.generate_city_world(
			renderer.local_tiles_per_world_tile,
			city_seed,
			true,
			0.45
		)
		if city_world == null or generator.generated_map_atlas_data.is_empty():
			return {}

		city_state.city_world = city_world
		city_state.city_seed = city_seed
		prepared_payload = _make_prepared_payload(
			city_world,
			city_seed,
			generator.generated_map_atlas_data
		)

	return bootstrap_and_configure_renderer(
		renderer,
		settlement_context,
		prepared_payload
	)


static func bootstrap_and_configure_renderer(
	renderer: CityRenderer,
	settlement_context: SettlementSimulationContext,
	prepared_payload: Dictionary = {}
) -> Dictionary:
	if renderer == null or settlement_context == null:
		return {}

	var bootstrap_result := CitySettlementRuntimeBootstrap.ensure_ready(
		settlement_context
	)
	if not bool(bootstrap_result.get("success", false)):
		return {}
	if not renderer.configure_initial_city_presentation(
		settlement_context,
		prepared_payload
	):
		return {}

	return {
		"settlement_context": settlement_context,
		"city_state": settlement_context.get_city_simulation_state(),
		"prepared_payload": prepared_payload,
		"bootstrap_result": bootstrap_result,
	}


static func configure_existing_renderer(
	renderer: CityRenderer,
	settlement_id: int,
	prepared_payload: Dictionary = {}
) -> Dictionary:
	var settlement_context = WorldPoliticalState.get_settlement_context(
		settlement_id
	)
	if settlement_context == null:
		return {}
	return bootstrap_and_configure_renderer(
		renderer,
		settlement_context,
		prepared_payload
	)


static func _make_prepared_payload(
	city_world: WorldData,
	city_seed: int,
	map_atlas: Dictionary
) -> Dictionary:
	return {
		"valid": true,
		"city_world": city_world,
		"city_seed": city_seed,
		"map_atlas": map_atlas,
		"tree_tiles": city_world.prepared_city_tree_tiles.duplicate(),
		"rock_tiles": city_world.prepared_city_rock_tiles.duplicate(),
		"feature_tile_data_version": (
			city_world.prepared_city_feature_tile_data_version
		),
		"city_surface_feature_change_version": (
			city_world.city_surface_feature_change_version
		),
		"preparation_duration_usec": 0,
	}
