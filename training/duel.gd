extends SceneTree
## Lets two nets play each other and counts who wins.
##
##   godot --headless --path . --script res://training/duel.gd -- --a=<net file> --b=<net file>
##     --games=1000    sides alternate, so neither net profits from its starting side
##     --seed=8000000  first game seed

const Sim = preload("res://sim/arena_sim.gd")
const Net = preload("res://sim/net_policy.gd")


func _initialize() -> void:
	var opts := {"a": "", "b": "", "games": "1000", "seed": "8000000"}
	for arg in OS.get_cmdline_user_args():
		var parts := arg.trim_prefix("--").split("=", true, 1)
		if parts.size() == 2:
			opts[parts[0]] = parts[1]
	var nets: Array[Net] = [Net.new(), Net.new()]
	for i in 2:
		var path: String = opts["a" if i == 0 else "b"]
		if not nets[i].load_weights(path):
			printerr("Cannot load net: ", path)
			quit(1)
			return
	var sim := Sim.new()
	var games := int(opts["games"])
	var wins := [0, 0]
	var draws := 0
	var seconds := 0.0
	for g in games:
		var a_side := g % 2
		sim.reset(int(opts["seed"]) + g, 90.0)
		while sim.result == Sim.RUNNING:
			if sim.tick % Sim.DECISION_TICKS == 0:
				sim.set_thrust(a_side, nets[0].act(sim, a_side))
				sim.set_thrust(1 - a_side, nets[1].act(sim, 1 - a_side))
			sim.step()
		seconds += sim.seconds()
		if sim.result == a_side:
			wins[0] += 1
		elif sim.result == 1 - a_side:
			wins[1] += 1
		else:
			draws += 1
	print("DUEL a=%s b=%s games=%d  a wins %d (%.1f%%)  b wins %d (%.1f%%)  undecided %d  mean length %.1fs" % [
		opts["a"].get_file().get_basename() if not opts["a"].contains("runs/") else opts["a"].get_base_dir().get_file(),
		opts["b"].get_file().get_basename() if not opts["b"].contains("runs/") else opts["b"].get_base_dir().get_file(),
		games, wins[0], 100.0 * wins[0] / games, wins[1], 100.0 * wins[1] / games, draws,
		seconds / games])
	quit(0)
