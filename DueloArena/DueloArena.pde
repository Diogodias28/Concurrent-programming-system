import processing.core.*;
import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStreamReader;
import java.io.PrintWriter;
import java.net.Socket;

public class DueloArena extends PApplet {
    // Configurações da arena
    final int ARENA_WIDTH = 800;
    final int ARENA_HEIGHT = 600;
    final int WALL_THICKNESS = 10;
    final int GUI_HEIGHT = 70; // Aumentei a altura da GUI para acomodar melhor o texto
    
    // Configurações do jogador
    final int PLAYER_SIZE = 20;
    final float MAX_SPEED = 6;
    final float INITIAL_ACCELERATION = 0.01f;
    final float ACCELERATION_INCREMENT = 0.01f;
    final float FRICTION = 0.98f;
    
    // Configurações de projéteis
    final int PROJECTILE_SIZE = 10;
    final float PROJECTILE_SPEED = 8;
    final int PLAYER_COOLDOWN = 1000; // ms entre disparos do jogador
    final int OPPONENT_COOLDOWN = PLAYER_COOLDOWN; // Igual ao do jogador
    int lastPlayerProjectileTime = 0;
    int lastOpponentProjectileTime = 0;
    
    // Posição e velocidade dos jogadores
    float playerX, playerY; // Jogador azul (controlado)
    float playerSpeedX, playerSpeedY;
    float opponentX, opponentY; // Jogador vermelho (estático)
    
    // Teclas pressionadas e tempo de pressão
    boolean upPressed, downPressed, leftPressed, rightPressed;
    boolean shootModeActive = false; // Modo de disparo do oponente
    int upPressedTime, downPressedTime, leftPressedTime, rightPressedTime;
    
    // Lista de projéteis
    ArrayList<Projectile> projectiles = new ArrayList<Projectile>();
    
    // Variáveis da GUI
    int blueScore = 0;
    int redScore = 0;
    int gameTime = 120; // 2 minutos em segundos
    int lastTimeUpdate;
    boolean gameRunning = false;
    
    // Classe para representar projéteis
    class Projectile {
        float x, y;
        float speedX, speedY;
        int size;
        boolean active;
        int owner; // 0 para azul, 1 para vermelho
        
        Projectile(float x, float y, float targetX, float targetY, int owner) {
            this.x = x;
            this.y = y;
            this.size = PROJECTILE_SIZE;
            this.active = true;
            this.owner = owner;
            
            // Calcula direção para o cursor
            float dx = targetX - x;
            float dy = targetY - y;
            float distance = sqrt(dx*dx + dy*dy);
            
            // Normaliza e multiplica pela velocidade
            this.speedX = (dx/distance) * PROJECTILE_SPEED;
            this.speedY = (dy/distance) * PROJECTILE_SPEED;
        }
        
        void update() {
            if (!active) return;
            
            // Move o projétil
            x += speedX;
            y += speedY;
            
            // Verifica colisões com paredes
            if (x - size/2 < WALL_THICKNESS || x + size/2 > width - WALL_THICKNESS ||
                y - size/2 < GUI_HEIGHT + WALL_THICKNESS || y + size/2 > height - WALL_THICKNESS) {
                active = false;
            }
            
            // Verifica colisão com jogadores
            if (owner == 0) { // Projétil do azul
                if (dist(x, y, opponentX, opponentY) < (PROJECTILE_SIZE + PLAYER_SIZE)/2) {
                    active = false;
                    blueScore++;
                }
            } else { // Projétil do vermelho
                if (dist(x, y, playerX, playerY) < (PROJECTILE_SIZE + PLAYER_SIZE)/2) {
                    active = false;
                    redScore++;
                }
            }
        }
        
        void display() {
            if (!active) return;
            
            if (owner == 0) {
                fill(0, 0, 255); // Azul
            } else {
                fill(255, 0, 0); // Vermelho
            }
            ellipse(x, y, size, size);
        }
    }
    
    public void settings() {
        size(ARENA_WIDTH, ARENA_HEIGHT + GUI_HEIGHT);
    }

    Socket socket;
    BufferedReader in;
    PrintWriter out;

    public void setup() {
        // Inicializa o jogador azul no centro esquerdo
        playerX = width / 4;
        playerY = (height - GUI_HEIGHT) / 2 + GUI_HEIGHT;
        playerSpeedX = 0;
        playerSpeedY = 0;
        
        // Inicializa o jogador vermelho no centro direito
        opponentX = 3 * width / 4;
        opponentY = (height - GUI_HEIGHT) / 2 + GUI_HEIGHT;
        
        // Inicializa tempos de pressão
        upPressedTime = downPressedTime = leftPressedTime = rightPressedTime = 0;
        
        // Configuração visual básica
        ellipseMode(CENTER);
        noStroke();
        smooth();
        textAlign(CENTER, CENTER);
        textSize(24);
        
        // Inicia o jogo
        gameRunning = true;
        lastTimeUpdate = millis();

        try{
            socket = new Socket("localhost", 12345);
            in = new BufferedReader(new InputStreamReader(socket.getInputStream()));
            out = new PrintWriter(socket.getOutputStream(), true);
        }catch(IOException e){
            e.printStackTrace();
            exit();
        }        

    }
    
