"""Measure the engine-free gates and write the verdict to a durable file.

Three problems this solves, all from concurrent-agent interference:
  - `build/logs/` gets wiped by other agents mid-run, so the verdict goes to the
    repo root, which nothing cleans.
  - A shell pipeline that redirects swallows the output, so nothing pipes here;
    subprocess captures directly and the script writes the file itself.
  - The owner must not watch a foreground gate, so this is launched with
    `run_in_background: true` and polled.
"""

import subprocess
import sys
from pathlib import Path

STAGES = [
    ["fmt", "--check"],
    ["lint"],
    ["arch"],
    ["mutation_history", "check"],
    ["godot_bypass"],
    ["deferred", "validate"],
    ["incident", "validate"],
    ["backlog", "validate"],
    ["data", "audit"],
    ["gate_reach", "check"],
    ["map_theme", "check"],
    ["unique_characters", "check"],
    ["lore", "validate"],
    ["realm_power", "check"],
    ["technique_power", "check"],
    ["difficulty", "check"],
    ["cultivation", "validate"],
    ["cultivation", "mutate"],
    ["acquisition", "validate"],
]

OUT = Path("gate_verdict.txt")
lines: list[str] = []

results: dict[str, int] = {}
for stage in STAGES:
    name = " ".join(stage)
    result = subprocess.run(
        [sys.executable, "-m", "tools", *stage],
        capture_output=True,
        text=True,
        check=False,
    )
    results[name] = result.returncode
    lines.append(f"exit={result.returncode}  {name}")
    print(lines[-1], flush=True)

passed = [n for n, c in results.items() if c == 0]
failed = [n for n, c in results.items() if c != 0]

lines.append("")
lines.append(f"PASSING: {len(passed)} of {len(STAGES)}")
lines.append("FAILING: " + (", ".join(failed) if failed else "(none)"))

for name in failed:
    result = subprocess.run(
        [sys.executable, "-m", "tools", *name.split()],
        capture_output=True,
        text=True,
        check=False,
    )
    detail = [
        ln
        for ln in (result.stdout + result.stderr).split("\n")
        if ln.startswith(("fail", "error", "Error")) or "Failure:" in ln or "Error:" in ln
    ]
    lines.append("")
    lines.append(f"=== {name} ({len(detail)} findings) ===")
    for entry in detail[:40]:
        lines.append("  " + entry.strip()[:160])

OUT.write_text("\n".join(lines) + "\n", encoding="utf-8")
print("", flush=True)
print(lines[-len(failed) - 2] if failed else "all green", flush=True)
print(f"wrote {OUT}", flush=True)