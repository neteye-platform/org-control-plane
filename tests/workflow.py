"""Read the scripts embedded in the GitHub Actions workflows.

The reusable workflows keep their scripts inline, so that another repository can
call them. The tests extract a script by step name with the standard library
only: the block scalar after `run: |` or `script: |`.
"""

from __future__ import annotations

import re
import textwrap
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
WORKFLOWS = ROOT / ".github" / "workflows"


def step_script(workflow: str, step_name: str, key: str) -> str:
    """Return the `key: |` block of the step named `step_name` in `workflow`."""
    lines = (WORKFLOWS / workflow).read_text(encoding="utf-8").splitlines()
    step = next(
        (
            i
            for i, line in enumerate(lines)
            if re.fullmatch(rf"\s*- name: {re.escape(step_name)}", line)
        ),
        None,
    )
    if step is None:
        raise LookupError(f"step {step_name!r} not found in {workflow}")

    step_indent = len(lines[step]) - len(lines[step].lstrip())
    for i in range(step + 1, len(lines)):
        line = lines[i]
        indent = len(line) - len(line.lstrip())
        if line.strip() and indent <= step_indent:
            break
        if line.strip() == f"{key}: |":
            block = []
            for body in lines[i + 1 :]:
                if body.strip() and len(body) - len(body.lstrip()) <= indent:
                    break
                block.append(body)
            return textwrap.dedent("\n".join(block)).strip("\n") + "\n"
    raise LookupError(f"step {step_name!r} in {workflow} has no `{key}: |` block")
