extends TestCase

## THROWAWAY PROBE 2: why does _code_only drop the refusal message?
const RECONCILE_SRC := "res://src/core/world_reconcile.gd"
const OUT_PATH := "C:/Users/NeneScarlet/AppData/Local/Temp/commandcode/D--Works-source-chaos-world/5a3ee98f-1336-4e01-b255-fcfc71294075/scratchpad/probe2_out.txt"
const ROOT_SRC := "res://src/app/item_workbench_app.gd"

var _out: FileAccess = null


func _p(text: String) -> void:
	if _out == null:
		_out = FileAccess.open(OUT_PATH, FileAccess.WRITE)
	if _out == null:
		return
	_out.store_line(text)
	_out.flush()


func test_probe_code_only() -> void:
	var raw := FileAccess.get_file_as_string(RECONCILE_SRC)
	var code := _code_only(raw)
	_p("code len=" + str(code.length()))
	_p("has 'No stamp was written'=" + str(code.contains("No stamp was written")))
	_p("has '% [asked, MAX_PLACES]'=" + str(code.contains("% [asked, MAX_PLACES]")))
	_p("push_error count=" + str(code.count("push_error(")))
	_p("--- every stripped line mentioning stamp was / decade old / asked for ---")
	for line in code.split("\n"):
		var l := String(line)
		if l.contains("stamp was written") or l.contains("decade old") or l.contains("asked for"):
			_p("  [" + l + "]")
	_p("--- RAW lines around 202-212 with an index ---")
	var lines := raw.split("\n")
	for i in range(199, 213):
		if i < lines.size():
			_p("  RAW " + str(i + 1) + ": " + String(lines[i]))
	_p("--- ROOT seam lines ---")
	var root_raw := FileAccess.get_file_as_string(ROOT_SRC)
	var root := _code_only(root_raw)
	_p("root len=" + str(root.length()))
	for line in root.split("\n"):
		var l := String(line)
		if l.contains("set_reconciler") or l.contains("set_epoch_reader"):
			_p("  [" + l + "]")
	_p("=== END ===")
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
