extends RefCounted
class_name CityDebugPresentation

# City-specific debug text presentation lives here so CityRenderer remains a
# rendering/input coordinator rather than a diagnostics formatter.

const CityStateValidator = preload(
	"res://scripts/city/simulation/CityStateValidator.gd"
)
const CityNavigationSystemScript = preload(
	"res://scripts/city/simulation/systems/CityNavigationSystem.gd"
)
const CitizenDebugPanelScript = preload(
	"res://scripts/ui/debug/CitizenDebugPanel.gd"
)

const CITY_SELECTION_KIND_CITIZEN := "citizen"

#region Navigation and simulation summary


static func get_navigation_text(values: Dictionary) -> String:
	var navigation_status := str(
		values.get(
			"navigation_status",
			CityNavigationSystemScript.PATH_STATUS_NOT_REQUESTED
		)
	)

	if (
		navigation_status
		== CityNavigationSystemScript.PATH_STATUS_NOT_REQUESTED
	):
		return (
			"Navigation Test: select or hover a tile/building "
			+ "and press P"
		)

	var start_tile: Vector2i = values.get(
		"navigation_start_tile",
		WorldData.INVALID_CITY_TILE_POSITION
	)
	var destination_tile: Vector2i = values.get(
		"navigation_destination_tile",
		WorldData.INVALID_CITY_TILE_POSITION
	)
	var path_cost := int(values.get("navigation_path_cost", 0))
	var candidate_count := int(
		values.get("navigation_candidate_count", 0)
	)
	var expanded_nodes := int(
		values.get("navigation_expanded_nodes", 0)
	)
	var duration_usec := int(
		values.get("navigation_duration_usec", 0)
	)

	return (
		"Navigation Test: "
		+ navigation_status
		+ " | Start: "
		+ str(start_tile)
		+ " | End: "
		+ str(destination_tile)
		+ "\n"
		+ "Path Distance: "
		+ format_navigation_path_cost(path_cost)
		+ " | Candidates: "
		+ str(candidate_count)
		+ " | Expanded: "
		+ str(expanded_nodes)
		+ " | Cost: "
		+ "%.3f ms"
		% (
			float(duration_usec)
			/ 1000.0
		)
	)


static func format_navigation_path_cost(path_cost: int) -> String:
	return (
		"%.3f tiles"
		% (
			float(maxi(path_cost, 0))
			/ float(
				WorldData.CITY_CITIZEN_CARDINAL_MOVEMENT_COST
			)
		)
	)


static func get_simulation_text(values: Dictionary) -> String:
	return (
		SimulationClock.get_debug_text()
		+ "\n"
		+ SimulationCoordinator.get_debug_text()
		+ "\n"
		+ CityStateValidator.get_summary_text()
		+ "\n"
		+ get_navigation_text(values)
	)

#endregion

#region Main city debug panel


