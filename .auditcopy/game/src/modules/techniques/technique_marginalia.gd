class_name TechniqueMarginalia
extends RefCounted

## The annotations a COPIED manual carries in its margin, and the one place they
## are drawn.
##
## ## What a manual is: fixed text, variable margin
##
## A technique's teaching is inscribed. The `.tres` holds what the manual says —
## which two body changes it trains, and at what value — and that text does not
## move. What varies is what the copy in a reader's hands has picked up from every
## hand it passed through: the corrections in a margin, the fuller breathing
## counts, the note beside a figure that says this one runs heavier than the
## printed number. So the roll is a **band around an authored value**, never a
## different authored value and never a different option.
##
## That is also the whole of the vocabulary this file owns. The inscribing is
## content; the transmitting is a fact about the object, and the two are separated
## exactly as ADR 0053 separates learning from equipping: nothing here edits a
## definition, and nothing here can move a number another module published.
##
## ## WHY THESE VALUES AND NOT THE OTHERS
##
## A technique carries `magnitude`, `qi_cost`, `stamina_cost`, `cooldown` and its
## option values. Only the last of the five may vary, and the other four are
## refused for reasons worth naming:
##
## - **`magnitude`** is the coefficient ADR 0055's authored ladder multiplies
##   (`technique_magnitude_table.tres`, 1.0 to 2.77x), and
##   `tools technique_power check` guards that table by walking its ratios.
##   `CombatSpine.base_damage` reads `def.magnitude` off the shared catalog
##   resource. A rolled magnitude would therefore have to reach the resolver as a
##   per-actor COPY of the def, which `technique_casting.gd` already refuses in
##   writing for the same reason: the spine is called directly by `app/` and by
##   other modules for hits that never pass through this module, so a value that
##   existed only on the technique route would be on for one route and off for the
##   same actor's next hit. It would also put a second multiplier on the base of
##   one hit whose first multiplier is the realm rate.
## - **`qi_cost` and `cooldown`** are exactly the two quantities ADR 0055 publishes
##   rung multipliers on (`0.94^n` and `0.96^n`). A band on the authored cost is a
##   second multiplier on a value the mastery ladder already scales, and ADR
##   0160 refuses that shape for the capacity channel by name. `stamina_cost` is
##   refused with it: ADR 0055 publishes no stamina column, so there is no rung
##   multiplier to pair it with and a band there would be the only multiplier on
##   that number, which is a different balance question, not this decision.
## - **Grade, path, element, the gates and `mastery_rungs`** are not stats.
##   `mastery_rungs` in particular is the ceiling ADR 0160's clamp reads, so a
##   copied ladder is a copied ceiling on an investment.
##
## ## The window is THIS file's, not the catalog's
##
## `OptionCatalog.magnitude_bounds` sizes an ITEM's magnitude by reading a realm id
## through `item_magnitude_scale.json`. A technique may not do that: that table is
## the item ladder, `technique_magnitude_table.tres` is the technique ladder, and
## AGENTS.md names all three as deliberate and never derived from one another.
## So the window here is a band on the AUTHORED value, which needs no ladder at
## all — and that is what makes the band safe to widen without a review.
##
## ## The band, and why it is both-sided
##
## `FLOOR_SPAN` / `CEILING_SPAN` are the same span either side of the authored
## figure, so a copied manual is on average the manual it was copied from: a
## one-sided band would make every copy strictly better than the sheet, and the
## printed value would be a number no player ever actually gets. The ceiling is
## bounded by construction rather than by arithmetic — the worst any copy of any
## option can be is `1.25` times a number an author wrote — and the floor cannot
## take a positive stat negative.
##
## Two bounds then apply, in this order: the option's OWN `bounds` (through
## `OptionCatalog.clamp_to_bounds`, the same call `fixed_effect` makes at authoring
## time) and the band. Measured over the 29 `cult_*` options in
## `master_option_pool.jsonl`, every one declares `bounds {min: 0.0, max: 9999.0}`
## — a sanity ceiling, not a balance window, which is exactly why the band cannot
## be delegated to the catalog and has to be authored here.
##
## ## The capacity channel is refused, and why
##
## A capacity option (`cult_dantian_capacity`, `cult_essence_capacity`,
## `cult_carry_capacity`, anything ending `max_*`) resizes a pool MAXIMUM. ADR
## 0160 refuses to let a mastery rung scale one, because `RealmScaling` already
## MULTs `MAX_QI` and `MAX_STAMINA` by the realm's own 1.0x-551.46x power and the
## authored dantian capacity re-seals the pool on top. A band here is the same
## second multiplier on the same quantity, from a different mechanism, and it would
## be the least authored of them — so a capacity option is carried at its AUTHORED
## value and the annotation on it is not taken. A copy is never worse than the
## sheet, which is what makes "this copy is a good one" mean something at all.
##
## `is_capacity_effect` is the twin of `CodexEntry._is_capacity`, which refuses the
## same channel for the same reason in the other direction (rung scaling).
## `test_technique_marginalia.gd` walks every `cult_*` option in the shipped
## catalog and asserts the two agree, so the pair cannot drift apart — a test,
## because a comment is not a tie.
##
## ## Determinism
##
## [method draw] takes an optional generator and consumes exactly one draw per
## rollable option, in authored order. Production passes none and takes the
## engine's own entropy once, at the learn that stores the result; a test passes a
## seeded generator, which is the idiom `ItemGenerator.generate` and
## `test_technique_passive_mastery` already use. There is no time source and no
## engine node anywhere in this file, so a copy's annotations are a pure function
## of (authored text, seed) and can be replayed from either.

