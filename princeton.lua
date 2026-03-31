-- princeton
--
-- Amp sim based on a combo.
-- Tuner, effects and looper.

engine.name = "Princeton"

local PARAMS_DEF = {
  { id="volume",         name="Volume",    default=5.0,  min=-0.1, max=10, step=0.1, db=false, cat="Amp"     },
  { id="bass",           name="Bass",      default=5.0,  min=0,   max=10, step=0.1, db=false, cat="Amp"     },
  { id="treble",         name="Treble",    default=5.0,  min=0,   max=10, step=0.1, db=false, cat="Amp"     },
  { id="master",         name="Master",    default=5.0,  min=0,   max=10, step=0.1, db=false, cat="Amp"     },
  { id="reverb",         name="Amount",    default=2.5,  min=0,   max=10, step=0.1, db=false, cat="Reverb"  },
  { id="trem_speed",     name="Speed",     default=0.0,  min=0,   max=10, step=0.1, db=false, cat="Tremolo" },
  { id="trem_intensity", name="Intensity", default=0.0,  min=0,   max=10, step=0.1, db=false, cat="Tremolo" },
  { id="mic",            name="Axis",      default=0,    min=0,   max=2,  step=1,   db=false, cat="Mic"     },
  { id="direction",      name="Direction", default=0,    min=0,   max=1,  step=1,   db=false, cat="Looper"  },
  { id="dub_style",      name="Dub Style", default=0,    min=0,   max=1,  step=1,   db=false, cat="Looper"  },
  { id="dub_level",      name="Dub Vol",   default=-2.5, min=-40, max=0,  step=0.5, db=true,  cat="Looper"  },
  { id="loop_level",     name="Loop Vol",  default=-2.5, min=-40, max=0,  step=0.5, db=true,  cat="Looper"  },
  { id="loop_speed",     name="Speed",     default=1,    min=0,   max=2,  step=1,   db=false, cat="Looper"  },
}
local MIC_NAMES  = { "Center", "Middle", "Edge" }
local CHAR_NAMES = { "Bright", "Dark" }
local DIR_NAMES  = { "Forward", "Reverse" }
local SPD_NAMES  = { "0.5x", "1x", "2x" }
local DUB_NAMES  = { "Regular", "Overwrite" }
local NUM_KNOBS  = 7

local LOOP_SR  = 48000
local LOOP_MAX = LOOP_SR * 60

local sel  = 1
local vals = {}
for i, p in ipairs(PARAMS_DEF) do vals[i] = p.default end

local function amp_is_bypassed()
  for i, p in ipairs(PARAMS_DEF) do
    if p.id == "volume" then return vals[i] < 0 end
  end
  return false
end

local pedal_active = false  -- pedalboard view (Push + Distort)
local pedal_sel    = 1      -- 1=Push, 2=Distort

local PEDALS = {
  {
    name       = "Push",
    display    = "Push",
    params     = {
      { id="push_gain",  name="Gain", default=5.0, min=0, max=10, step=0.1 },
      { id="push_tone",  name="Tone",  default=5.0, min=0, max=10, step=0.1 },
      { id="push_level", name="Level", default=5.0, min=0, max=10, step=0.1 },
    },
    vals       = { 5.0, 5.0, 5.0 },
    bypass     = true,
    psel       = 1,
    bypass_cmd = "push_bypass",
  },
  {
    name       = "Distort",
    display    = "Distort",
    params     = {
      { id="distort_gain",   name="Gain",   default=5.0, min=0, max=10, step=0.1 },
      { id="distort_tone", name="Tone", default=5.0, min=0, max=10, step=0.1 },
      { id="distort_level",    name="Level", default=2.5, min=0, max=10, step=0.1 },
    },
    vals       = { 5.0, 5.0, 5.0 },
    bypass     = true,
    psel       = 1,
    bypass_cmd = "distort_bypass",
  },
  {
    name       = "Warp",
    display    = "Warp",
    params     = {
      { id="warp_rate",  name="Rate",  default=3.0, min=0, max=10, step=0.1 },
      { id="warp_depth", name="Depth", default=5.0, min=0, max=10, step=0.1 },
      { id="warp_rise",  name="Rise",  default=3.0, min=0, max=10, step=0.1 },
    },
    vals       = { 2.5, 2.5, 5.0 },
    bypass     = true,
    psel       = 1,
    bypass_cmd = "warp_bypass",
  },
  {
    name       = "Repeat",
    display    = "Repeat",
    params     = {
      { id="repeat_time",       name="Time",      default=5.0, min=0, max=10, step=0.1 },
      { id="repeat_feedback",     name="Feedback",   default=5.0, min=0, max=10, step=0.1 },
      { id="repeat_level",      name="Level",     default=5.0, min=0, max=10, step=0.1 },
      { id="characteristic", name="Character", default=0,   min=0, max=1,  step=1   },
    },
    vals       = { 5.0, 5.0, 5.0, 0 },
    bypass     = true,
    psel       = 1,
    bypass_cmd = "repeat_bypass",
  },
}

