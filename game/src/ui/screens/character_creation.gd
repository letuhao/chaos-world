class_name CharacterCreation
extends UiScreen

## Where a hero is made: three ways of arriving in the world, and the one button
## that commits the answer.
##
## ## This is a NEW screen, and it had to be
##
## The fate codex (`destiny_screen.gd`) is architecturally barred from gaining a
## button — `destiny_branch_row.gd:13-15` states that a destiny is earned and cannot
## be chosen, so the codex is read-only by design. This screen is the one place a
## player answers a question about their own arrival, which is not the same act: the
## player does not pick a destiny, and nothing here lists fates.
##
## ## What the player actually chooses
##
## The player answers **how they arrived**. The creation layer turns that into
## exactly one `group = &"origin"` destiny through
## `CharacterCreationFlow.build`, which calls `DestinyApi.earn_destiny(actor, id,
## "origin")` once — DEF-0109, verbatim. ADR 0065 is untouched: there is no picker
## over the fate catalog, no control that grants an unearned fate, and the module's
## own `group` rule closes the other two arrivals permanently once one is committed.
##
## ## Contract
##
## `summary()` is the testable surface: primitives only, each row's own summary
## nested under `branches`, and `{}` when nothing has been committed. The screen
## itself never reads a module — it renders `CharacterCreationFlow.candidates()`
## and reports the flow's verdict, so `ui/` gains no edge the arch gate has not
## already granted.
##
## **`{}` is not a gap here, it is the rule.** There is no hero until the player
## answers, and `summary()` stays `{}` for exactly that reason: a summary that
## described three options before any exist would be describing content nobody can
## commit yet.

const BRANCH_ROWS := 3
const BRANCH_SCENE := "res://src/ui/panels/creation_branch_row.tscn"
## One line, and the whole of this screen's argument.
const HEADER_TEXT := "LOC_UI_SCREENS_A072A411A3"
const OPEN_FOOTER := "LOC_UI_SCREENS_CE1FBFB330"
const COMMITTED_TEXT := "LOC_UI_SCREENS_D89FBA96E7"
const COMMITTED_FOOTER := "LOC_UI_SCREENS_DEF9280FED"
## The ScreenStack hooks consume nothing on a screen that has already committed:
## `ui_cancel` is left free for the stack to pop, exactly as on every read-only one.
const COMMIT_OK := "committed"
## What `%ConfirmButton` is, once it has been wired. A live control that does nothing is
## worse than none: it reads as the door and refuses to open.
const CONFIRM_TEXT := "LOC_UI_SCREENS_02AD3B27AB"
const CONFIRM_OFFER := "LOC_UI_SCREENS_41E6BAF2EB"

var _candidates: Array[Dictionary] = []
var _result: Dictionary = {}
var _header: Label = null
var _footer: Label = null
var _branch_box: VBoxContainer = null
var _confirm_button: Button = null
var _picker: PortraitPicker = null
var _branch_rows: Array = []
var _bound: bool = false
## The face this hero is arriving with, or `""`.
##
## **`""` is an ANSWER, not an absence.** A hero with no chosen face resolves race,
## then placeholder (ADR 0131), which is exactly what happens today — so the
## control is optional and a creation can never fail because the catalogue is
## empty or a fetch failed (ADR 0257 §5).
var _chosen_portrait: StringName = &""
## The one door into gameplay this screen has: a `Callable` the composition root
## injects, exactly as `ItemWorkbenchApp._loot_bridge()` does for the loot screen.
##
## **`ui/` may not reference `app/`** (`PRIVATE_UNITS` in `tools/arch/rules.py`),
## so this screen cannot name `CharacterCreationFlow` and neither may its rows. The
## seam is the same answer the ADR 0076 split gives the loot program: the bridge
## carries callables, not gameplay types, so no module or app type crosses into
## this file. `_candidates` arrives the same way `DestinyScreen` takes a snapshot —
## the screen renders what it is handed and owns no rule.
var _commit_requested: Callable = Callable()


## The arrival this hero was committed with, or `""`. A report, never a selection:
## once committed there is no other answer.
func committed_origin() -> String:
	return String(_result.get("choice", ""))


## The hero this screen created, or null. The screen holds no `_actor` of its own
## before the commit — `UiScreen.actor()` stays null because the player has no hero
## yet — so `summary()` reports nothing until this is non-null.
func created_actor() -> Actor:
	return _result.get("actor", null) as Actor


