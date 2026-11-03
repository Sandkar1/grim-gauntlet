extends Node
## Global run state (autoload "Game").
##
## Everything that must survive between rooms lives here: chosen class,
## equipment, gold, level, life/mana, and the computed character stats.
## Gameplay nodes read `Game.stats` instead of hard-coding numbers.

signal stats_changed
signal gold_changed
signal xp_changed
signal equipment_changed
signal item_awakened(item: Dictionary)
signal notify(text: String, color: Color)

const SLOTS := ["weapon", "helm", "armor", "gloves", "boots", "amulet", "ring"]
const SLOT_NAMES := {
	"weapon": "Weapon", "helm": "Helm", "armor": "Armor", "gloves": "Gloves",
	"boots": "Boots", "amulet": "Amulet", "ring": "Ring",
}

const FLOORS := [
	{"name": "The Sunken Crypt", "biome": "crypt", "ambient": Color(0.30, 0.29, 0.37), "boss": "bone_warden"},
	{"name": "The Ossuary Deep", "biome": "catacomb", "ambient": Color(0.30, 0.31, 0.25), "boss": "mother_of_rot"},
	{"name": "The Cinder Cathedral", "biome": "inferno", "ambient": Color(0.36, 0.23, 0.21), "boss": "hollow_bishop"},
]
## Rooms you pass through on each floor before the boss door appears.
const ROOMS_PER_FLOOR := 7

const CLASSES := {
	"exile": {
		"name": "The Exile",
		"sprite": "exile",
		"weapon": "crossbow",
		"skill": "volley",
		"skill_name": "Volley",
		"skill_desc": "Loose a fan of 9 piercing bolts.",
		"skill_cost": 30.0,
		"desc": "A hunter cast out of the sunlit world. Fast on her feet and deadly at range.",
		"stats": {"max_hp": 90.0, "move_speed": 104.0, "max_mana": 60.0, "crit_chance": 0.08},
	},
	"heretic": {
		"name": "The Heretic",
		"sprite": "heretic",
		"weapon": "staff",
		"skill": "nova",
		"skill_name": "Blood Nova",
		"skill_desc": "Erupt in a ring of fire that hurls foes away.",
		"skill_cost": 35.0,
		"desc": "Burned once by the Church, he now burns everything. Fragile, but his fire spreads.",
		"stats": {"max_hp": 78.0, "move_speed": 98.0, "max_mana": 90.0, "mana_regen": 6.0, "area_pct": 0.1},
	},
	"penitent": {
		"name": "The Penitent",
		"sprite": "penitent",
		"weapon": "axe",
		"skill": "consecrate",
		"skill_name": "Consecrate",
		"skill_desc": "Sanctify the ground: burns the unholy and mends your wounds.",
		"skill_cost": 40.0,
		"desc": "A templar who walked into the dark to atone. Slow, armored, and unbreakable.",
		"stats": {"max_hp": 125.0, "move_speed": 92.0, "max_mana": 55.0, "armor": 12.0},
	},
}

## Baseline stats; class stats override these, then items and blessings add.
const BASE_STATS := {
	"max_hp": 100.0, "max_hp_pct": 0.0, "max_mana": 60.0, "mana_regen": 4.0,
	"armor": 0.0, "move_speed": 100.0, "damage_pct": 0.0, "attack_speed_pct": 0.0,
	"crit_chance": 0.05, "crit_mult": 0.75, "proj_speed_pct": 0.0, "extra_proj": 0.0,
	"pierce": 0.0, "life_on_kill": 0.0, "life_regen": 0.0, "dodge_cd_pct": 0.0,
	"gold_find": 0.0, "soul_gain": 0.0, "flask_heal": 0.35, "skill_pct": 0.0,
	"area_pct": 0.0, "dmg_taken_pct": 0.0, "enemy_speed_pct": 0.0, "flask_max": 3.0,
}