static func get_panel_text(values: Dictionary) -> String:
	var simulation_text := get_simulation_text(values)
	var city_world: WorldData = values.get("city_world", null)

	if city_world == null:
		return (
			"DEBUG INFO\n"
			+ simulation_text
			+ "\n\n"
			+ "Scene: City\n"
			+ "City world: not generated"
		)

	var city_view_name := str(values.get("city_view_name", "Unknown"))
	var city_seed := int(values.get("city_seed", 0))
	var base_text := (
		"DEBUG INFO\n"
		+ simulation_text
		+ "\n\n"
		+ "Scene: City\n"
		+ "View: "
		+ city_view_name
		+ "\n"
		+ "Seed: "
		+ str(city_seed)
		+ "\nResources (secured/loose/physical): "
		+ get_resource_conservation_text()
		+ "\n\n"
	)
	var hovered_tile: Vector2i = values.get(
		"hovered_city_tile",
		Vector2i(-1, -1)
	)
	var selected_debug_tile: Vector2i = values.get(
		"debug_selected_city_tile",
		WorldData.INVALID_CITY_TILE_POSITION
	)
	var inspected_tile := hovered_tile
	var inspector_source := "Cursor hover"

	if bool(values.get("has_debug_selected_city_tile", false)):
		inspected_tile = selected_debug_tile
		inspector_source = "Debug selection"

	var cursor_text := "Outside city"

	if hovered_tile != Vector2i(-1, -1):
		cursor_text = (
			str(hovered_tile.x)
			+ ", "
			+ str(hovered_tile.y)
		)

	if inspected_tile == Vector2i(-1, -1):
		return (
			base_text
			+ "Cursor: "
			+ cursor_text
			+ "\n"
			+ "Inspector: "
			+ inspector_source
			+ "\n"
			+ "Tile: none\n\n"
			+ get_selection_text(values)
		)

	var tile: Dictionary = city_world.get_tile(
		inspected_tile.x,
		inspected_tile.y
	)
	var fertility_text := "N/A"
	var fertility := float(tile.get("fertility", -1.0))

	if fertility >= 0.0:
		fertility_text = "%.1f" % fertility

	var city_object := CityObjectSystem.get_city_object_at_tile(
		inspected_tile
	)

	return (
		base_text
		+ "Cursor: "
		+ cursor_text
		+ "\n"
		+ "Inspector: "
		+ inspector_source
		+ "\n"
		+ "Tile: "
		+ str(inspected_tile.x)
		+ ", "
		+ str(inspected_tile.y)
		+ "\n"
		+ "Terrain: "
		+ str(tile.get("terrain", "unknown"))
		+ "\n"
		+ "Biome: "
		+ str(tile.get("biome", "unknown"))
		+ "\n"
		+ "Resource: "
		+ str(tile.get("resource", "none"))
		+ "\n\n"
		+ "Elevation: "
		+ "%.3f"
		% float(tile.get("elevation", 0.0))
		+ "\n"
		+ "Temperature: "
		+ "%.3f"
		% float(tile.get("temperature", 0.0))
		+ "\n"
		+ "Precipitation: "
		+ "%.3f"
		% float(tile.get("precipitation", 0.0))
		+ "\n"
		+ "Fertility: "
		+ fertility_text
		+ "\n\n"
		+ "Land: "
		+ DebugPanel.bool_to_yes_no(
			bool(tile.get("is_land", false))
		)
		+ "\n"
		+ "Walkable: "
		+ DebugPanel.bool_to_yes_no(
			CityNavigationSystem.is_city_tile_walkable_for_citizen(
				city_world,
				inspected_tile
			)
		)
		+ "\n"
		+ "Buildable 1x1: "
		+ DebugPanel.bool_to_yes_no(
			CityObjectSystem.can_place_city_object(
				city_world,
				inspected_tile,
				Vector2i(1, 1)
			)
		)
		+ "\n"
		+ "Road placeable: "
		+ DebugPanel.bool_to_yes_no(
			CityConstructionSystem.can_place_city_road_tile(
				city_world,
				inspected_tile
			)
		)
		+ "\n\n"
		+ get_object_text(city_object)
		+ get_ground_pile_text(inspected_tile)
		+ get_tile_citizen_text({
			"tile_position": inspected_tile,
			"debug_selected_city_tile": selected_debug_tile,
			"has_debug_selected_city_tile": bool(
				values.get("has_debug_selected_city_tile", false)
			),
		})
		+ "\n"
		+ get_selection_text(values)
	)

#endregion

#region Tile, object, resource, and selection details


static func get_object_text(city_object: Dictionary) -> String:
	if city_object.is_empty():
		return (
			"Object on tile: none\n"
			+ "Workplace: No\n"
		)

	var object_type := str(city_object.get("type", "unknown"))
	var top_left: Vector2i = city_object.get(
		"top_left",
		Vector2i(-1, -1)
	)
	var size_tiles: Vector2i = city_object.get(
		"size",
		Vector2i.ZERO
	)
	var object_id_text := "N/A"

	if city_object.has("id"):
		object_id_text = str(city_object["id"])

	var container_type := CityResourceContainerSystem.get_city_object_container_type(
		city_object
	)

	return (
		"Object on tile: "
		+ _get_city_object_display_name(city_object)
		+ "\n"
		+ "Object type: "
		+ object_type
		+ "\n"
		+ "Object id: "
		+ object_id_text
		+ "\n"
		+ "Workplace: "
		+ DebugPanel.bool_to_yes_no(
			WorldData.city_object_is_workplace(city_object)
		)
		+ "\n"
		+ "Owner: "
		+ str(city_object.get("owner", "none"))
		+ "\n"
		+ "Container: "
		+ _get_container_type_display_name(container_type)
		+ "\n"
		+ "Object pos: "
		+ str(top_left.x)
		+ ", "
		+ str(top_left.y)
		+ "\n"
		+ "Object size: "
		+ str(size_tiles.x)
		+ " x "
		+ str(size_tiles.y)
		+ "\n"
	)


