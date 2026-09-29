// Driver de teste (C#): completa a classe do jogo (agora "partial") com um Main.
using System;
using System.Globalization;
using System.IO;

unsafe partial class @CLASS@
{
    static int Main(string[] args)
    {
        CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
        var g = new Game(0);
        byte* keys = stackalloc byte[512];
        foreach (var line in File.ReadAllLines(args[0]))
        {
            var p = line.Split(' ', StringSplitOptions.RemoveEmptyEntries);
            if (p[0] == "init")  // saque fixo: direção e velocidade inteiras
            {
                g.ResetBall(double.Parse(p[1]));
                g.ServeTimer = 0;
                g.Vx = double.Parse(p[2]);
                g.Vy = double.Parse(p[3]);
                continue;
            }
            for (int i = 0; i < 512; i++) keys[i] = 0;
            if (p[1] != "-") foreach (var s in p[1].Split(',')) keys[int.Parse(s)] = 1;
            for (long i = 0, n = long.Parse(p[0]); i < n; i++) g.Update(keys, STEP);
        }
        Console.WriteLine($"left_y={g.LeftY:F4} right_y={g.RightY:F4} bx={g.Bx:F4} by={g.By:F4} vx={g.Vx:F4} vy={g.Vy:F4} speed={g.Speed:F4} score={g.ScoreL}-{g.ScoreR} serve_timer={g.ServeTimer:F4}");
        return 0;
    }
}
