extends Node2D
## The window. Four modes:
##   MENU    choose a net (training run and generation) to play against, or skip
##   PLAY    you (blue, W A S D) against the chosen net (red); as a free-for-all
##           also against other nets from the list
##   LIVE    nets steer all balls, live
##   REVIEW  recorded highlight games of the training runs, with play/pause,
##           rewind, fast forward and next/previous battle
##   FRIENDS host or join a game with friends (Steam or direct connection)
##   LOBBY   the players of a multiplayer game before the host starts it
## In a multiplayer game the host's window runs the rules; the others send their
## keys and show what the host sends back (see game/net_game.gd).
## All rules live in sim/arena_sim.gd; this file feeds it input and draws it.

const Sim = preload("res://sim/arena_sim.gd")
const Net = preload("res://sim/net_policy.gd")
const Bot = preload("res://sim/scripted_bot.gd")
const Recorder = preload("res://sim/game_recorder.gd")
const Profile = preload("res://sim/net_profile.gd")
const NetGame = preload("res://game/net_game.gd")

const NET_PATH := "res://net/rival_net.json"
## Version of this build; compared with the newest release on GitHub at start.
const VERSION := "0.4"
const RELEASES_API := "https://api.github.com/repos/Xaragan/KugelArena/releases/latest"
const DOWNLOAD_PAGE := "github.com/Xaragan/KugelArena/releases/latest"
const RUNS_DIR := "res://training/runs"
const PIXELS_PER_UNIT := 320.0 / Sim.ARENA_RADIUS
const CENTRE := Vector2(640.0, 372.0)
const PLAYER := 0
const RIVAL := 1

const MODE_MENU := 0
const MODE_PLAY := 1
const MODE_LIVE := 2
const MODE_REVIEW := 3
const MODE_FRIENDS := 4
const MODE_LOBBY := 5
const STATE_SEND_TICKS := 2      # the host sends the disc every second tick (30 per second)

const STATE_READY := 0
const STATE_PLAYING := 1
const STATE_OVER := 2
const READY_SECONDS := 1.5
const FALL_SECONDS := 0.7
const SPEEDS: Array[float] = [0.25, 0.5, 1.0, 2.0, 4.0]
const SEEK_SECONDS := 2.0

const COL_BACKGROUND := Color(0.05, 0.06, 0.10)
const COL_DISC := Color(0.16, 0.19, 0.27)
const COL_DISC_RIM := Color(0.75, 0.80, 0.95)
const COL_TEXT := Color(0.88, 0.90, 0.96)
const COL_DIM := Color(0.55, 0.59, 0.70)
const COL_BALL: Array[Color] = [Color(0.30, 0.62, 1.0), Color(1.0, 0.40, 0.32),
	Color(0.45, 0.85, 0.45), Color(1.0, 0.80, 0.30), Color(0.72, 0.50, 1.0),
	Color(0.35, 0.85, 0.85), Color(1.0, 0.60, 0.25), Color(1.0, 0.55, 0.80)]
const BALL_CHOICES: Array[int] = [2, 4, 6, 8]
const COL_ITEM: Array[Color] = [Color(1.0, 0.78, 0.20), Color(0.40, 0.90, 0.45),
	Color(0.66, 0.70, 0.85), Color(0.45, 0.90, 1.0), Color(0.92, 0.45, 0.95)]
const ITEM_LETTER: Array[String] = ["P", "S", "A", "F", "X"]
const ITEM_HELP: Array[String] = ["heavy ball: pushes harder", "more thrust and top speed",
	"more grip, shorter skids", "the others get sluggish", "blast that throws the others away"]
const ZONE_HELP: Array[String] = ["solid, bouncy", "no way through", "fall in and you are out",
	"slippery", "slows you down", "pushes you along"]
const ZONE_COLOR: Array[Color] = [Color(0.72, 0.76, 0.88), Color(0.10, 0.11, 0.17),
	Color(0.03, 0.03, 0.05), Color(0.55, 0.85, 1.0), Color(0.60, 0.42, 0.24), Color(0.90, 0.95, 1.0)]
const FX_NAME: Array[String] = ["Power", "Speed", "Anchor", "Frozen"]
const FX_COLOR: Array[Color] = [Color(1.0, 0.78, 0.20), Color(0.40, 0.90, 0.45),
	Color(0.66, 0.70, 0.85), Color(0.45, 0.90, 1.0)]

## Five dots showing a strength from one to five.
class Pips extends Control:
	var count := 0

	func _draw() -> void:
		for i in 5:
			draw_circle(Vector2(8 + i * 20, 9), 7.0,
				Color(1.0, 0.78, 0.2) if i < count else Color(1, 1, 1, 0.12))


## One opponent in the menu: coloured dot, name, one line about how it plays,
## strength dots.
class OpponentCard extends Button:
	var title := ""
	var line := ""
	var stars := 0
	var age := ""
	var numbers := ""   # test results, e.g. "Duel 78 %   FFA 23 %"
	var dot := Color.WHITE

	func _draw() -> void:
		var f := ThemeDB.fallback_font
		draw_string(f, Vector2(size.x - 190, 46), numbers if numbers != "" else age,
			HORIZONTAL_ALIGNMENT_RIGHT, 180, 11, Color(0.62, 0.66, 0.78))
		var title_width := f.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x
		draw_string(f, Vector2(60 + title_width, 25), age, HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
			Color(0.5, 0.54, 0.65))
		draw_circle(Vector2(28, size.y * 0.5), 14.0, dot)
		draw_circle(Vector2(23, size.y * 0.5 - 5), 4.0, Color(1, 1, 1, 0.3))
		draw_string(f, Vector2(54, 25), title, HORIZONTAL_ALIGNMENT_LEFT, size.x - 170, 17,
			Color(0.9, 0.92, 0.97))
		draw_string(f, Vector2(54, 45), line, HORIZONTAL_ALIGNMENT_LEFT, size.x - 200, 12,
			Color(0.6, 0.64, 0.75))
		for i in 5:
			draw_circle(Vector2(size.x - 100 + i * 18, 19), 6.0,
				Color(1.0, 0.78, 0.2) if i < stars else Color(1, 1, 1, 0.12))


var mode := MODE_MENU
var sim := Sim.new()
var ball_count := 2            # 2 = duel, more = free-for-all
var seat_brains: Array = []    # who steers each ball: null = you, else a net or a bot
var seat_names: Array[String] = []
var fall_time := PackedFloat32Array()   # seconds since a ball fell, -1 = not falling
var my_seat := 0               # the ball this window steers, -1 = none (watching)
var seat_peer: Array[int] = [] # multiplayer: which remote player steers a ball, 0 = nobody

# Multiplayer.
var net: NetGame
var net_role := ""             # "" = playing alone, "host" or "client"
var lineup_key := ""
var friends_panel: Panel
var friends_status: Label
var friends_list: ItemList
var friends_ids: Array = []
var address_edit: LineEdit
var lobby_panel: Panel
var lobby_status: Label
var lobby_players: Label
var lobby_counts: Array = []
var lobby_invites: ItemList
var lobby_invite_ids: Array = []
var lobby_invite_button: Button
var lobby_start: Button
var lobby_code: Label
var lobby_copy: Button
var code_edit: LineEdit
var refresh_timer := 0.0
var state := STATE_READY
var state_time := 0.0
var score: Array[int] = [0, 0]
var draws := 0
var flashes: Array = []        # {at, age, strength}
var texts: Array = []          # {at, age, text, color}
var font: Font
var recorder := Recorder.new()
var record_path := ""          # every finished live round is appended here as data
var round_seed := 0

# What the training runs left behind.
var opponents: Array = []      # every saved net: {path, name, run, run_index, generation, profile}
var opponent_index := 0
var shown: Array[int] = []     # indices into opponents that the current filter shows
var run_index_of := {}         # run name -> its number, which picks the first name
var tests_of := {}             # run name -> test results per generation (Profile.read_tests)
var battles: Array = []        # every highlight of every run: {run, game}
var battle_index := 0

# Replay state.
var replay: Dictionary = {}
var replay_t := 0.0
var replay_len := 0.0
var replay_playing := false
var speed_index := 2

# Controls.
var menu_panel: Panel
var card_box: VBoxContainer
var cards: Array = []
var tier_buttons: Array = []
var count_buttons: Array = []
var update_label: Label
var detail_name: Label
var detail_pips: Pips
var detail_line: Label
var detail_text: Label
var detail_small: Label
var review_box: Control
var battle_list: ItemList
var play_button: Button
var speed_button: Button
var timeline: HSlider
var menu_button: Button


