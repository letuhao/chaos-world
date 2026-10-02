"""Seed, audit, and prepare the Body Cultivation generation prompt."""

from __future__ import annotations

from ..common import REPO_ROOT, fail, ok


def register(subparsers) -> None:
    parser = subparsers.add_parser("cultivation", help="cultivation content workflow")
    parser.add_argument("action", choices=["seed", "seed-systems", "validate", "report", "prompt"])


def run(args) -> int:
    from . import seed, seed_systems

    if args.action == "seed":
        return seed.run()
    if args.action == "seed-systems":
        return seed_systems.run()
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
