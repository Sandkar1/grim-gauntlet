class_name ItemDB
extends RefCounted
## Item definitions and the random loot generator.
##
## Items are plain Dictionaries so they are easy to inspect, save and tweak:
##   slot, name, base, rarity, cursed, curse, icon, level, stats{},
##   weapon/dmg (weapons only), rite, souls, souls_needed, awakened, flavor, value
##
## THE TWIST - "Soulbound gear":
##   Every non-common item carries a dormant Rite. Each kill feeds souls to all
##   your equipped items; when an item has drunk enough it AWAKENS and its Rite
##   becomes active. Cursed items roll stronger stats but carry a drawback,
##   which is lifted forever once the item awakens.

enum { COMMON, MAGIC, RARE, UNIQUE }

const RARITY_NAMES := ["Common", "Magic", "Rare", "Unique"]
const RARITY_COLORS := [Color("d8d2c4"), Color("7d8fff"), Color("f2d65a"), Color("e09a3e")]
const CURSED_COLOR := Color("e0403a")
const SOULS_NEEDED := [0, 22, 32, 45]
const CURSE_POWER := 1.4

const WEAPONS := {
	"crossbow": {"name": "Crossbow", "damage": 10.0, "rate": 2.4, "speed": 410.0, "spread": 2.0, "count": 1,
		"pierce": 0, "proj": "bolt", "sfx": "shoot_bolt", "life": 0.9, "size": 4.0, "knock": 60.0},
	"repeater": {"name": "Repeater", "damage": 4.6, "rate": 6.5, "speed": 370.0, "spread": 9.0, "count": 1,
		"pierce": 0, "proj": "bolt", "sfx": "shoot_bolt", "life": 0.8, "size": 3.0, "knock": 25.0},
	"blunderbuss": {"name": "Blunderbuss", "damage": 4.4, "rate": 1.25, "speed": 330.0, "spread": 32.0, "count": 6,
		"pierce": 0, "proj": "pellet", "sfx": "shoot_cannon", "life": 0.45, "size": 3.0, "knock": 85.0, "speed_var": 0.25},
	"staff": {"name": "Staff", "damage": 15.0, "rate": 1.5, "speed": 230.0, "spread": 0.0, "count": 1,
		"pierce": 0, "proj": "fireball", "sfx": "shoot_magic", "life": 1.4, "size": 6.0, "explode": 26.0, "knock": 40.0},
	"wand": {"name": "Wand", "damage": 6.2, "rate": 3.2, "speed": 215.0, "spread": 10.0, "count": 1,
		"pierce": 0, "proj": "skull", "sfx": "shoot_wand", "life": 1.6, "size": 4.0, "homing": 4.0, "knock": 20.0},
	"axe": {"name": "Throwing Axes", "damage": 12.5, "rate": 1.8, "speed": 290.0, "spread": 3.0, "count": 1,
		"pierce": 2, "proj": "axe", "sfx": "shoot_axe", "life": 0.85, "size": 5.0, "knock": 70.0, "decel": 0.7},
}

const WEAPON_NAMES := {
	"crossbow": ["Light Crossbow", "Heavy Crossbow", "Arbalest"],
	"repeater": ["Repeater", "Siege Repeater", "Hellfire Repeater"],
	"blunderbuss": ["Blunderbuss", "Hand Cannon", "Dragon's Maw"],
	"staff": ["Ember Staff", "Pyre Staff", "Hellbrand Staff"],
	"wand": ["Bone Wand", "Grave Wand", "Lich Wand"],
	"axe": ["Hatchets", "Bearded Axes", "Executioner Axes"],
}