static func get_ground_pile_text(tile_position: Vector2i) -> String:
	var ground_piles := CityLogisticsSystem.get_city_ground_piles_at_tile(
		tile_position
	)

	if ground_piles.is_empty():
		return "Ground piles: none\n"

	var pile_descriptions: Array[String] = []

	for raw_ground_pile in ground_piles:
		if not raw_ground_pile is Dictionary:
			continue

		var ground_pile: Dictionary = raw_ground_pile
		var ground_pile_id := int(ground_pile.get("id", -1))
		var resource := str(
			ground_pile.get(
				"resource_type",
				WorldData.RESOURCE_NONE
			)
		)
		var amount := maxi(int(ground_pile.get("amount", 0)), 0)
		var source := CityLogisticsSystem.make_city_ground_pile_haul_endpoint(
			ground_pile_id
		)
		var reserved_amount := (
			CityLogisticsSystem.get_city_haul_endpoint_source_reserved_amount(
				source,
				resource
			)
		)

		pile_descriptions.append(
			"#"
			+ str(ground_pile_id)
			+ " "
			+ resource
			+ " "
			+ str(amount)
			+ " (reserved "
			+ str(reserved_amount)
			+ ")"
		)

	return "Ground piles: " + ", ".join(pile_descriptions) + "\n"


static func get_resource_conservation_text() -> String:
	var resource_descriptions: Array[String] = []

	for resource in WorldData.get_city_resource_types():
		resource_descriptions.append(
			resource
			+ " "
			+ str(CityResourceAccountingSystem.get_total_owned_city_resource_amount(resource))
			+ "/"
			+ str(
				CityLogisticsSystem.get_total_city_ground_pile_resource_amount(
					resource
				)
			)
			+ "/"
			+ str(
				WorldData.get_total_physical_city_resource_amount(
					resource
				)
			)
		)

	return ", ".join(resource_descriptions)


static func get_tile_citizen_text(values: Dictionary) -> String:
	var tile_position: Vector2i = values.get(
		"tile_position",
		WorldData.INVALID_CITY_TILE_POSITION
	)
	var selected_debug_tile: Vector2i = values.get(
		"debug_selected_city_tile",
		WorldData.INVALID_CITY_TILE_POSITION
	)
	var standing_ids := CityCitizenSpatialSystem.get_city_citizen_ids_at_tile(
		tile_position
	)
	var claiming_ids := []
	var claim_text := "select a debug tile"

	if (
		bool(values.get("has_debug_selected_city_tile", false))
		and tile_position == selected_debug_tile
	):
		for citizen_id in CityCitizenTaskRuntimeSystem.get_city_active_task_ids_snapshot():
			var current_task := CityCitizenTaskRuntimeSystem.get_city_citizen_current_task(
				citizen_id
			)

			if (
				current_task.get(
					"target_tile",
					WorldData.INVALID_CITY_TILE_POSITION
				)
				== tile_position
			):
				claiming_ids.append(citizen_id)

		claim_text = str(claiming_ids)

	return (
		"Citizen IDs standing here: "
		+ str(standing_ids)
		+ "\n"
		+ "Citizen task claims: "
		+ claim_text
		+ "\n"
	)


