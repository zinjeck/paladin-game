extends RefCounted
class_name CultureData

# Intrinsic schema helpers for one culture record. WorldData owns the
# authoritative collection, stable IDs, indexes, and session lifecycle.

const INVALID_CULTURE_ID: int = -1


static func normalize_culture_name(culture_name: String) -> String:
	return culture_name.strip_edges()


static func is_valid_culture_name(culture_name: String) -> bool:
	return not normalize_culture_name(culture_name).is_empty()


static func make_culture(values: Dictionary) -> Dictionary:
	var required_keys: Array[String] = ["id", "name"]

	for key in required_keys:
		if not values.has(key):
			push_error(
				"CultureData.make_culture is missing required key: "
				+ key
			)
			return {}

	if not values["id"] is int:
		push_error("CultureData.make_culture id must be an integer.")
		return {}

	if not values["name"] is String:
		push_error("CultureData.make_culture name must be a String.")
		return {}

	var culture_id: int = values["id"]
	var raw_culture_name: String = values["name"]
	var culture_name := normalize_culture_name(raw_culture_name)

	if culture_id <= 0:
		push_error("CultureData.make_culture id must be positive.")
		return {}

	if not is_valid_culture_name(culture_name):
		push_error("CultureData.make_culture name must not be blank.")
		return {}

	return {
		"id": culture_id,
		"name": culture_name,
	}


static func is_valid_culture_record(culture: Dictionary) -> bool:
	if not culture.has("id") or not culture["id"] is int:
		return false

	if int(culture["id"]) <= 0:
		return false

	if not culture.has("name") or not culture["name"] is String:
		return false

	var culture_name: String = culture["name"]

	return (
		is_valid_culture_name(culture_name)
		and culture_name == normalize_culture_name(culture_name)
	)
