// Pong em Rust com SDL2 (crate `sdl2`).
use rand::Rng;
use sdl2::audio::{AudioQueue, AudioSpecDesired};
use sdl2::event::Event;
use sdl2::keyboard::{KeyboardState, Scancode};
use sdl2::pixels::Color;
use sdl2::rect::Rect;
use sdl2::render::WindowCanvas;
use std::f64::consts::PI;
use std::time::Instant;

const W: i32 = 640;
const H: i32 = 480;
const PADDLE_W: i32 = 10;
const PADDLE_H: i32 = 60;
const PADDLE_MARGIN: i32 = 20;
const BALL: i32 = 10;
const PADDLE_SPEED: f64 = 400.0;
const BALL_SPEED: f64 = 300.0;
const BALL_MAX: f64 = 720.0;
const SPEEDUP: f64 = 1.07;
const STEP: f64 = 1.0 / 120.0;
const SERVE_DELAY: f64 = 1.0;
const RATE: i32 = 44100;

// Fonte 3x5 para os dígitos do placar.
const DIGITS: [&str; 10] = [
    "111101101101111", "001001001001001", "111001111100111", "111001111001111",
    "101101111001001", "111100111001111", "111100111101111", "111001001001001",
    "111101111101111", "111101111001111",
];

// Onda quadrada mono S16: um "beep" de console Atari.
fn square_wave(freq: i32, ms: i32) -> Vec<i16> {
    let n = (RATE * ms / 1000) as usize;
    (0..n)
        .map(|i| if (i * 2 * freq as usize / RATE as usize) % 2 == 1 { 4000 } else { -4000 })
        .collect()
}

struct Sounds {
    queue: Option<AudioQueue<i16>>,
    paddle: Vec<i16>,
    wall: Vec<i16>,
    score: Vec<i16>,
}

impl Sounds {
    fn play(&self, s: &[i16]) {
        if let Some(q) = &self.queue {
            q.clear();
            let _ = q.queue_audio(s);
        }
    }
}

struct Game {
    left_y: f64,
    right_y: f64,
    bx: f64,
    by: f64,
    vx: f64,
    vy: f64,
    speed: f64,
    serve_timer: f64,
    serve_dir: f64,
    score_l: u32,
    score_r: u32,
}

impl Game {
    fn new() -> Self {
        let mut g = Game {
            left_y: (H - PADDLE_H) as f64 / 2.0,
            right_y: (H - PADDLE_H) as f64 / 2.0,
            bx: 0.0, by: 0.0, vx: 0.0, vy: 0.0,
            speed: BALL_SPEED,
            serve_timer: 0.0,
            serve_dir: 1.0,
            score_l: 0,
            score_r: 0,
        };
        g.reset_ball(if rand::thread_rng().gen_bool(0.5) { 1.0 } else { -1.0 });
        g
    }

    fn reset_ball(&mut self, dir: f64) {
        self.bx = (W - BALL) as f64 / 2.0;
        self.by = (H - BALL) as f64 / 2.0;
        self.vx = 0.0;
        self.vy = 0.0;
        self.speed = BALL_SPEED;
        self.serve_dir = dir;
        self.serve_timer = SERVE_DELAY;
    }

    fn launch(&mut self) {
        let a = rand::thread_rng().gen_range(-PI / 6.0..PI / 6.0);
        self.vx = self.serve_dir * self.speed * a.cos();
        self.vy = self.speed * a.sin();
    }

    fn bounce(&mut self, dir: f64, paddle_y: f64, snd: &Sounds) {
        self.speed = (self.speed * SPEEDUP).min(BALL_MAX);
        let rel = ((self.by + BALL as f64 / 2.0) - (paddle_y + PADDLE_H as f64 / 2.0))
            / (PADDLE_H as f64 / 2.0);
        // Direção (1, t) normalizada, com t = tan do ângulo de saída (até 45° na borda da
        // raquete). Usa só sqrt, que o IEEE 754 exige arredondado corretamente: sin/cos
        // diferem no último bit entre as bibliotecas de cada linguagem, e num rali longo
        // essa diferença cresce até separar as versões.
        let t = rel.clamp(-1.0, 1.0);
        let len = (1.0 + t * t).sqrt();
        self.vx = dir * self.speed / len;
        self.vy = self.speed * t / len;
        snd.play(&snd.paddle);
    }

    fn overlaps_y(by: f64, py: f64) -> bool {
        by + BALL as f64 >= py && by <= py + PADDLE_H as f64
    }

