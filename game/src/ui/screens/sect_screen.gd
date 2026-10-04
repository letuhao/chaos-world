class_name SectScreen
extends UiScreen

## The sect a hero is sworn to: the member's own claim, its office and its authored
## duties, the offices of the sworn sect and their live seat state, and every
## authored sect for comparison. A pure consumer of the `sect` facade — it renders
## the facade's `summary(actor)` read model and names NOTHING else in the module
## (ADR 0083/0084).
##
## ## Position and standing are TWO lines, never one rank
##
## The member's own claim is a `SectClaimRow`, and that row prints the office and the
## standing separately. This screen never divides one by the other to make a single
## number: ADR 0064's split (a high position on thin standing is possible, and thick
## standing in no position is also possible) IS the politics layer, so collapsing it
## into a rank would throw the design away at the last step.
##
## ## A refusal is a rendered state, not a blank page
##
## The member row publishes either the claim or the facade's named refusal reason.
## An unaffiliated hero gets an explicit `not_a_member` row rather than an empty
## screen, because "the three tiers are peers" (ADR 0083) means "no institution" is
## the ordinary starting state and deserves a sentence, not a void.
##
## ## This screen ACTS, and the audit that found it read-only was right to
##
## It rendered thirteen mutating verbs' worth of state and could fire none of them, so
## a player could LOOK at a sect and never join, leave or take a seat. It now calls
## five of them by name — `SectApi.join`, `SectApi.leave`, `SectApi.promote`,
## `SectApi.found` and `SectApi.teach` — through the facade, and nothing else out of the
## module.
##
## ## Why `found` and `teach` are HERE and the three council acts are not
##
## The three it called first are the three a member's own hand is responsible for.
## `found` and `teach` are the two remaining verbs that are acts about the PLAYER'S OWN
## claim and nothing else: founding is one hero making a house, and a lesson is one
## member teaching another in a school they are both sworn to. Neither touches a third
## party's standing, a seat anybody else holds, or a split — so neither is "an
## inquisition a two-click accident", which is the reason the council and world acts
## (`move_standing`, `advance_succession`, `declare_schism`) still have no button here.
##
## ## The two BEATS a player reaches, and the order they must happen in
##
## Founding is priced against `sect_founding_funds`, a pool nothing in the game fills
## (`ActorFactory.fund_sect_from_purse` had zero callers), so founding is TWO actions
## and the order is the mechanic: **fund** the price out of the purse, then **found**.
## Both are one button each rather than one button that quietly converts first, because
## a silent conversion spends the player's own money and BL-0174 makes the price a real
## one — the player must press the thing that spends it.
##
## Teaching is the third beat: the school's own founder holds the first rung of the
## ladder (the founding grant in `sect_founding.gd`), so `act_teach` is live for a
## founder and refused by name for anybody else. The cost is the teacher's `stamina`,
## so it is a real cost and not a menu click that makes disciples a faucet (BL-0188).
##
## ## What is NOT refused here, and why
##
## `leave` refuses on nothing but `not_a_member` (ADR 0084), so its button stays live
## for every sworn member and the refusal is RENDERED rather than the control being
## greyed out: a player who is told nothing may still be told why nothing happened. The
## same is true of a promotion below its standing floor — the floor is a ROUTE, not a
## wall, and `act_promote(office, force)` is that route. `act_promote` with `force`
## overrules the floor AND the occupied seat, because `SectApi.promote` reads those
## two refusals as one decision, and a screen that overruled only one of them would
## publish a verb that cannot do what its name says.
##
## ## The refusal is `reason` VERBATIM, never prose this screen composed
##
## Every verb answers `{ok, reason}` with an authored constant
## (`already_sworn`, `not_a_member`, `standing_below_floor`, `seat_occupied`,
## `capacity_full`, `unknown_sect`). A refused action is handed to
## `SectClaimRow.show_refusal` untouched, which is the third of ADR 0083's three states
## and renders in its own card tone. An unaffiliated hero keeps `show_claim({})`,
## which is the FIRST state, so `{}` and a refusal never read alike.
##
## Contract: `summary()` is the testable surface, primitives only, `{}` with no
## actor, and each child's own summary nested under that child's key.

