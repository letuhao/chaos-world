class_name DomainGenerator
extends RefCounted

## Builds a `DomainMap` from an authored `DomainTemplateDef` and a seed (ADR 0072).
##
## ## Shape
##
## A recursive binary space partition over the tile grid, a spanning tree over the
## leaves, then proximity loop edges. Rooms are the leaves; a corridor is the
## connection an edge implies, and a room's exits are derived from the edges that
## touch it.
##
## ## Geometry first, dice second
##
## The split *structure* is mostly derived and almost never rolled:
##
## - leaves are put in CANONICAL spatial order (center.y, then center.x, then birth)
##   with zero rng, which is what makes the fill order a property of the geometry
##   rather than of the draw order;
## - the entry, the core, the gate and the arenas are placed BY RULE off that order
##   and the tree's distances — the entry is the leaf containing `entry_anchor`, the
##   core is the leaf furthest from the entry, the gate is the entry's lowest-index
##   neighbour;
## - corridor elbow order is `abs(dx) >= abs(dy) -> horizontal first`, not a coin
##   flip, because an L has two shapes and one of them is always the longer leg;
## - an over-wide leaf count is pruned by collapsing the LARGEST leaves, largest-first,
##   with no rng at all.
##
## What is left for the rng is exactly what is a judgement call: the split ratios, the
## axis repeats, the shuffle of the room kit, and which proximity candidates become
## loops. Everything else is a rule.
##
## ## Bounded everywhere
##
## There is NO RETRY and NO UNBOUNDED LOOP in this file. Every walk is a `for` over a
## canonically sorted list or is bounded by `max_depth`, the leaf count or the
## candidate count. A generator that cannot converge does not spin — it `push_error`s
## naming the template, the seed, the condition and the numbers, and returns `null`.
## The repo has already paid for the alternative: an unbounded loop whose exit
## condition was unreachable wrote ~10 GB of engine log before anyone noticed.

## Depth counted from the root cell. `max_depth` is checked BEFORE a cell is popped for
## splitting, so the recursion is bounded by construction and cannot loop.
const ROOT_DEPTH := 0

## A pruned map keeps at least this many rooms. Pruning down to a degenerate one-room
## map would satisfy "fewer rooms" and fail the contract's connectivity spirit.
const PRUNE_MIN_LEAVES := 2

## Rooms at least this far from the entry, breadth-first, are arena candidates.
const ARENA_MIN_DEPTH := 2

## A rectilinear gap, in tiles, no wider than this is "close enough to loop".
const CORNER_TIE := 0.0


## The map for `template` at `seed_value`, or `null` on a loud failure.
##
## Never a partial map: a caller that received half a domain would place a run in it.
static func generate(template: DomainTemplateDef, seed_value: int) -> DomainMap:
	if template == null:
		push_error("DomainGenerator: no template to generate from; refusing to return a map")
		return null
	if not DomainRng.is_valid_seed(seed_value):
		_fail(template, seed_value, "seed is outside the reproducible 64-bit range")
		return null
	var pools := DomainRng.streams(seed_value)
	if pools.is_empty():
		_fail(template, seed_value, "produced no rng streams")
		return null

	var leaves := _partition(template, pools[DomainRng.STREAM_GRAPH])
	if leaves.is_empty():
		_fail(
			template,
			seed_value,
			(
				"produced no leaf from extent %s with min_leaf %d, margin %d, max_depth %d"
				% [
					_box(template.extent),
					template.min_leaf,
					template.margin,
					template.max_depth,
				]
			)
		)
		return null
	leaves = _canonical_order(leaves)
	leaves = _prune_to(leaves, _prune_limit(leaves, template.max_rooms))
	if leaves.size() < template.min_rooms:
		_fail(
			template,
			seed_value,
			(
				(
					"produced %d room(s), below its min_rooms %d, from extent %s, "
					% [leaves.size(), template.min_rooms, _box(template.extent)]
				)
				+ "min_leaf %d, max_depth %d" % [template.min_leaf, template.max_depth]
			)
		)
		return null

	var tree := _spanning_tree(leaves)
	if tree.is_empty():
		_fail(
			template,
			seed_value,
			(
				"built no spanning tree over %d leaf/leaves; a one-room domain cannot be entered"
				% leaves.size()
			)
		)
		return null
	var loops := _loop_edges(template, leaves, tree, pools[DomainRng.STREAM_GRAPH])

	var rooms_rng: RandomNumberGenerator = pools[DomainRng.STREAM_ROOMS]
	var placements := _place_structural(template, leaves, tree)
	var map := _realize(
		template, seed_value, rooms_rng, leaves, placements, _key_edges(tree, loops)
	)
	if map == null:
		return null

	var problems := DomainMapContract.assert_valid(map)
	if problems.is_empty():
		return map
	_fail(template, seed_value, "produced a map failing its own contract: %s" % ", ".join(problems))
	return null