local function cur_pedal() return PEDALS[pedal_sel] end

local LOOP_IDLE = 0
local LOOP_REC  = 1
local LOOP_DUB  = 2
local LOOP_PLAY = 3
local LOOP_STOP = 4

local loop_state     = LOOP_IDLE
local loop_rec_start = 0
local loop_frames    = 0
local k3_clock       = nil

local tuner = {
  active  = false,
  muted   = false,
  ref_hz  = 440.0,
  note    = "--",
  octave  = 0,
  cents   = 0,
}
local tuner_cents_smooth = 0  -- smoothed cents value for stable arrow display

local k1_clock = nil
local k2_clock = nil
local tuner_pitch_poll = nil

local B = { DIM=0, MED=6, FULL=15 }

local CAB_W, CAB_H = 82, 56
local CAB = {
  x = 45,   -- explicit: 1px gap to right edge (45+82=127, screen=128)
  y = math.floor((64 - CAB_H) / 2),
  w = CAB_W,
  h = CAB_H,
}

local BORDER_LVL = B.MED
local BORDER_GAP = 3
local INT = {
  x = CAB.x + BORDER_GAP + 2,
  y = CAB.y + BORDER_GAP + 2,
  w = CAB.w - (BORDER_GAP + 2) * 2,
  h = CAB.h - (BORDER_GAP + 2) * 2,
}

local PANEL_H = 10
local PANEL = { x=INT.x, y=INT.y,          w=INT.w, h=PANEL_H        }
local GRILL  = { x=INT.x, y=INT.y+PANEL_H, w=INT.w, h=INT.h-PANEL_H }
local SEP_Y  = INT.y + PANEL_H

local KNOB_R       = 2
local KNOB_Y       = PANEL.y + math.floor((PANEL.h - 1) / 2)
-- Panel layout: [1 gap][B1][1 gap][B2][1 gap][7 knobs @ 6px][logo 23px][1 gap][lamp][1 gap]
local PANEL_BUCHSE1 = PANEL.x + 1
local PANEL_BUCHSE2 = PANEL.x + 3
local PANEL_LAMP    = PANEL.x + PANEL.w - 2
local KNOB_SPACING  = 6
local KNOB_START    = PANEL.x + 5   -- after: 1 gap + B1 + 1 gap + B2 + 1 gap
local KNOB_X        = {}
for i = 1, NUM_KNOBS do
  KNOB_X[i] = KNOB_START + KNOB_SPACING * (i - 1) + math.floor(KNOB_SPACING / 2)
end

local LEFT_W  = CAB.x - 1
local LEFT_CX = math.floor(LEFT_W / 2) - 1
local ICON_Y  = 53

local function db_to_lin(db)
  return 10 ^ (db / 20)
end

