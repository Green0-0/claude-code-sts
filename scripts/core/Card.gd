class_name Card
extends RefCounted

## A concrete card instance living in a deck or in a combat pile.

var id: String = "strike"
var upgraded: bool = false
var upgrade_count: int = 0        ## Searing Blow can be upgraded repeatedly
var uid: int = 0                  ## unique per instance, used by the UI

## Per-combat mutable state
var cost_override: int = -99      ## -99 = none; set by Corruption / Infernal Blade
var free_this_turn: bool = false
var bonus_damage: int = 0         ## Rampage / Glass Knife
var in_combat_upgrade: bool = false

static var _next_uid: int = 1


static func create(card_id: String, is_upgraded: bool = false) -> Card:
	var c := Card.new()
	c.id = card_id
	c.upgraded = is_upgraded
	c.upgrade_count = 1 if is_upgraded else 0
	c.uid = _next_uid
	_next_uid += 1
	return c


func duplicate_card() -> Card:
	var c := Card.create(id, upgraded)
	c.upgrade_count = upgrade_count
	c.bonus_damage = bonus_damage
	return c


func def() -> Dictionary:
	return CardLibrary.get_def(id)


func display_name() -> String:
	var n: String = def()["name"]
	if upgrade_count > 1:
		return "%s+%d" % [n, upgrade_count]
	if upgraded:
		return n + "+"
	return n


func type() -> String:
	return def()["type"]


func color() -> String:
	return def()["color"]


func rarity() -> String:
	return def()["rarity"]


func target_kind() -> String:
	return def()["target"]


func flags() -> Array:
	var d := def()
	var f: Array = (d["flags"] as Array).duplicate() if d.has("flags") else []
	var up: Dictionary = d.get("up", {})
	if upgraded:
		if up.has("flags_add"):
			for x in up["flags_add"]:
				if not f.has(x):
					f.append(x)
		if up.has("no_exhaust"):
			f.erase("exhaust")
		if up.has("innate") and not f.has("innate"):
			f.append("innate")
	return f


func has_flag(flag: String) -> bool:
	return flags().has(flag)


func is_unplayable() -> bool:
	return has_flag("unplayable")


func can_upgrade() -> bool:
	if has_flag("no_upgrade"):
		return false
	if id == "searing_blow":
		return true
	return not upgraded


func upgrade() -> void:
	if not can_upgrade():
		return
	upgraded = true
	upgrade_count += 1


## Base energy cost. -1 means X-cost, -2 means unplayable.
func base_cost() -> int:
	var d := def()
	var c: int = d["cost"]
	if upgraded and (d.get("up", {}) as Dictionary).has("cost"):
		c = d["up"]["cost"]
	return c


## Cost after per-combat modifiers. combat may be null (out of combat display).
func cost(combat = null) -> int:
	var base := base_cost()
	if base == -2:
		return -2
	if free_this_turn:
		return 0
	if cost_override != -99:
		return max(0, cost_override)
	if combat != null:
		base = combat.modify_card_cost(self, base)
	return base


func is_x_cost() -> bool:
	return base_cost() == -1


## Numeric parameters after upgrade, before any combat scaling.
func raw_params() -> Dictionary:
	var d := def()
	var p: Dictionary = (d["params"] as Dictionary).duplicate(true)
	if upgraded:
		var up: Dictionary = d.get("up", {})
		for k in up:
			if k in ["cost", "flags_add", "no_exhaust", "innate", "plus", "choose",
					"target_all", "count"]:
				continue
			p[k] = up[k]
	# Searing Blow scales with each additional upgrade.
	if id == "searing_blow" and upgrade_count > 1:
		var n := upgrade_count
		p["dmg"] = 12 + int(n * (n + 7) / 2.0)
	return p


## Parameters with combat scaling (Strength, Dexterity, Weak, Frail, Vulnerable)
## applied so the card text shows the numbers the player will actually get.
func display_params(combat = null) -> Dictionary:
	var p := raw_params()
	if combat == null or combat.player == null:
		return p
	var pl = combat.player
	for key in p.keys():
		if typeof(p[key]) != TYPE_INT and typeof(p[key]) != TYPE_FLOAT:
			continue
		if key.begins_with("dmg"):
			var mult := 1
			if p.has("mult") and id == "heavy_blade":
				mult = int(p["mult"])
			var target = combat.preview_target()
			p[key] = combat.calc_attack_damage(int(p[key]), pl, target, self, mult)
		elif key.begins_with("blk"):
			p[key] = combat.calc_block(int(p[key]), pl)
	p = _dynamic_params(p, combat)
	return p


