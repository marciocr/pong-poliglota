"""Driver de teste (Python): aplica um roteiro à lógica do jogo, sem janela."""
import importlib
import os
import sys

sys.path.insert(0, sys.argv[1])
game = importlib.import_module(os.environ["GAME"])

g = game.Game(0)
g.play = lambda s: None
for line in open(sys.argv[2]):
    p = line.split()
    if p[0] == "init":  # saque fixo: direção e velocidade inteiras
        g.reset_ball(int(p[1]))
        g.serve_timer = 0.0
        g.vx, g.vy = float(p[2]), float(p[3])
        continue
    keys = [0] * 512
    if p[1] != "-":
        for k in p[1].split(","):
            keys[int(k)] = 1
    for _ in range(int(p[0])):
        g.update(keys, game.STEP)
print("left_y=%.4f right_y=%.4f bx=%.4f by=%.4f vx=%.4f vy=%.4f speed=%.4f score=%d-%d serve_timer=%.4f"
      % (g.left_y, g.right_y, g.bx, g.by, g.vx, g.vy, g.speed, g.score_l, g.score_r, g.serve_timer))
