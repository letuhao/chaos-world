extends TestCase

## ADR 0083's "**one claim shape, never a second copy**" pinned structurally.
##
## ## Why a TEST and not a gate
##
## ADR 0083 states the rule and every case in this repo obeys it by hand:
## `position` is discrete and authored, `standing` is continuous and earned, `obligation`
## is an open ledger of lines. `tools arch` resolves `res://` REFERENCES and reads bare
## class names in `BARE_REF_UNITS` — and `BARE_REF_UNITS` is `("ui", "app", "contracts")`,
## so **`modules/*` and `core/` are not scanned at all**. A fourth `ClanClaim.gd` written
## with its own `position` / `standing` / `obligation` / `standing_cap` quartet would
## report ZERO violations, import cleanly, compile cleanly, and be a second source of
## truth for one fact. **No checker in this repo can see a copy of a shape; only a human
## can — so this suite is that human, expressed as an assertion.**
##
## The precedent is the one ADR 0084 states for its own invariant: *"tools arch cannot
## see a method that does not exist, so the refusal is pinned structurally instead."*
##
## ## What each case asserts, and which failure it is for
##
##   - the quartet has EXACTLY ONE owner in `game/src/` — a second `Resource` or
##     `RefCounted` carrying all four names is a second claim shape.
##   - every institution ledger reaches the quartet THROUGH `InstitutionClaim` — the
##     `from_dict` / `to_dict` pair is the only bridge, so a normalizer and a writer
##     cannot disagree about what a claim is.
##   - `standing_percent` has ONE formula and one cap — a per-module copy is the ADR
##     0066 failure mode inside the file that exists to prevent it.
##   - `promote` writes `position` and never `standing`; `move_standing` writes
##     `standing` and never `position`. Read off the SOURCE, because a value assertion
##     cannot see a writer that was handed the field and declined to use it.

## The one class allowed to hold the claim quartet, by `res://` path. Named rather than
## discovered so a NEW quartet fails as "a second owner appeared" instead of quietly
## becoming the second owner.
const CLAIM_OWNER := "res://src/core/institution_claim.gd"
## The file that OWNS the sect claim write. Moved here by ded5dd41e (a lint split of
## `sect/api.gd`, 1033 -> 975 lines): the rule below is about the writer, not about
## which file the writer happens to live in, so the case names the writer's home
## rather than the facade's.
const WRITER_PATH := "res://src/modules/sect/sect_ledger.gd"

## The four names that make a claim a claim (ADR 0083). A file declaring all four as
## its own members IS a claim shape, whatever it calls itself.
const QUARTET := ["position", "standing", "obligation", "standing_cap"]

## Every `.gd` under `game/src`, so the scan cannot be narrowed by editing the list. A
## `for` over an authored file set reading only — it writes nothing and mutates nothing,
## so the bound is the file count and there is no shape here for `test_no_unbounded_wait`
## to refuse.
const SRC_ROOT := "res://src"

## The shared vocabulary a second refusal table would copy. The names, so a case can say
## which one drifted.
const SHARED_REASONS := [
	"no_actor",
	"unknown_institution",
	"already_founded",
	"no_top_position",
	"founding_cost_unmet",
]

## The two constants that ARE the whole political stat surface (ADR 0084). Declared in
## `InstitutionClaim` and read through `InstitutionLedger.standing_percent` /
## `InstitutionFounding`; a second declaration anywhere is a second formula.
const PERCENT_CONSTANTS := ["STANDING_RATE", "STANDING_PERCENT_CAP"]

# --- One owner for the quartet -------------------------------------------------


## ## The load-bearing case: the claim quartet has exactly ONE owner in `game/src`
##
## Scanned over the WHOLE tree rather than a named list, because the defect this guards
## is a file nobody put on any list. A module that declared its own
## `(position, standing, obligation, standing_cap)` would be a second claim shape — and
## `tools arch` reports nothing, because it reads references and this is a value type.
func test_the_claim_quartet_has_exactly_one_owner_in_src() -> void:
	var owners := _quartet_owners()
	assert_eq(owners.has(CLAIM_OWNER), true, "the shared InstitutionClaim owns the quartet")
	# The whole list, asserted as a WHOLE rather than by absence of one known rival, so
	# a second owner fails here whether it is `ClanClaim`, `GuildClaim` or a `NationDef`
	# that grew the fields.
	assert_eq(owners, [CLAIM_OWNER], "and it is the ONLY owner")


