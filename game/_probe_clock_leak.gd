extends SceneTree

## Throwaway probe: does an ADVANCE persist into the next mount? Run:
## godot --headless -s res://_probe_clock_leak.gd


func _initialize() -> void:
	var harness_script := load("res://tests/ui/seam_harness.gd")
	var h1 = harness_script.mount_new()
	print("mount1 periods: ", (h1.app.summary() as Dictionary)["world"]["periods"])
	var rep = h1.app.call("advance_world", 1000)
	print("advance ok: ", rep.get("ok"), " moved: ", rep.get("moved"))
	print("mount1 after advance: ", (h1.app.summary() as Dictionary)["world"]["periods"])
	print("save summary after advance: ", JSON.stringify(SaveApi.summary()))
	h1.teardown()
	print("--- remount ---")
	var h2 = harness_script.mount_new()
	print("mount2 periods: ", (h2.app.summary() as Dictionary)["world"]["periods"])
	print("save summary: ", JSON.stringify(SaveApi.summary()))
	print("save dir listing:")
	var d := DirAccess.open("user://save")
	if d != null:
		for f in d.get_files():
			print("   ", f)
	h2.teardown()
	quit()
