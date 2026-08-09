extends RefCounted
class_name CityObjectState

# Settlement-owned mutable completed-object registry state for one CITY.
#
# This object owns only completed-object collections, indexes, occupancy,
# identity allocation, and the focused object change version. WorldData keeps
# the compatibility behavior surface during this ownership-only pass.
#
# Keep this class a small state container rather than a second simulation brain.

var objects: Array = []
var object_index_by_id: Dictionary = {}
var occupied_tiles: Dictionary = {}
var next_object_id: int = 1
var object_version: int = 0
