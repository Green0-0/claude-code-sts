class_name PokeCharacters
extends RefCounted

## The player-side version of every Pokemon.
##
## Character ids are "pkc_<name>", to keep them distinct from the enemy ids in
## PokeMobs ("pkm_<name>") — the same species is both, with different numbers.
##
## A character's deck and its card pool both come from its own learnset, chosen
## by answering the question the games answer: what does this species know at
## the level it is caught at? Level-up moves at or below START_LEVEL become the
## starting deck; everything it can ever learn becomes the reward pool.

const ID_PREFIX := "pkc_"
const COLOR := "pokemon"

## The level the run starts at. Low enough that a starter's deck is its first
## few moves rather than its whole movepool.
const START_LEVEL := 16

## Starting decks are padded to this size so early hands are not one card.
const DECK_SIZE := 10

## Distinct moves in the opening deck, and how many of them must be attacks.
## Three-to-one keeps a starting hand able to fight.
const SIGNATURE_SIZE := 4
const ATTACKS_IN_DECK := 3

static var _cache: Dictionary = {}
static var _pool_cache: Dictionary = {}


static func character_id(mon_name: String) -> String:
	return ID_PREFIX + mon_name.replace("-", "_")


static func is_pokemon_character(id: String) -> bool:
	return id.begins_with(ID_PREFIX)


static func mon_name_of(id: String) -> String:
	if not is_pokemon_character(id):
		return ""
	return id.substr(ID_PREFIX.length()).replace("_", "-")


static func mon_for(id: String) -> Dictionary:
	return PokeData.mon(mon_name_of(id))


# ═══════════════════════════════ Definitions ═════════════════════════════════
## Card pools are keyed by character id and go stale when a run evolves into a
## new species. Called by RunState.evolve_into.
static func forget(id: String) -> void:
	for key in _pool_cache.keys():
		if String(key).begins_with(id + "|"):
			_pool_cache.erase(key)


static func get_def(id: String, level: int = -1) -> Dictionary:
	# Max HP moves with the level, so it is computed per call; everything else
	# about a species is fixed and cached.
	var lvl := level if level > 0 else _current_level_for(id)
	if _cache.has(id):
		var cached: Dictionary = (_cache[id] as Dictionary).duplicate()
		cached["max_hp"] = PokeBalance.player_hp(mon_for(id), lvl)
		cached["level"] = lvl
		return cached
	var mon := mon_for(id)
	if mon.is_empty():
		return {}
	var types: Array = mon["types"]
	var d := {
		"name": PokeData.display_name(String(mon["name"])),
		"color": COLOR,
		"max_hp": PokeBalance.player_hp(mon, lvl),
		"level": lvl,
		# Every Pokemon run starts with the same relic; the species is already
		# the interesting variable.
		"relic": "burning_blood",
		"blurb": _blurb(mon),
		"tint": PokeData.type_color(String(types[0])),
		"poke": String(mon["name"]),
		"types": types,
		"bst": int(mon["bst"]),
		"stats": mon["stats"],
	}
	_cache[id] = d
	return d.duplicate()


## The level to report for a character. The one being played uses the run's
## live level; anything else (the picker listing every unit) uses the level a
## run would start at, so the list is comparing like with like.
static func _current_level_for(id: String) -> int:
	if Engine.get_main_loop() != null and Run != null and Run.character == id:
		return Run.player_level
	return PokeLevels.START_LEVEL


static func _blurb(mon: Dictionary) -> String:
	var stats: Dictionary = mon["stats"]
	var types: Array = mon["types"]
	var type_line := ""
	for t in types:
		type_line += ("/" if type_line != "" else "") + PokeData.display_name(String(t))
	var genus := String(mon.get("genus", ""))
	var lead := genus if genus != "" else "Pokemon"
	return "%s. %s type. HP %d / Atk %d / Def %d / SpA %d / SpD %d / Spe %d (BST %d)." % [
		lead, type_line, int(stats["hp"]), int(stats["atk"]), int(stats["df"]),
		int(stats["spa"]), int(stats["spd"]), int(stats["spe"]), int(mon["bst"])]