static func get_selection_text(values: Dictionary) -> String:
	var selected_entity_kind := str(
		values.get("selected_city_entity_kind", "none")
	)
	var selected_entity_id := int(
		values.get("selected_city_entity_id", -1)
	)

	if selected_entity_kind == "none" or selected_entity_id < 0:
		return "Selected entity: none\n"

	if selected_entity_kind == CITY_SELECTION_KIND_CITIZEN:
		var citizen := CityCitizenRegistrySystem.get_city_citizen_by_id(
			selected_entity_id
		)

		if citizen.is_empty():
			return "Selected citizen: missing\n"

		var current_task := CityCitizenTaskRuntimeSystem.get_city_citizen_current_task(
			selected_entity_id
		)
		var task_target_text := "none"
		var raw_task_target = current_task.get(
			"target_tile",
			WorldData.INVALID_CITY_TILE_POSITION
		)

		if (
			raw_task_target is Vector2i
			and raw_task_target
			!= WorldData.INVALID_CITY_TILE_POSITION
		):
			task_target_text = str(raw_task_target)

		var movement_destination_text := "none"
		var raw_destination = citizen.get(
			"movement_destination_tile",
			WorldData.INVALID_CITY_TILE_POSITION
		)

		if (
			raw_destination is Vector2i
			and raw_destination
			!= WorldData.INVALID_CITY_TILE_POSITION
		):
			movement_destination_text = str(raw_destination)

		var failure_text := str(
			citizen.get(
				"movement_failure_reason",
				WorldData.CITY_CITIZEN_MOVEMENT_FAILURE_NONE
			)
		)
		var task_phase := str(
			current_task.get(
				"phase",
				WorldData.CITY_CITIZEN_TASK_PHASE_NONE
			)
		)

		if (
			task_phase == WorldData.CITY_CITIZEN_TASK_PHASE_BLOCKED
			and failure_text
			== WorldData.CITY_CITIZEN_MOVEMENT_FAILURE_NONE
		):
			failure_text = (
				"task_blocked "
				+ "(specific cause is not recorded yet)"
			)

		var schedule_start := format_minute_of_day(
			CitizenDecisionSystem.WORK_SHIFT_START_MINUTE_OF_DAY
		)
		var schedule_end := format_minute_of_day(
			CitizenDecisionSystem.WORK_SHIFT_END_MINUTE_OF_DAY
		)

		return (
			"Selected citizen: "
			+ str(citizen.get("name", "Unknown"))
			+ "\n"
			+ "Selected id: "
			+ str(selected_entity_id)
			+ "\n"
			+ "Task: "
			+ CitizenDebugPanelScript.get_task_text(citizen)
			+ "\n"
			+ "Task target: "
			+ task_target_text
			+ " | Destination: "
			+ movement_destination_text
			+ "\n"
			+ "Workplace: "
			+ CitizenDebugPanelScript.get_job_text(citizen)
			+ "\n"
			+ "Schedule: Work "
			+ schedule_start
			+ "-"
			+ schedule_end
			+ " | Active: "
			+ DebugPanel.bool_to_yes_no(
				CitizenDecisionSystem.is_work_shift_active()
			)
			+ "\n"
			+ "Failure: "
			+ failure_text
			+ "\n"
		)

	var selected_object_id := int(
		values.get("selected_city_object_id", -1)
	)
	var selected_object := CityObjectSystem.get_city_object_by_id(
		selected_object_id
	)

	if selected_object.is_empty():
		return "Selected object: missing\n"

	return (
		"Selected object: "
		+ _get_city_object_display_name(selected_object)
		+ "\n"
		+ "Selected id: "
		+ str(selected_object_id)
		+ "\n"
	)


static func format_minute_of_day(minute_of_day: int) -> String:
	var safe_minute := clampi(
		minute_of_day,
		0,
		SimulationClock.MINUTES_PER_DAY - 1
	)
	var hour := int(
		safe_minute
		/ SimulationClock.MINUTES_PER_HOUR
	)
	var minute := safe_minute % SimulationClock.MINUTES_PER_HOUR

	return (
		str(hour).pad_zeros(2)
		+ ":"
		+ str(minute).pad_zeros(2)
	)

#endregion

#region Local presentation helpers


static func _get_city_object_display_name(
	city_object: Dictionary
) -> String:
	if city_object.is_empty():
		return "Unknown"

	return WorldData.get_city_object_display_name_for_type(
		str(city_object.get("type", ""))
	)


static func _get_container_type_display_name(
	container_type: String
) -> String:
	match container_type:
		WorldData.CONTAINER_TYPE_PUBLIC_CITY_STORAGE:
			return "Public city storage"
		WorldData.CONTAINER_TYPE_PRIVATE_HOME_STORAGE:
			return "Private home storage"
		WorldData.CONTAINER_TYPE_WORKPLACE_STORAGE:
			return "Workplace output buffer"
		WorldData.CONTAINER_TYPE_PERSONAL_INVENTORY:
			return "Personal inventory"
		WorldData.CONTAINER_TYPE_GROUND_PILE:
			return "Ground pile"
		_:
			return "None"

#endregion
