#!/usr/bin/env luajit
-- Pong em Lua (LuaJIT) com SDL2, chamando a libSDL2 diretamente via FFI.
local ffi = require("ffi")

ffi.cdef [[
typedef struct SDL_Window SDL_Window;
typedef struct SDL_Renderer SDL_Renderer;
typedef struct { int x, y, w, h; } SDL_Rect;
typedef struct {
    int freq; uint16_t format; uint8_t channels; uint8_t silence;
    uint16_t samples; uint16_t padding; uint32_t size;
    void *callback; void *userdata;
} SDL_AudioSpec;
typedef union { uint32_t type; uint8_t padding[56]; } SDL_Event;

int SDL_Init(uint32_t flags);
void SDL_Quit(void);
const char *SDL_GetError(void);
SDL_Window *SDL_CreateWindow(const char *title, int x, int y, int w, int h, uint32_t flags);
void SDL_DestroyWindow(SDL_Window *window);
SDL_Renderer *SDL_CreateRenderer(SDL_Window *window, int index, uint32_t flags);
void SDL_DestroyRenderer(SDL_Renderer *renderer);
int SDL_SetRenderDrawColor(SDL_Renderer *renderer, uint8_t r, uint8_t g, uint8_t b, uint8_t a);
int SDL_RenderClear(SDL_Renderer *renderer);
int SDL_RenderFillRect(SDL_Renderer *renderer, const SDL_Rect *rect);
void SDL_RenderPresent(SDL_Renderer *renderer);
int SDL_PollEvent(SDL_Event *event);
const uint8_t *SDL_GetKeyboardState(int *numkeys);
uint64_t SDL_GetPerformanceCounter(void);
uint64_t SDL_GetPerformanceFrequency(void);
uint32_t SDL_OpenAudioDevice(const char *device, int iscapture, const SDL_AudioSpec *desired,
                             SDL_AudioSpec *obtained, int allowed_changes);
void SDL_PauseAudioDevice(uint32_t dev, int pause_on);
int SDL_QueueAudio(uint32_t dev, const void *data, uint32_t len);
void SDL_ClearQueuedAudio(uint32_t dev);
void SDL_CloseAudioDevice(uint32_t dev);
]]

-- "SDL2" precisa do symlink libSDL2.so (pacote -devel); sem ele, usa o soname.
local ok, sdl = pcall(ffi.load, "SDL2")
if not ok then sdl = ffi.load("libSDL2-2.0.so.0") end

local W, H = 640, 480
local PADDLE_W, PADDLE_H, PADDLE_MARGIN = 10, 60, 20
local BALL = 10
local PADDLE_SPEED = 400.0
local BALL_SPEED = 300.0
local BALL_MAX = 720.0
local SPEEDUP = 1.07
local MAX_ANGLE = math.pi / 4
local STEP = 1.0 / 120.0
local SERVE_DELAY = 1.0
local RATE = 44100

-- Constantes dos headers da SDL2.
local SDL_INIT_AUDIO, SDL_INIT_VIDEO = 0x10, 0x20
local SDL_WINDOWPOS_CENTERED = 0x2FFF0000
local SDL_WINDOW_SHOWN = 0x04
local SDL_RENDERER_ACCELERATED, SDL_RENDERER_PRESENTVSYNC = 0x02, 0x04
local SDL_QUIT = 0x100
local SC_S, SC_W, SC_ESCAPE, SC_DOWN, SC_UP = 22, 26, 41, 81, 82
local AUDIO_S16LSB = 0x8010

-- Fonte 3x5 para os dígitos do placar.
local DIGITS = {
    [0] = "111101101101111", "001001001001001", "111001111100111", "111001111001111",
    "101101111001001", "111100111001111", "111100111101111", "111001001001001",
    "111101111101111", "111101111001111",
}

-- Onda quadrada mono S16: um "beep" de console Atari.
local function square_wave(freq, ms)
    local n = math.floor(RATE * ms / 1000)
    local buf = ffi.new("int16_t[?]", n)
    for i = 0, n - 1 do
        buf[i] = math.floor(i * 2 * freq / RATE) % 2 == 1 and 4000 or -4000
    end
    return { data = buf, bytes = n * 2 }
