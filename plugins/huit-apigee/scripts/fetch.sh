#!/usr/bin/env bash
# fetch.sh [PROXY] [--rev N] [--env ENV | --org ORG] [--out DIR] [--product] [--lf] [--force] [--no-state]
# Download one revision of an API proxy and unpack it as DIR/apiproxy/.
#   PROXY      default: .apigee.json proxy, else the local bundle's <APIProxy name>
#   --rev N    default: the org's latestRevisionId
#   --env ENV  pick the org for that environment (default env: dev); --org overrides
#   --out DIR  the directory that will contain apiproxy/ (default: the parent of the
#              current bundle dir, else <root>/<proxy>)
#   --product  also save the API product as DIR/<proxy>-product.json (outside the bundle)
#   --lf       normalize CRLF to LF in text files (exports downloaded via Windows have CRLF)
#   --force    overwrite DIR/apiproxy even if it has uncommitted changes or is not in git
#   --no-state do not write <root>/.apigee-state.json
# Refuses to replace DIR/apiproxy when git shows uncommitted or untracked changes
# under it, or when it is not inside a git repo (nothing could recover the edits).
# stdout: JSON summary. stderr: progress plus the proxy's external dependencies
# (KVM names, target servers, shared flows, target URLs). Names only, never values.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

usage() { sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//' >&2; exit "${1:-64}"; }
PROXY="${PROXY:-}"; REV=""; ENV=""; ORG="${ORG:-}"; OUT=""; PRODUCT=0; LF=0; FORCE=0; STATE=1
while [[ $# -gt 0 ]]; do
  case "$1" in
    --rev) REV=$2; shift 2 ;;
    --env) ENV=$2; shift 2 ;;
    --org) ORG=$2; shift 2 ;;
    --out) OUT=$2; shift 2 ;;
    --bundle-dir) BUNDLE_DIR=$2; shift 2 ;;
    --product) PRODUCT=1; shift ;;
    --lf) LF=1; shift ;;
    --force) FORCE=1; shift ;;
    --no-state) STATE=0; shift ;;
    -h|--help) usage 0 ;;
    -*) usage ;;
    *) PROXY=$1; shift ;;
  esac
done

find_config
# Proxy name: flag > config > local manifest. A missing local bundle is fine on a first pull.
if [[ -z "$PROXY" ]]; then
  PROXY=$(cfg proxy)
  if [[ -z "$PROXY" ]]; then
    bd=$(resolve_bundle_dir 2>/dev/null) || die 4 "no proxy name: pass one, or set proxy in .apigee.json (no single local apiproxy/ to read it from)"
    PROXY=$(manifest_name "$bd")
  fi
fi
[[ -n "$ENV" || -n "$ORG" ]] || ENV=dev
ORG=$(resolve_org "$ENV")
if [[ -z "$OUT" ]]; then
  if bd=$(resolve_bundle_dir 2>/dev/null); then OUT=$(dirname "$bd"); else OUT="$APIGEE_ROOT/$PROXY"; fi
fi
mkdir -p "$OUT"; OUT=$(cd "$OUT" && pwd)
target="$OUT/apiproxy"

# Safety: never destroy edits.
if [[ -d "$target" && $FORCE -eq 0 ]]; then
  if git_dirty "$target"; then
    die 3 "$target has uncommitted or untracked changes; commit or stash them first (or --force to discard):
$(git -C "$target" status --porcelain -- . | sed 's/^/  /')"
  elif [[ $? -eq 2 ]]; then
    die 3 "$target exists and is not inside a git repository, so lost edits could not be recovered; move it aside or --force"
  fi
fi

apigee_auth
log "proxy $PROXY, org $ORG"
info=$(mktmp)
api_ok GET "/organizations/$ORG/apis/$PROXY" "$info" >/dev/null
[[ -n "$REV" ]] || REV=$(jget "$info" 'd.get("latestRevisionId")')
[[ -n "$REV" ]] || die 5 "could not determine latest revision"
log "revision $REV (latest is $(jget "$info" 'd.get("latestRevisionId")'))"

zip=$(mktmp)
api_ok GET "/organizations/$ORG/apis/$PROXY/revisions/$REV?format=bundle" "$zip" >/dev/null
unzip -qq -l "$zip" 'apiproxy/*' >/dev/null 2>&1 || die 5 "downloaded bundle has no apiproxy/ tree"
stage=$(mktmpd)
unzip -qq "$zip" -d "$stage"

if [[ $LF -eq 1 ]]; then
  python3 - "$stage/apiproxy" <<'PY' >&2
import os, sys
n = 0
for root, _, files in os.walk(sys.argv[1]):
    for f in files:
        p = os.path.join(root, f)
        try:
            b = open(p, 'rb').read()
        except OSError:
            continue
        if b'\0' in b or b'\r\n' not in b:
            continue
        open(p, 'wb').write(b.replace(b'\r\n', b'\n')); n += 1
