extends RefCounted
class_name CityDebugPresentation

# Read-only diagnostics for one explicitly bound city presentation. The helper
# never discovers authority through the globally selected settlement.

const CityStateValidator = preload(
	"res://scripts/city/simulation/CityStateValidator.gd"
)
const CityNavigationSystemScript = preload(
	"res://scripts/city/simulation/systems/CityNavigationSystem.gd"
)

const CITY_SELECTION_KIND_CITIZEN := "citizen"

var presentation_binding: CityPresentationBinding
var citizen_debug_panel: CitizenDebugPanel


func bind_city_presentation(
	binding: CityPresentationBinding,
	debug_panel: CitizenDebugPanel
) -> bool:
	if binding == null or not binding.is_valid() or debug_panel == null:
		return false
	if not debug_panel.is_bound_to_city_presentation(binding):
		return false
	presentation_binding = binding
	citizen_debug_panel = debug_panel
	return true


func is_bound_to_city_presentation(
	binding: CityPresentationBinding
) -> bool:
	return (
		presentation_binding != null
		and presentation_binding.matches_binding(binding)
		and citizen_debug_panel != null
		and citizen_debug_panel.is_bound_to_city_presentation(binding)
	)


func get_navigation_text(values: Dictionary) -> String:
	var navigation_status := str(values.get(
		"navigation_status",
		CityNavigationSystemScript.PATH_STATUS_NOT_REQUESTED
	))
	if navigation_status == CityNavigationSystemScript.PATH_STATUS_NOT_REQUESTED:
		return "Navigation Test: select or hover a tile/building and press P"

	return (
		"Navigation Test: " + navigation_status
		+ " | Start: " + str(values.get(
			"navigation_start_tile",
			CityCitizens.INVALID_CITY_TILE_POSITION
		))
		+ " | End: " + str(values.get(
			"navigation_destination_tile",
			CityCitizens.INVALID_CITY_TILE_POSITION
		))
		+ "\nPath Distance: "
		+ format_navigation_path_cost(int(values.get("navigation_path_cost", 0)))
		+ " | Candidates: " + str(int(values.get("navigation_candidate_count", 0)))
		+ " | Expanded: " + str(int(values.get("navigation_expanded_nodes", 0)))
		+ " | Cost: %.3f ms" % (
			float(int(values.get("navigation_duration_usec", 0))) / 1000.0
		)
	)


static func format_navigation_path_cost(path_cost: int) -> String:
	return "%.3f tiles" % (
		float(maxi(path_cost, 0))
		/ float(CityCitizens.CITY_CITIZEN_CARDINAL_MOVEMENT_COST)
	)


func get_simulation_text(values: Dictionary) -> String:
	if presentation_binding == null or not presentation_binding.is_valid():
		return "City validation: no bound settlement"
	return (
		SimulationClock.get_debug_text()
		+ "\n" + SimulationCoordinator.get_debug_text()
		+ "\n" + CityStateValidator.get_summary_text_for_settlement(
			presentation_binding.settlement_context
		)
		+ "\n" + get_navigation_text(values)
	)


