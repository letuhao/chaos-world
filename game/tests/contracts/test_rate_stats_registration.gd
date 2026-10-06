extends TestCase

## BL-0675: `Stat.RATE_STATS` is the ONLY membership list both content gates read --
## `modules/status/status_def.gd:372` (a `StatusDef` FLAT) and
## `tools/data.py:2085` (`_resolve_rate_stats`, a fate FLAT) -- and it was hand-written
## over core's ids alone. ADR 0071 renamed `critical_chance`/`dodge_chance` into
## `mind_focus_chance`/`mind_avoidance` and the registration had nowhere to follow, so a
## `FLAT` on either validated clean and applied as `(0.05 + 10.0) = 1005%`.
##
## A list edit fixes today's entry and tomorrow's rename re-breaks it, so membership is
## DERIVED here from the fact that decides it, which is not a hand-kept list:
##
##   SHAPE - the baseline expression in the code that publishes the id. A cap literal
##           under `1.0` inside `minf`/`clampf`, or a `1.0 +` term at the HEAD of the
##           expression, is a fraction or a multiplier. `ActorStats._put` resolves
##           `(base + flat) * (1 + percent)`, so FLAT on either is a content error.
##   REACH - whether authored content can name the id as a modifier target. A rate
##           nothing can target cannot produce the defect, and the catalog's own `unit:`
##           is not proof: it is self-declared and wrong on 13 shipped options
##           (`move_speed`, `penetration`, the ten `element_defense_*` -- which ADR 0200
##           corrected from the capped percent this file used to name).
##
## The two completeness guards walk the AUTHORED surface -- option catalog stat targets
## and fate modifier keys -- so a new option aimed at a new rate id extends the check
## with no edit to this file. `test_every_registered_rate_id_is_live` is the rename
## guard: a registration whose id no longer has a baseline anywhere is a registration a
## rename left behind, and it fails naming the id.
##
## ## The rule errs in ONE direction, deliberately
##
## An expression the shape rule cannot classify is treated as NOT rate-shaped. That is a
## false negative -- one unchecked id -- rather than a false positive, which would demand
## registering a magnitude and then REFUSE a legitimate `FLAT` on it. Every id this
## guard does classify comes from real code, so its failure mode is a gap in coverage,
## never a refusal of good content.

const CATALOG := "res://data/item_options/master_option_pool.jsonl"
const FATE_DIR := "res://data/destiny/fates"
const MODULES_DIR := "res://src/modules"
const STAT_DEFS := "res://src/contracts/stat.gd"
const ACTOR_STATS := "res://src/core/actor_stats.gd"

## A published baseline longer than this many source lines is not a shape this guard can
## read. The cap is the terminator, so an unbalanced parenthesis ends the accumulation
## instead of running to the end of the file.
const MAX_EXPRESSION_LINES := 8

## `stat id -> baseline expression`, harvested once per run and read by every guard.
var _baselines: Dictionary = {}


func teardown() -> void:
	_baselines.clear()


# --- liveness: the scanner read something ---------------------------------------


## UNCONDITIONAL, with no filter and no loop-dependent condition. Every other guard here
## is a pass over a derived set, so an empty scan makes all of them vacuously true --
## the failure this repo has shipped repeatedly. These four are asserted on their own:
## no set is consulted, nothing is compared against a hand list, and none of them can be
## satisfied by an empty input.
func test_the_scanner_actually_read_the_stat_surface() -> void:
	var baselines := _baselines_in_res()
	assert_ne(baselines.size(), 0, "at least one stat has a published baseline in res://src")
	# Floors, not counts: the exact totals move whenever a module grows a stat, and a
	# guard that breaks on an unrelated addition gets deleted rather than fixed.
	assert_eq(
		baselines.size() >= 30,
		true,
		"core's _put list and every module provider were read (%d baselines)" % baselines.size()
	)
	var authored := _authored_stat_targets()
	assert_ne(authored.size(), 0, "authored content names stat targets")
	assert_eq(authored.size() >= 50, true, "the whole option catalog and fate set were read")
	assert_ne(Stat.RATE_STATS.size(), 0, "the registration list this file audits is not empty")
	assert_eq(Stat.RATE_STATS.size() >= 19, true, "and it holds core's ten plus the module's nine")


