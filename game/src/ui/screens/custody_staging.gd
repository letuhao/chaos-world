class_name CustodyStaging
extends RefCounted

## The custody page's staged beats: what may be taken, what a capture would commit
## and what a transfer would move.
##
## Extracted from `CustodyScreen`, which owns it and repaints it: every name the screen
## published before the extraction is still a one-line door there, so a route, a test
## and a driver all reach the same verbs and nothing outside had to change. What lives
## here is the STATE (the capturable list and the two staged beats) and the verbs that
## read and write it; the screen keeps the binding and the repaint.
##
## ## The subject list is a READ of one seam, never a verdict (ADR 0247)
##
## [method bind] takes the `Callable() -> Array` the composition root installs at the
## route mount — the shape `QuestScreen.bind_quests` uses, and the reason `ui/` never
## names the module that owns the cast (ADR 0143). It is a read model, not a verb: it
## writes nothing and decides nothing. Everything it returns is AUTHORED — a subject
## def id, the closed subject kind, a term id and a count of periods — and it cannot
## say whether one particular actor may be taken. ADR 0104's condition stays with the
## caller, and `combat` keeps owning a capture threshold.
##
## ## Staging is the caller's INPUT, never state
##
## An empty beat and a cleared beat are the same shape: a deliberate `""`/`{}` disarms
## the control rather than leaving a stale subject or holder for the next press to
## commit. [method wired] separates "nothing is capturable here" from "nothing told
## this page what is capturable", which are two different sentences and both reachable.

## The kind an empty subject kind defaults to. The module's own subject-kind set ships
## `npc`, and `player` is a closed value reserved for a def that does not exist yet.
## Spelled here rather than read off the module, which `ui/` may not name.
const DEFAULT_SUBJECT_KIND := "npc"

## The staged capture beat. Four fields and no widgets, because `ui/` builds no form
## controls and a headless driver stages a beat the same way a future combat outcome
## would.
var _capture_subject: String = ""
var _capture_kind: String = ""
var _capture_term: String = ""
var _capture_periods: int = 0

## The staged transfer. `to_holder` is an `OwnerRef` whose kind only a caller can name
## — the vocabulary is open (ADR 0933) — and the two parties are the wallets the
## caller agreed, forwarded verbatim and never derived here.
var _transfer_target: Dictionary = {}
var _transfer_coins: int = 0
var _transfer_payer: Actor = null
var _transfer_receiver: Actor = null

## The seam that answers "what is capturable here". `Callable() -> Array` of
## `{subject_id, subject_kind, term_id, periods}` primitives, installed by the
## composition root at the route mount.
var _capture_options: Callable = Callable()

## What that seam last answered, cached so a read costs one call per refresh however
## many times it is asked. Each entry is the four primitives plus the flag that says
## whether this hero ALREADY holds a claim on that subject, so the arming can be
## withheld from a subject this hero has taken rather than armed onto a button that
## would refuse `already_captive` for a reason the player did not cause.
var _options: Array = []


## Install the subject-list seam. A deliberate `Callable()` disarms the control:
## [method refresh_options] empties the cache rather than leaving a stale subject
## staged for a button nobody can see the cause of — the same rule `stage_capture("")`
## follows on purpose.
func bind(options: Callable, held: Array) -> void:
	_capture_options = options
	refresh_options(held)


## Whether the subject-listing seam is bound. Published by the screen's `summary()` so a
## probe can tell "this cast authors nothing capturable" from "nothing told this page
## what is capturable", which are different sentences and both reachable.
func wired() -> bool:
	return _capture_options.is_valid()


## Ask the seam what may be taken, and cache it with the one ledger fact that changes
## what a control should offer: whether THIS hero already holds a claim on that subject.
##
## Read once per refresh, and only when there is something to ask: an unbound seam is
## not called — `Callable.is_valid()` on an empty callable would throw at the call — and
## the cache is EMPTIED rather than left stale, so unbinding the seam withdraws the
## arming instead of leaving a subject staged for a button nobody can see the cause of.
##
## `held` is the subject ids the ledger says this hero holds, computed by the owner
## rather than re-read here, so the cache describes the same world the rows on screen
## describe.
func refresh_options(held: Array) -> void:
	_options.clear()
	if not _capture_options.is_valid():
		return
	var answered: Variant = _capture_options.call()
	if not answered is Array:
		return
	for entry in answered as Array:
		if not entry is Dictionary:
			continue
		var row := (entry as Dictionary).duplicate(true)
		if String(row.get("subject_id", "")) == "":
			continue
		row["held"] = held.has(String(row.get("subject_id", "")))
		row["takeable"] = not bool(row["held"])
		_options.append(row)


## The subjects this page is being told may be taken, as ids in the order the seam
## published them. A read of the CACHE rather than of the seam, so a caller walking the
## list costs nothing and cannot disagree with the action bar's live state.
func available_subject_ids() -> Array:
	var out: Array = []
	for entry in _options:
		out.append(String((entry as Dictionary).get("subject_id", "")))
	return out


## How many subjects the seam published, for the count the summary reports.
func available_count() -> int:
	return _options.size()


## The subject list as summary rows, each row's own keys plus the two flags. Four
## primitives and two booleans per row, and no name: the subject is named by the def id
## the seam published, which is the same rule the claim row follows for a claim's
## subject (ADR 0104).
func available_summaries() -> Array:
	var out: Array = []
	for entry in _options:
		out.append((entry as Dictionary).duplicate(true))
	return out


