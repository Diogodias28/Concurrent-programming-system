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
    player1Score = 0,
    player2Score = 0,
    player1LastShot = 0,
    player2LastShot = 0,
    player1ShotCooldown = 0,
    player2ShotCooldown = 0,
    player1ShotSpeed = 0,
    player2ShotSpeed = 0,
    projectiles = [],
    modificadores = [],
    modificadorSpawnTime = 0,
    startTime,
    player1_keys = [],
    player2_keys = []
}).

-record(projectile, {
    position,
    velocity,
    owner
}).

-record(modificador, {
    position,
    type
}).