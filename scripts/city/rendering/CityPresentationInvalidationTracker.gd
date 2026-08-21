extends RefCounted
class_name CityPresentationInvalidationTracker

# Non-authoritative presentation observations for one exact renderer binding.
# This tracker retains owner identities and version numbers only. It never
# copies or mutates settlement gameplay data.

var presentation_binding: CityPresentationBinding
var binding_generation: int = 0
var highest_accepted_binding_generation: int = 0

var observed_city_object_state: CityObjectState
var observed_city_object_version: int = -1
var observed_city_resource_accounting_state: CityResourceAccountingState
var observed_city_container_version: int = -1
var observed_city_public_storage_version: int = -1
var observed_city_citizen_registry_state: CityCitizenRegistryState
var observed_city_citizen_version: int = -1
var observed_city_citizen_spatial_state: CityCitizenSpatialState
var observed_city_citizen_spatial_version: int = -1
var observed_city_citizen_movement_runtime_state: CityCitizenMovementRuntimeState
var observed_city_citizen_movement_version: int = -1
var observed_city_citizen_task_runtime_state: CityCitizenTaskRuntimeState
var observed_city_citizen_task_version: int = -1
var observed_city_logistics_state: CityLogisticsState
var observed_city_ground_pile_version: int = -1
var observed_city_haul_reservation_version: int = -1
var observed_city_work_state: CityWorkState
var observed_city_player_command_version: int = -1
var observed_city_construction_state: CityConstructionState
var observed_city_construction_version: int = -1
var observed_city_assignment_state: CityAssignmentState
var observed_city_assignment_version: int = -1
var observed_city_workplace_state: CityWorkplaceState
var observed_city_workplace_version: int = -1
var observed_city_tile_data_version: int = -1
var observed_city_surface_feature_change_version: int = -1


func rebind_city_presentation(binding: CityPresentationBinding) -> bool:
	if not can_rebind_city_presentation(binding):
		return false

	presentation_binding = binding
	binding_generation = binding.generation
	highest_accepted_binding_generation = binding.generation
	reset_observations()
	return true


func can_rebind_city_presentation(binding: CityPresentationBinding) -> bool:
	return (
		binding != null
		and binding.is_valid()
		and binding.generation > highest_accepted_binding_generation
	)


func reset() -> void:
	presentation_binding = null
	binding_generation = 0
	reset_observations()


func reset_observations() -> void:
	observed_city_object_state = null
	observed_city_object_version = -1
	observed_city_resource_accounting_state = null
	observed_city_container_version = -1
	observed_city_public_storage_version = -1
	observed_city_citizen_registry_state = null
	observed_city_citizen_version = -1
	observed_city_citizen_spatial_state = null
	observed_city_citizen_spatial_version = -1
	observed_city_citizen_movement_runtime_state = null
	observed_city_citizen_movement_version = -1
	observed_city_citizen_task_runtime_state = null
	observed_city_citizen_task_version = -1
	observed_city_logistics_state = null
	observed_city_ground_pile_version = -1
	observed_city_haul_reservation_version = -1
	observed_city_work_state = null
	observed_city_player_command_version = -1
	observed_city_construction_state = null
	observed_city_construction_version = -1
	observed_city_assignment_state = null
	observed_city_assignment_version = -1
	observed_city_workplace_state = null
	observed_city_workplace_version = -1
	observed_city_tile_data_version = -1
	observed_city_surface_feature_change_version = -1


func is_bound_to_city_presentation(binding: CityPresentationBinding) -> bool:
	return (
		presentation_binding != null
		and binding != null
		and binding_generation == binding.generation
		and presentation_binding.matches_binding(binding)
	)


func accepts_generation(generation: int) -> bool:
	return (
		generation > 0
		and generation == binding_generation
		and presentation_binding != null
		and presentation_binding.generation == generation
		and presentation_binding.is_valid()
	)


