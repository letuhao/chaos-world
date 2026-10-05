class_name TestModApi
extends RefCounted

## Fixture mod module api for the mod boot wiring test. The attach method
## is a no-op — the test asserts the module was registered and its api
## path is resolvable, not that attach produced a side effect.


static func attach(_actor: Actor) -> void:
	pass
