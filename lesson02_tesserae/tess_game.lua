import "CoreLibs/graphics"
import "CoreLibs/sprites"
import "CoreLibs/timer"

import "tess_utils"

-- Global constants
local screenX <const> = 400
local screenY <const> = 240

-- Function factories
local function pos2_gen(boardX)
    local function pos2(position)
        -- Takes int position and returns x,y board coordinates.
        local posX = (position - 1) % boardX + 1
        local posY = (position - 1) // boardX + 1
        return posX, posY
    end
    return pos2
end
local function tilepos_gen(xshift, yshift, size, pos2)
    local function tile_pos(position)
        local x, y = pos2(position)
        -- Takes x,y board coordinates; returns xy screen coordinates (sprite location)
        return xshift + -size // 2 + (size + 1) * x, yshift -size // 2 + (size + 1) * y
    end
    return tile_pos
end

Game = {}
Game.__index = Game
function Game:create(x, y, size, difficulty)
    local game = {}             -- our new object
    setmetatable(game, Game)    -- make Game handle lookup
    -- initialize our object
    game.x = x
    game.y = y
    game.size = size
    game.difficulty = difficulty
    game.xshift = 0
    game.yshift = 0
    game.board = {}
    game.undo_buffer = {}
    game.redo_buffer = {}
    game.start_time = nil

    -- Game specific functions
    game.game_pos2 = pos2_gen(game.x)
    game.tile_pos2 = tilepos_gen(game.xshift, game.yshift, game.size, game.game_pos2)

    local diffs = {
        -- TODO: Make less difficult. E.g. medium 2/3 primary; 1/3 secondary not 1/2 & 1/2.
        easy = function(); return 2 ^ math.random(0,2); end,    -- all primary
        medium = function(); return math.random(1,6); end,      -- primary & secondary
        hard = function(); return math.random(1,7); end,        -- primary, secondary & tertiary
    }
    game.tile_gen = diffs[game.difficulty]
    -- Generate tiles for board
    for p = 1, game.x * game.y do
        game.board[p] = game.tile_gen()
    end

    game.images = {
        [0]=nil, [1]=nil, [2]=nil, [3]=nil, [4]=nil, [5]=nil, [6]=nil, [7]=nil,
        frame=nil, selected=nil, dot=nil, box=nil
    }
    game.sprites = {tiles = {}, blinks = {}, frame = nil, selected = nil}
    game.frame_pos = 1
    game.selected_pos = nil
    game.blinking = {}
    game.blink_timer = nil
    game.valid_moves = {}

    return game
end

function Game:create_images()
    for key, file in pairs({
        [0]="0.png", [1]="1.png", [2]="2.png", [3]="3.png",
        [4]="4.png", [5]="5.png", [6]="6.png", [7]="7.png",
        frame="frame.png",
        selected="selected.png",
        dot="dot.png",
        box="box.png",
    }) do
        local filepath = string.format("images/%sx%s/%s", self.size, self.size, file)
        self.images[key] = playdate.graphics.image.new( filepath )
        assert( self.images[key], "image load failure: " .. filepath)
    end
end

function Game:create_sprites()
    -- Tile sprites
    for p = 1, #self.board do
        local x, y = self.tile_pos2(p) -- Sprite coordinates
        local sprite = playdate.graphics.sprite.new( self.images[self.board[p]] )
        sprite:moveTo(x, y)
        sprite:add()
        self.sprites.tiles[p] = sprite
    end
    -- Valid move sprites (blinking dots)
    for j=1,8 do
        self.sprites.blinks[j] = playdate.graphics.sprite.new( self.images.dot )
        self.sprites.blinks[j]:setVisible(false)
        self.sprites.blinks[j]:add()
    end
    -- Frame and selected sprites
    self.sprites.frame = playdate.graphics.sprite.new( self.images.frame )
    self.sprites.frame:moveTo( self.tile_pos2(self.frame_pos) )
    self.sprites.frame:add()

    self.sprites.selected = playdate.graphics.sprite.new( self.images.selected )
    self.sprites.selected:setVisible(false)
    self.sprites.selected:add()
end

