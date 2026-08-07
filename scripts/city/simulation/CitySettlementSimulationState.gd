extends RefCounted
class_name CitySettlementSimulationState

# Instance-owned mutable state for one CITY settlement.
#
# WorldData still exposes historical city_* fields while the remaining city
# systems are migrated. Those fields act as an active compatibility workspace,
# not the long-term owner of settlement-local simulation state.
#
# Do not add world/polity identity here. SettlementData and PolityData own that
# information. This class is only local city-simulation state.

var city_world = null
var city_seed: int = 0
var city_runtime_data: Dictionary = {}

var resource_amounts: Dictionary = {}
var owned_resource_amount_cache: Dictionary = {}
var owned_resource_amount_cache_container_version: int = -1

var objects: Array = []
var object_index_by_id: Dictionary = {}
var occupied_tiles: Dictionary = {}
var next_object_id: int = 1

var construction_sites: Array = []
var construction_site_index_by_id: Dictionary = {}
var construction_site_id_by_tile: Dictionary = {}
var next_construction_site_id: int = 1

var ground_piles: Array = []
var ground_pile_index_by_id: Dictionary = {}
var next_ground_pile_id: int = 1

# Player commands and parent work orders are now a coherent local subsystem
# rather than another flat group of fields on either WorldData or this class.
var work_state: CityWorkState = CityWorkState.new()

var haul_reservations: Dictionary = {}
var haul_reservation_id_by_citizen_id: Dictionary = {}
var haul_source_reserved_amount_by_key: Dictionary = {}
var haul_destination_reserved_amount_by_key: Dictionary = {}
var next_haul_reservation_id: int = 1

var citizens: Array = []
var citizen_index_by_id: Dictionary = {}
var citizen_ids_by_tile: Dictionary = {}
var active_mover_ids: Array[int] = []
var active_mover_id_lookup: Dictionary = {}
var citizen_movement_visual_events: Array = []
var citizen_movement_visual_tick_index: int = -1
var active_task_ids: Array[int] = []
var active_task_id_lookup: Dictionary = {}
var object_access_tile_cache: Dictionary = {}
var next_citizen_id: int = 1

var object_version: int = 0
var container_version: int = 0
var public_storage_version: int = 0
var citizen_version: int = 0
var citizen_spatial_version: int = 0
var citizen_movement_version: int = 0
var citizen_task_version: int = 0
var assignment_version: int = 0
var workplace_version: int = 0
var ground_pile_version: int = 0
var haul_reservation_version: int = 0
var construction_version: int = 0


func capture_from_world_data() -> void:
	city_world = WorldData.official_city_world
	city_seed = WorldData.official_city_seed
	city_runtime_data = WorldData.player_city_data

	resource_amounts = WorldData.city_resource_amounts
	owned_resource_amount_cache = WorldData.city_owned_resource_amount_cache
	owned_resource_amount_cache_container_version = (
		WorldData.city_owned_resource_amount_cache_container_version
	)

	objects = WorldData.city_objects
	object_index_by_id = WorldData.city_object_index_by_id
	occupied_tiles = WorldData.city_occupied_tiles
	next_object_id = WorldData.next_city_object_id

	construction_sites = WorldData.city_construction_sites
	construction_site_index_by_id = WorldData.city_construction_site_index_by_id
	construction_site_id_by_tile = WorldData.city_construction_site_id_by_tile
	next_construction_site_id = WorldData.next_city_construction_site_id

	ground_piles = WorldData.city_ground_piles
	ground_pile_index_by_id = WorldData.city_ground_pile_index_by_id
	next_ground_pile_id = WorldData.next_city_ground_pile_id

	# This bridge captures the pre-extraction workspace on founding and keeps old
	# callers coherent until their WorldData aliases can be deleted completely.
	work_state.capture_legacy_workspace()

	haul_reservations = WorldData.city_haul_reservations
	haul_reservation_id_by_citizen_id = (
		WorldData.city_haul_reservation_id_by_citizen_id
	)
	haul_source_reserved_amount_by_key = (
		WorldData.city_haul_source_reserved_amount_by_key
	)
	haul_destination_reserved_amount_by_key = (
		WorldData.city_haul_destination_reserved_amount_by_key
	)
	next_haul_reservation_id = WorldData.next_city_haul_reservation_id

	citizens = WorldData.city_citizens
	citizen_index_by_id = WorldData.city_citizen_index_by_id
	citizen_ids_by_tile = WorldData.city_citizen_ids_by_tile
	active_mover_ids = WorldData.city_active_mover_ids
	active_mover_id_lookup = WorldData.city_active_mover_id_lookup
	citizen_movement_visual_events = WorldData.city_citizen_movement_visual_events
	citizen_movement_visual_tick_index = (
		WorldData.city_citizen_movement_visual_tick_index
	)
	active_task_ids = WorldData.city_active_task_ids
	active_task_id_lookup = WorldData.city_active_task_id_lookup
	object_access_tile_cache = WorldData.city_object_access_tile_cache
	next_citizen_id = WorldData.next_city_citizen_id

	object_version = WorldData.city_object_version
	container_version = WorldData.city_container_version
	public_storage_version = WorldData.city_public_storage_version
	citizen_version = WorldData.city_citizen_version
	citizen_spatial_version = WorldData.city_citizen_spatial_version
	citizen_movement_version = WorldData.city_citizen_movement_version
	citizen_task_version = WorldData.city_citizen_task_version
	assignment_version = WorldData.city_assignment_version
	workplace_version = WorldData.city_workplace_version
	ground_pile_version = WorldData.city_ground_pile_version
	haul_reservation_version = WorldData.city_haul_reservation_version
	construction_version = WorldData.city_construction_version


