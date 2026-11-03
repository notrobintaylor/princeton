-- strip draws the two faces the amp slot wears when the channel strip stands in for the amp: two
-- rack units, left channel above and right below, and the spring tank that Reverb becomes once the
-- combo is gone. Levels arrive from the engine polls in strip.lvl.
local strip = {}
local cabinet        = include("lib/cabinet")

local MED  = 5
local FULL = 15

-- One set of controls drives both channels, like a linked stereo pair.
strip.IDS = { "strip_gain", "strip_even", "strip_odd", "strip_lowcut", "strip_highcut", "strip_level" }

-- Gain offset in dB that makes the strip at 0 dB as loud as the amp at its default knobs, set by
-- measuring both with the same plucked test signal.
strip.CAL = 11

-- out L, out R, drive L, drive R (linear amplitude)
strip.lvl = { 0, 0, 0, 0 }

-- One unit is 82 x 28 like Build and Mesmerize, laid out like a slim studio preamp: a fine LED bar
-- over the amp's 4 px knobs and the gain digits, the engage LED centred on the right. Knobs and LED
-- keep Build's 7 px to the side walls, and the bar ends flush with the digits.
local UNIT = { W = 82, H = 28 }
UNIT.METER  = { X = 8, Y = 7, N = 25, PITCH = 2, H = 2 }
UNIT.LED    = { X = 70, Y = 13 }
UNIT.DIGITS = { MINUS = 41, X = { 45, 52 }, Y = 13 }
-- Even, Odd, Low Cut, High Cut, Level
UNIT.KNOBS  = { X = { 8, 14, 20, 26, 32 }, Y = 15 }
-- the bar runs from -60 dB to 0 dB, finer towards the top as on a studio meter
UNIT.METER.DB = {}
for k = 1, UNIT.METER.N do
  local t = (k - 1) / (UNIT.METER.N - 1)
  UNIT.METER.DB[k] = -60 * (1 - t) ^ 1.6
end

-- the drive stage starts to round off above this input amplitude
local CLIP_AT = 1.0

local function px(x, y, w, h, lv)
  screen.level(lv); screen.rect(x, y, w, h); screen.fill()
end

local function shell(x, y)
  px(x, y, UNIT.W, 1, MED); px(x, y + UNIT.H - 1, UNIT.W, 1, MED)
  px(x, y + 1, 1, UNIT.H - 2, MED); px(x + UNIT.W - 1, y + 1, 1, UNIT.H - 2, MED)
  for _, ey in ipairs({ 2, UNIT.H - 3 }) do px(x + 2, y + ey, 2, 1, MED); px(x + UNIT.W - 4, y + ey, 2, 1, MED) end
end

-- The engage LED in its bracket, the same one Mesmerize's Freeze wears.
local function led(x, y, on)
  px(x - 2, y - 1, 1, 4, 4); px(x + 4, y - 1, 1, 4, 4)
  px(x, y, 3, 2, on and FULL or 2)
end

local SEG = { ["0"]="abcdef", ["1"]="bc", ["2"]="abged", ["3"]="abgcd", ["4"]="fgbc",
              ["5"]="afgcd", ["6"]="afgedc", ["7"]="abc", ["8"]="abcdefg", ["9"]="abcdfg" }
local SEG_RECT = { a = {1, 0, 3, 1}, g = {1, 4, 3, 1}, d = {1, 8, 3, 1},
                   f = {0, 1, 1, 3}, b = {4, 1, 1, 3}, e = {0, 5, 1, 3}, c = {4, 5, 1, 3} }

local function digit(x, y, ch, lit_lv)
  local on = SEG[ch] or ""
  for name, r in pairs(SEG_RECT) do
    px(x + r[1], y + r[2], r[3], r[4], on:find(name, 1, true) and lit_lv or 1)
  end
end

-- The amp's knob: 4 x 4 with the corners off.
local function knob(x, y, lv)
  px(x + 1, y, 2, 1, lv); px(x, y + 1, 4, 2, lv); px(x + 1, y + 3, 2, 1, lv)
end