# ── BSP ───────────────────────────────────────────────────────────────────────


## The root cell, inset from the extent by the margin. Null when the extent cannot
## hold a single leaf, which the caller reports with the numbers.
static func _root_cell(template: DomainTemplateDef) -> DomainCell:
	var width := template.extent.x - template.margin * 2
	var height := template.extent.y - template.margin * 2
	if width < template.min_leaf or height < template.min_leaf:
		return null
	var cell := DomainCell.new()
	cell.rect = Rect2i(Vector2i(template.margin, template.margin), Vector2i(width, height))
	cell.depth = ROOT_DEPTH
	return cell


## Split until every leaf is legal or `max_depth` is reached.
##
## The walk is a stack, so the recursion is explicit: the stack can only ever hold as
## many cells as the tree has produced, and the tree is bounded by `max_depth`.
static func _partition(
	template: DomainTemplateDef, rng: RandomNumberGenerator
) -> Array[DomainCell]:
	var leaves: Array[DomainCell] = []
	var root := _root_cell(template)
	if root == null:
		return leaves
	var pending: Array[DomainCell] = [root]
	while not pending.is_empty():
		var cell: DomainCell = pending.pop_back()
		if cell.depth >= template.max_depth:
			leaves.append(cell)
			continue
		var children := _split(template, rng, cell)
		if children.is_empty():
			leaves.append(cell)
			continue
		# Push the second child first so the first pops first: a deterministic
		# left-to-right traversal, which is what keeps a cell's `birth` a stable index.
		pending.append(children[1])
		pending.append(children[0])
	return leaves


## The two children of `cell`, or empty when neither orientation is legal.
##
## Legal means BOTH children keep `min_leaf`; the `2 * margin` term is the authored
## allowance for the gap a corridor needs between two rooms, not a safety factor.
static func _split(
	template: DomainTemplateDef, rng: RandomNumberGenerator, cell: DomainCell
) -> Array[DomainCell]:
	var axis := _preferred_axis(cell.rect, template)
	if axis == &"":
		return [] as Array[DomainCell]
	if template.repeat_axis_chance > 0.0 and rng.randf() < template.repeat_axis_chance:
		axis = &"y" if axis == &"x" else &"x"
		if not _axis_legal(cell.rect, template, axis):
			axis = &"y" if axis == &"x" else &"x"
	var needed := template.min_leaf + template.margin * 2
	var span := cell.rect.size.y if axis == &"x" else cell.rect.size.x
	if span < needed * 2:
		return [] as Array[DomainCell]
	var ratio := rng.randf_range(template.split_ratio_range.x, template.split_ratio_range.y)
	var first := clampi(
		int(round(float(span) * ratio)), template.min_leaf, span - template.min_leaf
	)
	var rects := _split_rects(cell.rect, axis, first)
	if rects.is_empty():
		return [] as Array[DomainCell]
	var children: Array[DomainCell] = []
	for index in rects.size():
		var child := DomainCell.new()
		child.rect = rects[index]
		child.depth = cell.depth + 1
		child.birth = cell.birth * 2 + index
		child.parent = cell
		children.append(child)
	return children


## The axis to cut on: the LONGER one, so a cell's aspect does not drift. `&""` when
## that axis cannot legally be cut. A repeat-axis roll that lands on an illegal
## orientation falls back to the other one, so the roll only ever adds variety.
static func _preferred_axis(rect: Rect2i, template: DomainTemplateDef) -> StringName:
	var needed := template.min_leaf + template.margin * 2
	if rect.size.x >= rect.size.y and rect.size.x >= needed * 2:
		return &"x"
	if rect.size.y >= needed * 2:
		return &"y"
	return &""


static func _axis_legal(rect: Rect2i, template: DomainTemplateDef, axis: StringName) -> bool:
	var needed := template.min_leaf + template.margin * 2
	return rect.size.x >= needed * 2 if axis == &"x" else rect.size.y >= needed * 2


## Two rects covering `rect`, the first `first` tiles along the split axis. Empty when
## the split would leave a child under `min_leaf`.
static func _split_rects(rect: Rect2i, axis: StringName, first: int) -> Array[Rect2i]:
	if first <= 0:
		return [] as Array[Rect2i]
	if axis == &"x":
		if first >= rect.size.x:
			return [] as Array[Rect2i]
		return (
			[
				Rect2i(rect.position, Vector2i(first, rect.size.y)),
				Rect2i(
					Vector2i(rect.position.x + first, rect.position.y),
					Vector2i(rect.size.x - first, rect.size.y)
				),
			]
			as Array[Rect2i]
		)
	if first >= rect.size.y:
		return [] as Array[Rect2i]
	return (
		[
			Rect2i(rect.position, Vector2i(rect.size.x, first)),
			Rect2i(
				Vector2i(rect.position.x, rect.position.y + first),
				Vector2i(rect.size.x, rect.size.y - first)
			),
		]
		as Array[Rect2i]
	)