func get_panel_text(values: Dictionary) -> String:
	if presentation_binding == null or not presentation_binding.is_valid():
		return "DEBUG INFO\nCity presentation: not bound"
	var city_state := presentation_binding.city_state
	var city_world := presentation_binding.city_world
	var base_text := (
		"DEBUG INFO\n" + get_simulation_text(values)
		+ "\n\nScene: City"
		+ "\nSettlement: #" + str(presentation_binding.settlement_id)
		+ "\nView: " + str(values.get("city_view_name", "Unknown"))
		+ "\nSeed: " + str(presentation_binding.city_seed)
		+ "\nResources (secured/loose/physical): "
		+ get_resource_conservation_text()
		+ "\n\n"
	)
	var hovered_tile: Vector2i = values.get("hovered_city_tile", Vector2i(-1, -1))
	var selected_debug_tile: Vector2i = values.get(
		"debug_selected_city_tile",
		CityCitizens.INVALID_CITY_TILE_POSITION
	)
	var inspected_tile := hovered_tile
	var inspector_source := "Cursor hover"
	if bool(values.get("has_debug_selected_city_tile", false)):
		inspected_tile = selected_debug_tile
		inspector_source = "Debug selection"
	var cursor_text := (
		str(hovered_tile.x) + ", " + str(hovered_tile.y)
		if hovered_tile != Vector2i(-1, -1)
		else "Outside city"
	)
	if inspected_tile == Vector2i(-1, -1):
		return (
			base_text + "Cursor: " + cursor_text
			+ "\nInspector: " + inspector_source
			+ "\nTile: none\n\n" + get_selection_text(values)
		)

	var tile: Dictionary = city_world.get_tile_for_internal_read(
		inspected_tile.x,
		inspected_tile.y
	)
	var fertility := float(tile.get("fertility", -1.0))
	var fertility_text := "%.1f" % fertility if fertility >= 0.0 else "N/A"
	var city_object := CityObjectSystem.get_city_object_at_tile_for_city_state(
		city_state,
		inspected_tile
	)
	return (
		base_text
		+ "Cursor: " + cursor_text
		+ "\nInspector: " + inspector_source
		+ "\nTile: " + str(inspected_tile.x) + ", " + str(inspected_tile.y)
		+ "\nTerrain: " + str(tile.get("terrain", "unknown"))
		+ "\nBiome: " + str(tile.get("biome", "unknown"))
		+ "\nResource: " + str(tile.get("resource", "none"))
		+ "\n\nElevation: %.3f" % float(tile.get("elevation", 0.0))
		+ "\nTemperature: %.3f" % float(tile.get("temperature", 0.0))
		+ "\nPrecipitation: %.3f" % float(tile.get("precipitation", 0.0))
		+ "\nFertility: " + fertility_text
		+ "\n\nLand: " + DebugPanel.bool_to_yes_no(bool(tile.get("is_land", false)))
		+ "\nWalkable: " + DebugPanel.bool_to_yes_no(
			CityNavigationSystem.is_city_tile_walkable_for_citizen_for_city_state(
				city_state,
				city_world,
				inspected_tile
			)
		)
		+ "\nBuildable 1x1: " + DebugPanel.bool_to_yes_no(
			CityObjectSystem.can_place_city_object_for_city_state(
				city_state,
				city_world,
				inspected_tile,
				Vector2i.ONE
			)
		)
		+ "\nRoad placeable: " + DebugPanel.bool_to_yes_no(
			CityConstructionSystem.can_place_city_road_tile_for_city_state(
				city_state,
				city_world,
				inspected_tile
			)
		)
		+ "\n\n" + get_object_text(city_object)
		+ get_ground_pile_text(inspected_tile)
		+ get_tile_citizen_text({
			"tile_position": inspected_tile,
			"debug_selected_city_tile": selected_debug_tile,
			"has_debug_selected_city_tile": bool(
				values.get("has_debug_selected_city_tile", false)
			),
		})
		+ "\n" + get_selection_text(values)
	)


func get_object_text(city_object: Dictionary) -> String:
	if city_object.is_empty():
		return "Object on tile: none\nWorkplace: No\n"
	var top_left: Vector2i = city_object.get("top_left", Vector2i(-1, -1))
	var size_tiles: Vector2i = city_object.get("size", Vector2i.ZERO)
	var object_id_text := str(city_object.get("id", "N/A"))
	var container_type := CityResourceContainerSystem.get_city_object_container_type(
		city_object
	)
	return (
		"Object on tile: " + _get_city_object_display_name(city_object)
		+ "\nObject type: " + str(city_object.get("type", "unknown"))
		+ "\nObject id: " + object_id_text
		+ "\nWorkplace: " + DebugPanel.bool_to_yes_no(
			CityObjectCatalog.city_object_is_workplace(city_object)
		)
		+ "\nOwner: " + str(city_object.get("owner", "none"))
		+ "\nContainer: " + _get_container_type_display_name(container_type)
		+ "\nObject pos: " + str(top_left.x) + ", " + str(top_left.y)
		+ "\nObject size: " + str(size_tiles.x) + " x " + str(size_tiles.y)
		+ "\n"
	)


