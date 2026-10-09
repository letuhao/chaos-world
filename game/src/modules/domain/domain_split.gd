class_name DomainSplit
extends RefCounted

## Where a rect may be cut, and the two rects a cut produces.
##
## Extracted from `DomainGenerator`, which had grown past the file budget. This is the
## geometry a partition decides with: typed on `Rect2i` and the authored template alone,
## so it depends on no cell and no tree — which is what lets it live outside the generator
## while the cell-walking families cannot.
##
## **A legal cut is the whole subject.** A split that would leave a child under `min_leaf`
## is not a smaller split, it is an illegal one: `preferred_axis` answers what a rect
## WANTS, `axis_legal` answers whether that axis can legally be cut, and a repeat-axis roll
## that lands on an illegal orientation falls back to the other one, so the roll only ever
## adds variety.


## The axis `rect` prefers, `&"x"` or `&"y"`, or `&""` when neither can take a cut that
## leaves two legal children. X wins a tie, because a horizontal cut of a square reads as
## the first slice of a grid.
static func preferred_axis(rect: Rect2i, template: DomainTemplateDef) -> StringName:
	var needed := template.min_leaf + template.margin * 2
	if rect.size.x >= rect.size.y and rect.size.x >= needed * 2:
		return &"x"
	if rect.size.y >= needed * 2:
		return &"y"
	return &""


## Whether `axis` can legally be cut: the rect must be at least twice the margin the
## template needs on that axis, so both children clear `min_leaf`.
static func axis_legal(rect: Rect2i, template: DomainTemplateDef, axis: StringName) -> bool:
	var needed := template.min_leaf + template.margin * 2
	return rect.size.x >= needed * 2 if axis == &"x" else rect.size.y >= needed * 2


## Two rects covering `rect`, the first `first` tiles along the split axis. Empty when
## the split would leave a child under `min_leaf`.
static func split_rects(rect: Rect2i, axis: StringName, first: int) -> Array[Rect2i]:
	if first <= 0:
		return [] as Array[Rect2i]
	if axis == &"x":
		if first >= rect.size.x:
			return [] as Array[Rect2i]
		return (
			[
				Rect2i(rect.position, Vector2i(first, rect.size.y)),
				Rect2i(
					Vector2i(rect.position.x + first, rect.position.y),
					Vector2i(rect.size.x - first, rect.size.y)
				),
			]
			as Array[Rect2i]
		)
	if first >= rect.size.y:
		return [] as Array[Rect2i]
	return (
		[
			Rect2i(rect.position, Vector2i(rect.size.x, first)),
			Rect2i(
				Vector2i(rect.position.x, rect.position.y + first),
				Vector2i(rect.size.x, rect.size.y - first)
			),
		]
		as Array[Rect2i]
	)
