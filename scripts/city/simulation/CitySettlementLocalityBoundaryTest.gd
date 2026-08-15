extends Node

const FORBIDDEN_LOCAL_RESOLUTION_TOKENS := [
	"WorldPoliticalState.active_settlement_id",
	"WorldPoliticalState.get_active_settlement(",
	"WorldPoliticalState.get_active_city_simulation_state(",
	"WorldPoliticalState.get_current_city_",
	".get_current_state(",
	"CityWorkSystem.get_current_work_state(",
	"WorldData.has_active_city_save(",
	"WorldData.store_city_world_save(",
	"WorldData.reset_player_city_state(",
]

# Ratchet entries describe only legacy production call sites that exist on the
# baseline when this guard is introduced. Later locality passes must delete
# entries as they remove the corresponding compatibility path. New entries are
# not permitted as a way to make new implicit settlement resolution pass CI.
#
# Key format: res://path::function_or_property::forbidden_token
# Value fields:
#   max_count: exact number of legacy references allowed in that scope
#   reason: why this legacy path still exists temporarily
#   remove_in: the planned localization PR that removes it
const LEGACY_ALLOWLIST := {
}

var failure_count: int = 0


func _ready() -> void:
	_test_guard_behavior()
	_test_production_locality_boundary()

	if failure_count > 0:
		push_error(
			"City settlement locality boundary test failed: "
			+ str(failure_count)
		)
		get_tree().quit(1)
		return

	print("City settlement locality boundary test passed.")
	get_tree().quit(0)


func _test_guard_behavior() -> void:
	var ordinary_source := (
		"func legacy_reader() -> void:\n"
		+ "\tvar state = WorldPoliticalState.get_active_city_simulation_state()\n"
	)
	var ordinary_key := _make_allowlist_key(
		"res://synthetic.gd",
		"legacy_reader",
		"WorldPoliticalState.get_active_city_simulation_state("
	)
	var allowlisted := {
		ordinary_key: {
			"max_count": 1,
			"reason": "Synthetic legacy compatibility path.",
			"remove_in": "guard-self-test",
		},
	}
	_expect(
		_scan_source("res://synthetic.gd", ordinary_source, {}).size() == 1,
		"A synthetic forbidden reference must be detected by default."
	)
	_expect(
		_scan_source("res://synthetic.gd", ordinary_source, allowlisted).is_empty(),
		"An exact documented legacy allowlist entry must be accepted."
	)
	_expect(
		_scan_source("res://synthetic.gd", ordinary_source, {}).size() == 1,
		"Removing an allowlist entry while the source remains must fail."
	)

	var explicit_source := (
		"func run_tick_for_city_state(city_state) -> void:\n"
		+ "\tvar state = WorldPoliticalState.get_active_city_simulation_state()\n"
	)
	var explicit_key := _make_allowlist_key(
		"res://explicit.gd",
		"run_tick_for_city_state",
		"WorldPoliticalState.get_active_city_simulation_state("
	)
	var explicit_allowlist := {
		explicit_key: {
			"max_count": 1,
			"reason": "This must never be honored.",
			"remove_in": "guard-self-test",
		},
	}
	_expect(
		_scan_source(
			"res://explicit.gd",
			explicit_source,
			explicit_allowlist
		).size() == 1,
		"Explicit-target functions must not be allowlistable around implicit state."
	)

	var inert_source := (
		"func harmless() -> void:\n"
		+ "\t# WorldPoliticalState.active_settlement_id\n"
		+ "\tvar example = \"WorldPoliticalState.get_current_city_world()\"\n"
	)
	_expect(
		_scan_source("res://inert.gd", inert_source, {}).is_empty(),
		"Comments and string literals must not create locality false positives."
	)


func _test_production_locality_boundary() -> void:
	var gdscript_paths: Array[String] = []
	_collect_production_gdscript_paths("res://scripts", gdscript_paths)
	gdscript_paths.sort()
	_expect(
		not gdscript_paths.is_empty(),
		"The locality guard must discover production GDScript under res://scripts."
	)
	if gdscript_paths.is_empty():
		return

	var used_allowlist_counts: Dictionary = {}
	for path in gdscript_paths:
		var source := _read_text(path)
		if source.is_empty():
			continue
		var violations := _scan_source(path, source, LEGACY_ALLOWLIST)
		for violation in violations:
			push_error("LOCALITY_GUARD: " + str(violation))
			failure_count += 1
		_record_used_allowlist_entries(path, source, used_allowlist_counts)

	for key in LEGACY_ALLOWLIST.keys():
		var expected_count := int(
			Dictionary(LEGACY_ALLOWLIST[key]).get("max_count", 0)
		)
		var actual_count := int(used_allowlist_counts.get(key, 0))
		if actual_count != expected_count:
			push_error(
				"LOCALITY_GUARD_STALE_ALLOWLIST: %s expected=%d actual=%d. "
				% [str(key), expected_count, actual_count]
				+ "Shrink or correct the ratchet instead of preserving dead entries."
			)
			failure_count += 1


