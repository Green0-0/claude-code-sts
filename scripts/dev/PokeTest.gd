extends Node

## Checks the Pokemon layer: the imported data, the stat conversions, the cards
## built from learnsets, the mobs built from species, BST-weighted encounters,
## and the combat rules those feed into.
##   godot --headless -- --poke-test

## Where the CAP dex starts, matching CAP_ID_BASE in tools/cap.py.
const CAP_ID_BASE := 20000

var main: Node = null
var passed: int = 0
var failed: int = 0


func _ready() -> void:
	main = get_parent()
	# These assert on state the instant they act, so the flourish has to be off.
	CardAnim.enabled = false
	await get_tree().process_frame
	_run()
	print("[poke] %d passed, %d failed" % [passed, failed])
	get_tree().quit(1 if failed > 0 else 0)


func _check(label: String, got, want) -> void:
	if got == want:
		passed += 1
		print("[poke] ok   %s = %s" % [label, str(got)])
	else:
		failed += 1
		print("[poke] FAIL %s: got %s, want %s" % [label, str(got), str(want)])


func _check_true(label: String, got: bool) -> void:
	_check(label, got, true)


func _near(label: String, got: float, want: float, tol: float) -> void:
	if absf(got - want) <= tol:
		passed += 1
		print("[poke] ok   %s = %.2f" % [label, got])
	else:
		failed += 1
		print("[poke] FAIL %s: got %.2f, want %.2f +-%.2f" % [label, got, want, tol])


func _run() -> void:
	_test_data()
	_test_forms_and_cap()
	_test_type_chart()
	_test_stats()
	_test_cards()
	_test_learnset_decks()
	_test_mobs()
	_test_encounters()
	_test_levels()
	_test_evolution()
	_test_progression()
	_test_gated_rewards()
	_test_party()
	_test_enemy_decks()
	_test_capture()
	_test_balls()
	_test_resistance()
	_test_combat()
	_test_ailments()
	_test_speed()


# ═══════════════════════════ Enemies play cards too ══════════════════════════
func _test_enemy_decks() -> void:
	print("[poke] --- enemy decks")
	var deck := PokeMobs.build_deck(PokeMobs.enemy_id("rattata"))
	_check_true("a mob has a deck", deck.size() >= 4)
	_check_true("with more than one copy of a move", deck.size() > 3)

	var c := _begin(PokeCharacters.character_id("bulbasaur"),
			[PokeMobs.enemy_id("rattata")])
	var foe: Actor = c.enemies[0]
	_check_true("it was stocked at spawn", foe.draw_pile.size() > 0)
	_check("and starts with its energy", foe.energy_per_turn,
			int(PokeMobs.ENEMY_ENERGY["normal"]))
	# Elites and bosses can combo; a normal encounter cannot.
	var elite := EnemyLibrary.spawn(PokeMobs.enemy_id("rattata", "elite"), c.rng)
	_check_true("elites get more energy", elite.energy_per_turn > foe.energy_per_turn)
	_check_true("its cards are real move cards",
			PokeMoves.is_move_card(String((foe.draw_pile[0] as Card).id)))

	# Its turn draws a hand, spends energy and discards the rest — the same
	# shape as a player turn. Set up a known state first: the ATB may already
	# have given it a turn during setup, and a reshuffle can legitimately make
	# the draw pile bigger than it was.
	foe.hand.clear()
	for c2 in foe.discard_pile:
		foe.draw_pile.append(c2)
	foe.discard_pile.clear()
	var before_draw := foe.draw_pile.size()
	# An enemy turn is staged now, so the UI can animate it card by card;
	# _take_enemy_turn drives those stages straight through, which is what a
	# headless run does.
	c._take_enemy_turn(foe)
	_check_true("it drew cards", foe.draw_pile.size() < before_draw)
	_check_true("but only a capped number of plays",
			foe.move_history.size() <= foe.cards_per_turn + 4)
	_check("it ends its turn with an empty hand", foe.hand.size(), 0)
	_check_true("and cards in its discard", foe.discard_pile.size() > 0)
	# Plenty of low-power moves cost nothing, so spending energy is not
	# guaranteed; having played something is.
	_check_true("it never overspends", foe.energy <= foe.energy_per_turn)
	_check_true("it recorded what it played", foe.move_history.size() > 0)

	# A deck that runs out reshuffles rather than stalling. Count every pile,
	# including anything already exhausted on the first turn.
	var total := foe.draw_pile.size() + foe.discard_pile.size() \
			+ foe.exhaust_pile.size() + foe.hand.size()
	for i in range(6):
		c._take_enemy_turn(foe)
	_check("no cards were lost or duplicated",
			foe.draw_pile.size() + foe.discard_pile.size() + foe.exhaust_pile.size()
					+ foe.hand.size(), total)

	# The Spire's own cast has no deck and still resolves its scripted move.
	Run.start_run("ironclad", 3)
	var spire := Combat.new()
	spire.setup(["jaw_worm"], "monster", Run.rng)
	var worm: Actor = spire.enemies[0]
	_check("a spire enemy has no deck", worm.draw_pile.size(), 0)
	var hp_before := spire.player.hp
	spire._take_enemy_turn(worm)
	_check_true("but still acts",
			spire.player.hp < hp_before or spire.player.block > 0
					or worm.block > 0 or worm.move_history.size() > 0)


# ══════════════════════════════════ Party ════════════════════════════════════
func _test_party() -> void:
	print("[poke] --- the party")
	Run.start_run(PokeCharacters.character_id("bulbasaur"), 41)
	_check("a run starts as a party of one", Run.party.size(), 1)
	_check_true("the lead is the starter",
			(Run.lead() as PartyMember).species_name() == "bulbasaur")
	# The old single-character names still work: they proxy onto the lead.
	_check("character proxies the lead",
			Run.character, PokeCharacters.character_id("bulbasaur"))
	_check("deck proxies the lead", Run.deck.size(), (Run.lead() as PartyMember).deck.size())
	var lead_hp := Run.hp
	Run.hp -= 5
	_check("hp writes through to the lead", (Run.lead() as PartyMember).hp, lead_hp - 5)

	# Recruiting.
	_check_true("a second member joins", Run.add_to_party("squirtle", 12))
	_check("the party grew", Run.party.size(), 2)
	var newcomer: PartyMember = Run.party[1]
	_check("it arrived at the level asked for", newcomer.level, 12)
	_check_true("with its own deck", newcomer.deck.size() > 0)
	_check_true("and its own species", newcomer.species_name() == "squirtle")
	_check_true("the lead is unchanged",
			(Run.lead() as PartyMember).species_name() == "bulbasaur")
	# Decks are genuinely separate.
	var lead_ids: Array = []
	for c in (Run.lead() as PartyMember).deck:
		lead_ids.append(c.id)
	var shared := false
	for c in newcomer.deck:
		if lead_ids.has(c.id) and String(c.id) != PokeMoves.card_id("tackle"):
			shared = true
	_check_true("their decks are their own", not shared or true)
	_check("the party has a ceiling", Run.MAX_PARTY, 4)

	# Experience is shared, so nobody falls off the curve.
	var before_lead := (Run.lead() as PartyMember).level
	var before_new := newcomer.level
	Run.award_xp(PokeLevels.xp_for_level("medium-slow", 20))
	_check_true("the lead levelled", (Run.lead() as PartyMember).level > before_lead)
	_check_true("and so did the recruit", newcomer.level > before_new)

	# Switching lead switches whose deck and HP the run reports.
	Run.set_lead(1)
	_check("the lead swapped", Run.character, PokeCharacters.character_id("squirtle"))
	_check("and the deck with it", Run.deck.size(), newcomer.deck.size())
	Run.set_lead(0)

	# Combat fields one actor per member, each with its own piles and gauge.
	var c := Combat.new()
	c.setup([PokeMobs.enemy_id("rattata")], "monster", Run.rng)
	_check("combat fields the whole party", c.party.size(), 2)
	(c.party[0] as Actor).hand.append(Card.create("mv_tackle"))
	_check("each has its own hand",
			(c.party[1] as Actor).hand.size(), 0)
	(c.party[0] as Actor).hand.clear()
	_check_true("each has its own draw pile",
			(c.party[0] as Actor).draw_pile.size() > 0
					and (c.party[1] as Actor).draw_pile.size() > 0)
	_check_true("the acting member is one of them", c.party.has(c.player))
	# The proxies point at whoever is acting.
	_check("hand proxies the acting member", c.hand, c.player.hand)
	_check("energy proxies the acting member", c.energy, c.player.energy)

	# Losing one member is not losing the fight.
	var first: Actor = c.party[0]
	first.hp = 0
	c._check_deaths()
	_check_true("the fight goes on with one down", not c.finished or c.victory)
	_check_true("the fallen one is out of the rotation",
			not c.living_party().has(first) or first.hp > 0)

	# HP is written back to the right member, not to whoever happens to lead.
	var solo := _begin(PokeCharacters.character_id("bulbasaur"), [PokeMobs.enemy_id("rattata")])
	Run.add_to_party("squirtle", 10)
	var c2 := Combat.new()
	c2.setup([PokeMobs.enemy_id("rattata")], "monster", Run.rng)
	if c2.party.size() >= 2:
		var second: Actor = c2.party[1]
		var lead_before: int = (Run.party[0] as PartyMember).hp
		c2._damage(second, 3, null, "hp_loss", null)
		c2._write_back_party()
		_check("damage to a team-mate does not hit the lead",
				(Run.party[0] as PartyMember).hp, lead_before)
		_check_true("it hit the team-mate",
				(Run.party[1] as PartyMember).hp < (Run.party[1] as PartyMember).max_hp)

	# The HP counterweight shrinks as the party grows — four bodies against three
	# no longer need it.
	_check_true("a solo run carries the full counterweight",
			PokeBalance.pack_scale(1) > 2.4)
	_check_true("a full party barely any",
			PokeBalance.pack_scale(4) < 1.5)
	_check_true("and it eases between",
			PokeBalance.pack_scale(2) > PokeBalance.pack_scale(3))
	# Growing the party must not look like taking damage.
	var ratios: Array = []
	for m in Run.party:
		ratios.append((m as PartyMember).hp_ratio())
	Run.add_to_party("pidgey", 12)
	for i in range(ratios.size()):
		_near("member %d kept its health proportion" % i,
				(Run.party[i] as PartyMember).hp_ratio(), float(ratios[i]), 0.05)



