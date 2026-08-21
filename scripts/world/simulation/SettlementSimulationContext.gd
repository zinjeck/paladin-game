extends RefCounted
class_name SettlementSimulationContext

const CityCitizenDecisionRuntimeStateScript = preload(
	"res://scripts/city/simulation/CityCitizenDecisionRuntimeState.gd"
)

# Runtime identity passed into settlement-scale simulation. Local mutable city
# state is carried explicitly and remains independent of world/session
# presentation selection.

const BACKEND_NONE := "none"
const BACKEND_CITY_SETTLEMENT_STATE := "city_settlement_state"

var settlement_id: int = SettlementData.INVALID_SETTLEMENT_ID
var polity_id: int = PolityData.INVALID_POLITY_ID
var settlement_type: String = ""
var is_capital: bool = false
var is_player_polity: bool = false
var backend_kind: String = BACKEND_NONE
var local_state = null


func _init(values: Dictionary = {}) -> void:
	settlement_id = int(
		values.get("settlement_id", SettlementData.INVALID_SETTLEMENT_ID)
	)
	polity_id = int(values.get("polity_id", PolityData.INVALID_POLITY_ID))
	settlement_type = str(values.get("settlement_type", ""))
	is_capital = bool(values.get("is_capital", false))
	is_player_polity = bool(values.get("is_player_polity", false))
	backend_kind = str(values.get("backend_kind", BACKEND_NONE))
	local_state = values.get("local_state")


func is_valid() -> bool:
	return (
		settlement_id > 0
		and polity_id > 0
		and SettlementData.is_valid_settlement_type(settlement_type)
	)


func supports_detailed_simulation() -> bool:
	if not is_valid():
		return false
	if settlement_type != SettlementData.SETTLEMENT_TYPE_CITY:
		return false

	return (
		backend_kind == BACKEND_CITY_SETTLEMENT_STATE
		and local_state is CitySettlementSimulationState
	)


func supports_city_simulation() -> bool:
	# Compatibility name for the only detailed backend currently implemented.
	# Callers choosing a presentation or simulation policy should use the
	# capability name above so adding another settlement backend does not make
	# "city" the universal dispatch contract.
	return supports_detailed_simulation()


func has_instance_owned_city_state() -> bool:
	return (
		backend_kind == BACKEND_CITY_SETTLEMENT_STATE
		and local_state is CitySettlementSimulationState
	)


func get_detailed_simulation_state():
	if not supports_detailed_simulation():
		return null
	return local_state


func get_city_simulation_state():
	if not has_instance_owned_city_state():
		return null
	return local_state


func is_city_founded() -> bool:
	var city_state = get_city_simulation_state()
	return city_state != null and city_state.is_city_founded()


func can_build_city_objects() -> bool:
	var city_state = get_city_simulation_state()
	return city_state != null and city_state.can_build_city_objects()


func get_primary_culture_id() -> int:
	var city_state = get_city_simulation_state()
	return city_state.get_primary_culture_id() if city_state != null else -1


func get_city_work_state():
	if not has_instance_owned_city_state():
		return null

	var raw_work_state = local_state.work_state
	if raw_work_state is CityWorkState:
		return raw_work_state
	return null


func get_city_object_state():
	if not has_instance_owned_city_state():
		return null

	var raw_object_state = local_state.object_state
	if raw_object_state is CityObjectState:
		return raw_object_state
	return null


func get_city_resource_accounting_state():
	if not has_instance_owned_city_state():
		return null

	var raw_resource_accounting_state = (
		local_state.resource_accounting_state
	)
	if raw_resource_accounting_state is CityResourceAccountingState:
		return raw_resource_accounting_state
	return null


func get_city_citizen_registry_state():
	if not has_instance_owned_city_state():
		return null

	var raw_citizen_registry_state = local_state.citizen_registry_state
	if raw_citizen_registry_state is CityCitizenRegistryState:
		return raw_citizen_registry_state
	return null


func get_city_citizen_spatial_state():
	if not has_instance_owned_city_state():
		return null

	var raw_citizen_spatial_state = local_state.citizen_spatial_state
	if raw_citizen_spatial_state is CityCitizenSpatialState:
		return raw_citizen_spatial_state
	return null


func get_city_citizen_movement_runtime_state():
	if not has_instance_owned_city_state():
		return null

	var raw_movement_runtime_state = (
		local_state.citizen_movement_runtime_state
	)
	if raw_movement_runtime_state is CityCitizenMovementRuntimeState:
		return raw_movement_runtime_state
	return null


func get_city_citizen_task_runtime_state():
	if not has_instance_owned_city_state():
		return null

	var raw_task_runtime_state = (
		local_state.citizen_task_runtime_state
	)
	if raw_task_runtime_state is CityCitizenTaskRuntimeState:
		return raw_task_runtime_state
	return null


func get_city_citizen_decision_runtime_state():
	if not has_instance_owned_city_state():
		return null

	var raw_decision_runtime_state = (
		local_state.citizen_decision_runtime_state
	)
	if raw_decision_runtime_state is CityCitizenDecisionRuntimeStateScript:
		return raw_decision_runtime_state
	return null
