# How the net's behaviour develops, run 'next'

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
| 0 | 28.7 | 4.8 | 0.1 | 0.0 | 67 | 19 | -14 | 0 of 4 | does not seek the fight, lives near the edge |
| 10 | 48.5 | 41.2 | 0.3 | 0.3 | 32 | 51 | +85 | 0 of 4 | hunts the rival, holds the middle |
| 20 | 35.1 | 35.1 | 0.7 | 0.1 | 35 | 63 | +96 | 3 of 4 | hunts the rival, holds the middle |
| 30 | 35.2 | 34.3 | 0.7 | 0.1 | 34 | 81 | +96 | 2 of 4 | hunts the rival, holds the middle |
