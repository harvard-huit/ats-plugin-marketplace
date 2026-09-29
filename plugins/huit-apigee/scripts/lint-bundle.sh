#!/usr/bin/env bash
# lint-bundle.sh [BUNDLE_DIR] [--proxy NAME]
# Static checks on an apiproxy/ tree before importing it. Offline, read-only.
# Errors (exit 1) are things the import or deploy will reject:
#   a <Step><Name> with no policy file, a RouteRule to a missing TargetEndpoint,
#   a ResourceURL to a missing resource, BasicAuthentication User/Password without ref=.
# Warnings (exit 0) are drift and known gotchas:
#   manifest <Policies>/<Resources>/<*Endpoints> lists out of step with the files on
#   disk, policies never stepped from any flow, CRLF line endings, .DS_Store or other
#   stray files that would land in the zip, conditions using NotLike, unparenthesized
#   != "literal" with and/or, or MatchesPath "/", AssignMessage <Set><Path>, BasicAuthentication AssignTo not
#   request.header.Authorization, target.url set from a ProxyEndpoint-only policy.
# stdout: JSON {"bundleDir","proxy","errors":[],"warnings":[]}. stderr: the same as lines.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

usage() { sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//' >&2; exit "${1:-64}"; }
PROXY="${PROXY:-}"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --proxy) PROXY=$2; shift 2 ;;
    -h|--help) usage 0 ;;
    -*) usage ;;
    *) BUNDLE_DIR=$1; shift ;;
  esac
done
find_config
bundle=$(resolve_bundle_dir)
[[ -n "$PROXY" ]] || PROXY=$(cfg proxy)

python3 - "$bundle" "$PROXY" <<'PY'
import glob, json, os, re, sys
import xml.etree.ElementTree as ET

bundle, expected_name = sys.argv[1], sys.argv[2]
errors, warnings = [], []
E, W = errors.append, warnings.append

def rel(p): return os.path.relpath(p, bundle)
def parse(p):
    try:
        return ET.parse(p).getroot()
    except ET.ParseError as e:
        E("%s: XML parse error: %s" % (rel(p), e)); return None

# --- manifest -----------------------------------------------------------------
manifests = [p for p in glob.glob(os.path.join(bundle, "*.xml")) if "<APIProxy" in open(p, encoding="utf-8", errors="replace").read()]
if len(manifests) != 1:
    E("expected exactly one <APIProxy> manifest at the bundle root, found %d" % len(manifests)); man = None
else:
    man = parse(manifests[0])
name = man.get("name") if man is not None else None
if man is not None and not name:
    E("%s: <APIProxy> has no name attribute" % rel(manifests[0]))
if expected_name and name and name != expected_name:
    W("manifest name %r differs from the configured proxy %r" % (name, expected_name))

def listed(tag, child):
    return sorted(e.text.strip() for e in man.findall("./%s/%s" % (tag, child)) if e.text) if man is not None else []

# --- files on disk ------------------------------------------------------------
def root_name(p):
    r = parse(p)
    return (r.get("name") or os.path.splitext(os.path.basename(p))[0]) if r is not None else os.path.splitext(os.path.basename(p))[0]

policy_files = sorted(glob.glob(os.path.join(bundle, "policies", "*.xml")))
proxy_files = sorted(glob.glob(os.path.join(bundle, "proxies", "*.xml")))
target_files = sorted(glob.glob(os.path.join(bundle, "targets", "*.xml")))
policies = {root_name(p): p for p in policy_files}
proxies = {root_name(p): p for p in proxy_files}
targets = {root_name(p): p for p in target_files}
resources = set()
for root, _, files in os.walk(os.path.join(bundle, "resources")):
    for f in files:
        kind = os.path.relpath(root, os.path.join(bundle, "resources")).split(os.sep)[0]
        resources.add("%s://%s" % (kind, f))

def compare(label, in_manifest, on_disk):
    for x in sorted(set(in_manifest) - set(on_disk)):
        W("manifest lists %s %r but there is no such file" % (label, x))
    for x in sorted(set(on_disk) - set(in_manifest)):
        W("%s %r exists on disk but is missing from the manifest (import regenerates the list; exports will differ)" % (label, x))

if man is not None:
    compare("policy", listed("Policies", "Policy"), policies)
    compare("resource", listed("Resources", "Resource"), resources)
    for x in sorted(set(listed("ProxyEndpoints", "ProxyEndpoint")) - set(proxies)):
        E("manifest lists ProxyEndpoint %r but proxies/ has no such file" % x)
    for x in sorted(set(listed("TargetEndpoints", "TargetEndpoint")) - set(targets)):
        E("manifest lists TargetEndpoint %r but targets/ has no such file" % x)
    compare("ProxyEndpoint", listed("ProxyEndpoints", "ProxyEndpoint"), proxies)
    compare("TargetEndpoint", listed("TargetEndpoints", "TargetEndpoint"), targets)