# --- completeness: nothing authored is a rate without a registration ------------


## The guard that makes the next omission impossible to repeat. Walks the authored
## surface and asks the SHAPE question about each id, so the set is derived rather than
## declared. Failure names the id, because that is what the author has to look up.
func test_no_authored_rate_target_is_unregistered() -> void:
	var rate_shaped := _rate_shaped_ids()
	var unregistered: Array[String] = []
	for id in _authored_stat_targets():
		if rate_shaped.has(id) and not Stat.RATE_STATS.has(id):
			unregistered.append(String(id))
	assert_eq(
		unregistered,
		[],
		(
			"these authored stat targets have a fraction or multiplier baseline and are "
			+ (
				"absent from Stat.RATE_STATS, so a FLAT on one validates clean: %s"
				% ", ".join(unregistered)
			)
		)
	)


## A registered id must not name a baseline that is NOT rate-shaped. That is the false
## positive this file exists to avoid, and it is the failure that refuses good content.
## `damage_reduction` (baseline `0.0`, deliberately absent, ADR 0022) is the negative
## control, so the rule is falsifiable rather than vacuous.
func test_no_registered_rate_id_has_a_magnitude_baseline() -> void:
	var rate_shaped := _rate_shaped_ids()
	var wrong: Array[String] = []
	for id in Stat.RATE_STATS:
		if not rate_shaped.has(id):
			wrong.append(String(id))
	assert_eq(
		wrong,
		[],
		(
			"these are registered as rates but their baseline is a magnitude or is "
			+ "identically zero, so a FLAT on them is legal content and would be "
			+ "wrongly refused: %s" % ", ".join(wrong)
		)
	)
	assert_eq(
		Stat.RATE_STATS.has(Stat.DAMAGE_REDUCTION),
		false,
		"and damage_reduction stays out: its baseline is 0.0 (ADR 0022)"
	)


# --- liveness of each registration: the rename guard ----------------------------


## The rename guard, and the one BL-0675 needed. A registration is live when the id has
## a published baseline somewhere in `res://src`: `ActorStats._put` for core, a
## provider's `contribute` for a module. ADR 0071 moved `mind_avoidance`'s BASELINE to a
## new id and left the registration behind; this is the assertion that notices, and it
## names the id so the fix is to move the registration with the rename.
func test_every_registered_rate_id_is_live() -> void:
	var baselines := _baselines_in_res()
	var orphans: Array[String] = []
	for id in Stat.RATE_STATS:
		if not baselines.has(id):
			orphans.append(String(id))
	assert_eq(
		orphans,
		[],
		(
			"these are registered in Stat.RATE_STATS but no baseline in res://src "
			+ "publishes them -- a rename moved the id and left the registration "
			+ "behind: %s" % ", ".join(orphans)
		)
	)


## The registration this file exists for. A `FLAT` on a module-owned rate id is
## refused by name, so both halves of the fix are shown together: the entry is
## here AND it is enforced. The id is read off `MindVocabulary` rather than
## pasted, so a vocabulary rename moves this with it instead of fossilising.
##
## `mind_avoidance` was the id this assertion originally named (BL-0675). ADR 0215
## retired it in favour of `mind_veil` and dropped it from `RATE_STATS`, so the old
## spelling is pinned the other way: still absent, and no rate refusal on it.
func test_a_flat_on_a_module_owned_rate_is_refused() -> void:
	var rate_id := MindVocabulary.defence_id(MindVocabulary.SHAPE_SLOW)
	assert_eq(
		Stat.RATE_STATS.has(rate_id),
		true,
		"a vocabulary defence id is registered: %s" % String(rate_id)
	)
	var def := _stat_modifier_status(rate_id, &"flat", 5.0)
	assert_ne(def.problems().size(), 0, "a FLAT on %s is refused" % String(rate_id))
	assert_eq(
		String(def.problems()[0]).contains("RATE_STATS"),
		true,
		"the refusal is the rate rule, not some other defect: %s" % String(def.problems()[0])
	)
	assert_eq(
		String(def.problems()[0]).contains(String(rate_id)),
		true,
		"and it names the id: %s" % String(def.problems()[0])
	)
	# The positive control, so the refusal above is about the op and not about this
	# status being malformed: the same def with PERCENT is accepted.
	var percent := _stat_modifier_status(rate_id, &"percent", 0.2)
	assert_eq(percent.problems(), [], "the same id with PERCENT is accepted")
	assert_eq(
		Stat.RATE_STATS.has(Stat.MIND_AVOIDANCE),
		false,
		"mind_avoidance stays retired: ADR 0215 moved it to mind_veil and out of the list"
	)
	var retired := _stat_modifier_status(Stat.MIND_AVOIDANCE, &"flat", 5.0)
	var retired_is_rate_refusal := false
	for problem in retired.problems():
		if String(problem).contains("RATE_STATS"):
			retired_is_rate_refusal = true
	assert_eq(
		retired_is_rate_refusal, false, "a FLAT on the retired id is not a rate refusal"
	)


