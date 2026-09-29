#!/usr/bin/env bash
# deploy.sh [PROXY] --rev N --env ENV [--org ORG] [--timeout SECS] [--no-wait]
# Deploy revision N to ENV (override=true replaces whatever is deployed there), then
# poll until the deployment is READY or ERROR.
#   --rev N        the revision to deploy (from import.sh); required
#   --env ENV      target environment; the org comes from .apigee.json, the HUIT
#                  default table, or --org
#   --timeout S    give up polling after S seconds (default 180; READY in 30-50 s is typical)
#   --no-wait      start the deployment and return without polling
# Before deploying it records the revision currently deployed in ENV as
# "previousRevision" so the caller can roll back with the same command.
# stdout: JSON {"proxy","org","env","revision","previousRevision","state","seconds","errors"}
# exit: 0 READY, 6 ERROR (errors printed), 7 timed out (still PROGRESSING)
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

usage() { sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//' >&2; exit "${1:-64}"; }
PROXY="${PROXY:-}"; REV=""; ENV=""; ORG="${ORG:-}"; TIMEOUT=180; WAIT=1
while [[ $# -gt 0 ]]; do
  case "$1" in
    --rev) REV=$2; shift 2 ;;
    --env) ENV=$2; shift 2 ;;
    --org) ORG=$2; shift 2 ;;
    --bundle-dir) BUNDLE_DIR=$2; shift 2 ;;
    --timeout) TIMEOUT=$2; shift 2 ;;
    --no-wait) WAIT=0; shift ;;
    -h|--help) usage 0 ;;
    -*) usage ;;
    *) PROXY=$1; shift ;;
  esac
done
[[ -n "$REV" && -n "$ENV" ]] || usage

find_config
PROXY=$(resolve_proxy)
ORG=$(resolve_org "$ENV")
base="/organizations/$ORG/environments/$ENV/apis/$PROXY"

apigee_auth
cur=$(mktmp)
api_ok GET "$base/deployments" "$cur" >/dev/null
prev=$(jget "$cur" '(d.get("deployments") or [{}])[0].get("revision")')
if [[ -n "$prev" ]]; then
  [[ "$prev" == "$REV" ]] && warn "revision $REV is already deployed in $ENV; redeploying it anyway"
  log "currently deployed in $ORG/$ENV: revision $prev (rollback: $(basename "$0") $PROXY --rev $prev --env $ENV --org $ORG)"
else
  log "nothing deployed in $ORG/$ENV yet"
fi

log "deploying $PROXY revision $REV to $ORG/$ENV"
resp=$(mktmp)
api_ok POST "$base/revisions/$REV/deployments?override=true" "$resp" >/dev/null
state=$(jget "$resp" 'd.get("state","PROGRESSING")')

start=$(date +%s); elapsed=0; errors="[]"
if [[ $WAIT -eq 1 ]]; then
  while [[ "$state" != READY && "$state" != ERROR ]]; do
    elapsed=$(( $(date +%s) - start ))
    if [[ $elapsed -ge $TIMEOUT ]]; then break; fi
    sleep 10
    api_ok GET "$base/revisions/$REV/deployments" "$resp" >/dev/null
    state=$(jget "$resp" 'd.get("state","PROGRESSING")')
    log "  $state (${elapsed}s)"
  done
  elapsed=$(( $(date +%s) - start ))
  errors=$(jget "$resp" '[e.get("message", json.dumps(e)) for e in (d.get("errors") or [])]')
fi

python3 -c 'import json,sys; print(json.dumps({"proxy": sys.argv[1], "org": sys.argv[2], "env": sys.argv[3], "revision": sys.argv[4], "previousRevision": sys.argv[5] or None, "state": sys.argv[6], "seconds": int(sys.argv[7]), "errors": json.loads(sys.argv[8])}, indent=2))' "$PROXY" "$ORG" "$ENV" "$REV" "$prev" "$state" "$elapsed" "$errors"

case "$state" in
  READY) log "READY after ${elapsed}s" ;;
  ERROR) log "deployment ERROR:"; printf '%s' "$errors" | python3 -c 'import json,sys; [print("  - " + m) for m in json.load(sys.stdin)]' >&2
         [[ -n "$prev" ]] && log "rollback: $(basename "$0") $PROXY --rev $prev --env $ENV --org $ORG"
         exit 6 ;;
  *) [[ $WAIT -eq 1 ]] && { warn "still $state after ${elapsed}s; check again with status.sh"; exit 7; } ;;
esac