func _ready() -> void:
	font = ThemeDB.fallback_font
	RenderingServer.set_default_clear_color(COL_BACKGROUND)
	sim.record_events = true
	record_path = "res://recordings/window_%s.jsonl" % \
		Time.get_datetime_string_from_system().replace(":", "-")
	# Optional start arguments after "--":
	#   --second-screen  open on a screen that is not the primary one
	#   --watch          start in live mode (net against net)
	#   --review         start in the replays
	var args := OS.get_cmdline_user_args()
	if "--second-screen" in args:
		var primary := DisplayServer.get_primary_screen()
		for s in DisplayServer.get_screen_count():
			if s != primary:
				DisplayServer.window_set_current_screen(s)
				break
	for arg in args:
		if arg.begins_with("--balls="):   # --balls=6 starts with a six-ball free-for-all
			ball_count = clampi(int(arg.trim_prefix("--balls=")), 2, Sim.MAX_BALLS)
	net = NetGame.new()
	net.name = "Net"   # same path on every machine: Main/Net
	net.version = VERSION
	add_child(net)
	net.entered_lobby.connect(func() -> void: _set_mode(MODE_LOBBY))
	net.lobby_changed.connect(_refresh_lobby)
	net.friends_changed.connect(_refresh_friends)
	net.closed.connect(_on_net_closed)
	net.round_started.connect(_on_net_round_start)
	net.state_received.connect(_on_net_state)
	net.events_received.connect(_on_net_events)
	net.round_finished.connect(_on_net_round_over)
	_scan_runs()
	_build_controls()
	_build_net_controls()
	# Connect to Steam right away (silently if Steam is not running). Only then
	# does Steam hand an accepted invite to this game; otherwise it would start
	# the real "Spacewar", which owns the test app id this game borrows.
	if not ("--no-steam" in args):
		net.init_steam()
	sim.reset(1)
	# --host-lan hosts a direct-connection game at once, --join=ADDRESS joins one.
	for arg in args:
		if arg == "--host-lan":
			_set_mode(MODE_FRIENDS)
			net.host_lan()
			return
		if arg.begins_with("--join="):
			_set_mode(MODE_FRIENDS)
			net.join_lan(arg.trim_prefix("--join="))
			return
	if "--watch" in args:
		_start_live(MODE_LIVE)
	elif "--review" in args:
		_start_review()
	else:
		_set_mode(MODE_MENU)


# ------------------------------------------------------------------------------
# Training runs on disk
# ------------------------------------------------------------------------------

func _scan_runs() -> void:
	battles.clear()
	opponents.clear()
	run_index_of.clear()
	var base := ProjectSettings.globalize_path(RUNS_DIR)
	var names: Array = []
	if DirAccess.dir_exists_absolute(base):
		names = Array(DirAccess.get_directories_at(base))
		names.sort()
	for index in names.size():
		var run_name: String = names[index]
		run_index_of[run_name] = index
		var dir := base.path_join(run_name)
		tests_of[run_name] = Profile.read_tests(dir)
		var found := 0
		if DirAccess.dir_exists_absolute(dir.path_join("nets")):
			for file in DirAccess.get_files_at(dir.path_join("nets")):
				if file.ends_with(".json") and _add_opponent(dir.path_join("nets").path_join(file),
						run_name, index):
					found += 1
		if found == 0:
			_add_opponent(dir.path_join("net_best.json"), run_name, index)
		for game: Dictionary in Recorder.read_all(dir.path_join("highlights.jsonl")):
			battles.append({"run": run_name, "game": game})
	if opponents.is_empty():
		_add_opponent(NET_PATH, "", names.size())
	# Strongest first: by test score where there is one.
	opponents.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var wa := float(a["score"]) if float(a["score"]) >= 0.0 else \
			float((a["profile"] as Dictionary).get("win_vs_bot", -1.0)) * 0.5
		var wb := float(b["score"]) if float(b["score"]) >= 0.0 else \
			float((b["profile"] as Dictionary).get("win_vs_bot", -1.0)) * 0.5
		return wa > wb if wa != wb else int(a["generation"]) > int(b["generation"]))


func _add_opponent(path: String, run_name: String, run_index: int) -> bool:
	var data := Net.load_file(path)
	if data.is_empty():
		return false
	var info: Dictionary = data.get("info", {})
	var profile: Dictionary = info.get("profile", {})
	var generation := int(info.get("generation", 0))
	var test: Dictionary = (tests_of.get(run_name, {}) as Dictionary).get(generation, {})
	opponents.append({"path": path, "run": run_name, "run_index": run_index,
		"generation": generation, "profile": profile,
		"duel": float(test.get("duel", -1.0)), "ffa": float(test.get("ffa", -1.0)),
		"score": float(test.get("score", -1.0)),
		"name": Profile.display_name(profile, run_index)})
	return true


## Readable name for a player stored in a recorded game ("net_gen30", "baseline_bot").
func _friendly(player: String, run_name: String) -> String:
	if player == "baseline_bot" or player == "bot":
		return "Practice bot"
	if player == "human":
		return "You"
	if player.begins_with("net_gen"):
		var gen := int(player.trim_prefix("net_gen"))
		for o: Dictionary in opponents:
			if o["run"] == run_name and int(o["generation"]) == gen:
				return "%s (age %d)" % [o["name"], gen]
		return "%s (age %d)" % [Profile.FIRST_NAMES[posmod(int(run_index_of.get(run_name, 0)),
			Profile.FIRST_NAMES.size())], gen]
	return player


# ------------------------------------------------------------------------------
# Controls (built in code; none takes keyboard focus, keys belong to the game)
# ------------------------------------------------------------------------------

