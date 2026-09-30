#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT
#
# Vendors the GraphLaw capability registry (schema graphlaw.capability-registry/1) into
# priv/graphlaw/: capability-registry.json, capability-registry.ttl, op-examples.json.
#
#   scripts/vendor_registry.sh [--check] [--from DIR]
#
# Source directory defaults to ../graphlaw/registry (override with --from DIR or the
# GRAPHLAW_REGISTRY_DIR environment variable). The registry digest is recomputed per the
# DIGEST RULE (canonical JSON: sorted keys, compact separators, raw UTF-8, integers only,
# "registry_sha256" key removed) and the copy is REFUSED when it differs from the
# registry_sha256 the file declares, or when surface_sha256 does not match the recomputed
# surface document. --check writes nothing: exit 1 when priv/graphlaw differs from the source.
set -euo pipefail
cd "$(dirname "$0")/.."

check=0
from="${GRAPHLAW_REGISTRY_DIR:-../graphlaw/registry}"
while [ $# -gt 0 ]; do
  case "$1" in
    --check) check=1 ;;
    --from) shift; [ $# -gt 0 ] || { echo "REFUSED(usage: --from needs DIR)" >&2; exit 2; }; from="$1" ;;
    --from=*) from="${1#--from=}" ;;
    -h|--help) sed -n '5,17p' "$0"; exit 0 ;;
    *) echo "REFUSED(usage: unknown argument $1)" >&2; exit 2 ;;
  esac
  shift
done

files="capability-registry.json capability-registry.ttl op-examples.json"
dest="priv/graphlaw"

for f in $files; do
  [ -f "$from/$f" ] || { echo "REFUSED(registry_source_absent: $from/$f)" >&2; exit 2; }
done

python3 - "$from/capability-registry.json" <<'PY'
import hashlib, json, sys

def canonical(v):
    return json.dumps(v, sort_keys=True, separators=(",", ":"), ensure_ascii=False)

def no_floats(v, path="$"):
    if isinstance(v, float):
        raise SystemExit("REFUSED(registry_float_value at %s)" % path)
    if isinstance(v, dict):
        for k, x in v.items():
            no_floats(x, path + "." + k)
    elif isinstance(v, list):
        for i, x in enumerate(v):
            no_floats(x, "%s[%d]" % (path, i))

def sha(v):
    return "sha256:" + hashlib.sha256(canonical(v).encode("utf-8")).hexdigest()

src = sys.argv[1]
with open(src, encoding="utf-8") as fh:
    doc = json.load(fh)
no_floats(doc)
if doc.get("schema") != "graphlaw.capability-registry/1":
    raise SystemExit("REFUSED(registry_schema: %r)" % doc.get("schema"))
declared = doc.get("registry_sha256")
body = {k: v for k, v in doc.items() if k != "registry_sha256"}
actual = sha(body)
if declared != actual:
    raise SystemExit("REFUSED(registry_digest_mismatch: declared %s computed %s)" % (declared, actual))
surface = {
    "abi_version": doc["abi_version"],
    "ops": [o["name"] for o in doc["ops"]],
    "other_dialects": [d["name"] for d in doc["other_dialects"]],
    "rdf_dialects": [d["name"] for d in doc["rdf_dialects"]],
}
if doc.get("surface_sha256") != sha(surface):
    raise SystemExit("REFUSED(surface_digest_mismatch: declared %s computed %s)" % (doc.get("surface_sha256"), sha(surface)))
print("registry digest ok: %s (%d ops)" % (actual, len(doc["ops"])))
PY

drift=0
for f in $files; do
  if [ "$check" -eq 1 ]; then
    if [ ! -f "$dest/$f" ]; then
      echo "DRIFT($dest/$f absent)" >&2; drift=1
    elif ! cmp -s "$from/$f" "$dest/$f"; then
      echo "DRIFT($dest/$f differs from $from/$f)" >&2; drift=1
    fi
  else
    mkdir -p "$dest"
    cp "$from/$f" "$dest/$f"
    echo "vendored $dest/$f"
  fi
done

if [ "$check" -eq 1 ]; then
  [ "$drift" -eq 0 ] || exit 1
  echo "vendor_registry --check: priv/graphlaw registry files match $from"
fi
