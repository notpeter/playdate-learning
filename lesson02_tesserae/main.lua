-- Standard libs from PlayDate SDK
import "CoreLibs/object"
import "CoreLibs/graphics"
import "CoreLibs/sprites"
import "CoreLibs/timer"
import "CoreLibs/crank"
import "tess_game"

-- Import Aliases (More performant and shorter)
local gfx <const> = playdate.graphics
local bjp <const> = playdate.buttonJustPressed
local bip <const> = playdate.buttonIsPressed

-- Globals
local game = nil -- Game

local function handleInput()
    -- This is a terrible, but simple crank interface.
    if not playdate.isCrankDocked() then
        local cranks = playdate.getCrankTicks(6)
        if cranks > 0 then
            game:undo()
        elseif cranks < 0 then
            game:redo()
        end
    end

    -- Undo/redo buffer
    if bip("b") then
        if bjp("left") then
            game:undo()
        elseif bjp("right") then
            game:redo()
        end
    -- Frame movement
    else
        if bjp("right") then
            game:frame_move("right")
        elseif bjp("left") then
            game:frame_move("left")
        elseif bjp("up") then
            game:frame_move("up")
        elseif bjp("down") then
            game:frame_move("down")
        end
    end

    -- ButtonA / Frame selection
    if playdate.buttonJustReleased( "a" ) then
        game:select()
    end
end

function playdate.update()
    playdate.graphics.sprite.update()
    playdate.timer.updateTimers()
    handleInput()
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


    -- game = Game:create(10, 7, 32, "easy")
    game = Game:create(6, 3, 32, "easy")
    -- game = Game:create(14, 10, 24)
    game:start()
end

game_setup()
