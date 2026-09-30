#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT
#
# Splices the vendored GraphLaw capability registry into ontology.ttl.
#
#   scripts/import_registry.sh [--check]
#
# The statements of priv/graphlaw/capability-registry.ttl (prefix lines dropped; the gac:
# prefix is declared once in the ontology.ttl header) go between the marker lines
#   # BEGIN GENERATED-REGISTRY sha256:<registry_sha256>
#   # END GENERATED-REGISTRY
# When the markers are absent the block is appended at the end of the file. The
# glx:registrySha256 literal on glx:AshGraphLawProject is rewritten to the same digest.
# The digest is recomputed from priv/graphlaw/capability-registry.json (DIGEST RULE); the
# import is REFUSED when it differs from the file's declared registry_sha256. Idempotent.
# --check writes nothing: exit 1 when ontology.ttl differs from the expected result.
set -euo pipefail
cd "$(dirname "$0")/.."

check=0
case "${1:-}" in
  "") ;;
  --check) check=1 ;;
  -h|--help) sed -n '5,17p' "$0"; exit 0 ;;
  *) echo "REFUSED(usage: unknown argument $1)" >&2; exit 2 ;;
esac

json="${GRAPHLAW_REGISTRY_JSON:-priv/graphlaw/capability-registry.json}"
ttl="${GRAPHLAW_REGISTRY_TTL:-priv/graphlaw/capability-registry.ttl}"
onto="${ONTOLOGY_TTL:-ontology.ttl}"
for f in "$json" "$ttl" "$onto"; do
  [ -f "$f" ] || { echo "REFUSED(import_input_absent: $f)" >&2; exit 2; }
done

python3 - "$json" "$ttl" "$onto" "$check" <<'PY'
import hashlib, json, re, sys

json_path, ttl_path, onto_path, check = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4] == "1"

def canonical(v):
    return json.dumps(v, sort_keys=True, separators=(",", ":"), ensure_ascii=False)

with open(json_path, encoding="utf-8") as fh:
    doc = json.load(fh)
body = {k: v for k, v in doc.items() if k != "registry_sha256"}
digest = "sha256:" + hashlib.sha256(canonical(body).encode("utf-8")).hexdigest()
if doc.get("registry_sha256") != digest:
    raise SystemExit("REFUSED(registry_digest_mismatch: declared %s computed %s)" % (doc.get("registry_sha256"), digest))

with open(ttl_path, encoding="utf-8") as fh:
    ttl_lines = fh.read().splitlines()
if any(l.startswith("# BEGIN GENERATED-REGISTRY") or l.startswith("# END GENERATED-REGISTRY") for l in ttl_lines):
    raise SystemExit("REFUSED(registry_ttl_contains_marker_lines)")
prefix = re.compile(r"^\s*(@prefix|@base|PREFIX|BASE)\b", re.IGNORECASE)
statements = [l for l in ttl_lines if not prefix.match(l)]
while statements and not statements[0].strip():
    statements.pop(0)
while statements and not statements[-1].strip():
    statements.pop()
if not statements:
    raise SystemExit("REFUSED(registry_ttl_empty)")

begin = "# BEGIN GENERATED-REGISTRY " + digest
end = "# END GENERATED-REGISTRY"
block = "\n".join([begin] + statements + [end]) + "\n"

with open(onto_path, encoding="utf-8") as fh:
    text = fh.read()

pat = re.compile(r"^# BEGIN GENERATED-REGISTRY[^\n]*\n.*?^# END GENERATED-REGISTRY[^\n]*\n?", re.DOTALL | re.MULTILINE)
starts = len(re.findall(r"^# BEGIN GENERATED-REGISTRY", text, re.MULTILINE))
ends = len(re.findall(r"^# END GENERATED-REGISTRY", text, re.MULTILINE))
if starts != ends or starts > 1:
    raise SystemExit("REFUSED(ontology_marker_shape: %d BEGIN, %d END)" % (starts, ends))
if starts == 1:
    new = pat.sub(lambda m: block, text, count=1)
else:
    new = text if text.endswith("\n") else text + "\n"
    new += "\n#################################################################\n"
    new += "# Vendored GraphLaw capability registry (generated; scripts/import_registry.sh)\n"
    new += "#################################################################\n\n" + block

sha_re = re.compile(r'(glx:registrySha256\s+)"[^"]*"')
if not sha_re.search(new):
    raise SystemExit("REFUSED(ontology_missing glx:registrySha256)")
new = sha_re.sub(lambda m: m.group(1) + '"' + digest + '"', new, count=1)

if check:
    if new != text:
        sys.stderr.write("DRIFT(%s differs from the vendored registry %s)\n" % (onto_path, digest))
        sys.exit(1)
    print("import_registry --check: %s matches registry %s" % (onto_path, digest))
else:
    if new != text:
        with open(onto_path, "w", encoding="utf-8") as fh:
            fh.write(new)
        print("spliced registry %s into %s" % (digest, onto_path))
    else:
        print("already current: %s @ %s" % (onto_path, digest))
PY