## Leaves in canonical spatial order: center.y, then center.x, then birth. Zero rng —
## the order is the geometry's, so two runs of the same template fill the same way
## regardless of what the streams drew.
static func _canonical_order(leaves: Array[DomainCell]) -> Array[DomainCell]:
	var ordered := leaves.duplicate()
	ordered.sort_custom(
		func(a: DomainCell, b: DomainCell) -> bool:
			var ay := float(a.rect.position.y) + float(a.rect.size.y) / 2.0
			var by := float(b.rect.position.y) + float(b.rect.size.y) / 2.0
			if not is_equal_approx(ay, by):
				return ay < by
			var ax := float(a.rect.position.x) + float(a.rect.size.x) / 2.0
			var bx := float(b.rect.position.x) + float(b.rect.size.x) / 2.0
			if not is_equal_approx(ax, bx):
				return ax < bx
			return a.birth < b.birth
	)
	return ordered


# ── pruning ──────────────────────────────────────────────────────────────────


## How many leaves survive pruning against `limit`. Pure arithmetic: no rng, no retry.
## The walk is bounded by the leaf count on both axes and stops early the moment the
## limit is met.
static func _prune_limit(leaves: Array[DomainCell], limit: int) -> int:
	if limit < PRUNE_MIN_LEAVES or leaves.size() <= limit:
		return leaves.size()
	var collapsible: Array[DomainCell] = leaves.duplicate()
	var reserved: Array[DomainCell] = []
	var removed := 0
	for _step in leaves.size():
		if leaves.size() - removed <= limit:
			break
		var victim := _largest_collapsible(collapsible, reserved)
		if victim < 0:
			break
		collapsible.remove_at(victim)
		removed += 1
	return maxi(PRUNE_MIN_LEAVES, leaves.size() - removed)


## Index of the largest collapsible leaf. Ties go to the LOWER canonical index, so the
## collapse is a function of the geometry and not of a sort's stability. A leaf with no
## parent (the root) is never collapsed, and an already-removed leaf is not in the list.
static func _largest_collapsible(
	collapsible: Array[DomainCell], reserved: Array[DomainCell]
) -> int:
	var best := -1
	var best_area := -1
	for index in collapsible.size():
		var cell: DomainCell = collapsible[index]
		if cell.parent == null or reserved.has(cell):
			continue
		var area := cell.area()
		if best < 0 or area > best_area:
			best_area = area
			best = index
	return best


## The leaves that survive pruning, in the SAME canonical order as the input, with a
## leaf's `parent` back-reference cleared so a pruned parent cannot collapse a child.
static func _prune_to(leaves: Array[DomainCell], limit: int) -> Array[DomainCell]:
	if limit >= leaves.size():
		return leaves
	var collapsible: Array[DomainCell] = leaves.duplicate()
	while collapsible.size() > limit:
		var victim := _largest_collapsible(collapsible, [] as Array[DomainCell])
		if victim < 0:
			break
		var cell: DomainCell = collapsible[victim]
		cell.parent = null
		collapsible.remove_at(victim)
	return collapsible


# ── graph ────────────────────────────────────────────────────────────────────


## A spanning tree over the leaves: the edge that costs least at each step, accepted
## only if it joins two components (Prim over a complete graph). O(V^2) and bounded by
## the leaf count; it always produces exactly `n - 1` edges for `n > 1`, because a
## spanning tree exists on any complete graph. No retry, no spin.
static func _spanning_tree(leaves: Array[DomainCell]) -> Array[DomainPair]:
	var edges: Array[DomainPair] = []
	var count := leaves.size()
	if count < 2:
		return edges
	var component: Array[int] = []
	for index in count:
		component.append(index)
	while edges.size() < count - 1:
		var pair := _cheapest_link(leaves, count, component)
		if pair == null:
			return edges
		_union(component, pair.a, pair.b)
		edges.append(pair)
	return edges


## The cheapest edge joining two distinct components, or null when the graph is
## already connected. Exhaustive over the pairs, so "no better edge found" cannot
## loop: the answer is the same on every visit.
static func _cheapest_link(
	leaves: Array[DomainCell], count: int, component: Array[int]
) -> DomainPair:
	var best: DomainPair = null
	for i in count:
		for j in range(i + 1, count):
			if component[i] == component[j]:
				continue
			var gap := leaves[i].gap_to(leaves[j])
			if best != null and gap >= best.gap:
				continue
			best = DomainPair.new()
			best.a = i
			best.b = j
			best.gap = gap
	return best


