class_name SetCatalog
extends RefCounted

## The authored set/unique content tree, loaded once and cached.
##
## Set definitions live in `res://data/sets/`, the item definitions the sets and
## uniques are made of live in `res://data/sets/items/`, and the unique drop
## tuning lives in `res://data/sets/unique_routes.jsonl`. The item definitions
## are ordinary `ItemDef` resources: they resolve through the master option
## catalog exactly like any other item, and they fall back to the items
## module's single game-wide resolver so a set may also name content that lives
## in the main `data/items/` tree.
##
## Two facts are owned by the item definition and are therefore NOT restated in
## the route index, which used to duplicate both and agree only by luck:
##
##   - **Which boss drops a unique.** The definition's `unique_route:<boss_id>`
##     tag is what `LootRoutes` enforces at drop time, so it is the only
##     declaration that cannot drift from behaviour.
##   - **Which slot a unique occupies.** That is the definition's own
##     `subcategory`. The index carried a `slot` column that was a stale copy of
##     it for three of its five rows.
##
## The index therefore carries only what a drop author knows and nothing else
## can: `set_id`, `domain_id`, `route_realm`, `min_rarity`, `drop_weight`.

const SETS_ROOT := "res://data/sets"
const ITEMS_ROOT := "res://data/sets/items"
const ROUTES_PATH := "res://data/sets/unique_routes.jsonl"
const SET_SCRIPT_CLASS := "SetDef"
const BASE_OWNER := "base"

static var shared: SetCatalog = null

## Overlay stack for the sets family (ADR 0184 §5). Empty means "not wired
## yet": `_ensure_loaded` merges only the authored SETS_ROOT. When set, the
## overlay roots merge AFTER the base root so mod content is visible, with the
## declared-override collision policy CatalogOverlay enforces.
static var _overlay_stack: Array = []

var _sets: Dictionary = {}
var _definitions: Dictionary = {}
## Ids authored under `ITEMS_ROOT`, as opposed to anything `definition()` later
## resolved from the wider `data/items/` tree. Identity is read from this, so
## `unique_ids()` answers the same thing before and after any other lookup.
var _tree_ids: Dictionary = {}
var _routes: Dictionary = {}
var _loaded: bool = false


## Set the family's overlay stack: ordered rows of `{dir, owner,
## declared_overrides, id_field}`. Later rows overlay earlier ones; an id
## collision needs a declared override on the LATER root or the merge fails
## loudly (ADR 0240).
static func set_overlay_roots(stack: Array) -> void:
	_overlay_stack = stack


## The merge stack: the base root as a base-owned row, then the overlay rows
## in order. The base row carries the family's default id_field so the merge
## reads the correct property even when an overlay row omits it.
func _merge_stack() -> Array:
	var stack: Array = [
		{
			"dir": SETS_ROOT,
			"owner": BASE_OWNER,
			"declared_overrides": [],
			"id_field": "id",
		}
	]
	for row in _overlay_stack:
		stack.append(row)
	return stack


## Merge the family's overlay stack through CatalogOverlay (ADR 0184 §5).
## Returns CatalogOverlay.merge's dictionary unchanged: `{ok, reason, detail,
## merged, paths, owners}`.
func _overlay_merge() -> Dictionary:
	return CatalogOverlay.merge(_merge_stack(), SET_SCRIPT_CLASS, "id")


static func instance() -> SetCatalog:
	if shared == null:
		shared = SetCatalog.new()
	return shared


## Every authored set id, canonically ordered.
func set_ids() -> Array[StringName]:
	_ensure_loaded()
	var out: Array[StringName] = []
	for key in _sets.keys():
		out.append(StringName(key))
	out.sort()
	return out


func set_definition(set_id: StringName) -> SetDef:
	_ensure_loaded()
	return _sets.get(String(set_id))


## The definition behind a set member, a unique, or any other item id. Prefers
## this module's own tree, then the items module's resolver, so there is one
## lookup and never a guess.
func definition(item_id: StringName) -> ItemDef:
	_ensure_loaded()
	var id := String(item_id)
	if _definitions.has(id):
		return _definitions[id]
	var direct := "%s/%s.tres" % [ITEMS_ROOT, id]
	var def: ItemDef = null
	if ResourceLoader.exists(direct):
		def = load(direct) as ItemDef
	if def == null:
		def = Crafting.resolve(item_id)
	if def != null:
		_definitions[id] = def
	return def


## The declared drop tuning for a unique, or `{}` when it has no row. The boss
## itself is *not* here — read `UniqueItem.route_boss_id` for the enforced fact.
func route(unique_id: StringName) -> Dictionary:
	_ensure_loaded()
	return _routes.get(String(unique_id), {})


