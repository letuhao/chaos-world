"""Prove tools/cultivation reproduces the authored body seeds byte-for-byte."""

import difflib
import subprocess
import sys

sys.path.insert(0, r"D:\Works\source\chaos-world")

from tools.cultivation import ladder as L
from tools.cultivation import retune as R
from tools.cultivation.report import chance_range
from tools.cultivation.seed import BODY_WORK_REQUIRED as B
from tools.cultivation.seed import realms as ladder_realms

lines: list[str] = []
say = lines.append

ratio = L.milestone_physique_ratio()
say("MILESTONE_PHYSIQUE_RATIO = %s" % ratio)
say("fresh acupoint quality  = %s" % L.fresh_acupoint_quality())
say("")
bad = 0
for index, (realm_id, _n, _t) in enumerate(ladder_realms()):
    path = R.REALM_DIR / ("%s.tres" % realm_id)
    before = path.read_text(encoding="utf-8")
    after, _changes = R.rewrite(realm_id, index, ratio)
    if after != before:
        bad += 1
        say("R%02d %s: MISMATCH" % (index + 1, realm_id))
        for line in difflib.unified_diff(
            before.splitlines(), after.splitlines(), lineterm="", n=0
        ):
            if line.startswith(("+", "-")) and not line.startswith(("+++", "---")):
                say("    " + line)
say("%d of 30 seeds would be rewritten by `cultivation retune`" % bad)

say("")
say("--- cross-path identities on shipped data ---")
say("body R1->R2 progress step: %s" % (B[1] - B[0]))
say("qi   R29->R30 step: %.6f" % (2900.0 / 2800.0))
worst_body = min(((i + 1, B[i] / B[i - 1]) for i in range(2, 30)), key=lambda p: p[1])
say(
    "tightest body step above R2: R%d->R%d = %.6f"
    % (worst_body[0], worst_body[0] + 1, worst_body[1])
)
mind = [round(100.0 * max(1, i) ** 1.45) for i in range(30)]
worst_mind = min(((i + 1, mind[i] / mind[i - 1]) for i in range(2, 30)), key=lambda p: p[1])
say(
    "tightest mind step above R2: R%d->R%d = %.6f"
    % (worst_mind[0], worst_mind[0] + 1, worst_mind[1])
)

granted = 0.0
dead = []
for realm_id, _n, _t in ladder_realms():
    seed = R.load(realm_id)
    required = float(seed["scalars"].get("physique_required", 0.0))
    if required <= granted + 1e-6:
        dead.append(realm_id)
    granted += float(seed["dicts"].get("rewards", {}).get("physique", 0.0))
    granted += float(seed["scalars"].get("integrity_maximum", 0.0)) * ratio
say("physique-gate-dead realms (DEF-0104): %d %s" % (len(dead), dead))

seeds = [R.load(r) for r, _n, _t in ladder_realms()]
degen = []
for index, (realm_id, _n, _t) in enumerate(ladder_realms()):
    ceiling = float(seeds[index - 1]["scalars"]["quality_target"]) if index else None
    worst, best = chance_range(seeds[index], ceiling)
    if best - worst <= 1e-9:
        degen.append(realm_id)
say("degenerate chance bands (DEF-0079): %d %s" % (len(degen), degen))

head = subprocess.run(
    ["git", "show", "HEAD:game/data/body_cultivation/realms/qi_refining.tres"],
    capture_output=True,
    text=True,
    encoding="utf-8",
).stdout
say("")
say("--- HEAD qi_refining balance block ---")
for line in head.splitlines():
    if "=" in line and not line.startswith("["):
        say("  " + line)

say("")
say("body physique_required ladder (new): %r" % [float(R.load(r)["scalars"]["physique_required"]) for r, _n, _t in ladder_realms()])
say("qi comprehension_required ladder (unchanged): %r" % [10.0 + 2.0 * max(0, i - 1) for i in range(30)])
say("qi_dantian_quality ladder (unchanged): %r" % [0.50 + 0.01 * max(0, i - 1) for i in range(30)])

with open(sys.argv[1], "w", encoding="utf-8") as handle:
    handle.write("\n".join(lines) + "\n")
