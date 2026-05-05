-- princeton
--
-- Amp sim based on a combo.
-- Tuner, effects and looper.

engine.name = "Princeton"

local initing = true

local PARAMS_DEF = {
  { id="amp_volume",         name="Volume",    default=5.0,  min=0,    max=10, step=0.1, db=false, cat="Amp"     },
  { id="amp_bass",           name="Bass",      default=5.0,  min=0,   max=10, step=0.1, db=false, cat="Amp"     },
  { id="amp_treble",         name="Treble",    default=5.0,  min=0,   max=10, step=0.1, db=false, cat="Amp"     },
  { id="amp_master",         name="Master",    default=7.5,  min=0,   max=10, step=0.1, db=false, cat="Amp"     },
  { id="reverb_amount",     name="Amount",    default=25,   min=0,   max=100, step=1,  db=false, unit="%", cat="Reverb"  },
  { id="reverb_length",     name="Length",    default=2.5,  min=0.5, max=5.0, step=0.1, db=false, unit="s", cat="Reverb"  },
  { id="tremolo_speed",     name="Speed",     default=2.5,  min=0.1, max=25, step=0.1, db=false, unit="Hz", cat="Tremolo" },
  { id="tremolo_intensity", name="Intensity", default=0,    min=0,   max=100, step=1,  db=false, unit="%", cat="Tremolo" },
  { id="mic_position",            name="Position",     default=1,    min=0,   max=2,  step=1,   db=false, cat="Mic"     },
  { id="looper_medium",    name="Medium",    default=3,   min=1,  max=4,  step=1,   db=false, cat="Looper", options={"BBD","Cassette","Digital","Tape"} },
  { id="looper_wear",      name="Wear",      default=5,   min=0,  max=100, step=1, db=false, unit="%", cat="Looper"  },
  { id="looper_direction",      name="Direction", default=0,    min=0,   max=3,  step=1,   db=false, cat="Looper"  },
  { id="looper_dub_level",      name="Rec Level", default=-2.5, min=-40, max=0,  step=0.5, db=true,  cat="Looper"  },
  { id="looper_level",      name="Play Level",  default=-2.5, min=-40, max=0, step=0.5, db=true,  cat="Looper"  },
  { id="looper_fade_level", name="Fade Level",  default=-2.5, min=-40, max=0, step=0.5, db=true,  cat="Looper"  },
  { id="looper_speed",      name="Speed",       default=0,    min=-100, max=100, step=1, db=false, cat="Looper"  },
}
local MIC_NAMES  = { "Center", "Middle", "Edge" }
local DIR_NAMES  = { "Forward", "Reverse", "Pendulum", "Random" }

local NUM_KNOBS  = 8

local LOOP_SR  = 48000
local LOOP_MAX = LOOP_SR * 40

local sel = 1

local function amp_is_bypassed()
  return params:get("amp_enable") == 1
end