if not proxies:
    E("no ProxyEndpoint files in proxies/")

# --- steps, routes, conditions -------------------------------------------------
stepped = {}            # policy name -> set of endpoint kinds ("proxy"/"target") that step it
for kind, files in (("proxy", proxy_files), ("target", target_files)):
    for p in files:
        r = parse(p)
        if r is None: continue
        for s in r.iter("Step"):
            n = s.findtext("Name")
            if not n or not n.strip(): continue
            n = n.strip()
            stepped.setdefault(n, set()).add(kind)
            if n not in policies:
                E("%s: Step references policy %r which has no file in policies/" % (rel(p), n))
        for rr in r.iter("RouteRule"):
            t = rr.findtext("TargetEndpoint")
            if t and t.strip() and t.strip() not in targets:
                E("%s: RouteRule %r routes to TargetEndpoint %r which has no file in targets/" % (rel(p), rr.get("name"), t.strip()))
        for c in r.iter("Condition"):
            txt = (c.text or "").strip()
            if not txt: continue
            if " NotLike " in txt:
                W('%s: NotLike has failed deploy here with "Both operands for AND expression should be logical"; prefer Not (x Like y) or JavaRegex: %s' % (rel(p), txt))
            if re.search(r'!=\s*"', txt) and re.search(r'\s(and|or)\s', txt, re.I) and "(" not in txt:
                W('%s: unparenthesized != "literal" combined with and/or has failed deploy with "Both operands for AND expression should be logical"; wrap each comparison in parentheses: %s' % (rel(p), txt))
            if re.search(r'MatchesPath\s+"/"', txt):
                W('%s: MatchesPath "/" matches only an EMPTY path suffix, not "/"; use JavaRegex "^/?$": %s' % (rel(p), txt))
for n in sorted(set(policies) - set(stepped)):
    W("policy %r is never stepped from any flow (dead policy, or a Step is missing)" % n)

# --- per-policy gotchas ---------------------------------------------------------
for n, p in sorted(policies.items()):
    r = parse(p)
    if r is None: continue
    if r.tag == "BasicAuthentication":
        at = (r.findtext("AssignTo") or "").strip()
        if at != "request.header.Authorization":
            W("%s: BasicAuthentication <AssignTo> is %r; only request.header.Authorization writes the header (the policy still reports success otherwise)" % (rel(p), at or "missing"))
        for el in ("User", "Password"):
            e = r.find(el)
            if e is not None and not e.get("ref"):
                E('%s: BasicAuthentication <%s> must use ref=; a literal fails import with "The %s element is required"' % (rel(p), el, el))
    if r.tag == "AssignMessage" and r.find("./Set/Path") is not None:
        W("%s: AssignMessage <Set><Path> is ignored for the outbound target URL; set target.url (with target.copy.pathsuffix=false) or put the base path in the target <URL>" % rel(p))
    if r.tag == "AssignMessage":
        for av in r.iter("AssignVariable"):
            v = (av.findtext("Name") or "").strip()
            if v in ("target.url", "target.copy.pathsuffix") and stepped.get(n) == {"proxy"}:
                W("%s: sets %s but is stepped only from a ProxyEndpoint; that variable is reset at the TargetEndpoint boundary. Compute into custom.* here and apply it in the TargetEndpoint PreFlow" % (rel(p), v))
    for ru in list(r.iter("ResourceURL")) + list(r.iter("IncludeURL")):
        u = (ru.text or "").strip()
        if u and u not in resources:
            E("%s: %s %r has no file under resources/" % (rel(p), ru.tag, u))

# --- files that would land in the zip ------------------------------------------
allowed_top = {"policies", "proxies", "targets", "resources", "manifests"}
for root, dirs, files in os.walk(bundle):
    for f in files:
        p = os.path.join(root, f)
        r = rel(p)
        top = r.split(os.sep)[0]
        if f == ".DS_Store":
            W("%s: stray file (excluded from the zip, but delete it)" % r); continue
        if os.sep in r and top not in allowed_top:
            W("%s: unexpected top-level directory %r in the bundle" % (r, top))
        elif os.sep not in r and not (f.endswith(".xml") and "<APIProxy" in open(p, encoding="utf-8", errors="replace").read()):
            W("%s: unexpected file at the bundle root (only the <APIProxy> manifest belongs there)" % r)
        try:
            b = open(p, "rb").read(5_000_000)
        except OSError:
            continue
        if b"\0" not in b and b"\r\n" in b:
            W("%s: CRLF line endings (fetch.sh --lf normalizes)" % r)

for m in errors: sys.stderr.write("error:   %s\n" % m)
for m in warnings: sys.stderr.write("warning: %s\n" % m)
sys.stderr.write("%d error(s), %d warning(s) in %s\n" % (len(errors), len(warnings), bundle))
print(json.dumps({"bundleDir": bundle, "proxy": name, "errors": errors, "warnings": warnings}, indent=2))
sys.exit(1 if errors else 0)
PY
