-- princeton
--
-- Amp sim based on a combo.
-- Tuner, effects and looper.

engine.name = "Princeton"

local initing = true

local PARAMS_DEF = {
  { id="amp_volume",         name="Volume",    default=7.5,  min=0,    max=10, step=0.1, db=false, cat="Amp"     },
  { id="amp_bass",           name="Bass",      default=5.0,  min=0,   max=10, step=0.1, db=false, cat="Amp"     },
  { id="amp_treble",         name="Treble",    default=5.0,  min=0,   max=10, step=0.1, db=false, cat="Amp"     },
  { id="amp_master",         name="Master",    default=5.0,  min=0,   max=10, step=0.1, db=false, cat="Amp"     },
  { id="reverb_amount",     name="Amount",    default=2.5,  min=0,   max=10, step=0.1, db=false, cat="Reverb"  },
  { id="tremolo_speed",     name="Speed",     default=0.0,  min=0,   max=10, step=0.1, db=false, cat="Tremolo" },
  { id="tremolo_intensity", name="Intensity", default=0.0,  min=0,   max=10, step=0.1, db=false, cat="Tremolo" },
  { id="mic_position",            name="Position",     default=1,    min=0,   max=2,  step=1,   db=false, cat="Mic"     },
  { id="looper_topology",   name="Topology",   default=3,   min=1,  max=4,  step=1,   db=false, cat="Looper", options={"BBD","Cassette","Digital","Tape"} },
  { id="looper_character", name="Character",  default=0.0, min=0,  max=10, step=0.1, db=false, cat="Looper"  },
  { id="looper_direction",      name="Direction", default=0,    min=0,   max=3,  step=1,   db=false, cat="Looper"  },
  { id="looper_dub_level",      name="Dub Level", default=-2.5, min=-40, max=0,  step=0.5, db=true,  cat="Looper"  },
  { id="looper_level",     name="Level",        default=-2.5, min=-40, max=0, step=0.5, db=true,  cat="Looper"  },
  { id="looper_speed",     name="Speed",     default=1,    min=0,   max=2,  step=1,   db=false, cat="Looper"  },
}
local MIC_NAMES  = { "Center", "Middle", "Edge" }
local DIR_NAMES  = { "Forward", "Reverse", "Pendulum", "Random" }
local SPD_NAMES  = { "0.5x", "1x", "2x" }
local DUB_NAMES  = { "Regular", "Overwrite" }
local NUM_KNOBS  = 7

local LOOP_SR  = 48000
local LOOP_MAX = LOOP_SR * 40

local sel = 1

local function amp_is_bypassed()
  return params:get("amp_enable") == 1
end

local pedal_active = false
local pedal_sel    = 1

local PEDALS = {
  {
    name       = "Push",
    display    = "Push",
    params     = {
      { id="push_gain",  name="Gain",  default=5.0, min=0, max=10, step=0.1 },
      { id="push_tone",  name="Tone",  default=5.0, min=0, max=10, step=0.1 },
      { id="push_level", name="Level", default=5.0, min=0, max=10, step=0.1 },
      { id="push_mix",   name="Mix",   default=2.5, min=0, max=10, step=0.1 },
    },
    psel       = 1,
    bypass_cmd = "push_bypass",
    enable_id  = "push_enable",
  },
  {
    name       = "Distort",
    display    = "Distort",
    params     = {
      { id="distort_gain",    name="Gain",     default=5.0, min=0, max=10, step=0.1 },
      { id="distort_tone",    name="Tone",     default=7.5, min=0, max=10, step=0.1 },
      { id="distort_level",   name="Level",    default=5.0, min=0, max=10, step=0.1 },
      { id="distort_lowcut",  name="Low Cut",  default=0, min=0, max=2, step=1, options={"Off","100 Hz","250 Hz"} },
    },
    psel       = 1,
    bypass_cmd = "distort_bypass",
    enable_id  = "distort_enable",
  },
  {
    name       = "Warp",
    display    = "Warp",
    params     = {
      { id="warp_rate",  name="Rate",      default=2.5, min=0, max=10, step=0.1 },
      { id="warp_depth", name="Depth",     default=2.5, min=0, max=10, step=0.1 },
      { id="warp_rise",  name="Rise/Fall", default=5.0, min=0, max=10, step=0.1 },
      { id="warp_mix",   name="Mix",       default=0.0, min=0, max=10, step=0.1 },
    },
    psel       = 1,
    bypass_cmd = "warp_bypass",
    enable_id  = "warp_enable",
  },
  {
    name       = "Repeat",
    display    = "Repeat",
    params     = {
      { id="repeat_time",           name="Time",      default=7.5, min=0, max=10, step=0.1 },
      { id="repeat_feedback",       name="Feedback",  default=5.0, min=0, max=10, step=0.1 },
      { id="repeat_level",          name="Level",     default=5.0, min=0, max=10, step=0.1 },
      { id="repeat_characteristic", name="Character", default=0,   min=0, max=1,  step=1, options={"Bright","Dark"} },
    },
    psel       = 1,
    bypass_cmd = "repeat_bypass",
    enable_id  = "repeat_enable",
  },
}

