class_name ClanFixtureCatalog
extends RefCounted

## A test-local stand-in for `ClanCatalog`, holding `ClanDef` built in code. The module
## reads content through the catalog singleton, and the shipped content tree is authored
## independently of this suite, so the logic tests install their own catalog for the
## duration of a test instead of depending on which `.tres` files happen to exist.
##
## ## Reaching into the catalog's privates
##
## `install` writes `catalog._clans` and flips `catalog._loaded` directly, and
## `teardown` nulls the static `ClanCatalog.shared`. There is no public seam for
## either: the catalog is a lazily-loaded singleton over `res://data/clans/`, and a
## test that wants a *different* tree cannot get one through its published surface.
## This is the same deliberate reach the sibling `RaceFixtureCatalog` makes into
## `RaceCatalog._races`/`_loaded`/`shared`, and it is confined to this one file —
## `ClanCatalog` itself stays honest about loading the shipped tree.
##
## The fixtures use a reserved `t_` id prefix so they can never collide with a real
## authored clan, and `teardown()` restores whatever catalog the process held
## beforehand. One test (`test_clan_content.gd`) deliberately reads the SHIPPED tree,
## which is the only way to hold authored content to ADR 0064's rival-cycle rule.

const LADDER: Array[StringName] = [&"outer", &"inner", &"core", &"heir", &"head"]


## The fixture bloodline every logic fixture founds on, over an admission bar low
## enough to be open in the ordinary case. `sealed()` is the fixture that raises the
## bar, so a refusal test authors its value there rather than through a knob here.
static func open(clan_id: StringName) -> ClanDef:
	var def := _base(clan_id)
	def.founding_bloodline = &"hearthborn"
	def.min_purity = 0.3
	def.rival_clans = [&"t_other"]
	return def


## A clan whose admission bar is above the actor's concentration, for the refusal path.
static func sealed(clan_id: StringName, required: float) -> ClanDef:
	var def := _base(clan_id)
	def.founding_bloodline = &"hearthborn"
	def.min_purity = required
	return def


## A clan that additionally demands a body plan, for the race arm of admission.
static func housebound(clan_id: StringName, race_id: StringName) -> ClanDef:
	var def := _base(clan_id)
	def.required_race = race_id
	return def


## A clan that claims NO founding line at all. `_base` already publishes
## `founding_bloodline = &""`; this names the case so a caller reads why it asked for
## this rather than that one — a house with nothing to scale recognition by, which is
## the branch `ClanGate.recognition_scale` has to answer honestly.
static func line_less(clan_id: StringName) -> ClanDef:
	return _base(clan_id)


## A clan that additionally demands a realm floor, for the realm arm of admission.
static func ranked(clan_id: StringName, min_realm: int) -> ClanDef:
	var def := _base(clan_id)
	def.min_realm = min_realm
	return def


static func _base(clan_id: StringName) -> ClanDef:
	var def := ClanDef.new()
	def.id = clan_id
	def.display_name = str(clan_id)
	def.description = "A fixture clan."
	def.founding_bloodline = &""
	def.ranks = LADDER.duplicate()
	def.standing_bands = [0, 15, 40, 75, 120]
	def.patronage = {"wage": "A wage.", "quarters": "Quarters."}
	def.duty = {"muster": "Answer a muster."}
	def.rival_clans = []
	def.tags = []
	def.min_purity = 0.0
	def.required_race = &""
	def.min_realm = 0
	return def


## Replace the module's catalog singleton with one built from `clans`, for the duration
## of one test.
static func install(clans: Array[ClanDef]) -> void:
	var catalog := ClanCatalog.new()
	for def in clans:
		catalog._clans[String(def.id)] = def
	catalog._loaded = true
	ClanCatalog.shared = catalog


## Undo `install`. The real catalog is what the singleton lazily rebuilds when `shared`
## is null.
static func teardown() -> void:
	ClanCatalog.shared = null