local function fmt_val(idx)
  local id = PARAMS_DEF[idx].id
  if id == "volume" and vals[idx] < 0 then return "Bypass" end
  if id == "mic"        then return MIC_NAMES[math.floor(vals[idx]) + 1] end
  if id == "direction"  then return DIR_NAMES[math.floor(vals[idx]) + 1] end
  if id == "loop_speed" then return SPD_NAMES[math.floor(vals[idx]) + 1] end
  if id == "dub_style"  then return DUB_NAMES[math.floor(vals[idx]) + 1] end
  if PARAMS_DEF[idx].db then return string.format("%.1fdB", vals[idx]) end
  return string.format("%.1f", vals[idx])
end

local function send_param(idx)
  local p  = PARAMS_DEF[idx]
  if p.id == "volume" then
    local bypassed = vals[idx] < 0
    engine.amp_bypass(bypassed and 1 or 0)
    engine.volume(bypassed and 0 or vals[idx])
    return
  end
  local fn = engine[p.id]
  if fn == nil then return end
  local v = vals[idx]
  if p.db then v = db_to_lin(v) end
  fn(v)
end

local function loop_set_engine(st)
  engine.loop_rec (st == LOOP_REC  and 1 or 0)
  engine.loop_dub (st == LOOP_DUB  and 1 or 0)
  engine.loop_play(st == LOOP_PLAY and 1 or 0)
end

-- Tuner helpers
local NOTE_NAMES = {"C","C#","D","D#","E","F","F#","G","G#","A","A#","B"}

local function freq_to_note(freq)
  if freq < 20 then return "--", 0, 0 end
  local semitones = 69 + 12 * math.log(freq / 440.0) / math.log(2)
  local nearest   = math.floor(semitones + 0.5)
  local cents     = math.floor((semitones - nearest) * 100 + 0.5)
  local name      = NOTE_NAMES[nearest % 12 + 1]
  local octave    = math.floor(nearest / 12) - 1
  return name, octave, cents
end

local function cents_to_ref(freq, ref)
  if freq < 20 or ref < 20 then return 0 end
  local semitones = 12 * math.log(freq / ref) / math.log(2)
  local nearest   = math.floor(semitones + 0.5)
  local cents     = math.floor((semitones - nearest) * 100 + 0.5)
  return cents
end

local function rect_outline(x, y, w, h, lv)
  screen.level(lv)
  screen.line_width(1)
  screen.rect(x, y, w, h)
  screen.stroke()
end

local function draw_icon_record(cx, y, lv)
  screen.level(lv); screen.circle(cx, y, 5); screen.fill()
end

local function draw_icon_dub(cx, y, lv)
  screen.level(lv); screen.circle(cx, y, 5); screen.fill()
  screen.line_width(1)
  local px, py = cx + 8, y - 7
  screen.move(px-2, py); screen.line(px+1, py); screen.stroke()
  screen.move(px, py-2); screen.line(px, py+1); screen.stroke()
end

local function draw_icon_play(cx, y, lv)
  screen.level(lv)
  screen.move(cx-4, y-5); screen.line(cx+5, y); screen.line(cx-4, y+5)
  screen.fill()
end

local function draw_icon_stop(cx, y, lv)
  screen.level(lv); screen.rect(cx-4, y-4, 8, 8); screen.fill()
end

local function draw_strip(cat, name, val_str)
  screen.level(0); screen.rect(0, 0, LEFT_W, 64); screen.fill()
  screen.font_size(8); screen.font_face(0)
  screen.level(B.MED);  screen.move(LEFT_CX, 16); screen.text_center(cat)
  screen.level(B.MED);  screen.move(LEFT_CX, 25); screen.text_center(name)
  screen.level(B.FULL); screen.move(LEFT_CX, 34); screen.text_center(val_str)
end

