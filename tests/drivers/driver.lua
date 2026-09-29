-- Driver de teste (Lua): aplica um roteiro à lógica do jogo, sem janela.
package.path = arg[1] .. "/?.lua;" .. package.path
local ffi = require("ffi")
local game = require(os.getenv("GAME"))

local g = game.Game.new(0)
g.play = function() end
for line in io.lines(arg[2]) do
    local dir, vx, vy = line:match("^init%s+(%S+)%s+(%S+)%s+(%S+)")
    if dir then  -- saque fixo: direção e velocidade inteiras
        g:reset_ball(tonumber(dir))
        g.serve_timer = 0
        g.vx, g.vy = tonumber(vx), tonumber(vy)
    else
        local steps, ks = line:match("^(%S+)%s+(%S+)")
        local keys = ffi.new("uint8_t[512]")
        if ks ~= "-" then for k in ks:gmatch("%d+") do keys[tonumber(k)] = 1 end end
        for _ = 1, tonumber(steps) do g:update(keys, game.STEP) end
    end
end
print(string.format("left_y=%.4f right_y=%.4f bx=%.4f by=%.4f vx=%.4f vy=%.4f speed=%.4f score=%d-%d serve_timer=%.4f",
    g.left_y, g.right_y, g.bx, g.by, g.vx, g.vy, g.speed, g.score_l, g.score_r, g.serve_timer))
