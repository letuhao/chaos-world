class_name InstitutionProjection
extends RefCounted

## The ONE consumer of an institution's stat allowlist, for ANY kind (ADR 0084).
##
## ## What moved here and why
##
## The loop that turns a member's standing into a bounded PERCENT lived in
## `SectProjection._grant`, inside `sect`, so the three shipped guilds could not be
## given one: a `.tres` under the generic institutions directory authored no
## allowlist, because the field that would carry it had no reader outside one module
## and a generic allowlist with no projection is an author writing numbers that go
## nowhere (DEF-0337). The consumer moved down here instead; the CONTENT moved with
## it. `core/` is a layer rather than a module, so this creates zero new edges and
## every kind can drive it.
##
## ## The whole surface is a pure function of FOUR arguments
##
## `(allowlist, standing, source_tag, actor)` and nothing else. No catalog, no
## registry, no module, no ledger envelope, no clock — so a guild, a clan, a sect and
## a nation all call the same function with their own four values and there is no
## per-kind copy to keep in step (ADR 0066's `RealmRate` reasoning).
##
## ## PERCENT only. Never a FLAT, never `set_base`, never a second stat composer
##
## A FLAT is realm-blind: decisive at R2 and noise by roughly realm 12 across the
## ladder that now spans 1.0x to 551x (ADR 0063). A FLAT on a rate stat is the
## silent `(0.0 + 0.0) * (1 + p) = 0.0` no-op ADR 0068 measured on 44 items. And a
## `set_base` bypasses the modifier stack entirely, so it cannot be stripped, cannot
## be rebuilt idempotently, and DOES satisfy `get_base` — which is exactly how an
## institution would smuggle a member past the gates meant to test them. So the only
## op written here is `Stat.Op.PERCENT`, the value is
## [method InstitutionClaim.standing_percent], and the stack is the one
## `ActorStats` already folds (ADR 0026).
##
## ## STRIP FIRST, so a second grant cannot compound
##
## A projection that cannot be inverted is a projection that compounds on re-attach
## (ADR 0084). [method strip] removes by SOURCE TAG, which is why the ledger records
## the tag rather than re-reading the definition: a `.tres` that has been deleted
## still leaves a contribution that can be taken back, and that is exactly when
## losing a position would otherwise strand it. [method grant] strips its own tag
## before it writes, so a caller CANNOT double-grant by forgetting to — the failure
## is a no-op rather than a compounding multiplier.
##
## ## The cap bounds the RATIO and never the ledger's number
##
## `standing_percent` saturates at `STANDING_PERCENT_CAP` long before a large cap is
## reached, so a guild that publishes a cap of 150 hands a member at 150 exactly the
## same recognition as one at 100 while the LEDGER still reads 150. **Nothing here
## clamps `standing` and nothing here reads `standing_cap`**: a clamp would delete
## the politics ADR 0064's split exists for, where a member sits below what their
## standing reads as. The number in the ledger is the politics; the percent is the
## only thing an institution may express with it.
##
## ## An EMPTY allowlist is a legitimate authored choice, not a fault
##
## An office nobody is recognised for is a real office — the ordinary member, the
## ministers of a polity whose whole business is administration — and `{}` grants
## nothing without an error, which is ADR 0083's "this does not exist" rather than
## its third state. It is a success carrying an empty grant, never a refusal.
##
## ## ONE percent per id per tag — read this before migrating a tier that SUMS
##
## [method grant] writes a single percent for each authored id, under ONE tag. That is
## the whole of what ADR 0084 grants a member of one institution. A tier whose offices
## **accumulate** on one stat — `NationProjection.build` adds the percent of every held
## office together — therefore cannot be migrated by handing this the union of its
## allowlists: the union grants the ONE percent and drops the sum. Such a tier must
## grant once per office under a **per-office** tag, which this makes free because
## every tag is namespaced, or must merge before granting and accept the smaller number.
## Nothing here reads an allowlist's VALUE, because an authored multiplier is exactly
## the magnitude ADR 0084 refuses a second way.

