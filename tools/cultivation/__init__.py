"""Seed, audit, and prepare the Body Cultivation generation prompt."""

from __future__ import annotations

from ..common import REPO_ROOT, fail, ok


def register(subparsers) -> None:
    parser = subparsers.add_parser("cultivation", help="cultivation content workflow")
    parser.add_argument(
        "action",
        choices=[
            "seed",
            "seed-systems",
            "retune",
            "validate",
            "report",
            "prompt",
            "mutate",
            "loot-magnitude",
        ],
    )
    parser.add_argument(
        "loot_magnitude_action",
        nargs="?",
        default="check",
        choices=["report", "check", "fix", "repair"],
        help="loot-magnitude: print the rung each drop pays, guard it, or fix it",
    )
    parser.add_argument(
        "--scope",
        default="gate",
        choices=["gate", "all"],
        help="loot-magnitude only: which entries gate. 'gate' is the guaranteed "
        "reagents (BL-0645's class); 'all' is every direct entry",
    )


def run(args) -> int:
    from . import seed, seed_systems

    if args.action == "seed":
        return seed.run()
    if args.action == "retune":
        from . import retune

        return retune.run()
    if args.action == "mutate":
        from . import mutate

        return mutate.run()
    if args.action == "seed-systems":
        return seed_systems.run()
    if args.action == "loot-magnitude":
        from . import loot_magnitude

        return loot_magnitude.run(args.loot_magnitude_action, scope=args.scope)
    if args.action == "report":
        from . import report

        return report.run()
    from . import audit

    findings = audit.validate()
    if findings:
        for finding in findings:
            fail(finding)
        return 1
    if args.action == "prompt":
        output = REPO_ROOT / "build" / "prompts" / "body_cultivation.txt"
        output.parent.mkdir(parents=True, exist_ok=True)
        template = (REPO_ROOT / "tools" / "cultivation" / "master_prompt.txt").read_text(
            encoding="utf-8"
        )
        output.write_text(template + "\n" + audit.context(), encoding="utf-8")
        ok(f"generated {output.relative_to(REPO_ROOT).as_posix()}")
    else:
        ok("cultivation seed audit clean (30 realms, 60 acupoints, 20 meridians)")
    return 0
