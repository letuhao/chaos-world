class_name SectFixtureCatalog
extends RefCounted

## A test-local stand-in for `SectCatalog`, holding `SectDef` / `SectPositionDef`
## built in code. The module reads content through the catalog singleton, and the
## shipped content tree is authored independently of this suite, so the logic tests
## install their own catalog for the duration of a test instead of depending on
## which `.tres` files happen to exist.
##
## The fixtures use a reserved `t_` id prefix so they can never collide with a real
## authored sect or position, and `teardown()` restores whatever catalog the process
## held beforehand — including the case where it held none.
##
## ## What this file also holds
##
## `SectCatalog` and `SectDoctrineCatalog` each read their own `.tres` tree and both
## have a singleton, so both are swapped for the span of one test. `install()` swaps
## the sect catalog only — a case about a walk never wants a doctrine, and a case
## about a lesson never wants a sect — and `install_doctrine()` is its counterpart.
## `teardown()` restores both, because a doctrine left installed would keep answering
## `found` for a sect that is no longer there.
##
## Nothing here is a production path: `SectCatalog.shared` is swapped only for the
## span of one test, and a test that forgets to restore cannot affect its siblings
## because they install their own.
##
## `install()` reaches into the catalog's private `_sects` / `_positions` / `_loaded`
## members, exactly as `DestinyFixtureCatalog` and `BloodlineFixtureCatalog` do — the
## catalog has no public way to register content, and adding one would widen the
## module's surface for a test's benefit only.


## A member with enough fit to clear `sect_id`'s own `min_purity` door, so a case
## about a gate FURTHER down the path reaches it.
##
## ## Why this exists rather than each case seeding its own fit
##
## `teach` evaluates its gates in an authored order — teacher, then the sect's door,
## then the comprehension band, then the tax — and reports the first unmet one. That
## order is correct: a panel is told one unmet condition, and the one a fixture failed
## to satisfy is the one it is told. But it means a case whose subject is the
## comprehension band, seeded with a student at fit zero, never *reaches* that band:
## it reads `standing_below_floor` and looks like a failure of the code under test.
##
## A student is therefore given exactly the sect's own door, and nothing more — one
## point clear of `min_purity`, so the case cannot accidentally depend on fit it did
## not author.
static func admit_student(actor: Actor, sect_id: StringName, doctrine_id: StringName) -> Actor:
	var def := SectCatalog.instance().sect_definition(sect_id)
	var door := 0 if def == null else maxi(0, def.min_purity)
	var ledger := SectApi.state(actor)
	(ledger["fit"] as Dictionary)[String(doctrine_id)] = door + 1
	actor.set_module_data(SectState.MODULE_KEY, ledger)
	SectApi.attach(actor)
	return actor


## An office with no allowlist at all: the ordinary member, who is sworn to something
## and holds no office. Recognition begins where office begins (ADR 0064).
static func bare_position(position_id: StringName) -> SectPositionDef:
	var def := _position(position_id)
	def.capacity = 0
	return def


## An office whose authored cap is 1 — the seat whose refusal is `seat_occupied`.
static func seat(position_id: StringName, floor: int = 10) -> SectPositionDef:
	var def := _position(position_id)
	def.capacity = 1
	def.standing_floor = floor
	def.standing_percent_stats = {Stat.INSIGHT_GAIN: 0.0}
	return def


## An office whose authored cap is above 1 — the room whose refusal is
## `capacity_full`. The cap is the argument rather than a constant so a case can
## fill it and a case can leave it open.
static func room(position_id: StringName, capacity: int, floor: int = 5) -> SectPositionDef:
	var def := _position(position_id)
	def.capacity = capacity
	def.standing_floor = floor
	def.standing_percent_stats = {Stat.MAX_HEALTH: 0.0}
	return def


