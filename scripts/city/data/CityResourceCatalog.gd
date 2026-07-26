extends RefCounted
class_name CityResourceCatalog

# Resource identity, display order, and food values live here so simulation,
# rendering, and validation share one immutable catalog.
const RESOURCE_NONE := "none"
const RESOURCE_IRON := "iron"
const RESOURCE_COAL := "coal"
const RESOURCE_GOLD := "gold"
const RESOURCE_FISH := "fish"
const RESOURCE_MEAT := "meat"
const RESOURCE_LUMBER := "lumber"
const RESOURCE_STONE := "stone"

const CITY_FOOD_HUNGER_RESTORE_BY_RESOURCE := {
	RESOURCE_FISH: 40,
	RESOURCE_MEAT: 40,
}

static var _city_resource_types: Array[String] = [
	RESOURCE_FISH,
	RESOURCE_MEAT,
	RESOURCE_LUMBER,
	RESOURCE_STONE,
	RESOURCE_COAL,
	RESOURCE_IRON,
	RESOURCE_GOLD,
]
static var _city_food_resource_types: Array[String] = [
	RESOURCE_FISH,
	RESOURCE_MEAT,
]
static var _city_resource_type_lookup: Dictionary = {
	RESOURCE_FISH: true,
	RESOURCE_MEAT: true,
	RESOURCE_LUMBER: true,
	RESOURCE_STONE: true,
	RESOURCE_COAL: true,
	RESOURCE_IRON: true,
	RESOURCE_GOLD: true,
}


static func get_city_resource_types() -> Array[String]:
	return _city_resource_types.duplicate()


static func get_city_food_resource_types() -> Array[String]:
	return _city_food_resource_types.duplicate()


static func is_city_resource_type(resource: String) -> bool:
	return _city_resource_type_lookup.has(resource)


static func get_city_food_hunger_restore(resource: String) -> int:
	return maxi(
		int(CITY_FOOD_HUNGER_RESTORE_BY_RESOURCE.get(resource, 0)),
		0
	)