end

local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

local function overlaps_y(by, py) return by + BALL >= py and by <= py + PADDLE_H end

local Game = {}
Game.__index = Game

function Game.new(audio)
    local g = setmetatable({}, Game)
    g.left_y, g.right_y = (H - PADDLE_H) / 2, (H - PADDLE_H) / 2
    g.bx, g.by, g.vx, g.vy = 0, 0, 0, 0
    g.speed = BALL_SPEED
    g.serve_timer, g.serve_dir = 0, 1
    g.score_l, g.score_r = 0, 0
    g.audio = audio
    g.snd_paddle = square_wave(460, 50)
    g.snd_wall = square_wave(230, 50)
    g.snd_score = square_wave(490, 250)
    return g
end

function Game:play(s)
    if self.audio == 0 then return end
    sdl.SDL_ClearQueuedAudio(self.audio)
    sdl.SDL_QueueAudio(self.audio, s.data, s.bytes)
end

function Game:reset_ball(dir)
    self.bx = (W - BALL) / 2
    self.by = (H - BALL) / 2
    self.vx, self.vy = 0, 0
    self.speed = BALL_SPEED
    self.serve_dir = dir
    self.serve_timer = SERVE_DELAY
end

function Game:launch()
    local a = (math.random() * 2 - 1) * math.pi / 6
    self.vx = self.serve_dir * self.speed * math.cos(a)
    self.vy = self.speed * math.sin(a)
end

function Game:bounce(dir, paddle_y)
    self.speed = math.min(self.speed * SPEEDUP, BALL_MAX)
    local rel = ((self.by + BALL / 2) - (paddle_y + PADDLE_H / 2)) / (PADDLE_H / 2)
    local a = clamp(rel, -1, 1) * MAX_ANGLE
    self.vx = dir * self.speed * math.cos(a)
    self.vy = self.speed * math.sin(a)
    self:play(self.snd_paddle)
end

function Game:update(keys, dt)
    if keys[SC_W] ~= 0 then self.left_y = self.left_y - PADDLE_SPEED * dt end
    if keys[SC_S] ~= 0 then self.left_y = self.left_y + PADDLE_SPEED * dt end
    if keys[SC_UP] ~= 0 then self.right_y = self.right_y - PADDLE_SPEED * dt end
    if keys[SC_DOWN] ~= 0 then self.right_y = self.right_y + PADDLE_SPEED * dt end
    self.left_y = clamp(self.left_y, 0, H - PADDLE_H)
    self.right_y = clamp(self.right_y, 0, H - PADDLE_H)

    if self.serve_timer > 0 then
        self.serve_timer = self.serve_timer - dt
        if self.serve_timer <= 0 then self:launch() end
        return
    end

    self.bx = self.bx + self.vx * dt
    self.by = self.by + self.vy * dt

    if self.by < 0 then
        self.by = 0
        self.vy = math.abs(self.vy)
        self:play(self.snd_wall)
    end
    if self.by + BALL > H then
        self.by = H - BALL
        self.vy = -math.abs(self.vy)
        self:play(self.snd_wall)
    end

    local lx, rx = PADDLE_MARGIN, W - PADDLE_MARGIN - PADDLE_W
    if self.vx < 0 and self.bx <= lx + PADDLE_W and self.bx + BALL >= lx and overlaps_y(self.by, self.left_y) then
        self.bx = lx + PADDLE_W
        self:bounce(1, self.left_y)
    end
    if self.vx > 0 and self.bx + BALL >= rx and self.bx <= rx + PADDLE_W and overlaps_y(self.by, self.right_y) then
        self.bx = rx - BALL
        self:bounce(-1, self.right_y)
    end

    if self.bx + BALL < 0 then
        self.score_r = self.score_r + 1
        self:play(self.snd_score)
        self:reset_ball(-1)
    end
    if self.bx > W then
        self.score_l = self.score_l + 1
        self:play(self.snd_score)
        self:reset_ball(1)
    end
