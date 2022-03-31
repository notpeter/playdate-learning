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
local blinkingSprites = {} -- table of playdate.graphics.sprite
local frameSprite = nil -- playdate.graphics.sprite
local selectedSprite = nil -- playdate.graphics.sprite

local game = {} -- table of ints ()
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

local function setupTiles()  --> table[playdate.graphics.sprite]
    local sprite = nil --> playdate.graphics.sprite
    local tile_sprites = {} --> table[playdate.graphics.sprite]
    local num_tiles <const> = boardX * boardY
    for p=0,num_tiles do
        game[p] = difficulty.easy()

        local x, y = tilePos(pos2(p)) -- Sprite coordinates
        sprite = playdate.graphics.sprite.new( images[game[p]] )
        sprite:moveTo(x, y)
        sprite:add()
        tile_sprites[p] = sprite
    end
    return tile_sprites
end

local function setupImages()
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

local function setupBlinks()
    local sprite = nil
    local blink_sprites = {[1]={}, [2]={}}  -- a table containing two tables
    for i, image in pairs({[1]=images.dot, [2]=images.box}) do
        for j=1,8 do
            sprite = playdate.graphics.sprite.new( images.dot )
            sprite:setVisible(false)
            sprite:add()
            blink_sprites[i][j] = sprite
        end
    end
    return blink_sprites
end

local function myGameSetUp()
    math.randomseed(playdate.getSecondsSinceEpoch())

    images = setupImages()
    tileSprites = setupTiles()
    blinkSprites = setupBlinks()

    -- playdate.graphics.drawLine


    frameSprite = playdate.graphics.sprite.new( images.frame )
    frameSprite:moveTo( tilePos(1, 1) )
    frameSprite:add()

    selectedSprite = playdate.graphics.sprite.new( images.frame_selected )
    selectedSprite:setVisible(false)
    selectedSprite:add()

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

function handleInputMoveFrame()
    local fx, fy = pos2(frame_pos) -- frame x,y board coordinates
    -- TODO: Convert this to buttonIsPressed with delay + repeat
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
    frameSprite:moveTo( tilePos(pos2(frame_pos)) )
end

function moveFrame(horizontal, vertical)
    local fx, fy = pos2(frame_pos)
    local mx = frame_pos + horizontal * b2i(horizontal > 0) * b2i(fx == 1) * boardX
end

local function blinkCallback()
    if not(selectedPos == nil) then
        for _, spr in pairs(blinkingSprites) do
            spr:setVisible(not(spr:isVisible()))
        end
    end
end

---- Selection / Possible Moves
local function _hide_moves()
    frameSprite:setImage(images.frame)
    for _, sprite in pairs(blinkingSprites) do
        sprite:setVisible(false)
    end
    -- TODO: Research Lua GC frequency on playdate device.
    blinkingSprites = {}
    validMoves = {}
end
local function _show_moves(position)
    validMoves = _valid_moves(position)
    local num_moves = 0
    for dest_pos, new_dest in pairs(validMoves) do
        num_moves = num_moves + 1
        local dot_or_box = 1 + b2i(_isSecondary(new_dest) or _isTertiary(new_dest))
        local sprite = blinkSprites[dot_or_box][num_moves]
        sprite:moveTo(tilePos(pos2(dest_pos)))
        sprite:setVisible(true)
        table.insert(blinkingSprites, sprite)
    end
end
local function _select(position)
    selectedPos = position
    selectedSprite:moveTo(tilePos(pos2(position)))
    selectedSprite:setVisible(true)
    blinkTimer = playdate.timer.keyRepeatTimerWithDelay(300, 500, blinkCallback)
end
local function _deselect(position)
    selectedPos = nil
    selectedSprite:setVisible(false)
    blinkTimer:remove()
end

function handleInput()
    -- directionalHandler()
    handleInputMoveFrame()

    -- if selectedPos == nil then
        -- if bip("right") then
        --     print(frame_pos, frame_pos + 2, game[frame_pos], game[frame_pos +2])
        -- elseif bip("left") then
        --     print(frame_pos, frame_pos - 2, game[frame_pos], game[frame_pos -2])
        -- elseif bip("down") then
        --     print(frame_pos, frame_pos + boardX, game[frame_pos], game[frame_pos + boardX])
        -- elseif bip("up") then
        --     print(frame_pos, frame_pos - boardX, game[frame_pos], game[frame_pos - boardX])
        -- end

    -- ButtonA / Frame selection
    if playdate.buttonJustReleased( "a" ) then
        if selectedPos == nil then -- new selection
            _select(frame_pos)
            _show_moves(frame_pos)
        else -- clearing selection
            _deselect()
            _hide_moves()
        end
    end
end

function playdate.update()
    playdate.graphics.sprite.update()
    playdate.timer.updateTimers()
    handleInput()
end

myGameSetUp()
