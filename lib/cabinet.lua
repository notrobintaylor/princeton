local cabinet = {}

local DIM  = 0
local MED  = 5
local FULL = 15

local NUM_AMP_KNOBS = 8

-- The box every pane stands in, x 44..125 and y 2..61, filled by one device or shared by two
-- halves. CAB.y sits one row low because devices are drawn one row above their y.
cabinet.CAB = { x = 44, y = 3, w = 82, h = 59 }
local CAB = cabinet.CAB
local TOP = CAB.y - 1
cabinet.TOP    = TOP
cabinet.H      = CAB.y + CAB.h - TOP
cabinet.HALF_W = 37

local INNER = 3

-- The classic amp is a cabinet whose baffle holds the grille cloth and a row of knobs. 82 px
-- doesn't divide by 4, so the bars stand every 5 px from the centre outward.
local CLASSIC = {}
CLASSIC.x = CAB.x + 5
CLASSIC.w = 72
CLASSIC.panel = { x=CAB.x + 3, y=TOP + 3, w=CAB.w - 6, h=12 }
CLASSIC.grill = { x=CAB.x + 4, y=TOP + 15, w=74, h=41 }
CLASSIC.stays = { 0 }
for dx = 4, 69, 5 do CLASSIC.stays[#CLASSIC.stays + 1] = dx end
CLASSIC.stays[#CLASSIC.stays + 1] = 73
CLASSIC.knob_y = TOP + 9
CLASSIC.jack1 = CLASSIC.x
CLASSIC.jack2 = CLASSIC.x + 2
CLASSIC.lamp  = CLASSIC.x + CLASSIC.w - 1
CLASSIC.knob_x = {}
for i = 1, NUM_AMP_KNOBS do CLASSIC.knob_x[i] = CLASSIC.x + 8 + 6 * (i - 1) end

-- The neutral cabinet for NAM: no baffle, staggered dashes instead of a grid. The dash rows
-- alternate between two levels, keeping the surface calm yet giving it depth.
local NEUTRAL = {}
NEUTRAL.panel = { x=CAB.x + 1, y=TOP + 1, w=CAB.w - 2, h=14 }
NEUTRAL.grill = { x=CAB.x + 3, y=TOP + 18, w=CAB.w - 7, h=38 }
NEUTRAL.sep_y = TOP + 15
NEUTRAL.knob_y = TOP + 8
NEUTRAL.jack1 = CAB.x + 3
NEUTRAL.jack2 = CAB.x + 5
NEUTRAL.lamp  = CAB.x + CAB.w - 4
NEUTRAL.knob_x = {}
for i = 1, NUM_AMP_KNOBS + 1 do NEUTRAL.knob_x[i] = CAB.x + 17 + 6 * (i - 1) end

local KNOB_R = 2

-- The param strip on the left ends 2 px before the box; its text stays on the same centre line.
cabinet.LEFT_W  = CAB.x - 1
cabinet.LEFT_CX = math.floor(CAB.x / 2) - 1
cabinet.ICON_Y  = 55

local function px_rect(x, y, w, h, lv)
  screen.level(lv); screen.rect(x, y, w, h); screen.fill()
end

-- Filled, not stroked: on norns a stroked rectangle lands one pixel left of and above its
-- target and would overhang the base.
local function frame(x, y, w, h, lv)
  px_rect(x, y, w, 1, lv); px_rect(x, y + h - 1, w, 1, lv)
  px_rect(x, y + 1, 1, h - 2, lv); px_rect(x + w - 1, y + 1, 1, h - 2, lv)
end
cabinet.frame = frame

function cabinet.draw_cabinet(neutral)
  local h = CAB.y + CAB.h - TOP
  if neutral then
    px_rect(CAB.x, TOP, CAB.w, 1, MED)
    px_rect(CAB.x, TOP + h - 1, CAB.w, 1, MED)
    px_rect(CAB.x, TOP + 1, 1, h - 2, MED)
    px_rect(CAB.x + CAB.w - 1, TOP + 1, 1, h - 2, MED)
    return
  end
  frame(CAB.x, TOP, CAB.w, h, MED)
  frame(CAB.x + 2, TOP + 2, CAB.w - 4, h - 4, INNER)
end

function cabinet.draw_panel(sel, stereo, bypassed, slots)
  local neutral = slots and true or false
  local L = neutral and NEUTRAL or CLASSIC
  local P = L.panel
  px_rect(P.x, P.y, P.w, P.h, DIM)
  px_rect(L.jack1, L.knob_y, 1, 1, FULL)
  px_rect(L.jack2, L.knob_y, 1, 1, stereo and FULL or MED)
  px_rect(L.lamp, L.knob_y, 1, 1, bypassed and MED or FULL)
  for i = 1, slots and #slots or NUM_AMP_KNOBS do
    screen.level((slots and slots[i] or i) == sel and FULL or MED)
    screen.circle(L.knob_x[i], L.knob_y, KNOB_R); screen.fill()
  end
  if neutral then px_rect(CAB.x + 1, L.sep_y, CAB.w - 2, 1, INNER) end
end

local function draw_speaker_x(cx, cy, lv)
  screen.level(lv); screen.line_width(1)
  screen.move(cx-2, cy-2); screen.line(cx+2, cy+2); screen.stroke()
  screen.move(cx+2, cy-2); screen.line(cx-2, cy+2); screen.stroke()
end

function cabinet.draw_grillcloth(cab_mode, mic_cat_active, mic_position, neutral)
  local G = neutral and NEUTRAL.grill or CLASSIC.grill
  local gx, gy, gw, gh = G.x, G.y, G.w, G.h

  if not mic_cat_active and not neutral then
    for _, dx in ipairs(CLASSIC.stays) do px_rect(gx + dx, gy, 1, gh, 2) end
    for y = gy, gy + gh - 1, 2 do px_rect(gx, y, gw, 1, 3) end
    return
  end

  if not mic_cat_active then
    local row = 0
    for y = gy, gy + gh, 2 do
      local x = gx + (row % 2) * 3
      while x < gx + gw do
        px_rect(x, y, math.min(4, gx + gw + 1 - x), 1, row % 2 == 0 and 3 or 2)
        x = x + 6
      end
      row = row + 1
    end
    return
  end

  local cx, cy
  if neutral then
    px_rect(gx, gy, gw + 1, gh + 1, DIM)
    cx, cy = gx + math.floor(gw / 2), gy + math.floor(gh / 2)
  else
    px_rect(gx, gy, gw, gh, DIM)
    px_rect(gx, gy, gw, 1, 3)
    cx, cy = math.floor(gx + gw / 2 + 0.5), math.floor(gy + gh / 2 + 0.5)
  end

  if cab_mode == 2 then
    screen.line_width(1)
    screen.level(MED); screen.circle(cx, cy, 16); screen.stroke()
    screen.level(neutral and 2 or DIM); screen.circle(cx, cy, 11); screen.stroke()
    screen.level(MED); screen.circle(cx, cy, 5);  screen.stroke()
    local x_offsets = { 0, 8, 14 }
    -- only the mic currently in place is marked; otherwise the rings stay closed
    draw_speaker_x(cx + x_offsets[mic_position + 1], cy, FULL)
  else
    screen.level(MED); screen.line_width(1)
    screen.move(cx - 5, cy - 5); screen.line(cx + 5, cy + 5); screen.stroke()
    screen.move(cx + 5, cy - 5); screen.line(cx - 5, cy + 5); screen.stroke()
  end
end

return cabinet
