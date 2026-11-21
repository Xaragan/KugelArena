extends RefCounted
## Plays headless games. Shared by train.gd and evaluate.gd.
##
## A "scenario" is a Dictionary describing one game from the point of view of the
## player being tested:
##   seed    game seed (item spawns)
##   seat    which ball the tested player controls
##   seats   one entry per ball; two entries are a duel, more a free-for-all.
##           The tested player's entry is {"opp": "me"}, the others are
##             {"opp": "std", "bot_seed": ..}              baseline bot
##             {"opp": "panel", "panel": k, "bot_seed": ..} one of the test characters
##             {"opp": "var", "bot_seed": ..}              bot with a random character
##             {"opp": "net", "net": weights}              a net (in job files
##                                                         "net_index" instead of "net")

const Sim = preload("res://sim/arena_sim.gd")
const Net = preload("res://sim/net_policy.gd")
const Bot = preload("res://sim/scripted_bot.gd")

## A game that is still undecided after this many seconds counts as a failure.
## With the shrinking disc every game ends by second 75, so this is a safety net.
const TIME_LIMIT := 90.0

# Outcome codes, from the tested player's point of view. In a free-for-all only
# being the last ball on the disc is a WIN.
const WIN := 0
const LOSS := 1
const DRAW := 2
const TIMEOUT := 3
const PANEL_SIZE := 4
const FFA_TEST_BALLS := 4


## Fixed scripted characters for judging a net: the standard baseline plus three
## that play differently, so a net cannot look good by exploiting one habit.
static func panel_bot(index: int, bot_seed: int) -> RefCounted:
	var bot: RefCounted = Bot.standard(bot_seed)
	match index:
		1:  # reckless
			bot.caution = 0.95
			bot.noise = 0.05
			bot.lead = 0.5
		2:  # careful, item-hungry
			bot.caution = 0.65
			bot.item_bias = 2.0
		3:  # brawler that ignores items
			bot.item_bias = 0.0
			bot.noise = 0.05
			bot.lead = 0.6
	return bot


## Test set of `count` games, the tested player's seat rotating.
##   "std"    duels against the baseline bot
##   "panel"  duels against the four characters in turn
##   "ffa"    free-for-alls with four balls: the tested player and three characters
static func test_scenarios(count: int, first_seed: int, kind: String) -> Array:
	var list := []
	for i in count:
		var balls := FFA_TEST_BALLS if kind == "ffa" else 2
		var seat := i % balls
		var seats := []
		for s in balls:
			if s == seat:
				seats.append({"opp": "me"})
			elif kind == "std":
				seats.append({"opp": "std", "bot_seed": first_seed * 7 + i})
			else:
				seats.append({"opp": "panel", "bot_seed": first_seed * 7 + i * 8 + s,
					"panel": (i / balls + s) % PANEL_SIZE})
		list.append({"seed": first_seed + i, "seat": seat, "seats": seats})
	return list


## One game, played until it ends or the tested player is off the disc.
## Returns [outcome, seconds the tested player lasted, pressure, place, balls,
## knockouts]. Pressure is the average of (rivals' distance from the centre - own
## distance) / radius: positive when the tested player held the middle.
func play(sim: Sim, me: Variant, opp_net: Net, sc: Dictionary) -> Array:
	var seats: Array = sc["seats"]
	var balls := seats.size()
	var seat: int = sc["seat"]
	var ctrl := []
	for i in balls:
		var spec: Dictionary = seats[i]
		match spec["opp"]:
			"me":
				ctrl.append(null)
			"net":
				ctrl.append(spec["net"])
			"var":
				ctrl.append(Bot.varied(spec["bot_seed"]))
			"panel":
				ctrl.append(panel_bot(spec["panel"], spec["bot_seed"]))
			_:
				ctrl.append(Bot.standard(spec["bot_seed"]))
	sim.reset(sc["seed"], TIME_LIMIT, balls)
	var pressure := 0.0
	var decisions := 0
	while sim.result == Sim.RUNNING and sim.alive[seat] == 1:
		if sim.tick % Sim.DECISION_TICKS == 0:
			var others := 0.0
			for i in balls:
				if sim.alive[i] == 0:
					continue
				if i == seat:
					sim.set_thrust(i, me.act(sim, i))
					continue
				var c: Variant = ctrl[i]
				if c is PackedFloat32Array:
					opp_net.weights = c
					sim.set_thrust(i, opp_net.act(sim, i))
				else:
					sim.set_thrust(i, c.act(sim, i))
				others += sim.pos[i].length()
			pressure += others / maxi(sim.alive_count - 1, 1) - sim.pos[seat].length()
			decisions += 1
		sim.step()
	var outcome := LOSS
	if sim.result == seat:
		outcome = WIN
	elif sim.result == Sim.TIMEOUT:
		outcome = TIMEOUT
	elif sim.result == Sim.DRAW and sim.place[seat] == 1:
		outcome = DRAW
	return [outcome, sim.seconds(), pressure / (maxi(decisions, 1) * Sim.ARENA_RADIUS),
		maxi(sim.place[seat], 1), balls, sim.knockouts[seat]]


