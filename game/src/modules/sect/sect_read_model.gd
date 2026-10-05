class_name SectReadModel
extends RefCounted

## The **read side** of `sect`: how a ledger, an office, a doctrine and a sect are
## shaped for a panel. Extracted from `SectApi` because that file passed the
## thousand-line ceiling, and because these are not verbs — they answer no
## question about the world and take no action, so putting them behind a facade
## would have spent the module's public surface on formatting.
##
## ## These are PUBLISHED VALUES, not recomputations
##
## A schism publishes the **bill that was charged**, and a standoff publishes the
## prize that was declared, rather than either being re-derived from the inputs
## (ADR 0085: what the two sides agreed is the authority, and a display that
## re-derives it can drift from what was paid). Everything here follows that
## rule: read the line, do not rebuild it.
##
## ## `{}` is a real answer, not a missing one
##
## A member who joined rather than founded has no roster, and a member who has
## declared no split has no schisms. Both answer `{}` — ADR 0083's first state,
## "this does not exist" — and neither is an error. The middle state is spelled
## `"vacant": true` by `_succession_view`, never inferred from a blank string.


## The roster as a screen reads it: office id to member ids, plus the size.
## `{}` for a member who joined rather than founded — this ledger knows no
## roster, which is ADR 0083's open question rather than an empty institution.
static func roster_view(ledger: Dictionary) -> Dictionary:
	var out := {}
	var total := 0
	for position_id in SectState.roster(ledger).keys():
		var row = SectState.roster(ledger)[position_id]
		if not (row is Array):
			continue
		var ids: Array = []
		for member_id in row as Array:
			ids.append(String(member_id))
		out[String(position_id)] = ids
		total += ids.size()
	if not out.is_empty():
		out["size"] = total
	return out


## The declared splits as a screen reads them: the seceding sect id to the bill.
##
## The **bill** is published next to the declaration rather than recomputed from
## it, for the same reason `NationApi`'s standoff publishes its prize verbatim: what
## the two sides agreed to is the authority, and a display that re-derives it can
## drift from what was paid. `{}` for a member whose ledger holds none, which is
## ADR 0083's first state rather than an error.
static func schism_view(ledger: Dictionary) -> Dictionary:
	var out := {}
	for seceding_id in SectState.schisms(ledger).keys():
		var row := SectState.schism(ledger, StringName(seceding_id))
		if row.is_empty():
			continue
		out[String(seceding_id)] = row.duplicate(true)
	return out


## The walk on one office, as a board screen reads it: which side of the walk the
## seat is on, how far through it is, how many authored stages there are, and —
## for an empty seat — `"vacant": true`, which is ADR 0083's middle state spelled
## out rather than inferred from a blank string.
static func succession_view(ledger: Dictionary, office: SectPositionDef) -> Dictionary:
	if office == null:
		return {}
	var row := SectSuccession.walk(ledger, office.id)
	var vacant := String(row.get("side", "")) == SectSuccession.VACANT
	return {
		"method": String(office.succession_method),
		"walkable": office.is_walkable_method(),
		"stages": office.stages().size(),
		"walked": SectSuccession.walked_of(ledger, office),
		"periods_required": maxi(0, office.succession_periods),
		"periods_held": int(row.get("held_periods", 0)),
		"vacant": vacant,
		"complete": bool(row.get("complete", false)),
	}


## A doctrine's taught band, its refusals and its costs. `{}` for a doctrine this
## build does not ship, which is the first state again rather than a blank row.
static func doctrine_view(def: SectDoctrineDef) -> Dictionary:
	if def == null:
		return {}
	var band := def.comprehension_band()
	return {
		"id": String(def.id),
		"display_name": def.display_name,
		"teachings": strings(def.teachings),
		"refusals": strings(def.refusals),
		"comprehension_floor": band.x,
		"comprehension_span": band.y - band.x,
		"affinity_floor": def.floor_fit(),
		"fit_per_period": def.fit_per_period,
		"teach_tax": def.teach_tax,
	}