## An office that recognises two stats, so a case can prove the projection lands on
## the allowlist and touches nothing outside it.
static func wide_position(
	position_id: StringName, capacity: int = 1, floor: int = 0
) -> SectPositionDef:
	var def := _position(position_id)
	def.capacity = capacity
	def.standing_floor = floor
	def.standing_percent_stats = {Stat.MAX_HEALTH: 0.0, Stat.POISE: 0.0, Stat.DEFENSE_PHYSICAL: 0.0}
	return def


## An office carrying authored duties and authorities, so the gate has something
## real to ask and nothing has to be ranked.
static func office_with_authority(
	position_id: StringName, duties: Array[StringName], authorities: Array[StringName]
) -> SectPositionDef:
	var def := seat(position_id)
	def.duties = duties
	def.authorities = authorities
	return def


## An office whose seat changes hands by an AUTHORED walk, so a succession case has a
## real method to walk rather than a constant it wrote down itself.
##
## `method` is the argument rather than a per-builder constant because the whole
## content wave is exactly three methods and a case that hard-coded one of them
## could not ask "does a different method walk differently".
static func walkable_position(
	position_id: StringName,
	method: StringName = SectPositionDef.SUCCESSION_TRIAL,
	floor: int = 40,
	capacity: int = 1,
	periods: int = 1,
	teach_tax: float = 1.0
) -> SectPositionDef:
	var def := _position(position_id)
	def.capacity = capacity
	def.standing_floor = floor
	def.succession_method = method
	def.succession_periods = periods
	def.teach_tax = teach_tax
	def.standing_percent_stats = {Stat.INSIGHT_GAIN: 0.0}
	return def


## An office whose succession names an appointment this module does NOT walk
## (`seniority`, `named`, `inherited`). A walk verb has to refuse these by name
## rather than treating an unknown method as an instantly-completed walk.
static func unwalkable_position(
	position_id: StringName, method: StringName = SectPositionDef.SUCCESSION_NAMED, floor: int = 10
) -> SectPositionDef:
	var def := _position(position_id)
	def.capacity = 1
	def.standing_floor = floor
	def.succession_method = method
	def.standing_percent_stats = {Stat.INSIGHT_GAIN: 0.0}
	return def


static func _position(position_id: StringName) -> SectPositionDef:
	var def := SectPositionDef.new()
	def.id = position_id
	def.display_name = String(position_id)
	def.description = "A fixture office."
	def.standing_floor = 0
	def.capacity = 1
	def.duties = [&"t_fixture_duty"]
	def.authorities = [&"t_fixture_authority"]
	def.succession_method = SectPositionDef.SUCCESSION_TRIAL
	def.succession_param = {"stage_keeper": "t_fixture_ring"}
	def.succession_periods = 1
	def.teach_tax = 1.0
	def.standing_percent_stats = {}
	def.patronage_per_period = 1
	def.duty_per_period = 1
	return def


## A sect with the offices given, and the fields a case cares about. Defaults
## `min_purity` to 0 so an ordinary case is not accidentally teaching-gated, and
## `standing_cap` to 100 so a percentage is readable without arithmetic.
##
## `founding_cost` is authored `{found, outstanding}` because that is the shape the
## founding verb reads; `currency` is carried through untouched so a panel can render
## the price in the coin the author wrote.
static func sect(
	sect_id: StringName,
	positions: Array[SectPositionDef],
	cap: int = 100,
	min_purity: int = 0,
	founding: int = 10
) -> SectDef:
	var def := SectDef.new()
	def.id = sect_id
	def.display_name = String(sect_id)
	def.description = "A fixture sect."
	def.doctrine_id = StringName("%s_doctrine" % sect_id)
	def.positions = positions
	def.min_purity = min_purity
	def.standing_cap = cap
	def.founding_cost = {
		"currency": "silver",
		"amount": founding,
		"found": founding,
		"outstanding": founding,
	}
	var top := def.top_position()
	def.top_position_id = &"" if top == null else top.id
	return def