## A minimal valid `StatusDef` carrying one modifier, so the only problem it can report
## is the one under test. `test_status_refusals.gd:_good` is the same shape for the same
## reason; it is not reused because it also asserts catalogue registration, which is not
## what these guards are about.
func _stat_modifier_status(stat_id: StringName, op: StringName, value: float) -> StatusDef:
	var def := StatusDef.new()
	def.id = &"probe_rate_registration"
	def.element = &"metal"
	def.kind = &"dot"
	def.scope = &"combat"
	def.stacking = &"refresh"
	def.duration = 10.0
	def.magnitude_unit = &"stat_modifier"
	def.magnitude_cap = 5.0
	def.tick_interval = 1.0
	# ADR 0075 refuses an affinity-only mitigation, so a second lever is present or the
	# refusal under test would never be the first problem reported.
	def.mitigation_tags = [&"affinity", &"technique"]
	def.payload = {
		"mechanic": &"bleed",
		"text": "probe bleed",
		"pool": "health",
		"share_per_pulse": 0.05,
		"modifiers": [{"stat": stat_id, "op": op, "value": value}],
	}
	return def


# --- derivation ------------------------------------------------------------------


## `stat id -> baseline expression` for every stat `res://src` publishes. Core publishes
## through `ActorStats._put(Stat.X, <expr>, buckets)`; a module publishes through
## `<StatsConst>.<ID>: <expr>,` inside a provider's returned dictionary. Both are read
## as SOURCE because the shape IS source: the cap literal or the `1.0 +` term is how an
## id declares itself a rate, and there is no runtime value to ask for a cap.
func _baselines_in_res() -> Dictionary:
	if not _baselines.is_empty():
		return _baselines
	_core_baselines()
	_module_baselines()
	return _baselines


## The rate-shaped subset.
##
## "Rate-shaped" is not one lexical fact, and no single `contains` classifies it without
## getting a magnitude wrong. Two rules, and BOTH are load-bearing:
##
##   (a) A `minf`/`clampf` call carrying a literal at or under `1.0` -- an explicit cap
##       in [0,1]. `crit_chance` is `minf(0.75, ...)`, `conception_chance` is
##       `clampf(0.05 + fertility * 0.02, 0.0, 0.95)`, `attack_speed` is
##       `minf(2.5, 1.0 + ...)`.
##   (b) The expression opens on a CONSTANT term of `2.0` or under, ADDED to something
##       else, and carries no literal above it -- the `0.05 + fortune * 0.002` /
##       `1.5 + comprehension * 0.004` shape ADR 0039 calls `constant term`, where `1.0`
##       means no change. `technique_power` (`(1.0 + qi_affinity * 0.05) * factor`) is
##       the same shape behind an opening paren.
##
## Rule (b)'s two extra clauses are what keep the magnitudes out, and each one was a real
## false positive before it was written:
##
##   - `attack_physical` is `physique * 2.0` and `poise` is `physique * 0.5 + will *
##     0.5`. Every literal is under `2.0`, so "all literals are small" alone classifies
##     both as multipliers and then REFUSES a legal `FLAT` on each. Both are
##     attribute-scaled with no constant term, which is the shape a magnitude has -- so
##     the expression must OPEN on the number.
##   - `damage_reduction` is `0.0`. It opens on a number and the literal is small, so
##     without the `+` requirement it would classify as a rate; ADR 0022 keeps it out of
##     `RATE_STATS` precisely because a PERCENT on a `0.0` baseline is a no-op and FLAT
##     is the only form that can work.
func _rate_shaped_ids() -> Dictionary:
	var out: Dictionary = {}
	var baselines := _baselines_in_res()
	for id in baselines:
		if _is_rate_shaped(String(baselines[id])):
			out[id] = true
	return out


