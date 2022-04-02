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
local images = {}               -- table of playdate.graphics.images
local tileSprites = {}          -- table of playdate.graphics.sprite
local blinkSpritePool = {}      -- table of playdate.graphics.sprite
local blinkSprites = {}         -- table of playdate.graphics.sprite
local frameSprite = nil         -- playdate.graphics.sprite
local selectedSprite = nil      -- playdate.graphics.sprite
local movingSprite = nil        -- playdate.graphics.sprite
local animatedTileSprite = nil  -- playdate.graphics.sprite
local undoBuffer = {}
local redoBuffer = {}           -- table {src}

local game = {} -- table of ints ()
local framePos = 1
local selectedPos = nil
local validMoves = {}

local blinkTimer = nil

-- Random constants
local boards = {
    [0] = {x=6, y=3, size=32, xshift=104, yshift=72},
    [1] = {x=10, y=7, size=32, xshift=34, yshift=4},
    [2] = {x=14, y=10, size=24, xshift=32, yshift=0},
}
local board = boards[1]
local difficulty = {
    -- TODO: Make less difficult. E.g. medium 2/3 primary; 1/3 secondary not 1/2 & 1/2.
    easy = function(); return 2 ^ math.random(0,2); end,    -- all primary
    medium = function(); return math.random(1,6); end,      -- primary & secondary
    hard = function(); return math.random(1,7); end,        -- primary, secondary & tertiary
}
local boardX = board.x
local boardY = board.y
local boardXShift = board.xshift
local boardYShift = board.yshift
local tileSize = board.size

local screenX <const> = 400
local screenY <const> = 240