## Level-up "Blessings" (three are offered, pick one).
const BLESSINGS := [
	{"name": "Wrath", "desc": "+12% Damage", "stats": {"damage_pct": 0.12}},
	{"name": "Fervor", "desc": "+12% Attack Speed", "stats": {"attack_speed_pct": 0.12}},
	{"name": "Vigor", "desc": "+20 Maximum Life", "stats": {"max_hp": 20.0}, "heal": 20.0},
	{"name": "Fleetness", "desc": "+8 Movement Speed", "stats": {"move_speed": 8.0}},
	{"name": "Precision", "desc": "+5% Critical Chance", "stats": {"crit_chance": 0.05}},
	{"name": "Brutality", "desc": "+30% Critical Damage", "stats": {"crit_mult": 0.3}},
	{"name": "Iron Skin", "desc": "+8 Armor", "stats": {"armor": 8.0}},
	{"name": "Leeching", "desc": "+1 Life on Kill", "stats": {"life_on_kill": 1.0}},
	{"name": "Arcana", "desc": "+25% Skill Damage, +15 Mana", "stats": {"skill_pct": 0.25, "max_mana": 15.0}},
	{"name": "Shadowstep", "desc": "+20% Dodge Recovery", "stats": {"dodge_cd_pct": 0.2}},
	{"name": "Soul Hunger", "desc": "+30% Souls gained", "stats": {"soul_gain": 0.3}},
	{"name": "Hydra", "desc": "+1 Projectile, -8% Damage", "stats": {"extra_proj": 1.0, "damage_pct": -0.08}, "min_level": 4},
	{"name": "Impaling", "desc": "+1 Pierce", "stats": {"pierce": 1.0}},
	{"name": "Velocity", "desc": "+20% Projectile Speed, +5% Damage", "stats": {"proj_speed_pct": 0.2, "damage_pct": 0.05}},
	{"name": "Greed", "desc": "+40% Gold found", "stats": {"gold_find": 0.4}},
	{"name": "Clarity", "desc": "+2 Mana per second", "stats": {"mana_regen": 2.0}},
]

var rng := RandomNumberGenerator.new()
var run: Node = null # the active Run node, set by Run itself

var class_id := "exile"
var floor_idx := 0
var room_idx := 0
var gold := 0
var level := 1
var xp := 0
var pending_levels := 0
var equipment := {}
var blessings := {}
var blessing_names: Array = []
var flask_charges := 3
var flask_progress := 0.0
var hp := 100.0
var mana := 60.0
var kills := 0
var souls_total := 0
var awakened_count := 0
var run_time := 0.0
var room_history: Array = []
var revenant_used := false
var stats := {}
var autoplay := false # debug bot, enabled with `-- --autoplay`
var music_volume := 0.7
var sfx_volume := 0.8


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_input()
	autoplay = "--autoplay" in OS.get_cmdline_user_args()
	stats = BASE_STATS.duplicate()


