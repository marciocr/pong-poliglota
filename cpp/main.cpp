// Pong em C++ com SDL2 — versão de referência do pong-poliglota.
#include <SDL.h>

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <random>
#include <string>
#include <vector>

namespace {

constexpr int W = 640, H = 480;
constexpr int PADDLE_W = 10, PADDLE_H = 60, PADDLE_MARGIN = 20;
constexpr int BALL = 10;
constexpr double PADDLE_SPEED = 400.0;  // px/s
constexpr double BALL_SPEED = 300.0;    // px/s inicial
constexpr double BALL_MAX = 720.0;
constexpr double SPEEDUP = 1.07;        // a cada rebatida
constexpr double STEP = 1.0 / 120.0;    // passo fixo da física
constexpr double SERVE_DELAY = 1.0;     // s de pausa antes de sacar
constexpr int RATE = 44100;

// Fonte 3x5 para os dígitos do placar.
const char* const DIGITS[10] = {
    "111101101101111", "001001001001001", "111001111100111", "111001111001111",
    "101101111001001", "111100111001111", "111100111101111", "111001001001001",
    "111101111101111", "111101111001111"};

// Onda quadrada mono S16: um "beep" de console Atari.
std::vector<int16_t> square_wave(int freq, int ms) {
    std::vector<int16_t> buf(RATE * ms / 1000);
    for (size_t i = 0; i < buf.size(); ++i)
        buf[i] = ((i * 2 * freq) / RATE) % 2 ? 4000 : -4000;
    return buf;
}

struct Game {
    double left_y = (H - PADDLE_H) / 2.0, right_y = (H - PADDLE_H) / 2.0;
    double bx = 0, by = 0, vx = 0, vy = 0, speed = BALL_SPEED;
    double serve_timer = 0;
    int serve_dir = 1;
    int score_l = 0, score_r = 0;
    std::mt19937 rng{std::random_device{}()};

    SDL_AudioDeviceID audio = 0;
    std::vector<int16_t> snd_paddle = square_wave(460, 50);
    std::vector<int16_t> snd_wall = square_wave(230, 50);
    std::vector<int16_t> snd_score = square_wave(490, 250);

    void play(const std::vector<int16_t>& s) {
        if (!audio) return;
        SDL_ClearQueuedAudio(audio);
        SDL_QueueAudio(audio, s.data(), static_cast<Uint32>(s.size() * sizeof(int16_t)));
    }

    void reset_ball(int dir) {
        bx = (W - BALL) / 2.0;
        by = (H - BALL) / 2.0;
        vx = vy = 0;
        speed = BALL_SPEED;
        serve_dir = dir;
        serve_timer = SERVE_DELAY;
    }

    void launch() {
        std::uniform_real_distribution<double> d(-M_PI / 6, M_PI / 6);
        double a = d(rng);
        vx = serve_dir * speed * std::cos(a);
        vy = speed * std::sin(a);
    }

    void bounce(int dir, double paddle_y) {
        speed = std::min(speed * SPEEDUP, BALL_MAX);
        double rel = ((by + BALL / 2.0) - (paddle_y + PADDLE_H / 2.0)) / (PADDLE_H / 2.0);
        // Direção (1, t) normalizada, com t = tan do ângulo de saída (até 45° na borda da
        // raquete). Usa só sqrt, que o IEEE 754 exige arredondado corretamente: sin/cos
        // diferem no último bit entre as bibliotecas de cada linguagem, e num rali longo
        // essa diferença cresce até separar as versões.
        const double t = std::clamp(rel, -1.0, 1.0);
        const double len = std::sqrt(1 + t * t);
        vx = dir * speed / len;
        vy = speed * t / len;
        play(snd_paddle);
    }

    static bool overlaps_y(double by, double py) { return by + BALL >= py && by <= py + PADDLE_H; }

