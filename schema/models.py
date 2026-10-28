"""Input schema for catalyst_job_scheduler.

Single source of truth for what a valid job request looks like (doc 04
§4.2 of automation-design). Exported to schema.json (export_schema.py) -
that JSON file, not this Python module, is what netauto actually
validates against at runtime, matching aws_prefix_update's own split.

One request = one pre-defined Catalyst Center template deployed against
an operator-chosen set of switches, either scheduled for a single future
point in time (a one-shot systemd timer gets generated for it) or run
immediately ("run now", same schema and executor, no timer involved).

No approval/override field exists on this model, unlike
aws_prefix_update's `override`/`request_id` pair - deliberate, see
docs/adr/0001-no-approval-gate-prime-parity.md. Permission control for
this tool lives entirely in account/group scoping (who can invoke the
CLI at all, and what the execution account itself is allowed to touch),
not in a per-request sign-off step.
"""

from __future__ import annotations

from datetime import datetime, timedelta, timezone
from enum import Enum
from typing import List, Optional

from pydantic import BaseModel, Field, field_validator, model_validator

# Hard ceiling, not an operator-adjustable field like aws_prefix_update's
# le_ceiling/max_added/max_removed - those are legitimate per-run tuning
# knobs; this is a deliberate blast-radius guardrail substituting for the
# approval gate this tool doesn't have (doc 02 §D). Split a job that
# genuinely needs more switches into multiple job requests instead of
# raising this.
MAX_SWITCHES_PER_JOB = 25

# Minimum lead time between "job accepted" and its scheduled fire time -
# the root-mediated sudo helper needs a real window to install the
# generated systemd timer+service unit pair and run daemon-reload before
# the clock catches up to it.
MIN_SCHEDULING_LEAD = timedelta(minutes=2)

_JINJA_MARKERS = ("{{", "{%", "{#")


class RunTrigger(str, Enum):
    MANUAL = "manual"
    SCHEDULED = "scheduled"


class JobRequest(BaseModel):
    """One Catalyst Center template-deployment job.

    `catalyst_center` and `template_id` are opaque identifiers chosen
    from lists netauto itself resolves (the configured Catalyst Center
    inventory, and that CC's own template catalog) - this schema only
    validates that something was actually chosen, not that it's a real
    id; a real id gets confirmed live against the CC's own API at
    dispatch time, the same "selected from a list, re-validated against
    the live system before acting" shape aws_prefix_update already uses
    for its target-confirmation preview.

    `switches` is resolved live from the chosen Catalyst Center's own
    inventory API at job-definition time (not NetBox - see
    docs/ROADMAP.md), so by the time this model sees it, it's already a
    list of real device identifiers an operator picked from a live list,
    not typed free text.
    """

    catalyst_center: str = Field(..., min_length=1)
    template_id: str = Field(..., min_length=1)
    switches: List[str] = Field(..., min_length=1, max_length=MAX_SWITCHES_PER_JOB)

    run_trigger: RunTrigger = RunTrigger.SCHEDULED
    scheduled_time: Optional[datetime] = None

    justification: str = Field(..., min_length=1)
    requester: str = Field(..., min_length=1)

    @field_validator("switches")
    @classmethod
    def _switches_non_blank_and_unique(cls, value: List[str]) -> List[str]:
        cleaned = [v.strip() for v in value]
        if any(not v for v in cleaned):
            raise ValueError("switches must not contain blank entries")
        if len(set(cleaned)) != len(cleaned):
            raise ValueError("switches must not contain duplicates")
        return cleaned

    @field_validator("justification")
    @classmethod
    def _justification_rejects_jinja_markers(cls, value: str) -> str:
        # automation-design doc 14 §14.6 - justification is free text,
        # logged/posted to Webex+syslog verbatim; closing this off at the
        # schema boundary regardless of whether anything downstream
        # actually templates it today. Same rule as aws_prefix_update's
        # own justification field.
        if any(marker in value for marker in _JINJA_MARKERS):
            raise ValueError("justification must not contain Jinja template delimiters")
        return value

    @model_validator(mode="after")
    def _scheduled_time_matches_run_trigger(self) -> "JobRequest":
        if self.run_trigger == RunTrigger.SCHEDULED:
            if self.scheduled_time is None:
                raise ValueError(
                    "scheduled_time is required when run_trigger is 'scheduled'"
                )
            now = datetime.now(timezone.utc)
            target = self.scheduled_time
            if target.tzinfo is None:
                target = target.replace(tzinfo=timezone.utc)
            if target < now + MIN_SCHEDULING_LEAD:
                raise ValueError(
                    f"scheduled_time must be at least {MIN_SCHEDULING_LEAD} in the future"
                )
        elif self.scheduled_time is not None:
            raise ValueError(
                "scheduled_time must not be set when run_trigger is 'manual'"
            )
        return self