func capture_current_versions(generation: int) -> bool:
	if not accepts_generation(generation):
		return false

	var city_state: CitySettlementSimulationState = (
		presentation_binding.city_state
	)
	var city_world: WorldData = presentation_binding.city_world
	observed_city_object_state = city_state.object_state
	observed_city_object_version = city_state.object_state.object_version
	observed_city_resource_accounting_state = city_state.resource_accounting_state
	observed_city_container_version = (
		city_state.resource_accounting_state.container_version
	)
	observed_city_public_storage_version = (
		city_state.resource_accounting_state.public_storage_version
	)
	observed_city_citizen_registry_state = city_state.citizen_registry_state
	observed_city_citizen_version = (
		city_state.citizen_registry_state.citizen_version
	)
	observed_city_citizen_spatial_state = city_state.citizen_spatial_state
	observed_city_citizen_spatial_version = (
		city_state.citizen_spatial_state.citizen_spatial_version
	)
	observed_city_citizen_movement_runtime_state = (
		city_state.citizen_movement_runtime_state
	)
	observed_city_citizen_movement_version = (
		city_state.citizen_movement_runtime_state.citizen_movement_version
	)
	observed_city_citizen_task_runtime_state = (
		city_state.citizen_task_runtime_state
	)
	observed_city_citizen_task_version = (
		city_state.citizen_task_runtime_state.citizen_task_version
	)
	observed_city_logistics_state = city_state.logistics_state
	observed_city_ground_pile_version = (
		city_state.logistics_state.ground_pile_version
	)
	observed_city_haul_reservation_version = (
		city_state.logistics_state.haul_reservation_version
	)
	observed_city_work_state = city_state.work_state
	observed_city_player_command_version = (
		city_state.work_state.player_command_version
	)
	observed_city_construction_state = city_state.construction_state
	observed_city_construction_version = (
		city_state.construction_state.construction_version
	)
	observed_city_assignment_state = city_state.assignment_state
	observed_city_assignment_version = (
		city_state.assignment_state.assignment_version
	)
	observed_city_workplace_state = city_state.workplace_state
	observed_city_workplace_version = (
		city_state.workplace_state.workplace_version
	)
	observed_city_tile_data_version = city_world.tile_data_version
	observed_city_surface_feature_change_version = (
		city_world.city_surface_feature_change_version
	)
	return true


func create_change_flags() -> Dictionary:
	return {
		"city_objects_changed": false,
		"city_containers_changed": false,
		"public_storage_changed": false,
		"city_citizens_changed": false,
		"city_citizen_registry_changed": false,
		"city_citizen_spatial_changed": false,
		"city_citizen_movement_changed": false,
		"city_citizen_movement_runtime_changed": false,
		"city_citizen_task_changed": false,
		"city_citizen_task_runtime_changed": false,
		"city_ground_piles_changed": false,
		"city_player_commands_changed": false,
		"city_haul_reservations_changed": false,
		"city_construction_changed": false,
		"city_assignments_changed": false,
		"city_workplaces_changed": false,
		"city_tile_data_changed": false,
		"city_surface_features_changed": false,
	}


func collect_city_world_version_change_flags(
	generation: int,
	change_flags: Dictionary
) -> bool:
	if not accepts_generation(generation):
		return false

	var city_world: WorldData = presentation_binding.city_world
	if observed_city_tile_data_version != city_world.tile_data_version:
		observed_city_tile_data_version = city_world.tile_data_version
		observed_city_surface_feature_change_version = (
			city_world.city_surface_feature_change_version
		)
		change_flags["city_tile_data_changed"] = true
		return true

	if (
		observed_city_surface_feature_change_version
		== city_world.city_surface_feature_change_version
	):
		return true

	observed_city_surface_feature_change_version = (
		city_world.city_surface_feature_change_version
	)
	change_flags["city_surface_features_changed"] = true
	return true


func collect_city_state_change_flags(
	generation: int,
	change_flags: Dictionary
) -> bool:
	if not accepts_generation(generation):
		return false

	var city_state: CitySettlementSimulationState = (
		presentation_binding.city_state
	)
	_collect_object_change_flags(city_state, change_flags)
	_collect_resource_change_flags(city_state, change_flags)
	_collect_citizen_change_flags(city_state, change_flags)
	_collect_command_and_construction_change_flags(city_state, change_flags)
	_collect_assignment_and_workplace_change_flags(city_state, change_flags)
	return true


func _collect_object_change_flags(
	city_state: CitySettlementSimulationState,
	change_flags: Dictionary
) -> void:
	var current_state: CityObjectState = city_state.object_state
	var owner_changed := (
		observed_city_object_state == null
		or not is_same(observed_city_object_state, current_state)
	)
	if owner_changed or observed_city_object_version != current_state.object_version:
		observed_city_object_state = current_state
		observed_city_object_version = current_state.object_version
		change_flags["city_objects_changed"] = true


func _collect_resource_change_flags(
	city_state: CitySettlementSimulationState,
	change_flags: Dictionary
) -> void:
	var current_state: CityResourceAccountingState = (
		city_state.resource_accounting_state
	)
	var owner_changed := (
		observed_city_resource_accounting_state == null
		or not is_same(observed_city_resource_accounting_state, current_state)
	)
	if owner_changed or observed_city_container_version != current_state.container_version:
		observed_city_container_version = current_state.container_version
		change_flags["city_containers_changed"] = true
	if (
		owner_changed
		or observed_city_public_storage_version
		!= current_state.public_storage_version
	):
		observed_city_public_storage_version = current_state.public_storage_version
		change_flags["public_storage_changed"] = true
	observed_city_resource_accounting_state = current_state


