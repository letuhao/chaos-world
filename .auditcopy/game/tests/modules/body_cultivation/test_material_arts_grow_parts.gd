extends TestCase

## ## PROPERTIES 3 AND 4 — MULTIPLE MATERIAL ARTS, AND THEY GROW A PART
##
## Property 3: metals, woods/fiber, beast bone, mineral/crystal, blood/essence —
## five MATERIALS, and each turns matter into body differently.
## Property 4: a material art does not buff an arm. It BUILDS a limb the body did
## not have, which is the literal "destroy and recreate" payoff the owner's
## injury system depends on.
##
## ## Why "grow a part" is the right reading of the brief
##
## "Not buff the arm — grow one" is unambiguous about the SHAPE: the part must be
## absent before the art and present after. That is what `BodyPractice.has_part`
## asks, and this suite asserts the transition rather than a magnitude, because a
## magnitude could have come from a stat line.
##
## ## Coordination with the injury program, asserted rather than assumed
##
## A rebuilt limb is denominated in `body_integrity` — the same reservoir the
## injury ledger already measures severity in (`BodyWounds.add` divides damage by
## that pool's `maximum`) — so the two systems share a currency without either
## owning a second copy of it. The reverse edge (an amputation removing a part
## this module grew) is NOT built here: that is the injury program's to own, and
## the request is recorded in `docs/deferred.jsonl`.

const METAL := &"metal_flesh"
const WOOD := &"wood_tendon"
const BONE := &"bone_pillar"
const MINERAL := &"crystal_lens"
const BLOOD := &"essence_heart"


func _actor() -> Actor:
	var actor := Actor.new(&"shaper", {Stat.PHYSIQUE: 20.0})
	actor.set_path(PathState.new(BodyPath.PATH_ID, &"primordial_origin"))
	BodyCultivationApi.attach(actor)
	BodyCultivationApi.attach_acupoints(actor)
	ItemsApi.attach(actor, 128)
	BodyTraining.synchronize(actor)
	return actor


func _ledger(actor: Actor) -> BodyPractice:
	return actor.component(BodyCultivationApi.PRACTICE_ID)


## Give the body the material the named art wants. Through `ItemsApi`, so the cost
## really moves and the refusal tests below measure something.
func _stock(actor: Actor, art_id: StringName) -> void:
	var art := MaterialArtCatalog.find(art_id)
	var def := ItemDef.new()
	def.id = art.material_item
	def.stackable = true
	def.max_stack = 9999
	ItemsApi.inventory(actor).add(def, art.material_cost * 4)


## ## PROPERTY 3 — FIVE MATERIALS, FIVE ARTS, FIVE PARTS
##
## The brief names the materials. A suite that asserted "more than one" would pass
## on two arts over the same substance — the exact failure the requirement exists
## to prevent — so this walks the catalog and checks the MATERIAL set by name.
func test_five_kinds_of_material_art_ship_over_five_materials() -> void:
	var materials := MaterialArtCatalog.materials()
	for required in [&"metal", &"wood", &"bone", &"mineral", &"blood"]:
		assert_eq(materials.has(required), true, "an art is practised on %s" % required)
	assert_eq(materials.size(), 5, "exactly the five the brief names, no duplicates")


## Each art transforms into a DIFFERENT part, so two arts are two answers to the
## "what may a body become" question rather than one answer wearing five hats.
func test_each_art_grows_a_different_part() -> void:
	var arts := MaterialArtCatalog.all()
	var parts := {}
	for art in arts:
		assert_ne(art.transforms_into, &"", "%s names a part to build" % art.id)
		parts[String(art.transforms_into)] = String(art.material)
	assert_eq(parts.size(), arts.size(), "no two arts share a part")


## ## PROPERTY 4 — THE ART GROWS A LIMB THE BODY NEVER HAD
##
## Before the reshape the limb is ABSENT, not zero; after it, the body holds it.
## `created` is the module's own answer to "was this an act of creation", and the
## flag and the presence are asserted separately so a half-implementation cannot
## satisfy both.
func test_a_reshape_creates_a_part_the_body_never_had() -> void:
	var actor := _actor()
	var art := MaterialArtCatalog.find(METAL)
	var ledger := _ledger(actor)
	assert_eq(
		ledger.has_part(art.transforms_into),
		false,
		"before: the body does not have %s" % art.transforms_into
	)
	_stock(actor, METAL)
	var report := BodyMaterialArt.reshape(actor, METAL)
	assert_eq(bool(report["ok"]), true, "the reshape landed: %s" % report["reason"])
	assert_eq(bool(report["created"]), true, "and it reports CREATION, not a buff")
	assert_eq(ledger.has_part(art.transforms_into), true, "after: the body HAS the part")
	var part: BodyPart = ledger.part(art.transforms_into)
	assert_eq(part.id, art.transforms_into, "the part is the one the art names")
	assert_eq(part.art_id, METAL, "and it records which art built it")
	assert_eq(part.rebuilds, 1, "a body built this limb once")


