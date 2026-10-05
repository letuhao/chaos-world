class_name DlcExampleHook
extends RefCounted

## A fixture script for the DLC example mod's attach hook (ADR 0184). The
## static `fired` flag lets a test verify the callable was actually invoked.

static var fired := false


func on_dlc_boot() -> void:
	fired = true
