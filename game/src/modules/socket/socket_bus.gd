class_name SocketBus
extends RefCounted

## Change notifications for the socket subsystem. One process-wide bus so a
## listener (a screen, a test, an achievement hook) can observe a committed
## socket transaction without the module knowing who listens.
##
## Not a Godot autoload: the instance is created on first use and lives in the
## module, so the only global state is the notification channel itself.

signal socket_changed(result: Dictionary)

static var _shared: SocketBus = null


static func instance() -> SocketBus:
	if _shared == null:
		_shared = SocketBus.new()
	return _shared


## One coherent notification per committed or refused transaction, carrying the
## same result dictionary the facade returned. A mutation calls this exactly
## once, so a listener never sees a half-applied state and a refusal is as
## visible as a success.
static func publish(result: Dictionary) -> void:
	instance().socket_changed.emit(result.duplicate())
