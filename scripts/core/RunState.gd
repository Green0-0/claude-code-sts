extends Node

## Autoloaded as `Run`. Holds everything that persists between rooms.

signal run_started
signal gold_changed(amount: int)
signal hp_changed(hp: int, max_hp: int)
signal relic_gained(id: String)
signal deck_changed

const POTION_SLOTS := 3
const SAVE_PATH := "user://spire_save.json"

## ── The party ───────────────────────────────────────────────────────────────
## The player's side is a list of members. `character`, `deck`, `hp`, `max_hp`,
## `player_level` and `player_xp` below are proxies onto the *lead* member, so
## the rest of the game — rewards, shops, events, the card picker — carries on
## addressing "the player" without knowing there is a party behind it.
##
## A Spire run (Ironclad, Silent) has no party at all and uses the plain fields.
var party: Array = []                 ## Array[PartyMember]
var lead_index: int = 0
const MAX_PARTY := 4

var relics: Array = []                ## Array[String]
var potions: Array = []               ## Array[String], "" for an empty slot
var gold: int = 99

## Backing values for the Spire's two characters, which have no party.
var _solo_character: String = "ironclad"
var _solo_deck: Array = []
var _solo_hp: int = 80
var _solo_max_hp: int = 80
var _solo_level: int = PokeLevels.START_LEVEL
var _solo_xp: int = 0


func lead() -> PartyMember:
	if party.is_empty():
		return null
	return party[clampi(lead_index, 0, party.size() - 1)]


## Members still standing, in party order.
func living_party() -> Array:
	var out: Array = []
	for m in party:
		if (m as PartyMember).is_alive():
			out.append(m)
	return out


func has_party() -> bool:
	return not party.is_empty()


var character: String:
	get:
		var m := lead()
		return m.character_id if m != null else _solo_character
	set(value):
		var m := lead()
		if m != null:
			m.character_id = value
		else:
			_solo_character = value

var deck: Array:
	get:
		var m := lead()
		return m.deck if m != null else _solo_deck
	set(value):
		var m := lead()
		if m != null:
			m.deck = value
		else:
			_solo_deck = value

var hp: int:
	get:
		var m := lead()
		return m.hp if m != null else _solo_hp
	set(value):
		var m := lead()
		if m != null:
			m.hp = value
		else:
			_solo_hp = value

var max_hp: int:
	get:
		var m := lead()
		return m.max_hp if m != null else _solo_max_hp
	set(value):
		var m := lead()
		if m != null:
			m.max_hp = value
		else:
			_solo_max_hp = value
var act: int = 1
var floor_num: int = 0
var ascension: int = 0

var map: Dictionary = {}
var current_node: int = -1
var visited_nodes: Array = []
var recent_encounters: Array = []
var elites_slain: int = 0
var bosses_slain: int = 0
var seed_value: int = 0
var rng := RandomNumberGenerator.new()

## Reward-pool bookkeeping so rarities drift like the real game.
var card_rare_chance: float = 0.03
var card_uncommon_chance: float = 0.37
var relic_pool_used: Array = []
var event_pool_used: Array = []
var shop_removals: int = 0
var last_combat_was_elite: bool = false
var pending_boss_relic: bool = false
var run_active: bool = false
var run_score: int = 0

## ── Levelling ──────────────────────────────────────────────────────────────
## A Pokemon run is four acts rather than three, so there is room for a party to
## level through two or three evolutions before it ends. The Spire's own two
## characters keep their original three-act climb.
const ACTS := 3
const POKEMON_ACTS := 4

## The level the dungeon fields on the final floor. The party is expected to
## arrive somewhere near it, having evolved once or twice on the way.
const DUNGEON_END_LEVEL := 55

var player_level: int:
	get:
		var m := lead()
		return m.level if m != null else _solo_level
	set(value):
		var m := lead()
		if m != null:
			m.level = value
		else:
			_solo_level = value

var player_xp: int:
	get:
		var m := lead()
		return m.xp if m != null else _solo_xp
	set(value):
		var m := lead()
		if m != null:
			m.xp = value
		else:
			_solo_xp = value
var pending_evolution: Dictionary = {}   ## branch offered but not yet answered
var last_encounter_role: String = "monster"

## Species the player has actually met. A ball can only be thrown at something
## you have seen — catching out of a catalogue you have never fought would make
## the choice arbitrary.
var seen_species: Array = []
## Balls in hand, awarded one per boss.
var balls: Array = []


func _ready() -> void:
	randomize()


