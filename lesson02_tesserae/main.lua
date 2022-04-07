-- Standard libs from PlayDate SDK
import "CoreLibs/object"
import "CoreLibs/graphics"
import "CoreLibs/sprites"
import "CoreLibs/timer"
import "CoreLibs/crank"
import "tess_game"

-- Globals
local game = nil -- Game


function playdate.update()
    playdate.graphics.sprite.update()
    playdate.timer.updateTimers()
    game:handle_input()
    game:draw_grid()
    game:draw_scoreboard()
end

local function game_setup()
    math.randomseed(playdate.getSecondsSinceEpoch())
    menu = playdate.getSystemMenu()

    menu:addMenuItem("retile", function() game:retile("easy") end)
    local file = "poop"
    menu:addMenuItem("save", function() game:Write(file) end)
    menu:addMenuItem("load", function()
        playdate.graphics.sprite.removeAll()
        game = game.Read(file)
    while game:redo() do end
    end)


    game = Game:create(10, 7, 32, "easy")
    -- game = Game:create(6, 3, 32, "easy")
    -- game = Game:create(14, 10, 24)
    game:start()
end

game_setup()