## One sect as a screen reads it, with every authored office nested under
## `positions`. A board renders this without asking the facade for anything else.
##
## `treasury_lines` is the AUTHORED office rates — what content declares, not what a
## member's own ledger currently owes. The live lines, including the opening line the
## generic founding writer opens, come from `summary()["treasury"]`, which reads the
## ledger: this class's own rule is "read the line, do not rebuild it", and a
## reconstructed opening line beside the real one is exactly the drift it refuses.
static func sect_view(def: SectDef) -> Dictionary:
	if def == null:
		return {}
	var offices: Dictionary = {}
	for office in def.positions:
		if office == null or office.id == &"":
			continue
		offices[String(office.id)] = office_view(office)
	var top := def.top_position()
	return {
		"id": String(def.id),
		"display_name": def.display_name,
		"doctrine_id": String(def.doctrine_id),
		"top_position_id": "" if top == null else String(top.id),
		"min_purity": def.min_purity,
		"standing_cap": def.standing_cap,
		"founding_cost": def.founding_cost.duplicate(),
		"treasury_lines": SectFounding.treasury_lines(def),
		"positions": offices,
	}


## One office as a screen reads it: what it may do, what it costs to hold, and how
## it changes hands. `duties` and `authorities` are authored ids, published
## verbatim — a panel decides for itself what `judge_dispute` means (ADR 0084).
static func office_view(office: SectPositionDef) -> Dictionary:
	return {
		"id": String(office.id),
		"display_name": office.display_name,
		"capacity": office.capacity,
		"standing_floor": office.standing_floor,
		"succession_method": String(office.succession_method),
		"succession_param": office.succession_param.duplicate(),
		"succession_periods": office.succession_periods,
		"walkable": office.is_walkable_method(),
		"walk_stages": office.stages().size(),
		"duties": strings(office.duties),
		"authorities": strings(office.authorities),
		"standing_percent_stats": office.standing_percent_stats.duplicate(),
		"patronage_per_period": office.patronage_per_period,
		"duty_per_period": office.duty_per_period,
		"teach_tax": office.teach_tax,
	}


## `StringName` arrays as plain `String` arrays, because a summary dictionary
## crosses into `ui/` and ADR 0083's contract is primitives. Called from four
## places above rather than inlined, so the coercion exists once.
static func strings(values: Array[StringName]) -> Array:
	var out: Array = []
	for value in values:
		out.append(String(value))
	return out


