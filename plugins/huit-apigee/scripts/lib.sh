#!/usr/bin/env bash
# Shared helpers for the huit-apigee scripts. Source it:
#   source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
# Running it directly calls one function, for testing:
#   lib.sh resolve_proxy        lib.sh resolve_org dev
#
# Compatible with bash 3.2 (macOS /bin/bash) and Linux. Needs curl, python3,
# gcloud. Never prints a token: the bearer token lives in a mode-600 temp file
# that curl reads with -H @file, so it appears neither on stdout nor in ps.
set -euo pipefail

APIGEE_API="${APIGEE_API:-https://apigee.googleapis.com/v1}"
HUIT_NONPROD_ORG="${HUIT_NONPROD_ORG:-apigee-x-nonprod-406719}"
HUIT_PREPROD_ORG="${HUIT_PREPROD_ORG:-apigee-x-preprod}"
HUIT_PROD_ORG="${HUIT_PROD_ORG:-apigee-x-prod-406719}"

# ---------------------------------------------------------------- output ----
log()  { printf '%s\n' "$*" >&2; }
warn() { printf 'warning: %s\n' "$*" >&2; }
die()  { local code=$1; shift; printf 'error: %s\n' "$*" >&2; exit "$code"; }

# ---------------------------------------------------------------- cleanup ---
CLEANUP=()
cleanup_add() { CLEANUP+=("$1"); }
_cleanup() { rm -rf ${CLEANUP[@]+"${CLEANUP[@]}"}; }
trap _cleanup EXIT

mktmp() { local t; t=$(mktemp "${TMPDIR:-/tmp}/huit-apigee.XXXXXX"); cleanup_add "$t"; printf '%s' "$t"; }
mktmpd() { local t; t=$(mktemp -d "${TMPDIR:-/tmp}/huit-apigee.XXXXXX"); cleanup_add "$t"; printf '%s' "$t"; }

# ---------------------------------------------------------------- json ------
# jget FILE 'python expression over d'  (d is the parsed JSON). Prints the result.
# The expression is written by the calling script, never by a user.
jget() { python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); r=eval(sys.argv[2]); print(json.dumps(r) if isinstance(r,(dict,list)) else ("" if r is None else r))' "$1" "$2"; }

# ---------------------------------------------------------------- config ----
# Locate .apigee.json walking up from $PWD. Sets APIGEE_CONFIG (may stay empty)
# and APIGEE_ROOT (config dir, else git toplevel, else $PWD).
find_config() {
  APIGEE_CONFIG="${APIGEE_CONFIG:-}"
  if [[ -z "$APIGEE_CONFIG" ]]; then
    local d="$PWD"
    while :; do
      if [[ -f "$d/.apigee.json" ]]; then APIGEE_CONFIG="$d/.apigee.json"; break; fi
      [[ "$d" == "/" ]] && break
      d=$(dirname "$d")
    done
  fi
  if [[ -n "$APIGEE_CONFIG" ]]; then
    APIGEE_ROOT=$(cd "$(dirname "$APIGEE_CONFIG")" && pwd)
  else
    APIGEE_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
  fi
  export APIGEE_CONFIG APIGEE_ROOT
}

# cfg dotted.key -> value (scalars printed plainly, objects/lists as JSON, empty if absent)
cfg() {
  [[ -n "${APIGEE_CONFIG:-}" ]] || return 0
  python3 - "$APIGEE_CONFIG" "$1" <<'PY'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except ValueError as e:
    sys.stderr.write("error: %s is not valid JSON: %s\n" % (sys.argv[1], e)); sys.exit(3)
for k in sys.argv[2].split('.'):
    if isinstance(d, dict) and k in d:
        d = d[k]
    else:
        sys.exit(0)
if isinstance(d, bool):
    print(str(d).lower())
elif isinstance(d, (dict, list)):
    print(json.dumps(d))
elif d is not None:
    print(d)
PY
}

# ---------------------------------------------------------------- bundle ----
# Print candidate apiproxy/ directories under APIGEE_ROOT (one per line).
find_bundle_dirs() {
  find "$APIGEE_ROOT" -maxdepth 4 -type d -name apiproxy \
    -not -path '*/node_modules/*' -not -path '*/.git/*' 2>/dev/null | sort
}