## Stage the fields `CustodyScreen.act_capture` will commit: `subject_id` is a subject
## DEF id (never an `Actor`), `term_id` an authored term, `periods` a count.
##
## Nothing here decides that the capture MAY happen — ADR 0104 leaves that condition in
## the caller — and nothing here is stored: a refresh that found no staged subject
## reports `no_subject` rather than inventing one, which is what keeps this from being a
## grab button with no cause. Assigned exactly as given, so staging one subject and
## staging none are the same shape and a deliberate empty string CLEARS the staging
## rather than leaving a stale subject for the next press to commit.
func stage_capture(subject_id: String, subject_kind: String, term_id: String, periods: int) -> void:
	_capture_subject = subject_id
	_capture_kind = subject_kind if subject_kind != "" else DEFAULT_SUBJECT_KIND
	_capture_term = term_id
	_capture_periods = periods


## The staged capture beat as the summary publishes it: four primitives, so a test
## asserts what a press WOULD commit without reading it back off a widget.
func staged_capture() -> Dictionary:
	return {
		"subject_id": _capture_subject,
		"subject_kind": _capture_kind,
		"term_id": _capture_term,
		"periods": _capture_periods,
	}


## Stage the transfer `CustodyScreen.act_transfer` will commit. `to_holder` is an
## `OwnerRef` — `{kind, id}` over the open kind vocabulary (ADR 0933). `coins` is the
## AGREED settlement and both parties are the wallets it runs between; `coins == 0` is a
## legal hand-off that skips the exchange entirely (ADR 0104), and the module refuses
## `no_settlement_party` itself when coins are named and a party is not.
##
## Assigned exactly as given: staging a transfer and clearing it are the same shape, so
## a deliberate `{}` disarms the button rather than leaving the last target standing for
## the next press.
func stage_transfer(
	to_holder: Dictionary, coins: int, coin_payer: Actor, coin_receiver: Actor
) -> void:
	_transfer_target = to_holder.duplicate(true)
	_transfer_coins = coins
	_transfer_payer = coin_payer
	_transfer_receiver = coin_receiver


## The staged transfer, as the summary publishes it. The holder is nested rather than
## flattened because it is a ref, and a ref with its kind dropped is not a ref.
func staged_transfer() -> Dictionary:
	return {
		"staged": not _transfer_target.is_empty(),
		"to_kind": String(_transfer_target.get("kind", "")),
		"to_id": String(_transfer_target.get("id", "")),
		"coins": _transfer_coins,
		"payer": String(_transfer_payer.id) if _transfer_payer != null else "",
		"receiver": String(_transfer_receiver.id) if _transfer_receiver != null else "",
	}


## The staged transfer's holder ref as the VERB needs it, or `{}`. [method
## staged_transfer] is primitives-only for the summary; a verb that hands the facade an
## `OwnerRef` needs the ref itself, kind and id together.
func transfer_target() -> Dictionary:
	return _transfer_target


## The wallet the staged settlement pays from, or null.
func transfer_payer() -> Actor:
	return _transfer_payer


## The wallet the staged settlement pays to, or null.
func transfer_receiver() -> Actor:
	return _transfer_receiver


## Clear the staged capture beat, so the next press refuses `no_subject` rather than
## recommitting the last one.
func clear_capture() -> void:
	stage_capture("", DEFAULT_SUBJECT_KIND, "", 0)


## Clear the staged transfer, so the transfer button goes dead rather than naming the
## last holder the player agreed to.
func clear_transfer() -> void:
	stage_transfer({}, 0, null, null)


## Whether the capture control is live right now — a staged subject, a term and at least
## one period. One conjunction, named, so the screen's `Accept` and its action table
## cannot disagree about what a press means. It does NOT consult the seam: the seam
## populated the staging, and re-asking it here would make a button's live state depend
## on a call that may have been unbound since.
func armed() -> bool:
	return _capture_subject != "" and _capture_term != "" and _capture_periods > 0


## ## ## Arm the capture control on a subject this page was TOLD about (ADR 0247)
##
## Returns false for an id the seam does not offer, exactly as the screen's
## `select_claim` returns false for a claim it is not showing — so a caller can never
## "select" a subject the page has no cause to take, and a page can never be pointed at
## an id that nothing authored. This is the whole point: **the player types nothing**,
## and neither does the caller.
##
## Forwarding the row's OWN four primitives is what keeps the seam honest. The page does
## not default a term and does not compute periods: both are authored on the cast, and a
## row the seam published with no term arms nothing rather than arming a grab.
func select_capture_subject(subject_id: String) -> bool:
	var row := _available_subject(subject_id)
	if row.is_empty():
		return false
	stage_capture(
		String(row.get("subject_id", "")),
		String(row.get("subject_kind", DEFAULT_SUBJECT_KIND)),
		String(row.get("term_id", "")),
		int(row.get("periods", 0))
	)
	return true


## The capturable row for `subject_id`, or `{}` when the seam does not offer it. This is
## how the page's own pick becomes a capture beat: the row IS the four primitives
## [method stage_capture] forwards, so arming the control needs no id typed anywhere.
func _available_subject(subject_id: String) -> Dictionary:
	for entry in _options:
		var row := entry as Dictionary
		if String(row.get("subject_id", "")) == subject_id:
			return row.duplicate(true)
	return {}


## The subjects this page may be pointed at that it is NOT already holding — the list a
## walk should offer, as ids. A subject already taken is excluded rather than
## offered-and-refused, because `already_captive` is a fact about the ledger and not a
## reason the player caused.
func takeable_subject_ids() -> Array:
	var out: Array = []
	for entry in _options:
		if bool((entry as Dictionary).get("takeable", false)):
			out.append(String((entry as Dictionary).get("subject_id", "")))
	return out
