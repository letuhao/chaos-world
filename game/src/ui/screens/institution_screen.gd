class_name InstitutionScreen
extends UiScreen

## Every organization of ANY kind: the kinds the registry knows, the organizations
## authored for each, and the verbs a player presses on one.
##
## ## This screen reads `core` DIRECTLY, and that is not reaching into internals
##
## The institution family has **no module facade** -- `InstitutionRegistry`,
## `InstitutionDefCatalog`, `InstitutionDef`, `InstitutionFounding` and
## `InstitutionClaim` all live in `core/`, which is a LAYER BELOW `ui/`, and
## `institution_def_catalog.gd` states the rule in words: a module facade for a
## `core`-owned type "would be an indirection with no second owner". So the catalog read
## is a downward dependency, legal by the layering rule and reported by `tools arch`.
##
## ## What is NOT here, and why: join and leave are INJECTED, not reached for
##
## **The family publishes no `join`, no `leave` and no actor-scoped read.** The catalog
## read above answers "what exists"; nothing answers "what does THIS actor hold", and
## `InstitutionLedger` publishes exactly two writers -- `promote` and `move_standing` --
## neither of which enrols anybody. So the three actor-scoped seams arrive as `Callable`s
## from the composition root (ADR 0143's bridge, the same one `sect_screen`'s funding seam
## uses) and every one of them is **optional**: unbound, the verb refuses BY NAME rather
## than silently doing nothing. See [method bind_institutions] for the exact contract the
## gameplay side should publish.
##
## ## `found` needs no seam, because it genuinely exists
##
## [method act_found] calls the generic founding verb for real. It returns that verb's own
## verdict verbatim, so a hero who has not funded the price is told
## `founding_cost_unmet` by the author of that rule rather than by a greyed-out button.
## **It does not persist the ledger onto the actor** -- that write belongs to the missing
## facade, so the written ledger is published under `summary()["founded"]` rather than
## dropped on the floor.
##
## ## This screen FORMATS NOTHING
##
## Raw values go down to [InstitutionCard], which owns every `%d`, every word and every
## tone. A screen that re-derived a price or printed a ratio could disagree with the
## module that owns it.

## The card this screen's pool is built from. Rows the scene mounts, then enough grown
## rows to reach `CARD_CAP`, then a bounded surplus.
const CARD_SCENE := "res://src/ui/panels/institution_card.tscn"
const CARD_ROWS := 4
const CARD_CAP := 16
const CARD_SPARE_ROWS := 1
## Where the author wants the keyboard to land, as one sentence.
const HEADER_TEXT := "Every kind of organization, the offices it publishes, and your place in one."
const NO_ACTOR_TEXT := "No hero bound."
const FOOTER_TEXT := "Up / Down picks an organization, Accept founds or joins it. Cancel returns."
const NO_ACTOR_FOOTER := ""

## The refusals this screen raises ITSELF, before any verb is called. Authored constants
## rather than prose, for the reason the module's are: a panel renders a reason it did not
## have to invent, and an action a player asked for that did not happen is a refusal.
const NO_ACTOR := "no_actor"
const NO_ORGANIZATION_PICKED := "no_organization_picked"
const NO_ORGANIZATION := "unknown_organization"
const NO_JOIN_SEAM := "no_join_seam"
const NO_LEAVE_SEAM := "no_leave_seam"

## The verbs a player presses here, in the order the bar shows them. Fixed, never grown:
## the set of things a player may do to an organization is a design, not a data count.
const ACTION_FOUND := &"found"
const ACTION_JOIN := &"join"
const ACTION_LEAVE := &"leave"

var _catalog: Dictionary = {}
var _claims: Dictionary = {}
var _reader: Callable = Callable()
var _joiner: Callable = Callable()
var _leaver: Callable = Callable()
var _selected: String = ""
var _selected_kind: String = ""
var _last_result: Dictionary = {}
var _founded: Dictionary = {}
var _header: Label = null
var _footer: Label = null
var _cards_box: VBoxContainer = null
var _cards: Array = []
var _bound: bool = false