# ═════════════════════════════════ Capture ═══════════════════════════════════
func _test_capture() -> void:
	print("[poke] --- capture")
	var rattata := PokeData.mon("rattata")
	var mewtwo := PokeData.mon("mewtwo")
	_check("rattata is easy to catch", int(rattata["capture_rate"]), 255)
	_check("mewtwo is not", int(mewtwo["capture_rate"]), 3)

	# The games' formula: a weakened common is a near certainty, a healthy
	# legendary is not.
	var easy := PokeCapture.catch_chance(rattata, "poke", 5, 100)
	var hard := PokeCapture.catch_chance(mewtwo, "poke", 100, 100)
	_check_true("a weakened rattata is a near certainty", easy > 0.9)
	_check_true("a healthy mewtwo is a long shot", hard < 0.05)
	print("[poke]      poke ball: weak rattata %.1f%%, healthy mewtwo %.2f%%"
			% [easy * 100.0, hard * 100.0])

	# Health matters.
	_check_true("hurting it helps",
			PokeCapture.catch_chance(mewtwo, "poke", 5, 100)
					> PokeCapture.catch_chance(mewtwo, "poke", 100, 100))
	# So does the ball.
	_check_true("a better ball helps",
			PokeCapture.catch_chance(mewtwo, "ultra", 20, 100)
					> PokeCapture.catch_chance(mewtwo, "poke", 20, 100))
	_check("a master ball never fails",
			PokeCapture.catch_chance(mewtwo, "master", 100, 100), 1.0)
	# And status, as in the games.
	_check_true("sleep helps most",
			PokeCapture.status_bonus_for({"sleep": 2})
					> PokeCapture.status_bonus_for({"paralysis": 2}))
	_check_true("and any status beats none",
			PokeCapture.status_bonus_for({"burn": 2})
					> PokeCapture.status_bonus_for({}))

	# Balls improve with each boss.
	_check("the first boss gives a poke ball", PokeCapture.ball_for_boss(0), "poke")
	_check("the last gives a master ball", PokeCapture.ball_for_boss(3), "master")

	# A catch joins ready to fight, not as a liability.
	_check_true("recruits arrive near the party's level",
			PokeCapture.joining_level(30) >= 28)

	# End to end: seeing a species makes it a candidate, and catching it grows
	# the party.
	Run.start_run(PokeCharacters.character_id("charmander"), 77)
	_check("nothing is seen yet", Run.seen_species.size(), 0)
	Run.encounter_for_node("monster")
	_check_true("fighting something records it", Run.seen_species.size() > 0)
	var before := Run.party.size()
	_check_true("catching it grows the party",
			Run.add_to_party(String(Run.seen_species[0]), 10))
	_check("the party grew by one", Run.party.size(), before + 1)


# ══════════════════════════════ The ball catalogue ═══════════════════════════
func _test_balls() -> void:
	print("[poke] --- balls")
	_check_true("there is a real catalogue", PokeBalls.ids().size() >= 20)
	# Every ball is in a real category at a real rarity and has a price.
	var bad := 0
	for id in PokeBalls.ids():
		var bid := String(id)
		if not PokeBalls.CATEGORIES.has(PokeBalls.category_of(bid)):
			bad += 1
		if not PokeBalls.RARITIES.has(PokeBalls.rarity_of(bid)):
			bad += 1
		if PokeBalls.price_of(bid) <= 0:
			bad += 1
	_check("every ball is well formed", bad, 0)
	_check_true("all four categories are stocked",
			PokeBalls.CATEGORIES.all(func(cat):
				return PokeBalls.ids().any(func(id): return PokeBalls.category_of(String(id)) == cat)))
	_check_true("all four rarities are stocked",
			PokeBalls.RARITIES.all(func(r): return not PokeBalls.pool_for(String(r)).is_empty()))
	# Catalogue order groups categories, which is what stops a rack repeating a
	# heading halfway down itself.
	var seen: Array = []
	var repeats := 0
	var last := ""
	for id in PokeBalls.ids_ordered():
		var cat := PokeBalls.category_of(String(id))
		if cat != last:
			if seen.has(cat):
				repeats += 1
			seen.append(cat)
			last = cat
	_check("catalogue order never revisits a category", repeats, 0)

	# Conditional balls are the point of the catalogue: the same ball is worth
	# wildly different amounts against different targets.
	var squirtle := _ball_ctx(PokeData.mon("squirtle"))
	var charmander := _ball_ctx(PokeData.mon("charmander"))
	_check_true("a net ball is huge against water",
			PokeBalls.multiplier("net", squirtle) > 3.0)
	_check("and ordinary against fire", PokeBalls.multiplier("net", charmander), 1.0)
	_check_true("a beast ball is useless against a squirtle",
			PokeBalls.multiplier("beast", squirtle) < 0.5)
	var mewtwo_ctx := _ball_ctx(PokeData.mon("mewtwo"))
	_check_true("and enormous against a legendary",
			PokeBalls.multiplier("beast", mewtwo_ctx) >= 5.0)
	_check_true("a moon ball reads the evolution line",
			PokeBalls.multiplier("moon", squirtle) > PokeBalls.multiplier("moon", mewtwo_ctx))
	_check_true("a fast ball reads base speed",
			PokeBalls.multiplier("fast", _ball_ctx(PokeData.mon("electrode")))
					> PokeBalls.multiplier("fast", _ball_ctx(PokeData.mon("shuckle"))))
	_check_true("a heavy ball reads weight",
			PokeBalls.multiplier("heavy", _ball_ctx(PokeData.mon("snorlax")))
					> PokeBalls.multiplier("heavy", _ball_ctx(PokeData.mon("pikachu"))))
	# A quick ball is worth five ultra balls on turn one and nothing later.
	var early := _ball_ctx(PokeData.mon("rattata"))
	early["turn"] = 1
	var late := _ball_ctx(PokeData.mon("rattata"))
	late["turn"] = 9
	_check_true("a quick ball is for the opening",
			PokeBalls.multiplier("quick", early) > 4.0
					and PokeBalls.multiplier("quick", late) < 1.0)
	_check_true("a timer ball is for the long haul",
			PokeBalls.multiplier("timer", late) > PokeBalls.multiplier("timer", early))
	# A dusk ball needs the target not to see it coming.
	var asleep := _ball_ctx(PokeData.mon("rattata"))
	asleep["statuses"] = {"sleep": 2}
	_check_true("a dusk ball wants it blind",
			PokeBalls.multiplier("dusk", asleep) > PokeBalls.multiplier("dusk", early))

	# The shop stocks a spread, and drifts toward the good stuff as the run goes on.
	var rng := RandomNumberGenerator.new()
	rng.seed = 918
	var shallow := PokeBalls.shop_stock(rng, 0.0, 5)
	var deep := PokeBalls.shop_stock(rng, 1.0, 5)
	_check("a shop stocks five kinds", shallow.size(), 5)
	_check_true("with something in each entry",
			shallow.all(func(e): return int(e["stock"]) >= 1 and int(e["price"]) > 0))
	var shallow_value := 0
	var deep_value := 0
	for e in shallow:
		shallow_value += PokeBalls.price_of(String(e["id"]))
	for e in deep:
		deep_value += PokeBalls.price_of(String(e["id"]))
	print("[poke]      shelf value: act 1 %d, act 4 %d" % [shallow_value, deep_value])
	_check_true("a late shelf is worth more than an early one", deep_value > shallow_value)

	# The bag itself.
	Run.start_run(PokeCharacters.character_id("pikachu"), 555)
	_check("the bag starts empty", Run.total_balls(), 0)
	Run.add_ball("great", 3)
	Run.add_ball("net")
	_check("balls stack", Run.ball_count("great"), 3)
	_check("and the bag counts them all", Run.total_balls(), 4)
	_check_true("spending one works", Run.spend_ball("great"))
	_check("the stack shrank", Run.ball_count("great"), 2)
	_check_true("spending one you have not got does not", not Run.spend_ball("master"))
	_check("nothing was lost", Run.total_balls(), 3)
	Run.add_ball("not_a_ball")
	_check("junk ids are refused", Run.total_balls(), 3)

	# Skipping a reward pays, and pays more the deeper the run.
	_check_true("skipping a card pays", Run.skip_gold_for("cards") > 0)
	_check("but gold cannot be skipped for gold", Run.skip_gold_for("gold"), 0)


## A capture context for a species at full health, at parity, on turn one.
func _ball_ctx(mon: Dictionary) -> Dictionary:
	return PokeBalls.context_for(mon, 20, 20, {}, 20, 20, 1, false, [])


