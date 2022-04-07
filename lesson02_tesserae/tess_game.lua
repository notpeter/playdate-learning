import "CoreLibs/graphics"
import "CoreLibs/sprites"
import "CoreLibs/timer"

import "tess_utils"

-- Import Aliases (More performant and shorter)
local gfx <const> = playdate.graphics
local bjp <const> = playdate.buttonJustPressed
local bjr <const> = playdate.buttonJustReleased
local bip <const> = playdate.buttonIsPressed

-- Global constants
local screenX <const> = 400
local screenY <const> = 240
local directions = {"left", "right", "up", "down"}

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

local difficulty_funcs = {
    -- TODO: Make less difficult. E.g. medium 2/3 primary; 1/3 secondary not 1/2 & 1/2.
    easy = function(); return 2 ^ math.random(0,2); end,    -- all primary
    medium = function(); return math.random(1,6); end,      -- primary & secondary
    hard = function(); return math.random(1,7); end,        -- primary, secondary & tertiary
    empty = function(); return 0; end,
}

local function create_images(size) -- -> table[playdate.graphics.image]
    local _images = {}
    for key, file in pairs({
        [0]="0.png", [1]="1.png", [2]="2.png", [3]="3.png",
        [4]="4.png", [5]="5.png", [6]="6.png", [7]="7.png",
        frame="frame.png", selected="selected.png", dot="dot.png", box="box.png",
    }) do
        local filepath = string.format("images/%sx%s/%s", size, size, file)
        _images[key] = playdate.graphics.image.new( filepath )
        assert( _images[key], "image load failure: " .. filepath)
    end
    return _images
end


Game = {}
Game.__index = Game
Game.images = create_images(32) -- class variable