## An allowlist id this actor's stat sheet cannot name at all: a typo, or a
## module-owned rate nothing provides. Refused BY NAME rather than projected as zero,
## because a PERCENT on a stat with no derivation evaluates to
## `(0.0 + 0.0) * (1 + p) = 0.0` — a grant that reads as landed, sits in the ledger
## and moves nothing, which is the whole defect class ADR 0084's percent choice was
## made to avoid.
##
## **Authored here and not added to `InstitutionLedger.REASONS`**, for the reason
## `InstitutionDef.R_OFFICES_NOT_DECLARED` is: this is a fault in an AUTHORED CONTENT
## FIELD, not a refusal a mutating verb returns, and a second table is a list
## somebody has to keep in step with the first.
const R_UNKNOWN_RECOGNISED_STAT := "unknown_recognised_stat"
## A grant carrying no source tag. ADR 0084 requires the tag precisely so a rebuild
## can strip exactly what it added, and an empty tag cannot identify anything — so it
## is refused at the only place that could have produced one, rather than written and
## left for a later strip to guess at. **Distinct from `R_NO_ACTOR`**, because "there
## is no sheet to project onto" and "there is no way to take it back" are two
## different authoring bugs and a caller fixing one of them must not be handed the
## other's name.
const R_NO_SOURCE_TAG := "no_source_tag"
## Aliased from the ledger rather than restated, so a caller looking this reason up
## under either name gets one value.
const R_NO_ACTOR := InstitutionLedger.R_NO_ACTOR


## Project `allowlist` onto `actor` as one bounded PERCENT per id, and return
## `{ok, reason, granted}` with `granted` the `{stat_id: percent}` record the CALLER
## stores on its own ledger (ADR 0084: the ledger keeps the granted numbers rather
## than re-reading the definition, which is why stripping survives a deleted
## `.tres`).
##
## **Idempotent by construction.** Everything this source tag owns is stripped and
## rebuilt on every call, so calling this twice leaves the actor exactly where one call
## left it. An empty `allowlist` strips and writes nothing and is `ok`; a
## `source_tag` of `&""` and a null actor are refusals, because a grant either of them
## could not be inverted.
static func grant(
	actor: Actor, allowlist: Dictionary, standing: int, source_tag: StringName
) -> Dictionary:
	if actor == null:
		return _refused(R_NO_ACTOR)
	if source_tag == &"":
		return _refused(R_NO_SOURCE_TAG)
	# ## VALIDATE, THEN STRIP, THEN WRITE — and the order is the design
	#
	# The refusal comes first so it is **non-destructive**: a member does not lose the
	# recognition they already hold because a modder mistyped one id in a `.tres` five
	# minutes ago. ADR 0083's third state is "this was refused", and a refused verb
	# writes nothing (ADR 0044) — taking back a working grant would be a write.
	#
	# The strip comes before the write, which is what makes this idempotent: the first
	# version validated and wrote without stripping and `mods` climbed 2, 4, 6, 8, 10, 12
	# over five rebuilds while every assertion about the sheet went quietly wrong. A
	# caller CANNOT compound here by forgetting to strip, because the strip is not the
	# caller's job.
	# `Variant`, DECLARED rather than inferred: the answer is `null` or a `String`, so
	# `:=` would infer `Variant` and this repo treats that warning as an error.
	var unknown: Variant = unknown_stat(actor, allowlist)
	if unknown != null:
		return {
			"ok": false,
			"reason": R_UNKNOWN_RECOGNISED_STAT,
			"unknown": String(unknown),
			"granted": {},
		}
	strip(actor, source_tag)
	var percent := InstitutionClaim.standing_percent(int(standing))
	var granted: Dictionary = {}
	# `for` over the AUTHORED keys, writing into a NEW dictionary: the body never
	# touches the map being walked, so the bound is the content's own length and
	# there is no shape here for a loop to grow in lockstep with its own bound.
	for stat_id in allowlist.keys():
		granted[String(stat_id)] = percent
	for stat_id in granted.keys():
		actor.stats.add_modifier(
			StatModifier.new(StringName(stat_id), Stat.Op.PERCENT, percent, source_tag)
		)
	return InstitutionLedger.ok({"granted": granted})


## A refusal carrying `granted` and `unknown` as well, so a caller may index either key
## on EVERY answer instead of branching first — the shape
## `InstitutionLedger.ok`/`refuse` states for `ok` and `reason`, extended to this verb's
## two payloads.
static func _refused(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason, "unknown": "", "granted": {}}


