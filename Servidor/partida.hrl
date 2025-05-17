-record(partida, {
    player1,
    player2,
    sock1,
    sock2,
    player1Position,
    player2Position,
    player1Speed = {0,0},
    player2Speed = {0,0},
    player1acceleration = {0,0},
    player2acceleration = {0,0},
    player1Score,
    player2Score,
    player1LastShot = 0,
    player2LastShot = 0,
    projectiles = [],
    startTime
}).

-record(projectile, {
    id,
    owner,
    position,
    velocity
}).
