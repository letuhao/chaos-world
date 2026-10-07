extends SceneTree

## Headless Yarn compiler (ADR 0862): reads a Yarn-shaped script, compiles it with
## [code]DialogueYarn[/code], and writes the resulting [code]DialogueDef[/code] as a
## `.tres` so authored content and Yarn content share ONE runtime.
##
## ## Why a driver rather than a Python parser
##
## Compilation needs the real `DialogueDef`/`DialogueNodeDef`/`DialogueCondition`
## resources, their export defaults and their validation — a Python re-implementation
## would be a SECOND compiler that could disagree with the runtime. So the engine does the
## work and the CLI only ferries arguments (ADR 0072's shape).
##
## ## Usage (never invoked by path — `tools dialogue compile` goes through
## ## `godot.run_godot`)
##
##   godot --headless --path game -s res://tools/dialogue_driver.gd -- \
##     --src <path.x.yarn> --npc <npc_id> --id <dialog_id> --out res://data/dialogue/<name>.tres
##
## One line is printed, prefixed `DIALOGUEJSON `, carrying `ok`, `out`, `nodes` and
## `problems`. A refusal prints the problems and exits non-zero, so a bad script fails
## loudly instead of writing a half-built conversation.

const PREFIX := "DIALOGUEJSON "
const EXIT_OK := 0
const EXIT_ERROR := 1


func _initialize() -> void:
	var src := ""
	var npc := ""
	var dialog := ""
	var out := ""
	var argv := OS.get_cmdline_user_args()
	var index := 0
	while index < argv.size():
		var flag := argv[index]
		var value := "" if index + 1 >= argv.size() else argv[index + 1]
		match flag:
			"--src":
				src = value
				index += 2
			"--npc":
				npc = value
				index += 2
			"--id":
				dialog = value
				index += 2
			"--out":
				out = value
				index += 2
			_:
				index += 1
	_report(_run(src, npc, dialog, out))


func _run(src: String, npc: String, dialog: String, out: String) -> Dictionary:
	for pair in [["src", src], ["npc", npc], ["id", dialog], ["out", out]]:
		if String(pair[1]) == "":
			return {"ok": false, "problems": ["missing --%s" % String(pair[0])]}
	if not FileAccess.file_exists(src):
		return {"ok": false, "problems": ["source file not found: %s" % src]}
	var handle := FileAccess.open(src, FileAccess.READ)
	if handle == null:
		return {"ok": false, "problems": ["cannot read: %s" % src]}
	var text := handle.get_as_text()
	handle.close()
	var compiled := DialogueYarn.compile(text, StringName(npc), StringName(dialog))
	if not bool(compiled.get("ok", false)):
		return {"ok": false, "problems": compiled.get("problems", [])}
	var def := compiled["def"] as DialogueDef
	var saved := ResourceSaver.save(def, out)
	if saved != OK:
		return {"ok": false, "problems": ["ResourceSaver refused %s (error %d)" % [out, saved]]}
	return {"ok": true, "out": out, "nodes": def.node_count(), "problems": []}


func _report(payload: Dictionary) -> void:
	print(PREFIX + JSON.stringify(payload))
	quit(EXIT_OK if bool(payload.get("ok", false)) else EXIT_ERROR)
