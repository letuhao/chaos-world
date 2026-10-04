class_name ModBoot
extends Node

## The composition root's early mod step (ADR 0184).
##
## This node sits in `ItemWorkbenchApp.tscn` as a child of the app root, and
## children ready before their parent: so the load order is computed BEFORE
## `ItemWorkbenchApp._ready` runs any of its own wiring. That is the W2
## contract — compute, record, store `ctx`; do NOT staple registrations into
## boot yet (W3+).
##
## ## Failure policy
##
## A loader error is loud, not silent: the named cause is printed and the
## node refuses to pretend boot worked (`status.ok` false, empty order).
## First-party code keeps running unchanged because nothing is consumed yet —
## the seams' collected rows are read by the waves that wire them, not by this
## node.

## First-party optional modules (in-repo mods). Their `mod.json` files are
## discovered recursively by ContentScan; today there are none, so the empty
## order is the honest answer, not a missing directory.
const FIRST_PARTY_ROOT := "res://src/modules"
## Third-party external mods drop loose directories here. Absent directory is
## fine — it means "no external mods installed", not a load error.
const EXTERNAL_ROOT := "user://mods"

## The last successful pass, so later waves can read the SAME ctx the boot
## step stored without re-walking the roots. Static because a Node field
## belongs to one instance; the composition root owns that instance.
static var active_order: Array = []
static var active_contexts: Array = []

## Instance mirror of the pass, for the tests that drive `run()` without the
## scene. Primitives only in `status`.
var order: Array[String] = []
var contexts: Array = []
var status: Dictionary = {}


func _ready() -> void:
	run()


## Compute the load order over `roots()` and store it. Returns the loader
## dictionary: `{ok, order|reason, contexts}`. Public because tests drive it
## directly; production reaches it through `_ready`.
func run() -> Dictionary:
	status = ModsApi.load_order(roots())
	if bool(status.get("ok", false)):
		order.clear()
		for row in status["order"]:
			order.append(String(row))
		contexts = status.get("contexts", [])
		ModBoot.active_order = order.duplicate()
		ModBoot.active_contexts = contexts
	else:
		order = []
		contexts = []
		ModBoot.active_order = []
		ModBoot.active_contexts = []
		push_error("ModBoot: %s — %s" % [status.get("reason", ""), status.get("detail", "")])
	return status


## The roots this boot scans. External dir is listed only when it exists, so
## ContentScan never reads a directory that is not there.
func roots() -> Array:
	var out: Array = [FIRST_PARTY_ROOT]
	if DirAccess.dir_exists_absolute(EXTERNAL_ROOT):
		out.append(EXTERNAL_ROOT)
	return out
