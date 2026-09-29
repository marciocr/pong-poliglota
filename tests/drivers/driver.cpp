// Driver de teste (C++): inclui o jogo, renomeando o main() dele.
#define main jogo_main
#include "main.cpp"
#undef main
#include <cstdio>
#include <fstream>
#include <sstream>

int main(int, char** argv) {
    Game g;
    std::ifstream f(argv[1]);
    std::string line;
    while (std::getline(f, line)) {
        std::istringstream ss(line);
        std::string first;
        ss >> first;
        if (first == "init") {  // saque fixo: direção e velocidade inteiras
            int dir, vx, vy;
            ss >> dir >> vx >> vy;
            g.reset_ball(dir);
            g.serve_timer = 0;
            g.vx = vx;
            g.vy = vy;
            continue;
        }
        std::string ks;
        ss >> ks;
        Uint8 keys[512] = {};
        if (ks != "-") {
            std::stringstream k(ks);
            std::string n;
            while (std::getline(k, n, ',')) keys[std::stoi(n)] = 1;
        }
        for (long i = 0, steps = std::stol(first); i < steps; ++i) g.update(keys, STEP);
    }
    std::printf("left_y=%.4f right_y=%.4f bx=%.4f by=%.4f vx=%.4f vy=%.4f speed=%.4f score=%d-%d serve_timer=%.4f\n",
                g.left_y, g.right_y, g.bx, g.by, g.vx, g.vy, g.speed, g.score_l, g.score_r, g.serve_timer);
}