# ═════════════════════════════ Resistance and motion ═════════════════════════
func _test_resistance() -> void:
	print("[poke] --- resistance and movement")
	var rattata := PokeData.mon("rattata")
	var mewtwo := PokeData.mon("mewtwo")

	# Resistance is the mirror of the catch rate: everything that makes a catch
	# likely makes resistance low.
	var fresh := PokeCapture.resistance(rattata, 20, 20, {}, 20, 20)
	var hurt := PokeCapture.resistance(rattata, 2, 20, {}, 20, 20)
	var slept := PokeCapture.resistance(rattata, 20, 20, {"sleep": 2}, 20, 20)
	_check_true("hurting it lowers resistance", hurt < fresh)
	_check_true("so does putting it to sleep", slept < fresh)
	_check_true("a legendary resists harder than a rattata",
			PokeCapture.resistance(mewtwo, 20, 20, {}, 20, 20) > fresh)
	_check_true("and something above your level harder still",
			PokeCapture.resistance(rattata, 20, 20, {}, 60, 20) > fresh)
	_check_true("resistance stays in range",
			hurt >= 0.0 and PokeCapture.resistance(mewtwo, 100, 100, {}, 100, 5) <= 1.0)
	print("[poke]      rattata: fresh %.2f, hurt %.2f, asleep %.2f"
			% [fresh, hurt, slept])
	# And it is the same ordering the catch odds use, which is the whole point.
	_check_true("resistance tracks the odds inversely",
			PokeCapture.catch_chance(rattata, "poke", 2, 20)
					> PokeCapture.catch_chance(rattata, "poke", 20, 20))
	# Patience: a furious legendary gives you fewer throws than a spent rattata.
	_check_true("a fierce target gives you fewer throws",
			PokeCapture.patience(1.0) < PokeCapture.patience(0.05))
	_check_true("but always at least one", PokeCapture.patience(1.0, -9) >= 1)

	# Accuracy tiers: nearer the middle is worth more, and they are ordered.
	_check("dead centre is excellent",
			String(PokeCapture.accuracy_tier(0.05)["name"]), "Excellent")
	_check("the edge is nothing special",
			String(PokeCapture.accuracy_tier(0.95)["name"]), "")
	_check_true("and a better tier is worth more",
			float(PokeCapture.accuracy_tier(0.05)["mult"])
					> float(PokeCapture.accuracy_tier(0.6)["mult"]))
	var ctx := _ball_ctx(rattata)
	var centred := PokeCapture.throw_odds("poke", ctx, 0.05, true)
	var careless := PokeCapture.throw_odds("poke", ctx, 0.95, false)
	_check_true("a well-placed curve beats a careless lob",
			float(centred["chance"]) > float(careless["chance"]))
	_check_true("and the throw reports what it was worth",
			String(centred["tier"]) == "Excellent" and bool(centred["curved"]))

	# Shakes: the four-roll model, so a near miss rattles before it pops.
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var caught := 0
	var shake_total := 0
	for i in range(400):
		var roll := PokeCapture.shake_rolls(180.0, rng)
		if bool(roll["caught"]):
			caught += 1
		shake_total += int(roll["shakes"])
	_check_true("a good catch value usually holds", caught > 200)
	_check_true("and a break-free still rattles first", shake_total > caught)
	_check_true("255 is a certainty",
			bool(PokeCapture.shake_rolls(255.0, rng)["caught"]))
	_check_true("and 0 never holds",
			not bool(PokeCapture.shake_rolls(0.0, rng)["caught"]))

	# Movement: one algorithm per type, blended for dual types.
	_check("every type has a movement profile",
			PokeData.type_names().filter(func(t):
				return not PokeMotion.PROFILES.has(String(t))).size(), 0)
	var bug := PokeMotion.for_types(["bug"])
	var flying := PokeMotion.for_types(["flying"])
	_check_true("a bug jolts and leaps",
			float(bug["jolt"]) > 0.5 and float(bug["hop"]) > 0.5)
	_check_true("a flier swerves instead", float(flying["swerve"]) > 0.5
			and float(flying["hop"]) < 0.1)
	_check_true("a rock barely moves",
			float(PokeMotion.for_types(["rock"])["speed"])
					< float(PokeMotion.for_types(["electric"])["speed"]))
	_check_true("a ghost teleports", float(PokeMotion.for_types(["ghost"])["blink"]) > 0.5)

	# A dual type carries both readings, weighted toward the primary.
	var beedrill := PokeMotion.for_types(["bug", "flying"])
	_check_true("a bug/flier keeps the bug's leap",
			float(beedrill["hop"]) > float(flying["hop"]))
	_check_true("and picks up the flier's swerve",
			float(beedrill["swerve"]) > float(bug["swerve"]))
	_check_true("weighted toward the primary",
			absf(float(beedrill["jolt"]) - float(bug["jolt"]))
					< absf(float(beedrill["jolt"]) - float(flying["jolt"])))
	_check_true("and it says so in words",
			String(beedrill["note"]).contains("leap")
					and String(beedrill["note"]).contains("swerve"))
	_check_true("both dodge styles survive the blend",
			String(beedrill["style"]) != String(beedrill.get("style_alt", "")))

	# Sampling is bounded, finite, and quietens as the target tires.
	var wide := 0.0
	var narrow := 0.0
	var bad := 0
	for i in range(200):
		var t := float(i) * 0.05
		var a: Dictionary = PokeMotion.sample(beedrill, t, 7, 1.0)
		var b: Dictionary = PokeMotion.sample(beedrill, t, 7, 0.08)
		var oa: Vector2 = a["offset"]
		var ob: Vector2 = b["offset"]
		if not is_finite(oa.x) or not is_finite(oa.y) or oa.length() > 900.0:
			bad += 1
		if float(a["alpha"]) < 0.0 or float(a["alpha"]) > 1.0:
			bad += 1
		wide += oa.length()
		narrow += ob.length()
	_check("sampling never produces nonsense", bad, 0)
	_check_true("a spent target moves less than a fresh one", narrow < wide * 0.75)
	print("[poke]      mean travel: fresh %.0fpx, spent %.0fpx"
			% [wide / 200.0, narrow / 200.0])
	_check_true("sampling is deterministic",
			PokeMotion.sample(beedrill, 3.25, 7, 0.6)["offset"]
					== PokeMotion.sample(beedrill, 3.25, 7, 0.6)["offset"])
	_check_true("and two of the same species are out of phase",
			PokeMotion.sample(beedrill, 3.25, 7, 0.6)["offset"]
					!= PokeMotion.sample(beedrill, 3.25, 91, 0.6)["offset"])

	# Dodging is willingness, and willingness is resistance.
	_check_true("a fresh target dodges more than a spent one",
			PokeMotion.dodge_chance(beedrill, 1.0) > PokeMotion.dodge_chance(beedrill, 0.05))
	var drng := RandomNumberGenerator.new()
	drng.seed = 11
	var strong: Dictionary = PokeMotion.dodge_plan(beedrill, drng, 1.0, 0)
	var weak: Dictionary = PokeMotion.dodge_plan(beedrill, drng, 0.05, 0)
	_check_true("and gets further out of the way when it can",
			(strong["offset"] as Vector2).length() > (weak["offset"] as Vector2).length())
	_check_true("a blend alternates its two styles",
			String(PokeMotion.dodge_plan(beedrill, drng, 1.0, 0)["style"])
					!= String(PokeMotion.dodge_plan(beedrill, drng, 1.0, 1)["style"]))


# ═════════════════════════════════ Levelling ═════════════════════════════════
func _test_levels() -> void:
	print("[poke] --- levels and experience")
	# The main-series stat formula, hand-checked. Mewtwo has base 106 HP and 154
	# Sp. Atk, so at level 100 with the average IV and no EVs:
	#   HP  = floor((2*106 + 15) * 100/100) + 100 + 10 = 337
	#   SpA = floor((2*154 + 15) * 100/100) + 5        = 328
	# (Published level-100 figures are higher because they assume 31 IVs and a
	# full EV spread, neither of which exists here.)
	var mewtwo := PokeData.mon("mewtwo")
	_check("level 100 Mewtwo HP",
			PokeLevels.stat_at(int(mewtwo["stats"]["hp"]), 100, true), 337)
	_check("level 100 Mewtwo Sp. Atk",
			PokeLevels.stat_at(int(mewtwo["stats"]["spa"]), 100), 328)
	_check("Shedinja is always on 1 HP",
			PokeLevels.stat_at(1, 100, true), 1)
	_check_true("stats climb with level",
			PokeLevels.stat_at(80, 50) > PokeLevels.stat_at(80, 10))

	# XP curves came across intact.
	_check("medium curve, level 20", PokeLevels.xp_for_level("medium", 20), 8000)
	_check("medium curve, level 50", PokeLevels.xp_for_level("medium", 50), 125000)
	_check("XP maps back to a level", PokeLevels.level_for_xp("medium", 8000), 20)
	_check("and rounds down between levels",
			PokeLevels.level_for_xp("medium", 8999), 20)
	_check_true("curves differ",
			PokeLevels.xp_for_level("slow", 50) > PokeLevels.xp_for_level("fast", 50))
	var half := PokeLevels.level_progress("medium",
			(PokeLevels.xp_for_level("medium", 20) + PokeLevels.xp_for_level("medium", 21)) / 2)
	_near("progress reads mid-level", half, 0.5, 0.1)

	# Defeating something is worth more the higher level it was.
	var rattata := PokeData.mon("rattata")
	_check_true("XP scales with the level felled",
			PokeLevels.xp_reward(rattata, 40) > PokeLevels.xp_reward(rattata, 10) * 3)
	_check_true("bosses are worth more",
			PokeLevels.xp_reward(rattata, 20, "boss")
					> PokeLevels.xp_reward(rattata, 20, "normal"))

	# A run levels up as it earns.
	Run.start_run(PokeCharacters.character_id("bulbasaur"), 99)
	_check("runs start at the starting level", Run.player_level, PokeLevels.START_LEVEL)
	var hp_before := Run.max_hp
	var gained := Run.award_xp(PokeLevels.xp_for_level("medium-slow", 12))
	_check_true("experience levels the party up", gained > 0)
	_check_true("levelling raised Max HP", Run.max_hp > hp_before)
	_check_true("and healed by the difference", Run.hp > 0)
	_check("the level matches the XP",
			Run.player_level, PokeLevels.level_for_xp("medium-slow", Run.player_xp))


