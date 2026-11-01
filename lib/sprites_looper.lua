-- sprites_looper is the Looper's face, one wide text image with nine knobs, two meters and an LED.
-- Its dots are sorted once at load, so the pane only has to set levels on each draw.
local sprites_looper = {}
local sprite = include("lib/sprite")

local LOOPER = sprite.decode([[
5555555555555555555555555555555555555555555555555555555555555555555555555555555555
5................................................................................5
5................................................................................5
5................................................................................5
5................................................................................5
5....ccc....ccc....ccc....ccc....ccc....ccc....ccc.................ccc....ccc....5
5...ccccc..ccccc..ccccc..ccccc..ccccc..ccccc..ccccc..........f.f..ccccc..ccccc...5
5...ccccc..ccccc..ccccc..ccccc..ccccc..ccccc..ccccc...........f...ccccc..ccccc...5
5...ccccc..ccccc..ccccc..ccccc..ccccc..ccccc..ccccc..........f.f..ccccc..ccccc...5
5....ccc....ccc....ccc....ccc....ccc....ccc....ccc.................ccc....ccc....5
5................................................................................5
5................................................................................5
5................................................................................5
5................................................................................5
5................................................................................5
5.33333333333333333333333333333333333333..33333333333333333333333333333333333333.5
5.3....................................3..3....................................3.5
5.3.4444444444444444444444444444444444.3..3.4444444444444444444444444444444444.3.5
5.3.3333333333333333333333333333333333.3..3.3333333333333333333333333333333333.3.5
5.3.333333333333333....333333333333333.3..3.333333333333333....333333333333333.3.5
5.3.333333333333333.dd.333333333333333.3..3.333333333333333.ee.333333333333333.3.5
5.3.333333333333333....333333333333333.3..3.333333333333333....333333333333333.3.5
5.3.3333333333333333333333333333333333.3..3.3333333333333333333333333333333333.3.5
5.3.3333333333333333333333333333333333.3..3.3333333333333333333333333333333333.3.5
5.3....................................3..3....................................3.5
5.3.5555555555555555555555555555555555.3..3.5555555555555555555555555555555555.3.5
5.3.5................................5.3..3.5................................5.3.5
5.3.5.dddddddddddddddddddddddddddddd.5.3..3.5.eeeeeeeeeeeeeeeeeeeeeeeeeeeeee.5.3.5
5.3.5.dddddddddddddddddddddddddddddd.5.3..3.5.eeeeeeeeeeeeeeeeeeeeeeeeeeeeee.5.3.5
5.3.5.dddddddddddddddddddddddddddddd.5.3..3.5.eeeeeeeeeeeeeeeeeeeeeeeeeeeeee.5.3.5
5.3.5.dddddddddddddddddddddddddddddd.5.3..3.5.eeeeeeeeeeeeeeeeeeeeeeeeeeeeee.5.3.5
5.3.5.dddddddddddddddddddddddddddddd.5.3..3.5.eeeeeeeeeeeeeeeeeeeeeeeeeeeeee.5.3.5
5.3.5.dddddddddddddddddddddddddddddd.5.3..3.5.eeeeeeeeeeeeeeeeeeeeeeeeeeeeee.5.3.5
5.3.5.dddddddddddddddddddddddddddddd.5.3..3.5.eeeeeeeeeeeeeeeeeeeeeeeeeeeeee.5.3.5
5.3.5.dddddddddddddddddddddddddddddd.5.3..3.5.eeeeeeeeeeeeeeeeeeeeeeeeeeeeee.5.3.5
5.3.5.dddddddddddddddddddddddddddddd.5.3..3.5.eeeeeeeeeeeeeeeeeeeeeeeeeeeeee.5.3.5
5.3.5.dddddddddddddddddddddddddddddd.5.3..3.5.eeeeeeeeeeeeeeeeeeeeeeeeeeeeee.5.3.5
5.3.5.dddddddddddddddddddddddddddddd.5.3..3.5.eeeeeeeeeeeeeeeeeeeeeeeeeeeeee.5.3.5
5.3.5.dddddddddddddddddddddddddddddd.5.3..3.5.eeeeeeeeeeeeeeeeeeeeeeeeeeeeee.5.3.5
5.3.5.dddddddddddddddddddddddddddddd.5.3..3.5.eeeeeeeeeeeeeeeeeeeeeeeeeeeeee.5.3.5
5.3.5.dddddddddddddddddddddddddddddd.5.3..3.5.eeeeeeeeeeeeeeeeeeeeeeeeeeeeee.5.3.5
5.3.5.dddddddddddddddddddddddddddddd.5.3..3.5.eeeeeeeeeeeeeeeeeeeeeeeeeeeeee.5.3.5
5.3.5.dddddddddddddddddddddddddddddd.5.3..3.5.eeeeeeeeeeeeeeeeeeeeeeeeeeeeee.5.3.5
5.3.5.dddddddddddddddddddddddddddddd.5.3..3.5.eeeeeeeeeeeeeeeeeeeeeeeeeeeeee.5.3.5
5.3.5.dddddddddddddddddddddddddddddd.5.3..3.5.eeeeeeeeeeeeeeeeeeeeeeeeeeeeee.5.3.5
5.3.5.dddddddddddddddddddddddddddddd.5.3..3.5.eeeeeeeeeeeeeeeeeeeeeeeeeeeeee.5.3.5
5.3.5.dddddddddddddddddddddddddddddd.5.3..3.5.eeeeeeeeeeeeeeeeeeeeeeeeeeeeee.5.3.5
5.3.5.dddddddddddddddddddddddddddddd.5.3..3.5.eeeeeeeeeeeeeeeeeeeeeeeeeeeeee.5.3.5
5.3.5.d............................d.5.3..3.5.e............................e.5.3.5
5.3.5.dddddddddddddddddddddddddddddd.5.3..3.5.eeeeeeeeeeeeeeeeeeeeeeeeeeeeee.5.3.5
5.3.5.dddddddddddddddddddddddddddddd.5.3..3.5.eeeeeeeeeeeeeeeeeeeeeeeeeeeeee.5.3.5
5.3.5.d............................d.5.3..3.5.e............................e.5.3.5
5.3.5.dddddddddddddddddddddddddddddd.5.3..3.5.eeeeeeeeeeeeeeeeeeeeeeeeeeeeee.5.3.5
5.3.5.dddddddddddddddddddddddddddddd.5.3..3.5.eeeeeeeeeeeeeeeeeeeeeeeeeeeeee.5.3.5
5.3.5................................5.3..3.5................................5.3.5
5.3.5555555555555555555555555555555555.3..3.5555555555555555555555555555555555.3.5
5.3....................................3..3....................................3.5
5.33333333333333333333333333333333333333..33333333333333333333333333333333333333.5
5................................................................................5
5555555555555555555555555555555555555555555555555555555555555555555555555555555555
]])