## Rows the scene mounts and this screen tops up to. The claim pool is exactly one
## row — a member holds one claim, and a spare claim row would be a second thing to
## hide — while the office pool grows, because a sect may author more offices than a
## scene can enumerate and a pool that dropped one would read as dead content.
const CLAIM_SPARE_ROWS := 0
const OFFICE_ROWS := 8
const CLAIM_SCENE := "res://src/ui/panels/sect_claim_row.tscn"
const OFFICE_SCENE := "res://src/ui/panels/nation_office_row.tscn"
const ACTIONS_SCENE := "res://src/ui/panels/action_set.tscn"
const HEADER_TEXT := "The institution you are sworn to, and what the office obliges."
const NO_ACTOR_TEXT := "No hero bound."
const FOOTER_TEXT := (
	"Up / Down picks an entry, Accept joins or is seated. Cancel returns."
	+ " An institution grants recognition and access, and never power."
)
## The footer while nothing is bound, and while there is nothing to act on. A read-only
## sentence was published here for a screen that could do nothing; a screen that can
## now act says what its controls are instead.
const NO_ACTOR_FOOTER := ""
## What the action bar offers a hero sworn to nothing: the catalog, one entry at a time.
const OFFERED_TEXT := "Offered"
## The refusals this screen itself raises, before a verb is called. Authored constants
## rather than prose, for the same reason the module's are: a panel renders a reason it
## did not have to invent.
const NO_ACTOR := "no_actor"
## The row names a sect the catalog does not ship, so nothing was called.
const UNKNOWN_SECT := "unknown_sect"
## The row names an office the sworn sect does not author.
const UNKNOWN_POSITION := "unknown_position"
## A `join` was asked for with no sect picked. A refusal of the SCREEN's own seam,
## authored here for the same reason the module authors its own: a panel renders a
## reason it did not have to invent, and a silent no-op is not a refusal.
const NO_SECT_PICKED := "no_sect_picked"
## The same for a promotion with no office picked.
const NO_OFFICE_PICKED := "no_office_picked"
## `fund` was asked for with no amount, and `teach` with no pupil: the screen's own
## seam, refused rather than a silent no-op, for the same reason as the two above.
const NO_AMOUNT := "no_amount"
const NO_PUPIL := "no_pupil"
## The funding bridge is not bound, so the conversion the player pressed cannot run.
## Distinct from `no_amount`: the amount was named and there is nowhere to send it.
const NO_FUNDING_SEAM := "no_funding_seam"
## The action ids this screen publishes, in the order the bar shows them. Declared as
## constants rather than built per call so the order a test reads is the order the
## player sees — seven verbs, never a growing set.
const ACTION_JOIN := &"join"
const ACTION_LEAVE := &"leave"
const ACTION_PROMOTE := &"promote"
const ACTION_PROMOTE_FORCED := &"promote_forced"
## Funding is its own press rather than a side effect of founding: BL-0174 makes the
## price real, so the act that spends the player's money is a control the player sees.
const ACTION_FUND := &"fund"
const ACTION_FOUND := &"found"
const ACTION_TEACH := &"teach"

var _codex: Dictionary = {}
var _header: Label = null
var _footer: Label = null
var _claim_box: VBoxContainer = null
var _office_box: VBoxContainer = null
var _actions: ActionSet = null
var _bound: bool = false
var _claim_rows: Array = []
var _office_rows: Array = []
## The catalog row `act_join` would swear the hero to. `""` means nothing is picked, and
## a `join` with nothing picked is refused by `NO_SECT_PICKED` rather than silently
## swearing them to the first house in the list.
var _selected_sect: String = ""
## The office row `act_promote` would seat the hero in. Same rule: `""` picks nothing.
var _selected_office: String = ""
## The conversion the player's coins take into the sect founding fund, injected by the
## composition root as a `Callable(actor, coins) -> Dictionary`.
##
## ## Why it is a Callable and not a facade call
##
## The fund is `sect`'s own pool (`sect_founding.gd`) and the coins are the economy's
## numéraire, which is an INVENTORY ITEM. `sect` declares no `items` or `economy`
## dependency on purpose — `sect_founding.gd` says it "never charges an inventory and
## never settles a debt" — so the conversion has to live in the one layer allowed to
## know both vocabularies (`ActorFactory.fund_sect_from_purse`, `actor_factory.gd`), and
## `ui/` may not name `app/` at all (`rules.PRIVATE_UNITS`). This is ADR 0143's seam and
## the same one the quest accept and the soul reads use.
##
## Empty by default, and `act_fund` refuses `no_funding_seam` rather than pretending
## to have converted: a screen bound without its bridge says so in the module's own
## vocabulary instead of reporting a price nobody paid.
var _fund_from_purse: Callable = Callable()
## The pupil resolver: `Callable(actor_id: String) -> Actor`, injected by the
## composition root. `ui/` may not mint an `Actor` nor look one up by id, so the
## "who can I teach" question has to be answered outside — and it is answered through a
## bridge rather than a second roster, because the roster is `sect`'s to own, and a
## screen keeping its own list of members is that list drifting away from the ledger a
## player is actually playing.
##
## Empty by default and `act_teach` refuses `no_pupil` rather than teaching nobody
## and reporting a lesson.
var _pupil_resolver: Callable = Callable()
## The last verb's verdict, carried through verbatim. `{}` before any action, so a test
## reads "no action yet" rather than a refusal that never happened.
var _last_result: Dictionary = {}
## The refusal currently painted on the claim row, or `{}`. Kept so a repaint from the
## facade cannot silently erase a refusal the player has not read yet — the row shows
## the CLAIM after every successful verb, and only a refusal survives a refresh.
var _refusal: Dictionary = {}
## Every read model this screen PUBLISHES that is computed from the facade's snapshot
## rather than from the widget tree — the claim, the promotion routes, the catalog for
## comparison, the board's office ids, the authored founding price and the string lists.
## Built in `_bind_nodes` beside the node binding for the same reason the nodes are:
## a headless test drives this screen with no scene tree at all, so nothing may be built
## in `_ready()` and nothing may be assumed to exist because a scene mounted it.
##
## Reading the facade and painting it are two reasons to change: a new field the sect
## facade publishes or a retuned `.tres` touches that file and not this one. Same split
## `domain_explore_model.gd` makes beside the world map, and for the same reason.
var _report: SectReportModel = null


## Adopt a facade snapshot for the bound actor (the `summary(actor)` shape).
## `setup(actor)` takes the facade path inside `_refresh_view`; this exists so a
## headless test or a driver can render from a snapshot with no actor at all, and —
## importantly — so adopting a snapshot does NOT re-enter the facade. An empty
## snapshot clears it.
func apply_snapshot(snapshot: Dictionary) -> void:
	_bind_nodes()
	_codex = snapshot.duplicate(true)
	_fill_from_codex()
	_render()


