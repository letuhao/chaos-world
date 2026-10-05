class_name InstitutionDef
extends Resource

## One authored organization of ANY kind: what it is called, what offices it holds,
## what standing recognition ranges over, and what founding one costs. The
## generalisation of `SectDef`, `NationDef` and `ClanDef` into ONE type, so a
## trading guild, a hunting guild and a farmers' circle are all authored content
## rather than three modules (ADR 0271).
##
## ## Why a `Resource` in `core/`, and not a contract
##
## It is an `@export`ed authored content type, and Godot cannot `@export` a
## `RefCounted`. `RESOURCE_HOME_UNITS` is `("core", "modules")`, which is exactly why
## `InstitutionClaim` lives here and not in `contracts/`. And `core` is a LAYER, not
## a module, so the cross-module facade rule never applied to it: this file adds zero
## new edges and declares no dependency on `sect`, `clan` or `nation`.
##
## ## `kind` is DECLARED HERE, and this field is the ONLY place it is written
##
## Three answers were weighed. **Derived from the def type** fails outright: `core`
## ships ONE type for every kind, so a guild and a farmers' circle would be one kind
## and would have to share one capability set — the exact thing ADR 0271 says a kind
## exists to stop. **Read from the registry row** makes the def's meaning depend on
## read order: a catalog that has not booted would have no answer for a shipped
## `.tres` at all, which is the invented-default defect `InstitutionRegistry` names
## when it refuses an unknown kind by name. So the field IS the declaration, and it
## travels with the resource: `load()` yields a def and `def.kind` already answers.
##
## **The registry row is a CHECK, never a second source.** [method check] is where the
## two meet, and it refuses a `kind` nobody registered with a NAMED reason
## (`unknown_kind`) — it never loads such a def as a default, never falls back to a
## "generic guild", and never guesses.
##
## ## `capabilities` is the KIND's, so every def of one kind must AGREE
##
## Capabilities belong to a kind, not to an organization, so they cannot live on a
## per-organization field without letting two `.tres` of one kind disagree about one
## fact — two sources of truth for one thing, the failure this whole programme
## exists to remove. So the author declares them once per kind and the boot
## (`InstitutionBoot`) registers the FIRST def of a kind and refuses any later def
## whose set differs. [method check] is the def-side half of that rule; it also
## refuses the two authoring slips that would otherwise be invisible:
## `offices_not_declared` (positions authored, `has_offices` absent) and
## `territory_not_declared` (territory ids authored, `has_territory` absent).
##
## ## The fields, and the ones deliberately NOT here
##
## Taken, because a `found` genuinely needs them or an author genuinely wants them:
## `positions`, `top_position_id`, `standing_cap`, `founder_standing`,
## `founding_cost`, `member_duty_per_period`, `territory_ids`, `tags`, plus identity.
##
## **Deliberately absent**, each because it is either a sibling module's content or a
## field nothing in this programme reads:
##
##   - `doctrine_id` and `min_purity`. Transmission is the `teaches` CAPABILITY and a
##     doctrine is `sect` content; a guild's admission bar is the admitting layer's
##     question and `found` never reads either.
##   - `act_priority`. It belongs to `InstitutionBudget` tiers (`sect`, `nation`), and
##     a guild has no budget rung.
##   - `claim`. A `NationDef`'s own earned standing is the POLITY's, not a member's;
##     a member's claim lives in the ledger `found` writes.
##   - `sect_ids`, `rival_ids`, `ranks` / `standing_bands`. The first two are one
##     module's edges; the last two are a LADDER, and ADR 0064/ADR 0083 keep position
##     an authored id precisely so it never becomes an index.
##
## ## Authority, recognition and power, in that order
##
## An institution grants RECOGNITION, ACCESS and TRANSMISSION, and never power
## (ADR 0084). There is no `percent_modifiers`, no `base_attributes` and no `grants`
## field here, which is the design and not an omission — the whole of the political
## stat surface of the game is `InstitutionClaim.standing_percent`, a bounded percent
## capped by `STANDING_PERCENT_CAP`, and nothing on this class writes a stat. A
## registry row is never serialized either (ADR 0271): a save carries `kind` as a
## plain `String` and nothing else.

