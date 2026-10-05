"""Make the authored acquisition graph reachable, and prove it.

`ItemDef.sources` is read by no shipping code, so a `boss:` source is only
delivered once `LootApi.enter_domain` can spawn the boss it names, and that needs
an authored `LootEncounterDef` plus a loot table bound to the boss. This tool
seeds that content from the authored realm seeds and boss records, then audits
whether every trial's three consumables resolve to a fightable terminal.

All three cultivation ladders and every non-ladder world domain are walked. The
body ladder was seeded first and in isolation, which is why 265 boss records on
the qi/mind ladders and in the world domains carried drops no encounter could
deliver; a walk that only covered the seeded ladder reported the corpus as
connected while 1187 drops sat behind nothing.

    seed      write the missing encounters and tables, retire legacy boss loot
    validate  assert the shape; non-zero on any problem
    report    print the chain per trial and name every unreachable hop
"""

from __future__ import annotations

from ..common import fail, ok


def register(subparsers) -> None:
    parser = subparsers.add_parser(
        "acquisition", help="make authored item sources reachable and audit them"
    )
    actions = parser.add_subparsers(dest="acquisition_action", required=True)
    seed = actions.add_parser("seed", help="write the loot content every trial needs")
    seed.add_argument(
        "--force",
        action="store_true",
        help="rewrite a generated file whose declared id matches, so a generator "
        "change can be re-applied; a hand-written file is still never touched",
    )
    actions.add_parser("validate", help="assert every catalyst resolves to a fight")
    actions.add_parser("report", help="print the acquisition chain per trial")


def run(args) -> int:
    from .chain import Graph

    action = args.acquisition_action
    if action == "seed":
        from . import seed as seeding

        seeding.seed(Graph().require(), force=getattr(args, "force", False))
        return 0
    if action == "report":
        from . import report

        return report.run(Graph().require())

    from .validate import validate

    problems = validate(Graph().require())
    if problems:
        for problem in problems[:20]:
            fail(problem)
        if len(problems) > 20:
            fail(f"... and {len(problems) - 20} more")
        fail(f"acquisition validate: {len(problems)} problem(s)")
        return 1
    ok("acquisition shape clean: every catalyst resolves to a fightable terminal")
    return 0