## ## Take the two seams `ui/` is not allowed to build for itself
##
## `fund_sect_from_purse` lives in `app/actor_factory.gd` and the pupil resolver needs
## an `Actor`; `ui/` may name neither (`rules.PRIVATE_UNITS` makes `app/` reachable only
## from `app/`), so both arrive as Callables from the composition root — ADR 0143's
## bridge, the same one `bind_quests` and `bind_soul` use. **Both are optional**: an
## unbound screen still renders, still joins, leaves and promotes, and refuses the two
## beats BY NAME rather than pretending to have run them.
##
## Assigned exactly as given (not merged into a default), so binding a deliberate
## null clears a previously bound bridge — the same rule `item_workbench.setup`'s save
## and load callables follow, for the same reason.
func bind_sect_funding(fund_from_purse: Callable, pupil_resolver: Callable = Callable()) -> void:
	_bind_nodes()
	_fund_from_purse = fund_from_purse
	_pupil_resolver = pupil_resolver
	_refresh_view()
	_render()


## Whether the two seams are bound. Published so a driver or a test can tell "this
## screen cannot fund" from "this screen has nothing to fund", which are different
## sentences and both reachable.
func _funding_seam_bound() -> bool:
	return _fund_from_purse.is_valid()


func _summary() -> Dictionary:
	_bind_nodes()
	if _actor == null:
		return {}
	var promotions := _report.promotion_summaries(_codex)
	var sects := _report.sect_summaries(_codex)
	return {
		"actor": String(_actor.id),
		# `read_only` is now FALSE, and it is reported rather than deleted: a caller
		# reading `true` is reading a claim this screen no longer makes. The key stays
		# so the vocabulary does not drift under a test that already asks for it.
		"read_only": false,
		"is_member": bool(_codex.get("is_member", false)),
		"sect_id": String(_codex.get("sect_id", "")),
		"sect_name": String(_codex.get("sect_name", "")),
		"doctrine_id": String(_codex.get("doctrine_id", "")),
		"position_id": String(_codex.get("position_id", "")),
		"position_name": String(_codex.get("position_name", "")),
		"standing": int(_codex.get("standing", 0)),
		"standing_cap": int(_codex.get("standing_cap", 0)),
		"standing_ratio": float(_codex.get("standing_ratio", 0.0)),
		"standing_percent": float(_codex.get("standing_percent", 0.0)),
		"teaches": bool(_codex.get("teaches", false)),
		"duties": _report.string_list(_codex.get("duties", [])),
		"authorities": _report.string_list(_codex.get("authorities", [])),
		"claim": _report.claim_summary(_claim_rows),
		# ADR 0083's three states, reported as three DISTINCT facts rather than
		# collapsed: the claim, the refusal the last verb returned, and the offered
		# catalog. A screen that renders all three cannot make them read alike.
		"refused": bool(_last_result.get("ok", true) == false),
		"refusal_reason": String(_last_result.get("reason", "")),
		"last_reason": String(_last_result.get("reason", "")),
		"last_ok": bool(_last_result.get("ok", false)),
		"can_join": can_join(),
		"can_leave": can_leave(),
		"can_promote": promotions,
		"can_promote_count": promotions.size(),
		# Founding and teaching are player-reachable beats, so the screen publishes
		# what they would cost and what they need — read off the facade's OWN read model
		# (`sect_view` carries `founding_cost`; `can_promote` carries `teach_tax`), never
		# re-derived here. A screen that re-derived a price could disagree with what the
		# module charges, which is the one thing a priced act must never do.
		"can_found": can_found(),
		"can_fund": can_fund(),
		"can_teach": can_teach(),
		"founding_cost": _report.founding_cost_view(_codex, _selected_sect),
		"funds": _funding_seam_bound(),
		"selected_sect": _selected_sect,
		"selected_office": _selected_office,
		"actions": _action_ids(),
		"enabled": _enabled_actions(),
		"sects": sects,
		"sect_count": sects.size(),
		"offered_ids": offered_ids(),
		"office_ids": _report.office_ids(_office_rows),
	}


# --- Actions. Each returns the facade's own verdict, verbatim ----------------


## Whether a hero may be sworn to a sect from here right now. Only the seam being
## wired and a sect actually being picked gate the control; whether the CATALOG has
## this house is the facade's refusal to name, not a reason to grey out a button.
func can_join() -> bool:
	return _actor != null and _selected_sect != ""


## Whether a hero may leave from here. True for every sworn member, always: leaving is
## always permitted and always costs (ADR 0084), and `not_a_member` is the ONLY thing
## `leave` refuses on — which is a refusal a panel RENDERS, not a reason to hide the
## control.
func can_leave() -> bool:
	return _actor != null and bool(_codex.get("is_member", false))


## Whether a hero may found a sect from here. **Gating the control on only the seam
## being wired and a sect actually picked**, never on whether the price is already met:
## the pool is `sect`'s own and the screen cannot read it through the facade, so a
## screen that greyed the button on affordability would be pre-judging a rule the module
## owns — and a hero who cannot afford it is told WHY by pressing, which is the
## `already_sworn` argument `join` already makes.
func can_found() -> bool:
	return _actor != null and _selected_sect != ""


