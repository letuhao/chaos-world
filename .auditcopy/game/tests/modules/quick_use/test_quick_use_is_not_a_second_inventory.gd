extends TestCase

## **A quick-use bar binds an id; it never keeps a count.** That sentence is the whole
## design, and this suite is the only thing holding it in place.
##
## The hazard is specific. `modules/items` already owns inventory: `Inventory.count`,
## `Inventory.add`, `Inventory.remove`, `ItemStack`, and the `ItemsApi` verbs that
## reach them. A quick-use bar that also remembered "5 pills in slot 2" would be a
## second copy of one fact, and the two would drift the first time a save restored one
## and not the other — the ADR 0066 failure shape, one module over.
##
## Nothing in `tools arch` can catch it. The gate reads module boundaries and the app/
## placement heuristics; a member that does not exist yet is invisible to it, exactly
## as ADR 0084 records for the sect's "grants no power" rule. So the invariant is
## pinned structurally here, in the idiom `tests/modules/sect/test_sect_no_power.gd`
## established: name the whole published surface, so a verb added later fails here
## rather than slipping past a forbidden-word list, and then assert the behavioural
## halves a structural check cannot reach.

## The verbs the facade IS, asserted as a whole rather than as the absence of the
## forbidden ones. A bind, a clear, a spend and two reads. If this list grows, the
## surface grew, and the growth has to be argued here first.
const PUBLISHED := ["assign_slot", "attach", "clear_slot", "summary", "use_slot"]

## The component's whole public surface. There is deliberately no quantity accessor on
## it, which is the whole point: a caller that could ask the bar for a count is a
## caller one refactor away from believing the count.
const COMPONENT_SURFACE := ["bind", "bound_at", "release", "to_ids"]

## Every script this module owns, so the structural cases read the whole module rather
## than one file.
const MODULE_FILES := [
	"res://src/modules/quick_use/api.gd",
	"res://src/modules/quick_use/quick_use_slots.gd",
]

## Writes that would make this a second inventory rather than a binding. `ItemsApi`
## spells every one of them, so a hit here is either a bypass of the facade rule or an
## inventory being built by hand.
const INVENTORY_WRITES := [
	"Inventory.new",
	"ItemStack.new",
	"ItemInstance.new",
	".add(",
	".remove(",
	".add_batch(",
	".add_instance(",
	".remove_instance(",
]

const PILL := &"health_pill"

# --- The invariant, structurally ---------------------------------------------


func test_the_facade_publishes_exactly_the_bind_and_spend_surface() -> void:
	var published := _verbs("res://src/modules/quick_use/api.gd")
	assert_eq(published.is_empty(), false, "the facade's method list is readable")
	assert_eq(published, PUBLISHED, "the facade is a bind, a clear, a spend and two reads")
	assert_eq(published.size() <= 12, true, "and it is inside the twelve-method cap")


func test_the_bar_keeps_no_count_and_publishes_no_way_to_ask_for_one() -> void:
	# The strongest form of the claim: not "no verb is named `quantity`" but "here is
	# the entire surface, and reading one is all a caller can do". `bound_at` returns a
	# `StringName`; there is no `quantity_at` to drift.
	var surface := _verbs("res://src/modules/quick_use/quick_use_slots.gd")
	assert_eq(surface.is_empty(), false, "the component's method list is readable")
	assert_eq(surface, COMPONENT_SURFACE, "the component binds and reads ids, nothing else")


func test_no_module_file_writes_an_inventory_by_hand() -> void:
	for rel in MODULE_FILES:
		var body := FileAccess.get_file_as_string(rel)
		assert_ne(body, "", "%s is readable" % rel)
		for forbidden in INVENTORY_WRITES:
			assert_eq(
				_calls(body, forbidden),
				0,
				"%s never writes an inventory: %s" % [rel.get_file(), forbidden]
			)


func test_the_module_keeps_exactly_one_piece_of_state_and_it_is_six_ids() -> void:
	# The claim is not "the module never mentions a count" — `summary()` is *supposed*
	# to read one from the bag. The claim is that it never KEEPS one, and the only way
	# to keep a count is to have somewhere to put it. So this counts member
	# declarations across the whole module rather than grepping for words: the
	# component owns one array of six ids, the facade owns none, and a second member
	# cannot be added without failing here.
	assert_eq(
		_members("res://src/modules/quick_use/quick_use_slots.gd"),
		["_bound"],
		"the component's entire state is the one id array"
	)
	assert_eq(
		_members("res://src/modules/quick_use/api.gd"),
		[],
		"and the facade holds nothing at all, being all static"
	)


# --- The invariant, behaviourally --------------------------------------------


func test_binding_a_slot_creates_nothing_and_clearing_one_discards_nothing() -> void:
	# Both halves of "this is a binding". A bar cannot conjure a pill out of an empty
	# bag, and releasing a slot cannot delete one — the item is `items`' alone.
	var actor := _hero()
	QuickUseApi.assign_slot(actor, 0, PILL)
	assert_eq(
		ItemsApi.inventory(actor).stacks().size(),
		0,
		"binding a slot to an id the actor does not carry puts nothing in the bag"
	)
	_pills(actor, 2)
	QuickUseApi.assign_slot(actor, 1, PILL)
	QuickUseApi.clear_slot(actor, 1)
	assert_eq(ItemsApi.inventory(actor).count(PILL), 2, "and clearing a slot discards nothing")


