-- princeton cabinet
--
-- Cabinet panel + grillcloth geometry and rendering for the amp view.

local cabinet = {}

local DIM  = 0
local MED  = 5
local FULL = 15

local NUM_AMP_KNOBS = 8

local CAB_W, CAB_H = 82, 56
cabinet.CAB = {
  x = 45,
  y = math.floor((64 - CAB_H) / 2),
  w = CAB_W,
  h = CAB_H,
}
local CAB = cabinet.CAB

local BORDER_LVL = MED
local BORDER_GAP = 3

cabinet.INT = {
  x = CAB.x + BORDER_GAP + 2,
  y = CAB.y + BORDER_GAP + 2,
  w = CAB.w - (BORDER_GAP + 2) * 2,
  h = CAB.h - (BORDER_GAP + 2) * 2,
}
local INT = cabinet.INT

local PANEL_H = 10
cabinet.PANEL = { x=INT.x, y=INT.y,          w=INT.w, h=PANEL_H        }
cabinet.GRILL = { x=INT.x, y=INT.y+PANEL_H, w=INT.w, h=INT.h-PANEL_H }
local PANEL = cabinet.PANEL
local GRILL = cabinet.GRILL
local SEP_Y = INT.y + PANEL_H

local KNOB_R       = 2
local KNOB_Y       = PANEL.y + math.floor((PANEL.h - 1) / 2)
local PANEL_BUCHSE1 = PANEL.x
local PANEL_BUCHSE2 = PANEL.x + 2
local PANEL_LAMP    = PANEL.x + PANEL.w - 2
local KNOB_SPACING  = 6
local KNOB_START    = PANEL.x + 5
local KNOB_X = {}
for i = 1, NUM_AMP_KNOBS do
  KNOB_X[i] = KNOB_START + KNOB_SPACING * (i - 1) + math.floor(KNOB_SPACING / 2)
end

cabinet.LEFT_W  = CAB.x - 1
cabinet.LEFT_CX = math.floor(cabinet.LEFT_W / 2) - 1
cabinet.ICON_Y  = 55

local function rect_outline(x, y, w, h, lv)
  screen.level(lv)
  screen.line_width(1)
  screen.rect(x, y, w, h)
  screen.stroke()
end

function cabinet.draw_cabinet()
  rect_outline(CAB.x, CAB.y, CAB.w, CAB.h, BORDER_LVL)
  local g = BORDER_GAP
  rect_outline(CAB.x+g, CAB.y+g, CAB.w-g*2, CAB.h-g*2, BORDER_LVL)
end

function cabinet.draw_panel(sel, stereo, bypassed)
  screen.level(DIM); screen.rect(PANEL.x, PANEL.y, PANEL.w, PANEL.h); screen.fill()

  screen.level(FULL)
  screen.rect(PANEL_BUCHSE1, KNOB_Y, 1, 1); screen.fill()
  screen.level(stereo and FULL or MED)
  screen.rect(PANEL_BUCHSE2, KNOB_Y, 1, 1); screen.fill()

  screen.level(bypassed and MED or FULL)
  screen.rect(PANEL_LAMP, KNOB_Y, 1, 1); screen.fill()

  for i = 1, NUM_AMP_KNOBS do
    screen.level(i == sel and FULL or MED)
    screen.circle(KNOB_X[i], KNOB_Y, KNOB_R); screen.fill()
  end

  screen.line_width(1); screen.level(MED)
  screen.move(CAB.x + BORDER_GAP + 1, SEP_Y)
  screen.line(PANEL.x + PANEL.w,      SEP_Y)
  screen.stroke()
end

local function draw_speaker_x(cx, cy, lv)
  screen.level(lv); screen.line_width(1)
  screen.move(cx-2, cy-2); screen.line(cx+2, cy+2); screen.stroke()
  screen.move(cx+2, cy-2); screen.line(cx-2, cy+2); screen.stroke()
end

function cabinet.draw_grillcloth(cab_mode, mic_cat_active, mic_position)
  local gx, gy, gw, gh = GRILL.x, GRILL.y, GRILL.w, GRILL.h

  if not mic_cat_active then
    screen.line_width(1)
    local y = gy
    while y <= gy + gh do
      screen.level(MED)
      screen.move(gx, y); screen.line(gx + gw, y); screen.stroke()
      y = y + 2
    end
    local x = gx
    while x <= gx + gw do
      screen.level(MED)
      screen.move(x, gy); screen.line(x, gy + gh); screen.stroke()
      x = x + 4
    end
    return
  end

  screen.level(DIM); screen.rect(gx, gy, gw, gh); screen.fill()
  local cx = math.floor(gx + gw / 2 + 0.5)
  local cy = math.floor(gy + gh / 2 + 0.5)

  if cab_mode == 2 then
    screen.level(MED); screen.line_width(1)
    screen.circle(cx, cy, 16); screen.stroke()
    screen.level(DIM)
    screen.circle(cx, cy, 11); screen.stroke()
    screen.level(MED)
    screen.circle(cx, cy, 5); screen.stroke()
    local x_offsets = { 0, 8, 14 }
    for i = 1, 3 do
      draw_speaker_x(cx + x_offsets[i], cy, (i - 1 == mic_position) and FULL or DIM)
    end
  else
    screen.level(MED); screen.line_width(1)
    screen.move(cx - 5, cy - 5); screen.line(cx + 5, cy + 5); screen.stroke()
    screen.move(cx + 5, cy - 5); screen.line(cx - 5, cy + 5); screen.stroke()
  end
end

return cabinet