## ## The defect this guards is REAL and it was already reached once
##
## `SectDef` and `NationDef` each declare their OWN `standing_cap`, which is correct and
## is NOT a second shape: the authored ceiling is content, while `InstitutionClaim.
## standing_cap` is the value a claim clamps against. So this case is the one that would
## catch the mistake in the other direction — somebody "fixing" the duplication by
## deleting the authored cap, or by having a def's cap reach a ledger directly and skip
## the claim. Neither is visible to `tools arch` and both are visible here.
func test_a_defs_authored_standing_cap_is_not_a_second_claim_shape() -> void:
	for rel in ["res://src/modules/sect/sect_def.gd", "res://src/core/institution_def.gd"]:
		var body := FileAccess.get_file_as_string(rel)
		assert_ne(body, "", "%s is readable" % rel)
		assert_eq(_declares(body, "standing_cap"), true, "%s authors its own ceiling" % rel)
		# And the ceiling is CONTENT: a def must not be able to build a claim itself, or
		# the clamp would have two homes and could disagree with `InstitutionClaim`.
		assert_eq(
			_calls(body, "InstitutionClaim.from_dict"),
			0,
			"%s never constructs a claim — it authors content for one" % rel
		)


# --- Every ledger reaches the quartet THROUGH the claim ------------------------


## ## A ledger's PERSISTENCE FORM and the claim must agree, field for field
##
## This is the half a class-declaration scan cannot reach, and it is where a second
## shape actually hides. `SectState.normalize` legitimately spells the four names as
## dictionary keys — it is the save form of the claim, and ADR 0083's rule is about a
## second SHAPE, not about a second place the same four keys have to appear in
## (`InstitutionLedger.read` is the same rule restated for a ledger with no envelope).
## The risk is that the two spellings **disagree**: a normalizer that repaired
## `standing_cap` to 0 while the claim repairs it to 1 is a claim whose ratio cannot be
## computed, through a door no `tools arch` rule looks at.
##
## Compared through each side's own public entry rather than by reading either file.
func test_the_ledger_s_persistence_form_agrees_with_the_claim() -> void:
	for payload in [
		{},
		{"institution": "t_house", "position": "t_steward", "standing": 7},
		{"institution": "t_house", "standing_cap": 0, "standing": 0},
		{"institution": "t_house", "standing_cap": -4, "standing": 0},
		{"institution": "t_house", "position": "t_reader", "standing": 0},
	]:
		var from_claim := InstitutionClaim.from_dict(payload).to_dict()
		var from_ledger := SectState.normalize(payload)
		for field in ["position", "standing", "standing_cap"]:
			assert_eq(
				from_ledger[field],
				from_claim[field],
				(
					(
						"'%s' agrees for payload %s -- a normalizer that disagrees is a "
						+ "second claim shape"
					)
					% [field, str(payload)]
				)
			)
		assert_eq(
			(from_ledger["obligation"] as Dictionary).keys().size(),
			(from_claim["obligation"] as Dictionary).keys().size(),
			"and so does the open set of obligation lines for %s" % str(payload)
		)
	# The REPAIR, as its own case because it is the load-bearing one: a cap that cannot be
	# computed reports a normalized ratio of zero and reads as an institution nobody
	# respects. Both sides floor it at 1, or a ledger would carry a cap the claim refuses.
	assert_eq(
		SectState.normalize({"institution": "t_house", "standing_cap": 0})["standing_cap"],
		maxi(1, InstitutionClaim.from_dict({"standing_cap": 0}).standing_cap),
		"a zero cap is repaired to the same floor in both"
	)
	# The SAME payload on both sides, so the caps cannot differ: the first version forced
	# the claim's cap to 1 while the ledger defaulted to 100 and the case reported a
	# disagreement that was the case's own arithmetic.
	var repaired_payload := {"institution": "t_house", "standing": 5, "standing_cap": 0}
	assert_eq(
		float(SectState.claim(SectState.normalize(repaired_payload)).normalized()),
		float(InstitutionClaim.from_dict(repaired_payload).normalized()),
		"so a repaired ledger and a repaired claim report the same ratio"
	)


