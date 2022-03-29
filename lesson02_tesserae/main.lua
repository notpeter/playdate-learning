-- Standard libs from PlayDate SDK
import "CoreLibs/object"
import "CoreLibs/graphics"
import "CoreLibs/sprites"
import "CoreLibs/timer"
-- Import Aliases (More performant and shorter)
local gfx <const> = playdate.graphics
local bip <const> = playdate.buttonIsPressed

-- Global state
local logo = nil -- playdate.graphics.sprite
local tiles = {} -- table of playdate.graphics.images
local tileSprites = {}
-- Random constants
local screenX <const> = 400
local screenY <const> = 240

local function spriteLoad()
    local _tiles = {}
    local tbl = {"1", "2", "3", "4", "5", "6", "7"}
    for key, val in ipairs(tbl) do
        _tiles[key] = playdate.graphics.image.new( string.format("images/24x24/%s.png", val))
        assert( _tiles[key], "image load failure")
    end
    return _tiles
end

local function myGameSetUp()
    tiles = spriteLoad()
    math.randomseed(playdate.getSecondsSinceEpoch())

    for key, val in ipairs({"1", "2", "3", "4", "5", "6", "7"}) do
        tileSprites[key] = playdate.graphics.sprite.new( tiles[key] )
        tileSprites[key]:moveTo( screenX / 2 + key * 24, screenY / 2 )
        tileSprites[key]:add()
    end

    -- -- Background image.
    -- local backgroundImage = playdate.graphics.image.new( "images/400x240-black.png" )
    -- assert( backgroundImage, "image load failure")
    -- playdate.graphics.sprite.setBackgroundDrawingCallback(
    --     function( x, y, width, height )
    --         playdate.graphics.setClipRect( x, y, width, height )
    --         backgroundImage:draw( 0, 0 )
    --         playdate.graphics.clearClipRect()
    --     end
    -- )
end

local function b2i(value) -- converts boolean to int
    return value == true and 1 or 0
end


function playdate.update()
    playdate.graphics.sprite.update()
    playdate.timer.updateTimers()
end

myGameSetUp()