func _collect_citizen_change_flags(
	city_state: CitySettlementSimulationState,
	change_flags: Dictionary
) -> void:
	var registry_state: CityCitizenRegistryState = city_state.citizen_registry_state
	var registry_owner_changed := (
		observed_city_citizen_registry_state == null
		or not is_same(observed_city_citizen_registry_state, registry_state)
	)
	if (
		registry_owner_changed
		or observed_city_citizen_version != registry_state.citizen_version
	):
		observed_city_citizen_registry_state = registry_state
		observed_city_citizen_version = registry_state.citizen_version
		change_flags["city_citizens_changed"] = true
		change_flags["city_citizen_registry_changed"] = registry_owner_changed

	var spatial_state: CityCitizenSpatialState = city_state.citizen_spatial_state
	var spatial_owner_changed := (
		observed_city_citizen_spatial_state == null
		or not is_same(observed_city_citizen_spatial_state, spatial_state)
	)
	if (
		spatial_owner_changed
		or observed_city_citizen_spatial_version
		!= spatial_state.citizen_spatial_version
	):
		observed_city_citizen_spatial_state = spatial_state
		observed_city_citizen_spatial_version = spatial_state.citizen_spatial_version
		change_flags["city_citizen_spatial_changed"] = true

	var movement_state: CityCitizenMovementRuntimeState = (
		city_state.citizen_movement_runtime_state
	)
	var movement_owner_changed := (
		observed_city_citizen_movement_runtime_state == null
		or not is_same(
			observed_city_citizen_movement_runtime_state,
			movement_state
		)
	)
	if (
		movement_owner_changed
		or observed_city_citizen_movement_version
		!= movement_state.citizen_movement_version
	):
		observed_city_citizen_movement_runtime_state = movement_state
		observed_city_citizen_movement_version = (
			movement_state.citizen_movement_version
		)
		change_flags["city_citizen_movement_changed"] = true
		change_flags["city_citizen_movement_runtime_changed"] = (
			movement_owner_changed
		)

	var task_state: CityCitizenTaskRuntimeState = (
		city_state.citizen_task_runtime_state
	)
	var task_owner_changed := (
		observed_city_citizen_task_runtime_state == null
		or not is_same(observed_city_citizen_task_runtime_state, task_state)
	)
	if (
		task_owner_changed
		or observed_city_citizen_task_version
		!= task_state.citizen_task_version
	):
		observed_city_citizen_task_runtime_state = task_state
		observed_city_citizen_task_version = task_state.citizen_task_version
		change_flags["city_citizen_task_changed"] = true
		change_flags["city_citizen_task_runtime_changed"] = task_owner_changed


func _collect_command_and_construction_change_flags(
	city_state: CitySettlementSimulationState,
	change_flags: Dictionary
) -> void:
	var logistics_state: CityLogisticsState = city_state.logistics_state
	var logistics_owner_changed := (
		observed_city_logistics_state == null
		or not is_same(observed_city_logistics_state, logistics_state)
	)
	if (
		logistics_owner_changed
		or observed_city_ground_pile_version != logistics_state.ground_pile_version
	):
		observed_city_ground_pile_version = logistics_state.ground_pile_version
		change_flags["city_ground_piles_changed"] = true
	if (
		logistics_owner_changed
		or observed_city_haul_reservation_version
		!= logistics_state.haul_reservation_version
	):
		observed_city_haul_reservation_version = (
			logistics_state.haul_reservation_version
		)
		change_flags["city_haul_reservations_changed"] = true
	observed_city_logistics_state = logistics_state

	var work_state: CityWorkState = city_state.work_state
	var work_owner_changed := (
		observed_city_work_state == null
		or not is_same(observed_city_work_state, work_state)
	)
	if (
		work_owner_changed
		or observed_city_player_command_version != work_state.player_command_version
	):
		observed_city_player_command_version = work_state.player_command_version
		change_flags["city_player_commands_changed"] = true
	observed_city_work_state = work_state

	var construction_state: CityConstructionState = city_state.construction_state
	var construction_owner_changed := (
		observed_city_construction_state == null
		or not is_same(observed_city_construction_state, construction_state)
	)
	if (
		construction_owner_changed
		or observed_city_construction_version
		!= construction_state.construction_version
	):
		observed_city_construction_version = construction_state.construction_version
		change_flags["city_construction_changed"] = true
	observed_city_construction_state = construction_state


func _collect_assignment_and_workplace_change_flags(
	city_state: CitySettlementSimulationState,
	change_flags: Dictionary
) -> void:
	var assignment_state: CityAssignmentState = city_state.assignment_state
	var assignment_owner_changed := (
		observed_city_assignment_state == null
		or not is_same(observed_city_assignment_state, assignment_state)
	)
	if (
		assignment_owner_changed
		or observed_city_assignment_version != assignment_state.assignment_version
	):
		observed_city_assignment_state = assignment_state
		observed_city_assignment_version = assignment_state.assignment_version
		change_flags["city_assignments_changed"] = true

	var workplace_state: CityWorkplaceState = city_state.workplace_state
	var workplace_owner_changed := (
		observed_city_workplace_state == null
		or not is_same(observed_city_workplace_state, workplace_state)
	)
	if (
		workplace_owner_changed
		or observed_city_workplace_version != workplace_state.workplace_version
	):
		observed_city_workplace_state = workplace_state
		observed_city_workplace_version = workplace_state.workplace_version
		change_flags["city_workplaces_changed"] = true
