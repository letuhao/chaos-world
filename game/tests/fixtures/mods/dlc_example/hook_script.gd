class_name DlcExampleHook
extends RefCounted

## A fixture script for the DLC example mod's attach hook (ADR 0184). The
## static `fired` flag lets a test verify the callable was actually invoked.
##
## The hook takes the ACTOR because that is the contract: `AttachPipeline` invokes every
## hook with the actor it is attaching. A zero-argument hook was the arity error
## "Invalid call to function 'on_dlc_boot (via call)' … Expected 0 argument(s)" on every
## manifest-hook run.

static var fired := false


func on_dlc_boot(_actor: Actor) -> void:
	fired = true
