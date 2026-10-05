extends TestCase

## THROWAWAY PROBE. Writes the measured reconcile contract to a file. Delete when done.

const MORTAL_PLAINS := &"mortal_plains"
const RECONCILE_SRC := "res://src/core/world_reconcile.gd"
const ROOT_SRC := "res://src/app/item_workbench_app.gd"
const OUT_PATH := (
	"C:/Users/NeneScarlet/AppData/Local/Temp/commandcode/"
	+ "D--Works-source-chaos-world/5a3ee98f-1336-4e01-b255-fcfc71294075/"
	+ "scratchpad/probe_out.txt"
)

var _out: FileAccess = null


func _p(text: String) -> void:
	if _out == null:
		_out = FileAccess.open(OUT_PATH, FileAccess.WRITE)
	if _out == null:
		return
	_out.store_line(text)
	_out.flush()


func _dump(label: String, value: Variant = null) -> void:
	if value == null:
		_p("  " + label)
	else:
		_p("  " + label + " = " + str(value))


func test_probe_all_scenarios() -> void:
	_p("=== PROBE BEGIN ===")
	_p("--- ladder rows ---")
	_p("  magnitudes: " + str(TimeLadder.magnitudes()))
	_p(
		(
			"  BASE="
			+ str(TimeLadder.BASE)
			+ " month="
			+ str(TimeLadder.ratio_for(&"month"))
			+ " day="
			+ str(TimeLadder.ratio_for(&"day"))
			+ " year="
			+ str(TimeLadder.ratio_for(&"year"))
		)
	)
	var month := TimeLadder.ratio_for(&"month")
	var day := TimeLadder.ratio_for(&"day")
	var year := TimeLadder.ratio_for(&"year")

	_p("--- SCENARIO A: month total, offered twice ---")
	_dump("A1 raw magnitudes_crossed(month) ", TimeLadder.magnitudes_crossed(month))
	var a1 := WorldReconcile.observe(ReconcileStamp.empty(), MORTAL_PLAINS, month)
	_dump("A1 observe(first,month) ", a1)
	_dump("A1 stamp row ", ReconcileStamp.folds_for(a1["stamps"], MORTAL_PLAINS))
	var a2 := WorldReconcile.observe(a1["stamps"], MORTAL_PLAINS, month)
	_dump("A2 observe(same total,month) ", a2)
	_dump("A2 stamp row ", ReconcileStamp.folds_for(a2["stamps"], MORTAL_PLAINS))
	_p("  A2 crossed.get(month,-1)=" + str(int(a2["crossed"].get(&"month", -1))) + "  [WANTS 0]")
	_p(
		(
			"  A2 folded(month)="
			+ str(ReconcileStamp.folded(a2["stamps"], MORTAL_PLAINS, &"month"))
			+ "  [WANTS 1]"
		)
	)
	_p("  A2 elapsed_periods=" + str(int(a2["elapsed_periods"])) + "  [WANTS 0]")
	var a3 := WorldReconcile.observe(a2["stamps"], MORTAL_PLAINS, day)
	_dump("A3 observe(day-sized span) ", a3)
	_dump("A3 stamp row ", ReconcileStamp.folds_for(a3["stamps"], MORTAL_PLAINS))
	_p("  A3 elapsed_periods=" + str(int(a3["elapsed_periods"])) + "  [WANTS day=" + str(day) + "]")

	_p("--- SCENARIO B: year total, then doubled total ---")
	var b1 := WorldReconcile.observe(ReconcileStamp.empty(), MORTAL_PLAINS, year)
	_dump("B1 observe(first,year) ", b1)
	_dump("B1 stamp row ", ReconcileStamp.folds_for(b1["stamps"], MORTAL_PLAINS))
	var b2 := WorldReconcile.observe(b1["stamps"], MORTAL_PLAINS, year)
	_dump("B2 observe(second,same year) ", b2)
	_p("  B2 elapsed_periods=" + str(int(b2["elapsed_periods"])) + "  [WANTS 0]")
	var b3 := WorldReconcile.observe(b2["stamps"], MORTAL_PLAINS, year * 2)
	_dump("B3 observe(third,doubled total) ", b3)
	_dump("B3 stamp row ", ReconcileStamp.folds_for(b3["stamps"], MORTAL_PLAINS))
	_p(
		(
			"  B3 elapsed_periods="
			+ str(int(b3["elapsed_periods"]))
			+ "  [WANTS newly elapsed="
			+ str(year)
			+ "]"
		)
	)
	_p(
		(
			"  B3 place_periods="
			+ str(ReconcileStamp.folded_periods(b3["stamps"], MORTAL_PLAINS))
			+ "  [WANTS "
			+ str(year * 2)
			+ "]"
		)
	)

	_p("--- SCENARIO C: never-visited place, whole span (ADR 0173 c) ---")
	var c1 := WorldReconcile.observe(ReconcileStamp.empty(), &"spirit_peaks", year * 2)
	_dump("C1 observe(never visited,year*2) ", c1)
	_dump("C1 stamp row ", ReconcileStamp.folds_for(c1["stamps"], &"spirit_peaks"))
	_p(
		(
			"  C1 elapsed_periods="
			+ str(int(c1["elapsed_periods"]))
			+ "  [WANTS "
			+ str(year * 2)
			+ "]"
		)
	)
	_p("  C1 advanced=" + str(bool(c1["advanced"])) + "  [WANTS true]")

	_p("--- SCENARIO D: world_reconcile.gd source assertions ---")
	var raw_src := FileAccess.get_file_as_string(RECONCILE_SRC)
	var code := _code_only(raw_src)
	_p("  raw length=" + str(raw_src.length()) + " code_only length=" + str(code.length()))
	_p("  code_only count(push_error)= " + str(code.count("push_error(")) + "  [WANTS 1]")
	_p(
		(
			"  code_only contains pct=[asked,MAX_PLACES]= "
			+ str(code.contains("% [asked, MAX_PLACES]"))
		)
	)
	_p("  code_only contains 'No stamp was written'= " + str(code.contains("No stamp was written")))
	_p("  RAW count(push_error)= " + str(raw_src.count("push_error(")))
	_p("  RAW contains pct=[asked,MAX_PLACES]= " + str(raw_src.contains("% [asked, MAX_PLACES]")))
	_p("  RAW contains 'No stamp was written'= " + str(raw_src.contains("No stamp was written")))
	var at := raw_src.find("push_error")
	if at >= 0:
		var region := raw_src.substr(maxi(0, at - 200), 800)
		_p("  RAW REGION around push_error:")
		_p("<<<" + region + ">>>")
		_p("  --- same region through _code_only, newlines as \\n ---")
		_p("<<<" + _code_only(region).replace("\n", "\\n") + ">>>")

	_p("--- SCENARIO E: item_workbench_app.gd source assertions ---")
	var root_raw := FileAccess.get_file_as_string(ROOT_SRC)
	_p("  root raw length=" + str(root_raw.length()))
	var root := _code_only(root_raw)
	_p("  root code_only length=" + str(root.length()))
	var seam_a := 'WorldStage.set_reconciler(Callable(_world, "observe_place"))'
	var seam_b := 'WorldStage.set_epoch_reader(Callable(_world, "place_state"))'
	_p("  code_only has seam A=" + str(root.contains(seam_a)))
	_p("  code_only has seam B=" + str(root.contains(seam_b)))
	_p("  RAW has seam A=" + str(root_raw.contains(seam_a)))
	_p("  RAW has seam B=" + str(root_raw.contains(seam_b)))
	_p("  code_only count set_reconciler= " + str(root.count("WorldStage.set_reconciler(")))
	_p("  code_only count set_epoch_reader= " + str(root.count("WorldStage.set_epoch_reader(")))
	for raw_line in root.split("\n"):
		var l := String(raw_line)
		if l.contains("set_reconciler") or l.contains("set_epoch_reader"):
			_p("    stripped-root line: " + l)
	_p("=== PROBE END ===")
	assert_eq(true, true, "probe ran")


func _code_only(source: String) -> String:
	var kept: Array[String] = []
	var in_block := false
	for raw in source.split("\n"):
		var line := String(raw)
		if not in_block and line.strip_edges().begins_with("#"):
			continue
		var out := ""
		var at := 0
		var quote := ""
		while at < line.length():
			var character := line[at]
			if in_block:
				if line.substr(at, 3) == '"""':
					in_block = false
					at += 3
				else:
					at += 1
				continue
			if quote == "" and line.substr(at, 3) == '"""':
				in_block = true
				at += 3
				continue
			if quote == "" and (character == '"' or character == "'"):
				quote = character
				at += 1
				continue
			if quote != "":
				if character == "\\":
					at += 2
					continue
				if character == quote:
					quote = ""
				at += 1
				continue
			if character == "#":
				break
			out += character
			at += 1
		kept.append(out)
	return "\n".join(kept)
