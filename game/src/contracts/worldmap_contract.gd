class_name WorldmapContract
extends RefCounted

## The interface every worldmap generation pass implements, and the data
## shapes the spatial system speaks in. Dependency-free: data crosses as
## plain Dictionaries, never as module types, so passes stay composable and
## the core map system never names a gameplay concept.
##
## ## Node shape (SpatialNode)
##
## `{"id": String, "kind": StringName, "parent": StringName}`. `kind` is an
## open vocabulary — town, cave, domain, pocket world — never an enum, so a
## future concept needs no core change. `parent` names containment; travel is
## NOT derived from it (see below). `&""` parent means a root.
##
## ## Edge shape (TravelConnection)
##
## `{"from": String, "to": String, "kind": StringName, "from_cell": Vector2i,
## "to_cell": Vector2i, "two_way": bool, "hook": String, "toll": Dictionary}`.
## `kind` is open (doorway, portal, road, ship, world_transfer...). `hook`
## names a gate evaluator (absent means open); `toll` is `{amount}` with a
## non-negative int or `{}` for free. Containment and travel are independent:
## an edge may join nodes that share no parent, and a child may have no edge
## to its parent at all.
##
## ## Chunk shape
##
## `{"id": String, "node": String, "cx": int, "cy": int, "size": int,
## "seed": int, "walkable": Array, "terrain": Array, "props": Array,
## "mutations": Dictionary}`. Sizes are per-map (never a global 16);
## `walkable` is rows of bool, `terrain` rows of archetype String,
## `props` an array of placement dicts, `mutations` cell-keyed overrides
## (`"x,y" -> {"blocked": bool}`) applied over regeneration.
##
## ## Pass contract
##
## A pass reads the chunk context and earlier passes' output, and writes its
## own layer. `requires()` names the layers it reads (e.g. a scatter pass
## requires `"terrain"`), so the pipeline orders passes and fails a missing
## dependency by name instead of reading another pass's absence as emptiness.
##
## Two address books, one rule: `terrain`, `props` and `walkable` are
## first-class and read top-level; every later layer (elevation, encounters,
## ...) reads from `chunk["layers"]` under its own name and is written back
## there by the pipeline. A pass returns its payload top-level either way —
## the fold is the pipeline's, not the author's. `props` is the one
## first-class exception: every scatter-family pass APPENDS its own
## placements, because overwriting would let registration order eat writers.


## The pass's own layer name (e.g. `&"terrain"`, `&"vegetation"`). Empty here;
## the pipeline refuses a pass that does not name its layer.
func pass_id() -> StringName:
	return &""


## Layer names this pass reads. The pipeline runs producers first and refuses
## a requirement no registered pass provides.
func requires() -> Array:
	return []


## Run against `ctx` (`{seed, node, cx, cy, size, rng_state}`) and the chunk
## built so far; return the layer payload to merge (`{"terrain": rows}`,
## `{"props": [...]}`). Pure: same inputs, same output, no node touched.
func run(_ctx: Dictionary, _chunk: Dictionary) -> Dictionary:
	return {}