func _is_rate_shaped(expression: String) -> bool:
	var text := expression.replace(" ", "")
	if text.contains("minf(") or text.contains("clampf("):
		for literal in _numeric_literals(text):
			if literal <= 1.0:
				return true
	return _opens_on_a_constant_sum(text)


## True when `text` opens (after at most one opening paren) on a numeric CONSTANT of
## `2.0` or under, followed by `+`, with no literal anywhere above that ceiling. The
## three clauses are one predicate because removing any one of them produces a known
## wrong answer; see `_rate_shaped_ids` for which.
func _opens_on_a_constant_sum(text: String) -> bool:
	var rest := text
	if rest.begins_with("("):
		rest = rest.substr(1)
	var head := ""
	# `index` is the terminator and advances on every pass over the head's digits.
	while rest.length() > 0:
		var character := rest.substr(0, 1)
		if not character.is_valid_float() and character != ".":
			break
		head += character
		rest = rest.substr(1)
	if not head.is_valid_float() or head.to_float() > 2.0:
		return false
	if not rest.begins_with("+"):
		return false
	for literal in _numeric_literals(rest):
		if literal > 2.0:
			return false
	return true


## Every numeric literal in `text`, in order. The index is the terminator and advances
## on every pass, so this cannot outrun its input.
func _numeric_literals(text: String) -> Array[float]:
	var out: Array[float] = []
	var run := ""
	for index in text.length():
		var character := text.substr(index, 1)
		if character.is_valid_float() or character == ".":
			run += character
			continue
		if not run.is_empty() and run.is_valid_float():
			out.append(run.to_float())
		run = ""
	if not run.is_empty() and run.is_valid_float():
		out.append(run.to_float())
	return out


## `ActorStats._put` lines, with each `Stat.X` name resolved through stat.gd's own
## consts so the id string comes from a declaration rather than a literal here.
func _core_baselines() -> void:
	var stat_consts := _consts_in(STAT_DEFS)
	var put_line := RegEx.create_from_string("\\b_put\\(\\s*Stat\\.([A-Z_]+)\\s*,\\s*(.+)$")
	for line in FileAccess.get_file_as_string(ACTOR_STATS).split("\n"):
		var match := put_line.search(String(line))
		if match == null:
			continue
		if not stat_consts.has(match.get_string(1)):
			continue
		_baselines[stat_consts[match.get_string(1)]] = match.get_string(2)


## Every module provider's published baselines. Per MODULE directory rather than per
## file: a module that moves a baseline into a new file must not thereby escape the
## scan, which is the same reason `mind_gate_probe.module_code_all()` is per-directory.
func _module_baselines() -> void:
	var modules := DirAccess.open(MODULES_DIR)
	if modules == null:
		return
	# Snapshots taken before the walk; neither array is appended to inside a loop.
	var module_names := modules.get_directories()
	for module_name in module_names:
		var directory := "%s/%s" % [MODULES_DIR, String(module_name)]
		var dir := DirAccess.open(directory)
		if dir == null:
			continue
		var stat_consts := _module_stat_consts(directory)
		var files := dir.get_files()
		for file_name in files:
			var file := String(file_name)
			if file.ends_with("provider.gd"):
				_provider_entries("%s/%s" % [directory, file], stat_consts)
				_vocabulary_entries("%s/%s" % [directory, file])