# ═════════════════════════════════ The deck ══════════════════════════════════
## Level-up moves known by START_LEVEL, most recent first, padded out with the
## earliest moves so the deck is never too thin to function.
static func starter_deck(id: String) -> Array:
	var mon := mon_for(id)
	if mon.is_empty():
		return []
	var attacks: Array = []
	var utility: Array = []
	_split(_known_by(mon, START_LEVEL), attacks, utility)

	# A deck that cannot deal damage cannot win a fight, so a species with no
	# attack at its starting level reaches up its own level-up list and then
	# into what it can be taught. Metapod, whose entire level-up set is Harden,
	# ends on Struggle — as it should.
	var reached_ahead := false
	if attacks.is_empty():
		reached_ahead = true
		_split(_known_by(mon, 0), attacks, utility)
	if attacks.is_empty():
		_split(_known_by(mon, 0, false), attacks, utility)
	if attacks.is_empty():
		var last := PokeMoves.fallback_move()
		if not last.is_empty():
			attacks.append({"id": PokeMoves.card_id(String(last["name"])), "level": 1,
					"power": int(last.get("power", 0)), "attacks": true})

	# Normally the best move it knows leads the deck. When we have had to reach
	# past its starting level, take the weakest of what we found instead — a
	# level-1 Abra should not open the run holding a tutor move.
	if reached_ahead:
		attacks.sort_custom(func(a, b): return int(a["power"]) < int(b["power"]))
	else:
		attacks.sort_custom(func(a, b): return int(a["power"]) > int(b["power"]))

	var signature: Array = []
	for k in attacks:
		if signature.size() >= ATTACKS_IN_DECK:
			break
		signature.append(String(k["id"]))
	for k in utility:
		if signature.size() >= SIGNATURE_SIZE:
			break
		signature.append(String(k["id"]))
	# Backfill with whatever is left if one side was short.
	for k in attacks + utility:
		if signature.size() >= SIGNATURE_SIZE:
			break
		if not signature.has(String(k["id"])):
			signature.append(String(k["id"]))
	if signature.is_empty():
		signature = _fallback_deck()
	if signature.is_empty():
		# Only reachable with no move data at all, and the caller can cope with
		# an empty deck far better than with a division by zero below.
		return []

	# Duplicate the signature moves until the deck is a workable size, so the
	# opening hand has options without handing out moves it cannot learn.
	var deck: Array = []
	var i := 0
	while deck.size() < DECK_SIZE:
		deck.append(signature[i % signature.size()])
		i += 1
	return deck


## Sorts known moves into the ones that can hurt something and the ones that
## cannot. Picking purely by level would hand Pikachu Growl, Play Nice and Tail
## Whip — all learnt at level 1, all sorting above the Thunder Shock it is
## famous for — and leave it unable to hurt anything.
static func _split(known: Array, attacks: Array, utility: Array) -> void:
	attacks.clear()
	utility.clear()
	for k in known:
		if bool(k["attacks"]):
			attacks.append(k)
		else:
			utility.append(k)


## The moves a species knows by a given level, most recent first. level_up_only
## restricts it to moves learnt by levelling; a level of 0 means "any level".
static func _known_by(mon: Dictionary, level: int, level_up_only: bool = true) -> Array:
	var known: Array = []
	for row in mon.get("learnset", []):
		if level_up_only and int(row[2]) != PokeData.LEARN_LEVEL:
			continue
		if level > 0 and int(row[1]) > level:
			continue
		var mv := PokeData.move_at(int(row[0]))
		if mv.is_empty():
			continue
		var id := PokeMoves.card_id(String(mv["name"]))
		var d := PokeMoves.get_def(id)
		if d.is_empty() or (d["effects"] as Array).is_empty():
			continue
		known.append({"id": id, "level": int(row[1]), "power": int(mv.get("power", 0)),
				"attacks": PokeMoves.deals_damage(d)})
	known.sort_custom(func(a, b): return int(a["level"]) > int(b["level"]))
	return known


## Last resort when a species has no expressible move at all.
static func _fallback_deck() -> Array:
	var mv := PokeMoves.fallback_move()
	return [PokeMoves.card_id(String(mv["name"]))] if not mv.is_empty() else []


# ════════════════════════════════ Reward pool ════════════════════════════════
## How far above the current level a level-up move can still be offered. A
## little slack keeps rewards from drying up between levels.
const LEVEL_GATE_SLACK := 4