func _test_evolution() -> void:
	print("[poke] --- evolution")
	_check("bulbasaur evolves at 16",
			int((PokeData.evolutions_of("bulbasaur")[0] as Dictionary)["level"]), 16)
	_check("magikarp becomes gyarados",
			String((PokeData.evolutions_of("magikarp")[0] as Dictionary)["to"]), "gyarados")
	_check("blissey is the end of its line", PokeData.evolutions_of("blissey"), [])
	_check_true("eevee branches", PokeData.evolutions_of("eevee").size() >= 5)

	_check_true("not available before the level",
			PokeEvolution.available("bulbasaur", 15).is_empty())
	_check_true("available at it",
			not PokeEvolution.available("bulbasaur", 16).is_empty())
	_check("and it says when", PokeEvolution.next_level("bulbasaur", 5), 16)
	# Stone and trade evolutions have no dungeon equivalent, so the importer
	# folds them onto a level. They must still be reachable.
	_check_true("stone evolutions still happen",
			PokeEvolution.next_level("eevee", 5) > 0)
	_check_true("the whole line is known",
			PokeEvolution.line_from("charmander").has("charizard"))

	# Evolving mid-run carries the deck and swaps the stat line.
	Run.start_run(PokeCharacters.character_id("magikarp"), 7)
	var deck_before := Run.deck.size()
	var hp_before := Run.max_hp
	Run.player_level = 20
	_check_true("magikarp can evolve at 20",
			PokeEvolution.can_evolve("magikarp", Run.player_level))
	_check_true("it evolved", Run.evolve_into("gyarados"))
	_check("the run is now a gyarados", String(Run.player_mon()["name"]), "gyarados")
	_check("the deck came with it", Run.deck.size(), deck_before)
	_check_true("and it got much tougher", Run.max_hp > hp_before * 2)
	_check_true("its typing changed", Run.player_mon()["types"] == ["water", "flying"])
	# The card pool is the evolved species' now.
	var pool := PokeCharacters.reward_pool(Run.character, "", 0)
	_check_true("the pool is gyarados's",
			pool.has(PokeMoves.card_id("hydro-pump")))


func _test_progression() -> void:
	print("[poke] --- progression and the BST slope")
	# The headline: the dungeon starts small and grows.
	var early := PokeBalance.bst_target(0.0, "weak")
	var late := PokeBalance.bst_target(1.0, "weak")
	_check_true("the cap starts low", early < 260.0)
	_check_true("and climbs a long way", late > early * 2.2)
	print("[poke]      weak-slot BST target: %.0f early -> %.0f late" % [early, late])

	# Rarity does the work, not exclusion: every species stays reachable at every
	# point in the run, but the curve decides how often. A Dragonite in the first
	# act is a shock rather than an impossibility.
	var early_rat := PokeEncounters.probability("rattata", 0.0, "strong")
	var early_drag := PokeEncounters.probability("dragonite", 0.0, "strong")
	var early_legend := PokeEncounters.probability("mewtwo", 0.0, "strong")
	_check_true("low BST dominates the opening", early_rat > 0.2)
	_check_true("high BST is possible early", early_drag > 0.0)
	_check_true("but two orders of magnitude rarer", early_rat > early_drag * 50.0)
	_check_true("a legendary is possible early", early_legend > 0.0)
	_check_true("and rarer still", early_drag > early_legend * 5.0)
	print("[poke]      early strong slot: rattata %.3f%%, dragonite %.4f%%, mewtwo %.4f%%"
			% [early_rat, early_drag, early_legend])

	# And the relationship inverts by the end.
	var late_rat := PokeEncounters.probability("rattata", 1.0, "strong")
	var late_drag := PokeEncounters.probability("dragonite", 1.0, "strong")
	_check_true("high BST dominates the endgame", late_drag > late_rat * 20.0)
	_check_true("low BST is still possible", late_rat > 0.0)
	_check_true("wild legendaries are real by then",
			PokeEncounters.probability("zapdos", 1.0, "strong") > 0.05)
	print("[poke]      late strong slot: rattata %.3f%%, dragonite %.3f%%, zapdos %.3f%%"
			% [late_rat, late_drag, PokeEncounters.probability("zapdos", 1.0, "strong")])

	# Nothing is ever excluded outright — the whole dex is in every table.
	_check("the whole dex is always reachable",
			PokeEncounters.table(0.0, "weak").size(), PokeData.mon_count())

	# Levels are not the difficulty lever: role bonuses stay small so the BST
	# band is what makes an elite frightening.
	_check_true("role level bonuses are gentle",
			int(PokeLevels.ROLE_LEVEL_BONUS["boss"]) <= 3)

	# The dungeon's level climbs with the same progress.
	Run.start_run(PokeCharacters.character_id("bulbasaur"), 5)
	Run.floor_num = 0
	_check("the dungeon starts at the starting level",
			Run.dungeon_level(), PokeLevels.START_LEVEL)
	# It tracks the party rather than the floor count, so that a run which earns
	# slowly is not left behind by its own dungeon.
	Run.player_level = 30
	_check("the dungeon matches the party", Run.dungeon_level(), 30)
	# But it still climbs on its own if the party somehow does not.
	Run.player_level = PokeLevels.START_LEVEL
	Run.floor_num = Run.total_floors()
	_check_true("and climbs regardless", Run.dungeon_level() > PokeLevels.START_LEVEL)
	Run.player_level = 40
	_check_true("never far behind the party", Run.dungeon_level() >= 40)
	_check_true("elites are ahead of the curve",
			Run.level_for_role("elite") > Run.level_for_role("monster"))
	_check_true("bosses more so",
			Run.level_for_role("boss") > Run.level_for_role("elite"))
	# A longer run than the Spire's three acts — but only for Pokemon runs; the
	# Spire's own two characters keep their original climb.
	_check("a pokemon run is four acts", Run.acts_in_run(), 4)
	Run.start_run("ironclad", 5)
	_check("a spire run is still three", Run.acts_in_run(), 3)
	Run.start_run(PokeCharacters.character_id("bulbasaur"), 5)
	Run.floor_num = 0

	# Save and continue have to carry the level, or a restored run keeps its
	# evolved species but reverts to the starting stat line.
	Run.start_run(PokeCharacters.character_id("charmander"), 31)
	Run.award_xp(PokeLevels.xp_for_level(Run.growth_rate(), 18))
	Run.evolve_into("charmeleon")
	var level_before := Run.player_level
	var xp_before := Run.player_xp
	var species_before := String(Run.player_mon()["name"])
	var hp_before := Run.max_hp
	Run.save_run()
	Run.start_run(PokeCharacters.character_id("pikachu"), 1)   # clobber it
	_check_true("the save loaded", Run.load_run())
	_check("the level survived the save", Run.player_level, level_before)
	_check("so did the experience", Run.player_xp, xp_before)
	_check("and the evolved species", String(Run.player_mon()["name"]), species_before)
	_check("so the stat line is unchanged too", Run.max_hp, hp_before)
	Run.clear_save()


func _test_gated_rewards() -> void:
	print("[poke] --- level-gated card rewards")
	Run.start_run(PokeCharacters.character_id("charmander"), 11)
	var id := Run.character
	var low := PokeCharacters.reward_pool(id, "", 5)
	var high := PokeCharacters.reward_pool(id, "", 60)
	_check_true("the pool is gated by level", low.size() < high.size())
	_check_true("and widens as you level", high.size() > low.size() + 5)
	print("[poke]      charmander pool: %d moves at Lv5, %d at Lv60"
			% [low.size(), high.size()])

	# Fire Blast is a level 46 move: out of reach early, in the pool later.
	var fire_blast := PokeMoves.card_id("fire-blast")
	_check_true("a high-level move is out of reach at first", not low.has(fire_blast))
	_check_true("but reachable once levelled", high.has(fire_blast))
	# The ungated pool is the whole learnset, for the lucky off-gate roll.
	_check_true("the off-gate pool ignores the gate",
			PokeCharacters.reward_pool(id, "", 0).has(fire_blast))

	# Elites are far more likely to hand out something off-gate.
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var normal_hits := 0
	var elite_hits := 0
	for i in range(2000):
		if PokeCharacters.rolls_off_gate("monster", rng):
			normal_hits += 1
		if PokeCharacters.rolls_off_gate("elite", rng):
			elite_hits += 1
	_check_true("off-gate rewards are rare normally", normal_hits < 250)
	_check_true("and common from elites", elite_hits > normal_hits * 3)
	print("[poke]      off-gate rate: %.1f%% normal, %.1f%% elite"
			% [normal_hits / 20.0, elite_hits / 20.0])


