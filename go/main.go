// Pong em Go com SDL2 (github.com/veandco/go-sdl2).
package main

import (
	"encoding/binary"
	"fmt"
	"math"
	"math/rand"
	"os"
	"runtime"
	"strconv"

	"github.com/veandco/go-sdl2/sdl"
)

const (
	W            = 640
	H            = 480
	PaddleW      = 10
	PaddleH      = 60
	PaddleMargin = 20
	Ball         = 10
	PaddleSpeed  = 400.0
	BallSpeed    = 300.0
	BallMax      = 720.0
	Speedup      = 1.07
	MaxAngle     = math.Pi / 4
	Step         = 1.0 / 120.0
	ServeDelay   = 1.0
	Rate         = 44100
)

// Fonte 3x5 para os dígitos do placar.
var digits = [10]string{
	"111101101101111", "001001001001001", "111001111100111", "111001111001111",
	"101101111001001", "111100111001111", "111100111101111", "111001001001001",
	"111101111101111", "111101111001111",
}

// squareWave gera uma onda quadrada mono S16 (bytes little-endian): um "beep" Atari.
func squareWave(freq, ms int) []byte {
	n := Rate * ms / 1000
	buf := make([]byte, n*2)
	for i := 0; i < n; i++ {
		v := int16(-4000)
		if (i*2*freq/Rate)%2 == 1 {
			v = 4000
		}
		binary.LittleEndian.PutUint16(buf[i*2:], uint16(v))
	}
	return buf
}

type Game struct {
	leftY, rightY      float64
	bx, by, vx, vy     float64
	speed              float64
	serveTimer         float64
	serveDir           float64
	scoreL, scoreR     int
	audio              sdl.AudioDeviceID
	sndPaddle, sndWall []byte
	sndScore           []byte
}

func (g *Game) play(s []byte) {
	if g.audio == 0 {
		return
	}
	sdl.ClearQueuedAudio(g.audio)
	sdl.QueueAudio(g.audio, s)
}

func (g *Game) resetBall(dir float64) {
	g.bx = (W - Ball) / 2.0
	g.by = (H - Ball) / 2.0
	g.vx, g.vy = 0, 0
	g.speed = BallSpeed
	g.serveDir = dir
	g.serveTimer = ServeDelay
}

func (g *Game) launch() {
	a := (rand.Float64()*2 - 1) * math.Pi / 6
	g.vx = g.serveDir * g.speed * math.Cos(a)
	g.vy = g.speed * math.Sin(a)
}

func (g *Game) bounce(dir, paddleY float64) {
	g.speed = math.Min(g.speed*Speedup, BallMax)
	rel := ((g.by + Ball/2.0) - (paddleY + PaddleH/2.0)) / (PaddleH / 2.0)
	a := math.Max(-1, math.Min(1, rel)) * MaxAngle
	g.vx = dir * g.speed * math.Cos(a)
	g.vy = g.speed * math.Sin(a)
	g.play(g.sndPaddle)
}

func overlapsY(by, py float64) bool { return by+Ball >= py && by <= py+PaddleH }

func clamp(v, lo, hi float64) float64 { return math.Max(lo, math.Min(hi, v)) }

func (g *Game) update(keys []uint8, dt float64) {
	if keys[sdl.SCANCODE_W] != 0 {
		g.leftY -= PaddleSpeed * dt
	}
	if keys[sdl.SCANCODE_S] != 0 {
		g.leftY += PaddleSpeed * dt
	}
	if keys[sdl.SCANCODE_UP] != 0 {
		g.rightY -= PaddleSpeed * dt
	}
	if keys[sdl.SCANCODE_DOWN] != 0 {
		g.rightY += PaddleSpeed * dt
	}
	g.leftY = clamp(g.leftY, 0, H-PaddleH)
	g.rightY = clamp(g.rightY, 0, H-PaddleH)

	if g.serveTimer > 0 {
		g.serveTimer -= dt
		if g.serveTimer <= 0 {
			g.launch()
		}
		return
	}

	g.bx += g.vx * dt
	g.by += g.vy * dt

	if g.by < 0 {
		g.by = 0
		g.vy = math.Abs(g.vy)
		g.play(g.sndWall)
	}
	if g.by+Ball > H {
		g.by = H - Ball
		g.vy = -math.Abs(g.vy)
		g.play(g.sndWall)
	}

	const lx, rx = PaddleMargin, W - PaddleMargin - PaddleW
	if g.vx < 0 && g.bx <= lx+PaddleW && g.bx+Ball >= lx && overlapsY(g.by, g.leftY) {
		g.bx = lx + PaddleW
		g.bounce(1, g.leftY)
	}
	if g.vx > 0 && g.bx+Ball >= rx && g.bx <= rx+PaddleW && overlapsY(g.by, g.rightY) {
		g.bx = rx - Ball
		g.bounce(-1, g.rightY)
	}

	if g.bx+Ball < 0 {
		g.scoreR++
		g.play(g.sndScore)
		g.resetBall(-1)
	}
	if g.bx > W {
		g.scoreL++
		g.play(g.sndScore)
		g.resetBall(1)
	}
}

