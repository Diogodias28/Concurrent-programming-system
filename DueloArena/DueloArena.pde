import processing.core.*;
import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStreamReader;
import java.io.PrintWriter;
import java.net.Socket;
import javax.swing.JOptionPane;

public class DueloArena extends PApplet {
    // Configurações da arena
    final int ARENA_WIDTH = 800;
    final int ARENA_HEIGHT = 600;
    final int WALL_THICKNESS = 10;
    final int GUI_HEIGHT = 70;
    
    // Configurações do jogador
    final int PLAYER_SIZE = 30;
    final float MAX_SPEED = 6;
    final float FRICTION = 0.98f;
    final int PROJ_SIZE = 10;
    
    // Game states
    final int STATE_IP_INPUT = 0;
    final int STATE_CONNECTING = 1;
    final int STATE_LOGIN = 2;
    final int STATE_CREATE_ACCOUNT = 3;
    final int STATE_QUEUE = 4;
    final int STATE_GAME = 5;
    final int STATE_GAME_OVER = 6;
    int currentState = STATE_IP_INPUT;
    int gameTime = 0;
    int playerLevel = 1;
    int playerStreak = 0;
    
    // Connection variables
    String serverIP = "";
    String inputIP = "192.168.1.226";
    int serverPort = 1234;
    String inputPort = "1234";
    Socket socket;
    BufferedReader in;
    PrintWriter out;
    boolean connected = false;
    boolean enteringIP = true;
    
    // Player variables
    float playerX, playerY;
    float playerSpeedX, playerSpeedY;
    float opponentX, opponentY;
    boolean upPressed, downPressed, leftPressed, rightPressed;
    String loggedInUsername = "";
    String opponentUsername = "";
    boolean isPlayer1 = false;
    boolean inQueue = false;
    boolean moveUp = false;
    boolean moveDown = false;
    boolean moveLeft = false;
    boolean moveRight = false;
    
    // Login screen variables
    String username = "";
    String password = "";
    boolean enteringUsername = true;
    boolean loginError = false;
    String loginErrorMessage = "";
    
    // Create account variables
    String newUsername = "";
    String newPassword = "";
    String confirmPassword = "";
    boolean creatingUsername = true;
    boolean creatingPassword = false;
    boolean creatingConfirm = false;
    boolean createAccountError = false;
    String createAccountErrorMessage = "";
    
    boolean wasFocused = true;

    // Top 10 variables
    String[] top10Lines = {};
    boolean showTop10 = false;

    String winnerMessage = "";
    Button gameOverOkButton;
    
    int player1Score = 0, player2Score = 0;
    
    // Modifier colors
    final color MOD_GREEN = color(0, 255, 0);    // Type 1
    final color MOD_ORANGE = color(255, 165, 0); // Type 2
    final color MOD_BLUE = color(100, 100, 255); // Type 3 (lighter blue)
    final color MOD_RED = color(255, 100, 100);  // Type 4 (lighter red)
    final int MOD_SIZE = 20;                     // Size of modifier objects
    
    // UI elements
    Button queueButton;
    Button loginButton;
    Button createAccountButton;
    Button backToLoginButton;
    Button submitCreateButton;
    Button logoutButton;
    Button deleteAccountButton;
    Button top10Button;
    
    class Projectile {
      public float x,y;
      public String owner;
      public Projectile(float x, float y, String owner) {
        this.x = x;
        this.y = y;
        this.owner = owner;
      }
    }
    
    class Modifier {
        public float x, y;
        public int type;
        
        public Modifier(float x, float y, int type) {
            this.x = x;
            this.y = y;
            this.type = type;
        }
    }
    
    ArrayList<Projectile> projectiles = new ArrayList<>();
    ArrayList<Modifier> modifiers = new ArrayList<>();
    
    public void settings() {
        size(ARENA_WIDTH, ARENA_HEIGHT + GUI_HEIGHT);
    }

    public void setup() {
        // Initialize buttons
        queueButton = new Button(width/2 - 100, height/2 - 25, 200, 50, "Enter Queue", color(200), color(0));
        loginButton = new Button(width/2 - 75, 320, 150, 40, "Login", color(0, 150, 0), color(255));
        createAccountButton = new Button(width/2 - 75, 380, 150, 40, "Create Account", color(50, 50, 200), color(255));
        backToLoginButton = new Button(width/2 - 75, 400, 150, 40, "Back to Login", color(150, 150, 150), color(255));
        submitCreateButton = new Button(width/2 - 75, 360, 150, 40, "Create Account", color(0, 150, 0), color(255));
        gameOverOkButton = new Button(width/2 - 75, height/2 + 50, 150, 40, "OK", color(0, 150, 0), color(255));
        logoutButton = new Button(width/2 - 100, height/2 + 50, 200, 40, "Logout", color(200, 0, 0), color(255));
        deleteAccountButton = new Button(width/2 - 100, height/2 + 100, 200, 40, "Delete Account", color(150, 0, 0), color(255));
        top10Button = new Button(width/2 - 100, height/2 + 150, 200, 40, "Top 10", color(0, 0, 200), color(255));

        // Initialize player positions
        resetGamePositions();
    }