if n:
    print("normalized CRLF -> LF in %d file(s)" % n)
PY
fi

rm -rf "$target"
mv "$stage/apiproxy" "$target"
log "unpacked to $target"

# Deployments of this proxy in this org (for the state file and the report).
deps=$(mktmp)
api_ok GET "/organizations/$ORG/apis/$PROXY/deployments" "$deps" >/dev/null

# API product, saved next to (not inside) the bundle.
product_file=""
if [[ $PRODUCT -eq 1 ]]; then
  pj=$(mktmp)
  code=$(api GET "/organizations/$ORG/apiproducts/$PROXY" "$pj")
  if [[ "$code" != 200 ]]; then
    all=$(mktmp)
    api_ok GET "/organizations/$ORG/apiproducts?expand=true" "$all" >/dev/null
    python3 - "$all" "$PROXY" "$pj" <<'PY'
import json, sys
prods, proxy, out = json.load(open(sys.argv[1])).get("apiProduct", []), sys.argv[2], sys.argv[3]
hits = [p for p in prods if proxy in p.get("proxies", []) or any(
    c.get("apiSource") == proxy for g in [p.get("operationGroup") or {}] for c in g.get("operationConfigs", []))]
if len(hits) == 1:
    json.dump(hits[0], open(out, "w"), indent=2); sys.exit(0)
sys.stderr.write("no single API product references %s (%d matched)\n" % (proxy, len(hits))); sys.exit(1)
PY
    code=$?
  fi
  if [[ "$code" == 200 || "$code" == 0 ]]; then
    product_file="$OUT/$PROXY-product.json"
    python3 -m json.tool "$pj" > "$product_file"
    log "product saved to $product_file (not part of the bundle; never zip it)"
  else
    warn "no API product found for $PROXY in $ORG"
  fi
fi

# State file for the drift check in push.
state_path=""
if [[ $STATE -eq 1 ]]; then
  state_path=$(state_file)
  python3 - "$state_path" "$PROXY" "$ORG" "$REV" "$target" "$APIGEE_ROOT" "$deps" <<'PY'
import datetime, json, os, sys
path, proxy, org, rev, target, root, deps = sys.argv[1:8]
d = json.load(open(deps)).get("deployments", [])
json.dump({
    "proxy": proxy, "org": org, "revision": rev,
    "fetchedAt": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "bundleDir": os.path.relpath(target, root),
    "deployments": sorted(({"environment": x["environment"], "revision": x["revision"]} for x in d), key=lambda x: x["environment"]),
}, open(path, "w"), indent=2)
open(path, "a").write("\n")
PY
  log "state written to $state_path"
  if git -C "$APIGEE_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1 && ! git -C "$APIGEE_ROOT" check-ignore -q "$state_path"; then
    warn ".apigee-state.json is not gitignored; add it to $APIGEE_ROOT/.gitignore"
  fi
fi

# Dependencies and summary.
python3 - "$PROXY" "$ORG" "$REV" "$OUT" "$target" "$product_file" "$state_path" "$deps" <<'PY'
import glob, json, os, re, sys
proxy, org, rev, out, target, product, state, deps = sys.argv[1:9]
def scan(pattern, regex):
    found = set()
    for f in glob.glob(os.path.join(target, pattern)):
        found.update(re.findall(regex, open(f, encoding="utf-8", errors="replace").read()))
    return sorted(found)
dep = {
    "kvms": scan("policies/*.xml", r'mapIdentifier="([^"]+)"'),
    "sharedFlows": scan("policies/*.xml", r"<SharedFlowBundle>([^<]+)</SharedFlowBundle>"),
    "targetServers": scan("targets/*.xml", r'<Server\s+name="([^"]+)"'),
    "targetUrls": scan("targets/*.xml", r"<URL>([^<]+)</URL>"),
}
for k, label in (("kvms", "KVMs"), ("sharedFlows", "shared flows"), ("targetServers", "target servers"), ("targetUrls", "target URLs")):
    if dep[k]:
        sys.stderr.write("%s: %s\n" % (label, ", ".join(dep[k])))
d = sorted(json.load(open(deps)).get("deployments", []), key=lambda x: x["environment"])
sys.stderr.write("deployed in %s: %s\n" % (org, ", ".join("%s=rev%s" % (x["environment"], x["revision"]) for x in d) or "nowhere"))
print(json.dumps({"proxy": proxy, "org": org, "revision": rev, "out": out, "bundleDir": target,
                  "productFile": product or None, "stateFile": state or None,
                  "deployments": [{"environment": x["environment"], "revision": x["revision"]} for x in d],
                  "dependencies": dep}, indent=2))
PY