## Training reward for one game.
##
## Duel: win +1 (a little more for a fast win), loss -1, draw -0.5.
## Free-for-all: by place, from +1 for the last ball on the disc down to -1 for
## the first one off, plus 0.2 for every rival pushed off, so hiding while the
## others fight is worth less than fighting.
## In both, a game that runs out of time is as bad as a loss, so stalling never
## pays, and a small share rewards holding the middle, which gives early random
## nets something to climb before they win their first game.
static func reward(game: Array) -> float:
	var progress: float = game[1] / TIME_LIMIT
	var r := 0.15 * float(game[2])
	var outcome := int(game[0])
	var balls := int(game[4])
	if outcome == TIMEOUT:
		return r - 1.0
	if balls > 2:
		r += 1.0 - 2.0 * (float(game[3]) - 1.0) / (balls - 1.0)
		r += 0.2 * float(game[5])
		if outcome == WIN:
			r += 0.2 * (1.0 - progress)
		return r
	match outcome:
		WIN:
			r += 1.0 + 0.2 * (1.0 - progress)
		LOSS:
			r += -1.0 + 0.1 * progress
		_:
			r += -0.5
	return r


## Every candidate in `candidates` (weight arrays; an empty array means "the
## standard scripted bot") plays every scenario. Returns one entry per candidate:
## [mean reward, wins, losses, draws, timeouts, total seconds].
func play_all(candidates: Array, scenarios: Array, n_threads: int) -> Array:
	n_threads = clampi(n_threads, 1, maxi(candidates.size(), 1))
	var threads: Array[Thread] = []
	for t in n_threads:
		var th := Thread.new()
		th.start(_candidate_slice.bind(t, n_threads, candidates, scenarios))
		threads.append(th)
	var results := []
	results.resize(candidates.size())
	for t in n_threads:
		var part: Array = threads[t].wait_to_finish()
		var k := 0
		for m in range(t, candidates.size(), n_threads):
			results[m] = part[k]
			k += 1
	return results


func _candidate_slice(t: int, n_threads: int, candidates: Array, scenarios: Array) -> Array:
	var sim := Sim.new()
	var net := Net.new()
	var opp_net := Net.new()
	var out := []
	for m in range(t, candidates.size(), n_threads):
		var weights: PackedFloat32Array = candidates[m]
		var total := [0.0, 0, 0, 0, 0, 0.0]
		for sc: Dictionary in scenarios:
			var me: Variant
			if weights.is_empty():
				me = Bot.standard(int(sc["seed"]) + 991)
			else:
				net.weights = weights
				me = net
			var game := play(sim, me, opp_net, sc)
			total[0] += reward(game)
			total[1 + int(game[0])] += 1
			total[5] += float(game[1])
		total[0] /= maxi(scenarios.size(), 1)
		out.append(total)
	return out


## One candidate against a long list of scenarios, spread over threads.
## Returns [mean reward, wins, losses, draws, timeouts, total seconds].
func play_one(weights: PackedFloat32Array, scenarios: Array, n_threads: int) -> Array:
	n_threads = clampi(n_threads, 1, maxi(scenarios.size(), 1))
	var threads: Array[Thread] = []
	for t in n_threads:
		var part := []
		for i in range(t, scenarios.size(), n_threads):
			part.append(scenarios[i])
		var th := Thread.new()
		th.start(_candidate_slice.bind(0, 1, [weights], part))
		threads.append(th)
	var total := [0.0, 0, 0, 0, 0, 0.0]
	var games := 0
	for t in n_threads:
		var part_size := 0
		for i in range(t, scenarios.size(), n_threads):
			part_size += 1
		var res: Array = threads[t].wait_to_finish()[0]
		total[0] += float(res[0]) * part_size
		for k in range(1, 6):
			total[k] += res[k]
		games += part_size
	total[0] /= maxi(games, 1)
	return total
