-- Standard libs from PlayDate SDK
import "CoreLibs/object"
import "CoreLibs/graphics"
import "CoreLibs/sprites"
import "CoreLibs/timer"
-- Import Aliases (More performant and shorter)
local gfx <const> = playdate.graphics
local bjp <const> = playdate.buttonJustPressed
local bip <const> = playdate.buttonIsPressed


-- Global state
local tiles = {} -- table of playdate.graphics.images
local tileSprites = {}
local game = {}
local fPos = 1
local frameImages = {} -- table of playdate.graphics.images
local frameSprite = nil -- playdate.graphics.sprite
local frameSelected = 0
local selectedPos = nil
-- Random constants
local boardX <const> = 16
local boardY <const> = 8

local screenX <const> = 400
local screenY <const> = 240

local function dump(o)
    if type(o) == 'table' then
        local s = '{ '
        for k,v in pairs(o) do
                if type(k) ~= 'number' then k = '"'..k..'"' end
                s = s .. '['..k..'] = ' .. dump(v) .. ','
        end
        return s .. '} '
    else
        return tostring(o)
    end
end

local function spriteLoad()
    local _tiles = {}
    local tbl = {"1", "2", "3", "4", "5", "6", "7"}
    for key, val in ipairs(tbl) do
        _tiles[key] = playdate.graphics.image.new( string.format("images/24x24/%s.png", val))
        assert( _tiles[key], "image load failure")
    end
    return _tiles
end

local function _isPrimary(tile)
    if tile == 1 then
        return true
    elseif tile == 2 then
        return true
    elseif tile == 4 then
        return true
    else
        return false
    end
end

local function _isSecondary(tile)
    if tile == 3 then
        return true
    elseif tile == 5 then
        return true
    elseif tile == 6 then
        return true
    else
        return false
    end
end

local function _isTertiary(tile)
    if tile == 7 then
        return true
    else
        return false
    end
end

local function _hasCross(tile)
    if (tile & 4 > 0) then
        return true
    end
    return false
end
local function _hasCircle(tile)
    if tile == 1 or tile == 3 or tile == 5 or tile == 7 then
        return true
    end
    return false
end
local function _hasSquare(tile)
    if tile == 2 or tile == 3 or tile == 6 or tile == 7 then
        return true
    end
    return false
end

local function _contains(tile1, tile2)
    -- true when tile1 contains 2
    return (tile1 & tile2 == tile2)
end

local function _tileAdd(tile1, tile2)
    if tile1 == tile2 then
        return tile1
    elseif (tile1 | tile2) == (tile1 + tile2) then
        return tile1 | tile2
    end
    return 0
end

local function move(src, mid, dest)
    local valid = false
    local mid_ok = false
    local dest_ok = false

    if (_isPrimary(src) and _isPrimary(mid)) then
        new_mid = 0
    elseif (_contains(mid, src)) then
        new_mid = mid - src
    else
        return false, -1, -1
    end

    if not(_contains(dest, src)) or dest == 0 then
        new_dest = src + dest
    else
        return false, -1, -1
    end
    return true, new_mid, new_dest
end

local function pos2(position)
    local posX = (position - 1) % boardX + 1
    local posY = (position - 1) // boardX + 1
    return posX, posY
end

local function _valid_moves(position)
    moves = {}
    local x, y = pos2(position)
    local ok_right = x + 2 <= boardX
    local ok_left = x - 2 >= 1
    local ok_up = y - 2 >= 1
    local ok_down = y + 2 <= boardY
    if ok_right then
        table.insert(moves, position + 2)
    end
    if ok_left then
        table.insert(moves, position - 2)
    end
    if ok_down then
        table.insert(moves, position + 2 * boardX)
    end
    if ok_up then
        table.insert(moves, position - 2 * boardX)
    end
    if ok_up and ok_left then
        table.insert(moves, position - 2 * boardX - 2)
    end
    if ok_up and ok_right then
        table.insert(moves, position - 2 * boardX + 2)
    end
    if ok_down and ok_left then
        table.insert(moves, position + 2 * boardX - 2)
    end
    if ok_down and ok_right then
        table.insert(moves, position + 2 * boardX + 2)
    end
    return moves
end


local function myGameSetUp()
    tiles = spriteLoad()
    math.randomseed(playdate.getSecondsSinceEpoch())

    local p = 0
    while (p < (boardX * boardY))
    do
        p = p + 1
        game[p] = 2 ^ math.random(0,2)
        -- game[p] = math.random(1,7)
        local x, y = pos2(p)
        tileSprites[p] = playdate.graphics.sprite.new( tiles[game[p]] )
        tileSprites[p]:moveTo( 0 + 24 * x, 0 + 24 * y)
        tileSprites[p]:add()
    end

    frameImages[0] = playdate.graphics.image.new( "images/24x24/frame.png")
    assert( frameImages[0], "image load failure")
    frameImages[1] = playdate.graphics.image.new( "images/24x24/frame-selected.png")
    assert( frameImages[1], "image load failure")

    frameSprite = playdate.graphics.sprite.new( frameImages[0] )
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

    if frameSelected == 0 then
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
    else
        -- if bip("right") then
        --     print(fPos, fPos + 2, game[fPos], game[fPos +2])
        -- elseif bip("left") then
        --     print(fPos, fPos - 2, game[fPos], game[fPos -2])
        -- elseif bip("down") then
        --     print(fPos, fPos + boardX, game[fPos], game[fPos + boardX])
        -- elseif bip("up") then
        --     print(fPos, fPos - boardX, game[fPos], game[fPos - boardX])
        -- end
    end

    -- ButtonA / Frame selection
    if playdate.buttonJustReleased( "a" ) then
        selectedPos = fPos
        if frameSelected == 1 then
            frameSelected = 0
            frameSprite:setImage(frameImages[0])
        else
            frameSelected = 1
            frameSprite:setImage(frameImages[1])
            print(fPos, dump(_valid_moves(fPos)))
        end
    end
end

myGameSetUp()
