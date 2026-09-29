#!/usr/bin/env python3
"""Pong em Python com SDL2 (PySDL2, API de baixo nível sobre ctypes)."""
import ctypes
import math
import random
import sys
from array import array

import sdl2

W, H = 640, 480
PADDLE_W, PADDLE_H, PADDLE_MARGIN = 10, 60, 20
BALL = 10
PADDLE_SPEED = 400.0
BALL_SPEED = 300.0
BALL_MAX = 720.0
SPEEDUP = 1.07
STEP = 1.0 / 120.0
SERVE_DELAY = 1.0
RATE = 44100

# Fonte 3x5 para os dígitos do placar.
DIGITS = [
    "111101101101111", "001001001001001", "111001111100111", "111001111001111",
    "101101111001001", "111100111001111", "111100111101111", "111001001001001",
    "111101111101111", "111101111001111",
]


def square_wave(freq, ms):
    """Onda quadrada mono S16: um "beep" de console Atari."""
    n = RATE * ms // 1000
    buf = array("h", (4000 if (i * 2 * freq // RATE) % 2 else -4000 for i in range(n)))
    if sys.byteorder != "little":
        buf.byteswap()
    return buf.tobytes()


def clamp(v, lo, hi):
    return max(lo, min(hi, v))


def overlaps_y(by, py):
    return by + BALL >= py and by <= py + PADDLE_H


class Game:
    def __init__(self, audio):
        self.left_y = self.right_y = (H - PADDLE_H) / 2
        self.bx = self.by = self.vx = self.vy = 0.0
        self.speed = BALL_SPEED
        self.serve_timer = 0.0
        self.serve_dir = 1
        self.score_l = self.score_r = 0
        self.audio = audio
        self.snd_paddle = square_wave(460, 50)
        self.snd_wall = square_wave(230, 50)
        self.snd_score = square_wave(490, 250)

    def play(self, s):
        if not self.audio:
            return
        sdl2.SDL_ClearQueuedAudio(self.audio)
        sdl2.SDL_QueueAudio(self.audio, s, len(s))

    def reset_ball(self, direction):
        self.bx = (W - BALL) / 2
        self.by = (H - BALL) / 2
        self.vx = self.vy = 0.0
        self.speed = BALL_SPEED
        self.serve_dir = direction
        self.serve_timer = SERVE_DELAY

    def launch(self):
        a = random.uniform(-math.pi / 6, math.pi / 6)
        self.vx = self.serve_dir * self.speed * math.cos(a)
        self.vy = self.speed * math.sin(a)

    def bounce(self, direction, paddle_y):
        self.speed = min(self.speed * SPEEDUP, BALL_MAX)
        rel = ((self.by + BALL / 2) - (paddle_y + PADDLE_H / 2)) / (PADDLE_H / 2)
        # Direção (1, t) normalizada, com t = tan do ângulo de saída (até 45° na borda da
        # raquete). Usa só sqrt, que o IEEE 754 exige arredondado corretamente: sin/cos
        # diferem no último bit entre as bibliotecas de cada linguagem, e num rali longo
        # essa diferença cresce até separar as versões.
        t = clamp(rel, -1.0, 1.0)
        length = math.sqrt(1 + t * t)
        self.vx = direction * self.speed / length
        self.vy = self.speed * t / length
        self.play(self.snd_paddle)

    def update(self, keys, dt):
        if keys[sdl2.SDL_SCANCODE_W]:
            self.left_y -= PADDLE_SPEED * dt
        if keys[sdl2.SDL_SCANCODE_S]:
            self.left_y += PADDLE_SPEED * dt
        if keys[sdl2.SDL_SCANCODE_UP]:
            self.right_y -= PADDLE_SPEED * dt
        if keys[sdl2.SDL_SCANCODE_DOWN]:
            self.right_y += PADDLE_SPEED * dt
        self.left_y = clamp(self.left_y, 0, H - PADDLE_H)
        self.right_y = clamp(self.right_y, 0, H - PADDLE_H)

        if self.serve_timer > 0:
            self.serve_timer -= dt
            if self.serve_timer <= 0:
                self.launch()
            return

        self.bx += self.vx * dt
        self.by += self.vy * dt

        if self.by < 0:
            self.by = 0
            self.vy = abs(self.vy)
            self.play(self.snd_wall)
        if self.by + BALL > H:
            self.by = H - BALL
            self.vy = -abs(self.vy)
            self.play(self.snd_wall)

        lx, rx = PADDLE_MARGIN, W - PADDLE_MARGIN - PADDLE_W
        if self.vx < 0 and self.bx <= lx + PADDLE_W and self.bx + BALL >= lx and overlaps_y(self.by, self.left_y):
            self.bx = lx + PADDLE_W
            self.bounce(1, self.left_y)
        if self.vx > 0 and self.bx + BALL >= rx and self.bx <= rx + PADDLE_W and overlaps_y(self.by, self.right_y):
            self.bx = rx - BALL
            self.bounce(-1, self.right_y)

        if self.bx + BALL < 0:
            self.score_r += 1
            self.play(self.snd_score)
            self.reset_ball(-1)
        if self.bx > W:
            self.score_l += 1
            self.play(self.snd_score)
            self.reset_ball(1)


def fill(r, x, y, w, h):
    sdl2.SDL_RenderFillRect(r, sdl2.SDL_Rect(int(x), int(y), w, h))


def draw_number(r, n, x, y, align_right):
    """Desenha um número; align_right=True faz o número terminar em x."""
    s = 8
    text = str(n)
    if align_right:
        x -= len(text) * 3 * s + (len(text) - 1) * s
    for c in text:
        for i, bit in enumerate(DIGITS[int(c)]):
            if bit == "1":
                fill(r, x + (i % 3) * s, y + (i // 3) * s, s, s)
        x += 4 * s


def render(r, g):
    sdl2.SDL_SetRenderDrawColor(r, 0, 0, 0, 255)
    sdl2.SDL_RenderClear(r)
    sdl2.SDL_SetRenderDrawColor(r, 255, 255, 255, 255)
    for y in range(6, H, 24):
        fill(r, W // 2 - 2, y, 4, 12)
    draw_number(r, g.score_l, W // 2 - 40, 20, True)
    draw_number(r, g.score_r, W // 2 + 40, 20, False)
    fill(r, PADDLE_MARGIN, g.left_y, PADDLE_W, PADDLE_H)
    fill(r, W - PADDLE_MARGIN - PADDLE_W, g.right_y, PADDLE_W, PADDLE_H)
    fill(r, g.bx, g.by, BALL, BALL)
    sdl2.SDL_RenderPresent(r)


def main():
    if sdl2.SDL_Init(sdl2.SDL_INIT_VIDEO | sdl2.SDL_INIT_AUDIO) != 0:
        print("SDL_Init:", sdl2.SDL_GetError().decode(), file=sys.stderr)
        return 1
    win = sdl2.SDL_CreateWindow(b"Pong - Python", sdl2.SDL_WINDOWPOS_CENTERED, sdl2.SDL_WINDOWPOS_CENTERED,
                                W, H, sdl2.SDL_WINDOW_SHOWN)
    ren = win and sdl2.SDL_CreateRenderer(win, -1, sdl2.SDL_RENDERER_ACCELERATED | sdl2.SDL_RENDERER_PRESENTVSYNC)
    if not ren:
        print("janela/renderer:", sdl2.SDL_GetError().decode(), file=sys.stderr)
        return 1

    want = sdl2.SDL_AudioSpec(RATE, sdl2.AUDIO_S16LSB, 1, 1024)
    audio = sdl2.SDL_OpenAudioDevice(None, 0, want, None, 0)
    if audio:
        sdl2.SDL_PauseAudioDevice(audio, 0)
    else:
        print("sem áudio:", sdl2.SDL_GetError().decode(), file=sys.stderr)

    game = Game(audio)
    game.reset_ball(random.choice((1, -1)))

    event = sdl2.SDL_Event()
    freq = sdl2.SDL_GetPerformanceFrequency()
    last = sdl2.SDL_GetPerformanceCounter()
    acc = 0.0
    running = True
    while running:
        while sdl2.SDL_PollEvent(ctypes.byref(event)):
            if event.type == sdl2.SDL_QUIT:
                running = False
        keys = sdl2.SDL_GetKeyboardState(None)
        if keys[sdl2.SDL_SCANCODE_ESCAPE]:
            running = False

        now = sdl2.SDL_GetPerformanceCounter()
        acc += min((now - last) / freq, 0.25)
        last = now
        while acc >= STEP:
            game.update(keys, STEP)
            acc -= STEP
        render(ren, game)

    if audio:
        sdl2.SDL_CloseAudioDevice(audio)
    sdl2.SDL_DestroyRenderer(ren)
    sdl2.SDL_DestroyWindow(win)
    sdl2.SDL_Quit()
    return 0


if __name__ == "__main__":
    sys.exit(main())