local function draw_left_strip()
  draw_strip(PARAMS_DEF[sel].cat, PARAMS_DEF[sel].name, fmt_val(sel))

  if PARAMS_DEF[sel] and PARAMS_DEF[sel].cat == "Looper" then
    screen.level(B.FULL); screen.line_width(1)
    screen.move(11, 47); screen.line(8,  47); screen.line(8,  60); screen.line(11, 60)
    screen.move(31, 47); screen.line(35, 47); screen.line(35, 60); screen.line(31, 60)
    screen.stroke()
  end

  if loop_state == LOOP_REC then
    draw_icon_record(LEFT_CX, ICON_Y, B.FULL)
  elseif loop_state == LOOP_DUB then
    draw_icon_dub(LEFT_CX, ICON_Y, B.FULL)
  elseif loop_state == LOOP_PLAY then
    draw_icon_play(LEFT_CX, ICON_Y, B.FULL)
  elseif loop_state == LOOP_STOP then
    draw_icon_stop(LEFT_CX, ICON_Y, B.MED)
  end
end

local function draw_cabinet()
  rect_outline(CAB.x, CAB.y, CAB.w, CAB.h, BORDER_LVL)
  local g = BORDER_GAP
  rect_outline(CAB.x+g, CAB.y+g, CAB.w-g*2, CAB.h-g*2, BORDER_LVL)
end

local function draw_panel()
  screen.level(0); screen.rect(PANEL.x, PANEL.y, PANEL.w, PANEL.h); screen.fill()

  -- Buchsen (2 einzelne Pixel, links)
  screen.level(B.MED)
  screen.rect(PANEL_BUCHSE1, KNOB_Y, 1, 1); screen.fill()
  screen.rect(PANEL_BUCHSE2, KNOB_Y, 1, 1); screen.fill()

  -- Lampe (1 Pixel, rechts) — aus wenn Amp bypassed (volume < 0)
  screen.level(amp_is_bypassed() and B.MED or B.FULL)
  screen.rect(PANEL_LAMP, KNOB_Y, 1, 1); screen.fill()

  -- 7 Knöpfe
  for i = 1, NUM_KNOBS do
    screen.level(i == sel and B.FULL or B.MED)
    screen.circle(KNOB_X[i], KNOB_Y, KNOB_R); screen.fill()
  end

  screen.line_width(1); screen.level(B.MED)
  screen.move(CAB.x + BORDER_GAP + 1, SEP_Y)
  screen.line(PANEL.x + PANEL.w,      SEP_Y)
  screen.stroke()
end

local function draw_speaker_x(cx, cy, lv)
  screen.level(lv); screen.line_width(1)
  screen.move(cx-2, cy-2); screen.line(cx+2, cy+2); screen.stroke()
  screen.move(cx+2, cy-2); screen.line(cx-2, cy+2); screen.stroke()
end

local function draw_grillcloth()
  local gx, gy, gw, gh = GRILL.x, GRILL.y, GRILL.w, GRILL.h

  local mic_sel = PARAMS_DEF[sel] and PARAMS_DEF[sel].id == "mic"
  if mic_sel then
    screen.level(0); screen.rect(gx, gy, gw, gh); screen.fill()

    local cx = math.floor(gx + gw / 2 + 0.5)
    local cy = math.floor(gy + gh / 2 + 0.5)

    screen.level(B.MED); screen.line_width(1)
    screen.circle(cx, cy, 16); screen.stroke()

    screen.level(B.DIM)
    screen.circle(cx, cy, 11); screen.stroke()

    screen.level(B.MED)
    screen.circle(cx, cy, 5); screen.stroke()

    local mic_val = 0
    for i, p in ipairs(PARAMS_DEF) do
      if p.id == "mic" then mic_val = math.floor(vals[i]) end
    end

    -- Three fixed X positions (Center, Middle, Edge)
    -- The active one (matching mic_val) is FULL, others DIM
    local x_offsets = { 0, 8, 14 }
    for i = 1, 3 do
      local r   = x_offsets[i]
      local lv  = (i - 1 == mic_val) and B.FULL or B.DIM
      draw_speaker_x(cx + r, cy, lv)

    end
    return
  end

  screen.line_width(1)
  local y = gy
  while y <= gy + gh do
    screen.level(B.MED)
    screen.move(gx, y); screen.line(gx+gw, y); screen.stroke()
    y = y + 2
  end
  local x = gx
  while x <= gx + gw do
    screen.level(B.MED)
    screen.move(x, gy); screen.line(x, gy+gh); screen.stroke()
    x = x + 4
  end
