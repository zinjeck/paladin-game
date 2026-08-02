extends Node

const GAME_SESSION_SCENE := preload("res://scenes/GameSession.tscn")
const PREPARATION_SERVICE := preload(
	"res://scripts/session/CityPreparationService.gd"
)

var failure_count: int = 0


func _ready() -> void:
	await _test_background_city_preparation()
	await _test_persistent_world_city_views()
	WorldData.reset_runtime_session_state()

	if failure_count > 0:
		push_error("Game session persistence test failed: " + str(failure_count))
		get_tree().quit(1)
		return

	print("Game session persistence tests passed.")
	get_tree().quit(0)


func _test_background_city_preparation() -> void:
	var service = PREPARATION_SERVICE.new()
	var region_tiles := _make_region_tiles(2)
	var request := {
		"signature": "background-preparation-test",
		"region_tiles": region_tiles,
		"region_size": 2,
		"local_tiles_per_world_tile": 2,
		"city_seed": 9917,
	}
	service.request_preparation(request)
	var deadline_msec := Time.get_ticks_msec() + 5000

	while (
		not service.has_completed_payload(request["signature"])
		and Time.get_ticks_msec() < deadline_msec
	):
		await get_tree().process_frame

	var payload := service.take_completed_payload(request["signature"])
	_expect(not payload.is_empty(), "Background city preparation must complete.")

	if not payload.is_empty():
		var prepared_world = payload.get("city_world")
		var prepared_atlas = payload.get("map_atlas")
		_expect(
			prepared_world is WorldData
			and prepared_world.width == 4
			and prepared_world.height == 4,
			"Background preparation must build the requested city dimensions."
		)
		_expect(
			prepared_atlas is Dictionary
			and prepared_atlas.get("rgba8") is PackedByteArray
			and int(prepared_atlas.get("width", 0)) == 4
			and int(prepared_atlas.get("height", 0)) == 4
			and prepared_atlas.get("modes", []).size()
			== MapVisuals.get_all_view_modes().size(),
			"Background preparation must build one complete atomic map atlas."
		)

	service.shutdown()


