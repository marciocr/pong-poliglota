import java.lang.foreign.Arena;
import java.lang.foreign.MemorySegment;
import java.util.concurrent.ThreadLocalRandom;

import static java.lang.foreign.ValueLayout.JAVA_BYTE;
import static java.lang.foreign.ValueLayout.JAVA_INT;
import static java.lang.foreign.ValueLayout.JAVA_SHORT;

/** Pong em Java com SDL2, chamando a libSDL2 via API FFM (Java 22+). */
public final class Pong {
    static final int W = 640, H = 480;
    static final int PADDLE_W = 10, PADDLE_H = 60, PADDLE_MARGIN = 20;
    static final int BALL = 10;
    static final double PADDLE_SPEED = 400.0;
    static final double BALL_SPEED = 300.0;
    static final double BALL_MAX = 720.0;
    static final double SPEEDUP = 1.07;
    static final double STEP = 1.0 / 120.0;
    static final double SERVE_DELAY = 1.0;
    static final int RATE = 44100;

    // Fonte 3x5 para os dígitos do placar.
    static final String[] DIGITS = {
        "111101101101111", "001001001001001", "111001111100111", "111001111001111",
        "101101111001001", "111100111001111", "111100111101111", "111001001001001",
        "111101111101111", "111101111001111",
    };

    /** Onda quadrada mono S16: um "beep" de console Atari. */
    static MemorySegment squareWave(Arena arena, int freq, int ms) {
        short[] buf = new short[RATE * ms / 1000];
        for (int i = 0; i < buf.length; i++)
            buf[i] = (short) (((long) i * 2 * freq / RATE) % 2 == 1 ? 4000 : -4000);
        return arena.allocateFrom(JAVA_SHORT, buf);
    }

    static double clamp(double v, double lo, double hi) { return Math.max(lo, Math.min(hi, v)); }

    static boolean overlapsY(double by, double py) { return by + BALL >= py && by <= py + PADDLE_H; }

    static final class Game {
        double leftY = (H - PADDLE_H) / 2.0, rightY = (H - PADDLE_H) / 2.0;
        double bx, by, vx, vy, speed = BALL_SPEED;
        double serveTimer, serveDir = 1;
        int scoreL, scoreR;

        final int audio;
        final MemorySegment sndPaddle, sndWall, sndScore;

        Game(Arena arena, int audio) {
            this.audio = audio;
            sndPaddle = squareWave(arena, 460, 50);
            sndWall = squareWave(arena, 230, 50);
            sndScore = squareWave(arena, 490, 250);
        }

        void play(MemorySegment s) {
            if (audio == 0) return;
            Sdl.clearQueuedAudio(audio);
            Sdl.queueAudio(audio, s);
        }

        void resetBall(double dir) {
            bx = (W - BALL) / 2.0;
            by = (H - BALL) / 2.0;
            vx = vy = 0;
            speed = BALL_SPEED;
            serveDir = dir;
            serveTimer = SERVE_DELAY;
        }

        void launch() {
            double a = ThreadLocalRandom.current().nextDouble(-Math.PI / 6, Math.PI / 6);
            vx = serveDir * speed * Math.cos(a);
            vy = speed * Math.sin(a);
        }

        void bounce(double dir, double paddleY) {
            speed = Math.min(speed * SPEEDUP, BALL_MAX);
            double rel = ((by + BALL / 2.0) - (paddleY + PADDLE_H / 2.0)) / (PADDLE_H / 2.0);
            // Direção (1, t) normalizada, com t = tan do ângulo de saída (até 45° na borda da
            // raquete). Usa só sqrt, que o IEEE 754 exige arredondado corretamente: sin/cos
            // diferem no último bit entre as bibliotecas de cada linguagem, e num rali longo
            // essa diferença cresce até separar as versões.
            double t = clamp(rel, -1, 1);
            double len = Math.sqrt(1 + t * t);
            vx = dir * speed / len;
            vy = speed * t / len;
            play(sndPaddle);
        }

        void update(MemorySegment keys, double dt) {
            if (pressed(keys, Sdl.SCANCODE_W)) leftY -= PADDLE_SPEED * dt;
            if (pressed(keys, Sdl.SCANCODE_S)) leftY += PADDLE_SPEED * dt;
            if (pressed(keys, Sdl.SCANCODE_UP)) rightY -= PADDLE_SPEED * dt;
            if (pressed(keys, Sdl.SCANCODE_DOWN)) rightY += PADDLE_SPEED * dt;
            leftY = clamp(leftY, 0, H - PADDLE_H);
            rightY = clamp(rightY, 0, H - PADDLE_H);

            if (serveTimer > 0) {
                serveTimer -= dt;
                if (serveTimer <= 0) launch();
                return;
            }

            bx += vx * dt;
            by += vy * dt;

            if (by < 0) { by = 0; vy = Math.abs(vy); play(sndWall); }
            if (by + BALL > H) { by = H - BALL; vy = -Math.abs(vy); play(sndWall); }

            final double lx = PADDLE_MARGIN, rx = W - PADDLE_MARGIN - PADDLE_W;
            if (vx < 0 && bx <= lx + PADDLE_W && bx + BALL >= lx && overlapsY(by, leftY)) {
                bx = lx + PADDLE_W;
                bounce(1, leftY);
            }
            if (vx > 0 && bx + BALL >= rx && bx <= rx + PADDLE_W && overlapsY(by, rightY)) {
                bx = rx - BALL;
                bounce(-1, rightY);
            }

            if (bx + BALL < 0) { scoreR++; play(sndScore); resetBall(-1); }
            if (bx > W) { scoreL++; play(sndScore); resetBall(1); }
        }
    }

