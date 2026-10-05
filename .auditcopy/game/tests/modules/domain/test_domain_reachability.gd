extends TestCase

## **A room the kit ships is a room a player can walk into — on EVERY seed, not on the
## seed that happened to work.**
##
## `test_domain_content.gd` proves a template carries the room in its `room_pool` or
## `pins`. That is pool MEMBERSHIP, and it is weaker than it looks: `DomainGenerator`
## deals the kit by `index % dealt_size` (`_deal`, `domain_generator.gd`) over the
## leaves a pin has not taken (`_dealt_pool`), and a domain's LEAF COUNT varies with
## the seed, so a def that is carried can still be crowded out by the roll. Three
## authored rooms (`ash_gate`, `ash_arena`, `ash_heart` — the threshold trap, the only
## arena and the boss hoard) were unreachable for exactly this reason, and nothing that
## read the pool would ever have said so.
##
## TWO claims, not one, because they fail for different reasons and need different fixes:
##
## 1. **CONTAINMENT, every seed.** Whatever a seed's leaf count, it can only build defs
##    that template carries — a def no template carries can never appear. This is the
##    original defect restated as a property of generated maps.
## 2. **COMPLETENESS, every seed.** Every def a template carries is BUILT, not merely
##    carried. This used to be measured against `map.room_count()`, and that was wrong
##    twice over. It is neither a necessary nor a sufficient condition for the kit
##    being covered:
##
##    - **NOT NECESSARY.** `_place_structural` reserves entry, core, the gate, every
##      arena and every PINNED leaf before the pool is dealt, so an arena is a structural
##      room that the kit's deals can never land on. `ember_grotto` seed 13 has nine
##      rooms, one def to place and only four deals — and was flagged by the old rule
##      while the map it built was complete.
##    - **NOT SUFFICIENT.** The old budget was `carried + 3 + pins.size()` = 9 / 11 / 13,
##      counting a pin TWICE (once as a carried def, once as a reserved leaf) and
##      counting the arena count as though it were the constant 3. The real requirement
##      is one leaf per def NO PIN HAS ALREADY PLACED, plus one per pin: 4+1 = 5, 4+2 =
##      6, 6+2 = 8 for the three templates. And `_deal` used to subtract the whole pin
##      count from every leaf, so on `ember_grotto` — one pin, five defs — the fifth pool
##      entry was never dealt on ANY of the 64 seeds and `ash_chamber` was never built at
##      all, whatever the room count.
##
##    A guard that names the wrong number is not a weaker guard, it is a wrong one: this
##    file's own header used to claim "a pool of `p` defs is fully built only once a map
##    has at least `p + reserved` rooms", and that sentence is what let a shipped
##    template drop a room on every seed. The claim is now stated as what the generator
##    actually guarantees, and nothing in this suite infers it from a number it guesses.
##    What the threshold SHOULD be is declared by the author, on the template, as
##    `requires_full_kit` — so a template whose own numbers cannot cover its own kit says
##    so and is refused rather than shipped with a hole in it.
##
## Claim 2 as an assertion is therefore a PAIR: every seed that DID generate a map must
## build the whole kit, and every seed that did not must have had a leaf budget too small
## to do it. Neither half can pass alone: dropping the `continue` would make a starved
## seed look complete, and deleting the starvation check would make a hole look like a
## coverage guarantee.

const TEMPLATE_DIR := "res://src/data/domains/templates"
const ROOM_DIR := "res://src/data/domains/rooms"

## The seeds this guard walks. `test_domain_generator.gd` holds its own determinism and
## contract claims over a 64-seed matrix and this suite reuses that number rather than
## inventing a second width: the leaf COUNT is what decides whether a pool this size is
## fully dealt, and a matrix is the only way to see a def crowded out by a single
## shallow roll. Bounded by this constant itself.
const REACHABILITY_SEED_COUNT := 64

## The rule-placed leaves `_place_structural` consumes before the pool is dealt, over
## and above the pins: the entry floor, the core and the gate. An arena is NOT part of
## it — `_arena_indices` only ever returns leaves at breadth depth >= ARENA_MIN_DEPTH,
## and a two-leaf map has none, so a reserve that counted arenas would be a constant
## that is sometimes zero and sometimes several. The three are genuinely rule-placed on
## every map of every template, so this count is. Bounded by the constant.
const RULE_PLACED_RESERVE := 3

## The most leaves this guard allows a seed to short the kit by and still call the map
## complete: one, because that is the difference between a kit of `d` and a map of `d + 1`
## leaves. Anything more is a missing ROOM, not a missing repetition.
const ALLOWED_SHORTFALL := 1


## Every `while` below is over a directory listing, which `DirAccess.get_next()` always
## terminates. `for` over an Array is bounded by that Array.
func _tres_files(dir_path: String) -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if not dir.current_is_dir() and entry.ends_with(".tres"):
			out.append(entry)
		entry = dir.get_next()
	dir.list_dir_end()
	return out