# ─────────────────────────────────── Run setup ────────────────────────────────
func start_run(char_id: String, run_seed: int = 0, asc: int = 0) -> void:
	character = char_id
	seed_value = run_seed if run_seed != 0 else randi()
	rng = RandomNumberGenerator.new()
	rng.seed = seed_value
	ascension = asc

	pending_evolution = {}
	party.clear()
	lead_index = 0
	seen_species.clear()
	balls.clear()

	var cdef: Dictionary = CardLibrary.character(char_id)
	if PokeCharacters.is_pokemon_character(char_id):
		# A Pokemon run starts as a party of one and grows by capture.
		party.append(PartyMember.create(char_id, PokeLevels.START_LEVEL, 1))
		(party[0] as PartyMember).party_size_hint = 1
		if ascension >= 1:
			lead().max_hp -= 5
			lead().hp = lead().max_hp
	else:
		_solo_character = char_id
		_solo_level = PokeLevels.START_LEVEL
		_solo_xp = 0
		_solo_deck = []
		_solo_max_hp = int(cdef["max_hp"])
		if ascension >= 1:
			_solo_max_hp -= 5
		_solo_hp = _solo_max_hp
	gold = 99
	act = 1
	floor_num = 0
	elites_slain = 0
	bosses_slain = 0
	run_score = 0
	relics.clear()
	potions = ["", "", ""]
	visited_nodes.clear()
	recent_encounters.clear()
	relic_pool_used.clear()
	event_pool_used.clear()
	shop_removals = 0
	card_rare_chance = 0.03
	card_uncommon_chance = 0.37
	pending_boss_relic = false

	# A party member arrives with its own starter deck already built.
	if not has_party():
		for id in CardLibrary.starter_deck(char_id):
			deck.append(Card.create(id))
	add_relic(String(cdef["relic"]))
	if ascension >= 10:
		deck.append(Card.create("ascenders_bane"))

	new_act(1)
	run_active = true
	run_started.emit()


func new_act(new_act_num: int) -> void:
	act = new_act_num
	map = MapGen.generate(act, rng)
	current_node = -1
	visited_nodes.clear()
	recent_encounters.clear()


# ─────────────────────────────────── Resources ────────────────────────────────
func add_gold(amount: int) -> void:
	gold = max(0, gold + amount)
	gold_changed.emit(gold)


func spend_gold(amount: int) -> bool:
	if gold < amount:
		return false
	gold -= amount
	gold_changed.emit(gold)
	return true


func heal(amount: int) -> void:
	hp = clampi(hp + amount, 0, max_hp)
	hp_changed.emit(hp, max_hp)


func take_damage(amount: int) -> void:
	hp = max(0, hp - amount)
	hp_changed.emit(hp, max_hp)


func add_max_hp(amount: int) -> void:
	max_hp += amount
	hp += amount
	hp_changed.emit(hp, max_hp)


func is_dead() -> bool:
	return hp <= 0


func hp_ratio_low() -> bool:
	return max_hp > 0 and float(hp) / float(max_hp) < 0.3


# ───────────────────────────────────── Relics ─────────────────────────────────
func has_relic(id: String) -> bool:
	return relics.has(id)


func add_relic(id: String) -> void:
	if not RelicLibrary.has(id) or has_relic(id):
		return
	var d := RelicLibrary.get_def(id)
	if d.has("replaces") and has_relic(String(d["replaces"])):
		relics.erase(String(d["replaces"]))
	relics.append(id)
	relic_pool_used.append(id)
	_apply_relic_pickup(id)
	relic_gained.emit(id)


func _apply_relic_pickup(id: String) -> void:
	var d := RelicLibrary.get_def(id)
	var hook: String = String(d.get("on_pickup", ""))
	if hook.begins_with("max_hp:"):
		add_max_hp(int(hook.split(":")[1]))
	elif hook == "tiny_house":
		add_gold(50)
		add_max_hp(5)
		add_potion(PotionLibrary.random_potion(rng))
		var choices := random_card_ids(1, false)
		if choices.size() > 0:
			add_card(Card.create(choices[0]))
		var upgradable: Array = []
		for c in deck:
			if c.can_upgrade():
				upgradable.append(c)
		if upgradable.size() > 0:
			(upgradable[rng.randi_range(0, upgradable.size() - 1)] as Card).upgrade()


