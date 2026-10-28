"""Export JobRequest as portable JSON Schema.

Run `python -m schema.export_schema` from the repo root to (re)generate
schema.json - the artifact netauto's catalyst_job domain reads to drive
its prompts and pre-execution validation, a JSON file, not a Python
import, so netauto never needs this repo's Python package on its own
path. Regenerate and commit whenever models.py changes; nothing enforces
staleness automatically, so it is only as current as the last person who
ran this after editing models.py.
"""

from __future__ import annotations

import json
from pathlib import Path

from schema.models import JobRequest

SCHEMA_PATH = Path(__file__).parent / "schema.json"


def main() -> None:
    schema = JobRequest.model_json_schema()
    SCHEMA_PATH.write_text(json.dumps(schema, indent=2) + "\n")
    print(f"Wrote {SCHEMA_PATH}")


if __name__ == "__main__":
    main()