## Whether the fund button can run. A seam AND an amount: the amount is the whole
## decision, because converting everything a player presses would be a real loss with
## no confirmation, and converting nothing is a no-op a player reads as a bug.
func can_fund() -> bool:
	return _actor != null and _funding_seam_bound()


## Whether this member may run a lesson from here. The FIT gate is deliberately NOT
## pre-judged: `SectApi.teach` owns `teacher_unfit`, and a screen that hid the button
## from an unfit teacher would make the one rule the audit found vacuous invisible
## rather than named. Live for every sworn member; the verdict is what teaches them.
func can_teach() -> bool:
	return _actor != null and bool(_codex.get("is_member", false))


## The doctrine id the picked sect teaches, or `""`. Read from the facade's own
## `sect_view`, so `act_found` names the school the CONTENT authored rather than a
## doctrine the screen chose — two houses may share a doctrine, and picking the wrong
## one would found a school that does not exist.
func _doctrine_of(sect_id: String) -> String:
	var catalog: Dictionary = _codex.get("sects", {}) as Dictionary
	return String((catalog.get(sect_id, {}) as Dictionary).get("doctrine_id", ""))


## The actor `id` names, or null. **Always through the injected resolver**, never a
## lookup of this screen's own: `ui/` may not mint an `Actor`, and a screen that kept
## a member list would be a second roster beside the module's own.
func _pupil(id: String) -> Actor:
	if id == "" or not _pupil_resolver.is_valid():
		return null
	return _pupil_resolver.call(id) as Actor


## Swear the bound actor to the picked sect. Returns `SectApi.join`'s verdict
## unchanged, so a caller never has to read the message line to learn what happened.
##
## `SectApi.join` is called for its rule, not for its opinion: the three tiers are
## peers (ADR 0083), so a hero already sworn is refused `already_sworn` and must leave
## first. That refusal is RENDERED through `show_refusal` and is a distinct visual
## state from "sworn to nothing", which is `show_claim({})`.
func act_join(sect_id: String = "") -> Dictionary:
	_bind_nodes()
	var wanted := sect_id if sect_id != "" else _selected_sect
	if _actor == null:
		return _verdict({NO_ACTOR: true})
	if wanted == "":
		return _verdict({NO_SECT_PICKED: true})
	var result := SectApi.join(_actor, StringName(wanted))
	return _settle(result)


## Walk out of the sect the bound actor is sworn to. Returns `SectApi.leave`'s
## verdict. The standing the sect gave is settled against it rather than refunded,
## which is what makes a demotion a real cost.
func act_leave() -> Dictionary:
	_bind_nodes()
	if _actor == null:
		return _verdict({NO_ACTOR: true})
	var result := SectApi.leave(_actor)
	return _settle(result)


## Take `office_id` in the sect the bound actor is sworn to. `force` is ADR 0064's
## route: the floor is a route, not a wall, and the trail records a forced promotion
## as `promote_forced` so a later reader can tell an earned seat from a political one.
##
## `held` is NOT passed. The module counts the room from the ledger's OWN roster and
## reads the office's cap from its authored def, so a screen that passed a number would
## be passing a claim the module then treats as a question.
func act_promote(office_id: String = "", force: bool = false) -> Dictionary:
	_bind_nodes()
	var wanted := office_id if office_id != "" else _selected_office
	if _actor == null:
		return _verdict({NO_ACTOR: true})
	if wanted == "":
		return _verdict({NO_OFFICE_PICKED: true})
	var result := SectApi.promote(_actor, StringName(wanted), force)
	return _settle(result)


## ## Move `coins` of the player's own purse into the sect founding fund
##
## ## This is the beat that made founding REACHABLE, and it exists because the price
## ## was unpayable. `SectApi.found` compares `SectFounding.funds(actor)` against the
## authored `founding_cost.outstanding`, and the pool was mounted EMPTY on purpose (a
## non-zero mount would GRANT the authored price to every hero). With no verb to fill
## it, founding was refused `founding_cost_unmet` for every actor in the game at every
## price — so the verb that spends the money had to exist somewhere a player presses.
##
## ## It is NOT a facade call and the screen cannot make it one
##
## The coins are the economy's numéraire and the fund is `sect`'s own pool; `sect`
## declares no `economy` dependency on purpose and `ui/` may not name `app/`. So the
## conversion is injected as a `Callable` by the composition root — ADR 0143's seam, the
## same one the quest accept uses. An unbound screen refuses `no_funding_seam` BY NAME
## rather than reporting a success nobody can audit.
##
## Returns the bridge's own verdict verbatim, so a caller reads what actually landed
## (`moved`, `purse`, `funds`) rather than a screen-composed summary of it.
func act_fund(coins: int) -> Dictionary:
	_bind_nodes()
	if _actor == null:
		return _verdict({NO_ACTOR: true})
	if coins <= 0:
		return _verdict({NO_AMOUNT: true})
	if not _fund_from_purse.is_valid():
		return _verdict({NO_FUNDING_SEAM: true})
	return _settle(_fund_from_purse.call(_actor, coins) as Dictionary)


