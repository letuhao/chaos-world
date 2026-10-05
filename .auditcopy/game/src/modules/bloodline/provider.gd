class_name BloodlineProvider
extends StatProvider

## Contributes the module's own stat vocabulary from the actor's ancestry: how many
## lineages it carries, how many have unlocked, how concentrated the strongest and the
## average of them are, and what the awakened set is currently worth.
##
## **Pure, by construction.** Every value is read from the `bloodline_summary`
## component `BloodlineProjection` attached — never from the catalog and never from the
## module ledger. That matters beyond style: a provider runs on every cache miss, and a
## catalog lookup per stat query would make a stat read depend on mutable module state
## and defeat the caching `ActorStats` already does.
##
## It deliberately does NOT re-derive `percent_modifiers`: the projection already
## applies those to the shared derived-stat pipeline, and contributing them here as well
## would count them twice — which is exactly the bug ADR 0026 exists to prevent.

## Ceiling on `bloodline_power`. An actor can carry several awakened lineages and each
## one authors several percent grants, so the raw sum is whatever the content happens
## to add up to. Clamping it means a broad lineage cannot dominate the shared stat pool,
## and the stat stays a readable aggregate rather than a balance dial. The authored
## content budget is a few tenths; this is the backstop, not the target.
const MAX_BLOODLINE_POWER := 1.0


func contribute(context: StatContext) -> Dictionary:
	var summary := context.component(BloodlineProjection.SUMMARY_COMPONENT) as BloodlineSummary
	if summary == null:
		return {}
	return {
		BloodlineStats.LINEAGE_COUNT: float(summary.lineages.size()),
		BloodlineStats.AWAKENED_COUNT: float(summary.awakened.size()),
		BloodlineStats.PEAK_PURITY: clampf(summary.peak_purity, 0.0, 1.0),
		BloodlineStats.MEAN_PURITY: clampf(summary.mean_purity, 0.0, 1.0),
		BloodlineStats.BLOODLINE_POWER: clampf(summary.bloodline_power, 0.0, MAX_BLOODLINE_POWER),
	}
