-- Standard libs from PlayDate SDK
import "CoreLibs/object"
import "CoreLibs/graphics"
import "CoreLibs/sprites"
import "CoreLibs/timer"

-- Project imports
-- import "mylib"

local gfx <const> = playdate.graphics

-- Here's our player sprite declaration. File scope local.
local playerSprite = nil
local otherdinos = {}
local dino_count = 0

function myGameSetUp()
    local dino = gfx.image.new("images/dino.png")
    assert( dino ) -- make sure the image was where we thought

    playerSprite = gfx.sprite.new( dino )
    playerSprite:moveTo( 200, 120 ) -- center of sprite; (200,120) is the center of the Playdate screen (400x240)
    playerSprite:add() -- This is critical!
  
    for i = 0,10,1
    do
        otherdinos[i] = gfx.sprite.new(dino)
    end

    local backgroundImage = gfx.image.new( "images/hitwitch.png" )
    assert( backgroundImage )
    -- playdate.graphics.sprite.setBackgroundDrawingCallback
    gfx.sprite.setBackgroundDrawingCallback(
        function( x, y, width, height )
            gfx.setClipRect( x, y, width, height ) -- let's only draw the part of the screen that's dirty
            backgroundImage:draw( 0, 0 )
            gfx.clearClipRect() -- clear so we don't interfere with drawing that comes after this
        end
    )
end

function playdate.update()
    -- Poll the d-pad and move our player accordingly.
    -- (There are multiple ways to read the d-pad; this is the simplest.)
    -- Note that it is possible for more than one of these directions
    -- to be pressed at once, if the user is pressing diagonally.

    if playdate.buttonIsPressed( playdate.kButtonUp ) then
        playerSprite:moveBy( 0, -2 )
    end
    if playdate.buttonIsPressed( playdate.kButtonRight ) then
        playerSprite:moveBy( 2, 0 )
    end
    if playdate.buttonIsPressed( playdate.kButtonDown ) then
        playerSprite:moveBy( 0, 2 )
    end
    if playdate.buttonIsPressed( playdate.kButtonLeft ) then
        playerSprite:moveBy( -2, 0 )
    end
--[[
    -- buttonJustPressed / buttonJustReleased
    if playdate.buttonJustReleased( playdate.kButtonA ) then
        dino_count = dino_count + 1
        new_dino = otherdinos[dino_count]
        new_dino:moveTo(dino_count * 100,100)
        new_dino:add()
    end
    if playdate.buttonJustReleased( playdate.kButtonB ) then
        dino_count = dino_count - 1
        new_dino:remove()
    end
]]--
    -- Call the functions below in playdate.update() to draw sprites and keep
    -- timers updated. (We aren't using timers in this example, but in most
    -- average-complexity games, you will.)

    -- playdate.graphics.sprite.update
    gfx.sprite.update()
    playdate.timer.updateTimers()

end


myGameSetUp()