function Game:create(x, y, size, difficulty, board, moves_buffer)
    local game = {}             -- our new object
    setmetatable(game, Game)    -- make Game handle lookup
    -- initialize our object
    game.x = x
    game.y = y
    game.size = size or 32
    difficulty = difficulty or "easy"
    game.xshift = 0
    game.yshift = 0
    game.board = {}
    game.undo_buffer = {}
    game.redo_buffer = {}
    game.start_time = nil

    -- Game specific functions
    game.game_pos2 = pos2_gen(game.x)
    game.tile_pos2 = tilepos_gen(game.xshift, game.yshift, game.size, game.game_pos2)

    if board and moves_buffer then
        for i = 1,#board do
            game.board[i] = board[i]
        end
        for i = 1,#moves_buffer do
            game.redo_buffer[#self.redo_buffer+1] = moves_buffer[i]
        end
    else
        local tile_gen = difficulty_funcs[difficulty]
        for t = 1,x*y do
            game.board[t] = tile_gen()
        end
    end
    game.sprites = {tiles = {}, blinks = {}, frame = nil, selected = nil}
    -- Used to create callbacks for repeated holding of d-pad directions.
    game.key_timers = {left=nil, right=nil, up=nil, down=nil}
    game.frame_pos = 1
    game.selected_pos = nil
    game.blinking = {}
    game.blink_timer = nil
    game.valid_moves = {}

    return game
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

function Game:handle_input()
    local function cancel_timers(timers)
        for i = 1,#timers do
            if timers[i] then
                timers[i]:remove()
                timers[i] = nil
            end
        end
    end
    local timers = self.key_timers

    if not playdate.isCrankDocked() then -- Undo/Redo via crank.
        local cranks = playdate.getCrankTicks(6)
        if cranks > 0 then
            cancel_timers(timers)
            game:undo()
        elseif cranks < 0 then
            cancel_timers(timers)
            game:redo()
        end
    elseif bip("b") then -- Undo/Redo via B+left and B+right
        self:_deselect()
        cancel_timers(timers)
        if bip("a") then
            ;
        elseif bjp("left") then
            self:undo()
        elseif bjp("right") then
            self:redo()
        end
    elseif bjr("a") then -- Select tile
        cancel_timers(timers)
        self:select()
    elseif not self.selected_pos then -- movement with no
        for i = 1,4 do
            local dir = directions[i]
            if bjp(dir) and not timers[dir] then -- pressed
                 timers[dir] = playdate.timer.keyRepeatTimer(function() self:frame_move(dir) end)
            end
            if bjr(dir) then -- released
                timers[dir]:remove()
                timers[dir] = nil
            end
        end
    else
        for i = 1,4 do
            if bjr(directions[i]) then
                if timers[i] then
                    timers[i]:remove()
                    timers[i] = nil
                else
                    self:frame_move(directions[i])
                end
            end
        end
    end
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
local function _isPrimary(tile); return tile == 1 or tile == 2 or tile == 4; end
local function _isSecondary(tile); return tile == 3 or tile == 5 or tile == 6; end
local function _isTertiary(tile); return tile == 7; end
local function _hasCircle(tile); return tile & 1 > 0; end
local function _hasCross(tile); return tile & 2 > 0; end
local function _hasSquare(tile); return tile & 4 > 0; end
local function _contains(tile1, tile2); return (tile1 & tile2 == tile2); end

function Game:move_check(src_pos, mid_pos, dest_pos)
    -- returns (valid:bool, new_mid:int, new_dest:int)
    local src, mid, dest = self.board[src_pos], self.board[mid_pos], self.board[dest_pos]

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

function Game:_deselect()
    if self.selected_pos then
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

function Game:select()
    local function blink_callback()
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
        self:_deselect()
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

-- TODO: Get rid of this.
function Game:start()
    self:create_sprites()
    self.remaining = self:calc_remaining()
    self.start_time = playdate.getSecondsSinceEpoch()
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
        self.frame_pos = moo.src_pos
        self.sprites.frame:moveTo( self.tile_pos2(self.frame_pos) )
        self.selected_pos = nil
        self:update()
        return true
    end
    return false
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
        self.frame_pos = moo.dest_pos
        self.sprites.frame:moveTo( self.tile_pos2(self.frame_pos) )
        self.selected_pos = nil
        self:update()
        return true
    end
    return false
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

function Game:__tostring()
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
    local t = {""}
    local stripe = {}
    for i = 1,self.x do
        stripe[#stripe+1] = "+-----"
    end
    stripe = table.concat(stripe, "")

    for i = 1,#self.board do
        if i % self.x == 1 then
            t[#t+1] = "\n"
            t[#t+1] = stripe
            t[#t+1] = "+\n|"
        end
        t[#t+1] = tile2str(self.board[i])
        t[#t+1] = "|"
    end
    t[#t+1] = "\n"
    t[#t+1] = stripe
    t[#t+1] = "+"
    return table.concat(t, "")
end

function Game:serialize()
    local initial, slides = {}, {}
    -- Capture the end game
    for pos, tile in pairs(self.board) do
        if tile then
            initial[pos] = tile
        end
    end
    -- Apply the undo.
    for _, step in pairs(self.undo_buffer) do
        initial[step.src_pos] = step.src
        initial[step.mid_pos] = step.mid
        initial[step.dest_pos] = step.dest
    end
    -- Reverse the undo
    for i=#self.undo_buffer, 1, -1 do
        slides[#slides+1] = self.undo_buffer[i]
    end
    local g = {x=self.x, y=self.y, initial=initial, slides=slides}
    return g
end

-- function Game:refresh_sprites()
--     print("r", self.sprites)
--     print("refresh", json.encode(self.sprites.tiles))
--     for pos = 1,#self.board do
--         print("sprite", pos, self.board[pos])
--
--         -- self.sprites.tiles[pos]:setVisible(false)
--         self.sprites.tiles[pos]:setImage(self.images[self.board[pos]])
--     end
-- end

function Game.Load(x, y, initial, slides, size) -- -> Game
    -- Create empty game; copy board/sprites; update sprites; update metadata.
    print("load", x,y,size,json.encode(initial),json.encode(slides) )
    local game = Game:create(x, y, size)
    for t = 1,#initial do
        game.board[t] = initial[t]
    end
    for r = 1,#slides do
        game.redo_buffer = slides[r]
    end
    game:create_sprites()
    game:start()
    return game
end

function Game:retile(difficulty)
    local tile_gen = difficulty_funcs[difficulty]
    for t = 1,#self.board do
        self.board[t] = tile_gen()
    end
    -- FIXME:
    -- self:refresh_sprites()
end


function Game:Write(filename)
    g = self:serialize()
    print(json.encodePretty(g))
    playdate.datastore.write(g, filename)
end

function Game.Read(filename)
    -- Does no validation. Expects {x:int,y:int,:int,initial,slides}
    local g = playdate.datastore.read(filename)
    print("read:", json.encodePretty(g))
    return Game.Load(g.x, g.y, g.initial, g.slides, 32)
end