## ## The actor-scoped seams, injected by the composition root
##
## All three are OPTIONAL and independently so, because "the reader is not bound" and
## "the join verb is not bound" are different sentences a player must be able to tell
## apart:
##
##   - `state_reader()` -> `Dictionary`. **The read the family is missing**: the same
##     `summary(actor)` shape `SectApi` and `NationApi` already publish, carrying
##     `{"institutions": {<organization_id>: {exists, position, standing, standing_cap,
##     normalized, obligations, roster}}}`. `normalized` is the ratio
##     `InstitutionClaim.normalized()` computed -- this screen never divides.
##   - `joiner(institution_id: String)` -> `Dictionary`. `{ok, reason}`.
##   - `leaver()` -> `Dictionary`. `{ok, reason}`.
##
## Assigned exactly as given (not merged into a default), so binding a deliberate
## `Callable()` clears a previously bound seam -- the rule `item_workbench.setup` follows.
func bind_institutions(
	state_reader: Callable = Callable(),
	joiner: Callable = Callable(),
	leaver: Callable = Callable()
) -> void:
	_bind_nodes()
	_reader = state_reader
	_joiner = joiner
	_leaver = leaver
	refresh()


## Adopt a catalog snapshot instead of re-reading `core`, so a headless driver can render
## one without a boot. An empty snapshot clears the adoption and the screen falls back to
## the live read.
func apply_snapshot(snapshot: Dictionary) -> void:
	_bind_nodes()
	_catalog = snapshot.duplicate(true)
	_fill_cards()
	_render()


## Adopt an actor-scoped claim read model, so a driver can render membership without the
## seam. `{}` clears it, which is the FIRST state -- not "no institutions".
func apply_claim(view: Dictionary) -> void:
	_bind_nodes()
	_claims = view.duplicate(true)
	_fill_cards()
	_render()


func _summary() -> Dictionary:
	_bind_nodes()
	if _actor == null:
		return {}
	var organizations := _organization_summaries()
	var vacant := 0
	var offices := 0
	for row in organizations:
		var view: Dictionary = row
		vacant += 1 if bool(view.get("vacant", false)) else 0
		offices += int(view.get("position_count", 0))
	var picked := _selected_view()
	return {
		"actor": String(_actor.id),
		"read_only": false,
		# The KINDS the registry knows, canonically ordered, and the ORGANIZATIONS
		# authored for each -- the two halves of "what exists in this world".
		"kinds": _strings(_catalog.get("kinds", [])),
		"kind_count": (_catalog.get("kinds", []) as Array).size(),
		# The registry's own half, reported beside the union so "this world has no kinds"
		# and "the boot has not run" stay tellable apart.
		"registered_kinds": _strings(_catalog.get("registered_kinds", [])),
		"boot_ran": bool(_catalog.get("boot_ran", false)),
		"organizations": organizations,
		"organization_count": organizations.size(),
		"organization_ids": organization_ids(),
		"vacant_count": vacant,
		"position_count": offices,
		# Child summaries nested under the child's key: the cards' own summaries are the
		# testable surface for everything they render.
		"cards": _card_summaries(),
		# ## RAW values, never formatted. The panel owns every number it prints.
		"founding_cost": int(picked.get("founding_cost", 0)),
		"standing_cap": int(picked.get("standing_cap", 0)),
		"founder_standing": int(picked.get("founder_standing", 0)),
		"claims_bound": claims_bound(),
		"join_bound": _joiner.is_valid(),
		"leave_bound": _leaver.is_valid(),
		"selected": _selected,
		"selected_kind": _selected_kind,
		"actions": _action_ids(),
		"enabled": _enabled_actions(),
		# ADR 0083's three states as three DISTINCT facts: the claim, the refusal the
		# last verb returned, and the catalog. A screen that renders all three cannot
		# make them read alike.
		"refused": bool(_last_result.get("ok", true)) == false,
		"refusal_reason": String(_last_result.get("reason", "")),
		"last_reason": String(_last_result.get("reason", "")),
		"last_ok": bool(_last_result.get("ok", false)),
		"founded": _founded.duplicate(true),
	}