static func _union(component: Array[int], from_index: int, to_index: int) -> void:
	var from_root := _find(component, from_index)
	var to_root := _find(component, to_index)
	if from_root == to_root:
		return
	for index in component.size():
		if _find(component, index) == to_root:
			component[index] = from_root


## The component representative. Bounded by the component size — the forest is a set of
## trees over `component`, so this cannot outrun `index`.
static func _find(component: Array[int], index: int) -> int:
	var value := index
	for _hop in component.size():
		if component[value] == value:
			return value
		value = component[value]
	return value


## Loop edges: pairs whose gap is within `loop_gap_tiles`, drawn without replacement.
##
## The candidate list is SORTED by gap then by canonical index, so the draw is over a
## deterministic list rather than over the order leaves happened to be visited in. The
## tree edges are excluded, so a loop is always an ADDITIONAL connection.
static func _loop_edges(
	template: DomainTemplateDef,
	leaves: Array[DomainCell],
	tree: Array[DomainPair],
	rng: RandomNumberGenerator
) -> Array[DomainPair]:
	var out: Array[DomainPair] = []
	if template.loop_ratio <= 0.0 or leaves.size() < 3:
		return out
	var wanted := template.loop_count_for(leaves.size())
	if wanted <= 0:
		return out
	var candidates := _loop_candidates(template, leaves, tree)
	if candidates.is_empty():
		return out
	var pool := _seeded_shuffle(candidates, rng)
	var taken := 0
	for pair in pool:
		if taken >= wanted:
			break
		out.append(pair)
		taken += 1
	return out


## The loop candidates, sorted: gap first, then canonical index.
static func _loop_candidates(
	template: DomainTemplateDef, leaves: Array[DomainCell], tree: Array[DomainPair]
) -> Array[DomainPair]:
	var have: Dictionary = {}
	for edge in tree:
		have[_pair_key(edge.a, edge.b)] = true
	var candidates: Array[DomainPair] = []
	for i in leaves.size():
		for j in range(i + 1, leaves.size()):
			if have.has(_pair_key(i, j)):
				continue
			var pair := DomainPair.new()
			pair.a = i
			pair.b = j
			pair.gap = leaves[i].gap_to(leaves[j])
			if pair.gap <= float(template.loop_gap_tiles):
				candidates.append(pair)
	candidates.sort_custom(
		func(a: DomainPair, b: DomainPair) -> bool:
			if not is_equal_approx(a.gap, b.gap):
				return a.gap < b.gap
			if a.a != b.a:
				return a.a < b.a
			return a.b < b.b
	)
	return candidates


## Fisher-Yates driven by `rng`. `Array.shuffle()` in Godot 4.7 draws from the GLOBAL
## RandomNumberGenerator and takes no generator argument, so using it here would make
## every map depend on whatever touched the global RNG first — which is exactly the
## determinism this file exists to hold. An explicit seeded shuffle is the only form
## that keeps the claim true.
static func _seeded_shuffle(values: Array, rng: RandomNumberGenerator) -> Array:
	var out := values.duplicate()
	for index in range(out.size() - 1, 0, -1):
		var swap := rng.randi_range(0, index)
		if swap == index:
			continue
		var held = out[index]
		out[index] = out[swap]
		out[swap] = held
	return out


static func _pair_key(a: int, b: int) -> int:
	return a * 100000 + b


static func _key_edges(tree: Array[DomainPair], loops: Array[DomainPair]) -> Array[DomainPair]:
	var out: Array[DomainPair] = []
	var have: Dictionary = {}
	for edge in tree:
		out.append(edge)
		have[_pair_key(edge.a, edge.b)] = true
	for edge in loops:
		if have.has(_pair_key(edge.a, edge.b)):
			continue
		out.append(edge)
		have[_pair_key(edge.a, edge.b)] = true
	return out


# ── structural placement ─────────────────────────────────────────────────────


