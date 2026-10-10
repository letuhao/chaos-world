extends TestCase

## Shared fixture for `test_institution_card.gd`. NOT a suite itself: the runner
## discovers `test_*.gd` only, so this file is never executed on its own.
##
## Split out of the suite purely for size -- gdlint's `max-file-lines` is 1000. Nothing
## was rewritten, no assertion changed and no case renamed: every constant, `_born` and
## the `setup()` / `teardown()` pair and each helper now live here, which the suite
## `extends`. A test file can only move HELPERS, which is why the moved bodies are
## exactly the ones no `test_` function names.
##
## `setup` / `teardown` MUST live here rather than in the suite: `InstitutionRegistry`
## and `InstitutionDefCatalog` are PROCESS-WIDE and the runner shares one process across
## every suite, calling `teardown` after EVERY test -- so a registry installed by one
## case and cleared by another outlives the suite and is inherited by everything after.

## The screen and card scenes, loaded once: two `load()` calls for one scene is a second
## source of truth about which scene this suite drives.
const CARD_SCENE := preload("res://src/ui/panels/institution_card.tscn")
const SCREEN_SCENE := preload("res://src/ui/screens/institution_screen.tscn")
const CARD_SCRIPT := "res://src/ui/panels/institution_card.gd"
const SCREEN_SCRIPT := "res://src/ui/screens/institution_screen.gd"
const CARD_SCENE_TEXT := "res://src/ui/panels/institution_card.tscn"
const SCREEN_SCENE_TEXT := "res://src/ui/screens/institution_screen.tscn"

const LANTERN := &"lantern_exchange"
const CIRCLE := &"torrent_field_circle"
## The Exchange's single SEAT (`capacity = 1`) and its UNCAPPED ordinary office
## (`capacity = 0`). Named because the two ends of the cap are what the vacancy assertions
## are actually about, and reaching them by ARRAY INDEX would test whichever office the
## `.tres` happened to list first rather than the one the assertion names.
const SEAT := "first_ledger"
const ROOM := "clerk"
## A guild that authors offices to assert on: the Circle deliberately authors NONE, which
## is the case that makes "no office at all" reachable.
const GUILD := LANTERN

## ## The verbs a screen is not allowed to use, and why `%d` is NOT among them
##
## The rule is about formatting a VALUE the player reads. A bare `%d` is not that: a
## screen names its pooled nodes `"Card%d"`, which is a node identity and never printed.
## Asserting `%d` absent would fail a correct screen and teach the next author to hide
## the rule in a comment. So the probe names the shapes that RENDER a number -- a `%`
## format with a width/precision, a rounding call, and the string-number converters -- and
## the behavioural half of the same rule is the type assertion above: `founding_cost`
## arrives as an `int`, which no amount of formatting could survive.
const SCREEN_FORMAT_VERBS := [
	"%.0f",
	"%.1f",
	"%.2f",
	"%d /",
	"%s / %d",
	"roundf(",
	"roundi(",
	"str(",
	"String.num",
	"itos(",
]

## Every node this suite instantiated, freed from [method teardown]. A row added here and
## not freed is a leak, not a fixture: the runner drives every suite from one process, so a
## leaked subtree survives into the next suite. **Only `Node`s are freed** -- an `Actor` is
## a `RefCounted` and `free()` on one is a SCRIPT ERROR that aborts the rest of teardown.
var _born: Array = []


func setup() -> void:
	_born = []
	# The boot runs ONCE per test rather than per assertion: the registry is process
	# state and the runner drives every suite in one process, so leaving it registered
	# here is exactly what `teardown` clears. A suite that skipped the boot reported an
	# EMPTY kind list next to three authored organizations, which is the honest answer to
	# "what did nobody register" and an entirely misleading one for a screen.
	InstitutionRegistry.shared = null
	InstitutionDefCatalog.clear()
	var report := InstitutionBoot.install()
	assert_eq(bool(report["ok"]), true, "the shipped organizations register cleanly")


func teardown() -> void:
	# Freed from ONE place, called after every test including one that returned early.
	# A `Node` is detached before `free()`: the headless runner drives from
	# `SceneTree._initialize()` and a deferred free never runs under `tools test`.
	for node in _born:
		var victim := node as Node
		if victim == null:
			continue
		if victim.get_parent() != null:
			victim.get_parent().remove_child(victim)
		victim.free()
	_born = []
	InstitutionDefCatalog.clear()
	InstitutionRegistry.shared = null