# --- The actor-scoped verbs ---------------------------------------------------


## Whether the actor-scoped READ is bound. Published so a driver or a test can tell "this
## screen cannot see your claim" from "this screen has no claim", which are different
## sentences and both reachable.
func claims_bound() -> bool:
	return _reader.is_valid()


## Whether the bound actor FOUND the picked organization. Read off the claim model, and
## **never derived from a refusal** -- a refused `found` writes nothing at all.
func is_founder() -> bool:
	var claim := _claim_of(_selected)
	return claim.is_empty() == false and bool(claim.get("exists", false))


## Bring the picked organization into being, seating the actor in its top authored
## office. The generic founding verb, reached through `core`, returned verbatim.
##
## There is deliberately no `force`: `InstitutionFounding.cost` prices an organization's
## existence, and an override would make the price decorative. A hero who has not funded
## the price is refused `founding_cost_unmet` with both numbers published and nothing
## written -- the whole refusal contract.
##
## ## The ledger it writes is PUBLISHED, not dropped
##
## `found` returns a NEW ledger and writes nothing onto the actor: persisting it is the
## missing facade's job, not this screen's. So the written ledger is kept under
## `summary()["founded"]`, where a caller can adopt it, rather than being discarded by a
## screen that cannot store it.
func act_found(organization_id: String = "") -> Dictionary:
	_bind_nodes()
	var wanted := organization_id if organization_id != "" else _selected
	if _actor == null:
		return _verdict(NO_ACTOR)
	if wanted == "":
		return _verdict(NO_ORGANIZATION_PICKED)
	var def := _definition(wanted)
	if def == null:
		return _verdict(NO_ORGANIZATION)
	var answer := InstitutionFounding.found(
		InstitutionRegistry.instance(), _actor, def.founding_profile(), String(_actor.id), {}
	)
	# ## The SETTLEMENT is read from `ok`, not from the verdict this screen composes
	#
	# `settled()` was the first version and it read a key `InstitutionLedger.ok` does not
	# write: every answer carries `ok` and `reason`, and `reason` is `""` on success, so a
	# success is an empty reason rather than a missing key. Reading the key that is not
	# there made a SUCCESSFUL founding read as unsettled and drop the ledger a hero had
	# just paid for.
	if bool(answer.get("ok", false)):
		var written: Variant = answer.get("ledger", {})
		_founded = written as Dictionary if written is Dictionary else {}
	else:
		_founded = {}
	return _settle(answer)


## Enrol the bound actor in the picked organization. Returns the injected verb's verdict
## unchanged, so a caller reads what actually happened rather than a screen's account of
## it. Unbound, it refuses `no_join_seam` **by name** -- a silent no-op is not a refusal.
func act_join(organization_id: String = "") -> Dictionary:
	_bind_nodes()
	var wanted := organization_id if organization_id != "" else _selected
	if _actor == null:
		return _verdict(NO_ACTOR)
	if wanted == "":
		return _verdict(NO_ORGANIZATION_PICKED)
	if _definition(wanted) == null:
		return _verdict(NO_ORGANIZATION)
	if not _joiner.is_valid():
		return _verdict(NO_JOIN_SEAM)
	return _settle(_joiner.call(wanted) as Dictionary)


## Walk out. Returns the injected verb's verdict unchanged, refused `no_leave_seam` by
## name when unbound.
func act_leave() -> Dictionary:
	_bind_nodes()
	if _actor == null:
		return _verdict(NO_ACTOR)
	if not _leaver.is_valid():
		return _verdict(NO_LEAVE_SEAM)
	return _settle(_leaver.call() as Dictionary)


## Pick the organization the next verb would act on. An id the catalog does not carry is
## REFUSED rather than selected, so a caller never "joins" a house that does not exist.
func select_organization(organization_id: String) -> bool:
	_bind_nodes()
	if organization_id == "":
		_selected = ""
		_selected_kind = ""
	elif _definition(organization_id) != null:
		_selected = organization_id
		_selected_kind = String(_definition(organization_id).kind)
	else:
		return false
	_render()
	return true


