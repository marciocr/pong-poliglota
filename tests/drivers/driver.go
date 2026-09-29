// Driver de teste (Go): roda no mesmo pacote do jogo, cujo main() foi renomeado.
package main

import (
	"bufio"
	"fmt"
	"os"
	"strconv"
	"strings"
)

func main() {
	g := &Game{leftY: (H - PaddleH) / 2.0, rightY: (H - PaddleH) / 2.0}
	f, _ := os.Open(os.Args[1])
	sc := bufio.NewScanner(f)
	for sc.Scan() {
		p := strings.Fields(sc.Text())
		if p[0] == "init" { // saque fixo: direção e velocidade inteiras
			dir, _ := strconv.Atoi(p[1])
			vx, _ := strconv.Atoi(p[2])
			vy, _ := strconv.Atoi(p[3])
			g.resetBall(float64(dir))
			g.serveTimer = 0
			g.vx, g.vy = float64(vx), float64(vy)
			continue
		}
		steps, _ := strconv.Atoi(p[0])
		keys := make([]uint8, 512)
		if p[1] != "-" {
			for _, k := range strings.Split(p[1], ",") {
				n, _ := strconv.Atoi(k)
				keys[n] = 1
			}
		}
		for i := 0; i < steps; i++ {
			g.update(keys, Step)
		}
	}
	fmt.Printf("left_y=%.4f right_y=%.4f bx=%.4f by=%.4f vx=%.4f vy=%.4f speed=%.4f score=%d-%d serve_timer=%.4f\n",
		g.leftY, g.rightY, g.bx, g.by, g.vx, g.vy, g.speed, g.scoreL, g.scoreR, g.serveTimer)
}