## Armor bases: implicit stat value = a + b * (level - 1)
const BASES := {
	"helm": {"names": ["Rusted Cap", "Iron Helm", "Grim Visage"], "icon": "helm",
		"implicit": {"armor": [3.0, 2.0], "max_hp": [6.0, 5.0]}},
	"armor": {"names": ["Tattered Hauberk", "Ring Mail", "Ossuary Plate"], "icon": "armor",
		"implicit": {"armor": [6.0, 4.0], "max_hp": [10.0, 8.0]}},
	"gloves": {"names": ["Leather Wraps", "Iron Gauntlets", "Flayed Grips"], "icon": "gloves",
		"implicit": {"attack_speed_pct": [0.06, 0.03]}},
	"boots": {"names": ["Worn Boots", "Iron Greaves", "Ashen Treads"], "icon": "boots",
		"implicit": {"move_speed": [6.0, 3.0]}},
	"amulet": {"names": ["Bone Charm", "Grave Amulet", "Seraph Locket"], "icon": "amulet",
		"implicit": {"damage_pct": [0.08, 0.04]}},
	"ring": {"names": ["Copper Band", "Signet", "Blackened Ring"], "icon": "ring",
		"implicit": {"crit_chance": [0.03, 0.015]}},
}

## Random affixes. Value = (base + per * (level-1)) * random(0.8 .. 1.2)
const AFFIXES := [
	{"stat": "damage_pct", "word": "Cruel", "pre": true, "base": 0.08, "per": 0.04},
	{"stat": "attack_speed_pct", "word": "Swift", "pre": true, "base": 0.07, "per": 0.03},
	{"stat": "crit_chance", "word": "Keen", "pre": true, "base": 0.04, "per": 0.015},
	{"stat": "max_hp", "word": "Stalwart", "pre": true, "base": 12.0, "per": 8.0},
	{"stat": "armor", "word": "Iron-bound", "pre": true, "base": 5.0, "per": 3.0},
	{"stat": "proj_speed_pct", "word": "Hurling", "pre": true, "base": 0.12, "per": 0.04},
	{"stat": "area_pct", "word": "Blasting", "pre": true, "base": 0.12, "per": 0.05},
	{"stat": "skill_pct", "word": "Arcane", "pre": true, "base": 0.15, "per": 0.07},
	{"stat": "life_on_kill", "word": "of the Leech", "pre": false, "base": 1.0, "per": 0.5},
	{"stat": "move_speed", "word": "of Haste", "pre": false, "base": 6.0, "per": 2.0},
	{"stat": "mana_regen", "word": "of the Mind", "pre": false, "base": 1.5, "per": 0.7},
	{"stat": "gold_find", "word": "of Greed", "pre": false, "base": 0.25, "per": 0.1},
	{"stat": "soul_gain", "word": "of Souls", "pre": false, "base": 0.2, "per": 0.08},
	{"stat": "life_regen", "word": "of Mending", "pre": false, "base": 0.6, "per": 0.4},
	{"stat": "dodge_cd_pct", "word": "of Evasion", "pre": false, "base": 0.12, "per": 0.05},
	{"stat": "crit_mult", "word": "of Slaughter", "pre": false, "base": 0.2, "per": 0.1},
	{"stat": "flask_heal", "word": "of the Vial", "pre": false, "base": 0.08, "per": 0.03},
]

const RARE_FIRST := ["Grim", "Blood", "Doom", "Bone", "Ash", "Gloom", "Rot", "Soul", "Dread",
	"Hate", "Wraith", "Corpse", "Plague", "Storm", "Night", "Grave", "Wyrm", "Hollow"]
const RARE_SECOND := {
	"weapon": ["Bite", "Song", "Wrath", "Reaver", "Thorn", "Fang", "Needle"],
	"helm": ["Visage", "Cowl", "Crown", "Mask", "Brow"],
	"armor": ["Shroud", "Carapace", "Hide", "Mantle", "Shell"],
	"gloves": ["Grasp", "Fist", "Clutches", "Claw", "Hold"],
	"boots": ["Stride", "Trample", "March", "Tread", "Path"],
	"amulet": ["Talisman", "Heart", "Eye", "Charm", "Idol"],
	"ring": ["Loop", "Coil", "Band", "Circle", "Knot"],
}

