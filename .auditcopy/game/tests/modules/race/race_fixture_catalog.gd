class_name RaceFixtureCatalog
extends RefCounted

## A test-local stand-in for `RaceCatalog`, holding `RaceDef` built in code. The module
## reads content through the catalog singleton, and the shipped content tree is authored
## independently of this suite, so the logic tests install their own catalog for the
## duration of a test instead of depending on which `.tres` files happen to exist.
##
## The fixtures use a reserved `t_` id prefix so they can never collide with a real
## authored race, and `teardown()` restores whatever catalog the process held beforehand.
## One test (`test_race_content.gd`) deliberately reads the SHIPPED tree, which is the
## only way to hold authored content to ADR 0062's partition rule.


## A race that closes one path and nothing else: the ordinary body plan.
static func closed(race_id: StringName, closed_path: StringName, dominance: float) -> RaceDef:
	var def := _base(race_id)
	def.closed_paths = [closed_path]
	def.dominance = dominance
	return def


## A race with a hard realm ceiling and a base-attribute grant, so the projection has
## something a `StatModifier` cannot express.
##
## `dominance` is an explicit parameter, not a default. The resolution suite needs its
## capped race to out-dominate the tide caller's 0.6, while the attach suite asserts the
## neutral `_base` value is what a provider reads back — a default here would silently
## satisfy one and silently break the other.
static func capped(
	race_id: StringName,
	closed_path: StringName,
	ceiling: int,
	attribute: StringName,
	dominance: float = 0.45
) -> RaceDef:
	var def := _base(race_id)
	def.closed_paths = [closed_path]
	def.realm_ceiling = ceiling
	def.base_attributes = {attribute: 4.0}
	def.dominance = dominance
	return def


## A race whose threshold no roll can clear, used to drive a conception to the baseline.
##
## The ceiling is `1.0 * dominance`, so a threshold above `dominance` is unreachable by
## ANY roll in any seat. An earlier draft used 0.9/0.5 and relied on the two-way split
## capping the share at `0.5 * 0.9 = 0.45` — which only held while the roll was tied to
## the parent's seat. Resolution is now order-independent, so the first contesting
## parent takes the whole roll and a share of `1.0 * 0.9` clears 0.5. The bar has to sit
## above the dominance to mean what this fixture claims.
static func mute(race_id: StringName, closed_a: StringName, closed_b: StringName) -> RaceDef:
	var def := _base(race_id)
	def.dominance = 0.9
	def.manifestation_threshold = 0.95
	def.closed_paths = [closed_a, closed_b]
	return def


static func _base(race_id: StringName) -> RaceDef:
	var def := RaceDef.new()
	def.id = race_id
	# `str()`, not `String()`: this Godot build has no callable `String` constructor for a
	# StringName, so `String(race_id)` throws the moment a fixture is built. The throw
	# happened inside fixture construction, which aborted whichever suite called it
	# mid-function — and the runner reports that as "script error(s) aborted a test", NOT
	# as a failure, so the suite still printed a pass count. Silent, and worth a comment.
	def.display_name = str(race_id)
	def.description = "A fixture body plan."
	def.dominance = 0.45
	def.manifestation_threshold = 0.1
	def.gestation_days = 30.0
	def.base_fertility = 0.5
	def.base_potency = 0.5
	def.offspring_variance = 0.1
	def.closed_paths = []
	def.realm_ceiling = 0
	def.lifespan = 36500.0
	def.tags = []
	return def


## Replace the module's catalog singleton with one built from `races`, for the duration
## of one test. `baseline` is tagged as the catalog's fallback race.
static func install(races: Array[RaceDef], baseline: StringName) -> void:
	var catalog := RaceCatalog.new()
	for def in races:
		catalog._races[String(def.id)] = def
	var tagged := catalog._races[String(baseline)] as RaceDef
	if tagged != null:
		tagged.tags = [RaceDef.BASELINE_TAG]
	catalog._loaded = true
	RaceCatalog.shared = catalog


## Undo `install`. The real catalog is what the singleton lazily rebuilds when `shared`
## is null.
static func teardown() -> void:
	RaceCatalog.shared = null