    void resetGamePositions() {
        playerX = width/4;
        playerY = (ARENA_HEIGHT)/2 + GUI_HEIGHT;
        playerSpeedX = 0;
        playerSpeedY = 0;
        
        opponentX = 3*width/4;
        opponentY = (ARENA_HEIGHT)/2 + GUI_HEIGHT;
    }
    
    public void draw() {
        background(240);
        checkServerMessages();
        
        switch(currentState) {
            case STATE_IP_INPUT:
                drawIPInputScreen();
                break;
            case STATE_CONNECTING:
                drawConnectingScreen();
                break;
            case STATE_LOGIN:
                drawLoginScreen();
                break;
            case STATE_CREATE_ACCOUNT:
                drawCreateAccountScreen();
                break;
            case STATE_QUEUE:
                drawQueueScreen();
                break;
            case STATE_GAME:
                if (focused != wasFocused) {
                    if (!focused) {
                        // Window lost focus
                        print("lost focus");
                        if (connected && out != null) {
                            out.println("KEY_RELEASE:UP"); upPressed = false;
                            out.println("KEY_RELEASE:DOWN"); downPressed = false;
                            out.println("KEY_RELEASE:LEFT"); leftPressed = false;
                            out.println("KEY_RELEASE:RIGHT"); rightPressed = false;
                        }
                    }
                    wasFocused = focused;
                }
                drawGameScreen();
                break;
            case STATE_GAME_OVER:
                drawGameOverScreen();
                break;
        }
    }
      
    void checkServerMessages() {
        if (connected && in != null) {
            try {
                while (in.ready()) {
                    String message = in.readLine();
                    if (message != null) {
                        handleServerMessage(message);
                    }
                }
            } catch (IOException e) {
                println("Error reading from server: " + e.getMessage());
            }
        }
    }
    
    void parseProjectiles(String projData) {
        projectiles.clear();
        
        // Clean the input string
        String clean = projData.replaceAll("\\s+", "")
                             .replace("\"", "")
                             .replace("[", "")
                             .replace("]", "");
        
        if (clean.isEmpty()) return;
        
        // Split into components
        String[] parts = clean.split(",");
        
        // Parse components in groups of 3 (x,y,owner)
        for (int i = 0; i < parts.length - 2; i += 3) {
            try {
                float x = Float.parseFloat(parts[i]);
                float y = Float.parseFloat(parts[i+1]);
                String owner = parts[i+2];
                projectiles.add(new Projectile(x, y, owner));
            } catch (NumberFormatException e) {
                System.err.println("Error parsing projectile at index " + i);
            }
        }
    }
    
    void parseModifiers(String modData) {
        modifiers.clear();
        
        // Clean the input string
        String clean = modData.replaceAll("\\s+", "")
                             .replace("\"", "")
                             .replace("[", "")
                             .replace("]", "");
        
        if (clean.isEmpty()) return;
        
        // Split into components
        String[] parts = clean.split(",");
        
        // Parse components in groups of 3 (x,y,type)
        for (int i = 0; i < parts.length - 2; i += 3) {
            try {
                float x = Float.parseFloat(parts[i]);
                float y = Float.parseFloat(parts[i+1]);
                int type = Integer.parseInt(parts[i+2]);
                modifiers.add(new Modifier(x, y, type));
            } catch (NumberFormatException e) {
                System.err.println("Error parsing modifier at index " + i);
            }
        }
    }

