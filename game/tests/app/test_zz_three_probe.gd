extends TestCase

## THROWAWAY probe (session diag-fate-cache): why do 3 cases still fail?
## Delete before commit.


func test_zz_probe_three_left() -> void:
	var harness := SeamHarness.mount_new()
	var app := harness.app as ItemWorkbenchApp
	var origin := StringName(FateCatalog.instance().destinies_in_group(&"origin")[0])
	print("PROBE[3] origin=%s" % origin)
	var body := app.actor()
	DestinyApi.attach(body)
	var ledger := DestinyApi.earn_destiny(body, origin, "test")
	print("PROBE[3] ledger_after_earn=%s" % str(ledger))
	print(
		(
			"PROBE[3] has_destiny=%s destinies=%s"
			% [DestinyApi.has_destiny(body, origin), str(DestinyApi.destinies(body))]
		)
	)
	var def := FateCatalog.instance().destiny_definition(origin)
	print(
		(
			"PROBE[3] def=%s group=%s requires_fates=%s requires_destinies=%s"
			% [def.id, def.group, str(def.requires_fates), str(def.requires_destinies)]
		)
	)
	print(
		(
			"PROBE[3] earnable=%s unmet=%s"
			% [
				str(DestinyGate.earnable(ledger, def)),
				str(DestinyGate.unmet_prerequisites(ledger, def)),
			]
		)
	)
	harness.teardown()
	assert_eq(true, true, "probe ran")
