extends SceneTree
## Measures a net (or the scripted baseline itself) over many headless games.
##
##   godot --headless --path . --script res://training/evaluate.gd -- [options]
##     --net=res://net/rival_net.json   net to test; "bot" tests the baseline bot
##     --games=2000                     number of games
##     --opponent=std                   std = duels against the baseline, panel = duels
##                                      against four characters, ffa = four-ball
##                                      free-for-alls against three of them
##     --seed=5000000                   first game seed (training never uses these)
##     --threads=N

const Match = preload("res://training/match.gd")
const Net = preload("res://sim/net_policy.gd")


func _initialize() -> void:
	var opts := {"net": "res://net/rival_net.json", "games": "2000", "opponent": "std",
		"seed": "5000000", "threads": str(maxi(1, OS.get_processor_count() - 2))}
	for arg in OS.get_cmdline_user_args():
		var parts := arg.trim_prefix("--").split("=", true, 1)
		if parts.size() == 2:
			opts[parts[0]] = parts[1]
	var weights := PackedFloat32Array()
	if opts["net"] != "bot":
		var net := Net.new()
		if not net.load_weights(opts["net"]):
			printerr("Cannot load net: ", opts["net"])
			quit(1)
			return
		weights = net.weights
	var games := int(opts["games"])
	var scenarios := Match.test_scenarios(games, int(opts["seed"]), opts["opponent"])
	var started := Time.get_ticks_msec()
	var res: Array = Match.new().play_one(weights, scenarios, int(opts["threads"]))
	var took := (Time.get_ticks_msec() - started) / 1000.0
	print("Tested: %s   opponent: %s   games: %d" % [opts["net"], opts["opponent"], games])
	print("  wins     %5d  %5.1f %%%s" % [res[1], 100.0 * res[1] / games,
		"  (last ball on the disc; by chance 25 %)" if opts["opponent"] == "ffa" else ""])
	print("  losses   %5d  %5.1f %%" % [res[2], 100.0 * res[2] / games])
	print("  draws    %5d  %5.1f %%" % [res[3], 100.0 * res[3] / games])
	print("  timeouts %5d  %5.1f %%  (undecided after %d s)" % [res[4], 100.0 * res[4] / games,
		int(Match.TIME_LIMIT)])
	print("  mean game length %.1f s, %.1f s wall time, %.0f games/s" % [res[5] / games, took,
		games / maxf(took, 0.001)])
	quit(0)
