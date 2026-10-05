extends TestCase

## THROWAWAY PROBE 4: strip lines 195-215 in isolation and in full context.
const RECONCILE_SRC := "res://src/core/world_reconcile.gd"
const OUT_PATH := "C:/Users/NeneScarlet/AppData/Local/Temp/commandcode/D--Works-source-chaos-world/5a3ee98f-1336-4e01-b255-fcfc71294075/scratchpad/probe4_out.txt"

var _out: FileAccess = null


func _p(text: String) -> void:
	if _out == null:
		_out = FileAccess.open(OUT_PATH, FileAccess.WRITE)
	if _out == null:
		return
	_out.store_line(text)
	_out.flush()


func test_probe_slice() -> void:
	var raw := FileAccess.get_file_as_string(RECONCILE_SRC)
	var lines := raw.split("\n")
	_p("total raw lines=" + str(lines.size()))
	_p("--- stripped output of lines 196..215 (1-indexed), full-file context ---")
	var code := _code_only(raw)
	var code_lines := code.split("\n")
	_p("total stripped lines=" + str(code_lines.size()))
	for i in range(code_lines.size()):
		var cl := String(code_lines[i])
		if (
			cl.contains("push_error")
			or cl.contains("MAX_PLACES")
			or cl.contains("decade")
			or cl.contains("stamp was")
			or cl.contains("truncating")
		):
			_p("  stripped[" + str(i + 1) + "]: " + cl)
	_p("--- does ANY stripped line contain the word 'written'? ---")
	var hit := 0
	for i in range(code_lines.size()):
		if String(code_lines[i]).contains("written"):
			hit += 1
			_p("  stripped[" + str(i + 1) + "]: " + String(code_lines[i]))
	_p("  count=" + str(hit))
	_p("--- isolate: strip ONLY raw lines 199-213 joined ---")
	var slice_lines: Array[String] = []
	for i in range(198, 213):
		slice_lines.append(String(lines[i]))
	_p("  ISOLATED: " + _code_only("\n".join(slice_lines)))
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