func random_relic(rarity: String = "") -> String:
	var pools: Array = []
	if rarity != "":
		pools = RelicLibrary.pool(rarity)
	else:
		var r := rng.randf()
		if r < 0.50:
			pools = RelicLibrary.common_pool()
		elif r < 0.83:
			pools = RelicLibrary.uncommon_pool()
		else:
			pools = RelicLibrary.rare_pool()
	var avail: Array = []
	for id in pools:
		if not has_relic(id):
			avail.append(id)
	if avail.is_empty():
		# Fall back to any relic the player is missing.
		for id in RelicLibrary.RELICS:
			if not has_relic(id) and RelicLibrary.RELICS[id]["rarity"] != "starter":
				avail.append(id)
		avail.sort()
	if avail.is_empty():
		return ""
	return avail[rng.randi_range(0, avail.size() - 1)]


# ───────────────────────────────────── Potions ────────────────────────────────
func potion_count() -> int:
	var n := 0
	for p in potions:
		if p != "":
			n += 1
	return n


func has_potion_space() -> bool:
	return potions.has("")


func add_potion(id: String) -> bool:
	if id == "":
		return false
	for i in range(potions.size()):
		if potions[i] == "":
			potions[i] = id
			return true
	return false


func remove_potion(slot: int) -> void:
	if slot >= 0 and slot < potions.size():
		potions[slot] = ""


# ────────────────────────────────────── Deck ──────────────────────────────────
func add_card(c: Card) -> void:
	deck.append(c)
	deck_changed.emit()


func remove_card(c: Card) -> void:
	deck.erase(c)
	deck_changed.emit()


func card_color() -> String:
	return String(CardLibrary.character(character)["color"])


## True while the player is running a Pokemon, which switches the dungeon over
## to Pokemon encounters and the Pokemon damage rules.
func is_pokemon_run() -> bool:
	return PokeCharacters.is_pokemon_character(character)


## The species record behind the current run, or {} for Ironclad and Silent.
## After an evolution this is the *evolved* species: evolving rewrites
## `character`, so everything downstream — stats, types, card pool — follows.
func player_mon() -> Dictionary:
	if not is_pokemon_run():
		return {}
	return PokeCharacters.mon_for(character)


# ──────────────────────────────── Levelling ───────────────────────────────────
signal levelled_up(level: int)
signal evolution_available(branches: Array)


func growth_rate() -> String:
	var mon := player_mon()
	return String(mon.get("growth", "medium")) if not mon.is_empty() else "medium"


func xp_to_next() -> int:
	if player_level >= PokeLevels.MAX_LEVEL:
		return 0
	return PokeLevels.xp_for_level(growth_rate(), player_level + 1) - player_xp


func level_progress() -> float:
	return PokeLevels.level_progress(growth_rate(), player_xp)


## Grants experience to the whole party and applies any level-ups.
##
## Everyone still standing gets the full amount, Exp-Share style, rather than
## only whoever landed the blow. A party that levels unevenly stops being a party
## — the back two would fall behind the curve and never catch up.
##
## Returns the number of levels the lead gained, which is what the reward screen
## reports.
func award_xp(amount: int) -> int:
	if amount <= 0:
		return 0
	if not has_party():
		if not is_pokemon_run():
			return 0
		_solo_xp += amount
		return 0
	var lead_gain := 0
	for m in living_party():
		var member: PartyMember = m
		var gained := member.award_xp(amount)
		if member == lead():
			lead_gain = gained
	hp_changed.emit(hp, max_hp)
	if lead_gain > 0:
		levelled_up.emit(player_level)
	return lead_gain


## Every member with an evolution waiting, as [{member, branches}].
func pending_evolutions() -> Array:
	var out: Array = []
	for m in party:
		var member: PartyMember = m
		if not member.is_alive():
			continue
		var branches := member.evolutions()
		if not branches.is_empty():
			out.append({"member": member, "branches": branches})
	return out


## Swaps the run's species for one it evolves into. The deck comes along
## untouched — they are moves, and the evolved form knows them — but the stat
## line, typing and future card pool are the new species'.
## Evolves a specific member, or the lead if none is given.
func evolve_member(member: PartyMember, species_name: String) -> bool:
	if member == null or not member.evolve_into(species_name):
		return false
	pending_evolution = {}
	hp_changed.emit(hp, max_hp)
	deck_changed.emit()
	return true


func evolve_into(species_name: String) -> bool:
	return evolve_member(lead(), species_name)


# ──────────────────────────────── Recruiting ──────────────────────────────────
## Adds a caught Pokemon to the party. Returns false when there is no room.
func add_to_party(species: String, at_level: int) -> bool:
	if party.size() >= MAX_PARTY:
		return false
	var member := PartyMember.create(PokeCharacters.character_id(species), at_level,
			party.size() + 1)
	member.caught = true
	party.append(member)
	_resize_party()
	deck_changed.emit()
	return true


