import processing.core.*;
import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStreamReader;
import java.io.PrintWriter;
import java.net.Socket;
import javax.swing.JOptionPane;

public class DueloArena extends PApplet {
    // Game states
    final int STATE_IP_INPUT = 0;
    final int STATE_CONNECTING = 1;
    final int STATE_LOGIN = 2;
    final int STATE_CREATE_ACCOUNT = 3;
    final int STATE_QUEUE = 4;
    final int STATE_GAME = 5;
    int currentState = STATE_IP_INPUT;
    
    // Connection variables
    String serverIP = "";
    String inputIP = "";
    int serverPort = 1234;
    String inputPort = "1234";
    Socket socket;
    BufferedReader in;
    PrintWriter out;
    boolean connected = false;
    boolean enteringIP = true;
    
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
    String loggedInUsername = "";
    
    // Queue screen variables
    boolean inQueue = false;
    Button queueButton;
    
    // UI elements
    Button loginButton;
    Button createAccountButton;
    Button backToLoginButton;
    Button submitCreateButton;


    boolean upPressed = false;
    boolean downPressed = false;
    boolean leftPressed = false;
    boolean rightPressed = false;
    String opponentUsername = "";
    boolean isPlayer1 = false;
    
    public void settings() {
        size(800, 600);
    }

    public void setup() {
      // Default values for testing
      inputIP = "192.168.1.112";  // Default IP
      inputPort = "1234";     // Default port
      
      // Initialize buttons
      queueButton = new Button(width/2 - 100, height/2 - 25, 200, 50, "Enter Queue", color(200), color(0));
      loginButton = new Button(width/2 - 75, 320, 150, 40, "Login", color(0, 150, 0), color(255));
      createAccountButton = new Button(width/2 - 75, 380, 150, 40, "Create Account", color(50, 50, 200), color(255));
      backToLoginButton = new Button(width/2 - 75, 400, 150, 40, "Back to Login", color(150, 150, 150), color(255));
      submitCreateButton = new Button(width/2 - 75, 360, 150, 40, "Create Account", color(0, 150, 0), color(255));
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
                  drawGameScreen();
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
    
    void handleServerMessage(String message) {
        if (message.startsWith("MATCHED")) {
            String[] parts = message.split(" ");
            if (parts.length >= 2) {
                opponentUsername = parts[1];
                isPlayer1 = parts[1].equals(loggedInUsername);
                
                inQueue = false;
                currentState = STATE_GAME;
                queueButton.text = "Enter Queue";
            }
        }
    }
    
    void drawGameScreen() {
        // Draw arena background
        background(0, 50, 100);
        
        // Draw GUI area at the top
        fill(50);
        rect(0, 0, width, 70);
        
        // Draw player info
        fill(255);
        textAlign(LEFT, CENTER);
        textSize(16);
        text("Player: " + loggedInUsername, 20, 35);
        text("Opponent: " + opponentUsername, width/2 - 100, 35);
        
        // Draw arena boundaries
        fill(0);
        rect(0, 70, width, height - 70);
        
        // Draw player paddles (simple rectangles for now)
        fill(255);
        float paddleWidth = 20;
        float paddleHeight = 100;
        
        // Player 1 paddle (left side)
        float player1X = 50;
        float player1Y = height/2 - paddleHeight/2;
        rect(player1X, player1Y, paddleWidth, paddleHeight);
        
        // Player 2 paddle (right side)
        float player2X = width - 50 - paddleWidth;
        float player2Y = height/2 - paddleHeight/2;
        rect(player2X, player2Y, paddleWidth, paddleHeight);
        
        // Draw center line
        stroke(255);
        strokeWeight(2);
        line(width/2, 70, width/2, height);
        noStroke();
        
        // Draw controls instructions
        textAlign(CENTER, CENTER);
        textSize(14);
        text("Use arrow keys to move", width/2, height - 30);
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
        // Title
        fill(0);
        textAlign(CENTER, CENTER);
        textSize(32);
        text("Matchmaking", width/2, 100);
        
        // Queue status
        textSize(24);
        text(inQueue ? "Searching for opponent..." : "Press the button to queue", width/2, 180);
        
        // Draw queue button
        queueButton.display();
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
                // Your game mouse handling
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
        if (queueButton.isMouseOver()) {
            inQueue = !inQueue;
            queueButton.text = inQueue ? "Leave Queue" : "Enter Queue";
            
            if (connected) {
                out.println((inQueue ? "QUEUE:" : "UNQUEUE:") +  loggedInUsername);
            }
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
                    loggedInUsername = username; // Store the username
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
              if ("ACCOUNT_CREATED".equals(response)) {
                  // Server will automatically attempt login
                  String loginResponse = in.readLine();
                  if ("LOGIN_SUCCESS".equals(loginResponse)) {
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
    
    public void keyPressed() {
        switch(currentState) {
            case STATE_IP_INPUT:
                handleIPInputKeyPress();
                break;
            case STATE_LOGIN:
                handleLoginScreenKeyPress();
                break;
            case STATE_CREATE_ACCOUNT:
                handleCreateAccountKeyPress();
                break;
            case STATE_QUEUE:
            case STATE_GAME:
                // Your existing key handling
                break;
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
