#!/usr/bin/env bash
# hosts.sh --org ORG [--env ENV]
# Environment groups of an Apigee org: hostnames and attached environments.
# Read-only. Use it to find the gateway host for a smoke test instead of a
# hardcoded table, and to check which org hosts which environment.
# stdout: JSON {"org":..., "groups":[{"name","hostnames","environments"}], "envHosts":{env:[hosts]}}
# stderr: one line per environment. With --env, stdout is just that env's hostname (the go.* one).
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

usage() { sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//' >&2; exit "${1:-64}"; }
ORG=""; ENV_FILTER=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --org) ORG=$2; shift 2 ;;
    --env) ENV_FILTER=$2; shift 2 ;;
    -h|--help) usage 0 ;;
    *) usage ;;
  esac
done
[[ -n "$ORG" ]] || usage

apigee_auth
groups=$(mktmp)
api_ok GET "/organizations/$ORG/envgroups" "$groups" >/dev/null
out=$(mktmpd)
for g in $(jget "$groups" '" ".join(x["name"] for x in d.get("environmentGroups",[]))'); do
  api_ok GET "/organizations/$ORG/envgroups/$g/attachments" "$out/$g.json" >/dev/null
done

python3 - "$ORG" "$groups" "$out" "$ENV_FILTER" <<'PY'
import json, os, sys
org, gfile, adir, env_filter = sys.argv[1:5]
groups = json.load(open(gfile)).get("environmentGroups", [])
rows, env_hosts = [], {}
for g in groups:
    att = json.load(open(os.path.join(adir, g["name"] + ".json"))).get("environmentGroupAttachments", [])
    envs = sorted(a["environment"] for a in att)
    rows.append({"name": g["name"], "hostnames": g.get("hostnames", []), "environments": envs})
    for e in envs:
        env_hosts.setdefault(e, []).extend(g.get("hostnames", []))
if env_filter:
    hosts = env_hosts.get(env_filter)
    if not hosts:
        sys.stderr.write("error: environment %r is not attached to any env group in %s (envs: %s)\n" % (env_filter, org, ", ".join(sorted(env_hosts)) or "none"))
        sys.exit(4)
    # Prefer the ADEX "go." virtual host, which is what every HUIT proxy is documented under.
    print(sorted(hosts, key=lambda h: (not h.startswith("go."), h))[0])
else:
    for e in sorted(env_hosts):
        sys.stderr.write("%-10s %s\n" % (e, ", ".join(env_hosts[e])))
    print(json.dumps({"org": org, "groups": rows, "envHosts": env_hosts}, indent=2))
PY
