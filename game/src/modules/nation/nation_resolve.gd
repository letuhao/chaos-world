class_name NationResolve
extends RefCounted

## The conflict machinery behind `NationApi.resolve_conflict`: the tally, the
## forced close, and the payment of a DECLARED prize.
##
## ## Why this is an internal script and not a `NationApi` method
##
## Extracted from `api.gd` because that file passed the thousand-line ceiling, and
## because these are not verbs — a caller reaches them through the single published
## resolution entry point rather than behind a facade of their own. The only
## arithmetic below is `tally + transfer` (ADR 0085): a withdrawal moves NO
## territory, so the declaration and the counter cannot decide a war between them.
##
## ## No `rng`, no `Time`, no clock
##
## Nothing here invents an outcome. A verdict is counted from one decided
## elsewhere — a `CombatApi.exchange` the caller ran, a tournament result, a
## tribunal's ruling — and this file never calls combat, never reads a combat stat
## and never owns a generator (ADR 0085). Every accrual it settles takes an
## explicit `periods` count from a caller that owns time (DEF-0111).

## How far into a standoff a verdict must be, by mode (ADR 0085). A mode changes
## the quota and the prize shape only, never how a verdict is produced.
const QUOTAS := {NationState.CONTEST: 3, NationState.SIEGE: 5, NationState.TRIBUNAL: 1}


## A standoff that is still being fought, and one that is already closed: the two
## stages that are not the settlement itself. They differ in exactly what a caller
## must ask — has it ended, and if so how — and in nothing else, which is the whole
## reason they share a shape.
##
## `settled` names a standoff whose own facts answer the question rather than the
## ledger: what a caller that resolves a CLOSED war is asking is what the call that
## closed it decided, so that is what it is told. `territory_transferred` is
## therefore the ground the winner holds NOW rather than a fresh claim over it, and
## both standing deltas are zero because a second call must not pay a second time.
static func unpaid_verdict(
	ledger: Dictionary,
	standoff_id: StringName,
	standoff: Dictionary,
	settled: bool,
	detail: Dictionary = {}
) -> Dictionary:
	var winner := String(standoff.get("winner_id", ""))
	var loser := ""
	var stored: Dictionary = standoff.get("sides", {}) as Dictionary
	for side_id in stored.keys():
		if String(side_id) != winner:
			loser = String(side_id)
	var view := {"standoff_id": String(standoff_id), "loser_id": loser}
	if settled:
		view["winner_id"] = winner
		view["outcome"] = String(standoff.get("outcome", NationState.OUTCOME_OPEN))
		# What the war's OWN settlement landed, read back rather than replayed. A
		# second call must not pay a second time, and reporting `0` would make a
		# settled war read as one that paid nobody — so the amounts the closing call
		# recorded are the answer here. A standoff closed before this field existed
		# reports `0`, which is the truth for it.
		view["standing_gained"] = int(standoff.get("standing_gained", 0))
		view["standing_lost"] = int(standoff.get("standing_lost", 0))
		# The ground the winner holds, read from the ledger rather than replayed, so
		# the answer is about who holds it NOW.
		var territory_id := String(standoff.get("territory_id", ""))
		view["territory_transferred"] = (
			territory_id
			if NationState.holder_of(ledger, StringName(territory_id)) == winner
			else ""
		)
	# An open standoff has no winner yet: the verdict counted, and the war is still
	# being fought. `detail` carries the names the CALLER supplied for this verdict.
	view.merge(detail, true)
	return _ok(
		ledger,
		NationState.verdict_view(
			standoff, settled, String(view.get("outcome", NationState.OUTCOME_OPEN)), view
		)
	)


