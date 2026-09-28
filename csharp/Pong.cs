// Pong em C# com SDL2, chamando a libSDL2 via P/Invoke.
using System;

unsafe class Pong
{
    const int W = 640, H = 480;
    const int PADDLE_W = 10, PADDLE_H = 60, PADDLE_MARGIN = 20;
    const int BALL = 10;
    const double PADDLE_SPEED = 400.0;
    const double BALL_SPEED = 300.0;
    const double BALL_MAX = 720.0;
    const double SPEEDUP = 1.07;
    const double MAX_ANGLE = Math.PI / 4;
    const double STEP = 1.0 / 120.0;
    const double SERVE_DELAY = 1.0;
    const int RATE = 44100;

    // Fonte 3x5 para os dígitos do placar.
    static readonly string[] Digits =
    [
        "111101101101111", "001001001001001", "111001111100111", "111001111001111",
        "101101111001001", "111100111001111", "111100111101111", "111001001001001",
        "111101111101111", "111101111001111",
    ];

    // Onda quadrada mono S16: um "beep" de console Atari.
    static short[] SquareWave(int freq, int ms)
    {
        var buf = new short[RATE * ms / 1000];
        for (int i = 0; i < buf.Length; i++)
            buf[i] = (short)(((long)i * 2 * freq / RATE) % 2 == 1 ? 4000 : -4000);
        return buf;
    }

    static bool OverlapsY(double by, double py) => by + BALL >= py && by <= py + PADDLE_H;

    sealed class Game(uint audio)
    {
        public double LeftY = (H - PADDLE_H) / 2.0, RightY = (H - PADDLE_H) / 2.0;
        public double Bx, By, Vx, Vy, Speed = BALL_SPEED;
        public double ServeTimer, ServeDir = 1;
        public int ScoreL, ScoreR;

        readonly short[] sndPaddle = SquareWave(460, 50);
        readonly short[] sndWall = SquareWave(230, 50);
        readonly short[] sndScore = SquareWave(490, 250);

        void Play(short[] s)
        {
            if (audio == 0) return;
            Sdl.ClearQueuedAudio(audio);
            fixed (short* p = s) Sdl.QueueAudio(audio, p, (uint)(s.Length * sizeof(short)));
        }

        public void ResetBall(double dir)
        {
            Bx = (W - BALL) / 2.0;
            By = (H - BALL) / 2.0;
            Vx = Vy = 0;
            Speed = BALL_SPEED;
            ServeDir = dir;
            ServeTimer = SERVE_DELAY;
        }

        void Launch()
        {
            double a = (Random.Shared.NextDouble() * 2 - 1) * Math.PI / 6;
            Vx = ServeDir * Speed * Math.Cos(a);
            Vy = Speed * Math.Sin(a);
        }

        void Bounce(double dir, double paddleY)
        {
            Speed = Math.Min(Speed * SPEEDUP, BALL_MAX);
            double rel = ((By + BALL / 2.0) - (paddleY + PADDLE_H / 2.0)) / (PADDLE_H / 2.0);
            double a = Math.Clamp(rel, -1, 1) * MAX_ANGLE;
            Vx = dir * Speed * Math.Cos(a);
            Vy = Speed * Math.Sin(a);
            Play(sndPaddle);
        }

        public void Update(byte* keys, double dt)
        {
            if (keys[Sdl.SCANCODE_W] != 0) LeftY -= PADDLE_SPEED * dt;
            if (keys[Sdl.SCANCODE_S] != 0) LeftY += PADDLE_SPEED * dt;
            if (keys[Sdl.SCANCODE_UP] != 0) RightY -= PADDLE_SPEED * dt;
            if (keys[Sdl.SCANCODE_DOWN] != 0) RightY += PADDLE_SPEED * dt;
            LeftY = Math.Clamp(LeftY, 0, H - PADDLE_H);
            RightY = Math.Clamp(RightY, 0, H - PADDLE_H);

            if (ServeTimer > 0)
            {
                ServeTimer -= dt;
                if (ServeTimer <= 0) Launch();
                return;
            }

            Bx += Vx * dt;
            By += Vy * dt;

            if (By < 0) { By = 0; Vy = Math.Abs(Vy); Play(sndWall); }
            if (By + BALL > H) { By = H - BALL; Vy = -Math.Abs(Vy); Play(sndWall); }

            const double lx = PADDLE_MARGIN, rx = W - PADDLE_MARGIN - PADDLE_W;
            if (Vx < 0 && Bx <= lx + PADDLE_W && Bx + BALL >= lx && OverlapsY(By, LeftY))
            {
                Bx = lx + PADDLE_W;
                Bounce(1, LeftY);
            }
            if (Vx > 0 && Bx + BALL >= rx && Bx <= rx + PADDLE_W && OverlapsY(By, RightY))
            {
                Bx = rx - BALL;
                Bounce(-1, RightY);
            }

            if (Bx + BALL < 0) { ScoreR++; Play(sndScore); ResetBall(-1); }
            if (Bx > W) { ScoreL++; Play(sndScore); ResetBall(1); }
        }
    }