## Every authored unique under this module's own content tree, canonically
## ordered. Identity comes from the definitions — a unique is anything tagged
## `unique` — never from the route index, so deleting or mistyping a route row
## can never make a shipped unique disappear from a count or from a screen.
func unique_ids() -> Array[StringName]:
	_ensure_loaded()
	var out: Array[StringName] = []
	for key in _tree_ids.keys():
		if UniqueItem.is_unique(_definitions.get(key)):
			out.append(StringName(key))
	out.sort()
	return out


## The slots each of a set's members may occupy, in `member_ids()` order.
##
## The ruling comes from the item definition's own authored subtype rule, read
## through the items module's value object rather than through its internals, so
## `set_bonus` holds no copy of it. An unruled subtype gets every wearable slot,
## because that is what `Equipment.equip` grants it; a subtype authored as
## wearing nowhere gets none, which is the same answer for the same reason.
##
## `Equipment.SLOTS` is named directly and deliberately: the wearable slot ids are
## the vocabulary both sides count in, not behaviour owned by one module, and
## re-deriving the list here would be a second copy that could drift.
func member_slots(set_id: StringName) -> Array:
	var out: Array = []
	var set_def := set_definition(set_id)
	if set_def == null:
		return out
	for member_id in set_def.member_ids():
		var def := definition(member_id)
		if def == null or not def.is_wearable():
			out.append([])
			continue
		var allowed: Array = def.wearable_slots()
		out.append(allowed if not allowed.is_empty() else Equipment.SLOTS.duplicate())
	return out


## Which slot each member of `set_id` can be worn in at once, in
## `member_ids()` order, `&""` for a member that cannot be placed. This is the
## answer a caller acts on: equipping index `i` into this result's `i` is a legal
## arrangement that reaches [method max_wearable] distinct members.
func placement(set_id: StringName) -> Array[StringName]:
	return SetPlacement.assign(member_slots(set_id))


## The most distinct members of `set_id` a body can ever have equipped at once.
##
## A threshold is satisfied only by what is actually worn, and a body has exactly
## `Equipment.SLOTS` places to wear it — so a tier above this is unreachable
## content rather than a reward. It is a placement, not a minimum of two counts:
## `min(member_count(), Equipment.SLOTS.size())` cannot see that two artifacts
## contend for one artifact slot, and it called a six-member tier on a five-slot
## body reachable. See [SetPlacement].
func max_wearable(set_id: StringName) -> int:
	return SetPlacement.placed_count(member_slots(set_id))


## Which authored tiers of `set_id` no body can ever reach. Empty means the whole
## ladder is winnable, which is what the content suite asserts over the shipped
## sets.
func unreachable_tier_indices(set_id: StringName) -> Array[int]:
	var out: Array[int] = []
	var set_def := set_definition(set_id)
	if set_def == null:
		return out
	var ceiling := max_wearable(set_id)
	for index in set_def.tiers.size():
		if int((set_def.tiers[index] as Dictionary).get("count", 0)) > ceiling:
			out.append(index)
	return out


func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	_load_sets()
	_load_items()
	_load_routes()


func _load_sets() -> void:
	var merged := _overlay_merge()
	if not bool(merged.get("ok", false)):
		push_error("SetCatalog: %s" % String(merged.get("detail", "")))
		return
	for entry in merged["merged"]:
		var def := load(String(entry["path"])) as SetDef
		if def != null and def.id != &"":
			_sets[String(def.id)] = def


func _load_items() -> void:
	for path in _scan(ITEMS_ROOT):
		if not path.get_file().ends_with(".tres"):
			continue
		var def := load(path) as ItemDef
		if def != null and def.id != &"":
			_definitions[String(def.id)] = def
			_tree_ids[String(def.id)] = true


## One JSON object per line. Keys: `unique_id`, `domain_id`, `route_realm`,
## `min_rarity`, `drop_weight`.
##
## `boss_id` and `slot` are deliberately absent: the definition's route tag owns
## the first and its `subcategory` owns the second, and a second copy of a fact
## two files disagree about is how a drop route rots. `set_id` is absent for the
## same reason and is derived from the set definitions instead — this module
## already knows which set lists a unique, so a column repeating it could only
## ever disagree with the membership that counts. `domain_id` is kept because the
## boss's own domain belongs to a module this one may not name; a guard pins the
## two together, so a disagreement is loud rather than silent.
func _load_routes() -> void:
	if not FileAccess.file_exists(ROUTES_PATH):
		push_error("SetCatalog: unique route index missing at %s" % ROUTES_PATH)
		return
	var json := JSON.new()
	for line in FileAccess.get_file_as_string(ROUTES_PATH).split("\n"):
		line = line.strip_edges()
		if line.is_empty():
			continue
		if json.parse(line) != OK or not json.data is Dictionary:
			push_error("SetCatalog: malformed unique route row: %s" % line)
			continue
		var row: Dictionary = json.data
		var unique_id := StringName(OptionCatalog.text_field(row, "unique_id"))
		if unique_id != &"":
			_routes[String(unique_id)] = row


func _scan(root: String) -> Array[String]:
	return ContentScan.files_under(root)