## The refusal a def naming no institution reaches. **ALIASED** from the ledger
## rather than restated: "a def with no id" and "a profile with no institution" are
## one fact about one thing, and two constants for it is the ADR 0066 failure mode
## inside the file that exists to stop it.
const R_NO_ID := InstitutionLedger.R_UNKNOWN_INSTITUTION
## The refusal a def naming no kind reaches. Aliasing the registry's own constant, so
## a caller may look the reason up under either name and get one value.
const R_NO_KIND := InstitutionRegistry.R_NO_KIND
## The refusal a def whose kind no boot registered reaches. NEVER a default load: a
## catalog that treated this as "some kind that cannot X" would be gating on an
## institution that does not exist.
const R_UNKNOWN_KIND := InstitutionRegistry.R_UNKNOWN_KIND
## Aliased from the registry: an invented capability name fails where it was written
## rather than at a gate that would silently never fire.
const R_UNKNOWN_CAPABILITY := InstitutionRegistry.R_UNKNOWN_CAPABILITY
## Aliased from the ledger: a kind that authors offices but names no reachable top
## one is the same refusal `found` raises on a profile naming none.
const R_NO_TOP_POSITION := InstitutionLedger.R_NO_TOP_POSITION
## Authored HERE because the registry has no opinion about it: this def carries
## positions and its kind does not declare `has_offices`, so the positions would grant
## nothing and seat nobody. A content bug, named at the place it was written.
const R_OFFICES_NOT_DECLARED := "offices_not_declared"
## The same authoring slip for territory: claims authored under a kind that declares
## no territory, which is exactly the ADR 0085 rule a def can break silently.
const R_TERRITORY_NOT_DECLARED := "territory_not_declared"

## Which KIND this organization is. The one and only declaration of it; see the class
## note for the three options weighed and why this one.
@export var kind: StringName = &""
## What this kind MAY do, by name. Declared on the organization because it is the
## kind's, and every `.tres` of one kind must agree — see the class note and
## `InstitutionBoot.register_def`.
@export var capabilities: Array[StringName] = []

@export var id: StringName = &""
@export var display_name: String = ""
## Clinical and mechanical, in the game's own voice (AGENTS.md).
@export var description: String = ""

## The offices this organization holds. Discretely authored and keyed by `id`, never
## a ladder: `position` is an authored id and never an index (ADR 0083). Empty is a
## legitimate shape for a kind that declares no `has_offices`, and then a founder
## holds thick standing in NO position at all — the state ADR 0064's two-part split
## exists to make expressible.
@export var positions: Array[InstitutionPositionDef] = []
## The office a founder is seated in, by id. **Authored, never derived from array
## order**: a founding is the moment somebody is told which seat they hold, and
## content that answers it by index is content whose answer changes when a row is
## inserted. Empty under `has_offices` is refused by name rather than guessed at.
@export var top_position_id: StringName = &""

## The ceiling `standing` clamps to. Authored here so the political range is content
## rather than a constant buried in a ledger.
@export var standing_cap: int = 100
## The standing a FOUNDER starts on. A named authored integer and never a percent or
## a multiple of the cap: founding already PRICES an organization, so charging the
## founder again for standing inside their own house makes the price of existing an
## infinite regress — while a floor would make founding a demotion and a multiple
## would make it a grant, and ADR 0064's split says it is neither.
@export var founder_standing: int = 0

## What founding one costs, read from the funding pool [method funding_pool] names.
## **A guild that is cheap to found is a bug**, and the zero this clamps to is a
## deliberate way to author a free organization — content, not an accident this class
## has to guess about (`InstitutionFounding.cost` states the same rule).
@export var founding_cost: int = 0
## Periods of `duty_<id>` this organization charges a member who holds NO office at
## all. The counterpart of `founder_standing`'s reasoning: an organization nobody has
## to do anything for has nothing to recognise anybody for.
@export var member_duty_per_period: int = 1

## The places this organization claims, by id. **Ids, never sub-resources.** A claim
## confers nothing — no yield, no upkeep, no combat bonus — and decides only who MAY
## fight and where, which is the whole of ADR 0085's territory rule. Empty means it
## authors no claims at all, which is different from a claim on nothing.
@export var territory_ids: Array[StringName] = []

## Authored category words, the convention every other def in this repo follows
## (`ClanDef.tags`, `NationDef.tags`, `RoomDef.tags`, `NpcDef.tags`). **The one field
## here no founding verb reads**, and it is here on purpose: a content family the
## game cannot filter is the silent skip ADR 0184 forbids, and a modder inventing
## their own vocabulary inside a directory the shipped code cannot query is how that
## skip starts. See [method has_tag].
@export var tags: Array[StringName] = []


