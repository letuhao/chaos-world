class_name W8LifecycleProbe
extends RefCounted

## A fixture callable for the lifecycle-hook seam. The loader mints the instance
## through a manifest's `callable` spec, so the static record is the only way a
## test can see WHICH hooks ran and what context each was handed.

static var calls: Array[Dictionary] = []


func on_load(ctx: RegistrationContext) -> void:
	calls.append({"event": "on_load", "ctx": ctx, "mod_id": ctx.mod_id})


func on_save(ctx: RegistrationContext) -> void:
	calls.append({"event": "on_save", "ctx": ctx, "mod_id": ctx.mod_id})
