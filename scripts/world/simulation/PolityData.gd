extends RefCounted
class_name PolityData

# Intrinsic schema helpers for one polity record. Runtime registries and
# lifecycle live elsewhere so this type stays reusable by player and CPU
# polities alike.

const INVALID_POLITY_ID: int = -1
const INVALID_SETTLEMENT_ID: int = -1

const POLITY_TYPE_CHIEFDOM := "chiefdom"
const POLITY_TYPE_KINGDOM := "kingdom"
const POLITY_TYPE_EMPIRE := "empire"
const POLITY_TYPE_REPUBLIC := "republic"

const VALID_POLITY_TYPES: Array[String] = [
	POLITY_TYPE_CHIEFDOM,
	POLITY_TYPE_KINGDOM,
	POLITY_TYPE_EMPIRE,
	POLITY_TYPE_REPUBLIC,
]


static func normalize_name(polity_name: String) -> String:
	return polity_name.strip_edges()


static func is_valid_polity_type(polity_type: String) -> bool:
	return VALID_POLITY_TYPES.has(polity_type)


static func make_polity(values: Dictionary) -> Dictionary:
	var required_keys: Array[String] = [
		"id",
		"name",
		"polity_type",
		"primary_culture_id",
	]

	for key in required_keys:
		if not values.has(key):
			push_error(
				"PolityData.make_polity is missing required key: "
				+ key
			)
			return {}

	if not values["id"] is int:
		push_error("PolityData.make_polity id must be an integer.")
		return {}
	if not values["name"] is String:
		push_error("PolityData.make_polity name must be a String.")
		return {}
	if not values["polity_type"] is String:
		push_error("PolityData.make_polity polity_type must be a String.")
		return {}
	if not values["primary_culture_id"] is int:
		push_error("PolityData.make_polity primary_culture_id must be an integer.")
		return {}

	var polity_id: int = values["id"]
	var polity_name := normalize_name(str(values["name"]))
	var polity_type: String = values["polity_type"]
	var primary_culture_id: int = values["primary_culture_id"]
	var accepted_culture_ids := _normalize_positive_unique_ids(
		values.get("accepted_culture_ids", []),
		primary_culture_id
	)
	var settlement_ids := _normalize_positive_unique_ids(
		values.get("settlement_ids", []),
		INVALID_POLITY_ID
	)
	var capital_settlement_id := int(
		values.get("capital_settlement_id", INVALID_SETTLEMENT_ID)
	)

	if polity_id <= 0:
		push_error("PolityData.make_polity id must be positive.")
		return {}
	if polity_name.is_empty():
		push_error("PolityData.make_polity name must not be blank.")
		return {}
	if not is_valid_polity_type(polity_type):
		push_error("PolityData.make_polity received an unknown polity type.")
		return {}
	if primary_culture_id <= 0:
		push_error(
			"PolityData.make_polity primary_culture_id must be positive."
		)
		return {}
	if capital_settlement_id != INVALID_SETTLEMENT_ID:
		if capital_settlement_id <= 0:
			push_error(
				"PolityData.make_polity capital_settlement_id must be positive or invalid."
			)
			return {}
		if not settlement_ids.has(capital_settlement_id):
			push_error(
				"PolityData.make_polity capital must belong to settlement_ids."
			)
			return {}

	return {
		"id": polity_id,
		"name": polity_name,
		"polity_type": polity_type,
		"primary_culture_id": primary_culture_id,
		"accepted_culture_ids": accepted_culture_ids,
		"capital_settlement_id": capital_settlement_id,
		"settlement_ids": settlement_ids,
	}


static func is_valid_polity_record(polity: Dictionary) -> bool:
	if not polity.has("id") or not polity["id"] is int:
		return false
	if int(polity["id"]) <= 0:
		return false
	if not polity.has("name") or not polity["name"] is String:
		return false
	if normalize_name(str(polity["name"])).is_empty():
		return false
	if str(polity["name"]) != normalize_name(str(polity["name"])):
		return false
	if not polity.has("polity_type") or not polity["polity_type"] is String:
		return false
	if not is_valid_polity_type(str(polity["polity_type"])):
		return false
	if (
		not polity.has("primary_culture_id")
		or not polity["primary_culture_id"] is int
		or int(polity["primary_culture_id"]) <= 0
	):
		return false
	if not polity.get("accepted_culture_ids", []) is Array:
		return false
	if not polity.get("settlement_ids", []) is Array:
		return false

	var accepted_culture_ids := _normalize_positive_unique_ids(
		polity.get("accepted_culture_ids", []),
		int(polity["primary_culture_id"])
	)
	if accepted_culture_ids != polity.get("accepted_culture_ids", []):
		return false

	var settlement_ids := _normalize_positive_unique_ids(
		polity.get("settlement_ids", []),
		INVALID_POLITY_ID
	)
	if settlement_ids != polity.get("settlement_ids", []):
		return false

	var capital_settlement_id := int(
		polity.get("capital_settlement_id", INVALID_SETTLEMENT_ID)
	)
	if capital_settlement_id == INVALID_SETTLEMENT_ID:
		return true

	return (
		capital_settlement_id > 0
		and settlement_ids.has(capital_settlement_id)
	)


static func _normalize_positive_unique_ids(
	raw_ids,
	excluded_id: int
) -> Array[int]:
	var normalized_ids: Array[int] = []

	if not raw_ids is Array:
		return normalized_ids

	for raw_id in raw_ids:
		if not raw_id is int:
			continue

		var item_id: int = raw_id
		if item_id <= 0 or item_id == excluded_id:
			continue
		if normalized_ids.has(item_id):
			continue

		normalized_ids.append(item_id)

	return normalized_ids
