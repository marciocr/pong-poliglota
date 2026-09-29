import java.lang.foreign.Arena;
import java.lang.foreign.MemorySegment;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Locale;

import static java.lang.foreign.ValueLayout.JAVA_BYTE;

/** Driver de teste (Java): aplica um roteiro à lógica do jogo, sem janela. */
public class Drv {
    public static void main(String[] a) throws Exception {
        try (Arena arena = Arena.ofConfined()) {
            var g = new @CLASS@.Game(arena, 0);
            MemorySegment keys = arena.allocate(512);
            for (String line : Files.readAllLines(Path.of(a[0]))) {
                String[] p = line.trim().split("\\s+");
                if (p[0].equals("init")) {  // saque fixo: direção e velocidade inteiras
                    g.resetBall(Double.parseDouble(p[1]));
                    g.serveTimer = 0;
                    g.vx = Double.parseDouble(p[2]);
                    g.vy = Double.parseDouble(p[3]);
                    continue;
                }
                keys.fill((byte) 0);
                if (!p[1].equals("-")) for (String s : p[1].split(",")) keys.set(JAVA_BYTE, Integer.parseInt(s), (byte) 1);
                for (long i = 0, n = Long.parseLong(p[0]); i < n; i++) g.update(keys, @CLASS@.STEP);
            }
            System.out.println(String.format(Locale.ROOT,
                "left_y=%.4f right_y=%.4f bx=%.4f by=%.4f vx=%.4f vy=%.4f speed=%.4f score=%d-%d serve_timer=%.4f",
                g.leftY, g.rightY, g.bx, g.by, g.vx, g.vy, g.speed, g.scoreL, g.scoreR, g.serveTimer));
        }
    }
}
