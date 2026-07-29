class_name PokeMobs
extends RefCounted

## Builds an EnemyLibrary-shaped definition for any Pokemon, and drives its AI.
##
## Enemy ids are "pkm_<name>" with an optional role suffix:
##   pkm_pikachu         a normal encounter
##   pkm_pikachu_elite   the same species as an elite: tougher, more moves
##   pkm_pikachu_boss    as an act boss
##
## Its moveset comes from its real learnset — the highest-level moves it knows
## that this engine can actually express — so a Gyarados opens with Waterfall
## and a Gengar reaches for Shadow Ball.

const ID_PREFIX := "pkm_"
const ROLE_SUFFIX := {"_elite": "elite", "_boss": "boss"}

## How many moves an enemy gets. More for the fights that need to stay
## interesting for longer.
const MOVE_COUNT := {"normal": 4, "elite": 5, "boss": 6}

## A mob knows what its level says it knows — no more. This is why an Act 1
## Deerling cannot open with the level-40 Double-Edge it eventually learns, and
## why the same species met again in Act 4 is genuinely more dangerous rather
## than simply having more HP.

static var _cache: Dictionary = {}


static func enemy_id(mon_name: String, role: String = "normal") -> String:
	var id := ID_PREFIX + mon_name.replace("-", "_")
	if role == "elite":
		return id + "_elite"
	if role == "boss":
		return id + "_boss"
	return id


static func is_mob(id: String) -> bool:
	return id.begins_with(ID_PREFIX)


## Splits "pkm_pikachu_elite" back into its species and role.
static func split_id(id: String) -> Dictionary:
	if not is_mob(id):
		return {}
	var body := id.substr(ID_PREFIX.length())
	var role := "normal"
	for suffix in ROLE_SUFFIX:
		if body.ends_with(suffix):
			role = String(ROLE_SUFFIX[suffix])
			body = body.substr(0, body.length() - suffix.length())
			break
	return {"name": body.replace("_", "-"), "role": role}


static func mon_for(id: String) -> Dictionary:
	var parts := split_id(id)
	if parts.is_empty():
		return {}
	return PokeData.mon(String(parts["name"]))


# ═══════════════════════════════ Definitions ═════════════════════════════════
## The level a mob of this role spawns at, from how far into the run it is.
static func _level_for(role: String) -> int:
	if Engine.get_main_loop() != null and Run != null and Run.is_pokemon_run():
		return Run.level_for_role(role)
	# Outside a run — menus, the dex picker, tests — the dungeon has not started
	# climbing yet, but an elite is still an elite.
	return PokeLevels.role_level(PokeLevels.START_LEVEL, role)


static func get_def(id: String) -> Dictionary:
	# Definitions depend on the dungeon's current level, so the cache is keyed by
	# it too — otherwise the first Rattata you meet would fix that species'
	# numbers for the rest of the run.
	var parts := split_id(id)
	if parts.is_empty():
		return {}
	var key := "%s@%d" % [id, _level_for(String(parts["role"]))]
	if _cache.has(key):
		return _cache[key]
	var mon := PokeData.mon(String(parts["name"]))
	if mon.is_empty():
		return {}
	var d := _build_def(mon, String(parts["role"]))
	_cache[key] = d
	return d


static func _build_def(mon: Dictionary, role: String) -> Dictionary:
	# The level the dungeon is currently fighting at. Definitions are rebuilt
	# whenever it moves — see get_def — so an Act 1 Rattata and an Act 4 Rattata
	# really are different animals.
	var level := _level_for(role)
	var hp := PokeBalance.mob_hp(mon, level)
	var scaled := int(round(hp * PokeBalance.role_hp_multiplier(role)))
	var moves := _moveset(mon, role, level)
	var d := {
		"name": PokeData.display_name(String(mon["name"])),
		# A small spread so two of the same species are not identical.
		"hp": [max(4, int(round(scaled * 0.92))), max(5, int(round(scaled * 1.08)))],
		"moves": moves,
		"poke": String(mon["name"]),
		"role": role,
		"level": level,
	}
	if role == "boss":
		d["boss"] = true
	return d


