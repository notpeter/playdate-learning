-- Standard libs from PlayDate SDK
import "CoreLibs/object"
import "CoreLibs/graphics"
import "CoreLibs/sprites"
import "CoreLibs/timer"

--This is more performant and shorter.
--local gfx <const> = playdate.graphics

-- Global state
logo = nil -- playdate.graphics.sprite
-- Random constants
local screenX <const> = 400
local screenY <const> = 240

function myGameSetUp()
    math.randomseed(playdate.getSecondsSinceEpoch())

    local dvdImage = playdate.graphics.image.new( "images/dvd-64-white.png" )
    assert( dvdImage , "image load failure" )
    dvd = playdate.graphics.sprite.new( dvdImage )
    dvd:moveTo( screenX / 2, screenY / 2 ) -- center to center of Playdate screens
    dvd:add()
    -- Let's attach some state
    dvd.dx, dvd.dy = 2, 2
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
    local bip = playdate.buttonIsPressed

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

    -- d-pad control
    if bip("up") or bip("right") or bip("left") or bip("down") then
        d:moveBy(
            2 * (b2i(bip("right")) - b2i(bip("left"))),
            2 * (b2i(bip("down")) - b2i(bip("up")))
        )
    else
        d:moveBy( d.dx, d.dy )
        if d.x > d.box.right or d.x < d.box.left then
            d.dx = d.dx * -1
            d:moveBy( 2 * d.dx, 0)
        end
        if d.y > d.box.bottom or d.y < d.box.top then
            d.dy = d.dy * -1
            d:moveBy( 0, 2 * d.dy)
        end
    end

    playdate.graphics.sprite.update()
    playdate.timer.updateTimers()
end

myGameSetUp()
