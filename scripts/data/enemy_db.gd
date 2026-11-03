class_name EnemyDB
extends RefCounted
## Enemy definitions. `ai` selects a behaviour in enemy.gd.
## Numbers are floor-1 values; enemies scale up on deeper floors.

const ENEMIES := {
	"skeleton": {"name": "Skeleton", "sprite": "skeleton", "fw": 20, "fh": 28, "hp": 24.0, "speed": 52.0,
		"dmg": 12.0, "ai": "melee", "radius": 6.0, "xp": 3, "gold": [0, 2], "cost": 2, "gore": "bone"},
	"skel_archer": {"name": "Skeleton Archer", "sprite": "skel_archer", "fw": 20, "fh": 28, "hp": 16.0, "speed": 44.0,
		"dmg": 10.0, "ai": "archer", "radius": 6.0, "xp": 3, "gold": [0, 2], "cost": 2, "gore": "bone"},
	"bat": {"name": "Crypt Bat", "sprite": "bat", "fw": 19, "fh": 14, "hp": 8.0, "speed": 100.0,
		"dmg": 8.0, "ai": "bat", "radius": 5.0, "xp": 1, "gold": [0, 1], "cost": 1, "gore": "blood", "fly": 12.0},
	"ghoul": {"name": "Ghoul", "sprite": "ghoul", "fw": 24, "fh": 24, "hp": 36.0, "speed": 64.0,
		"dmg": 15.0, "ai": "charger", "radius": 7.0, "xp": 4, "gold": [1, 3], "cost": 3, "gore": "blood"},
	"cultist": {"name": "Cultist", "sprite": "cultist", "fw": 20, "fh": 28, "hp": 30.0, "speed": 40.0,
		"dmg": 11.0, "ai": "caster", "radius": 6.0, "xp": 5, "gold": [1, 4], "cost": 4, "gore": "blood"},
	"bloater": {"name": "Bloater", "sprite": "bloater", "fw": 25, "fh": 26, "hp": 44.0, "speed": 30.0,
		"dmg": 20.0, "ai": "bomber", "radius": 9.0, "xp": 4, "gold": [1, 3], "cost": 3, "gore": "rot"},
	"wraith": {"name": "Wraith", "sprite": "wraith", "fw": 22, "fh": 30, "hp": 30.0, "speed": 52.0,
		"dmg": 12.0, "ai": "wraith", "radius": 6.0, "xp": 5, "gold": [1, 3], "cost": 4, "gore": "ghost", "fly": 4.0},
	"imp": {"name": "Imp", "sprite": "imp", "fw": 18, "fh": 20, "hp": 22.0, "speed": 78.0,
		"dmg": 11.0, "ai": "imp", "radius": 5.0, "xp": 4, "gold": [1, 3], "cost": 3, "gore": "blood"},
	"brute": {"name": "Flayed Brute", "sprite": "brute", "fw": 30, "fh": 34, "hp": 105.0, "speed": 36.0,
		"dmg": 22.0, "ai": "brute", "radius": 10.0, "xp": 9, "gold": [2, 6], "cost": 6, "gore": "blood"},
}

## Which enemies appear on each floor.
const FLOOR_POOLS := [
	["skeleton", "skeleton", "skel_archer", "bat", "ghoul"],
	["skeleton", "skel_archer", "ghoul", "cultist", "bloater", "bat", "wraith"],
	["imp", "brute", "wraith", "cultist", "skel_archer", "ghoul", "bloater"],
]

const BOSSES := {
	"bone_warden": {"name": "The Bone Warden", "title": "Keeper of the Sunken Crypt", "sprite": "bone_warden",
		"fw": 46, "fh": 57, "hp": 850.0, "speed": 40.0, "dmg": 20.0, "radius": 14.0, "gore": "bone"},
	"mother_of_rot": {"name": "Mother of Rot", "title": "She Who Feeds the Deep", "sprite": "mother_of_rot",
		"fw": 58, "fh": 48, "hp": 1500.0, "speed": 18.0, "dmg": 24.0, "radius": 20.0, "gore": "rot"},
	"hollow_bishop": {"name": "The Hollow Bishop", "title": "Last Voice of a Dead God", "sprite": "hollow_bishop",
		"fw": 42, "fh": 58, "hp": 2300.0, "speed": 30.0, "dmg": 28.0, "radius": 13.0, "gore": "ghost", "fly": 6.0},
}

## Champions: Diablo-style named elites with a modifier.
const CHAMPION_MODS := {
	"Fanatic": {"color": Color("7d8fff"), "desc": "fast"},
	"Stoneskin": {"color": Color("a0a8b8"), "desc": "tough"},
	"Fire-Touched": {"color": Color("ff8040"), "desc": "explodes in fire"},
	"Hexed": {"color": Color("b070f0"), "desc": "curses on hurt"},
}
const CHAMPION_FIRST := ["Gorefang", "Bonesnap", "Ashmaw", "Rotgut", "Gravel", "Hollowjaw",
	"Bloodwick", "Grimtooth", "Marrow", "Wormtongue", "Blightclaw", "Duskhowl"]
const CHAMPION_EPITHET := ["the Hungry", "the Defiler", "the Unburied", "the Gaunt", "the Cruel",
	"the Damned", "the Weeping", "the Flayer", "the Pale", "Soulrender"]


static func scaled(id: String, floor_i: int) -> Dictionary:
	var d: Dictionary = ENEMIES[id].duplicate()
	var hp_mult := 1.0 + 0.7 * floor_i
	var dmg_mult := 1.2 + 0.35 * floor_i
	d["hp"] = d["hp"] * hp_mult
	d["dmg"] = d["dmg"] * dmg_mult
	d["id"] = id
	return d


static func champion_name() -> String:
	var r: RandomNumberGenerator = Game.rng
	return CHAMPION_FIRST[r.randi_range(0, CHAMPION_FIRST.size() - 1)] + " " + CHAMPION_EPITHET[r.randi_range(0, CHAMPION_EPITHET.size() - 1)]
