# Apigee X gotchas (HUIT ADEX gateway)

Things that cost a debugging session at least once, collected from the
ats-snow-proxy, aais-splunk-api, aais-idphoto-api, aais-maestro-api, and
person-api-proxy repos. Read the relevant section before editing a bundle, and
the whole "Import, deploy, poll" section when an import or deploy fails.
Statements marked *observed* were seen on these orgs; the rest is documented
Apigee behavior confirmed here.

## Orgs, environments, hosts

- Three orgs, not one. `apigee-x-nonprod-406719` hosts `dev`, `test`, `sand`,
  `train`, `archive`. `apigee-x-preprod` hosts `stage`. `apigee-x-prod-406719`
  hosts `prod`. (Verified against the env groups API 2026-09-29; an older
  CLAUDE.md that says nonprod hosts stage is wrong.)
- Gateway hosts follow `go.<env>.apis.huit.harvard.edu`, except prod, which
  answers on both `go.apis.huit.harvard.edu` and
  `go.prod.apis.huit.harvard.edu`. `test` has its own host,
  `go.test.apis.huit.harvard.edu`; it is not served from the stage host.
  `train` and `archive` share dev's hostnames, so base paths must be unique
  across those three.
- **Revision numbers are per org.** The same bundle is rev 13 in nonprod and
  rev 2 in prod. Compare content, never numbers.
- `gcloud config get-value project` is whatever was set last. Any tool that
  takes the org from it silently will push stage or prod bundles into the
  wrong org. Always resolve the org from the environment.
- Env-based routing patterns in use: RouteRules on `environment.name`
  (snow: dev/test to the ServiceNow test instance, stage/prod to production;
  idphoto: one target per env plus `?env=test|stage` to force one); a single
  target with the URL computed from a path prefix (maestro rev 61+).
- Dev targets do not always point at dev data: person-api's dev target hits
  the stage OpenSearch cluster. A count mismatch between envs is not
  automatically a proxy bug.
- Promotion to stage and prod is, for some proxies, owned by another team's
  tool (person-api: the "HAPI Utility"). Put that in `.apigee.json`
  `envs.<env>.note` so the push skill prints it before asking for confirmation.

## Import, deploy, poll

- **Import is a multipart form POST** to
  `/v1/organizations/{org}/apis?action=import&name={proxy}` with
  `-F file=@bundle.zip`. *Observed:* the `application/octet-stream` body the
  REST docs suggest and the `/apis/{name}/revisions` import path both return
  404 on these orgs.
- `action=validate` on the same endpoint checks the bundle and creates no
  revision. Use it before every real import.
- The zip must contain the `apiproxy/` tree and nothing else. `.DS_Store`,
  an API product JSON, or an old zip next to the bundle all break or bloat
  the upload. The product JSON is not part of the deployable bundle.
- Deploy with `POST .../environments/{env}/apis/{proxy}/revisions/{rev}/deployments?override=true`.
  `override=true` replaces the deployed revision, so record the previous one
  first; there is no server-side undo.
- Poll `GET` on the same path. `.state` goes `PROGRESSING` to `READY` or
  `ERROR`; `.errors[].message` has the reason. READY within 30 to 50 seconds
  is typical. Two minutes without READY is worth investigating, not waiting
  out.
- `bundle contains errors` on import comes with `details[].violations[]`
  naming the file and the rule; print those, do not guess.
- A pulled export can differ from the repo copy in ways that do not matter:
  the manifest's `revision` attribute and timestamps, policies missing from
  the manifest `<Policies>` list (import regenerates it), and CRLF line
  endings when the export came through a Windows browser. Normalize before
  diffing.
- Auth is `gcloud auth print-access-token`. On a host without a browser:
  `gcloud auth login --no-launch-browser`. An expired login surfaces as
  gcloud's generic "set account" text; re-login is the fix.

## Conditions

- `MatchesPath "/"` matches only an **empty** path suffix, not `/`. For the
  root use `JavaRegex "^/?$"`; for "anything else" use `JavaRegex "/.+"`.
