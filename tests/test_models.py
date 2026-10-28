from datetime import datetime, timedelta, timezone

import pytest
from pydantic import ValidationError

from schema.models import MAX_SWITCHES_PER_JOB, JobRequest, RunTrigger


def _future(minutes: int = 10) -> datetime:
    return datetime.now(timezone.utc) + timedelta(minutes=minutes)


def test_scheduled_valid():
    req = JobRequest(
        catalyst_center="dc-east",
        template_id="vlan-prune-v3",
        switches=["sw-east-01", "sw-east-02"],
        run_trigger=RunTrigger.SCHEDULED,
        scheduled_time=_future(),
        justification="maintenance window change",
        requester="gnoc.engineer",
    )
    assert req.run_trigger == RunTrigger.SCHEDULED
    assert req.switches == ["sw-east-01", "sw-east-02"]


def test_manual_valid_without_scheduled_time():
    req = JobRequest(
        catalyst_center="dc-east",
        template_id="vlan-prune-v3",
        switches=["sw-east-01"],
        run_trigger=RunTrigger.MANUAL,
        justification="run now",
        requester="gnoc.engineer",
    )
    assert req.scheduled_time is None


def test_manual_with_scheduled_time_rejected():
    with pytest.raises(ValidationError, match="must not be set"):
        JobRequest(
            catalyst_center="dc-east",
            template_id="vlan-prune-v3",
            switches=["sw-east-01"],
            run_trigger=RunTrigger.MANUAL,
            scheduled_time=_future(),
            justification="run now",
            requester="gnoc.engineer",
        )


def test_scheduled_without_scheduled_time_rejected():
    with pytest.raises(ValidationError, match="is required"):
        JobRequest(
            catalyst_center="dc-east",
            template_id="vlan-prune-v3",
            switches=["sw-east-01"],
            run_trigger=RunTrigger.SCHEDULED,
            justification="maintenance window change",
            requester="gnoc.engineer",
        )


def test_scheduled_time_too_close_rejected():
    with pytest.raises(ValidationError, match="at least"):
        JobRequest(
            catalyst_center="dc-east",
            template_id="vlan-prune-v3",
            switches=["sw-east-01"],
            run_trigger=RunTrigger.SCHEDULED,
            scheduled_time=_future(minutes=1),
            justification="maintenance window change",
            requester="gnoc.engineer",
        )


def test_scheduled_time_in_past_rejected():
    with pytest.raises(ValidationError, match="at least"):
        JobRequest(
            catalyst_center="dc-east",
            template_id="vlan-prune-v3",
            switches=["sw-east-01"],
            run_trigger=RunTrigger.SCHEDULED,
            scheduled_time=datetime.now(timezone.utc) - timedelta(minutes=5),
            justification="maintenance window change",
            requester="gnoc.engineer",
        )


def test_switches_required_non_empty():
    with pytest.raises(ValidationError):
        JobRequest(
            catalyst_center="dc-east",
            template_id="vlan-prune-v3",
            switches=[],
            run_trigger=RunTrigger.MANUAL,
            justification="run now",
            requester="gnoc.engineer",
        )


def test_switches_over_ceiling_rejected():
    with pytest.raises(ValidationError):
        JobRequest(
            catalyst_center="dc-east",
            template_id="vlan-prune-v3",
            switches=[f"sw-{i}" for i in range(MAX_SWITCHES_PER_JOB + 1)],
            run_trigger=RunTrigger.MANUAL,
            justification="run now",
            requester="gnoc.engineer",
        )


def test_switches_at_ceiling_valid():
    req = JobRequest(
        catalyst_center="dc-east",
        template_id="vlan-prune-v3",
        switches=[f"sw-{i}" for i in range(MAX_SWITCHES_PER_JOB)],
        run_trigger=RunTrigger.MANUAL,
        justification="run now",
        requester="gnoc.engineer",
    )
    assert len(req.switches) == MAX_SWITCHES_PER_JOB


def test_switches_blank_entry_rejected():
    with pytest.raises(ValidationError, match="blank"):
        JobRequest(
            catalyst_center="dc-east",
            template_id="vlan-prune-v3",
            switches=["sw-east-01", "   "],
            run_trigger=RunTrigger.MANUAL,
            justification="run now",
            requester="gnoc.engineer",
        )


def test_switches_duplicate_rejected():
    with pytest.raises(ValidationError, match="duplicates"):
        JobRequest(
            catalyst_center="dc-east",
            template_id="vlan-prune-v3",
            switches=["sw-east-01", "sw-east-01"],
            run_trigger=RunTrigger.MANUAL,
            justification="run now",
            requester="gnoc.engineer",
        )


def test_catalyst_center_required():
    with pytest.raises(ValidationError):
        JobRequest(
            catalyst_center="",
            template_id="vlan-prune-v3",
            switches=["sw-east-01"],
            run_trigger=RunTrigger.MANUAL,
            justification="run now",
            requester="gnoc.engineer",
        )


def test_template_id_required():
    with pytest.raises(ValidationError):
        JobRequest(
            catalyst_center="dc-east",
            template_id="",
            switches=["sw-east-01"],
            run_trigger=RunTrigger.MANUAL,
            justification="run now",
            requester="gnoc.engineer",
        )


def test_requester_required():
    with pytest.raises(ValidationError):
        JobRequest(
            catalyst_center="dc-east",
            template_id="vlan-prune-v3",
            switches=["sw-east-01"],
            run_trigger=RunTrigger.MANUAL,
            justification="run now",
            requester="",
        )


@pytest.mark.parametrize("marker", ["{{", "{%", "{#"])
def test_justification_rejects_jinja_markers(marker):
    with pytest.raises(ValidationError, match="Jinja template delimiters"):
        JobRequest(
            catalyst_center="dc-east",
            template_id="vlan-prune-v3",
            switches=["sw-east-01"],
            run_trigger=RunTrigger.MANUAL,
            justification=f"legit reason {marker} lookup('file','/etc/passwd') }}",
            requester="gnoc.engineer",
        )
