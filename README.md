# catalyst_job_scheduler

## Purpose

Triggers pre-defined Cisco Catalyst Center template-deployment jobs
against GNOC-selected switches, either at a single scheduled future
point in time or immediately ("run now"). Replaces the equivalent
workflow GNOC currently runs by hand through Cisco Prime. An operator
picks a Catalyst Center instance (from a configured list), a template
(from that Catalyst Center's own template catalog), and switches
(resolved live from that Catalyst Center's own inventory API — not
NetBox); the tool then either arms a one-shot systemd timer for a
future fire time, or dispatches immediately.

## Owner

TODO — fill in once assigned. Same requirement as every other tool in
this design family (doc 06): this section must be filled in before the
tool is used outside its original author, including the on-call path
if a scheduled job fails or never fires.

## Risk tier

**High**, same as `aws_prefix_update`'s own `sync`/`rollback` — this is
a production-impacting config push against multiple devices in one run.

Unlike every other High-risk tool in this family, **this one
deliberately has no approval/override gate** — see
[docs/adr/0001-no-approval-gate-prime-parity.md](docs/adr/0001-no-approval-gate-prime-parity.md)
for why (parity with the existing Prime-based GNOC workflow, which has
none either) and what substitutes for it (account/group scoping, a hard
per-job switch-count cap, a protected-device deny-list, a dry-run/
preview step — guardrails doing the job an approval step would
otherwise do, doc 02 §D).

## Requirements

TODO once the role is built:
- The `cisco.dnac` Ansible collection (httpapi connection method, doc
  01 §1.7 — this tool has no device CLI session, unlike
  `obj_fw_block`/`aws_prefix_update`'s `network_cli` roles).
- Whatever Python package that collection's httpapi plugin needs on the
  controller (likely `dnacentersdk` — confirm against the real
  collection version and Catalyst Center API version in use, see
  `requirements-dev.txt`'s own note; do not assume this from recall).
- Python dev/CI tooling: see `requirements-dev.txt`. Run
  `./scripts/setup-python-env.sh` to install all of it (venv,
  `requirements.yml`'s collections, and the `pre-commit` git hook) in
  one step — **this is the step that actually activates
  `.pre-commit-config.yaml`'s checks on `git commit`/`git push`**.
- Credentials: per-Catalyst-Center API credentials, vault-encrypted —
  shape TBD alongside the role/netauto-registry wiring (one
  `authentication/<name>.yml` per configured Catalyst Center, following
  `aws_prefix_update`'s own `authentication/netbox_auth.yml` precedent,
  is the likely shape but not yet built).
- Two-machine split: same as every sibling tool — `ansible-core`/
  `ansible-lint` don't run natively on Windows; schema/pytest work
  happens on the Windows dev machine, Ansible/Molecule work on a
  separate Linux box.

## Running

TODO once wired into `netauto` as a domain (not yet done — see
docs/ROADMAP.md):

```
netauto catalyst_job schedule --catalyst-center <name> --template <id> \
  --switches <...> --at <datetime> --justification "..."
netauto catalyst_job run-now --catalyst-center <name> --template <id> \
  --switches <...> --justification "..."
netauto catalyst_job list
netauto catalyst_job cancel --job-id <id>
```

## Inputs

Mirrors `schema/models.py`'s `JobRequest` — see that file for the
authoritative definition (doc 04 §4.2: the schema is the single source
of truth, this table must not diverge from it).

| Field | Type | Required? | Notes |
|---|---|---|---|
| `catalyst_center` | string | yes | Chosen from netauto's configured list; re-validated live at dispatch time |
| `template_id` | string | yes | Chosen from that Catalyst Center's own template catalog |
| `switches` | list of strings | yes | 1–25 (`MAX_SWITCHES_PER_JOB`), resolved live from that Catalyst Center's inventory API, no duplicates/blanks |
| `run_trigger` | `manual` \| `scheduled` | no (default `scheduled`) | `manual` = run now, no timer; `scheduled` requires `scheduled_time` |
| `scheduled_time` | datetime | required if `scheduled`, forbidden if `manual` | Must be ≥2 minutes in the future (`MIN_SCHEDULING_LEAD`) |
| `justification` | string | yes | Free text, rejected if it contains Jinja template delimiters |
| `requester` | string | yes | The GNOC engineer's identity |

## What it changes

Pushes a pre-defined Catalyst Center template to the switches named in
`switches` — nothing else. This tool never resolves or acts on a device
outside that explicit, operator-chosen list; there is no fleet-wide or
site-wide implicit scope. Device-level outcome (which switches actually
succeeded vs. failed within a job) is tracked per device — see Audit
log below.

## Rollback procedure

TODO — not yet designed. Unlike `aws_prefix_update`'s inverse-the-delta
model, a template deployment's rollback shape depends entirely on
whether Catalyst Center's own template programmer exposes an inverse/
undo operation, or whether this needs its own separate "rollback
template" selected by the operator the same way the forward job is.
Needs a deliberate decision once the role/API integration exists — see
`obj_fw_block/docs/ROADMAP.md`'s "Model decision" entry for the
reasoning process to follow, don't default to one without writing down
why.

## Audit log

TODO once the executor exists. Planned shape (see
[docs/adr/0002-no-catchup-firing-on-missed-window.md](docs/adr/0002-no-catchup-firing-on-missed-window.md)):
a structured `armed` → `fired` → outcome (per-device pass/fail, overall
success only if *all* devices succeeded) → or `missed` event sequence
per job id, written to `output_files/audit_log.jsonl` following doc 13's
fixed schema. This is the durable record of what was scheduled/ran —
the generated systemd unit files themselves are deleted after firing,
so this log, not the unit files, is the source of truth for "what
happened."

## Syslog forwarding

TODO — see [doc 13](https://github.com/plamen1/automation-design/blob/main/docs/13-syslog-audit-forwarding.md)
for the fixed schema every project follows (RFC 5424 over UDP,
`send_syslog.py` copied as-is, one forwarding task per audit-write
site). Document the four required group_vars here (`syslog_host`,
`syslog_port`, `reporting_host`, `scripts`) once the role exists — never
commit real values.

## Repository layout

```
schema/            JobRequest (schema/models.py), schema.json export
tests/             pytest unit tests for the schema
scripts/           setup-python-env.sh, deploy.sh, rollback.sh
docs/
  adr/             Architecture Decision Records
  ROADMAP.md        maturity tracked against doc 10's T1-T5
roles/              TODO - not yet built (role skeleton, filter_plugins,
                    CONFIG_<ACTION>.yml task file)
```

## Related design documentation

- [automation-design](https://github.com/plamen1/automation-design) —
  the standard this tool is built against.
- [docs/adr/0001-no-approval-gate-prime-parity.md](docs/adr/0001-no-approval-gate-prime-parity.md)
- [docs/adr/0002-no-catchup-firing-on-missed-window.md](docs/adr/0002-no-catchup-firing-on-missed-window.md)
- [docs/ROADMAP.md](docs/ROADMAP.md) — maturity tracked against
  [doc 10](https://github.com/plamen1/automation-design/blob/main/docs/10-implementation-roadmap.md)'s
  T1–T5 checkboxes.
- `docs/architecture.md` + `docs/pipelines/` + `docs/demo-scenarios.md` —
  **not yet written**, mandatory per
  [doc 11 §11.3](https://github.com/plamen1/automation-design/blob/main/docs/11-project-template.md#113-the-diagrampipeline-doc-requirement-mandatory)
  before this tool reaches T2 exit. Tracked in docs/ROADMAP.md, not
  silently skipped.
