#!/usr/bin/env python3
from pathlib import Path

path = Path(__file__).with_name("apply_topology_safety_pass.py")
text = path.read_text(encoding="utf-8")
old = '''    text = replace_once(
        text,
        "\\t\\tsite.is_empty()\\n"
        "\\t\\tor str(site.get(\\\"phase\\\", \\\"\\\"))\\n"
        "\\t\\t!= WorldData.CITY_CONSTRUCTION_PHASE_LABOR",
        "\\t\\tsite.is_empty()\\n"
        "\\t\\tor str(\\n"
        "\\t\\t\\tsite.get(\\\"finalization_state\\\", FINALIZATION_STATE_NONE)\\n"
        "\\t\\t) != FINALIZATION_STATE_NONE\\n"
        "\\t\\tor str(site.get(\\\"phase\\\", \\\"\\\"))\\n"
        "\\t\\t!= WorldData.CITY_CONSTRUCTION_PHASE_LABOR",
        "Construction labor finalization exclusion",
    )
'''
new = '''    text = regex_replace_once(
        text,
        r"(static func advance_labor_task\\(.*?\\n\\tif \\(\\n\\t\\tsite\\.is_empty\\(\\)\\n)"
        r"(\\t\\tor str\\(site\\.get\\(\\\"phase\\\", \\\"\\\"\\)\\)\\n)"
        r"(\\t\\t!= WorldData\\.CITY_CONSTRUCTION_PHASE_LABOR)",
        r"\\1"
        "\\t\\tor str(\\n"
        "\\t\\t\\tsite.get(\\\"finalization_state\\\", FINALIZATION_STATE_NONE)\\n"
        "\\t\\t) != FINALIZATION_STATE_NONE\\n"
        r"\\2\\3",
        "Construction labor finalization exclusion",
    )
'''
count = text.count(old)
if count != 1:
    raise RuntimeError(f"Expected one transformer block, found {count}")
path.write_text(text.replace(old, new, 1), encoding="utf-8")
print("Topology transformer repaired.")