## Baselines for ids a provider builds through `MindVocabulary.offence_id` /
## `defence_id` rather than spelling as `<Class>.<CONST>:` entries, which is what
## `mind_mastery_provider.gd` does for all twelve control ids. The literal-entry
## scan above cannot see a computed key, so without this the twelve read as
## having no baseline and the liveness guard fails on ids that are published,
## capped and registered. `tools/data.py::_resolve_rate_stats` carries the same
## fallback on its side; the two must agree on the set or the gates disagree.
##
## Only ids already in `Stat.RATE_STATS` are recorded, so this cannot invent a
## registration: a new suffix still has to earn its list entry, and a suffix the
## provider stops publishing keeps no baseline here. Cap names are substituted
## with the values the same file declares, because the shape rule reads
## literals, not names.
func _vocabulary_entries(path: String) -> void:
	var text := FileAccess.get_file_as_string(path)
	if not text.contains("MindVocabulary.offence_id") and not text.contains(
		"MindVocabulary.defence_id"
	):
		return
	var off_expr := _minf_rhs(text, "offence_id")
	var def_expr := _minf_rhs(text, "defence_id")
	if off_expr == "" and def_expr == "":
		return
	var caps := _numeric_consts(text)
	for suffix in MindVocabulary.SHAPES + MindVocabulary.CHANNELS:
		var off := MindVocabulary.offence_id(suffix)
		if off_expr != "" and Stat.RATE_STATS.has(off) and not _baselines.has(off):
			_baselines[off] = _substitute(off_expr, caps)
		var dn := MindVocabulary.defence_id(suffix)
		if def_expr != "" and Stat.RATE_STATS.has(dn) and not _baselines.has(dn):
			_baselines[dn] = _substitute(def_expr, caps)


## The `minf(...)` right-hand side of a line publishing through the named
## generator, or "". Wrapped right-hand sides share `_publish`'s single-line
## shape, which is what this reads.
func _minf_rhs(text: String, generator: String) -> String:
	var matcher := RegEx.create_from_string(
		"MindVocabulary\\." + generator + "[^=]*=\\s*(minf\\(.*\\))\\s*$"
	)
	for line in text.split("\n"):
		var found := matcher.search(String(line))
		if found != null:
			return found.get_string(1)
	return ""


## `const NAME := 0.45` numeric constants in one file, so a cap name in a
## harvested expression is replaced with the literal the shape rule reads.
func _numeric_consts(text: String) -> Dictionary:
	var out: Dictionary = {}
	var matcher := RegEx.create_from_string("^\\s*const ([A-Z_0-9]+) := ([0-9.]+)\\s*$")
	for line in text.split("\n"):
		var found := matcher.search(String(line))
		if found != null:
			out[found.get_string(1)] = found.get_string(2)
	return out


## Replace whole-word cap names with their declared values. Word-boundaried so
## `ATTACK_CAP` never rewrites inside a longer identifier.
func _substitute(expression: String, caps: Dictionary) -> String:
	var out := expression
	for name in caps:
		var key := String(name)
		out = RegEx.create_from_string("\\b" + key + "\\b").sub(out, String(caps[name]), true)
	return out


## `MindStats.MIND_AVOIDANCE` -> `&"mind_avoidance"`, harvested from the module's own
## declarations. `MindStats` is a `class_name`, not a `const`, so the owning class of
## each `const NAME := &"id"` is read from that file's `class_name` line; a module that
## declares the const in a different file from the class would need both files scanned,
## which the per-directory walk below already does.
##
## Resolving through the declaration is what makes a rename visible: a renamed const
## changes the id this scan reports, and a registration left on the old id then has no
## baseline. First declaration wins, so a module that repeats a name across files gets
## one answer rather than a silent overwrite per file.
func _module_stat_consts(directory: String) -> Dictionary:
	var dir := DirAccess.open(directory)
	if dir == null:
		return {}
	var out: Dictionary = {}
	var files := dir.get_files()
	for file_name in files:
		var file := String(file_name)
		if not file.ends_with(".gd"):
			continue
		var path := "%s/%s" % [directory, file]
		var owner := _class_name_in(path)
		if owner == "":
			continue
		var consts := _consts_in(path)
		for name in consts:
			var key := "%s.%s" % [owner, name]
			if not out.has(key):
				out[key] = consts[name]
	return out


