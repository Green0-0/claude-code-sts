class_name PokeMoves
extends RefCounted

## Turns an imported move into a playable card definition.
##
## PokeAPI describes what a move does in structured "meta" fields — its damage
## class and power, the ailment it inflicts and how often, which stats it raises
## or lowers, how much it drains or heals, how many times it hits. Those fields
## are what this file reads; the English effect text is only ever used as flavour
## on the card, never parsed. The result is a normal CardLibrary definition, so
## every existing card mechanic (upgrades, exhaust, targeting) keeps working.
##
## Card ids are "mv_<move-name>", e.g. "mv_thunderbolt".

const ID_PREFIX := "mv_"

## Struggle has been typeless since Gen 4 — it is what a Pokemon does when
## nothing else will land, so it must never be stopped by an immunity. The type
## chart has no row for "typeless", so every matchup comes back neutral.
const TYPELESS := "typeless"
const TYPELESS_MOVES := ["struggle"]

## PokeAPI ailment name -> the status id Combat understands.
const AILMENTS := {
	"burn": "burn",
	"freeze": "freeze",
	"paralysis": "paralysis",
	"poison": "poison",
	"sleep": "sleep",
	"confusion": "confusion",
	"infatuation": "infatuation",
	"trap": "trapped",
	"leech-seed": "leech_seed",
	"nightmare": "nightmare",
	"yawn": "drowsy",
	"heal-block": "heal_block",
	"embargo": "embargo",
	"ingrain": "regen",
	"perish-song": "fading",
	"torment": "disable",
	"disable": "disable",
	"silence": "disable",
	"no-type-immunity": "identified",
	"tar-shot": "",          # handled as a Speed drop by its stat_changes
	"unknown": "",
	"none": "",
}

## How long an inflicted ailment lasts, in turns. The games use their own
## counters per ailment; these are Spire-sized stacks.
const AILMENT_STACKS := {
	"burn": 3, "poison": 3, "paralysis": 2, "sleep": 2, "freeze": 1,
	"confusion": 3, "infatuation": 2, "trapped": 4, "leech_seed": 3,
	"nightmare": 3, "drowsy": 1, "heal_block": 2, "embargo": 2,
	"disable": 2, "identified": 3, "regen": 3, "fading": 3,
}

## Moves whose power is computed rather than printed, so PokeAPI reports it as
## null. The formula name is resolved by Combat._variable_power against live
## combat state — Low Kick reads the target's weight, Gyro Ball the Speed gap,
## Flail the user's remaining HP.
const VARIABLE_POWER := {
	"low-kick": "target_weight", "grass-knot": "target_weight",
	"heavy-slam": "weight_ratio", "heat-crash": "weight_ratio",
	"electro-ball": "speed_ratio", "gyro-ball": "inverse_speed",
	"flail": "low_hp", "reversal": "low_hp",
	"crush-grip": "target_hp", "wring-out": "target_hp",
	"return": "friendship_high", "frustration": "friendship_low",
	"punishment": "target_stages", "magnitude": "random_quake",
	"counter": "counter_physical", "mirror-coat": "counter_special",
	"metal-burst": "counter_any",
}

## Moves that deal a set amount outright, ignoring Attack and Defense. Type
## immunities still apply — Night Shade does nothing to a Normal type.
const FIXED_DAMAGE := {
	"dragon-rage": "flat_40", "sonic-boom": "flat_20",
	"seismic-toss": "user_level", "night-shade": "user_level",
	"psywave": "psywave", "super-fang": "half_target_hp",
	"natures-madness": "half_target_hp", "ruination": "half_target_hp",
	"endeavor": "match_user_hp", "final-gambit": "user_hp",
	"guillotine": "ohko", "horn-drill": "ohko", "fissure": "ohko",
	"sheer-cold": "ohko",
}

static var _cache: Dictionary = {}       ## card id -> definition
static var _id_to_index: Dictionary = {} ## card id -> move index


static func card_id(move_name: String) -> String:
	return ID_PREFIX + move_name.replace("-", "_")


