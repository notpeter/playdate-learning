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
-- Random constants
local screenX <const> = 400
local screenY <const> = 240

local function myGameSetUp()
    math.randomseed(playdate.getSecondsSinceEpoch())

    local dvdImage = playdate.graphics.image.new( "images/dvd-64-white.png" )
    assert( dvdImage , "image load failure" )
    local dvd = playdate.graphics.sprite.new( dvdImage )
    dvd:moveTo( screenX / 2, screenY / 2 ) -- center to center of Playdate screens
    dvd:add()
    -- Let's attach some state
    dvd.dx, dvd.dy = 1, 1
    dvd.box = {
        left = dvd.width /  2,
        right = screenX - dvd.width /  2,
        bottom = screenY - dvd.height /  2,
        top = dvd.height / 2,
    }
    logo = dvd

    -- Background image.
    local backgroundImage = playdate.graphics.image.new( "images/400x240-black.png" )
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


function playdate.update()
    local d = logo
    local speed = 2

    -- A Button: random position and direction
    if playdate.buttonJustReleased( "a" ) then
        d:moveTo(
            math.random( d.box.left, d.box.right ),
            math.random( d.box.top, d.box.bottom )
        )
        -- Set x/y velocity to -1 or 1
        d.dx = math.random(0, 1) * 2 - 1
        d.dy = math.random(0, 1) * 2 - 1
    end

    -- This is a terrible, but simple crank interface.
    if not playdate.isCrankDocked() then
        local change, _ = playdate.getCrankChange()
        if change > 0 then
            speed = math.abs(speed)
        elseif change < 0 then
            speed = -1 * math.abs(speed)
        else -- crank undocked and not moving
            speed = 0
        end
    -- B Button: reverse direction
    elseif playdate.buttonIsPressed("b") then
        speed = -1 * math.abs(speed)
    end

    -- d-pad control
    if bip("up") or bip("right") or bip("left") or bip("down") then
        d:moveBy(
            speed * (b2i(bip("right")) - b2i(bip("left"))),
            speed * (b2i(bip("down")) - b2i(bip("up")))
        )
    else
        d:moveBy( speed * d.dx, speed * d.dy )
        if d.x > d.box.right or d.x < d.box.left then
            d.dx = d.dx * -1
            d:moveBy( speed * d.dx, 0)
        end
        if d.y > d.box.bottom or d.y < d.box.top then
            d.dy = d.dy * -1
            d:moveBy( 0, speed * d.dy)
        end
    end

    playdate.graphics.sprite.update()
    playdate.timer.updateTimers()
end

myGameSetUp()