## Reshaping again is a REBUILD, not a second limb: one part, counted. This is the
## "no two sources of truth for the same missing arm" rule made executable.
func test_a_second_reshape_rebuilds_rather_than_duplicating() -> void:
	var actor := _actor()
	# Two reshapes in a row, with the DERIVED stat re-read between them: an author
	# added `BodyRealmSeed.integrity_maximum` per realm, so a second reshape charges
	# a deeper price than the first. Re-reading a derived value mid-transaction is the
	# actor being restored mid-run, not a test artifact.
	var pool := actor.resource(BodyStats.BODY_INTEGRITY)
	pool.change(160.0)
	_stock(actor, METAL)
	BodyMaterialArt.reshape(actor, METAL)
	actor.mark_stats_dirty()
	var art := MaterialArtCatalog.find(METAL)
	_stock(actor, METAL)
	var report := BodyMaterialArt.reshape(actor, METAL)
	assert_eq(bool(report["created"]), false, "the second reshape is a rebuild")
	var ledger := _ledger(actor)
	assert_eq(ledger.parts.size(), 1, "still exactly one part")
	assert_eq(ledger.part(art.transforms_into).rebuilds, 2, "rebuilt twice")


## All five arts run on one body and all five produce their part. The loop is five
## independent questions, not one question asked five ways.
func test_every_authored_art_creates_its_own_part() -> void:
	var actor := _actor()
	var ledger := _ledger(actor)
	for art in MaterialArtCatalog.all():
		_stock(actor, art.id)
		assert_eq(
			ledger.has_part(art.transforms_into), false, "%s: the part is absent before" % art.id
		)
		var report := BodyMaterialArt.reshape(actor, art.id)
		assert_eq(bool(report["ok"]), true, "%s reshaped: %s" % [art.id, report["reason"]])
		assert_eq(ledger.has_part(art.transforms_into), true, "%s grew its part" % art.id)
	assert_eq(ledger.parts.size(), 5, "five arts, five parts")


## Art mastery, like weapon mastery, advances by USING the art — and the arts are
## independent, so a body deep in bone has not thereby advanced in crystal.
func test_art_mastery_advances_only_for_the_art_practised() -> void:
	var actor := _actor()
	_stock(actor, BONE)
	var ledger := _ledger(actor)
	var before := ledger.art_level(BONE)
	var report := BodyMaterialArt.reshape(actor, BONE)
	assert_eq(bool(report["ok"]), true, "the bone art reshaped")
	assert_eq(ledger.art_level(BONE) > before, true, "its own mastery rose")
	assert_eq(ledger.art_level(METAL), 0.0, "the metal art is still at zero")
	assert_eq(ledger.art_level(MINERAL), 0.0, "and so is the crystal art")


## ## PROPERTY 5 (part two) — THE PART IS NOT FREE
##
## The liability: reshaping costs integrity from the body's own reservoir, and the
## grown limb is denominated in the same currency a wound spends. Without this the
## art is pure upside and the system violates the yin-yang rule at the one place it
## is most tempting.
func test_a_reshape_drains_integrity_and_stands_in_the_wound_currency() -> void:
	var actor := _actor()
	var art := MaterialArtCatalog.find(MINERAL)
	var pool := actor.resource(BodyStats.BODY_INTEGRITY)
	pool.change(60.0)
	var before := pool.current
	_stock(actor, MINERAL)
	var report := BodyMaterialArt.reshape(actor, MINERAL)
	assert_eq(bool(report["ok"]), true, "the crystal art reshaped")
	assert_almost_eq(pool.current, before - art.price_drain, "the authored drain was paid")
	assert_eq(float(report["drain"]), art.price_drain, "the report names the price")
	var part: BodyPart = _ledger(actor).part(art.transforms_into)
	assert_eq(part.integrity < before, true, "the grown limb carries its own reserve")
	assert_ne(art.draws_demand, &"", "and a demand the body must keep paying")


## The refusal is all-or-nothing and it is NAMED. A body too spent to reshape keeps
## its material and its integrity — a half-paid reshape would leave a limb made of
## unpaid matter.
func test_a_reshape_refuses_without_paying_anything() -> void:
	var actor := _actor()
	var art := MaterialArtCatalog.find(BLOOD)
	var pool := actor.resource(BodyStats.BODY_INTEGRITY)
	# Spend the reservoir rather than `change(0.0)`: `ResourcePool.change` ADDS, so
	# adding zero left the deep-realm maximum in place and the reshape sailed through.
	# The case under test is a body with NOTHING in the reservoir, so it has to be
	# actually emptied.
	pool.change(-pool.current)
	_stock(actor, BLOOD)
	var held := ItemsApi.inventory(actor).count(art.material_item)
	var report := BodyMaterialArt.reshape(actor, BLOOD)
	assert_eq(bool(report["ok"]), false, "no integrity, no reshape")
	assert_ne(String(report["reason"]), "", "the refusal names itself (ADR 0150)")
	assert_eq(pool.current, 0.0, "nothing was drained")
	assert_eq(
		ItemsApi.inventory(actor).count(art.material_item),
		held,
		"and the material was not consumed"
	)
	assert_eq(_ledger(actor).has_part(art.transforms_into), false, "no part was grown")