static func is_move_card(id: String) -> bool:
	return id.begins_with(ID_PREFIX)


static func move_for_card(id: String) -> Dictionary:
	_build_index()
	var idx: int = int(_id_to_index.get(id, -1))
	return PokeData.move_at(idx) if idx >= 0 else {}


static func _build_index() -> void:
	if not _id_to_index.is_empty():
		return
	var list := PokeData.moves()
	for i in range(list.size()):
		_id_to_index[card_id(String(list[i]["name"]))] = i


## True when a built card actually attacks, including the computed-power moves
## whose printed power is zero.
static func deals_damage(d: Dictionary) -> bool:
	for eff in d.get("effects", []):
		if String(eff.get("op", "")) == "poke_damage":
			return true
	return false


## The move to fall back on when a species has nothing else this engine can
## express. Struggle is the canonical answer; Tackle covers a missing import.
static func fallback_move() -> Dictionary:
	for name in ["struggle", "tackle", "pound", "scratch"]:
		var mv := PokeData.move(name)
		if mv.is_empty():
			continue
		if not get_def(card_id(name)).get("effects", []).is_empty():
			return mv
	return {}


## Card ids for every move in the game, used to seed reward pools.
static func all_card_ids() -> Array:
	_build_index()
	var out: Array = _id_to_index.keys()
	out.sort()
	return out


# ═══════════════════════════════ Definitions ═════════════════════════════════
static func get_def(id: String) -> Dictionary:
	if _cache.has(id):
		return _cache[id]
	var mv := move_for_card(id)
	if mv.is_empty():
		return {}
	var d := _build_def(id, mv)
	_cache[id] = d
	return d


static func _build_def(id: String, mv: Dictionary) -> Dictionary:
	var power := int(mv.get("power", 0))
	var cls := String(mv.get("class", "status"))
	var mtype := String(mv.get("type", "normal"))
	if TYPELESS_MOVES.has(String(mv["name"])):
		mtype = TYPELESS
	var ctype := PokeBalance.card_type(mv)
	var target := _target_kind(mv)

	var params := {"pw": power}
	var effects: Array = []
	var lines: Array = []
	_emit_damage(mv, params, effects, lines)
	_emit_ailment(mv, params, effects, lines)
	_emit_stages(mv, params, effects, lines)
	_emit_flinch(mv, params, effects, lines)
	_emit_healing(mv, params, effects, lines)

	if effects.is_empty():
		# A handful of moves (Transform, Metronome, field weather) have no
		# mechanical fields we model. They still read as a card and cost energy;
		# the imported description tells the player what it is meant to do.
		lines.append(_flavour(mv))

	var flags: Array = []
	# A move with no PP to speak of is a one-shot in a deck-builder.
	if power >= 140 or int(mv.get("pp", 10)) <= 5:
		flags.append("exhaust")

	var d := {
		"name": PokeData.display_name(String(mv["name"])),
		"type": ctype,
		# Rarity off the move's own strength. How a given species learns it can
		# raise this — see PokeCharacters.rarity_for, which is what the reward
		# pool and the shop actually price against.
		"rarity": PokeBalance.card_rarity(mv, 99, PokeData.LEARN_MACHINE),
		"color": "pokemon",
		"cost": PokeBalance.card_cost(mv),
		"target": target,
		"params": params,
		"text": " ".join(lines),
		"effects": effects,
		"flags": flags,
		# Marks this as a Pokemon card and carries what the damage formula needs.
		"poke": {
			"move": String(mv["name"]), "type": mtype, "class": cls,
			"acc": int(mv.get("acc", 0)), "prio": int(mv.get("prio", 0)),
			"category": String(mv.get("category", "")),
		},
		"up": _upgrade_for(mv, params),
	}
	return d