## A doctrine with every field a teaching case touches. The defaults are a doctrine
## that is cheap to learn and easy to teach, so a case asserts the RULE rather than
## an arithmetic it wrote down itself.
static func doctrine(
	doctrine_id: StringName,
	affinity_floor: int = 20,
	floor: float = 5.0,
	span: float = 60.0,
	fit_per_period: int = 3,
	teach_tax: float = 1.0
) -> SectDoctrineDef:
	var def := SectDoctrineDef.new()
	def.id = doctrine_id
	def.display_name = String(doctrine_id)
	def.description = "A fixture doctrine."
	def.teachings = [&"t_fixture_practice"]
	def.refusals = [&"t_unready"]
	def.comprehension_floor = floor
	def.comprehension_span = span
	def.affinity_floor = affinity_floor
	def.fit_per_period = fit_per_period
	def.teach_tax = teach_tax
	return def


## The catalog every logic suite installs: one sect holding one seat, one room and
## one unbounded office, so `seat_occupied`, `capacity_full` and the ordinary
## member are all reachable without a case building content of its own.
static func default_sect() -> SectDef:
	return sect(
		&"t_house",
		[bare_position(&"t_member"), seat(&"t_steward", 60), room(&"t_reader", 3, 20)],
		100,
		25
	)


## A sect whose top office is one a SUCCESSION can actually reach, so a founding
## case does not have to build its own board to have somewhere to seat a founder.
static func foundable_sect(sect_id: StringName = &"t_foundry") -> SectDef:
	return sect(
		sect_id,
		[
			bare_position(&"t_member"),
			walkable_position(&"t_reader", SectPositionDef.SUCCESSION_APPOINTED, 20, 3),
			walkable_position(&"t_steward", SectPositionDef.SUCCESSION_TRIAL, 60, 1),
		],
		100,
		10,
		25
	)


## The doctrine the fixture sect teaches: `t_house`'s `doctrine_id` is derived from
## the sect id, so this is the id a case gets without ever writing it down.
static func default_doctrine() -> SectDoctrineDef:
	return doctrine(default_sect().doctrine_id)


## A second sect, so `join` has somewhere to be refused for and a member can be
## shown leaving one institution for another.
static func rival_sect() -> SectDef:
	return sect(&"t_rival_house", [seat(&"t_rival_steward", 50)], 80)


## Replace the module's catalog singleton with one built from `defs`, for the
## duration of one test.
static func install(defs: Array[SectDef] = []) -> void:
	var catalog := SectCatalog.new()
	var fallback: Array[SectDef] = [default_sect()] if defs.is_empty() else defs
	for def in fallback:
		catalog._sects[String(def.id)] = def
		for position_id in def.position_ids():
			catalog._positions[String(position_id)] = StringName(def.id)
	catalog._loaded = true
	SectCatalog.shared = catalog


## Replace the module's doctrine catalog with one built from `defs`. Separate from
## `install` on purpose: a succession case has no business installing a doctrine,
## and swapping both from one call would make every suite quietly depend on content
## it never asked for.
static func install_doctrine(defs: Array[SectDoctrineDef] = []) -> void:
	var catalog := SectDoctrineCatalog.new()
	# Built by append rather than by a ternary: `[default_doctrine()]` infers a
	# plain `Array`, and assigning that to a typed `Array[SectDoctrineDef]` is a
	# runtime type error, not a warning. The loop keeps one type throughout.
	var fallback: Array[SectDoctrineDef] = []
	if defs.is_empty():
		fallback.append(default_doctrine())
	else:
		fallback.append_array(defs)
	for def in fallback:
		catalog._doctrines[String(def.id)] = def
	catalog._loaded = true
	SectDoctrineCatalog.shared = catalog


## Undo both `install` calls. The real catalogs are what the singletons lazily
## rebuild when `shared` is null, so a restored test that needs real authored content
## simply has none installed.
static func teardown() -> void:
	SectCatalog.shared = null
	SectDoctrineCatalog.shared = null
