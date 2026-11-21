# KugelArena

Balls on a disc. Whoever touches the edge falls off. As a duel (one against one)
or as a free-for-all with up to eight balls, where the last ball on the disc wins.
You steer the blue ball with W A S D; every other ball is steered by a small neural
net that learned the game by playing it headless, many thousands of times.

Godot 4.7, GDScript only. No Python, no ML library: the net is evaluated and
trained in plain GDScript.

## Download and play

Windows only. Get `KugelArena.zip` from the
[latest release](https://github.com/Xaragan/KugelArena/releases/latest), unpack it
and double-click `KugelArena.bat`. Nothing needs to be installed. To play with
friends over Steam, Steam must be running; see "Playing with friends" below.

The rest of this page is about the source: the rules, the net and its training.

## Start the game

```powershell
.\play.ps1
```

(or open the folder in the Godot editor and press F5). A Godot 4.7.2 build is
expected in `tools\godot\`. `.\play.ps1 -Watch` starts with the nets playing each
other, `-SecondScreen` opens the window on the non-primary screen.

The game starts with the **opponent menu**: every saved net is a card with a name,
a strength from one to five dots and a line about how it plays (hover for more).
Choose "Duel" or a free-for-all with 4, 6 or 8 balls, then Play. In a free-for-all
the other balls are other nets from the list.

| Where | Key | |
|---|---|---|
| Menu | Up / Down | choose an opponent |
| | Enter | play |
| | Space | skip: watch the best fights from training |
| | Esc | quit |
| Playing | W A S D (or arrows) | thrust |
| | Space / Enter | next round (also when you are out of a free-for-all) |
| | R | new round now |
| | N | switch between playing yourself and watching the nets |
| | M | back to the menu |
| Replays | Space | play / pause |
| | Left / Right | rewind / fast forward (hold the key) |
| | Up / Down | speed, 0.25x to 4x |
| | PgUp / PgDn | previous / next battle |
| | Home | back to the start |

The replay controls are also buttons with a timeline at the right edge. The window
reads the training runs when it starts; restart it to see nets trained since.

## Playing with friends

"Play with friends" in the menu. One player hosts, the others join; the host's
PC runs the game. Duel or free-for-all with up to eight balls; balls without a
player are steered by nets.

**Over Steam.** Steam must be running on every PC. The game uses the GodotSteam
extension (`addons/godotsteam`, version 4.24) and Valve's public test app id 480,
so Steam shows everyone as playing "Spacewar".

1. Host: Play with friends -> "Host a game and invite friends". In the lobby pick
   a friend from the list of friends who are online and press "Invite selected
   friend". Choose Duel or 4 / 6 / 8 balls, then "Start the game".
2. Friend: start the game, open "Play with friends" and accept the invite in
   Steam. Or pick the host under "Friends who are hosting right now" and press Join.
3. After a round the host presses Space for the next one. M leaves the game.

**Without Steam.** "Host on this PC" opens port 24800 (UDP); friends type the
host's address and press "Join address". Works in the same network, or over the
internet when the host forwards that port.

**Giving the game to friends.** `.\package.ps1` writes `dist\KugelArena.zip` with
the game, the nets, the Steam extension and the Godot runtime. A friend unpacks
it and double-clicks `KugelArena.bat`.

How it works (`game/net_game.gd`): players send their thrust every tick; the host
sends the state of the disc 30 times per second and the hits, pickups and falls
as they happen. Between two states a joined window moves the balls on with their
last velocity. There is no lag compensation beyond that.

## Rules

All rules are in `sim/arena_sim.gd`; the constants at its top are the tuning knobs.

- The disc is 20 units wide and a ball's top speed is 5.4 units per second, so
  crossing it takes about 3.7 seconds. Drag is high (2.2), so a ball reaches top
  speed in about half a second and can still stop before the edge.
- Collisions are real physics: momentum is conserved and the balls separate with
  90 % of their closing speed. Two equal balls swap their speeds along the line
  of the hit, so the one that rams stops and the one that is hit flies off.
- A hard hit knocks a ball into a skid: for up to a second it has only 15 % of
  its grip, so it slides on and its own thrust does little.
- A ball that touches the edge is out. In a duel the other ball wins; in a
  free-for-all the last ball on the disc wins. The last balls falling in the same
  instant is a draw.
- After 15 seconds the disc starts to shrink and is gone 60 seconds later, so
  every round ends by second 75.
- Items lie on the disc (two at a time in a duel, up to four in a free-for-all):

| Item | Effect |
|---|---|
| Power (P) | your ball is 2.5 times as heavy: it pushes harder and is pushed less, 6 s |
| Speed (S) | 60 % more thrust and top speed, 6 s |
| Anchor (A) | 2.5 times the grip: you stop and turn faster and never skid, 6 s |
| Freeze (F) | every other ball's thrust drops to 40 %, 4 s |
| Shock (X) | instant blast that throws the others away from you; stronger when close |

How the values were chosen: speed and the shrink rule came from watching rounds,
and so did the wish for physically correct collisions (an earlier version
multiplied every hit by 2.3, which felt unnatural). Purely physical collisions
alone made rounds a 48-second shoving match that only the shrinking disc
decided, so the skid was added and its length and grip were picked by game
statistics of scripted bots: rounds of about 28 seconds, 16 % decided before the
disc shrinks, 2 % over within 8 seconds. That is a measurement of bots, not of
how it feels to play.

## The net

`sim/net_policy.gd`; the game's default net is `net/rival_net.json`.

**Shape:** 49 inputs -> 32 neurons (tanh) -> 16 neurons (tanh) -> 2 outputs (tanh),
2162 weights. It decides ten times per second. The same net plays duels and
free-for-alls.

**Inputs.** Everything is given in the ball's own frame: the origin is the ball,
the x axis points at the nearest rival, the y axis a quarter turn to the left.
Lengths are divided by the disc's starting radius (10), speeds by the top speed (5.4).

| # | Input |
|---|---|
| 0 | distance to the nearest rival (divided by 20) |
| 1-2 | where the centre of the disc is (x, y) |
| 3-4 | own velocity (x, y) |
| 5-6 | the nearest rival's velocity (x, y) |
| 7 | own room left before the edge |
| 8 | the nearest rival's room left before the edge |
| 9-12 | own effects, time left as 0..1: Power, Speed, Anchor, Frozen |
| 13-16 | the nearest rival's effects, same order |
| 17-24 | nearest item: present (0/1), position (x, y), kind as five 0/1 flags |
| 25-32 | second nearest item, same layout |
| 33 | current disc radius (1 = full size) |
| 34 | rivals still on the disc (divided by 7) |
| 35-40 | second nearest rival: present, position (x, y), velocity (x, y), room before the edge |
| 41-46 | third nearest rival, same layout |
| 47 | own skid, time left as 0..1 |
| 48 | the nearest rival's skid, same |

In a duel inputs 35-46 are 0.

**Outputs:** thrust along x (towards the nearest rival) and along y, each -1..1.
The vector is turned back into disc coordinates and cut to length 1. So unlike the
keyboard's eight directions, the net can thrust in any direction.

## Training

```powershell
.\train.ps1                 # 30 minutes; continues the run if it exists
.\train.ps1 -Minutes 120
.\train.ps1 -Stop           # from a second terminal: stop after the current generation
.\train.ps1 -Fresh          # throw the run away, start from a random net
.\train.ps1 -Run second     # another run; it shows up in the menu as its own family
```

Ctrl+C also works and loses at most the generation in progress. A checkpoint is
written after every generation, so after a stop, a crash or the PC going to sleep
the same command picks up where it left off.

Files of a run, in `training/runs/<run>/`:

- `progress.md` - readable table, one row per test
- `behaviour.md` - how the net's behaviour develops, one row per test
- `log.txt` - one line per generation
- `net_best.json` - best net of this run
- `nets/gen_NNNN.json` - the net at every test; these are the opponents in the menu
- `games/gen_NNNN.jsonl` - sample games recorded at every test
- `highlights.jsonl` - the run's most interesting games, shown in the replays
- `checkpoint.bin` - everything needed to continue

The game's default net, `net/rival_net.json`, is replaced whenever a run keeps a
new best net (`--export=0` on `train.gd` switches that off).

**Method** (`training/train.gd`): evolution strategies. Each generation makes 112
copies of the current net with small random changes to the weights (56 changes and
their mirror images). Every copy plays the same 10 games. The weights then move
towards the changes that scored better (rank-based, Adam step). The 1120 games of a
generation are spread over worker processes; each worker writes its own result
file and a missing or broken one is skipped.

**Games.** Half of the training games are duels, half free-for-alls with three to
six balls. Every other ball is, half of the time, a net (one third the current
net itself, two thirds an earlier version; a snapshot every 10 generations, 12
kept) and otherwise a scripted bot (`sim/scripted_bot.gd`) whose character is drawn
at random: careful or reckless, item-hungry or not, accurate or sloppy, strong or
weak.

**Reward.** Duel: win +1 (up to +0.2 more for winning quickly), loss -1, draw
-0.5. Free-for-all: by place, from +1 for the last ball on the disc to -1 for the
first one off, plus 0.2 for every rival pushed off, so hiding while the others
fight is worth less than fighting. A game still undecided after 90 seconds counts
like a loss. A small share (at most +-0.15) rewards holding the middle; it gives
the very first random nets something to learn from.

**Tests.** Every 10 generations the net plays fixed test games against scripted
bots: 600 duels against four characters and 400 four-ball free-for-alls against
three of them. The score is the mean of the two win rates; the best-scoring net
is kept. Because "best of many tests" flatters the winner, the numbers under
Results come from separate games that training never used.

**Why this method.** Three ways of choosing opponents and the kept net were
compared on the duel-only version, twice, 10 minutes each (`--net-share`,
`--selection`): (a) half nets, half bots, keep the best against bots; (b) nets
only, keep a net when it beats the kept one directly; (c) 70 % nets with the same
direct selection. In 1000-game duels (a) beat (b) 59:41 and 58:42 and beat (c)
67:33 and 65:35, so (a) is the default.

## Measuring

```powershell
.\evaluate.ps1                    # 2000 fresh duels against the scripted baseline
.\evaluate.ps1 -Opponent panel    # duels against the four test characters
.\evaluate.ps1 -Opponent ffa      # four-ball free-for-alls against three of them
.\evaluate.ps1 -Net bot           # the baseline in the net's place, for comparison
```

Headless tools, each started as
`tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://training/<name>.gd -- <options>`:

- `tournament.gd` - everyone against everyone: the best net of every run and the
  scripted bot, duels and free-for-alls; writes `training/tournament.md`
  (`--all` enters every saved generation)
- `duel.gd --a=<net file> --b=<net file>` - two nets against each other
- `profile_nets.gd` - measures how every saved net behaves (for the menu)
- `rebuild_highlights.gd` - picks the highlights again from the recorded games
- `leaderboard.gd` - lists every saved net with its test results; writes
  `training/leaderboard.md` and `.json`. `python tools/leaderboard_page.py` turns the
  JSON into `training/leaderboard.html` (standard library only)

## Recording games as data

Every finished round in the window is appended to
`recordings/window_<start time>.jsonl`. Headless:

```powershell
.\record.ps1                      # 50 duels, the net against itself
.\record.ps1 -B bot -Games 200    # the net against the scripted baseline
```

One line per game, a JSON object: `seed`, `n` (balls), `players`, `result`
(`win_<ball>`, `draw`, `timeout`), `places`, `seconds`, `stats` (collisions,
pickups, knockouts, escapes, ... per ball), `events` (hits, pickups, falls) and
`rows`: ten rows per second with every ball's position, velocity, thrust and
whether it is still on the disc, the disc radius, the item slots and all effect
timers. The layout is described at the top of `sim/game_recorder.gd`.

## Names and descriptions in the menu

`sim/net_profile.gd`. Every saved net plays 60 games (20 duels against the
baseline bot, 20 against itself, 20 four-ball free-for-alls); the counts are
stored in the net's file. The strength dots come from the share of bot duels it
won, the epithet ("the Hunter", "the Collector", ...) and the sentences from what
it did. The first name belongs to the training run, so the generations of a run
are one character growing up ("age" = generation).

## Results

**Version 0.2 (current rules, physical collisions with skid).** The change of
physics made the earlier nets useless, so training started again from a random
net and was stopped by hand after 2.0 minutes (11 generations). The nets in this
version are therefore weak: on 1000 fresh games per mode against the scripted
bots the kept net (generation 10) wins 8.6 % of duels against the baseline bot
and 6.8 % of four-ball free-for-alls (chance would be 25 %). In the tournament
(`training/tournament.md`, 100 duels per pairing) the scripted bot beats it 88
to 12. `.	rain.ps1` continues this run; it has not been run longer yet.

**Version 0.1 (earlier rules, every hit multiplied by 2.3), for comparison.**
After 20.2 minutes of training on 13 worker processes (174 generations, about
195,000 games) the kept net won, on 2000 fresh games per line: 79.8 % of duels
against the baseline bot, 87.0 % against the four test characters, and 31.6 % of
four-ball free-for-alls, where the baseline bot in the same seat won 34.6 %. So
it was clearly better than the bots in duels and no better in free-for-alls.
Those nets do not fit the current rules and are not part of this version.

Multiplayer, tested on one PC without Steam: one host and two joined players in
headless windows played four-ball rounds with one net; all three saw the same
winner, score and round length, and the joined players' thrust reached the host.
With Steam, tested: logging in, reading the friends list and opening a lobby as
host. Not tested by me: a second Steam account joining, invites, play over the
internet.

Not verified: how the new collisions feel to play. The window was checked with
screenshots only.

## Files

- `sim/arena_sim.gd` - the rules; used unchanged by the window and by training
- `sim/net_policy.gd` - the net
- `sim/scripted_bot.gd` - scripted sparring partners and the baseline
- `sim/game_recorder.gd` - game recording and highlight selection
- `sim/net_profile.gd` - names, strength and descriptions of nets
- `game/main.gd`, `game/main.tscn` - the window
- `training/` - training, measuring and the tools listed above

## License

MIT, see `LICENSE`. Third-party parts keep their own licenses: the Godot engine
(MIT), the GodotSteam extension in `addons/godotsteam` (MIT, see its `license.md`)
and Valve's `steam_api64.dll` that comes with it (Steamworks SDK).
