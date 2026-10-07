class_name QiTestKit
extends RefCounted

## The one LOUD door to an actor's dantian in tests (BL-0807).
##
## `QiAccess.dantian` returns null for an actor the qi path never attached, and 64 test
## call sites dereferenced it with no guard: a regression in `QiCultivationApi.attach`
## then became a SCRIPT ERROR that aborted the test body, and the runner could only
## report an unnamed abort with the remaining assertions skipped. This helper fails AT
## THE CALL with the actor's id, so the message names the fixture rather than a line.
##
## Use it wherever a test DEREFERENCES a dantian. An assertion that expects null
## (`assert_eq(QiAccess.dantian(actor), null, ...)`) must keep calling the accessor
## directly: this helper exists to refuse that state, not to observe it.


static func dantian(actor: Actor) -> Dantian:
	var found := QiAccess.dantian(actor)
	assert(
		found != null,
		(
			"QiTestKit.dantian: '%s' has no dantian - attach the qi path before using it"
			% ("" if actor == null else String(actor.id))
		)
	)
	return found
