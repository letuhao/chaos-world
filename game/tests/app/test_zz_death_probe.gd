extends TestCase

## THROWAWAY probe (session diag-fate-cache): why does the death poll refuse to re-body?
## Delete before commit.


func test_zz_probe_death_poll() -> void:
	var harness := SeamHarness.mount_new()
	var app := harness.app as ItemWorkbenchApp
	var first := app.actor()
	print("PROBE[d] actor=%s boot_error=%s" % [first.id, harness.boot_error])
	print("PROBE[d] soul_state=%s" % str(SoulApi.state()))
	print("PROBE[d] soul=%s" % str(SoulApi.soul(first)))
	print("PROBE[d] verdict=%s" % str(SoulApi.verdict(first)))
	print("PROBE[d] guardian=%s" % str(SoulApi.spend_guardian(first)))
	print("PROBE[d] next_arrival=%s" % str(SoulApi.next_arrival(first)))
	var pool := first.resource(&"health")
	print("PROBE[d] health cur=%s max=%s" % [pool.current, pool.maximum])
	pool.change(-pool.maximum)
	print("PROBE[d] after kill health=%s is_dead=%s" % [
		first.resource(&"health").current, str(SoulDeath.new().is_dead(first))
	])
	var outcome := app.poll_death()
	print("PROBE[d] poll_death=%s" % str(outcome))
	print("PROBE[d] actor_after=%s" % app.actor().id)
	print("PROBE[d] arrival_def=%s" % str(SoulCatalog.instance().arrival_definition(SoulApi.next_arrival(first))))
	harness.teardown()
	assert_eq(true, true, "probe ran")