    void update(const Uint8* keys, double dt) {
        if (keys[SDL_SCANCODE_W]) left_y -= PADDLE_SPEED * dt;
        if (keys[SDL_SCANCODE_S]) left_y += PADDLE_SPEED * dt;
        if (keys[SDL_SCANCODE_UP]) right_y -= PADDLE_SPEED * dt;
        if (keys[SDL_SCANCODE_DOWN]) right_y += PADDLE_SPEED * dt;
        left_y = std::clamp(left_y, 0.0, double(H - PADDLE_H));
        right_y = std::clamp(right_y, 0.0, double(H - PADDLE_H));

        if (serve_timer > 0) {
            serve_timer -= dt;
            if (serve_timer <= 0) launch();
            return;
        }

        bx += vx * dt;
        by += vy * dt;

        if (by < 0) { by = 0; vy = std::abs(vy); play(snd_wall); }
        if (by + BALL > H) { by = H - BALL; vy = -std::abs(vy); play(snd_wall); }

        const double lx = PADDLE_MARGIN, rx = W - PADDLE_MARGIN - PADDLE_W;
        if (vx < 0 && bx <= lx + PADDLE_W && bx + BALL >= lx && overlaps_y(by, left_y)) {
            bx = lx + PADDLE_W;
            bounce(+1, left_y);
        }
        if (vx > 0 && bx + BALL >= rx && bx <= rx + PADDLE_W && overlaps_y(by, right_y)) {
            bx = rx - BALL;
            bounce(-1, right_y);
        }

        if (bx + BALL < 0) { ++score_r; play(snd_score); reset_ball(-1); }
        if (bx > W) { ++score_l; play(snd_score); reset_ball(+1); }
    }
};

void fill(SDL_Renderer* r, int x, int y, int w, int h) {
    SDL_Rect rc{x, y, w, h};
    SDL_RenderFillRect(r, &rc);
}

// Desenha um número; align_right=true faz o número terminar em x.
void draw_number(SDL_Renderer* r, int n, int x, int y, bool align_right) {
    constexpr int S = 8;  // tamanho de cada "pixel" da fonte
    std::string s = std::to_string(n);
    int width = int(s.size()) * 3 * S + (int(s.size()) - 1) * S;
    if (align_right) x -= width;
    for (char c : s) {
        const char* g = DIGITS[c - '0'];
        for (int i = 0; i < 15; ++i)
            if (g[i] == '1') fill(r, x + (i % 3) * S, y + (i / 3) * S, S, S);
        x += 4 * S;
    }
}

void render(SDL_Renderer* r, const Game& g) {
    SDL_SetRenderDrawColor(r, 0, 0, 0, 255);
    SDL_RenderClear(r);
    SDL_SetRenderDrawColor(r, 255, 255, 255, 255);
    for (int y = 6; y < H; y += 24) fill(r, W / 2 - 2, y, 4, 12);  // rede
    draw_number(r, g.score_l, W / 2 - 40, 20, true);
    draw_number(r, g.score_r, W / 2 + 40, 20, false);
    fill(r, PADDLE_MARGIN, int(g.left_y), PADDLE_W, PADDLE_H);
    fill(r, W - PADDLE_MARGIN - PADDLE_W, int(g.right_y), PADDLE_W, PADDLE_H);
    fill(r, int(g.bx), int(g.by), BALL, BALL);
    SDL_RenderPresent(r);
}

}  // namespace

int main(int, char**) {
    if (SDL_Init(SDL_INIT_VIDEO | SDL_INIT_AUDIO) != 0) {
        SDL_Log("SDL_Init: %s", SDL_GetError());
        return 1;
    }
    SDL_Window* win = SDL_CreateWindow("Pong - C++", SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED,
                                       W, H, SDL_WINDOW_SHOWN);
    SDL_Renderer* ren = win ? SDL_CreateRenderer(win, -1, SDL_RENDERER_ACCELERATED | SDL_RENDERER_PRESENTVSYNC)
                            : nullptr;
    if (!ren) {
        SDL_Log("janela/renderer: %s", SDL_GetError());
        return 1;
    }

    Game game;
    SDL_AudioSpec want{};
    want.freq = RATE;
    want.format = AUDIO_S16SYS;
    want.channels = 1;
    want.samples = 1024;
    game.audio = SDL_OpenAudioDevice(nullptr, 0, &want, nullptr, 0);
    if (game.audio) SDL_PauseAudioDevice(game.audio, 0);
    else SDL_Log("sem áudio: %s", SDL_GetError());

    game.reset_ball(std::uniform_int_distribution<int>(0, 1)(game.rng) ? 1 : -1);

    Uint64 last = SDL_GetPerformanceCounter();
    double acc = 0;
    bool running = true;
    while (running) {
        SDL_Event e;
        while (SDL_PollEvent(&e))
            if (e.type == SDL_QUIT) running = false;
        const Uint8* keys = SDL_GetKeyboardState(nullptr);
        if (keys[SDL_SCANCODE_ESCAPE]) running = false;

        Uint64 now = SDL_GetPerformanceCounter();
        acc += std::min(double(now - last) / SDL_GetPerformanceFrequency(), 0.25);
        last = now;
        while (acc >= STEP) {
            game.update(keys, STEP);
            acc -= STEP;
        }
        render(ren, game);
    }

    if (game.audio) SDL_CloseAudioDevice(game.audio);
    SDL_DestroyRenderer(ren);
    SDL_DestroyWindow(win);
    SDL_Quit();
    return 0;
}
