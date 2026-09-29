#!/usr/bin/env bash
# smoke.sh [PROXY] --env ENV [--org ORG] [--host HOST] [--bundle-dir DIR]
# Hit the deployed proxy through the gateway and compare status codes.
# Routes come from .apigee.json "smoke": [{"path","method","headers","expect"}], where
# a header value may be "$NAME" to read the environment variable NAME at run time
# (the value is sent, never printed). With no smoke config the check is the bundle's
# <BasePath> alone, where anything but a 404 counts as reachable (a 404 means the base
# path is not deployed on that host; a 401/403/405 means the proxy answered).
# The host comes from .apigee.json envs.ENV.host, else from the org's env groups
# (hosts.sh --env ENV), never from a hardcoded table.
# stdout: JSON {"host","basePath","results":[{"path","method","status","expect","ok"}],"ok"}
# exit: 0 all ok, 8 any failure
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$here/lib.sh"

usage() { sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//' >&2; exit "${1:-64}"; }
PROXY="${PROXY:-}"; ENV=""; ORG="${ORG:-}"; HOST=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --env) ENV=$2; shift 2 ;;
    --org) ORG=$2; shift 2 ;;
    --host) HOST=$2; shift 2 ;;
    --bundle-dir) BUNDLE_DIR=$2; shift 2 ;;
    -h|--help) usage 0 ;;
    -*) usage ;;
    *) PROXY=$1; shift ;;
  esac
done
[[ -n "$ENV" ]] || usage
find_config
bundle=$(resolve_bundle_dir)
PROXY=$(resolve_proxy)
ORG=$(resolve_org "$ENV")
bp=$(base_path "$bundle")
[[ -n "$bp" ]] || die 4 "no <BasePath> in $bundle/proxies/*.xml"
[[ -n "$HOST" ]] || HOST=$(cfg "envs.$ENV.host")
[[ -n "$HOST" ]] || HOST=$("$here/hosts.sh" --org "$ORG" --env "$ENV" 2>/dev/null) || die 4 "no host for $ENV in $ORG; set envs.$ENV.host in .apigee.json or pass --host"
routes=$(cfg smoke)
[[ -n "$routes" ]] || routes='[{"path":"/","expect":"!404"}]'
log "smoke $PROXY on https://$HOST$bp ($ENV, $ORG)"

python3 - "$HOST" "$bp" "$routes" <<'PY'
import json, os, subprocess, sys, time
host, bp, routes = sys.argv[1], sys.argv[2], json.loads(sys.argv[3])
results, ok_all = [], True
for r in routes:
    path = r.get("path", "/"); method = r.get("method", "GET").upper(); expect = r.get("expect", 200)
    url = "https://%s%s%s" % (host, bp.rstrip("/"), path if path.startswith("/") else "/" + path)
    cmd = ["curl", "-sS", "-o", "/dev/null", "-w", "%{http_code}", "-X", method, "--max-time", "30"]
    for k, v in (r.get("headers") or {}).items():
        if isinstance(v, str) and v.startswith("$"):
            v = os.environ.get(v[1:], "")
            if not v:
                sys.stderr.write("  %s %s: header %s: environment variable %s is unset, skipping route\n" % (method, path, k, r["headers"][k])); v = None
        if v is None: break
        cmd += ["-H", "%s: %s" % (k, v)]
    else:
        status = None
        for attempt in range(3):
            try:
                status = int(subprocess.run(cmd + [url], capture_output=True, text=True, timeout=40).stdout.strip() or 0)
            except Exception:
                status = 0
            if status >= 500 or status == 0:
                time.sleep(5); continue
            break
        ok = (status != 404 and status != 0) if expect == "!404" else (status == int(expect))
        ok_all &= ok
        sys.stderr.write("  %s %s%s -> %s (expected %s) %s\n" % (method, bp.rstrip("/"), path, status, expect, "ok" if ok else "FAIL"))
        results.append({"path": path, "method": method, "status": status, "expect": expect, "ok": ok})
        continue
    results.append({"path": path, "method": method, "status": None, "expect": expect, "ok": False, "skipped": "missing env var"})
    ok_all = False
print(json.dumps({"host": host, "basePath": bp, "results": results, "ok": bool(ok_all)}, indent=2))
sys.exit(0 if ok_all else 8)
PY
