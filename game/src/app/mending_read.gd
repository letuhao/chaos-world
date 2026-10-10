class_name MendingRead
extends RefCounted

## What each of the EIGHT mending avenues can do for the actor's WEAKEST scar, as
## primitives, so a foundation readout renders the whole web in one place (BL-0951 / ADR
## 0939, S15) while each avenue's INVOCATION stays in its own screen.
##
## ## Why this lives in `app/`
##
## The avenues are spread across `items` (the elixir), `heavenly_tribulation` (the rite),
## `domain` (the secret realm), `social` (the master's sacrifice), `foundation` (the
## forbidden art), `destiny` (karmic virtue) and `dual_cultivation` (the aid). No module may
## name the others, so the ONE read that spans them is the composition root's — exactly as
## `RecipeCatalog` and the bridges are. `ui/` then reads it through a screen, never by
## naming a module the read reached.
##
## ## Every row is primitives, and the price is STATED
##
## `{id, available, price, note}`. `available` is what the actor can do RIGHT NOW with the
## reads that need only the actor; an avenue that needs a partner, a mentor or a site names
## that in `note` and reads `available: false` rather than pretending. The scar the read is
## about is `FoundationApi.mend_target` — the WEAKEST snapshot, the same default every
## avenue uses, because lifting the worst raises the carried mean the fastest.


static func for_actor(actor: Actor) -> Dictionary:
	if actor == null:
		return {}
	var target := FoundationApi.mend_target(actor)
	if target == &"":
		return {
			"scar": "",
			"standing": 0.0,
			"mend_cap": FoundationApi.MEND_CAP,
			"avenues": [] as Array,
			"count": 0,
		}
	var standing := FoundationApi.snapshot_for(actor, target)
	var rows: Array = [
		_elixir(actor),
		_rite(standing),
		_forbidden_art(actor, standing),
		_karmic_virtue(actor),
		_secret_realm(),
		_mentor(actor),
		_dual_aid(actor),
		{
			"id": "rebirth",
			"available": false,
			"price": "a life",
			"note": "the baseline: die and return with a karmic floor",
		},
	]
	return {
		"scar": String(target),
		"standing": standing,
		"mend_cap": FoundationApi.MEND_CAP,
		"avenues": rows,
		"count": rows.size(),
	}


## The miracle elixir (S7): available when the actor CARRIES an item that mends foundation.
static func _elixir(actor: Actor) -> Dictionary:
	var inventory := ItemsApi.inventory(actor)
	if inventory == null:
		return _row("miracle_elixir", false, "an elixir", "no inventory")
	for batch in inventory.stacks():
		var def: Resource = inventory.definition_of(batch.def_id)
		if def != null and float(def.get("foundation_mend")) > 0.0:
			return _row("miracle_elixir", true, "an elixir", String(batch.def_id))
	return _row("miracle_elixir", false, "an elixir", "none carried")


## The heaven-defying rite (S8): available while the scar is below the mended ceiling.
static func _rite(standing: float) -> Dictionary:
	return _row(
		"heaven_defying_rite",
		standing < FoundationApi.MEND_CAP,
		"a karmic fight",
		"mends on a win, scars on a loss"
	)


## The forbidden lifespan art (S11): a year of life, refused in the final band.
static func _forbidden_art(actor: Actor, standing: float) -> Dictionary:
	var lastlight := AgeBandTable.band_for_actor(actor) == AgeBandTable.LASTLIGHT
	return _row(
		"forbidden_lifespan_art",
		not lastlight and standing < FoundationApi.MEND_CAP,
		"a year of life",
		"refused in the final band" if lastlight else "burn years for a mend"
	)


## Karmic virtue (S12): available when enough deeds are unspent.
static func _karmic_virtue(actor: Actor) -> Dictionary:
	var owed := DestinyKarmicVirtue.available(actor)
	return _row(
		"karmic_virtue",
		owed >= DestinyKarmicVirtue.VIRTUE_PER_MEND,
		"%d deeds" % DestinyKarmicVirtue.VIRTUE_PER_MEND,
		"%d deed(s) available" % owed
	)


## The secret realm (S9): a one-time site inside a domain run. Its availability is a
## PROPERTY OF A RUN, not of the actor, so it reads unavailable here and says where to find it.
static func _secret_realm() -> Dictionary:
	return _row("secret_realm", false, "danger and time", "found in a domain, spent once")


## The master's sacrifice (S10): available when the actor holds a CONFIDANT bond.
static func _mentor(actor: Actor) -> Dictionary:
	var state := SocialApi.social_state(actor)
	if state == null:
		return _row("master_sacrifice", false, "a relationship", "no bonds")
	for partner_id in state.partner_ids():
		var bond := state.bond(partner_id)
		if bond != null and bond.bond_class() == SocialBondClass.CONFIDANT:
			return _row("master_sacrifice", true, "a relationship", String(partner_id))
	return _row("master_sacrifice", false, "a relationship", "no confidant yet")


## The dual-cultivation aid (S13): available when the actor holds the ritual's essence.
static func _dual_aid(actor: Actor) -> Dictionary:
	var essence := actor.resource(DualCultivationStats.ESSENCE)
	var held := 0.0 if essence == null else essence.current
	return _row(
		"dual_cultivation_aid",
		held >= DualCultivationAid.AID_ESSENCE,
		"%d essence" % int(DualCultivationAid.AID_ESSENCE),
		"%d held, needs a partner" % int(held)
	)


static func _row(id: String, available: bool, price: String, note: String) -> Dictionary:
	return {"id": id, "available": available, "price": price, "note": note}
