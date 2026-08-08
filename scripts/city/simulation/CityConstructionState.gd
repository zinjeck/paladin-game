extends RefCounted
class_name CityConstructionState

# Settlement-owned mutable construction registry state for one CITY.
#
# This object owns only construction-site collections, indexes, counters, and
# the focused construction change version. CityConstructionSystem owns the
# construction rules, queries, mutations, lifecycle, and scheduling behavior.
#
# Keep this class a small state container rather than a second simulation brain.

var construction_sites: Array = []
var construction_site_index_by_id: Dictionary = {}
var construction_site_id_by_tile: Dictionary = {}
var next_construction_site_id: int = 1
var construction_version: int = 0