## ## The two halves of "is this def loadable", split because they answer different
## questions and one of them can be asked BEFORE a kind exists
##
## [method check_content] is the REGISTERISTRY-FREE half: does what this file
## AUTHOR agree with what this file DECLARES. [method check] is the whole thing,
## content first and then the registry — and the split is not cosmetic: a boot has to
## run `check_content` BEFORE registering a brand-new kind, because `check`'s
## registry half asks whether the kind is registered and a kind nobody has registered
## yet is the normal state of a first `.tres`. Running only `check` would either
## deadlock on that ordering or hand the boot no way to keep a broken `.tres` out of
## the registry — and a live row is more than a warning, because other systems consult
## it.
func check(registry: InstitutionRegistry) -> Dictionary:
	var content := check_content()
	if not bool(content["ok"]):
		return content
	if registry == null:
		return InstitutionLedger.refuse(R_UNKNOWN_KIND)
	if not registry.knows(kind):
		return InstitutionLedger.refuse(R_UNKNOWN_KIND)
	return content


## ## Does what this def AUTHOR agree with what it DECLARES? No registry needed.
##
## Every refusal is eager and knowable from this file alone, and NONE of them repairs
## the def: a corrupt institution is a content bug that must be loud at the boot that
## reads it, not silently defaulted into something that loads.
func check_content() -> Dictionary:
	var fault := _content_fault()
	if fault != "":
		return InstitutionLedger.refuse(fault)
	return (
		InstitutionLedger
		. ok(
			{
				"id": String(id),
				"kind": String(kind),
				"institution": String(id),
				"capabilities": authored_capabilities(),
				"positions": position_ids(),
			}
		)
	)


## ## The first authoring fault in this file, or `""` when there is none
##
## Split out of [method check_content] because that method is a read model and a
## `_content_fault` is the rule: keeping them together made one function carry seven
## `return` statements, which is over gdlint's `max-returns` and is the shape where a
## later edit adds an eighth arm nobody re-reads. Offices and territory share one
## branch because they are the same fault in two shapes — the def authored something
## its own declared capabilities do not cover — and the reason still names which half.
func _content_fault() -> String:
	if id == &"":
		return R_NO_ID
	if kind == &"":
		return R_NO_KIND
	# The set is CLOSED, so a typo fails here rather than reading as a capability the
	# kind quietly lacks (`InstitutionRegistry` states the same rule for `register`).
	for capability in authored_capabilities():
		if not InstitutionRegistry.CAPABILITIES.has(capability):
			return R_UNKNOWN_CAPABILITY
	var fault := ""
	if positions.size() > 0 and not declares_locally(InstitutionRegistry.CAP_HAS_OFFICES):
		fault = R_OFFICES_NOT_DECLARED
	elif territory_ids.size() > 0 and not declares_locally(InstitutionRegistry.CAP_HAS_TERRITORY):
		fault = R_TERRITORY_NOT_DECLARED
	elif declares_locally(InstitutionRegistry.CAP_HAS_OFFICES) and top_position() == null:
		# A kind that AUTHORS offices must name one a founder can be seated in. Absent
		# the flag, an empty top position is the legitimate "no office at all" state and
		# is never a refusal — which is the whole difference between the two.
		fault = R_NO_TOP_POSITION
	if fault != "":
		return fault
	return ""


## Whether this def's OWN authored capability list names `capability`. The
## registry-free read, and the one [method check_content] uses — the question it asks
## is "do the offices I author sit inside the capabilities I declare", which is a
## question about this file and not about any boot.
func declares_locally(capability: StringName) -> bool:
	return authored_capabilities().has(capability)


## Whether this def's kind carries `capability`, read off the REGISTRY rather than
## off this file's own `capabilities` array. The registry is the authority — it is
## what a boot registered and what `found` consults — so a def that asked itself would
## be asking a question whose answer lives somewhere else, and two readers could
## disagree about it.
func declares(registry: InstitutionRegistry, capability: StringName) -> bool:
	if registry == null:
		return false
	return bool(registry.has_capability(kind, capability)["has"])


## This def's authored capabilities, canonically ordered by their STRING value.
## Sorted on `Array[String]` and converted back for the reason
## `InstitutionLedger.sorted_keys` states: `Array[StringName].sort()` is not
## specified to order by string value and the ids are interned, so a list whose order
## is load-bearing must not depend on which id loaded first.
func authored_capabilities() -> Array[StringName]:
	var text: Array[String] = []
	for capability in capabilities:
		if capability != &"":
			text.append(String(capability))
	text.sort()
	var out: Array[StringName] = []
	for entry in text:
		out.append(StringName(entry))
	return out


## Whether this def carries `tag_id`. The one read [member tags] exists for; the
## field is a category vocabulary and a vocabulary nothing queries is a comment.
func has_tag(tag_id: StringName) -> bool:
	return tag_id != &"" and tags.has(tag_id)