## Every leaf's `kind`, plus the entry/core/gate indexes. All four structural kinds are
## placed BY RULE; a pinned kind is applied on top and never overrules a rule.
static func _place_structural(
	template: DomainTemplateDef, leaves: Array[DomainCell], tree: Array[DomainPair]
) -> Dictionary:
	var kinds: Array[StringName] = []
	for index in leaves.size():
		kinds.append(&"chamber")
	var neighbours := _adjacency(leaves.size(), tree)
	var entry := _entry_index(template, leaves)
	var depth := _breadth_depth(entry, leaves.size(), neighbours)
	var core := _farthest(entry, depth)
	# The core must be a leaf DISTINCT from the entry, because `kinds[core] = &"core"`
	# below is guarded on `core != entry`. `_farthest` answers the entry whenever the
	# entry is its own farthest, which a shallow or single-branch map produces routinely,
	# and then the map has NO core room at all -- a structural kind the domain contract
	# requires to exist exactly once. Fall back to the lowest canonical non-entry index:
	# a rule, never a roll, the same shape as `_entry_index`. A one-room map has no such
	# index, and that map is already rejected by the contract.
	if core == entry:
		for candidate in leaves.size():
			if candidate != entry:
				core = candidate
				break
	var gate := _lowest_neighbour(entry, neighbours)
	kinds[entry] = &"floor"
	if core != entry:
		kinds[core] = &"core"
	if gate != entry and gate != core:
		kinds[gate] = &"gate"
	# The structural set every pin relocates PAST, resolved once here so the pin's kind
	# and the pin's def cannot disagree about which leaf it lands on.
	#
	# Two rules this set must obey, both learned from a pin that vanished:
	#
	#   - NO DUPLICATES AND NO -1. `entry`, `core` and `gate` come from three different
	#     searches and can coincide, and `_lowest_neighbour` can answer -1. A repeated or
	#     negative index made `_free_leaf` read a taken-set that was not the set of
	#     leaves actually reserved.
	#   - IT LEAVES ROOM FOR THE PINS. An author pin is CONTENT, and this module exists
	#     so content is not starved by a rule. Arenas are the only discretionary kind
	#     here, so they are what gives way: when `ember_grotto` seed 46 reserved all eight
	#     of its leaves, `_free_leaf` answered -1 and the pin was dropped with no
	#     diagnostic at all -- which is the one outcome the docstring below says must not
	#     happen. Budget the arenas against the pin count so every pin has a leaf to land
	#     on, and hard structure (floor/core/gate) never yields, because geometry is the
	#     part a pin is documented never to overrule.
	var reserved: Array = []
	for index in [entry, core, gate]:
		if index >= 0 and not reserved.has(index):
			reserved.append(index)
	var arena_budget := maxi(0, leaves.size() - reserved.size() - template.pins.size())
	var arenas: Array[int] = []
	for index in _arena_indices(entry, core, depth):
		if index != core and arenas.size() < arena_budget and not reserved.has(index):
			kinds[index] = &"arena"
			arenas.append(index)
	reserved.append_array(arenas)
	_apply_pins(template, leaves, kinds, reserved)
	return {
		&"kinds": kinds,
		&"entry": entry,
		&"core": core,
		&"gate": gate,
		&"arenas": arenas,
		&"reserved": reserved,
	}


## The entry leaf: the one whose rect CONTAINS `entry_anchor`, else the lowest canonical
## index. A rule, never a roll — the door a run starts at is geometry.
static func _entry_index(template: DomainTemplateDef, leaves: Array[DomainCell]) -> int:
	var anchor := Vector2i(template.entry_anchor)
	if anchor != Vector2i.ZERO:
		for index in leaves.size():
			if leaves[index].rect.has_point(anchor):
				return index
	return 0


## The core leaf: max breadth-first distance from the entry, tie to the LOWEST canonical
## index. `_breadth_depth` bounds the walk, so this cannot spin.
static func _farthest(entry: int, depth: Array[int]) -> int:
	var best := entry
	var best_depth := 0
	for index in depth.size():
		if depth[index] > best_depth:
			best_depth = depth[index]
			best = index
	return best


## The gate leaf: the entry's lowest-indexed neighbour. -1 when the entry is alone,
## which only happens for the one-room map the contract rejects anyway.
static func _lowest_neighbour(entry: int, neighbours: Array) -> int:
	if entry < 0 or entry >= neighbours.size():
		return -1
	var adjacent: Array = neighbours[entry]
	if adjacent.is_empty():
		return -1
	return int(adjacent[0])


## Arena leaves: every leaf at breadth depth >= 2 except the entry and the core. A
## rule, not a die: an arena is "out past the gate", and the generator writes that down
## rather than guessing a distance.
static func _arena_indices(entry: int, core: int, depth: Array[int]) -> Array[int]:
	var out: Array[int] = []
	for index in depth.size():
		if index == entry or index == core:
			continue
		if depth[index] >= ARENA_MIN_DEPTH:
			out.append(index)
	return out


