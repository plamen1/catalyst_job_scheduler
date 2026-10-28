# Roadmap — aligning with automation-design

Tracks the phased work to bring this tool in line with the
[automation-design](https://github.com/plamen1/automation-design)
architecture, scored against
[doc 10's tool-maturity levels](https://github.com/plamen1/automation-design/blob/main/docs/10-implementation-roadmap.md#102-tool-maturity-phases)
(T1 → T5).

**This file is a maturity dashboard, not a decision log** (doc 06
§6.2/§6.3) — every real design decision lives in `docs/adr/`, every
real-run finding will live in `docs/findings/<component>.md` once
there's a real executor to find bugs in. This file points at those
rather than narrating them.

## Current maturity: pre-T1 — scoped and scaffolded, no role/executor yet (2026-10-28)

This tool was scoped entirely through a design conversation before any
Ansible role or Catalyst Center API integration was written (doc 11
§11.0: "a process checklist, not a design generator" — the design had
to exist first). What's actually done as of this entry: the input
schema (`schema/models.py`), its unit tests, the three ADRs for this
tool's foundational scoping and deliberate deviations from the rest of
this design family (`docs/adr/`), and the day-one skeleton files
(`.gitignore`, `.ansible-lint`, `.pre-commit-config.yaml`,
`requirements-dev.txt`, `scripts/{setup-python-env,deploy,rollback}.sh`).
**Nothing below T1's "Idempotent role" item is built yet** — no
`roles/`, no filter plugins, no `netauto` wiring, no real Catalyst
Center API calls.

---

## T1 — Core & dry-run

- [x] Input schema (`schema/models.py`) — `JobRequest`, single source
      of truth per [doc 04 §4.2](https://github.com/plamen1/automation-design/blob/main/docs/04-validation.md#42-schema-as-single-source-of-truth).
      17 unit tests passing.
- [ ] `schema/schema.json` regenerated and kept in sync — done once
      (2026-10-28), **nothing enforces staleness automatically**;
      re-run `python -m schema.export_schema` after every
      `models.py` change, same caveat as every sibling tool.
- [ ] Idempotent role — **not started.** Depends on confirming the real
      Catalyst Center API version in use (template-deploy and
      task-status endpoints differ between v1/v2 — check the actual
      API reference for the version in use, don't design from recall)
      and the `cisco.dnac` Ansible collection's httpapi plugin shape.
- [ ] Static analysis running for real — `black`/`flake8`/`mypy`/
      `bandit`/`pytest` all pass locally on `schema/`+`tests/` as of
      2026-10-28; `yamllint`/`ansible-lint` not yet run anywhere (no
      YAML task files exist yet to lint).
- [ ] `requirements.yml` — not created yet; needs the `cisco.dnac`
      collection pin once the role starts.
- [ ] Molecule `default` scenario — not started, blocked on the role
      existing at all.
- [x] Unit tests (pytest) for the schema — `tests/test_models.py`, 17
      cases, passing.
- [x] `.pre-commit-config.yaml` with `detect-secrets` — committed
      2026-10-28, **not yet activated anywhere** (see the T1 item
      below — same real gap `aws_prefix_update` hit on 2026-10-15,
      being avoided here by writing it down immediately instead of
      discovering it weeks later).
- [ ] `scripts/setup-python-env.sh` **run** (not just committed) in
      every clone that will ever commit here, including the real
      deployment host once one exists. Not yet run anywhere as of
      this entry.
- [x] `.gitignore` covering vault password files and runtime-generated
      artifacts — committed 2026-10-28, before any real credential or
      runtime file exists.

**Exit criteria:** reliably converges against a representative lab
Catalyst Center/switch pair. Not reachable yet — no lab target
confirmed.

## T2 — Guardrails hardened

This tool deliberately has **no approval/override gate** — see
[docs/adr/0001-no-approval-gate-prime-parity.md](adr/0001-no-approval-gate-prime-parity.md).
The guardrails below substitute for it; none are built yet.

- [ ] Fail loud, not silent, on invalid input — the pydantic schema
      already does this at the request-validation layer; needs
      confirming all the way through once an executor exists.
- [ ] Hard per-job switch-count cap (`MAX_SWITCHES_PER_JOB` = 25,
      `schema/models.py`) — **enforced in the schema already**, the
      executor/role still needs to exist to prove it's actually
      unbypassable end to end.
- [ ] Protected-device deny-list — not designed yet. Mirrors
      `obj_fw_block`'s own canary/exclusion model; needs the real
      inventory-resolution step to exist first.
- [ ] Dry-run/preview before committing a template deployment — depends
      on whether the Catalyst Center API version in use actually
      supports a template preview call. Not confirmed yet.
- [ ] Pre-change snapshot/backup — TODO, needs the real deploy API
      semantics confirmed first (what, if anything, Catalyst Center
      itself snapshots before a template push).
- [ ] Automated rollback — see README.md's own "Rollback procedure"
      TODO; genuinely undecided, needs its own deliberate "Model
      decision" entry once the deploy API shape is known.
- [ ] `armed`/`fired`/`missed` audit-log sequence + the missed-job
      sweep — see
      [docs/adr/0002-no-catchup-firing-on-missed-window.md](adr/0002-no-catchup-firing-on-missed-window.md).
      Not built yet; this is the mechanism that makes a VM-down miss
      visible instead of silent.
- [ ] Run via `netauto`, not raw `ansible-playbook` — not wired in yet.
- [ ] Negative Molecule scenario proving every guardrail above actually
      rejects what it claims to — blocked on the guardrails themselves
      existing first.

**Exit criteria:** every guardrail above has a passing compliance-as-
test. Not reachable yet.

## T3 — CLI self-service

- [ ] Interactive select prompts for Catalyst Center, template, and
      switches (all three resolved from live lists, never typed free
      text per the scoping decision below) — this is `netauto`'s job
      once this tool is wired in as a domain. Not done yet.
- [ ] `list`/`cancel` commands for pending scheduled jobs — agreed as
      in-scope for v1 (see
      [ADR-0003](adr/0003-initial-job-account-and-ha-scoping.md)), not
      built.
- [ ] No override/approval flow to rehearse — deliberately absent, see
      ADR-0001.
- [ ] Tagged release.
- [ ] Full documentation — `docs/architecture.md` + `docs/pipelines/
      *.md` + diagrams (**mandatory**, doc 11 §11.3), `docs/
      demo-scenarios.md`, rollback runbook, owner/on-call. **None of
      these exist yet** — explicitly tracked here, not silently
      deferred, per this project's own "pipeline docs on merge"
      discipline.
- [x] Risk tier assigned — **High**, see README.md's "Risk tier"
      section and ADR-0001 for why it deviates from this family's
      default High-risk shape (no approval gate).

**Exit criteria:** N successful executor-run production uses with zero
guardrail-bypass incidents. Not reachable yet.

## T4/T5

Not reachable until infrastructure Phase 1+/5 exists. Not relevant at
this stage — left as a stub per doc 10 §10.4.

---

## Documentation tasks

- [ ] README.md — **done, but several sections are TODO** pending the
      role/executor existing (Requirements, Running, Rollback
      procedure, Audit log, Syslog forwarding).
- [ ] Runbook: rollback steps, who to contact, how to interpret a
      failed run — not started.
- [ ] `docs/architecture.md` + `docs/pipelines/*.md` + diagrams
      (mandatory) — not started.
- [ ] `docs/demo-scenarios.md` — not started.
- [x] ADR for every foundational/guardrail decision — see `docs/adr/`
      (three as of 2026-10-28: no approval gate, no catch-up firing,
      initial job/account/HA scoping) — all written before any code
      that depends on them.

## Version-control tasks

- [ ] `CODEOWNERS` — not created yet.
- [ ] Branch protection on `main` — not configured yet.
- [ ] First tagged release — not reachable until T1 exit criteria are
      met.
- [x] `.pre-commit-config.yaml` + `.secrets.baseline` committed
      (2026-10-28) — **hook not yet activated anywhere**; see the T1
      item above, this exact gap is why it's called out twice.
- [x] `.gitignore` for vault password files and runtime artifacts.

---

## Open questions (revisit later, don't assume an answer)

See [ADR-0003](adr/0003-initial-job-account-and-ha-scoping.md) for the
full foundational-scoping record. Still genuinely undecided as of
2026-10-28:

- The missed-job sweep's own cadence/grace-period length — needs a
  real executor's typical deploy+poll duration first, not a guess.
- The protected-device deny-list's real content.
- Whether the Catalyst Center API version in use supports a template
  preview (the dry-run guardrail depends on this).
- The rollback model — inverse-via-Catalyst-Center vs. a second,
  operator-chosen "undo" template. Genuinely undecided, not defaulted.