## Chance that a reward ignores the level gate entirely and offers anything from
## the whole learnset — the lucky Hyper Beam at level 12. Elites are where you go
## looking for that, so they are far more generous.
const OFF_GATE_CHANCE := {"monster": 0.06, "elite": 0.35, "boss": 0.25}


## The moves this species can be offered right now.
##
## Rewards roll from what it could plausibly know: level-up moves at or below its
## level, plus everything it can be taught. The pool genuinely widens as the run
## goes on, and widens again on evolution, because the evolved species has a
## longer learnset.
##
## `level` of 0 means "no gate" — the whole learnset, used for the off-gate roll.
static func reward_pool(character_id: String, rarity: String = "",
		level: int = -1) -> Array:
	var gate := level if level >= 0 else _current_level_for(character_id)
	var key := "%s|%s|%d" % [character_id, rarity, gate]
	if _pool_cache.has(key):
		return _pool_cache[key]
	var mon := mon_for(character_id)
	var out: Array = []
	if mon.is_empty():
		_pool_cache[key] = out
		return out

	# Evolving mid-run should not strand you with a pool built for the form you
	# have outgrown, so anything further down the line counts as learnable too.
	var learnsets: Array = [mon]
	for later in PokeEvolution.line_from(String(mon["name"])):
		var m := PokeData.mon(later)
		if not m.is_empty():
			learnsets.append(m)

	for source in learnsets:
		for row in source.get("learnset", []):
			var mv := PokeData.move_at(int(row[0]))
			if mv.is_empty():
				continue
			var method := int(row[2])
			var learn_level := PokeBalance.learn_level(mv, int(row[1]), method)
			# The gate. Machine and tutor moves are gated too, on an implied
			# level — see PokeBalance.learn_level — or a level 5 starter could be
			# handed Fire Blast on the first floor.
			if gate > 0 and learn_level > gate + LEVEL_GATE_SLACK:
				continue
			var card_id := PokeMoves.card_id(String(mv["name"]))
			var d := PokeMoves.get_def(card_id)
			if d.is_empty() or (d["effects"] as Array).is_empty():
				continue
			# Rarity depends on how the move is learnt, so it is computed here
			# rather than being baked into the shared card definition.
			var r := PokeBalance.card_rarity(mv, learn_level, method)
			if r == "basic":
				continue
			if rarity != "" and r != rarity:
				continue
			if not out.has(card_id):
				out.append(card_id)
	out.sort()
	_pool_cache[key] = out
	return out


## Rolls whether this reward ignores the level gate. Elites are where the
## out-of-reach moves come from.
static func rolls_off_gate(role: String, rng: RandomNumberGenerator) -> bool:
	return rng.randf() < float(OFF_GATE_CHANCE.get(role, 0.06))


## Rarity of a card for the Pokemon currently being played. The same move can be
## a common level-up move for one species and a rare tutor move for another.
static func rarity_for(character_id: String, card_id: String) -> String:
	var mon := mon_for(character_id)
	var target := PokeData.move_index(PokeMoves.move_for_card(card_id).get("name", ""))
	if mon.is_empty() or target < 0:
		return "common"
	for row in mon.get("learnset", []):
		if int(row[0]) == target:
			return PokeBalance.card_rarity(PokeData.move_at(target), int(row[1]), int(row[2]))
	return "common"


# ═════════════════════════════════ Listing ═══════════════════════════════════
## Every playable Pokemon, in dex order, for the character-select screen.
static func all_ids() -> Array:
	var out: Array = []
	for mon in PokeData.mons():
		out.append(character_id(String(mon["name"])))
	return out


## Substring search over names and types, for the character-select filter.
static func search(query: String, limit: int = 60) -> Array:
	var q := query.strip_edges().to_lower()
	var out: Array = []
	for mon in PokeData.mons():
		if out.size() >= limit:
			break
		var name := String(mon["name"])
		if q != "":
			var hit := name.contains(q)
			if not hit:
				for t in mon["types"]:
					if String(t).begins_with(q):
						hit = true
			if not hit and not str(mon["id"]) == q:
				continue
		out.append(character_id(name))
	return out
