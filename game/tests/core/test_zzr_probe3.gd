extends TestCase

## THROWAWAY PROBE 3: find which line leaves _code_only's quote state open.
const RECONCILE_SRC := "res://src/core/world_reconcile.gd"
const ROOT_SRC := "res://src/app/item_workbench_app.gd"
const OUT_PATH := "C:/Users/NeneScarlet/AppData/Local/Temp/commandcode/D--Works-source-chaos-world/5a3ee98f-1336-4e01-b255-fcfc71294075/scratchpad/probe3_out.txt"

var _out: FileAccess = null


func _p(text: String) -> void:
	if _out == null:
		_out = FileAccess.open(OUT_PATH, FileAccess.WRITE)
	if _out == null:
		return
	_out.store_line(text)
	_out.flush()


func _trace(path: String, label: String) -> void:
	var raw := FileAccess.get_file_as_string(path)
	var in_block := false
	var quote := ""
	var line_no := 0
	for l in raw.split("\n"):
		line_no += 1
		var line := String(l)
		var quote_before := quote
		var in_block_before := in_block
		if not in_block and line.strip_edges().begins_with("#"):
			continue
		var at := 0
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
			at += 1
		if quote_before == "" and quote != "":
			_p(label + " OPENS quote at line " + str(line_no) + ": " + line)
		elif quote_before != "" and quote == "":
			_p(label + " closes at line " + str(line_no))
	_p(label + " FINAL quote state = '" + quote + "' in_block=" + str(in_block))
	_p("")


func test_probe_quote_state() -> void:
	_trace(RECONCILE_SRC, "RECONCILE")
	_trace(ROOT_SRC, "ROOT")
	_p("=== END ===")
	assert_eq(true, true, "probe ran")