const CURSES := {
	"frail": {"text": "-20% Maximum Life", "stats": {"max_hp_pct": -0.2}},
	"sluggish": {"text": "-12 Movement Speed", "stats": {"move_speed": -12.0}},
	"brittle": {"text": "You take 20% more damage", "stats": {"dmg_taken_pct": 0.2}},
	"parched": {"text": "Flasks heal 40% less", "stats": {"flask_heal": -0.14}},
	"hunted": {"text": "Enemies move 15% faster", "stats": {"enemy_speed_pct": 0.15}},
	"bleeding": {"text": "Lose 1 Life per second", "stats": {"life_regen": -1.0}},
	"dulled": {"text": "-35% Skill Damage", "stats": {"skill_pct": -0.35}},
	"poor": {"text": "-50% Gold found", "stats": {"gold_find": -0.5}},
}

const RITES := {
	"splinter": {"name": "Splintering", "desc": "Your projectiles burst into 2 bone shards on hitting a foe."},
	"leech": {"name": "Bloodthirst", "desc": "Heal 3 Life whenever you slay a foe."},
	"embers": {"name": "Ember Wake", "desc": "Dodging leaves a trail of burning ground."},
	"frost": {"name": "Grave Chill", "desc": "Your hits slow enemies by 35% for 2 seconds."},
	"harvest": {"name": "Soul Harvest", "desc": "Your items drink twice as many souls."},
	"martyr": {"name": "Martyrdom", "desc": "When struck, release a ring of 12 holy bolts."},
	"storm": {"name": "Wrath of Heaven", "desc": "15% chance on hit to call chain lightning."},
	"revenant": {"name": "Revenant", "desc": "Once per room, survive a killing blow."},
	"executioner": {"name": "Executioner", "desc": "+80% damage against foes below 35% Life."},
	"haste": {"name": "Fleet of the Damned", "desc": "Kills grant +35% movement speed for 2 seconds."},
	"corpse": {"name": "Corpse Burst", "desc": "Slain foes have a 35% chance to explode."},
	"phylactery": {"name": "Phylactery", "desc": "+1 Flask charge. Flasks also restore Mana."},
	"echo": {"name": "Echo", "desc": "Every 4th attack is fired twice."},
	"thorns": {"name": "Bone Ward", "desc": "Foes that strike you suffer 30 damage."},
	"volatile": {"name": "Volatile", "desc": "Critical hits explode."},
	"spectral": {"name": "Spectral Host", "desc": "Every 3rd kill releases a seeking spirit."},
}

