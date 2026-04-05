--[[----------------------------------------------

	 _       _   _           
	| |_ ___| |_| |_ ___ ___ 
	| . | -_|  _|  _| -_|  _|
	|___|___|_| |_| |___|_| 
   _____ _      _____ _____ /  ______ _____  
  / ____| |    |_   _/ ___ / ||  ____|  __ \ 
 | (___ | |      | || |   /   | |__  | |__) |
  \___ \| |      | || |  /    |  __| |  _  / 
  ____) | |____ _| || | / ___ | |____| | \ \ 
 |_____/|______|_____\ / ____||______|_|  \_\
                      /
  	
	BETTER SLICER for Aseprite

	-------------Credits-------------------------
	Original Script by NgnHaiDang
	Updated & Optimized by Pix3lPirat3
	---------------------------------------------
	A handy utility for automatically or manually 
	slicing spritesheets with grids, cell counts, 
	and contiguous transparency bounds.

--]]

local M_AUTO, M_SIZE, M_COUNT = "Automatic", "Grid by Cell Size", "Grid by Cell Count"

local spr = app.activeSprite
if not spr or app.activeImage:isEmpty() then 
    return app.alert("Error: Active sprite is invalid or blank.") 
end

local function warn(msg) app.alert(msg) end

local function notify(msg)
    local d = Dialog("Slicer")
    d:label{ text = msg }
    d:button{ text = "OK", focus = true, onclick = function() d:close() end }
    d:show{ wait = false }
end