function Game:show_moves()
    local num_moves = 0
    for dest_pos, new_dest in pairs(self.valid_moves) do
        num_moves = num_moves + 1
        local sprite = self.sprites.blinks[num_moves]
        if _isSecondary(new_dest) or _isTertiary(new_dest) then
            sprite:setImage( self.images.box )
        else
            sprite:setImage( self.images.dot )
        end
        sprite:setVisible(true)
        sprite:moveTo( self.tile_pos2(dest_pos) )
        self.blinking[#self.blinking+1] = sprite
    end
end

-- Finds the midpoint between two tiles (does no validation)
function Game:_mid_pos(src_pos, dest_pos)
    local x1, y1 = self.game_pos2(src_pos)
    local x2, y2 = self.game_pos2(dest_pos)
    local mid_pos = self.x * (((y1 + y2) // 2) - 1) + ((x1 + x2) // 2)
    return mid_pos
end

-- TODO: Make these local / class methods
function _isPrimary(tile); return tile == 1 or tile == 2 or tile == 4; end
function _isSecondary(tile); return tile == 3 or tile == 5 or tile == 6; end
function _isTertiary(tile); return tile == 7; end
function _hasCircle(tile); return tile & 1 > 0; end
function _hasCross(tile); return tile & 2 > 0; end
function _hasSquare(tile); return tile & 4 > 0; end
function _contains(tile1, tile2); return (tile1 & tile2 == tile2); end

function Game:move_check(src_pos, mid_pos, dest_pos)
    -- returns (valid:bool, new_mid:int, new_dest:int)
    local src, mid, dest = self.board[src_pos], self.board[mid_pos], self.board[dest_pos]
    print(src_pos, mid_pos, dest_pos, src, mid, dest)

    -- First check if dest tile is suitable
    if dest == 0 or src == dest or (src | dest == src + dest) then
        -- Then check whether mid tile is suitable.
        if _isPrimary(src) and _isPrimary(mid) then
            return true, 0, src | dest
        elseif _contains(mid, src) then
            return true, mid - src, src | dest
        end
    end
    return false, nil, nil
end

function Game:_valid_moves(position)
    local boardX, boardY = self.x, self.y
    local moves = {}
    local x, y = self.game_pos2(position)
    local ok_right = x + 2 <= boardX
    local ok_left = x - 2 >= 1
    local ok_up = y - 2 >= 1
    local ok_down = y + 2 <= boardY
    if ok_right then
        moves[#moves+1] = position + 2
    end
    if ok_left then
        moves[#moves+1] = position - 2
    end
    if ok_down then
        moves[#moves+1] = position + 2 * boardX
    end
    if ok_up then
        moves[#moves+1] = position - 2 * boardX
    end
    if ok_up and ok_left then
        moves[#moves+1] = position - 2 * boardX - 2
    end
    if ok_up and ok_right then
        moves[#moves+1] = position - 2 * boardX + 2
    end
    if ok_down and ok_left then
        moves[#moves+1] = position + 2 * boardX - 2
    end
    if ok_down and ok_right then
        moves[#moves+1] = position + 2 * boardX + 2
    end
    local valids = {}
    for _, dest_pos in pairs(moves) do
        print("mid?", position, dest_pos)
        local mid_pos = self:_mid_pos(position, dest_pos)
        local valid, new_mid, new_dest = self:move_check(position, mid_pos, dest_pos)
        if valid then
            valids[dest_pos] = new_dest
        end
    end
    return valids
end

function Game:move(src_pos, mid_pos, dest_pos)
    local valid, new_mid, new_dest = self:move_check(src_pos, mid_pos, dest_pos)
    assert ( valid, "invalid tile move" )

    self.undo_buffer[#self.undo_buffer+1] = {
        src_pos=src_pos,
        mid_pos=mid_pos,
        dest_pos=dest_pos,
        src=self.board[src_pos],
        mid=self.board[mid_pos],
        dest=self.board[dest_pos]
    }
    self.redo_buffer = {}
    self.board[src_pos] = 0
    self.board[mid_pos] = new_mid
    self.board[dest_pos] = new_dest
    self.sprites.tiles[src_pos]:setImage(self.images[0])
    self.sprites.tiles[mid_pos]:setImage(self.images[new_mid])
    self.sprites.tiles[dest_pos]:setImage(self.images[new_dest])
    self:update()
end

function Game:select()
    local function blink_callback()
        print(self.blinking)
        for _, spr in pairs(self.blinking) do
            spr:setVisible(not(spr:isVisible()))
        end
    end

    if self.selected_pos == nil and self.board[self.frame_pos] > 0 then -- Select
        self.selected_pos = self.frame_pos
        self.sprites.selected:moveTo( self.tile_pos2(self.selected_pos) )
        self.sprites.selected:setVisible(true)
        self.valid_moves = self:_valid_moves(self.selected_pos)
        self:show_moves()
        self.blink_timer = playdate.timer.keyRepeatTimerWithDelay(300, 500, blink_callback)
    else -- move or deselect
        self.sprites.selected:setVisible(false)
        if self.valid_moves[self.frame_pos] then
            local src_pos, dest_pos = self.selected_pos, self.frame_pos
            local mid_pos = self:_mid_pos(src_pos, dest_pos)
            local valid, new_mid, new_dest = self:move_check(src_pos, mid_pos, dest_pos)
            if valid then
                self:move(src_pos, mid_pos, dest_pos)
            end
        end
        self.selected_pos = nil
        for _, sprite in pairs(self.sprites.blinks) do
            sprite:setVisible(false)
        end
        self.blinking = {}
        self.blink_timer:remove()
        self:update()
    end
end

function Game:draw_scoreboard()
    playdate.graphics.drawText("Moves", screenX - 50, 10)
    playdate.graphics.drawTextAligned(
        string.format("*%s*", #self.undo_buffer), screenX - 25, 30, kTextAlignment.center
    )
    -- Timer
    local elapsed = playdate.getSecondsSinceEpoch() - self.start_time
    playdate.graphics.drawText("Timer", screenX - 50, 60)
    playdate.graphics.drawTextAligned(
        string.format("*%02d:%02d", elapsed // 60, elapsed % 60), screenX - 50, 80, kTextAlignment.left
    )
    -- Tiles remaining
    playdate.graphics.drawTextAligned("Left", screenX - 50, 120,  kTextAlignment.left )
    playdate.graphics.drawTextAligned(
        string.format("*%s*", self.remaining), screenX - 25, 140, kTextAlignment.center
    )
end

function Game:draw_grid()
    local rows, cols, size = self.x, self.y, self.size
    -- TODO: Implement xshift/yshift
    for row = 0, rows do
        local x = row * (size + 1)
        playdate.graphics.drawLine(x, 0, x, cols * (size + 1))
    end
    for col = 0, cols do
        local y = col * (size + 1)
        playdate.graphics.drawLine(0, y, rows * (size + 1), y)
    end
end

-- Bits per tile lookup table.
local cntr = {[1]=1, [2]=1, [3]=2, [4]=1, [5]=2, [6]=2, [7]=3}
function Game:calc_remaining()
    local tile_count = 0
    for _, tile in pairs(self.board) do
        tile_count = tile_count + (cntr[tile] or 0)
    end
    return tile_count
end

function Game:update()
    self.remaining = self:calc_remaining()
    if self.selected_pos then
        self.valid_moves = self:_valid_moves(self.selected_pos)
    end
end

function Game:start()
    self:create_images()
    self:create_sprites()
    self.start_time = playdate.getSecondsSinceEpoch()
    self:update()
end

function Game:undo()
    if #self.undo_buffer >= 1 then
        local moo = table.remove(self.undo_buffer)
        self.redo_buffer[#self.redo_buffer+1] = {
            src_pos=moo.src_pos,
            mid_pos=moo.mid_pos,
            dest_pos=moo.dest_pos,
            src=self.board[moo.src_pos],
            mid=self.board[moo.mid_pos],
            dest=self.board[moo.dest_pos]
        }
        self.board[moo.src_pos] = moo.src
        self.board[moo.mid_pos] = moo.mid
        self.board[moo.dest_pos] = moo.dest
        self.sprites.tiles[moo.src_pos]:setImage(self.images[moo.src])
        self.sprites.tiles[moo.mid_pos]:setImage(self.images[moo.mid])
        self.sprites.tiles[moo.dest_pos]:setImage(self.images[moo.dest])
        self.sprites.frame:moveTo( self.tile_pos2(framePos) )
        self.frame_pos = moo.src_pos
        self.selected_pos = nil
        self:update()
    end
end

function Game:redo()
    if #self.redo_buffer >= 1 then
        local moo = table.remove(self.redo_buffer)
        self.undo_buffer[#self.undo_buffer+1] = {
            src_pos=moo.src_pos,
            mid_pos=moo.mid_pos,
            dest_pos=moo.dest_pos,
            src=self.board[moo.src_pos],
            mid=self.board[moo.mid_pos],
            dest=self.board[moo.dest_pos]
        }
        self.board[moo.src_pos] = moo.src
        self.board[moo.mid_pos] = moo.mid
        self.board[moo.dest_pos] = moo.dest
        self.sprites.tiles[moo.src_pos]:setImage(self.images[moo.src])
        self.sprites.tiles[moo.mid_pos]:setImage(self.images[moo.mid])
        self.sprites.tiles[moo.dest_pos]:setImage(self.images[moo.dest])
        self.sprites.frame:moveTo( tile_pos2(self.framePos) )
        self.frame_pos = moo.dest_pos
        self.selected_pos = nil
        self:update()
    end
end

function Game:frame_move(direction)
    local fx, fy = self.game_pos2(self.frame_pos) -- frame x,y board coordinates
    -- TODO: Convert this to buttonIsPressed with delay + repeat
    -- d-pad control. b2i terms apply screen wrap if required.
    if direction == "right" then
        self.frame_pos = self.frame_pos + 1 + (b2i(fx == self.x) * -self.x)
    elseif direction == "left" then
        self.frame_pos = self.frame_pos - 1 + (b2i(fx == 1) * self.x)
    elseif direction == "up" then
        self.frame_pos = self.frame_pos - self.x + (b2i(fy == 1) * self.x * self.y)
    elseif direction == "down" then
        self.frame_pos = self.frame_pos + self.x - (b2i(fy == self.y) * self.x * self.y)
    else
        return
    end
    self.sprites.frame:moveTo( self.tile_pos2(self.frame_pos) )
end