## Hand the screen the arrivals to offer and the callable that commits one.
##
## `candidates` is an `Array[Dictionary]` exactly as
## `CharacterCreationFlow.candidates()` publishes it; `commit` is called as
## `commit(origin_id) -> Dictionary` and its verdict is rendered verbatim. Both are
## injected because `ui/` is a pure consumer and may hold neither (ADR 0076/0078).
##
## Without both the screen renders an empty form rather than guessing: a screen
## with no seam is a screen with nothing to offer, and saying so is the whole of
## its job until the composition root wires it.
func bind_creation(candidates: Array[Dictionary], commit: Callable) -> void:
	_candidates = candidates.duplicate(true)
	_commit_requested = commit
	_bind_nodes()
	_feed()
	_render()


## Re-render the rows from the snapshot already handed in. A no-op with no
## snapshot: this screen never reads gameplay for itself.
func refresh_candidates() -> void:
	_bind_nodes()
	if not _bound:
		return
	_feed()
	_render()


## Commit `origin_id` as this hero's arrival: press the row's button, and this is
## what happens.
##
## Delegates the whole earn through the injected seam and never touches a module
## itself. Returns the creation layer's own verdict verbatim — `{ok, reason, ...}` —
## so a caller never has to infer an outcome from this screen's message line.
## Without a seam it refuses `no_creation_seam` rather than quietly doing nothing.
func act_commit(origin_id: StringName) -> Dictionary:
	_bind_nodes()
	if not _commit_requested.is_valid():
		_result = {"ok": false, "reason": "no_creation_seam", "unmet": []}
		set_message(String(_result["reason"]), TONE_ERROR)
		return _result
	var outcome := _commit_requested.call(origin_id) as Dictionary
	_result = outcome
	if bool(outcome.get("ok", false)):
		# The creation layer now owns a hero, so this screen becomes a view OF it
		# rather than a form. Reporting it through `UiScreen` is what keeps
		# `summary()` honest: with an actor bound it renders the committed arrival.
		var hero := outcome.get("actor", null) as Actor
		setup(hero)
		_record_face(hero)
		set_message(COMMITTED_TEXT, COMMIT_OK)
	else:
		set_message(String(outcome.get("reason", "")), TONE_ERROR)
	refresh()
	return outcome


## Record the face the player took, through the EXISTING verb and nothing else.
##
## ## Why this runs HERE and not inside the commit seam
##
## `ui/` reads `core/` — `soul_hearth_screen.gd:531` already calls
## `PortraitResolver.resolve` directly — and `PortraitResolver.choose` is the one
## place a chosen face is ever written (ADR 0257 §1). So the screen calls it on
## the hero the seam returned, rather than a second persistence path and rather
## than widening `CharacterCreationFlow.build`, which a dozen callers already
## hold with one argument.
##
## ## Why it can never fail a creation
##
## **A hero with no chosen face records NOTHING**, so `resolve` answers race then
## placeholder exactly as it did before this control existed. And a `choose` that
## refuses — an id the catalogue lost between the offer and the press — is
## REPORTED and never propagated, because a face is not a gate: a hero that cannot
## be given a face still arrives (ADR 0257 §5).
func _record_face(hero: Actor) -> Dictionary:
	var answer := {"ok": true, "reason": "no_face_chosen", "portrait_id": ""}
	if hero == null or _chosen_portrait.is_empty():
		return answer
	var outcome := PortraitResolver.choose(hero, _chosen_portrait)
	answer = {
		"ok": bool(outcome.get("ok", false)),
		"reason": String(outcome.get("reason", "")),
		"portrait_id": String(outcome.get("portrait_id", "")),
	}
	# A refusal must not leave the screen claiming a face the hero does not carry.
	if not bool(outcome.get("ok", false)):
		_chosen_portrait = &""
	return answer


## The face this hero is arriving with, or `""` — which resolves race, then
## placeholder. A report, never a selection the caller can write directly.
func chosen_portrait() -> StringName:
	return _chosen_portrait


## Take `portrait_id` as this hero's face, or nothing when it is `""`.
##
## ## Why this is a REQUEST and the write happens on COMMIT
##
## The face is not recorded here. `ui/` is a pure consumer and may hold no
## gameplay actor, and this screen has no hero until the player answers the
## arrival — so there is nothing to write to. The id is held, and
## [method act_commit] hands it to the flow, which calls `PortraitResolver.choose`
## once on the hero it just minted (ADR 0257 §1). One verb, one persistence path,
## no second field.
##
## An id this screen's picker never offered is refused rather than stored, so the
## control cannot become a way to write a face the catalogue cannot explain.
func act_choose_face(portrait_id: StringName) -> bool:
	_bind_nodes()
	# An id this screen's picker never offered is refused rather than stored, so
	# the control cannot become a way to write a face the catalogue cannot
	# explain. `take` re-renders the row that just announced the press, which is
	# what marks it Worn — and `take` does NOT emit, so this is not a re-entry.
	if _picker == null or not _picker.take(portrait_id):
		return false
	_chosen_portrait = portrait_id
	return true