## The `class_name X` this file declares, or `""`. A provider can only name ids through
## a class, so a file with no class_name contributes no resolvable ids.
func _class_name_in(path: String) -> String:
	var match := RegEx.create_from_string("^class_name ([A-Za-z_0-9]+)").search(
		FileAccess.get_file_as_string(path)
	)
	if match == null:
		return ""
	return match.get_string(1)


## One provider's published entries and their baseline expressions, joined across the
## line break a long expression may wrap at. `DualCultivationStats.DUAL_CULTIVATION_RATE`
## ends its line at the colon and starts the expression on the next, so the pattern's
## tail is optional and an entry with nothing after the colon borrows the next line.
func _provider_entries(path: String, stat_consts: Dictionary) -> void:
	var entry_line := RegEx.create_from_string("^\\s*([A-Za-z_]+)\\.([A-Z_]+)\\s*:(.*)$")
	var lines := FileAccess.get_file_as_string(path).split("\n")
	var index := 0
	# `index` is the terminator, is bounded by `lines.size()`, and is advanced on every
	# path through the body including the `break`.
	while index < lines.size():
		var start := entry_line.search(String(lines[index]))
		if start == null:
			index += 1
			continue
		var key := "%s.%s" % [start.get_string(1), start.get_string(2)]
		if not stat_consts.has(key):
			index += 1
			continue
		var expression := start.get_string(3).strip_edges()
		var span := 1
		if expression.is_empty():
			index += 1
			span = 2
			if index >= lines.size():
				break
			expression = String(lines[index]).strip_edges()
		while span < MAX_EXPRESSION_LINES and not _balanced(expression):
			index += 1
			span += 1
			if index >= lines.size():
				break
			expression += " " + String(lines[index]).strip_edges()
		_baselines[stat_consts[key]] = expression
		index += 1


## True once the accumulated text has closed every paren it opened AND ends at a comma,
## which is where a dictionary entry actually terminates.
func _balanced(expression: String) -> bool:
	var depth := 0
	for index in expression.length():
		var character := expression.substr(index, 1)
		if character == "(":
			depth += 1
		elif character == ")":
			depth -= 1
	return depth <= 0 and expression.strip_edges().ends_with(",")


## `const NAME := &"value"` in one file. Returns every match, and a caller decides which
## declarations it wants, so this stays a scanner rather than a policy.
func _consts_in(path: String) -> Dictionary:
	var out: Dictionary = {}
	if not FileAccess.file_exists(path):
		return out
	var matcher := RegEx.create_from_string('^const ([A-Z_0-9]+) := &"([a-z_0-9.]+)"')
	for line in FileAccess.get_file_as_string(path).split("\n"):
		var match := matcher.search(String(line))
		if match != null:
			out[match.get_string(1)] = StringName(match.get_string(2))
	return out


## Every stat id authored content can name as a modifier target: the option catalog's
## stat targets plus every fate modifier key. Read from `game/data` rather than kept
## here, so a new option aimed at a new id needs no edit to be checked.
func _authored_stat_targets() -> Dictionary:
	var out: Dictionary = {}
	if FileAccess.file_exists(CATALOG):
		var catalog := RegEx.create_from_string('"type":\\s*"stat",\\s*"id":\\s*"([a-z_0-9.]+)"')
		for line in FileAccess.get_file_as_string(CATALOG).split("\n"):
			var match := catalog.search(String(line))
			if match != null:
				out[StringName(match.get_string(1))] = true
	var fates := DirAccess.open(FATE_DIR)
	if fates == null:
		return out
	var modifier_block := RegEx.create_from_string("(?:flat|percent)_modifiers = \\{([^}]*)\\}")
	var key := RegEx.create_from_string('"([a-z_0-9.]+)":')
	var files := fates.get_files()
	for file_name in files:
		var file := String(file_name)
		if not file.ends_with(".tres"):
			continue
		var text := FileAccess.get_file_as_string("%s/%s" % [FATE_DIR, file])
		var block := modifier_block.search(text)
		if block == null:
			continue
		for name in key.search_all(block.get_string(1)):
			out[StringName(name.get_string(1))] = true
	return out
