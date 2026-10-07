class_name SaveSlot
extends RefCounted

## The save envelope: the shape on disk, and nothing else (ADR 0128).
##
## ## Why an envelope and not a bare actor payload
##
## The soul and the world ledgers OUTLIVE the actor carrying them (ADR 0127), so an envelope is
## not decoration — it is the only shape in which a soul can be written beside a body that is
## about to be replaced. `actor` holds `Actor.to_dict()` whole and untouched, so cultivation
## progress, the dantian, the sea and every module ledger ride along with it and DEF-0059 dies
## here rather than needing a second item path.
##
## ## Two version numbers, deliberately
##
## `envelope_version` governs this file and `actor.version` governs the actor payload, and
## they are INDEPENDENT. A new world key must never bump `SCHEMA_VERSION`, which is pinned at
## exactly 4 and asserted there — and a save migration must never rewrite an actor payload,
## because a migration is a guess about a file this module did not author.

## The envelope's own version. Starts at 1; `SaveMigrate` owns every later step.
const ENVELOPE_VERSION := 1
## The marker a reader checks before trusting a parsed file. A JSON object without it is not a
## save, whatever else it happens to contain.
const FORMAT := "chaos-world.save"

## The world ledger keys carried beside the actor. `soul` is one of them for ADR 0127's reason:
## it is a world fact by the ADR 0101 test — per-actor it would be incorrect the moment a second
## soul existed. `polity` is one for DEF-0119's reason, which is the same test with two subjects:
## an obligation between two institutions is true of no actor at all, so per-actor it would be a
## copy each actor could contradict.
##
## `world_time` is the SEVENTH for ADR 0259's reason, which is the same test with no
## subject at all: a period count is true of the WORLD, not of whoever is carrying it, so
## per-actor it would be a copy every body could contradict — and a player who quit and
## returned would resume at period zero holding a full ledger. Nothing else about this file
## changes: `build`, `SaveApi.publish_world` and `SaveApi._snapshot_world` all iterate this
## one array, and `envelope_version` deliberately does NOT move for a new world key.
const WORLD_KEYS: Array[String] = [
	"holdings",
	"market",
	"custody",
	"soul",
	"anchor",
	"polity",
	"world_time",
	"worldmap",
]


## The empty envelope, before anything is written into it.
static func empty() -> Dictionary:
	return {
		"envelope_version": ENVELOPE_VERSION,
		"format": FORMAT,
		"generation": 0,
		"difficulty": "",
		"actor": {},
		"world": {},
	}


## Whether `parsed` is a save this build can read. Three checks and no more: it is a
## dictionary, it carries the marker, and it carries a version this build knows about. A file
## failing any of them is treated as UNREADABLE, which routes to the backup rather than to a
## half-populated world.
static func is_readable(parsed) -> bool:
	if not (parsed is Dictionary):
		return false
	var envelope := parsed as Dictionary
	if String(envelope.get("format", "")) != FORMAT:
		return false
	var version := int(envelope.get("envelope_version", 0))
	return version >= 1 and version <= ENVELOPE_VERSION


## An envelope as the disk should hold it, with every value already JSON-safe.
##
## `world` is normalized in both directions here rather than trusted: a store that returned a
## malformed ledger must not be able to write a half-formed world into a file that later reads
## as authoritative.
static func build(
	actor_payload: Dictionary, world: Dictionary, difficulty: String, generation: int
) -> Dictionary:
	var safe_world := {}
	for key in WORLD_KEYS:
		var value = world.get(key)
		safe_world[key] = value if (value is Dictionary) else {}
	return {
		"envelope_version": ENVELOPE_VERSION,
		"format": FORMAT,
		"generation": generation,
		"difficulty": difficulty,
		"actor": actor_payload,
		"world": safe_world,
	}
