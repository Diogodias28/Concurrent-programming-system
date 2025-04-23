import processing.core.*;

public class DueloArena extends PApplet {
    // Configurações da arena
    final int ARENA_WIDTH = 800;
    final int ARENA_HEIGHT = 600;
    final int WALL_THICKNESS = 20;
    
    // Configurações do jogador
    final int PLAYER_SIZE = 30;
    final float MAX_SPEED = 5;
    final float ACCELERATION = 0.2;
    final float FRICTION = 0.98;
    
    // Posição e velocidade do jogador
    float playerX, playerY;
    float playerSpeedX, playerSpeedY;
    
    // Teclas pressionadas
    boolean upPressed, downPressed, leftPressed, rightPressed;
    
    public void settings() {
        size(ARENA_WIDTH, ARENA_HEIGHT);
    }
    
    public void setup() {
        // Inicializa o jogador no centro da arena
        playerX = width / 2;
        playerY = height / 2;
        playerSpeedX = 0;
        playerSpeedY = 0;
        
        // Configuração visual básica
        ellipseMode(CENTER);
        noStroke();
    }
    
    public void draw() {
        background(240);
        
        // Desenha a arena (paredes)
        drawArena();
        
        // Atualiza a posição do jogador
        updatePlayer();
        
        // Desenha o jogador
        fill(0, 0, 255); // Azul para o jogador
        ellipse(playerX, playerY, PLAYER_SIZE, PLAYER_SIZE);
    }
    
    void drawArena() {
        fill(150); // Cor das paredes
        // Paredes: superior, inferior, esquerda, direita
        rect(0, 0, width, WALL_THICKNESS);
        rect(0, height - WALL_THICKNESS, width, WALL_THICKNESS);
        rect(0, 0, WALL_THICKNESS, height);
        rect(width - WALL_THICKNESS, 0, WALL_THICKNESS, height);
    }
    
    void updatePlayer() {
        // Aplica aceleração baseada nas teclas pressionadas
        if (upPressed) playerSpeedY -= ACCELERATION;
        if (downPressed) playerSpeedY += ACCELERATION;
        if (leftPressed) playerSpeedX -= ACCELERATION;
        if (rightPressed) playerSpeedX += ACCELERATION;
        
        // Limita a velocidade máxima
        playerSpeedX = constrain(playerSpeedX, -MAX_SPEED, MAX_SPEED);
        playerSpeedY = constrain(playerSpeedY, -MAX_SPEED, MAX_SPEED);
        
        // Aplica atrito (inércia)
        playerSpeedX *= FRICTION;
        playerSpeedY *= FRICTION;
        
        // Atualiza posição
        playerX += playerSpeedX;
        playerY += playerSpeedY;
        
        // Verifica colisões com as paredes
        checkWallCollisions();
    }
    
    void checkWallCollisions() {
        // Verifica colisão com paredes laterais
        if (playerX - PLAYER_SIZE/2 < WALL_THICKNESS) {
            playerX = WALL_THICKNESS + PLAYER_SIZE/2;
            playerSpeedX *= -0.5; // Rebote
        } else if (playerX + PLAYER_SIZE/2 > width - WALL_THICKNESS) {
            playerX = width - WALL_THICKNESS - PLAYER_SIZE/2;
            playerSpeedX *= -0.5; // Rebote
        }
        
        // Verifica colisão com paredes superior/inferior
        if (playerY - PLAYER_SIZE/2 < WALL_THICKNESS) {
            playerY = WALL_THICKNESS + PLAYER_SIZE/2;
            playerSpeedY *= -0.5; // Rebote
        } else if (playerY + PLAYER_SIZE/2 > height - WALL_THICKNESS) {
            playerY = height - WALL_THICKNESS - PLAYER_SIZE/2;
            playerSpeedY *= -0.5; // Rebote
        }
    }
    
    public void keyPressed() {
        // Atualiza o estado das teclas quando pressionadas
        if (keyCode == UP) upPressed = true;
        if (keyCode == DOWN) downPressed = true;
        if (keyCode == LEFT) leftPressed = true;
        if (keyCode == RIGHT) rightPressed = true;
    }
    
    public void keyReleased() {
        // Atualiza o estado das teclas quando liberadas
        if (keyCode == UP) upPressed = false;
        if (keyCode == DOWN) downPressed = false;
        if (keyCode == LEFT) leftPressed = false;
        if (keyCode == RIGHT) rightPressed = false;
    }
    
    public static void main(String[] args) {
        PApplet.main("DueloArena");
    }
}
