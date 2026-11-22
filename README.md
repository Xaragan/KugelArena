# KugelArena

Balls on a disc with pillars, holes, ice, mud and wind. Whoever touches the edge
or drops into a hole is out. As a duel (one against one) or as a free-for-all
with up to eight balls, where the last ball on the disc wins.
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
| | Space or Shift | dodge: a burst of speed the way you steer; ready again after 3 s |
| | Space / Enter | after a round: next round (also when you are out of a free-for-all) |
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
2. Friend: start KugelArena first, then accept the invite in Steam. The game must
   already be running: the borrowed test app id belongs to Valve's "Spacewar", so
   Steam starts that instead when it finds no running game to hand the invite to.
   Two ways without an invite: pick the host under "Friends who are hosting right
   now" and press Join, or paste the lobby code the host copied in the lobby.
3. After a round the host presses Space for the next one. M leaves the game.

**Without Steam.** "Host on this PC" opens port 24800 (UDP); friends type the
host's address and press "Join address". Works in the same network, or over the
internet when the host forwards that port.

**Giving the game to friends.** `.\package.ps1` writes `dist\KugelArena.zip` with
the game, the nets, the Steam extension and the Godot runtime. A friend unpacks
it and double-clicks `KugelArena.bat`.

How it works (`game/net_game.gd`): players send their thrust every tick; the host
sends the state of the disc 30 times per second and the hits, pickups, dodges and
falls as they happen; the layout of obstacles goes out once per round. Host and
guests must run the same version, a guest with another one is told so and
turned away. Between two states a joined window moves the balls on with their
last velocity. There is no lag compensation beyond that.

## Rules

All rules are in `sim/arena_sim.gd`; the constants at its top are the tuning knobs.

- The disc is 35 units wide (three times the area of the first version) and a
  ball's top speed is 5.4 units per second, so crossing it takes about 6.5
  seconds. Drag is high (2.2), so a ball reaches top speed in about half a
  second and can still stop before the edge.
- **Dodge.** A burst of 7.5 units per second in the direction you steer (or the
  way you are moving). It also ends a skid. Cooldown 3 seconds.
- Collisions are real physics: momentum is conserved and the balls separate with
  90 % of their closing speed. Two equal balls swap their speeds along the line
  of the hit, so the one that rams stops and the one that is hit flies off.
- A hard hit knocks a ball into a skid: for up to 1.2 seconds it has only 12 %
  of its grip, so it slides on and its own thrust does little.
- A ball that touches the edge or gets its centre into a hole is out. In a duel
  the other ball wins; in a free-for-all the last ball on the disc wins. The last
  balls falling in the same instant is a draw.
- After 15 seconds the disc starts to shrink and is gone 60 seconds later, so
  every round ends by second 75. Obstacles and zones vanish as the edge passes
  them.
- **Obstacles and zones.** Every round lays out a new set, rotationally
  symmetric, so every ball starts with the same surroundings and nothing solid
  or deadly is near a starting position. A duel gets about 18:

| On the disc | What it does |
|---|---|
| Pillar | solid and bouncy |
| Block | a big solid area, no way through, hardly bouncy |
| Hole | trap: fall in and you are out; pushing someone in counts as your knockout |
| Ice | patch with a quarter of the grip: you slide |
| Mud | patch with 2.5 times the drag: you crawl |
| Wind | area with a steady wind in one direction |

- Items lie on the disc (three at a time in a duel, up to six in a free-for-all)
  and appear 1.5 times as often as before. They were weakened after the change
  to physical collisions made them too strong:

| Item | Effect |
|---|---|
| Power (P) | your ball is 1.7 times as heavy: it pushes harder and is pushed less, 5 s |
| Speed (S) | 35 % more thrust and top speed, 5 s |
| Anchor (A) | 1.8 times the grip, skids last only 40 % as long, ice does not bother you, 5 s |
| Freeze (F) | every other ball's thrust drops to 60 %, 3 s |
| Shock (X) | instant blast that throws others within 6 units away from you; stronger when close |

How the values were chosen: speed, the shrink rule, the wish for physically
correct collisions, the dodge, the bigger disc with obstacles and the weaker
items came from the designer after playing and watching. Purely physical
collisions alone made rounds a shoving match that only the shrinking disc
decided, so the skid was added. Measured with scripted bots on the current
rules: a duel lasts about 51 seconds with 16 collisions, 9 dodges and 17 items,
a four-ball free-for-all about 62 seconds; only 6 % of duels end before the disc
starts to shrink. On this bigger disc cautious bots mostly survive until the
edge comes to them. That is a measurement of bots, not of how it feels to play.

## The net

`sim/net_policy.gd`; the game's default net is `net/rival_net.json`.

**Shape:** 87 inputs -> 32 neurons (tanh) -> 16 neurons (tanh) -> 3 outputs (tanh),
3395 weights. It decides ten times per second. The same net plays duels and
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
| 49 | own dodge cooldown, 0 = ready |
| 50 | the nearest rival's dodge cooldown |
| 51-62 | nearest obstacle or zone: present, position (x, y), radius, kind as six 0/1 flags, wind direction (x, y) |
| 63-74 | second nearest, same layout |
| 75-86 | third nearest, same layout |

In a duel inputs 35-46 are 0.

**Outputs:** thrust along x (towards the nearest rival) and along y, each -1..1,
and a third number that triggers the dodge in the thrust direction when it is
above 0.5. The thrust vector is turned back into disc coordinates and cut to
length 1. So unlike the keyboard's eight directions, the net can thrust in any
direction.

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

**Version 0.4 (current rules: dodge, bigger disc, obstacles and zones).** Every
change of the rules makes the earlier nets useless, so training started again
from a random net. It was stopped by hand after 10.1 minutes (33 generations,
13 worker processes), so these nets are still weak. On 1000 fresh games per mode
against the scripted bots the kept net (generation 30) wins 37.0 % of duels
against the baseline bot and 14.2 % of four-ball free-for-alls (chance would be
25 %). In the tournament (`training/tournament.md`, 40 duels per pairing) the
scripted bot beats it 60 to 40. In the training tests the rates were still
rising when it stopped (duels 20.8, 40.3, 42.8 %; free-for-alls 3.0, 8.5,
16.5 %). `.	rain.ps1` continues this run.

**Earlier versions, for comparison.** Version 0.1 (no obstacles, every hit
multiplied by 2.3): after 20.2 minutes of training the net won 79.8 % of 2000
fresh duels against the baseline bot and 31.6 % of four-ball free-for-alls,
where the bot in the same seat won 34.6 %. Those nets do not fit the current
rules and are not part of this version.

Multiplayer, tested on one PC without Steam: one host and two joined players in
headless windows played a four-ball round with one net; all three saw the same
obstacles, winner, score and round length, the joined players' thrust and
dodges reached the host, and a guest with an older version was turned away with
a message. With Steam, tested: logging in, reading the friends list and opening
a lobby as host. Not tested by me: a second Steam account joining, invites,
play over the internet.

Not verified: how the new rules feel to play. The window was checked with
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