const UNIQUES := [
	{"name": "Gravesong", "slot": "weapon", "weapon": "crossbow", "dmg_mult": 1.35,
		"stats": {"pierce": 2.0, "crit_chance": 0.08}, "rite": "spectral",
		"flavor": "Every bolt a requiem."},
	{"name": "The Choir Eternal", "slot": "weapon", "weapon": "wand", "dmg_mult": 1.25,
		"stats": {"extra_proj": 1.0, "soul_gain": 0.3}, "rite": "harvest",
		"flavor": "They sing still, inside the bone."},
	{"name": "Mouth of Ruin", "slot": "weapon", "weapon": "blunderbuss", "dmg_mult": 1.3,
		"stats": {"crit_chance": 0.1, "knock": 0.0}, "rite": "volatile",
		"flavor": "It does not fire. It screams."},
	{"name": "Pyre of Saint Ashe", "slot": "weapon", "weapon": "staff", "dmg_mult": 1.3,
		"stats": {"area_pct": 0.4, "attack_speed_pct": 0.1}, "rite": "embers",
		"flavor": "She burned so that others would. They did."},
	{"name": "Widowmaker", "slot": "weapon", "weapon": "axe", "dmg_mult": 1.35,
		"stats": {"crit_chance": 0.12, "crit_mult": 0.5}, "rite": "executioner",
		"flavor": "Swing low. Swing often."},
	{"name": "Litany of Nails", "slot": "weapon", "weapon": "repeater", "dmg_mult": 1.3,
		"stats": {"attack_speed_pct": 0.15, "pierce": 1.0}, "rite": "splinter",
		"flavor": "A thousand small confessions."},
	{"name": "Crown of the Martyr", "slot": "helm", "cursed": "bleeding",
		"stats": {"damage_pct": 0.3, "max_hp": 25.0, "armor": 6.0}, "rite": "martyr",
		"flavor": "It does not rest upon the brow. It grows from it."},
	{"name": "Flayed Saint's Hide", "slot": "armor",
		"stats": {"max_hp": 60.0, "armor": 18.0}, "rite": "thorns",
		"flavor": "Worn inside out, as penance."},
	{"name": "Hands of the Hanged", "slot": "gloves",
		"stats": {"attack_speed_pct": 0.3, "damage_pct": 0.1}, "rite": "echo",
		"flavor": "Still twitching."},
	{"name": "Exile's Last Road", "slot": "boots",
		"stats": {"move_speed": 22.0, "dodge_cd_pct": 0.35}, "rite": "haste",
		"flavor": "Walked by the damned. Never back."},
	{"name": "Heart of the Gauntlet", "slot": "amulet",
		"stats": {"damage_pct": 0.15, "max_hp": 20.0, "attack_speed_pct": 0.1}, "rite": "revenant",
		"flavor": "It beats when you do not."},
	{"name": "Ouroboros Coil", "slot": "ring",
		"stats": {"life_on_kill": 3.0, "soul_gain": 0.5}, "rite": "leech",
		"flavor": "What is eaten, returns."},
]

## How each stat is shown: [label, format]  (pct = percentage, flat, flat1 = 1 decimal)
const STAT_INFO := {
	"max_hp": ["Maximum Life", "flat"], "max_hp_pct": ["Maximum Life", "pct"],
	"max_mana": ["Maximum Mana", "flat"], "mana_regen": ["Mana per second", "flat1"],
	"armor": ["Armor", "flat"], "move_speed": ["Movement Speed", "flat"],
	"damage_pct": ["Damage", "pct"], "attack_speed_pct": ["Attack Speed", "pct"],
	"crit_chance": ["Critical Chance", "pct"], "crit_mult": ["Critical Damage", "pct"],
	"proj_speed_pct": ["Projectile Speed", "pct"], "extra_proj": ["Projectiles", "flat"],
	"pierce": ["Pierce", "flat"], "life_on_kill": ["Life on Kill", "flat"],
	"life_regen": ["Life per second", "flat1"], "dodge_cd_pct": ["Dodge Recovery", "pct"],
	"gold_find": ["Gold Found", "pct"], "soul_gain": ["Souls Gained", "pct"],
	"flask_heal": ["Flask Healing", "pct"], "skill_pct": ["Skill Damage", "pct"],
	"area_pct": ["Area of Effect", "pct"], "dmg_taken_pct": ["Damage Taken", "pct"],
	"enemy_speed_pct": ["Enemy Speed", "pct"], "flask_max": ["Flask Charges", "flat"],
}

static var _next_id := 1


static func stat_line(stat: String, v: float) -> String:
	var info: Array = STAT_INFO.get(stat, [stat.capitalize(), "flat"])
	var sgn := "+" if v >= 0 else "-"
	match info[1]:
		"pct":
			return "%s%d%% %s" % [sgn, int(round(absf(v) * 100.0)), info[0]]
		"flat1":
			return "%s%.1f %s" % [sgn, absf(v), info[0]]
		_:
			return "%s%d %s" % [sgn, int(round(absf(v))), info[0]]