end

local function draw_tuner()
  screen.level(0); screen.rect(0, 0, 128, 64); screen.fill()

  local cx = 64

  screen.font_size(24); screen.font_face(0)
  screen.level(tuner.muted and B.MED or B.FULL)
  screen.move(cx, 36)
  screen.text_center(tuner.note)

  screen.font_size(8); screen.level(B.MED)
  screen.move(cx + 10, 24)
  screen.text(tostring(tuner.octave))

  if tuner.note ~= "--" then
    local abs_cents = math.abs(tuner.cents)
    local in_tune   = abs_cents < 5

    if in_tune then
        screen.level(B.FULL)
      screen.circle(cx, 50, 2); screen.fill()
    elseif tuner.cents < 0 then
        screen.level(B.FULL)
      screen.move(18, 50)
      screen.line(10, 46); screen.line(10, 54)
      screen.fill()
    else
        screen.level(B.FULL)
      screen.move(110, 50)
      screen.line(118, 46); screen.line(118, 54)
      screen.fill()
    end
  end

  screen.font_size(8); screen.level(B.MED)
  screen.move(cx, 61)
  screen.text_center(string.format("A = %.1f Hz", tuner.ref_hz))

  if tuner.muted then
    screen.font_size(8); screen.level(B.MED)
    screen.move(126, 8); screen.text_right("mute")
  end
end

local function draw_knob(x, y, level)
  screen.level(level)
  screen.rect(x + 1, y,     1, 1)  -- Reihe 1:   xOx
  screen.rect(x,     y + 1, 3, 2)  -- Reihe 2+3: OOO
  screen.rect(x + 1, y + 3, 1, 1)  -- Reihe 4:   xOx
  screen.fill()
end

local function draw_pedal(ox, oy, name, display, bypassed)
  local id  = name:lower()
  local lv  = B.FULL
  local mid = oy + 24  -- vertikale Mitte des Icon-Bereichs


  screen.line_width(1); screen.level(lv)

  if id == "push" then
    -- Plus-Zeichen (Boost/Gain), 3px dick
    local cx = ox + 16
    local cy = mid
    local arm = 9
    screen.line_width(4)
    screen.level(lv)
    screen.move(cx,       cy - arm); screen.line(cx,       cy + arm)
    screen.move(cx - arm, cy);       screen.line(cx + arm, cy)
    screen.stroke()
    screen.line_width(1)

  elseif id == "distort" then
    -- Zerrissene Welle: linke Hälfte sauber, rechte Hälfte zerstört
    local cy = mid
    -- Sauber links (halber Sinus)
    screen.level(lv)
    screen.move(  ox,    cy)
    screen.curve( ox+3,  cy,    ox+4,  oy+12, ox+8,  oy+12)
    screen.curve( ox+12, oy+12, ox+13, cy,    ox+16, cy)
    screen.stroke()
    -- Gestrichelte Trennlinie
    screen.level(B.MED)
    for y = oy+10, oy+38, 4 do
      screen.move(ox+16, y); screen.line(ox+16, y+2)
    end
    screen.stroke()
    -- Zerstört rechts (Zackenlinie)
    screen.level(lv)
    screen.move(ox+16, cy)
    screen.line(ox+19, oy+32)
    screen.line(ox+22, oy+16)
    screen.line(ox+25, oy+36)
    screen.line(ox+28, oy+20)
    screen.line(ox+32, cy)
    screen.stroke()

  elseif id == "warp" then
    -- Drei Wellen (Warp)
    for _, cy in ipairs({oy+14, oy+24, oy+34}) do
      local a = cy - 6
      local b = cy + 6
      screen.move(  ox,    cy)
      screen.curve( ox+4,  cy,  ox+4,  a,  ox+8,  a)
      screen.curve( ox+12, a,   ox+12, cy, ox+16, cy)
      screen.curve( ox+20, cy,  ox+20, b,  ox+24, b)
      screen.curve( ox+28, b,   ox+28, cy, ox+32, cy)
      screen.stroke()
    end

  elseif id == "repeat" then
    -- 5 Striche: gleicher Abstand, abnehmende Höhe und Helligkeit
    local levels  = {15, 10, 6, 3, 1}  -- gradient allowed here
    local heights = {20, 15, 11, 7, 4}
    for i = 1, 5 do
      local bx = ox + 3 + (i - 1) * 7  -- Abstand 7px, Start ox+3
      local bh = heights[i]
      screen.level(levels[i])
      screen.move(bx, mid - bh); screen.line(bx, mid + bh)
      screen.stroke()
    end
  end

  -- Label unten: hell wenn aktiv, gedimmt wenn bypassed
  screen.font_size(8); screen.font_face(0)
  screen.level(bypassed and B.MED or B.FULL)
  screen.move(ox + 16, oy + 55); screen.text_center(display)