## The office under `position_id`, or null. **Null rather than a guess**: an office
## nothing defines seats nobody, gates nothing and cannot be filled, so inventing one
## would hide a content bug behind a working-looking promotion (`SectDef.position`
## states the same reason).
func position(position_id: StringName) -> InstitutionPositionDef:
	if position_id == &"":
		return null
	for def in positions:
		if def != null and def.id == position_id:
			return def
	return null


## Whether this def authors an office under `position_id`.
func has_position(position_id: StringName) -> bool:
	return position(position_id) != null


## Every authored office id, canonically ordered.
func position_ids() -> Array[StringName]:
	var text: Array[String] = []
	for def in positions:
		if def != null and def.id != &"":
			text.append(String(def.id))
	text.sort()
	var out: Array[StringName] = []
	for entry in text:
		out.append(StringName(entry))
	return out


## The office a founder is seated in, or null when this organization authors none.
## **The authored id and nothing else**: an earlier sibling answered this by scanning
## for the highest `standing_floor`, which needed a field no promotion reads and made
## "the top" a number. Here it is a name an author wrote down.
func top_position() -> InstitutionPositionDef:
	return position(top_position_id)


## Whether this organization authors an office a founder could be seated in. The
## refusal `no_top_position` reads off this rather than being written per caller.
func has_top_position() -> bool:
	return top_position() != null


## The places this organization claims, canonically ordered.
func claimed_territories() -> Array[StringName]:
	var text: Array[String] = []
	for place in territory_ids:
		if place != &"":
			text.append(String(place))
	text.sort()
	var out: Array[StringName] = []
	for entry in text:
		out.append(StringName(entry))
	return out


## Whether this organization authors a claim over any place at all. Different from
## claiming nothing in particular: an organization with no claim is not a polity that
## happens to hold nothing today.
func has_territory_claim() -> bool:
	return territory_ids.size() > 0


## The prefix this organization's treasury lines are namespaced under. **Namespaced
## per organization**, because a treasury belongs to a person and two organizations may
## both owe the same actor's save — a line one of them cannot see is a line it cannot
## accidentally settle.
func treasury_prefix() -> String:
	return "treasury_%s_" % String(id)


## The pool a founder funds this organization from. Named here and read through the
## profile, so the sect's own pool and the generic one are visibly different
## currencies and a treasury can never be mistaken for an inventory.
func funding_pool() -> StringName:
	return InstitutionFounding.DEFAULT_FUNDING_POOL


## ## The PROFILE `InstitutionFounding.found` consumes — the whole proof
##
## A plain `Dictionary` of primitives, assembled here and nowhere else, because
## `core/` may not name a `SectDef` (ADR 0271 §2) and a profile is a transient
## argument rather than authored content. **Every key below is one `found` or `write`
## actually reads**, and there is no key nothing reads — which is what makes a modder's
## `.tres` reach the generic founding verb with no GDScript anywhere in the path.
func founding_profile() -> Dictionary:
	var top := top_position()
	var office_lines := {} if top == null else top.obligation_lines()
	return {
		"kind": String(kind),
		"institution_id": String(id),
		"top_position": String(top.id) if top != null else "",
		"standing_cap": standing_cap,
		"founder_standing": founder_standing,
		"founding_cost": founding_cost,
		"funding_pool": String(funding_pool()),
		"treasury": _treasury_lines(),
		"obligation": member_obligation_lines(),
		"office_obligation": office_lines,
	}


## What a member of this organization owes while they hold no office at all. Ids and
## counts only, so a save never carries an authored amount. A zero rate opens NO line
## rather than a line worth zero, because "nobody opened this debt" and "this debt is
## settled" are the same state.
func member_obligation_lines() -> Dictionary:
	if member_duty_per_period <= 0:
		return {}
	return {"duty_%s" % String(id): member_duty_per_period}


## The treasury lines founding opens: one line per office this organization authors
## that carries an authored rate. A `for` over the AUTHORED offices writing into a NEW
## dictionary — the body never grows the array being walked, so the bound is the
## content's own length and there is no shape here for a loop to grow in lockstep with
## its own bound.
##
## Each office's lines are built ONCE and read twice. The first version called
## `obligation_lines()` inside the loop condition and again in the body, which minted
## two dictionaries per office and indexed one of them with a key taken from the other;
## it happened to be deterministic, and "happened to" is the standard both of those
## mistakes share.
func _treasury_lines() -> Dictionary:
	var prefix := treasury_prefix()
	var out := {}
	for office in positions:
		if office == null or office.id == &"":
			continue
		var lines := office.obligation_lines()
		for term_id in InstitutionLedger.sorted_keys(lines):
			out["%s%s" % [prefix, term_id]] = int(lines[term_id])
	return out
