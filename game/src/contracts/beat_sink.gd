class_name BeatSink
extends RefCounted

## The seam: how ONE place decides what a claimed beat means (ADR 0114).
## Two virtuals, and nothing else.
##
## ## Why an abstract base and not a `Dictionary` of callables
##
## The repo rule is "any script implementing a `contracts/` interface must pass
## the same contract tests", and a dictionary of lambdas has no name to point
## that at — the same reasoning `DamageMechanism` (ADR 0067) states for the
## damage seam. A named class is what makes "the quest sink, the event sink and
## the npc sink all ship the same contract tests" a thing anyone can be held to.
##
## ## Why the parameters are `Variant` and not `WorldBeat`
##
## `contracts/` is a leaf layer: `tools/arch/rules.py` `LAYER_DEPS` declares
## `contracts: {contracts}`, so it may depend on nothing and naming `core` is a
## violation the gate reports, not a convention. `LocationResolver` (ADR 0070)
## is the precedent for typing a contract's arguments loosely and says so in its
## own docstring: it takes `_actor: Variant` and returns a primitives-only
## dictionary precisely because `core/` is out of reach. Rejected alternatives,
## in order of how nearly they worked:
##
## - **Move `WorldBeat` into `contracts/`.** Legal, but it inverts ADR 0114's
##   placement: the beat is stored nowhere and read by no ledger, while `WorldFact`
##   beside it is the world's memory and must stay reachable foundation in `core`
##   (ADR 0082's split). Splitting one ADR's pair across two layers to satisfy a
##   one-line signature is the wrong direction.
## - **Put the sink in `core/`.** Also legal, and it is why this is a real
##   choice rather than an obvious answer — but ADR 0114 names `contracts/`
##   explicitly, for the named-implementation reason above.
## - **A `preload` of `core/world_beat.gd`.** The arch detector scans a file's RAW
##   text for `res://` — comments included, which is why this bullet had to be
##   worded around the literal — so a preload would fail the gate identically
##   while merely looking like a workaround.
##
## So the beat arrives as `Variant`, and every sink — and every contract test for
## one — casts it once at the top. The base class therefore does NOT type
## `handles`/`resolve` with `WorldBeat`: a typed parameter in an override must
## match its parent's exactly, so typing it here would be what makes the honest
## signature impossible to write.
##
## ## The contract, in full
##
## **PURE.** A sink does not mutate anything: not the beat it was handed, not an
## actor's ledger, not a module's state. It returns a PROPOSAL and the director
## applies — ADR 0067's "a mechanism returns a proposal" applied to narrative,
## and what lets a test assert the decision without asserting the side effect. No
## scene tree, no `Actor`, no frame time, and no clock of its own: time-driven
## beats come from a caller that owns the moment (DEF-0111).
##
## The default `handles` claims nothing and `resolve` declines, so a sink with no
## override is a correct no-op rather than a stub that lies.


## Whether this sink claims `beat`. Called in priority order and the first sink
## that answers true owns the outcome — a claim, not a veto: `handles` false
## means "not mine", never "this beat is invalid". Read-only by contract.
func handles(_beat: Variant) -> bool:
	return false


## What this sink proposes for `beat`, or nothing.
##
## Returns `{claimed: bool, reason: String}` and nothing else. Deliberately
## primitives-only: the result travels into logs, UI summaries and
## `BeatHandler` announcements, and a `Resource`, an `Actor` or a lambda in here
## would be a save-schema bug no gate can see — the same rule
## `DamageProposal.is_primitive_effect` enforces by refusing at construction.
##
## `claimed: false` is a legitimate answer, not a failure: an unclaimed beat is
## still recorded, because a fact that happened is true whether or not a handler
## cared. Rejected: returning the effect this sink would have applied, because
## applying is the director's job and a sink that could write would be a second
## place a fact gets moved.
func resolve(_beat: Variant) -> Dictionary:
	return {"claimed": false, "reason": ""}
