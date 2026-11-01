local sprites = {}
local sprite  = include("lib/sprite")

local MED  = 5
local FULL = 15

-- ── Pedal sprites (37 x 60; 1..10 fixed level, 12 footswitch and LED, 13–15 knob 1–3, 16 frame) ──
-- Push, Distort, Warp and Repeat are text images, with glyphs up to 10 fixed and higher ones lit at
-- draw time. A pedal has only three knobs, so selecting a fourth control lights the frame.
local PEDAL_DISTORT = sprite.decode([[
ggggggggggggggggggggggggggggggggggggg
g...................................g
g...................................g
g...................................g
g...................................g
g...................................g
g...................................g
g...................................g
g...................................g
g.....ddd........eee........fff.....g
g....ddddd......eeeee......fffff....g
g...ddddddd....eeeeeee....fffffff...g
g...ddddddd....eeeeeee....fffffff...g
g...ddddddd....eeeeeee....fffffff...g
g....ddddd......eeeee......fffff....g
g.....ddd........eee........fff.....g
g...................................g
g...................................g
g...................................g
g...................................g
g...................................g
g...................................g
g...55555555555555555555555555555...g
g...5...5333333333333333333333335...g
g...5.c.5333333333333333333333335...g
g...5...5333333333333333333333335...g
g...55555333333333333333333333335...g
g...53333333333333333333333333335...g
g...53333333333333333333333333335...g
g...53333333333333333333333333335...g
g...53333333333333333333333333335...g
g...53333333333333333333333333335...g
g...53333333333333333333333333335...g
g...53333333333333333333333333335...g
g...53333333333333333333333333335...g
g...53333333333333333333333333335...g
g...53333333333333333333333333335...g
g...53333333333333333333333333335...g
g...55555555555555555555555555555...g
g...................................g
g...................................g
g...................................g
g...................................g
g...................................g
g...................................g
g................ccc................g
g...............ccccc...............g
g...............ccccc...............g
g...............ccccc...............g
g................ccc................g
g...................................g
g...................................g
g...................................g
g...................................g
g...................................g
g...................................g
g...................................g
g...................................g
g...................................g
ggggggggggggggggggggggggggggggggggggg
]])

local PEDAL_PUSH = sprite.decode([[
ggggggggggggggggggggggggggggggggggggg
g...................................g
g...................................g
g...................................g
g...................................g
g...................................g
g.....ddd.........c.........fff.....g
g....ddddd.................fffff....g
g...ddddddd...............fffffff...g
g...ddddddd...............fffffff...g
g...ddddddd...............fffffff...g
g....ddddd.................fffff....g
g.....ddd........eee........fff.....g
g...............eeeee...............g
g..............eeeeeee..............g
g..............eeeeeee..............g
g..............eeeeeee..............g
g...............eeeee...............g
g................eee................g
g...................................g
g...................................g
g...................................g
g...................................g
g..5555555555555555555555555555555..g
g..5.............................5..g
g..5.444444444444444444444444444.5..g
g..5.333333333333333333333333333.5..g
g..5.333333333333333333333333333.5..g
g..5.333333333333333333333333333.5..g
g..5.333333333333333333333333333.5..g
g..5.333333333333333333333333333.5..g
g..5.............................5..g
g..5.ccccccccccccccccccccccccccc.5..g
g..5.ccccccccccccccccccccccccccc.5..g
g..5.ccccccccccccccccccccccccccc.5..g
g..5.c.........................c.5..g
g..5.ccccccccccccccccccccccccccc.5..g
g..5.ccccccccccccccccccccccccccc.5..g
g..5.ccccccccccccccccccccccccccc.5..g
g..5.c.........................c.5..g
g..5.ccccccccccccccccccccccccccc.5..g
g..5.ccccccccccccccccccccccccccc.5..g
g..5.ccccccccccccccccccccccccccc.5..g
g..5.c.........................c.5..g
g..5.ccccccccccccccccccccccccccc.5..g
g..5.ccccccccccccccccccccccccccc.5..g
g..5.ccccccccccccccccccccccccccc.5..g
g..5.c.........................c.5..g
g..5.ccccccccccccccccccccccccccc.5..g
g..5.ccccccccccccccccccccccccccc.5..g
g..5.ccccccccccccccccccccccccccc.5..g
g..5.c.........................c.5..g
g..5.ccccccccccccccccccccccccccc.5..g
g..5.ccccccccccccccccccccccccccc.5..g
g..5.ccccccccccccccccccccccccccc.5..g
g..5.............................5..g
g..5555555555555555555555555555555..g
g...................................g
g...................................g
ggggggggggggggggggggggggggggggggggggg
]])