## Bring the picked sect into being, seating the bound actor in its top office.
##
## ## The price is the CALLER's, never overridden
##
## There is deliberately no `force`: `sect_founding.gd` prices an institution's
## existence on purpose and an override would make the price decorative. A hero who
## has not funded the price is refused `founding_cost_unmet` with both numbers
## published, and the trail records nothing — the whole ADR 0084 refusal contract.
##
## ## `founder_id` is a STRING, never this screen
##
## The ledger records the founder as a plain actor-id string, and an `Actor` reference
## would reach the save untouched with no checker in this repo able to see it.
func act_found(sect_id: String = "", doctrine_id: String = "") -> Dictionary:
	_bind_nodes()
	var wanted := sect_id if sect_id != "" else _selected_sect
	if _actor == null:
		return _verdict({NO_ACTOR: true})
	if wanted == "":
		return _verdict({NO_SECT_PICKED: true})
	var doctrine := doctrine_id if doctrine_id != "" else _doctrine_of(wanted)
	if doctrine == "":
		# A sect whose doctrine this build does not ship names no school to teach. The
		# module refuses `unknown_doctrine` for exactly this; asking it to is honest and
		# keeps the refusal in one vocabulary.
		return _settle(SectApi.found(_actor, StringName(wanted), &"", ""))
	var result := SectApi.found(_actor, StringName(wanted), StringName(doctrine), String(_actor.id))
	return _settle(result)


## Teach one period of the sworn sect's doctrine to `student_id`, spending this
## member's own `stamina` at the office's authored `teach_tax` plus the doctrine's.
##
## ## This is the ONLY caller of `SectApi.teach` in the shipped program
##
## `teach` was the only writer of `fit` and no verb anywhere called it, so the whole
## teaching ladder was reachable by no one — `SectApi.teach`'s only callers were tests.
## The cost stays the cost: one session is charged the teacher's stamina whether it is
## pressed here or anywhere else, so a button cannot make disciples a faucet (BL-0188).
##
## ## The teacher's fit gate is NOT bypassed
##
## A founder holds the first rung of the ladder through the founding grant, so this is
## live for them; anybody else is refused `teacher_unfit` by name. The screen does not
## pre-judge that — it asks the facade and renders the answer, because a screen that
## decided the gate itself would be a second copy of a rule the module owns.
func act_teach(student_id: String, periods: int = 1) -> Dictionary:
	_bind_nodes()
	if _actor == null:
		return _verdict({NO_ACTOR: true})
	if student_id == "":
		return _verdict({NO_PUPIL: true})
	var student := _pupil(student_id)
	if student == null:
		# The pupil is resolved by the composition root too (see `_pupil`): `ui/` may not
		# mint or look up an `Actor` by id, and naming a second roster would be a second
		# answer to "who is in this sect" that the module owns.
		return _verdict({NO_PUPIL: true})
	var doctrine := String(_codex.get("doctrine_id", ""))
	if doctrine == "":
		return _settle(SectApi.teach(_actor, student, &"", 1))
	return _settle(SectApi.teach(_actor, student, StringName(doctrine), maxi(1, periods)))


## Pick the sect `act_join` would swear the hero to. Returns false for an id the
## facade's catalog does not carry, so a caller never "selects" a house that does not
## exist — and clears the selection rather than leaving a stale one behind.
func select_sect(sect_id: String) -> bool:
	_bind_nodes()
	if sect_id == "":
		_selected_sect = ""
	elif (_codex.get("sects", {}) as Dictionary).has(sect_id):
		_selected_sect = sect_id
	else:
		return false
	_render()
	return true


## Pick the office `act_promote` would seat the hero in. Same rule: an office this
## board does not show is not selectable, and `""` clears.
func select_office(office_id: String) -> bool:
	_bind_nodes()
	if office_id == "":
		_selected_office = ""
	elif _office_ids().has(office_id):
		_selected_office = office_id
	else:
		return false
	_render()
	return true


## The sect the next `act_join` would use, or `""`. Private: `summary()` publishes
## `selected_sect` for a caller, so a second accessor for the same fact is the second
## thing that can go stale against the pick.
func _selected_sect_id() -> String:
	return _selected_sect


## The office the next `act_promote` would use, or `""`. Private for the reason
## [method _selected_sect_id] is.
func _selected_office_id() -> String:
	return _selected_office


## The last verb's verdict, verbatim. `{}` before any action has been taken. Private:
## `summary()` publishes `last_reason` / `last_ok` / `refused` from this same
## dictionary, and a duplicate copy is a copy that can be edited by a caller.
func _last_verdict() -> Dictionary:
	return _last_result.duplicate(true)


## The sect ids this screen is offering to be sworn to, in canonical order. A member
## is offered the whole catalog too — leaving is a `leave`, and re-swearing is the two
## in order — so this is the same list whatever the membership is.
func offered_ids() -> Array:
	_bind_nodes()
	return _report.offered_ids(_codex)


## Re-read the facade — the ONE call this screen makes — and hand raw values down.
## Every later read is of the cached `_codex`, never of the facade, so a refresh
## costs exactly one call however many times `summary()` is asked. The rows own
## every format.
func _refresh_view() -> void:
	_bind_nodes()
	if not _bound:
		return
	var live := SectApi.summary(_actor) if _actor != null else {}
	if not live.is_empty():
		_codex = live
	_fill_from_codex()


## Push the cached codex into the row pools. Split out from `_refresh_view` so that
## adopting a snapshot renders it without a second facade read.
func _fill_from_codex() -> void:
	_fill_claims()
	_fill_offices()