func _scan_source(
	path: String,
	source: String,
	allowlist: Dictionary
) -> Array[String]:
	var sanitized := _strip_comments_and_strings(source)
	var lines := sanitized.split("\n")
	var current_scope := "<top-level>"
	var occurrence_counts: Dictionary = {}
	var violation_messages: Array[String] = []

	for line_index in range(lines.size()):
		var line := str(lines[line_index])
		var discovered_scope := _get_declared_function_name(line)
		if not discovered_scope.is_empty():
			current_scope = discovered_scope

		for token in FORBIDDEN_LOCAL_RESOLUTION_TOKENS:
			var search_from := 0
			while true:
				var found_at := line.find(token, search_from)
				if found_at < 0:
					break
				var key := _make_allowlist_key(path, current_scope, token)
				occurrence_counts[key] = int(occurrence_counts.get(key, 0)) + 1
				var explicit_target := _is_explicit_target_scope(current_scope)
				var entry: Dictionary = allowlist.get(key, {})
				var max_count := int(entry.get("max_count", 0))
				var occurrence_number := int(occurrence_counts[key])
				if explicit_target:
					violation_messages.append(
						"%s:%d explicit-target function %s reads implicit local authority via %s"
						% [path, line_index + 1, current_scope, token]
					)
				elif entry.is_empty() or occurrence_number > max_count:
					violation_messages.append(
						"%s:%d unallowlisted implicit local authority in %s via %s (key=%s occurrence=%d)"
						% [
							path,
							line_index + 1,
							current_scope,
							token,
							key,
							occurrence_number,
						]
					)
				search_from = found_at + token.length()

	return violation_messages


func _record_used_allowlist_entries(
	path: String,
	source: String,
	used_counts: Dictionary
) -> void:
	var sanitized := _strip_comments_and_strings(source)
	var lines := sanitized.split("\n")
	var current_scope := "<top-level>"
	for line in lines:
		var discovered_scope := _get_declared_function_name(str(line))
		if not discovered_scope.is_empty():
			current_scope = discovered_scope
		for token in FORBIDDEN_LOCAL_RESOLUTION_TOKENS:
			var search_from := 0
			while true:
				var found_at := str(line).find(token, search_from)
				if found_at < 0:
					break
				var key := _make_allowlist_key(path, current_scope, token)
				if LEGACY_ALLOWLIST.has(key):
					used_counts[key] = int(used_counts.get(key, 0)) + 1
				search_from = found_at + token.length()


func _collect_production_gdscript_paths(
	directory_path: String,
	output: Array[String]
) -> void:
	var directory := DirAccess.open(directory_path)
	if directory == null:
		push_error("Unable to scan locality boundary directory: " + directory_path)
		failure_count += 1
		return

	directory.list_dir_begin()
	var entry_name := directory.get_next()
	while not entry_name.is_empty():
		if entry_name == "." or entry_name == "..":
			entry_name = directory.get_next()
			continue
		var entry_path := directory_path.path_join(entry_name)
		if directory.current_is_dir():
			_collect_production_gdscript_paths(entry_path, output)
		elif (
			entry_name.ends_with(".gd")
			and not entry_name.ends_with("Test.gd")
		):
			output.append(entry_path)
		entry_name = directory.get_next()
	directory.list_dir_end()


func _strip_comments_and_strings(source: String) -> String:
	var output := ""
	var in_string := false
	var quote := ""
	var escaped := false
	var index := 0
	while index < source.length():
		var character := source.substr(index, 1)
		if in_string:
			if character == "\n":
				output += "\n"
			else:
				output += " "
			if escaped:
				escaped = false
			elif character == "\\":
				escaped = true
			elif character == quote:
				in_string = false
				quote = ""
			index += 1
			continue

		if character == "\"" or character == "'":
			in_string = true
			quote = character
			output += " "
			index += 1
			continue
		if character == "#":
			while index < source.length() and source.substr(index, 1) != "\n":
				output += " "
				index += 1
			continue
		output += character
		index += 1
	return output


func _get_declared_function_name(line: String) -> String:
	var stripped := line.strip_edges()
	var marker := "func "
	var marker_index := stripped.find(marker)
	if marker_index < 0:
		return ""
	if marker_index > 0 and not stripped.begins_with("static func "):
		return ""
	var name_start := marker_index + marker.length()
	var paren_index := stripped.find("(", name_start)
	if paren_index < 0:
		return ""
	return stripped.substr(name_start, paren_index - name_start).strip_edges()


func _is_explicit_target_scope(scope_name: String) -> bool:
	return (
		scope_name.contains("_for_city_state")
		or scope_name.contains("_for_settlement")
		or scope_name.contains("_for_context")
	)


func _make_allowlist_key(path: String, scope_name: String, token: String) -> String:
	return path + "::" + scope_name + "::" + token


func _read_text(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Unable to read locality boundary source file: " + path)
		failure_count += 1
		return ""
	return file.get_as_text()


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	failure_count += 1
	push_error(message)
