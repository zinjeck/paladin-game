extends RefCounted
class_name SettlementData

# Intrinsic schema helpers for one persistent settlement identity. Local
# simulation state is intentionally not embedded here yet; the settlement
# context layer owns that boundary so city-state extraction can happen safely.

const INVALID_SETTLEMENT_ID: int = -1
const INVALID_POLITY_ID: int = -1
const INVALID_CITIZEN_ID: int = -1

const SETTLEMENT_TYPE_OUTPOST := "outpost"
const SETTLEMENT_TYPE_VILLAGE := "village"
const SETTLEMENT_TYPE_CITY := "city"

const VALID_SETTLEMENT_TYPES: Array[String] = [
	SETTLEMENT_TYPE_OUTPOST,
	SETTLEMENT_TYPE_VILLAGE,
	SETTLEMENT_TYPE_CITY,
]


static func normalize_name(settlement_name: String) -> String:
	return settlement_name.strip_edges()


static func is_valid_settlement_type(settlement_type: String) -> bool:
	return VALID_SETTLEMENT_TYPES.has(settlement_type)


static func make_settlement(values: Dictionary) -> Dictionary:
	var required_keys: Array[String] = [
		"id",
		"name",
		"settlement_type",
		"polity_id",
		"world_region_top_left",
		"world_region_center",
		"world_region_size",
	]

	for key in required_keys:
		if not values.has(key):
			push_error(
				"SettlementData.make_settlement is missing required key: "
				+ key
			)
			return {}

	if not values["id"] is int:
		push_error("SettlementData.make_settlement id must be an integer.")
		return {}
	if not values["name"] is String:
		push_error("SettlementData.make_settlement name must be a String.")
		return {}
	if not values["settlement_type"] is String:
		push_error(
			"SettlementData.make_settlement settlement_type must be a String."
		)
		return {}
	if not values["polity_id"] is int:
		push_error("SettlementData.make_settlement polity_id must be an integer.")
		return {}
	if not values["world_region_top_left"] is Vector2i:
		push_error(
			"SettlementData.make_settlement world_region_top_left must be Vector2i."
		)
		return {}
	if not values["world_region_center"] is Vector2i:
		push_error(
			"SettlementData.make_settlement world_region_center must be Vector2i."
		)
		return {}
	if not values["world_region_size"] is int:
		push_error(
			"SettlementData.make_settlement world_region_size must be an integer."
		)
		return {}

	var settlement_id: int = values["id"]
	var settlement_name := normalize_name(str(values["name"]))
	var settlement_type: String = values["settlement_type"]
	var polity_id: int = values["polity_id"]
	var world_region_size: int = values["world_region_size"]
	var parent_city_id := int(
		values.get("parent_city_id", INVALID_SETTLEMENT_ID)
	)
	var governor_citizen_id := int(
		values.get("governor_citizen_id", INVALID_CITIZEN_ID)
	)

	if settlement_id <= 0:
		push_error("SettlementData.make_settlement id must be positive.")
		return {}
	if settlement_name.is_empty():
		push_error("SettlementData.make_settlement name must not be blank.")
		return {}
	if not is_valid_settlement_type(settlement_type):
		push_error(
			"SettlementData.make_settlement received an unknown settlement type."
		)
		return {}
	if polity_id <= 0:
		push_error("SettlementData.make_settlement polity_id must be positive.")
		return {}
	if world_region_size <= 0:
		push_error(
			"SettlementData.make_settlement world_region_size must be positive."
		)
		return {}
	if parent_city_id != INVALID_SETTLEMENT_ID and parent_city_id <= 0:
		push_error(
			"SettlementData.make_settlement parent_city_id must be positive or invalid."
		)
		return {}
	if governor_citizen_id != INVALID_CITIZEN_ID and governor_citizen_id <= 0:
		push_error(
			"SettlementData.make_settlement governor_citizen_id must be positive or invalid."
		)
		return {}

	return {
		"id": settlement_id,
		"name": settlement_name,
		"settlement_type": settlement_type,
		"polity_id": polity_id,
		"world_region_top_left": values["world_region_top_left"],
		"world_region_center": values["world_region_center"],
		"world_region_size": world_region_size,
		"parent_city_id": parent_city_id,
		"governor_citizen_id": governor_citizen_id,
	}


static func is_valid_settlement_record(settlement: Dictionary) -> bool:
	if (
		not settlement.has("id")
		or not settlement["id"] is int
		or int(settlement["id"]) <= 0
	):
		return false
	if not settlement.has("name") or not settlement["name"] is String:
		return false
	if normalize_name(str(settlement["name"])).is_empty():
		return false
	if str(settlement["name"]) != normalize_name(str(settlement["name"])):
		return false
	if (
		not settlement.has("settlement_type")
		or not settlement["settlement_type"] is String
		or not is_valid_settlement_type(str(settlement["settlement_type"]))
	):
		return false
	if (
		not settlement.has("polity_id")
		or not settlement["polity_id"] is int
		or int(settlement["polity_id"]) <= 0
	):
		return false
	if not settlement.get("world_region_top_left") is Vector2i:
		return false
	if not settlement.get("world_region_center") is Vector2i:
		return false
	if (
		not settlement.get("world_region_size") is int
		or int(settlement["world_region_size"]) <= 0
	):
		return false

	var parent_city_id := int(
		settlement.get("parent_city_id", INVALID_SETTLEMENT_ID)
	)
	if parent_city_id != INVALID_SETTLEMENT_ID and parent_city_id <= 0:
		return false

	var governor_citizen_id := int(
		settlement.get("governor_citizen_id", INVALID_CITIZEN_ID)
	)
	return (
		governor_citizen_id == INVALID_CITIZEN_ID
		or governor_citizen_id > 0
	)