sprites_looper.LOOPER_PTS = (function()
  local cx = {6, 13, 20, 27, 34, 41, 48, 68, 75}
  local bbox = {}
  for i = 1, 9 do
    bbox[i] = {x1=cx[i]-2, y1=5, x2=cx[i]+2, y2=9}
  end
  local pts = {
    knob = { {}, {}, {}, {}, {}, {}, {}, {}, {} },
    ldisp = {}, rdisp = {}, led = {}, bg_lv = {},
  }
  local function in_bbox(x, y, b) return x >= b.x1 and x <= b.x2 and y >= b.y1 and y <= b.y2 end
  for slot, sp in pairs(LOOPER) do
    for _, q in ipairs(sp) do
      if slot == 12 then
        for i = 1, 9 do
          if in_bbox(q[1], q[2], bbox[i]) then
            pts.knob[i][#pts.knob[i]+1] = q; break
          end
        end
      elseif slot == 13 then pts.ldisp[#pts.ldisp+1] = q
      elseif slot == 14 then pts.rdisp[#pts.rdisp+1] = q
      elseif slot == 15 then pts.led[#pts.led+1]     = q
      else
        local lv = slot <= 10 and slot or 5
        pts.bg_lv[lv] = pts.bg_lv[lv] or {}
        table.insert(pts.bg_lv[lv], q)
      end
    end
  end
  return pts
end)()

return sprites_looper
