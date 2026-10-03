class_name TemplatePin
extends Resource

## One author-placed room in a domain template: which leaf it fills, and which
## authored `RoomDef` fills it.
##
## A pin exists because `settlement` and `boss` are STORY rooms (ADR 0073): whether a
## town's tavern exists is an author's decision, never a die. The generator places
## every other structural kind by rule and silently ignores a pin that names one.
##
## It is a top-level `class_name` rather than a nested class because a GDScript
## `@export` type must be a built-in, a `Resource`, a `Node` or an enum — an inner
## class cannot be one, so a nested pin could never be authored in a `.tres`.

## Index into the CANONICAL leaf order — center.y, then center.x, then birth index.
## Not a position on the grid: an author says "the third room in reading order", and
## the grid resolves where that is.
@export var leaf_index: int = 0

## What fills it. One of the template's `room_pool`; a pin naming a def outside the
## pool is a template error, and the generator ignores it rather than smuggling in
## content the shared kit does not have.
@export var room_def: RoomDef = null

## One of `RoomDef.KINDS`. `DomainTemplateDef.is_pinnable_kind` gates which of them
## are accepted; the structural kinds are placed by rule.
@export var kind: StringName = &"settlement"

## Optional display name for the realized room, when the template wants the map to
## read differently from the def it is built from. Empty keeps the def's own name.
@export var display_name: String = ""
