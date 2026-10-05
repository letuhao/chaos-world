class_name BaseGrantLedger
extends RefCounted

## The per-SOURCE press counter, and the only arithmetic that touches it.
##
## ## What this counts, and what it deliberately does not
##
## It counts how many times one `source` has been granted against one actor. It does
## NOT count magnitude, does not carry a realm, and cannot answer "how strong is this
## grant" — a source's grants may be any authored amounts and the ledger is the same
## whatever they are.
##
## That is the whole reason this is a press count and not a total of points. ADR 0200's
## own test: *a cap on a magnitude axis dies, because that axis must scale with the
## ladder.* A base attribute has to climb to 551x, so nothing here may bound it. What
## must not be unbounded is the RATE at which one source can inject permanent power
## into a save, and a press count is exactly that.
##
## ## Why the counter is persisted rather than recomputed
##
## Without a save key a reload would hand the same source a fresh budget, so the bound
## would be theatre that a save/load cycle walks straight through. The key is a
## `String`, like every inner key this repo writes, because `Actor.to_dict` converts
## the OUTER `module_data` key and nothing else (`core/actor.gd`) — a `StringName` inner
## key reaches the save untouched and returns as a `String`, so a map keyed by it reads
## empty after a reload.
##
## ## Why `normalize` rebuilds rather than repairs
##
## `Actor.get_module_data` hands back the LIVE dictionary and a save is untrusted
## input, so the normaliser copies rather than writes through, and `maxi`s every count
## because a JSON round trip turns every number into a float. A hand-edited save cannot
## park a negative count and buy itself presses.

const VERSION := 1

const KEY_VERSION := "version"
const KEY_GRANTS := "grants"


## `raw` as this module's ledger, whatever a save or a caller handed over. Always a NEW
## dictionary and always String-keyed inside, so a save is never written through.
static func normalize(raw: Variant) -> Dictionary:
	var out := {KEY_VERSION: VERSION, KEY_GRANTS: {}}
	if not raw is Dictionary:
		return out
	var source := raw as Dictionary
	var grants: Variant = source.get(KEY_GRANTS, {})
	if not grants is Dictionary:
		return out
	var copied: Dictionary = {}
	# `keys()` is snapshotted by the `for` itself and the body writes to `copied`, never
	# to the dictionary being walked, so the walk cannot outrun its input (INC-0002).
	for key in (grants as Dictionary).keys():
		copied[str(key)] = maxi(0, int((grants as Dictionary)[key]))
	out[KEY_GRANTS] = copied
	return out


## How many grants `source_id` has already landed on this actor. `0` for a source this
## ledger has never heard of.
static func used(ledger: Dictionary, source_id: String) -> int:
	var grants: Variant = normalize(ledger).get(KEY_GRANTS, {})
	if not grants is Dictionary:
		return 0
	return maxi(0, int((grants as Dictionary).get(source_id, 0)))


## The ledger with `source_id`'s press count advanced by one.
static func record(ledger: Dictionary, source_id: String) -> Dictionary:
	var out := normalize(ledger)
	var grants: Dictionary = out[KEY_GRANTS]
	grants[source_id] = maxi(0, int(grants.get(source_id, 0))) + 1
	return out