   void handleServerMessage(String message) {
        //println("Server message: " + message);

        if (message.startsWith("SERVER_SHUTDOWN")) {
            // Reset all relevant variables
            try { if (socket != null) socket.close(); } catch (Exception e) {}
            connected = false;
            inQueue = false;
            loggedInUsername = "";
            opponentUsername = "";
            playerLevel = 1;
            playerStreak = 0;
            isPlayer1 = false;
            projectiles.clear();
            modifiers.clear();
            winnerMessage = "";
            queueButton.text = "Enter Queue";
            // Reset any other game state variables you use
            // ...

            // Reset input fields
            username = "";
            password = "";
            loggedInUsername = "";
            newPassword = "";
            confirmPassword = "";
            creatingPassword = false;
            creatingConfirm = false;

            // Go to IP input screen
            currentState = STATE_IP_INPUT;

            JOptionPane.showMessageDialog(null, "O servidor foi desligado.");
            return;
        } else if (message.startsWith("MATCHED")) {
          String[] parts = message.split(" ");
          if (parts.length >= 3) {
              // First username in MATCHED message is always player1 (blue)
              isPlayer1 = parts[1].equals(loggedInUsername);
              opponentUsername = isPlayer1 ? parts[2] : parts[1];
              out.println("MATCH_FOUND:" + loggedInUsername);
              currentState = STATE_GAME;
              resetGamePositions();
          }
        }
        else if (message.startsWith("GAME_OVER:")) {
            winnerMessage = message.substring("GAME_OVER:".length()).trim();
            out.println("MATCH_ENDED:" + loggedInUsername);
            currentState = STATE_GAME_OVER;
            inQueue = false;
            queueButton.text = "Enter Queue";
        }
        else if (message.startsWith("STATS:")) {
            String[] stats = message.substring(6).split(",");
            if (stats.length >= 2) {
                playerLevel = Integer.parseInt(stats[0]);
                playerStreak = Integer.parseInt(stats[1]);
            }
        }
        else if (message.startsWith("TOP_10:")) {
            String top10Raw = message.substring(7).trim();
            if (top10Raw.isEmpty() || top10Raw.equals("EMPTY")) {
                top10Lines = new String[] { "Sem dados de Top 10." };
            } else {
                top10Lines = top10Raw.split("\\|\\|");
            }
            showTop10 = true;
        }
        else if (message.startsWith("P1:")) {
            // Split the message into components
            String[] components = message.split("\\|");
            
            // Create a map to store the values
            HashMap<String, String> gameState = new HashMap<String, String>();
            
            // Parse each component
            for (String component : components) {
                String[] keyValue = component.split(":", 2); // Split on first colon only
                if (keyValue.length == 2) {
                    gameState.put(keyValue[0], keyValue[1]);
                }
            }
            
            // Update positions based on which player we are
            if (gameState.containsKey("P1_POS") && gameState.containsKey("P2_POS")) {
                try {
                    // Parse positions (format "{x,y}")
                    String p1PosStr = gameState.get("P1_POS").replace("{", "").replace("}", "");
                    String p2PosStr = gameState.get("P2_POS").replace("{", "").replace("}", "");
                    
                    String[] p1Pos = p1PosStr.split(",");
                    String[] p2Pos = p2PosStr.split(",");
                    
                    float p1X = Float.parseFloat(p1Pos[0].trim());
                    float p1Y = Float.parseFloat(p1Pos[1].trim());
                    float p2X = Float.parseFloat(p2Pos[0].trim());
                    float p2Y = Float.parseFloat(p2Pos[1].trim());
                    
                    if (isPlayer1) {
                        playerX = p1X;
                        playerY = p1Y + GUI_HEIGHT; // Add GUI offset
                        opponentX = p2X;
                        opponentY = p2Y + GUI_HEIGHT; // Add GUI offset
                    } else {
                        playerX = p2X;
                        playerY = p2Y + GUI_HEIGHT; // Add GUI offset
                        opponentX = p1X;
                        opponentY = p1Y + GUI_HEIGHT; // Add GUI offset
                    }
                } catch (Exception e) {
                    println("Error parsing positions: " + e);
                    e.printStackTrace();
                }
            }
            
            // Update scores
            if (gameState.containsKey("P1_SCORE") && gameState.containsKey("P2_SCORE")) {
                try {
                    player1Score = Integer.parseInt(gameState.get("P1_SCORE"));
                    player2Score = Integer.parseInt(gameState.get("P2_SCORE"));
                } catch (NumberFormatException e) {
                    println("Error parsing scores: " + e);
                }
            }
            
            // Update time if needed
            if (gameState.containsKey("TIME")) {
                try {
                    gameTime = Integer.parseInt(gameState.get("TIME"));
                } catch (NumberFormatException e) {
                    println("Error parsing time: " + e);
                }
            }

          if (message.contains("PROJ:")) {
              String projData = message.substring(message.indexOf("PROJ:") + 5, 
                                               message.indexOf("|TIME:"));
              parseProjectiles(projData);
          }
          
          if (message.contains("MOD:")) {
              String modData = message.substring(message.indexOf("MOD:") + 4, 
                                       message.indexOf("|PROJ:"));
              parseModifiers(modData);
          }
   
        }
    }
    
    void drawModifiers() {
        for (Modifier m : modifiers) {
            // Set color based on modifier type
            switch(m.type) {
                case 1: fill(MOD_GREEN); break;
                case 2: fill(MOD_ORANGE); break;
                case 3: fill(MOD_BLUE); break;
                case 4: fill(MOD_RED); break;
                default: fill(150); // Default gray
            }
            
            // Draw modifier as a circle
            ellipse(m.x, m.y + GUI_HEIGHT, MOD_SIZE, MOD_SIZE);
        }
    }
    
   void drawGameScreen() {
        // Draw GUI
        drawGameGUI();
        
        // Draw arena walls
        drawArena();
        
        drawModifiers();
        
        // Determine which positions correspond to which player
        float blueX = isPlayer1 ? playerX : opponentX;
        float blueY = isPlayer1 ? playerY : opponentY;
        float redX = isPlayer1 ? opponentX : playerX;
        float redY = isPlayer1 ? opponentY : playerY;
        
        // Draw players with fixed colors
        fill(0, 0, 255); // Blue for player1
        ellipse(blueX, blueY, PLAYER_SIZE, PLAYER_SIZE);
        
        fill(255, 0, 0); // Red for player2
        ellipse(redX, redY, PLAYER_SIZE, PLAYER_SIZE);
        
        // Draw projectiles
        for (Projectile p : projectiles) {
            if (p.owner.equals(isPlayer1 ? loggedInUsername : opponentUsername)) {
                fill(0, 0, 255); // Blue for player1's projectiles
            } else {
                fill(255, 0, 0); // Red for player2's projectiles
            }
            ellipse(p.x, p.y + GUI_HEIGHT, PROJ_SIZE, PROJ_SIZE);
        }
    }
    
