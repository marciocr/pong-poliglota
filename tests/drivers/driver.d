
// Driver de teste (D): anexado ao fim do app.d, cujo main() foi renomeado.
int main(string[] args)
{
    import std.stdio : File, writefln;
    import std.string : split, strip;

    Game g;
    foreach (line; File(args[1]).byLine)
    {
        auto p = line.strip.split;
        if (p[0] == "init")  // saque fixo: direção e velocidade inteiras
        {
            g.resetBall(p[1].to!double);
            g.serveTimer = 0;
            g.vx = p[2].to!double;
            g.vy = p[3].to!double;
            continue;
        }
        ubyte[512] keys;
        if (p[1] != "-") foreach (k; p[1].split(",")) keys[k.to!int] = 1;
        foreach (_; 0 .. p[0].to!long) g.update(keys.ptr, STEP);
    }
    writefln("left_y=%.4f right_y=%.4f bx=%.4f by=%.4f vx=%.4f vy=%.4f speed=%.4f score=%d-%d serve_timer=%.4f",
             g.leftY, g.rightY, g.bx, g.by, g.vx, g.vy, g.speed, g.scoreL, g.scoreR, g.serveTimer);
    return 0;
}