func test_a_summary_quantity_is_read_from_items_and_never_kept_here() -> void:
	# The case that would fail if the bar kept its own count: the number has to MOVE
	# when the bag moves. A cached count stays at whatever it was written and the two
	# disagree, which is the drift this module exists not to have.
	var actor := _hero()
	_pills(actor, 3)
	QuickUseApi.assign_slot(actor, 0, PILL)
	assert_eq(int(_row(actor, 0)["quantity"]), 3, "the row reports what the bag holds")

	_pills(actor, 4)
	assert_eq(
		int(_row(actor, 0)["quantity"]),
		7,
		"and it follows the bag, which a count kept here could not do"
	)

	ItemsApi.consume_item(actor, PILL, 7)
	assert_eq(int(_row(actor, 0)["quantity"]), 0, "and down to nothing when the bag empties")


func test_a_bar_with_no_inventory_reads_zero_rather_than_raising() -> void:
	# `ItemsApi.inventory` is null until `items` attaches. A panel drawing the bar of an
	# actor mid-wiring must get a number, not a null dereference.
	var bare := Actor.new(&"bare", {Stat.SPIRIT: 20.0})
	bare.attach_core_resources()
	QuickUseApi.assign_slot(bare, 0, PILL)
	assert_eq(int(_row(bare, 0)["quantity"]), 0, "a bound id with no bag reads zero")


func test_spending_a_slot_goes_through_items_and_nowhere_else() -> void:
	# The delegation is the feature: the effect belongs to `items`, so the bar's own
	# contribution to a spend is the removal of one unit and no stat write of its own.
	# Reading `restores` off the delegated result is the direct evidence that the
	# restoration was `items`' doing, since this module never resolves an effect.
	var actor := _hero()
	_pills(actor, 2)
	QuickUseApi.assign_slot(actor, 0, PILL)
	var result: Dictionary = QuickUseApi.use_slot(actor, 0)
	assert_eq(bool(result.get("ok", false)), true, "the spend lands")
	assert_eq(
		float((result.get("restores", {}) as Dictionary).get("health", 0.0)),
		20.0,
		"and the pill's own restoration came back from `items`"
	)
	assert_eq(
		ItemsApi.inventory(actor).count(PILL),
		1,
		"exactly one unit left the bag, and the bar decided nothing about it"
	)


# --- Helpers -----------------------------------------------------------------


func _hero() -> Actor:
	var actor := Actor.new(&"bar", {Stat.SPIRIT: 20.0, Stat.PHYSIQUE: 20.0})
	actor.attach_core_resources()
	ItemsApi.attach(actor)
	return actor


## Give `actor` `count` more of a restoring pill, the way `items` builds one.
func _pills(actor: Actor, count: int) -> void:
	var def := ItemDef.new()
	def.id = PILL
	def.category = ItemCategory.CONSUMABLE
	def.stackable = true
	def.max_stack = 99
	def.fixed_modifiers = [{"option_id": &"restore_health", "value": 20.0}]
	ItemsApi.inventory(actor).add(def, count)


func _row(actor: Actor, slot_index: int) -> Dictionary:
	return QuickUseApi.summary(actor)["slots"][slot_index]


## Every method name the script at `rel` publishes, read from the script itself, with
## underscore-prefixed names dropped exactly as `tools/arch/enforce.py` drops them
## (`FUNC_RE` then `if not name.startswith("_")`). The gate and this helper therefore
## count the same verbs.
func _verbs(rel: String) -> Array[String]:
	var out: Array[String] = []
	var script: GDScript = load(rel)
	if script == null:
		return out
	for method in script.get_script_method_list():
		var name: String = method["name"]
		if name.begins_with("_"):
			continue
		if not out.has(name):
			out.append(name)
	out.sort()
	return out


## Every member name the script at `rel` declares, sorted.
##
## Anchored to COLUMN ZERO on the RAW line, never on a stripped one, which is the same
## anchoring and the same reason as `rules.APP_UNSHAPED_ARRAY_RE`: a `var` inside a
## function body is a local, and a local cannot be this module's long-lived state.
## Stripping the indentation first — the obvious way to write this — reads every local
## in the file as a member, which is how the first cut of this helper found
## `quantity` and `rows:` in a facade that has no members at all.
func _members(rel: String) -> Array[String]:
	var out: Array[String] = []
	var body := FileAccess.get_file_as_string(rel)
	assert_ne(body, "", "%s is readable" % rel)
	for line in body.split("\n"):
		var rest := ""
		if line.begins_with("@onready var "):
			rest = line.trim_prefix("@onready var ")
		elif line.begins_with("var "):
			rest = line.trim_prefix("var ")
		else:
			continue
		var name := ""
		for character in rest:
			if character == " " or character == ":" or character == "=":
				break
			name += character
		if not name.is_empty():
			out.append(name)
	out.sort()
	return out


## How many times `needle` appears in CODE, ignoring the `##` prose that documents it.
## This module names the things it refuses inside its own docs — that refusal IS the
## design — so a raw `body.contains(needle)` scan fails on those sentences while
## reading the code beside them as clean. The invariant is about what the module
## EXECUTES, so comment lines are dropped first. Same helper, same reason, as
## `test_sect_no_power.gd`.
func _calls(body: String, needle: String) -> int:
	var hits := 0
	for line in body.split("\n"):
		var code := line.strip_edges()
		if code.begins_with("#"):
			continue
		if code.contains(needle):
			hits += 1
	return hits