func _authored_room_ids() -> Dictionary:
	var out: Dictionary = {}
	for file_name in _tres_files(ROOM_DIR):
		var room := load("%s/%s" % [ROOM_DIR, file_name]) as RoomDef
		if room != null:
			out[String(room.room_id)] = true
	return out


## The authored `room_id`s this template carries, through either door — its `room_pool`
## or a `pins` entry. Bounded by the two arrays; no loop whose bound is derived from
## anything but the template's own content.
func _carried_ids(template: DomainTemplateDef) -> Dictionary:
	var out: Dictionary = {}
	for room_def in template.room_pool:
		out[String(room_def.room_id)] = true
	for pin in template.pins:
		if pin != null and pin.room_def != null:
			out[String(pin.room_def.room_id)] = true
	return out


## How many of this template's pins actually PLACE a def — the pins `_pinned_defs`
## honours. A null pin, a pin with no `room_def`, a negative `leaf_index` and a
## structural kind are all refused there, so they cannot be counted as placed rooms
## here either. Read off the template rather than restated, so this cannot drift.
func _honoured_pin_count(template: DomainTemplateDef) -> int:
	var count := 0
	for pin in template.pins:
		if pin == null or pin.room_def == null or pin.leaf_index < 0:
			continue
		if DomainTemplateDef.is_pinnable_kind(pin.kind):
			count += 1
	return count


## The authored def ids a generated map actually built, as the part of each namespaced
## room id before the `#`.
func _built_def_ids(map: DomainMap) -> Dictionary:
	var out: Dictionary = {}
	for room_id in map.room_ids_sorted():
		out[String(room_id).split("#", false)[0]] = true
	return out


func test_every_authored_room_appears_in_a_generated_domain() -> void:
	var templates := _tres_files(TEMPLATE_DIR)
	assert_eq(templates.is_empty(), false, "the authored template kit is not empty")
	var kit_size := _authored_room_ids().size()
	var foreign: Array[String] = []
	var incomplete: Array[String] = []
	for file_name in templates:
		var template := load("%s/%s" % [TEMPLATE_DIR, file_name]) as DomainTemplateDef
		assert_ne(template, null, "template '%s' loads" % file_name)
		if template == null:
			continue
		var template_id := String(template.template_id)
		var carried := _carried_ids(template)
		var pins := _honoured_pin_count(template)
		# Every rule-placed leaf the generator reserves before dealing, plus every PINNED
		# leaf. Read off the template's OWN pin count rather than restated, so this cannot
		# drift from the generator.
		var reserve := RULE_PLACED_RESERVE + pins
		var budget := carried.size() + reserve
		assert_eq(
			budget >= kit_size,
			true,
			(
				(
					"template '%s' reserves %d leaf/leaves before dealing its %d-def kit, so its "
					% [template_id, reserve, carried.size()]
				)
				+ ("largest possible map covers the %d-room kit" % kit_size)
			)
		)
		# The `requires_full_kit` contract, stated once and read off the template: the kit
		# is fully dealt from `min_rooms` leaves only while the pins it relies on are
		# DISTINCT pool defs. Two pins naming one def would leave `pins` leaves to cover
		# `pool + 1` defs and the seed would have to be refused instead of built.
		var distinct_pinned := _distinct_pinned_count(template)
		assert_eq(
			(
				(not template.requires_full_kit or template.room_pool.size() <= template.min_rooms)
				and distinct_pinned == pins
			),
			true,
			(
				(
					"template '%s' requires_full_kit, so its %d-deal kit must fit its "
					% [template_id, template.room_pool.size()]
				)
				+ (
					"min_rooms %d with %d distinct pin(s); it reserves %d"
					% [template.min_rooms, distinct_pinned, reserve]
				)
			)
		)
		# ONE report per defect, each naming the seeds that produced it. Asserting per
		# seed would trip `MAX_FAILURES` on the first bad roll and the backstop would
		# kill the process reporting only the least useful of them.
		var foreign_seeds: Array[int] = []
		var starved_seeds: Array[int] = []
		var hollow_seeds: Array[int] = []
		var covering_maps := 0
		for seed_value in range(1, REACHABILITY_SEED_COUNT + 1):
			var map := DomainGenerator.generate(template, seed_value)
			# TOTALITY. Every seed of every authored template produces a map: a template
			# whose own numbers refuse it is an authoring error, and a null here is a seed
			# no player can enter rather than a seed that built less. Asserted per seed
			# rather than summarised so the failure names the roll.
			assert_ne(map, null, "template '%s' seed %d produced a map" % [template_id, seed_value])
			if map == null:
				continue
			var built := _built_def_ids(map)
			for room_id in built:
				if not carried.has(room_id):
					foreign_seeds.append(seed_value)
					break
			# Claim 2, half one: every seed that produced a map built the whole kit.
			var missing: Array[String] = []
			for room_id in carried:
				if not built.has(room_id):
					missing.append(room_id)
			if not missing.is_empty():
				starved_seeds.append(seed_value)
				continue
			covering_maps += 1
			# Claim 2, half two: the leaves this seed's kit was actually DEALT from, told
			# to the author. A template that CLAIMS full coverage (`requires_full_kit`) is
			# covered on EVERY seed, and a seed that covered its kit while its own leaves
			# could not have carried it means the generator and the template's stated
			# budget have drifted apart — which is exactly what the old
			# `3 + pins.size()` restatement of this number did.
			var dealt := _dealt_leaf_count(template, seed_value)
			if template.requires_full_kit and dealt < template.room_pool.size() - ALLOWED_SHORTFALL:
				hollow_seeds.append(seed_value)
		if not foreign_seeds.is_empty():
			foreign.append(
				(
					(
						"template '%s' built a room its room_pool does not carry on %d of %d seeds "
						% [template_id, foreign_seeds.size(), REACHABILITY_SEED_COUNT]
					)
					+ (
						"(widest map held %d distinct defs); a room placed by nothing is "
						% _widest_map(template)
					)
					+ "content no player can reach"
				)
			)
		if not starved_seeds.is_empty():
			incomplete.append(
				(
					(
						"template '%s' left a def it carries UNBUILT on %d of %d seeds "
						% [template_id, starved_seeds.size(), REACHABILITY_SEED_COUNT]
					)
					+ (
						"(%d seed(s) built its whole %d-def kit; %d room(s) were not enough): "
						% [covering_maps, carried.size(), reserve]
					)
					+ (
						"a room the kit ships is a room a player can walk into, and a deal is "
						+ "a slot in the kit, not a rule-placed leaf"
					)
				)
			)
		if not hollow_seeds.is_empty():
			incomplete.append(
				(
					(
						"template '%s' claims requires_full_kit but could not build its whole "
						% template_id
					)
					+ (
						"%d-deal kit on %d of %d seeds; its own leaf budget cannot cover it"
						% [template.room_pool.size(), hollow_seeds.size(), REACHABILITY_SEED_COUNT]
					)
				)
			)
	assert_eq(foreign.is_empty(), true, "; ".join(foreign))
	assert_eq(incomplete.is_empty(), true, "; ".join(incomplete))


