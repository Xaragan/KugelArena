# Training progress, run 'main'

Every 10 generations the net plays the same test games against scripted bots:
600 duels against four characters, and 400 four-ball free-for-alls against three
of them, where winning by chance would be 25 %. The score is the mean of the two
win rates. One generation = 1120 training games, half duels, half free-for-alls
with 3 to 6 balls. Generation 0 is the untrained random net.

Method of this run: 50 % of the training games are against nets, selection 'panel'.
The last number column is the share of decided games won against the kept net.

| generation | minutes trained | duel wins % | free-for-all wins % | score | duel length s | vs kept net % | note |
|---:|---:|---:|---:|---:|---:|---:|---|
| 0 | 0.0 | 0.0 | 0.0 | 0.0 | 2.8 | - | kept as best, now the game's net |
| 10 | 1.1 | 8.8 | 5.0 | 6.9 | 25.2 | - | kept as best, now the game's net |
| 20 | 2.6 | 41.0 | 13.0 | 27.0 | 25.0 | - | kept as best, now the game's net |
| 30 | 3.9 | 65.3 | 17.5 | 41.4 | 20.7 | - | kept as best, now the game's net |
| 40 | 5.2 | 64.3 | 17.0 | 40.7 | 21.1 | - |  |
| 50 | 6.4 | 76.5 | 25.8 | 51.1 | 19.1 | - | kept as best, now the game's net |
| 60 | 7.6 | 78.0 | 23.0 | 50.5 | 20.6 | - |  |
| 70 | 8.8 | 84.8 | 29.8 | 57.3 | 20.0 | - | kept as best, now the game's net |
| 80 | 10.0 | 82.0 | 25.3 | 53.6 | 19.4 | - |  |
| 90 | 11.1 | 85.5 | 31.3 | 58.4 | 17.9 | - | kept as best, now the game's net |
| 100 | 12.2 | 86.5 | 32.8 | 59.6 | 17.2 | - | kept as best, now the game's net |
| 110 | 13.3 | 86.2 | 29.8 | 58.0 | 18.1 | - |  |
| 120 | 14.3 | 88.2 | 32.8 | 60.5 | 16.3 | - | kept as best, now the game's net |
| 130 | 15.3 | 88.2 | 29.8 | 59.0 | 16.3 | - |  |
| 140 | 16.4 | 90.2 | 35.0 | 62.6 | 15.8 | - | kept as best, now the game's net |
| 150 | 17.5 | 88.3 | 33.5 | 60.9 | 16.3 | - |  |
| 160 | 18.6 | 88.8 | 33.0 | 60.9 | 16.4 | - |  |
| 170 | 19.7 | 89.0 | 32.8 | 60.9 | 16.4 | - |  |