## ## The whole read model, in one call
##
## Every read this module owes a screen or a sibling is a key here, folded rather
## than published as its own method — see the class note on why the facade is at
## its cap and why `summary()` is the right shape. `{}` when there is no actor,
## which is the contract a panel tests instead of pixels.
##
## What a caller gets: which sect, who founded it, which office and its authored
## duties and authorities, standing and its share of the cap, what is still owed,
## the treasury's lines, the fit this member has with each doctrine, the bounded
## percent the claim currently projects, **the roster with each office's live seat
## state** — including the `seat_occupied` / `capacity_full` distinction, so a board
## screen renders the difference without re-deriving it — **the walk in progress on
## each seat**, every authored office of the sworn sect, every authored sect for
## comparison, and every authored doctrine.
static func summary(ledger: Dictionary, catalog: SectCatalog) -> Dictionary:
	var out := {
		"has_actor": ledger != null,
		"actor_id": "",
		"is_member": false,
		"founded": false,
		"sect_id": "",
		"sect_name": "",
		"founder_id": "",
		"doctrine_id": "",
		"doctrine_name": "",
		"position_id": "",
		"position_name": "",
		"standing": 0,
		"standing_cap": 0,
		"standing_ratio": 0.0,
		"standing_percent": 0.0,
		"granted_percent": {},
		"min_purity": 0,
		"teaches": false,
		"fit": {},
		"obligations": {},
		"settled": true,
		"treasury": {},
		"roster": {},
		"roster_size": 0,
		"duties": [],
		"authorities": [],
		"can_promote": {},
		"schisms": {},
		"schism_count": 0,
		"sects": {},
		"doctrines": {},
	}
	var sect_id := SectState.institution(ledger)
	out["is_member"] = SectState.is_affiliated(ledger)
	out["founded"] = SectFounding.founded(ledger)
	out["sect_id"] = String(sect_id)
	out["founder_id"] = SectState.founder(ledger)
	out["position_id"] = String(SectState.position(ledger))
	out["standing"] = SectState.standing(ledger)
	out["standing_cap"] = int(ledger["standing_cap"])
	out["standing_ratio"] = SectState.claim(ledger).normalized()
	out["standing_percent"] = InstitutionClaim.standing_percent(SectState.standing(ledger))
	out["granted_percent"] = (ledger["granted_percent"] as Dictionary).duplicate()
	out["fit"] = (ledger["fit"] as Dictionary).duplicate()
	out["obligations"] = (ledger["obligation"] as Dictionary).duplicate()
	out["settled"] = SectState.claim(ledger).settled()
	out["treasury"] = (ledger["treasury"] as Dictionary).duplicate()
	out["roster"] = SectReadModel.roster_view(ledger)
	# The declared splits, folded in rather than published as a thirteenth method.
	# A panel rendering a schism screen reads the whole declaration from one call,
	# exactly as it reads the roster and the walk from the same payload.
	out["schisms"] = SectReadModel.schism_view(ledger)
	out["schism_count"] = (out["schisms"] as Dictionary).size()
	for doctrine_id in (ledger["fit"] as Dictionary).keys():
		var sworn := catalog.sect_definition(sect_id)
		if sworn == null:
			continue
		out["teaches"] = sworn.teaches_at(int((ledger["fit"] as Dictionary)[doctrine_id]))
	var def := catalog.sect_definition(sect_id)
	if def != null:
		out["sect_name"] = def.display_name
		out["doctrine_id"] = String(def.doctrine_id)
		out["min_purity"] = def.min_purity
		var doctrine := SectDoctrineCatalog.instance().doctrine(def.doctrine_id)
		out["doctrine_name"] = "" if doctrine == null else doctrine.display_name
		var office := def.position(SectState.position(ledger))
		if office != null:
			out["position_name"] = office.display_name
			out["duties"] = SectReadModel.strings(office.duties)
			out["authorities"] = SectReadModel.strings(office.authorities)
	# Every authored sect is listed whatever the actor is, so a screen can compare
	# institutions without a second call; `sworn` is the only thing that differs.
	for authored_id in catalog.sect_ids():
		out["sects"][String(authored_id)] = SectReadModel.sect_view(
			catalog.sect_definition(authored_id)
		)
	for authored in SectDoctrineCatalog.instance().doctrine_ids():
		out["doctrines"][String(authored)] = SectReadModel.doctrine_view(
			SectDoctrineCatalog.instance().doctrine(authored)
		)
	if def == null:
		return out
	var teaching_doctrine := SectDoctrineCatalog.instance().doctrine(def.doctrine_id)
	for office in def.positions:
		if office == null or office.id == &"":
			continue
		var room := def.position(office.id)
		# `held` is counted from THIS ledger's roster rather than passed in: an
		# argument is a number a caller can be wrong about, and the whole point of
		# BL-0176 is that the count is authored content read against authored
		# content. A member whose ledger holds no roster (anyone who joined rather
		# than founded) reads 0, which is the honest answer for "how many members
		# does MY ledger know about" — and the refusal still names the office.
		var held := SectState.roster_held(ledger, office.id, room)
		out["roster_size"] = int(out["roster_size"]) + held
		var seat := def.seat_state(office.id, held)
		out["can_promote"][String(office.id)] = {
			"id": String(office.id),
			"display_name": office.display_name,
			"capacity": office.capacity,
			"standing_floor": office.standing_floor,
			"below_floor": SectState.standing(ledger) < office.standing_floor,
			"held": held,
			"has_room": bool(seat["has_room"]),
			"reason": String(seat["reason"]),
			# The walk, read from the ledger rather than re-derived: a board screen
			# renders a vacancy without ever learning how the succession advances.
			"succession": SectReadModel.succession_view(ledger, office),
			# `SectTeaching.tax_for` is a null-receiver on a doctrine this build does
			# not ship, so the office's own authored tax is the fallback. A missing
			# doctrine must not abort the whole summary — a panel still renders the
			"teach_tax":
			(
				# seat it can see.
				SectTeaching.tax_for(teaching_doctrine, office)
				if teaching_doctrine != null
				else office.teach_tax
			),
		}
	return out
