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
local images = {} -- table of playdate.graphics.images
local tileSprites = {}  -- table of playdate.graphics.sprite
local blinkSprites = {} -- table of playdate.graphics.sprite
local frameSprite = nil -- playdate.graphics.sprite

local game = {}
local frame_pos = 1
local selectedPos = nil
local validMoves = {}

local blinkTimer = nil

-- Random constants
local boards = {
    [1] = {x=14, y=10, size=24},
    [2] = {x=10, y=7, size=32},
}
local board = boards[2]
local difficulty = {
    -- TODO: Make less difficult. E.g. medium 2/3 primary; 1/3 secondary not 1/2 & 1/2.
    easy = function(); return 2 ^ math.random(0,2); end,    -- all primary
    medium = function(); return math.random(1,6); end,      -- primary & secondary
    hard = function(); return math.random(1,7); end,        -- primary, secondary & tertiary
}
local boardX = board.x
local boardY = board.y
local tileSize = board.size

local screenX <const> = 400
local screenY <const> = 240

local function tile2str(tile)
    local k =  {
        [0]="     ",
        [1]="(   )",
        [2]="  +  ",
        [3]="( + )",
        [4]=" [ ] ",
        [5]="([ ])",
        [6]=" [+] ",
        [7]="([+])"
    }
    return k[tile]
end

local function dump(o)
    if type(o) == 'table' then
        local s = '{ '
        for k,v in pairs(o) do
                if type(k) ~= 'number' then k = '"'..k..'"' end
                s = s .. '['..k..']=' .. dump(v) .. ', '
        end
        return s .. '} '
    else
        return tostring(o)
    end
end

local function imagesLoad()
    local _images = {}
    local filename = ""
    for key, val in pairs({
        [0]="0.png", [1]="1.png", [2]="2.png", [3]="3.png",
        [4]="4.png", [5]="5.png", [6]="6.png", [7]="7.png",
        frame="frame.png",
        frame_selected="frame-selected.png",
        dot="dot.png",
        box="box.png",
    }) do
        filename = string.format("images/%sx%s/%s", tileSize, tileSize, val)
        _images[key] = playdate.graphics.image.new( filename )
        assert( _images[key], "image load failure: " .. filename)
    end
    return _images
end

local function _isPrimary(tile); return tile == 1 or tile == 2 or tile == 4; end
local function _isSecondary(tile); return tile == 3 or tile == 5 or tile == 6; end
local function _isTertiary(tile); return tile == 7; end
local function _hasCircle(tile); return tile & 1 > 0; end
local function _hasCross(tile); return tile & 2 > 0; end
local function _hasSquare(tile); return tile & 4 > 0; end

local function _contains(tile1, tile2)
    -- true when tile1 contains 2
    return (tile1 & tile2 == tile2)
end

local function move(src, mid, dest)
    -- returns (valid:bool, new_mid:int, new_dest:int)
    -- Check if dest tile is suitable
    if dest == 0 or src == dest or (src | dest == src + dest) then
        -- Check whether mid tile is suitable.
        if _isPrimary(src) and _isPrimary(mid) then
            return true, 0, src | dest
        elseif _contains(mid, src) then
            return true, mid - src, src | dest
        end
    end
    return false, nil, nil
end

local function tilePos(x, y)
    -- Takes x,y board coordinates; returns xy screen coordinates (sprite location)
    return -tileSize // 2 + tileSize * x, -tileSize // 2 + tileSize * y
end

local function pos2(position)
    -- Takes int position and returns x,y board coordinates.
    local posX = (position - 1) % boardX + 1
    local posY = (position - 1) // boardX + 1
    return posX, posY
end

local function _mid_pos(src_pos, dest_pos)
    -- returns the midpoint between two tiles (does no validation)
    local x1, y1 = pos2(src_pos)
    local x2, y2 = pos2(dest_pos)
    return (x1 + x2 // 2), (y1 + y2 // 2)
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
    local valids = {}
    local new_dest = null
    local new_mid = null
    local mid_pos = null
    local valid = false
    for _, dest_pos in pairs(moves) do
        mid_pos = _mid_pos(position, dest_pos)
        valid, new_mid, new_dest = move(game[position], game[mid_pos], game[dest_pos])
        if valid then
            valids[dest_pos] = new_dest
        end
    end
    return valids
end

local function myGameSetUp()
    images = imagesLoad()
    math.randomseed(playdate.getSecondsSinceEpoch())

    local p = 0
    while (p < (boardX * boardY))
    do
        p = p + 1
        game[p] = difficulty.easy()

        local x, y = tilePos(pos2(p)) -- Sprite coordinates

        local tileSprite = playdate.graphics.sprite.new( images[game[p]] )
        tileSprite:moveTo(x, y)
        tileSprite:add()
        tileSprites[p] = tileSprite

        local blinkSprite = playdate.graphics.sprite.new( images.dot )
        blinkSprite:moveTo(x, y)
        blinkSprite:setVisible(false)
        blinkSprite:add()
        blinkSprites[p] = blinkSprite
    end

    frameSprite = playdate.graphics.sprite.new( images.frame )
    frameSprite:moveTo( tilePos(1, 1) )
    frameSprite:add()

    local function blinkCallback()
        if not(selectedPos == nil) then
            print("blink", dump(validMoves))
            for dest_pos, new_dest in pairs(validMoves) do
                blinkSprites[dest_pos]:setVisible(not(blinkSprites[dest_pos]:isVisible()))
            end
        end
    end
    blinkTimer = playdate.timer.keyRepeatTimerWithDelay(500, 500, blinkCallback)

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

    if selectedPos == nil then
        local fx, fy = pos2(frame_pos) -- frame x,y board coordinates
        -- d-pad control. b2i terms apply screen wrap if required.
        if bjp("right") then
            frame_pos = frame_pos + 1 + (b2i(fx == boardX) * -boardX)
        elseif bjp("left") then
            frame_pos = frame_pos - 1 + (b2i(fx == 1) * boardX)
        elseif bjp("up") then
            frame_pos = frame_pos - boardX + (b2i(fy == 1) * boardX * boardY)
        elseif bjp("down") then
            frame_pos = frame_pos + boardX - (b2i(fy == boardY) * boardX * boardY)
        end
        fx, fy = pos2(frame_pos)
        frameSprite:moveTo( tilePos(pos2(frame_pos)) )
    else

        -- if bip("right") then
        --     print(frame_pos, frame_pos + 2, game[frame_pos], game[frame_pos +2])
        -- elseif bip("left") then
        --     print(frame_pos, frame_pos - 2, game[frame_pos], game[frame_pos -2])
        -- elseif bip("down") then
        --     print(frame_pos, frame_pos + boardX, game[frame_pos], game[frame_pos + boardX])
        -- elseif bip("up") then
        --     print(frame_pos, frame_pos - boardX, game[frame_pos], game[frame_pos - boardX])
        -- end
    end

    -- ButtonA / Frame selection
    if playdate.buttonJustReleased( "a" ) then
        if selectedPos == nil then -- new selection
            selectedPos = frame_pos
            frameSprite:setImage(images.frame_selected)
            validMoves = _valid_moves(frame_pos)
            for dest_pos, new_dest in pairs(validMoves) do
                blinkSprites[dest_pos]:setVisible(true)
            end
        else -- clearing selection
            selectedPos = nil
            frameSprite:setImage(images.frame)
            validMoves = {}
            for dest_pos, new_dest in pairs(validMoves) do
                blinkSprites[dest_pos]:setVisible(false)
            end
        end
    end
end

myGameSetUp()
