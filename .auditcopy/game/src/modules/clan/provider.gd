class_name ClanProvider
extends StatProvider

## Contributes the module's own stat vocabulary from the actor's standing: how much they
## have earned, how far they are into the clan's ladder, how much is on the table in
## each direction, and how many rival houses their clan names.
##
## ## Every id here is a bounded, non-combat SUMMARY. Read this before adding one.
##
## ADR 0064: a clan grants **recognition, never power**. So this provider contributes
## four numbers that describe a social position and not one number that a fight can
## read. `standing` is a recognition currency for a reputation system to compose
## against; `patronage_tier` is a count of published obligations; the rest are
## ordinals.
##
## **Never add `attack_*`, `defense_*`, `max_health`, `max_qi`, any base attribute, or
## any other id the shared derived pipeline treats as combat value.** A clan that
## granted one would hand a player power for being recognised, and the recognition a
## clan actually confers — who will vouch for you — is worth more in a reputation
## system than in a modifier stack. `test_clan_grants_no_power.gd` holds the line.
##
## **Pure, by construction.** Every value is read from the `clan_summary` component
## `ClanProjection` attached — never from the catalog and never from the module
## ledger. That matters beyond style: a provider runs on every cache miss, and a
## catalog lookup per stat query would make a stat read depend on mutable module state
## and defeat the caching `ActorStats` already does.


func contribute(context: StatContext) -> Dictionary:
	var summary := context.component(ClanProjection.SUMMARY_COMPONENT) as ClanSummary
	if summary == null or summary.clan_id == &"":
		return {}
	return {
		ClanStats.STANDING: maxf(0.0, float(summary.standing)),
		ClanStats.RANK_INDEX: maxf(0.0, float(summary.rank_index)),
		ClanStats.BAND_INDEX: float(summary.band_index + 1),
		ClanStats.PATRONAGE_TIER:
		clampf(summary.patronage_tier, 0.0, ClanSummary.MAX_PATRONAGE_TIER),
		ClanStats.RIVAL_COUNT: float(summary.rivals),
	}