- *Observed (maestro):* `proxy.pathsuffix != "/"` and `NotLike "/"` failed
  deploy with `Both operands for AND expression should be logical`.
  *Also observed:* parenthesized `!=` comparisons such as
  `(request.verb != "GET")` and `(environment.name != "prod") and (...)`
  deploy and run fine in splunk and person-api. Parenthesize every comparison
  when combining with `and`/`or`; if a deploy still fails with that message,
  rewrite with `JavaRegex` or `Not (x Like y)`.
- Condition operators cannot do lexicographic string comparison
  (`"B" < "C"`). Do it in a JavaScript policy (idphoto's `clamp-sec-cat.js`).
- Gate steps with `!(request.verb = "OPTIONS")` where CORS preflight must pass.
- RouteRules are evaluated **after** the ProxyEndpoint flows. Anything that
  rewrites what a RouteRule reads (stripping `?env=` from the query string,
  for example) must not run in the proxy flow, or routing breaks.

## Path rewriting and the TargetEndpoint boundary

- AssignMessage `<Set><Path>` does **not** change the outbound target URL,
  with or without `target.copy.pathsuffix=false`, and `{proxy.pathsuffix}`
  templates inside it do not resolve.
- Two patterns that work. Pass-through: put the base path in the target
  `<URL>` and let Apigee append `proxy.pathsuffix`. Fixed path: set
  `target.url` fully and set `target.copy.pathsuffix=false`.
- `target.url` and `target.copy.pathsuffix` are **reset at the TargetEndpoint
  boundary**. Setting them in a ProxyEndpoint flow silently reverts. Compute
  the value into a `custom.*` variable in the proxy flow and apply it with
  `<AssignVariable><Name>target.url</Name><Ref>custom.target_url</Ref>` in the
  TargetEndpoint **PreFlow** request. Maestro's `js-parse-env-route` plus
  `am-set-target-url` is the reference implementation.
- Symptom of a lost path suffix: the request hits the target's root. A target
  that returns 200 on `/` (Splunk, most portals) masks the bug; a `POST` then
  returns 405 with `Allow: GET, HEAD, OPTIONS` and an HTML body. Compare an
  echoed `origin` or hit a path that 405s at the root.
- Apigee forwards the caller's query string verbatim. ORDS lets a query
  parameter override a header-sourced bind variable, so idphoto strips the
  query string in each target's PreFlow (`am-strip-target-queryparams`) and
  rejects known-dangerous parameters with a 400 (`fault-forbidden-queryparam`).
  Template parameters are safe; header-sourced binds are not.

## BasicAuthentication

- `<AssignTo>` must be `request.header.Authorization`. With
  `<AssignTo>request</AssignTo>` the policy reports `result=true` in trace and
  writes **no** header; the target then 401s.
- `<User>` and `<Password>` must use `ref=`. Literal values fail import with
  `The User element is required` / `The Password element is required`.
- `Unresolved variable : private.<name>` at run time means the KVM entry the
  policy reads is missing or misnamed, not that the policy is wrong.

## KVMs, shared flows, app attributes

- KVM entry names are conventions, not contracts. Snow's `ats-snow-proxy-kvm`
  key `apikey` holds a ServiceNow password. The KVM update path in the console
  was broken when that was noticed, which is why it is still misnamed.
- `private.*` variables are masked in trace. To see a value while debugging,
  assign it to a non-`private.` name temporarily, and remove that before
  shipping.
- A `FlowCallout` to a shared flow (idphoto's `fc-auth` to `adex-auth`) is a
  dependency that lives outside the repo. `fetch.sh` lists shared flows,
  KVM names, and target servers so those dependencies are visible.
- App attributes can carry JSON (`ats-common`), read with JSONPath such as
  `$.idphoto-api-v1.quota`, and can override a product-level quota.

## OpenAPI specs

- Apigee X validates OAS **3.0.x** only; 3.1 documents must be converted.
- The runtime OASValidation policy is stricter than the upload API: it
  rejects `extensions` fields and malformed `default` values that the upload
  accepted.
- The developer portal upload fails with 413 somewhere under 877 KB even
  after minifying. Strip descriptions, prune paths, or remove orphaned
  schemas.
- A `validate-spec` policy declared in the manifest but never stepped
  (snow, splunk) does nothing. The lint reports it.

## Debug sessions (trace)

- Create with `POST .../environments/{env}/apis/{proxy}/revisions/{rev}/debugsessions?timeout=180`.
  *Observed:* adding a `count` parameter returns 403. Fire requests, then read
  `.../debugsessions/{id}/data/{txn}`.
- A prod trace is the fastest way to confirm which policies ran and what the
  outbound request looked like (idphoto's query-string strip, splunk's
  missing Authorization header were both found this way).

## Testing

- The gateway rate-limits: a newman run needs `--delay-request 300` or it
  gets 429s. Consumer quota is 100 per minute on some products; throttle to
  about 80 and back off 30 seconds on 429.
- Base-path-only smoke tests prove almost nothing. Each repo has a better
  route table: splunk's `GET .../services/search/jobs?count=1` must return 200
  with `origin` ending in `/services/search/jobs`; person-api's
  `/monitor/health` with an API key; snow's `/table/incident?sysparm_limit=1`.
  Put them in `.apigee.json` `smoke`.
- The Apigee JavaScript runtime is Rhino, not Node: no modern ES features,
  and `Date` handling differs. `IncludeURL` files share one global scope with
  the `ResourceURL` script.

## gcloud login on networks that filter YouTube

*Observed 2026-10-04 from a café on the Harvard VPN; cost most of a morning.*

- **Symptom.** `gcloud auth login` (loopback flow or `--no-launch-browser`)
  gets through HarvardKey, then right after the g.harvard.edu account is
  chosen the browser shows "This site can't be reached",
  `ERR_SOCKET_NOT_CONNECTED`, on
  `https://accounts.youtube.com/accounts/SetSID?...`. Google Workspace
  sign-in always bounces through `accounts.youtube.com` once to sync the
  session cookie, so any network that blocks YouTube (cafés, hotels, some
  guest Wi-Fi) breaks every Google OAuth login, gcloud included. An old gcloud
  is not the cause; upgrading does not help.
- **Why the VPN does not help.** Cisco Secure Client on `vpn.harvard.edu`
  reports `Tunnel Mode: Tunnel All Traffic` but the headend pushes a
  **Dynamic Tunnel Exclusion** list (`youtube.com`, `ytimg.com`,
  `googleapis.com`, `gstatic.com`, `gmail.com`, plus Zoom, Teams, Office
  365, Netflix, Apple and others) that sends those hostnames straight out the
  local network. It is server policy; nothing in the client disables it and
  the local profile XML is rewritten on every connect. Note `googleapis.com`
  is on the list, so `apigee.googleapis.com` management calls also bypass the
  tunnel and depend on what the local network allows.
- **Diagnose in three commands.**
  ```sh
  /opt/cisco/secureclient/bin/vpn stats | grep -E 'Tunnel Mode|Dynamic Tunnel'
  route -n get 142.250.191.14      # a Google IP: "interface: en0" means it bypasses the tunnel
  curl -s -o /dev/null -w '%{http_code}\n' --max-time 10 https://accounts.youtube.com/
  ```
  `000` from the last one while `https://accounts.google.com/` answers is the
  signature. An empty `lsof -iTCP:8085` is normal for `--no-launch-browser`
  (that mode opens no local port) and is not the problem.
- **Fix.** Leave `gcloud auth login --no-launch-browser` waiting in its
  terminal, move the browser to a phone hotspot or any network that allows
  YouTube, finish the sign-in, copy the verification code, switch back, paste.
  The code does not care which network produced it. Reconnect the VPN before
  touching nonprod Apigee. The durable fix is a request to HUIT networking to
  take `youtube.com` (or at least `accounts.youtube.com`) off the exclusion
  list.