func _button(parent: Node, text: String, rect: Rect2, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.position = rect.position
	b.size = rect.size
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(action)
	parent.add_child(b)
	return b


func _label(parent: Node, text: String, at: Vector2, size: int, colour: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.position = at
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", colour)
	parent.add_child(l)
	return l


func _build_controls() -> void:
	# Menu: pick an opponent or skip.
	menu_panel = Panel.new()
	menu_panel.position = Vector2(190, 56)
	menu_panel.size = Vector2(900, 610)
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.09, 0.10, 0.15)
	panel_style.border_color = Color(0.25, 0.28, 0.38)
	panel_style.set_border_width_all(1)
	panel_style.set_corner_radius_all(14)
	menu_panel.add_theme_stylebox_override("panel", panel_style)
	add_child(menu_panel)
	_label(menu_panel, "KugelArena", Vector2(30, 16), 34, COL_TEXT)
	_label(menu_panel, "Pick your opponent", Vector2(30, 66), 18, COL_DIM)
	var x := 30.0
	for tier: String in ["All", "Easy", "Medium", "Hard"]:
		var b := _button(menu_panel, tier, Rect2(x, 104, 100, 30),
			_set_tier.bind("" if tier == "All" else tier))
		b.toggle_mode = true
		tier_buttons.append(b)
		x += 108.0
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(30, 146)
	scroll.size = Vector2(474, 440)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	menu_panel.add_child(scroll)
	card_box = VBoxContainer.new()
	card_box.add_theme_constant_override("separation", 6)
	scroll.add_child(card_box)
	detail_name = _label(menu_panel, "", Vector2(530, 146), 26, COL_TEXT)
	detail_pips = Pips.new()
	detail_pips.position = Vector2(530, 192)
	detail_pips.size = Vector2(110, 20)
	menu_panel.add_child(detail_pips)
	detail_line = _label(menu_panel, "", Vector2(646, 190), 14, COL_DIM)
	detail_text = _label(menu_panel, "", Vector2(530, 232), 15, COL_TEXT)
	detail_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_text.size = Vector2(340, 150)
	detail_small = _label(menu_panel, "", Vector2(530, 376), 12, COL_DIM)
	var bx := 530.0
	for count: int in BALL_CHOICES:
		var cb := _button(menu_panel, "Duel" if count == 2 else "%d balls" % count,
			Rect2(bx, 420, 80, 34), _set_ball_count.bind(count))
		cb.toggle_mode = true
		cb.tooltip_text = "One against one." if count == 2 else \
			"Free-for-all: %d balls, the last one on the disc wins.\nThe other balls are nets from the list." % count
		count_buttons.append(cb)
		bx += 87.0
	_set_ball_count(ball_count)
	_button(menu_panel, "Play with friends", Rect2(690, 22, 180, 38), _open_friends).tooltip_text = \
		"Host a game and invite Steam friends, or join a friend's game."
	_button(menu_panel, "Play   (Enter)", Rect2(530, 470, 340, 52), _menu_play)
	_button(menu_panel, "Just watch the nets fight   (Space)", Rect2(530, 532, 340, 40),
		_start_review)
	_label(menu_panel, "Up / Down: choose     Esc: quit", Vector2(530, 584), 12, COL_DIM)
	_set_tier("")
	update_label = _label(menu_panel, "", Vector2(30, 588), 12, Color(1.0, 0.78, 0.2))
	_check_for_update()

	# Replay controls, right column.
	review_box = Control.new()
	review_box.position = Vector2(985, 250)
	add_child(review_box)
	_label(review_box, "BEST FIGHTS FROM TRAINING", Vector2(0, 0), 12, COL_DIM)
	battle_list = ItemList.new()
	battle_list.position = Vector2(0, 22)
	battle_list.size = Vector2(285, 196)
	battle_list.focus_mode = Control.FOCUS_NONE
	battle_list.add_theme_font_size_override("font_size", 12)
	for b: Dictionary in battles:
		var game: Dictionary = b["game"]
		var stats: Dictionary = game.get("stats", {})
		var players: Array = game["players"]
		if players.size() == 2:
			battle_list.add_item("%s  vs  %s" % [_friendly(str(players[0]), b["run"]),
				_friendly(str(players[1]), b["run"])])
		else:
			battle_list.add_item("Free-for-all, %d balls  (%s)" % [players.size(),
				_friendly(str(players[0]), b["run"])])
		battle_list.set_item_tooltip(battle_list.item_count - 1,
			"%d seconds, %d collisions, the lead changed %d times.\nFrom training run '%s'." % [
			int(game["seconds"]), int(stats.get("hits", 0)), int(stats.get("lead_changes", 0)),
			b["run"]])
	battle_list.item_selected.connect(func(index: int) -> void: _load_battle(index))
	review_box.add_child(battle_list)
	_button(review_box, "|<", Rect2(0, 228, 52, 34), func() -> void: _load_battle(battle_index - 1))
	_button(review_box, "<<", Rect2(58, 228, 52, 34), func() -> void: _seek(replay_t - SEEK_SECONDS))
	play_button = _button(review_box, "Pause", Rect2(116, 228, 62, 34), _toggle_replay)
	_button(review_box, ">>", Rect2(184, 228, 46, 34), func() -> void: _seek(replay_t + SEEK_SECONDS))
	_button(review_box, ">|", Rect2(236, 228, 49, 34), func() -> void: _load_battle(battle_index + 1))
	timeline = HSlider.new()
	timeline.position = Vector2(0, 270)
	timeline.size = Vector2(285, 20)
	timeline.step = 0.05
	timeline.focus_mode = Control.FOCUS_NONE
	timeline.value_changed.connect(func(value: float) -> void: _seek(value))
	review_box.add_child(timeline)
	speed_button = _button(review_box, "Speed 1x", Rect2(0, 318, 110, 30),
		func() -> void: _set_speed((speed_index + 1) % SPEEDS.size()))
	_button(review_box, "Live: net vs net", Rect2(0, 362, 285, 32),
		func() -> void: _start_live(MODE_LIVE))
	_button(review_box, "Choose a net and play   (M)", Rect2(0, 400, 285, 32),
		func() -> void: _set_mode(MODE_MENU))

	menu_button = _button(self, "Menu  (M)", Rect2(1090, 630, 120, 32),
		func() -> void: _set_mode(MODE_MENU))


## Asks GitHub for the newest release and says so in the menu when it is newer
## than this build. Nothing is downloaded; the player fetches the zip themselves.
func _check_for_update() -> void:
	var request := HTTPRequest.new()
	request.timeout = 8.0
	add_child(request)
	request.request_completed.connect(func(_result: int, code: int, _headers: PackedStringArray,
			body: PackedByteArray) -> void:
		request.queue_free()
		if code != 200:
			return
		var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
		if typeof(parsed) != TYPE_DICTIONARY:
			return
		var latest := str((parsed as Dictionary).get("tag_name", "")).trim_prefix("v")
		if latest != "" and _version_number(latest) > _version_number(VERSION):
			update_label.text = "Version %s is out (you have %s). Download: %s" % [latest, VERSION,
				DOWNLOAD_PAGE])
	request.request(RELEASES_API, ["User-Agent: KugelArena"])


func _version_number(text: String) -> float:
	var parts := text.split(".")
	var value := 0.0
	for i in mini(parts.size(), 3):
		value += float(parts[i].to_int()) / pow(1000.0, i)
	return value


## Shows the opponents of one difficulty ("" = all) as cards.
func _set_tier(tier: String) -> void:
	for i in tier_buttons.size():
		(tier_buttons[i] as Button).button_pressed = ["", "Easy", "Medium", "Hard"][i] == tier
	for card: Node in cards:
		card.queue_free()
	cards.clear()
	shown.clear()
	for i in opponents.size():
		var o: Dictionary = opponents[i]
		var profile: Dictionary = o["profile"]
		if tier != "" and Profile.difficulty(profile) != tier:
			continue
		var card := OpponentCard.new()
		card.custom_minimum_size = Vector2(456, 60)
		card.focus_mode = Control.FOCUS_NONE
		card.toggle_mode = true
		card.title = o["name"]
		card.line = Profile.tagline(profile)
		card.stars = Profile.stars(profile)
		card.age = "age %d" % int(o["generation"])
		if float(o["score"]) >= 0.0:
			card.numbers = "Duel %d %%    FFA %d %%" % [int(round(100.0 * float(o["duel"]))),
				int(round(100.0 * float(o["ffa"])))]
		card.dot = Color.from_hsv(fmod(0.58 + int(o["run_index"]) * 0.137, 1.0), 0.55, 0.95)
		card.tooltip_text = "%s\n%s" % [o["name"], Profile.description(profile)]
		card.pressed.connect(_select_opponent.bind(i))
		card_box.add_child(card)
		cards.append(card)
		shown.append(i)
	if not shown.is_empty():
		_select_opponent(opponent_index if opponent_index in shown else shown[0])
	else:
		detail_name.text = "Nobody here"
		detail_pips.visible = false
		detail_line.text = ""
		detail_small.text = ""
		detail_text.text = "No opponent of this difficulty yet." if not opponents.is_empty() \
			else "No trained net yet. Train one with train.ps1 - until then a simple practice bot plays."


func _select_opponent(index: int) -> void:
	opponent_index = index
	for k in cards.size():
		(cards[k] as Button).button_pressed = shown[k] == index
	var o: Dictionary = opponents[index]
	var profile: Dictionary = o["profile"]
	detail_name.text = o["name"]
	detail_pips.visible = true
	detail_pips.count = Profile.stars(profile)
	detail_pips.queue_redraw()
	detail_line.text = Profile.difficulty(profile)
	detail_text.text = Profile.description(profile)
	var numbers := ""
	if float(o["score"]) >= 0.0:
		numbers = "Against the practice bots: wins %d %% of duels, %d %% of four-ball free-for-alls\n" % [
			int(round(100.0 * float(o["duel"]))), int(round(100.0 * float(o["ffa"])))]
	detail_small.text = numbers + "Training age %d" % int(o["generation"]) + \
		("" if o["run"] == "" else "   -   family '%s'" % o["run"])


func _set_ball_count(count: int) -> void:
	ball_count = count
	for i in count_buttons.size():
		(count_buttons[i] as Button).button_pressed = BALL_CHOICES[i] == count


## Moves the selection up or down among the cards shown.
func _step_opponent(step: int) -> void:
	var at := shown.find(opponent_index)
	if at >= 0:
		_select_opponent(shown[clampi(at + step, 0, shown.size() - 1)])
		var scroll := card_box.get_parent() as ScrollContainer
		scroll.ensure_control_visible(cards[shown.find(opponent_index)])


func _set_mode(new_mode: int) -> void:
	mode = new_mode
	menu_panel.visible = mode == MODE_MENU
	review_box.visible = mode == MODE_REVIEW
	menu_button.visible = mode == MODE_PLAY or mode == MODE_LIVE
	friends_panel.visible = mode == MODE_FRIENDS
	lobby_panel.visible = mode == MODE_LOBBY
	if mode == MODE_LOBBY:
		_refresh_lobby()
	if mode == MODE_MENU or mode == MODE_REVIEW:
		# Leaving to the menu ends a multiplayer game.
		if net.active:
			net.leave()
		net_role = ""
		lineup_key = ""
	if mode == MODE_MENU or mode == MODE_FRIENDS or mode == MODE_LOBBY:
		sim.reset(1)
		flashes.clear()
		texts.clear()
		state = STATE_READY
	queue_redraw()


func _menu_play() -> void:
	_start_live(MODE_PLAY)


# ------------------------------------------------------------------------------
# Live rounds (PLAY and LIVE)
# ------------------------------------------------------------------------------

func _start_live(new_mode: int) -> void:
	_set_mode(new_mode)
	_build_lineup()
	_new_round()


## Decides who steers which ball. Humans come first: you when playing alone, or
## every player of the multiplayer game (the host is ball 0). The remaining
## balls go to nets: the chosen one first, then others from the list at random.
func _build_lineup() -> void:
	seat_brains.clear()
	seat_names.clear()
	seat_peer.clear()
	var humans := []   # [peer id, name]; peer 0 = this window when playing alone
	if net_role == "host":
		var ids := net.players.keys()
		ids.sort()
		for id: int in ids:
			humans.append([id, str(net.players[id])])
		ball_count = int(net.settings.get("balls", 2))
		while ball_count < humans.size():
			ball_count = mini(Sim.MAX_BALLS, ball_count + 2)
	elif mode == MODE_PLAY:
		humans.append([0, "You"])
	my_seat = -1
	var pool: Array = range(opponents.size())
	pool.erase(opponent_index)
	pool.shuffle()
	var chosen_seat := maxi(humans.size(), 1)
	for i in ball_count:
		if i < humans.size():
			seat_brains.append(null)
			seat_names.append(humans[i][1])
			seat_peer.append(int(humans[i][0]) if int(humans[i][0]) > 1 else 0)
			if int(humans[i][0]) <= 1:
				my_seat = i
			continue
		var pick := -1
		if not opponents.is_empty():
			pick = opponent_index if i == chosen_seat or pool.is_empty() else int(pool.pop_back())
		seat_brains.append(_brain(pick))
		seat_peer.append(0)
		var label := "Practice bot"
		if pick >= 0:
			label = str(opponents[pick]["name"])
			if mode == MODE_LIVE or ball_count > 2:
				label += " (age %d)" % int(opponents[pick]["generation"])
		seat_names.append(label)
	score.clear()
	score.resize(ball_count)
	score.fill(0)
	draws = 0


func _brain(index: int) -> RefCounted:
	if index >= 0:
		var brain := Net.new()
		if brain.load_weights(opponents[index]["path"]):
			return brain
	return Bot.standard(randi())


func _new_round() -> void:
	if net_role == "host":
		# Players may have joined or left, or the host changed the number of balls.
		var key := "%s %s" % [net.players.keys(), net.settings]
		if key != lineup_key:
			lineup_key = key
			_build_lineup()
		net.inputs.clear()
	round_seed = randi()
	sim.reset(round_seed, 0.0, ball_count)
	var names := []
	for i in ball_count:
		names.append("human" if seat_brains[i] == null else seat_names[i])
	recorder.begin(round_seed, names)
	fall_time.resize(ball_count)
	fall_time.fill(-1.0)
	flashes.clear()
	texts.clear()
	state = STATE_READY
	state_time = 0.0
	if net_role == "host":
		var peers := [1]   # who steers each ball, as the clients need it
		peers.resize(ball_count)
		for i in ball_count:
			peers[i] = seat_peer[i] if seat_peer[i] > 1 else (1 if i == my_seat else 0)
		net.send_round_start({"balls": ball_count, "names": seat_names, "peers": peers,
			"item_slots": sim.item_kind.size(), "score": score, "draws": draws,
			"zones": _zones_as_list()})


## Dodge in the direction of the keys held (or the way the ball is moving).
func _dodge() -> void:
	if net_role == "client":
		net.send_dash(_player_thrust())
	else:
		sim.dash(my_seat, _player_thrust())


func _player_thrust() -> Vector2:
	var t := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		t.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		t.x += 1.0
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		t.y -= 1.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		t.y += 1.0
	return t.normalized()


func _live_step(_delta: float) -> void:
	if state == STATE_READY:
		if state_time >= READY_SECONDS:
			state = STATE_PLAYING
			state_time = 0.0
	elif state == STATE_PLAYING:
		if my_seat >= 0 and sim.alive[my_seat] == 1:
			sim.set_thrust(my_seat, _player_thrust())
		for i in sim.n:
			if seat_peer[i] > 1 and sim.alive[i] == 1:
				sim.set_thrust(i, net.inputs.get(seat_peer[i], Vector2.ZERO))
				if net.dashes.has(seat_peer[i]):
					sim.dash(i, net.dashes[seat_peer[i]])
		if net_role == "host":
			net.dashes.clear()
		if sim.tick % Sim.DECISION_TICKS == 0:
			for i in sim.n:
				if sim.alive[i] == 1 and seat_brains[i] != null:
					sim.set_thrust(i, seat_brains[i].act(sim, i))
			recorder.capture(sim)
		sim.step()
		recorder.note_events(sim)
		if net_role == "host":
			var list := []
			for e: Dictionary in sim.events:
				var at: Vector2 = e["at"]
				match e["type"]:
					"hit":
						list.append(["hit", at.x, at.y, e["strength"]])
					"pickup":
						list.append(["pickup", at.x, at.y, e["who"], e["kind"]])
					"fall":
						list.append(["fall", at.x, at.y, e["who"]])
					"dash":
						list.append(["dash", at.x, at.y, e["who"]])
			if not list.is_empty():
				net.send_events(list)
			if sim.tick % STATE_SEND_TICKS == 0 or sim.result != Sim.RUNNING:
				net.send_state(_pack_state())
		_show_events(sim.events)
		sim.events.clear()
		if sim.result != Sim.RUNNING:
			state = STATE_OVER
			state_time = 0.0
			Recorder.append(record_path, recorder.finish(sim))
			if sim.result >= 0:
				score[sim.result] += 1
			else:
				draws += 1
			if net_role == "host":
				net.send_round_over({"result": sim.result, "score": score, "draws": draws})
	elif state == STATE_OVER and mode == MODE_LIVE and state_time > 3.0:
		_new_round()  # live mode keeps playing by itself


## Shows what happened on the disc: flashes for hits, texts for pickups and falls.
func _show_events(events: Array) -> void:
	for e: Dictionary in events:
		match e["type"]:
			"hit":
				flashes.append({"at": e["at"], "age": 0.0, "strength": e["strength"]})
			"pickup":
				var kind: int = e["kind"]
				texts.append({"at": e["at"], "age": 0.0, "text": Sim.ITEM_NAMES[kind] + "!",
					"color": COL_ITEM[kind]})
			"dash":
				flashes.append({"at": e["at"], "age": 0.0, "strength": 2.5})
			"fall":
				var who: int = e["who"]
				if who < fall_time.size():
					fall_time[who] = 0.0
				if sim.n > 2 and who < seat_names.size():
					texts.append({"at": e["at"], "age": 0.0, "text": seat_names[who] + " is out",
						"color": COL_BALL[who]})


# ------------------------------------------------------------------------------
# Multiplayer (see game/net_game.gd)
# ------------------------------------------------------------------------------

func _build_net_controls() -> void:
	var style: StyleBox = menu_panel.get_theme_stylebox("panel")

	# Host or join.
	friends_panel = Panel.new()
	friends_panel.position = Vector2(290, 90)
	friends_panel.size = Vector2(700, 540)
	friends_panel.add_theme_stylebox_override("panel", style)
	friends_panel.visible = false
	add_child(friends_panel)
	_label(friends_panel, "Play with friends", Vector2(30, 18), 30, COL_TEXT)
	friends_status = _label(friends_panel, "", Vector2(30, 64), 13, COL_DIM)
	friends_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	friends_status.size = Vector2(640, 40)
	_button(friends_panel, "Host a game and invite friends", Rect2(30, 116, 640, 48),
		func() -> void: net.host_steam())
	_label(friends_panel, "Friends who are hosting right now", Vector2(30, 184), 14, COL_DIM)
	friends_list = ItemList.new()
	friends_list.position = Vector2(30, 210)
	friends_list.size = Vector2(470, 120)
	friends_list.focus_mode = Control.FOCUS_NONE
	friends_panel.add_child(friends_list)
	_button(friends_panel, "Join", Rect2(512, 210, 158, 40), _join_selected_friend)
	_button(friends_panel, "Refresh", Rect2(512, 258, 158, 34), _refresh_friends)
	code_edit = LineEdit.new()
	code_edit.position = Vector2(30, 338)
	code_edit.size = Vector2(470, 36)
	code_edit.placeholder_text = "or paste the lobby code the host sent you"
	friends_panel.add_child(code_edit)
	_button(friends_panel, "Join with code", Rect2(512, 338, 158, 36), _join_code)
	_label(friends_panel, "A Steam invite also works, as long as this game is already running when you accept it.",
		Vector2(30, 380), 12, COL_DIM)
	_label(friends_panel, "Without Steam (same network, or a forwarded port %d)" % NetGame.DEFAULT_PORT,
		Vector2(30, 410), 14, COL_DIM)
	_button(friends_panel, "Host on this PC", Rect2(30, 436, 200, 40), func() -> void: net.host_lan())
	address_edit = LineEdit.new()
	address_edit.position = Vector2(250, 436)
	address_edit.size = Vector2(250, 40)
	address_edit.placeholder_text = "host's address, e.g. 192.168.0.12"
	friends_panel.add_child(address_edit)
	_button(friends_panel, "Join address", Rect2(512, 436, 158, 40),
		func() -> void: net.join_lan(address_edit.text if address_edit.text != "" else "127.0.0.1"))
	_button(friends_panel, "Back   (Esc)", Rect2(30, 490, 200, 38), func() -> void: _set_mode(MODE_MENU))

	# Lobby.
	lobby_panel = Panel.new()
	lobby_panel.position = Vector2(290, 70)
	lobby_panel.size = Vector2(700, 580)
	lobby_panel.add_theme_stylebox_override("panel", style)
	lobby_panel.visible = false
	add_child(lobby_panel)
	_label(lobby_panel, "Game lobby", Vector2(30, 18), 30, COL_TEXT)
	lobby_status = _label(lobby_panel, "", Vector2(30, 64), 13, COL_DIM)
	lobby_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lobby_status.size = Vector2(640, 40)
	_label(lobby_panel, "PLAYERS", Vector2(30, 116), 12, COL_DIM)
	lobby_players = _label(lobby_panel, "", Vector2(30, 138), 16, COL_TEXT)
	_label(lobby_panel, "ROUND", Vector2(360, 116), 12, COL_DIM)
	var bx := 360.0
	for count: int in BALL_CHOICES:
		var cb := _button(lobby_panel, "Duel" if count == 2 else "%d balls" % count,
			Rect2(bx, 138, 74, 34), func() -> void: net.set_setting("balls", count))
		cb.toggle_mode = true
		lobby_counts.append(cb)
		bx += 79.0
	_label(lobby_panel, "Balls without a player are steered by nets.
With more players than balls the round grows.",
		Vector2(360, 180), 12, COL_DIM)
	_label(lobby_panel, "INVITE STEAM FRIENDS (ONLINE NOW)", Vector2(360, 240), 12, COL_DIM)
	lobby_invites = ItemList.new()
	lobby_invites.position = Vector2(360, 262)
	lobby_invites.size = Vector2(310, 190)
	lobby_invites.focus_mode = Control.FOCUS_NONE
	lobby_panel.add_child(lobby_invites)
	lobby_invite_button = _button(lobby_panel, "Invite selected friend", Rect2(360, 460, 310, 36), _invite_selected)
	lobby_code = _label(lobby_panel, "", Vector2(30, 410), 13, COL_TEXT)
	lobby_copy = _button(lobby_panel, "Copy lobby code", Rect2(30, 460, 200, 36), _copy_lobby_code)
	lobby_start = _button(lobby_panel, "Start the game", Rect2(30, 516, 320, 46), _host_start)
	_button(lobby_panel, "Leave   (Esc)", Rect2(470, 516, 200, 46), func() -> void: _set_mode(MODE_MENU))


func _open_friends() -> void:
	_set_mode(MODE_FRIENDS)
	net.init_steam()
	friends_status.text = net.status
	_refresh_friends()


func _refresh_friends() -> void:
	if mode == MODE_LOBBY:
		_refresh_lobby()
	if mode != MODE_FRIENDS:
		return
	friends_list.clear()
	friends_ids.clear()
	for f: Dictionary in net.friends():
		if int(f["lobby"]) != 0:
			friends_list.add_item(str(f["name"]))
			friends_ids.append(int(f["lobby"]))
	if friends_ids.is_empty():
		friends_list.add_item("(nobody is hosting right now)")
		friends_list.set_item_disabled(0, true)


func _join_code() -> void:
	var digits := ""
	for c in code_edit.text:
		if c >= "0" and c <= "9":
			digits += c
	if digits.length() < 6:
		friends_status.text = "That does not look like a lobby code. The host finds it in the lobby (Copy lobby code)."
		return
	net.join_steam(digits.to_int())


func _copy_lobby_code() -> void:
	DisplayServer.clipboard_set(str(net.lobby_id))
	lobby_status.text = "Lobby code copied. Send it to your friend; they paste it under Play with friends."


func _join_selected_friend() -> void:
	var picked := friends_list.get_selected_items()
	if not picked.is_empty() and picked[0] < friends_ids.size():
		net.join_steam(friends_ids[picked[0]])


func _refresh_lobby() -> void:
	if lobby_panel == null or mode != MODE_LOBBY:
		return
	lobby_status.text = net.status
	var lines := PackedStringArray()
	var ids := net.players.keys()
	ids.sort()
	for id: int in ids:
		lines.append("%s%s" % [str(net.players[id]), "   (host)" if id == 1 else ""])
	lobby_players.text = "\n".join(lines) if not lines.is_empty() else "connecting ..."
	var balls := int(net.settings.get("balls", 2))
	for i in lobby_counts.size():
		var b: Button = lobby_counts[i]
		b.button_pressed = BALL_CHOICES[i] == balls
		b.disabled = not net.hosting
	lobby_start.visible = net.hosting
	var can_invite: bool = net.hosting and net.via_steam
	lobby_invites.visible = can_invite
	lobby_invite_button.visible = can_invite
	lobby_copy.visible = can_invite
	lobby_code.visible = can_invite
	lobby_code.text = "Lobby code, if the invite does not work:\n%d" % net.lobby_id
	if can_invite:
		var keep := lobby_invites.get_selected_items()
		lobby_invites.clear()
		lobby_invite_ids.clear()
		for f: Dictionary in net.friends():
			lobby_invites.add_item(str(f["name"]))
			lobby_invite_ids.append(int(f["id"]))
		if not keep.is_empty() and keep[0] < lobby_invites.item_count:
			lobby_invites.select(keep[0])


func _invite_selected() -> void:
	var picked := lobby_invites.get_selected_items()
	if not picked.is_empty():
		net.invite(lobby_invite_ids[picked[0]])
		lobby_status.text = "Invite sent to %s. Their KugelArena must already be running when they accept it." % \
			lobby_invites.get_item_text(picked[0])


func _host_start() -> void:
	net_role = "host"
	lineup_key = ""
	_start_live(MODE_PLAY)


func _on_net_closed(reason: String) -> void:
	net_role = ""
	_set_mode(MODE_FRIENDS)
	friends_status.text = reason
	_refresh_friends()


## Everything a client needs to draw the disc, as one flat list of numbers.
func _pack_state() -> PackedFloat32Array:
	var data := PackedFloat32Array([sim.tick, sim.radius, sim.result, sim.n, sim.item_kind.size()])
	for i in sim.n:
		data.append_array(PackedFloat32Array([sim.pos[i].x, sim.pos[i].y, sim.vel[i].x, sim.vel[i].y,
			sim.alive[i], sim.place[i]]))
	for s in sim.item_kind.size():
		data.append_array(PackedFloat32Array([sim.item_kind[s], sim.item_pos[s].x, sim.item_pos[s].y]))
	data.append_array(sim.fx)
	data.append_array(sim.dash_cd)
	return data


## The round's obstacles and zones as [kind, x, y, radius, wind x, wind y] each.
func _zones_as_list() -> Array:
	var list := []
	for z in sim.zone_kind.size():
		list.append([sim.zone_kind[z], sim.zone_pos[z].x, sim.zone_pos[z].y, sim.zone_radius[z],
			sim.zone_dir[z].x, sim.zone_dir[z].y])
	return list


## Replaces the sim's obstacles and zones (for a replay or a joined game).
func _set_zones(list: Array) -> void:
	sim.zone_kind.clear()
	sim.zone_pos.clear()
	sim.zone_radius.clear()
	sim.zone_dir.clear()
	for z: Array in list:
		sim.zone_kind.append(int(z[0]))
		sim.zone_pos.append(Vector2(z[1], z[2]))
		sim.zone_radius.append(float(z[3]))
		sim.zone_dir.append(Vector2(z[4], z[5]))


# --- what a client does with the host's messages -------------------------------

func _on_net_round_start(info: Dictionary) -> void:
	net_role = "client"
	_set_mode(MODE_PLAY)
	ball_count = int(info["balls"])
	sim.reset(1, 0.0, ball_count)
	sim.item_kind.resize(int(info["item_slots"]))
	sim.item_pos.resize(sim.item_kind.size())
	_set_zones(info.get("zones", []))
	seat_names.clear()
	seat_brains.clear()
	seat_peer.clear()
	my_seat = -1
	for i in ball_count:
		seat_names.append(str(info["names"][i]))
		seat_brains.append(null)
		seat_peer.append(int(info["peers"][i]))
		if int(info["peers"][i]) == net.my_id():
			my_seat = i
	score.clear()
	for value: int in info["score"]:
		score.append(value)
	draws = int(info["draws"])
	fall_time.resize(ball_count)
	fall_time.fill(-1.0)
	flashes.clear()
	texts.clear()
	state = STATE_READY
	state_time = 0.0


func _on_net_state(data: PackedFloat32Array) -> void:
	if net_role != "client" or data.size() < 5 or int(data[3]) != sim.n \
			or int(data[4]) != sim.item_kind.size():
		return
	sim.tick = int(data[0])
	sim.radius = data[1]
	var at := 5
	for i in sim.n:
		sim.pos[i] = Vector2(data[at], data[at + 1])
		sim.vel[i] = Vector2(data[at + 2], data[at + 3])
		sim.alive[i] = int(data[at + 4])
		sim.place[i] = int(data[at + 5])
		at += 6
	for s in sim.item_kind.size():
		sim.item_kind[s] = int(data[at])
		sim.item_pos[s] = Vector2(data[at + 1], data[at + 2])
		at += 3
	for k in sim.fx.size():
		sim.fx[k] = data[at + k]
	at += sim.fx.size()
	if data.size() >= at + sim.n:
		for i in sim.n:
			sim.dash_cd[i] = data[at + i]
	if state == STATE_READY:
		state = STATE_PLAYING
		state_time = 0.0


func _on_net_events(list: Array) -> void:
	if net_role != "client":
		return
	var events := []
	for e: Array in list:
		var at := Vector2(e[1], e[2])
		match e[0]:
			"hit":
				events.append({"type": "hit", "at": at, "strength": float(e[3])})
			"pickup":
				events.append({"type": "pickup", "at": at, "who": int(e[3]), "kind": int(e[4])})
			"fall":
				events.append({"type": "fall", "at": at, "who": int(e[3])})
			"dash":
				events.append({"type": "dash", "at": at, "who": int(e[3])})
	_show_events(events)


func _on_net_round_over(info: Dictionary) -> void:
	if net_role != "client":
		return
	sim.result = int(info["result"])
	score.clear()
	for value: int in info["score"]:
		score.append(value)
	draws = int(info["draws"])
	state = STATE_OVER
	state_time = 0.0


## A client's frame: send the keys, and keep the balls moving between two
## messages from the host.
func _client_step(delta: float) -> void:
	if state == STATE_OVER:
		return
	if my_seat >= 0:
		net.send_input(_player_thrust())
	if state == STATE_PLAYING:
		for i in sim.n:
			if sim.alive[i] == 1:
				sim.pos[i] += sim.vel[i] * delta


# ------------------------------------------------------------------------------
# Replays (REVIEW)
# ------------------------------------------------------------------------------

func _start_review() -> void:
	my_seat = -1
	if battles.is_empty():
		# Nothing recorded yet: show a live fight instead.
		_start_live(MODE_LIVE)
		return
	_set_mode(MODE_REVIEW)
	_load_battle(battle_index)


func _load_battle(index: int) -> void:
	if battles.is_empty():
		return
	battle_index = posmod(index, battles.size())
	replay = battles[battle_index]["game"]
	replay_len = float(replay["seconds"])
	sim.reset(1, 0.0, int(replay.get("n", 2)))
	sim.item_kind.resize(int(replay.get("item_slots", 2)))
	sim.item_pos.resize(sim.item_kind.size())
	_set_zones(replay.get("zones", []))
	fall_time.resize(sim.n)
	fall_time.fill(-1.0)
	timeline.max_value = replay_len
	battle_list.select(battle_index)
	battle_list.ensure_current_is_visible()
	flashes.clear()
	texts.clear()
	replay_playing = true
	play_button.text = "Pause"
	_seek(0.0)


func _toggle_replay() -> void:
	if replay_t >= replay_len:
		_seek(0.0)
		replay_playing = true
	else:
		replay_playing = not replay_playing
	play_button.text = "Pause" if replay_playing else "Play"


func _set_speed(index: int) -> void:
	speed_index = clampi(index, 0, SPEEDS.size() - 1)
	speed_button.text = "Speed %sx" % str(SPEEDS[speed_index])


func _seek(t: float) -> void:
	replay_t = clampf(t, 0.0, replay_len)
	_show_replay_frame()


## Puts the recorded moment replay_t into `sim`, so the normal drawing shows it.
func _show_replay_frame() -> void:
	var rows: Array = replay.get("rows", [])
	if rows.is_empty():
		return
	var f := replay_t * float(replay.get("rows_per_second", 10))
	var i0 := clampi(int(floor(f)), 0, rows.size() - 1)
	var i1 := mini(i0 + 1, rows.size() - 1)
	var k := clampf(f - i0, 0.0, 1.0)
	var a: Array = rows[i0]
	var b: Array = rows[i1]
	var balls := sim.n
	for i in balls:
		var at := i * Recorder.PER_BALL
		sim.pos[i] = Vector2(a[at], a[at + 1]).lerp(Vector2(b[at], b[at + 1]), k)
		sim.vel[i] = Vector2(a[at + 2], a[at + 3])
		sim.alive[i] = int(a[at + 6])
	sim.radius = lerpf(float(a[Recorder.col_radius(balls)]), float(b[Recorder.col_radius(balls)]), k)
	for s in sim.item_kind.size():
		var at := Recorder.col_items(balls) + s * 3
		sim.item_kind[s] = int(a[at])
		sim.item_pos[s] = Vector2(a[at + 1], a[at + 2])
	var fx_at := Recorder.col_fx(balls, sim.item_kind.size())
	for j in sim.fx.size():
		sim.fx[j] = float(a[fx_at + j])
	sim.tick = int(replay_t * Sim.TICKS_PER_SECOND)
	timeline.set_value_no_signal(replay_t)
	if replay_t >= replay_len:
		if state != STATE_OVER:
			state = STATE_OVER
			state_time = 0.0
		var outcome := str(replay.get("result", ""))
		sim.result = int(outcome.trim_prefix("win_")) if outcome.begins_with("win_") else Sim.DRAW
		for i in balls:
			sim.alive[i] = 1 if i == sim.result else 0
	else:
		state = STATE_PLAYING
		sim.result = Sim.RUNNING


func _review_step(delta: float) -> void:
	if not replay_playing or replay.is_empty():
		return
	if replay_t >= replay_len:
		replay_playing = false
		play_button.text = "Replay"
		return
	var before := replay_t
	replay_t = minf(replay_len, replay_t + delta * SPEEDS[speed_index])
	for e: Array in replay.get("events", []):
		var t: float = e[0]
		if t <= before or t > replay_t:
			continue
		if e[1] == "hit":
			flashes.append({"at": Vector2(e[2], e[3]), "age": 0.0, "strength": float(e[4])})
		elif e[1] == "pickup":
			var kind := int(e[3])
			texts.append({"at": sim.pos[int(e[2])], "age": 0.0, "text": Sim.ITEM_NAMES[kind] + "!",
				"color": COL_ITEM[kind]})
	_show_replay_frame()


# ------------------------------------------------------------------------------
# Input and frame loop
# ------------------------------------------------------------------------------

func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed:
		return
	var code := key.physical_keycode
	if mode == MODE_REVIEW:
		# Held arrow keys keep rewinding / forwarding.
		if code == KEY_LEFT:
			_seek(replay_t - (0.5 if key.echo else SEEK_SECONDS))
			return
		if code == KEY_RIGHT:
			_seek(replay_t + (0.5 if key.echo else SEEK_SECONDS))
			return
	if key.echo:
		return
	if mode == MODE_FRIENDS or mode == MODE_LOBBY:
		if code == KEY_ESCAPE:
			_set_mode(MODE_MENU)
		return
	if mode == MODE_MENU:
		match code:
			KEY_ENTER, KEY_KP_ENTER:
				_menu_play()
			KEY_SPACE:
				_start_review()
			KEY_UP, KEY_W:
				_step_opponent(-1)
			KEY_DOWN, KEY_S:
				_step_opponent(1)
			KEY_ESCAPE:
				get_tree().quit()
		return
	if code == KEY_M or code == KEY_ESCAPE:
		_set_mode(MODE_MENU)
		return
	if mode == MODE_REVIEW:
		match code:
			KEY_SPACE:
				_toggle_replay()
			KEY_UP:
				_set_speed(speed_index + 1)
			KEY_DOWN:
				_set_speed(speed_index - 1)
			KEY_PAGEDOWN:
				_load_battle(battle_index + 1)
			KEY_PAGEUP:
				_load_battle(battle_index - 1)
			KEY_HOME:
				_seek(0.0)
		return
	if (code == KEY_SPACE or code == KEY_SHIFT) and mode == MODE_PLAY and state == STATE_PLAYING \
			and my_seat >= 0 and sim.alive[my_seat] == 1:
		_dodge()
		return
	if net_role == "client":
		return  # only the host starts rounds
	match code:
		KEY_SPACE, KEY_ENTER, KEY_KP_ENTER:
			# Playing alone also when you are out of a free-for-all that is still going on.
			if state == STATE_OVER or (net_role == "" and my_seat >= 0 and sim.alive[my_seat] == 0):
				_new_round()
		KEY_R:
			_new_round()
		KEY_N:
			if net_role == "":
				_start_live(MODE_LIVE if mode == MODE_PLAY else MODE_PLAY)


func _physics_process(delta: float) -> void:
	state_time += delta
	for f: Dictionary in flashes:
		f["age"] += delta
	for t: Dictionary in texts:
		t["age"] += delta
	flashes = flashes.filter(func(f: Dictionary) -> bool: return f["age"] < 0.35)
	texts = texts.filter(func(t: Dictionary) -> bool: return t["age"] < 1.2)
	for i in fall_time.size():
		if fall_time[i] >= 0.0:
			fall_time[i] += delta
	if mode == MODE_FRIENDS or mode == MODE_LOBBY:
		# Friends come and go; keep the lists current.
		refresh_timer += delta
		if refresh_timer >= 3.0:
			refresh_timer = 0.0
			_refresh_friends()
	if net_role == "client":
		if mode == MODE_PLAY:
			_client_step(delta)
	elif mode == MODE_PLAY or mode == MODE_LIVE:
		_live_step(delta)
	elif mode == MODE_REVIEW:
		_review_step(delta)
	queue_redraw()


# ------------------------------------------------------------------------------
# Drawing
# ------------------------------------------------------------------------------

func _to_screen(p: Vector2) -> Vector2:
	return CENTRE + p * PIXELS_PER_UNIT


func _draw() -> void:
	# Disc. The faint ring shows the original size once it has started to shrink.
	if sim.radius < Sim.ARENA_RADIUS - 0.01:
		draw_arc(CENTRE, Sim.ARENA_RADIUS * PIXELS_PER_UNIT, 0.0, TAU, 96,
			Color(COL_DISC_RIM, 0.15), 1.5, true)
	var disc_r := maxf(sim.radius * PIXELS_PER_UNIT, 0.5)
	draw_circle(CENTRE, disc_r, COL_DISC)
	draw_arc(CENTRE, disc_r * 0.5, 0.0, TAU, 64, Color(1, 1, 1, 0.04), 1.5, true)
	draw_circle(CENTRE, 3.0, Color(1, 1, 1, 0.08))
	var shrinking := sim.seconds() > Sim.SHRINK_START and sim.radius > Sim.MIN_RADIUS
	var rim := COL_DISC_RIM
	if shrinking:
		rim = COL_DISC_RIM.lerp(Color(1.0, 0.45, 0.3), 0.5 + 0.5 * sin(sim.seconds() * 8.0))
	draw_arc(CENTRE, disc_r, 0.0, TAU, 128, rim, 3.0, true)
	if mode == MODE_MENU or mode == MODE_FRIENDS or mode == MODE_LOBBY:
		return

	_draw_zones()

	for s in sim.item_kind.size():
		var kind := sim.item_kind[s]
		if kind < 0:
			continue
		var at := _to_screen(sim.item_pos[s])
		var r := Sim.ITEM_RADIUS * PIXELS_PER_UNIT
		draw_circle(at, r + 4.0, Color(COL_ITEM[kind], 0.18))
		draw_circle(at, r, COL_ITEM[kind])
		_text_centred(ITEM_LETTER[kind], at + Vector2(0, 6), 17, Color(0.08, 0.08, 0.12))

	var names := _ball_names()
	for i in sim.n:
		_draw_ball(i, names[i])

	for f: Dictionary in flashes:
		var k: float = f["age"] / 0.35
		draw_arc(_to_screen(f["at"]), 10.0 + 60.0 * k * clampf(f["strength"] / 8.0, 0.4, 1.5),
			0.0, TAU, 32, Color(1, 1, 1, 0.7 * (1.0 - k)), 3.0, true)
	for t: Dictionary in texts:
		var k: float = t["age"] / 1.2
		_text_centred(t["text"], _to_screen(t["at"]) + Vector2(0, -24.0 - 30.0 * k), 20,
			Color(t["color"], 1.0 - k))

	_draw_hud(names)


## Obstacles and zones: patches first, then holes, then the solid things.
func _draw_zones() -> void:
	for layer in 3:
		for z in sim.zone_kind.size():
			var kind := sim.zone_kind[z]
			# A zone is gone once the shrinking disc has passed its centre.
			if kind < 0 or sim.zone_pos[z].length() > sim.radius:
				continue
			var its_layer := 0 if kind >= Sim.ZONE_ICE else (1 if kind == Sim.ZONE_HOLE else 2)
			if its_layer != layer:
				continue
			var at := _to_screen(sim.zone_pos[z])
			var r := sim.zone_radius[z] * PIXELS_PER_UNIT
			var colour := ZONE_COLOR[kind]
			match kind:
				Sim.ZONE_ICE:
					draw_circle(at, r, Color(colour, 0.22))
					draw_arc(at, r, 0.0, TAU, 48, Color(colour, 0.5), 1.5, true)
					draw_line(at + Vector2(-r * 0.4, -r * 0.2), at + Vector2(r * 0.1, -r * 0.5), Color(1, 1, 1, 0.3), 1.5, true)
					draw_line(at + Vector2(-r * 0.1, r * 0.4), at + Vector2(r * 0.45, r * 0.05), Color(1, 1, 1, 0.3), 1.5, true)
				Sim.ZONE_MUD:
					draw_circle(at, r, Color(colour, 0.4))
					draw_arc(at, r, 0.0, TAU, 48, Color(colour, 0.7), 1.5, true)
					for k in 5:
						draw_circle(at + Vector2.from_angle(k * 1.9 + z) * r * 0.5, 2.5, Color(colour, 0.8))
				Sim.ZONE_WIND:
					draw_circle(at, r, Color(colour, 0.06))
					draw_arc(at, r, 0.0, TAU, 48, Color(colour, 0.25), 1.0, true)
					# Chevrons drifting the way the wind blows.
					var dir := sim.zone_dir[z]
					var side := Vector2(-dir.y, dir.x)
					var drift := fmod(Time.get_ticks_msec() / 1000.0, 1.0)
					for k in 3:
						var along := (fmod(k / 3.0 + drift, 1.0) - 0.5) * 1.3 * r
						var fade := 1.0 - absf(along) / (0.65 * r)
						var tip := at + dir * (along + 7.0)
						draw_line(tip, tip - dir * 9.0 + side * 8.0, Color(colour, 0.6 * fade), 2.0, true)
						draw_line(tip, tip - dir * 9.0 - side * 8.0, Color(colour, 0.6 * fade), 2.0, true)
				Sim.ZONE_HOLE:
					draw_circle(at, r, colour)
					draw_arc(at, r, 0.0, TAU, 40, Color(1.0, 0.35, 0.3, 0.9), 2.0, true)
					draw_arc(at, r * 0.6, 0.0, TAU, 32, Color(1.0, 0.35, 0.3, 0.25), 1.0, true)
				Sim.ZONE_BLOCK:
					draw_circle(at, r, colour)
					draw_arc(at, r, 0.0, TAU, 48, Color(0.5, 0.54, 0.68), 2.5, true)
					draw_arc(at, r * 0.7, 0.0, TAU, 40, Color(0.5, 0.54, 0.68, 0.25), 1.0, true)
				_:
					draw_circle(at + Vector2(2, 3), r, Color(0, 0, 0, 0.3))
					draw_circle(at, r, colour)
					draw_circle(at - Vector2(r, r) * 0.3, r * 0.3, Color(1, 1, 1, 0.3))


## The name of every ball in the current game.
func _ball_names() -> Array[String]:
	var names: Array[String] = []
	for i in sim.n:
		if mode == MODE_REVIEW and not replay.is_empty():
			names.append(_friendly(str(replay["players"][i]), battles[battle_index]["run"]))
		elif i < seat_names.size():
			names.append(seat_names[i])
		else:
			names.append("")
	return names


func _draw_ball(i: int, ball_name: String) -> void:
	var scale_k := 1.0
	if sim.alive[i] == 0:
		# A ball that fell shrinks away; in a replay it is simply gone.
		if i >= fall_time.size() or fall_time[i] < 0.0:
			return
		scale_k = clampf(1.0 - fall_time[i] / FALL_SECONDS, 0.0, 1.0)
	if scale_k <= 0.0:
		return
	var at := _to_screen(sim.pos[i])
	var r := Sim.BALL_RADIUS * PIXELS_PER_UNIT * scale_k
	draw_circle(at + Vector2(3, 4), r, Color(0, 0, 0, 0.3 * scale_k))
	draw_circle(at, r, COL_BALL[i])
	draw_circle(at - Vector2(r, r) * 0.3, r * 0.3, Color(1, 1, 1, 0.25))
	# One arc per running effect; its length is the time left.
	var ring := r + 4.0
	for k in Sim.FX_COUNT:
		var left := sim.fx[i * Sim.FX_COUNT + k]
		if left <= 0.0:
			continue
		draw_arc(at, ring, -PI * 0.5, -PI * 0.5 + TAU * left / Sim.FX_DURATION[k], 40,
			FX_COLOR[k], 3.0, true)
		ring += 5.0
	if sim.n > 2 and sim.alive[i] == 1:
		# First name, plus the age when the name carries one.
		var short := ball_name.get_slice(" ", 0)
		if ball_name.contains("(age "):
			short += " " + ball_name.get_slice("(age ", 1).trim_suffix(")")
		_text_centred(short, at + Vector2(0, -r - 10.0), 12, Color(COL_BALL[i], 0.9))


func _draw_hud(names: Array[String]) -> void:
	var duel := sim.n == 2
	var review := mode == MODE_REVIEW
	# The left side shows the ball this window steers (ball 0 when only watching).
	var me := my_seat if my_seat >= 0 and my_seat < sim.n else 0
	var foe := 1 - me
	var playing := mode == MODE_PLAY and my_seat >= 0
	_text(names[me], Vector2(40, 60), 22, COL_BALL[me])
	if review:
		_draw_replay_info()
	else:
		_text(str(score[me]), Vector2(40, 130), 64, COL_TEXT)
		if playing:
			_text("W A S D  move      Space  dodge", Vector2(40, 170), 14, COL_DIM)
			# Dodge: full bar = ready.
			var ready := 1.0 - clampf(sim.dash_cd[me] / Sim.DASH_COOLDOWN, 0.0, 1.0)
			draw_rect(Rect2(40, 180, 200, 6), Color(1, 1, 1, 0.08))
			draw_rect(Rect2(40, 180, 200 * ready, 6), COL_BALL[me] if ready >= 1.0 else COL_DIM)
	_draw_effects(me, Vector2(40, 215))
	if duel:
		_text(names[foe], Vector2(985, 60), 20, COL_BALL[foe])
		if not review:
			_text(str(score[foe]), Vector2(985, 130), 64, COL_TEXT)
			if draws > 0:
				_text("draws: %d" % draws, Vector2(985, 170), 16, COL_DIM)
		_draw_effects(foe, Vector2(985, 100 if review else 215))
	else:
		# Free-for-all: everyone in a list, wins on the right.
		_text("FREE-FOR-ALL  -  last ball on the disc wins", Vector2(985, 40), 12, COL_DIM)
		for i in sim.n:
			var y := 68.0 + i * 22.0
			var on_disc := sim.alive[i] == 1
			draw_circle(Vector2(993, y - 5), 7.0, COL_BALL[i] if on_disc else Color(COL_BALL[i], 0.3))
			_text(names[i], Vector2(1008, y), 14, COL_TEXT if on_disc else COL_DIM)
			if not on_disc:
				_text("out", Vector2(1210, y), 12, COL_DIM)
			if not review:
				_text(str(score[i]), Vector2(1250, y), 14, COL_TEXT)

	_text_centred("%d s" % int(sim.seconds()), Vector2(CENTRE.x, 30), 18, COL_DIM)
	if sim.seconds() > Sim.SHRINK_START - 5.0 and sim.seconds() <= Sim.SHRINK_START \
			and state == STATE_PLAYING:
		_text_centred("The disc starts shrinking in %d" % int(ceil(Sim.SHRINK_START - sim.seconds())),
			Vector2(CENTRE.x, 30 + 22), 16, Color(1.0, 0.6, 0.4))
	var you_are_out := playing and state == STATE_PLAYING and sim.alive[me] == 0
	if you_are_out:
		_text_centred("You are out - place %d of %d.   %s" % [sim.place[me], sim.n,
			"Space: new round" if net_role == "" else "The round goes on without you."],
			Vector2(CENTRE.x, 700), 16, Color(1.0, 0.6, 0.4))

	# Field legend.
	_text("ON THE DISC", Vector2(40, 334), 12, COL_DIM)
	for k in Sim.ZONE_KINDS:
		var zy := 354.0 + k * 18.0
		draw_circle(Vector2(48, zy - 4), 6.0, Color(ZONE_COLOR[k], 1.0 if k <= Sim.ZONE_BLOCK else 0.7))
		if k == Sim.ZONE_HOLE or k == Sim.ZONE_BLOCK:
			draw_arc(Vector2(48, zy - 4), 6.0, 0.0, TAU, 16,
				Color(1.0, 0.35, 0.3) if k == Sim.ZONE_HOLE else Color(0.5, 0.54, 0.68), 1.5, true)
		_text("%s  -  %s" % [Sim.ZONE_NAMES[k], ZONE_HELP[k]], Vector2(62, zy), 12, COL_DIM)

	# Item legend.
	_text("ITEMS", Vector2(40, 470), 15, COL_DIM)
	for k in Sim.ITEM_KINDS:
		var y := 500.0 + k * 40.0
		draw_circle(Vector2(52, y - 5), 12.0, COL_ITEM[k])
		_text_centred(ITEM_LETTER[k], Vector2(52, y), 15, Color(0.08, 0.08, 0.12))
		_text(Sim.ITEM_NAMES[k], Vector2(74, y - 4), 15, COL_TEXT)
		_text(ITEM_HELP[k], Vector2(74, y + 13), 12, COL_DIM)

	if review:
		_text("Space play/pause   Left/Right rewind/forward   Up/Down speed   PgUp/PgDn battle   M menu",
			Vector2(40, 708), 12, COL_DIM)
	elif net_role != "":
		_text("Playing with friends (%s)     M  leave the game" % ("you host" if net_role == "host"
			else "you joined"), Vector2(40, 708), 12, COL_DIM)
	elif not you_are_out:
		_text("N  %s     R  new round     M  menu" % ("play yourself" if mode == MODE_LIVE
			else "watch the nets"), Vector2(40, 708), 12, COL_DIM)

	var winner := sim.result
	if review:
		if state == STATE_OVER:
			if winner >= 0:
				_banner(names[winner] + " wins", "PgDn: next battle     Space: watch again",
					COL_BALL[winner])
			else:
				_banner("Nobody wins", "PgDn: next battle     Space: watch again")
	elif state == STATE_READY:
		var sub := "Push the others off the disc. Touch the edge and you fall."
		if mode == MODE_LIVE:
			sub = "The nets play each other."
		elif not duel:
			sub = "%d balls. The last one on the disc wins." % sim.n
		_banner("Get ready", sub)
	elif state == STATE_OVER:
		var headline := "Nobody is left - draw"
		var colour := COL_TEXT
		if winner >= 0 and winner < names.size():
			colour = COL_BALL[winner]
			headline = names[winner] + " wins."
			if playing:
				if winner == me:
					headline = "You win!"
				elif duel:
					headline = "You fell off. %s wins." % names[winner].get_slice(" ", 0)
		var sub := "Next round starts by itself"
		if net_role == "client":
			sub = "Waiting for the host to start the next round"
		elif mode == MODE_PLAY:
			sub = "Space or Enter: play again"
		_banner(headline, sub)


func _draw_replay_info() -> void:
	var b: Dictionary = battles[battle_index]
	var stats: Dictionary = replay.get("stats", {})
	_text("Battle %d of %d" % [battle_index + 1, battles.size()], Vector2(40, 96), 16, COL_TEXT)
	_text("%d collisions" % int(stats.get("hits", 0)), Vector2(40, 120), 14, COL_DIM)
	_text("the lead changed %d times" % int(stats.get("lead_changes", 0)), Vector2(40, 140), 14, COL_DIM)
	_text("family '%s'" % b["run"], Vector2(40, 160), 12, COL_DIM)
	_text("%.1f / %.1f s      %sx" % [replay_t, replay_len, str(SPEEDS[speed_index])],
		Vector2(985, 250 + 308), 14, COL_TEXT)


func _draw_effects(who: int, at: Vector2) -> void:
	var y := at.y
	for k in Sim.FX_COUNT:
		var left := sim.fx[who * Sim.FX_COUNT + k]
		if left <= 0.0:
			continue
		_text(FX_NAME[k], Vector2(at.x, y), 15, FX_COLOR[k])
		draw_rect(Rect2(at.x, y + 6, 130, 5), Color(1, 1, 1, 0.08))
		draw_rect(Rect2(at.x, y + 6, 130 * left / Sim.FX_DURATION[k], 5), FX_COLOR[k])
		y += 27.0


func _banner(headline: String, sub: String, colour: Color = COL_TEXT) -> void:
	# Low on the disc, so it does not hide the balls in the middle.
	var y := CENTRE.y + 190.0
	draw_rect(Rect2(CENTRE.x - 330, y - 62, 660, 112), Color(0.03, 0.04, 0.07, 0.82))
	_text_centred(headline, Vector2(CENTRE.x, y - 12), 34, colour)
	_text_centred(sub, Vector2(CENTRE.x, y + 26), 17, COL_DIM)


func _text(text: String, at: Vector2, size: int, colour: Color) -> void:
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, colour)


func _text_centred(text: String, at: Vector2, size: int, colour: Color) -> void:
	draw_string(font, Vector2(at.x - 400, at.y), text, HORIZONTAL_ALIGNMENT_CENTER, 800, size, colour)