    public void draw() {
        background(240);
        
        // Desenha a GUI
        drawGUI();
        
        // Desenha a arena (paredes)
        drawArena();
        
        // Atualiza o jogo se estiver rodando
        if (gameRunning) {
            updateGame();
        }
        
        // Desenha os jogadores
        fill(0, 0, 255); // Azul para o jogador principal
        ellipse(playerX, playerY, PLAYER_SIZE, PLAYER_SIZE);
        
        fill(255, 0, 0); // Vermelho para o oponente
        ellipse(opponentX, opponentY, PLAYER_SIZE, PLAYER_SIZE);
        
        // Desenha os projéteis
        for (Projectile p : projectiles) {
            p.display();
        }
        
        // Mostra status do modo de disparo (agora parte da GUI)


        try{
            if(in.ready()){
                String serverMessage = in.readLine();
                String[] parts = serverMessage.split(",");
                if(parts[0].equals("PLAYER_POS")){
                    playerX = float(parts[1]);
                    playerY = float(parts[2]);
                }
            }
        }catch(IOException e){
            e.printStackTrace();
        }

    }
    
    void drawGUI() {
        // Fundo da GUI
        fill(220);
        rect(0, 0, width, GUI_HEIGHT);
        
        // Placar azul (esquerda)
        fill(0, 0, 255);
        text(blueScore, 50, GUI_HEIGHT/2 - 10);
        
        // Timer (centro)
        fill(0);
        int minutes = gameTime / 60;
        int seconds = gameTime % 60;
        String timeString = String.format("%d:%02d", minutes, seconds);
        text(timeString, width/2, GUI_HEIGHT/2 - 10);
        
        // Placar vermelho (direita)
        fill(255, 0, 0);
        text(redScore, width - 50, GUI_HEIGHT/2 - 10);
        
        // Status do modo de disparo (abaixo do placar)
        textSize(16);
        if (shootModeActive) {
            fill(255, 0, 0);
            text("MODO DISPARO: ATIVO (K para desativar)", width/2, GUI_HEIGHT/2 + 15);
        } else {
            fill(150);
            text("MODO DISPARO: INATIVO (K para ativar)", width/2, GUI_HEIGHT/2 + 15);
        }
        textSize(24);
        
        // Linha separadora
        stroke(150);
        line(0, GUI_HEIGHT, width, GUI_HEIGHT);
        noStroke();
    }
    
    void drawArena() {
        // Ajusta o desenho para a área da arena (abaixo da GUI)
        pushMatrix();
        translate(0, GUI_HEIGHT);
        
        fill(150); // Cor das paredes
        // Paredes: superior, inferior, esquerda, direita
        rect(0, 0, width, WALL_THICKNESS);
        rect(0, ARENA_HEIGHT - WALL_THICKNESS, width, WALL_THICKNESS);
        rect(0, 0, WALL_THICKNESS, ARENA_HEIGHT);
        rect(width - WALL_THICKNESS, 0, WALL_THICKNESS, ARENA_HEIGHT);
        
        popMatrix();
    }
    
    void updateGame() {
        // Atualiza o timer
        if (millis() - lastTimeUpdate > 1000) {
            gameTime--;
            lastTimeUpdate = millis();
            
            if (gameTime <= 0) {
                gameRunning = false;
                gameTime = 0;
                println("Game Over!");
                println("Blue Score: " + blueScore);
                println("Red Score: " + redScore);
            }
        }
        
        // Atualiza a posição do jogador
        updatePlayer();
        
        // Atualiza projéteis
        updateProjectiles();
        
        // Dispara projéteis do oponente se o modo estiver ativo
        if (shootModeActive && millis() - lastOpponentProjectileTime > OPPONENT_COOLDOWN) {
            projectiles.add(new Projectile(opponentX, opponentY, playerX, playerY, 1));
            lastOpponentProjectileTime = millis();
        }
    }
    