local function get_speed_value()
  if params:get("looper_speed_control") == 1 then
    local v = params:get("looper_speed")
    if v < 0 then return 0.5 elseif v > 0 then return 2.0 else return 1.0 end
  else
    local pct = params:get("looper_speed")
    return 2 ^ (pct / 100)
  end
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
      { id="push_mix",   name="Mix",   default=25, min=0, max=100, step=1, unit="%" },
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
      { id="warp_rate",  name="Rate",      default=2.5, min=0.1, max=25, step=0.1, unit="Hz", warp="exp" },
      { id="warp_depth", name="Depth",     default=5, min=0, max=100, step=1, unit="%" },
      { id="warp_rise",  name="Rise/Fall", default=2.5, min=0.01, max=5.0, step=0.01, unit="s", warp="exp" },
      { id="warp_mix",   name="Mix",       default=0,  min=0, max=100, step=1, unit="%" },
    },
    psel       = 1,
    bypass_cmd = "warp_bypass",
    enable_id  = "warp_enable",
  },
  {
    name       = "Repeat",
    display    = "Repeat",
    params     = {
      { id="repeat_time",           name="Time",      default=250, min=1, max=1000, step=1, unit="ms" },
      { id="repeat_feedback",       name="Feedback",  default=50, min=0, max=100, step=1, unit="%" },
      { id="repeat_level",          name="Level",     default=50, min=0, max=100, step=1, unit="%" },
      { id="repeat_characteristic", name="Color",     default=0,   min=0, max=1,  step=1, options={"Bright","Dark"} },
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

local loop_state       = LOOP_IDLE
local loop_rec_start   = 0
local loop_frames      = 0
local speed_steps_prev = 0

local tuner = {
  active  = false,
  muted   = false,
  ref_hz  = 440.0,
  note    = "--",
  octave  = 0,
  cents   = 0,
  arrow   = 0,
}
local tuner_cents_smooth    = 0
local tuner_note_candidate  = "--"
local tuner_oct_candidate   = 0
local tuner_note_hold       = 0
local tuner_lost_count      = 0
local TUNER_HOLD_FRAMES     = 3
local TUNER_LOST_FRAMES     = 27

local metro_active = false
local metro_clock  = nil

local k_clock = {}
local tuner_pitch_poll = nil

local sample_retrig_val = 0
local sample_done_clock = nil

local ir_l_path = ""
local ir_r_path = ""

local loop_quant_pending = false
local clock_running      = true
local SYNC_DIV_OPTS  = {"Off","1/1","1/2","1/4","1/8","1/16","1/32","1/64"}
local SYNC_DIV_BEATS = {0, 4, 2, 1, 0.5, 0.25, 0.125, 0.0625}
local SYNC_FEEL_OPTS = {"Note","Dotted","Triplet"}
local SYNC_FEEL_MULT  = {1.0, 1.5, 2.0/3.0}
local METRO_DIV_OPTS  = {"1/1","1/2","1/4","1/8","1/16"}
local METRO_DIV_BEATS = {4, 2, 1, 0.5, 0.25}
local SYNC_PARAM_MAP = {
  tremolo_speed = {div = "tremolo_sync_div", feel = "tremolo_sync_feel",
                   value_fn = function(hz) return util.clamp(hz, 0.1, 20.0) end},
  warp_rate     = {div = "warp_sync_div",    feel = "warp_sync_feel",
                   value_fn = function(hz) return util.clamp(hz, 0.1, 20.0) end},
  repeat_time   = {div = "repeat_sync_div",  feel = "repeat_sync_feel",
                   value_fn = function(hz) return util.clamp(1000.0 / hz, 1, 1000) end},
}

local B = { DIM=0, GHOST=5, MED=6, FULL=15 }

local CAB_W, CAB_H = 82, 56
local CAB = {
  x = 45,
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
-- Panel layout: [1 gap][B1][1 gap][B2][1 gap][8 knobs @ 6px][logo 17px][1 gap][lamp][1 gap]
local PANEL_BUCHSE1 = PANEL.x
local PANEL_BUCHSE2 = PANEL.x + 2
local PANEL_LAMP    = PANEL.x + PANEL.w - 2
local KNOB_SPACING  = 6
local KNOB_START    = PANEL.x + 5
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

local function ir_short_name(path)
  if not path or path == "" then return "No IR > Bypass" end
  local name = path:match("([^/]+)$") or path
  name = name:gsub("%.wav$", "")
  if #name > 10 then name = "..." .. name:sub(-10) end
  return name
end

local function sync_hz_df(bpm, div_opt, feel_opt)
  if div_opt <= 1 then return nil end
  local beats = SYNC_DIV_BEATS[div_opt] * SYNC_FEEL_MULT[feel_opt]
  return bpm / (beats * 60.0)
end

local function sync_in_range(id, hz)
  if id == "tremolo_speed" then return hz >= 0.1  and hz <= 25.0 end
  if id == "warp_rate"     then return hz >= 0.1  and hz <= 25.0 end
  if id == "repeat_time"   then return (1.0/hz) >= 0.001 and (1.0/hz) <= 1.0  end
  return true
end

local function sync_val_level(id)
  local m = SYNC_PARAM_MAP[id]
  if not m or not clock_running then return B.FULL end
  local div_opt = params:get(m.div)
  if div_opt <= 1 then return B.FULL end
  local hz = sync_hz_df(clock.get_tempo(), div_opt, params:get(m.feel))
  return (hz and sync_in_range(id, hz)) and B.FULL or B.MED
end

local function sync_fmt(p_id)
  if not clock_running then return nil end
  local m = SYNC_PARAM_MAP[p_id]
  if not m then return nil end
  local div_opt = params:get(m.div)
  if div_opt <= 1 then return nil end
  local s = SYNC_DIV_OPTS[div_opt]
  local f = params:get(m.feel)
  if f == 2 then return s .. "." end
  if f == 3 then return s .. "T" end
  return s
end

local function sync_push_all()
  if initing then return end
  local bpm = clock.get_tempo()
  for id, m in pairs(SYNC_PARAM_MAP) do
    local div = params:get(m.div)
    if clock_running and div > 1 then
      engine[id](m.value_fn(sync_hz_df(bpm, div, params:get(m.feel))))
    else
      engine[id](params:get(id))
    end
  end
end

local function sync_activate_defaults()
  if params:get("tremolo_sync_div") <= 1 then params:set("tremolo_sync_div", 4) end
  if params:get("warp_sync_div")    <= 1 then params:set("warp_sync_div",    4) end
  if params:get("repeat_sync_div")  <= 1 then params:set("repeat_sync_div",  4) end
  if params:get("looper_quant_div") <= 1 then params:set("looper_quant_div", 4) end
end

local function looper_quantize_then(fn)
  local div_opt = params:get("looper_quant_div")
  if not clock_running or div_opt <= 1 then fn(); return end
  local beats = SYNC_DIV_BEATS[div_opt] * SYNC_FEEL_MULT[params:get("looper_quant_feel")]
  clock.run(function()
    clock.sync(beats)
    fn()
  end)
end

local function fmt_val(idx)
  local id = PARAMS_DEF[idx].id
  local v  = params:get(id)
  if PARAMS_DEF[idx].options then return PARAMS_DEF[idx].options[v] end
  if id == "mic_position"     then return MIC_NAMES[v] end
  if id == "looper_direction" then return DIR_NAMES[v] end
  if id == "looper_speed" then
    if params:get("looper_speed_control") == 1 then
      if v < 0 then return "-100%" elseif v > 0 then return "+100%" else return "+0%" end
    else
      return string.format("%+d%%", math.floor(v))
    end
  end
  local s = sync_fmt(id)
  if s then return s end
  if PARAMS_DEF[idx].db   then return string.format("%.1fdB", v) end
  if PARAMS_DEF[idx].unit then
    local s = PARAMS_DEF[idx].step
    return s < 1 and string.format("%.1f%s", v, PARAMS_DEF[idx].unit) or string.format("%d%s", math.floor(v), PARAMS_DEF[idx].unit)
  end
  return string.format("%.1f", v)
end

local function snap_val(v, step)
  if step == 1 then return math.floor(v + 0.5)
  else return math.floor(v * 10 + 0.5) / 10 end
end

local function loop_set_engine(st)
  engine.loop_rec (st == LOOP_REC  and 1 or 0)
  engine.loop_dub (st == LOOP_DUB  and 1 or 0)
  engine.loop_play((st == LOOP_PLAY or st == LOOP_DUB) and 1 or 0)
end

local function sample_oneshot_start()
  if sample_done_clock then clock.cancel(sample_done_clock) end
  local speed_mult = get_speed_value()
  local passes     = params:get("looper_direction") == 3 and 2 or 1
  local duration   = loop_frames / LOOP_SR / speed_mult * passes
  sample_done_clock = clock.run(function()
    clock.sleep(duration)
    if loop_state == LOOP_PLAY and params:get("looper_dub_style") == 3 then
      loop_state = LOOP_STOP
      loop_set_engine(LOOP_STOP)
      redraw()
    end
    sample_done_clock = nil
  end)
end

local function looper_step()
  if loop_state == LOOP_IDLE then
    if loop_quant_pending then return end
    loop_quant_pending = true
    looper_quantize_then(function()
      if not loop_quant_pending then return end
      loop_quant_pending = false
      engine.loop_frames(LOOP_MAX)
      loop_rec_start = util.time()
      loop_state = LOOP_REC
      loop_set_engine(LOOP_REC)
      redraw()
    end)
    redraw()
  elseif loop_state == LOOP_REC then
    if loop_quant_pending then return end
    loop_quant_pending = true
    looper_quantize_then(function()
      loop_quant_pending = false
      local elapsed    = util.time() - loop_rec_start
      local speed_mult = get_speed_value()
      loop_frames      = math.max(math.min(math.floor(elapsed * LOOP_SR * speed_mult), LOOP_MAX), 2)
      engine.loop_frames(loop_frames)
      if params:get("looper_dub_style") == 3 then
        loop_state = LOOP_STOP
        loop_set_engine(LOOP_STOP)
      else
        local next = params:get("looper_transport") == 2 and LOOP_DUB or LOOP_PLAY
        loop_state = next
        loop_set_engine(next)
      end
      redraw()
    end)
  elseif loop_state == LOOP_PLAY then
    if params:get("looper_dub_style") == 3 then
      sample_retrig_val = 1 - sample_retrig_val
      engine.loop_sample_retrig(sample_retrig_val)
      sample_oneshot_start()
      redraw()
    else
      loop_state = LOOP_DUB
      loop_set_engine(LOOP_DUB)
      redraw()
    end
  elseif loop_state == LOOP_DUB then
    looper_quantize_then(function()
      loop_state = LOOP_PLAY
      loop_set_engine(LOOP_PLAY)
      redraw()
    end)
  elseif loop_state == LOOP_STOP then
    loop_state = LOOP_PLAY
    loop_set_engine(LOOP_PLAY)
    if params:get("looper_dub_style") == 3 then
      if params:get("looper_play_from") == 2 then
        sample_retrig_val = 1 - sample_retrig_val
        engine.loop_sample_retrig(sample_retrig_val)
      end
      sample_oneshot_start()
    end
    redraw()
  end
end

local function looper_stop_clear()
  if loop_state == LOOP_IDLE then
    loop_quant_pending = false
    return
  elseif loop_state == LOOP_REC then
    loop_quant_pending = false
    loop_state  = LOOP_IDLE
    loop_frames = 0
    engine.loop_clear()
    redraw()
  elseif loop_state == LOOP_DUB then
    looper_quantize_then(function()
      loop_state = LOOP_STOP
      loop_set_engine(LOOP_STOP)
      redraw()
    end)
  elseif loop_state == LOOP_STOP then
    loop_state  = LOOP_IDLE
    loop_frames = 0
    engine.loop_clear()
    redraw()
  elseif loop_state ~= LOOP_IDLE then
    if sample_done_clock then clock.cancel(sample_done_clock); sample_done_clock = nil end
    looper_quantize_then(function()
      loop_state = LOOP_STOP
      loop_set_engine(LOOP_STOP)
      redraw()
    end)
  end
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

local function round_sym(x)
  if x >= 0 then return math.floor(x + 0.5)
  else return -math.floor(-x + 0.5) end
end

local function rect_outline(x, y, w, h, lv)
  screen.level(lv)
  screen.line_width(1)
  screen.rect(x, y, w, h)
  screen.stroke()
end

local function draw_icon_filled_circle(cx, y)
  screen.rect(cx - 5, y - 2, 10, 4)
  screen.rect(cx - 2, y - 5, 4, 10)
  screen.rect(cx - 4, y - 4, 2, 2)
  screen.rect(cx + 2, y - 4, 2, 2)
  screen.rect(cx - 4, y + 2, 2, 2)
  screen.rect(cx + 2, y + 2, 2, 2)
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

local function draw_strip(cat, name, val_str, val_lv)
  val_lv = val_lv or B.FULL
  screen.level(B.DIM); screen.rect(0, 0, LEFT_W, 64); screen.fill()
  screen.font_size(8); screen.font_face(0)
  screen.level(B.MED);  screen.move(LEFT_CX, 16); screen.text_center(cat)
  screen.level(B.MED);  screen.move(LEFT_CX, 25); screen.text_center(name)
  screen.level(val_lv); screen.move(LEFT_CX, 34); screen.text_center(val_str)
end

local function draw_left_strip()
  local cm = params:get("cab_mode")
  if PARAMS_DEF[sel] and PARAMS_DEF[sel].id == "mic_position" and cm == 1 then
    screen.level(B.DIM); screen.rect(0, 0, LEFT_W, 64); screen.fill()
    screen.font_size(8); screen.font_face(0)
    screen.level(B.MED)
    screen.move(LEFT_CX, 16); screen.text_center("Cab & Mic")
    screen.move(LEFT_CX, 25); screen.text_center("Simulation")
    screen.move(LEFT_CX, 34); screen.text_center("Bypass")
  elseif PARAMS_DEF[sel] and PARAMS_DEF[sel].id == "mic_position" and cm == 3 then
    screen.level(B.DIM); screen.rect(0, 0, LEFT_W, 64); screen.fill()
    screen.font_size(8); screen.font_face(0)
    screen.level(B.GHOST); screen.move(LEFT_CX, 16); screen.text_center("IR")
  else
    draw_strip(PARAMS_DEF[sel].cat, PARAMS_DEF[sel].name, fmt_val(sel), sync_val_level(PARAMS_DEF[sel].id))
  end

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
  screen.level(B.DIM); screen.rect(PANEL.x, PANEL.y, PANEL.w, PANEL.h); screen.fill()

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
  local cm       = params:get("cab_mode")
  local mic_cat  = PARAMS_DEF[sel] and PARAMS_DEF[sel].id == "mic_position"

  if not mic_cat then
    screen.line_width(1)
    local y = gy
    while y <= gy + gh do
      screen.level(B.MED)
      screen.move(gx, y); screen.line(gx + gw, y); screen.stroke()
      y = y + 2
    end
    local x = gx
    while x <= gx + gw do
      screen.level(B.MED)
      screen.move(x, gy); screen.line(x, gy + gh); screen.stroke()
      x = x + 4
    end
    return
  end

  screen.level(B.DIM); screen.rect(gx, gy, gw, gh); screen.fill()
  local cx = math.floor(gx + gw / 2 + 0.5)
  local cy = math.floor(gy + gh / 2 + 0.5)

  if cm == 2 then
    screen.level(B.MED); screen.line_width(1)
    screen.circle(cx, cy, 16); screen.stroke()
    screen.level(B.DIM)
    screen.circle(cx, cy, 11); screen.stroke()
    screen.level(B.MED)
    screen.circle(cx, cy, 5); screen.stroke()
    local mic_val   = params:get("mic_position") - 1
    local x_offsets = { 0, 8, 14 }
    for i = 1, 3 do
      draw_speaker_x(cx + x_offsets[i], cy, (i - 1 == mic_val) and B.FULL or B.DIM)
    end
  elseif cm == 3 then
    screen.font_size(8); screen.font_face(0)
    screen.level(B.MED)
    screen.move(cx, cy - 4); screen.text_center(ir_short_name(ir_l_path))
    screen.move(cx, cy + 6); screen.text_center(ir_short_name(ir_r_path))
  else
    screen.level(B.MED); screen.line_width(1)
    screen.move(cx - 5, cy - 5); screen.line(cx + 5, cy + 5); screen.stroke()
    screen.move(cx + 5, cy - 5); screen.line(cx - 5, cy + 5); screen.stroke()
  end
end

local function draw_tuner()
  screen.level(B.DIM); screen.rect(0, 0, 128, 64); screen.fill()

  local cx = 64

  screen.font_size(24); screen.font_face(0)
  screen.level(tuner.muted and B.MED or B.FULL)
  screen.move(cx, 36)
  screen.text_center(tuner.note)

  if tuner.note ~= "--" then
    screen.font_size(8); screen.level(B.FULL)
    screen.move(cx + 15, 19)
    screen.text(tostring(tuner.octave))

    screen.level(B.FULL)
    if tuner.arrow == 0 then
      screen.circle(cx, 50, 2); screen.fill()
    elseif tuner.arrow < 0 then
      screen.move(18, 50)
      screen.line(10, 46); screen.line(10, 54)
      screen.fill()
    else
      screen.move(110, 50)
      screen.line(118, 46); screen.line(118, 54)
      screen.fill()
    end
  end

  screen.font_size(8)
  screen.level(B.GHOST);  screen.move(38, 61); screen.text("A = ")
  screen.level(B.FULL); screen.text(string.format("%.1f Hz", tuner.ref_hz))

  if tuner.muted then
    screen.font_size(8); screen.level(B.MED)
    screen.move(126, 8); screen.text_right("mute")
  end
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

  local pd  = cur_pedal()
  local p   = pd.params[pd.psel]
  local v    = params:get(p.id)
  local vstr = sync_fmt(p.id)
  if not vstr then
    if p.options then vstr = p.options[v]
    elseif p.unit then
      vstr = p.step < 1 and string.format("%.1f%s", v, p.unit) or string.format("%d%s", math.floor(v), p.unit)
    else vstr = string.format("%.1f", v) end
  end
  draw_strip(pd.name, p.name, vstr, sync_val_level(p.id))

  -- ── Two pedals, snapped to CAB edges ────────────────────────────
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
  local semitones = params:get("metro_pitch") - 1 - 57
  engine.metro_tick(params:get("metro_level") / 10.0, semitones)
end

local function metro_clock_start()
  if metro_clock then clock.cancel(metro_clock) end
  metro_clock = clock.run(function()
    if clock_running then
      local beats = METRO_DIV_BEATS[params:get("metro_div")]
      clock.sync(beats)
      while true do
        metro_tick_now()
        clock.sync(beats)
      end
    else
      while true do
        metro_tick_now()
        clock.sleep(60.0 / (tonumber(params:get("metro_bpm")) or 120))
      end
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
  tuner.arrow          = 0
  tuner_cents_smooth   = 0
  tuner_note_candidate = "--"
  tuner_oct_candidate  = 0
  tuner_note_hold      = 0
  tuner_lost_count     = 0
  engine.mute(0)
  tuner_pitch_poll:start()
  redraw()
end

local function tuner_stop()
  tuner.active = false
  tuner_pitch_poll:stop()
  engine.mute(0)
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
      local m  = SYNC_PARAM_MAP[p.id]
      if m and params:get(m.div) > 1 then
        params:set(m.div, util.clamp(params:get(m.div) + (d > 0 and 1 or -1), 2, #SYNC_DIV_OPTS))
      else
        params:set(p.id, snap_val(params:get(p.id) + d * p.step, p.step))
      end
    end
    return
  end
  if tuner.active then
    if n == 3 then
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
    local m = SYNC_PARAM_MAP[p.id]
    if m and params:get(m.div) > 1 then
      params:set(m.div, util.clamp(params:get(m.div) + (d > 0 and 1 or -1), 2, #SYNC_DIV_OPTS))
    else
      params:set(p.id, snap_val(params:get(p.id) + d * p.step, p.step))
    end
  end
end

local function long_press(key, z, fn_long, fn_short)
  if z == 1 then
    k_clock[key] = clock.run(function()
      clock.sleep(2.0)
      k_clock[key] = nil
      fn_long()
    end)
  else
    if k_clock[key] ~= nil then
      clock.cancel(k_clock[key])
      k_clock[key] = nil
      if fn_short then fn_short() end
    end
  end
end

function key(n, z)
  if n == 1 then
    long_press("k1", z, function()
      if tuner.active then tuner_stop() else pedal_active = false; tuner_start() end
    end)
    return
  end

  if n == 2 then
    long_press("k2", z, function()
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
    end, function()
      if tuner.active or pedal_active then return end
      looper_step()
    end)
    return
  end

  if n == 3 then
    if tuner.active then
      long_press("k3", z, function()
        tuner_stop()
        pedal_active = true
        pedal_sel = 3
        redraw()
      end, function()
        tuner.muted = not tuner.muted
        engine.mute(tuner.muted and 1 or 0)
        redraw()
      end)
      return
    end

    if pedal_active then
      long_press("k3", z, function()
        if pedal_sel >= 3 then
          pedal_active = false
        else
          pedal_active = true
          pedal_sel = 3
        end
        redraw()
      end, function()
        local pd  = cur_pedal()
        local cur = params:get(pd.enable_id)
        params:set(pd.enable_id, 3 - cur)
      end)
      return
    end

    long_press("k3", z, function()
      pedal_sel = 3; pedal_active = true
      redraw()
    end, function()
      looper_stop_clear()
    end)
    return
  end
end


function init()
  audio.level_monitor(0)
  local function re() if not initing then redraw() end end

  local function add_p_params(ped)
    for _, p in ipairs(ped.params) do
      if p.options then
        params:add_option(p.id, p.name, p.options, p.default + 1)
        params:set_action(p.id, function(v) engine[p.id](v - 1); re() end)
      else
        params:add_control(p.id, p.name, controlspec.new(p.min, p.max, p.warp or "lin", p.step, p.default, p.unit or ""))
        params:set_action(p.id, function(v) engine[p.id](p.step == 1 and math.floor(v) or v); re() end)
      end
    end
  end

  local function sync_df_action()
    return function(_) if not initing then sync_push_all() end; re() end
  end

  local function db_action(name)
    return function(v) engine[name](db_to_lin(v)); re() end
  end

  local function add_sync_params(prefix)
    params:add_separator(prefix .. "_sep_sync", "─── Synchronization ───")
    params:add_option(prefix .. "_sync_div", "Synchronization", SYNC_DIV_OPTS, 4)
    params:set_action(prefix .. "_sync_div", sync_df_action())
    params:add_option(prefix .. "_sync_feel", "Synchronization Feel", SYNC_FEEL_OPTS, 1)
    params:set_action(prefix .. "_sync_feel", sync_df_action())
  end

  local function setup_pedal(idx)
    local ped = PEDALS[idx]
    local prefix = ped.name:lower()
    local has_sync = false
    for _, p in ipairs(ped.params) do
      if SYNC_PARAM_MAP[p.id] then has_sync = true; break end
    end
    params:add_group(ped.name:upper(), 6 + (has_sync and 3 or 0))
    params:add_separator(prefix .. "_sep_control", "─── Control ───")
    params:add_option(ped.enable_id, "Enable", {"Bypass", "Active"}, 1)
    params:set_action(ped.enable_id, function(v) engine[ped.bypass_cmd](2 - v); re() end)
    add_p_params(ped)
    if has_sync then add_sync_params(prefix) end
  end

  local function setup_amp()
    params:add_group("AMP", 6)
    params:add_separator("amp_sep_control", "─── Control ───")
    params:add_option("amp_enable", "Enable", {"Bypass", "Active"}, 2)
    params:set_action("amp_enable", function(v) engine.amp_bypass(2 - v); re() end)
    params:add_control("amp_volume", "Volume", controlspec.new(0, 10, "lin", 0.1, 5.0, ""))
    params:set_action("amp_volume", function(v) engine.amp_volume(v); re() end)
    params:add_control("amp_bass", "Bass", controlspec.new(0, 10, "lin", 0.1, 5.0, ""))
    params:set_action("amp_bass", function(v) engine.amp_bass(v); re() end)
    params:add_control("amp_treble", "Treble", controlspec.new(0, 10, "lin", 0.1, 5.0, ""))
    params:set_action("amp_treble", function(v) engine.amp_treble(v); re() end)
    params:add_control("amp_master", "Master", controlspec.new(0, 10, "lin", 0.1, 7.5, ""))
    params:set_action("amp_master", function(v) engine.amp_master(v); re() end)
  end

  local function setup_tremolo()
    params:add_group("TREMOLO", 7)
    params:add_separator("tremolo_sep_control", "─── Control ───")
    params:add_option("tremolo_enable", "Enable", {"Bypass", "Active"}, 2)
    params:set_action("tremolo_enable", function(v) engine.tremolo_intensity(v == 2 and params:get("tremolo_intensity") or 0); re() end)
    params:add_control("tremolo_speed", "Speed", controlspec.new(0.1, 25, "exp", 0, 2.5, "Hz"))
    params:set_action("tremolo_speed", function(v) engine.tremolo_speed(v); re() end)
    params:add_control("tremolo_intensity", "Intensity", controlspec.new(0, 100, "lin", 1, 0, "%"))
    params:set_action("tremolo_intensity", function(v) if params:get("tremolo_enable") == 2 then engine.tremolo_intensity(v) end; re() end)
    add_sync_params("tremolo")
  end

  local function setup_looper()
    params:add_group("LOOPER", 24)
    params:add_separator("looper_sep_control", "─── Control ───")
    params:add_option("looper_transport", "Step Order", {"Rec·Play·Dub", "Rec·Dub·Play"}, 1)
    params:add_option("looper_play_from", "Play From", {"Start", "Cue"}, 1)
    params:set_action("looper_play_from", function(v) engine.looper_play_from(v - 1); re() end)
    params:add_option("looper_dub_style", "Mode", {"Overdub", "Overwrite", "Sample", "Resample"}, 1)
    params:set_action("looper_dub_style", function(v) engine.looper_dub_style(v - 1); re() end)
    params:add_option("looper_direction", "Direction", {"Forward", "Reverse", "Pendulum", "Random"}, 1)
    params:set_action("looper_direction", function(v) engine.looper_direction(v - 1); re() end)
    params:add_control("looper_dub_level", "Rec Level", controlspec.new(-40, 0, "lin", 0.5, -2.5, "dB"))
    params:set_action("looper_dub_level", db_action("looper_dub_level"))
    params:add_control("looper_level", "Play Level", controlspec.new(-40, 0, "lin", 0.5, -2.5, "dB"))
    params:set_action("looper_level", db_action("looper_level"))
    params:add_control("looper_fade_level", "Fade Level", controlspec.new(-40, 0, "lin", 0.5, -2.5, "dB"))
    params:set_action("looper_fade_level", db_action("looper_fade_level"))
    params:add{type="number", id="looper_speed", name="Speed", min=-100, max=100, default=0, formatter=function(p) return p:get() .. "%" end, action=function(v)
      if params:get("looper_speed_control") == 1 then
        local snapped
        if     v > speed_steps_prev then snapped = v > 0 and 100 or 0
        elseif v < speed_steps_prev then snapped = v < 0 and -100 or 0
        else                             snapped = speed_steps_prev end
        speed_steps_prev = snapped
        if v ~= snapped then params:set("looper_speed", snapped); return end
      else
        speed_steps_prev = v
      end
      engine.looper_speed(get_speed_value()); re()
    end}
    params:add_option("looper_speed_control", "Speed Control", {"Steps","Smooth"}, 1)

    params:add_separator("looper_sep_medium", "─── Medium ───")
    params:add_option("looper_medium", "Medium", {"BBD","Cassette","Digital","Tape"}, 3)
    params:set_action("looper_medium", function(v) engine.looper_medium(v - 1); re() end)
    params:add_control("looper_imprint", "Imprint", controlspec.new(0, 100, "lin", 1, 50, "%"))
    params:set_action("looper_imprint", function(v) engine.looper_imprint(v); re() end)
    params:add_control("looper_wear", "Wear", controlspec.new(0, 100, "lin", 1, 5, "%"))
    params:set_action("looper_wear", function(v) engine.looper_wear(v); re() end)
    params:add_option("looper_bbd_tone", "M: BBD Tone", {"Bright", "Dark"}, 1)
    params:set_action("looper_bbd_tone", function(v) engine.looper_bbd_tone(v - 1) end)
    params:add_control("looper_cas_wow", "M: Cassette Wow", controlspec.new(0, 100, "lin", 1, 5, "%"))
    params:set_action("looper_cas_wow", function(v) engine.looper_wow_cas(v) end)
    params:add_control("looper_dig_glitch", "M: Digital Glitch", controlspec.new(0, 100, "lin", 1, 0, "%"))
    params:set_action("looper_dig_glitch", function(v) engine.looper_dig_glitch(v) end)
    params:add_control("looper_tape_wow", "M: Tape Wow", controlspec.new(0, 100, "lin", 1, 5, "%"))
    params:set_action("looper_tape_wow", function(v) engine.looper_wow_tape(v) end)

    params:add_separator("looper_sep_sync", "─── Quantization ───")
    params:add_option("looper_quant_div", "Quantization", SYNC_DIV_OPTS, 1)
    params:add_option("looper_quant_feel", "Quantization Feel", SYNC_FEEL_OPTS, 1)

    params:add_separator("looper_sep_trigger", "─── Trigger ───")
    params:add_binary("looper_rec_play", "Rec/Play", "trigger", 0)
    params:set_action("looper_rec_play", function(v) if v == 1 then looper_step() end end)
    params:add_binary("looper_stop_clear", "Stop/Clear", "trigger", 0)
    params:set_action("looper_stop_clear", function(v) if v == 1 then looper_stop_clear() end end)
  end

  local function setup_reverb()
    params:add_group("REVERB", 6)
    params:add_separator("reverb_sep_control", "─── Control ───")
    params:add_option("reverb_enable", "Enable", {"Bypass", "Active"}, 2)
    params:set_action("reverb_enable", function(v) engine.reverb_mute(v == 2 and 0 or 1); re() end)
    params:add_control("reverb_amount", "Amount", controlspec.new(0, 100, "lin", 1, 25, "%"))
    params:set_action("reverb_amount", function(v) engine.reverb_amount(v); re() end)
    params:add_control("reverb_length", "Length", controlspec.new(0.5, 5.0, "lin", 0.1, 2.5, "s"))
    params:set_action("reverb_length", function(v) engine.reverb_length(v); re() end)
    params:add_control("reverb_low_shelf", "Low Shelf", controlspec.new(-5, 5, "lin", 0.5, 0, "dB"))
    params:set_action("reverb_low_shelf", function(v) engine.reverb_low_shelf(v); re() end)
    params:add_control("reverb_high_shelf", "High Shelf", controlspec.new(-5, 5, "lin", 0.5, 0, "dB"))
    params:set_action("reverb_high_shelf", function(v) engine.reverb_high_shelf(v); re() end)
  end

  local CAB_MODE_ALL = {"mic_position", "cab_level", "ir_l", "ir_r", "ir_level_l", "ir_level_r"}
  local CAB_MODE_VISIBLE = {
    [1] = {},
    [2] = {mic_position=true, cab_level=true},
    [3] = {ir_l=true, ir_r=true, ir_level_l=true, ir_level_r=true},
  }

  local function setup_cab()
    params:add_group("CAB & MIC", 8)
    params:add_separator("cab_sep_control", "─── Control ───")
    params:add_option("cab_mode", "Mode", {"Bypass", "Cab & Mic Sim", "IR"}, 2)
    params:set_action("cab_mode", function(v)
      engine.cab_mode(v - 1)
      for _, p in ipairs(CAB_MODE_ALL) do
        if CAB_MODE_VISIBLE[v][p] then params:show(p) else params:hide(p) end
      end
      if _menu and _menu.rebuild_params then _menu.rebuild_params() end
      re()
    end)
    params:add_option("mic_position", "Mic Position", {"Center", "Middle", "Edge"}, 2)
    params:set_action("mic_position", function(v) engine.mic_position(v - 1); re() end)
    params:add_control("cab_level", "Cab Level", controlspec.new(-10, 10, "lin", 0.5, 0, "dB"))
    params:set_action("cab_level", db_action("cab_level"))
    params:add_file("ir_l", "IR L", "")
    do
      local p = params:lookup_param("ir_l")
      function p:string() return ir_short_name(self.path or "") end
    end
    params:set_action("ir_l", function(path)
      ir_l_path = path
      if path and path ~= "" then engine.load_ir_l(path) end
      re()
    end)
    params:add_file("ir_r", "IR R", "")
    do
      local p = params:lookup_param("ir_r")
      function p:string() return ir_short_name(self.path or "") end
    end
    params:set_action("ir_r", function(path)
      ir_r_path = path
      if path and path ~= "" then engine.load_ir_r(path) end
      re()
    end)
    params:add_control("ir_level_l", "IR Level L", controlspec.new(-40, 0, "lin", 0.5, -10, "dB"))
    params:set_action("ir_level_l", db_action("ir_level_l"))
    params:add_control("ir_level_r", "IR Level R", controlspec.new(-40, 0, "lin", 0.5, -10, "dB"))
    params:set_action("ir_level_r", db_action("ir_level_r"))
  end

  local function setup_limit()
    params:add_group("LIMIT", 7)
    params:add_separator("limit_sep_control", "─── Control ───")
    params:add_option("limit_enable", "Enable", {"Bypass", "Active"}, 1)
    params:set_action("limit_enable", function(v) engine.limit_bypass(2 - v); re() end)
    params:add_control("limit_threshold", "Threshold", controlspec.new(-40, 0, "lin", 0.5, -10, "dB"))
    params:set_action("limit_threshold", db_action("limit_threshold"))
    params:add_control("limit_ratio", "Ratio", controlspec.new(2.0, 20.0, "lin", 0.5, 4.0, ":1"))
    params:set_action("limit_ratio", function(v) engine.limit_ratio(v); re() end)
    params:add_control("limit_gain", "Gain", controlspec.new(-20, 20, "lin", 0.5, 0, "dB"))
    params:set_action("limit_gain", db_action("limit_gain"))
    params:add_control("limit_attack", "Attack", controlspec.new(1, 100, "lin", 1, 10, "ms"))
    params:set_action("limit_attack", function(v) engine.limit_attack(v); re() end)
    params:add_control("limit_decay", "Decay", controlspec.new(50, 2000, "lin", 50, 50, "ms"))
    params:set_action("limit_decay", function(v) engine.limit_decay(v); re() end)
  end

  local function setup_metro()
    params:add_group("METRO", 6)
    params:add_separator("metro_sep_control", "─── Control ───")
    params:add_option("metro_enable", "Enable", {"Off", "On"}, 1)
    params:set_action("metro_enable", function(v) metro_active = (v == 2); if metro_active then metro_clock_start() else metro_clock_stop() end; re() end)
    params:add_text("metro_bpm", "BPM", "120")
    params:add_option("metro_div", "Division", METRO_DIV_OPTS, 3)
    params:set_action("metro_div", function(_) if metro_active then metro_clock_start() end end)
    params:add_control("metro_level", "Level", controlspec.new(0, 10, "lin", 0.1, 5.0, ""))
    params:add_option("metro_pitch", "Pitch", METRO_PITCH_NAMES, 37)
  end

  local function setup_tuner()
    params:add_group("TUNER", 2)
    params:add_separator("tuner_sep_control", "─── Control ───")
    params:add_control("tuner_ref", "Reference", controlspec.new(420, 460, "lin", 0.1, 440.0, "Hz"))
    params:set_action("tuner_ref", function(v) tuner.ref_hz = v; re() end)
  end

  local function setup_pitch_poll()
    tuner_pitch_poll = poll.set("tuner_pitch", function(freq)
      if not tuner.active then return end
      if freq and freq > 30 then
        tuner_lost_count = 0
        local note, oct, _ = freq_to_note(freq)
        local c = cents_to_ref(freq, tuner.ref_hz)

        tuner_cents_smooth = tuner_cents_smooth * 0.75 + c * 0.25
        tuner.cents = round_sym(tuner_cents_smooth)

        local abs = math.abs(tuner.cents)
        if abs < 5 then
          tuner.arrow = 0
        elseif abs > 8 then
          tuner.arrow = tuner.cents < 0 and -1 or 1
        end

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
        tuner_lost_count = tuner_lost_count + 1
        if tuner_lost_count >= TUNER_LOST_FRAMES then
          tuner.note          = "--"
          tuner.octave        = 0
          tuner.cents         = 0
          tuner.arrow         = 0
          tuner_cents_smooth  = 0
          tuner_note_candidate = "--"
          tuner_oct_candidate  = 0
          tuner_note_hold      = 0
        end
      end
      redraw()
    end)
    tuner_pitch_poll.time = 0.055
  end

  local function setup_clock_watchers()
    clock.run(function()
      clock.sleep(1.0)
      params:set("tremolo_sync_div", 1)
      params:set("warp_sync_div", 1)
      params:set("repeat_sync_div", 1)
      params:set("looper_quant_div", 1)
    end)

    clock.transport.start = function()
      clock_running = true
      sync_activate_defaults()
      if metro_active then metro_clock_start() end
      sync_push_all()
      redraw()
    end

    clock.transport.stop = function()
      clock_running = false
      if metro_active then metro_clock_start() end
      sync_push_all()
      redraw()
    end

    clock.run(function()
      local last_source = nil
      while true do
        clock.sleep(0.5)
        local current_source = nil
        pcall(function()
          current_source = params:get("clock_source")
        end)
        if current_source and current_source ~= last_source then
          if current_source == 2 then
            params:set("tremolo_sync_div", 4)
            params:set("warp_sync_div", 4)
            params:set("repeat_sync_div", 4)
            params:set("looper_quant_div", 4)
          else
            params:set("tremolo_sync_div", 1)
            params:set("warp_sync_div", 1)
            params:set("repeat_sync_div", 1)
            params:set("looper_quant_div", 1)
          end
          last_source = current_source
        end
      end
    end)

    clock.run(function()
      local last_bpm = 0
      while true do
        clock.sleep(0.5)
        local bpm = math.floor(clock.get_tempo() + 0.5)
        if bpm ~= last_bpm then
          if last_bpm == 0 and bpm > 0 then
            clock_running = true
            sync_activate_defaults()
            if metro_active then metro_clock_start() end
          elseif bpm == 0 and last_bpm > 0 then
            clock_running = false
            if metro_active then metro_clock_start() end
          end
          last_bpm = bpm
          sync_push_all()
          redraw()
        end
        if bpm > 0 and params:get("metro_bpm") ~= tostring(bpm) then
          params:set("metro_bpm", tostring(bpm))
        end
      end
    end)
  end

  -- ── Param registration ───────────────────────────────────────
  params:add_separator("princeton_header", "─── PRINCETON ───")
  for i = 1, #PEDALS do setup_pedal(i) end
  setup_amp()
  setup_tremolo()
  setup_looper()
  setup_reverb()
  setup_cab()
  setup_limit()
  setup_metro()
  setup_tuner()
  setup_pitch_poll()

  params:bang()
  initing = false

  setup_clock_watchers()
  redraw()

  clock.run(function()
    clock.sleep(0.2)
    audio.level_monitor(0)
  end)
end