## ## The ONE MEASURED DIVERGENCE, pinned rather than quietly narrowed around
##
## Writing the case above is what found this: **`InstitutionClaim.from_dict` does not
## clamp `standing` into `standing_cap`, and both ledgers do.**
## `SectState.normalize` and `InstitutionLedger.read` both answer
## `clampi(standing, 0, cap)`; `from_dict` answers `maxi(0, standing)`. A hand-edited
## save carrying 999 standing on a 40 cap therefore yields a claim of 999 and a ledger
## of 40.
##
## **It is not a power leak** — `normalized()` clamps to `[0, 1]` and
## `standing_percent` is capped at `STANDING_PERCENT_CAP`, so the political stat surface
## is bounded either way, which is why nothing else in the tree notices. It is a claim
## that reports a number its own cap says is impossible, reached through a door no
## `tools arch` rule looks at.
##
## Asserted as a MEASUREMENT rather than worked around, for the reason ADR 0066 gives
## about `RealmRate`: a guard that quietly narrows to the subset where two copies agree
## is a guard that hides the disagreement it was written to surface. The fix is
## `core/`'s — `InstitutionClaim.from_dict` is outside this file's claim — and the
## narrowest form is one clamp in one method. Until then this is the boundary.
func test_the_one_measured_divergence_from_the_claim_is_pinned() -> void:
	var payload := {"institution": "t_house", "standing": 999, "standing_cap": 40}
	var from_claim := InstitutionClaim.from_dict(payload)
	var from_ledger := SectState.normalize(payload)
	# The claim takes the number as written; the ledger clamps it into the cap.
	assert_eq(int(from_claim.standing), 999, "the claim reads standing as written")
	assert_eq(int(from_ledger["standing"]), 40, "and the ledger clamps it into the cap")
	# `InstitutionLedger.read` is the third reader and it AGREES with the ledger, so this
	# is `from_dict` alone rather than a three-way split. Asserted because "two of the
	# three" is the shape a future edit could quietly make three.
	assert_eq(
		int(InstitutionLedger.read(payload)["standing"]), 40, "and so does the shared ledger read"
	)
	# The consequences are bounded, which is why this is filed rather than treated as an
	# emergency: no stat surface and no ratio exceeds the cap whichever side answers.
	assert_almost_eq(float(from_claim.normalized()), 1.0, "a claim past its cap normalizes to one")
	assert_almost_eq(
		InstitutionClaim.standing_percent(int(from_claim.standing)),
		InstitutionClaim.STANDING_PERCENT_CAP,
		"and the recognition percent is still capped"
	)