end

local function draw_pedalboard()
  screen.clear()

  -- ── Left param strip (same width as amp view) ──────────────────
  local pd   = cur_pedal()
  local p    = pd.params[pd.psel]
  local vstr = p.id == "characteristic"
    and CHAR_NAMES[math.floor(pd.vals[pd.psel]) + 1]
    or  string.format("%.1f", pd.vals[pd.psel])
  draw_strip(pd.name, p.name, vstr)

  -- ── Two pedals, snapped to CAB edges ────────────────────────────
  -- OX1 = CAB.x = 39  (left pedal flush with amp left edge)
  -- OX2 = CAB.x + CAB.w - 32 = 95  (right pedal flush with amp right edge)
  local OX1 = CAB.x
  local OX2 = CAB.x + CAB.w - 33
  local py  = 4

  if pedal_sel >= 3 then
    draw_pedal(OX1, py, PEDALS[3].name, PEDALS[3].display, PEDALS[3].bypass)
    draw_pedal(OX2, py, PEDALS[4].name, PEDALS[4].display, PEDALS[4].bypass)
  else
    draw_pedal(OX1, py, PEDALS[1].name, PEDALS[1].display, PEDALS[1].bypass)
    draw_pedal(OX2, py, PEDALS[2].name, PEDALS[2].display, PEDALS[2].bypass)
  end
  local ptr_x = (pedal_sel == 1 or pedal_sel == 3) and OX1 + 16 or OX2 + 16
  screen.level(B.FULL)
  screen.move(ptr_x-3,1); screen.line(ptr_x+3,1); screen.line(ptr_x,5); screen.fill()
  screen.update()
end


function redraw()
  if pedal_active then
    draw_pedalboard()
    return
  end
  screen.clear()
  draw_left_strip()
  if tuner.active then
    draw_tuner()
  else
    draw_grillcloth()
    draw_panel()
    draw_cabinet()
  end
  screen.update()
end

local function tuner_start()
  tuner.active = true
  tuner.muted  = false
  tuner.note   = "--"
  tuner.octave = 0
  tuner.cents  = 0
  -- Stop looper: abort any recording or playback
  if loop_state ~= LOOP_IDLE then
    loop_state = LOOP_STOP
    loop_set_engine(LOOP_STOP)
  end
  engine.mute(0)
  tuner_pitch_poll:start()
  redraw()
end

local function tuner_stop()
  tuner.active = false
  tuner_pitch_poll:stop()
  engine.mute(0)  -- always unmute on exit
  redraw()
end

