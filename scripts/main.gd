extends Node
## Entry point: switches between the title screen, class select, a run,
## and the end screen.
##
## Debug command-line options (after `--`):
##   --autoplay            a simple bot plays (smoke testing)
##   --class=heretic       skip menus and start with this class
##   --first-room=boss     first room type (combat, elite, shop, shrine, rest, treasure, boss)
##   --floor=2             start on floor 1-3
##   --screenshots=a,b,c   save screenshots at these times (seconds) into --shotdir=
##   --quit-after=N        quit after N seconds
##   --timescale=N         speed the game up

var current: Node = null
var _shots: Array = []
var _shot_dir := "user://"
var _quit_after := -1.0
var _t := 0.0
var _shot_i := 0


func _ready() -> void:
	Input.set_custom_mouse_cursor(load("res://assets/sprites/ui/cursor.png"), Input.CURSOR_ARROW, Vector2(15, 15))
	var cls := ""
	var floor_i := 0
	var screen := ""
	for a: String in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=")
		match kv[0]:
			"class":
				cls = kv[1]
			"floor":
				floor_i = clampi(int(kv[1]) - 1, 0, 2)
			"screenshots":
				for s in kv[1].split(","):
					_shots.append(float(s))
			"shotdir":
				_shot_dir = kv[1]
			"quit-after":
				_quit_after = float(kv[1])
			"timescale":
				Engine.time_scale = float(kv[1])
			"screen":
				screen = kv[1]
	if screen == "class":
		show_class_select()
		return
	if Game.autoplay and cls == "":
		cls = "exile"
	if cls != "":
		Game.start_run(cls)
		Game.floor_idx = floor_i
		_launch_run()
	else:
		show_title()


func _process(delta: float) -> void:
	_t += delta / maxf(Engine.time_scale, 0.01)
	if _shot_i < _shots.size() and _t >= _shots[_shot_i]:
		var img := get_viewport().get_texture().get_image()
		img.save_png(_shot_dir.path_join("shot_%02d.png" % _shot_i))
		print("screenshot ", _shot_i, " at ", _t)
		_shot_i += 1
	if _quit_after > 0.0 and _t >= _quit_after:
		print("quit-after reached. floor=%d room=%d kills=%d level=%d hp=%.0f gold=%d awakened=%d" % [
			Game.floor_idx, Game.room_idx, Game.kills, Game.level, Game.hp, Game.gold, Game.awakened_count])
		get_tree().quit()


func _swap(n: Node) -> void:
	get_tree().paused = false
	Engine.time_scale = 1.0 if Engine.time_scale < 1.0 else Engine.time_scale
	if current != null:
		current.queue_free()
	current = n
	add_child(n)


func show_title() -> void:
	_swap(Screens.TitleScreen.new(self))


func show_class_select() -> void:
	_swap(Screens.ClassSelect.new(self))


func start_run(cls: String) -> void:
	Game.start_run(cls)
	_launch_run()


func _launch_run() -> void:
	var r := Run.new()
	r.process_mode = Node.PROCESS_MODE_PAUSABLE
	r.ended.connect(_on_run_ended)
	_swap(r)


func _on_run_ended(victory: bool) -> void:
	if Game.autoplay:
		print("RUN ENDED victory=%s floor=%d room=%d kills=%d level=%d time=%.0f" % [victory, Game.floor_idx, Game.room_idx, Game.kills, Game.level, Game.run_time])
		Game.start_run(Game.class_id)
		_launch_run()
		return
	_swap(Screens.EndScreen.new(self, victory))