    void drawGameOverScreen() {
        // Dark overlay
        fill(0, 0, 0, 200);
        rect(0, 0, width, height);
        
        // Winner message
        fill(255);
        textAlign(CENTER, CENTER);
        textSize(32);
        text(winnerMessage, width/2, height/2 - 30);
        
        // OK button
        gameOverOkButton.display();
    }
        
      void drawGameGUI() {
          fill(220);
          rect(0, 0, width, GUI_HEIGHT);
          
          // Player info and scores
          textAlign(LEFT, CENTER);
          textSize(16);
          
          // Player 1 (blue) info - always left
          fill(0, 0, 255); // Blue
          String p1Name = isPlayer1 ? loggedInUsername : opponentUsername;
          text("Player 1: " + p1Name, 20, GUI_HEIGHT/3);
          textSize(24);
          text(str(player1Score), 20, 2*GUI_HEIGHT/3);
          
          // Player 2 (red) info - always right
          fill(255, 0, 0); // Red
          textAlign(RIGHT, CENTER);
          String p2Name = isPlayer1 ? opponentUsername : loggedInUsername;
          text("Player 2: " + p2Name, width - 20, GUI_HEIGHT/3);
          textSize(24);
          text(str(player2Score), width - 20, 2*GUI_HEIGHT/3);
          
          // Timer in center top
          fill(0); // Black for timer
          textAlign(CENTER, CENTER);
          textSize(32);
          
          // Format time as MM:SS
          int minutes = gameTime / 60;
          int seconds = gameTime % 60;
          String timeString = nf(minutes, 2) + ":" + nf(seconds, 2);
          text(timeString, width/2, GUI_HEIGHT/2);
          
          // Separator line
          stroke(150);
          line(0, GUI_HEIGHT, width, GUI_HEIGHT);
          noStroke();
      }
    
    void drawArena() {
        fill(150);
        // Top wall
        rect(0, GUI_HEIGHT, width, WALL_THICKNESS);
        // Bottom wall
        rect(0, height - WALL_THICKNESS, width, WALL_THICKNESS);
        // Left wall
        rect(0, GUI_HEIGHT, WALL_THICKNESS, ARENA_HEIGHT);
        // Right wall
        rect(width - WALL_THICKNESS, GUI_HEIGHT, WALL_THICKNESS, ARENA_HEIGHT);
    }


    public void keyPressed() {
        if (currentState == STATE_GAME && focused) {
            switch (key) {
                case 'w': case 'W':
                    if (!upPressed) {
                        out.println("KEY_PRESS:UP");
                        upPressed = true;
                    }
                    break;
                case 's': case 'S':
                    if (!downPressed) {
                        out.println("KEY_PRESS:DOWN");
                        downPressed = true;
                    }
                    break;
                case 'a': case 'A':
                    if (!leftPressed) {
                        out.println("KEY_PRESS:LEFT");
                        leftPressed = true;
                    }
                    break;
                case 'd': case 'D':
                    if (!rightPressed) {
                        out.println("KEY_PRESS:RIGHT");
                        rightPressed = true;
                    }
                    break;
            }
        } else {
            switch (currentState) {
                case STATE_IP_INPUT:
                    handleIPInputKeyPress();
                    break;
                case STATE_LOGIN:
                    handleLoginScreenKeyPress();
                    break;
                case STATE_CREATE_ACCOUNT:
                    handleCreateAccountKeyPress();
                    break;
            }
        }
    }

    public void keyReleased() {
        if (currentState == STATE_GAME && focused) {
            switch (key) {
                case 'w': case 'W':
                    if (upPressed) {
                        out.println("KEY_RELEASE:UP");
                        upPressed = false;
                    }
                    break;
                case 's': case 'S':
                    if (downPressed) {
                        out.println("KEY_RELEASE:DOWN");
                        downPressed = false;
                    }
                    break;
                case 'a': case 'A':
                    if (leftPressed) {
                        out.println("KEY_RELEASE:LEFT");
                        leftPressed = false;
                    }
                    break;
                case 'd': case 'D':
                    if (rightPressed) {
                        out.println("KEY_RELEASE:RIGHT");
                        rightPressed = false;
                    }
                    break;
            }
        }
    }