func get_ground_pile_text(tile_position: Vector2i) -> String:
	var city_state := presentation_binding.city_state
	var ground_piles: Array[Dictionary] = []
	for raw_ground_pile in city_state.logistics_state.ground_piles:
		if (
			raw_ground_pile is Dictionary
			and raw_ground_pile.get(
				"tile_position",
				CityCitizens.INVALID_CITY_TILE_POSITION
			) == tile_position
		):
			ground_piles.append(raw_ground_pile)
	if ground_piles.is_empty():
		return "Ground piles: none\n"
	ground_piles.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return int(a.get("id", -1)) < int(b.get("id", -1))
	)
	var descriptions: Array[String] = []
	for ground_pile in ground_piles:
		var pile_id := int(ground_pile.get("id", -1))
		var resource := str(ground_pile.get(
			"resource_type",
			WorldData.RESOURCE_NONE
		))
		var source := CityLogisticsSystem.make_city_ground_pile_haul_endpoint(pile_id)
		var reserved_amount := CityLogisticsSystem.get_city_haul_endpoint_source_reserved_amount_for_city_state(
			city_state,
			source,
			resource
		)
		descriptions.append(
			"#" + str(pile_id) + " " + resource + " "
			+ str(maxi(int(ground_pile.get("amount", 0)), 0))
			+ " (reserved " + str(reserved_amount) + ")"
		)
	return "Ground piles: " + ", ".join(descriptions) + "\n"


func get_resource_conservation_text() -> String:
	var city_state := presentation_binding.city_state
	var owned := CityResourceAccountingSystem.get_total_owned_city_resource_amounts_for_city_state(
		city_state
	)
	var descriptions: Array[String] = []
	for resource in CityResourceCatalog.get_city_resource_types():
		var loose_amount := 0
		for raw_ground_pile in city_state.logistics_state.ground_piles:
			if (
				raw_ground_pile is Dictionary
				and str(raw_ground_pile.get(
					"resource_type",
					WorldData.RESOURCE_NONE
				)) == resource
			):
				loose_amount += maxi(int(raw_ground_pile.get("amount", 0)), 0)
		descriptions.append(
			resource + " " + str(maxi(int(owned.get(resource, 0)), 0))
			+ "/" + str(loose_amount)
			+ "/" + str(
				CityResourceAccountingSystem.get_total_physical_city_resource_amount_for_city_state(
					city_state,
					resource
				)
			)
		)
	return ", ".join(descriptions)


func get_tile_citizen_text(values: Dictionary) -> String:
	var city_state := presentation_binding.city_state
	var tile_position: Vector2i = values.get(
		"tile_position",
		CityCitizens.INVALID_CITY_TILE_POSITION
	)
	var standing_ids := CityCitizenSpatialSystem.get_city_citizen_ids_at_tile_for_city_state(
		city_state,
		tile_position
	)
	var claiming_ids: Array[int] = []
	var claim_text := "select a debug tile"
	if (
		bool(values.get("has_debug_selected_city_tile", false))
		and tile_position == values.get(
			"debug_selected_city_tile",
			CityCitizens.INVALID_CITY_TILE_POSITION
		)
	):
		for citizen_id in CityCitizenTaskRuntimeSystem.get_city_active_task_ids_snapshot_for_city_state(
			city_state
		):
			var current_task := CityCitizenTaskRuntimeSystem.get_city_citizen_current_task_for_city_state(
				city_state,
				citizen_id
			)
			if current_task.get(
				"target_tile",
				CityCitizens.INVALID_CITY_TILE_POSITION
			) == tile_position:
				claiming_ids.append(citizen_id)
		claim_text = str(claiming_ids)
	return (
		"Citizen IDs standing here: " + str(standing_ids)
		+ "\nCitizen task claims: " + claim_text + "\n"
	)