    static void Fill(nint r, double x, double y, int w, int h) =>
        Sdl.RenderFillRect(r, new Sdl.Rect { X = (int)x, Y = (int)y, W = w, H = h });

    // Desenha um número; alignRight=true faz o número terminar em x.
    static void DrawNumber(nint r, int n, int x, int y, bool alignRight)
    {
        const int s = 8;
        string text = n.ToString();
        if (alignRight) x -= text.Length * 3 * s + (text.Length - 1) * s;
        foreach (char c in text)
        {
            string g = Digits[c - '0'];
            for (int i = 0; i < 15; i++)
                if (g[i] == '1') Fill(r, x + (i % 3) * s, y + (i / 3) * s, s, s);
            x += 4 * s;
        }
    }

    static void Render(nint r, Game g)
    {
        Sdl.SetRenderDrawColor(r, 0, 0, 0, 255);
        Sdl.RenderClear(r);
        Sdl.SetRenderDrawColor(r, 255, 255, 255, 255);
        for (int y = 6; y < H; y += 24) Fill(r, W / 2 - 2, y, 4, 12);
        DrawNumber(r, g.ScoreL, W / 2 - 40, 20, true);
        DrawNumber(r, g.ScoreR, W / 2 + 40, 20, false);
        Fill(r, PADDLE_MARGIN, g.LeftY, PADDLE_W, PADDLE_H);
        Fill(r, W - PADDLE_MARGIN - PADDLE_W, g.RightY, PADDLE_W, PADDLE_H);
        Fill(r, g.Bx, g.By, BALL, BALL);
        Sdl.RenderPresent(r);
    }

    static int Main()
    {
        if (Sdl.Init(Sdl.INIT_VIDEO | Sdl.INIT_AUDIO) != 0)
        {
            Console.Error.WriteLine("SDL_Init: " + Sdl.GetError());
            return 1;
        }
        nint win = Sdl.CreateWindow("Pong - C#", Sdl.WINDOWPOS_CENTERED, Sdl.WINDOWPOS_CENTERED, W, H, Sdl.WINDOW_SHOWN);
        nint ren = win == 0 ? 0 : Sdl.CreateRenderer(win, -1, Sdl.RENDERER_ACCELERATED | Sdl.RENDERER_PRESENTVSYNC);
        if (ren == 0)
        {
            Console.Error.WriteLine("janela/renderer: " + Sdl.GetError());
            return 1;
        }

        var want = new Sdl.AudioSpec { Freq = RATE, Format = Sdl.AUDIO_S16LSB, Channels = 1, Samples = 1024 };
        uint audio = Sdl.OpenAudioDevice(0, 0, want, 0, 0);
        if (audio != 0) Sdl.PauseAudioDevice(audio, 0);
        else Console.Error.WriteLine("sem áudio: " + Sdl.GetError());

        var game = new Game(audio);
        game.ResetBall(Random.Shared.Next(2) == 0 ? 1 : -1);

        byte* keys = Sdl.GetKeyboardState(null);
        double freq = Sdl.GetPerformanceFrequency();
        ulong last = Sdl.GetPerformanceCounter();
        double acc = 0;
        bool running = true;
        while (running)
        {
            while (Sdl.PollEvent(out var e) != 0)
                if (e.Type == Sdl.QUIT) running = false;
            if (keys[Sdl.SCANCODE_ESCAPE] != 0) running = false;

            ulong now = Sdl.GetPerformanceCounter();
            acc += Math.Min((now - last) / freq, 0.25);
            last = now;
            while (acc >= STEP)
            {
                game.Update(keys, STEP);
                acc -= STEP;
            }
            Render(ren, game);
        }

        if (audio != 0) Sdl.CloseAudioDevice(audio);
        Sdl.DestroyRenderer(ren);
        Sdl.DestroyWindow(win);
        Sdl.Quit();
        return 0;
    }
}
