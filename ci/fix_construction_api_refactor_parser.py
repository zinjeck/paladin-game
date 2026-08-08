#!/usr/bin/env python3
from pathlib import Path

path = Path("ci/refactor_city_construction_api.py")
text = path.read_text(encoding="utf-8")
start = text.find("def top_level_block(")
end = text.find("\ndef remove_top_level_function", start)
if start < 0 or end < 0:
    raise SystemExit("Could not locate top_level_block helper")
replacement = '''def top_level_block(text: str, declaration_pattern: str) -> tuple[int, int, str]:
    match = re.search(declaration_pattern, text, re.MULTILINE)
    if not match:
        fail(f"missing expected declaration: {declaration_pattern}")
    start = match.start()
    first_end = text.find("\\n", start)
    if first_end < 0:
        return start, len(text), text[start:]

    first_line = text[start:first_end]
    paren_balance = first_line.count("(") - first_line.count(")")
    pos = first_end + 1
    while pos < len(text):
        next_end = text.find("\\n", pos)
        if next_end < 0:
            next_end = len(text)
        line = text[pos:next_end]

        # Multiline function/const declarations may close parentheses at column
        # zero. Those lines are part of the declaration, not the next top-level
        # block. Only treat a zero-indent line as a boundary after the opening
        # declaration's parentheses are balanced.
        if paren_balance <= 0 and line.strip() and not line[0].isspace():
            return start, pos, text[start:pos]

        paren_balance += line.count("(") - line.count(")")
        pos = next_end + 1

    return start, len(text), text[start:]

'''
text = text[:start] + replacement + text[end + 1:]
path.write_text(text, encoding="utf-8")
print("Fixed construction refactor multiline declaration parser.")