local Tiles = {
    "EMPTY",
    "CIRCLE",           --  ( )  circle
    "CROSS",            --   +   cross
    "CROSS_CIRCLE",     --  (+)  cross in circle
    "SQUARE",           -- [   ] square
    "CIRCLE_SQUARE",    -- [( )] circle in square
    "CROSS_SQUARE",     -- [ + ] cross in square
    "TERTIARY",         -- [(+)]
}

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
    -- Note these are not positions, they are tile ints
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
    return boardXShift + -tileSize // 2 + (tileSize + 1) * x, boardYShift -tileSize // 2 + (tileSize + 1) * y
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
    local mid_pos = boardX * (((y1 + y2) // 2) - 1) + ((x1 + x2) // 2)
    return mid_pos
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

local function setupTiles(images, tile_generator)  --> table[playdate.graphics.sprite]
    local sprite = nil --> playdate.graphics.sprite
    local tile_sprites = {} --> table[playdate.graphics.sprite]
    local num_tiles <const> = boardX * boardY
    for p=1,num_tiles do
        game[p] = tile_generator()

        local x, y = tilePos(pos2(p)) -- Sprite coordinates
        sprite = playdate.graphics.sprite.new( images[game[p]] )
        sprite:moveTo(x, y)
        sprite:add()
        tile_sprites[p] = sprite
    end
    return tile_sprites
end

local function setupImages(tile_size)
    local _images = {}
    local filename = ""
    folder_fmt = "images/%sx%s/%s"
    for key, val in pairs({
        [0]="0.png", [1]="1.png", [2]="2.png", [3]="3.png",
        [4]="4.png", [5]="5.png", [6]="6.png", [7]="7.png",
        frame="frame.png",
        frame_selected="selected.png",
        dot="dot.png",
        box="box.png",
    }) do
        filename = string.format(folder_fmt, tile_size, tile_size, val)
        _images[key] = playdate.graphics.image.new( filename )
        assert( _images[key], "image load failure: " .. filename)
    end
    return _images
end

local function setupBlinks(primary_image, secondary_image)
    local sprite = nil
    local blink_sprites = {[1]={}, [2]={}}  -- a table containing two tables
    for i, image in pairs({[1]=primary_image, [2]=secondary_image}) do
        for j=1,8 do
            sprite = playdate.graphics.sprite.new( image )
            sprite:setVisible(false)
            sprite:add()
            blink_sprites[i][j] = sprite
        end
    end
    return blink_sprites
end

local function myGameSetUp()
    math.randomseed(playdate.getSecondsSinceEpoch())

    -- Init our globals
    images = setupImages(tileSize)
    tileSprites = setupTiles(images, difficulty.easy)
    blinkSpritePool = setupBlinks(images.dot, images.box)
    blinkSprites = {}
    framePos = 1

    frameSprite = playdate.graphics.sprite.new( images.frame )
    frameSprite:moveTo( tilePos(pos2(framePos)) )
    frameSprite:add()

    selectedSprite = playdate.graphics.sprite.new( images.frame_selected )
    selectedSprite:setVisible(false)
    selectedSprite:add()

    -- Background image.
    local backgroundImage = playdate.graphics.image.new( "images/400x240-10x7.png" )
    assert( backgroundImage, "image load failure")
    playdate.graphics.sprite.setBackgroundDrawingCallback(
        function( x, y, width, height )
            playdate.graphics.setClipRect( x, y, width, height )
            backgroundImage:draw( 0, 0 )
            playdate.graphics.clearClipRect()
        end
    )
end

local function b2i(value) -- converts boolean to int
    return value == true and 1 or 0
end

function handleInputMoveFrame(frame_pos, frame_sprite)
    local fx, fy = pos2(frame_pos) -- frame x,y board coordinates
    local new_pos = nil
    -- TODO: Convert this to buttonIsPressed with delay + repeat
    -- d-pad control. b2i terms apply screen wrap if required.
    if bjp("right") then
        new_pos = frame_pos + 1 + (b2i(fx == boardX) * -boardX)
    elseif bjp("left") then
        new_pos = frame_pos - 1 + (b2i(fx == 1) * boardX)
    elseif bjp("up") then
        new_pos = frame_pos - boardX + (b2i(fy == 1) * boardX * boardY)
    elseif bjp("down") then
        new_pos = frame_pos + boardX - (b2i(fy == boardY) * boardX * boardY)
    else
        return frame_pos
    end
    frame_sprite:moveTo( tilePos(pos2(new_pos)) )
    return new_pos
end

-- function moveFrame(horizontal, vertical)
--     local fx, fy = pos2(frame_pos)
--     local mx = frame_pos + horizontal * b2i(horizontal > 0) * b2i(fx == 1) * boardX
-- end
--
-- function directionalHandler()
--     local horizontal = b2i(bip("right")) - b2i(bip("left"))
--     local vertical = b2i(bip("down")) - b2i(bip("up"))
-- end

local function blinkCallback()
    for _, spr in pairs(blinkSprites) do
        spr:setVisible(not(spr:isVisible()))
    end
end

local function _show_moves(position, valid_moves, blinking_sprite_pool)
    local blinks = {}
    local num_moves = 0
    for dest_pos, new_dest in pairs(valid_moves) do
        num_moves = num_moves + 1
        local dot_or_box = 1 + b2i(_isSecondary(new_dest) or _isTertiary(new_dest))
        local sprite = blinking_sprite_pool[dot_or_box][num_moves]
        sprite:moveTo(tilePos(pos2(dest_pos)))
        sprite:setVisible(true)
        table.insert(blinks, sprite)
    end
    return blinks
end

local function undo()
    if #undoBuffer >= 1 then
        local moo = table.remove(undoBuffer)
        table.insert(redoBuffer, {
            src_pos=moo.src_pos, mid_pos=moo.mid_pos, dest_pos=moo.dest_pos,
            src=game[moo.src_pos], mid=game[moo.mid_pos], dest=game[moo.dest_pos]
        })
        game[moo.src_pos] = moo.src
        game[moo.mid_pos] = moo.mid
        game[moo.dest_pos] = moo.dest
        tileSprites[moo.src_pos]:setImage(images[moo.src])
        tileSprites[moo.mid_pos]:setImage(images[moo.mid])
        tileSprites[moo.dest_pos]:setImage(images[moo.dest])
        framePos = moo.src_pos
        frameSprite:moveTo( tilePos(pos2(framePos)) )
    end
end
local function redo()
    if #redoBuffer >= 1 then
        local moo = table.remove(redoBuffer)
        table.insert(undoBuffer, {
            src_pos=moo.src_pos, mid_pos=moo.mid_pos, dest_pos=moo.dest_pos,
            src=game[moo.src_pos], mid=game[moo.mid_pos], dest=game[moo.dest_pos]
        })
        game[moo.src_pos] = moo.src
        game[moo.mid_pos] = moo.mid
        game[moo.dest_pos] = moo.dest
        tileSprites[moo.src_pos]:setImage(images[moo.src])
        tileSprites[moo.mid_pos]:setImage(images[moo.mid])
        tileSprites[moo.dest_pos]:setImage(images[moo.dest])
        framePos = moo.dest_pos
        frameSprite:moveTo( tilePos(pos2(framePos)) )
    end
end

local function tileMove(src_pos, mid_pos, dest_pos)
    print("move", src_pos, mid_pos, dest_pos, game[src_pos], game[mid_pos], game[dest_pos])
    valid, new_mid, new_dest = move(game[src_pos], game[mid_pos], game[dest_pos])
    assert ( valid, "invalid tile move" )

    table.insert(undoBuffer, {
        src_pos=src_pos, mid_pos=mid_pos, dest_pos=dest_pos,
        src=game[src_pos], mid=game[mid_pos], dest=game[dest_pos]
    })
    redoBuffer = {}

    game[src_pos] = 0
    game[mid_pos] = new_mid
    game[dest_pos] = new_dest
    tileSprites[src_pos]:setImage(images[0])
    tileSprites[mid_pos]:setImage(images[new_mid])
    tileSprites[dest_pos]:setImage(images[new_dest])
end


local function tileAnimationFactory(src_pos, mid_pos, dest_pos)
    -- animatedTileSprite
    local function tileAnimaitonCallback()
    end
end

local function handleInput()
    -- directionalHandler()

    if bip("b") then
        if bjp("left") then
            undo()
        elseif bjp("right") then
            redo()
        end
    else
        framePos = handleInputMoveFrame(framePos, frameSprite)
    end

    -- ButtonA / Frame selection
    if playdate.buttonJustReleased( "a" ) then
        if selectedPos == nil and game[framePos] > 0 then
            -- Select
            selectedPos = framePos
            selectedSprite:moveTo(tilePos(pos2(selectedPos)))
            selectedSprite:setVisible(true)
            validMoves = _valid_moves(selectedPos)
            blinkSprites = _show_moves(framePos, validMoves, blinkSpritePool)
            blinkTimer = playdate.timer.keyRepeatTimerWithDelay(300, 500, blinkCallback)
        else
            selectedSprite:setVisible(false)
            print(framePos, dump(validMoves), validMoves[framePos] == nil)
            if (selectedPos == framePos) then
                ;
            elseif validMoves[framePos] == nil then
                ;
            else
                local src_pos = selectedPos
                local mid_pos = _mid_pos(selectedPos, framePos)
                local dest_pos = framePos
                valid, new_mid, new_dest = move(game[src_pos], game[mid_pos], game[dest_pos])
                print(src_pos, mid_pos, dest_pos)
                print(valid, new_mid, new_dest)
                if valid then
                    tileMove(src_pos, mid_pos, dest_pos)
                end
            end
            selectedPos = nil
            for _, sprite in pairs(blinkSprites) do
                sprite:setVisible(false)
            end
            blinkTimer:remove()
            blinkingSprites = {}
            validMoves = {}
            -- RESEARCH: Performance/GC; is re-using tables faster?
            -- for i = #blinkingSprites, 1, -1 do
            --     blinkingSprites[i]:setVisible(false)
            --     table.remove(blinkingSprites, i)
            -- end
        end
    end
end

function playdate.update()
    playdate.graphics.sprite.update()
    playdate.timer.updateTimers()
    handleInput()
end

myGameSetUp()