## The HP counterweight depends on how many of you there are, so everyone
## restats when the party changes size. Proportions are preserved, so nobody
## looks like they took damage for gaining a team-mate.
func _resize_party() -> void:
	for m in party:
		var member: PartyMember = m
		member.party_size_hint = party.size()
		member.restat(false, party.size())
	hp_changed.emit(hp, max_hp)


func set_lead(index: int) -> void:
	lead_index = clampi(index, 0, max(0, party.size() - 1))
	deck_changed.emit()
	hp_changed.emit(hp, max_hp)


## Rarity-weighted card ids for a combat reward.
func random_card_ids(count: int, allow_colorless: bool = true) -> Array:
	var out: Array = []
	var guard := 0
	while out.size() < count and guard < 200:
		guard += 1
		# A Pokemon is offered its own moves and nothing else, so the Colorless
		# pool is off the table for the whole run.
		var use_colorless := allow_colorless and not is_pokemon_run() \
				and rng.randf() < 0.05
		var color := "colorless" if use_colorless else card_color()
		var rarity := _roll_card_rarity()
		# Most rewards are gated to what the party could plausibly know; a few
		# reach past it into the rest of the learnset, and elites do so often.
		var pool: Array = []
		if use_colorless:
			pool = CardLibrary.colorless_pool(rarity)
		elif is_pokemon_run() and PokeCharacters.rolls_off_gate(last_encounter_role, rng):
			pool = PokeCharacters.reward_pool(character, rarity, 0)
		else:
			pool = CardLibrary.pool_for(color, rarity)
		# Not every colour has cards at every rarity (there are no common
		# Colorless cards), so widen the search until something is available.
		if pool.is_empty():
			pool = CardLibrary.colorless_pool() if use_colorless \
					else CardLibrary.pool_for(color, "common")
		if pool.is_empty():
			pool = CardLibrary.pool_for(card_color())
		if pool.is_empty():
			break
		var pick: String = pool[rng.randi_range(0, pool.size() - 1)]
		if out.has(pick):
			continue
		out.append(pick)
	return out


## Rarity of a card for this run. The same move can be a cheap level-up move for
## one species and an expensive tutor move for another, so a Pokemon run asks
## its own learnset rather than the shared card definition.
func card_rarity_of(id: String) -> String:
	if is_pokemon_run() and PokeMoves.is_move_card(id):
		return PokeCharacters.rarity_for(character, id)
	return String(CardLibrary.get_def(id)["rarity"])


func _roll_card_rarity() -> String:
	var r := rng.randf()
	if r < card_rare_chance:
		card_rare_chance = 0.03
		return "rare"
	if r < card_rare_chance + card_uncommon_chance:
		return "uncommon"
	# Missing a rare nudges the odds up, like the real game's rarity drift.
	card_rare_chance = minf(card_rare_chance + 0.01, 0.25)
	return "common"


func should_upgrade_reward_card() -> bool:
	# Cards from rewards are occasionally pre-upgraded in later acts.
	var chance := 0.0 if act == 1 else (0.125 if act == 2 else 0.25)
	return rng.randf() < chance


# ─────────────────────────────────── Navigation ───────────────────────────────
func nodes() -> Array:
	return map.get("nodes", [])


func node_at(idx: int) -> Dictionary:
	var ns := nodes()
	if idx < 0 or idx >= ns.size():
		return {}
	return ns[idx]


func available_nodes() -> Array:
	if current_node < 0:
		return map.get("starts", [])
	return node_at(current_node).get("next", [])


func enter_node(idx: int) -> void:
	current_node = idx
	visited_nodes.append(idx)
	floor_num += 1


## How far through the whole run this is, 0 at the first floor and 1 at the
## last. Drives the opponent BST cap and the level the dungeon fields, so both
## stretch automatically if the run gets longer or shorter.
## How many acts this run climbs. Pokemon runs are longer.
func acts_in_run() -> int:
	return POKEMON_ACTS if is_pokemon_run() else ACTS


func total_floors() -> int:
	return acts_in_run() * (MapGen.ROWS + 1)


func progress() -> float:
	return clampf(float(floor_num) / float(max(1, total_floors())), 0.0, 1.0)


