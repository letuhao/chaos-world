class_name ContentScan
extends RefCounted

## Every file under `root`, recursively. ONE implementation for every catalog that
## loads authored `.tres` content from disk.
##
## Iterative, and depth-capped, for the same reason twice over. A recursive walk
## is a `while` in disguise, so `test_no_unbounded_wait.gd` cannot see it and a
## directory junction pointing at an ancestor would recurse until the stack
## died. An explicit worklist makes the traversal a loop the existing arch rule
## CAN check, and `MAX_DEPTH` caps what a malformed tree can cost even so.
##
## Why this is one shared function rather than ten local copies: every catalog
## had grown its own `_scan`, they had already drifted (some sorted the result,
## some recursed through `DirAccess.dir_exists_absolute` instead of
## `current_is_dir`), and a fix applied to one of them fixes exactly one of them.
## Content loading is a foundation concern, not a module concern, so it belongs
## in `core/`.

## A content tree deeper than this is a symlink loop, not content. Real authored
## data is one or two directories deep.
const MAX_DEPTH := 32

## Default filter: authored resources only. Pass "" to take every file.
const DEFAULT_SUFFIX := ".tres"


## Every file under `root` whose name ends with `suffix`, recursively, sorted.
##
## `suffix` of "" takes every file. Sorted so a catalog's load order never
## depends on `DirAccess` iteration order, which is not stable across platforms.
static func files_under(root: String, suffix: String = DEFAULT_SUFFIX) -> Array[String]:
	var out: Array[String] = []
	_walk(root, suffix, 0, out)
	out.sort()
	return out


## One directory level, resolved before returning: `DirAccess` holds an OS handle
## that must not stay open across a deeper listing, so "is this a directory" has
## to be answered while the listing is live.
static func _list(dir_path: String, depth: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if depth >= MAX_DEPTH:
		push_error(
			(
				(
					"ContentScan: %s is deeper than %d levels, so the rest was not read. "
					% [dir_path, MAX_DEPTH]
				)
				+ "A content tree that deep is a symlink loop, not content."
			)
		)
		return out
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if not entry.begins_with("."):
			(
				out
				. append(
					{
						"path": dir_path.path_join(entry),
						"is_dir": dir.current_is_dir(),
					}
				)
			)
		entry = dir.get_next()
	dir.list_dir_end()
	return out


## Recursive, but over a snapshot that is already resolved — so each level opens
## exactly one directory and the recursion depth is `MAX_DEPTH`, never the depth
## of whatever the tree happens to contain.
static func _walk(dir_path: String, suffix: String, depth: int, out: Array[String]) -> void:
	for entry in _list(dir_path, depth):
		if bool(entry["is_dir"]):
			_walk(String(entry["path"]), suffix, depth + 1, out)
		elif suffix.is_empty() or String(entry["path"]).ends_with(suffix):
			out.append(String(entry["path"]))


## `files_under` without the sort, for a caller that needs a different order.
static func files_under_unsorted(root: String, suffix: String = DEFAULT_SUFFIX) -> Array[String]:
	var out: Array[String] = []
	_walk(root, suffix, 0, out)
	return out
