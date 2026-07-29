class_name PartyMember
extends RefCounted

## One Pokemon on the player's side, between fights.
##
## Everything that used to be a single value on RunState — the species, its
## level, its experience, its HP and its deck — belongs to a member now. A run
## with one member behaves exactly as it did; RunState proxies the old names
## through to the lead so nothing else had to change all at once.

var character_id: String = ""      ## "pkc_pikachu"
var level: int = PokeLevels.START_LEVEL
var xp: int = 0
var hp: int = 1
var max_hp: int = 1
var deck: Array = []               ## Array[Card]

## Set when this one was caught rather than started with, purely for flavour on
## the party screen.
var caught: bool = false


static func create(id: String, at_level: int = PokeLevels.START_LEVEL,
		party_size: int = 1) -> PartyMember:
	var m := PartyMember.new()
	m.character_id = id
	m.level = at_level
	m.xp = PokeLevels.xp_for_level(m.growth(), at_level)
	m.max_hp = PokeBalance.player_hp(m.mon(), at_level, party_size)
	m.hp = m.max_hp
	for card_id in CardLibrary.starter_deck(id):
		m.deck.append(Card.create(card_id))
	return m


func mon() -> Dictionary:
	return PokeCharacters.mon_for(character_id)


func growth() -> String:
	var d := mon()
	return String(d.get("growth", "medium")) if not d.is_empty() else "medium"


func species_name() -> String:
	var d := mon()
	return String(d["name"]) if not d.is_empty() else character_id


func display_name() -> String:
	var d := mon()
	return PokeData.display_name(String(d["name"])) if not d.is_empty() else character_id


func is_alive() -> bool:
	return hp > 0


func hp_ratio() -> float:
	return 0.0 if max_hp <= 0 else clampf(float(hp) / float(max_hp), 0.0, 1.0)


## Recomputes Max HP for the current species and level, keeping the same
## proportion of health. Used after levelling and after evolving.
func restat(heal_by_gain: bool = true, party_size: int = 1) -> void:
	var before := max_hp
	var ratio := hp_ratio()
	max_hp = PokeBalance.player_hp(mon(), level, party_size)
	# When the party grows the counterweight shrinks, so Max HP can go *down*.
	# Keep the same proportion of health rather than the same number, or gaining
	# a team-mate would look like taking damage.
	if max_hp < before:
		hp = clampi(int(round(max_hp * ratio)), 1, max_hp)
		return
	if heal_by_gain:
		hp = min(max_hp, hp + max(0, max_hp - before))
	else:
		hp = clampi(hp, 1, max_hp)


## How big the party is, kept up to date by RunState. A member needs it to
## restat, because the HP counterweight depends on how many of you there are.
var party_size_hint: int = 1


## Grants experience and applies level-ups. Returns levels gained.
func award_xp(amount: int) -> int:
	if amount <= 0 or not is_alive():
		return 0
	xp += amount
	var was := level
	level = PokeLevels.level_for_xp(growth(), xp)
	if level <= was:
		return 0
	restat(true, party_size_hint)
	return level - was


## Evolution branches this member could take right now.
func evolutions() -> Array:
	return PokeEvolution.available(species_name(), level)


## Becomes the species it evolves into. The deck comes along untouched — they
## are moves, and the evolved form knows them.
func evolve_into(species: String) -> bool:
	var target := PokeData.mon(species)
	if target.is_empty():
		return false
	var ratio := hp_ratio()
	character_id = PokeCharacters.character_id(species)
	max_hp = PokeBalance.player_hp(target, level, party_size_hint)
	# Evolving is a reward, so it tops you up as well as growing the pool.
	hp = clampi(int(round(max_hp * maxf(ratio, 0.5))), 1, max_hp)
	PokeCharacters.forget(character_id)
	return true


func to_dict() -> Dictionary:
	var cards: Array = []
	for c in deck:
		cards.append({"id": c.id, "up": c.upgrade_count})
	return {"id": character_id, "level": level, "xp": xp, "hp": hp,
			"max_hp": max_hp, "deck": cards, "caught": caught}


static func from_dict(d: Dictionary) -> PartyMember:
	var m := PartyMember.new()
	m.character_id = String(d.get("id", ""))
	m.level = int(d.get("level", PokeLevels.START_LEVEL))
	m.xp = int(d.get("xp", 0))
	m.max_hp = int(d.get("max_hp", 1))
	m.hp = int(d.get("hp", m.max_hp))
	m.caught = bool(d.get("caught", false))
	for entry in d.get("deck", []):
		var c := Card.create(String(entry["id"]), int(entry.get("up", 0)) > 0)
		c.upgrade_count = int(entry.get("up", 0))
		m.deck.append(c)
	return m
