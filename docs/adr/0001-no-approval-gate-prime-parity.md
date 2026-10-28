# ADR-0001: No approval/override gate — permission scoping instead, matching the existing Prime-based workflow

- **Status:** Accepted, tool-owner-directed 2026-10-26, pre-implementation.
- **Date:** 2026-10-26
- **Owner:** see README.md's own Owner section (TODO once assigned).

## Context

Every other mutating tool in this design family (`aws_prefix_update`'s
`sync`/`rollback`, and `obj_fw_block` before it) gates a real device
change behind a universal approval/override mechanism (doc 02 §E) — a
pending request needs a second person's sign-off in Webex before it can
actually execute, with a documented break-glass override path for when
that's not practical.

This tool pushes pre-defined Catalyst Center templates to GNOC-selected
switches — by doc 07 §7.1's own criteria (production-impacting config
push, multiple devices per run) it would normally be scored High risk,
which is exactly the tier doc 02 §E says needs this gate.

The GNOC team already runs the equivalent workflow today against the
same switches via Cisco Prime, and that workflow has **no approval gate
at all** — just a group of users with the permissions needed to execute
it. The tool owner's explicit direction: keep that parity. This tool is
replacing Prime's execution path, not introducing new process friction
on top of what GNOC already operates under today.

## Decision

1. **No approval/override field exists on `JobRequest`** (contrast
   `aws_prefix_update`'s `override`/`request_id` pair) — there is no
   pending-request state, no second sign-off, no break-glass path to
   document, because there is no gate to break past.
2. **Permission control happens entirely through account/group scoping,
   not a per-request workflow step:**
   - GNOC engineers' own human accounts are members of the existing
     `netauto-operators` group — this gates who can invoke the CLI at
     all, same tier `aws_prefix_update`/`obj_fw_block` operators already
     use.
   - The actual generated systemd units execute under a new,
     dedicated **`gnoc-service`** account — parallel to
     `aws_prefix_update`'s own `aws-prefix-svc` (doc 14 §14.1) — scoped
     minimally to only this tool's own runtime paths. Its purpose is
     purely to identify "this ran as a GNOC-related job" in file
     ownership/ACLs/the audit trail, and to keep that execution identity
     narrow, not to run as any broader service account.
3. **The guardrails doc 02 §D would normally expect an approval gate to
   backstop are implemented directly instead**, since this tool
   deliberately doesn't have the gate itself:
   - A hard, non-overridable cap on switches per job
     (`MAX_SWITCHES_PER_JOB` in `schema/models.py`) — the blast-radius
     limit an approval step would otherwise impose by making a human
     look at the request before it runs.
   - A protected-device deny-list (TODO once the Catalyst Center
     inventory-resolution step is built — mirrors `obj_fw_block`'s own
     canary/exclusion model).
   - A dry-run/preview step, if the Catalyst Center API version actually
     in use supports previewing a template deployment before committing
     it (TODO — depends on confirming the real CC API version against
     its own reference, not assumed from recall).

## Alternatives considered

- **Add the same universal approval gate as `aws_prefix_update`** —
  rejected by the tool owner specifically to avoid introducing new
  friction GNOC doesn't currently have under Prime. Scope-restricting
  who can act and what they're allowed to act on was judged sufficient,
  matching the status quo this tool replaces rather than exceeding it.
- **Add an approval gate only for jobs above some switch-count
  threshold** (a middle ground) — not raised by the tool owner, not
  pursued; the hard per-job switch cap already bounds the worst case of
  a single run without needing a second, conditional gate on top of it.

## Consequences

- This tool's own risk-tiering writeup (README.md's "Risk tier" section,
  TODO) needs to state this deviation explicitly and point back here —
  doc 07 §7.1's default expectation for a tool at this risk profile is
  an approval gate; this ADR is the documented reason this one doesn't
  have it, not an oversight.
- `docs/pipelines/guardrails.md` (TODO, mandatory per doc 11 §11.3) must
  list the switch-count cap, deny-list, and dry-run/preview explicitly as
  the guardrails doing the job an approval step would otherwise do —
  "known gaps kept visible rather than omitted" applies here: the
  absence of an approval gate is itself a gap worth stating plainly, not
  a silent design choice.
- If GNOC's own permission model ever changes (e.g. Prime itself grows
  an approval step), this ADR's premise — parity with the current,
  gate-less workflow — should be explicitly revisited, not left stale.