## ## RARITY DECIDES HOW WIDE THE BAND IS, NOT HOW BIG THE NUMBER IS
##
## `ItemRarity.magnitude_budget` was dead code — one declaration, zero callers in
## the tree — and it is a fraction of a ceiling (`0.0` COMMON, `0.25` MAGIC, `0.5`
## RARE, `1.0` LEGENDARY), which is the wrong SHAPE for a band edge and the right
## shape for a half-width. So it is read as one:
##
## ```
## var reach := ItemRarity.magnitude_budget(def.rarity)   # 0.0 .. 1.0
## var span := lerpf(1.0 - reach * BAND_REACH, 1.0 + reach * BAND_REACH, source.randf())
## ```
##
## `BAND_REACH = 0.25` is the widest a LEGENDARY copy may sit from its authored
## figure — a `0.75x` to `1.25x` band, both-sided on purpose, so two copies of one
## manual differ in both directions rather than one always reading high. A COMMON
## copy now carries no variance at all: the transmitted text and the printed text
## agree, which is the right statement for a common book and is what `budget = 0.0`
## has always meant.
##
## `1.25^4 = 2.44` is the worst one copy of a rung-4 passive can be against the
## worst copy of the same manual at rung 0, and `1.25 * 1.749 = 2.19` is the spread
## two copies of one manual reach at the same rung — a real difference between
## copies, and a finite one.
##
## This is a rarity-to-VARIANCE knob and deliberately not a fourth magnitude table.
## It never moves the authored value by more than `1.25`, never touches
## `magnitude`, and is derived from no per-realm table (ADR 0055, AGENTS.md).
const BAND_REACH := 0.25


## The band's two edges for a rarity, as multiples of the AUTHORED value.
##
## One reader, so a caller that needs the declared window — a test asserting a copy
## never escapes it, or a panel showing a player the range they may see — cannot
## disagree with `draw` about how wide the band is. Published as a pair rather than
## two constants because the width is no longer a constant: it is `rarity`.
static func band_for(rarity: StringName) -> Vector2:
	var reach := clampf(ItemRarity.magnitude_budget(rarity), 0.0, 1.0)
	var spread := reach * BAND_REACH
	return Vector2(1.0 - spread, 1.0 + spread)


## The annotations this copy of `def`'s manual carries: one realized effect per
## authored option that may vary, in authored order. A capacity option comes back
## at its authored value with a `rolled` channel, because a rolled channel with
## no variation in it would be a lie in the read model.
##
## A technique with no options — every active one — realizes nothing, so the
## margin of an active manual is empty and that is the honest answer rather than a
## number invented for it.
static func draw(def: TechniqueDef, rng: RandomNumberGenerator = null) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if def == null:
		return out
	var catalog := OptionCatalog.instance()
	# The two-option cap is read from `TechniquePolicy` rather than restated, so a
	# copy can never carry more annotations than the sheet it was copied from.
	for authored in def.passive_options.slice(0, TechniquePolicy.PASSIVE_OPTION_CAP):
		if not authored is Dictionary:
			continue
		var entry: Dictionary = authored
		var option_id := StringName(entry.get("option_id", ""))
		var record := catalog.option_record(option_id)
		# An option the catalog no longer knows is dropped here exactly as
		# `TechniqueDef.effects` drops it: a copy of a manual whose ink has gone
		# unreadable carries no annotation rather than an invented one.
		if option_id == &"" or record.is_empty():
			continue
		var value := float(entry.get("value", 0.0))
		var target: Dictionary = record.get("target", {})
		if is_capacity_effect(target.get("id", &"")):
			out.append(OptionCatalog.make_effect(record, value, &"rolled"))
			continue
		# ## A MISSING GENERATOR IS ENTROPY, NOT AN IDENTITY BAND
		#
		# This used to read `var span := 1.0` and only band when a generator was
		# supplied, which made PRODUCTION the one caller that rolled nothing:
		# `bind_learner` → `TechniquesApi.learn` passes no generator (production has
		# no seed), so every copy a real player received carried the authored value
		# exactly, and the margin differed between copies only in the suites that
		# seeded one. A component whose tests exercise the branch its only production
		# caller never reaches is the `delivers` / `bind_target` defect with a
		# green tick on it.
		#
		# So a null generator mints the engine's own entropy, which is what "one
		# draw from the ambient stream" means, and a supplied one is a SEED SOURCE
		# (ADR 0191's shape): the caller sets `.seed` and the draw is reproducible.
		# Both arms take exactly one draw per rollable option, in authored order, so
		# the two are the same function of their source.
		var source: RandomNumberGenerator = rng if rng != null else RandomNumberGenerator.new()
		# Rarity is the half-width of the band, so a common copy is exact and a
		# legendary one spans the full authored reach. See BAND_REACH.
		var band := band_for(def.rarity)
		var span := lerpf(band.x, band.y, source.randf())
		# Snap to the option's own declared precision BEFORE the clamp, so two copies
		# of one manual never read as 3.9999999 and 4.0000001 of the same figure —
		# the same order `OptionCatalog.roll_value` applies them in.
		var precision := pow(10.0, -float(int(record.get("precision", 2))))
		var rolled := snappedf(value * span, precision)
		out.append(OptionCatalog.make_effect(record, rolled, &"rolled"))
	return out


## Whether an effect resizes a pool MAXIMUM, which the realm ladder and the
## authored capacity already govern.
##
## The twin of `CodexEntry._is_capacity`, and matched on the CONCEPT rather than on
## a curated list: `CodexEntry`'s own header records that a name list is out of date
## the moment someone adds a pool. `target_type` cannot answer it either — every
## `cult_*` capacity is typed `stat`, which is the reason ADR 0160's first attempt
## at a `target_type` test never fired.
static func is_capacity_effect(target_id) -> bool:
	var id := String(target_id)
	return id.begins_with("max_") or id.ends_with("_maximum") or id.contains("capacity")