## Every organization id this screen is offering, in canonical order. The whole catalog
## whatever the membership is: leaving and re-joining are the two verbs, in that order.
func organization_ids() -> Array:
	var out: Array = []
	var rows: Variant = _catalog.get("organizations", [])
	if not (rows is Array):
		return out
	for entry in rows as Array:
		if not (entry is Dictionary):
			continue
		out.append(String((entry as Dictionary).get("id", "")))
	return out


# --- Reading `core`. One call per refresh ------------------------------------


## Re-read `core` and the injected reader. Every later read is of the CACHED dictionaries,
## so a refresh costs one walk however many times `summary()` is asked, and the rows own
## every format.
func _refresh_view() -> void:
	_bind_nodes()
	if not _bound:
		return
	# ## The CLAIMS are read BEFORE the catalog, and that order is load-bearing
	#
	# `_read_catalog` bakes each organization's claim INTO the row it hands the card, so
	# reading the catalog first built every row against the PREVIOUS pass's claims -- the
	# first refresh rendered an actor as belonging to nothing, and no later refresh could
	# correct it because the catalog it re-read already carried the empty claim.
	_claims = _read_claims()
	_catalog = _read_catalog()
	_fill_cards()


## The kinds the registry knows and the organizations authored for them, as primitives.
##
## A `for` over the catalog's OWN sorted id list, writing into two FRESH arrays: the body
## never grows the container it walks, so the bound is the authored content count and
## there is no shape here for a loop to grow in lockstep with its own bound
## (`tests/arch_rules/test_no_unbounded_wait.gd`).
func _read_catalog() -> Dictionary:
	var registry := InstitutionRegistry.instance()
	var catalog := InstitutionDefCatalog.instance()
	var registered: Array = []
	for kind in registry.kinds():
		registered.append(String(kind))
	var rows: Array = []
	var authored_kinds: Array = []
	for institution_id in catalog.ids():
		var def := catalog.definition(institution_id)
		if def == null:
			continue
		rows.append(_organization_view(def))
		if not authored_kinds.has(String(def.kind)):
			authored_kinds.append(String(def.kind))
	# ## `kinds` is the UNION, and the union is not a convenience
	#
	# The registry only knows a kind once `InstitutionBoot.install()` has run, and nothing
	# in `ui/` runs it. So a screen that published the registry's list alone rendered three
	# guilds under an EMPTY kind list the first time anything drove it headlessly -- and an
	# empty list is a claim ("this world has no kinds") rather than an admission that the
	# boot had not happened. Each authored organization names its own kind, so the union is
	# answerable either way, and the two halves are published separately so a reader can
	# still tell which boot had run.
	var union: Array = []
	for kind in registered:
		if not union.has(kind):
			union.append(kind)
	for kind in authored_kinds:
		if not union.has(kind):
			union.append(kind)
	union.sort()
	return {
		"ok": catalog.is_loaded(),
		"root": String(InstitutionDefCatalog.INSTITUTIONS_ROOT),
		"kinds": union,
		"registered_kinds": registered,
		"boot_ran": not registered.is_empty(),
		"organizations": rows,
	}


## The actor-scoped read, or `{}` when the seam is unbound. `{}` is the FIRST state and
## never "the actor holds nothing", which is a different claim about the world.
func _read_claims() -> Dictionary:
	if not _reader.is_valid():
		return {}
	var answered: Variant = _reader.call()
	return answered as Dictionary if answered is Dictionary else {}


