function b2i(value) -- converts boolean to int
    return value == true and 1 or 0
end

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

function dump(o)
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