## Authored pins, over the rule-placed kinds. A pin NEVER overrules a structural rule:
## the rules own entry/core/gate/arena, and an author who wants a different shape
## changes the template. But a pin whose leaf IS structural, or whose index is past the
## last leaf, is RELOCATED to the next free leaf rather than dropped — dropping it would
## silently delete authored content, which is the failure this module exists to prevent.
## Bounded by the leaf count, so it cannot spin.
static func _apply_pins(
	template: DomainTemplateDef,
	leaves: Array[DomainCell],
	kinds: Array[StringName],
	structural: Array
) -> void:
	if leaves.is_empty():
		return
	var taken: Dictionary = {}
	for index in structural:
		taken[index] = true
	for pin in template.pins:
		if pin == null or pin.room_def == null or pin.leaf_index < 0:
			continue
		if not DomainTemplateDef.is_pinnable_kind(pin.kind):
			continue
		var index := _free_leaf(pin.leaf_index, leaves.size(), taken.keys())
		if index < 0:
			continue
		taken[index] = true
		kinds[index] = pin.kind


## The leaf a pin lands on: its authored index clamped into range, relocated to the
## lowest already-taken-free leaf when that one is occupied. ONE rule shared by the pin's
## DEF and its KIND so the two can never land on different leaves. Bounded by the leaf
## count, so it cannot spin.
static func _free_leaf(wanted: int, leaf_count: int, taken: Array) -> int:
	if leaf_count <= 0:
		return -1
	var index := clampi(wanted, 0, leaf_count - 1)
	if not taken.has(index):
		return index
	for candidate in leaf_count:
		if not taken.has(candidate):
			return candidate
	return -1


## Adjacency from the edge list, canonical order, as `Array[Array]`.
static func _adjacency(count: int, edges: Array[DomainPair]) -> Array:
	var out: Array = []
	for _index in count:
		out.append([] as Array[int])
	for edge in edges:
		if edge.a < 0 or edge.b < 0 or edge.a >= count or edge.b >= count:
			continue
		(out[edge.a] as Array).append(edge.b)
		(out[edge.b] as Array).append(edge.a)
	for index in out.size():
		var adjacent: Array = out[index]
		adjacent.sort()
	return out


## Breadth-first distance from the entry over the adjacency. -1 marks unreached; the
## frontier walk is bounded by the leaf count, so an unreachable leaf cannot spin.
static func _breadth_depth(entry: int, count: int, neighbours: Array) -> Array[int]:
	var depth: Array[int] = []
	for _index in count:
		depth.append(-1)
	if entry < 0 or entry >= count:
		return depth
	depth[entry] = 0
	var frontier: Array[int] = [entry]
	while not frontier.is_empty():
		var current: int = frontier.pop_front()
		for next_index in neighbours[current] as Array:
			if depth[next_index] >= 0:
				continue
			depth[next_index] = depth[current] + 1
			frontier.append(next_index)
	return depth


# ── materialization ──────────────────────────────────────────────────────────


## Every realized room, keyed by its namespaced `room_id`, already wired to its exits.
## Null when the template cannot fill its own leaves, which the caller reports.
static func _realize(
	template: DomainTemplateDef,
	seed_value: int,
	rng: RandomNumberGenerator,
	leaves: Array[DomainCell],
	placements: Dictionary,
	edges: Array[DomainPair]
) -> DomainMap:
	if template.room_pool.is_empty():
		_fail(
			template,
			seed_value,
			"has an empty room_pool; a domain with no authored rooms is not a domain"
		)
		return null
	var kinds: Array[StringName] = placements[&"kinds"]
	var kit := _seeded_shuffle(template.room_pool.duplicate(), rng)
	# The SAME reserved set `_apply_pins` used, resolved once in `_place_structural`, so
	# a pin's def and its kind land on the same leaf. Passing different sets is how a
	# settlement kind ended up on a plain chamber def.
	var pinned := _pinned_defs(template, leaves, placements[&"reserved"])
	# The pin's KIND travels with its def, resolved from the same reserved set, so a
	# relocated settlement is not realized as whatever the rule put on that leaf.
	var pinned_kinds := _pinned_kinds(template, leaves, placements[&"reserved"])
	var entry := int(placements[&"entry"])
	var map := DomainMap.new(template.extent, seed_value)
	var ids: Array[StringName] = []
	for index in leaves.size():
		var kind: StringName = kinds[index]
		var def: RoomDef = pinned.get(index, null)
		if def == null:
			def = kit[_deal(index, pinned.size(), kit.size())]
		var room := _materialize(def, leaves[index], kind, index, pinned_kinds.get(index, &""))
		ids.append(room.room_id)
		map.add_room(room)
	for edge in edges:
		if edge.a < 0 or edge.b < 0 or edge.a >= ids.size() or edge.b >= ids.size():
			continue
		_append_exit(map.room(ids[edge.a]), ids[edge.b])
		_append_exit(map.room(ids[edge.b]), ids[edge.a])
	_guarantee_connected(map, ids, placements)
	map.entry_room = ids[entry]
	return map


