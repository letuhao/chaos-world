class_name DeclarationVocabulary
extends RefCounted

## The vocabularies a mod's declaration block is checked against (ADR 0275).
##
## ## Why this is its OWN file and not five methods on RegistrationContext
##
## Two reasons, and the second is the one that matters. The first is size:
## `RegistrationContext` is the locked SEAM, and a seam that carries its own
## vocabulary reader, its own block parser and its own row checker is a file with
## three reasons to change — `rules.LINE_BUDGET` is an SRP proxy and it fires.
## The second is that a VOCABULARY has a different lifetime from a REGISTRATION:
## there is exactly one stat vocabulary for the whole process, read once, whereas
## a ctx's rows are per-mod and replaced on every boot.
##
## ## Every vocabulary is READ out of the class that declares it, never restated
##
## `contracts/stat.gd` declares the stat ids, `Stat.Op` declares the ops and
## `ActorPools.CORE_POOL_STATS` declares the pools core owns. A second literal
## here would be ADR 0066 — two declarations of one fact with nothing keeping them
## in agreement — and a hand-written list of ~60 stat ids is exactly how BL-0675
## happened (a module-owned rate had nowhere to register).
##
## ## UNKNOWN is not EMPTY, and the difference is the whole safety story
##
## [method stat_ids] returning `{}` means the reader failed, not that no stat is
## legal. `tools/data.py:_read_fate_tags` draws the same distinction and says why:
## a reader that answers `()` for a moved file turns a correct tree red the first
## time a class is renamed, while a reader that answers `()` for a PRESENT file is
## a gate that reports ok on a tree it never checked. So the declaration seam
## treats empty as UNKNOWN and refuses, which is the loud direction.
##
## ## What this does NOT own
##
## A mod's OWN pools. `resources[]` in the block is the mod's declaration, and a
## stat row's `resource` resolves against that union the core pools. Nothing here
## decides whether a pool is legal — the seam does, because only the seam knows
## which mod is asking.

## Memoised per PROCESS, not per call: the vocabulary is a property of the classes,
## so a boot with forty mods reads `stat.gd`'s constants once. `staticvars` rather
## than a per-instance field because there is no instance — this class is a namespace
## of static readers, and a cache per ctx would mean one read per mod.
static var _stat_id_cache: Dictionary = {}


## `contracts/stat.gd`'s constants, read through the ONE declaration of them.
##
## Two forms were tried and the second is the one that compiles:
##
## - `Stat.get_script_constant_map()` — GDScript rejects a non-static method called on
##   a class directly ("Cannot call non-static function … on the class 'Stat'
##   directly. Make an instance instead"), and the analyzer rejects it at COMPILE time
##   whether or not the class happens to be a resource.
## - `preload("res://src/contracts/stat.gd").get_script_constant_map()` — the analyzer
##   resolves a `class_name`d `preload` back to the class, so this fails identically
##   while looking like it should work.
## - **an instance, then its script** — `Stat.new().get_script().get_script_constant_map()`.
##   Both calls are instance calls on values, which is what the analyzer requires.
##
## `Stat` extends `RefCounted` and declares no state, so the probe allocates nothing and
## is released with the expression. It runs ONCE: [method stat_ids] memoises the result,
## because a boot with forty mods must not read `stat.gd` forty times.
static func _stat_constants() -> Dictionary:
	var probe: RefCounted = Stat.new()
	var script: Script = probe.get_script()
	if script == null:
		return {}
	return script.get_script_constant_map()


## Every stat id `contracts/stat.gd` declares, as `{id: true}`.
##
## ARRAY constants are expanded as well as scalars, and that arm is load-bearing:
## `RATE_STATS` and `MIND_CONTROL_RATES` are exactly where the ids a content gate most
## needs live (`tools/data.py:_resolve_rate_stats` reads the same array), so a
## scalar-only reader would silently drop twelve mind-control ids and then refuse a mod
## that legitimately declared one.
static func stat_ids() -> Dictionary:
	if _stat_id_cache.is_empty():
		_stat_id_cache = _read_stat_ids()
	return _stat_id_cache


## The ops a `stats[]` row may carry: `Stat.Op`'s own keys, lowercased for JSON
## (`"flat"`, `"percent"`, `"mult"`). Read rather than restated — see the class
## docstring.
static func stat_ops() -> Dictionary:
	var out: Dictionary = {}
	for key in Stat.Op.keys():
		out[String(key).to_lower()] = true
	return out


## The pools core owns, read out of `ActorPools.CORE_POOL_STATS`. A mod may
## REFERENCE one of these without re-declaring a pool core already owns and sizes
## from a derived stat; declaring one it does not bring would be a second owner.
static func core_resource_ids() -> Dictionary:
	var out: Dictionary = {}
	for pool_id in ActorPools.CORE_POOL_STATS:
		out[String(pool_id)] = true
	return out


## Whether `candidate` is a stat id this repo declares. Separate from
## [method stat_ids] so a CALLER can ask the question without holding the
## dictionary — and so the question has one spelling.
static func is_stat_id(candidate: String) -> bool:
	return stat_ids().has(candidate)


## Whether `candidate` is an op a `stats[]` row may carry. See
## [method is_stat_id] for why this is not just `stat_ops().has(...)` inline.
static func is_stat_op(candidate: String) -> bool:
	return stat_ops().has(candidate.to_lower())


## Whether `candidate` is a pool CORE owns. A mod's own pools are not answered
## here — see the class docstring.
static func is_core_resource(candidate: String) -> bool:
	return core_resource_ids().has(candidate)


static func _read_stat_ids() -> Dictionary:
	var out: Dictionary = {}
	var constants := _stat_constants()
	for key in constants:
		var value: Variant = constants[key]
		if value is StringName or value is String:
			if _is_stat_id(String(value)):
				out[String(value)] = true
		elif value is Array:
			for entry in value as Array:
				if (entry is StringName or entry is String) and _is_stat_id(String(entry)):
					out[String(entry)] = true
	return out


## A stat id is lowercase-and-underscore, the shape every `Stat` constant uses.
## FILTERED rather than assumed: an unrelated constant (an int, a display string)
## must not widen the vocabulary into accepting ids that are not stat ids, or the
## seam starts rubber-stamping typos by accident.
static func _is_stat_id(value: String) -> bool:
	if value.is_empty() or not (value[0] >= "a" and value[0] <= "z"):
		return false
	for index in range(1, value.length()):
		var character := value[index]
		var is_lower := character >= "a" and character <= "z"
		var is_digit := character >= "0" and character <= "9"
		if not is_lower and not is_digit and character != "_":
			return false
	return true