## Close a standoff and pay its DECLARED prize. The only arithmetic here is
## `tally + transfer` (ADR 0085): a withdrawal moves NO territory, so the
## declaration and the counter cannot decide a war between them.
##
## `forced` is what `resolve_conflict` decided ends this war early, or `""` for the
## ordinary case where the declared quota is what decided it. A war that did not
## reach its quota has no winner to pay, so `winner` is `""` on that path and both
## sides pay nothing at all: the declared deltas name the sides, and a side that
## was not in the war cannot be paid out of it.
static func close(
	actor: Actor,
	ledger: Dictionary,
	standoff_id: StringName,
	standoff: Dictionary,
	winner: String,
	loser: String,
	forced: String,
	regard: Callable
) -> Dictionary:
	var tuning := _tuning()
	var deltas: Dictionary = (standoff["prize"] as Dictionary).get("standing", {})
	var won := forced == "" and winner != "" and loser != ""
	var winner_gain := int(deltas.get(winner, int(tuning.standing_on_win))) if won else 0
	var loser_cost := absi(int(deltas.get(loser, -int(tuning.standing_on_loss)))) if won else 0
	var outcome := NationState.OUTCOME_RESOLVED if won else forced
	if forced == NationState.OUTCOME_WITHDRAWAL:
		# A broken side pays the surrender cost and moves nothing. The WINNER is
		# paid nothing either: the war was not won, it was stopped.
		loser_cost = absi(int(deltas.get(loser, int(tuning.standing_on_surrender))))
	var gained := _pay(ledger, winner, winner_gain, String(standoff.get("home_id", "")))
	var lost := _pay(ledger, loser, -loser_cost, String(standoff.get("home_id", "")))
	var transferred := ""
	if (
		outcome == NationState.OUTCOME_RESOLVED
		and (
			String((standoff["prize"] as Dictionary).get("transfer", ""))
			== String(NationState.OWNERSHIP)
		)
	):
		transferred = _transfer(ledger, standoff, winner)
	standoff["winner_id"] = winner
	standoff["outcome"] = outcome
	standoff["closed"] = true
	# What this settlement ACTUALLY landed, kept on the standoff. A verdict that
	# arrives after the war is closed must report the war's own settlement rather
	# than zero — the caller is asking what that war paid, and replaying the tally
	# to answer it is how a second call would look like a second payout. Reading it
	# back is the same discipline `territory_transferred` already uses: the ground
	# the winner holds NOW, not a fresh claim over it.
	standoff["standing_gained"] = gained
	standoff["standing_lost"] = lost
	(ledger["standoffs"] as Dictionary)[String(standoff_id)] = standoff
	_advance(ledger)
	_record(ledger, outcome, StringName(winner), loser)
	# A closed war is the one deed a nation records publicly about its own people, and
	# it is what `fought_for_a_nation` is authored for. **Only the standing side gets
	# it**: a war fought and lost is not a credential, and a cause applied to both
	# sides would make the prize a participation trophy. A withdrawal is excluded too
	# — the polity did not fight, it ran.
	if outcome == NationState.OUTCOME_RESOLVED and winner == String(ledger.get("nation_id", "")):
		regard.call(actor, NationState.nation_id(ledger), NationApi.CAUSE_FOUGHT)
	_persist(actor, ledger)
	NationProjection.events().conflict_resolved.emit(
		String(actor.id), String(standoff_id), winner, outcome
	)
	return _ok(
		ledger,
		(
			NationState
			. verdict_view(
				standoff,
				true,
				outcome,
				{
					"standoff_id": String(standoff_id),
					"winner_id": winner,
					"loser_id": loser,
					"standing_gained": gained,
					"standing_lost": lost,
					"territory_transferred": transferred,
				}
			)
		)
	)


## Move a whole claim to `winner` and return the territory id, or `""` when there
## was nothing to transfer. The claim row MOVES rather than merging: a territory
## has exactly one holder, and two polities' rows for the same ground would be the
## one-sided ownership a single canonical row exists to prevent.
static func _transfer(ledger: Dictionary, standoff: Dictionary, winner: String) -> String:
	var territory_id := String(standoff.get("territory_id", ""))
	var entry = (ledger["claims"] as Dictionary).get(territory_id, null)
	if territory_id == "" or not (entry is Dictionary):
		return ""
	var moved: Dictionary = (entry as Dictionary).duplicate(true)
	moved["holder_id"] = winner
	moved["held_since"] = int(ledger.get("sequence", 0))
	moved["challenger_id"] = ""
	(ledger["claims"] as Dictionary)[territory_id] = moved
	return territory_id