    void updatePositionsFromServer() {
        if (connected && in != null) {
            try {
                while (in.ready()) {
                    String message = in.readLine();
                    if (message.startsWith("POS:")) {
                        String[] parts = message.split(":");
                        playerX = Float.parseFloat(parts[1]);
                        playerY = Float.parseFloat(parts[2]);
                        opponentX = Float.parseFloat(parts[3]);
                        opponentY = Float.parseFloat(parts[4]);
                    }
                }
            } catch (IOException e) {
                println("Erro ao ler do servidor: " + e.getMessage());
            }
        }
    }

    void drawIPInputScreen() {
        // Title
        fill(0);
        textAlign(CENTER, CENTER);
        textSize(32);
        text("Server Connection", width/2, 100);
        
        // IP field (show default value if empty)
        fill(255);
        rect(width/2 - 150, 200, 300, 40);
        fill(enteringIP ? 0 : 100);
        textAlign(LEFT, CENTER);
        textSize(20);
        String ipDisplay = inputIP.isEmpty() ? "" : inputIP;
        text(ipDisplay + (enteringIP ? "|" : ""), width/2 - 140, 220);
        
        // Port field (show default value if empty)
        fill(255);
        rect(width/2 - 150, 260, 300, 40);
        fill(!enteringIP ? 0 : 100);
        String portDisplay = inputPort.isEmpty() ? "" : inputPort;
        text(portDisplay + (!enteringIP ? "|" : ""), width/2 - 140, 280);
        
        // Connect button
        loginButton.display();
        loginButton.text = "Connect";
        loginButton.y = 320;
    }
        
    void drawConnectingScreen() {
        fill(0);
        textAlign(CENTER, CENTER);
        textSize(24);
        text("Connecting to " + serverIP + ":" + serverPort + "...", width/2, height/2);
    }
    
    void drawLoginScreen() {
        // Title
        fill(0);
        textAlign(CENTER, CENTER);
        textSize(32);
        text("Login", width/2, 100);
        
        // Error message
        if (loginError) {
            fill(255, 0, 0);
            textSize(16);
            text(loginErrorMessage, width/2, 140);
        }
        
        // Username field
        fill(255);
        rect(width/2 - 150, 200, 300, 40);
        fill(enteringUsername ? 0 : 100);
        textAlign(LEFT, CENTER);
        textSize(20);
        text(username.isEmpty() ? (enteringUsername ? "|" : "Username") : username, width/2 - 140, 220);
        
        // Password field
        fill(255);
        rect(width/2 - 150, 260, 300, 40);
        fill(!enteringUsername ? 0 : 100);
        String passwordDisplay = "";
        for (int i = 0; i < password.length(); i++) passwordDisplay += "*";
        text(password.isEmpty() ? (!enteringUsername ? "|" : "Password") : passwordDisplay, width/2 - 140, 280);
        passwordDisplay = ""; // Clear the display variable
        
        // Login button
        loginButton.display();
        loginButton.text = "Login";
        loginButton.y = 320;
        
        // Create Account button
        createAccountButton.display();
        createAccountButton.y = 380;
    }
    
    void drawCreateAccountScreen() {
        // Title
        fill(0);
        textAlign(CENTER, CENTER);
        textSize(32);
        text("Create Account", width/2, 80);
        
        // Error message
        if (createAccountError) {
            fill(255, 0, 0);
            textSize(16);
            text(createAccountErrorMessage, width/2, 120);
        }
        
        // Username field
        fill(255);
        rect(width/2 - 150, 160, 300, 40);
        fill(creatingUsername ? 0 : 100);
        textAlign(LEFT, CENTER);
        textSize(20);
        text(newUsername.isEmpty() ? (creatingUsername ? "|" : "New Username") : newUsername, width/2 - 140, 180);
        
        // Password field
        fill(255);
        rect(width/2 - 150, 220, 300, 40);
        fill(creatingPassword ? 0 : 100);
        String newPasswordDisplay = "";
        for (int i = 0; i < newPassword.length(); i++) newPasswordDisplay += "*";
        text(newPassword.isEmpty() ? (creatingPassword ? "|" : "New Password") : newPasswordDisplay, width/2 - 140, 240);
        
        // Confirm Password field
        fill(255);
        rect(width/2 - 150, 280, 300, 40);
        fill(creatingConfirm ? 0 : 100);
        String confirmPasswordDisplay = "";
        for (int i = 0; i < confirmPassword.length(); i++) confirmPasswordDisplay += "*";
        text(confirmPassword.isEmpty() ? (creatingConfirm ? "|" : "Confirm Password") : confirmPasswordDisplay, width/2 - 140, 300);
        
        // Create Account button
        submitCreateButton.display();
        
        // Back to Login button
        backToLoginButton.display();
    }
    
    void drawQueueScreen() {
        background(240);
        
        // Title (unchanged)
        fill(0);
        textAlign(CENTER, CENTER);
        textSize(32);
        text("Matchmaking", width/2, 100);
        
        // Queue status (unchanged)
        textSize(24);
        text(inQueue ? "Searching for opponent..." : "Press the button to queue", width/2, 180);
        
        // Draw queue button (unchanged)
        queueButton.display();
        
        // Draw logout and delete account buttons (unchanged)
        logoutButton.display();
        deleteAccountButton.display();

        // Draw top 10 button
        top10Button.display();
    
        // Player stats panel on the right side
        drawPlayerStatsPanel();

        if (showTop10) {
            drawTop10Screen();
        }
    }
    
