#!/usr/bin/env python3
"""Gera os roteiros de tests/scripts/ usando a versão Python como "robô".

Formato dos roteiros: uma linha "init <direção> <vx> <vy>" com o saque fixo (o
único sorteio do Pong), e depois linhas "<passos> <scancodes|->", em que cada
passo é 1/120 s de física. Um roteiro termina logo depois do primeiro ponto:
o saque seguinte sorteia o ângulo, e por isso não é reprodutível.

Os roteiros já estão no repositório; este arquivo só documenta como nasceram.
Uso: python3 tests/gen_scripts.py
"""
import os
import random
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "python"))
import pong as game  # noqa: E402

W_KEY, S_KEY, UP_KEY, DOWN_KEY = 26, 22, 82, 81


def robot(paddle_y, ball_y, bias):
    """+1 desce, -1 sobe, 0 fica, mirando o centro da bola com um erro."""
    center = paddle_y + game.PADDLE_H / 2
    target = ball_y + game.BALL / 2 + bias
    return 1 if target > center + 4 else -1 if target < center - 4 else 0


def make(name, init, seed, bias_range, max_steps=60000, need_point=True):
    rnd = random.Random(seed)
    g = game.Game(0)
    g.play = lambda s: None
    g.reset_ball(init[0])
    g.serve_timer = 0.0
    g.vx, g.vy = float(init[1]), float(init[2])
    segs, biases, tail = [], [0, 0], None
    for step in range(max_steps):
        if step % 240 == 0:
            biases = [rnd.uniform(-bias_range, bias_range) for _ in range(2)]
        left, right = robot(g.left_y, g.by, biases[0]), robot(g.right_y, g.by, biases[1])
        keys = set()
        if left < 0: keys.add(W_KEY)
        if left > 0: keys.add(S_KEY)
        if right < 0: keys.add(UP_KEY)
        if right > 0: keys.add(DOWN_KEY)
        arr = [0] * 512
        for k in keys: arr[k] = 1
        g.update(arr, game.STEP)
        label = ",".join(map(str, sorted(keys))) or "-"
        if segs and segs[-1][1] == label: segs[-1][0] += 1
        else: segs.append([1, label])
        if g.score_l + g.score_r and tail is None:
            tail = step + 40  # mais 1/3 s, dentro do 1 s de espera do saque
        if tail is not None and step >= tail:
            break
    else:
        if need_point:
            raise SystemExit(f"{name}: nenhum ponto em {max_steps} passos")
    with open(os.path.join(ROOT, "tests", "scripts", f"{name}.txt"), "w") as f:
        f.write("init %d %d %d\n" % init)
        for n, k in segs: f.write(f"{n} {k}\n")
    print(f"{name}: {sum(n for n, _ in segs)} passos, placar {g.score_l}-{g.score_r}, velocidade final {g.speed:.0f}")


os.makedirs(os.path.join(ROOT, "tests", "scripts"), exist_ok=True)
#          nome                 saque (dir, vx, vy)  semente  erro máx. da raquete (px)
make("rali_reto",          (1, 300, 0),     1, 0, max_steps=24000, need_point=False)  # raquetes perfeitas: rali sem ponto até a velocidade máxima
make("rali_erro_pequeno",  (-1, -300, 60),  2, 10)
make("rali_erro_medio",    (1, 290, -90),   3, 30)
make("rali_erro_grande",   (-1, -280, 100), 4, 60)
make("parede_de_cima",     (1, 300, -220),  5, 15)   # começa subindo: bate no teto
make("parede_de_baixo",    (-1, -300, 220), 6, 15)   # começa descendo: bate no chão
