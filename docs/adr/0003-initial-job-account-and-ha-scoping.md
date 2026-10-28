# ADR-0003: Initial job shape, account model, and HA/duplicate-call scoping

- **Status:** Accepted, tool-owner-directed, 2026-10-26 through
  2026-10-28, pre-implementation.
- **Date:** 2026-10-26
- **Owner:** see README.md's own Owner section (TODO once assigned).
- **Relocated from `docs/ROADMAP.md`'s "Scoping decisions" section,
  2026-10-28** — content below is the original record, not rewritten,
  per automation-design doc 06 §6.2/§6.3's decision/finding split.
- **See also:** [ADR-0001](0001-no-approval-gate-prime-parity.md) (the
  permission-scoping decision this account model implements),
  [ADR-0002](0002-no-catchup-firing-on-missed-window.md) (the HA/
  missed-window decision this ADR's own HA bullet summarizes).

## Context

Before any code existed, this tool needed its foundational shape
decided through a design conversation: what a job actually consists
of, who can create one and under what account, how the automation
VM's single-point-of-failure risk should be handled, and how to
prevent a job firing twice.

## Decision

- **Job shape**: operator picks a Catalyst Center (from a configured
  list), a template (from that Catalyst Center's own template
  catalog — no custom per-job parameters; whatever variables the
  template itself needs are Catalyst Center's own concern), and
  switches (resolved **live from that Catalyst Center's inventory
  API**, not NetBox — avoids a NetBox-cleanup dependency for v1). A
  single point-in-time fire, not a start/end window.
- **No approval gate** — parity with the current Prime-based GNOC
  workflow, which has none either. See
  [ADR-0001](0001-no-approval-gate-prime-parity.md).
- **Account model**: GNOC engineers' own accounts join the existing
  `netauto-operators` group (same tier every other operator uses). The
  actual generated systemd units run as a new, dedicated
  **`gnoc-service`** account, parallel to `aws_prefix_update`'s own
  `aws-prefix-svc` (doc 14 §14.1) — minimally scoped, exists only to
  tag "this ran as a GNOC-related job" in ownership/ACLs/the audit
  trail.
- **Unit-creation privilege model**: a **root-mediated sudo helper**
  that takes only a validated job id and installs a fixed template
  unit — mirrors the sudo-mediated pattern `aws_prefix_update` already
  uses, chosen over `gnoc-service`'s own user-level systemd
  (`systemd-run --user`) specifically so a GNOC engineer invoking this
  tool never gains a general root-reachable write path.
- **HA/SPOF**: raised as a side question (the automation VM is a
  single point of failure) — explicitly **not** solved with a second
  VM; solved instead with `Persistent=false` (a missed window stays
  missed, never fires late) plus a durable `armed`/`fired`/`missed`
  audit trail and a one-time missed-job Webex alert, so the miss is
  visible rather than silent. See
  [ADR-0002](0002-no-catchup-firing-on-missed-window.md). A second
  automation VM was explicitly considered and rejected as
  disproportionate infrastructure for this tool's own risk profile.
- **Duplicate-call prevention**: a `fired` audit-log entry is written
  *before* the Catalyst Center deploy call, not after (claim, then
  act) — refuses if `fired` already exists for a job id. `run-now`
  against an already-armed job id is refused unless that job is
  cancelled first.
- **Switch/template overlap**: two different jobs (different
  templates) are explicitly allowed against the same switches at
  different times — the guardrail is a **minimum time-spacing
  buffer** between two armed jobs that share a switch (long enough to
  cover the slower template's expected deploy+poll duration), not a
  blanket "one pending job per switch."
- **Per-device success**: a template deploy to N switches can
  partially succeed. Plan: report per-device pass/fail; overall job
  success only if *all* devices succeeded.
- **Repo/remote**: new standalone repo
  (`github.com/plamen1/catalyst_job_scheduler`), not bolted onto
  `aws_prefix_update` or folded into `netauto` itself — wired into
  `netauto` as a third domain once the role exists.

## Alternatives considered

- **Switch/template overlap guardrail: refuse if any switch already
  has ANY pending job** — an initial, too-strict draft; rejected by
  the tool owner, who pointed out two different jobs (different
  templates) against the same switch at genuinely different times are
  legitimate and must be allowed. Replaced with the minimum
  time-spacing buffer above.
- **A second automation VM for HA** — considered and rejected; see
  [ADR-0002](0002-no-catchup-firing-on-missed-window.md)'s own
  Alternatives section for the full reasoning.
- **`gnoc-service`'s own user-level systemd** (`systemd-run --user`)
  for unit creation — rejected in favor of the root-mediated sudo
  helper specifically to avoid giving a GNOC engineer any
  root-reachable write path.

## Consequences

- **Still open, deliberately not decided yet** (as of 2026-10-28): the
  missed-job sweep's own cadence/grace-period length (needs a real
  executor's typical deploy+poll duration first, not a guess); the
  protected-device deny-list's real content; whether Catalyst Center's
  API version in use supports a template preview (the dry-run
  guardrail depends on this); the rollback model (inverse-via-Catalyst-
  Center vs. a second, operator-chosen "undo" template — genuinely
  undecided, not defaulted).
- `list`/`cancel` commands for pending scheduled jobs are in-scope for
  v1 as a direct consequence of allowing multiple parallel future
  jobs — tracked in `docs/ROADMAP.md`'s T3 checklist.
- All three device inputs (Catalyst Center, template, switches) being
  resolved from live lists rather than typed free text is what the
  T3 "interactive select prompts" checklist item depends on.