    static boolean pressed(MemorySegment keys, int scancode) { return keys.get(JAVA_BYTE, scancode) != 0; }

    static final class Renderer {
        final MemorySegment r, rect;

        Renderer(Arena arena, MemorySegment r) {
            this.r = r;
            this.rect = arena.allocate(16);  // SDL_Rect = 4 x int
        }

        void fill(double x, double y, int w, int h) {
            rect.set(JAVA_INT, 0, (int) x);
            rect.set(JAVA_INT, 4, (int) y);
            rect.set(JAVA_INT, 8, w);
            rect.set(JAVA_INT, 12, h);
            Sdl.renderFillRect(r, rect);
        }

        /** Desenha um número; alignRight=true faz o número terminar em x. */
        void drawNumber(int n, int x, int y, boolean alignRight) {
            final int s = 8;
            String text = Integer.toString(n);
            if (alignRight) x -= text.length() * 3 * s + (text.length() - 1) * s;
            for (char c : text.toCharArray()) {
                String g = DIGITS[c - '0'];
                for (int i = 0; i < 15; i++)
                    if (g.charAt(i) == '1') fill(x + (i % 3) * s, y + (i / 3) * s, s, s);
                x += 4 * s;
            }
        }

        void render(Game g) {
            Sdl.setRenderDrawColor(r, 0, 0, 0, 255);
            Sdl.renderClear(r);
            Sdl.setRenderDrawColor(r, 255, 255, 255, 255);
            for (int y = 6; y < H; y += 24) fill(W / 2 - 2, y, 4, 12);
            drawNumber(g.scoreL, W / 2 - 40, 20, true);
            drawNumber(g.scoreR, W / 2 + 40, 20, false);
            fill(PADDLE_MARGIN, g.leftY, PADDLE_W, PADDLE_H);
            fill(W - PADDLE_MARGIN - PADDLE_W, g.rightY, PADDLE_W, PADDLE_H);
            fill(g.bx, g.by, BALL, BALL);
            Sdl.renderPresent(r);
        }
    }

    public static void main(String[] args) {
        try (Arena arena = Arena.ofConfined()) {
            System.exit(run(arena));
        }
    }

    static int run(Arena arena) {
        if (Sdl.init(Sdl.INIT_VIDEO | Sdl.INIT_AUDIO) != 0) {
            System.err.println("SDL_Init: " + Sdl.getError());
            return 1;
        }
        MemorySegment win = Sdl.createWindow(arena.allocateFrom("Pong - Java"), Sdl.WINDOWPOS_CENTERED,
                Sdl.WINDOWPOS_CENTERED, W, H, Sdl.WINDOW_SHOWN);
        MemorySegment ren = win.equals(MemorySegment.NULL) ? MemorySegment.NULL
                : Sdl.createRenderer(win, -1, Sdl.RENDERER_ACCELERATED | Sdl.RENDERER_PRESENTVSYNC);
        if (ren.equals(MemorySegment.NULL)) {
            System.err.println("janela/renderer: " + Sdl.getError());
            return 1;
        }

        // SDL_AudioSpec: freq (0), format (4), channels (6), samples (8); 32 bytes no total.
        MemorySegment want = arena.allocate(32);
        want.set(JAVA_INT, 0, RATE);
        want.set(JAVA_SHORT, 4, (short) Sdl.AUDIO_S16LSB);
        want.set(JAVA_BYTE, 6, (byte) 1);
        want.set(JAVA_SHORT, 8, (short) 1024);
        int audio = Sdl.openAudioDevice(want);
        if (audio != 0) Sdl.pauseAudioDevice(audio, 0);
        else System.err.println("sem áudio: " + Sdl.getError());

        Game game = new Game(arena, audio);
        game.resetBall(ThreadLocalRandom.current().nextBoolean() ? 1 : -1);
        Renderer renderer = new Renderer(arena, ren);

        MemorySegment event = arena.allocate(Sdl.EVENT_SIZE);
        MemorySegment keys = Sdl.getKeyboardState();
        double freq = Sdl.getPerformanceFrequency();
        long last = Sdl.getPerformanceCounter();
        double acc = 0;
        boolean running = true;
        while (running) {
            while (Sdl.pollEvent(event) != 0)
                if (event.get(JAVA_INT, 0) == Sdl.QUIT) running = false;
            if (pressed(keys, Sdl.SCANCODE_ESCAPE)) running = false;

            long now = Sdl.getPerformanceCounter();
            acc += Math.min((now - last) / freq, 0.25);
            last = now;
            while (acc >= STEP) {
                game.update(keys, STEP);
                acc -= STEP;
            }
            renderer.render(game);
        }

        if (audio != 0) Sdl.closeAudioDevice(audio);
        Sdl.destroyRenderer(ren);
        Sdl.destroyWindow(win);
        Sdl.quit();
        return 0;
    }
}