local function draw_unit(x, y, ch, active, fk)
  shell(x, y)
  led(x + UNIT.LED.X, y + UNIT.LED.Y, active)

  local m  = UNIT.METER
  local db = 20 * math.log(math.max(strip.lvl[ch], 1e-6), 10)
  local clip = active and strip.lvl[ch + 2] > CLIP_AT
  for k = 1, m.N do
    local lit = active and (db > m.DB[k] or (k == m.N and clip))
    px(x + m.X + (k - 1) * m.PITCH, y + m.Y, 1, m.H, lit and (k > m.N - 3 and FULL or 8) or 2)
  end

  local gv  = params:get("strip_gain")
  local g   = math.floor(gv + (gv < 0 and -0.5 or 0.5))
  local txt = string.format("%2d", math.abs(g))
  local glv = fk == 1 and FULL or 8
  local D = UNIT.DIGITS
  px(x + D.MINUS, y + D.Y + 4, 3, 1, g < 0 and glv or 1)
  for i = 1, 2 do digit(x + D.X[i], y + D.Y, txt:sub(i, i), glv) end

  for i = 1, #UNIT.KNOBS.X do
    knob(x + UNIT.KNOBS.X[i], y + UNIT.KNOBS.Y, fk == i + 1 and FULL or MED)
  end
end

-- The controls are linked, so the focused knob lights on both units at once.
function strip.draw(active, fk)
  local c = cabinet.CAB
  local h = math.floor((c.h - 4) / 2)
  draw_unit(c.x, c.y - 1, 1, active, fk)
  draw_unit(c.x, c.y + h + 4, 2, active, fk)
end

-- ── Spring tank ──────────────────────────────────────────────
-- Reverb as a Fender tank behind glass: the knobs and the Freeze LED on top, below them the pan
-- with its two transducers and the springs as helices whose near turns catch more light. They
-- swing with the reverb's own level, so a long tail keeps them moving and Freeze keeps them ringing.
strip.rev = { level = 0, t = 0 }

local TANK = { W = 82, H = 60 }
TANK.KNOBS  = { X = { 8, 14, 20, 26 }, Y = 8 }
TANK.LED    = { X = 70, Y = 9 }
TANK.WIN    = { X = 3, Y = 19, W = 76, H = 38 }
TANK.XDCR   = { X = { 6, 68 }, Y = 25, W = 8, H = 26 }
TANK.SPRING = { X0 = 14, X1 = 67, ROWS = { 31, 44 }, PITCH = 3.5, AMP = 2.2 }

local function frame(x, y, w, h, lv)
  px(x, y, w, 1, lv); px(x, y + h - 1, w, 1, lv)
  px(x, y + 1, 1, h - 2, lv); px(x + w - 1, y + 1, 1, h - 2, lv)
end

-- One transducer: a can with its lid seam and the coil it drives.
local function transducer(x, y)
  local T = TANK.XDCR
  px(x, y, T.W, T.H, 2)
  frame(x, y, T.W, T.H, 4)
  px(x + 1, y + 3, T.W - 2, 1, 3); px(x + 1, y + T.H - 4, T.W - 2, 1, 3)
  for _, row in ipairs(TANK.SPRING.ROWS) do px(x + 2, y + row - T.Y - 1, T.W - 4, 3, 5) end
end

function strip.draw_tank(active, fk, frozen)
  local x, y = cabinet.CAB.x, cabinet.TOP
  frame(x, y, TANK.W, TANK.H, MED)

  local W = TANK.WIN
  px(x + W.X, y + W.Y, W.W, W.H, 1)
  frame(x + W.X, y + W.Y, W.W, W.H, 3)
  for _, tx in ipairs(TANK.XDCR.X) do transducer(x + tx, y + TANK.XDCR.Y) end

  -- the swing is a standing wave, fixed at both transducers, as large as the reverb is loud
  local S  = TANK.SPRING
  local sw = active and math.min(strip.rev.level * 30, 2) or 0
  local near = frozen and FULL or (active and 10 or 4)
  local far  = frozen and 8 or (active and 4 or 2)
  for k, row in ipairs(S.ROWS) do
    local prev
    for sx = S.X0, S.X1 do
      local u   = (sx - S.X0) / (S.X1 - S.X0)
      local off = sw * math.sin(math.pi * u) * math.sin(strip.rev.t * (k == 1 and 7 or 9))
      -- the helix is centred on the middle column, so both ends of a spring match
      local ph  = 2 * math.pi * (sx - 40.5) / S.PITCH
      local hy  = math.floor(math.sin(ph) * S.AMP + off + 0.5)
      local top = prev and math.min(prev, hy) or hy
      local bot = prev and math.max(prev, hy) or hy
      px(x + sx, y + row + top, 1, bot - top + 1, math.cos(ph) > 0 and near or far)
      prev = hy
    end
  end

  for i, kx in ipairs(TANK.KNOBS.X) do knob(x + kx, y + TANK.KNOBS.Y, fk == i and FULL or MED) end
  led(x + TANK.LED.X, y + TANK.LED.Y, frozen)
end

return strip