## Connectivity as a STRUCTURAL guarantee, not a property of the tree that was built.
##
## The spanning tree is connected over LEAF INDEXES; a map is connected over ROOM IDS,
## and those two sets only correspond while nothing reorders, drops or renames a leaf
## between the tree and `_realize`. Rather than trust that correspondence to hold for
## every edit, this walks the realized map and links whatever the tree left stranded to
## the reachable set — one edge per orphan, always to the lowest canonical reachable
## neighbour. Deterministic, bounded by the room count, and it can never loop.
##
## This is the last line of defence, not the plan: the BSP plus spanning tree is what
## makes a map connected, and this closes the gap between that and the ids a player
## actually walks.
static func _guarantee_connected(
	map: DomainMap, ids: Array[StringName], placements: Dictionary
) -> void:
	var stranded: Array[StringName] = []
	var seen: Dictionary = {}
	var frontier: Array[StringName] = []
	var start: StringName = ids[mini(int(placements[&"entry"]), ids.size() - 1)]
	frontier.append(start)
	seen[start] = true
	while not frontier.is_empty():
		var current: StringName = frontier.pop_front()
		for exit_id in (map.room(current) as RoomDef).exits:
			if seen.has(exit_id) or not map.has_room(exit_id):
				continue
			seen[exit_id] = true
			frontier.append(exit_id)
	for room_id in map.room_ids_sorted():
		if not seen.has(room_id):
			stranded.append(room_id)
	if stranded.is_empty():
		return
	# One edge from each orphan to the lowest reachable room that already exists. Not
	# the nearest — NEAREST is a distance rule, and this must stay a pure function of
	# canonical order.
	var reachable: Array[StringName] = []
	for room_id in map.room_ids_sorted():
		if seen.has(room_id):
			reachable.append(room_id)
	for orphan in stranded:
		if reachable.is_empty():
			break
		var anchor: StringName = reachable[0]
		_append_exit(map.room(anchor), orphan)
		_append_exit(map.room(orphan), anchor)
		reachable.append(orphan)


## The pool entry for the `index`-th unfilled leaf. The pool is dealt ROUND ROBIN over
## the leaves in canonical order: the first unfilled leaf takes kit[0], the second
## kit[1], and the pool wraps. The shuffle happened once, so this is a function of the
## canonical order and the shuffled kit, not of a second draw per leaf.
static func _deal(index: int, pinned_count: int, pool_size: int) -> int:
	# Wraps over the POOL, not the leaf count. A kit of 3 defs filling 24 leaves must
	# repeat those 3, not index past the end of the array: `index % pool_size` is what
	# makes round-robin mean round-robin.
	if pool_size <= 0:
		return 0
	var unfilled_before := index - mini(index, pinned_count)
	return maxi(0, unfilled_before) % pool_size


## The def a leaf's pin fixes, keyed by leaf index.
##
## A pin names a leaf by INDEX and the realized leaf count varies with the seed, so an
## index past the end cannot be honoured literally. It is CLAMPED, and `_apply_pins`
## RELOCATES a pin whose leaf is structural, so both go through `_free_leaf` and cannot
## land on different leaves. A pin the generator silently drops is content the player
## never sees, which is the failure this whole module exists to prevent.
static func _pinned_defs(
	template: DomainTemplateDef, leaves: Array[DomainCell], reserved: Array
) -> Dictionary:
	var out: Dictionary = {}
	if leaves.is_empty():
		return out
	var taken: Dictionary = {}
	for index in reserved:
		taken[index] = true
	for pin in template.pins:
		if pin == null or pin.room_def == null or pin.leaf_index < 0:
			continue
		if not DomainTemplateDef.is_pinnable_kind(pin.kind):
			continue
		# A pin names a def the POOL must already carry: the pool IS the shared kit
		# (ADR 0073) and a pin does not smuggle in content the kit does not have. A
		# template whose pin names a def outside its own pool is an authoring error the
		# author has to see, so it is reported rather than silently honoured.
		if not template.room_pool.has(pin.room_def):
			_fail(
				template,
				-1,
				(
					(
						"pins leaf %d to def '%s', which its room_pool does not contain; the pool is "
						% [pin.leaf_index, String(pin.room_def.room_id)]
					)
					+ "the shared kit and a pin cannot add to it"
				)
			)
			continue
		var index := _free_leaf(pin.leaf_index, leaves.size(), taken.keys())
		if index < 0:
			continue
		taken[index] = true
		out[index] = pin.room_def
	return out