## How many leaves this seed's room kit was actually DEALT into — the number the kit's
## completeness depends on, as opposed to the room count, which is not it.
##
## Read by walking the generator's own steps (`_partition` -> `_canonical_order` ->
## `_prune_to` -> `_spanning_tree` -> `_place_structural` -> `_pinned_defs`), the same
## shape `test_domain_generator.gd` uses, so the number cannot be a restatement of the
## generator's intent rather than its behaviour. `_pinned_defs` is what decides which
## leaves a pin fills, so counting the rest is counting the deals. Every walk is bounded
## by the leaf count or by `REACHABILITY_SEED_COUNT`; no `while` at all.
func _dealt_leaf_count(template: DomainTemplateDef, seed_value: int) -> int:
	var leaves := DomainGenerator._partition(
		template, DomainRng.streams(seed_value)[DomainRng.STREAM_GRAPH]
	)
	leaves = DomainGenerator._canonical_order(leaves)
	leaves = DomainGenerator._prune_to(
		leaves, DomainGenerator._prune_limit(leaves, template.max_rooms)
	)
	if leaves.size() < template.min_rooms:
		return 0
	var placements := DomainGenerator._place_structural(
		template, leaves, DomainGenerator._spanning_tree(leaves)
	)
	return (
		leaves.size()
		- DomainGenerator._pinned_defs(template, leaves, placements[&"reserved"]).size()
	)


## The defs this template's pins name, counted once each — a pin that repeats a def its
## pool already carries contributes no extra coverage. Bounded by `template.pins` and by
## the dictionary it fills; no `while`.
func _distinct_pinned_count(template: DomainTemplateDef) -> int:
	var distinct: Dictionary = {}
	for pin in template.pins:
		if pin == null or pin.room_def == null or pin.leaf_index < 0:
			continue
		if DomainTemplateDef.is_pinnable_kind(pin.kind):
			distinct[String(pin.room_def.room_id)] = true
	return distinct.size()


## How many distinct defs the deepest roll built, read by re-walking the same bounded
## matrix rather than remembered from the pass above — so a report names the ceiling it
## was measured against.
func _widest_map(template: DomainTemplateDef) -> int:
	var widest := 0
	for seed_value in range(1, REACHABILITY_SEED_COUNT + 1):
		var map := DomainGenerator.generate(template, seed_value)
		if map == null:
			continue
		widest = maxi(widest, _built_def_ids(map).size())
	return widest