func _summary() -> Dictionary:
	_bind_nodes()
	# `{}` with no actor is the contract every screen here keeps (ADR 0038), and it
	# is literally true on this one: a hero does not exist until the player answers.
	if _actor == null:
		return {}
	var branches := _branch_summaries()
	return {
		"actor": String(_actor.id),
		"is_creation": true,
		"committed": not committed_origin().is_empty(),
		"committed_origin": committed_origin(),
		"race": String(_result.get("race", "")),
		"closed_paths": _strings(_result.get("closed_paths", [])),
		"open_paths": _strings(_result.get("open_paths", [])),
		"destinies": _strings(_result.get("destinies", [])),
		"fates": _strings(_result.get("fates", [])),
		"fact": String(_result.get("fact", "")),
		"branches": branches,
		"branch_ids": _ids_of(branches),
		"open_branch_ids": _open_ids_of(branches),
		# ## What the picker publishes, and why it is NESTED rather than flattened
		# ##
		# `faces` is the picker's own `summary()`, so the screen's contract stays
		# "each row's summary nested under its key" (AGENTS.md). Flattening
		# `option_ids` to the top level would put a second copy of the list here that
		# could disagree with the panel's — which is the drift ADR 0257 §1 forbids when
		# it says one catalogue and one resolver serve every character.
		"faces": _faces_summary(),
		"chosen_portrait": String(_chosen_portrait),
		"offers_fate_picker": false,
		"granting_verbs": [],
	}


## Repaint from the snapshot the composition root handed in. The rows own every
## format; this screen renders none.
func _refresh_view() -> void:
	refresh_candidates()


## Repaint this screen's own labels. Each row repaints itself.
##
## ## The footer button is enabled off the ROWS, and that is what makes it honest
##
## `_confirm_button.disabled` used to be driven by `committed` alone, so it sat greyed out
## with nothing in the file connected to its `pressed` — a live control the player could
## focus and press that did nothing at all. It is now the commit path for the arrival
## [method focus_initial] already names as "the thing a player would act on": it commits
## THAT row through [method act_commit], which is the same verb a row's own button calls, so
## there is still one earn in this screen rather than two.
func _render() -> void:
	if _header == null:
		return
	var committed := not committed_origin().is_empty()
	_header.text = L.t(COMMITTED_TEXT if committed else HEADER_TEXT)
	_footer.text = L.t(COMMITTED_FOOTER if committed else OPEN_FOOTER)
	if _confirm_button != null:
		_confirm_button.disabled = committed or _focused_origin().is_empty()
		_confirm_button.text = L.t(CONFIRM_OFFER if committed else CONFIRM_TEXT)


## The arrival this screen's own commit button would commit: the FIRST row that may still
## be committed, in the order the catalog published them.
##
## This is the same order [method focus_initial] already picks the landing spot from, and
## it is asked of the ROWS rather than of `_candidates`, so it answers the rows' own gate
## (`CreationBranchRow.can_commit`) and cannot disagree with what the player can see.
func _focused_origin() -> StringName:
	for row in _branch_rows:
		if bool(row.call(&"can_commit")):
			return StringName(row.call(&"origin_id"))
	return &""


# --- ScreenStack hooks ------------------------------------------------------


## The landing spot is the first arrival still open to the player — the thing a
## player would act on. Recorded first, because a node outside a viewport has
## nothing to focus yet.
func focus_initial() -> void:
	_bind_nodes()
	for row in _branch_rows:
		if bool(row.call(&"can_commit")):
			_focus_target = String(row.name)
			if row.is_inside_tree():
				row.call(&"focus_initial")
			return


func on_stack_input(_event: InputEvent) -> bool:
	return false


func on_screen_hidden() -> void:
	pass


# --- Plumbing ---------------------------------------------------------------


