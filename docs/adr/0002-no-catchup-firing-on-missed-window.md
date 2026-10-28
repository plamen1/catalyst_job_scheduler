# ADR-0002: A missed scheduled window does not fire late — visible miss, not silent, not a catch-up run

- **Status:** Accepted, tool-owner-directed 2026-10-26, pre-implementation.
- **Date:** 2026-10-26
- **Owner:** see README.md's own Owner section (TODO once assigned).

## Context

Every scheduled job here is a dynamically-generated, one-shot systemd
timer (`OnCalendar=<exact datetime>`), not a recurring cadence like
`aws_prefix_update`'s feedwatch timer. If the automation VM is down at
the exact moment a job is supposed to fire, systemd's own
`Persistent=true` option would make that timer fire once as soon as the
VM comes back up, rather than being silently skipped.

This tool's execution is explicitly time-sensitive — a GNOC engineer
picks a date/time because that's when the change is supposed to happen
(a maintenance window, a program's own approved change schedule), not
an arbitrary "sometime around then." The tool owner's explicit call,
raised directly in response to a general single-automation-VM SPOF
question: a late, catch-up fire against a window that's already closed
is worse than the job simply not having run at all — it directly
answered the question of whether `Persistent=true`-style recovery was
wanted, and the answer was no.

## Decision

1. **Generated timer units do not set `Persistent=true`.** If the VM
   is down (or the timer service otherwise fails to run) at the exact
   `OnCalendar=` moment, the job does not fire, full stop — no catch-up
   on next boot/restart.
2. **A missed job must still be visible, not silent** — this is the
   gap this ADR exists to close, not just document. Because unit files
   are removed after firing (see README.md's "What it changes"/Audit
   log sections, TODO) and the only thing that would ever report an
   outcome is the executor itself running, a VM-down miss would
   otherwise leave zero signal anywhere that it happened. Closed by:
   - An `armed` audit-log entry written at schedule time (job id,
     Catalyst Center, switches, template, scheduled time, requester) —
     this, not the transient unit file, is the durable record that a
     job was supposed to run.
   - A periodic sweep (TODO, implementation pending) that finds
     `armed` entries with no matching `fired`/outcome entry past a
     grace period, sends exactly one Webex alert ("job `<id>` missed,
     reschedule manually"), then writes a `missed` entry so the same
     miss doesn't re-alert on every subsequent sweep tick.
   - A late-start guard in the executor itself, independent of
     `Persistent=false`: if the executor ever does run with "now"
     later than its own scheduled time plus a fixed tolerance (a
     resumed VM, a manual `systemctl start`, clock skew), it refuses
     and logs `missed` rather than firing late anyway. This makes "late
     is worse than never" an enforced property of the executor, not
     something that only holds because of how the timer happens to be
     configured.

## Alternatives considered

- **`Persistent=true`, fire late on recovery** — rejected directly by
  the tool owner; see Context. A late config push against a maintenance
  window that's already closed could land during live traffic the
  window was specifically chosen to avoid.
- **Build real multi-VM HA (a second automation VM, leader election,
  shared locking) to shrink the window where a miss is even possible** —
  raised as a side question, not pursued for this tool: disproportionate
  infrastructure for a low-frequency scheduled job, and doesn't actually
  change the decision above (a second VM still needs a "what if the
  window closes before this fires" answer; it only shrinks how often
  that question comes up, not what the answer is).
- **Say nothing further and accept a fully silent miss** — rejected:
  this was the gap flagged before any code existed (not yet confirmed
  against the tool owner's own direct request the way the rest of this
  ADR's content was), and left open would mean the only way GNOC learns
  a scheduled change never happened is noticing the switch itself never
  changed — not something this design should rely on.

## Consequences

- The `armed`/`fired`/`missed` audit-log vocabulary this ADR introduces
  needs to be the same structured format every other audit write in
  this project uses (doc 13) — not a parallel, tool-specific shape.
- `docs/pipelines/<flow>.md` (TODO, mandatory per doc 11 §11.3) must
  depict the missed-job sweep as its own flow, not just a footnote on
  the normal schedule → fire → outcome pipeline.
- The sweep's own schedule/cadence and grace-period length are
  implementation decisions still open — TODO once the executor itself
  is built and its own typical deploy-duration-plus-polling time is
  known, so the grace period isn't guessed ahead of having that number.