## The compliant shape, asserted rather than described: `sect`'s writer hands the ledger
## to `InstitutionClaim.to_dict` and writes back exactly what came out, so the four names
## are never spelled by this module.
func test_a_module_writes_its_ledger_through_the_claim_not_through_the_four_names() -> void:
	# ## The writer moved, and this case follows the WRITER, not the file name
	#
	# When this case was written the bridge sat in `sect/api.gd`. Commit ded5dd41e ("lint:
	# split the sect ledger plumbing out of the facade", 1033 -> 975) moved
	# `SectLedger.write_claim` into `sect/sect_ledger.gd`, so `claim.to_dict()` appears
	# there now and appears ZERO times in the facade. The rule is unchanged -- a module
	# reaches the quartet through `InstitutionClaim.to_dict` and never spells the four
	# names -- so the assertion moves to the file that owns the write, and the "never
	# constructs a claim of its own" half is asserted over BOTH.
	#
	# Pinned to an explicit PAIR rather than a walk of `modules/sect/`: a walk would go
	# green on a second `to_dict()` appearing anywhere in the module, which is the very
	# duplication (ADR 0066) this case exists to catch.
	var writer := FileAccess.get_file_as_string(WRITER_PATH)
	assert_ne(writer, "", "the claim writer is readable")
	assert_eq(_calls(writer, "claim.to_dict()"), 1, "the writer persists the claim's own payload")
	var body := FileAccess.get_file_as_string("res://src/modules/sect/api.gd")
	assert_ne(body, "", "the facade is readable")
	assert_eq(
		_calls(body, "InstitutionClaim.new()") + _calls(writer, "InstitutionClaim.new()"),
		0,
		"neither the facade nor the writer constructs a claim of its own"
	)
	# `SectState.claim` is the module's reader, and it is a delegation for the same
	# reason — asserted on the file rather than taken from its docstring.
	var state := FileAccess.get_file_as_string("res://src/modules/sect/sect_state.gd")
	assert_eq(
		_calls(state, "InstitutionClaim.from_dict"),
		1,
		"SectState.claim delegates to the shared constructor"
	)


# --- The formula has one home ---------------------------------------------------


## ## `standing_percent` is ONE formula, and a per-module copy is ADR 0066 restated
##
## `RealmRate` is the precedent this repo already paid for: three paths each held a copy
## of one curve, the copies were kept in step BY HAND, and one retune made three
## different answers to the same question. `InstitutionClaim.standing_percent` exists for
## the same reason, and `InstitutionLedger.standing_percent` is a deliberate delegate to
## it. A module that published its own copy would be undetectable to `tools arch` and
## would be the third such copy.
func test_the_recognition_percent_has_exactly_one_formula_and_one_cap() -> void:
	for rel in _files():
		var body := FileAccess.get_file_as_string(rel)
		for constant in PERCENT_CONSTANTS:
			var declared := _declares(body, constant)
			if rel == CLAIM_OWNER:
				assert_eq(declared, true, "%s owns %s" % [rel.get_file(), constant])
				continue
			assert_eq(
				declared,
				false,
				(
					(
						"%s declares its own %s — the recognition formula has one home "
						+ "(ADR 0084, the RealmRate precedent)"
					)
					% [rel.get_file(), constant]
				)
			)


## The shared formula is reached by DELEGATION wherever it is published, so a caller
## reading either entry point gets one number. Asserted as a value rather than a
## docstring, because the whole risk is two files answering differently.
func test_both_published_reads_of_standing_percent_agree_with_the_claim() -> void:
	for standing in [0, 1, 35, 100, 1000000]:
		var from_claim := InstitutionClaim.standing_percent(standing)
		assert_eq(
			from_claim,
			InstitutionLedger.standing_percent(standing),
			"standing %d reads the same through both names" % standing
		)
		assert_eq(
			from_claim <= InstitutionClaim.STANDING_PERCENT_CAP,
			true,
			"and never past the cap, at %d" % standing
		)
	assert_almost_eq(
		InstitutionClaim.standing_percent(1000000),
		InstitutionClaim.STANDING_PERCENT_CAP,
		"a standing of a million still projects only the capped percent"
	)


# --- The two writers never touch each other's field -----------------------------


