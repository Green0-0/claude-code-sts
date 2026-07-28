extends Node

## Assertions for the combat maths. Run with:
##   godot --headless -- --rules-test
##
## These lock down the numbers that everything else depends on: damage scaling
## order, block, status decay, poison, energy and card text generation.

var passed: int = 0
var failed: int = 0


func _ready() -> void:
	print("[rules] running")
	_run()
	print("[rules] %d passed, %d failed" % [passed, failed])
	get_tree().quit(1 if failed > 0 else 0)


func _check(label: String, got, want) -> void:
	if got == want:
		passed += 1
	else:
		failed += 1
		print("[rules] FAIL %s: got %s, want %s" % [label, str(got), str(want)])


func _fresh_combat(enemy_ids: Array = ["jaw_worm"]) -> Combat:
	Run.start_run("ironclad", 1234)
	var c := Combat.new()
	c.setup(enemy_ids, "monster", Run.rng)
	return c


func _run() -> void:
	_test_damage_order()
	_test_block()
	_test_statuses()
	_test_poison()
	_test_piles()
	_test_card_text()
	_test_energy_and_costs()
	_test_upgrades()


func _test_damage_order() -> void:
	var c := _fresh_combat()
	var p := c.player
	var e: Actor = c.enemies[0]

	_check("plain strike", c.calc_attack_damage(6, p, e, null, 1), 6)

	p.add_signed_status("strength", 2)
	_check("strength adds flat", c.calc_attack_damage(6, p, e, null, 1), 8)

	# Weak is applied to the attacker after Strength: floor(8 * 0.75) = 6
	p.add_status("weak", 1)
	_check("weak after strength", c.calc_attack_damage(6, p, e, null, 1), 6)

	# Then Vulnerable on the defender: floor(6 * 1.5) = 9
	e.add_status("vulnerable", 1)
	_check("vulnerable after weak", c.calc_attack_damage(6, p, e, null, 1), 9)

	p.set_status("weak", 0)
	_check("vulnerable only", c.calc_attack_damage(6, p, e, null, 1), 12)

	# Heavy Blade counts Strength three times: 14 + 2*3 = 20, then vulnerable.
	p.set_status("vulnerable", 0)
	e.set_status("vulnerable", 0)
	_check("heavy blade str x3", c.calc_attack_damage(14, p, e, null, 3), 20)

	# Flight halves incoming attack damage (Strength cleared so 9 -> 4).
	p.set_status("strength", 0)
	e.add_status("flight", 3)
	_check("flight halves", c.calc_attack_damage(9, p, e, null, 1), 4)
	e.set_status("flight", 0)

	# Potion damage ignores Strength and Weak but not Vulnerable.
	p.add_signed_status("strength", 5)
	p.add_status("weak", 1)
	e.add_status("vulnerable", 1)
	_check("unscaled ignores strength and weak, keeps vulnerable",
			c.calc_attack_damage(20, p, e, null, 1, true), 30)
	_check("scaled version differs",
			c.calc_attack_damage(20, p, e, null, 1, false), 27)


func _test_block() -> void:
	var c := _fresh_combat()
	var p := c.player
	_check("plain block", c.calc_block(5, p), 5)
	p.add_signed_status("dexterity", 2)
	_check("dexterity adds", c.calc_block(5, p), 7)
	p.add_status("frail", 1)
	_check("frail after dexterity", c.calc_block(5, p), 5)

	# Block absorbs damage before HP, and the excess carries through.
	var e: Actor = c.enemies[0]
	p.set_status("frail", 0)
	p.set_status("dexterity", 0)
	p.block = 10
	var hp_before := p.hp
	var through: int = c._damage(p, 4, e, "attack", null)
	_check("block absorbs all", through, 0)
	_check("block reduced", p.block, 6)
	_check("hp untouched", p.hp, hp_before)
	through = c._damage(p, 10, e, "attack", null)
	_check("overflow through block", through, 4)
	_check("block emptied", p.block, 0)
	_check("hp took overflow", p.hp, hp_before - 4)

	# HP loss ignores block entirely.
	p.block = 20
	c._lose_hp(p, 3, "test")
	_check("hp loss ignores block", p.block, 20)
	_check("hp loss applied", p.hp, hp_before - 7)


func _test_statuses() -> void:
	var c := _fresh_combat()
	var p := c.player
	var e: Actor = c.enemies[0]

	# Artifact eats one debuff, then stops.
	e.add_status("artifact", 1)
	c._apply_status(e, "vulnerable", 2, p)
	_check("artifact blocks debuff", e.get_status("vulnerable"), 0)
	_check("artifact consumed", e.get_status("artifact"), 0)
	c._apply_status(e, "vulnerable", 2, p)
	_check("debuff lands after artifact", e.get_status("vulnerable"), 2)

	# Artifact does not block buffs.
	e.add_status("artifact", 1)
	c._apply_status(e, "strength", 2, p)
	_check("artifact ignores buffs", e.get_status("strength"), 2)
	_check("artifact kept", e.get_status("artifact"), 1)

	# Turn-based debuffs tick down; permanent ones do not.
	p.add_status("vulnerable", 2)
	p.add_signed_status("strength", 3)
	c._decay_statuses(p)
	_check("vulnerable decays", p.get_status("vulnerable"), 1)
	_check("strength persists", p.get_status("strength"), 3)

	# Strength can go negative (Disarm, Siphon Soul).
	p.add_signed_status("strength", -5)
	_check("strength goes negative", p.get_status("strength"), -2)

	# Thorns hits back on attacks only.
	var e2: Actor = c.enemies[0]
	e2.add_status("thorns", 3)
	e2.block = 0
	var php := p.hp
	c._damage(e2, 1, p, "attack", null)
	_check("thorns retaliates", p.hp, php - 3)
	php = p.hp
	c._damage(e2, 1, p, "poison", null)
	_check("thorns ignores poison", p.hp, php)