    void drawPlayerStatsPanel() {
        // Panel background
        fill(220);
        noStroke();
        rect(width - 250, 50, 200, 150, 10);
        
        // Panel title
        fill(0);
        textAlign(CENTER, CENTER);
        textSize(20);
        text("Your Stats", width - 150, 80);
        
        // Player name
        textAlign(LEFT, CENTER);
        textSize(16);

        text("Player: " + loggedInUsername, width - 240, 110);
        
        // Level with icon
        fill(0, 100, 200); // Blue for level
        text("Level: " + playerLevel, width - 240, 140);
        
        // Streak with icon
        fill(200, 100, 0); // Orange for streak
        text("Streak: " + playerStreak, width - 240, 170);
        
        // Reset fill color
        fill(0);
    }

    void drawTop10Screen() {
        fill(255, 240);
        rect(width/2 - 220, height/2 - 180, 440, 360, 16);
        fill(0);
        textAlign(CENTER, TOP);
        textSize(28);
        text("Top 10 Jogadores", width/2, height/2 - 160);
        textSize(18);
        for (int i = 0; i < top10Lines.length; i++) {
            text((i+1) + ". " + top10Lines[i], width/2, height/2 - 120 + i*28);
        }
        // Botão para fechar
        fill(200,0,0);
        rect(width/2 + 160, height/2 - 170, 40, 40, 10);
        fill(255);
        textSize(24);
        text("X", width/2 + 180, height/2 - 155);
    }
        
    public void mousePressed() {
        switch(currentState) {
            case STATE_IP_INPUT:
                handleIPInputClick();
                break;
            case STATE_LOGIN:
                handleLoginScreenClick();
                break;
            case STATE_CREATE_ACCOUNT:
                handleCreateAccountClick();
                break;
            case STATE_QUEUE:
                handleQueueScreenClick();
                break;
            case STATE_GAME:
                handleProjectilesLaunchClick();
                break;
            case STATE_GAME_OVER:
              if (gameOverOkButton.isMouseOver()) {
                  currentState = STATE_QUEUE;
              }
              break;
        }
    }
    
    void handleIPInputClick() {
        // Check if clicked on IP field
        if (mouseX > width/2 - 150 && mouseX < width/2 + 150 && 
            mouseY > 200 && mouseY < 240) {
            enteringIP = true;
            return;
        }
        
        // Check if clicked on Port field
        if (mouseX > width/2 - 150 && mouseX < width/2 + 150 && 
            mouseY > 260 && mouseY < 300) {
            enteringIP = false;
            return;
        }
        
        // Check if clicked on Connect button
        if (loginButton.isMouseOver()) {
            attemptConnection();
            return;
        }
    }
    
    void handleLoginScreenClick() {
        // Check if clicked on username field
        if (mouseX > width/2 - 150 && mouseX < width/2 + 150 && 
            mouseY > 200 && mouseY < 240) {
            enteringUsername = true;
            return;
        }
        
        // Check if clicked on password field
        if (mouseX > width/2 - 150 && mouseX < width/2 + 150 && 
            mouseY > 260 && mouseY < 300) {
            enteringUsername = false;
            return;
        }
        
        // Check if clicked on login button
        if (loginButton.isMouseOver()) {
            attemptLogin();
            return;
        }
        
        // Check if clicked on create account button
        if (createAccountButton.isMouseOver()) {
            switchToCreateAccount();
            return;
        }
    }
    
    void handleCreateAccountClick() {
        // Check if clicked on username field
        if (mouseX > width/2 - 150 && mouseX < width/2 + 150 && 
            mouseY > 160 && mouseY < 200) {
            creatingUsername = true;
            creatingPassword = false;
            creatingConfirm = false;
            return;
        }
        
        // Check if clicked on password field
        if (mouseX > width/2 - 150 && mouseX < width/2 + 150 && 
            mouseY > 220 && mouseY < 260) {
            creatingUsername = false;
            creatingPassword = true;
            creatingConfirm = false;
            return;
        }
        
        // Check if clicked on confirm password field
        if (mouseX > width/2 - 150 && mouseX < width/2 + 150 && 
            mouseY > 280 && mouseY < 320) {
            creatingUsername = false;
            creatingPassword = false;
            creatingConfirm = true;
            return;
        }
        
        // Check if clicked on create account button
        if (submitCreateButton.isMouseOver()) {
            attemptCreateAccount();
            return;
        }
        
        // Check if clicked on back to login button
        if (backToLoginButton.isMouseOver()) {
            currentState = STATE_LOGIN;
            createAccountError = false;
            return;
        }
    }
    