static func _round_stat(stat: String, v: float) -> float:
	var info: Array = STAT_INFO.get(stat, ["", "flat"])
	match info[1]:
		"pct":
			return snappedf(v, 0.01)
		"flat1":
			return snappedf(v, 0.1)
		_:
			return maxf(1.0, round(v))


static func _blank(slot: String, level: int, rarity: int) -> Dictionary:
	var it := {
		"id": _next_id, "slot": slot, "name": "", "base": "", "rarity": rarity,
		"cursed": false, "curse": "", "icon": "", "level": level, "stats": {},
		"weapon": "", "dmg": 0.0, "rite": "", "souls": 0.0, "souls_needed": 0.0,
		"awakened": false, "flavor": "", "value": 0,
	}
	_next_id += 1
	return it


static func roll_rarity(floor_i: int, min_rarity := 0) -> int:
	var weights: Array = [[58, 32, 9, 1], [42, 38, 16, 4], [30, 40, 23, 7]][clampi(floor_i, 0, 2)]
	var total := 0
	for i in range(min_rarity, 4):
		total += weights[i]
	var r := Game.rng.randi_range(1, total)
	for i in range(min_rarity, 4):
		r -= weights[i]
		if r <= 0:
			return i
	return min_rarity


static func make_starting_weapon(wtype: String) -> Dictionary:
	var it := _blank("weapon", 1, COMMON)
	it["weapon"] = wtype
	it["base"] = WEAPON_NAMES[wtype][0]
	it["name"] = "Worn " + WEAPON_NAMES[wtype][0]
	it["icon"] = "w_" + wtype
	it["dmg"] = WEAPONS[wtype]["damage"]
	it["value"] = 3
	return it


## Generates a random item for the given floor (0-based).
## rarity -1 = roll it, slot "" = random slot.
static func generate(floor_i: int, rarity := -1, slot := "", min_rarity := 0) -> Dictionary:
	var rng: RandomNumberGenerator = Game.rng
	if rarity < 0:
		rarity = roll_rarity(floor_i, min_rarity)
	if rarity == UNIQUE:
		return make_unique(floor_i, slot)
	if slot == "":
		# Weapons are slightly more common: they change how you play.
		slot = "weapon" if rng.randf() < 0.24 else Game.SLOTS[rng.randi_range(1, Game.SLOTS.size() - 1)]
	var level := floor_i + 1
	var it := _blank(slot, level, rarity)
	var tier := clampi(floor_i, 0, 2)
	if slot == "weapon":
		var types := WEAPONS.keys()
		var wtype: String = types[rng.randi_range(0, types.size() - 1)]
		it["weapon"] = wtype
		it["base"] = WEAPON_NAMES[wtype][tier]
		it["icon"] = "w_" + wtype
		var rarity_mult: float = [1.0, 1.1, 1.22, 1.35][rarity]
		it["dmg"] = snappedf(WEAPONS[wtype]["damage"] * (1.0 + 0.32 * floor_i) * rarity_mult * rng.randf_range(0.92, 1.08), 0.1)
	else:
		var base: Dictionary = BASES[slot]
		it["base"] = base["names"][tier]
		it["icon"] = base["icon"]
		for k: String in base["implicit"]:
			var ab: Array = base["implicit"][k]
			it["stats"][k] = _round_stat(k, (ab[0] + ab[1] * floor_i) * rng.randf_range(0.9, 1.1))

	var n_affix := 0
	match rarity:
		MAGIC:
			n_affix = 1 if rng.randf() < 0.6 else 2
		RARE:
			n_affix = 2 if rng.randf() < 0.5 else 3
	var pool := AFFIXES.duplicate()
	pool.shuffle()
	var prefix := ""
	var suffix := ""
	var picked := 0
	for a: Dictionary in pool:
		if picked >= n_affix:
			break
		# Magic items: at most one prefix and one suffix (classic naming).
		if rarity == MAGIC and ((a["pre"] and prefix != "") or (not a["pre"] and suffix != "")):
			continue
		var v: float = (a["base"] + a["per"] * floor_i) * rng.randf_range(0.8, 1.2)
		it["stats"][a["stat"]] = _round_stat(a["stat"], it["stats"].get(a["stat"], 0.0) + v)
		if a["pre"]:
			prefix = a["word"]
		else:
			suffix = a["word"]
		picked += 1

	match rarity:
		COMMON:
			it["name"] = it["base"]
		MAGIC:
			it["name"] = ((prefix + " ") if prefix != "" else "") + it["base"] + ((" " + suffix) if suffix != "" else "")
		RARE:
			var firsts := RARE_FIRST
			var seconds: Array = RARE_SECOND[slot]
			it["name"] = firsts[rng.randi_range(0, firsts.size() - 1)] + " " + seconds[rng.randi_range(0, seconds.size() - 1)]

	if rarity >= MAGIC:
		var rites := RITES.keys()
		it["rite"] = rites[rng.randi_range(0, rites.size() - 1)]
		it["souls_needed"] = float(SOULS_NEEDED[rarity])
		# Cursed: stronger, with a drawback until awakened.
		if rng.randf() < 0.16:
			_apply_curse(it, "")
	it["value"] = int(([5, 14, 32, 65][rarity] as int) * level * (1.3 if it["cursed"] else 1.0))
	return it