func _test_persistent_world_city_views() -> void:
	WorldData.reset_runtime_session_state()
	SimulationClock.suspend_simulation()
	SimulationClock.set_speed_multiplier(3.0)
	SimulationClock.set_simulation_paused(false)
	var world := _make_world(8, 8, 4301)
	var locked := WorldData.lock_world_save({
		"source_world": world,
		"region_top_left": Vector2i(2, 2),
		"region_center": Vector2i(2, 2),
		"region_size": 1,
		"world_scene_path": "res://scenes/GameSession.tscn",
		"city_scene_path": "res://scenes/CityScreen.tscn",
		"city_name": "Persistence Test City",
		"culture_name": "Persistence Test Culture",
	})
	_expect(locked, "The persistence fixture must lock its world save.")

	var city_world := _make_world(16, 16, 8123)
	WorldData.store_city_world_save(city_world, 8123)
	var session = GAME_SESSION_SCENE.instantiate()
	add_child(session)
	await get_tree().process_frame

	var initial_world_view = session.world_view
	var initial_world_id: int = initial_world_view.get_instance_id()
	_expect(
		session.simulation_speed_controls == null,
		"World view must not show speed controls before first city entry."
	)

	session.show_city_view()
	await get_tree().process_frame

	_expect(session.city_view != null, "City view must be created on first entry.")
	_expect(
		session.active_view == session.city_view,
		"First entry must activate the city view."
	)
	_expect(
		is_instance_valid(initial_world_view)
		and initial_world_view.get_instance_id() == initial_world_id,
		"Entering the city must not destroy or reload the world view."
	)
	_expect(
		session.city_view_has_been_entered,
		"First city activation must unlock the shared playback controls."
	)
	_expect(
		SimulationClock.simulation_paused,
		"First city entry must pause the simulation by default."
	)
	_expect(
		is_equal_approx(SimulationClock.speed_multiplier, 1.0),
		"First city entry must select normal speed beneath the paused state."
	)

	var speed_controls = session.simulation_speed_controls
	_expect(
		speed_controls != null,
		"First city entry must create the session-wide speed controls."
	)

	var speed_controls_id := 0

	if speed_controls != null:
		speed_controls_id = speed_controls.get_instance_id()
		_expect(
			speed_controls.buttons.size() == 4,
			"Playback controls must contain Pause, 1x, 2x, and 3x."
		)
		_expect(
			speed_controls.speed_one_button.text == "1x"
			and speed_controls.speed_two_button.text == "2x"
			and speed_controls.speed_three_button.text == "3x",
			"Playback speed labels must match the accepted design."
		)
		_expect(
			speed_controls.get_selected_mode_name() == "pause",
			"The pause control must be selected on first city entry."
		)
		speed_controls.select_speed(2.0)

	_expect(
		not SimulationClock.simulation_paused
		and is_equal_approx(SimulationClock.speed_multiplier, 2.0),
		"Selecting 2x must resume the shared clock at double speed."
	)

	var city_renderer = session.city_view
	var first_city_id: int = session.city_view.get_instance_id()
	var all_modes_ready := true

	for mode in MapVisuals.get_all_view_modes():
		all_modes_ready = (
			all_modes_ready
			and city_renderer.city_texture_cache.is_mode_ready(
				city_renderer.city_world,
				mode
			)
		)

	_expect(
		all_modes_ready,
		"City entry must publish all map modes atomically before activation."
	)

	session.show_world_view()
	await get_tree().process_frame
	_expect(
		session.active_view == initial_world_view,
		"Back must reactivate the existing world view."
	)
	_expect(
		session.simulation_speed_controls != null
		and session.simulation_speed_controls.visible,
		"Returning to the world after city entry must retain visible controls."
	)
	_expect(
		session.simulation_speed_controls.get_instance_id()
		== speed_controls_id,
		"World and city views must share one playback-control instance."
	)
	_expect(
		not SimulationClock.simulation_paused
		and is_equal_approx(SimulationClock.speed_multiplier, 2.0),
		"World return must preserve the city-selected clock speed."
	)

	session.show_city_view()
	await get_tree().process_frame
	_expect(
		session.city_view.get_instance_id() == first_city_id,
		"Repeated city entry must reuse the same city instance."
	)
	_expect(
		initial_world_view.get_instance_id() == initial_world_id,
		"Repeated switching must preserve the same world instance."
	)
	_expect(
		not SimulationClock.simulation_paused
		and is_equal_approx(SimulationClock.speed_multiplier, 2.0),
		"Repeated city entry must not reset the shared playback state."
	)

	if speed_controls != null:
		speed_controls.select_pause()
		_expect(
			SimulationClock.simulation_paused
			and speed_controls.get_selected_mode_name() == "pause",
			"Pause must update both the clock and active-button state."
		)
		speed_controls.select_speed(3.0)
		_expect(
			not SimulationClock.simulation_paused
			and is_equal_approx(SimulationClock.speed_multiplier, 3.0)
			and speed_controls.get_selected_mode_name() == "3x",
			"The final speed button must run the clock at triple speed."
		)

	SimulationClock.set_simulation_paused(false)
	SimulationClock.set_speed_multiplier(1.0)
	session.queue_free()
	await get_tree().process_frame


func _make_region_tiles(size: int) -> Array:
	var rows: Array = []

	for _y in range(size):
		var row: Array = []

		for _x in range(size):
			row.append(_make_land_tile())

		rows.append(row)

	return rows


func _make_world(width: int, height: int, seed: int) -> WorldData:
	var world := WorldData.new()
	world.setup(width, height, seed)

	for y in range(height):
		for x in range(width):
			world.tiles[y][x] = _make_land_tile()

	world.mark_tile_data_changed()
	return world


func _make_land_tile() -> Dictionary:
	return {
		"fertility": 55.0,
		"elevation": 0.2,
		"temperature": 0.5,
		"precipitation": 0.5,
		"terrain": WorldData.TERRAIN_LAND,
		"biome": WorldData.BIOME_PLAIN,
		"resource": WorldData.RESOURCE_NONE,
		"is_land": true,
	}


func _expect(condition: bool, message: String) -> void:
	if condition:
		return

	failure_count += 1
	push_error("Game session persistence test: " + message)
