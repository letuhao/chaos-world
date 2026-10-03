extends TestCase

## PROBE: what does the layout actually place, and in which direction is a route
## emitted? Temporary diagnostic — deleted once the cause is fixed.


func test_probe_layout() -> void:
	var map := DomainMap.new(Vector2i(40, 32), 5)
	var west := RoomDef.new()
	west.room_id = &"west"
	west.kind = &"floor"
	west.roster_band = &"empty"
	west.size = Vector2i(4, 4)
	west.exits = [&"east"] as Array[StringName]
	map.add_room(west)
	var east := RoomDef.new()
	east.room_id = &"east"
	east.kind = &"floor"
	east.roster_band = &"empty"
	east.size = Vector2i(4, 4)
	east.exits = [&"west"] as Array[StringName]
	map.add_room(east)
	map.entry_room = &"west"

	var rects := DomainPaths.layout(map)
	print("PROBE entry_room=%s" % String(map.entry_room))
	print("PROBE rects=%s" % str(rects))
	var routes := DomainPaths.routes(map)
	for route in routes:
		print("PROBE route from=%s to=%s points=%s" % [route["from"], route["to"], str(route["points"])])
	assert_eq(true, true, "probe")