## One organization's whole view, handed to [InstitutionCard] as RAW values.
func _organization_view(def: InstitutionDef) -> Dictionary:
	var roster := _roster_of(String(def.id))
	var offices: Array = []
	for office in def.positions:
		offices.append(_office_view(def, office))
	var claim := _claim_of(String(def.id))
	var view := {
		"id": String(def.id),
		"kind": String(def.kind),
		"display_name": String(def.display_name),
		"description": String(def.description),
		"founding_cost": int(def.founding_cost),
		"standing_cap": int(def.standing_cap),
		"founder_standing": int(def.founder_standing),
		"capabilities": _strings(def.authored_capabilities()),
		"territories": _strings(def.claimed_territories()),
		"positions": offices,
		"claim": claim,
		"ok": true,
	}
	# ## A VACANCY is published only when the actor-scoped read actually ANSWERED
	#
	# The organization exists and the viewer holds no claim in it, which is ADR 0083's
	# middle state -- but only when the reader is bound. With the seam unbound this key
	# is ABSENT, so the card reports "not a member" without claiming to know the world's
	# rosters. Inventing `held == 0` from an absent roster would fabricate a succession.
	if claims_bound():
		view["vacant"] = not bool(claim.get("exists", false))
	return view


## One office's view. The `vacant` key is ABSENT rather than `false` when no roster was
## published, so "nobody holds it" and "nobody told us" stay different facts.
func _office_view(def: InstitutionDef, office: InstitutionPositionDef) -> Dictionary:
	var roster := _roster_of(String(def.id))
	var key := String(office.id)
	var known := roster.has(key)
	var held := 0
	var holders := ""
	if known:
		var members: Variant = roster[key]
		if members is Array:
			held = (members as Array).size()
		holders = ", ".join(PackedStringArray(_strings(members)))
	var view := {
		"id": key,
		"display_name": String(office.display_name),
		"capacity": office.room(),
		"held": held,
		"holders": holders,
		"duty_per_period": int(office.duty_per_period),
		"patronage_per_period": int(office.patronage_per_period),
		"duties": _strings(office.duty_terms()),
		"authorities": _strings(office.authorities),
	}
	if known:
		view["vacant"] = held == 0
	return view


## The claim the reader published for one organization, or `{}`. **The ratio is read, not
## divided**: `normalized` is what `InstitutionClaim.normalized()` computed, and a screen
## that recomputed it could disagree with the claim it is showing.
func _claim_of(institution_id: String) -> Dictionary:
	if institution_id == "":
		return {}
	var rows: Variant = _claims.get("institutions", {})
	if not (rows is Dictionary):
		return {}
	var found: Variant = (rows as Dictionary).get(institution_id, {})
	return found as Dictionary if found is Dictionary else {}


## The published roster for one organization, or `{}`. `{}` means nobody published one.
func _roster_of(institution_id: String) -> Dictionary:
	var claim := _claim_of(institution_id)
	var roster: Variant = claim.get("roster", {})
	return roster as Dictionary if roster is Dictionary else {}


func _definition(institution_id: String) -> InstitutionDef:
	if institution_id == "":
		return null
	return InstitutionDefCatalog.instance().definition(StringName(institution_id))


## The picked organization's cached catalog row, or `{}` when nothing is picked. Read from
## the cache rather than rebuilt, so `summary()` costs no `core` walk of its own.
func _selected_view() -> Dictionary:
	var rows: Variant = _catalog.get("organizations", [])
	if not (rows is Array):
		return {}
	for entry in rows as Array:
		if not (entry is Dictionary):
			continue
		var view := entry as Dictionary
		if String(view.get("id", "")) == _selected:
			return view
	return {}


# --- ScreenStack hooks -------------------------------------------------------


## The landing spot is the action row's first LIVE control, because this screen can act
## and the control a player can press is the one the keyboard must land on. Failing that,
## the first filled card.
func focus_initial() -> void:
	_bind_nodes()
	if _actions_live_target() != "":
		return
	var target := _first_filled()
	if target == null:
		return
	_focus_target = String(target.name)
	if target.is_inside_tree():
		target.call(&"focus_initial")


## `ui_accept` fires the verb the picked organization offers and `ui_up` / `ui_down` walk
## the catalog. Each is CONSUMED only when it did something, so `ui_cancel` stays free for
## `ScreenStack` to pop exactly as it pops every other screen -- a screen that could commit
## a founding and also swallowed the cancel would trap a player inside it.
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