## Upgrading a move card sharpens it: more power, or a stronger effect.
static func _upgrade_for(mv: Dictionary, params: Dictionary) -> Dictionary:
	var up := {}
	var power := int(mv.get("power", 0))
	if power > 0:
		up["pw"] = int(round(power * 1.25))
	# Chance-based riders become reliable, which is the interesting upgrade for
	# a move whose damage is not the point.
	if params.has("chance") and int(params["chance"]) < 100:
		up["chance"] = min(100, int(round(int(params["chance"]) * 1.6)))
	if params.has("stage"):
		var s := int(params["stage"])
		up["stage"] = s + (1 if s > 0 else -1)
	if params.has("heal"):
		up["heal"] = int(round(int(params["heal"]) * 1.3))
	if up.is_empty():
		up["cost"] = max(0, PokeBalance.card_cost(mv) - 1)
	return up


static func _target_kind(mv: Dictionary) -> String:
	match String(mv.get("target", "selected-pokemon")):
		"all-opponents", "all-other-pokemon", "all-pokemon", "entire-field":
			return "all"
		"user", "users-field", "user-and-allies", "ally":
			return "self"
		"random-opponent":
			return "random"
	# A status move that only changes the user's own stats targets the user even
	# though the API calls it "selected-pokemon".
	if String(mv.get("class", "")) == "status":
		var changes: Array = mv.get("stat_changes", [])
		var all_positive := changes.size() > 0
		for c in changes:
			if int(c.get("change", 0)) < 0:
				all_positive = false
		if all_positive:
			return "self"
	return "enemy"


# ══════════════════════════════ Effect emitters ══════════════════════════════
static func _emit_damage(mv: Dictionary, params: Dictionary, effects: Array,
		lines: Array) -> void:
	var name := String(mv["name"])
	var power := int(mv.get("power", 0))
	var mtype := String(mv.get("type", "normal"))
	if TYPELESS_MOVES.has(name):
		mtype = TYPELESS
	var eff := {
		"op": "poke_damage", "power": "pw",
		"class": String(mv.get("class", "physical")),
		"mtype": mtype,
		"acc": int(mv.get("acc", 0)),
		"crit": int(mv.get("crit_rate", 0)),
	}
	if power <= 0:
		# A computed-power move still deals damage; its number just is not
		# printable until it is played.
		if FIXED_DAMAGE.has(name):
			eff["fixed"] = String(FIXED_DAMAGE[name])
			effects.append(eff)
			lines.append(_fixed_text(String(FIXED_DAMAGE[name])))
			return
		if VARIABLE_POWER.has(name):
			eff["formula"] = String(VARIABLE_POWER[name])
			effects.append(eff)
			lines.append("Deal {dmg} damage. %s" % _formula_text(String(VARIABLE_POWER[name])))
			return
		return
	var min_hits := int(mv.get("min_hits", 0))
	var max_hits := int(mv.get("max_hits", 0))
	if max_hits > 1:
		var low: int = max(1, min_hits)
		eff["min_hits"] = low
		eff["max_hits"] = max_hits
		if low == max_hits:
			lines.append("Deal {dmg} damage %s." % ("twice" if low == 2 else "%d times" % low))
		else:
			lines.append("Deal {dmg} damage %d-%d times." % [low, max_hits])
	else:
		lines.append("Deal {dmg} damage.")

	var drain := int(mv.get("drain", 0))
	if drain > 0:
		eff["drain"] = drain
		lines.append("Heal for %d%% of the damage dealt." % drain)
	elif drain < 0:
		eff["recoil"] = -drain
		lines.append("Take %d%% of the damage dealt as recoil." % -drain)
	if int(mv.get("crit_rate", 0)) > 0:
		lines.append("High critical-hit ratio.")
	effects.append(eff)