    fn update(&mut self, keys: &KeyboardState, dt: f64, snd: &Sounds) {
        let down = |s| keys.is_scancode_pressed(s);
        if down(Scancode::W) { self.left_y -= PADDLE_SPEED * dt; }
        if down(Scancode::S) { self.left_y += PADDLE_SPEED * dt; }
        if down(Scancode::Up) { self.right_y -= PADDLE_SPEED * dt; }
        if down(Scancode::Down) { self.right_y += PADDLE_SPEED * dt; }
        let max_y = (H - PADDLE_H) as f64;
        self.left_y = self.left_y.clamp(0.0, max_y);
        self.right_y = self.right_y.clamp(0.0, max_y);

        if self.serve_timer > 0.0 {
            self.serve_timer -= dt;
            if self.serve_timer <= 0.0 {
                self.launch();
            }
            return;
        }

        self.bx += self.vx * dt;
        self.by += self.vy * dt;

        let ball = BALL as f64;
        if self.by < 0.0 {
            self.by = 0.0;
            self.vy = self.vy.abs();
            snd.play(&snd.wall);
        }
        if self.by + ball > H as f64 {
            self.by = H as f64 - ball;
            self.vy = -self.vy.abs();
            snd.play(&snd.wall);
        }

        let lx = PADDLE_MARGIN as f64;
        let rx = (W - PADDLE_MARGIN - PADDLE_W) as f64;
        let pw = PADDLE_W as f64;
        if self.vx < 0.0 && self.bx <= lx + pw && self.bx + ball >= lx
            && Self::overlaps_y(self.by, self.left_y)
        {
            self.bx = lx + pw;
            self.bounce(1.0, self.left_y, snd);
        }
        if self.vx > 0.0 && self.bx + ball >= rx && self.bx <= rx + pw
            && Self::overlaps_y(self.by, self.right_y)
        {
            self.bx = rx - ball;
            self.bounce(-1.0, self.right_y, snd);
        }

        if self.bx + ball < 0.0 {
            self.score_r += 1;
            snd.play(&snd.score);
            self.reset_ball(-1.0);
        }
        if self.bx > W as f64 {
            self.score_l += 1;
            snd.play(&snd.score);
            self.reset_ball(1.0);
        }
    }
}

fn fill(c: &mut WindowCanvas, x: i32, y: i32, w: i32, h: i32) {
    let _ = c.fill_rect(Rect::new(x, y, w as u32, h as u32));
}

// Desenha um número; align_right=true faz o número terminar em x.
fn draw_number(c: &mut WindowCanvas, n: u32, mut x: i32, y: i32, align_right: bool) {
    const S: i32 = 8;
    let s = n.to_string();
    let len = s.len() as i32;
    if align_right {
        x -= len * 3 * S + (len - 1) * S;
    }
    for ch in s.bytes() {
        let g = DIGITS[(ch - b'0') as usize].as_bytes();
        for i in 0..15 {
            if g[i] == b'1' {
                fill(c, x + (i as i32 % 3) * S, y + (i as i32 / 3) * S, S, S);
            }
        }
        x += 4 * S;
    }
}

fn render(c: &mut WindowCanvas, g: &Game) {
    c.set_draw_color(Color::RGB(0, 0, 0));
    c.clear();
    c.set_draw_color(Color::RGB(255, 255, 255));
    for y in (6..H).step_by(24) {
        fill(c, W / 2 - 2, y, 4, 12);
    }
    draw_number(c, g.score_l, W / 2 - 40, 20, true);
    draw_number(c, g.score_r, W / 2 + 40, 20, false);
    fill(c, PADDLE_MARGIN, g.left_y as i32, PADDLE_W, PADDLE_H);
    fill(c, W - PADDLE_MARGIN - PADDLE_W, g.right_y as i32, PADDLE_W, PADDLE_H);
    fill(c, g.bx as i32, g.by as i32, BALL, BALL);
    c.present();
}

fn main() -> Result<(), String> {
    let sdl = sdl2::init()?;
    let video = sdl.video()?;
    let window = video
        .window("Pong - Rust", W as u32, H as u32)
        .position_centered()
        .build()
        .map_err(|e| e.to_string())?;
    let mut canvas = window
        .into_canvas()
        .accelerated()
        .present_vsync()
        .build()
        .map_err(|e| e.to_string())?;

    let spec = AudioSpecDesired { freq: Some(RATE), channels: Some(1), samples: Some(1024) };
    let queue = sdl
        .audio()
        .and_then(|a| a.open_queue::<i16, _>(None, &spec))
        .map_err(|e| eprintln!("sem áudio: {e}"))
        .ok();
    if let Some(q) = &queue {
        q.resume();
    }
    let snd = Sounds {
        queue,
        paddle: square_wave(460, 50),
        wall: square_wave(230, 50),
        score: square_wave(490, 250),
    };

    let mut events = sdl.event_pump()?;
    let mut game = Game::new();
    let mut last = Instant::now();
    let mut acc = 0.0;
    'running: loop {
        for e in events.poll_iter() {
            if let Event::Quit { .. } = e {
                break 'running;
            }
        }
        let keys = events.keyboard_state();
        if keys.is_scancode_pressed(Scancode::Escape) {
            break;
        }

        let now = Instant::now();
        acc += now.duration_since(last).as_secs_f64().min(0.25);
        last = now;
        while acc >= STEP {
            game.update(&keys, STEP, &snd);
            acc -= STEP;
        }
        render(&mut canvas, &game);
    }
    Ok(())
}