## Move one side's standing and return the amount that actually landed, clamped at
## zero. A defeat lowers a number and never dissolves an institution (ADR 0085), and
## a polity this actor does not speak for pays nothing.
##
## "Speaks for" is two ids, not one. `nation_id` is the POLITY the ledger belongs to,
## and `standoff.home_id` is the side that DECLARED the standoff — the actor's own id,
## which `declare_war` writes into the pair (`api.gd:370`). Those are not always the
## same string, and the declaring side is by construction the side this actor was
## speaking for, so refusing its payout would silently drop the declared prize
## whenever a caller founded a nation under a different name than the actor carrying
## it. The guard exists to stop a RIVAL's standing moving this ledger, and a rival
## is neither of these two.
static func _pay(ledger: Dictionary, nation_id: String, delta: int, home_id: String = "") -> int:
	if nation_id == "":
		return 0
	var mine := String(ledger.get("nation_id", ""))
	if nation_id != mine and (home_id == "" or nation_id != home_id):
		return 0
	var before := int(ledger["standing"])
	ledger["standing"] = clampi(before + delta, 0, int(ledger["standing_cap"]))
	return int(ledger["standing"]) - before


static func _advance(ledger: Dictionary) -> void:
	ledger["sequence"] = NationState.next_sequence(ledger)


static func _record(ledger: Dictionary, kind: String, id: StringName, detail: String) -> void:
	var history: Array = ledger["history"]
	if history.size() >= NationState.HISTORY_LIMIT:
		return
	history.append(
		{"kind": kind, "id": String(id), "detail": detail, "sequence": int(ledger["sequence"])}
	)


## Persist, rebuild the bounded PERCENT recognition, and keep the component in
## step. The three effects are one operation because a ledger without a projection
## is the one state a player cannot recover from.
static func _persist(actor: Actor, ledger: Dictionary) -> void:
	actor.set_module_data(NationState.MODULE_KEY, ledger)
	_mirror(actor, ledger)
	_project(actor, ledger)


## Keep the `actor.components` mirror in step with the persisted payload.
##
## The mirror is a `RefCounted` holder rather than the dictionary itself because
## `Actor.set_component` takes a `RefCounted` and the ledger is a plain
## `Dictionary`. The ledger in `module_data` stays the single source of truth —
## core persists it verbatim and never names a nation type — so the mirror is
## only what a caller reads without going through the facade.
static func _mirror(actor: Actor, ledger: Dictionary) -> void:
	var mirror := actor.component(NationApi.STATE_COMPONENT) as NationStateComponent
	if mirror == null:
		mirror = NationStateComponent.new()
		actor.set_component(NationApi.STATE_COMPONENT, mirror)
	mirror.write(ledger)


static func _project(actor: Actor, ledger: Dictionary) -> void:
	var catalog := NationCatalog.instance()
	var nation_id := NationState.nation_id(ledger)
	var granted := NationProjection.apply(
		actor, ledger, catalog.office_definitions(nation_id), nation_id
	)
	var next := NationState.normalize(ledger, catalog.known_ids())
	next["applied_percent"] = granted
	actor.set_module_data(NationState.MODULE_KEY, next)
	_mirror(actor, next)


## The shipped tuning, or `null` when the build does not ship one.
##
## `load()` returns `null` for a `.tres` that cannot be read, and every field of
## `NationTuning` defaults to `0`, so a caller that treated that null as a tuning
## would read "a defeat costs nothing, and a side breaks at zero exhaustion". The
## second is not a harmless default: exhaustion is compared with `>=`, so a break of
## zero declares EVERY side exhausted the moment it loses once, and every standoff
## in the build refuses its first verdict. It happened here exactly that way. So the
## absence is resolved where the tuning is resolved — `NationCatalog.tuning()` hands
## back a zeroed struct rather than null, and the break is read through
## `NationCatalog.war_break()`, which keeps a non-positive break as "nobody ever
## breaks" rather than as "everybody is already broken". `shipped()` stays as the
## load it was, for a caller that genuinely wants to know.
static func _tuning() -> NationTuning:
	return NationCatalog.instance().tuning()


static func _ok(ledger: Dictionary, detail: Dictionary = {}) -> Dictionary:
	var out := {"ok": true, "nation_id": String(ledger.get("nation_id", ""))}
	for key in detail.keys():
		out[String(key)] = detail[key]
	return out