## Repaint this screen's own labels and the action row. The claim and office rows
## repaint themselves; `ActionSet` owns every button's label and its result line, so
## this screen formats nothing — it hands ids and the facade's own reason string down.
##
## The claim row shows the REFUSAL when one is outstanding, and the CLAIM otherwise.
## Those are deliberately not the same call: `show_claim({})` is ADR 0083's first
## state ("you belong to nothing"), while `show_refusal({"reason": R})` is the third
## ("you asked and were refused, here is the named rule"). Collapsing them would make
## a hero who is NOT sworn read exactly like a hero whose `join` was refused — which is
## the one distinction this screen exists to keep legible.
func _render() -> void:
	if _header == null:
		return
	if _actor == null:
		_header.text = NO_ACTOR_TEXT
		_footer.text = NO_ACTOR_FOOTER
		_publish_actions()
		return
	_header.text = HEADER_TEXT if bool(_codex.get("is_member", false)) else OFFERED_TEXT
	_footer.text = FOOTER_TEXT
	_publish_actions()


# --- ScreenStack hooks ------------------------------------------------------


## The landing spot is the member's own claim row — the thing the screen is read for —
## and failing that the first office with room. The action row's first LIVE control
## wins over both, because this screen now does something and the control a player can
## press is the one the keyboard must land on. Recorded first, because a node outside a
## viewport has nothing to focus yet.
func focus_initial() -> void:
	_bind_nodes()
	if _actions != null:
		var before := String(_focus_target)
		_actions.focus_initial()
		if String(_actions.summary().get("focus_target", "")) != "":
			_focus_target = String(_actions.summary()["focus_target"])
			return
		_focus_target = before
	var target := _first_filled(_claim_rows)
	if target == null:
		target = _first_filled(_office_rows)
	if target == null:
		return
	_focus_target = String(target.name)
	if target.is_inside_tree():
		target.call(&"focus_initial")


## `ui_accept` fires whatever is picked — a `join` when a sect is selected, a
## promotion when an office is — and `ui_up` / `ui_down` walk the picked list. Each is
## CONSUMED only when it did something, so `ui_cancel` stays free for `ScreenStack` to
## pop exactly as it pops every other screen: a screen that could commit an oath and
## also swallowed the cancel would trap a player inside it.
##
## The guards are merged into one clause on purpose rather than stacked: a screen that
## declines an unbound or unbound-input event by DECLARING it declined is exactly the
## contract `ScreenStack` relies on, and one decision says it once.
func on_stack_input(event: InputEvent) -> bool:
	if _actor == null or event == null or not _bound:
		return false
	if not event.is_pressed() or event.is_echo() or event.is_action_pressed(&"ui_cancel"):
		return false
	if event.is_action_pressed(&"ui_accept"):
		return _accept()
	if event.is_action_pressed(&"ui_down"):
		return _step(1)
	if event.is_action_pressed(&"ui_up"):
		return _step(-1)
	return false


func on_screen_hidden() -> void:
	pass


# --- Plumbing ---------------------------------------------------------------


func _bind_nodes() -> void:
	if _report == null:
		_report = SectReportModel.new()
	if _header != null:
		return
	_header = get_node_or_null("%ClaimHeader") as Label
	_footer = get_node_or_null("%FooterLabel") as Label
	_claim_box = get_node_or_null("Layout/Scroll/Codex/Claims") as VBoxContainer
	_office_box = get_node_or_null("Layout/Scroll/Codex/Offices") as VBoxContainer
	_actions = get_node_or_null("%Actions") as ActionSet
	_bound = _header != null and _footer != null and _claim_box != null and _office_box != null
	if not _bound:
		return
	_claim_rows = _rows_in(_claim_box, CLAIM_SCENE, "Claim", CLAIM_SPARE_ROWS)
	_office_rows = _rows_in(_office_box, OFFICE_SCENE, "Office", OFFICE_ROWS)
	_connect_actions()


## The action row, mounted by the scene. Bound lazily and only if the scene declares
## it, because a headless test may instantiate this screen's script against a scene
## that predates the action row; the ACTIONS are then unreachable and every verb
## reports `no_action_row` rather than pretending to have fired.
##
## The guard is what makes "one handler per connection" a fact rather than an
## accident of the `_bind_nodes` early return: the moment anything calls it a second
## time, an unguarded `connect` would duplicate silently.
func _connect_actions() -> void:
	if _actions == null:
		return
	if not _actions.action_requested.is_connected(_on_action_requested):
		_actions.action_requested.connect(_on_action_requested)


## Declare this screen's actions and their live state. Only ids and booleans go down;
## `ActionSet` owns the button text and the result line, so the screen formats no
## number and no sentence.
##
## `leave` and the two promotions stay DISABLED for a hero sworn to nothing rather
## than being live and refused: those refusals are `not_a_member`, which a hero who
## has not joined yet learns from the claim row already. `join` is live the moment a
## sect is picked, and the button stays live for a hero who is ALREADY sworn — because
## `already_sworn` is a rule the player should be told by pressing, not inferred from
## a greyed-out control.
func _publish_actions() -> void:
	if _actions == null:
		return
	(
		_actions
		. set_state(
			{
				"actions": _action_ids(),
				"labels":
				{
					ACTION_JOIN: "Swear to the picked sect",
					ACTION_LEAVE: "Leave the sect",
					ACTION_PROMOTE: "Take the picked office",
					ACTION_PROMOTE_FORCED: "Take it over the objection",
					ACTION_FUND: "Fund the founding price",
					ACTION_FOUND: "Found the picked sect",
					ACTION_TEACH: "Teach one period",
				},
				"enabled": _enabled_actions(),
				"primary": ACTION_JOIN if can_join() else ACTION_LEAVE,
			}
		)
	)


