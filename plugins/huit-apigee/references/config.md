# huit-apigee configuration

Two files, both at the repo root of a proxy project. Every key is optional; a
repo with no `.apigee.json` still works for `dev` on the HUIT orgs.

## `.apigee.json` (committed)

```json
{
  "proxy": "ats-snow-proxy",
  "bundleDir": "ats-snow-proxy/apiproxy",
  "envs": {
    "dev":   { "org": "apigee-x-nonprod-406719" },
    "stage": { "org": "apigee-x-preprod", "confirm": true, "note": "Promotion to stage is owned by <team>; ask before deploying." },
    "prod":  { "org": "apigee-x-prod-406719", "host": "go.apis.huit.harvard.edu", "confirm": true }
  },
  "prePush": "python3 scripts/convert-spec-3.0.py spec.json out.json",
  "smoke": [
    { "path": "/monitor/health", "expect": 200 },
    { "path": "/table/incident?sysparm_limit=1", "headers": { "x-api-key": "$DEV_APIKEY" }, "expect": 200 },
    { "path": "/services/search/jobs", "method": "POST", "expect": 405 }
  ],
  "postDeploy": "scripts/test.sh postman"
}
```

| Key | Meaning | Default |
|---|---|---|
| `proxy` | API proxy name in Apigee | the `name` attribute of the `<APIProxy>` manifest in `bundleDir` |
| `bundleDir` | path of the `apiproxy/` directory, relative to this file | the single `*/apiproxy/` under the repo; more than one (idphoto has `apigee-x/` and a retired `archive/`) is refused until this key pins it |
| `envs.<env>.org` | Apigee org (GCP project) that hosts `<env>` | the HUIT table below |
| `envs.<env>.host` | gateway hostname for smoke tests | derived from the org's environment groups (`hosts.sh --env`) |
| `envs.<env>.confirm` | ask the person before importing or deploying to this env | `true` for `stage` and `prod`, `false` otherwise |
| `envs.<env>.note` | text the push skill prints before asking for confirmation | none |
| `prePush` | shell command run from the repo root before lint and import (spec regeneration, code generation) | none |
| `smoke` | routes to hit after deploy; `path` is appended to the bundle's `<BasePath>`; `method` defaults to `GET`; `headers` values starting with `$` are read from the environment at run time and never printed; `expect` is a status code | one `GET <BasePath>/` where anything but a gateway 404 counts as reachable |
| `postDeploy` | shell command run from the repo root after a successful smoke (newman, integration tests) | none |

Never put a key, token, or password in this file. Reference an environment
variable (`"$DEV_APIKEY"`) and keep the value in the person's shell or a
gitignored `.env`.

## Resolution order

Flags beat config, config beats defaults, and the scripts say where a value
came from when it came from a default.

- **proxy:** `--proxy`/positional > `proxy` > manifest name.
- **bundle dir:** `--bundle-dir` > `bundleDir` > the single `apiproxy/` found (max depth 4, skipping `node_modules` and `.git`).
- **org:** `--org` > `envs.<env>.org` > HUIT table > gcloud's active project, with a warning. The old commands used gcloud's project silently, which is how a stage or prod push could land in the wrong org.
- **host:** `--host` > `envs.<env>.host` > the `go.*` hostname of the env group the environment is attached to.

## HUIT defaults (verified 2026-09-29 against the environment groups API)

| Environment | Org | Gateway host |
|---|---|---|
| `dev` | `apigee-x-nonprod-406719` | `go.dev.apis.huit.harvard.edu` |
| `test` | `apigee-x-nonprod-406719` | `go.test.apis.huit.harvard.edu` |
| `sand` | `apigee-x-nonprod-406719` | `go.sand.apis.huit.harvard.edu` |
| `train` | `apigee-x-nonprod-406719` | `go.dev.apis.huit.harvard.edu` (shares dev's group) |
| `archive` | `apigee-x-nonprod-406719` | `go.dev.apis.huit.harvard.edu` (shares dev's group) |
| `stage` | `apigee-x-preprod` | `go.stage.apis.huit.harvard.edu` |
| `prod` | `apigee-x-prod-406719` | `go.apis.huit.harvard.edu` (also `go.prod.apis.huit.harvard.edu`; both are attached) |

Every group also carries a bare `<env>.apis.huit.harvard.edu` and an
`apigee-x.<env>.apis.huit.harvard.edu` hostname; the `go.` one is the ADEX
virtual host every proxy is documented under, so the scripts prefer it. Two
earlier claims were wrong: `test` is not served from the stage host (it has
its own), and stage is not in the nonprod org. Revision numbers restart per
org, so "rev 13" in nonprod and "rev 2" in prod can be the same bundle.
Re-run `hosts.sh --org <org>` if a host stops answering; this table is a
snapshot.

## `.apigee-state.json` (gitignored)

Written by `fetch.sh` (the `pull` skill), read by the `push` skill's drift check.

```json
{
  "proxy": "ats-snow-proxy",
  "org": "apigee-x-nonprod-406719",
  "revision": "2",
  "fetchedAt": "2026-09-29T15:27:05Z",
  "bundleDir": "ats-snow-proxy/apiproxy",
  "deployments": [ { "environment": "dev", "revision": "2" } ]
}
```

`push` compares `revision` against the org's current `latestRevisionId`. A
higher latest revision means someone imported since the last pull, and the
local bundle may be missing their change. The file is a hint, not a lock: a
missing state file only means "no drift check possible", and the diff against
the deployed revision still runs.
