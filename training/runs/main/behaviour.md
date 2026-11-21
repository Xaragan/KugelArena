# How the net's behaviour develops, run 'main'

Measured at every test on 12 recorded games (a third each: net against itself,
net against the baseline bot, four-ball free-for-all); few games, so read
trends, not single rows.

- game s: mean game length. hits: collisions per game.
- items: items the net collects per game. escapes: times per game it was at the
  edge and got away again.
- from centre: its mean distance from the middle, in % of the disc radius.
- speed: its mean speed in % of top speed.
- chase: how much of its thrust points at the rival, +100 = always hunting,
  -100 = always running away.
- beats bot: wins in the sample duels against the baseline bot.

| generation | game s | hits | items | escapes | from centre % | speed % | chase | beats bot | in words |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|
| 0 | 13.0 | 8.6 | 0.0 | 0.0 | 67 | 35 | -25 | 0 of 4 | does not seek the fight, lives near the edge |
| 10 | 34.5 | 31.3 | 0.9 | 0.3 | 35 | 60 | +75 | 0 of 4 | hunts the rival |
| 20 | 24.3 | 44.3 | 0.8 | 0.4 | 34 | 71 | +94 | 0 of 4 | hunts the rival, holds the middle |
| 30 | 26.7 | 31.8 | 0.8 | 0.3 | 37 | 79 | +96 | 1 of 4 | hunts the rival |
| 40 | 27.6 | 27.7 | 0.8 | 0.2 | 34 | 77 | +95 | 1 of 4 | hunts the rival, holds the middle |
| 50 | 25.7 | 28.5 | 1.1 | 0.3 | 36 | 78 | +93 | 3 of 4 | hunts the rival |
| 60 | 23.8 | 28.5 | 0.8 | 0.3 | 36 | 73 | +92 | 1 of 4 | hunts the rival |
| 70 | 30.6 | 80.2 | 1.4 | 0.2 | 36 | 72 | +92 | 4 of 4 | hunts the rival |
| 80 | 31.3 | 54.8 | 0.8 | 0.3 | 35 | 77 | +92 | 4 of 4 | hunts the rival |
| 90 | 23.0 | 24.3 | 0.7 | 0.2 | 35 | 75 | +92 | 2 of 4 | hunts the rival, holds the middle |
| 100 | 20.7 | 26.3 | 1.2 | 0.2 | 35 | 76 | +92 | 2 of 4 | hunts the rival, holds the middle |
| 110 | 23.1 | 18.8 | 0.8 | 0.3 | 37 | 82 | +92 | 2 of 4 | hunts the rival |
| 120 | 23.3 | 22.1 | 0.9 | 0.5 | 36 | 84 | +91 | 3 of 4 | hunts the rival, saves itself at the edge |
| 130 | 26.7 | 23.1 | 0.8 | 0.6 | 35 | 81 | +93 | 3 of 4 | hunts the rival, holds the middle, saves itself at the edge |
| 140 | 26.4 | 28.3 | 0.8 | 0.4 | 33 | 80 | +94 | 4 of 4 | hunts the rival, holds the middle |
| 150 | 18.4 | 16.9 | 0.9 | 0.1 | 36 | 86 | +92 | 4 of 4 | hunts the rival |
| 160 | 19.1 | 17.4 | 0.5 | 0.3 | 34 | 82 | +92 | 3 of 4 | hunts the rival, holds the middle |
| 170 | 21.8 | 23.5 | 1.1 | 0.3 | 33 | 81 | +92 | 4 of 4 | hunts the rival, holds the middle |