## The action ids, in the order the bar shows them. Read off the constants above so
## the order a test reads is the order the player sees.
func _action_ids() -> Array:
	return [
		String(ACTION_JOIN),
		String(ACTION_LEAVE),
		String(ACTION_PROMOTE),
		String(ACTION_PROMOTE_FORCED),
		String(ACTION_FUND),
		String(ACTION_FOUND),
		String(ACTION_TEACH)
	]


## Which of the seven is live right now. `join` needs a sect picked; `leave` needs a
## membership; both promotions need an office picked AND a membership, because an
## office only exists to somebody who is sworn to the sect that authors it.
##
## `fund` and `found` need a hero and a bound bridge / a picked sect, and `teach` needs
## a membership — **never more than that**. `found` in particular is NOT gated on the
## price being met: the pool belongs to the module and the screen cannot read it, so a
## hero who has not funded it presses and is told `founding_cost_unmet` with both
## numbers. `teach` is NOT gated on the teacher's fit either, for the same reason and
## the same one `join` is left live for an already-sworn hero.
func _enabled_actions() -> Dictionary:
	var member := _actor != null and bool(_codex.get("is_member", false))
	return {
		String(ACTION_JOIN): can_join(),
		String(ACTION_LEAVE): member,
		String(ACTION_PROMOTE): member and _selected_office != "",
		String(ACTION_PROMOTE_FORCED): member and _selected_office != "",
		String(ACTION_FUND): can_fund(),
		String(ACTION_FOUND): can_found(),
		String(ACTION_TEACH): can_teach(),
	}


## The button press, routed to the verb. `ActionSet.request` refuses a disabled
## action, so this cannot fire a verb the control does not offer.
##
## `fund` and `found` take the **authored price** as their amount rather than a number
## a button author typed: the fund button moves exactly what the picked sect charges to
## exist, read off the facade's own read model, so a retuned `.tres` changes what the
## button spends without anyone editing a screen. `teach` takes no pupil here and is
## refused `no_pupil` — a member to teach is chosen on a roster screen, and a screen
## that invented one would be teaching a body nobody named.
func _on_action_requested(action: StringName) -> void:
	match action:
		ACTION_JOIN:
			act_join()
		ACTION_LEAVE:
			act_leave()
		ACTION_PROMOTE:
			act_promote()
		ACTION_PROMOTE_FORCED:
			act_promote("", true)
		ACTION_FUND:
			# The AUTHORED price, read off the facade's own `founding_cost` rather than
			# from a number this screen kept — the same read `summary()` publishes, so
			# the button cannot spend a figure the module has since retuned away from.
			act_fund(int(_report.founding_cost_view(_codex, _selected_sect)["outstanding"]))
		ACTION_FOUND:
			act_found()
		ACTION_TEACH:
			act_teach("")


## `ui_accept` on the screen: a join when a sect is picked, otherwise a promotion.
##
## An office ALWAYS belongs to the sect the hero is already sworn to, so a hero who
## has picked both is making two different requests and the screen answers the one the
## ACT row is offering first: the sworn-to relation is the one they are already in, so
## a promotion is the more specific act and a join is the larger one. Declared in one
## place because two consumers (`on_stack_input` and the action bar) must agree.
func _accept() -> bool:
	if can_join():
		act_join()
		return true
	if member() and _selected_office != "":
		act_promote()
		return true
	return false


## The membership this screen is showing, for `_accept`'s own decision. A named
## predicate so the two consumers above read the same fact the same way.
func member() -> bool:
	return bool(_codex.get("is_member", false))


## Move the pick `step` entries along the offered list, wrapping. Returns false when
## there is nothing to pick, so `ui_down` on an empty catalog is declined rather than
## consumed — a screen that swallows a key it cannot honour is a screen that has
## swallowed the player's cancel by association.
##
## The list is the CATALOG while a hero is sworn to nothing and the BOARD once they
## are sworn: "which house may I join" and "which office may I take" are the two
## questions this screen asks, and only one of them has an answer at a time.
func _step(step: int) -> bool:
	var ids: Array = offered_ids() if not member() else _office_ids()
	if ids.is_empty():
		return false
	var index := ids.find(_selected_sect if not member() else _selected_office)
	if index < 0:
		index = 0 if step > 0 else ids.size() - 1
	var next := posmod(index + step, ids.size())
	var chosen := String(ids[next])
	if member():
		_selected_office = chosen
	else:
		_selected_sect = chosen
	_render()
	return true


## Every office id this board is showing, in display order — the list `ui_up` /
## `ui_down` walk for a sworn member. Read off the rows rather than off the facade, so
## what the player can pick is exactly what they can see.
func _office_ids() -> Array:
	return _report.office_ids(_office_rows)


## A refusal this screen raises ITSELF, in the facade's own `{ok, reason}` shape.
## Never a silent no-op: an action a player asked for that did not happen is reported
## in the same vocabulary the module uses, so one renderer covers both.
func _verdict(reasons: Dictionary) -> Dictionary:
	var reason := ""
	for key in reasons.keys():
		if reason == "":
			reason = String(key)
	return _settle({"ok": false, "reason": reason})


