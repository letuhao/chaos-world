"""Print what a player can actually acquire, per trial.

The report is deliberately a chain, not a count: for each trial it names the
consumables, the reagents their recipes need, the boss each reagent names, and
whether that boss is reachable through an authored encounter. A shortfall is
therefore attributable to one hop rather than to "5,191 items".

All three cultivation ladders and every non-ladder world domain are walked, so a
report that says the graph is connected is a statement about the whole corpus and
not about the one ladder that happened to be seeded first.
"""

from __future__ import annotations

from ..common import info
from .chain import Graph


def run(graph: Graph) -> int:
    hosted = graph.hosted_bosses()
    trials = sorted(graph.all_trials, key=lambda entry: (not entry.ladder, entry.path, entry.index))
    enterable = 0
    blocked: list[str] = []
    for trial in trials:
        encounter = graph.encounter_for_domain(trial.domain_id)
        state = "enterable" if encounter is not None else "NO ENCOUNTER"
        if encounter is not None:
            enterable += 1
        else:
            blocked.append(f"{trial.trial_id}: {trial.domain_id} has no authored encounter")
        rung = f"R{trial.index + 1:02d}" if trial.ladder else "--  "
        info(f"{rung} {trial.trial_id:26s} {trial.domain_id:32s} {state}")
        for consumable in trial.consumables:
            info(f"      {consumable.role:20s} {consumable.item_id} <- {consumable.recipe_id}")
            for reagent in consumable.reagents:
                for boss_id in reagent.bosses:
                    reachable = boss_id in hosted
                    if not reachable:
                        blocked.append(f"{trial.trial_id}: {boss_id}")
                    info(
                        f"         reagent {reagent.item_id:38s}"
                        f" boss {boss_id:38s} {'hosted' if reachable else 'UNHOSTED'}"
                    )
                if not reagent.bosses:
                    blocked.append(f"{trial.trial_id}: {reagent.item_id} names no boss")
                    info(f"         reagent {reagent.item_id:38s} names no boss source")
    ladders = len(graph.trials)
    info("")
    info(
        f"{enterable}/{len(trials)} trial(s) resolve to an authored encounter "
        f"({ladders} on a cultivation ladder, {len(trials) - ladders} world domain(s))"
    )
    unspawnable = sorted(
        {
            boss_id
            for trial in trials
            for boss_id in trial.boss_ids
            if boss_id not in hosted
        }
    )
    if unspawnable:
        info(f"{len(unspawnable)} boss(es) a trial names are in no encounter at all:")
        for line in unspawnable[:12]:
            info(f"  - {line}")
        if len(unspawnable) > 12:
            info(f"  ... and {len(unspawnable) - 12} more")
    if blocked:
        info(f"{len(blocked)} unresolved hop(s):")
        for line in blocked[:12]:
            info(f"  - {line}")
        if len(blocked) > 12:
            info(f"  ... and {len(blocked) - 12} more")
    return 0
