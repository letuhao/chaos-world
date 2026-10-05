class_name AgeBandTable
extends Resource

## The authored AGE BANDS, keyed by NAME, beside `RealmLifespan` (ADR 0258 §3).
##
## A lifespan is computed and `age_years` is a body fact, but neither says WHICH STAGE of a
## life a body is in — so without this table a hundred-year lifespan is one undifferentiated
## number from day one to its end. Four bands cross at AUTHORED FRACTIONS of the lifespan:
##
## | band        | enters at | what the crossing means                                      |
## |-------------|-----------|-------------------------------------------------------------|
## | `first_ash` |  0.00     | the body a hero is born into; no cost, no gain             |
## | `greenwood` |  0.25     | the climb: the body still pays for everything               |
## | `gilded`    |  0.50     | the turn: slower to learn, harder to mend, clearer to read |
## | `lastlight` |  0.75     | the end: the cost is nearly everything the buff is not     |
##
## ## Why this is a SEPARATE table and not a row on the lifespan table
##
## Different questions, different units, different guards. `RealmLifespan` is keyed by
## `RealmDef.tier` because a lifespan is a function of the BAND A REALM IS IN; a band is a
## function of a DURATION the actor has lived. One is a tier (an ordinal), the other is a
## share of a magnitude — ADR 0050's category error would be exactly this, multiplying one
## by the other.
##
## ## Keyed by NAME, never by index or by position — the ANTI-SHIFT property
##
## `fraction` is an ABSOLUTE authored number, never an offset from the previous row, so a
## band inserted anywhere changes no existing band's fraction. `tests/core/test_age_band_table.gd`
## proves it by inserting one and comparing every value before and after, which is the same
## proof `tests/core/test_realm_lifespan_table.gd` gives for the sibling table. An index
## key would slide every band below the insertion onto the wrong fraction, which is the
## `RealmPowerTable` failure this repo already paid for.
##
## ## The reader walks the AUTHORED DATA, and the data is sorted before the walk
##
## `band_for` reads `fractions` rather than a `const` list, because a row the lookup cannot
## reach is a reference that reads as working and grants nothing — the exact shape ADR 0135
## names, and the reason a fifth band must be one EDIT rather than two. The rows are sorted
## by fraction before the walk, so a band inserted into the `.tres` out of order resolves
## correctly anyway and the file's row order is never load-bearing.
##
## That walk is bounded by the table's OWN ROW COUNT, snapshotted before the loop: the count
## is a property of AUTHORED CONTENT, exactly as `TimeLadder.magnitudes()` is, and it is
## read once so no comparison can use a count its own body changed (AGENTS.md:52,
## `tests/arch_rules/test_no_unbounded_wait.gd`).
##
## ## Falling back to `FIRST_ASH` is a JOKE about ageing, never an expiry
##
## A lifespan nobody authored (a body plan with no `race_def` component reads `0.0`)
## answers the YOUNGEST band — the same refusal `realm_power_table.gd:32` makes for an
## unknown tier, and for the same reason: a missing row must leave a body as it was authored
## rather than invent a state. It is emphatically NOT the last band: a zero lifespan must
## never read as "this body has outlived everything", which would kill a hero with no race
## on their first frame.

## The band every body starts in, and the fallback for anything this table does not
## author. Named rather than index 0 for the ADR 0050 reason, and named rather than a
## generic word because a vocabulary a reader can guess is the whole point.
const FIRST_ASH := &"first_ash"

## The four authored band ids, in ascending order of the fraction at which they are
## ENTERED. This is the SHAPE the feature ships and the test pins; it is deliberately NOT
## what [method band_for] walks, because an inserted band is reachable the moment its
## fraction is authored and must not need this literal edited first. A name declared here
## and absent from the `.tres` is a shape failure the test names; a name in the `.tres` and
## absent here is a NEW band, which is the ADR 0050 answer.
const AUTHORED_BANDS: Array[StringName] = [&"first_ash", &"greenwood", &"gilded", &"lastlight"]

## One authored band per name, mapping name -> fraction of the lifespan at which it is
## ENTERED. The whole of the table: four names, four absolute fractions, and nothing derived
## from anything.
@export var fractions: Dictionary = {}


## The authored fraction of the lifespan at which `band` is ENTERED, in `[0.0, 1.0]`, or
## `0.0` for a band nobody authored.
##
## `0.0` rather than `1.0` for an unknown name, because `0.0` is the value the YOUNGEST
## band genuinely carries: an unauthored band must read as "not a stage yet", never as
## "the last stage" — the same fallback direction as `RealmLifespan.NEUTRAL`.
func fraction_for(band: StringName) -> float:
	if band == &"":
		return 0.0
	return float(fractions.get(band, 0.0))


## The band `age_days` has carried `body` to, against the `lifespan_days` it was born with.
##
## ## Comparison is `>=`, because a band ENTERING is the event
##
## The same reason ADR 0258 §5's own age check is `>=`: a body standing exactly on a
## crossing has ARRIVED at it, so a body at exactly one quarter of its lifespan is in
## `greenwood` and not still in `first_ash`.
##
## ## The walk keeps the LAST band it has passed, so authoring cannot decide the answer
##
## Rows are sorted by fraction first, and a pass is taken when the share has reached that
## row. Two rows at the same fraction therefore resolve to the SECOND of them — the
## furthest reached — which is deterministic and independent of the order they were typed
## in. The strictly-rising shape is asserted in `tests/core/test_age_band_table.gd`, so a
## tie is named there rather than silently resolved here.
func band_for(age_days: float, lifespan_days: float) -> StringName:
	if lifespan_days <= 0.0:
		return FIRST_ASH
	var share := clampf(age_days / lifespan_days, 0.0, 1.0)
	# Snapshot the bound BEFORE the loop: `rows` is the AUTHORED row set and the count is
	# read once, so nothing in the body can change what the walk is measured against.
	var rows := _authored_rows()
	var reached := FIRST_ASH
	for row in rows:
		if share >= float(row["fraction"]):
			reached = StringName(row["band"])
	return reached


## The authored bands as `{band, fraction}` rows ordered by the fraction each is entered at,
## so a reader cannot be surprised by the order the `.tres` happens to be written in.
func _authored_rows() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for band in fractions.keys():
		if band == &"":
			continue
		rows.append({"band": String(band), "fraction": fraction_for(StringName(band))})
	# `sort_custom` on a PAIR is how a Dictionary of bands gets a real order without a second
	# authored table to keep in step. A stable secondary key on the name means two rows at
	# the same fraction still sort deterministically rather than by dictionary insertion.
	rows.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			var left := float(a["fraction"])
			var right := float(b["fraction"])
			if is_equal_approx(left, right):
				return String(a["band"]) < String(b["band"])
			return left < right
	)
	return rows


## The authored bands as primitives, youngest first, for a screen and a test to read the
## same way. Fraction included so a lineage screen can draw the crossing points without
## holding a second copy of the numbers.
func bands() -> Array[Dictionary]:
	return _authored_rows()