static func _apply_curse(it: Dictionary, curse_id: String) -> void:
	if curse_id == "":
		var keys := CURSES.keys()
		curse_id = keys[Game.rng.randi_range(0, keys.size() - 1)]
	it["cursed"] = true
	it["curse"] = curse_id
	for k: String in it["stats"]:
		it["stats"][k] = _round_stat(k, it["stats"][k] * CURSE_POWER)
	if it["slot"] == "weapon":
		it["dmg"] = snappedf(it["dmg"] * 1.2, 0.1)
	if it["rarity"] != UNIQUE:
		it["name"] = "Cursed " + it["name"]


static func make_unique(floor_i: int, slot := "") -> Dictionary:
	var choices := []
	for u: Dictionary in UNIQUES:
		if slot == "" or u["slot"] == slot:
			choices.append(u)
	var u: Dictionary = choices[Game.rng.randi_range(0, choices.size() - 1)]
	var level := floor_i + 1
	var it := _blank(u["slot"], level, UNIQUE)
	it["name"] = u["name"]
	it["flavor"] = u["flavor"]
	it["rite"] = u["rite"]
	it["souls_needed"] = float(SOULS_NEEDED[UNIQUE])
	var scale := 1.0 + 0.3 * floor_i
	if u["slot"] == "weapon":
		var wtype: String = u["weapon"]
		it["weapon"] = wtype
		it["base"] = WEAPON_NAMES[wtype][clampi(floor_i, 0, 2)]
		it["icon"] = "w_" + wtype
		it["dmg"] = snappedf(WEAPONS[wtype]["damage"] * (1.0 + 0.32 * floor_i) * u["dmg_mult"], 0.1)
	else:
		var base: Dictionary = BASES[u["slot"]]
		it["base"] = base["names"][clampi(floor_i, 0, 2)]
		it["icon"] = base["icon"]
	for k: String in u["stats"]:
		if k == "knock":
			continue
		var v: float = u["stats"][k]
		# Flat stats scale with depth; percentages stay put.
		if STAT_INFO.get(k, ["", "flat"])[1] == "flat" and k not in ["extra_proj", "pierce"]:
			v *= scale
		it["stats"][k] = _round_stat(k, v)
	if u.has("cursed"):
		_apply_curse(it, u["cursed"])
	it["value"] = int(65 * level * (1.3 if it["cursed"] else 1.0))
	return it


static func color_of(it: Dictionary) -> Color:
	if it["cursed"] and not it["awakened"]:
		return CURSED_COLOR
	return RARITY_COLORS[it["rarity"]]