func apply_to_world_data() -> void:
	WorldData.official_city_world = city_world
	WorldData.official_city_seed = city_seed
	WorldData.player_city_data = city_runtime_data

	WorldData.city_resource_amounts = resource_amounts
	WorldData.city_owned_resource_amount_cache = owned_resource_amount_cache
	WorldData.city_owned_resource_amount_cache_container_version = (
		owned_resource_amount_cache_container_version
	)

	WorldData.city_objects = objects
	WorldData.city_object_index_by_id = object_index_by_id
	WorldData.city_occupied_tiles = occupied_tiles
	WorldData.next_city_object_id = next_object_id

	WorldData.city_construction_sites = construction_sites
	WorldData.city_construction_site_index_by_id = construction_site_index_by_id
	WorldData.city_construction_site_id_by_tile = construction_site_id_by_tile
	WorldData.next_city_construction_site_id = next_construction_site_id

	WorldData.city_ground_piles = ground_piles
	WorldData.city_ground_pile_index_by_id = ground_pile_index_by_id
	WorldData.next_city_ground_pile_id = next_ground_pile_id

	work_state.apply_legacy_workspace()

	WorldData.city_haul_reservations = haul_reservations
	WorldData.city_haul_reservation_id_by_citizen_id = (
		haul_reservation_id_by_citizen_id
	)
	WorldData.city_haul_source_reserved_amount_by_key = (
		haul_source_reserved_amount_by_key
	)
	WorldData.city_haul_destination_reserved_amount_by_key = (
		haul_destination_reserved_amount_by_key
	)
	WorldData.next_city_haul_reservation_id = next_haul_reservation_id

	WorldData.city_citizens = citizens
	WorldData.city_citizen_index_by_id = citizen_index_by_id
	WorldData.city_citizen_ids_by_tile = citizen_ids_by_tile
	WorldData.city_active_mover_ids = active_mover_ids
	WorldData.city_active_mover_id_lookup = active_mover_id_lookup
	WorldData.city_citizen_movement_visual_events = citizen_movement_visual_events
	WorldData.city_citizen_movement_visual_tick_index = (
		citizen_movement_visual_tick_index
	)
	WorldData.city_active_task_ids = active_task_ids
	WorldData.city_active_task_id_lookup = active_task_id_lookup
	WorldData.city_object_access_tile_cache = object_access_tile_cache
	WorldData.next_city_citizen_id = next_citizen_id

	WorldData.city_object_version = object_version
	WorldData.city_container_version = container_version
	WorldData.city_public_storage_version = public_storage_version
	WorldData.city_citizen_version = citizen_version
	WorldData.city_citizen_spatial_version = citizen_spatial_version
	WorldData.city_citizen_movement_version = citizen_movement_version
	WorldData.city_citizen_task_version = citizen_task_version
	WorldData.city_assignment_version = assignment_version
	WorldData.city_workplace_version = workplace_version
	WorldData.city_ground_pile_version = ground_pile_version
	WorldData.city_haul_reservation_version = haul_reservation_version
	WorldData.city_construction_version = construction_version


func is_bound_to_world_data_workspace() -> bool:
	return (
		WorldData.city_objects == objects
		and WorldData.city_citizens == citizens
		and WorldData.city_ground_piles == ground_piles
		and WorldData.city_construction_sites == construction_sites
		and WorldData.city_work_orders == work_state.work_orders
		and WorldData.city_player_commands == work_state.player_commands
		and WorldData.city_haul_reservations == haul_reservations
	)
