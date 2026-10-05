class_name ItemStateStore
extends RefCounted

## File-backed item state for the playable shell (ADR 0027).
##
## The UI program never touches the filesystem: the workbench asks its injected
## callables to save and to load, and this is what those callables are. One place
## owns the path, the encoding and the "did it work" wording, so the composition root
## wires two callables instead of knowing what a save file is.
##
## The format is the facade's own `ItemsApi.serialize` payload, passed through
## untouched. Nothing here interprets it, so a save can never change what is saved.

const SAVE_PATH := "user://item_workbench_state.json"


## Write `payload` as the saved state. Returns "" on success, or the reason it failed
## so the caller can show it rather than swallowing a lost save.
func save(payload: Dictionary) -> String:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		return "cannot open %s" % SAVE_PATH
	file.store_string(JSON.stringify(payload))
	file.close()
	return ""


## The saved state, or `{}` when there is none or it is unreadable. An unreadable file
## reads as "nothing saved" rather than as an error the player has to act on: the
## workbench reports "no saved state" and the player saves again.
func load() -> Dictionary:
	if not FileAccess.file_exists(SAVE_PATH):
		return {}
	var text := FileAccess.get_file_as_string(SAVE_PATH)
	var parsed = JSON.parse_string(text)
	return parsed if parsed is Dictionary else {}