## The level the dungeon is fighting at right now.
##
## It tracks the *party*, not the floor count. Driving it from progress alone let
## the curve outrun the experience the player was actually earning — by the Act 1
## boss the dungeon was eight levels ahead and the fight was a wall. The floor
## curve is kept as a lower bound so the dungeon still climbs for a player who
## skips fights, but the party's own level is what it matches.
func dungeon_level() -> int:
	var t := progress()
	var by_floor := float(PokeLevels.START_LEVEL) \
			+ (DUNGEON_END_LEVEL - PokeLevels.START_LEVEL) * t
	var floor_bound := int(round(by_floor * 0.75))
	var lvl: int = max(player_level, floor_bound) if is_pokemon_run() else int(round(by_floor))
	return clampi(lvl, PokeLevels.START_LEVEL, PokeLevels.MAX_LEVEL)


## Level for one encounter slot: elites and bosses are ahead of the curve, which
## is what makes them worth the relic.
func level_for_role(role: String) -> int:
	return PokeLevels.role_level(dungeon_level(), role)


func at_boss() -> bool:
	return current_node >= 0 and String(node_at(current_node).get("type", "")) == "boss"


func advance_act() -> bool:
	bosses_slain += 1
	run_score += 100 * act
	if act >= acts_in_run():
		return false
	new_act(act + 1)
	return true


# ─────────────────────────────────── Encounters ───────────────────────────────
func encounter_for_node(node_type: String) -> Array:
	var group: Array = []
	if node_type == "boss":
		group = EncounterLibrary.boss_for(act, rng)
	elif node_type == "elite":
		group = EncounterLibrary.pick(act, "elite", rng, recent_encounters)
	else:
		var early := visited_nodes.size() <= 3 and act == 1
		group = EncounterLibrary.pick(act, "weak" if early else "strong", rng, recent_encounters)
	last_encounter_role = node_type
	for id in group:
		var mon := PokeMobs.mon_for(String(id))
		if not mon.is_empty() and not seen_species.has(String(mon["name"])):
			seen_species.append(String(mon["name"]))
	recent_encounters.append(",".join(group))
	if recent_encounters.size() > 3:
		recent_encounters.pop_front()
	return group


func combat_gold_reward(node_type: String) -> int:
	match node_type:
		"elite": return rng.randi_range(25, 35)
		"boss": return rng.randi_range(95, 105)
	return rng.randi_range(10, 20)


# ────────────────────────────────────── Shop ──────────────────────────────────
func generate_shop() -> Dictionary:
	var stock := {"cards": [], "relics": [], "potions": [], "removal_cost": 75 + shop_removals * 25}
	var color := card_color()
	var attack_ids: Array = []
	var skill_ids: Array = []
	var power_ids: Array = []
	for id in CardLibrary.pool_for(color):
		match String(CardLibrary.get_def(id)["type"]):
			"attack": attack_ids.append(id)
			"skill": skill_ids.append(id)
			"power": power_ids.append(id)
	var picks: Array = []
	picks.append_array(_take_random(attack_ids, 2))
	picks.append_array(_take_random(skill_ids, 2))
	picks.append_array(_take_random(power_ids, 1))
	# A Pokemon's shop stocks its own moves and nothing else.
	if not is_pokemon_run():
		picks.append_array(_take_random(CardLibrary.colorless_pool(), 2))
	else:
		picks.append_array(_take_random(CardLibrary.pool_for(color), 2))
	for id in picks:
		var base := _card_base_price(card_rarity_of(id))
		var price := int(round(base * rng.randf_range(0.9, 1.1)))
		stock["cards"].append({"id": id, "price": price, "sold": false})
	for i in range(3):
		var rid := random_relic()
		if rid == "":
			continue
		var rprice := 150
		match String(RelicLibrary.get_def(rid)["rarity"]):
			"uncommon": rprice = 250
			"rare": rprice = 300
			"shop": rprice = 150
		stock["relics"].append({"id": rid, "price": int(round(rprice * rng.randf_range(0.95, 1.05))),
				"sold": false})
	for i in range(3):
		var pid := PotionLibrary.random_potion(rng)
		stock["potions"].append({"id": pid, "price": PotionLibrary.price(pid), "sold": false})
	return stock


func _card_base_price(rarity: String) -> int:
	match rarity:
		"common": return 50
		"uncommon": return 75
		"rare": return 150
	return 60


func _take_random(pool: Array, count: int) -> Array:
	var copy: Array = pool.duplicate()
	var out: Array = []
	while out.size() < count and copy.size() > 0:
		var i := rng.randi_range(0, copy.size() - 1)
		out.append(copy[i])
		copy.remove_at(i)
	return out


