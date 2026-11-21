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
| 0 | 19.0 | 25.5 | 0.1 | 0.1 | 62 | 26 | +0 | 0 of 4 | does not seek the fight, lives near the edge |
| 10 | 36.4 | 88.7 | 0.5 | 0.3 | 37 | 47 | +89 | 1 of 4 | hunts the rival |