## The pinned KIND for each pinned leaf, so `_materialize` can restore it. A pin's kind
## travels with its def: without this the relocated leaf would take the rule-placed kind
## and a settlement would be realized as an arena.
static func _pinned_kinds(
	template: DomainTemplateDef, leaves: Array[DomainCell], reserved: Array
) -> Dictionary:
	var out: Dictionary = {}
	if leaves.is_empty():
		return out
	var taken: Dictionary = {}
	for index in reserved:
		taken[index] = true
	for pin in template.pins:
		if pin == null or pin.room_def == null or pin.leaf_index < 0:
			continue
		if not DomainTemplateDef.is_pinnable_kind(pin.kind):
			continue
		var index := _free_leaf(pin.leaf_index, leaves.size(), taken.keys())
		if index < 0:
			continue
		taken[index] = true
		out[index] = pin.kind
	return out


## One deep-copied `RoomDef` with its realized size, namespaced id and no exits — the
## exits come from the corridor graph, never from the authored def.
##
## `pinned_kind` is the kind a PIN fixed for this leaf, or empty when the leaf was dealt
## from the pool. A PINNED def keeps its pinned kind, because the pin is the authored
## decision and a relocation must not turn a settlement into an arena. A FILLED leaf
## takes the rule-placed kind, because that is what makes an entry a floor and a core a
## core no matter which def the shuffle dealt there. The authored def's own kind is the
## last resort for a def that declares none.
static func _materialize(
	def: RoomDef, cell: DomainCell, kind: StringName, index: int, pinned_kind: StringName = &""
) -> RoomDef:
	var room := _copy_def(def)
	if pinned_kind != &"" and RoomDef.KINDS.has(pinned_kind):
		room.kind = pinned_kind
	elif kind != &"" and RoomDef.KINDS.has(kind):
		room.kind = kind
	else:
		room.kind = def.kind
	room.size = cell.rect.size
	room.room_id = StringName("%s#%d" % [String(def.room_id), index])
	room.exits = [] as Array[StringName]
	return room


## A deep copy of `def`. The generator never mutates an authored resource: the same def
## is placed again in the next map a seed builds, and a shared write would change both.
static func _copy_def(def: RoomDef) -> RoomDef:
	var room := RoomDef.new()
	room.room_id = def.room_id
	room.display_name = def.display_name
	room.kind = def.kind
	room.roster_band = def.roster_band
	room.tags = def.tags.duplicate()
	room.size = def.size
	for ref in def.actor_spawn_refs:
		room.actor_spawn_refs.append((ref as Dictionary).duplicate(true))
	for fixture in def.fixtures:
		room.fixtures.append((fixture as Dictionary).duplicate(true))
	for zone in def.environment_zones:
		room.environment_zones.append(_copy_zone(zone))
	return room


static func _copy_zone(zone: EnvironmentZoneDef) -> EnvironmentZoneDef:
	var out := EnvironmentZoneDef.new()
	out.zone_id = zone.zone_id
	out.kind = zone.kind
	out.intensity = zone.intensity
	out.status_id = zone.status_id
	out.stay_budget = zone.stay_budget
	out.tags = zone.tags.duplicate()
	out.mitigation_tags = zone.mitigation_tags.duplicate()
	out.bounds = zone.bounds
	return out


static func _append_exit(room: RoomDef, target: StringName) -> void:
	if room == null or room.exits.has(target):
		return
	room.exits.append(target)
	room.exits.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))


# ── helpers ──────────────────────────────────────────────────────────────────


## The loud failure. One shape for every refusal, naming the template, the seed, the
## condition and the numbers — a message that cannot be acted on is noise.
static func _fail(template: DomainTemplateDef, seed_value: int, condition: String) -> void:
	push_error(
		(
			"DomainGenerator: template '%s' seed %d %s"
			% [String(template.template_id), seed_value, condition]
		)
	)


static func _box(extent: Vector2i) -> String:
	return "%dx%d" % [extent.x, extent.y]


class DomainCell:
	## One BSP cell. A leaf cell is a room's rect; an internal cell is only reached
	## through its children's `parent` back-reference. Nested classes default to
	## `RefCounted` in Godot 4 — they are generator scratch, never authored content.

	var rect: Rect2i = Rect2i()
	var depth: int = 0
	var birth: int = 0
	var parent: DomainCell = null

	func area() -> int:
		return rect.size.x * rect.size.y

	## The rectilinear gap between two cells: `0` when they touch or overlap.
	func gap_to(other: DomainCell) -> float:
		var ax := rect.position.x
		var ay := rect.position.y
		var bx := other.rect.position.x
		var by := other.rect.position.y
		var dx := maxi(0, maxi(ax - (bx + other.rect.size.x), bx - (ax + rect.size.x)))
		var dy := maxi(0, maxi(ay - (by + other.rect.size.y), by - (ay + rect.size.y)))
		return float(dx + dy)


class DomainPair:
	## Two leaf indexes and the rectilinear gap that made them an edge.

	var a: int = 0
	var b: int = 0
	var gap: float = 0.0