func fill(r *sdl.Renderer, x, y, w, h int32) {
	r.FillRect(&sdl.Rect{X: x, Y: y, W: w, H: h})
}

// drawNumber desenha um número; alignRight=true faz o número terminar em x.
func drawNumber(r *sdl.Renderer, n int, x, y int32, alignRight bool) {
	const S = 8
	s := strconv.Itoa(n)
	l := int32(len(s))
	if alignRight {
		x -= l*3*S + (l-1)*S
	}
	for _, c := range s {
		g := digits[c-'0']
		for i := int32(0); i < 15; i++ {
			if g[i] == '1' {
				fill(r, x+(i%3)*S, y+(i/3)*S, S, S)
			}
		}
		x += 4 * S
	}
}

func render(r *sdl.Renderer, g *Game) {
	r.SetDrawColor(0, 0, 0, 255)
	r.Clear()
	r.SetDrawColor(255, 255, 255, 255)
	for y := int32(6); y < H; y += 24 {
		fill(r, W/2-2, y, 4, 12)
	}
	drawNumber(r, g.scoreL, W/2-40, 20, true)
	drawNumber(r, g.scoreR, W/2+40, 20, false)
	fill(r, PaddleMargin, int32(g.leftY), PaddleW, PaddleH)
	fill(r, W-PaddleMargin-PaddleW, int32(g.rightY), PaddleW, PaddleH)
	fill(r, int32(g.bx), int32(g.by), Ball, Ball)
	r.Present()
}

func run() error {
	if err := sdl.Init(sdl.INIT_VIDEO | sdl.INIT_AUDIO); err != nil {
		return err
	}
	defer sdl.Quit()

	win, err := sdl.CreateWindow("Pong - Go", sdl.WINDOWPOS_CENTERED, sdl.WINDOWPOS_CENTERED,
		W, H, sdl.WINDOW_SHOWN)
	if err != nil {
		return err
	}
	defer win.Destroy()
	ren, err := sdl.CreateRenderer(win, -1, sdl.RENDERER_ACCELERATED|sdl.RENDERER_PRESENTVSYNC)
	if err != nil {
		return err
	}
	defer ren.Destroy()

	g := &Game{
		leftY:     (H - PaddleH) / 2.0,
		rightY:    (H - PaddleH) / 2.0,
		sndPaddle: squareWave(460, 50),
		sndWall:   squareWave(230, 50),
		sndScore:  squareWave(490, 250),
	}
	want := sdl.AudioSpec{Freq: Rate, Format: sdl.AUDIO_S16LSB, Channels: 1, Samples: 1024}
	if dev, err := sdl.OpenAudioDevice("", false, &want, nil, 0); err == nil {
		g.audio = dev
		sdl.PauseAudioDevice(dev, false)
		defer sdl.CloseAudioDevice(dev)
	} else {
		fmt.Fprintln(os.Stderr, "sem áudio:", err)
	}

	if rand.Intn(2) == 0 {
		g.resetBall(1)
	} else {
		g.resetBall(-1)
	}

	last := sdl.GetPerformanceCounter()
	acc := 0.0
	for {
		for e := sdl.PollEvent(); e != nil; e = sdl.PollEvent() {
			if _, ok := e.(*sdl.QuitEvent); ok {
				return nil
			}
		}
		keys := sdl.GetKeyboardState()
		if keys[sdl.SCANCODE_ESCAPE] != 0 {
			return nil
		}

		now := sdl.GetPerformanceCounter()
		acc += math.Min(float64(now-last)/float64(sdl.GetPerformanceFrequency()), 0.25)
		last = now
		for acc >= Step {
			g.update(keys, Step)
			acc -= Step
		}
		render(ren, g)
	}
}

// A SDL exige que vídeo/eventos rodem na thread principal do SO.
func init() { runtime.LockOSThread() }

func main() {
	if err := run(); err != nil {
		fmt.Fprintln(os.Stderr, "erro:", err)
		os.Exit(1)
	}
}
