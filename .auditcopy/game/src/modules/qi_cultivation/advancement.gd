class_name QiAdvancement
extends RefCounted

## The qi breakthrough, as a thin surface over the one implementation.
##
## `QiBreakthroughTransaction` is the production entry point
## (`QiCultivationApi.attempt_breakthrough`), so it is where the gate is enforced.
## This file used to carry a SECOND, inline copy of that gate plus its own copy of
## the roll, and ADR 0036 recorded the duplication as still open. Two copies of a
## gate is how a preview reports a realm enterable while the transaction refuses
## it, so there is now one of each and this file delegates (ADR 0095).
##
## Kept as a public surface because the module's own tests and any caller holding
## this class name keep working; nothing here decides anything.
##
## There is deliberately NO `cancel_attempt` here, and the module guard
## (`tests/modules/qi_cultivation/test_qi_ruling_q3_no_voluntary_deviation.gd`)
## fails the build if one returns. It used to forward to a `cancel` that called
## `_deviate` — and that was a free-standing damage button wearing a cooperative
## name. This path is SINGLE-PHASE: `QiBreakthroughTransaction.execute` validates,
## consumes the pill, rolls and resolves in one call, so no attempt is ever "in
## flight" and none of the three siblings' precondition (`trial_complete` on a
## stored `BodyAttempt`/`MindAttempt`) exists here to check. Body and mind cancel a
## committed attempt and owe NO deviation; this one inflicted one unconditionally,
## with no roll and no pill spent. A verb named `cancel_attempt` that halves your
## progress, scars your dantian and burns a channel is the one answer a player
## cannot act on correctly, so it is gone rather than published (ADR 0180).

## The fate a qi breakthrough earns (DEF-0106).
##
## `remembered_by_the_mountain`, chosen from the fate's OWN text: "Walked into a
## forbidden ridge and came back with the ridge's name in your mouth. Nobody has
## asked where you learned it. You have not offered." Its `counters =
## [breakthroughs]` names this very path — a breakthrough IS a barrier crossed and
## something brought back that nobody asked for — and it is the only authored fate
## whose declared counter is one this module's own successes are what that count
## WOULD mean. It is also paid by `the_riven_peak_disaster.tres` and by
## `the_returned_instrument.tres`; `earn_fate` is exactly-once, so those pay nothing
## twice (ADR 0065).
const FATE_BARRIER := &"remembered_by_the_mountain"

## The `source` string this path's earn carries, in the shape `QuestGrants
## .FATE_SOURCE_PREFIX + quest_id` and `EventDef.fate_source()` both build: it names
## the SYSTEM that earned the fate and the decision point, never the fate id itself
## (ADR 0065 on id namespaces).
const EARN_SOURCE := "qi_breakthrough"


## Preview the breakthrough: structured unmet conditions, costs and the chance.
## Never consumes items, changes progression, or advances RNG.
static func preview(actor: Actor) -> Dictionary:
	return QiBreakthroughTransaction.preview(actor)


## Execute the breakthrough. Returns true on success. On failure the actor takes
## a qi deviation: lost progress, a scarred dantian, and a damaged channel.
##
## ## DEF-0106: a breakthrough is this path's OATH, and it is earned here
##
## The `true` this verb returns IS the decision that a breakthrough happened: the
## transaction below rolls, advances and pays, and reports a bare `true`/`false`
## with nothing attached to the success. So the earn is wired at BOTH entry points
## rather than at one of them — `QiAdvancement.try_breakthrough` and
## `QiCultivationApi.attempt_breakthrough` are two independent production callers,
## and a gate wired at one of them is a gate the other walks past. That is the same
## shape as `combat`: the owning module decides, `destiny` records, and fate is
## never a listener (ADR 0065). `earn_fate` is exactly-once, so the two sites
## cannot pay the same fate twice even if both run for one breakthrough.
##
## `remembered_by_the_mountain` is the authored fate a breakthrough earns, from its
## own text: "Walked into a forbidden ridge and came back with the ridge's name in
## your mouth." Its `counters = [breakthroughs]` is the very counter this module's
## successes are what a `breakthroughs` count WOULD mean; the `counter` verb is not
## yet driven by this path, so the fate is the honest earn where the counter was
## the aspirational one. It is also paid by `the_riven_peak_disaster.tres` and by
## `the_returned_instrument.tres`, and `earn_fate` is exactly-once, so those pay
## nothing twice.
##
## The two bodies are the same three lines on purpose and are NOT deduplicated into
## one shared call the transaction could own: `QiBreakthroughTransaction.execute` is
## itself a public entry point (ADR 0095 records that the module's own suites and
## `tools` call it directly), and a gate placed inside it would be the module
## reaching into a class that documents itself as a pure transaction. So each entry
## point calls [method earn_breakthrough_oath] itself, and
## `test_destiny_earn_sources_cultivation.gd` drives both to hold that pair shut.
static func try_breakthrough(actor: Actor, rng: RandomNumberGenerator = null) -> bool:
	if not QiBreakthroughTransaction.execute(actor, rng):
		return false
	earn_breakthrough_oath(actor)
	return true


## Earn this path's breakthrough fate for `actor`, and VERIFY it. The one place the
## id, the source string and the verification live, so both entry points pay
## identically — `QiAdvancement.try_breakthrough` above and
## `QiCultivationApi.attempt_breakthrough`, which the qi screen presses.
##
## ## Why the verification IS the body
##
## `DestinyApi.earn_fate` returns the LEDGER, never a verdict, and every refusal
## path is byte-identical in shape — an unknown id, an already-held entry, a null
## actor all hand back the same unchanged ledger. Nothing is queued and nothing
## retries (ADR 0134), so a call trusted as "already offered" silently never fires.
## `has_fate` afterwards is the only honest answer: the idiom
## `character_creation_flow.gd:280-284` takes and `event_prize.gd:95-96` does not.
##
## The returned boolean says which happened. Nothing above branches on it — a
## breakthrough is not rolled back because its narrative receipt failed, and the
## refusal is an authoring bug rather than a player-facing outcome — but it makes the
## seam assertable without reaching into the ledger from a test.
static func earn_breakthrough_oath(actor: Actor) -> bool:
	if actor == null:
		return false
	DestinyApi.earn_fate(actor, FATE_BARRIER, EARN_SOURCE)
	if DestinyApi.has_fate(actor, FATE_BARRIER):
		return true
	# A miss means the id is not in the catalog, so this is a developer's warning and
	# never a player-facing notice.
	push_warning(
		(
			(
				"qi_cultivation: a breakthrough was granted but %s was not earned (id unknown "
				+ "to the fate catalog?). Nothing records the debt and nothing retries it."
			)
			% String(FATE_BARRIER)
		)
	)
	return false


## The chance this attempt would roll. Reads the dantian and nothing else, because
## comprehension is this path's own entry gate and a gate input is a precondition
## rather than a difficulty dial (ADR 0051).
static func chance(actor: Actor) -> float:
	return QiChance.of(QiAccess.dantian(actor))
