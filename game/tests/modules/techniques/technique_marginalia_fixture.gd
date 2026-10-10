class_name TechniqueMarginaliaFixture
extends RefCounted

## The fixtures `test_technique_marginalia.gd` reads: a hero with the budget the study
## cases need, a legendary passive manual with one stat and one capacity option, a
## seeded generator, and the corpus readers the coverage cases walk.
##
## Extracted from the suite when it passed gdlint's `max-file-lines` ceiling. Every verb
## is static and class-independent — a fixture carries no assertions, so nothing here can
## pass or fail — and the ids it mints come off its own serial so a reused id cannot
## silently replace a registered def (`TechniqueCatalog` is process-wide, last-wins).
##
## The five constants live here with the fixtures that read them; the suite names them
## through this class, so a second copy cannot drift.

const MORTAL := &"qi_refining"

## Two real technique-legal options (ADR 0054's list), one stat and one capacity.
const STAT_OPTION := &"cult_qi_control"

const CAPACITY_OPTION := &"cult_dantian_capacity"

const STAT_VALUE := 6.0

const CAPACITY_VALUE := 5.0

## `TechniqueCatalog` is process-wide and registration is last-wins, so a reused
## id would have its second def silently replace the first.
static var _serial: int = 0


static func fresh_id(label: String) -> StringName:
	_serial += 1
	return StringName("marginalia_suite_%s_%d" % [label, _serial])


## A hero with a budget big enough for every study below — the price itself is
## asserted in `test_technique_study_cost.gd`, so this is a fixture and not a
## balance claim.
static func hero() -> Actor:
	var actor := Actor.new(&"reader", {Stat.PHYSIQUE: 10.0, Stat.SPIRIT: 10.0})
	actor.add_resource(ResourcePool.new(&"qi", 500.0))
	actor.add_resource(ResourcePool.new(&"stamina", 100.0))
	actor.set_path(PathState.new(PathState.QI, MORTAL))
	actor.path(PathState.QI).progress = 100000.0
	TechniquesApi.attach(actor)
	return actor


## A passive manual inscribing one stat option and one capacity option.
##
## `rarity` is LEGENDARY deliberately: the band's WIDTH is rarity
## (`ItemRarity.magnitude_budget`, adopted by ADR 0204), so a def left at the
## default COMMON carries `budget = 0.0` and therefore NO variance at all. Every
## assertion in this file about two copies differing would then be vacuous, and
## it would pass for the wrong reason. The `test_a_common_copy_carries_no_variance`
## case is the one that pins the narrow end, explicitly.
static func manual() -> TechniqueDef:
	var def := TechniqueDef.new()
	def.id = fresh_id("manual")
	def.display_name = "Marrow Circulation Primer"
	def.grade = ItemGrade.MORTAL
	def.rarity = ItemRarity.LEGENDARY
	def.active = false
	def.path = PathState.QI
	def.magnitude = 1.6
	def.passive_options = [
		{"option_id": STAT_OPTION, "value": STAT_VALUE},
		{"option_id": CAPACITY_OPTION, "value": CAPACITY_VALUE},
	]
	TechniqueCatalog.instance().register(def)
	return def


## A generator seeded to `seed_value`, which is the whole determinism contract:
## the repo's other rollers take a seeded `RandomNumberGenerator` (see
## `ItemGenerator.generate` and `BodyAttemptRoll.replay`).
static func rng(seed_value: int) -> RandomNumberGenerator:
	var generator := RandomNumberGenerator.new()
	generator.seed = seed_value
	return generator


## Learn `def` with a chosen seed, so the copy under test is the one the seed
## picked rather than the engine's entropy.
static func study(actor: Actor, def: TechniqueDef, seed_value: int) -> Dictionary:
	return TechniquesApi.learn(actor, def, 0, rng(seed_value))


## The stat contribution on the ACTOR, which is what a player experiences. Read
## off the stat rather than off the entry, so this asserts the modifier pipeline
## agrees with the stored annotations rather than the projection against itself.
static func qi_control(actor: Actor) -> float:
	return actor.stats.derived(&"qi_control")


# --- Two copies of one manual differ, and each says what it holds --------------


## The FIRST `randf()` the drawer would take for `seed_value`, drawn from a
## generator seeded exactly as `_rng` seeds it. Reproduced here rather than
## imported from `draw` so this case tests the CONSTANTS and the CLAMP independently
## — if it called `draw`, deleting the clamp inside `draw` could not be observed by
## this case at all, which is precisely what the mutation showed.
static func randf_from(seed_value: int) -> float:
	var generator := RandomNumberGenerator.new()
	generator.seed = seed_value
	return generator.randf()


## Every authored `{option_id, value}` pair the shipped technique corpus carries
## for `option_id`, read from the content tree rather than restated, so a retune
## of any `.tres` widens the coverage of this suite instead of silently narrowing
## it.
static func shipped_option_values(option_id: StringName) -> Array:
	var out: Array = []
	var dir := DirAccess.open("res://data/techniques")
	if dir == null:
		return [STAT_VALUE]
	dir.list_dir_begin()
	var entry := dir.get_next()
	# Snapshot the row count is not the bound here — `get_next` returns "" at the
	# end of the directory, which is the terminator, and `test_no_unbounded_wait`
	# accepts a `while` that breaks on it.
	while not entry.is_empty():
		if entry.ends_with(".tres"):
			var text := FileAccess.get_file_as_string("res://data/techniques/%s" % entry)
			for authored in parse_passive_options(text):
				if String(authored.get("option_id", "")) == String(option_id):
					out.append(float(authored.get("value", 0.0)))
		entry = dir.get_next()
	dir.list_dir_end()
	if out.is_empty():
		return [STAT_VALUE]
	return out


## The `passive_options` block of a `.tres` read as rows. Read as TEXT rather than
## loading each resource, so the suite walks the corpus without depending on the
## catalog's own lazy loader — and so a `.tres` that would fail to load is a
## finding rather than a crash here.
static func parse_passive_options(text: String) -> Array:
	var out: Array = []
	var open := text.find("passive_options = Array[Dictionary]([")
	if open < 0:
		return out
	var close := text.find("])", open)
	if close < 0:
		return out
	var body := text.substr(open, close - open)
	for line in body.split("\n"):
		if not line.contains("option_id"):
			continue
		var id_start := line.find('&"') + 2
		var id_end := line.find('"', id_start)
		var value_start := line.find('"value":') + 8
		var value_end := line.find(",", value_start)
		if id_start < 2 or id_end < 0 or value_start < 8 or value_end < 0:
			continue
		(
			out
			. append(
				{
					"option_id": line.substr(id_start, id_end - id_start),
					"value": float(line.substr(value_start, value_end - value_start)),
				}
			)
		)
	return out


# --- The one that must not be decorative: the roll is PERSISTENT ---------------


## A manual as a REAL `category = &"technique"` ITEM, so the case below can go
## through `ItemsApi.use_item` — the same call `item_workbench.gd:166` and
## `QuickUseApi.use_slot` make — rather than through the facade this suite would
## otherwise be testing in isolation.
static func manual_item(technique_id: StringName) -> ItemDef:
	var item := ItemDef.new()
	item.id = technique_id
	item.display_name = "A Manual"
	item.category = ItemCategory.TECHNIQUE
	item.stackable = false
	item.rarity = &"magic"
	item.realm = MORTAL
	item.roll_spec = {"count": 1, "contexts": ["base"]}
	item.fixed_modifiers = [{"option_id": &"base_comprehension", "value": 4.0}]
	return item
