from __future__ import annotations

import base64
import gzip
import hashlib
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PAYLOAD_DIR = ROOT / "ci" / "persistent_session_payload"
EXPECTED_SHA256 = "da360e369fe197171509804048f17a8686fa08fb37c772dee581ff719487b7d4"

parts = sorted(PAYLOAD_DIR.glob("part*.txt"))
if len(parts) != 2:
    raise RuntimeError(f"Expected 2 payload parts, found {len(parts)}")

encoded = "".join(part.read_text(encoding="utf-8").strip() for part in parts)
patch = gzip.decompress(base64.b64decode(encoded))
actual_sha256 = hashlib.sha256(patch).hexdigest()
if actual_sha256 != EXPECTED_SHA256:
    raise RuntimeError(
        f"Patch checksum mismatch: expected {EXPECTED_SHA256}, got {actual_sha256}"
    )

patch_path = ROOT / "ci" / ".persistent_session.patch"
patch_path.write_bytes(patch)
try:
    subprocess.run(["git", "apply", "--check", str(patch_path)], cwd=ROOT, check=True)
    subprocess.run(["git", "apply", str(patch_path)], cwd=ROOT, check=True)
finally:
    patch_path.unlink(missing_ok=True)

print("Applied persistent world/city session and atomic map-cache patch.")