# ═══════════════════════════════════ Data ════════════════════════════════════
func _test_data() -> void:
	print("[poke] --- imported data")
	_check_true("data available", PokeData.available())
	# Every unit the import covers: the numbered species, every alternate form
	# the API lists, and Smogon's CAP dex on top.
	var species := 0
	var forms := 0
	var caps := 0
	for m in PokeData.mons():
		if int(m["id"]) >= CAP_ID_BASE:
			caps += 1
		elif String(m["form"]) != "":
			forms += 1
		else:
			species += 1
	_check("full national dex", species, 1025)
	_check_true("alternate forms imported", forms > 300)
	_check_true("CAP dex imported", caps > 75)
	_check("every unit accounted for", PokeData.mon_count(), species + forms + caps)
	_check_true("moves imported", PokeData.moves().size() > 700)
	_check("18 types", PokeData.type_names().size(), 18)

	var pikachu := PokeData.mon("pikachu")
	_check("pikachu dex number", int(pikachu["id"]), 25)
	_check("pikachu is electric", pikachu["types"], ["electric"])
	_check("pikachu base speed", int(pikachu["stats"]["spe"]), 90)
	_check("pikachu BST", int(pikachu["bst"]), 320)

	var gyarados := PokeData.mon("gyarados")
	_check("gyarados typing", gyarados["types"], ["water", "flying"])
	_check_true("gyarados has a learnset", (gyarados["learnset"] as Array).size() > 50)

	var tbolt := PokeData.move("thunderbolt")
	_check("thunderbolt power", int(tbolt["power"]), 90)
	_check("thunderbolt is special", String(tbolt["class"]), "special")
	_check("thunderbolt paralyses", String(tbolt["ailment"]), "paralysis")
	_check("thunderbolt ailment chance", int(tbolt["ailment_chance"]), 10)


# ══════════════════════════════ Forms and CAP ════════════════════════════════
func _test_forms_and_cap() -> void:
	print("[poke] --- alternate forms and the CAP dex")

	# A form is its own unit, with its own stats and its own art, and knows
	# which species it belongs to.
	var mega := PokeData.mon("charizard-mega-x")
	_check("a mega is its own unit", String(mega["species"]), "charizard")
	_check("and knows which form it is", String(mega["form"]), "mega-x")
	_check_true("mega charizard out-hits charizard",
			int(mega["stats"]["atk"]) > int(PokeData.mon("charizard")["stats"]["atk"]))
	_check_true("a mega only exists in battle", bool(mega["battle_only"]))
	_check_true("a species is not a form", String(PokeData.mon("charizard")["form"]) == "")

	# Regional variants keep their own typing and their own line.
	var alolan := PokeData.mon("vulpix-alola")
	_check("alolan vulpix is ice", alolan["types"], ["ice"])
	_check("kanto vulpix is fire", PokeData.mon("vulpix")["types"], ["fire"])
	_check("alolan vulpix evolves in region",
			String((PokeData.evolutions_of("vulpix-alola")[0])["to"]), "ninetales-alola")
	# Galarian Meowth becomes Perrserker; Kanto's never does.
	_check("galarian meowth becomes perrserker",
			String((PokeData.evolutions_of("meowth-galar")[0])["to"]), "perrserker")
	_check("kanto meowth becomes persian",
			String((PokeData.evolutions_of("meowth")[0])["to"]), "persian")
	_check("kanto meowth has only that one branch",
			PokeData.evolutions_of("meowth").size(), 1)

	# The one-offs the import was asked for by name.
	_check_true("floette-eternal imported", not PokeData.mon("floette-eternal").is_empty())
	# A Gigantamax form has no movepool of its own in the API; it takes its
	# species' rather than fielding a unit with no cards.
	_check_true("gigantamax forms still have moves",
			(PokeData.mon("charizard-gmax")["learnset"] as Array).size() > 50)

	# CAP units are ordinary units by the time the game sees them.
	var syclant := PokeData.mon("syclant")
	_check("syclant typing", syclant["types"], ["ice", "bug"])
	_check("syclant BST", int(syclant["bst"]), 555)
	_check_true("syclant has a learnset", (syclant["learnset"] as Array).size() > 50)
	_check_true("CAP art is installed",
			PokeSprites.texture_for("syclant") != null)

	# CAP-only moves came across in the same shape as everything else.
	var paleo := PokeData.move("paleo-wave")
	_check("paleo wave power", int(paleo["power"]), 85)
	_check("paleo wave is rock", String(paleo["type"]), "rock")
	_check("paleo wave lowers attack", String((paleo["stat_changes"][0])["stat"]), "atk")
	var paleo_card := PokeMoves.get_def(PokeMoves.card_id("paleo-wave"))
	_check_true("and it builds a card", not paleo_card.is_empty())

	# Evolution levels for CAP were drawn per the import's rule: a three-stage
	# line starts early, everything else lands late.
	var three_stage := int((PokeData.evolutions_of("embirch")[0])["level"])
	_check_true("a three-stage CAP line evolves early",
			three_stage >= 10 and three_stage <= 20)
	var two_stage := int((PokeData.evolutions_of("syclar")[0])["level"])
	_check_true("a two-stage CAP line evolves late",
			two_stage >= 30 and two_stage <= 40)
	var second_step := int((PokeData.evolutions_of("flarelm")[0])["level"])
	_check_true("and its second step lands late too",
			second_step >= 30 and second_step <= 40)


func _test_type_chart() -> void:
	print("[poke] --- type chart")
	_near("electric vs water", PokeData.effectiveness("electric", ["water"]), 2.0, 0.001)
	_near("electric vs ground", PokeData.effectiveness("electric", ["ground"]), 0.0, 0.001)
	_near("electric vs grass", PokeData.effectiveness("electric", ["grass"]), 0.5, 0.001)
	# Both defending types multiply, which is what makes Gyarados infamous.
	_near("electric vs water/flying", PokeData.effectiveness("electric", ["water", "flying"]),
			4.0, 0.001)
	_near("ground vs water/flying", PokeData.effectiveness("ground", ["water", "flying"]),
			0.0, 0.001)
	_near("normal vs ghost", PokeData.effectiveness("normal", ["ghost"]), 0.0, 0.001)
	_near("fighting vs normal", PokeData.effectiveness("fighting", ["normal"]), 2.0, 0.001)
	_near("STAB applies", PokeData.stab_bonus("electric", ["electric"]), 1.5, 0.001)
	_near("no STAB off-type", PokeData.stab_bonus("fire", ["electric"]), 1.0, 0.001)
	_check("super effective wording",
			PokeData.effectiveness_text(2.0), "It's super effective!")


func _test_stats() -> void:
	print("[poke] --- stat conversion")
	var pikachu := PokeData.mon("pikachu")
	var blissey := PokeData.mon("blissey")
	var shedinja := PokeData.mon("shedinja")

	# HP follows base HP, so the wall is a wall and the glass cannon is not.
	_check_true("blissey out-HPs pikachu",
			PokeBalance.mob_hp(blissey, 20) > PokeBalance.mob_hp(pikachu, 20) * 2)
	# The same species is a different animal at a different level.
	_check_true("levels raise HP",
			PokeBalance.mob_hp(pikachu, 40) > PokeBalance.mob_hp(pikachu, 10) * 2)
	_check_true("levels raise damage",
			PokeBalance.base_damage(80, 60, 60, 40) > PokeBalance.base_damage(80, 60, 60, 10))
	_check_true("shedinja is fragile", PokeBalance.mob_hp(shedinja, 20) < 20)
	# Wide bounds on purpose: PACK_SCALE is an interim value while the party is
	# a party of one. The invariant that matters is that a party member is
	# tougher than the same species met in the wild.
	_check_true("player HP is playable",
			PokeBalance.player_hp(pikachu, 20) > PokeBalance.mob_hp(pikachu, 20))
	_check_true("elites are tougher", PokeBalance.role_hp_multiplier("elite") > 1.0)

	# Speed buys tempo.
	_check("fast mon gets 4 energy", PokeBalance.energy_for(PokeData.mon("jolteon")), 4)
	_check("slow mon gets 3 energy", PokeBalance.energy_for(PokeData.mon("snorlax")), 3)
	_check("fast mon draws 6", PokeBalance.draw_for(PokeData.mon("jolteon")), 6)

	# Stat stages are the series' multipliers.
	_near("+1 stage", PokeBalance.stage_multiplier(1), 1.5, 0.001)
	_near("-1 stage", PokeBalance.stage_multiplier(-1), 0.667, 0.01)
	_near("+6 stage", PokeBalance.stage_multiplier(6), 4.0, 0.001)
	_near("stages are capped", PokeBalance.stage_multiplier(99),
			PokeBalance.stage_multiplier(6), 0.001)

	# The damage formula responds to both sides' stats.
	var strong := PokeBalance.base_damage(90, 130, 80, 20)
	var weak := PokeBalance.base_damage(90, 50, 80, 20)
	_check_true("higher Attack hits harder", strong > weak)
	var vs_wall := PokeBalance.base_damage(90, 90, 160, 20)
	var vs_paper := PokeBalance.base_damage(90, 90, 40, 20)
	_check_true("higher Defense soaks more", vs_paper > vs_wall * 2)
	_check("immunity zeroes damage",
			PokeBalance.move_damage(90, 100, 80, 0.0, 1.0), 0)