function enc(n, d)
  if pedal_active then
    if n == 1 then
      if pedal_sel <= 2 then pedal_sel = util.clamp(pedal_sel + d, 1, 2)
      elseif pedal_sel >= 3 then pedal_sel = util.clamp(pedal_sel + d, 3, 4) end
      redraw()
      return
    end
    if n == 2 then
      cur_pedal().psel = util.clamp(cur_pedal().psel + d, 1, #cur_pedal().params)
      redraw()
    elseif n == 3 then
      local pd = cur_pedal()
      local p  = pd.params[pd.psel]
      local v  = util.clamp(pd.vals[pd.psel] + d * p.step, p.min, p.max)
      pd.vals[pd.psel] = math.floor(v * 10 + 0.5) / 10
      engine[p.id](pd.vals[pd.psel])
      redraw()
    end
    return
  end
  if tuner.active then
    if n == 2 then
      tuner.ref_hz = util.clamp(tuner.ref_hz + d * 0.1, 420.0, 460.0)
      tuner.ref_hz = math.floor(tuner.ref_hz * 10 + 0.5) / 10
      redraw()
    end
    return
  end

  if n == 2 then
    sel = util.clamp(sel + d, 1, #PARAMS_DEF)
    redraw()
  elseif n == 3 then
    local p = PARAMS_DEF[sel]
    local v = util.clamp(vals[sel] + d * p.step, p.min, p.max)
    if p.step == 1 then
      v = math.floor(v + 0.5)
    else
      v = math.floor(v * 10 + 0.5) / 10
    end
    vals[sel] = v
    send_param(sel)
    redraw()
  end
end

function key(n, z)

  -- ── K1: 2s hold = tuner on/off ───────────────────────────────────
  if n == 1 then
    if z == 1 then
      k1_clock = clock.run(function()
        clock.sleep(2.0)
        k1_clock = nil
        if tuner.active then tuner_stop() else tuner_start() end
      end)
    else
      if k1_clock ~= nil then clock.cancel(k1_clock); k1_clock = nil end
    end
    return
  end

  -- ── K2: short = looper (amp view only), hold = Verzerrer on/off ──────
  if n == 2 then
    if z == 1 then
      k2_clock = clock.run(function()
        clock.sleep(2.0)
        k2_clock = nil
        if tuner.active then
          -- Tuner -> Verzerrer
          tuner_stop()
          pedal_active = true
          pedal_sel = 1
          redraw()
          return
        end
        -- Hold: toggle Verzerrer, or navigate from Modulations to Verzerrer
        if pedal_active and (pedal_sel == 3 or pedal_sel == 4) then
          pedal_sel = 1
        elseif pedal_active and pedal_sel <= 2 then
          pedal_active = false
        else
          pedal_active = true
          pedal_sel = 1
        end
        redraw()
      end)
      return
    else
      if k2_clock ~= nil then
        clock.cancel(k2_clock)
        k2_clock = nil
        if tuner.active then return end
        if pedal_active then return end  -- kein Looper aus Pedalansicht
      else
        return
      end
    end
    -- Kurzdruck: Looper (nur aus Amp-Ansicht)
    if loop_state == LOOP_IDLE then
      engine.loop_frames(LOOP_MAX)
      loop_rec_start = util.time()
      loop_state = LOOP_REC
      loop_set_engine(LOOP_REC)
    elseif loop_state == LOOP_REC then
      local elapsed = util.time() - loop_rec_start
      loop_frames = math.max(math.min(math.floor(elapsed * LOOP_SR), LOOP_MAX), 2)
      engine.loop_frames(loop_frames)
      loop_state = LOOP_PLAY
      loop_set_engine(LOOP_PLAY)
    elseif loop_state == LOOP_PLAY then
      loop_state = LOOP_DUB
      loop_set_engine(LOOP_DUB)
    elseif loop_state == LOOP_DUB then
      loop_state = LOOP_PLAY
      loop_set_engine(LOOP_PLAY)
    elseif loop_state == LOOP_STOP then
      loop_state = LOOP_PLAY
      loop_set_engine(LOOP_PLAY)
    end
    redraw()
    return
  end

  if n == 3 then
    if tuner.active then
      if z == 1 then
        k3_clock = clock.run(function()
          clock.sleep(2.0)
          k3_clock = nil
          -- Hold: Tuner -> Modulationen
          tuner_stop()
          pedal_active = true
          pedal_sel = 3
          redraw()
        end)
      else
        if k3_clock ~= nil then
          clock.cancel(k3_clock)
          k3_clock = nil
          -- Kurzdruck: Mute toggle
          tuner.muted = not tuner.muted
          engine.mute(tuner.muted and 1 or 0)
          redraw()
        end
      end
      return
    end

    if pedal_active then
      -- Bypass toggle: kurz. Schliessen: halten
      if z == 1 then
        k3_clock = clock.run(function()
          clock.sleep(2.0)
          k3_clock = nil
          -- Hold: Modulationen schliessen (oder öffnen falls Verzerrer offen)
          if pedal_sel >= 3 then
            pedal_active = false
          else
            pedal_active = true
            pedal_sel = 3
          end
          redraw()
        end)
      else
        if k3_clock ~= nil then
          clock.cancel(k3_clock)
          k3_clock = nil
          -- Kurzdruck: Bypass toggle des aktiven Pedals
          local pd = cur_pedal()
          pd.bypass = not pd.bypass
          engine[pd.bypass_cmd](pd.bypass and 1 or 0)
          redraw()
        end
      end
      return
    end

    -- Normal (kein Pedal offen): kurz = Looper stop/abort, hold = Modulationen öffnen
    if z == 1 then
      k3_clock = clock.run(function()
        clock.sleep(2.0)
        k3_clock = nil
        if loop_state == LOOP_IDLE then
          pedal_sel = 3; pedal_active = true
        else
          loop_state  = LOOP_IDLE
          loop_frames = 0
          engine.loop_clear()
        end
        redraw()
      end)
    else
      if k3_clock ~= nil then
        clock.cancel(k3_clock)
        k3_clock = nil
        if loop_state == LOOP_REC then
          loop_state  = LOOP_IDLE
          loop_frames = 0
          engine.loop_clear()
          redraw()
        elseif loop_state == LOOP_DUB then
          loop_state = LOOP_PLAY
          loop_set_engine(LOOP_PLAY)
          redraw()
        elseif loop_state ~= LOOP_IDLE then
          loop_state = LOOP_STOP
          loop_set_engine(LOOP_STOP)
          redraw()
        end
      end
    end
    return
  end
end


function init()
  audio.level_monitor(0)
  for i = 1, #PARAMS_DEF do send_param(i) end
  local function send_pedal(params, vals, bypass_cmd)
    for i, p in ipairs(params) do
      if engine[p.id] then engine[p.id](vals[i]) end
    end
    if engine[bypass_cmd] then engine[bypass_cmd](1) end
  end
  for _, pd in ipairs(PEDALS) do send_pedal(pd.params, pd.vals, pd.bypass_cmd) end

  -- Pitch poll
  tuner_pitch_poll = poll.set("pitch_in_l", function(freq)
    if not tuner.active then return end
    if freq and freq > 30 then
      tuner.note, tuner.octave, _ = freq_to_note(freq)
      local c = cents_to_ref(freq, tuner.ref_hz)
      -- Smooth cents with exponential moving average (alpha=0.15 = slow/stable arrows)
      tuner_cents_smooth = tuner_cents_smooth * 0.5 + c * 0.5
      tuner.cents = math.floor(tuner_cents_smooth + 0.5)
    else
      tuner.note          = "--"
      tuner.octave        = 0
      tuner.cents         = 0
      tuner_cents_smooth  = 0
    end
    redraw()
  end)
  tuner_pitch_poll.time = 0.055  -- ~18Hz, fast note detection

  clock.run(function()
    clock.sleep(0.1)
    redraw()
  end)
end
