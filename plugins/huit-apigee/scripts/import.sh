#!/usr/bin/env bash
# import.sh [PROXY] [--bundle-dir DIR] [--env ENV | --org ORG] [--validate] [--keep-zip PATH]
# Zip the local apiproxy/ tree and import it as a new revision, or just validate it.
#   PROXY         default: .apigee.json proxy, else the bundle's <APIProxy name>
#   --bundle-dir  the apiproxy/ directory (default: .apigee.json bundleDir, else the single one found)
#   --env ENV     pick the org for that environment (default env: dev); --org overrides
#   --validate    action=validate: the server checks the bundle and creates NO revision
#   --keep-zip P  also leave a copy of the uploaded zip at P (default: temp, deleted)
# The zip holds only apiproxy/ and excludes .DS_Store, so product JSON or old zips
# sitting next to the bundle never get uploaded.
# Endpoint: POST /organizations/{org}/apis?action=import&name={proxy} as multipart
# form (-F file=@zip). That is the one form that works on the HUIT orgs: the
# application/octet-stream body and the /apis/{name}/revisions import path both 404.
# stdout: JSON {"action","proxy","org","revision","zipBytes","files"}. Exit 5 with the
# server's violations on stderr when the bundle is rejected ("bundle contains errors").
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

usage() { sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//' >&2; exit "${1:-64}"; }
PROXY="${PROXY:-}"; ENV=""; ORG="${ORG:-}"; VALIDATE=0; KEEP=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --bundle-dir) BUNDLE_DIR=$2; shift 2 ;;
    --env) ENV=$2; shift 2 ;;
    --org) ORG=$2; shift 2 ;;
    --validate) VALIDATE=1; shift ;;
    --keep-zip) KEEP=$2; shift 2 ;;
    -h|--help) usage 0 ;;
    -*) usage ;;
    *) PROXY=$1; shift ;;
  esac
done

find_config
bundle=$(resolve_bundle_dir)
PROXY=$(resolve_proxy)
[[ -n "$ENV" || -n "$ORG" ]] || ENV=dev
ORG=$(resolve_org "$ENV")
[[ "$(basename "$bundle")" == apiproxy ]] || die 4 "bundle dir must be named apiproxy: $bundle"
mname=$(manifest_name "$bundle")
[[ "$mname" == "$PROXY" ]] || warn "manifest <APIProxy name=\"$mname\"> differs from the import name $PROXY; the name in the URL wins"

zip=$(mktmp).zip; cleanup_add "$zip"
( cd "$(dirname "$bundle")" && zip -qr "$zip" apiproxy -x '*.DS_Store' '*/.git/*' '*~' )
files=$(unzip -Z1 "$zip" | grep -vc '/$' || true)
bytes=$(wc -c < "$zip" | tr -d ' ')
[[ -n "$KEEP" ]] && cp "$zip" "$KEEP"
if unzip -Z1 "$zip" | grep -q -- '-product\.json$\|\.zip$'; then
  die 4 "the zip contains a product JSON or a zip; those do not belong inside apiproxy/"
fi

action=import; [[ $VALIDATE -eq 1 ]] && action=validate
log "$action $PROXY into $ORG ($files files, $bytes bytes)"
apigee_auth
resp=$(mktmp)
api_ok POST "/organizations/$ORG/apis?action=$action&name=$PROXY" "$resp" -F "file=@$zip" >/dev/null
rev=$(jget "$resp" 'd.get("revision")')
if [[ $VALIDATE -eq 1 ]]; then
  log "bundle is valid (no revision created)"
else
  log "imported as revision $rev"
fi
python3 -c 'import json,sys; print(json.dumps({"action": sys.argv[1], "proxy": sys.argv[2], "org": sys.argv[3], "revision": (sys.argv[4] if sys.argv[1]=="import" else None), "zipBytes": int(sys.argv[5]), "files": int(sys.argv[6])}, indent=2))' "$action" "$PROXY" "$ORG" "$rev" "$bytes" "$files"
