// Pong em D com SDL2 (bindbc-sdl, carregamento dinâmico da libSDL2).
module app;

import bindbc.sdl;
import std.algorithm : clamp, min;
import std.conv : to;
import std.math : abs, cos, sin, PI;
import std.random : uniform;
import std.stdio : stderr;

enum W = 640, H = 480;
enum PADDLE_W = 10, PADDLE_H = 60, PADDLE_MARGIN = 20;
enum BALL = 10;
enum double PADDLE_SPEED = 400.0;
enum double BALL_SPEED = 300.0;
enum double BALL_MAX = 720.0;
enum double SPEEDUP = 1.07;
enum double MAX_ANGLE = PI / 4;
enum double STEP = 1.0 / 120.0;
enum double SERVE_DELAY = 1.0;
enum RATE = 44_100;

// Fonte 3x5 para os dígitos do placar.
immutable string[10] DIGITS = [
    "111101101101111", "001001001001001", "111001111100111", "111001111001111",
    "101101111001001", "111100111001111", "111100111101111", "111001001001001",
    "111101111101111", "111101111001111",
];

// Onda quadrada mono S16: um "beep" de console Atari.
short[] squareWave(int freq, int ms)
{
    auto buf = new short[RATE * ms / 1000];
    foreach (i, ref s; buf)
        s = ((i * 2 * freq) / RATE) % 2 ? 4000 : -4000;
    return buf;
}

struct Game
{
    double leftY = (H - PADDLE_H) / 2.0, rightY = (H - PADDLE_H) / 2.0;
    double bx = 0, by = 0, vx = 0, vy = 0, speed = BALL_SPEED;
    double serveTimer = 0, serveDir = 1;
    int scoreL, scoreR;

    SDL_AudioDeviceID audio;
    short[] sndPaddle, sndWall, sndScore;

    void play(const short[] s)
    {
        if (!audio) return;
        SDL_ClearQueuedAudio(audio);
        SDL_QueueAudio(audio, s.ptr, cast(uint)(s.length * short.sizeof));
    }

    void resetBall(double dir)
    {
        bx = (W - BALL) / 2.0;
        by = (H - BALL) / 2.0;
        vx = vy = 0;
        speed = BALL_SPEED;
        serveDir = dir;
        serveTimer = SERVE_DELAY;
    }

    void launch()
    {
        const a = uniform(-PI / 6, PI / 6);
        vx = serveDir * speed * cos(a);
        vy = speed * sin(a);
    }

    void bounce(double dir, double paddleY)
    {
        speed = min(speed * SPEEDUP, BALL_MAX);
        const rel = ((by + BALL / 2.0) - (paddleY + PADDLE_H / 2.0)) / (PADDLE_H / 2.0);
        const a = clamp(rel, -1.0, 1.0) * MAX_ANGLE;
        vx = dir * speed * cos(a);
        vy = speed * sin(a);
        play(sndPaddle);
    }

    static bool overlapsY(double by, double py) { return by + BALL >= py && by <= py + PADDLE_H; }

    void update(const(ubyte)* keys, double dt)
    {
        if (keys[SDL_SCANCODE_W]) leftY -= PADDLE_SPEED * dt;
        if (keys[SDL_SCANCODE_S]) leftY += PADDLE_SPEED * dt;
        if (keys[SDL_SCANCODE_UP]) rightY -= PADDLE_SPEED * dt;
        if (keys[SDL_SCANCODE_DOWN]) rightY += PADDLE_SPEED * dt;
        leftY = clamp(leftY, 0.0, double(H - PADDLE_H));
        rightY = clamp(rightY, 0.0, double(H - PADDLE_H));

        if (serveTimer > 0)
        {
            serveTimer -= dt;
            if (serveTimer <= 0) launch();
            return;
        }

        bx += vx * dt;
        by += vy * dt;

        if (by < 0) { by = 0; vy = abs(vy); play(sndWall); }
        if (by + BALL > H) { by = H - BALL; vy = -abs(vy); play(sndWall); }

        enum double lx = PADDLE_MARGIN, rx = W - PADDLE_MARGIN - PADDLE_W;
        if (vx < 0 && bx <= lx + PADDLE_W && bx + BALL >= lx && overlapsY(by, leftY))
        {
            bx = lx + PADDLE_W;
            bounce(1, leftY);
        }
        if (vx > 0 && bx + BALL >= rx && bx <= rx + PADDLE_W && overlapsY(by, rightY))
        {
            bx = rx - BALL;
            bounce(-1, rightY);
        }

        if (bx + BALL < 0) { ++scoreR; play(sndScore); resetBall(-1); }
        if (bx > W) { ++scoreL; play(sndScore); resetBall(1); }
    }
}