## Picks the moves this species fights with.
##
## Level-up moves come first and highest-level-first, since those are the ones a
## wild Pokemon of that species would actually know. Only moves this engine can
## express are eligible, and the set is forced to contain at least one attack so
## no encounter can stall.
static func _moveset(mon: Dictionary, role: String, cap: int) -> Dictionary:
	var want := int(MOVE_COUNT.get(role, 4))

	var attacks: Array = []
	var others: Array = []
	_collect(mon, true, cap, attacks, others)
	# An encounter with no way to deal damage can never be won, so a species
	# with nothing to hit with at this level reaches further up its own level-up
	# list, then into what it can be taught. Metapod really does learn nothing
	# but Harden, and Ditto nothing but Transform: those end on Struggle.
	if attacks.is_empty():
		_collect(mon, true, 0, attacks, others)
	if attacks.is_empty():
		_collect(mon, false, 0, attacks, others)
	if attacks.is_empty():
		var last_resort := PokeMoves.fallback_move()
		if not last_resort.is_empty():
			attacks.append(last_resort)

	# Roughly three attacks to one utility move keeps fights aggressive but
	# leaves room for a Growl or a Swords Dance to matter.
	var chosen: Array = []
	var want_utility: int = clampi(want / 3, 1, 2)
	for mv in attacks:
		if chosen.size() >= want - want_utility:
			break
		chosen.append(mv)
	for mv in others:
		if chosen.size() >= want:
			break
		chosen.append(mv)
	for mv in attacks:
		if chosen.size() >= want:
			break
		if not chosen.has(mv):
			chosen.append(mv)

	if chosen.is_empty():
		var last_resort := PokeMoves.fallback_move()
		if not last_resort.is_empty():
			chosen.append(last_resort)

	var out := {}
	for mv in chosen:
		_add_move(out, mv)
	# Every Pokemon can Struggle, and it is typeless, so a mob whose whole
	# moveset is walled by an immunity still has something to do. The AI only
	# reaches for it when nothing else can land.
	var struggle := PokeData.move("struggle")
	if not struggle.is_empty():
		_add_move(out, struggle)
	return out


static func _add_move(out: Dictionary, mv: Dictionary) -> void:
	var card := PokeMoves.get_def(PokeMoves.card_id(String(mv["name"])))
	if card.is_empty():
		return
	out[PokeData.display_name(String(mv["name"]))] = {
		"intent": _intent_for(card),
		"effects": PokeMoves.literal_effects(card),
		"power": int(mv.get("power", 0)),
		"mtype": String(card.get("poke", {}).get("type", mv.get("type", "normal"))),
		"class": String(mv.get("class", "status")),
	}


## Sorts a species' learnable moves into attacks and utility, highest-level
## first. level_only restricts it to moves learnt by levelling up; a non-zero
## cap drops moves it would not know yet at that level.
static func _collect(mon: Dictionary, level_only: bool, cap: int, attacks: Array,
		others: Array) -> void:
	attacks.clear()
	others.clear()
	var rows: Array = []
	for row in mon.get("learnset", []):
		if level_only and int(row[2]) != PokeData.LEARN_LEVEL:
			continue
		if cap > 0 and int(row[1]) > cap:
			continue
		rows.append(row)
	rows.sort_custom(func(a, b): return int(a[1]) > int(b[1]))
	for row in rows:
		var mv := PokeData.move_at(int(row[0]))
		if mv.is_empty():
			continue
		var d := PokeMoves.get_def(PokeMoves.card_id(String(mv["name"])))
		if d.is_empty() or (d["effects"] as Array).is_empty():
			continue
		if int(mv.get("power", 0)) > 0 or PokeMoves.deals_damage(d):
			attacks.append(mv)
		else:
			others.append(mv)


