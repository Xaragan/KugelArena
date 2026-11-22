# Training progress, run 'next'

Every 10 generations the net plays the same test games against scripted bots:
600 duels against four characters, and 400 four-ball free-for-alls against three
of them, where winning by chance would be 25 %. The score is the mean of the two
win rates. One generation = 1120 training games, half duels, half free-for-alls
with 3 to 6 balls. Generation 0 is the untrained random net.

Method of this run: 50 % of the training games are against nets, selection 'panel'.
The last number column is the share of decided games won against the kept net.

| generation | minutes trained | duel wins % | free-for-all wins % | score | duel length s | vs kept net % | note |
|---:|---:|---:|---:|---:|---:|---:|---|
| 0 | 0.0 | 0.2 | 0.0 | 0.1 | 13.0 | - | kept as best |
| 10 | 3.3 | 20.8 | 3.0 | 11.9 | 32.7 | - | kept as best |
| 20 | 6.7 | 40.3 | 8.5 | 24.4 | 24.9 | - | kept as best |
| 30 | 9.3 | 42.8 | 16.5 | 29.7 | 20.2 | - | kept as best |