## Cards whose printed numbers depend on live combat state.
func _dynamic_params(p: Dictionary, combat) -> Dictionary:
	match id:
		"body_slam":
			var target = combat.preview_target()
			p["dmg"] = combat.calc_attack_damage(combat.player.block, combat.player, target, self, 1)
		"perfected_strike":
			var strikes := 0
			for c in Run.deck:
				if String(CardLibrary.get_def(c.id)["name"]).to_lower().contains("strike"):
					strikes += 1
			var per := int(raw_params()["per"])
			var target = combat.preview_target()
			p["dmg"] = combat.calc_attack_damage(int(raw_params()["dmg"]) + per * strikes,
					combat.player, target, self, 1)
		"rampage", "glass_knife":
			var target = combat.preview_target()
			p["dmg"] = combat.calc_attack_damage(int(raw_params()["dmg"]) + bonus_damage,
					combat.player, target, self, 1)
		"finisher":
			var n: int = combat.attacks_played_this_turn
			p["dmg"] = combat.calc_attack_damage(int(raw_params()["dmg"]) * n,
					combat.player, combat.preview_target(), self, 1)
		"flechettes":
			var n := 0
			for c in combat.hand:
				if c.type() == "skill":
					n += 1
			p["dmg"] = combat.calc_attack_damage(int(raw_params()["dmg"]) * n,
					combat.player, combat.preview_target(), self, 1)
		"fiend_fire":
			p["dmg"] = combat.calc_attack_damage(int(raw_params()["dmg"]),
					combat.player, combat.preview_target(), self, 1)
		"shiv":
			var acc: int = combat.player.get_status("accuracy")
			p["dmg"] = combat.calc_attack_damage(int(raw_params()["dmg"]) + acc,
					combat.player, combat.preview_target(), self, 1)
	return p


func rules_text(combat = null) -> String:
	var d := def()
	var txt: String = d["text"]
	var p := display_params(combat)
	for k in p:
		txt = txt.replace("{" + String(k) + "}", str(p[k]))
	var extra: Array = []
	var f := flags()
	if f.has("innate") and not txt.contains("Innate"):
		extra.append("Innate.")
	if f.has("ethereal") and not txt.contains("Ethereal"):
		extra.append("Ethereal.")
	if f.has("retain") and not txt.contains("Retain"):
		extra.append("Retain.")
	if f.has("exhaust") and not txt.contains("Exhaust"):
		extra.append("Exhaust.")
	if extra.size() > 0:
		txt = " ".join(extra) + " " + txt
	return _pluralize(txt)


static var _plural_re: RegEx = null

## Turns "Draw 1 card(s)" into "Draw 1 card" and "Draw 3 card(s)" into
## "Draw 3 cards", so the printed rules read naturally at every value.
static func _pluralize(text: String) -> String:
	if not text.contains("(s)"):
		return text
	if _plural_re == null:
		_plural_re = RegEx.new()
		_plural_re.compile("(-?\\d+) ([A-Za-z]+)\\(s\\)")
	var out := text
	var matches := _plural_re.search_all(out)
	# Walk backwards so earlier match offsets stay valid as we substitute.
	for i in range(matches.size() - 1, -1, -1):
		var m := matches[i]
		var count := int(m.get_string(1))
		var word := m.get_string(2)
		var replacement := "%d %s" % [count, word]
		if absi(count) != 1:
			replacement = "%d %s" % [count, "copies" if word == "copy" else word + "s"]
		out = out.substr(0, m.get_start()) + replacement + out.substr(m.get_end())
	return out.replace("(s)", "s")


func needs_target() -> bool:
	return target_kind() == "enemy" and not _upgraded_targets_all()


func _upgraded_targets_all() -> bool:
	return upgraded and (def().get("up", {}) as Dictionary).has("target_all")


func effective_target_kind() -> String:
	if _upgraded_targets_all():
		return "all"
	return target_kind()


func effects() -> Array:
	var d := def()
	if upgraded and (d.get("up", {}) as Dictionary).has("effects"):
		return d["up"]["effects"]
	return d.get("effects", [])
