#!/usr/bin/env bash
# status.sh [PROXY] [--org ORG ...]
# Deployed revision per environment for a proxy, across orgs. Read-only.
# Default orgs: the distinct envs.*.org values in .apigee.json, else the three
# HUIT orgs (nonprod, preprod, prod). PROXY defaults to the .apigee.json proxy
# or the local bundle's <APIProxy name>. Revision numbers are per org: the same
# bundle is rev 13 in nonprod and rev 2 in prod, so compare content, not numbers.
# stdout: JSON [{"org","present","latestRevision","deployments":[{"environment","revision","deployStartTime"}]}]
# stderr: a table.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

usage() { sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//' >&2; exit "${1:-64}"; }
PROXY="${PROXY:-}"; ORGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --org) ORGS+=("$2"); shift 2 ;;
    --bundle-dir) BUNDLE_DIR=$2; shift 2 ;;
    -h|--help) usage 0 ;;
    -*) usage ;;
    *) PROXY=$1; shift ;;
  esac
done
find_config
PROXY=$(resolve_proxy)
[[ ${#ORGS[@]} -gt 0 ]] || ORGS=($(all_orgs))

apigee_auth
out=$(mktmpd)
for org in "${ORGS[@]}"; do
  code=$(api GET "/organizations/$org/apis/$PROXY" "$out/$org.api.json")
  case "$code" in
    200) api_ok GET "/organizations/$org/apis/$PROXY/deployments" "$out/$org.dep.json" >/dev/null ;;
    404) : ;;
    403) warn "$org: permission denied (HTTP 403); your account may not have access to that org" ;;
    *)   warn "$org: HTTP $code"; head -c 400 "$out/$org.api.json" >&2; echo >&2 ;;
  esac
  echo "$code" > "$out/$org.code"
done

python3 - "$PROXY" "$out" "${ORGS[@]}" <<'PY'
import json, os, sys
proxy, out = sys.argv[1], sys.argv[2]
rows = []
for org in sys.argv[3:]:
    code = open(os.path.join(out, org + ".code")).read().strip()
    row = {"org": org, "present": code == "200", "httpStatus": int(code), "latestRevision": None, "deployments": []}
    if code == "200":
        api = json.load(open(os.path.join(out, org + ".api.json")))
        row["latestRevision"] = api.get("latestRevisionId")
        row["revisions"] = api.get("revision", [])
        deps = json.load(open(os.path.join(out, org + ".dep.json"))).get("deployments", [])
        row["deployments"] = sorted(({"environment": d["environment"], "revision": d["revision"], "deployStartTime": d.get("deployStartTime")} for d in deps), key=lambda x: x["environment"])
    rows.append(row)
w = max(len(r["org"]) for r in rows)
sys.stderr.write("%s\n" % proxy)
for r in rows:
    if not r["present"]:
        sys.stderr.write("  %-*s  not present (HTTP %s)\n" % (w, r["org"], r["httpStatus"])); continue
    deps = ", ".join("%s=rev%s" % (d["environment"], d["revision"]) for d in r["deployments"]) or "not deployed anywhere"
    sys.stderr.write("  %-*s  latest rev%s  %s\n" % (w, r["org"], r["latestRevision"], deps))
sys.stderr.write("  (revision numbers are per org; compare bundle content across orgs, not numbers)\n")
print(json.dumps(rows, indent=2))
PY
