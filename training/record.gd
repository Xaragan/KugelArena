extends SceneTree
## Plays headless games between two players and records every game as data.
##
##   godot --headless --path . --script res://training/record.gd -- [options]
##     --a=res://net/rival_net.json   player of ball 0: a net file, "bot" or "varied"
##     --b=res://net/rival_net.json   player of ball 1 (default: the same net, so
##                                    two rivals play each other)
##     --games=50
##     --seed=7000000                 first game seed
##     --out=res://recordings/...     default: a new file named after players and time

const Sim = preload("res://sim/arena_sim.gd")
const Net = preload("res://sim/net_policy.gd")
const Bot = preload("res://sim/scripted_bot.gd")
const Recorder = preload("res://sim/game_recorder.gd")
const TIME_LIMIT := 90.0


func _initialize() -> void:
	var opts := {"a": "res://net/rival_net.json", "b": "res://net/rival_net.json",
		"games": "50", "seed": "7000000", "out": ""}
	for arg in OS.get_cmdline_user_args():
		var parts := arg.trim_prefix("--").split("=", true, 1)
		if parts.size() == 2:
			opts[parts[0]] = parts[1]
	var names := [_label(opts["a"]), _label(opts["b"])]
	var nets := [null, null]
	for i in 2:
		var spec: String = opts["a" if i == 0 else "b"]
		if spec != "bot" and spec != "varied":
			var net := Net.new()
			if not net.load_weights(spec):
				printerr("Cannot load net: ", spec)
				quit(1)
				return
			nets[i] = net
	var out: String = opts["out"]
	if out == "":
		out = "res://recordings/%s_vs_%s_%s.jsonl" % [names[0], names[1],
			Time.get_datetime_string_from_system().replace(":", "-")]
	var sim := Sim.new()
	sim.record_events = true
	var recorder := Recorder.new()
	var tally := {}
	var games := int(opts["games"])
	for g in games:
		var game_seed := int(opts["seed"]) + g
		var players := []
		for i in 2:
			var spec: String = opts["a" if i == 0 else "b"]
			if nets[i] != null:
				players.append(nets[i])
			elif spec == "varied":
				players.append(Bot.varied(game_seed * 2 + i))
			else:
				players.append(Bot.standard(game_seed * 2 + i))
		sim.reset(game_seed, TIME_LIMIT)
		recorder.begin(game_seed, names)
		while sim.result == Sim.RUNNING:
			if sim.tick % Sim.DECISION_TICKS == 0:
				for i in 2:
					sim.set_thrust(i, players[i].act(sim, i))
				recorder.capture(sim)
			sim.step()
			recorder.note_events(sim)
			sim.events.clear()
		var game := recorder.finish(sim)
		Recorder.append(out, game)
		tally[game["result"]] = int(tally.get(game["result"], 0)) + 1
	print("Recorded %d games, %s (ball 0) against %s (ball 1): %s" % [games, names[0], names[1], tally])
	print("File: ", ProjectSettings.globalize_path(out))
	quit(0)


func _label(spec: String) -> String:
	if spec == "bot" or spec == "varied":
		return spec + "_bot"
	var info: Dictionary = Net.load_file(spec).get("info", {})
	return "net_gen%d" % int(info.get("generation", 0))
