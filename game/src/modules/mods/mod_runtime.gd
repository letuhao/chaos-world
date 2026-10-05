class_name ModRuntime
extends RefCounted

## Fold every mod's RegistrationContext into the boot's runtime registrations
## (ADR 0184). One call, in load order, produces the four collections the
## composition root consumes: per-family content roots for the catalog overlay
## stack, the module attach order, the screen routes and the attach hooks.
##
## Pure aggregation: no clocks, no caches, no engine calls beyond the registry
## the caller already holds. Same contexts in the same order, same result.


## Aggregate `contexts` (in load order) into the runtime registrations.
## `registry` is the shared ModuleRegistry the contexts registered through.
## Returns `{content_roots, modules, screens, attach_hooks, subscriptions}`:
##   content_roots: {family: Array[{dir, owner, declared_overrides}]}
##   modules: ModuleRegistry.order() — {ok, order, reason, detail}
##   screens: Array[{id, scene_path, label}]
##   attach_hooks: Array[{phase, callable}]
##   subscriptions: Array[{event_bus, event_name, callable}]
static func finalize(contexts: Array, registry: ModuleRegistry) -> Dictionary:
	var content_roots := {}
	var screens: Array[Dictionary] = []
	var attach_hooks: Array[Dictionary] = []
	var subscriptions: Array[Dictionary] = []
	for ctx in contexts:
		if ctx == null:
			continue
		for family in ctx.content_roots:
			if not content_roots.has(family):
				content_roots[family] = []
			for row in ctx.content_roots[family]:
				(content_roots[family] as Array).append(row)
		for row in ctx.screens:
			(
				screens
				. append(
					{
						"id": String(row.get("id", "")),
						"scene_path": String(row.get("scene", "")),
						"label": String(row.get("label", "")),
					}
				)
			)
		for row in ctx.attach_hooks:
			(
				attach_hooks
				. append(
					{
						"phase": String(row.get("phase", "")),
						"callable": row.get("hook", Callable()),
					}
				)
			)
		for row in ctx.subscriptions:
			(
				subscriptions
				. append(
					{
						"event_bus": String(row.get("event_bus", "")),
						"event_name": String(row.get("event_name", "")),
						"callable": row.get("callable", Callable()),
					}
				)
			)
	return {
		"content_roots": content_roots,
		"modules": registry.order(),
		"screens": screens,
		"attach_hooks": attach_hooks,
		"subscriptions": subscriptions,
		"registry": registry,
	}