local function cur_pedal() return PEDALS[pedal_sel] end

-- Metro pitch: C0..B7 in piano order (0-based index 57 = A4 = 0 semitones from A440)
local NOTE_NAMES_PIANO = {"C","C#","D","D#","E","F","F#","G","G#","A","A#","B"}
local METRO_PITCH_NAMES = {}
for oct = 0, 7 do
  for _, n in ipairs(NOTE_NAMES_PIANO) do
    METRO_PITCH_NAMES[#METRO_PITCH_NAMES + 1] = n .. oct
  end
end
-- METRO_PITCH_NAMES[58] (1-based) = A4 (0-based index 57); semitones = index - 57

local LOOP_IDLE = 0
local LOOP_REC  = 1
local LOOP_DUB  = 2
local LOOP_PLAY = 3
local LOOP_STOP = 4

local loop_state     = LOOP_IDLE
local loop_rec_start = 0
local loop_frames    = 0

local tuner = {
  active  = false,
  muted   = false,
  ref_hz  = 440.0,
  note    = "--",
  octave  = 0,
  cents   = 0,
}
local tuner_cents_smooth    = 0
local tuner_note_candidate  = "--"
local tuner_oct_candidate   = 0
local tuner_note_hold       = 0
local TUNER_HOLD_FRAMES     = 3   -- consecutive frames before note name switches

local metro_active = false
local metro_clock  = nil

local k1_clock = nil
local k2_clock = nil
local k3_clock = nil
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
local PANEL_BUCHSE1 = PANEL.x
local PANEL_BUCHSE2 = PANEL.x + 2
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
  local v  = params:get(id)
  if PARAMS_DEF[idx].options then return PARAMS_DEF[idx].options[v] end
  if id == "mic_position"    then return MIC_NAMES[v] end
  if id == "looper_direction" then return DIR_NAMES[v] end
  if id == "looper_speed"    then return SPD_NAMES[v] end
  if PARAMS_DEF[idx].db then return string.format("%.1fdB", v) end
  return string.format("%.1f", v)
end

local function snap_val(v, step)
  if step == 1 then return math.floor(v + 0.5)
  else return math.floor(v * 10 + 0.5) / 10 end
end


local function loop_set_engine(st)
  engine.loop_rec (st == LOOP_REC  and 1 or 0)
  engine.loop_dub (st == LOOP_DUB  and 1 or 0)
  engine.loop_play(st == LOOP_PLAY and 1 or 0)
end

local function looper_step()
  if loop_state == LOOP_IDLE then
    engine.loop_frames(LOOP_MAX)
    loop_rec_start = util.time()
    loop_state = LOOP_REC
    loop_set_engine(LOOP_REC)
  elseif loop_state == LOOP_REC then
    local elapsed = util.time() - loop_rec_start
    loop_frames = math.max(math.min(math.floor(elapsed * LOOP_SR), LOOP_MAX), 2)
    engine.loop_frames(loop_frames)
    local next = params:get("looper_transport") == 2 and LOOP_DUB or LOOP_PLAY
    loop_state = next
    loop_set_engine(next)
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
end

local function looper_stop_clear()
  if loop_state == LOOP_REC then
    loop_state  = LOOP_IDLE
    loop_frames = 0
    engine.loop_clear()
  elseif loop_state == LOOP_DUB then
    loop_state = LOOP_STOP
    loop_set_engine(LOOP_STOP)
  elseif loop_state == LOOP_STOP then
    loop_state  = LOOP_IDLE
    loop_frames = 0
    engine.loop_clear()
  elseif loop_state ~= LOOP_IDLE then
    loop_state = LOOP_STOP
    loop_set_engine(LOOP_STOP)
  end
  redraw()
end

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

local function draw_icon_filled_circle(cx, y)
  -- Manual pixel circle: 4px-thick cross + 2×2 corner fills → octagon, r≈5
  screen.rect(cx - 5, y - 2, 10, 4)   -- horizontal arm
  screen.rect(cx - 2, y - 5, 4, 10)   -- vertical arm
  screen.rect(cx - 4, y - 4, 2, 2)    -- corner top-left
  screen.rect(cx + 2, y - 4, 2, 2)    -- corner top-right
  screen.rect(cx - 4, y + 2, 2, 2)    -- corner bottom-left
  screen.rect(cx + 2, y + 2, 2, 2)    -- corner bottom-right
  screen.fill()
end

local function draw_icon_record(cx, y, lv)
  screen.level(lv)
  draw_icon_filled_circle(cx, y)
end

local function draw_icon_dub(cx, y, lv)
  screen.level(lv)
  draw_icon_filled_circle(cx, y)
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

  screen.level(B.MED)
  screen.rect(PANEL_BUCHSE1, KNOB_Y, 1, 1); screen.fill()
  screen.rect(PANEL_BUCHSE2, KNOB_Y, 1, 1); screen.fill()

  screen.level(amp_is_bypassed() and B.MED or B.FULL)
  screen.rect(PANEL_LAMP, KNOB_Y, 1, 1); screen.fill()

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

  -- Speaker bypass: blank grill (no cloth, no mic markers)
  if params:get("speaker_enable") == 1 then
    screen.level(0); screen.rect(gx, gy, gw, gh); screen.fill()
    return
  end

  local mic_sel = PARAMS_DEF[sel] and PARAMS_DEF[sel].id == "mic_position"
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

    local mic_val = params:get("mic_position") - 1
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

  if tuner.note ~= "--" then
    screen.font_size(8); screen.level(15)
    screen.move(cx + 15, 19)
    screen.text(tostring(tuner.octave))

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

  screen.font_size(8)
  screen.level(5);  screen.move(38, 61); screen.text("A = ")
  screen.level(15); screen.text(string.format("%.1f Hz", tuner.ref_hz))

  if tuner.muted then
    screen.font_size(8); screen.level(B.MED)
    screen.move(126, 8); screen.text_right("mute")
  end
end

local function draw_knob(x, y, level)
  screen.level(level)
  screen.rect(x + 1, y,     1, 1)
  screen.rect(x,     y + 1, 3, 2)
  screen.rect(x + 1, y + 3, 1, 1)
  screen.fill()
end

local function draw_pedal(ox, oy, name, display, bypassed)
  local id  = name:lower()
  local lv  = B.FULL
  local mid = oy + 24

  screen.line_width(1); screen.level(lv)

  if id == "push" then
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
    local cy = mid
    screen.level(lv)
    screen.move(  ox,    cy)
    screen.curve( ox+3,  cy,    ox+4,  oy+12, ox+8,  oy+12)
    screen.curve( ox+12, oy+12, ox+13, cy,    ox+16, cy)
    screen.stroke()
    screen.level(B.MED)
    for y = oy+10, oy+38, 4 do
      screen.move(ox+16, y); screen.line(ox+16, y+2)
    end
    screen.stroke()
    screen.level(lv)
    screen.move(ox+16, cy)
    screen.line(ox+19, oy+32)
    screen.line(ox+22, oy+16)
    screen.line(ox+25, oy+36)
    screen.line(ox+28, oy+20)
    screen.line(ox+32, cy)
    screen.stroke()

  elseif id == "warp" then
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
    local levels  = {15, 10, 6, 3, 1}
    local heights = {20, 15, 11, 7, 4}
    for i = 1, 5 do
      local bx = ox + 3 + (i - 1) * 7
      local bh = heights[i]
      screen.level(levels[i])
      screen.move(bx, mid - bh); screen.line(bx, mid + bh)
      screen.stroke()
    end
  end

  screen.font_size(8); screen.font_face(0)
  screen.level(bypassed and B.MED or B.FULL)
  screen.move(ox + 16, oy + 55); screen.text_center(display)
end

local function draw_pedalboard()
  screen.clear()

  local pd   = cur_pedal()
  local p    = pd.params[pd.psel]
  local v    = params:get(p.id)
  local vstr = p.options and p.options[v] or string.format("%.1f", v)
  draw_strip(pd.name, p.name, vstr)

  -- ── Two pedals, snapped to CAB edges ────────────────────────────
  -- OX1 = CAB.x = 39  (left pedal flush with amp left edge)
  -- OX2 = CAB.x + CAB.w - 32 = 95  (right pedal flush with amp right edge)
  local OX1 = CAB.x
  local OX2 = CAB.x + CAB.w - 33
  local py  = 4

  if pedal_sel >= 3 then
    draw_pedal(OX1, py, PEDALS[3].name, PEDALS[3].display, params:get(PEDALS[3].enable_id) == 1)
    draw_pedal(OX2, py, PEDALS[4].name, PEDALS[4].display, params:get(PEDALS[4].enable_id) == 1)
  else
    draw_pedal(OX1, py, PEDALS[1].name, PEDALS[1].display, params:get(PEDALS[1].enable_id) == 1)
    draw_pedal(OX2, py, PEDALS[2].name, PEDALS[2].display, params:get(PEDALS[2].enable_id) == 1)
  end
  local ptr_x = (pedal_sel == 1 or pedal_sel == 3) and OX1 + 16 or OX2 + 16
  screen.level(B.FULL)
  screen.move(ptr_x-3,1); screen.line(ptr_x+3,1); screen.line(ptr_x,5); screen.fill()
  screen.update()
end


function redraw()
  if initing then return end
  if pedal_active then
    draw_pedalboard()
    return
  end
  screen.clear()
  if tuner.active then
    draw_tuner()
  else
    draw_left_strip()
    draw_grillcloth()
    draw_panel()
    draw_cabinet()
  end
  screen.update()
end

local function metro_tick_now()
  local semitones = params:get("metro_pitch") - 1 - 57  -- 0-based index, A4=57 → 0
  engine.metro_tick(params:get("metro_level") / 10.0, semitones)
end

local function metro_clock_start()
  if metro_clock then clock.cancel(metro_clock) end
  metro_clock = clock.run(function()
    while true do
      metro_tick_now()
      clock.sleep(60.0 / params:get("metro_bpm"))
    end
  end)
end

local function metro_clock_stop()
  if metro_clock then clock.cancel(metro_clock); metro_clock = nil end
end

local function tuner_start()
  tuner.active         = true
  tuner.muted          = false
  tuner.note           = "--"
  tuner.octave         = 0
  tuner.cents          = 0
  tuner_cents_smooth   = 0
  tuner_note_candidate = "--"
  tuner_oct_candidate  = 0
  tuner_note_hold      = 0
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
      params:set(p.id, snap_val(params:get(p.id) + d * p.step, p.step))
    end
    return
  end
  if tuner.active then
    if n == 2 then
      local v = params:get("tuner_ref") + d * 0.1
      params:set("tuner_ref", math.floor(v * 10 + 0.5) / 10)
    end
    return
  end

  if n == 2 then
    sel = util.clamp(sel + d, 1, #PARAMS_DEF)
    redraw()
  elseif n == 3 then
    local p = PARAMS_DEF[sel]
    params:set(p.id, snap_val(params:get(p.id) + d * p.step, p.step))
  end
end

function key(n, z)

  if n == 1 then
    if z == 1 then
      k1_clock = clock.run(function()
        clock.sleep(2.0)
        k1_clock = nil
        if tuner.active then tuner_stop() else pedal_active = false; tuner_start() end
      end)
    else
      if k1_clock ~= nil then clock.cancel(k1_clock); k1_clock = nil end
    end
    return
  end

  if n == 2 then
    if z == 1 then
      k2_clock = clock.run(function()
        clock.sleep(2.0)
        k2_clock = nil
        if tuner.active then
          tuner_stop()
          pedal_active = true
          pedal_sel = 1
          redraw()
          return
        end
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
        if pedal_active then return end
      else
        return
      end
    end
    looper_step()
    return
  end

  if n == 3 then
    if tuner.active then
      if z == 1 then
        k3_clock = clock.run(function()
          clock.sleep(2.0)
          k3_clock = nil
          tuner_stop()
          pedal_active = true
          pedal_sel = 3
          redraw()
        end)
      else
        if k3_clock ~= nil then
          clock.cancel(k3_clock)
          k3_clock = nil
          tuner.muted = not tuner.muted
          engine.mute(tuner.muted and 1 or 0)
          redraw()
        end
      end
      return
    end

    if pedal_active then
      if z == 1 then
        k3_clock = clock.run(function()
          clock.sleep(2.0)
          k3_clock = nil
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
          local pd  = cur_pedal()
          local cur = params:get(pd.enable_id)
          params:set(pd.enable_id, 3 - cur)
        end
      end
      return
    end

    if z == 1 then
      k3_clock = clock.run(function()
        clock.sleep(2.0)
        k3_clock = nil
        pedal_sel = 3; pedal_active = true
        redraw()
      end)
    else
      if k3_clock ~= nil then
        clock.cancel(k3_clock)
        k3_clock = nil
        looper_stop_clear()
      end
    end
    return
  end
end


function init()
  audio.level_monitor(0)

  local function re() if not initing then redraw() end end

  -- ── Tuner ───────────────────────────────────────────────────────────
  params:add_separator("Tuner")
  params:add_control("tuner_ref", "Tuner Reference",
    controlspec.new(420, 460, "lin", 0.1, 440.0, "Hz"))
  params:set_action("tuner_ref", function(v)
    tuner.ref_hz = v
    re()
  end)

  -- ── Metro ───────────────────────────────────────────────────────────
  params:add_separator("Metro")
  params:add_option("metro_enable", "Metro Enable", {"Bypass", "Active"}, 1)
  params:set_action("metro_enable", function(v)
    metro_active = (v == 2)
    if metro_active then
      metro_clock_start()
    else
      metro_clock_stop()
    end
    re()
  end)
  params:add_control("metro_bpm", "Metro BPM",
    controlspec.new(20, 300, "lin", 1, 120, ""))
  params:set_action("metro_bpm", function(_)
    if metro_active then metro_clock_start() end
    re()
  end)
  params:add_control("metro_level", "Metro Level",
    controlspec.new(0, 10, "lin", 0.1, 5.0, ""))
  params:set_action("metro_level", function(_) re() end)
  params:add_option("metro_pitch", "Metro Pitch", METRO_PITCH_NAMES, 37)
  params:set_action("metro_pitch", function(_) re() end)

  -- ── Pedals (Push / Distort / Warp / Repeat) ─────────────────────────
  local function register_pedal(ped)
    params:add_separator(ped.name)
    params:add_option(ped.enable_id, ped.name .. " Enable", {"Bypass", "Active"}, 1)
    params:set_action(ped.enable_id, function(v) engine[ped.bypass_cmd](2 - v); re() end)
    for _, p in ipairs(ped.params) do
      if p.options then
        params:add_option(p.id, ped.name .. " " .. p.name, p.options, p.default + 1)
        params:set_action(p.id, function(v) engine[p.id](v - 1); re() end)
      else
        params:add_control(p.id, ped.name .. " " .. p.name,
          controlspec.new(p.min, p.max, "lin", p.step, p.default, ""))
        params:set_action(p.id, function(v)
          engine[p.id](p.step == 1 and math.floor(v) or v); re()
        end)
      end
    end
  end

  for _, ped in ipairs(PEDALS) do register_pedal(ped) end

  -- ── Amp ─────────────────────────────────────────────────────────────
  params:add_separator("Amp")
  params:add_option("amp_enable", "Amp Enable", {"Bypass", "Active"}, 2)
  params:set_action("amp_enable", function(v)
    engine.amp_bypass(2 - v); re()
  end)
  params:add_control("amp_volume", "Amp Volume",
    controlspec.new(0, 10, "lin", 0.1, 7.5, ""))
  params:set_action("amp_volume", function(v) engine.amp_volume(v); re() end)
  params:add_control("amp_bass", "Amp Bass",
    controlspec.new(0, 10, "lin", 0.1, 5.0, ""))
  params:set_action("amp_bass",   function(v) engine.amp_bass(v);   re() end)
  params:add_control("amp_treble", "Amp Treble",
    controlspec.new(0, 10, "lin", 0.1, 5.0, ""))
  params:set_action("amp_treble", function(v) engine.amp_treble(v); re() end)
  params:add_control("amp_master", "Amp Master",
    controlspec.new(0, 10, "lin", 0.1, 5.0, ""))
  params:set_action("amp_master", function(v) engine.amp_master(v); re() end)

  -- ── Tremolo ─────────────────────────────────────────────────────────
  params:add_separator("Tremolo")
  params:add_option("tremolo_enable", "Tremolo Enable", {"Bypass", "Active"}, 2)
  params:set_action("tremolo_enable", function(v)
    engine.tremolo_intensity(v == 2 and params:get("tremolo_intensity") or 0)
    re()
  end)
  params:add_control("tremolo_speed", "Tremolo Speed",
    controlspec.new(0, 10, "lin", 0.1, 0.0, ""))
  params:set_action("tremolo_speed",     function(v) engine.tremolo_speed(v);     re() end)
  params:add_control("tremolo_intensity", "Tremolo Intensity",
    controlspec.new(0, 10, "lin", 0.1, 0.0, ""))
  params:set_action("tremolo_intensity", function(v)
    if params:get("tremolo_enable") == 2 then engine.tremolo_intensity(v) end
    re()
  end)

  -- ── Looper ──────────────────────────────────────────────────────────
  params:add_separator("Looper")
  params:add_option("looper_topology", "Looper Topology", {"BBD","Cassette","Digital","Tape"}, 3)
  params:set_action("looper_topology", function(v) engine.looper_topology(v - 1); re() end)
  params:add_control("looper_character", "Looper Character",
    controlspec.new(0, 10, "lin", 0.1, 0.0, ""))
  params:set_action("looper_character", function(v) engine.looper_character(v); re() end)
  params:add_option("looper_direction", "Looper Direction", {"Forward", "Reverse", "Pendulum", "Random"}, 1)
  params:set_action("looper_direction", function(v) engine.looper_direction(v - 1); re() end)
  params:add_control("looper_dub_level", "Looper Dub Level",
    controlspec.new(-40, 0, "lin", 0.5, -2.5, "dB"))
  params:set_action("looper_dub_level",  function(v) engine.looper_dub_level(db_to_lin(v));  re() end)
  params:add_control("looper_level", "Looper Level",
    controlspec.new(-40, 0, "lin", 0.5, -2.5, "dB"))
  params:set_action("looper_level", function(v) engine.looper_level(db_to_lin(v)); re() end)
  params:add_option("looper_speed", "Looper Speed", {"0.5x", "1x", "2x"}, 2)
  params:set_action("looper_speed", function(v) engine.looper_speed(v - 1); re() end)
  params:add_option("looper_dub_style", "Looper Dub Style", {"Regular", "Overwrite"}, 1)
  params:set_action("looper_dub_style", function(v) engine.looper_dub_style(v - 1); re() end)
  params:add_option("looper_play_from", "Looper Play From", {"Start", "Cue"}, 1)
  params:set_action("looper_play_from", function(v) engine.looper_play_from(v - 1); re() end)
  params:add_option("looper_transport", "Looper Transport", {"Rec·Play·Dub", "Rec·Dub·Play"}, 1)
  params:set_action("looper_transport", function(_) re() end)
  params:add_binary("looper_rec_play", "Looper Rec/Play", "trigger", 0)
  params:set_action("looper_rec_play", function(v)
    if v ~= 1 then return end
    looper_step()
  end)
  params:add_binary("looper_stop_clear", "Looper Stop/Clear", "trigger", 0)
  params:set_action("looper_stop_clear", function(v)
    if v ~= 1 then return end
    looper_stop_clear()
  end)

  -- ── Reverb ──────────────────────────────────────────────────────────
  params:add_separator("Reverb")
  params:add_option("reverb_enable", "Reverb Enable", {"Bypass", "Active"}, 2)
  params:set_action("reverb_enable", function(v)
    engine.reverb_mute(v == 2 and 0 or 1)
    re()
  end)
  params:add_control("reverb_amount", "Reverb Amount",
    controlspec.new(0, 10, "lin", 0.1, 2.5, ""))
  params:set_action("reverb_amount", function(v)
    engine.reverb_amount(v)
    re()
  end)

  -- ── Speaker & Mic ────────────────────────────────────────────────────
  params:add_separator("Speaker & Mic")
  params:add_option("speaker_enable", "Speaker Enable", {"Bypass", "Active"}, 2)
  params:set_action("speaker_enable", function(v)
    engine.speaker_bypass(2 - v); re()
  end)
  params:add_option("mic_position", "Mic Position", {"Center", "Middle", "Edge"}, 2)
  params:set_action("mic_position", function(v) engine.mic_position(v - 1); re() end)

  -- ── Pitch poll ──────────────────────────────────────────────────────
  tuner_pitch_poll = poll.set("pitch_in_l", function(freq)
    if not tuner.active then return end
    if freq and freq > 30 then
      local note, oct, _ = freq_to_note(freq)
      local c = cents_to_ref(freq, tuner.ref_hz)

      -- longer EMA window (~190 ms τ at 55 ms poll rate)
      tuner_cents_smooth = tuner_cents_smooth * 0.75 + c * 0.25
      -- hysteresis: only update displayed cents when change > 2
      if math.abs(math.floor(tuner_cents_smooth + 0.5) - tuner.cents) > 2 then
        tuner.cents = math.floor(tuner_cents_smooth + 0.5)
      end

      -- note hold: require TUNER_HOLD_FRAMES consistent frames before switching
      if note == tuner_note_candidate and oct == tuner_oct_candidate then
        tuner_note_hold = tuner_note_hold + 1
        if tuner_note_hold >= TUNER_HOLD_FRAMES then
          tuner.note   = tuner_note_candidate
          tuner.octave = tuner_oct_candidate
        end
      else
        tuner_note_candidate = note
        tuner_oct_candidate  = oct
        tuner_note_hold      = 1
      end
    else
      tuner.note          = "--"
      tuner.octave        = 0
      tuner.cents         = 0
      tuner_cents_smooth  = 0
      tuner_note_candidate = "--"
      tuner_oct_candidate  = 0
      tuner_note_hold      = 0
    end
    redraw()
  end)
  tuner_pitch_poll.time = 0.055

  params:bang()
  initing = false
  redraw()

  -- params:read fires after init() and may restore a saved monitor_level; defer wins.
  clock.run(function()
    clock.sleep(0.2)
    audio.level_monitor(0)
  end)
end