## Which intent icon to telegraph, read off what the move actually does.
static func _intent_for(card: Dictionary) -> String:
	var damages := false
	var debuffs := false
	var buffs := false
	var heals := false
	for eff in card.get("effects", []):
		match String(eff.get("op", "")):
			"poke_damage":
				damages = true
			"poke_status":
				debuffs = true
			"poke_stage":
				if String(eff.get("target", "")) == "self":
					buffs = true
				else:
					debuffs = true
			"poke_heal":
				heals = true
	if damages and debuffs:
		return "attack_debuff"
	if damages and buffs:
		return "attack_buff"
	if damages:
		return "attack"
	if heals:
		return "defend"
	if buffs:
		return "buff"
	if debuffs:
		return "debuff"
	return "unknown"


# ══════════════════════════════════ Spawning ═════════════════════════════════
## Attaches the species' stats and types to a freshly spawned Actor, which is
## what every Pokemon rule in Combat keys off.
static func decorate(a: Actor, id: String) -> void:
	var mon := mon_for(id)
	if mon.is_empty():
		return
	var d := get_def(id)
	a.poke_name = String(mon["name"])
	a.poke_stats = mon["stats"]
	a.poke_types = mon["types"]
	a.level = int(d.get("level", PokeLevels.START_LEVEL))
	a.name = "%s Lv%d" % [String(d["name"]), a.level]


# ════════════════════════════════════ AI ═════════════════════════════════════
## Pick a move. The heuristic is deliberately simple and readable: hit hard,
## hit for super-effective damage when you can, set up occasionally, and never
## grind the same button three times in a row.
static func choose_move(a: Actor, combat) -> String:
	var moves: Dictionary = get_def(a.enemy_id).get("moves", {})
	if moves.is_empty():
		return ""
	var names: Array = moves.keys()
	var rng: RandomNumberGenerator = combat.rng
	var target: Actor = combat.player

	var best := ""
	var best_score := -1.0
	for name in names:
		var mv: Dictionary = moves[name]
		var score := _score(a, mv, target, combat)
		# Repeating a move is allowed, but it has to be clearly the right call.
		if EnemyLibrary._repeated(a, String(name), 2):
			score *= 0.35
		elif EnemyLibrary._last(a) == String(name):
			score *= 0.8
		# A little noise so the same species does not play identically every run.
		score *= 1.0 + rng.randf() * 0.25
		if score > best_score:
			best_score = score
			best = String(name)
	return best if best != "" else String(names[0])


static func _score(a: Actor, mv: Dictionary, target: Actor, combat) -> float:
	var power := int(mv.get("power", 0))
	# Struggle hurts the user, so it is strictly a last resort: scored just above
	# nothing, so any move that can actually land beats it.
	if String(mv.get("mtype", "")) == PokeMoves.TYPELESS:
		return 0.2
	if power > 0:
		var dmg: int = combat.calc_poke_damage(power, String(mv.get("class", "physical")),
				String(mv.get("mtype", "normal")), a, target, 1.0)
		# Finishing blow: take it.
		if target != null and dmg >= target.hp + target.block:
			return 1000.0
		return float(dmg)

	# Utility moves are worth about as much as a mid-sized attack, but only
	# while they still do something.
	var value := 8.0
	for eff in mv.get("effects", []):
		match String(eff.get("op", "")):
			"poke_status":
				var sid := String(eff.get("id", ""))
				# No point re-applying an ailment that is already stuck on.
				if target != null and target.has_status(sid):
					value -= 6.0
			"poke_stage":
				var stat := String(eff.get("stat", "atk"))
				if String(eff.get("target", "")) == "self":
					if absi(a.stage(stat)) >= PokeBalance.MAX_STAGE:
						value -= 6.0
				elif target != null and absi(target.stage(stat)) >= PokeBalance.MAX_STAGE:
					value -= 6.0
			"poke_heal":
				# Healing is worth a lot when hurt and nothing when healthy.
				value += 14.0 * (1.0 - a.hp_ratio())
	return maxf(0.5, value)