    void updatePlayer() {
        // Calcula aceleração baseada no tempo de pressão das teclas
        float currentAccelX = 0;
        float currentAccelY = 0;
        
        if (leftPressed) {
            leftPressedTime++;
            currentAccelX -= INITIAL_ACCELERATION + (leftPressedTime * ACCELERATION_INCREMENT);
        } else {
            leftPressedTime = 0;
        }
        
        if (rightPressed) {
            rightPressedTime++;
            currentAccelX += INITIAL_ACCELERATION + (rightPressedTime * ACCELERATION_INCREMENT);
        } else {
            rightPressedTime = 0;
        }
        
        if (upPressed) {
            upPressedTime++;
            currentAccelY -= INITIAL_ACCELERATION + (upPressedTime * ACCELERATION_INCREMENT);
        } else {
            upPressedTime = 0;
        }
        
        if (downPressed) {
            downPressedTime++;
            currentAccelY += INITIAL_ACCELERATION + (downPressedTime * ACCELERATION_INCREMENT);
        } else {
            downPressedTime = 0;
        }
        
        // Aplica aceleração
        playerSpeedX += currentAccelX;
        playerSpeedY += currentAccelY;
        
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
    
    void updateProjectiles() {
        // Atualiza todos os projéteis e remove os inativos
        for (int i = projectiles.size() - 1; i >= 0; i--) {
            Projectile p = projectiles.get(i);
            p.update();
            
            if (!p.active) {
                projectiles.remove(i);
            }
        }
    }
    
    void checkWallCollisions() {
        // Ajusta para coordenadas da arena (considerando a GUI)
        float arenaTop = GUI_HEIGHT;
        float arenaBottom = height;
        
        // Verifica colisão com paredes laterais
        if (playerX - PLAYER_SIZE/2 < WALL_THICKNESS) {
            playerX = WALL_THICKNESS + PLAYER_SIZE/2;
            playerSpeedX *= -0.7; // Rebote mais forte
            redScore += 2; // Pontos para o vermelho quando azul bate na parede
        } else if (playerX + PLAYER_SIZE/2 > width - WALL_THICKNESS) {
            playerX = width - WALL_THICKNESS - PLAYER_SIZE/2;
            playerSpeedX *= -0.7; // Rebote mais forte
            redScore += 2; // Pontos para o vermelho quando azul bate na parede
        }
        
        // Verifica colisão com paredes superior/inferior
        if (playerY - PLAYER_SIZE/2 < arenaTop + WALL_THICKNESS) {
            playerY = arenaTop + WALL_THICKNESS + PLAYER_SIZE/2;
            playerSpeedY *= -0.7; // Rebote mais forte
            redScore += 2; // Pontos para o vermelho quando azul bate na parede
        } else if (playerY + PLAYER_SIZE/2 > arenaBottom - WALL_THICKNESS) {
            playerY = arenaBottom - WALL_THICKNESS - PLAYER_SIZE/2;
            playerSpeedY *= -0.7; // Rebote mais forte
            redScore += 2; // Pontos para o vermelho quando azul bate na parede
        }
    }
    
    public void keyPressed() {
        // Atualiza o estado das teclas quando pressionadas
        if (keyCode == UP){ 
            upPressed = true;
            out.println("MOVE, UP");
        }else if (keyCode == DOWN){ 
            downPressed = true;
            out.println("MOVE, DOWN");
        }else if (keyCode == LEFT) 
            leftPressed = true;
            out.println("MOVE, LEFT");
        }else if (keyCode == RIGHT) 
            rightPressed = true;
            out.println("MOVE, RIGHT");
        }
        
        // Tecla K para ativar/desativar modo de disparo
        if (key == 'k' || key == 'K') {
            shootModeActive = !shootModeActive;
        }
        
        // Espaço para reiniciar o jogo
        if (key == ' ' && !gameRunning) {
            resetGame();
        }
    }
    
    public void keyReleased() {
        // Atualiza o estado das teclas quando liberadas
        if (keyCode == UP) {
            upPressed = false;
            out.println("STOP, UP");
        } else if (keyCode == DOWN){
            downPressed = false;
            out.println("STOP, DOWN");
        }else if (keyCode == LEFT){
            leftPressed = false;
            out.println("STOP, LEFT");
        }else if (keyCode == RIGHT){ 
            rightPressed = false;
            out.println("STOP, RIGHT");
        }
    }
    
    public void mousePressed() {
        // Dispara projétil quando o mouse é clicado
        if (gameRunning && millis() - lastPlayerProjectileTime > PLAYER_COOLDOWN) {
            projectiles.add(new Projectile(playerX, playerY, mouseX, mouseY, 0));
            lastPlayerProjectileTime = millis();
        }
    }
    
    void resetGame() {
        // Reinicia as posições
        playerX = width / 4;
        playerY = (height - GUI_HEIGHT) / 2 + GUI_HEIGHT;
        playerSpeedX = 0;
        playerSpeedY = 0;
        
        opponentX = 3 * width / 4;
        opponentY = (height - GUI_HEIGHT) / 2 + GUI_HEIGHT;
        
        // Reinicia os placares
        blueScore = 0;
        redScore = 0;
        gameTime = 120;
        
        // Limpa projéteis
        projectiles.clear();
        
        // Desativa modo de disparo
        shootModeActive = false;
        
        // Reinicia o jogo
        gameRunning = true;
        lastTimeUpdate = millis();
    }
    
    public void stop(){
        try{
            if(socket != null){
                socket.close();
            }
        }catch (IOException e){
            e.printStackTrace();
        }
        super.stop();
    }

    public static void main(String[] args) {
        PApplet.main("DueloArena");
    }

}
