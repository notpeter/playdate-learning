-- Standard libs from PlayDate SDK
import "CoreLibs/object"
import "CoreLibs/graphics"
import "CoreLibs/sprites"
import "CoreLibs/timer"

--This is more performant that 
--local gfx <const> = playdate.graphics
local dvdSprite = nil
local mode = 1
local screenX = 400
local screenY = 240

function myGameSetUp()
    math.randomseed(playdate.getSecondsSinceEpoch())

    local dvdImage = playdate.graphics.image.new( "images/dvd-64-white.png" )
    assert( dvdImage , "image load failure" )

    dvdSprite = playdate.graphics.sprite.new( dvdImage )
    dvdSprite:moveTo( screenX / 2, screenY / 2 ) -- center to center of Playdate screens
    dvdSprite:add()
    dvdSprite.dx = 2
    dvdSprite.dy = 2
    dvdSprite.box = {
        left = dvdSprite.width /  2,
        right = screenX - dvdSprite.width /  2,
        bottom = screenY - dvdSprite.height /  2,
        top = dvdSprite.height / 2,
    }
  
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

function playdate.update()
    d = dvdSprite
    if (
        playdate.buttonIsPressed( playdate.kButtonUp ) 
        or playdate.buttonIsPressed( playdate.kButtonRight ) 
        or playdate.buttonIsPressed( playdate.kButtonDown ) 
        or playdate.buttonIsPressed( playdate.kButtonLeft )
    ) then
        mode = 0
    elseif playdate.buttonJustReleased( playdate.kButtonA ) then
        mode = ~mode -- bitwise not
    end
    
    if playdate.buttonIsPressed( playdate.kButtonUp ) then
        d:moveBy( 0, -2 )
    end
    if playdate.buttonIsPressed( playdate.kButtonRight ) then
        d:moveBy( 2, 0 )
    end
    if playdate.buttonIsPressed( playdate.kButtonDown ) then
        d:moveBy( 0, 2 )
    end
    if playdate.buttonIsPressed( playdate.kButtonLeft ) then
        d:moveBy( -2, 0 )
    end

    if (mode == 1) then
        d:moveBy( d.dx, d.dy )
        if d.x > d.box.right or d.x < d.box.left then
            d.dx = d.dx * -1
            d:moveBy( d.dx, 0)
        end
        if d.y > d.box.bottom or d.y < d.box.top then
            d.dy = d.dy * -1
            d:moveBy( 0, d.dy)
        end
    end
    if playdate.buttonJustReleased( playdate.kButtonB ) then
        d:moveTo(
            math.random( d.box.left, d.box.right ), 
            math.random( d.box.top, d.box.bottom )
        )
        -- Set x/y velocity to -2 or 2
        d.dx = math.random(0, 1) * 4 - 2
        d.dy = math.random(0, 1) * 4 - 2
    end

    playdate.graphics.sprite.update()
    playdate.timer.updateTimers()
end


myGameSetUp()