static func _emit_ailment(mv: Dictionary, params: Dictionary, effects: Array,
		lines: Array) -> void:
	var raw := String(mv.get("ailment", "none"))
	var sid := String(AILMENTS.get(raw, ""))
	if sid == "":
		return
	var chance := int(mv.get("ailment_chance", 0))
	if chance <= 0:
		chance = 100
	var stacks := int(AILMENT_STACKS.get(sid, 2))
	params["chance"] = chance
	params["stacks"] = stacks
	var to_self := sid in ["regen"]
	effects.append({
		"op": "poke_status", "id": sid, "stacks": "stacks", "chance": "chance",
		"target": "self" if to_self else "enemy",
	})
	var who := "yourself" if to_self else "the target"
	if chance >= 100:
		lines.append("Apply {stacks} %s to %s." % [Statuses.display_name(sid), who])
	else:
		lines.append("{chance}%% chance to apply {stacks} %s to %s."
				% [Statuses.display_name(sid), who])


static func _emit_stages(mv: Dictionary, params: Dictionary, effects: Array,
		lines: Array) -> void:
	var changes: Array = mv.get("stat_changes", [])
	if changes.is_empty():
		return
	var chance := int(mv.get("stat_chance", 0))
	if chance <= 0:
		chance = 100
	params["chance"] = chance
	# Raising your own stats or lowering the target's: the sign says which.
	for c in changes:
		var stat := String(c.get("stat", "atk"))
		var change := int(c.get("change", 0))
		if change == 0:
			continue
		var to_self := change > 0
		effects.append({
			"op": "poke_stage", "stat": stat, "change": change, "chance": "chance",
			"target": "self" if to_self else "enemy",
		})
		var word := "raise your" if to_self else "lower the target's"
		var text := _sentence("%s %s by %d." % [word, _stat_label(stat), absi(change)])
		if chance < 100:
			text = "{chance}%% chance to %s %s by %d." % [word, _stat_label(stat),
					absi(change)]
		lines.append(text)
	if changes.size() > 0 and not params.has("stage"):
		params["stage"] = int(changes[0].get("change", 1))


static func _emit_flinch(mv: Dictionary, params: Dictionary, effects: Array,
		lines: Array) -> void:
	var chance := int(mv.get("flinch_chance", 0))
	if chance <= 0:
		return
	params["flinch"] = chance
	effects.append({"op": "poke_status", "id": "flinch", "stacks": 1,
			"chance": "flinch", "target": "enemy"})
	lines.append("{flinch}% chance to make the target flinch.")


static func _emit_healing(mv: Dictionary, params: Dictionary, effects: Array,
		lines: Array) -> void:
	var healing := int(mv.get("healing", 0))
	if healing == 0:
		return
	params["heal"] = absi(healing)
	if healing > 0:
		effects.append({"op": "poke_heal", "percent": "heal", "target": "self"})
		lines.append("Heal {heal}% of your Max HP.")
	else:
		# Explosion and friends: the user pays with its own HP.
		effects.append({"op": "poke_recoil_self", "percent": "heal"})
		lines.append("Lose {heal}% of your Max HP.")


static func _fixed_text(kind: String) -> String:
	match kind:
		"flat_40": return "Deal exactly 40 damage."
		"flat_20": return "Deal exactly 20 damage."
		"user_level": return "Deal damage equal to your level."
		"psywave": return "Deal 50-150% of your level as damage."
		"half_target_hp": return "Halve the target's current HP."
		"match_user_hp": return "Cut the target down to your own HP."
		"user_hp": return "Deal damage equal to your current HP. You faint."
		"ohko": return "One-hit KO, if it lands."
	return "Deal a set amount of damage."


static func _formula_text(kind: String) -> String:
	match kind:
		"target_weight": return "Stronger against heavier targets."
		"weight_ratio": return "Stronger the heavier you are than the target."
		"speed_ratio": return "Stronger the faster you are than the target."
		"inverse_speed": return "Stronger the slower you are than the target."
		"low_hp": return "Stronger the less HP you have left."
		"target_hp": return "Stronger the more HP the target has left."
		"friendship_high": return "Powered by friendship."
		"friendship_low": return "Powered by spite."
		"target_stages": return "Stronger against a target that has buffed itself."
		"random_quake": return "Power varies wildly."
		"counter_physical": return "Returns double the last physical hit you took."
		"counter_special": return "Returns double the last special hit you took."
		"counter_any": return "Returns 1.5x the last hit you took."
	return ""


