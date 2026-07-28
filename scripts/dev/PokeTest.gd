extends Node

## Checks the Pokemon layer: the imported data, the stat conversions, the cards
## built from learnsets, the mobs built from species, BST-weighted encounters,
## and the combat rules those feed into.
##   godot --headless -- --poke-test

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
	_test_type_chart()
	_test_stats()
	_test_cards()
	_test_learnset_decks()
	_test_mobs()
	_test_encounters()
	_test_combat()
	_test_ailments()
	_test_speed()


# ═══════════════════════════════════ Data ════════════════════════════════════
func _test_data() -> void:
	print("[poke] --- imported data")
	_check_true("data available", PokeData.available())
	_check("full national dex", PokeData.mon_count(), 1025)
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
			PokeBalance.mob_hp(blissey) > PokeBalance.mob_hp(pikachu) * 3)
	_check_true("shedinja is fragile", PokeBalance.mob_hp(shedinja) < 20)
	_check_true("player HP is playable",
			PokeBalance.player_hp(pikachu) >= 50 and PokeBalance.player_hp(pikachu) <= 90)
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
	var strong := PokeBalance.base_damage(90, 130, 80)
	var weak := PokeBalance.base_damage(90, 50, 80)
	_check_true("higher Attack hits harder", strong > weak)
	var vs_wall := PokeBalance.base_damage(90, 90, 160)
	var vs_paper := PokeBalance.base_damage(90, 90, 40)
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
	_check_true("HP came from base stats", int(d["max_hp"]) > 40)

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

	var pool := PokeCharacters.reward_pool(pika)
	_check_true("reward pool is big", pool.size() > 40)
	var pool_legal := true
	for id in pool:
		if not learnable.has(id):
			pool_legal = false
	_check_true("reward pool is drawn from the learnset", pool_legal)

	# A different species gets a different deck and pool.
	var char_bulba := PokeCharacters.character_id("bulbasaur")
	_check_true("species differ",
			PokeCharacters.starter_deck(char_bulba) != deck)
	_check_true("bulbasaur cannot learn Thunderbolt",
			not PokeCharacters.reward_pool(char_bulba).has(PokeMoves.card_id("thunderbolt")))
	_check_true("pikachu can learn Thunderbolt",
			pool.has(PokeMoves.card_id("thunderbolt")))

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
	_check_true("boss has the most moves",
			(boss["moves"] as Dictionary).size() > (d["moves"] as Dictionary).size())

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
	var deerling_boss := EnemyLibrary.get_def(PokeMobs.enemy_id("deerling", "boss"))
	_check_true("as a boss it has",
			(deerling_boss["moves"] as Dictionary).has("Double Edge"))

	# Nothing may know a move above its role's level cap — unless it has no way
	# to attack at all below it, in which case reaching higher beats a fight
	# that cannot be won. Delibird learns its first attack at 25.
	var cap: int = PokeMobs.MOVE_LEVEL_CAP["normal"]
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
	var rattata := PokeEncounters.probability("rattata", 1, "weak")
	var dragonite := PokeEncounters.probability("dragonite", 1, "weak")
	_check_true("weak act 1 favours low BST", rattata > dragonite * 100.0)
	print("[poke]      act1 weak: rattata %.3f%%, dragonite %.4f%%" % [rattata, dragonite])

	var drag3 := PokeEncounters.probability("dragonite", 3, "boss")
	var ratt3 := PokeEncounters.probability("rattata", 3, "boss")
	_check_true("act 3 bosses favour high BST", drag3 > ratt3 * 100.0)
	print("[poke]      act3 boss: dragonite %.3f%%, rattata %.4f%%" % [drag3, ratt3])

	# Legendaries are boss material only.
	_check("mewtwo is not a weak encounter",
			PokeEncounters.probability("mewtwo", 1, "weak"), 0.0)
	_check_true("mewtwo can be a boss",
			PokeEncounters.probability("mewtwo", 3, "boss") > 0.0)

	# The same species gets rarer as the band moves away from its BST.
	var caterpie1 := PokeEncounters.probability("caterpie", 1, "weak")
	var caterpie3 := PokeEncounters.probability("caterpie", 3, "weak")
	_check_true("caterpie fades by act 3", caterpie1 > caterpie3 * 10.0)

	# Tables must be non-empty and sum to 100%.
	for act in [1, 2, 3]:
		for kind in ["weak", "strong", "elite", "boss"]:
			var rows := PokeEncounters.table(act, kind)
			if rows.is_empty():
				_check("act %d %s table is populated" % [act, kind], 0, 1)
				continue
			var total := 0.0
			for row in rows:
				total += PokeEncounters.probability(
						String(PokeData.mon_at(int(row["index"]))["name"]), act, kind)
			_near("act %d %s sums to 100%%" % [act, kind], total, 100.0, 0.5)

	# Picking yields spawnable ids, and weak groups come in packs.
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var pack_sizes: Array = []
	for i in range(40):
		var group := PokeEncounters.pick(1, "weak", rng, [])
		_check_true("picked group is not empty", group.size() > 0) if i == 0 else null
		pack_sizes.append(group.size())
		for eid in group:
			if EnemyLibrary.get_def(eid).is_empty():
				_check("picked id %s is spawnable" % eid, 0, 1)
	var biggest := 0
	for n in pack_sizes:
		biggest = maxi(biggest, int(n))
	_check_true("weak encounters can be packs", biggest >= 2)

	var boss_group := PokeEncounters.boss_for(3, rng)
	_check("bosses come alone", boss_group.size(), 1)
	_check_true("boss id is a boss", String(boss_group[0]).ends_with("_boss"))

	print("[poke]      act1 weak top: %s" % str(PokeEncounters.top_candidates(1, "weak", 5)))
	print("[poke]      act3 boss top: %s" % str(PokeEncounters.top_candidates(3, "boss", 5)))


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

	# But it cannot deny the player their first turn. A pack of fast attackers
	# used to be able to end the fight before a card was drawn.
	for i in range(25):
		var ambush := _begin(PokeCharacters.character_id("shuckle"),
				[PokeMobs.enemy_id("electrode"), PokeMobs.enemy_id("jolteon"),
				PokeMobs.enemy_id("crobat")])
		if ambush.player.hp < 1 or ambush.finished:
			_check("an ambush left the player alive (seed %d)" % i, ambush.player.hp, 1)
			break
		if i == 24:
			_check_true("25 ambushes, still standing every time", true)
	# Only one of them gets the jump, however many are faster.
	var pack := _begin(PokeCharacters.character_id("shuckle"),
			[PokeMobs.enemy_id("electrode"), PokeMobs.enemy_id("jolteon")])
	_check_true("the ambush is one attacker, not the whole pack",
			pack.player.max_hp - pack.player.hp < pack.player.max_hp * 0.5)

	# Enemies act fastest-first within the enemy phase.
	var many := _begin(PokeCharacters.character_id("snorlax"),
			[PokeMobs.enemy_id("slowpoke"), PokeMobs.enemy_id("jolteon")])
	many.end_turn()
	var order: Array = many._enemy_order
	if order.size() >= 2:
		_check_true("enemy phase runs in Speed order",
				many.effective_speed(order[0]) >= many.effective_speed(order[1]))
	else:
		_check("enemy order was built", order.size(), 2)
