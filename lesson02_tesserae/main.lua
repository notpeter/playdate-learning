-- Standard libs from PlayDate SDK
import "CoreLibs/object"
import "CoreLibs/graphics"
import "CoreLibs/sprites"
import "CoreLibs/timer"
-- Import Aliases (More performant and shorter)
local gfx <const> = playdate.graphics
local bjp <const> = playdate.buttonJustPressed

-- Global state
local tiles = {} -- table of playdate.graphics.images
local tileSprites = {}
local game = {}
local fPos = 1
local frameSprite = nil -- playdate.graphics.sprite
-- Random constants
local boardX <const> = 16
local boardY <const> = 8

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

local function pos2(position)
    local posX = (position - 1) % boardX + 1
    local posY = (position - 1) // boardX + 1
    return posX, posY
end

local function move(tile1, tile2)
    return
end

local function myGameSetUp()
    tiles = spriteLoad()
    math.randomseed(playdate.getSecondsSinceEpoch())

    local p = 0
    while (p < (boardX * boardY))
    do
        p = p + 1
        game[p] = 2 ^ math.random(0,2)
        local x, y = pos2(p)
        tileSprites[p] = playdate.graphics.sprite.new( tiles[game[p]] )
        tileSprites[p]:moveTo( 0 + 24 * x, 0 + 24 * y)
        tileSprites[p]:add()
    end

    local frameImage = playdate.graphics.image.new( "images/24x24/frame.png")
    assert( frameImage, "image load failure")
    frameSprite = playdate.graphics.sprite.new( frameImage )
    frameSprite:moveTo( 24, 24)
    frameSprite:add()

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

    local adjust = 0
    local fx, fy = pos2(fPos)
    -- d-pad control
    if bjp("right") then
        if fx == boardX then
            adjust = -boardX
        end
        fPos = fPos + 1 + adjust
    elseif bjp("left") then
        if fx == 1 then
            adjust = boardX
        end
        fPos = fPos - 1 + adjust
    elseif bjp("up") then
        if fy == 1 then
            adjust = boardX * boardY
        end
        fPos = fPos - boardX + adjust
    elseif bjp("down") then
        if fy == boardY then
            fPos = fx
        else
            fPos = fPos + boardX
        end
    end
    fx, fy = pos2(fPos)

    frameSprite:moveTo( 0 + 24 * fx, 0 + 24 * fy)
end

myGameSetUp()