## Record a verdict, repaint, and hand the caller the module's OWN dictionary. The
## screen never rewrites it, so `last_result` is the facade's answer and a test can
## compare it against `SectApi` directly.
##
## The repaint happens AFTER the verdict is recorded, so the claim row the player sees
## is the one the verdict describes: a refused verb writes nothing (ADR 0084), so the
## claim behind it is byte-for-byte as found, and painting the refusal over it is what
## makes "the world did not change, and here is why" legible in one row.
func _settle(result: Dictionary) -> Dictionary:
	_bind_nodes()
	_last_result = (result as Dictionary).duplicate(true)
	if bool(_last_result.get("ok", false)):
		_refusal = {}
		set_message(String(_last_result.get("reason", "")), TONE_OK)
	else:
		_refusal = {"reason": String(_last_result.get("reason", ""))}
		# The reason VERBATIM. Not "Rejected: already_sworn", not a sentence this
		# screen composed: the module authored the constant and a panel that reworded
		# it would be describing a rule the module never wrote.
		set_message(String(_last_result.get("reason", "")), TONE_ERROR)
	refresh()
	return _last_result.duplicate(true)


## The rows the scene declares, in order, then enough grown rows to reach `extra`.
## A pool smaller than `extra` would have to truncate the data the next refresh
## brings, so the mounted rows are topped up here rather than left to `_grow()`.
func _rows_in(box: VBoxContainer, scene_path: String, prefix: String, extra: int) -> Array:
	var out: Array = []
	for child in box.get_children():
		var row := child as Control
		if row != null and (row.has_method(&"show_claim") or row.has_method(&"show_office")):
			out.append(row)
	for index in range(extra):
		var row := load(scene_path).instantiate() as Control
		row.name = "%s%d" % [prefix, out.size()]
		box.add_child(row)
		out.append(row)
	return out


## Grow a mounted pool to fit the data, so the page scrolls rather than truncates. A
## promotion route that silently vanished would read as an office the sect does not
## author, which is the dead-content failure ADR 0063 shipped once already.
func _grow(
	box: VBoxContainer, rows: Array, scene_path: String, prefix: String, needed: int
) -> void:
	# Bounded, not trusted: `needed` is a data-derived claim/office count, and a
	# pool that grows to fit an unbounded one parents live Controls without limit.
	var target := RowBudget.cap(needed)
	while rows.size() < target:
		var row := load(scene_path).instantiate() as Control
		row.name = "%s%d" % [prefix, rows.size()]
		box.add_child(row)
		rows.append(row)


func _first_filled(rows: Array) -> Node:
	for row in rows:
		if row.has_method(&"is_filled") and bool(row.call(&"is_filled")):
			return row
	return null


# --- Filling ----------------------------------------------------------------


## The member's own claim, or the refusal the last verb returned — ADR 0083's second
## and third states, kept apart.
##
## A refusal paints the row instead of the claim, and it keeps the module's OWN
## `reason` untouched. The claim behind it is still handed to the row as well — a
## refused verb writes nothing at all (ADR 0084), so those two are the same instant
## and showing both is what makes the refusal legible rather than an empty page.
##
## The refusal is cleared the moment a verb SUCCEEDS, and never by a plain repaint: a
## refresh reads the facade, and the facade has no memory of a refusal. So a refusal
## survives exactly as long as the player has not done anything else, which is what
## "you asked, you were refused, here is the named rule" has to mean.
func _fill_claims() -> void:
	if _claim_rows.is_empty():
		return
	if _refusal.is_empty():
		(_claim_rows[0] as SectClaimRow).show_claim(_codex.duplicate(true))
	else:
		var refused: Dictionary = _refusal.duplicate(true)
		refused["is_member"] = bool(_codex.get("is_member", false))
		(_claim_rows[0] as SectClaimRow).show_refusal(refused)
	for index in range(1, _claim_rows.size()):
		(_claim_rows[index] as SectClaimRow).show_claim({})


## Every authored office of the sworn sect, in canonical order. A seat nobody holds
## is a row with `"vacant": true` and renders; the offices a promotion route offers
## are rendered as their own rows too, so the board never hides a seat just because
## nobody is in it right now.
func _fill_offices() -> void:
	var promotion: Dictionary = _codex.get("can_promote", {}) as Dictionary
	var ids := promotion.keys()
	ids.sort()
	var views: Array = []
	for office_id in ids:
		var view: Dictionary = promotion[office_id]
		(
			views
			. append(
				{
					"office_id": String(view.get("id", "")),
					"display_name": String(view.get("display_name", "")),
					# This module holds no roster, so `held` is a count and the seat's
					# state is the authored reason the facade published. A seat with no
					# holder is still a row: `vacant` is exactly `held == 0`.
					"vacant": int(view.get("held", 0)) == 0,
					"holder_id": "",
					"capacity": 1,
					"succession_method": String(view.get("reason", "")),
					"powers": [],
				}
			)
		)
	_grow(_office_box, _office_rows, OFFICE_SCENE, "Office", views.size())
	var index := 0
	while index < _office_rows.size():
		(_office_rows[index] as NationOfficeRow).show_office(
			views[index] as Dictionary if index < views.size() else {}
		)
		index += 1

# --- Reporting --------------------------------------------------------------

## Every read model this screen publishes is [SectReportModel]'s — the claim the row
## reported, the promotion routes, the catalog for comparison, the board's office ids,
## the authored founding price and the string lists. They are reads of the facade's
## snapshot and of the mounted rows, never formatting and never a verb, so they move
## there whole; the screen keeps the calls thin so the shape `summary()` publishes is
## still visible in one place.
##
## `row_ids` was public and is now the model's `office_ids`: nothing outside this class
## called it, and `summary()["office_ids"]` is the surface the suites read.