## Nothing to release: this screen holds no timer, no subscription and no bridge of its
## own, and the seams are the composition root's to clear. Declared rather than inherited
## so the four hooks are visibly all here.
func on_screen_hidden() -> void:
	pass


# --- Plumbing ---------------------------------------------------------------


func _bind_nodes() -> void:
	if _header != null:
		return
	_header = get_node_or_null("%InstitutionHeader") as Label
	_footer = get_node_or_null("%FooterLabel") as Label
	_cards_box = get_node_or_null("Layout/Scroll/Codex/Cards") as VBoxContainer
	_bound = _header != null and _footer != null and _cards_box != null
	if not _bound:
		return
	_cards = _cards_in(_cards_box)
	# The guard that makes "one handler per connection" a fact rather than an accident
	# of the `_bind_nodes` early return: the moment anything calls this a second time an
	# unguarded connect would duplicate silently.
	var actions := get_node_or_null("%InstitutionActions") as ActionSet
	if actions != null and not actions.action_requested.is_connected(_on_action_requested):
		actions.action_requested.connect(_on_action_requested)


## Push the cached catalog into the card pool. Each card is shown one organization's raw
## view and clears itself on `{}`, which is how a spare pool row and a real organization
## stay different things.
func _fill_cards() -> void:
	if _cards.is_empty():
		return
	var rows: Array = _catalog.get("organizations", []) as Array
	var wanted := mini(RowBudget.cap(rows.size()), CARD_CAP)
	_grow(_cards_box, _cards, wanted)
	var shown := mini(_cards.size(), wanted)
	for index in range(_cards.size()):
		var view: Dictionary = {}
		if index < shown:
			view = rows[index] as Dictionary
		(_cards[index] as InstitutionCard).show_organization(view)


## Grow the mounted pool toward `target`, capped by `RowBudget` and never past
## `CARD_CAP`. The bound is snapshotted BEFORE the loop and is a constant, so this is the
## "fills toward a fixed count with an unconditional append" shape the unbounded-wait
## guard accepts -- there is no `while` and no size another body grows.
func _grow(box: VBoxContainer, rows: Array, target: int) -> void:
	var ceiling := mini(maxi(target, rows.size()), CARD_CAP)
	for index in range(rows.size(), ceiling):
		var card := load(CARD_SCENE).instantiate() as InstitutionCard
		card.name = "Card%d" % index
		box.add_child(card)
		rows.append(card)


## The cards the scene declares, in order, then the grown surplus. A pool smaller than
## the data would truncate a promotion route, which reads as an office the organization
## does not author.
func _cards_in(box: VBoxContainer) -> Array:
	var out: Array = []
	for child in box.get_children():
		var card := child as InstitutionCard
		if card != null:
			out.append(card)
	for index in range(CARD_SPARE_ROWS):
		var card := load(CARD_SCENE).instantiate() as InstitutionCard
		card.name = "Spare%d" % index
		box.add_child(card)
		out.append(card)
	return out


func _render() -> void:
	if _header == null:
		return
	if _actor == null:
		_header.text = NO_ACTOR_TEXT
		_footer.text = NO_ACTOR_FOOTER
		_publish_actions()
		return
	_header.text = HEADER_TEXT
	_footer.text = FOOTER_TEXT
	_publish_actions()


## Declare this screen's actions and their live state. Only ids and booleans go down;
## `ActionSet` owns every button's label and the result line.
##
## `found` and `join` are live whenever an organization is picked and are NOT gated on
## what the verb will decide: a player who cannot afford a house, or who is already in
## one, is told WHY by pressing. `leave` needs a claim. A screen that greyed a button out
## on a rule it cannot read would make that rule invisible rather than named.
func _publish_actions() -> void:
	var actions := get_node_or_null("%InstitutionActions") as ActionSet
	if actions == null:
		return
	(
		actions
		. set_state(
			{
				"actions": _action_ids(),
				"labels":
				{
					ACTION_FOUND: "Found the picked organization",
					ACTION_JOIN: "Join the picked organization",
					ACTION_LEAVE: "Leave the organization",
				},
				"enabled": _enabled_actions(),
				"primary": ACTION_JOIN if can_join() else ACTION_FOUND,
			}
		)
	)


