from __future__ import annotations

import base64
import gzip
import hashlib
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PATCH_SHA256 = "1731f4c4651e979741a8dfa4470c28cac7f3827226c6002db35142a71a3ad362"
payload = (ROOT / "ci" / "compile_fix_payload.txt").read_text(encoding="utf-8").strip()
patch = gzip.decompress(base64.b64decode(payload))
actual_sha256 = hashlib.sha256(patch).hexdigest()

if actual_sha256 != PATCH_SHA256:
    raise RuntimeError(
        "Compile fix checksum mismatch: "
        f"expected {PATCH_SHA256}, got {actual_sha256}"
    )

patch_path = ROOT / "ci" / ".compile_fix.patch"
patch_path.write_bytes(patch)

try:
    subprocess.run(
        ["git", "apply", "--check", str(patch_path)],
        cwd=ROOT,
        check=True,
    )
    subprocess.run(
        ["git", "apply", str(patch_path)],
        cwd=ROOT,
        check=True,
    )
finally:
    patch_path.unlink(missing_ok=True)

print("Applied compile fixes.")