func _bind_nodes() -> void:
	if _header != null:
		return
	_header = get_node_or_null("%CreationHeader") as Label
	_footer = get_node_or_null("%FooterLabel") as Label
	_branch_box = get_node_or_null("Layout/Scroll/Arrivals/Branches") as VBoxContainer
	_confirm_button = get_node_or_null("%ConfirmButton") as Button
	_picker = get_node_or_null("%PortraitPicker") as PortraitPicker
	_bound = _header != null and _branch_box != null
	# Guarded, because `_bind_nodes` returns early on the second call but the button itself
	# could still be re-resolved by a reparent, and an unguarded `connect` fires the handler
	# once per press times however many times it was wired (AGENTS.md).
	if _confirm_button != null and not _confirm_button.pressed.is_connected(_on_confirm_pressed):
		_confirm_button.pressed.connect(_on_confirm_pressed)
	if _picker != null and not _picker.chosen.is_connected(_on_face_chosen):
		_picker.chosen.connect(_on_face_chosen)
	if not _bound:
		return
	_branch_rows = _rows_in(_branch_box, BRANCH_SCENE, "Branch", BRANCH_ROWS)
	for row in _branch_rows:
		var signal_ref: Signal = row.get(&"committed")
		if not signal_ref.is_connected(_on_committed):
			signal_ref.connect(_on_committed)


## The rows the scene declares, in order, then enough more to reach `extra`.
##
## The count is clamped through `RowBudget` before the loop rather than inside it,
## because `extra` is an authored constant today and a data-derived one is exactly
## the shape the bound exists for.
func _rows_in(box: VBoxContainer, scene_path: String, prefix: String, extra: int) -> Array:
	var out: Array = []
	for child in box.get_children():
		var row := child as CreationBranchRow
		if row != null:
			out.append(row)
	for index in range(out.size(), RowBudget.cap(extra)):
		var grown := load(scene_path).instantiate() as Control
		grown.name = "%s%d" % [prefix, index]
		box.add_child(grown)
		out.append(grown)
	return out


func _on_committed(origin_id: StringName) -> void:
	act_commit(origin_id)


## `%ConfirmButton`'s press. Commits the arrival the screen already points the keyboard at.
##
## It routes through [method act_commit] rather than emitting anything, so pressing it and
## pressing a row's own button take the SAME path and there is one earn here rather than two.
## `_focused_origin` re-reads the rows at press time rather than caching an id, so a press
## after a re-render commits what the screen is actually showing.
func _on_confirm_pressed() -> void:
	var origin_id := _focused_origin()
	if origin_id.is_empty():
		return
	act_commit(origin_id)


# --- Filling ----------------------------------------------------------------


## One row per arrival, with any spare row in the pool cleared — a blank row would
## read as an arrival the player cannot see.
func _feed() -> void:
	var index := 0
	for row in _branch_rows:
		var view: Dictionary = {}
		if index < _candidates.size():
			view = (_candidates[index] as Dictionary).duplicate(true)
		(row as CreationBranchRow).show_branch(view)
		index += 1
	_feed_faces()


## Offer the faces for the arrival the keyboard is pointed at.
##
## ## Why the FOCUSED arrival, and not all three
##
## A hero arrives in ONE body, and the bodies differ per arrival — so offering one
## list would either show faces the hero may not wear or blend three bodies into
## one list. The focused row is the arrival this screen would commit, so its faces
## are the faces that commit would accept.
##
## ## Why an unknown race is not an error
##
## With no race the picker publishes zero options and creation carries on. That is
## the optional contract (ADR 0257 §5) implemented rather than asserted: the only
## thing a body plan contributes here is a shorter list, never a refusal.
func _feed_faces() -> void:
	if _picker == null:
		return
	var race := ""
	for row in _branch_rows:
		if bool(row.call(&"can_commit")):
			race = String((row.call(&"summary") as Dictionary).get("race", ""))
			break
	_picker.show_race(StringName(race), _chosen_portrait)


## The picker's own summary, nested under `faces`. `{}` when there is no picker,
## so a screen that failed to mount it reports its absence rather than a
## fabricated empty list that would read as "this body has no faces".
func _faces_summary() -> Dictionary:
	if _picker == null:
		return {}
	return _picker.summary()


func _on_face_chosen(portrait_id: StringName) -> void:
	act_choose_face(portrait_id)


# --- Reporting --------------------------------------------------------------


func _branch_summaries() -> Array:
	var out: Array = []
	for row in _branch_rows:
		var view: Dictionary = (row as CreationBranchRow).summary()
		if not view.is_empty():
			out.append(view)
	return out


func _ids_of(views: Array) -> Array:
	var out: Array = []
	for entry in views:
		out.append(String((entry as Dictionary).get("id", "")))
	return out


func _open_ids_of(views: Array) -> Array:
	var out: Array = []
	for entry in views:
		var view: Dictionary = entry
		if bool(view.get("can_commit", false)):
			out.append(String(view.get("id", "")))
	return out


func _strings(values: Array) -> Array:
	var out: Array = []
	for value in values:
		out.append(String(value))
	return out