func _action_ids() -> Array:
	return [String(ACTION_FOUND), String(ACTION_JOIN), String(ACTION_LEAVE)]


func _enabled_actions() -> Dictionary:
	var picked := _actor != null and _selected != ""
	return {
		String(ACTION_FOUND): picked,
		String(ACTION_JOIN): picked,
		String(ACTION_LEAVE): _actor != null and _claim_of(_selected).get("exists", false) == true,
	}


## Whether a `join` can run from here: an actor and a picked organization. The SEAM is
## deliberately not part of it -- an unbound verb refuses by name, which is the sentence
## the player needs.
func can_join() -> bool:
	return _actor != null and _selected != ""


## The button press, routed to the verb. `ActionSet.request` refuses a disabled action, so
## this cannot fire a verb the control does not offer.
func _on_action_requested(action: StringName) -> void:
	match action:
		ACTION_FOUND:
			act_found()
		ACTION_JOIN:
			act_join()
		ACTION_LEAVE:
			act_leave()


## `ui_accept` on the screen: the JOIN when one is offered, otherwise the founding. A join
## is the smaller act of the two and the one a hero with no organization wants first.
func _accept() -> bool:
	if can_join():
		act_join()
		return true
	return false


## Move the pick `step` entries along the catalog, wrapping. Declines on an empty catalog
## rather than consuming the key: a screen that swallows a key it cannot honour has, by
## association, swallowed the player's cancel too.
func _step(step: int) -> bool:
	var ids := organization_ids()
	if ids.is_empty():
		return false
	var index := ids.find(_selected)
	if index < 0:
		index = 0 if step > 0 else ids.size() - 1
	var chosen := String(ids[posmod(index + step, ids.size())])
	return select_organization(chosen)


## A refusal this screen raises ITSELF, in the facade's own `{ok, reason}` shape. Never a
## silent no-op.
func _verdict(reason: String) -> Dictionary:
	return _settle({"ok": false, "reason": reason})


## Record a verdict, repaint, and hand the caller the verb's OWN dictionary -- this screen
## never rewrites it, so a test can compare it against `core` directly.
##
## The repaint happens AFTER the verdict is recorded, so the row the player sees is the one
## the verdict describes: a refused verb writes nothing, and painting the refusal over an
## unchanged claim is what makes "the world did not change, and here is why" legible.
func _settle(result: Dictionary) -> Dictionary:
	_bind_nodes()
	_last_result = (result as Dictionary).duplicate(true)
	set_message(
		String(_last_result.get("reason", "")),
		TONE_OK if bool(_last_result.get("ok", false)) else TONE_ERROR
	)
	refresh()
	return _last_result.duplicate(true)


## The live control the keyboard should land on, or `""`. Records the target on the action
## row itself, which is where the focus actually goes.
func _actions_live_target() -> String:
	var actions := get_node_or_null("%InstitutionActions") as ActionSet
	if actions == null:
		return ""
	actions.focus_initial()
	var target := String(actions.summary().get("focus_target", ""))
	if target != "":
		_focus_target = target
	return target


## Every card's own summary, nested under this screen's `cards` key so a test reads the
## rendered payload without walking the tree. Spare rows report `{}` and stay in place.
func _card_summaries() -> Array:
	var out: Array = []
	for card in _cards:
		out.append((card as InstitutionCard).summary())
	return out


## The catalog rows that carry an organization, as their own card payloads. A spare row
## is dropped here so `organization_count` counts organizations, not widgets.
func _organization_summaries() -> Array:
	var out: Array = []
	for row in _card_summaries():
		var view: Dictionary = row
		if view.is_empty():
			continue
		out.append(view)
	return out


func _first_filled() -> Node:
	for card in _cards:
		if bool((card as InstitutionCard).is_filled()):
			return card
	return null


func _strings(value: Variant) -> Array:
	var out: Array = []
	if not (value is Array):
		return out
	for entry in value as Array:
		out.append(String(entry))
	return out