# ────────────────────────────────────── Events ────────────────────────────────
static var EVENTS := {
"big_fish": {
	"name": "Big Fish",
	"text": "You cast a line into a pool of shimmering water. Something bites.",
	"options": [
		{"label": "Banana — Heal 1/3 of your Max HP", "do": "heal_third"},
		{"label": "Donut — Gain 5 Max HP", "do": "maxhp_5"},
		{"label": "Box — Gain a relic and a Regret curse", "do": "relic_and_curse"},
	]},
"golden_idol": {
	"name": "Golden Idol",
	"text": "A golden idol sits on a pedestal, wired to something unpleasant.",
	"options": [
		{"label": "Take it — Gain 200 Gold, take 15 damage", "do": "idol_take"},
		{"label": "Leave it", "do": "nothing"},
	]},
"shining_light": {
	"name": "Shining Light",
	"text": "A blinding light pours from a crack in the rock.",
	"options": [
		{"label": "Enter — Upgrade 2 random cards, take 12 damage", "do": "light_enter"},
		{"label": "Leave", "do": "nothing"},
	]},
"the_cleric": {
	"name": "The Cleric",
	"text": "A traveling cleric offers her services, for a price.",
	"options": [
		{"label": "Heal — 35 Gold to heal 25% of Max HP", "do": "cleric_heal"},
		{"label": "Purify — 50 Gold to remove a card", "do": "cleric_purify"},
		{"label": "Leave", "do": "nothing"},
	]},
"living_wall": {
	"name": "Living Wall",
	"text": "The wall of the corridor is covered in writhing script.",
	"options": [
		{"label": "Forget — Remove a card from your deck", "do": "remove_card"},
		{"label": "Change — Replace a card with a random one", "do": "transform_card"},
		{"label": "Grow — Upgrade a card", "do": "upgrade_card"},
	]},
"bonfire": {
	"name": "Bonfire Spirits",
	"text": "Spirits dance around a roaring bonfire, hungry for an offering.",
	"options": [
		{"label": "Offer a card — Remove it and heal fully", "do": "bonfire_offer"},
		{"label": "Leave", "do": "nothing"},
	]},
"scrap_ooze": {
	"name": "Scrap Ooze",
	"text": "A vile ooze clutches something metallic in its mass.",
	"options": [
		{"label": "Reach in — Take 3 damage, 40% chance of a relic", "do": "ooze_reach"},
		{"label": "Leave", "do": "nothing"},
	]},
"world_of_goop": {
	"name": "World of Goop",
	"text": "Gold coins glitter beneath a pool of sucking goop.",
	"options": [
		{"label": "Gather gold — Gain 75 Gold, take 11 damage", "do": "goop_gather"},
		{"label": "Leave — Lose 15 Gold", "do": "goop_leave"},
	]},
"the_ssssserpent": {
	"name": "The Ssssserpent",
	"text": "\"Take my gold,\" the serpent hisses. \"All it costs is a little regret.\"",
	"options": [
		{"label": "Agree — Gain 175 Gold and a Doubt curse", "do": "serpent_agree"},
		{"label": "Disagree", "do": "nothing"},
	]},
"wheel_of_change": {
	"name": "Wheel of Change",
	"text": "A great wheel creaks in the dark. Fate favours the bold.",
	"options": [
		{"label": "Spin the wheel", "do": "wheel_spin"},
	]},
}


func pick_event() -> String:
	var avail: Array = []
	for id in EVENTS:
		if not event_pool_used.has(id):
			avail.append(id)
	avail.sort()
	if avail.is_empty():
		event_pool_used.clear()
		for id in EVENTS:
			avail.append(id)
		avail.sort()
	var pick: String = avail[rng.randi_range(0, avail.size() - 1)]
	event_pool_used.append(pick)
	return pick