func _setup_input() -> void:
	var keys := {
		"move_up": [KEY_W, KEY_UP],
		"move_down": [KEY_S, KEY_DOWN],
		"move_left": [KEY_A, KEY_LEFT],
		"move_right": [KEY_D, KEY_RIGHT],
		"dodge": [KEY_SPACE, KEY_SHIFT],
		"flask": [KEY_Q],
		"interact": [KEY_E],
		"salvage": [KEY_F],
		"sheet": [KEY_TAB, KEY_C, KEY_I],
		"pause": [KEY_ESCAPE, KEY_P],
		"skill_key": [KEY_R],
	}
	for action: String in keys:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for k: Key in keys[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = k
			InputMap.action_add_event(action, ev)
	var mouse := {"shoot": MOUSE_BUTTON_LEFT, "skill": MOUSE_BUTTON_RIGHT}
	for action: String in mouse:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		var mb := InputEventMouseButton.new()
		mb.button_index = mouse[action]
		InputMap.action_add_event(action, mb)


# ---------------------------------------------------------------------------
# Run lifecycle
# ---------------------------------------------------------------------------

func start_run(cls: String) -> void:
	rng.randomize()
	class_id = cls
	floor_idx = 0
	room_idx = 0
	gold = 0
	level = 1
	xp = 0
	pending_levels = 0
	kills = 0
	souls_total = 0
	awakened_count = 0
	run_time = 0.0
	blessings = {}
	blessing_names = []
	room_history = []
	revenant_used = false
	equipment = {}
	for s in SLOTS:
		equipment[s] = null
	equipment["weapon"] = ItemDB.make_starting_weapon(CLASSES[cls]["weapon"])
	recalc_stats()
	hp = stats["max_hp"]
	mana = stats["max_mana"]
	flask_charges = int(stats["flask_max"])
	flask_progress = 0.0


func class_data() -> Dictionary:
	return CLASSES[class_id]


func floor_data() -> Dictionary:
	return FLOORS[floor_idx]


# ---------------------------------------------------------------------------
# Stats
# ---------------------------------------------------------------------------

func recalc_stats() -> void:
	var s := BASE_STATS.duplicate()
	var cls: Dictionary = CLASSES[class_id]["stats"]
	for k: String in cls:
		s[k] = cls[k]
	for slot: String in SLOTS:
		var it = equipment.get(slot)
		if it == null:
			continue
		for k: String in it["stats"]:
			s[k] = s.get(k, 0.0) + it["stats"][k]
		if it["cursed"] and not it["awakened"]:
			var cs: Dictionary = ItemDB.CURSES[it["curse"]]["stats"]
			for k: String in cs:
				s[k] = s.get(k, 0.0) + cs[k]
	for k: String in blessings:
		s[k] = s.get(k, 0.0) + blessings[k]
	s["flask_max"] += rite_count("phylactery")
	s["max_hp"] = maxf(10.0, s["max_hp"] * (1.0 + s["max_hp_pct"]))
	s["move_speed"] = maxf(45.0, s["move_speed"])
	s["crit_chance"] = clampf(s["crit_chance"], 0.0, 0.9)
	stats = s
	hp = minf(hp, s["max_hp"])
	mana = minf(mana, s["max_mana"])
	flask_charges = mini(flask_charges, int(s["flask_max"]))
	stats_changed.emit()


func stat(key: String) -> float:
	return stats.get(key, 0.0)


## Weapon stats merged with the equipped weapon item.
func weapon_data() -> Dictionary:
	var it = equipment.get("weapon")
	var wtype: String = it["weapon"] if it != null else "crossbow"
	var w: Dictionary = ItemDB.WEAPONS[wtype].duplicate()
	w["damage"] = it["dmg"] if it != null else w["damage"]
	w["type"] = wtype
	return w


## How many equipped, awakened items carry a given rite.
func rite_count(id: String) -> int:
	var n := 0
	for slot: String in SLOTS:
		var it = equipment.get(slot)
		if it != null and it["awakened"] and it["rite"] == id:
			n += 1
	return n


# ---------------------------------------------------------------------------
# Equipment, gold, xp, souls
# ---------------------------------------------------------------------------

## Equips an item, returning the previously equipped one (or null).
func equip(item: Dictionary) -> Variant:
	var old = equipment.get(item["slot"])
	equipment[item["slot"]] = item
	recalc_stats()
	equipment_changed.emit()
	return old


func add_gold(n: int) -> void:
	gold = maxi(0, gold + n)
	gold_changed.emit()


func xp_to_next() -> int:
	return 24 + (level - 1) * 18


func add_xp(n: int) -> void:
	xp += n
	while xp >= xp_to_next():
		xp -= xp_to_next()
		level += 1
		pending_levels += 1
		notify.emit("Level %d reached" % level, Color("f2d65a"))
	xp_changed.emit()


func add_souls(n: float) -> void:
	var gain := n * (1.0 + stat("soul_gain")) * (1 + rite_count("harvest"))
	souls_total += int(round(gain))
	var awakened_any := false
	for slot: String in SLOTS:
		var it = equipment.get(slot)
		if it == null or it["awakened"] or it["rite"] == "":
			continue
		it["souls"] = minf(it["souls"] + gain, it["souls_needed"])
		if it["souls"] >= it["souls_needed"]:
			awaken(it)
			awakened_any = true
	if not awakened_any:
		equipment_changed.emit()


func awaken(it: Dictionary) -> void:
	it["awakened"] = true
	it["souls"] = it["souls_needed"]
	awakened_count += 1
	recalc_stats()
	equipment_changed.emit()
	item_awakened.emit(it)


func roll_blessings(count := 3) -> Array:
	var pool := []
	for b: Dictionary in BLESSINGS:
		if level >= b.get("min_level", 0):
			pool.append(b)
	pool.shuffle()
	return pool.slice(0, count)


func apply_blessing(b: Dictionary) -> void:
	for k: String in b["stats"]:
		blessings[k] = blessings.get(k, 0.0) + b["stats"][k]
	blessing_names.append(b["name"])
	recalc_stats()
	if b.has("heal"):
		heal(b["heal"])


func heal(amount: float) -> void:
	hp = minf(stat("max_hp"), hp + amount)
	stats_changed.emit()


func add_flask_progress(amount: float) -> void:
	if flask_charges >= int(stat("flask_max")):
		flask_progress = 0.0
		return
	flask_progress += amount
	if flask_progress >= 1.0:
		flask_progress = 0.0
		flask_charges += 1
		notify.emit("Your flask refills with blood", Color("d8352f"))
	stats_changed.emit()