func get_selection_text(values: Dictionary) -> String:
	var city_state := presentation_binding.city_state
	var selected_entity_kind := str(values.get("selected_city_entity_kind", "none"))
	var selected_entity_id := int(values.get("selected_city_entity_id", -1))
	if selected_entity_kind == "none" or selected_entity_id < 0:
		return "Selected entity: none\n"

	if selected_entity_kind == CITY_SELECTION_KIND_CITIZEN:
		var citizen := CityCitizenRegistrySystem.get_city_citizen_by_id_for_city_state(
			city_state,
			selected_entity_id
		)
		if citizen.is_empty():
			return "Selected citizen: missing\n"
		var current_task := CityCitizenTaskRuntimeSystem.get_city_citizen_current_task_for_city_state(
			city_state,
			selected_entity_id
		)
		var task_target = current_task.get(
			"target_tile",
			CityCitizens.INVALID_CITY_TILE_POSITION
		)
		var destination = citizen.get(
			"movement_destination_tile",
			CityCitizens.INVALID_CITY_TILE_POSITION
		)
		var task_target_text := (
			str(task_target)
			if task_target is Vector2i and task_target != CityCitizens.INVALID_CITY_TILE_POSITION
			else "none"
		)
		var destination_text := (
			str(destination)
			if destination is Vector2i and destination != CityCitizens.INVALID_CITY_TILE_POSITION
			else "none"
		)
		var failure_text := str(citizen.get(
			"movement_failure_reason",
			CityCitizens.CITY_CITIZEN_MOVEMENT_FAILURE_NONE
		))
		if (
			str(current_task.get("phase", ""))
			== CityCitizens.CITY_CITIZEN_TASK_PHASE_BLOCKED
			and failure_text == CityCitizens.CITY_CITIZEN_MOVEMENT_FAILURE_NONE
		):
			failure_text = "task_blocked (specific cause is not recorded yet)"
		return (
			"Selected citizen: " + str(citizen.get("name", "Unknown"))
			+ "\nSelected id: " + str(selected_entity_id)
			+ "\nTask: " + citizen_debug_panel.get_task_text(citizen)
			+ "\nTask target: " + task_target_text
			+ " | Destination: " + destination_text
			+ "\nWorkplace: " + citizen_debug_panel.get_job_text(citizen)
			+ "\nSchedule: Work "
			+ format_minute_of_day(CitizenDecisionSystem.WORK_SHIFT_START_MINUTE_OF_DAY)
			+ "-" + format_minute_of_day(CitizenDecisionSystem.WORK_SHIFT_END_MINUTE_OF_DAY)
			+ " | Active: " + DebugPanel.bool_to_yes_no(
				CitizenDecisionSystem.is_work_shift_active()
			)
			+ "\nFailure: " + failure_text + "\n"
		)

	var selected_object := CityObjectSystem.get_city_object_by_id_for_city_state(
		city_state,
		int(values.get("selected_city_object_id", -1))
	)
	if selected_object.is_empty():
		return "Selected object: missing\n"
	return (
		"Selected object: " + _get_city_object_display_name(selected_object)
		+ "\nSelected id: " + str(selected_entity_id) + "\n"
	)


static func format_minute_of_day(minute_of_day: int) -> String:
	var safe_minute := clampi(
		minute_of_day,
		0,
		SimulationClock.MINUTES_PER_DAY - 1
	)
	return (
		str(int(safe_minute / SimulationClock.MINUTES_PER_HOUR)).pad_zeros(2)
		+ ":"
		+ str(safe_minute % SimulationClock.MINUTES_PER_HOUR).pad_zeros(2)
	)


static func _get_city_object_display_name(city_object: Dictionary) -> String:
	if city_object.is_empty():
		return "Unknown"
	return CityObjectCatalog.get_city_object_display_name_for_type(
		str(city_object.get("type", ""))
	)


static func _get_container_type_display_name(container_type: String) -> String:
	match container_type:
		CityObjectCatalog.CONTAINER_TYPE_PUBLIC_CITY_STORAGE:
			return "Public city storage"
		CityObjectCatalog.CONTAINER_TYPE_PRIVATE_HOME_STORAGE:
			return "Private home storage"
		CityObjectCatalog.CONTAINER_TYPE_WORKPLACE_STORAGE:
			return "Workplace output buffer"
		CityObjectCatalog.CONTAINER_TYPE_PERSONAL_INVENTORY:
			return "Personal inventory"
		CityObjectCatalog.CONTAINER_TYPE_GROUND_PILE:
			return "Ground pile"
	return "None"