# resolve_bundle_dir -> absolute path of the apiproxy/ directory.
# Order: $BUNDLE_DIR (flag) > .apigee.json bundleDir > the single apiproxy/ found.
resolve_bundle_dir() {
  [[ -n "${APIGEE_ROOT:-}" ]] || find_config
  local d="${BUNDLE_DIR:-}"
  if [[ -z "$d" ]]; then d=$(cfg bundleDir); [[ -n "$d" && "$d" != /* ]] && d="$APIGEE_ROOT/$d"; fi
  if [[ -z "$d" ]]; then
    local n; n=$(find_bundle_dirs | grep -c . || true)
    case "$n" in
      0) die 4 "no apiproxy/ directory found under $APIGEE_ROOT; pass --bundle-dir or set bundleDir in .apigee.json" ;;
      1) d=$(find_bundle_dirs) ;;
      *) die 4 "more than one apiproxy/ directory under $APIGEE_ROOT, refusing to guess (set bundleDir in .apigee.json or pass --bundle-dir):
$(find_bundle_dirs | sed 's/^/  /')" ;;
    esac
  fi
  [[ -d "$d" ]] || die 4 "bundle directory not found: $d"
  (cd "$d" && pwd)
}

# manifest_path BUNDLE_DIR -> the <APIProxy> manifest xml (bundle root, not policies/)
manifest_path() {
  local f
  for f in "$1"/*.xml; do
    [[ -f "$f" ]] || continue
    grep -q '<APIProxy' "$f" && { printf '%s\n' "$f"; return 0; }
  done
  return 1
}

# manifest_name BUNDLE_DIR -> the name="..." attribute of <APIProxy>
manifest_name() {
  local m; m=$(manifest_path "$1") || die 4 "no <APIProxy> manifest in $1"
  python3 -c 'import sys, xml.etree.ElementTree as ET; print(ET.parse(sys.argv[1]).getroot().get("name") or "")' "$m"
}

# resolve_proxy -> proxy name. Order: $PROXY (flag) > .apigee.json proxy > manifest.
resolve_proxy() {
  [[ -n "${APIGEE_ROOT:-}" ]] || find_config
  local p="${PROXY:-}"
  [[ -n "$p" ]] || p=$(cfg proxy)
  if [[ -z "$p" ]]; then
    local bd; bd=$(resolve_bundle_dir) || exit $?
    p=$(manifest_name "$bd") || exit $?
  fi
  [[ -n "$p" ]] || die 4 "could not determine the proxy name"
  printf '%s\n' "$p"
}

# base_path BUNDLE_DIR -> the first <BasePath> in proxies/*.xml
base_path() { grep -ho '<BasePath>[^<]*</BasePath>' "$1"/proxies/*.xml 2>/dev/null | head -1 | sed 's/<[^>]*>//g'; }

# ---------------------------------------------------------------- org -------
# HUIT default org for an environment. Fallback only; .apigee.json wins.
# The stage -> preprod row is unverified until hosts.sh has been run against
# both orgs (see references/config.md).
default_org_for_env() {
  case "$1" in
    dev|test|sand|train|archive) printf '%s\n' "$HUIT_NONPROD_ORG" ;;
    stage)                       printf '%s\n' "$HUIT_PREPROD_ORG" ;;
    prod)                        printf '%s\n' "$HUIT_PROD_ORG" ;;
    *) return 1 ;;
  esac
}

# resolve_org ENV -> org. Order: $ORG (flag) > .apigee.json envs.ENV.org > default table > gcloud project (warns).
resolve_org() {
  [[ -n "${APIGEE_ROOT:-}" ]] || find_config
  local env="${1:-}" o="${ORG:-}"
  [[ -n "$o" ]] || { [[ -n "$env" ]] && o=$(cfg "envs.$env.org"); }
  [[ -n "$o" ]] || { [[ -n "$env" ]] && o=$(default_org_for_env "$env" || true); }
  if [[ -z "$o" ]]; then
    o=$(gcloud config get-value project 2>/dev/null || true)
    [[ -n "$o" ]] || die 4 "could not determine the Apigee org; pass --org"
    warn "org taken from gcloud's active project ($o); pass --org or set envs.<env>.org in .apigee.json to be explicit"
  fi
  printf '%s\n' "$o"
}

# all_orgs -> distinct orgs from .apigee.json envs, else the three HUIT defaults.
all_orgs() {
  [[ -n "${APIGEE_ROOT:-}" ]] || find_config
  local envs; envs=$(cfg envs)
  if [[ -n "$envs" ]]; then
    printf '%s' "$envs" | python3 -c 'import json,sys; seen=[]; [seen.append(v["org"]) for v in json.load(sys.stdin).values() if isinstance(v,dict) and v.get("org") and v["org"] not in seen]; print("\n".join(seen))'
  else
    printf '%s\n%s\n%s\n' "$HUIT_NONPROD_ORG" "$HUIT_PREPROD_ORG" "$HUIT_PROD_ORG"
  fi
}

gcloud_project() { gcloud config get-value project 2>/dev/null || true; }

# ---------------------------------------------------------------- auth ------
# apigee_auth: mint one token per script run into a mode-600 header file.
apigee_auth() {
  command -v gcloud >/dev/null 2>&1 || die 2 "gcloud not found. Install the Google Cloud SDK, then: gcloud auth login"
  command -v curl >/dev/null 2>&1 || die 2 "curl not found"
  command -v python3 >/dev/null 2>&1 || die 2 "python3 not found"
  APIGEE_AUTH_HEADER=$(mktmp)
  chmod 600 "$APIGEE_AUTH_HEADER"
  local tok
  if ! tok=$(gcloud auth print-access-token 2>/dev/null) || [[ -z "$tok" ]]; then
    die 2 "gcloud login expired or missing. Run: gcloud auth login   (on a host without a browser: gcloud auth login --no-launch-browser)"
  fi
  printf 'Authorization: Bearer %s\n' "$tok" > "$APIGEE_AUTH_HEADER"
  unset tok
  export APIGEE_AUTH_HEADER
}

# api METHOD PATH OUTFILE [curl args...] -> prints the HTTP status; body goes to OUTFILE.
# PATH is relative to $APIGEE_API (start it with /organizations/...).
api() {
  local method=$1 path=$2 out=$3; shift 3
  [[ -n "${APIGEE_AUTH_HEADER:-}" ]] || apigee_auth
  curl -sS -o "$out" -w '%{http_code}' -X "$method" -H @"$APIGEE_AUTH_HEADER" "$@" "${APIGEE_API}${path}"
}

# api_ok METHOD PATH OUTFILE [curl args...] -> like api, but dies (exit 5) on HTTP >= 400 with the body on stderr.
api_ok() {
  local code; code=$(api "$@")
  if [[ "$code" -ge 400 ]]; then
    log "HTTP $code from $1 $2"
    python3 -c 'import json,sys
try:
    d=json.load(open(sys.argv[1])); e=d.get("error",d)
    print("  %s %s" % (e.get("status",""), e.get("message","")).strip())
    for det in e.get("details",[]) or []:
        for v in det.get("violations",[]) or []:
            print("  - %s: %s" % (v.get("type",""), v.get("description","")))
except Exception:
    print(open(sys.argv[1]).read()[:2000])' "$3" >&2
    exit 5
  fi
  printf '%s' "$code"
}

# ---------------------------------------------------------------- misc ------
# git_dirty DIR -> 0 if DIR is inside a git repo and has uncommitted or untracked changes.
# Returns 2 if DIR is not inside a git repo.
git_dirty() {
  git -C "$1" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 2
  [[ -n "$(git -C "$1" status --porcelain -- . 2>/dev/null)" ]]
}

state_file() { [[ -n "${APIGEE_ROOT:-}" ]] || find_config; printf '%s\n' "$APIGEE_ROOT/.apigee-state.json"; }

# When executed rather than sourced, run the named function.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  [[ $# -gt 0 ]] || { log "usage: lib.sh <function> [args]"; exit 64; }
  "$@"
fi
