import java.net.*;
import java.io.*;
import java.util.*;

public class Cliente {
    private Socket s;
    public String username = "";
    public String password = "";
    public boolean connected = true;
    public boolean logged = false;
    public Displayable cur;
    private String msg = "";

    public Cliente(String Ip, int portNumber) {
        try {
            this.s = new Socket(Ip, portNumber);
            (new SocketReader(this)).start();
            (new SocketWriter(this)).start();
        } catch (Exception e) {
            System.out.println("Failed to connect to server: " + e.getMessage());
        }
    }

    public synchronized void setMessage(String msg) {
        this.msg = msg;
    }

    public synchronized void Notify() {
        notifyAll();
    }

    public synchronized boolean sendMessageToServer() {
        while (msg.length() == 0) {
            try {
                wait();
            } catch (Exception e) {
                System.out.println(e.getMessage());
            }
        }
        String message = this.msg;

        switch (message) {
            case "online":
                break;
            case "queue":
                message += " " + this.username;
                break;
            case "logout":
                message += " " + this.username;
                break;
            case "get_queue": // Não sei se é necessário
                break;
            default:
                message += " " + this.username + " " + this.password;
                break;
        }
        message += "\n";

        try {
            DataOutputStream dout = new DataOutputStream(this.s.getOutputStream());
            dout.writeBytes(message);
            dout.flush();
            this.msg = "";
        } catch (Exception e) {
            System.out.println(e.getMessage());
        }

        return this.connected;
    }

    public boolean receiveMessageFromServer(Socket s) {
        String receive = "";
        try {
            BufferedReader b = new BufferedReader(new InputStreamReader(s.getInputStream()));
            receive = b.readLine();

            synchronized (this) {
                switch (receive) {
                    case "logged in":
                        this.cur = JoinGame;
                        this.logged = true;
                        this.cur.setMessages("\n" + receive);
                        break;
                    case "logged out":
                        this.cur = Inicial;
                        this.logged = false;
                        this.cur.setMessages("\n" + receive);
                        break;
                    case "queued":
                        this.cur = Queued;
                        this.cur.setMessages("\n" + receive);
                        break;
                    case "matched":
                        this.cur = Jogo;
                        this.cur.setMessages("\n" + receive);
                        break;
                    case "already queued": // Podíamos mudar para uma tela com um botão para sair da queue(botão cancelar tipo clash royale)
                        this.cur.setMessages("\n" + receive);
                        break;
                    default:
                        this.cur = logged ? JoinGame : Login;
                        this.cur.setMessages("\n" + receive);
                        break;
                }
            }
        } catch (Exception e) {
            this.cur.setMessages("\nLost server connection...");
            this.connected = false;
        }
        return this.connected;
    }
}

class SocketReader extends Thread {
    Cliente c;
    SocketReader(Cliente c) { 
        this.c = c;
    }
    
    @Override
    public void run() {
        boolean con = true;
        while (con) {
            try {
                con = c.receiveMessageFromServer(c.s);
            } catch (Exception e) {
                System.out.println("Erro ao ler do servidor: " + e.getMessage());
                con = false;
            }
        }
    }
}

class SocketWriter extends Thread {
    Cliente c;
    SocketWriter(Cliente c) { 
        this.c = c; 
    }
    
    @Override
    public void run() {
        boolean con = true;
        while (con) {
            try {
                con = c.sendMessageToServer();
            } catch (Exception e) {
                System.out.println("Erro ao escrever para o servidor: " + e.getMessage());
                con = false;
            }
        }
    }
}