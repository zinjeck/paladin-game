extends Node

var failure_count: int = 0

func _ready() -> void:
	WorldData.reset_runtime_session_state()
	_test_catalog_boundary()
	_test_registry_boundary()
	WorldData.reset_runtime_session_state()
	if failure_count > 0:
		push_error("WorldData boundary test failed: " + str(failure_count))
		get_tree().quit(1)
		return
	print("WorldData final boundary test passed.")
	get_tree().quit(0)

func _test_catalog_boundary() -> void:
	var house := CityObjectCatalog.get_city_object_definition(CityObjectCatalog.CITY_OBJECT_HOUSE)
	_expect(not house.is_empty(), "CityObjectCatalog must own object definitions.")
	_expect(CityObjectCatalog.get_city_object_size_for_type(CityObjectCatalog.CITY_OBJECT_HOUSE) == Vector2i(3, 3), "Object metadata must resolve outside WorldData.")
	_expect(CityObjectCatalog.get_city_object_resident_capacity({"type": CityObjectCatalog.CITY_OBJECT_HOUSE}) == 4, "Housing policy must resolve through CityObjectCatalog.")

func _test_registry_boundary() -> void:
	var culture := WorldData.create_culture("Pass 14 Culture")
	_expect(not culture.is_empty(), "World-level culture creation must remain available.")
	var citizen := CityCitizenRegistrySystem.add_city_citizen("", Vector2i(1, 1), CityCitizens.CITY_CITIZEN_SEX_MALE, int(culture.get("id", -1)))
	_expect(not citizen.is_empty(), "Citizen creation must resolve through CityCitizenRegistrySystem.")
	_expect(CityCitizenRegistrySystem.get_city_population_count() == 1, "Citizen registry owner must receive the new citizen.")

func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	failure_count += 1
	push_error("WorldData boundary test: " + message)
