#!/usr/bin/env python3
"""Idempotently merge the room fragment into a Paseo config.json.

Only the keys this kit owns are touched:
  * agents.providers["hermes-supervisor" | "hermes-lead" | "hermes-peer"]
  * daemon.agentProfiles entries whose provider starts with "hermes-"

Everything else — other agent providers, plugin flags, daemon listen address,
relay/cors settings — is preserved verbatim. (Wholesale replacement is the
failure mode of the codex-room-setup installer: it drops the operator's
hermes-* seats.) A timestamped backup is written before any change.

Usage:
  merge_paseo_config.py --fragment FILE --config FILE [--force] [--dry-run]
"""
from __future__ import annotations

import argparse
import json
import os
import secrets
import shutil
import sys
import time

DEFAULT_SKELETON = {
    "version": 1,
    "daemon": {
        "listen": "127.0.0.1:6767",
        "mcp": {"injectIntoAgents": True},
    },
    "app": {"baseUrl": "https://app.paseo.sh"},
    "pluginsEnabled": True,
    "agents": {"providers": {}},
}


def load(path: str) -> dict:
    if not os.path.isfile(path):
        return json.loads(json.dumps(DEFAULT_SKELETON))
    with open(path, encoding="utf-8") as fh:
        return json.load(fh)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--fragment", required=True)
    ap.add_argument("--config", required=True)
    ap.add_argument("--force", action="store_true", help="overwrite differing hermes-* entries")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    with open(args.fragment, encoding="utf-8") as fh:
        fragment = json.load(fh)
    frag_providers = (fragment.get("agents") or {}).get("providers") or {}
    frag_profiles = (fragment.get("daemon") or {}).get("agentProfiles") or []
    if not frag_providers:
        print("error: fragment carries no agents.providers", file=sys.stderr)
        return 2

    existed = os.path.isfile(args.config)
    cfg = load(args.config)
    before = json.dumps(cfg, sort_keys=True)

    cfg.setdefault("agents", {}).setdefault("providers", {})
    providers = cfg["agents"]["providers"]

    added, updated, kept = [], [], []
    for name, spec in frag_providers.items():
        if name not in providers:
            providers[name] = spec
            added.append(name)
        elif providers[name] != spec:
            if args.force:
                providers[name] = spec
                updated.append(name)
            else:
                kept.append(name)
        else:
            kept.append(name)

    daemon = cfg.setdefault("daemon", {})
    profiles = daemon.setdefault("agentProfiles", [])
    if not isinstance(profiles, list):
        print("error: daemon.agentProfiles is not a list — refusing to touch it", file=sys.stderr)
        return 2
    by_name = {p.get("name"): p for p in profiles if isinstance(p, dict)}
    ids_in_use = {p.get("id") for p in profiles if isinstance(p, dict)}

    p_added, p_updated, p_kept = [], [], []
    for spec in frag_profiles:
        spec = dict(spec)
        name = spec.get("name")
        if name in by_name:
            if by_name[name] != spec and args.force:
                spec.setdefault("id", by_name[name].get("id"))
                by_name[name].clear()
                by_name[name].update(spec)
                p_updated.append(name)
            else:
                p_kept.append(name)
            continue
        if not spec.get("id") or spec["id"] in ids_in_use:
            spec["id"] = f"agent_profile_roomkit_{secrets.token_hex(6)}"
        ids_in_use.add(spec["id"])
        profiles.append(spec)
        by_name[name] = spec
        p_added.append(name)

    changed = json.dumps(cfg, sort_keys=True) != before
    print(f"config: {args.config} ({'existing' if existed else 'new file from skeleton'})")
    print(f"  providers     added={added or '-'} updated={updated or '-'} kept={kept or '-'}")
    print(f"  agentProfiles added={p_added or '-'} updated={p_updated or '-'} kept={p_kept or '-'}")
    other = sorted(k for k in providers if not k.startswith("hermes-"))
    print(f"  untouched non-room providers: {', '.join(other) if other else '(none)'}")

    if not changed:
        print("no change needed (already up to date)")
        return 0
    if args.dry_run:
        print("dry-run: nothing written")
        return 0

    os.makedirs(os.path.dirname(os.path.abspath(args.config)), exist_ok=True)
    if existed:
        backup = f"{args.config}.bak-{time.strftime('%Y%m%d-%H%M%S')}"
        if os.path.exists(backup):
            backup = f"{backup}-{os.getpid()}"
        shutil.copy2(args.config, backup)
        print(f"  backup: {backup}")

    tmp = f"{args.config}.tmp-{os.getpid()}"
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump(cfg, fh, indent=2, ensure_ascii=False)
        fh.write("\n")
    json.load(open(tmp, encoding="utf-8"))  # parse-back guard
    os.replace(tmp, args.config)
    print(f"  written: {args.config}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