local function clearSlices()
    local q = {}
    for _, s in ipairs(spr.slices) do q[#q+1] = s end
    for _, s in ipairs(q) do spr:deleteSlice(s) end
end

local function createGrid(d, sel, cw, ch, cols, rows)
    local id = 0
    local cel, img, colorMode, tColor
    if d.ignoreEmpty then
        cel = app.activeLayer:cel(app.activeFrame)
        if cel then
            img, colorMode = cel.image, cel.image.colorMode
            tColor = spr.transparentColor
        end
    end

    local function isCellEmpty(x, y, w, h)
        if not cel then return true end
        for cy = y, y + h - 1 do
            for cx = x, x + w - 1 do
                local ix, iy = cx - cel.bounds.x, cy - cel.bounds.y
                if ix >= 0 and ix < cel.bounds.width and iy >= 0 and iy < cel.bounds.height then
                    local p = img:getPixel(ix, iy)
                    local trans = false
                    if colorMode == ColorMode.RGB then trans = (app.pixelColor.rgbaA(p) == 0)
                    elseif colorMode == ColorMode.GRAY then trans = (app.pixelColor.grayaA(p) == 0)
                    else trans = (p == tColor) end
                    if not trans then return false end
                end
            end
        end
        return true
    end

    app.transaction(function()
        if d.clear then clearSlices() end
        local ox, oy = sel.origin.x, sel.origin.y
        for r = 0, rows - 1 do
            for c = 0, cols - 1 do
                local x = c * cw + c * d.padding_X + d.offset_X + ox
                local y = r * ch + r * d.padding_Y + d.offset_Y + oy
                
                if not (d.ignoreEmpty and isCellEmpty(x, y, cw, ch)) then
                    local s = spr:newSlice(Rectangle(x, y, cw, ch))
                    s.color, s.name, id = d.color, d.name .. "_" .. id, id + 1
                end
            end
        end
    end)
    notify(string.format("Created %d slices", id))
end

local function doGridSlice(d, isFixedCount)
    local sel = spr.selection
    if sel.isEmpty then return warn("Select a region to slice.") end

    local bw, bh = sel.bounds.width, sel.bounds.height
    local cw, ch, cols, rows = 0, 0, 0, 0

    if isFixedCount then
        cols, rows = d.no_Col, d.no_Row
        if cols <= 0 or rows <= 0 then return end
        cw, ch = bw // cols, bh // rows
    else
        cw, ch = d.cell_W, d.cell_H
        if cw <= 0 or ch <= 0 then return end
        cols, rows = bw // cw, bh // ch
    end

    if cw <= 0 or ch <= 0 or cols <= 0 or rows <= 0 then
        return warn("Parameters resulted in invalid slice dimensions.")
    end

    createGrid(d, sel, cw, ch, cols, rows)
end

local function doAutoSlice(d)
    local cel = app.activeLayer:cel(app.activeFrame)
    if not cel then return warn("Active layer is empty on this frame.") end
    
    local img, colorMode = cel.image:clone(), cel.image.colorMode
    local w, h, ox, oy = cel.bounds.width, cel.bounds.height, cel.bounds.x, cel.bounds.y
    local tColor = spr.transparentColor

    local function isTrans(x, y)
        if x < 0 or x >= w or y < 0 or y >= h then return true end
        local p = img:getPixel(x, y)
        if colorMode == ColorMode.RGB then return app.pixelColor.rgbaA(p) == 0
        elseif colorMode == ColorMode.GRAY then return app.pixelColor.grayaA(p) == 0
        else return p == tColor end
    end

    local count = 0
    app.transaction(function()
        if d.clear then clearSlices() end
        local vis = {}

        for y = 0, h - 1 do
            for x = 0, w - 1 do
                local i = y * w + x
                if not vis[i] and not isTrans(x, y) then
                    local x1, x2, y1, y2 = x, x, y, y
                    local q, head = {{x, y}}, 1
                    vis[i] = true
                    
                    while head <= #q do
                        local cx, cy = q[head][1], q[head][2]
                        head = head + 1
                        
                        if cx < x1 then x1 = cx elseif cx > x2 then x2 = cx end
                        if cy < y1 then y1 = cy elseif cy > y2 then y2 = cy end
                        
                        for dy = -1, 1 do
                            for dx = -1, 1 do
                                if dx ~= 0 or dy ~= 0 then
                                    local nx, ny = cx + dx, cy + dy
                                    local ni = ny * w + nx
                                    if nx >= 0 and nx < w and ny >= 0 and ny < h and not vis[ni] and not isTrans(nx, ny) then
                                        vis[ni] = true
                                        q[#q+1] = {nx, ny}
                                    end
                                end
                            end
                        end
                    end
                    
                    local s = spr:newSlice(Rectangle(x1 + ox, y1 + oy, x2 - x1 + 1, y2 - y1 + 1))
                    s.color, s.name, count = d.color, d.name .. "_" .. count, count+1
                end
                vis[i] = true
            end
        end
    end)
    app.refresh()
    notify(string.format("Auto-slicer generated %d slices", count or 0))
end

local dlg = Dialog("Better Slicer")

local function updateUI()
    local mode = dlg.data.mode
    local isSz, isCnt = (mode == M_SIZE), (mode == M_COUNT)
    local isGrid = isSz or isCnt
    
    dlg:modify{id="size_header", text=isSz and "Slice Size" or "Slice Count", visible=isGrid}
       :modify{id="cell_W", visible=isSz} :modify{id="cell_H", visible=isSz}
       :modify{id="no_Col", visible=isCnt} :modify{id="no_Row", visible=isCnt}
       :modify{id="padding_header", visible=isGrid} :modify{id="padding_X", visible=isGrid} :modify{id="padding_Y", visible=isGrid}
       :modify{id="offset_header", visible=isGrid} :modify{id="offset_X", visible=isGrid} :modify{id="offset_Y", visible=isGrid}
end

dlg:combobox{ id="mode", label="Mode:", option=M_SIZE, options={M_AUTO, M_SIZE, M_COUNT}, onchange=updateUI }
   :entry{id="name", label="Base Name:", text="Slice"}
   :color{id="color", label="Color:", color=Color{r=0, g=0, b=250, a=150}}
   :check{id="clear", text="Clear existing slices", selected=false}
   :check{id="ignoreEmpty", text="Ignore empty cells", selected=false}
   
   :separator{id="size_header", text="Slice Size"}
   :number{id="cell_W", label="W:", text="16"} :number{id="cell_H", label="H:", text="16"}
   :number{id="no_Col", label="Col:", text="1"} :number{id="no_Row", label="Row:", text="1"}
   
   :separator{id="padding_header", text="Padding"}
   :number{id="padding_X", label="X:", text="0"} :number{id="padding_Y", label="Y:", text="0"}
   
   :separator{id="offset_header", text="Offset"}
   :number{id="offset_X", label="X:", text="0"} :number{id="offset_Y", label="Y:", text="0"}
   
   :separator{}
   :button{id="slice", text="Slice", focus=true, onclick=function()
        local d = dlg.data
        if d.mode == M_SIZE then doGridSlice(d, false); dlg:close()
        elseif d.mode == M_COUNT then doGridSlice(d, true); dlg:close()
        elseif d.mode == M_AUTO then
            local adlg = Dialog("Alert")
            adlg:label{text="Auto-Slice determines boundaries by opaque regions."}
            if d.clear then adlg:label{text="Warning: Pre-existing slices will be cleared."} end
            adlg:button{text="Run", focus=true, onclick=function() doAutoSlice(d); adlg:close(); dlg:close() end}
                :button{text="Cancel", onclick=function() adlg:close() end}
                :show()
            return
        end
        app.refresh()
   end}
   :button{text="Close", onclick=function() dlg:close() end}

updateUI()
dlg:show{wait=false}
