import io

# --- domain_scene.gd: re-apply the docstring, add the WORLD consts, append the block ---
P = "game/src/app/domain_scene.gd"
s = io.open(P, encoding="utf-8").read()

OLD_HEAD = """## than inside the data.
##
## ## Why this is a new class and not a `WorldEntry`"""
NEW_HEAD = """## than inside the data.
##
## ## WHO BUILDS THIS IN PRODUCTION
##
## [method realize], via `DomainBoot.realize_world` — which the composition root installs as
## a `Callable` seam (`DomainBoot.set_world_observer`) and `DomainBoot.enter_domain` fires
## the moment a run exists. It builds this scene, parents it under the mounted domain SCREEN
## so the floor is a node in the live tree and not a description of one, places one inhabitant
## body per minted `Actor` at `DomainSpawner.placement`, adds a `PlayerAdapter` bounded to
## [method map_bounds], and is undone by [method release_world] on `leave_domain`, on a route
## change, and in `ItemWorkbenchApp.teardown()`.
##
## That is the whole production path. **What is NOT built: an avatar that MOVES.**
## `PlayerAdapter` is placed and bounded, and `move_to` / `step_movement` work headlessly,
## but nothing in the shipped program drives its `_physics_process` from a real frame and no
## screen exposes a movement control. A player can ENTER a domain and SEE its floor, its
## walls and the creatures standing on it, but cannot yet walk across it. That is the
## remaining half, recorded here rather than implied by this file's existence.
##
## ## Why this is a new class and not a `WorldEntry`"""
assert s.count(OLD_HEAD) == 1, s.count(OLD_HEAD)
s = s.replace(OLD_HEAD, NEW_HEAD)

# The world names, declared with the other consts (class-definitions-order puts every
# const before every func, so a const declared beside the world section is an error).
OLD_CONSTS = """const ZONES_NODE := "Zones"
"""
NEW_CONSTS = """const ZONES_NODE := "Zones"

## The realized world, by name. [method realize] builds a `Node2D` under a parent the CALLER
## chose, so the composition root owns the node that draws the world and the world goes away
## with it; these four names are how anyone finds it afterwards. Declared among the other
## constants rather than beside the world section because `class-definitions-order` puts every
## `const` before every `func`.
const WORLD_NODE := "DomainWorld"
const WORLD_SCENE_NODE := "DomainScene"
const WORLD_PLAYER_NODE := "DomainPlayer"
const WORLD_INHABITANTS_NODE := "DomainInhabitants"

## Every node a realized world creates, so [method release_world] frees the subtree by NAME
## rather than by walking it — bounded, and self-describing: anything under the world that is
## not in this list was created by somebody else and is reported as `stranded`. An engine
## element type (`StringName`), never a repo type, which is what keeps this off the `app/`
## state-table heuristic.
const WORLD_BORN: Array[StringName] = [
	WORLD_PLAYER_NODE,
	WORLD_INHABITANTS_NODE,
	WORLD_SCENE_NODE,
]
"""
assert s.count(OLD_CONSTS) == 1
s = s.replace(OLD_CONSTS, NEW_CONSTS)

block = io.open("scratchpad_world_scene_block.txt", encoding="utf-8").read()
if not s.endswith("\n"):
    s += "\n"
s += block
io.open(P, "w", encoding="utf-8", newline="").write(s)
print("domain_scene.gd now", s.count("\n") + 1)

# --- domain_boot.gd: strip its own WORLD consts, replace the engine verbs with forwarders ---
P = "game/src/app/domain_boot.gd"
b = io.open(P, encoding="utf-8").read()

OLD_BOOT_CONSTS = """
## The realized world, by name. [method realize_world] builds a `Node2D` under a parent the
## CALLER chose, so the composition root owns the node that draws the world and the world
## goes away with it; these four names are how anyone finds it afterwards.
##
## Declared HERE rather than beside the world section because `class-definitions-order`
## (gdlint) puts every `const` before every `func`, and a const declared mid-file is an
## ordering error rather than a local convenience.
const WORLD_NODE := &"DomainWorld"
const WORLD_SCENE_NODE := &"DomainScene"
const WORLD_PLAYER_NODE := &"DomainPlayer"
const WORLD_INHABITANTS_NODE := &"DomainInhabitants"

## Every node a realized world creates, so [method release_world] frees the subtree by name
## rather than by walking it — and so a caller can see exactly what it now owes the process.
##
## An ENGINE element type (`StringName`), never a repo type, which is what keeps this out of
## the `app/` state-table heuristic — see [method _last_inhabitants].
const WORLD_BORN: Array[StringName] = [
	WORLD_PLAYER_NODE,
	WORLD_INHABITANTS_NODE,
	WORLD_SCENE_NODE,
]
"""
assert b.count(OLD_BOOT_CONSTS) == 1
b = b.replace(OLD_BOOT_CONSTS, "")

FWD = '''## REALIZE the active run as a walkable world under `parent`, and answer what happened.
##
## A THIN FORWARDER, and that is the whole of its job. The engine side — the `DomainScene`,
## the inhabitant bodies, the player adapter and the free — belongs to `DomainScene` itself
## (`domain_scene.gd`), which already owns "where is this map in pixels". Putting it there
## rather than here keeps one question answered in one file: a world that had to ask a
## different class where its own tiles are could disagree with them about which tile a
## corridor ends on.
##
## What this file still owns is the ONE thing only it can know: which run is active, and
## which bodies the spawner minted for it. Those go down as ARGUMENTS to
## [method DomainScene.realize] and land nowhere else.
##
## Refuses `no_parent`, `no_actor` and `no_map` BY NAME. Writes nothing before all three
## resolve, so a refusal leaves the caller's tree exactly as it found it.
static func realize_world(parent: Node, player: Actor) -> Dictionary:
\tif _run == null:
\t\treturn {"ok": false, "reason": "no_map"}
\treturn DomainScene.realize(parent, _run, player, _last_inhabitants())


## FREE the realized world under `parent`. Idempotent, and a no-op when nothing was ever
## realized, so a `teardown()` may call it without asking first.
static func release_world(parent: Node) -> Dictionary:
\treturn DomainScene.release_world(parent)


## Whether a world is currently realized under `parent`. Read by the composition root and by
## `test_domain_playable.gd` through this one verb, so neither walks for a node name this
## file does not publish.
static func world_realized(parent: Node) -> bool:
\treturn DomainScene.world_realized(parent)


## The realized world's read model, primitives only, or `{}` when nothing is realized.
static func world_summary(parent: Node) -> Dictionary:
\treturn DomainScene.world_summary(parent)


'''
A = "## REALIZE the active run as a walkable world under"
C = "## Every inhabitant the LAST `enter_domain` minted, as `Actor`s."
a = b.index(A)
c = b.index(C)
b = b[:a] + FWD + b[c:]
io.open(P, "w", encoding="utf-8", newline="").write(b)
print("domain_boot.gd now", b.count("\n") + 1)
