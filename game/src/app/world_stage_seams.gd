class_name WorldStageSeams
extends RefCounted

## The two process-wide callables `WorldStage` is handed at boot, and the verbs that
## install and read them.
##
## Extracted from `WorldStage`, which had grown past the file budget. `WorldStage` keeps
## every one of these names as a one-line delegate, so nothing that calls the stage had to
## change — the same shape `WorldStageReconcile`'s reconciler and epoch-reader seams
## already use, and the reason their four wrappers stay where they are.
##
## **The seams are process-wide on purpose.** `app/` installs them once at boot rather
## than per mount, so `interact()` has a consumer from the first press rather than only
## after a travel; installing them in `mount` instead would leave a body that arrived by
## the composition root's own call one press short of doing anything.

## `app/` passes `func(actor, location_id, target_name) -> Dictionary`.
static var _handler: Callable = Callable()

## `app/` passes `Callable(EventApi, "set_location")`, taking `(actor, location_id)`.
static var _location_publisher: Callable = Callable()


## The interaction handler, or an empty `Callable` when none is installed. An empty one
## is not an error: a press is still received and still answers, with `no_handler`.
static func handler() -> Callable:
	return _handler


## Whether an interaction handler is installed.
static func has_handler() -> bool:
	return _handler.is_valid()


## Install the interaction seam. With nothing installed an interaction is still received
## and still returns a dictionary — it simply answers `no_handler`. That is the
## `HoldingsApi._resolve` posture: a null injection fails loudly with a named reason
## rather than dereferencing nothing (ADR 0002).
static func set_handler(handler: Callable) -> void:
	_handler = handler


## The location publisher, or an empty `Callable` when none is installed.
static func publisher() -> Callable:
	return _location_publisher


## Whether the world is being told where the player is. Published on `summary()` so a
## probe can tell "the seam is missing" from "the seam is installed and the event module
## refused the place".
static func has_publisher() -> bool:
	return _location_publisher.is_valid()


## Install the seam that tells the EVENT module where the player is.
##
## Passing an empty `Callable` clears the binding, so a test (or a boot order that
## deliberately runs without the event module) can uninstall it deterministically rather
## than only overwrite it — the `CombatBoot.set_attack_resolver` shape.
static func set_publisher(publisher: Callable) -> void:
	_location_publisher = publisher
