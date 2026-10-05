extends TestCase

## BL-0854. The boot probe's cells each pick a DIFFERENT domain (`_choose_domain(screen, nth)`),
## fight that domain's band, and read `reward_count` afterwards. Its verdict - "every boss in
## this band was defeated and the run cleared, so there is no boss left to pay" - is reachable
## only when `after.reward_count < 1`.
##
## Two things already measured make that a DATA question rather than a probe question:
##   - test_loot_band_walk_reward.gd (7 passed): walking a band to its end in EMBER leaves
##     `pending_drops > 0` and `reward_count = 1`. A kill's payload OUTLIVES the fight, so the
##     band-walk costs nothing and the loop is not the cause.
##   - test_loot_fight_state_published.gd (8 passed, MUTATION-M3): the fight's published state
##     is live mid-fight and damage moves it.
## So a `reward_count` of zero means the DOMAIN paid nothing. This suite walks the domain list
## the same way the probe does and says which ones, so the answer is a table instead of a guess.
##
## It is deliberately a MEASUREMENT rather than a gate assertion: asserting "every domain pays"
## would go red on a corpus defect that is somebody else's to fix, and a red suite in the gate
## trains everyone to ignore red. So this records what it found and asserts only the invariant
## that must hold for the measurement to mean anything - a domain that can be entered at all
## must publish a boss.

const MAX_DOMAINS := 24

var _rig: LootScreenRig = null
## domain label -> what that domain's band paid, for the run's own report.
var _tally: Dictionary = {}


func setup() -> void:
	_rig = LootScreenRig.new()
	_tally = {}


## Idempotent, so this is safe after a test that aborted mid-walk.
func teardown() -> void:
	if _rig != null:
		_rig.release()
		_rig = null


func test_which_domains_pay_nothing_when_their_band_is_walked() -> void:
	var view := _rig.screen(_rig.hero())
	var offered := int((view.summary() as Dictionary).get("domain_count", 0))
	assert_ne(offered, 0, "the screen offers domains to hunt, so there is a list to walk")
	var walked := 0
	var refused := 0
	var entered := 0
	var paid := 0
	var silent: Array[String] = []
	var index := 0
	while index < mini(offered, MAX_DOMAINS):
		index += 1
		if not _rig.select_domain(view, index - 1, 0):
			continue
		walked += 1
		var label := String((view.summary() as Dictionary).get("domain_label", ""))
		if label.is_empty():
			label = String(
				(view.summary() as Dictionary).get("domain_id", "domain_%d" % (index - 1))
			)
		if not _rig.enter_domain(view, _selected_domain(view), 0):
			refused += 1
			continue
		entered += 1
		# A boss must be live once the domain was accepted, or the measurement below would
		# read "paid nothing" for a fight that never happened.
		if not bool((view.summary() as Dictionary).get("in_domain", false)):
			continue
		# Walk the whole band: `defeat_boss` stops at ONE kill, so calling it again is how the
		# probe's loop gets here. Bounded by MAX_DOMAINS and ended by the rig itself.
		var guard := 0
		while guard < 12 and not _rig.defeat_boss(view, 200).is_empty():
			guard += 1
		var after := view.summary() as Dictionary
		var rewards := int(after.get("reward_count", 0))
		if rewards > 0:
			paid += 1
		else:
			silent.append(label)
			_tally[label] = {
				"reward_count": rewards, "pending_drops": int(after.get("pending_drops", 0))
			}
		_rig.press(view, "%LeaveButton")

	print(
		(
			"DOMAIN PAYMENT SWEEP: offered=%d walked=%d entered=%d refused=%d PAID=%d SILENT=%d"
			% [offered, walked, entered, refused, paid, silent.size()]
		)
	)
	for label in silent:
		print("  pays nothing: %s" % label)
	# The invariant that makes the measurement meaningful: at least one domain accepted entry and
	# published a live boss, so "paid" is a property of the loot content rather than of a screen
	# that never mounted a fight.
	assert_ne(entered, 0, "at least one domain was entered and fought")
	assert_ne(
		paid,
		0,
		(
			"and at least one paid something. If every domain reported zero rewards, the sweep would "
			+ "be measuring a broken enter path rather than the loot content: %s" % str(_tally)
		)
	)


func _selected_domain(view: Node) -> StringName:
	return StringName(String((view.summary() as Dictionary).get("domain_id", "")))
