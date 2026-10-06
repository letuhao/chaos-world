class_name ClanFounding
extends RefCounted

## The one place a clan declares ITS KIND to the shared registry, and the half of founding
## a clan is allowed to have. **`clan` cannot be founded, and that is the whole reason this
## file is this short** (ADR 0064, ADR 0083, ADR 0271 decision 5).
##
## ## Why clan does not get a `profile()` the way sect does
##
## `SectFounding.profile` exists because a sect is SWORN TO and `core/institution_founding.gd`
## cannot name a `SectDef` to read its authored cost off. A clan is **born to**, so the
## verb `InstitutionFounding.found` refuses before any cost is ever consulted — and it
## refuses by reading `CAP_IS_BORN_TO` off the registry row **this file registers**. A
## profile assembled here would be a dictionary no caller could legally hand the writer:
## `found` returns `kind_cannot_be_founded` at the `is_born_to` check, which is above the
## `institution_id` check that reads the profile at all.
##
## So the alternative was weighed and the SHORTER file won: the profile would be dead code
## with a `founding_cost` and a `standing_cap` in it that nothing could ever charge.
##
## ## What a clan CAN be, and the answer is authored per house rather than per kind
##
## A clan authors `founding_bloodline`, `ranks` and `standing_bands`, which is a lineage's
## own inheritance vocabulary — **not** a founding act. `CAP_IS_BORN_TO` is the flag that
## says so, and it is the ONLY place that answer is written, so no second `can_found` flag
## exists here that could disagree with it.
##
## Deliberately ABSENT, each for a stated reason rather than by omission:
##
##   - `teaches` — a clan has no doctrine and no fit axis. `ClanGate`'s eighth verb
##     `recognised_at_least` reads the recognition HINGE, which is `standing` scaled by
##     the member's purity, and that is not transmission: ADR 0084's fit is a GATE
##     projecting zero modifiers, and a house that authored no floor would let the flag
##     decide rather than the clan.
##   - `has_territory` — `ClanDef.rival_clans` is authored antagonism (ADR 0085's
##     declaration of sides), not a claim over ground. `ClanDef` has no territory field and
##     inventing one to satisfy the flag would be a content type authored for a capability
##     the clan does not have.
##   - `has_offices` — `ranks` is a list of published ids, not the `InstitutionPositionDef`
##     an office is. A clan cannot be founded so nothing is ever seated in one, and the
##     flag would claim a shape this def does not have.

## The registry id a clan is REGISTERED under (ADR 0271). **Not a container**: the tiers
## are peers, and a clan is not a thing a sect or a nation holds.
const KIND := &"clan"

## The def class a `clan` kind's registry row names. Loaded HERE, in the module that owns
## the def, because `core/` may not resolve a path into `modules/` — `InstitutionRegistry`
## states the same rule for the same reason.
const DEF_SCRIPT := preload("res://src/modules/clan/clan_def.gd")
## The `class_name` that script declares — a label a panel prints and a save may carry.
const DEF_TYPE := "ClanDef"

## `is_born_to`, aliased so `ClanApi` names the flag rather than repeating a bare id.
## `InstitutionRegistry` owns the string; this is one value under a second spelling.
const CAP_IS_BORN_TO := InstitutionRegistry.CAP_IS_BORN_TO

## What a CLAN may do, as the registry's closed capability flags. Declared HERE because
## `core/` may not name `clan` and the row is the only place the answer is written.
const CAPABILITIES: Array[StringName] = [CAP_IS_BORN_TO]


## The registry a clan row is read from, and why `clan` registers it itself.
##
## `InstitutionFounding.found` takes a registry as an ARGUMENT rather than reaching for a
## global, because "which kinds exist" is a fact about one boot. **Nothing ships the `clan`
## row**: `InstitutionBoot.install()` discovers `.tres` under `res://data/institutions/` and
## `ClanCatalog` loads `res://data/clans/` on its own `ClanDef` class, so the boot cannot see
## it — and `install()` itself has no production caller yet (DEF-0326). A tier that cannot
## answer its own capability question would be refused `unknown_kind` by every caller, which
## is the invented default the registry exists to refuse.
##
## So the module that OWNS the declaration registers it, **into the shared instance and only
## when the row is absent**: whoever gets there first wins, there is exactly one `clan` row
## per process, and a `clear()` by a suite leaves the next call to re-register rather than to
## fail. A later wiring of the boot needs no change here.
static func registry() -> InstitutionRegistry:
	var shared := InstitutionRegistry.instance()
	if not shared.knows(KIND):
		shared.register(KIND, DEF_TYPE, CAPABILITIES, DEF_SCRIPT)
	return shared
