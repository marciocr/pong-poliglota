
// Driver de teste (Rust): o código foi cortado antes do main() da SDL. Este
// KeyboardState toma o lugar do da crate sdl2, que só existe com a SDL viva.
struct KeyboardState {
    k: [bool; 512],
}
impl KeyboardState {
    fn is_scancode_pressed(&self, s: Scancode) -> bool {
        self.k[s as usize]
    }
}

fn main() {
    let path = std::env::args().nth(1).unwrap();
    let snd = Sounds { queue: None, paddle: vec![], wall: vec![], score: vec![] };
    let mut g = Game::new();
    for line in std::fs::read_to_string(path).unwrap().lines() {
        let p: Vec<&str> = line.split_whitespace().collect();
        if p[0] == "init" {
            // saque fixo: direção e velocidade inteiras
            g.reset_ball(p[1].parse().unwrap());
            g.serve_timer = 0.0;
            g.vx = p[2].parse().unwrap();
            g.vy = p[3].parse().unwrap();
            continue;
        }
        let mut keys = KeyboardState { k: [false; 512] };
        if p[1] != "-" {
            for k in p[1].split(',') {
                keys.k[k.parse::<usize>().unwrap()] = true;
            }
        }
        for _ in 0..p[0].parse::<u64>().unwrap() {
            g.update(&keys, STEP, &snd);
        }
    }
    println!(
        "left_y={:.4} right_y={:.4} bx={:.4} by={:.4} vx={:.4} vy={:.4} speed={:.4} score={}-{} serve_timer={:.4}",
        g.left_y, g.right_y, g.bx, g.by, g.vx, g.vy, g.speed, g.score_l, g.score_r, g.serve_timer
    );
}
