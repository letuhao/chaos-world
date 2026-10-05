class_name ModHookFixture
extends RefCounted

## A fixture script for attach hook callable tests. The static `fired` flag
## lets a test verify the callable was actually invoked.

static var fired := false


func on_attach() -> void:
	fired = true
