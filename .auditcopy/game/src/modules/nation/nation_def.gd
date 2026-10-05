class_name NationDef
extends Resource

## One authored polity: a set of offices, a claim over places, and an initial
## board. A nation is the tier that answers "whose law am I under, and who holds
## the seats?" (ADR 0083), and the seats are the whole point: they may be vacant.
##
## It lives in `modules/`, not `contracts/`, because it is an authored content type
## an author fills in as a `.tres`. It carries an `InstitutionClaim` because ADR
## 0083 makes that the one vocabulary all three tiers speak — but the nation's own
## claim is the POLITY's standing, not a member's: a seat's holder standing lives
## in the ledger under `offices`, and `claim` here is what the nation itself has
## earned and can lose.
##
## ## A nation is made of many sects and clans that were never related
##
## The three tiers are not nested. `sect_ids` names who fills the seats from —
## which is the whole content of the `nation -> sect` edge, and it is a list of
## **ids**, never a reference, so no module edge exists in the data either.

@export var id: StringName = &""
@export var display_name: String = ""
@export var description: String = ""
## The seats this polity authors. **A seat with a `""` holder is authored as
## vacant and must stay that way in content** — that is how the vacancy the
## succession design exists to make legible is representable at all.
@export var offices: Array[NationOfficeDef] = []
## The claims over places this polity authors, by id. Ids, never sub-resources:
## a territory claim is content the polity holds rather than a place, and ADR 0085
## gives it no yield, upkeep or combat bonus of its own.
@export var territory_ids: Array[StringName] = []
## Which sects may fill the seats. Ids, never `SectDef` references.
@export var sect_ids: Array[StringName] = []
## The polity's own claim: its earned standing and what it owes (ADR 0083).
@export var claim: InstitutionClaim = null
## The authored initial board: office id → holder actor id string. A seat an author
## leaves out of this map is authored and unfilled, which is exactly how the
## vacancy the succession design exists to make legible is representable in
## content. Never write a `0` or a `"-"` in place of a holder — `""` IS the value.
@export var initial_offices: Dictionary = {}
@export var tags: Array[StringName] = []

## Who this polity acts FIRST among the institutions competing for one period's
## budget (BL-0198). **An integer, because the tie-break is structural and no
## generator is consulted**: candidates sort by `(act_priority, institution_id)` and
## `institution_id` is a `StringName`, so the second key is lexicographic and total —
## ties are impossible by construction, so no seed has to be saved and a test can run
## the identical walk a hundred times and get identical output. Higher acts sooner; it
## is an ORDER, never a magnitude, and it is never multiplied by anything.
@export var act_priority: int = 0


## The polity's own claim, created on demand. Never null after this call, so no
## caller has to null-check a `.tres` field an author may simply have left empty.
func own_claim() -> InstitutionClaim:
	if claim == null:
		claim = InstitutionClaim.new()
	return claim


## Every authored seat id, canonically ordered. Including the vacant ones: the
## seat exists, and its being unfilled is a property of the board rather than a
## gap in the content.
func office_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for office in offices:
		if office != null and office.id != &"":
			out.append(office.id)
	out.sort()
	return out


## One seat definition, or null when this polity authors no such seat.
func office_definition(office_id: StringName) -> NationOfficeDef:
	for office in offices:
		if office != null and office.id == office_id:
			return office
	return null


## The authored initial board: office id → holder actor id string. Every authored
## seat is present, and one an author left out maps to `""` — a seat that exists
## and whose value is absent (ADR 0083), which is the middle state and never a
## missing row.
func board() -> Dictionary:
	var out := {}
	for office_id in office_ids():
		out[String(office_id)] = ""
	for office_id in initial_offices.keys():
		if not out.has(String(office_id)):
			continue
		var holder = initial_offices[office_id]
		if holder is String:
			out[String(office_id)] = String(holder)
	return out


## The seat ids this polity authors with nobody holding them, canonically ordered.
## The initial board: a new polity is expected to have at least one, because a
## board with every seat filled has nothing to succeed to.
func vacant_office_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	var board_rows := board()
	for office_id in board_rows.keys():
		if String(board_rows[office_id]) == "":
			out.append(StringName(office_id))
	out.sort()
	return out