static func _flavour(mv: Dictionary) -> String:
	var text := String(mv.get("effect", "")).strip_edges()
	if text == "":
		return "Its effect is unlike anything else."
	if text.length() > 150:
		text = text.substr(0, 147) + "..."
	return text


## Uppercases the first letter only. String.capitalize() would Title Case The
## Whole Sentence, which is not what rules text wants.
static func _sentence(text: String) -> String:
	if text.is_empty():
		return text
	return text.substr(0, 1).to_upper() + text.substr(1)


static func _stat_label(stat: String) -> String:
	match stat:
		"atk": return "Attack"
		"df": return "Defense"
		"spa": return "Sp. Atk"
		"spd": return "Sp. Def"
		"spe": return "Speed"
		"accuracy": return "Accuracy"
		"evasion": return "Evasion"
	return stat.capitalize()


## The effect fields that hold a number and may therefore name a param. Fields
## outside this list are identifiers — "id": "flinch" names the status Flinch,
## and must not be swapped for params["flinch"], which is its chance.
const NUMERIC_FIELDS := ["power", "stacks", "chance", "percent", "times", "count",
		"min_hits", "max_hits", "crit", "acc", "drain", "recoil", "change"]

## Effects with every "params" reference resolved to its number.
##
## A card resolves names like "pw" against the card's own params at play time.
## An enemy has no card, so its moves need the numbers baked in.
static func literal_effects(d: Dictionary) -> Array:
	var params: Dictionary = d.get("params", {})
	var out: Array = []
	for eff in d.get("effects", []):
		var copy: Dictionary = (eff as Dictionary).duplicate(true)
		for key in NUMERIC_FIELDS:
			if not copy.has(key):
				continue
			var v = copy[key]
			if typeof(v) == TYPE_STRING and params.has(String(v)):
				copy[key] = params[String(v)]
		out.append(copy)
	return out


# ═══════════════════════════ Numbers shown on the card ═══════════════════════
## Cards print live numbers, so a move's damage has to be recomputed against
## whoever is holding it and whatever it is pointed at.
static func display_params(c: Card, combat) -> Dictionary:
	var p := c.raw_params()
	var d := c.def()
	var poke: Dictionary = d.get("poke", {})
	if poke.is_empty() or not p.has("pw"):
		return p
	var cls := String(poke.get("class", "physical"))
	var mtype := String(poke.get("type", "normal"))
	var power := int(p.get("pw", 0))

	if combat == null:
		p["dmg"] = PokeBalance.base_damage(power, 80, PokeBalance.NEUTRAL_DEFENSE)
		return p
	var source = combat.player
	var target = combat.preview_target()

	# Low Kick and Gyro Ball have no printed power, so the card has to ask what
	# it would come to against whoever is currently in front of it.
	var damage_eff := _damage_effect(c)
	if damage_eff.has("fixed"):
		p["dmg"] = combat._fixed_damage(String(damage_eff["fixed"]), mtype, source, target)
		return p
	if damage_eff.has("formula"):
		power = combat._variable_power(String(damage_eff["formula"]), source, target)
	if power <= 0:
		p["dmg"] = 0
		return p
	p["dmg"] = combat.calc_poke_damage(power, cls, mtype, source, target, 1.0)
	return p


static func _damage_effect(c: Card) -> Dictionary:
	for eff in c.effects():
		if String(eff.get("op", "")) == "poke_damage":
			return eff
	return {}


## The type-effectiveness note shown under a card when a target is selected.
static func matchup_note(c: Card, combat) -> String:
	var poke: Dictionary = c.def().get("poke", {})
	if poke.is_empty() or combat == null:
		return ""
	if int(c.raw_params().get("pw", 0)) <= 0:
		return ""
	var target = combat.preview_target()
	if target == null or target.poke_types.is_empty():
		return ""
	var mult := PokeData.effectiveness(String(poke.get("type", "normal")), target.poke_types)
	return PokeData.effectiveness_text(mult)