## ## ADR 0064's split, read off the SOURCE
##
## `promote` writes `position` and never `standing`; `move_standing` writes `standing`
## and never `position`. The behavioural halves of this are asserted in
## `test_institution_foundation.gd::test_position_and_standing_never_derive_from_each_other`,
## which is stronger evidence and lives with the verb. This case is the one they cannot
## reach: **a writer that took the other field as an ARGUMENT and declined to use it
## still passes every value assertion**, and a `set(field, value)` setter — which is what
## collapsing the pair looks like — has one parameter and so nothing stopping it being
## handed the wrong one. Two verbs, not one.
func test_promote_writes_position_and_move_standing_writes_standing_and_neither_crosses() -> void:
	var body := FileAccess.get_file_as_string("res://src/core/institution_ledger.gd")
	assert_ne(body, "", "the ledger is readable")
	var promote := _function_body(body, "static func promote(")
	var move := _function_body(body, "static func move_standing(")
	assert_ne(promote, "", "promote is findable, so the scan below read its body")
	assert_ne(move, "", "move_standing is findable, so the scan below read its body")
	# The two writers are checked on the ASSIGNMENT, not on the key: `move_standing`
	# reads `out["standing"]` twice more in its success payload, so a count over the bare
	# key reports three hits for a function that writes it once, and a guard that reads
	# three has either been weakened or will fail on a harmless refactor.
	assert_eq(_calls(promote, 'out["standing"] ='), 0, "promote never assigns standing")
	assert_eq(_calls(promote, 'out["position"] ='), 1, "promote assigns the position exactly once")
	assert_eq(_calls(move, 'out["standing"] ='), 1, "move_standing assigns the standing once")
	assert_eq(_calls(move, 'out["position"] ='), 0, "and move_standing never assigns the position")
	# `move_standing` reads no position at all, which is the stronger half: a promotion
	# that RECOMPUTED standing from the office would be assigning it too, but a standing
	# change that READ the position and clamped against it would be deriving one from the
	# other without an assignment at all.
	assert_eq(
		_calls(move, 'read(ledger)["position"]'),
		0,
		"and it never reads the position, so neither can derive from the other"
	)
	# And there is no combined setter to collapse them into one number: that is the shape
	# that has no second number to contradict.
	assert_eq(
		_calls(body, "func set("),
		0,
		"no `set(field, value)` exists, because a field name as DATA is the collapse"
	)


# --- One refusal vocabulary, named not copied ------------------------------------


## ## A refusal is a named constant, and the names are authored ONCE
##
## `InstitutionLedger` owns the vocabulary and indexes it from the constants, because a
## hand-written `REASONS` table of the same eight strings was the ADR 0066 failure mode
## inside the very file that exists to remove it. A module may ALIAS those names — that is
## one value under two spellings — and may add its OWN (`unknown_sect`,
## `unknown_doctrine`), which is this tier's vocabulary rather than a copy of the shared
## one. What it may not do is publish a table that disagrees with the shared one, because
## a panel looks a reason up by name and would get a silent null.
func test_every_shared_refusal_name_has_one_value_across_the_institution_vocabulary() -> void:
	for name in SHARED_REASONS:
		assert_eq(
			InstitutionLedger.REASONS.has(name), true, "the shared vocabulary publishes '%s'" % name
		)
		assert_eq(
			String(InstitutionLedger.REASONS[name]),
			name,
			"and it is the same string it is keyed by"
		)
	# The two aliases a sect publishes over the shared names are asserted EQUAL, which is
	# what "alias" means: a caller writing either name holds one value.
	assert_eq(SectFounding.R_NO_ACTOR, InstitutionLedger.R_NO_ACTOR, "no_actor is one value")
	assert_eq(
		SectFounding.R_ALREADY_FOUNDED,
		InstitutionLedger.R_ALREADY_FOUNDED,
		"already_founded is one value"
	)
	assert_eq(
		SectFounding.R_NO_TOP_POSITION,
		InstitutionLedger.R_NO_TOP_POSITION,
		"no_top_position is one value"
	)
	assert_eq(
		SectFounding.R_FOUNDING_COST_UNMET,
		InstitutionLedger.R_FOUNDING_COST_UNMET,
		"founding_cost_unmet is one value"
	)
	# And the sect's own two are NOT in the shared table, which is the proof that
	# `SectFounding.REASONS` is a SUPERSET rather than a filtered copy the two would
	# have to be kept in step with.
	assert_eq(
		InstitutionLedger.REASONS.has(SectFounding.R_UNKNOWN_SECT),
		false,
		"unknown_sect is this tier's own wording, not a shared name"
	)
	assert_eq(
		InstitutionLedger.REASONS.has(SectFounding.R_UNKNOWN_DOCTRINE),
		false,
		"and so is unknown_doctrine"
	)
	# Every key the sect publishes resolves to ITSELF, so a lookup by name cannot go null.
	for name in SectFounding.REASONS.keys():
		assert_eq(String(SectFounding.REASONS[name]), String(name), "'%s' resolves" % name)