## Returns {log: String, request: String} — `request` names a card-picker the UI
## must open ("remove", "upgrade", "transform") before the event completes.
func apply_event_option(event_id: String, option_index: int) -> Dictionary:
	var ev: Dictionary = EVENTS[event_id]
	var opt: Dictionary = ev["options"][option_index]
	var what: String = String(opt["do"])
	match what:
		"heal_third":
			var amount := int(round(max_hp / 3.0))
			heal(amount)
			return {"log": "You heal %d HP." % amount}
		"maxhp_5":
			add_max_hp(5)
			return {"log": "Your Max HP rises by 5."}
		"relic_and_curse":
			var rid := random_relic()
			add_relic(rid)
			add_card(Card.create("regret"))
			return {"log": "You obtain %s, and a Regret settles in your deck."
					% RelicLibrary.display_name(rid)}
		"idol_take":
			add_gold(200)
			take_damage(15)
			return {"log": "You grab the idol and take 15 damage. +200 Gold."}
		"light_enter":
			var upgraded := 0
			var pool: Array = []
			for c in deck:
				if c.can_upgrade():
					pool.append(c)
			while upgraded < 2 and pool.size() > 0:
				var i := rng.randi_range(0, pool.size() - 1)
				(pool[i] as Card).upgrade()
				pool.remove_at(i)
				upgraded += 1
			take_damage(12)
			deck_changed.emit()
			return {"log": "%d card(s) upgraded. You take 12 damage." % upgraded}
		"cleric_heal":
			if not spend_gold(35):
				return {"log": "You cannot afford it."}
			var amt := int(round(max_hp * 0.25))
			heal(amt)
			return {"log": "The cleric heals you for %d HP." % amt}
		"cleric_purify":
			if gold < 50:
				return {"log": "You cannot afford it."}
			spend_gold(50)
			return {"log": "Choose a card to remove.", "request": "remove"}
		"remove_card":
			return {"log": "Choose a card to remove.", "request": "remove"}
		"transform_card":
			return {"log": "Choose a card to transform.", "request": "transform"}
		"upgrade_card":
			return {"log": "Choose a card to upgrade.", "request": "upgrade"}
		"bonfire_offer":
			return {"log": "Choose a card to offer.", "request": "bonfire"}
		"ooze_reach":
			take_damage(3)
			if rng.randf() < 0.4:
				var rid2 := random_relic()
				add_relic(rid2)
				return {"log": "You take 3 damage and pull out %s!"
						% RelicLibrary.display_name(rid2)}
			return {"log": "You take 3 damage and find nothing but slime."}
		"goop_gather":
			add_gold(75)
			take_damage(11)
			return {"log": "+75 Gold. The goop burns for 11 damage."}
		"goop_leave":
			add_gold(-15)
			return {"log": "The goop swallows 15 of your Gold."}
		"serpent_agree":
			add_gold(175)
			add_card(Card.create("doubt"))
			return {"log": "+175 Gold. A Doubt joins your deck."}
		"wheel_spin":
			var roll := rng.randi_range(0, 5)
			match roll:
				0:
					add_gold(100)
					return {"log": "The wheel lands on riches: +100 Gold."}
				1:
					var rid3 := random_relic()
					add_relic(rid3)
					return {"log": "The wheel grants %s." % RelicLibrary.display_name(rid3)}
				2:
					heal(int(round(max_hp * 0.5)))
					return {"log": "The wheel restores half your Max HP."}
				3:
					return {"log": "Choose a card to remove.", "request": "remove"}
				4:
					take_damage(int(round(max_hp * 0.10)))
					return {"log": "The wheel bites: you lose 10% of your Max HP."}
				_:
					add_card(Card.create(_random_curse()))
					return {"log": "The wheel curses you."}
	return {"log": "Nothing happens."}


func _random_curse() -> String:
	var pool := CardLibrary.curse_pool()
	return pool[rng.randi_range(0, pool.size() - 1)]


func complete_event_request(request: String, c: Card) -> String:
	match request:
		"remove", "cleric_purify":
			remove_card(c)
			return "%s leaves your deck." % c.display_name()
		"upgrade":
			c.upgrade()
			deck_changed.emit()
			return "%s is upgraded." % c.display_name()
		"transform":
			remove_card(c)
			var ids := random_card_ids(1, false)
			var nc := Card.create(ids[0])
			add_card(nc)
			return "%s becomes %s." % [c.display_name(), nc.display_name()]
		"bonfire":
			remove_card(c)
			heal(max_hp)
			return "%s burns away. You are fully healed." % c.display_name()
	return ""


func removable_cards() -> Array:
	var out: Array = []
	for c in deck:
		if c.id != "ascenders_bane":
			out.append(c)
	return out


func upgradable_cards() -> Array:
	var out: Array = []
	for c in deck:
		if c.can_upgrade():
			out.append(c)
	return out