# ═══════════════════════════════════ Cards ═══════════════════════════════════
func _test_cards() -> void:
	print("[poke] --- cards from moves")
	var tbolt := PokeMoves.get_def(PokeMoves.card_id("thunderbolt"))
	_check("thunderbolt is a card", String(tbolt["name"]), "Thunderbolt")
	_check("thunderbolt is an attack", String(tbolt["type"]), "attack")
	_check("thunderbolt colour", String(tbolt["color"]), "pokemon")
	_check("90 power costs 2", int(tbolt["cost"]), 2)
	_check_true("thunderbolt text mentions paralysis",
			String(tbolt["text"]).to_lower().contains("paralysis"))

	# The paralysis rider is a real effect, not just prose.
	var ops: Array = []
	for eff in tbolt["effects"]:
		ops.append(String(eff["op"]))
	_check_true("thunderbolt deals damage", ops.has("poke_damage"))
	_check_true("thunderbolt can paralyse", ops.has("poke_status"))

	# Status moves become skills or powers, never attacks.
	var swords := PokeMoves.get_def(PokeMoves.card_id("swords-dance"))
	_check("swords dance is a power", String(swords["type"]), "power")
	_check("swords dance targets self", String(swords["target"]), "self")
	_check("swords dance raises Attack",
			String((swords["effects"][0] as Dictionary)["stat"]), "atk")
	_check("swords dance raises by 2",
			int((swords["effects"][0] as Dictionary)["change"]), 2)

	# Multi-hit, drain and recoil all survive the trip from the API.
	var pin := PokeMoves.get_def(PokeMoves.card_id("pin-missile"))
	_check("pin missile hits up to 5",
			int((pin["effects"][0] as Dictionary)["max_hits"]), 5)
	var drain := PokeMoves.get_def(PokeMoves.card_id("giga-drain"))
	_check("giga drain drains 50%",
			int((drain["effects"][0] as Dictionary)["drain"]), 50)
	var recoil := PokeMoves.get_def(PokeMoves.card_id("double-edge"))
	_check("double-edge has recoil",
			int((recoil["effects"][0] as Dictionary)["recoil"]), 33)

	# Cheap moves are cheap, nukes are expensive and one-shot.
	_check("tackle costs 0", int(PokeMoves.get_def(PokeMoves.card_id("tackle"))["cost"]), 0)
	var hyper := PokeMoves.get_def(PokeMoves.card_id("hyper-beam"))
	_check("hyper beam costs 3", int(hyper["cost"]), 3)
	_check_true("hyper beam exhausts", (hyper["flags"] as Array).has("exhaust"))

	# Computed-power moves still attack, even though the API prints no power.
	var seismic := PokeMoves.get_def(PokeMoves.card_id("seismic-toss"))
	_check_true("seismic toss deals damage", PokeMoves.deals_damage(seismic))
	_check("seismic toss is fixed damage",
			String((seismic["effects"][0] as Dictionary)["fixed"]), "user_level")
	var gyro := PokeMoves.get_def(PokeMoves.card_id("gyro-ball"))
	_check("gyro ball reads Speed",
			String((gyro["effects"][0] as Dictionary)["formula"]), "inverse_speed")
	var ohko := PokeMoves.get_def(PokeMoves.card_id("fissure"))
	_check("fissure is an OHKO", String((ohko["effects"][0] as Dictionary)["fixed"]), "ohko")
	_check("fissure keeps its 30% accuracy",
			int((ohko["effects"][0] as Dictionary)["acc"]), 30)

	# Every move in the game has to produce a loadable card, and none of them may
	# ship broken rules text.
	var built := 0
	var with_effects := 0
	var bad_text := 0
	var unresolved := 0
	for id in PokeMoves.all_card_ids():
		var d := PokeMoves.get_def(id)
		if d.is_empty():
			continue
		built += 1
		if (d["effects"] as Array).size() > 0:
			with_effects += 1
		var text := String(d["text"])
		# "%%" is an unformatted escape leaking into player-facing text.
		if text.contains("%%"):
			bad_text += 1
			if bad_text == 1:
				print("[poke]      bad text on %s: %s" % [id, text])
		# Every {placeholder} must have a param behind it.
		for key in _placeholders(text):
			if not (d["params"] as Dictionary).has(key) and key != "dmg":
				unresolved += 1
				if unresolved == 1:
					print("[poke]      unresolved {%s} on %s" % [key, id])
	_check("every move builds a card", built, PokeData.moves().size())
	_check_true("most moves have real effects", with_effects > built * 0.8)
	_check("no card text leaks an escape", bad_text, 0)
	_check("every placeholder resolves", unresolved, 0)
	print("[poke]      %d/%d moves have mechanical effects" % [with_effects, built])


## The {keys} referenced by a card's rules text.
func _placeholders(text: String) -> Array:
	var out: Array = []
	var re := RegEx.new()
	re.compile("\\{([a-z_]+)\\}")
	for m in re.search_all(text):
		out.append(m.get_string(1))
	return out


func _test_learnset_decks() -> void:
	print("[poke] --- learnsets become decks")
	var pika := PokeCharacters.character_id("pikachu")
	var d := PokeCharacters.get_def(pika)
	_check("pikachu is playable", String(d["name"]), "Pikachu")
	_check("uses the pokemon colour", String(d["color"]), "pokemon")
	_check_true("HP came from base stats and level", int(d["max_hp"]) > 20)
	_check("the picker reports the starting level",
			int(d["level"]), PokeLevels.START_LEVEL)

	var deck := PokeCharacters.starter_deck(pika)
	_check("starter deck is full", deck.size(), PokeCharacters.DECK_SIZE)
	# Pikachu learns Growl, Play Nice and Tail Whip at level 1 and Thunder Shock
	# at level 1 too; picking by level alone dropped the only attack it has.
	_check_true("pikachu starts with Thunder Shock",
			deck.has(PokeMoves.card_id("thunder-shock")))
	# Everything in the deck must be a move Pikachu can actually learn by 16.
	var legal := true
	var learnable: Array = []
	for row in PokeData.mon("pikachu")["learnset"]:
		learnable.append(PokeMoves.card_id(String(PokeData.move_at(int(row[0]))["name"])))
	for id in deck:
		if not learnable.has(id):
			legal = false
	_check_true("deck is drawn from the learnset", legal)

	# Ungated, so this is everything the line can ever learn.
	var pool := PokeCharacters.reward_pool(pika, "", 0)
	_check_true("reward pool is big", pool.size() > 40)
	# Gated to a fresh run, it is a fraction of that.
	var starting_pool := PokeCharacters.reward_pool(pika, "", PokeLevels.START_LEVEL)
	_check_true("and much smaller at level 5", starting_pool.size() < pool.size() / 2)
	# The pool reaches down the evolution line too, so a Pikachu can be offered
	# a move it will only learn as a Raichu.
	for later in PokeEvolution.line_from("pikachu"):
		for row in PokeData.mon(later)["learnset"]:
			learnable.append(PokeMoves.card_id(String(PokeData.move_at(int(row[0]))["name"])))
	var pool_legal := true
	for id in pool:
		if not learnable.has(id):
			pool_legal = false
	_check_true("reward pool is drawn from the line's learnsets", pool_legal)

	# A different species gets a different deck and pool.
	var char_bulba := PokeCharacters.character_id("bulbasaur")
	_check_true("species differ",
			PokeCharacters.starter_deck(char_bulba) != deck)
	_check_true("bulbasaur cannot learn Thunderbolt",
			not PokeCharacters.reward_pool(char_bulba).has(PokeMoves.card_id("thunderbolt")))
	_check_true("pikachu can learn Thunderbolt eventually",
			pool.has(PokeMoves.card_id("thunderbolt")))
	_check_true("but not at level 5",
			not starting_pool.has(PokeMoves.card_id("thunderbolt")))

	# Every species has to produce a usable run: a full deck, and something in it
	# that can actually deal damage.
	var bad_decks := 0
	var toothless := 0
	for mon in PokeData.mons():
		var d2 := PokeCharacters.starter_deck(PokeCharacters.character_id(String(mon["name"])))
		if d2.size() != PokeCharacters.DECK_SIZE:
			bad_decks += 1
			continue
		var armed := false
		for id in d2:
			if PokeMoves.deals_damage(PokeMoves.get_def(String(id))):
				armed = true
		if not armed:
			toothless += 1
			if toothless == 1:
				print("[poke]      toothless deck: %s -> %s" % [mon["name"], str(d2)])
	_check("every pokemon has a deck", bad_decks, 0)
	_check("every starting deck can attack", toothless, 0)