    void handleQueueScreenClick() {
        if (showTop10) {
            // Se clicar no X fecha o painel
            if (mouseX > width/2 + 160 && mouseX < width/2 + 200 &&
                mouseY > height/2 - 170 && mouseY < height/2 - 130) {
                showTop10 = false;
                return;
            }
        }
        if (queueButton.isMouseOver()) {
            inQueue = !inQueue;
            queueButton.text = inQueue ? "Leave Queue" : "Enter Queue";
            
            if (connected) {
                out.println((inQueue ? "QUEUE:" : "UNQUEUE:") + loggedInUsername);
            }
        }
        else if (logoutButton.isMouseOver()) {
            if (connected) {
                out.println("LOGOUT:" + loggedInUsername);
                try {
                    String response = in.readLine();
                    if ("LOGOUT_SUCCESS".equals(response)) {
                        // Reset all relevant states
                        loggedInUsername = "";
                        username = "";
                        password = "";
                        playerLevel = 1;
                        playerStreak = 0;
                        inQueue = false;
                        queueButton.text = "Enter Queue";
                        player1Score = 0;
                        player2Score = 0;
                        currentState = STATE_LOGIN;
                        
                        // Clear any game state
                        resetGamePositions();
                        
                        // Reset movement flags
                        moveUp = moveDown = moveLeft = moveRight = false;
                    }
                } catch (IOException e) {
                    println("Error during logout: " + e.getMessage());
                }
            }
        }
        else if (deleteAccountButton.isMouseOver()) {
            String password = JOptionPane.showInputDialog(null, "Enter password to delete account:");
            if (password != null && !password.isEmpty()) {
                if (connected) {
                    out.println("CLOSE_ACCOUNT:" + loggedInUsername + ":" + password);
                    try {
                        String response = in.readLine();
                        if ("ACCOUNT_CLOSED".equals(response)) {
                            loggedInUsername = "";
                            currentState = STATE_LOGIN;
                            inQueue = false;
                            queueButton.text = "Enter Queue";
                            JOptionPane.showMessageDialog(null, "Account deleted successfully");
                        } else {
                            JOptionPane.showMessageDialog(null, "Account deletion failed");
                        }
                    } catch (IOException e) {
                        println("Error during account deletion: " + e.getMessage());
                    }
                }
            }
        }
        else if (top10Button.isMouseOver()) {
            if (connected) {
            out.println("TOP_10:" + loggedInUsername);
            }
        }
    }

      void handleProjectilesLaunchClick() {
          if (connected && out != null) {
              // Use our own position (playerX/Y) since that's always correct for our player
              float centerX = playerX;
              float centerY = playerY;
      
              float dx = mouseX - centerX;
              float dy = mouseY - centerY;
              float angle = atan2(dy, dx);
      
              out.println(String.format("LAUNCH_PROJ:%.2f", angle));
          }
      }
    
    void attemptConnection() {
        if (inputIP.isEmpty() || inputPort.isEmpty()) {
            JOptionPane.showMessageDialog(null, "Please enter both IP and Port");
            return;
        }
        
        try {
            serverIP = inputIP;
            serverPort = Integer.parseInt(inputPort);
            currentState = STATE_CONNECTING;
            
            // Connect in a new thread to avoid freezing the UI
            new Thread(() -> {
                try {
                    socket = new Socket(serverIP, serverPort);
                    in = new BufferedReader(new InputStreamReader(socket.getInputStream()));
                    out = new PrintWriter(socket.getOutputStream(), true);
                    connected = true;
                    
                    // Switch to login screen on success
                    currentState = STATE_LOGIN;
                } catch (Exception e) {
                    JOptionPane.showMessageDialog(null, 
                        "Connection failed: " + e.getMessage());
                    currentState = STATE_IP_INPUT;
                }
            }).start();
        } catch (NumberFormatException e) {
            JOptionPane.showMessageDialog(null, "Invalid port number");
        }
    }
    
    void attemptLogin() {
        if (username.isEmpty() || password.isEmpty()) {
            loginError = true;
            loginErrorMessage = "Please enter both username and password";
            return;
        }
        
        if (connected) {
            out.println("LOGIN:" + username + ":" + password);
            
            try {
                String response = in.readLine();
                if ("LOGIN_SUCCESS".equals(response)) {
                    loggedInUsername = username;
                    currentState = STATE_QUEUE;
                    loginError = false;
                } else {
                    loginError = true;
                    loginErrorMessage = "Login failed. Please try again.";
                }
            } catch (IOException e) {
                loginError = true;
                loginErrorMessage = "Connection error during login";
            }
        }
    }
        
    void switchToCreateAccount() {
        currentState = STATE_CREATE_ACCOUNT;
        newUsername = "";
        newPassword = "";
        confirmPassword = "";
        creatingUsername = true;
        creatingPassword = false;
        creatingConfirm = false;
        createAccountError = false;
    }
        