static func hex(c: Color) -> String:
	return c.to_html(false)


## BBCode description used by tooltips. `compare` = currently equipped item.
static func describe(it: Dictionary, compare: Variant = null, with_title := true) -> String:
	var s := ""
	var col := hex(color_of(it))
	if with_title:
		s += "[color=#%s]%s[/color]\n" % [col, it["name"]]
		var sub: String = Game.SLOT_NAMES[it["slot"]]
		if it["rarity"] >= RARE:
			sub = it["base"]
		s += "[color=#8a8078]%s %s[/color]\n" % [RARITY_NAMES[it["rarity"]], sub]
	if it["slot"] == "weapon":
		var w: Dictionary = WEAPONS[it["weapon"]]
		var dmg_txt := "%.1f" % it["dmg"]
		if w["count"] > 1:
			dmg_txt += " x%d" % w["count"]
		s += "[color=#e8e0d0]%s damage[/color]" % dmg_txt
		if compare != null and compare["slot"] == "weapon":
			var cur := float(compare["dmg"]) * float(WEAPONS[compare["weapon"]]["count"])
			var new := float(it["dmg"]) * float(w["count"])
			var diff := new - cur
			if absf(diff) >= 0.1:
				s += "  [color=#%s](%s%.1f)[/color]" % ["7ad46a" if diff > 0 else "d0504a", "+" if diff > 0 else "", diff]
		s += "\n[color=#a09888]%.1f attacks/s  -  %s[/color]\n" % [w["rate"], _weapon_blurb(it["weapon"])]
	var keys: Array = it["stats"].keys()
	for k: String in keys:
		var v: float = it["stats"][k]
		var line := stat_line(k, v)
		var c := "c8c0ff" if it["rarity"] >= MAGIC else "d8d2c4"
		s += "[color=#%s]%s[/color]" % [c, line]
		if compare != null:
			var old_v: float = compare["stats"].get(k, 0.0)
			var d := v - old_v
			if absf(d) > 0.001 and old_v != 0.0:
				s += " [color=#%s](%s)[/color]" % ["7ad46a" if d > 0 else "d0504a", stat_line(k, d).split(" ")[0]]
		s += "\n"
	if compare != null:
		for k: String in compare["stats"]:
			if not it["stats"].has(k):
				s += "[color=#d0504a]%s (lost)[/color]\n" % stat_line(k, compare["stats"][k])
	if it["cursed"]:
		var curse: Dictionary = CURSES[it["curse"]]
		if it["awakened"]:
			s += "[color=#7ad46a][s]%s[/s]  Curse broken[/color]\n" % curse["text"]
		else:
			s += "[color=#e0403a]CURSED: %s[/color]\n[color=#a06060](Awaken to break the curse)[/color]\n" % curse["text"]
	if it["rite"] != "":
		var r: Dictionary = RITES[it["rite"]]
		if it["awakened"]:
			s += "[color=#7ee0ff]Rite of %s (Awakened)[/color]\n[color=#bfe8f0]%s[/color]\n" % [r["name"], r["desc"]]
		else:
			s += "[color=#6a7a88]Dormant Rite of %s  %d/%d souls[/color]\n[color=#5a6670]%s[/color]\n" % [
				r["name"], int(it["souls"]), int(it["souls_needed"]), r["desc"]]
	if it["flavor"] != "":
		s += "[color=#a08060][i]\"%s\"[/i][/color]\n" % it["flavor"]
	return s.strip_edges()


static func _weapon_blurb(wtype: String) -> String:
	match wtype:
		"crossbow":
			return "fast, precise bolts"
		"repeater":
			return "a hail of light bolts"
		"blunderbuss":
			return "close-range spread"
		"staff":
			return "exploding fireballs"
		"wand":
			return "seeking skulls"
		"axe":
			return "piercing throws"
	return ""