# --- Fixtures -----------------------------------------------------------------


func _card() -> InstitutionCard:
	return _born_card(CARD_SCENE.instantiate())


## A card built from the SCRIPT alone -- no scene, no tree, no widgets at all. This is the
## shape a headless suite can drive, and the reason the standard forbids `@onready`: an
## `@onready` binding would never have run here.
func _bare_card() -> InstitutionCard:
	return _born_card(InstitutionCard.new())


func _born_card(node: InstitutionCard) -> InstitutionCard:
	_born.append(node)
	return node


func _screen() -> InstitutionScreen:
	var screen := SCREEN_SCENE.instantiate() as InstitutionScreen
	_born.append(screen)
	return screen


func _actor() -> Actor:
	return Actor.new(&"hero", {Stat.PHYSIQUE: 10.0, Stat.WILL: 5.0})


## A card view for one authored organization, built from the SHIPPED `.tres` so the
## fixture cannot drift from the content. `claim` is `{}` -- the FIRST state -- unless a
## caller passes one.
func _organization(
	def_id: StringName, claim: Dictionary = {}, vacant: Variant = null
) -> Dictionary:
	var def := InstitutionDefCatalog.instance().definition(def_id)
	assert_ne(def, null, "%s is authored" % String(def_id))
	if def == null:
		return {}
	var offices: Array = []
	for office in def.positions:
		(
			offices
			. append(
				{
					"id": String(office.id),
					"display_name": String(office.display_name),
					"capacity": office.room(),
					"held": 1,
					"holders": "hero",
					"duty_per_period": int(office.duty_per_period),
					"patronage_per_period": int(office.patronage_per_period),
					"duties": ["weigh_the_ledger"],
					"authorities": ["expel"],
					"vacant": false,
				}
			)
		)
	var view := {
		"ok": true,
		"id": String(def.id),
		"kind": String(def.kind),
		"display_name": String(def.display_name),
		"founding_cost": int(def.founding_cost),
		"standing_cap": int(def.standing_cap),
		"capabilities": ["has_offices"],
		"territories": [],
		"positions": offices,
		"claim": claim,
	}
	if vacant != null:
		view["vacant"] = vacant
	return view


## Show `def_id` on `card` with `position_id` authored but nobody holding it.
##
## By ID and never by index: the first office a `.tres` lists is content order, and an
## assertion written against an index tests whichever office that happens to be rather
## than the one it names. Returns nothing -- the card is the assertion's subject.
func _vacate(card: InstitutionCard, def_id: StringName, position_id: String) -> void:
	var view := _organization(def_id)
	var offices: Array = view["positions"]
	var found := 0
	for entry in offices:
		var office: Dictionary = entry
		if String(office.get("id", "")) != position_id:
			continue
		found += 1
		office["vacant"] = true
		office["held"] = 0
		office["holders"] = ""
	assert_eq(found, 1, "%s authors exactly one office called %s" % [String(def_id), position_id])
	card.show_organization(view)


## A real claim, so `normalized()` is `core`'s own answer and not a number this suite
## wrote twice.
func _claim(position: String, standing: int, cap: int) -> InstitutionClaim:
	var claim := InstitutionClaim.new()
	claim.position = StringName(position)
	claim.standing = standing
	claim.standing_cap = cap
	claim.obligation = {"duty_lantern_exchange": 3}
	return claim


func _claim_view(claim: InstitutionClaim) -> Dictionary:
	return {
		"exists": true,
		"position": String(claim.position),
		"standing": claim.standing,
		"standing_cap": claim.standing_cap,
		# The RATIO, as `InstitutionClaim.normalized()` computes it. A caller that
		# published `standing / standing_cap` here would have written a second copy of a
		# formula that already exists, which is ADR 0066's shape.
		"normalized": claim.normalized(),
		"obligations": {"duty_lantern_exchange": 3},
	}


## The same fixture with every roster field cleared, which is what a screen publishes when
## its actor-scoped reader is unbound.
func _show_unpublished(card: InstitutionCard) -> void:
	var view := _organization(GUILD)
	for entry in view["positions"] as Array:
		var office: Dictionary = entry
		office["holders"] = ""
		office["held"] = 0
		office.erase("vacant")
	card.show_organization(view)