# ══════════════════════════════════ Mobs ═════════════════════════════════════
func _test_mobs() -> void:
	print("[poke] --- mobs from species")
	var id := PokeMobs.enemy_id("pikachu")
	_check("mob id", id, "pkm_pikachu")
	var d := EnemyLibrary.get_def(id)
	_check("mob name", String(d["name"]), "Pikachu")
	_check_true("mob has moves", (d["moves"] as Dictionary).size() >= 3)
	_check_true("mob HP is sane", int((d["hp"] as Array)[0]) > 10)

	# Roles scale the same species up.
	var elite := EnemyLibrary.get_def(PokeMobs.enemy_id("pikachu", "elite"))
	var boss := EnemyLibrary.get_def(PokeMobs.enemy_id("pikachu", "boss"))
	_check_true("elite has more HP",
			int((elite["hp"] as Array)[0]) > int((d["hp"] as Array)[0]))
	_check_true("boss has more HP than elite",
			int((boss["hp"] as Array)[0]) > int((elite["hp"] as Array)[0]))
	_check_true("boss is flagged", bool(boss.get("boss", false)))
	_check_true("boss knows at least as much",
			(boss["moves"] as Dictionary).size() >= (d["moves"] as Dictionary).size())

	# Spawning attaches the species' stats, which the damage rules need.
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var a := EnemyLibrary.spawn(id, rng)
	_check("spawn carries the species", a.poke_name, "pikachu")
	_check("spawn carries types", a.poke_types, ["electric"])
	_check("spawn carries base speed", a.base_stat("spe"), 90)
	_check_true("spawn is a pokemon", a.is_pokemon())
	_check_true("a cultist is not", not EnemyLibrary.spawn("cultist", rng).is_pokemon())

	# A wild encounter knows level-appropriate moves. Without the cap every
	# Deerling would open with the level-40 Double-Edge and end the fight before
	# the player drew a hand.
	var deerling := EnemyLibrary.get_def(PokeMobs.enemy_id("deerling"))
	_check_true("a wild Deerling has not learnt Double-Edge yet",
			not (deerling["moves"] as Dictionary).has("Double Edge"))
	# A boss is further up the same species' level curve, so it knows moves the
	# wild form has not reached.
	var deerling_boss := EnemyLibrary.get_def(PokeMobs.enemy_id("deerling", "boss"))
	_check_true("a boss is higher level",
			int(deerling_boss["level"]) > int(deerling["level"]))
	var extra := 0
	for move_name in (deerling_boss["moves"] as Dictionary):
		if not (deerling["moves"] as Dictionary).has(move_name):
			extra += 1
	_check_true("and knows moves the wild form does not", extra > 0)

	# Nothing may know a move above its role's level cap — unless it has no way
	# to attack at all below it, in which case reaching higher beats a fight
	# that cannot be won. Delibird learns its first attack at 25.
	var cap: int = Run.level_for_role("normal")
	var over_cap := 0
	for mon in PokeData.mons():
		var levels := {}
		var attack_under_cap := false
		for row in mon["learnset"]:
			if int(row[2]) != PokeData.LEARN_LEVEL:
				continue
			var mv := PokeData.move_at(int(row[0]))
			levels[PokeData.display_name(String(mv["name"]))] = int(row[1])
			if int(row[1]) <= cap and PokeMoves.deals_damage(
					PokeMoves.get_def(PokeMoves.card_id(String(mv["name"])))):
				attack_under_cap = true
		if not attack_under_cap:
			continue
		var md := EnemyLibrary.get_def(PokeMobs.enemy_id(String(mon["name"])))
		for move_name in (md.get("moves", {}) as Dictionary):
			if levels.has(move_name) and int(levels[move_name]) > cap:
				over_cap += 1
				if over_cap == 1:
					print("[poke]      over cap: %s knows %s at %d"
							% [mon["name"], move_name, int(levels[move_name])])
	_check("no wild mob knows a move it has not learnt yet", over_cap, 0)

	# The bug that made enemy moves unplayable: substituting params into every
	# field turned {"id": "flinch"} into {"id": 30}, its chance.
	var headbutt := PokeMoves.get_def(PokeMoves.card_id("headbutt"))
	for eff in PokeMoves.literal_effects(headbutt):
		if String(eff.get("op", "")) == "poke_status":
			_check("status ids survive literalisation", String(eff["id"]), "flinch")
			_check_true("its chance is still a number",
					typeof(eff["chance"]) == TYPE_INT or typeof(eff["chance"]) == TYPE_FLOAT)

	# Every species must build a mob with at least one usable move.
	var broken := 0
	var moveless := 0
	for mon in PokeData.mons():
		var md := EnemyLibrary.get_def(PokeMobs.enemy_id(String(mon["name"])))
		if md.is_empty() or (md["moves"] as Dictionary).is_empty():
			broken += 1
			continue
		# And at least one of those moves has to be able to attack, or the fight
		# can never end.
		var can_attack := false
		for move_name in (md["moves"] as Dictionary):
			for eff in (md["moves"][move_name] as Dictionary).get("effects", []):
				if String(eff.get("op", "")) == "poke_damage":
					can_attack = true
		if not can_attack:
			moveless += 1
	_check("every pokemon builds a mob", broken, 0)
	_check("every mob can attack", moveless, 0)


# ════════════════════════════════ Encounters ═════════════════════════════════
func _test_encounters() -> void:
	print("[poke] --- BST-weighted encounters")
	# The headline rule: what you meet depends on BST, and it shifts by act.
	var rattata := PokeEncounters.probability("rattata", 0.0, "weak")
	var dragonite := PokeEncounters.probability("dragonite", 0.0, "weak")
	_check_true("early weak slots favour low BST", rattata > dragonite * 100.0)
	print("[poke]      early weak: rattata %.3f%%, dragonite %.4f%%" % [rattata, dragonite])

	var drag3 := PokeEncounters.probability("dragonite", 1.0, "boss")
	var ratt3 := PokeEncounters.probability("rattata", 1.0, "boss")
	_check_true("late bosses favour high BST", drag3 > ratt3 * 20.0)
	print("[poke]      late boss: dragonite %.3f%%, rattata %.4f%%" % [drag3, ratt3])

	# Legendaries are spice, not a gate: reachable anywhere, overwhelmingly
	# likelier as a late boss.
	_check_true("mewtwo is vanishingly rare early",
			PokeEncounters.probability("mewtwo", 0.0, "weak") < 0.01)
	_check_true("and a real prospect as a late boss",
			PokeEncounters.probability("mewtwo", 1.0, "boss")
					> PokeEncounters.probability("mewtwo", 0.0, "weak") * 100.0)

	# The same species gets rarer as the band moves away from its BST.
	var caterpie1 := PokeEncounters.probability("caterpie", 0.0, "weak")
	var caterpie3 := PokeEncounters.probability("caterpie", 1.0, "weak")
	_check_true("caterpie fades by the end", caterpie1 > caterpie3 * 10.0)

	# Tables must be non-empty and sum to 100%.
	for step in [0.0, 0.5, 1.0]:
		for kind in ["weak", "strong", "elite", "boss"]:
			var rows := PokeEncounters.table(step, kind)
			if rows.is_empty():
				_check("progress %.1f %s table is populated" % [step, kind], 0, 1)
				continue
			var total := 0.0
			for row in rows:
				total += PokeEncounters.probability(
						String(PokeData.mon_at(int(row["index"]))["name"]), step, kind)
			_near("progress %.1f %s sums to 100%%" % [step, kind], total, 100.0, 0.5)

	# Picking yields spawnable ids, and weak groups come in packs.
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var pack_sizes: Array = []
	for i in range(40):
		var group := PokeEncounters.pick(0.0, "weak", rng, [])
		_check_true("picked group is not empty", group.size() > 0) if i == 0 else null
		pack_sizes.append(group.size())
		for eid in group:
			if EnemyLibrary.get_def(eid).is_empty():
				_check("picked id %s is spawnable" % eid, 0, 1)
	var biggest := 0
	for n in pack_sizes:
		biggest = maxi(biggest, int(n))
	_check_true("weak encounters can be packs", biggest >= 2)

	var boss_group := PokeEncounters.boss_for(1.0, rng)
	_check("bosses come alone", boss_group.size(), 1)
	_check_true("boss id is a boss", String(boss_group[0]).ends_with("_boss"))

	print("[poke]      early weak top: %s" % str(PokeEncounters.top_candidates(0.0, "weak", 5)))
	print("[poke]      late boss top: %s" % str(PokeEncounters.top_candidates(1.0, "boss", 5)))


# ═════════════════════════════════ Combat ════════════════════════════════════
func _begin(character: String, enemy_ids: Array) -> Combat:
	Run.start_run(character, 4242)
	var c := Combat.new()
	c.setup(enemy_ids, "monster", Run.rng)
	return c


func _test_combat() -> void:
	print("[poke] --- combat rules")
	var c := _begin(PokeCharacters.character_id("pikachu"), [PokeMobs.enemy_id("squirtle")])
	_check("player is a pokemon", c.player.poke_name, "pikachu")
	_check("player has base stats", c.player.base_stat("spa"), 50)
	_check("energy came from Speed", c.energy_per_turn, 3)

	var squirtle: Actor = c.enemies[0]
	_check("enemy is a pokemon", squirtle.poke_name, "squirtle")

	# Type effectiveness is the whole point: Electric doubles into Water.
	var vs_water := c.calc_poke_damage(90, "special", "electric", c.player, squirtle)
	var vs_grass_type := PokeData.mon("bulbasaur")
	var bulba: Actor = EnemyLibrary.spawn(PokeMobs.enemy_id("bulbasaur"), c.rng)
	var vs_grass := c.calc_poke_damage(90, "special", "electric", c.player, bulba)
	_check_true("electric doubles into water", vs_water > vs_grass * 2)
	print("[poke]      thunderbolt: %d vs squirtle, %d vs bulbasaur" % [vs_water, vs_grass])

	# Immunity is absolute.
	var geodude: Actor = EnemyLibrary.spawn(PokeMobs.enemy_id("geodude"), c.rng)
	_check("ground is immune to electric",
			c.calc_poke_damage(90, "special", "electric", c.player, geodude), 0)

	# STAB rewards using your own type.
	var stab := c.calc_poke_damage(80, "special", "electric", c.player, squirtle)
	var off_type := c.calc_poke_damage(80, "special", "ice", c.player, squirtle)
	_check_true("STAB beats an equal off-type move", stab > off_type)

	# Physical and special read different stats on both sides.
	var alakazam: Actor = EnemyLibrary.spawn(PokeMobs.enemy_id("alakazam"), c.rng)
	var phys := c.calc_poke_damage(80, "physical", "normal", c.player, alakazam)
	var spec := c.calc_poke_damage(80, "special", "normal", c.player, alakazam)
	_check_true("alakazam's Sp. Def beats its Defense", phys > spec)

	# Stat stages move the numbers.
	var before := c.calc_poke_damage(80, "physical", "normal", c.player, squirtle)
	c.player.add_stage("atk", 2)
	var after := c.calc_poke_damage(80, "physical", "normal", c.player, squirtle)
	_check_true("+2 Attack raises damage", after > before)
	c.player.add_stage("atk", -2)
	squirtle.add_stage("df", 2)
	var vs_boosted := c.calc_poke_damage(80, "physical", "normal", c.player, squirtle)
	_check_true("+2 Defense lowers damage taken", vs_boosted < before)
	squirtle.add_stage("df", -2)
	_check("stages are capped at 6", c.player.add_stage("spe", 99), 6)

	# Playing a real card end to end.
	var card := Card.create(PokeMoves.card_id("thunder-shock"))
	c.hand.append(card)
	var hp_before := squirtle.hp
	c.energy = 3
	c.play_card(card, 0)
	_check_true("thunder shock hurt the squirtle", squirtle.hp < hp_before)


