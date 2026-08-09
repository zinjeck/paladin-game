extends RefCounted
class_name SettlementSimulationContext

# Runtime identity passed into settlement-scale simulation. Local mutable city
# state is carried explicitly so systems can migrate away from WorldData without
# changing how the world selects or identifies a settlement.

const BACKEND_NONE := "none"
const BACKEND_LEGACY_CITY_WORLD_DATA := "legacy_city_world_data"
const BACKEND_CITY_SETTLEMENT_STATE := "city_settlement_state"

var settlement_id: int = SettlementData.INVALID_SETTLEMENT_ID
var polity_id: int = PolityData.INVALID_POLITY_ID
var settlement_type: String = ""
var is_capital: bool = false
var backend_kind: String = BACKEND_NONE
var local_state = null


func _init(values: Dictionary = {}) -> void:
	settlement_id = int(
		values.get("settlement_id", SettlementData.INVALID_SETTLEMENT_ID)
	)
	polity_id = int(values.get("polity_id", PolityData.INVALID_POLITY_ID))
	settlement_type = str(values.get("settlement_type", ""))
	is_capital = bool(values.get("is_capital", false))
	backend_kind = str(values.get("backend_kind", BACKEND_NONE))
	local_state = values.get("local_state")


func is_valid() -> bool:
	return (
		settlement_id > 0
		and polity_id > 0
		and SettlementData.is_valid_settlement_type(settlement_type)
	)


func supports_city_simulation() -> bool:
	if not is_valid():
		return false
	if settlement_type != SettlementData.SETTLEMENT_TYPE_CITY:
		return false

	if backend_kind == BACKEND_CITY_SETTLEMENT_STATE:
		return local_state is CitySettlementSimulationState

	# Kept only as a compatibility backend for records created by the previous
	# foundation pass. New city settlements use BACKEND_CITY_SETTLEMENT_STATE.
	return backend_kind == BACKEND_LEGACY_CITY_WORLD_DATA


func has_instance_owned_city_state() -> bool:
	return (
		backend_kind == BACKEND_CITY_SETTLEMENT_STATE
		and local_state is CitySettlementSimulationState
	)


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