# --- Helpers --------------------------------------------------------------------


## Every `.gd` under `res://src`, through `ContentScan` — which caps depth at
## `MAX_DEPTH` and SORTS its result, so the set is the same on every run and the failure
## names the same file twice. A recursive walk here would be a `while` in disguise that
## `test_no_unbounded_wait.gd` cannot see, and a self-referential directory would recurse
## until the stack died.
##
## **`.gd` is passed explicitly.** `ContentScan`'s suffix argument defaults to
## `DEFAULT_SUFFIX` (`.tres`), because every catalog that used it was loading authored
## content — so the first version of this case asked for scripts and received an EMPTY
## list, which made all three scans vacuous: "no file declares a second copy of the
## formula" is exactly what an empty tree also answers. A guard that passes because it
## looked at nothing is the shape this file exists to refuse.
func _files() -> Array[String]:
	var out: Array[String] = []
	for path in ContentScan.files_under(SRC_ROOT, ".gd"):
		out.append(String(path))
	return out


func _module_files() -> Array[String]:
	var out: Array[String] = []
	for file in _files():
		if file.begins_with("res://src/modules/"):
			out.append(file)
	return out


## The files that declare all four quartet names as their own members. **The `and` of
## four independent membership tests**, so a file holding two of them is not reported:
## the defect is the complete shape, and a lone `standing` is a summary value
## (`ClanSummary.standing`) rather than a second claim.
func _quartet_owners() -> Array[String]:
	var out: Array[String] = []
	for file in _files():
		var body := FileAccess.get_file_as_string(file)
		var holds := true
		for name in QUARTET:
			if not _declares(body, name):
				holds = false
		if holds:
			out.append(file)
	return out


## Whether `body` declares `name` as its own member or constant. **`@export` counts**,
## because `InstitutionClaim`'s four are all `@export` — they have to be, they are
## `@export`ed fields on an authored `Resource` — and a scan that missed the prefix
## would report the ONE legitimate owner as no owner and the guard would be vacuous.
## `const` counts too, because the recognition formula is a constant rather than a
## member and the second-copy scan is looking for that shape.
func _declares(body: String, name: String) -> bool:
	var forms := [
		"var %s" % name, "@export var %s" % name, "const %s" % name, "@export const %s" % name
	]
	for line in body.split("\n"):
		var code := line.strip_edges()
		if code.begins_with("#"):
			continue
		for form in forms:
			if code.begins_with(form):
				return true
	return false


## The body of the function whose signature line contains `signature`, as a string, or
## `""` when there is none. Cut at the next top-level `static func` / `func`, which is a
## bounded scan of an authored file rather than a loop over anything a caller controls.
func _function_body(body: String, signature: String) -> String:
	var at := body.find(signature)
	if at < 0:
		return ""
	var tail := body.substr(at + signature.length())
	var stop := tail.find("\nstatic func ")
	if stop < 0:
		stop = tail.find("\nfunc ")
	if stop < 0:
		stop = tail.length()
	return tail.substr(0, stop)


## How many times `needle` appears in CODE, ignoring the `##` prose that documents it.
## Every file in this programme names the words it forbids inside its own class docs —
## ADR 0084's whole argument is WHICH writes are forbidden, so the forbidden names are
## written down in sentences — and a raw `body.contains(needle)` scan fails on those
## sentences while reading the code beside them as clean. The invariant is about what the
## tree EXECUTES, so the comment lines are dropped first.
func _calls(body: String, needle: String) -> int:
	var hits := 0
	for line in body.split("\n"):
		var code := line.strip_edges()
		if code.begins_with("#"):
			continue
		if code.contains(needle):
			hits += 1
	return hits