end

local rect = ffi.new("SDL_Rect")

local function fill(r, x, y, w, h)
    rect.x, rect.y, rect.w, rect.h = math.floor(x), math.floor(y), w, h
    sdl.SDL_RenderFillRect(r, rect)
end

-- Desenha um número; align_right=true faz o número terminar em x.
local function draw_number(r, n, x, y, align_right)
    local S = 8
    local text = tostring(n)
    if align_right then x = x - (#text * 3 * S + (#text - 1) * S) end
    for c in text:gmatch("%d") do
        local g = DIGITS[tonumber(c)]
        for i = 0, 14 do
            if g:sub(i + 1, i + 1) == "1" then
                fill(r, x + (i % 3) * S, y + math.floor(i / 3) * S, S, S)
            end
        end
        x = x + 4 * S
    end
end

local function render(r, g)
    sdl.SDL_SetRenderDrawColor(r, 0, 0, 0, 255)
    sdl.SDL_RenderClear(r)
    sdl.SDL_SetRenderDrawColor(r, 255, 255, 255, 255)
    for y = 6, H - 1, 24 do fill(r, W / 2 - 2, y, 4, 12) end
    draw_number(r, g.score_l, W / 2 - 40, 20, true)
    draw_number(r, g.score_r, W / 2 + 40, 20, false)
    fill(r, PADDLE_MARGIN, g.left_y, PADDLE_W, PADDLE_H)
    fill(r, W - PADDLE_MARGIN - PADDLE_W, g.right_y, PADDLE_W, PADDLE_H)
    fill(r, g.bx, g.by, BALL, BALL)
    sdl.SDL_RenderPresent(r)
end

local function main()
    math.randomseed(os.time())
    if sdl.SDL_Init(bit.bor(SDL_INIT_VIDEO, SDL_INIT_AUDIO)) ~= 0 then
        io.stderr:write("SDL_Init: ", ffi.string(sdl.SDL_GetError()), "\n")
        return 1
    end
    local win = sdl.SDL_CreateWindow("Pong - Lua", SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED,
                                     W, H, SDL_WINDOW_SHOWN)
    local ren = win ~= nil and sdl.SDL_CreateRenderer(win, -1,
        bit.bor(SDL_RENDERER_ACCELERATED, SDL_RENDERER_PRESENTVSYNC)) or nil
    if ren == nil then
        io.stderr:write("janela/renderer: ", ffi.string(sdl.SDL_GetError()), "\n")
        return 1
    end

    local want = ffi.new("SDL_AudioSpec", { freq = RATE, format = AUDIO_S16LSB, channels = 1, samples = 1024 })
    local audio = sdl.SDL_OpenAudioDevice(nil, 0, want, nil, 0)
    if audio ~= 0 then
        sdl.SDL_PauseAudioDevice(audio, 0)
    else
        io.stderr:write("sem áudio: ", ffi.string(sdl.SDL_GetError()), "\n")
    end

    local game = Game.new(audio)
    game:reset_ball(math.random() < 0.5 and 1 or -1)

    local event = ffi.new("SDL_Event")
    local freq = tonumber(sdl.SDL_GetPerformanceFrequency())
    local last = sdl.SDL_GetPerformanceCounter()
    local acc = 0
    local running = true
    while running do
        while sdl.SDL_PollEvent(event) ~= 0 do
            if event.type == SDL_QUIT then running = false end
        end
        local keys = sdl.SDL_GetKeyboardState(nil)
        if keys[SC_ESCAPE] ~= 0 then running = false end

        local now = sdl.SDL_GetPerformanceCounter()
        acc = acc + math.min(tonumber(now - last) / freq, 0.25)
        last = now
        while acc >= STEP do
            game:update(keys, STEP)
            acc = acc - STEP
        end
        render(ren, game)
    end

    if audio ~= 0 then sdl.SDL_CloseAudioDevice(audio) end
    sdl.SDL_DestroyRenderer(ren)
    sdl.SDL_DestroyWindow(win)
    sdl.SDL_Quit()
    return 0
end

os.exit(main())