void fill(SDL_Renderer* r, int x, int y, int w, int h)
{
    auto rc = SDL_Rect(x, y, w, h);
    SDL_RenderFillRect(r, &rc);
}

// Desenha um número; alignRight=true faz o número terminar em x.
void drawNumber(SDL_Renderer* r, int n, int x, int y, bool alignRight)
{
    enum S = 8;
    const s = n.to!string;
    const len = cast(int) s.length;
    if (alignRight) x -= len * 3 * S + (len - 1) * S;
    foreach (c; s)
    {
        const g = DIGITS[c - '0'];
        foreach (i; 0 .. 15)
            if (g[i] == '1') fill(r, x + (i % 3) * S, y + (i / 3) * S, S, S);
        x += 4 * S;
    }
}

void render(SDL_Renderer* r, ref const Game g)
{
    SDL_SetRenderDrawColor(r, 0, 0, 0, 255);
    SDL_RenderClear(r);
    SDL_SetRenderDrawColor(r, 255, 255, 255, 255);
    for (int y = 6; y < H; y += 24) fill(r, W / 2 - 2, y, 4, 12);
    drawNumber(r, g.scoreL, W / 2 - 40, 20, true);
    drawNumber(r, g.scoreR, W / 2 + 40, 20, false);
    fill(r, PADDLE_MARGIN, cast(int) g.leftY, PADDLE_W, PADDLE_H);
    fill(r, W - PADDLE_MARGIN - PADDLE_W, cast(int) g.rightY, PADDLE_W, PADDLE_H);
    fill(r, cast(int) g.bx, cast(int) g.by, BALL, BALL);
    SDL_RenderPresent(r);
}

int main()
{
    const loaded = loadSDL();
    if (loaded != sdlSupport)
    {
        stderr.writeln(loaded == SDLSupport.noLibrary ? "libSDL2 não encontrada"
                                                      : "libSDL2 antiga demais (precisa >= 2.0.18)");
        return 1;
    }
    if (SDL_Init(SDL_INIT_VIDEO | SDL_INIT_AUDIO) != 0)
    {
        stderr.writeln("SDL_Init: ", SDL_GetError().to!string);
        return 1;
    }
    scope (exit) SDL_Quit();

    auto win = SDL_CreateWindow("Pong - D", SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED,
                                W, H, SDL_WINDOW_SHOWN);
    auto ren = win ? SDL_CreateRenderer(win, -1, SDL_RENDERER_ACCELERATED | SDL_RENDERER_PRESENTVSYNC)
                   : null;
    if (!ren)
    {
        stderr.writeln("janela/renderer: ", SDL_GetError().to!string);
        return 1;
    }
    scope (exit) { SDL_DestroyRenderer(ren); SDL_DestroyWindow(win); }

    Game game;
    game.sndPaddle = squareWave(460, 50);
    game.sndWall = squareWave(230, 50);
    game.sndScore = squareWave(490, 250);

    SDL_AudioSpec want;
    want.freq = RATE;
    want.format = AUDIO_S16SYS;
    want.channels = 1;
    want.samples = 1024;
    game.audio = SDL_OpenAudioDevice(null, 0, &want, null, 0);
    if (game.audio) SDL_PauseAudioDevice(game.audio, 0);
    else stderr.writeln("sem áudio: ", SDL_GetError().to!string);
    scope (exit) if (game.audio) SDL_CloseAudioDevice(game.audio);

    game.resetBall(uniform(0, 2) ? 1 : -1);

    ulong last = SDL_GetPerformanceCounter();
    double acc = 0;
    for (;;)
    {
        SDL_Event e;
        while (SDL_PollEvent(&e))
            if (e.type == SDL_QUIT) return 0;
        const keys = SDL_GetKeyboardState(null);
        if (keys[SDL_SCANCODE_ESCAPE]) return 0;

        const now = SDL_GetPerformanceCounter();
        acc += min(double(now - last) / SDL_GetPerformanceFrequency(), 0.25);
        last = now;
        while (acc >= STEP)
        {
            game.update(keys, STEP);
            acc -= STEP;
        }
        render(ren, game);
    }
}
