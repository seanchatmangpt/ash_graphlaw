#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 ash_graphlaw contributors <https://github.com/seanchatmangpt/ash_graphlaw/graphs/contributors>
#
# SPDX-License-Identifier: MIT
"""Generate A2A v1.0 capability cards from the vendored GraphLaw registry.

    python3 scripts/generate_capability_cards.py [--check]

Reads the vendored registry JSON (priv/graphlaw/capability-registry.json), verifies its
registry_sha256 exactly as scripts/import_registry.sh does, and emits one A2A v1.0
agent-card-shaped JSON document per gac:Capability (registry `ops` entry) into
priv/graphlaw/cards/<name>.json.

Card shape (ash_a2a codec, AshA2A.Protocol.AgentCard, A2A v1.0 spec section 4.4/8.2):
  name / description / version / skills[{id, name, description, tags}] /
  supportedInterfaces[{url, protocolBinding, protocolVersion}].
No top-level `url` and no top-level `preferredTransport` (the wasm host is not a network
endpoint; transport identification lives on supportedInterfaces, positional preference
per spec section 4.4). The authority boundary is stated in every card description: the
digest-pinned graphlaw.wasm host derives and validates (SELECT/CONSTRUCT only); it never
authorizes and never carries DO.

Generated output; do not hand-edit. Rerun scripts/import_registry.sh to regenerate.
--check writes nothing and exits non-zero on drift.
"""
import hashlib
import json
import pathlib
import re
import sys

REPO = pathlib.Path(__file__).resolve().parent.parent
JSON_PATH = REPO / "priv/graphlaw/capability-registry.json"
CARDS_DIR = REPO / "priv/graphlaw/cards"
PROTOCOL_VERSION = "1.0"
PROTOCOL_BINDING = "HTTP+JSON"
TAGS = ["graphlaw", "a2a-v1.0", "select-construct-only"]

# Deterministic verb-form per capability, used for skill ids `graphlaw.<capability>.<verb>`.
VERB_FORMS = {
    "capabilities": "describe",
    "sniff": "sniff",
    "parse": "parse",
    "convert": "convert",
    "canonical": "canonicalize",
    "sparql": "query",
    "shacl": "validate",
    "shex": "validate",
    "n3": "reason",
    "entail": "entail",
    "datalog": "reason",
    "hooks": "dispatch",
    "law": "execute",
    "policy": "check",
}

AUTHORITY_BOUNDARY = (
    "Authority boundary: served by the digest-pinned graphlaw.wasm host, "
    "SELECT/CONSTRUCT only - it derives and validates, never authorizes, never carries DO."
)


def main() -> None:
    check = "--check" in sys.argv[1:]
    doc = json.loads(JSON_PATH.read_text(encoding="utf-8"))
    # Digest-rule-aware, mirroring scripts/import_registry.sh: the rule follows the key
    # the file itself declares — blake3 ("registry_blake3", computed with b3sum over the
    # canonical JSON minus the key) or sha256 (legacy "registry_sha256"); neither key is
    # a typed refusal.
    if "registry_blake3" in doc:
        dkey = "registry_blake3"
    elif "registry_sha256" in doc:
        dkey = "registry_sha256"
    else:
        raise SystemExit("REFUSED(registry_digest_key_absent: no registry_blake3 or registry_sha256)")
    body = {k: v for k, v in doc.items() if k != dkey}
    canonical = json.dumps(body, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
    if dkey == "registry_blake3":
        import subprocess

        p = subprocess.run(["b3sum"], input=canonical.encode("utf-8"), capture_output=True)
        if p.returncode != 0:
            raise SystemExit("REFUSED(b3sum_failed: %s)" % p.stderr.decode().strip())
        digest = "blake3:" + p.stdout.decode().split()[0]
    else:
        digest = "sha256:" + hashlib.sha256(canonical.encode("utf-8")).hexdigest()
    if doc.get(dkey) != digest:
        raise SystemExit(
            "REFUSED(registry_digest_mismatch: declared %s computed %s)" % (doc.get(dkey), digest)
        )

    version = str(doc["graphlaw_version"])
    cards = {}
    for op in doc["ops"]:
        name = op["name"]
        verb = VERB_FORMS.get(name)
        if verb is None:
            raise SystemExit("REFUSED(capability_verb_form_absent: %s)" % name)
        summary = op["summary"]
        card = {
            "name": "graphlaw-%s" % name,
            "description": "%s %s" % (summary, AUTHORITY_BOUNDARY),
            "version": version,
            "skills": [
                {
                    "id": "graphlaw.%s.%s" % (name, verb),
                    "name": "GraphLaw %s" % name,
                    "description": summary,
                    "tags": TAGS + [name],
                }
            ],
            "supportedInterfaces": [
                {
                    "url": "https://graphlaw.dev/registry#op/%s" % name,
                    "protocolBinding": PROTOCOL_BINDING,
                    "protocolVersion": PROTOCOL_VERSION,
                }
            ],
        }
        cards["%s.json" % name] = json.dumps(card, indent=2, ensure_ascii=False) + "\n"

    CARDS_DIR.mkdir(parents=True, exist_ok=True)
    for path in sorted(CARDS_DIR.glob("*.json")):
        if path.name not in cards:
            if check:
                sys.stderr.write("DRIFT(stale card %s)\n" % path.name)
                sys.exit(1)
            path.unlink()
            print("removed stale card %s" % path.name)
    drift = []
    for fname, text in sorted(cards.items()):
        path = CARDS_DIR / fname
        if check:
            if not path.exists() or path.read_text(encoding="utf-8") != text:
                drift.append(fname)
            continue
        changed = (not path.exists()) or path.read_text(encoding="utf-8") != text
        if changed:
            path.write_text(text, encoding="utf-8")
            print("wrote %s" % path.relative_to(REPO))
        else:
            print("current %s" % path.relative_to(REPO))
    if check and drift:
        sys.stderr.write(
            "DRIFT(%d card(s) differ from registry %s: %s)\n"
            % (len(drift), digest, ", ".join(drift))
        )
        sys.exit(1)
    if check:
        print("generate_capability_cards --check: %d cards match registry %s" % (len(cards), digest))


if __name__ == "__main__":
    main()