# ─────────────────────────────────── Save / load ──────────────────────────────
func save_run() -> void:
	if not run_active:
		return
	var cards: Array = []
	for c in deck:
		cards.append({"id": c.id, "up": c.upgrade_count})
	var members: Array = []
	for m in party:
		members.append((m as PartyMember).to_dict())
	var data := {
		"party": members, "lead": lead_index,
		"seen": seen_species, "balls": balls,
		"character": character, "gold": gold, "hp": hp, "max_hp": max_hp,
		"act": act, "floor": floor_num, "seed": seed_value, "ascension": ascension,
		"deck": cards, "relics": relics, "potions": potions,
		"map": map, "current_node": current_node, "visited": visited_nodes,
		"elites": elites_slain, "bosses": bosses_slain, "score": run_score,
		"rare_chance": card_rare_chance, "shop_removals": shop_removals,
		"events_used": event_pool_used,
		# Without these a restored run keeps its evolved species but drops back to
		# the starting level, which would rewrite its stats and its card pool.
		"player_level": player_level, "player_xp": player_xp,
		"encounter_role": last_encounter_role,
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(data))
		f.close()


func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


func load_run() -> bool:
	if not has_save():
		return false
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return false
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return false
	var d: Dictionary = parsed
	character = String(d.get("character", "ironclad"))
	gold = int(d.get("gold", 99))
	hp = int(d.get("hp", 70))
	max_hp = int(d.get("max_hp", 80))
	act = int(d.get("act", 1))
	floor_num = int(d.get("floor", 0))
	seed_value = int(d.get("seed", 0))
	ascension = int(d.get("ascension", 0))
	elites_slain = int(d.get("elites", 0))
	bosses_slain = int(d.get("bosses", 0))
	run_score = int(d.get("score", 0))
	card_rare_chance = float(d.get("rare_chance", 0.03))
	shop_removals = int(d.get("shop_removals", 0))
	event_pool_used = (d.get("events_used", []) as Array).duplicate()
	# The party has to be rebuilt before anything touches the proxies, since
	# character/deck/hp all read through the lead member.
	seen_species = (d.get("seen", []) as Array).duplicate()
	balls = (d.get("balls", []) as Array).duplicate()
	party.clear()
	lead_index = int(d.get("lead", 0))
	for entry in d.get("party", []):
		party.append(PartyMember.from_dict(entry))
	for m in party:
		(m as PartyMember).party_size_hint = party.size()
	lead_index = clampi(lead_index, 0, max(0, party.size() - 1))
	player_level = int(d.get("player_level", PokeLevels.START_LEVEL))
	player_xp = int(d.get("player_xp", 0))
	last_encounter_role = String(d.get("encounter_role", "monster"))
	# An older save, or a Spire run, has no level recorded; derive one so the
	# stat formula still has something sane to work with.
	if player_xp <= 0 and is_pokemon_run():
		player_xp = PokeLevels.xp_for_level(growth_rate(), player_level)
	rng = RandomNumberGenerator.new()
	rng.seed = seed_value
	rng.state = randi()
	# A party run restored its decks member by member above; the flat "deck" key
	# is only for the Spire's two, and rewriting it would clobber the lead's.
	if not has_party():
		deck.clear()
		for entry in d.get("deck", []):
			var c := Card.create(String(entry["id"]))
			c.upgrade_count = int(entry["up"])
			c.upgraded = c.upgrade_count > 0
			deck.append(c)
	relics = (d.get("relics", []) as Array).duplicate()
	potions = (d.get("potions", ["", "", ""]) as Array).duplicate()
	# JSON turns the map's integer arrays into floats; rebuild them as ints.
	map = _sanitize_map(d.get("map", {}))
	current_node = int(d.get("current_node", -1))
	visited_nodes.clear()
	for v in d.get("visited", []):
		visited_nodes.append(int(v))
	run_active = true
	return true


func _sanitize_map(raw) -> Dictionary:
	if typeof(raw) != TYPE_DICTIONARY:
		return MapGen.generate(act, rng)
	var out := {"nodes": [], "starts": [], "boss": 0, "act": act}
	for n in raw.get("nodes", []):
		var nn := {"row": int(n["row"]), "col": int(n["col"]), "type": String(n["type"]),
				"next": [], "prev": [], "id": int(n["id"])}
		for x in n.get("next", []):
			(nn["next"] as Array).append(int(x))
		for x in n.get("prev", []):
			(nn["prev"] as Array).append(int(x))
		(out["nodes"] as Array).append(nn)
	for s in raw.get("starts", []):
		(out["starts"] as Array).append(int(s))
	out["boss"] = int(raw.get("boss", 0))
	if (out["nodes"] as Array).is_empty():
		return MapGen.generate(act, rng)
	return out


func clear_save() -> void:
	if has_save():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
		if has_save():
			var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
			if f != null:
				f.store_string("")
				f.close()


func end_run() -> void:
	run_active = false
	clear_save()