    void attemptCreateAccount() {
        if (newUsername.isEmpty() || newPassword.isEmpty() || confirmPassword.isEmpty()) {
            createAccountError = true;
            createAccountErrorMessage = "Please fill all fields";
            return;
        }
        
        if (!newPassword.equals(confirmPassword)) {
            createAccountError = true;
            createAccountErrorMessage = "Passwords don't match";
            return;
        }
        
        if (newPassword.length() < 6) {
            createAccountError = true;
            createAccountErrorMessage = "Password must be at least 6 characters";
            return;
        }
        
        if (connected) {
            out.println("CREATE_ACCOUNT:" + newUsername + ":" + newPassword);
            
            try {
                String response = in.readLine();
                print(response + "\n");
                if ("ACCOUNT_CREATED".equals(response)) {
                    // Server will automatically attempt login
                    String loginResponse = in.readLine();
                    print(loginResponse + "\n");
                    if ("LOGIN_SUCCESS".equals(loginResponse)) {
                        loggedInUsername = newUsername;
                        currentState = STATE_QUEUE;
                        createAccountError = false;
                        loginError = false;
                    } else {
                        createAccountError = false;
                        loginError = true;
                        loginErrorMessage = "Account created but login failed";
                    }
                } else if ("USERNAME_TAKEN".equals(response)) {
                    createAccountError = true;
                    createAccountErrorMessage = "Username already taken";
                } else {
                    createAccountError = true;
                    createAccountErrorMessage = "Account creation failed";
                }
            } catch (IOException e) {
                createAccountError = true;
                createAccountErrorMessage = "Connection error during account creation";
            }
        }
    }
    
    void handleIPInputKeyPress() {
        if (key == BACKSPACE) {
            if (enteringIP && inputIP.length() > 0) {
                inputIP = inputIP.substring(0, inputIP.length() - 1);
            } else if (!enteringIP && inputPort.length() > 0) {
                inputPort = inputPort.substring(0, inputPort.length() - 1);
            }
        } else if (key == TAB) {
            enteringIP = !enteringIP;
        } else if (key == ENTER || key == RETURN) {
            attemptConnection();
        } else if (key >= 32 && key <= 126) { // Printable characters
            if (enteringIP) {
                inputIP += key;
            } else {
                // Only allow numbers for port
                if (Character.isDigit(key)) {
                    inputPort += key;
                }
            }
        }
    }
    
    void handleLoginScreenKeyPress() {
        if (key == BACKSPACE) {
            if (enteringUsername && username.length() > 0) {
                username = username.substring(0, username.length() - 1);
            } else if (!enteringUsername && password.length() > 0) {
                password = password.substring(0, password.length() - 1);
            }
        } else if (key == TAB) {
            enteringUsername = !enteringUsername;
        } else if (key == ENTER || key == RETURN) {
            attemptLogin();
        } else if (key >= 32 && key <= 126) { // Printable characters
            if (enteringUsername) {
                username += key;
            } else {
                password += key;
            }
        }
    }
    
    void handleCreateAccountKeyPress() {
        if (key == BACKSPACE) {
            if (creatingUsername && newUsername.length() > 0) {
                newUsername = newUsername.substring(0, newUsername.length() - 1);
            } else if (creatingPassword && newPassword.length() > 0) {
                newPassword = newPassword.substring(0, newPassword.length() - 1);
            } else if (creatingConfirm && confirmPassword.length() > 0) {
                confirmPassword = confirmPassword.substring(0, confirmPassword.length() - 1);
            }
        } else if (key == TAB) {
            if (creatingUsername) {
                creatingUsername = false;
                creatingPassword = true;
                creatingConfirm = false;
            } else if (creatingPassword) {
                creatingUsername = false;
                creatingPassword = false;
                creatingConfirm = true;
            } else {
                creatingUsername = true;
                creatingPassword = false;
                creatingConfirm = false;
            }
        } else if (key == ENTER || key == RETURN) {
            attemptCreateAccount();
        } else if (key >= 32 && key <= 126) { // Printable characters
            if (creatingUsername) {
                newUsername += key;
            } else if (creatingPassword) {
                newPassword += key;
            } else if (creatingConfirm) {
                confirmPassword += key;
            }
        }
    }
    
    class Button {
        float x, y, w, h;
        String text;
        color bgColor;
        color textColor;
        
        Button(float x, float y, float w, float h, String text, color bgColor, color textColor) {
            this.x = x;
            this.y = y;
            this.w = w;
            this.h = h;
            this.text = text;
            this.bgColor = bgColor;
            this.textColor = textColor;
        }
        
        void display() {
            fill(bgColor);
            rect(x, y, w, h, 5);
            fill(textColor);
            textAlign(CENTER, CENTER);
            textSize(18);
            text(text, x + w/2, y + h/2);
        }
        
        boolean isMouseOver() {
            return mouseX > x && mouseX < x + w && mouseY > y && mouseY < y + h;
        }
    }
    
    public void stop() {
        try {
            if (socket != null) {
                socket.close();
            }
        } catch (IOException e) {
            e.printStackTrace();
        }
        super.stop();
    }
    
    public static void main(String[] args) {
        PApplet.main("DueloArena");
    }
}