local PEDAL_REPEAT = sprite.decode([[
ggggggggggggggggggggggggggggggggggggg
g...................................g
g...................................g
g...................................g
g...................................g
g....ddd............................g
g...ddddd.......................c...g
g..ddddddd..........................g
g..ddddddd..........................g
g..ddddddd..........................g
g...ddddd...........................g
g....ddd............................g
g...................................g
g...................................g
g...................................g
g...................................g
g...................................g
g....eee............................g
g...eeeee...........................g
g..eeeeeee..........................g
g..eeeeeee..........................g
g..eeeeeee..........................g
g...eeeee...........................g
g....eee............................g
g...................................g
g...................................g
g...................................g
g...................................g
g...................................g
g....fff............................g
g...fffff...........................g
g..fffffff..........................g
g..fffffff..........................g
g..fffffff..........................g
g...fffff...........................g
g....fff............................g
g...................................g
g...................................g
g...................................g
g...................................g
g...................................g
g..5555555555555555555555555555555..g
g..5.............555.............5..g
g..5.ccccccccccc.555.ccccccccccc.5..g
g..5.ccccccccccc.....ccccccccccc.5..g
g..5.c........ccccccccc........c.5..g
g..5.ccccccccccccccccccccccccccc.5..g
g..5.c.........................c.5..g
g..5.ccccccccccccccccccccccccccc.5..g
g..5.c.........................c.5..g
g..5.ccccccccccccccccccccccccccc.5..g
g..5.c.........................c.5..g
g..5.ccccccccccccccccccccccccccc.5..g
g..5.c.........................c.5..g
g..5.ccccccccccccccccccccccccccc.5..g
g..5.............................5..g
g..5555555555555555555555555555555..g
g...................................g
g...................................g
ggggggggggggggggggggggggggggggggggggg
]])

local PEDAL_WARP = sprite.decode([[
ggggggggggggggggggggggggggggggggggggg
g...................................g
g.33333333333....ddd....33333333333.g
g.3.............ddddd.............3.g
g.3............ddddddd............3.g
g.3............ddddddd............3.g
g.3............ddddddd............3.g
g.3.............ddddd.............3.g
g.3..............ddd..............3.g
g.3...............................3.g
g.3...............................3.g
g...................................g
g...................................g
g...eee.......................fff...g
g..eeeee.....................fffff..g
g.eeeeeee...................fffffff.g
g.eeeeeee...................fffffff.g
g.eeeeeee...................fffffff.g
g..eeeee.....................fffff..g
g...eee.......................fff...g
g...................................g
g...................................g
g.3...............................3.g
g.3...............................3.g
g.3...............................3.g
g.3...............................3.g
g.3...............................3.g
g.3...............................3.g
g.3...............................3.g
g.3...............................3.g
g.3...............................3.g
g.444444444444444444444444444444444.g
g.3333333333333.......3333333333333.g
g.3333333333333.ccccc.3333333333333.g
g.3333333333333.......3333333333333.g
g.333333333333333333333333333333333.g
g.555...........................555.g
g.5...ccccccccccccccccccccccccc...5.g
g.5.ccccccccccccccccccccccccccccc.5.g
g.5.ccccccccccccccccccccccccccccc.5.g
g.5.ccccccccccccccccccccccccccccc.5.g
g.5.ccccccccccccccccccccccccccccc.5.g
g.5.ccccccccccccccccccccccccccccc.5.g
g.5.ccccccccccccccccccccccccccccc.5.g
g.5.ccccccccccccccccccccccccccccc.5.g
g.5.ccccccccccccccccccccccccccccc.5.g
g.5.ccccccccccccccccccccccccccccc.5.g
g.5.ccccccccccccccccccccccccccccc.5.g
g.5.ccccccccccccccccccccccccccccc.5.g
g.5.ccccccccccccccccccccccccccccc.5.g
g.5.ccccccccccccccccccccccccccccc.5.g
g.5.ccccccccccccccccccccccccccccc.5.g
g.5.c...........................c.5.g
g.5.ccccccccccccccccccccccccccccc.5.g
g.5.c...........................c.5.g
g.5.ccccccccccccccccccccccccccccc.5.g
g.5...............................5.g
g.555555555555555555555555555555555.g
g...................................g
ggggggggggggggggggggggggggggggggggggg
]])

local PEDAL_BY_NAME = {
  push       = PEDAL_PUSH,
  distort    = PEDAL_DISTORT,
  warp       = PEDAL_WARP,
  ["repeat"] = PEDAL_REPEAT,
}

function sprites.draw_pedal(ox, oy, name, bypassed, focused_knob)
  local sp = PEDAL_BY_NAME[name:lower()]
  if sp then
    local oy_sprite = oy - 1
    local fs_lv     = bypassed and MED or FULL
    local focus_slot  = (focused_knob == 1 and 13)
                   or (focused_knob == 2 and 14)
                   or (focused_knob == 3 and 15)
                   or (focused_knob == 4 and 16)
                   or nil
    for slot, pts in pairs(sp) do
      local sl
      if     slot == 12       then sl = fs_lv
      elseif slot == focus_slot then sl = FULL
      elseif slot <= 10         then sl = slot
      else                         sl = MED end
      screen.level(sl)
      sprite.rects(pts, ox, oy_sprite)
      screen.fill()
    end
  end
end

sprites.LOOPER_PTS = include("lib/sprites_looper").LOOPER_PTS

return sprites