func _test_poison() -> void:
	var c := _fresh_combat()
	var e: Actor = c.enemies[0]
	e.block = 99
	e.add_status("poison", 4)
	var hp_before := e.hp
	c._tick_poison(e)
	_check("poison ignores block", e.hp, hp_before - 4)
	_check("poison decays", e.get_status("poison"), 3)
	_check("poison left block alone", e.block, 99)


func _test_piles() -> void:
	var c := _fresh_combat()
	# A fresh Ironclad deck is 10 cards; 5 are drawn on turn 1.
	_check("hand size turn 1", c.hand.size(), 5)
	_check("draw pile turn 1", c.draw_pile.size(), 5)
	_check("energy turn 1", c.energy, 3)

	# Emptying the draw pile reshuffles the discard pile into it.
	while c.draw_pile.size() > 0:
		c.discard_pile.append(c.draw_pile.pop_back())
	var total := c.discard_pile.size()
	c._draw(1)
	_check("reshuffled on empty draw", c.draw_pile.size(), total - 1)
	_check("discard emptied", c.discard_pile.size(), 0)

	# The hand caps at 10 cards.
	while c.hand.size() < Combat.HAND_LIMIT:
		c.hand.append(Card.create("strike"))
	var overflow := Card.create("defend")
	c._put_in_hand(overflow)
	_check("hand limit respected", c.hand.size(), Combat.HAND_LIMIT)
	_check("overflow discarded", c.discard_pile.has(overflow), true)


func _test_card_text() -> void:
	# The printed numbers must track upgrades.
	var strike := Card.create("strike")
	_check("strike text", strike.rules_text(null), "Deal 6 damage.")
	strike.upgrade()
	_check("strike+ text", strike.rules_text(null), "Deal 9 damage.")
	_check("strike+ name", strike.display_name(), "Strike+")

	# Singular / plural agreement.
	var warcry := Card.create("warcry")
	_check("singular card", warcry.rules_text(null).contains("Draw 1 card."), true)
	warcry.upgrade()
	_check("plural cards", warcry.rules_text(null).contains("Draw 2 cards."), true)

	# Flags are appended to the text automatically.
	_check("exhaust noted", warcry.rules_text(null).contains("Exhaust"), true)
	var carnage := Card.create("carnage")
	_check("ethereal noted", carnage.rules_text(null).begins_with("Ethereal."), true)

	# Live previews use combat state.
	var c := _fresh_combat()
	c.player.add_signed_status("strength", 3)
	var s2 := Card.create("strike")
	_check("preview includes strength", s2.rules_text(c), "Deal 9 damage.")

	# Body Slam reads the current Block.
	c.player.block = 17
	var slam := Card.create("body_slam")
	_check("body slam previews block",
			slam.rules_text(c).contains("(20)"), true)


func _test_energy_and_costs() -> void:
	var c := _fresh_combat()
	var p := c.player

	# Corruption makes skills free.
	var defend := Card.create("defend")
	_check("defend costs 1", defend.cost(c), 1)
	p.add_status("corruption", 1)
	_check("corruption frees skills", defend.cost(c), 0)
	p.set_status("corruption", 0)

	# Blood for Blood gets cheaper each time you lose HP.
	var bfb := Card.create("blood_for_blood")
	_check("blood for blood base", bfb.cost(c), 4)
	c.hp_loss_events = 2
	_check("blood for blood discounted", bfb.cost(c), 2)

	# X-cost cards spend everything.
	var whirl := Card.create("whirlwind")
	_check("whirlwind is X cost", whirl.is_x_cost(), true)
	c.hand.append(whirl)
	c.energy = 3
	c.play_card(whirl, 0)
	_check("X cost drained energy", c.energy, 0)

	# Unplayable cards are refused.
	var wound := Card.create("wound")
	c.hand.append(wound)
	_check("wound unplayable", c.can_play(wound, 0)["ok"], false)


func _test_upgrades() -> void:
	# Most cards upgrade once.
	var bash := Card.create("bash")
	_check("bash upgradable", bash.can_upgrade(), true)
	bash.upgrade()
	_check("bash not twice", bash.can_upgrade(), false)
	_check("bash+ damage", int(bash.raw_params()["dmg"]), 10)

	# Searing Blow upgrades without limit: 12 + n(n+7)/2.
	var sb := Card.create("searing_blow")
	sb.upgrade()
	_check("searing blow +1", int(sb.raw_params()["dmg"]), 16)
	sb.upgrade()
	_check("searing blow +2", int(sb.raw_params()["dmg"]), 21)
	sb.upgrade()
	_check("searing blow +3", int(sb.raw_params()["dmg"]), 27)
	_check("searing blow still upgradable", sb.can_upgrade(), true)
	_check("searing blow name", sb.display_name(), "Searing Blow+3")

	# Curses and status cards never upgrade.
	_check("curse not upgradable", Card.create("regret").can_upgrade(), false)

	# Upgrades that change cost rather than numbers.
	var entrench := Card.create("entrench")
	_check("entrench cost", entrench.base_cost(), 2)
	entrench.upgrade()
	_check("entrench+ cost", entrench.base_cost(), 1)

	# Upgrades that widen targeting.
	var blind := Card.create("blind")
	_check("blind single target", blind.effective_target_kind(), "enemy")
	blind.upgrade()
	_check("blind+ hits all", blind.effective_target_kind(), "all")