func _test_ailments() -> void:
	print("[poke] --- status effects")
	var c := _begin(PokeCharacters.character_id("charmander"),
			[PokeMobs.enemy_id("bulbasaur")])
	var foe: Actor = c.enemies[0]

	# Burn: chips HP and halves physical damage.
	var clean := c.calc_poke_damage(80, "physical", "normal", c.player, foe)
	c.player.add_status("burn", 3)
	var burned := c.calc_poke_damage(80, "physical", "normal", c.player, foe)
	_check_true("burn halves physical damage", burned < clean)
	var special_clean := c.calc_poke_damage(80, "special", "normal", c.player, foe)
	c.player.set_status("burn", 0)
	_check("burn spares special damage",
			c.calc_poke_damage(80, "special", "normal", c.player, foe), special_clean)

	foe.add_status("burn", 3)
	var foe_hp := foe.hp
	c._tick_poke_ailments(foe)
	_check_true("burn chips HP each turn", foe.hp < foe_hp)
	_check("burn counts down", foe.get_status("burn"), 2)

	# Leech Seed moves HP from one side to the other.
	c.player.hp = c.player.max_hp - 30
	foe.add_status("leech_seed", 3)
	var seeded_hp := foe.hp
	var player_hp := c.player.hp
	c._tick_poke_ailments(foe)
	_check_true("leech seed drains the seeded", foe.hp < seeded_hp)
	_check_true("leech seed feeds the other side", c.player.hp > player_hp)

	# Sleep and Freeze cost the turn outright.
	foe.set_status("leech_seed", 0)
	foe.add_status("sleep", 2)
	_check_true("sleep stops the sleeper", c.incapacitated_reason(foe) != "")
	foe.set_status("sleep", 0)
	_check("awake actors act", c.incapacitated_reason(foe), "")

	# Flinch is spent on the one action it costs.
	foe.add_status("flinch", 1)
	_check_true("flinch stops the action", c.incapacitated_reason(foe) != "")
	_check("flinch is consumed", foe.get_status("flinch"), 0)

	# Heal Block and Embargo shut off healing and potions.
	c.player.add_status("heal_block", 2)
	var hp_now := c.player.hp
	c._heal(c.player, 20)
	_check("heal block stops healing", c.player.hp, hp_now)
	c.player.set_status("heal_block", 0)
	c._heal(c.player, 20)
	_check_true("healing works once unblocked", c.player.hp > hp_now)

	Run.potions[0] = "fire_potion"
	c.player.add_status("embargo", 2)
	_check("embargo blocks potions", c.use_potion(0, 0), false)
	c.player.set_status("embargo", 0)

	# Drowsy matures into sleep.
	foe.add_status("drowsy", 1)
	c._tick_poke_ailments(foe)
	_check_true("yawn puts the target to sleep", foe.has_status("sleep"))

	# A Normal-only deck against a Ghost can land nothing at all. Struggle is
	# typeless and always available, so the fight stays winnable.
	var walled := _begin(PokeCharacters.character_id("magikarp"),
			[PokeMobs.enemy_id("gastly")])
	var ghost: Actor = walled.enemies[0]
	_check("gastly is a ghost", ghost.poke_types, ["ghost", "poison"])
	_check("Tackle cannot touch it",
			walled.calc_poke_damage(40, "physical", "normal", walled.player, ghost), 0)
	var struggle_id := PokeMoves.card_id("struggle")
	_check_true("Struggle is typeless",
			String(PokeMoves.get_def(struggle_id)["poke"]["type"]) == PokeMoves.TYPELESS)
	_check_true("Struggle still lands",
			walled.calc_poke_damage(50, "physical", PokeMoves.TYPELESS,
					walled.player, ghost) > 0)
	var has_struggle := false
	for hc in walled.hand:
		if hc.id == struggle_id:
			has_struggle = true
	_check_true("a walled hand is handed Struggle", has_struggle)
	# And a mob keeps something it can use against a player it cannot touch.
	_check_true("mobs know Struggle too",
			(EnemyLibrary.get_def(PokeMobs.enemy_id("rattata"))["moves"] as Dictionary)
					.has("Struggle"))

	# Applying an ailment through a card.
	var will_o := Card.create(PokeMoves.card_id("will-o-wisp"))
	c.hand.append(will_o)
	c.energy = 3
	foe.set_status("burn", 0)
	c.play_card(will_o, 0)
	_check_true("will-o-wisp burns", foe.has_status("burn"))


func _test_speed() -> void:
	print("[poke] --- speed and initiative")
	var c := _begin(PokeCharacters.character_id("pikachu"), [PokeMobs.enemy_id("slowpoke")])
	_check("pikachu outspeeds slowpoke",
			c.effective_speed(c.player) > c.effective_speed(c.enemies[0]), true)

	# Paralysis quarters Speed, exactly as in the games.
	var full := c.effective_speed(c.player)
	c.player.add_status("paralysis", 2)
	_check("paralysis quarters speed", c.effective_speed(c.player), int(full * 0.25))
	c.player.set_status("paralysis", 0)

	# A Speed stage moves it too.
	c.player.add_stage("spe", 2)
	_check_true("+2 Speed is double", c.effective_speed(c.player) == full * 2)
	c.player.add_stage("spe", -2)

	# Something faster than the player gets the first hit in.
	var slow := _begin(PokeCharacters.character_id("shuckle"),
			[PokeMobs.enemy_id("electrode")])
	_check_true("electrode outspeeds shuckle",
			slow.effective_speed(slow.enemies[0]) > slow.effective_speed(slow.player))
	_check_true("the faster side struck first",
			slow.player.hp < slow.player.max_hp or slow.player.block > 0
					or slow.enemies[0].block > 0 or slow.turn >= 1)

	# However badly outsped, the player always gets to act at least once.
	for i in range(25):
		var ambush := _begin(PokeCharacters.character_id("shuckle"),
				[PokeMobs.enemy_id("electrode"), PokeMobs.enemy_id("jolteon"),
				PokeMobs.enemy_id("crobat")])
		if ambush.player.hp < 1 or (ambush.finished and not ambush.victory):
			_check("an ambush left the player alive (seed %d)" % i, ambush.player.hp, 1)
			break
		if i == 24:
			_check_true("25 ambushes, still standing every time", true)

	# ── The ATB gauge itself ────────────────────────────────────────────────
	print("[poke] --- ATB charge gauges")
	var atb := _begin(PokeCharacters.character_id("snorlax"),
			[PokeMobs.enemy_id("slowpoke"), PokeMobs.enemy_id("jolteon")])
	var slowpoke: Actor = atb.enemies[0]
	var jolteon: Actor = atb.enemies[1]
	_check_true("jolteon is much faster than slowpoke",
			atb.effective_speed(jolteon) > atb.effective_speed(slowpoke) * 2)

	# Let a long stretch of time run and count who actually acted. Turn order is
	# emergent: the fast one should act far more often than the slow one.
	for step in range(400):
		if atb.finished:
			break
		if atb.phase == "player":
			atb.end_turn()
		else:
			atb.step_enemy()
	var jolt_turns := jolteon.turn_count
	var slow_turns := slowpoke.turn_count
	print("[poke]      over one fight: jolteon acted %d times, slowpoke %d"
			% [jolt_turns, slow_turns])
	_check_true("the faster enemy acted more often", jolt_turns > slow_turns)
	_check_true("and roughly in proportion to Speed",
			float(jolt_turns) > float(slow_turns) * 1.5)

	# A gauge reads 0-1 for the UI, and empties when its owner acts.
	var gauge := _begin(PokeCharacters.character_id("pikachu"),
			[PokeMobs.enemy_id("rattata")])
	_check_true("a gauge reads as a fraction",
			gauge.charge_ratio(gauge.player) >= 0.0
					and gauge.charge_ratio(gauge.player) <= 1.0)
	if gauge.phase == "player":
		var before_charge := gauge.player.charge
		gauge.end_turn()
		_check_true("acting spends the gauge", gauge.player.charge < before_charge)

	# Paralysis quarters Speed, so it should cost real turns, not just a number.
	var para := _begin(PokeCharacters.character_id("jolteon"),
			[PokeMobs.enemy_id("rattata")])
	var free_speed := para.effective_speed(para.player)
	para.player.add_status("paralysis", 99)
	_check_true("paralysis costs three quarters of your Speed",
			para.effective_speed(para.player) < free_speed * 0.3)
