function draw_grid(rows, cols, size)
    -- rows, cols, size = 10, 7, 32
    local x, y = 0, 0
    for row = 0, rows do
        local x = row * (size + 1)
        playdate.graphics.drawLine(x, 0, x, cols * (size + 1))
    end
    for col = 0, cols do
        local y = col * (size + 1)
        playdate.graphics.drawLine(0, y, rows * (size + 1), y)
    end
end
