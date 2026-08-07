extends RefCounted
class_name SettlementSimulationContext

# Runtime identity passed into settlement-scale simulation. The backend kind is
# explicit so the current global city state can be adapted today and replaced
# by per-settlement state later without changing the world-facing contract.

const BACKEND_NONE := "none"
const BACKEND_LEGACY_CITY_WORLD_DATA := "legacy_city_world_data"

var settlement_id: int = SettlementData.INVALID_SETTLEMENT_ID
var polity_id: int = PolityData.INVALID_POLITY_ID
var settlement_type: String = ""
var is_capital: bool = false
var backend_kind: String = BACKEND_NONE


func _init(values: Dictionary = {}) -> void:
	settlement_id = int(
		values.get("settlement_id", SettlementData.INVALID_SETTLEMENT_ID)
	)
	polity_id = int(values.get("polity_id", PolityData.INVALID_POLITY_ID))
	settlement_type = str(values.get("settlement_type", ""))
	is_capital = bool(values.get("is_capital", false))
	backend_kind = str(values.get("backend_kind", BACKEND_NONE))


func is_valid() -> bool:
	return (
		settlement_id > 0
		and polity_id > 0
		and SettlementData.is_valid_settlement_type(settlement_type)
		and backend_kind != BACKEND_NONE
	)


func supports_city_simulation() -> bool:
	return (
		is_valid()
		and settlement_type == SettlementData.SETTLEMENT_TYPE_CITY
		and backend_kind == BACKEND_LEGACY_CITY_WORLD_DATA
	)