## [method grant], with the standing read off the caller's own ledger. **The driver any
## kind calls**: four arguments, one of them a plain dictionary of primitives, and no
## tier vocabulary anywhere in the path.
##
## ## It writes NOTHING back into the ledger, and that is the whole envelope question
##
## ADR 0084 has a ledger record what it granted so a rebuild can strip exactly what
## it added. A SOURCE TAG already answers that — and it answers it BETTER, because
## the tag survives the defining `.tres` being deleted while a re-read of the
## definition does not, which is the case ADR 0063 raises and the reason the record
## exists. So the granted map is returned for a panel or a history line to publish and
## the tier's ledger keys stay the tier's own: `InstitutionClaim` has no
## `applied_standing` and does not acquire one here, because a second envelope shape
## across three tiers is ADR 0066's failure mode inside the file that exists to
## prevent it.
static func apply(
	actor: Actor, ledger: Dictionary, allowlist: Dictionary, source_tag: StringName
) -> Dictionary:
	return grant(actor, allowlist, _standing(ledger), source_tag)


## Take back everything [method grant] wrote under `source_tag`, and nothing else.
## **By tag, never by re-reading the definition** — a deleted `.tres` is exactly when
## a contribution would otherwise be left welded to whoever held it.
static func strip(actor: Actor, source_tag: StringName) -> void:
	actor.stats.remove_modifiers_from(source_tag)


## The standing `ledger` records, **as stored and never clamped into its own cap**.
## A member sitting at 500 under a cap of 150 is a political fact the projector has no
## opinion about — the cap bounds the RATIO (see the class note) and the number stays
## the politics (ADR 0064). Refused as zero rather than cast: a `standing` that
## arrived as text is a corrupt save, and a corrupt save reads as a member nobody
## thinks of rather than aborting an attach.
static func _standing(ledger: Dictionary) -> int:
	var value = ledger.get("standing", 0)
	return 0 if not (value is int or value is float) else maxi(0, int(value))


## Whether this office's standing may project onto `stat_id`.
##
## **Keys are compared as TEXT, whatever type they were authored with.** A `.tres`
## stores plain `String` keys while a def built in GDScript authors a `StringName`,
## and `Dictionary.has()` is key-type strict — so `has(String(x))` against a
## `StringName`-keyed map silently matches nothing. That failure is invisible from
## the outside: nothing is projected, every derived stat stays put, and the suite
## reads as "the institution correctly touched nothing" rather than as an allowlist
## that was never consulted.
static func recognises(allowlist: Dictionary, stat_id: StringName) -> bool:
	if stat_id == &"":
		return false
	for key in allowlist.keys():
		if String(key) == String(stat_id):
			return true
	return false


## The first allowlist id this actor's stat sheet cannot NAME, or `null` when every id
## has a derivation. The authoring-time read, published so a def can be checked before a
## member ever holds the office.
##
## ## `null` and NOT `""`, and that is not a style preference
##
## The first version returned `""` for "no fault" and `String(stat_id)` for the
## offender. An allowlist carrying an **empty-string key** — `{"": 0.0}`, which Godot
## loads from a `.tres` without complaint — therefore reported itself clean, because the
## offender it found WAS the empty string, and the projector went on to write a modifier
## on `&""` that no reader could ever look up. So the two answers had to be told apart by
## something other than their text, and `null` is the one value a stat id cannot be.
## `""` is a legal, if useless, allowlist key; it is a CONTENT fault and is named.
##
## **Nameable is not the same as non-zero.** An id whose derivation happens to read
## zero on THIS actor is a member who has invested nothing there, which is an ordinary
## sheet and not a content fault — and a percent that waits for the investment is
## exactly the behaviour ADR 0084 asks for. What is refused is an id with no derivation
## at all, where the percent is guaranteed to do nothing forever.
##
## ## It can refuse too eagerly, and that is the safe direction
##
## Membership is read off the actor's whole sheet, so an id carried ONLY by another
## subsystem's transient modifier reads as unnameable the moment that subsystem strips
## it — a false refusal. Safe, because a refusal writes nothing and the previous grant
## stands, where a false GRANT would be a modifier nothing ever reads.
static func unknown_stat(actor: Actor, allowlist: Dictionary) -> Variant:
	if actor == null:
		return null
	for key in allowlist.keys():
		var stat_id := StringName(InstitutionLedger.text(key, ""))
		if not _derivable(actor, stat_id):
			return String(stat_id)
	return null


## Whether `stat_id` has a derivation this sheet can carry: a base attribute counts
## even when the actor has none of it yet, because an attribute is a real derivation
## that this particular actor has not bought, and every other id must already be
## among the derived sheet.
static func _derivable(actor: Actor, stat_id: StringName) -> bool:
	if stat_id == &"":
		return false
	if Stat.BASE_ATTRIBUTES.has(stat_id):
		return true
	for known in actor.stats.derived_all().keys():
		if String(known) == String(stat_id):
			return true
	return false
