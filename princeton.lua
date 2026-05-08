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
}
local LOOPER_DEF = {
  { id="looper_medium",     name="Medium",     default=4,   min=1,  max=6,  step=1,   db=false, cat="Looper", options={"BBD","Cassette","CD","Chip","Tape","Vinyl"} },
  { id="looper_wear",       name="Wear",       default=5,   min=0,  max=100, step=1, db=false, unit="%", cat="Looper"  },
  { id="looper_direction",  name="Direction",  default=0,   min=0,   max=3,  step=1,  db=false, cat="Looper"  },
  { id="looper_dub_level",  name="Rec Level",  default=-2.5, min=-40, max=0, step=0.5, db=true, cat="Looper"  },
  { id="looper_level",      name="Play Level", default=-2.5, min=-40, max=0, step=0.5, db=true, cat="Looper"  },
  { id="looper_fade_level", name="Fade Level", default=-2.5, min=-40, max=0, step=0.5, db=true, cat="Looper"  },
  { id="looper_speed",      name="Speed",      default=0,   min=-100, max=100, step=1, db=false, cat="Looper"  },
  { id="looper_quant_div",  name="Quant Div",  default=1,   min=1, max=8, step=1, db=false, cat="Looper", options={"Off","1/1","1/2","1/4","1/8","1/16","1/32","1/64"} },
  { id="looper_quant_feel", name="Quant Feel", default=1,   min=1, max=3, step=1, db=false, cat="Looper", options={"Note","Dotted","Triplet"} },
}
local MIC_NAMES  = { "Center", "Middle", "Edge" }
local DIR_NAMES  = { "Forward", "Reverse", "Pendulum", "Random" }

local NUM_AMP_KNOBS  = 8

local LOOP_SR  = 48000
local LOOP_MAX = LOOP_SR * 40

local sel = 1
local looper_sel = 1

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

local view_group = 0
local view_pane  = {[0]=1, [1]=1, [3]=1}
local lfo_strip_sel = {1, 1, 1, 1, 1, 1, 1, 1}
local metro_strip_sel = 1

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

local function cur_pedal_sel()
  if view_group == 3 then return view_pane[3] end
  return 1
end

local function cur_pedal() return PEDALS[cur_pedal_sel()] end

-- ── Mod Rack ─────────────────────────────────────────────────────
local NUM_LFOS = 8
local WAVEFORMS = {"Sine", "Triangle", "Saw", "Square", "Smooth Random", "Step Random"}
local DIR_OPTS  = {"+", "-", "+/-"}

local lfo_metro_level  = nil
local lfo_metro_length = nil
local lfo_metro_pitch  = nil
local lfo_metro_div    = nil
local lfo_mod = {
  rate        = {},
  depth       = {},
  rate_slewed = {},
  phase       = {},
  steps       = {},
  stability   = {},
  rate_slew   = {},
  sync_div    = {},
  sync_feel   = {},
}
local lfo_sync_override = {}
local sync_push_all
local quant_led_clock_restart

local SCALE_NAMES      = {"Chromatic","Major","Minor","Dorian","Pent Maj","Pent Min","Blues"}
local SCALE_INTERVALS  = {
  {0,1,2,3,4,5,6,7,8,9,10,11},
  {0,2,4,5,7,9,11},
  {0,2,3,5,7,8,10},
  {0,2,3,5,7,9,10},
  {0,2,4,7,9},
  {0,3,5,7,10},
  {0,3,5,6,7,10},
}

local function quantize_to_scale(pitch_idx, root, scale_idx)
  if scale_idx == 1 then return pitch_idx end
  local intervals = SCALE_INTERVALS[scale_idx]
  local best, best_dist = pitch_idx, 97
  for oct = 0, 7 do
    for _, iv in ipairs(intervals) do
      local p = oct * 12 + (root + iv) % 12 + 1
      if p >= 1 and p <= 96 then
        local d = math.abs(pitch_idx - p)
        if d < best_dist then best_dist = d; best = p end
      end
    end
  end
  return best
end

local TARGET_PARAMS = {
  {label="Off"},
  {label="Push: Gain",         id="push_gain",         mn=0,    mx=10,    st=0.1,  send=function(v) engine.push_gain(v) end},
  {label="Push: Tone",         id="push_tone",         mn=0,    mx=10,    st=0.1,  send=function(v) engine.push_tone(v) end},
  {label="Push: Level",        id="push_level",        mn=0,    mx=10,    st=0.1,  send=function(v) engine.push_level(v) end},
  {label="Push: Mix",          id="push_mix",          mn=0,    mx=100,   st=1,    send=function(v) engine.push_mix(math.floor(v)) end},
  {label="Distort: Gain",      id="distort_gain",      mn=0,    mx=10,    st=0.1,  send=function(v) engine.distort_gain(v) end},
  {label="Distort: Tone",      id="distort_tone",      mn=0,    mx=10,    st=0.1,  send=function(v) engine.distort_tone(v) end},
  {label="Distort: Level",     id="distort_level",     mn=0,    mx=10,    st=0.1,  send=function(v) engine.distort_level(v) end},
  {label="Warp: Rate",         id="warp_rate",         mn=0.1,  mx=25,    st=0.1,  send=function(v) engine.warp_rate(v) end},
  {label="Warp: Depth",        id="warp_depth",        mn=0,    mx=100,   st=1,    send=function(v) engine.warp_depth(math.floor(v)) end},
  {label="Warp: Rise/Fall",    id="warp_rise",         mn=0.01, mx=5.0,   st=0.01, send=function(v) engine.warp_rise(v) end},
  {label="Warp: Mix",          id="warp_mix",          mn=0,    mx=100,   st=1,    send=function(v) engine.warp_mix(math.floor(v)) end},
  {label="Repeat: Time",       id="repeat_time",       mn=1,    mx=1000,  st=1,    send=function(v) engine.repeat_time(math.floor(v)) end},
  {label="Repeat: Feedback",   id="repeat_feedback",   mn=0,    mx=100,   st=1,    send=function(v) engine.repeat_feedback(math.floor(v)) end},
  {label="Repeat: Level",      id="repeat_level",      mn=0,    mx=100,   st=1,    send=function(v) engine.repeat_level(math.floor(v)) end},
  {label="Amp: Volume",        id="amp_volume",        mn=0,    mx=10,    st=0.1,  send=function(v) engine.amp_volume(v) end},
  {label="Amp: Bass",          id="amp_bass",          mn=0,    mx=10,    st=0.1,  send=function(v) engine.amp_bass(v) end},
  {label="Amp: Treble",        id="amp_treble",        mn=0,    mx=10,    st=0.1,  send=function(v) engine.amp_treble(v) end},
  {label="Amp: Master",        id="amp_master",        mn=0,    mx=10,    st=0.1,  send=function(v) engine.amp_master(v) end},
  {label="Tremolo: Speed",     id="tremolo_speed",     mn=0.1,  mx=25,    st=0.1,  send=function(v) engine.tremolo_speed(v) end},
  {label="Tremolo: Intensity", id="tremolo_intensity", mn=0,    mx=100,   st=1,    send=function(v) engine.tremolo_intensity(math.floor(v)) end},
  {label="Looper: Rec Level",  id="looper_dub_level",  mn=-40,  mx=0,     st=0.5,  send=function(v) engine.looper_dub_level(db_to_lin(v)) end},
  {label="Looper: Play Level", id="looper_level",      mn=-40,  mx=0,     st=0.5,  send=function(v) engine.looper_level(db_to_lin(v)) end},
  {label="Looper: Fade Level", id="looper_fade_level", mn=-40,  mx=0,     st=0.5,  send=function(v) engine.looper_fade_level(db_to_lin(v)) end},
  {label="Looper: Imprint",    id="looper_imprint",    mn=0,    mx=100,   st=1,    send=function(v) engine.looper_imprint(math.floor(v)) end},
  {label="Looper: Wear",       id="looper_wear",       mn=0,    mx=100,   st=1,    send=function(v) engine.looper_wear(math.floor(v)) end},
  {label="Looper: Cas Wow",    id="looper_cas_wow",    mn=0,    mx=100,   st=1,    send=function(v) engine.looper_wow_cas(math.floor(v)) end},
  {label="Looper: CD Errors",  id="looper_cd_errors",  mn=0,    mx=100,   st=1,    send=function(v) engine.looper_cd_errors(math.floor(v)) end},
  {label="Looper: Chip Crush", id="looper_chip_crush", mn=0,    mx=100,   st=1,    send=function(v) engine.looper_chip_crush(math.floor(v)) end},
  {label="Looper: Tape Wow",   id="looper_tape_wow",   mn=0,    mx=100,   st=1,    send=function(v) engine.looper_wow_tape(math.floor(v)) end},
  {label="Reverb: Amount",     id="reverb_amount",     mn=0,    mx=100,   st=1,    send=function(v) engine.reverb_amount(math.floor(v)) end},
  {label="Reverb: Length",     id="reverb_length",     mn=0.5,  mx=5.0,   st=0.1,  send=function(v) engine.reverb_length(v) end},
  {label="Reverb: Low Shelf",  id="reverb_low_shelf",  mn=-5,   mx=5,     st=0.5,  send=function(v) engine.reverb_low_shelf(v) end},
  {label="Reverb: High Shelf", id="reverb_high_shelf", mn=-5,   mx=5,     st=0.5,  send=function(v) engine.reverb_high_shelf(v) end},
  {label="Cab: Cab Level",     id="cab_level",         mn=-10,  mx=10,    st=0.5,  send=function(v) engine.cab_level(db_to_lin(v)) end},
  {label="Cab: IR Level L",    id="ir_level_l",        mn=-40,  mx=0,     st=0.5,  send=function(v) engine.ir_level_l(db_to_lin(v)) end},
  {label="Cab: IR Level R",    id="ir_level_r",        mn=-40,  mx=0,     st=0.5,  send=function(v) engine.ir_level_r(db_to_lin(v)) end},
  {label="Limit: Threshold",   id="limit_threshold",   mn=-40,  mx=0,     st=0.5,  send=function(v) engine.limit_threshold(db_to_lin(v)) end},
  {label="Limit: Ratio",       id="limit_ratio",       mn=2.0,  mx=20.0,  st=0.5,  send=function(v) engine.limit_ratio(v) end},
  {label="Limit: Gain",        id="limit_gain",        mn=-20,  mx=20,    st=0.5,  send=function(v) engine.limit_gain(db_to_lin(v)) end},
  {label="Limit: Attack",      id="limit_attack",      mn=1,    mx=100,   st=1,    send=function(v) engine.limit_attack(math.floor(v)) end},
  {label="Limit: Decay",       id="limit_decay",       mn=50,   mx=2000,  st=50,   send=function(v) engine.limit_decay(math.floor(v)) end},
  {label="Metro: Division",    id="metro_div",         mn=1,    mx=5,     st=1,    send=function(v) lfo_metro_div = math.floor(v+0.5) end},
  {label="Metro: Level",       id="metro_level",       mn=0,    mx=10,    st=0.1,  send=function(v) lfo_metro_level = v end},
  {label="Metro: Length",      id="metro_length",      mn=1,    mx=500,   st=1,    send=function(v) lfo_metro_length = math.floor(v + 0.5) end},
  {label="Metro: Pitch",       id="metro_pitch",       mn=0,    mx=96,    st=1,    send=function(v)
    local p = math.floor(v + 0.5)
    if p <= 0 then lfo_metro_pitch = 0; return end
    local root = (params:get("metro_pitch") - 1) % 12
    lfo_metro_pitch = quantize_to_scale(p, root, params:get("metro_scale"))
  end},
  {label="LFO 1: Rate",        id="lfo1_rate",         mn=0.1,  mx=25,    st=0.1,  send=function(v) lfo_mod.rate[1]  = v end},
  {label="LFO 2: Rate",        id="lfo2_rate",         mn=0.1,  mx=25,    st=0.1,  send=function(v) lfo_mod.rate[2]  = v end},
  {label="LFO 3: Rate",        id="lfo3_rate",         mn=0.1,  mx=25,    st=0.1,  send=function(v) lfo_mod.rate[3]  = v end},
  {label="LFO 4: Rate",        id="lfo4_rate",         mn=0.1,  mx=25,    st=0.1,  send=function(v) lfo_mod.rate[4]  = v end},
  {label="LFO 5: Rate",        id="lfo5_rate",         mn=0.1,  mx=25,    st=0.1,  send=function(v) lfo_mod.rate[5]  = v end},
  {label="LFO 6: Rate",        id="lfo6_rate",         mn=0.1,  mx=25,    st=0.1,  send=function(v) lfo_mod.rate[6]  = v end},
  {label="LFO 7: Rate",        id="lfo7_rate",         mn=0.1,  mx=25,    st=0.1,  send=function(v) lfo_mod.rate[7]  = v end},
  {label="LFO 8: Rate",        id="lfo8_rate",         mn=0.1,  mx=25,    st=0.1,  send=function(v) lfo_mod.rate[8]  = v end},
  {label="LFO 1: Depth",       id="lfo1_depth",        mn=0,    mx=100,   st=1,    send=function(v) lfo_mod.depth[1] = v end},
  {label="LFO 2: Depth",       id="lfo2_depth",        mn=0,    mx=100,   st=1,    send=function(v) lfo_mod.depth[2] = v end},
  {label="LFO 3: Depth",       id="lfo3_depth",        mn=0,    mx=100,   st=1,    send=function(v) lfo_mod.depth[3] = v end},
  {label="LFO 4: Depth",       id="lfo4_depth",        mn=0,    mx=100,   st=1,    send=function(v) lfo_mod.depth[4] = v end},
  {label="LFO 5: Depth",       id="lfo5_depth",        mn=0,    mx=100,   st=1,    send=function(v) lfo_mod.depth[5] = v end},
  {label="LFO 6: Depth",       id="lfo6_depth",        mn=0,    mx=100,   st=1,    send=function(v) lfo_mod.depth[6] = v end},
  {label="LFO 7: Depth",       id="lfo7_depth",        mn=0,    mx=100,   st=1,    send=function(v) lfo_mod.depth[7] = v end},
  {label="LFO 8: Depth",       id="lfo8_depth",        mn=0,    mx=100,   st=1,    send=function(v) lfo_mod.depth[8] = v end},
  {label="Tremolo: Sync Div",  id="tremolo_sync_div",  mn=2,    mx=8,     st=1,    send=function(v)
    local new_v = math.floor(v+0.5)
    if lfo_sync_override["tremolo_sync_div"] ~= new_v then
      lfo_sync_override["tremolo_sync_div"] = new_v
      sync_push_all()
    end
  end},
  {label="Tremolo: Sync Feel", id="tremolo_sync_feel", mn=1,    mx=3,     st=1,    send=function(v)
    local new_v = math.floor(v+0.5)
    if lfo_sync_override["tremolo_sync_feel"] ~= new_v then
      lfo_sync_override["tremolo_sync_feel"] = new_v
      sync_push_all()
    end
  end},
  {label="Warp: Sync Div",     id="warp_sync_div",     mn=2,    mx=8,     st=1,    send=function(v)
    local new_v = math.floor(v+0.5)
    if lfo_sync_override["warp_sync_div"] ~= new_v then
      lfo_sync_override["warp_sync_div"] = new_v
      sync_push_all()
    end
  end},
  {label="Warp: Sync Feel",    id="warp_sync_feel",    mn=1,    mx=3,     st=1,    send=function(v)
    local new_v = math.floor(v+0.5)
    if lfo_sync_override["warp_sync_feel"] ~= new_v then
      lfo_sync_override["warp_sync_feel"] = new_v
      sync_push_all()
    end
  end},
  {label="Repeat: Sync Div",   id="repeat_sync_div",   mn=2,    mx=8,     st=1,    send=function(v)
    local new_v = math.floor(v+0.5)
    if lfo_sync_override["repeat_sync_div"] ~= new_v then
      lfo_sync_override["repeat_sync_div"] = new_v
      sync_push_all()
    end
  end},
  {label="Repeat: Sync Feel",  id="repeat_sync_feel",  mn=1,    mx=3,     st=1,    send=function(v)
    local new_v = math.floor(v+0.5)
    if lfo_sync_override["repeat_sync_feel"] ~= new_v then
      lfo_sync_override["repeat_sync_feel"] = new_v
      sync_push_all()
    end
  end},
  {label="Looper: Quant Div",  id="looper_quant_div",  mn=2,    mx=8,     st=1,    send=function(v)
    local new_v = math.floor(v+0.5)
    if lfo_sync_override["looper_quant_div"] ~= new_v then
      lfo_sync_override["looper_quant_div"] = new_v
      quant_led_clock_restart()
    end
  end},
  {label="Looper: Quant Feel", id="looper_quant_feel", mn=1,    mx=3,     st=1,    send=function(v)
    local new_v = math.floor(v+0.5)
    if lfo_sync_override["looper_quant_feel"] ~= new_v then
      lfo_sync_override["looper_quant_feel"] = new_v
      quant_led_clock_restart()
    end
  end},
  {label="Looper: Speed",      id="looper_speed",      mn=-100, mx=100,   st=1,    send=function(v)
    local ratio
    if params:get("looper_speed_control") == 1 then
      if v < 0 then ratio = 0.5 elseif v > 0 then ratio = 2.0 else ratio = 1.0 end
    else ratio = 2^(v/100) end
    engine.looper_speed(ratio)
  end},
}

for i = 1, NUM_LFOS do
  TARGET_PARAMS[#TARGET_PARAMS+1] = {label="LFO "..i..": Phase",     id="lfo"..i.."_phase",     mn=1, mx=4,   st=1,   send=function(v) lfo_mod.phase[i]     = math.floor(v + 0.5) end}
  TARGET_PARAMS[#TARGET_PARAMS+1] = {label="LFO "..i..": Steps",     id="lfo"..i.."_steps",     mn=1, mx=16,  st=1,   send=function(v) lfo_mod.steps[i]     = math.floor(v + 0.5) end}
  TARGET_PARAMS[#TARGET_PARAMS+1] = {label="LFO "..i..": Stability", id="lfo"..i.."_stability", mn=0, mx=100, st=1,   send=function(v) lfo_mod.stability[i] = v end}
  TARGET_PARAMS[#TARGET_PARAMS+1] = {label="LFO "..i..": Rate Slew", id="lfo"..i.."_rate_slew", mn=0, mx=5,   st=0.1, send=function(v) lfo_mod.rate_slew[i] = v end}
  TARGET_PARAMS[#TARGET_PARAMS+1] = {label="LFO "..i..": Sync Div",  id="lfo"..i.."_sync_div",  mn=2, mx=8,   st=1,   send=function(v) lfo_mod.sync_div[i]  = math.floor(v + 0.5) end}
  TARGET_PARAMS[#TARGET_PARAMS+1] = {label="LFO "..i..": Sync Feel", id="lfo"..i.."_sync_feel", mn=1, mx=3,   st=1,   send=function(v) lfo_mod.sync_feel[i] = math.floor(v + 0.5) end}
end

local TARGET_LABELS = {}
local TARGET_BY_ID = {}
for i, t in ipairs(TARGET_PARAMS) do
  TARGET_LABELS[i] = t.label
  if t.id then TARGET_BY_ID[t.id] = i end
end

local DEVICE_NAMES     = {}
local DEVICE_PARAMS    = {}
local TARGET_DEVICE_OF = {}
for i = 2, #TARGET_PARAMS do
  local t = TARGET_PARAMS[i]
  if t.id then
    local dev_name, short_name = t.label:match("^(.-): (.+)$")
    if dev_name then
      local di
      for ix, dn in ipairs(DEVICE_NAMES) do
        if dn == dev_name then di = ix; break end
      end
      if not di then
        DEVICE_NAMES[#DEVICE_NAMES + 1] = dev_name
        di = #DEVICE_NAMES
        DEVICE_PARAMS[di] = {}
      end
      DEVICE_PARAMS[di][#DEVICE_PARAMS[di] + 1] = { global_idx = i, short = short_name }
      TARGET_DEVICE_OF[i] = di
    end
  end
end

local NOTE_NAMES = {"C","C#","D","D#","E","F","F#","G","G#","A","A#","B"}
local METRO_PITCH_NAMES = {}
for oct = 0, 7 do
  for _, n in ipairs(NOTE_NAMES) do
    METRO_PITCH_NAMES[#METRO_PITCH_NAMES + 1] = n .. oct
  end
end

local LOOP_IDLE = 0
local LOOP_REC  = 1
local LOOP_DUB  = 2
local LOOP_PLAY = 3
local LOOP_STOP = 4

local loop_state       = LOOP_IDLE
local loop_rec_start   = 0
local loop_frames      = 0
local speed_steps_prev = 0

local lfo_state                = {}
local lfo_clocks               = {}
local lfo_target_base          = {}
local lfo_target_owner         = {}
local lfo_orig_name            = {}
local lfo_last_global          = {}
local lfo_target_device_filter = {}
local lfo_target_param_filter  = {}

for i = 1, NUM_LFOS do
  lfo_state[i] = { phase = 0, smooth_rand_v = 0.5, smooth_rand_target = 0.5, tm_register = 0 }
  lfo_last_global[i] = 1
  lfo_target_device_filter[i] = {}
  for di = 1, #DEVICE_NAMES do lfo_target_device_filter[i][di] = di end
  lfo_target_param_filter[i] = {}
  if DEVICE_PARAMS[1] then
    for j, e in ipairs(DEVICE_PARAMS[1]) do lfo_target_param_filter[i][j] = e.global_idx end
  end
end

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
  tremolo_speed = {
    div = "tremolo_sync_div", feel = "tremolo_sync_feel",
    in_range = function(hz) return hz >= 0.1 and hz <= 25.0 end,
    value_fn = function(hz) return util.clamp(hz, 0.1, 25.0) end,
  },
  warp_rate = {
    div = "warp_sync_div", feel = "warp_sync_feel",
    in_range = function(hz) return hz >= 0.1 and hz <= 25.0 end,
    value_fn = function(hz) return util.clamp(hz, 0.1, 25.0) end,
  },
  repeat_time = {
    div = "repeat_sync_div", feel = "repeat_sync_feel",
    in_range = function(hz) local ms = 1000.0 / hz; return ms >= 1.0 and ms <= 1000.0 end,
    value_fn = function(hz) return util.clamp(1000.0 / hz, 1, 1000) end,
  },
}

local B = { DIM=0, MED=5, FULL=15 }

local LOOPER_KNOB_CX = {51, 58, 65, 72, 79, 86, 93, 100, 107}

local quant_led_clock     = nil
local quant_led_off_clock = nil
local quant_led_lit       = false

local function quant_led_pulse_now()
  quant_led_lit = true
  if quant_led_off_clock then clock.cancel(quant_led_off_clock); quant_led_off_clock = nil end
  if view_group == 0 and view_pane[0] == 2 then redraw() end
  quant_led_off_clock = clock.run(function()
    clock.sleep(0.08)
    quant_led_lit = false
    quant_led_off_clock = nil
    if view_group == 0 and view_pane[0] == 2 then redraw() end
  end)
end

quant_led_clock_restart = function()
  if quant_led_clock then clock.cancel(quant_led_clock); quant_led_clock = nil end
  if quant_led_off_clock then clock.cancel(quant_led_off_clock); quant_led_off_clock = nil end
  quant_led_lit = false
  if not clock_running then return end
  local div_opt = lfo_sync_override["looper_quant_div"] or params:get("looper_quant_div")
  if div_opt <= 1 then return end
  local feel_opt = lfo_sync_override["looper_quant_feel"] or params:get("looper_quant_feel")
  local beats = SYNC_DIV_BEATS[div_opt] * SYNC_FEEL_MULT[feel_opt]
  quant_led_clock = clock.run(function()
    while true do
      clock.sync(beats)
      quant_led_pulse_now()
    end
  end)
end

local GROUP_MAX = {[0]=2, [1]=10, [3]=4}
local LFO_WF_SYM = {"Sin", "Tri", "Saw", "Sqr", "SmR", "StR"}

local METRO_STRIP = {
  {name="Division", id="metro_div",     typ="opt",  nmax=5,  fmt=function(v) return METRO_DIV_OPTS[v] end},
  {name="Level",    id="metro_level",   typ="ctrl", step=0.1, fmt=function(v) return string.format("%.1f",v) end},
  {name="Pitch",    id="metro_pitch",   typ="opt",  nmax=96, fmt=function(v) return METRO_PITCH_NAMES[v] end},
  {name="Length",   id="metro_length",  typ="ctrl", step=1,  fmt=function(v) return string.format("%dms",math.floor(v)) end},
  {name="Scale",    id="metro_scale",    typ="opt",  nmax=7,  fmt=function(v) return SCALE_NAMES[v] end},
  {name="Position", id="metro_position", typ="opt",  nmax=2,  fmt=function(v) return ({"Parallel","Inline"})[v] end},
}

local function lfo_sync_active(idx)  return params:get("lfo"..idx.."_sync_div") > 1 end
local function lfo_step_random(idx)  return params:get("lfo"..idx.."_waveform") == 6 end

local LFO_STRIP = {
  {name="Waveform",  suf="_waveform",     typ="opt",  nmax=6, fmt=function(v,i) return WAVEFORMS[v] end},
  {name="Rate",      suf="_rate",         typ="ctrl", step=0.1, fmt=function(v,i) return string.format("%.1fHz",v) end,
   visible_when=function(idx) return not lfo_sync_active(idx) end},
  {name="Depth",     suf="_depth",        typ="ctrl", step=1,   fmt=function(v,i) return string.format("%d%%",math.floor(v)) end},
  {name="Direction", suf="_dir",          typ="opt",  nmax=3, fmt=function(v,i) return DIR_OPTS[v] end},
  {name="Phase",     suf="_phase",        typ="opt",  nmax=4, fmt=function(v,i) return ({"0°","90°","180°","270°"})[v] end,
   visible_when=function(idx) return not lfo_step_random(idx) end},
  {name="Sync",      suf="_sync_div",     typ="opt",  nmax=8, fmt=function(v,i) return SYNC_DIV_OPTS[v] end},
  {name="Sync Feel", suf="_sync_feel",    typ="opt",  nmax=3, fmt=function(v,i) return SYNC_FEEL_OPTS[v] end,
   visible_when=function(idx) return lfo_sync_active(idx) end},
  {name="Rate Slew", suf="_rate_slew",    typ="ctrl", step=0.1, fmt=function(v,i) return string.format("%.1fs",v) end,
   visible_when=function(idx) return not lfo_step_random(idx) end},
  {name="Steps",     suf="_steps",        typ="ctrl", step=1,   fmt=function(v,i) return tostring(math.floor(v)) end,
   visible_when=function(idx) return lfo_step_random(idx) end},
  {name="Stability", suf="_stability",    typ="ctrl", step=1,   fmt=function(v,i) return string.format("%d%%",math.floor(v)) end,
   visible_when=function(idx) return lfo_step_random(idx) end},
  {name="Device",    suf="_target_device", typ="opt",  nmax_fn=function(i) return #(lfo_target_device_filter[i] or {}) end,
   fmt=function(v,i)
     local dmap=lfo_target_device_filter[i]
     return (dmap and DEVICE_NAMES[dmap[v]]) or "?"
   end},
  {name="Parameter", suf="_target_param",  typ="opt",  nmax_fn=function(i) return #(lfo_target_param_filter[i] or {}) end,
   fmt=function(v,i)
     local pmap=lfo_target_param_filter[i]
     local gi=pmap and pmap[v]
     if gi and TARGET_PARAMS[gi] then return TARGET_PARAMS[gi].label:match(": (.+)$") or TARGET_PARAMS[gi].label end
     return "-"
   end},
}

local function lfo_strip_visible(idx, strip_i)
  local entry = LFO_STRIP[strip_i]
  return entry and (not entry.visible_when or entry.visible_when(idx))
end

local function lfo_strip_resolve(idx, current)
  if lfo_strip_visible(idx, current) then return current end
  for i = current + 1, #LFO_STRIP do
    if lfo_strip_visible(idx, i) then return i end
  end
  for i = current - 1, 1, -1 do
    if lfo_strip_visible(idx, i) then return i end
  end
  return current
end

local function lfo_strip_advance(idx, current, d)
  if d == 0 then return current end
  local step = d > 0 and 1 or -1
  local next_idx = current + step
  while next_idx >= 1 and next_idx <= #LFO_STRIP do
    if lfo_strip_visible(idx, next_idx) then return next_idx end
    next_idx = next_idx + step
  end
  return current
end

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
local PANEL_BUCHSE1 = PANEL.x
local PANEL_BUCHSE2 = PANEL.x + 2
local PANEL_LAMP    = PANEL.x + PANEL.w - 2
local KNOB_SPACING  = 6
local KNOB_START    = PANEL.x + 5
local KNOB_X        = {}
for i = 1, NUM_AMP_KNOBS do
  KNOB_X[i] = KNOB_START + KNOB_SPACING * (i - 1) + math.floor(KNOB_SPACING / 2)
end

local LEFT_W  = CAB.x - 1
local LEFT_CX = math.floor(LEFT_W / 2) - 1
local ICON_Y  = 55

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
  local m = SYNC_PARAM_MAP[id]
  return not m or m.in_range(hz)
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

sync_push_all = function()
  if initing then return end
  local bpm = clock.get_tempo()
  for id, m in pairs(SYNC_PARAM_MAP) do
    local div = lfo_sync_override[m.div] or params:get(m.div)
    if clock_running and div > 1 then
      engine[id](m.value_fn(sync_hz_df(bpm, div, lfo_sync_override[m.feel] or params:get(m.feel))))
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
  local div_opt = lfo_sync_override["looper_quant_div"] or params:get("looper_quant_div")
  if not clock_running or div_opt <= 1 then fn(); return end
  local feel_opt = lfo_sync_override["looper_quant_feel"] or params:get("looper_quant_feel")
  local beats = SYNC_DIV_BEATS[div_opt] * SYNC_FEEL_MULT[feel_opt]
  clock.run(function()
    clock.sync(beats)
    fn()
  end)
end

local function fmt_def_val(def, idx)
  local p  = def[idx]
  local id = p.id
  local v  = params:get(id)
  if p.options then return p.options[v] end
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
  if p.db   then return string.format("%.1fdB", v) end
  if p.unit then
    local stp = p.step
    return stp < 1 and string.format("%.1f%s", v, p.unit) or string.format("%d%s", math.floor(v), p.unit)
  end
  return string.format("%.1f", v)
end
local function fmt_val(idx) return fmt_def_val(PARAMS_DEF, idx) end

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
      transition_to(LOOP_STOP)
    end
    sample_done_clock = nil
  end)
end

local function transition_to(state)
  loop_state = state
  loop_set_engine(state)
  redraw()
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
      transition_to(LOOP_REC)
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
        transition_to(LOOP_STOP)
      else
        local next = params:get("looper_transport") == 2 and LOOP_DUB or LOOP_PLAY
        transition_to(next)
      end
    end)
  elseif loop_state == LOOP_PLAY then
    if params:get("looper_dub_style") == 3 then
      sample_retrig_val = 1 - sample_retrig_val
      engine.loop_sample_retrig(sample_retrig_val)
      sample_oneshot_start()
      redraw()
    else
      transition_to(LOOP_DUB)
    end
  elseif loop_state == LOOP_DUB then
    looper_quantize_then(function()
      transition_to(LOOP_PLAY)
    end)
  elseif loop_state == LOOP_STOP then
    if params:get("looper_dub_style") == 3 then
      loop_state = LOOP_PLAY
      loop_set_engine(LOOP_PLAY)
      if params:get("looper_play_from") == 2 then
        sample_retrig_val = 1 - sample_retrig_val
        engine.loop_sample_retrig(sample_retrig_val)
      end
      sample_oneshot_start()
      redraw()
    else
      if loop_quant_pending then return end
      loop_quant_pending = true
      looper_quantize_then(function()
        loop_quant_pending = false
        transition_to(LOOP_PLAY)
      end)
      redraw()
    end
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
      transition_to(LOOP_STOP)
    end)
  elseif loop_state == LOOP_STOP then
    loop_state  = LOOP_IDLE
    loop_frames = 0
    engine.loop_clear()
    redraw()
  elseif loop_state ~= LOOP_IDLE then
    if sample_done_clock then clock.cancel(sample_done_clock); sample_done_clock = nil end
    looper_quantize_then(function()
      transition_to(LOOP_STOP)
    end)
  end
end

-- ── Mod Rack helpers ────────────────────────────────────────────
local function tm_register_max(steps)
  if steps <= 0 then return 0 end
  return (1 << steps) - 1
end

local function lfo_g(field, idx)
  return lfo_mod[field][idx] or params:get("lfo"..idx.."_"..field)
end

local function lfo_phase_offset(idx)
  local opt = lfo_g("phase", idx)
  if opt == 2 then return 0.25
  elseif opt == 3 then return 0.5
  elseif opt == 4 then return 0.75
  end
  return 0
end

local function lfo_compute_v_unsigned(idx)
  local s = lfo_state[idx]
  local wf = params:get("lfo"..idx.."_waveform")
  local p = (s.phase + lfo_phase_offset(idx)) % 1
  if wf == 1 then return (math.sin(p * 2 * math.pi) + 1) / 2
  elseif wf == 2 then return 1 - 2 * math.abs(p - 0.5)
  elseif wf == 3 then return p
  elseif wf == 4 then return p < 0.5 and 1 or 0
  elseif wf == 5 then return s.smooth_rand_v
  elseif wf == 6 then
    local m = tm_register_max(lfo_g("steps", idx))
    if m == 0 then return 0 end
    return s.tm_register / m
  end
  return 0
end

local function mark_modulated(target_id)
  if not target_id then return end
  local idx = params.lookup[target_id]
  if not idx then return end
  local p = params.params[idx]
  if not lfo_orig_name[target_id] then lfo_orig_name[target_id] = p.name end
  if not string.find(p.name, "%(M%)") then
    p.name = "(M) " .. lfo_orig_name[target_id]
  end
  if _menu and _menu.rebuild_params then _menu.rebuild_params() end
end

local function unmark_modulated(target_id)
  if not target_id then return end
  local idx = params.lookup[target_id]
  if not idx or not lfo_orig_name[target_id] then return end
  params.params[idx].name = lfo_orig_name[target_id]
  if _menu and _menu.rebuild_params then _menu.rebuild_params() end
end

local function rebuild_lfo_target_param_dropdown(idx, dev_idx)
  local p = params:lookup_param("lfo"..idx.."_target_param")
  if not p then return end
  local opts, map = {}, {}
  local target_lfo
  if dev_idx and DEVICE_NAMES[dev_idx] then
    local n = DEVICE_NAMES[dev_idx]:match("^LFO (%d+)$")
    if n then target_lfo = tonumber(n) end
  end
  local target_wf, target_synced
  if target_lfo then
    target_wf     = params:get("lfo"..target_lfo.."_waveform")
    target_synced = params:get("lfo"..target_lfo.."_sync_div") > 1
  end
  if dev_idx and DEVICE_PARAMS[dev_idx] then
    for _, entry in ipairs(DEVICE_PARAMS[dev_idx]) do
      local target_id = TARGET_PARAMS[entry.global_idx].id
      local owner = lfo_target_owner[target_id]
      local visible = true
      if target_lfo then
        local _, suf = target_id:match("^lfo(%d+)_(.+)$")
        if suf == "rate" then visible = not target_synced
        elseif suf == "phase" or suf == "rate_slew" then visible = (target_wf ~= 6)
        elseif suf == "steps" or suf == "stability" then visible = (target_wf == 6)
        elseif suf == "sync_div" or suf == "sync_feel" then visible = target_synced
        end
      else
        if target_id == "tremolo_sync_div" or target_id == "tremolo_sync_feel" then
          visible = params:get("tremolo_sync_div") > 1
        elseif target_id == "warp_sync_div" or target_id == "warp_sync_feel" then
          visible = params:get("warp_sync_div") > 1
        elseif target_id == "repeat_sync_div" or target_id == "repeat_sync_feel" then
          visible = params:get("repeat_sync_div") > 1
        elseif target_id == "looper_quant_div" or target_id == "looper_quant_feel" then
          visible = params:get("looper_quant_div") > 1
        end
      end
      if visible and (owner == nil or owner == idx) then
        opts[#opts + 1] = entry.short
        map[#map + 1]  = entry.global_idx
      end
    end
  end
  if #opts == 0 then opts = {"-"}; map = {1} end
  lfo_target_param_filter[idx] = map
  p.options = opts
  p.count = #opts
  local cur_global = lfo_last_global[idx] or 1
  local new_filtered = 1
  for fi, gi in ipairs(map) do
    if gi == cur_global then new_filtered = fi; break end
  end
  p.selected = new_filtered
end

local function rebuild_lfo_target_device_dropdown(idx)
  local p = params:lookup_param("lfo"..idx.."_target_device")
  if not p then return end
  local opts, map = {}, {}
  for di = 1, #DEVICE_NAMES do
    if DEVICE_NAMES[di] ~= "LFO " .. idx then
      local has_available = false
      if DEVICE_PARAMS[di] then
        for _, entry in ipairs(DEVICE_PARAMS[di]) do
          local owner = lfo_target_owner[TARGET_PARAMS[entry.global_idx].id]
          if owner == nil or owner == idx then has_available = true; break end
        end
      end
      if has_available then
        opts[#opts + 1] = DEVICE_NAMES[di]
        map[#map + 1]  = di
      end
    end
  end
  if #opts == 0 then opts = {"-"}; map = {1} end
  lfo_target_device_filter[idx] = map
  p.options = opts
  p.count = #opts
  local cur_global = lfo_last_global[idx] or 1
  local cur_dev = TARGET_DEVICE_OF[cur_global] or 1
  local new_filtered = 1
  for fi, di in ipairs(map) do
    if di == cur_dev then new_filtered = fi; break end
  end
  p.selected = new_filtered
end

local function rebuild_lfo_target_dropdown(idx)
  rebuild_lfo_target_device_dropdown(idx)
  local cur_global = lfo_last_global[idx] or 1
  local cur_dev = TARGET_DEVICE_OF[cur_global]
  if not cur_dev then
    local dev_filtered = params:get("lfo"..idx.."_target_device")
    cur_dev = (lfo_target_device_filter[idx] and lfo_target_device_filter[idx][dev_filtered]) or 1
  end
  rebuild_lfo_target_param_dropdown(idx, cur_dev)
end

local function lfo_apply_to_target(idx)
  if initing then return end
  if params:get("lfo"..idx.."_enable") ~= 2 then return end
  local target_idx = lfo_last_global[idx] or 1
  if target_idx == 1 then return end
  local t = TARGET_PARAMS[target_idx]
  if not t or not t.id or not t.send then return end
  if lfo_target_owner[t.id] ~= idx then return end

  local base = lfo_target_base[t.id]
  if base == nil then base = params:get(t.id) end

  local v_un = lfo_compute_v_unsigned(idx)
  local depth = lfo_mod.depth[idx] ~= nil and lfo_mod.depth[idx] or params:get("lfo"..idx.."_depth")
  local dir = params:get("lfo"..idx.."_dir")
  local d = depth / 100
  local range = t.mx - t.mn

  local off
  if dir == 1 then     off = v_un * d * range
  elseif dir == 2 then off = -v_un * d * range
  else                 off = (v_un * 2 - 1) * d * range / 2
  end

  local val = util.clamp(base + off, t.mn, t.mx)
  val = math.floor(val / t.st + 0.5) * t.st
  t.send(val)
end

local function clear_lfo_override(target_id)
  local n = target_id:match("^lfo(%d+)_rate$")
  if n then
    local i = tonumber(n)
    lfo_mod.rate[i] = nil
    lfo_mod.rate_slewed[i] = nil
    return
  end
  n = target_id:match("^lfo(%d+)_depth$")
  if n then lfo_mod.depth[tonumber(n)] = nil; return end
  local nn, field = target_id:match("^lfo(%d+)_(.+)$")
  if nn and lfo_mod[field] then
    lfo_mod[field][tonumber(nn)] = nil
    return
  end
  if target_id == "metro_level"  then lfo_metro_level  = nil; return end
  if target_id == "metro_length" then lfo_metro_length = nil; return end
  if target_id == "metro_pitch"  then lfo_metro_pitch  = nil; return end
  if target_id == "metro_div"    then lfo_metro_div    = nil; return end
  if lfo_sync_override[target_id] ~= nil then
    lfo_sync_override[target_id] = nil
    sync_push_all()
    if target_id == "looper_quant_div" or target_id == "looper_quant_feel" then
      quant_led_clock_restart()
    end
  end
end

local function start_lfo_clock(idx)
  if lfo_clocks[idx] then clock.cancel(lfo_clocks[idx]); lfo_clocks[idx] = nil end
  if initing then return end
  if params:get("lfo"..idx.."_enable") ~= 2 then
    local ti = lfo_last_global[idx] or 1
    if ti > 1 and TARGET_PARAMS[ti] and TARGET_PARAMS[ti].id then
      clear_lfo_override(TARGET_PARAMS[ti].id)
    end
    return
  end
  local target_idx = lfo_last_global[idx] or 1
  if target_idx == 1 then return end
  local t = TARGET_PARAMS[target_idx]
  if not t or not t.id or lfo_target_owner[t.id] ~= idx then return end

  lfo_clocks[idx] = clock.run(function()
    while true do
      local cur_target = lfo_last_global[idx] or 1
      if cur_target == 1 then break end
      local wf = params:get("lfo"..idx.."_waveform")

      if wf == 6 then
        local sync_div_opt = lfo_g("sync_div", idx)
        if sync_div_opt > 1 and clock_running then
          local beats = SYNC_DIV_BEATS[sync_div_opt] * SYNC_FEEL_MULT[lfo_g("sync_feel", idx)]
          clock.sync(beats)
        else
          local target_rate = lfo_mod.rate[idx] ~= nil and lfo_mod.rate[idx] or params:get("lfo"..idx.."_rate")
          local slew = lfo_g("rate_slew", idx)
          local rate
          if slew > 0 and lfo_mod.rate[idx] ~= nil then
            if lfo_mod.rate_slewed[idx] == nil then lfo_mod.rate_slewed[idx] = target_rate end
            local dt_step = 1 / math.max(0.05, lfo_mod.rate_slewed[idx])
            local coeff = math.min(1, dt_step / slew)
            lfo_mod.rate_slewed[idx] = lfo_mod.rate_slewed[idx] + (target_rate - lfo_mod.rate_slewed[idx]) * coeff
            rate = lfo_mod.rate_slewed[idx]
          else
            lfo_mod.rate_slewed[idx] = nil
            rate = target_rate
          end
          clock.sleep(1 / math.max(0.05, rate))
        end
        local s = lfo_state[idx]
        local steps = lfo_g("steps", idx)
        if steps > 0 then
          local m = tm_register_max(steps)
          local msb = (s.tm_register >> (steps - 1)) & 1
          s.tm_register = (s.tm_register << 1) & m
          local stab = lfo_g("stability", idx)
          if math.random(100) > stab then
            s.tm_register = s.tm_register | (1 - msb)
          else
            s.tm_register = s.tm_register | msb
          end
        end
        lfo_apply_to_target(idx)
      else
        local dt = 1/60
        clock.sleep(dt)
        local sync_div_opt = lfo_g("sync_div", idx)
        local rate
        if sync_div_opt > 1 and clock_running then
          local beats = SYNC_DIV_BEATS[sync_div_opt] * SYNC_FEEL_MULT[lfo_g("sync_feel", idx)]
          rate = clock.get_tempo() / (60 * beats)
        else
          local target_rate = lfo_mod.rate[idx] ~= nil and lfo_mod.rate[idx] or params:get("lfo"..idx.."_rate")
          local slew = lfo_g("rate_slew", idx)
          if slew > 0 and lfo_mod.rate[idx] ~= nil then
            if lfo_mod.rate_slewed[idx] == nil then lfo_mod.rate_slewed[idx] = target_rate end
            local coeff = math.min(1, dt / slew)
            lfo_mod.rate_slewed[idx] = lfo_mod.rate_slewed[idx] + (target_rate - lfo_mod.rate_slewed[idx]) * coeff
            rate = lfo_mod.rate_slewed[idx]
          else
            lfo_mod.rate_slewed[idx] = nil
            rate = target_rate
          end
        end
        local s = lfo_state[idx]
        local prev_phase = s.phase
        s.phase = (s.phase + dt * rate) % 1
        if wf == 5 then
          if s.phase < prev_phase then
            s.smooth_rand_target = math.random()
          end
          local alpha = math.min(1, dt * rate * 4)
          s.smooth_rand_v = s.smooth_rand_v + (s.smooth_rand_target - s.smooth_rand_v) * alpha
        end
        lfo_apply_to_target(idx)
      end
    end
    lfo_clocks[idx] = nil
  end)
end

local function lfo_is_enabled(idx)
  return params:get("lfo"..idx.."_enable") == 2
end

local function set_lfo_target(idx, new_global_idx)
  local prev_global_idx = lfo_last_global[idx] or 1
  local enabled = lfo_is_enabled(idx)

  if prev_global_idx > 1 then
    local old_t = TARGET_PARAMS[prev_global_idx]
    if old_t and old_t.id and lfo_target_owner[old_t.id] == idx then
      lfo_target_owner[old_t.id] = nil
      unmark_modulated(old_t.id)
      local base = lfo_target_base[old_t.id]
      if base == nil then base = params:get(old_t.id) end
      if old_t.send then old_t.send(base) end
      clear_lfo_override(old_t.id)
    end
  end

  lfo_last_global[idx] = new_global_idx

  if enabled and new_global_idx > 1 then
    local new_t = TARGET_PARAMS[new_global_idx]
    if new_t and new_t.id and not lfo_target_owner[new_t.id] then
      lfo_target_owner[new_t.id] = idx
      lfo_target_base[new_t.id] = params:get(new_t.id)
      mark_modulated(new_t.id)
    end
  end

  for i = 1, NUM_LFOS do rebuild_lfo_target_dropdown(i) end
  if _menu and _menu.rebuild_params then _menu.rebuild_params() end

  start_lfo_clock(idx)
end

local function lfo_refresh_dropdowns_for_device(dev_name)
  for other = 1, NUM_LFOS do
    local other_target_global = lfo_last_global[other] or 1
    if other_target_global > 1 then
      local cur_dev = TARGET_DEVICE_OF[other_target_global]
      if cur_dev and DEVICE_NAMES[cur_dev] == dev_name then
        rebuild_lfo_target_param_dropdown(other, cur_dev)
        local new_filter = lfo_target_param_filter[other]
        local still_present = false
        if new_filter then
          for _, gi in ipairs(new_filter) do
            if gi == other_target_global then still_present = true; break end
          end
        end
        if not still_present then
          local fallback = (new_filter and new_filter[1]) or 1
          set_lfo_target(other, fallback)
        end
      end
    end
  end
end

local function tm_randomize(idx)
  local s = lfo_state[idx]
  local m = tm_register_max(params:get("lfo"..idx.."_steps"))
  if m == 0 then return end
  s.tm_register = math.random(0, m)
  lfo_apply_to_target(idx)
end

local function round_sym(x)
  if x >= 0 then return math.floor(x + 0.5)
  else return -math.floor(-x + 0.5) end
end

local function freq_to_note(freq)
  if freq < 20 then return "--", 0, 0 end
  local semitones = 69 + 12 * math.log(freq / 440.0) / math.log(2)
  local nearest   = round_sym(semitones)
  local cents     = round_sym((semitones - nearest) * 100)
  local name      = NOTE_NAMES[nearest % 12 + 1]
  local octave    = math.floor(nearest / 12) - 1
  return name, octave, cents
end

local function cents_to_ref(freq, ref)
  if freq < 20 or ref < 20 then return 0 end
  local semitones = 12 * math.log(freq / ref) / math.log(2)
  local nearest   = round_sym(semitones)
  local cents     = round_sym((semitones - nearest) * 100)
  return cents
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
  local px, py = cx + 8, y - 3
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

local function draw_strip(cat, name, val_str, val_lv, val_str2)
  val_lv = val_lv or B.FULL
  screen.level(B.DIM); screen.rect(0, 0, LEFT_W, 64); screen.fill()
  screen.font_size(8); screen.font_face(0)
  screen.level(B.MED);  screen.move(LEFT_CX,  8); screen.text_center(cat)
  screen.level(B.MED);  screen.move(LEFT_CX, 17); screen.text_center(name)
  if val_str2 then
    screen.level(val_lv); screen.move(LEFT_CX, 26); screen.text_center(val_str)
    screen.level(val_lv); screen.move(LEFT_CX, 35); screen.text_center(val_str2)
  else
    screen.level(val_lv); screen.move(LEFT_CX, 26); screen.text_center(val_str)
  end
end

local function draw_left_strip()
  local cm = params:get("cab_mode")
  if PARAMS_DEF[sel] and PARAMS_DEF[sel].id == "mic_position" and cm == 1 then
    screen.level(B.DIM); screen.rect(0, 0, LEFT_W, 64); screen.fill()
    screen.font_size(8); screen.font_face(0)
    screen.level(B.MED)
    screen.move(LEFT_CX,  8); screen.text_center("Cab & Mic")
    screen.move(LEFT_CX, 17); screen.text_center("Simulation")
    screen.move(LEFT_CX, 26); screen.text_center("Bypass")
  elseif PARAMS_DEF[sel] and PARAMS_DEF[sel].id == "mic_position" and cm == 3 then
    screen.level(B.DIM); screen.rect(0, 0, LEFT_W, 64); screen.fill()
    screen.font_size(8); screen.font_face(0)
    screen.level(B.MED); screen.move(LEFT_CX,  8); screen.text_center("IR")
  else
    draw_strip(PARAMS_DEF[sel].cat, PARAMS_DEF[sel].name, fmt_val(sel), sync_val_level(PARAMS_DEF[sel].id))
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

-- ── LFO waveform sprites (33x56, vector center 16,28) ───────────
local LFO_WF_SPRITES = {
  [1] = {  -- Sine
    -- 181 px, 33x56
    [5] = {
    {3,5}, {4,5}, {5,5}, {6,5}, {7,5}, {8,5}, {9,5}, {10,5}, {11,5}, {12,5},
    {13,5}, {2,6}, {14,6}, {2,7}, {14,7}, {1,8}, {15,8}, {1,9}, {15,9}, {17,37},
    {31,37}, {17,38}, {31,38}, {18,39}, {30,39}, {18,40}, {30,40}, {19,41}, {20,41}, {21,41},
    {22,41}, {23,41}, {24,41}, {25,41}, {26,41}, {27,41}, {28,41}, {29,41}
    },
    [15] = {
    {3,0}, {4,0}, {5,0}, {6,0}, {7,0}, {8,0}, {9,0}, {10,0}, {11,0}, {12,0},
    {13,0}, {2,1}, {14,1}, {2,2}, {14,2}, {1,3}, {15,3}, {1,4}, {15,4}, {0,5},
    {16,5}, {0,6}, {16,6}, {0,7}, {16,7}, {0,8}, {16,8}, {32,8}, {0,9}, {16,9},
    {32,9}, {0,10}, {16,10}, {32,10}, {0,11}, {16,11}, {32,11}, {0,12}, {16,12}, {32,12},
    {0,13}, {16,13}, {32,13}, {0,14}, {16,14}, {32,14}, {0,15}, {16,15}, {32,15}, {0,16},
    {16,16}, {32,16}, {0,17}, {16,17}, {32,17}, {0,18}, {16,18}, {32,18}, {0,19}, {16,19},
    {32,19}, {0,20}, {16,20}, {32,20}, {0,21}, {16,21}, {32,21}, {0,22}, {16,22}, {32,22},
    {0,23}, {16,23}, {32,23}, {0,24}, {16,24}, {32,24}, {0,25}, {16,25}, {32,25}, {0,26},
    {16,26}, {32,26}, {0,27}, {16,27}, {32,27}, {0,28}, {16,28}, {32,28}, {0,29}, {16,29},
    {32,29}, {0,30}, {16,30}, {32,30}, {0,31}, {16,31}, {32,31}, {0,32}, {16,32}, {32,32},
    {0,33}, {16,33}, {32,33}, {0,34}, {16,34}, {32,34}, {0,35}, {16,35}, {32,35}, {0,36},
    {16,36}, {32,36}, {0,37}, {16,37}, {32,37}, {0,38}, {16,38}, {32,38}, {16,39}, {32,39},
    {16,40}, {32,40}, {16,41}, {32,41}, {17,42}, {31,42}, {17,43}, {31,43}, {18,44}, {30,44},
    {18,45}, {30,45}, {19,46}, {20,46}, {21,46}, {22,46}, {23,46}, {24,46}, {25,46}, {26,46},
    {27,46}, {28,46}, {29,46}
    },
  },
  [2] = {  -- Triangle
    -- 145 px, 33x56
    [5] = {
    {8,4}, {7,5}, {9,5}, {7,6}, {9,6}, {6,7}, {10,7}, {6,8}, {10,8}, {5,9},
    {11,9}, {5,10}, {11,10}, {5,11}, {11,11}, {4,12}, {12,12}, {4,13}, {12,13}, {3,15},
    {13,15}, {3,16}, {13,16}, {2,19}, {14,19}, {18,27}, {30,27}, {19,30}, {29,30}, {19,31},
    {29,31}, {20,32}, {28,32}, {20,33}, {28,33}, {20,34}, {28,34}, {21,35}, {27,35}, {21,36},
    {27,36}, {21,37}, {27,37}, {22,38}, {26,38}, {22,39}, {26,39}, {23,40}, {25,40}, {23,41},
    {25,41}, {24,42}
    },
    [15] = {
    {8,0}, {7,1}, {9,1}, {7,2}, {9,2}, {6,3}, {10,3}, {6,4}, {10,4}, {5,5},
    {11,5}, {5,6}, {11,6}, {5,7}, {11,7}, {5,8}, {11,8}, {4,9}, {12,9}, {4,10},
    {12,10}, {4,11}, {12,11}, {3,12}, {13,12}, {3,13}, {13,13}, {3,14}, {13,14}, {2,15},
    {14,15}, {2,16}, {14,16}, {2,17}, {14,17}, {2,18}, {14,18}, {1,19}, {15,19}, {1,20},
    {15,20}, {1,21}, {15,21}, {0,22}, {16,22}, {0,23}, {16,23}, {32,23}, {16,24}, {32,24},
    {17,25}, {31,25}, {17,26}, {31,26}, {17,27}, {31,27}, {18,28}, {30,28}, {18,29}, {30,29},
    {18,30}, {30,30}, {18,31}, {30,31}, {19,32}, {29,32}, {19,33}, {29,33}, {19,34}, {29,34},
    {20,35}, {28,35}, {20,36}, {28,36}, {20,37}, {28,37}, {21,38}, {27,38}, {21,39}, {27,39},
    {21,40}, {27,40}, {21,41}, {27,41}, {22,42}, {26,42}, {22,43}, {26,43}, {23,44}, {25,44},
    {23,45}, {25,45}, {24,46}
    },
  },
  [3] = {  -- Saw
    -- 125 px, 33x56
    [5] = {
    {15,6}, {14,7}, {13,8}, {12,9}, {12,10}, {11,11}, {10,12}, {9,13}, {8,14}, {7,15},
    {6,16}, {5,17}, {4,18}, {4,19}, {3,20}, {2,21}, {30,25}, {29,26}, {28,27}, {28,28},
    {27,29}, {26,30}, {25,31}, {24,32}, {23,33}, {22,34}, {21,35}, {20,36}, {20,37}, {19,38},
    {18,39}, {17,40}
    },
    [15] = {
    {16,0}, {15,1}, {16,1}, {15,2}, {16,2}, {14,3}, {16,3}, {13,4}, {16,4}, {13,5},
    {16,5}, {12,6}, {16,6}, {11,7}, {16,7}, {10,8}, {16,8}, {10,9}, {16,9}, {9,10},
    {16,10}, {8,11}, {16,11}, {8,12}, {16,12}, {7,13}, {16,13}, {6,14}, {16,14}, {6,15},
    {16,15}, {5,16}, {16,16}, {4,17}, {16,17}, {3,18}, {16,18}, {3,19}, {16,19}, {2,20},
    {16,20}, {1,21}, {16,21}, {1,22}, {16,22}, {0,23}, {16,23}, {32,23}, {16,24}, {31,24},
    {16,25}, {31,25}, {16,26}, {30,26}, {16,27}, {29,27}, {16,28}, {29,28}, {16,29}, {28,29},
    {16,30}, {27,30}, {16,31}, {26,31}, {16,32}, {26,32}, {16,33}, {25,33}, {16,34}, {24,34},
    {16,35}, {24,35}, {16,36}, {23,36}, {16,37}, {22,37}, {16,38}, {22,38}, {16,39}, {21,39},
    {16,40}, {20,40}, {16,41}, {19,41}, {16,42}, {19,42}, {16,43}, {18,43}, {16,44}, {17,44},
    {16,45}, {17,45}, {16,46}
    },
  },
  [4] = {  -- Square
    -- 201 px, 33x56
    [5] = {
    {1,6}, {2,6}, {3,6}, {4,6}, {5,6}, {6,6}, {7,6}, {8,6}, {9,6}, {10,6},
    {11,6}, {12,6}, {13,6}, {14,6}, {15,6}, {17,41}, {18,41}, {19,41}, {20,41}, {21,41},
    {22,41}, {23,41}, {24,41}, {25,41}, {26,41}, {27,41}, {28,41}, {29,41}, {30,41}, {31,41}
    },
    [15] = {
    {0,0}, {1,0}, {2,0}, {3,0}, {4,0}, {5,0}, {6,0}, {7,0}, {8,0}, {9,0},
    {10,0}, {11,0}, {12,0}, {13,0}, {14,0}, {15,0}, {16,0}, {32,0}, {0,1}, {16,1},
    {32,1}, {0,2}, {16,2}, {32,2}, {0,3}, {16,3}, {32,3}, {0,4}, {16,4}, {32,4},
    {0,5}, {16,5}, {32,5}, {0,6}, {16,6}, {32,6}, {0,7}, {16,7}, {32,7}, {0,8},
    {16,8}, {32,8}, {0,9}, {16,9}, {32,9}, {0,10}, {16,10}, {32,10}, {0,11}, {16,11},
    {32,11}, {0,12}, {16,12}, {32,12}, {0,13}, {16,13}, {32,13}, {0,14}, {16,14}, {32,14},
    {0,15}, {16,15}, {32,15}, {0,16}, {16,16}, {32,16}, {0,17}, {16,17}, {32,17}, {0,18},
    {16,18}, {32,18}, {0,19}, {16,19}, {32,19}, {0,20}, {16,20}, {32,20}, {0,21}, {16,21},
    {32,21}, {0,22}, {16,22}, {32,22}, {0,23}, {16,23}, {32,23}, {0,24}, {16,24}, {32,24},
    {0,25}, {16,25}, {32,25}, {0,26}, {16,26}, {32,26}, {0,27}, {16,27}, {32,27}, {0,28},
    {16,28}, {32,28}, {0,29}, {16,29}, {32,29}, {0,30}, {16,30}, {32,30}, {0,31}, {16,31},
    {32,31}, {0,32}, {16,32}, {32,32}, {0,33}, {16,33}, {32,33}, {0,34}, {16,34}, {32,34},
    {0,35}, {16,35}, {32,35}, {0,36}, {16,36}, {32,36}, {0,37}, {16,37}, {32,37}, {0,38},
    {16,38}, {32,38}, {0,39}, {16,39}, {32,39}, {0,40}, {16,40}, {32,40}, {0,41}, {16,41},
    {32,41}, {0,42}, {16,42}, {32,42}, {0,43}, {16,43}, {32,43}, {0,44}, {16,44}, {32,44},
    {0,45}, {16,45}, {32,45}, {0,46}, {16,46}, {17,46}, {18,46}, {19,46}, {20,46}, {21,46},
    {22,46}, {23,46}, {24,46}, {25,46}, {26,46}, {27,46}, {28,46}, {29,46}, {30,46}, {31,46},
    {32,46}
    },
  },
  [5] = {  -- Smooth Random
    -- 153 px, 33x56
    [5] = {
    {5,16}, {6,16}, {7,16}, {8,16}, {9,16}, {3,17}, {4,17}, {5,17}, {9,17}, {10,17},
    {11,17}, {2,18}, {3,18}, {11,18}, {12,18}, {1,19}, {2,19}, {12,19}, {13,19}, {1,20},
    {13,20}, {14,20}, {28,20}, {29,20}, {30,20}, {31,20}, {14,21}, {15,21}, {27,21}, {28,21},
    {31,21}, {32,21}, {15,22}, {26,22}, {27,22}, {32,22}, {16,23}, {25,23}, {26,23}, {32,23},
    {16,24}, {17,24}, {23,24}, {17,25}, {18,25}, {21,25}, {22,25}, {18,26}, {19,26}, {20,26},
    {21,26}
    },
    [15] = {
    {8,0}, {9,0}, {10,0}, {11,0}, {12,0}, {13,0}, {14,0}, {6,1}, {7,1}, {8,1},
    {14,1}, {15,1}, {16,1}, {5,2}, {6,2}, {16,2}, {17,2}, {5,3}, {17,3}, {18,3},
    {4,4}, {5,4}, {18,4}, {19,4}, {4,5}, {19,5}, {3,6}, {4,6}, {19,6}, {3,7},
    {19,7}, {20,7}, {2,8}, {3,8}, {20,8}, {2,9}, {20,9}, {2,10}, {20,10}, {21,10},
    {1,11}, {2,11}, {21,11}, {1,12}, {21,12}, {1,13}, {21,13}, {22,13}, {1,14}, {22,14},
    {0,15}, {1,15}, {22,15}, {0,16}, {22,16}, {0,17}, {22,17}, {23,17}, {0,18}, {23,18},
    {0,19}, {23,19}, {0,20}, {23,20}, {24,20}, {0,21}, {24,21}, {0,22}, {24,22}, {0,23},
    {24,23}, {24,24}, {25,24}, {25,25}, {25,26}, {25,27}, {26,27}, {26,28}, {26,29}, {26,30},
    {26,31}, {27,31}, {27,32}, {27,33}, {27,34}, {28,34}, {28,35}, {28,36}, {28,37}, {29,37},
    {29,38}, {29,39}, {30,39}, {30,40}, {30,41}, {30,42}, {30,43}, {31,43}, {31,44}, {31,45},
    {32,45}, {32,46}
    },
  },
  [6] = {  -- Step Random
    -- 291 px, 33x56
    [5] = {
    {7,6}, {8,6}, {9,6}, {10,6}, {7,7}, {10,7}, {7,8}, {10,8}, {7,9}, {10,9},
    {7,10}, {10,10}, {7,11}, {10,11}, {7,12}, {10,12}, {7,13}, {10,13}, {7,14}, {10,14},
    {22,14}, {23,14}, {24,14}, {25,14}, {7,15}, {10,15}, {22,15}, {25,15}, {7,16}, {10,16},
    {22,16}, {25,16}, {2,17}, {3,17}, {7,17}, {10,17}, {16,19}, {17,19}, {18,19}, {19,19},
    {16,20}, {19,20}, {28,21}, {29,21}, {30,21}, {31,21}, {28,22}, {31,22}, {4,25}, {7,25},
    {4,26}, {5,26}, {6,26}, {7,26}, {26,27}, {27,27}, {19,28}, {22,28}, {11,29}, {12,29},
    {19,29}, {22,29}, {19,30}, {22,30}, {19,31}, {22,31}, {19,32}, {22,32}, {19,33}, {22,33},
    {19,34}, {22,34}, {19,35}, {22,35}, {19,36}, {22,36}, {19,37}, {22,37}, {19,38}, {22,38},
    {19,39}, {22,39}, {19,40}, {22,40}, {19,41}, {20,41}, {21,41}, {22,41}
    },
    [15] = {
    {1,0}, {2,0}, {3,0}, {4,0}, {1,1}, {4,1}, {1,2}, {4,2}, {1,3}, {4,3},
    {1,4}, {4,4}, {1,5}, {4,5}, {1,6}, {4,6}, {1,7}, {4,7}, {1,8}, {4,8},
    {1,9}, {4,9}, {1,10}, {4,10}, {1,11}, {4,11}, {1,12}, {4,12}, {1,13}, {4,13},
    {1,14}, {4,14}, {1,15}, {4,15}, {1,16}, {4,16}, {1,17}, {4,17}, {22,17}, {23,17},
    {24,17}, {25,17}, {1,18}, {4,18}, {7,18}, {8,18}, {9,18}, {10,18}, {22,18}, {25,18},
    {1,19}, {4,19}, {7,19}, {10,19}, {22,19}, {25,19}, {1,20}, {4,20}, {7,20}, {10,20},
    {22,20}, {25,20}, {1,21}, {4,21}, {7,21}, {10,21}, {16,21}, {17,21}, {18,21}, {19,21},
    {22,21}, {25,21}, {1,22}, {4,22}, {7,22}, {10,22}, {16,22}, {19,22}, {22,22}, {25,22},
    {1,23}, {4,23}, {7,23}, {10,23}, {13,23}, {14,23}, {15,23}, {16,23}, {19,23}, {22,23},
    {25,23}, {28,23}, {29,23}, {30,23}, {31,23}, {1,24}, {4,24}, {5,24}, {6,24}, {7,24},
    {10,24}, {13,24}, {19,24}, {22,24}, {25,24}, {28,24}, {31,24}, {1,25}, {10,25}, {13,25},
    {19,25}, {22,25}, {25,25}, {28,25}, {31,25}, {1,26}, {10,26}, {13,26}, {19,26}, {22,26},
    {25,26}, {28,26}, {31,26}, {1,27}, {10,27}, {13,27}, {19,27}, {20,27}, {21,27}, {22,27},
    {25,27}, {28,27}, {31,27}, {1,28}, {10,28}, {13,28}, {25,28}, {28,28}, {31,28}, {1,29},
    {10,29}, {13,29}, {25,29}, {28,29}, {31,29}, {0,30}, {1,30}, {10,30}, {13,30}, {25,30},
    {28,30}, {31,30}, {10,31}, {13,31}, {25,31}, {28,31}, {31,31}, {10,32}, {13,32}, {25,32},
    {28,32}, {31,32}, {32,32}, {10,33}, {13,33}, {25,33}, {28,33}, {10,34}, {13,34}, {25,34},
    {28,34}, {10,35}, {13,35}, {25,35}, {28,35}, {10,36}, {11,36}, {12,36}, {13,36}, {25,36},
    {28,36}, {25,37}, {28,37}, {25,38}, {28,38}, {25,39}, {28,39}, {25,40}, {28,40}, {25,41},
    {28,41}, {25,42}, {28,42}, {25,43}, {28,43}, {25,44}, {28,44}, {25,45}, {28,45}, {25,46},
    {26,46}, {27,46}, {28,46}
    },
  },
}

local function draw_waveform_icon(cx, mid, wf, lv)
  local sprite = LFO_WF_SPRITES[wf]
  if not sprite then return end
  local ox = cx - 16
  local oy = mid - 29
  for slot_lv, pts in pairs(sprite) do
    screen.level(slot_lv == 15 and lv or B.MED)
    for _, p in ipairs(pts) do screen.rect(ox + p[1], oy + p[2], 1, 1) end
    screen.fill()
  end
end

local function draw_tuner_half(ox, oy, focused)
  local cx  = ox + 16
  local lv  = focused and B.FULL or B.MED
  local tlv = tuner.muted and B.MED or lv
  screen.font_size(16); screen.font_face(0)
  screen.level(tlv)
  screen.move(cx, oy + 28); screen.text_center(tuner.note)
  screen.font_size(8)
  if tuner.note ~= "--" then
    screen.level(lv)
    screen.move(cx + 11, oy + 16); screen.text(tostring(tuner.octave))
    if tuner.arrow == 0 then
      screen.circle(cx, oy + 42, 2); screen.fill()
    elseif tuner.arrow < 0 then
      screen.move(cx - 4, oy + 42)
      screen.line(cx - 9, oy + 39); screen.line(cx - 9, oy + 45); screen.fill()
    else
      screen.move(cx + 4, oy + 42)
      screen.line(cx + 9, oy + 39); screen.line(cx + 9, oy + 45); screen.fill()
    end
  end
  screen.level(lv)
  screen.move(cx, oy + 56); screen.text_center("Tuner")
end

local function draw_metro_half(ox, oy, focused)
  local cx  = ox + 16
  local lv  = focused and B.FULL or B.MED
  local bpm_str
  if clock_running then bpm_str = string.format("%.0f", clock.get_tempo())
  else bpm_str = tostring(params:get("metro_bpm") or "?") end
  screen.font_size(8); screen.font_face(0)
  screen.level(metro_active and lv or B.MED)
  screen.move(cx, oy + 22); screen.text_center(bpm_str)
  screen.move(cx, oy + 32); screen.text_center("BPM")
  screen.level(lv)
  screen.move(cx, oy + 56); screen.text_center("Metro")
end

local function draw_lfo_half(ox, oy, idx, focused)
  local cx      = ox + 16
  local mid     = oy + 28
  local lv      = B.FULL
  local enabled = params:get("lfo" .. idx .. "_enable") == 2
  local wf      = params:get("lfo" .. idx .. "_waveform")
  local icon_lv = enabled and lv or B.MED
  draw_waveform_icon(cx, mid, wf, icon_lv)
  screen.font_size(8); screen.font_face(0)
  screen.level(icon_lv)
  screen.move(cx, oy + 56); screen.text_center("LFO " .. idx)
end


local function draw_label_cursor(cx, baseline, text)
  screen.font_size(8); screen.font_face(0)
  local w = screen.text_extents(text)
  local left_x = cx - math.floor(w / 2)
  screen.level(B.FULL)
  screen.rect(left_x - 2, baseline - 5, 1, 1); screen.fill()
end

local function draw_group1_pane()
  screen.clear()
  local p       = view_pane[1]
  local is_left = (p % 2) == 1
  local pair    = math.ceil(p / 2)
  local OX1     = CAB.x
  local OX2     = CAB.x + CAB.w - 33
  local py      = 4

  if pair == 1 then
    draw_tuner_half(OX1, py, is_left)
    draw_metro_half(OX2, py, not is_left)
    if is_left then
      draw_strip("Tuner", "Ref Hz", string.format("%.1f Hz", params:get("tuner_ref")), B.FULL)
    else
      local ms = METRO_STRIP[metro_strip_sel]
      draw_strip("Metro", ms.name, ms.fmt(params:get(ms.id)), B.FULL)
    end
  else
    local lfo_l = (pair - 2) * 2 + 1
    local lfo_r = lfo_l + 1
    draw_lfo_half(OX1, py, lfo_l, is_left)
    draw_lfo_half(OX2, py, lfo_r, not is_left)
    local idx       = is_left and lfo_l or lfo_r
    local strip_idx = lfo_strip_resolve(idx, lfo_strip_sel[idx])
    local ls        = LFO_STRIP[strip_idx]
    local id  = "lfo" .. idx .. ls.suf
    local v1  = ls.fmt(params:get(id), idx)
    local v2  = nil
    if ls.suf == "_waveform" then
      local sp = v1:find(" ")
      if sp then v1, v2 = v1:sub(1, sp - 1), v1:sub(sp + 1) end
    end
    draw_strip("LFO " .. idx, ls.name, v1, B.FULL, v2)
  end

  local cur_cx = (is_left and OX1 or OX2) + 16
  local cur_label
  if pair == 1 then
    cur_label = is_left and "Tuner" or "Metro"
  else
    local lfo_l = (pair - 2) * 2 + 1
    cur_label = "LFO " .. (is_left and lfo_l or (lfo_l + 1))
  end
  draw_label_cursor(cur_cx, py + 56, cur_label)

  screen.update()
end

local function draw_cabinet()
  rect_outline(CAB.x, CAB.y, CAB.w, CAB.h, BORDER_LVL)
  local g = BORDER_GAP
  rect_outline(CAB.x+g, CAB.y+g, CAB.w-g*2, CAB.h-g*2, BORDER_LVL)
end

local function draw_panel()
  screen.level(B.DIM); screen.rect(PANEL.x, PANEL.y, PANEL.w, PANEL.h); screen.fill()

  screen.level(B.FULL)
  screen.rect(PANEL_BUCHSE1, KNOB_Y, 1, 1); screen.fill()
  screen.level(params:get("signal_input") == 2 and B.FULL or B.MED)
  screen.rect(PANEL_BUCHSE2, KNOB_Y, 1, 1); screen.fill()

  screen.level(amp_is_bypassed() and B.MED or B.FULL)
  screen.rect(PANEL_LAMP, KNOB_Y, 1, 1); screen.fill()

  for i = 1, NUM_AMP_KNOBS do
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
  screen.level(B.MED);  screen.move(38, 61); screen.text("A = ")
  screen.level(B.FULL); screen.text(string.format("%.1f Hz", tuner.ref_hz))

  if tuner.muted then
    screen.font_size(8); screen.level(B.MED)
    screen.move(126, 8); screen.text_right("mute")
  end
end


-- ── Pedal sprites (33x56, slot levels: 5=bg 12=foot+led 13=knob1 14=knob2 15=knob3 16=frame) ──
local PEDAL_DISTORT_SPRITE = {  -- 580 px, 33x56
  [5] = {
    {4,19}, {5,19}, {6,19}, {7,19}, {8,19}, {9,19}, {10,19}, {11,19}, {12,19}, {13,19},
    {14,19}, {15,19}, {16,19}, {17,19}, {18,19}, {19,19}, {20,19}, {21,19}, {22,19}, {23,19},
    {24,19}, {25,19}, {26,19}, {27,19}, {28,19}, {4,20}, {8,20}, {9,20}, {10,20}, {11,20},
    {12,20}, {13,20}, {14,20}, {15,20}, {16,20}, {17,20}, {18,20}, {19,20}, {20,20}, {21,20},
    {22,20}, {23,20}, {24,20}, {25,20}, {26,20}, {27,20}, {28,20}, {4,21}, {8,21}, {9,21},
    {10,21}, {11,21}, {12,21}, {13,21}, {14,21}, {15,21}, {16,21}, {17,21}, {18,21}, {19,21},
    {20,21}, {21,21}, {22,21}, {23,21}, {24,21}, {25,21}, {26,21}, {27,21}, {28,21}, {4,22},
    {8,22}, {9,22}, {10,22}, {11,22}, {12,22}, {13,22}, {14,22}, {15,22}, {16,22}, {17,22},
    {18,22}, {19,22}, {20,22}, {21,22}, {22,22}, {23,22}, {24,22}, {25,22}, {26,22}, {27,22},
    {28,22}, {4,23}, {5,23}, {6,23}, {7,23}, {8,23}, {9,23}, {10,23}, {11,23}, {12,23},
    {13,23}, {14,23}, {15,23}, {16,23}, {17,23}, {18,23}, {19,23}, {20,23}, {21,23}, {22,23},
    {23,23}, {24,23}, {25,23}, {26,23}, {27,23}, {28,23}, {4,24}, {5,24}, {6,24}, {7,24},
    {8,24}, {9,24}, {10,24}, {11,24}, {12,24}, {13,24}, {14,24}, {15,24}, {16,24}, {17,24},
    {18,24}, {19,24}, {20,24}, {21,24}, {22,24}, {23,24}, {24,24}, {25,24}, {26,24}, {27,24},
    {28,24}, {4,25}, {5,25}, {6,25}, {7,25}, {8,25}, {9,25}, {10,25}, {11,25}, {12,25},
    {13,25}, {14,25}, {15,25}, {16,25}, {17,25}, {18,25}, {19,25}, {20,25}, {21,25}, {22,25},
    {23,25}, {24,25}, {25,25}, {26,25}, {27,25}, {28,25}, {4,26}, {5,26}, {6,26}, {7,26},
    {8,26}, {9,26}, {10,26}, {11,26}, {12,26}, {13,26}, {14,26}, {15,26}, {16,26}, {17,26},
    {18,26}, {19,26}, {20,26}, {21,26}, {22,26}, {23,26}, {24,26}, {25,26}, {26,26}, {27,26},
    {28,26}, {4,27}, {5,27}, {6,27}, {7,27}, {8,27}, {9,27}, {10,27}, {11,27}, {12,27},
    {13,27}, {14,27}, {15,27}, {16,27}, {17,27}, {18,27}, {19,27}, {20,27}, {21,27}, {22,27},
    {23,27}, {24,27}, {25,27}, {26,27}, {27,27}, {28,27}, {4,28}, {5,28}, {6,28}, {7,28},
    {8,28}, {9,28}, {10,28}, {11,28}, {12,28}, {13,28}, {14,28}, {15,28}, {16,28}, {17,28},
    {18,28}, {19,28}, {20,28}, {21,28}, {22,28}, {23,28}, {24,28}, {25,28}, {26,28}, {27,28},
    {28,28}, {4,29}, {5,29}, {6,29}, {7,29}, {8,29}, {9,29}, {10,29}, {11,29}, {12,29},
    {13,29}, {14,29}, {15,29}, {16,29}, {17,29}, {18,29}, {19,29}, {20,29}, {21,29}, {22,29},
    {23,29}, {24,29}, {25,29}, {26,29}, {27,29}, {28,29}, {4,30}, {5,30}, {6,30}, {7,30},
    {8,30}, {9,30}, {10,30}, {11,30}, {12,30}, {13,30}, {14,30}, {15,30}, {16,30}, {17,30},
    {18,30}, {19,30}, {20,30}, {21,30}, {22,30}, {23,30}, {24,30}, {25,30}, {26,30}, {27,30},
    {28,30}
  },
  [12] = {
    {6,21}, {15,35}, {16,35}, {17,35}, {14,36}, {15,36}, {16,36}, {17,36}, {18,36}, {14,37},
    {15,37}, {16,37}, {17,37}, {18,37}, {14,38}, {15,38}, {16,38}, {17,38}, {18,38}, {15,39},
    {16,39}, {17,39}
  },
  [13] = {
    {6,8}, {7,8}, {8,8}, {5,9}, {6,9}, {7,9}, {8,9}, {9,9}, {4,10}, {5,10},
    {6,10}, {7,10}, {8,10}, {9,10}, {10,10}, {4,11}, {5,11}, {6,11}, {7,11}, {8,11},
    {9,11}, {10,11}, {4,12}, {5,12}, {6,12}, {7,12}, {8,12}, {9,12}, {10,12}, {5,13},
    {6,13}, {7,13}, {8,13}, {9,13}, {6,14}, {7,14}, {8,14}
  },
  [14] = {
    {15,8}, {16,8}, {17,8}, {14,9}, {15,9}, {16,9}, {17,9}, {18,9}, {13,10}, {14,10},
    {15,10}, {16,10}, {17,10}, {18,10}, {19,10}, {13,11}, {14,11}, {15,11}, {16,11}, {17,11},
    {18,11}, {19,11}, {13,12}, {14,12}, {15,12}, {16,12}, {17,12}, {18,12}, {19,12}, {14,13},
    {15,13}, {16,13}, {17,13}, {18,13}, {15,14}, {16,14}, {17,14}
  },
  [15] = {
    {24,8}, {25,8}, {26,8}, {23,9}, {24,9}, {25,9}, {26,9}, {27,9}, {22,10}, {23,10},
    {24,10}, {25,10}, {26,10}, {27,10}, {28,10}, {22,11}, {23,11}, {24,11}, {25,11}, {26,11},
    {27,11}, {28,11}, {22,12}, {23,12}, {24,12}, {25,12}, {26,12}, {27,12}, {28,12}, {23,13},
    {24,13}, {25,13}, {26,13}, {27,13}, {24,14}, {25,14}, {26,14}
  },
  [16] = {
    {0,0}, {1,0}, {2,0}, {3,0}, {4,0}, {5,0}, {6,0}, {7,0}, {8,0}, {9,0},
    {10,0}, {11,0}, {12,0}, {13,0}, {14,0}, {15,0}, {16,0}, {17,0}, {18,0}, {19,0},
    {20,0}, {21,0}, {22,0}, {23,0}, {24,0}, {25,0}, {26,0}, {27,0}, {28,0}, {29,0},
    {30,0}, {31,0}, {32,0}, {0,1}, {32,1}, {0,2}, {32,2}, {0,3}, {32,3}, {0,4},
    {32,4}, {0,5}, {32,5}, {0,6}, {32,6}, {0,7}, {32,7}, {0,8}, {32,8}, {0,9},
    {32,9}, {0,10}, {32,10}, {0,11}, {32,11}, {0,12}, {32,12}, {0,13}, {32,13}, {0,14},
    {32,14}, {0,15}, {32,15}, {0,16}, {32,16}, {0,17}, {32,17}, {0,18}, {32,18}, {0,19},
    {32,19}, {0,20}, {32,20}, {0,21}, {32,21}, {0,22}, {32,22}, {0,23}, {32,23}, {0,24},
    {32,24}, {0,25}, {32,25}, {0,26}, {32,26}, {0,27}, {32,27}, {0,28}, {32,28}, {0,29},
    {32,29}, {0,30}, {32,30}, {0,31}, {32,31}, {0,32}, {32,32}, {0,33}, {32,33}, {0,34},
    {32,34}, {0,35}, {32,35}, {0,36}, {32,36}, {0,37}, {32,37}, {0,38}, {32,38}, {0,39},
    {32,39}, {0,40}, {32,40}, {0,41}, {32,41}, {0,42}, {32,42}, {0,43}, {32,43}, {0,44},
    {32,44}, {0,45}, {32,45}, {0,46}, {1,46}, {2,46}, {3,46}, {4,46}, {5,46}, {6,46},
    {7,46}, {8,46}, {9,46}, {10,46}, {11,46}, {12,46}, {13,46}, {14,46}, {15,46}, {16,46},
    {17,46}, {18,46}, {19,46}, {20,46}, {21,46}, {22,46}, {23,46}, {24,46}, {25,46}, {26,46},
    {27,46}, {28,46}, {29,46}, {30,46}, {31,46}, {32,46}
  },
}

local PEDAL_PUSH_SPRITE = {  -- 790 px, 33x56
  [5] = {
    {3,18}, {4,18}, {5,18}, {6,18}, {7,18}, {8,18}, {9,18}, {10,18}, {11,18}, {12,18},
    {13,18}, {14,18}, {15,18}, {16,18}, {17,18}, {18,18}, {19,18}, {20,18}, {21,18}, {22,18},
    {23,18}, {24,18}, {25,18}, {26,18}, {27,18}, {28,18}, {29,18}, {3,19}, {29,19}, {3,20},
    {5,20}, {6,20}, {7,20}, {8,20}, {9,20}, {10,20}, {11,20}, {12,20}, {13,20}, {14,20},
    {15,20}, {16,20}, {17,20}, {18,20}, {19,20}, {20,20}, {21,20}, {22,20}, {23,20}, {24,20},
    {25,20}, {26,20}, {27,20}, {29,20}, {3,21}, {5,21}, {6,21}, {7,21}, {8,21}, {9,21},
    {10,21}, {11,21}, {12,21}, {13,21}, {14,21}, {15,21}, {16,21}, {17,21}, {18,21}, {19,21},
    {20,21}, {21,21}, {22,21}, {23,21}, {24,21}, {25,21}, {26,21}, {27,21}, {29,21}, {3,22},
    {5,22}, {6,22}, {7,22}, {8,22}, {9,22}, {10,22}, {11,22}, {12,22}, {13,22}, {14,22},
    {15,22}, {16,22}, {17,22}, {18,22}, {19,22}, {20,22}, {21,22}, {22,22}, {23,22}, {24,22},
    {25,22}, {26,22}, {27,22}, {29,22}, {3,23}, {5,23}, {6,23}, {7,23}, {8,23}, {9,23},
    {10,23}, {11,23}, {12,23}, {13,23}, {14,23}, {15,23}, {16,23}, {17,23}, {18,23}, {19,23},
    {20,23}, {21,23}, {22,23}, {23,23}, {24,23}, {25,23}, {26,23}, {27,23}, {29,23}, {3,24},
    {5,24}, {6,24}, {7,24}, {8,24}, {9,24}, {10,24}, {11,24}, {12,24}, {13,24}, {14,24},
    {15,24}, {16,24}, {17,24}, {18,24}, {19,24}, {20,24}, {21,24}, {22,24}, {23,24}, {24,24},
    {25,24}, {26,24}, {27,24}, {29,24}, {3,25}, {5,25}, {6,25}, {7,25}, {8,25}, {9,25},
    {10,25}, {11,25}, {12,25}, {13,25}, {14,25}, {15,25}, {16,25}, {17,25}, {18,25}, {19,25},
    {20,25}, {21,25}, {22,25}, {23,25}, {24,25}, {25,25}, {26,25}, {27,25}, {29,25}, {3,26},
    {29,26}, {3,27}, {29,27}, {3,28}, {29,28}, {3,29}, {29,29}, {3,30}, {29,30}, {3,31},
    {29,31}, {3,32}, {29,32}, {3,33}, {29,33}, {3,34}, {29,34}, {3,35}, {29,35}, {3,36},
    {29,36}, {3,37}, {29,37}, {3,38}, {29,38}, {3,39}, {29,39}, {3,40}, {29,40}, {3,41},
    {29,41}, {3,42}, {29,42}, {3,43}, {4,43}, {5,43}, {6,43}, {7,43}, {8,43}, {9,43},
    {10,43}, {11,43}, {12,43}, {13,43}, {14,43}, {15,43}, {16,43}, {17,43}, {18,43}, {19,43},
    {20,43}, {21,43}, {22,43}, {23,43}, {24,43}, {25,43}, {26,43}, {27,43}, {28,43}, {29,43}
  },
  [12] = {
    {16,3}, {5,27}, {6,27}, {7,27}, {8,27}, {9,27}, {10,27}, {11,27}, {12,27}, {13,27},
    {14,27}, {15,27}, {16,27}, {17,27}, {18,27}, {19,27}, {20,27}, {21,27}, {22,27}, {23,27},
    {24,27}, {25,27}, {26,27}, {27,27}, {5,28}, {6,28}, {7,28}, {8,28}, {9,28}, {10,28},
    {11,28}, {12,28}, {13,28}, {14,28}, {15,28}, {16,28}, {17,28}, {18,28}, {19,28}, {20,28},
    {21,28}, {22,28}, {23,28}, {24,28}, {25,28}, {26,28}, {27,28}, {5,29}, {6,29}, {7,29},
    {8,29}, {9,29}, {10,29}, {11,29}, {12,29}, {13,29}, {14,29}, {15,29}, {16,29}, {17,29},
    {18,29}, {19,29}, {20,29}, {21,29}, {22,29}, {23,29}, {24,29}, {25,29}, {26,29}, {27,29},
    {5,30}, {27,30}, {5,31}, {6,31}, {7,31}, {8,31}, {9,31}, {10,31}, {11,31}, {12,31},
    {13,31}, {14,31}, {15,31}, {16,31}, {17,31}, {18,31}, {19,31}, {20,31}, {21,31}, {22,31},
    {23,31}, {24,31}, {25,31}, {26,31}, {27,31}, {5,32}, {6,32}, {7,32}, {8,32}, {9,32},
    {10,32}, {11,32}, {12,32}, {13,32}, {14,32}, {15,32}, {16,32}, {17,32}, {18,32}, {19,32},
    {20,32}, {21,32}, {22,32}, {23,32}, {24,32}, {25,32}, {26,32}, {27,32}, {5,33}, {6,33},
    {7,33}, {8,33}, {9,33}, {10,33}, {11,33}, {12,33}, {13,33}, {14,33}, {15,33}, {16,33},
    {17,33}, {18,33}, {19,33}, {20,33}, {21,33}, {22,33}, {23,33}, {24,33}, {25,33}, {26,33},
    {27,33}, {5,34}, {27,34}, {5,35}, {6,35}, {7,35}, {8,35}, {9,35}, {10,35}, {11,35},
    {12,35}, {13,35}, {14,35}, {15,35}, {16,35}, {17,35}, {18,35}, {19,35}, {20,35}, {21,35},
    {22,35}, {23,35}, {24,35}, {25,35}, {26,35}, {27,35}, {5,36}, {6,36}, {7,36}, {8,36},
    {9,36}, {10,36}, {11,36}, {12,36}, {13,36}, {14,36}, {15,36}, {16,36}, {17,36}, {18,36},
    {19,36}, {20,36}, {21,36}, {22,36}, {23,36}, {24,36}, {25,36}, {26,36}, {27,36}, {5,37},
    {6,37}, {7,37}, {8,37}, {9,37}, {10,37}, {11,37}, {12,37}, {13,37}, {14,37}, {15,37},
    {16,37}, {17,37}, {18,37}, {19,37}, {20,37}, {21,37}, {22,37}, {23,37}, {24,37}, {25,37},
    {26,37}, {27,37}, {5,38}, {27,38}, {5,39}, {6,39}, {7,39}, {8,39}, {9,39}, {10,39},
    {11,39}, {12,39}, {13,39}, {14,39}, {15,39}, {16,39}, {17,39}, {18,39}, {19,39}, {20,39},
    {21,39}, {22,39}, {23,39}, {24,39}, {25,39}, {26,39}, {27,39}, {5,40}, {6,40}, {7,40},
    {8,40}, {9,40}, {10,40}, {11,40}, {12,40}, {13,40}, {14,40}, {15,40}, {16,40}, {17,40},
    {18,40}, {19,40}, {20,40}, {21,40}, {22,40}, {23,40}, {24,40}, {25,40}, {26,40}, {27,40},
    {5,41}, {6,41}, {7,41}, {8,41}, {9,41}, {10,41}, {11,41}, {12,41}, {13,41}, {14,41},
    {15,41}, {16,41}, {17,41}, {18,41}, {19,41}, {20,41}, {21,41}, {22,41}, {23,41}, {24,41},
    {25,41}, {26,41}, {27,41}
  },
  [13] = {
    {6,3}, {7,3}, {8,3}, {5,4}, {6,4}, {7,4}, {8,4}, {9,4}, {4,5}, {5,5},
    {6,5}, {7,5}, {8,5}, {9,5}, {10,5}, {4,6}, {5,6}, {6,6}, {7,6}, {8,6},
    {9,6}, {10,6}, {4,7}, {5,7}, {6,7}, {7,7}, {8,7}, {9,7}, {10,7}, {5,8},
    {6,8}, {7,8}, {8,8}, {9,8}, {6,9}, {7,9}, {8,9}
  },
  [14] = {
    {15,9}, {16,9}, {17,9}, {14,10}, {15,10}, {16,10}, {17,10}, {18,10}, {13,11}, {14,11},
    {15,11}, {16,11}, {17,11}, {18,11}, {19,11}, {13,12}, {14,12}, {15,12}, {16,12}, {17,12},
    {18,12}, {19,12}, {13,13}, {14,13}, {15,13}, {16,13}, {17,13}, {18,13}, {19,13}, {14,14},
    {15,14}, {16,14}, {17,14}, {18,14}, {15,15}, {16,15}, {17,15}
  },
  [15] = {
    {24,3}, {25,3}, {26,3}, {23,4}, {24,4}, {25,4}, {26,4}, {27,4}, {22,5}, {23,5},
    {24,5}, {25,5}, {26,5}, {27,5}, {28,5}, {22,6}, {23,6}, {24,6}, {25,6}, {26,6},
    {27,6}, {28,6}, {22,7}, {23,7}, {24,7}, {25,7}, {26,7}, {27,7}, {28,7}, {23,8},
    {24,8}, {25,8}, {26,8}, {27,8}, {24,9}, {25,9}, {26,9}
  },
  [16] = {
    {0,0}, {1,0}, {2,0}, {3,0}, {4,0}, {5,0}, {6,0}, {7,0}, {8,0}, {9,0},
    {10,0}, {11,0}, {12,0}, {13,0}, {14,0}, {15,0}, {16,0}, {17,0}, {18,0}, {19,0},
    {20,0}, {21,0}, {22,0}, {23,0}, {24,0}, {25,0}, {26,0}, {27,0}, {28,0}, {29,0},
    {30,0}, {31,0}, {32,0}, {0,1}, {32,1}, {0,2}, {32,2}, {0,3}, {32,3}, {0,4},
    {32,4}, {0,5}, {32,5}, {0,6}, {32,6}, {0,7}, {32,7}, {0,8}, {32,8}, {0,9},
    {32,9}, {0,10}, {32,10}, {0,11}, {32,11}, {0,12}, {32,12}, {0,13}, {32,13}, {0,14},
    {32,14}, {0,15}, {32,15}, {0,16}, {32,16}, {0,17}, {32,17}, {0,18}, {32,18}, {0,19},
    {32,19}, {0,20}, {32,20}, {0,21}, {32,21}, {0,22}, {32,22}, {0,23}, {32,23}, {0,24},
    {32,24}, {0,25}, {32,25}, {0,26}, {32,26}, {0,27}, {32,27}, {0,28}, {32,28}, {0,29},
    {32,29}, {0,30}, {32,30}, {0,31}, {32,31}, {0,32}, {32,32}, {0,33}, {32,33}, {0,34},
    {32,34}, {0,35}, {32,35}, {0,36}, {32,36}, {0,37}, {32,37}, {0,38}, {32,38}, {0,39},
    {32,39}, {0,40}, {32,40}, {0,41}, {32,41}, {0,42}, {32,42}, {0,43}, {32,43}, {0,44},
    {32,44}, {0,45}, {32,45}, {0,46}, {1,46}, {2,46}, {3,46}, {4,46}, {5,46}, {6,46},
    {7,46}, {8,46}, {9,46}, {10,46}, {11,46}, {12,46}, {13,46}, {14,46}, {15,46}, {16,46},
    {17,46}, {18,46}, {19,46}, {20,46}, {21,46}, {22,46}, {23,46}, {24,46}, {25,46}, {26,46},
    {27,46}, {28,46}, {29,46}, {30,46}, {31,46}, {32,46}
  },
}

local PEDAL_REPEAT_SPRITE = {  -- 468 px, 33x56
  [5] = {
    {3,32}, {4,32}, {5,32}, {6,32}, {7,32}, {8,32}, {9,32}, {10,32}, {11,32}, {12,32},
    {13,32}, {14,32}, {15,32}, {16,32}, {17,32}, {18,32}, {19,32}, {20,32}, {21,32}, {22,32},
    {23,32}, {24,32}, {25,32}, {26,32}, {27,32}, {28,32}, {29,32}, {3,33}, {15,33}, {16,33},
    {17,33}, {29,33}, {3,34}, {15,34}, {16,34}, {17,34}, {29,34}, {3,35}, {29,35}, {3,36},
    {29,36}, {3,37}, {29,37}, {3,38}, {29,38}, {3,39}, {29,39}, {3,40}, {29,40}, {3,41},
    {29,41}, {3,42}, {29,42}, {3,43}, {4,43}, {5,43}, {6,43}, {7,43}, {8,43}, {9,43},
    {10,43}, {11,43}, {12,43}, {13,43}, {14,43}, {15,43}, {16,43}, {17,43}, {18,43}, {19,43},
    {20,43}, {21,43}, {22,43}, {23,43}, {24,43}, {25,43}, {26,43}, {27,43}, {28,43}, {29,43}
  },
  [12] = {
    {28,4}, {5,34}, {6,34}, {7,34}, {8,34}, {9,34}, {10,34}, {11,34}, {12,34}, {13,34},
    {19,34}, {20,34}, {21,34}, {22,34}, {23,34}, {24,34}, {25,34}, {26,34}, {27,34}, {5,35},
    {6,35}, {7,35}, {8,35}, {9,35}, {10,35}, {11,35}, {12,35}, {13,35}, {19,35}, {20,35},
    {21,35}, {22,35}, {23,35}, {24,35}, {25,35}, {26,35}, {27,35}, {5,36}, {12,36}, {13,36},
    {14,36}, {15,36}, {16,36}, {17,36}, {18,36}, {19,36}, {20,36}, {27,36}, {5,37}, {6,37},
    {7,37}, {8,37}, {9,37}, {10,37}, {11,37}, {12,37}, {13,37}, {14,37}, {15,37}, {16,37},
    {17,37}, {18,37}, {19,37}, {20,37}, {21,37}, {22,37}, {23,37}, {24,37}, {25,37}, {26,37},
    {27,37}, {5,38}, {27,38}, {5,39}, {6,39}, {7,39}, {8,39}, {9,39}, {10,39}, {11,39},
    {12,39}, {13,39}, {14,39}, {15,39}, {16,39}, {17,39}, {18,39}, {19,39}, {20,39}, {21,39},
    {22,39}, {23,39}, {24,39}, {25,39}, {26,39}, {27,39}, {5,40}, {27,40}, {5,41}, {6,41},
    {7,41}, {8,41}, {9,41}, {10,41}, {11,41}, {12,41}, {13,41}, {14,41}, {15,41}, {16,41},
    {17,41}, {18,41}, {19,41}, {20,41}, {21,41}, {22,41}, {23,41}, {24,41}, {25,41}, {26,41},
    {27,41}
  },
  [13] = {
    {5,3}, {6,3}, {7,3}, {4,4}, {5,4}, {6,4}, {7,4}, {8,4}, {3,5}, {4,5},
    {5,5}, {6,5}, {7,5}, {8,5}, {9,5}, {3,6}, {4,6}, {5,6}, {6,6}, {7,6},
    {8,6}, {9,6}, {3,7}, {4,7}, {5,7}, {6,7}, {7,7}, {8,7}, {9,7}, {4,8},
    {5,8}, {6,8}, {7,8}, {8,8}, {5,9}, {6,9}, {7,9}
  },
  [14] = {
    {5,13}, {6,13}, {7,13}, {4,14}, {5,14}, {6,14}, {7,14}, {8,14}, {3,15}, {4,15},
    {5,15}, {6,15}, {7,15}, {8,15}, {9,15}, {3,16}, {4,16}, {5,16}, {6,16}, {7,16},
    {8,16}, {9,16}, {3,17}, {4,17}, {5,17}, {6,17}, {7,17}, {8,17}, {9,17}, {4,18},
    {5,18}, {6,18}, {7,18}, {8,18}, {5,19}, {6,19}, {7,19}
  },
  [15] = {
    {5,23}, {6,23}, {7,23}, {4,24}, {5,24}, {6,24}, {7,24}, {8,24}, {3,25}, {4,25},
    {5,25}, {6,25}, {7,25}, {8,25}, {9,25}, {3,26}, {4,26}, {5,26}, {6,26}, {7,26},
    {8,26}, {9,26}, {3,27}, {4,27}, {5,27}, {6,27}, {7,27}, {8,27}, {9,27}, {4,28},
    {5,28}, {6,28}, {7,28}, {8,28}, {5,29}, {6,29}, {7,29}
  },
  [16] = {
    {0,0}, {1,0}, {2,0}, {3,0}, {4,0}, {5,0}, {6,0}, {7,0}, {8,0}, {9,0},
    {10,0}, {11,0}, {12,0}, {13,0}, {14,0}, {15,0}, {16,0}, {17,0}, {18,0}, {19,0},
    {20,0}, {21,0}, {22,0}, {23,0}, {24,0}, {25,0}, {26,0}, {27,0}, {28,0}, {29,0},
    {30,0}, {31,0}, {32,0}, {0,1}, {32,1}, {0,2}, {32,2}, {0,3}, {32,3}, {0,4},
    {32,4}, {0,5}, {32,5}, {0,6}, {32,6}, {0,7}, {32,7}, {0,8}, {32,8}, {0,9},
    {32,9}, {0,10}, {32,10}, {0,11}, {32,11}, {0,12}, {32,12}, {0,13}, {32,13}, {0,14},
    {32,14}, {0,15}, {32,15}, {0,16}, {32,16}, {0,17}, {32,17}, {0,18}, {32,18}, {0,19},
    {32,19}, {0,20}, {32,20}, {0,21}, {32,21}, {0,22}, {32,22}, {0,23}, {32,23}, {0,24},
    {32,24}, {0,25}, {32,25}, {0,26}, {32,26}, {0,27}, {32,27}, {0,28}, {32,28}, {0,29},
    {32,29}, {0,30}, {32,30}, {0,31}, {32,31}, {0,32}, {32,32}, {0,33}, {32,33}, {0,34},
    {32,34}, {0,35}, {32,35}, {0,36}, {32,36}, {0,37}, {32,37}, {0,38}, {32,38}, {0,39},
    {32,39}, {0,40}, {32,40}, {0,41}, {32,41}, {0,42}, {32,42}, {0,43}, {32,43}, {0,44},
    {32,44}, {0,45}, {32,45}, {0,46}, {1,46}, {2,46}, {3,46}, {4,46}, {5,46}, {6,46},
    {7,46}, {8,46}, {9,46}, {10,46}, {11,46}, {12,46}, {13,46}, {14,46}, {15,46}, {16,46},
    {17,46}, {18,46}, {19,46}, {20,46}, {21,46}, {22,46}, {23,46}, {24,46}, {25,46}, {26,46},
    {27,46}, {28,46}, {29,46}, {30,46}, {31,46}, {32,46}
  },
}

local PEDAL_WARP_SPRITE = {  -- 803 px, 33x56
  [5] = {
    {2,2}, {3,2}, {4,2}, {5,2}, {6,2}, {7,2}, {8,2}, {9,2}, {10,2}, {11,2},
    {21,2}, {22,2}, {23,2}, {24,2}, {25,2}, {26,2}, {27,2}, {28,2}, {29,2}, {30,2},
    {2,3}, {30,3}, {2,4}, {30,4}, {2,5}, {30,5}, {2,6}, {30,6}, {2,7}, {30,7},
    {2,8}, {30,8}, {2,9}, {30,9}, {2,19}, {30,19}, {2,20}, {30,20}, {2,21}, {30,21},
    {2,22}, {30,22}, {2,23}, {3,23}, {4,23}, {5,23}, {6,23}, {7,23}, {8,23}, {9,23},
    {10,23}, {11,23}, {12,23}, {13,23}, {14,23}, {15,23}, {16,23}, {17,23}, {18,23}, {19,23},
    {20,23}, {21,23}, {22,23}, {23,23}, {24,23}, {25,23}, {26,23}, {27,23}, {28,23}, {29,23},
    {30,23}, {2,24}, {3,24}, {4,24}, {5,24}, {6,24}, {7,24}, {8,24}, {9,24}, {10,24},
    {11,24}, {12,24}, {20,24}, {21,24}, {22,24}, {23,24}, {24,24}, {25,24}, {26,24}, {27,24},
    {28,24}, {29,24}, {30,24}, {2,25}, {3,25}, {4,25}, {5,25}, {6,25}, {7,25}, {8,25},
    {9,25}, {10,25}, {11,25}, {12,25}, {20,25}, {21,25}, {22,25}, {23,25}, {24,25}, {25,25},
    {26,25}, {27,25}, {28,25}, {29,25}, {30,25}, {2,26}, {3,26}, {4,26}, {5,26}, {6,26},
    {7,26}, {8,26}, {9,26}, {10,26}, {11,26}, {12,26}, {20,26}, {21,26}, {22,26}, {23,26},
    {24,26}, {25,26}, {26,26}, {27,26}, {28,26}, {29,26}, {30,26}, {2,27}, {3,27}, {4,27},
    {5,27}, {6,27}, {7,27}, {8,27}, {9,27}, {10,27}, {11,27}, {12,27}, {13,27}, {14,27},
    {15,27}, {16,27}, {17,27}, {18,27}, {19,27}, {20,27}, {21,27}, {22,27}, {23,27}, {24,27},
    {25,27}, {26,27}, {27,27}, {28,27}, {29,27}, {30,27}, {2,28}, {3,28}, {4,28}, {28,28},
    {29,28}, {30,28}, {2,29}, {30,29}, {2,30}, {30,30}, {2,31}, {30,31}, {2,32}, {30,32},
    {2,33}, {30,33}, {2,34}, {30,34}, {2,35}, {30,35}, {2,36}, {30,36}, {2,37}, {30,37},
    {2,38}, {30,38}, {2,39}, {30,39}, {2,40}, {30,40}, {2,41}, {30,41}, {2,42}, {30,42},
    {2,43}, {30,43}, {2,44}, {3,44}, {4,44}, {5,44}, {6,44}, {7,44}, {8,44}, {9,44},
    {10,44}, {11,44}, {12,44}, {13,44}, {14,44}, {15,44}, {16,44}, {17,44}, {18,44}, {19,44},
    {20,44}, {21,44}, {22,44}, {23,44}, {24,44}, {25,44}, {26,44}, {27,44}, {28,44}, {29,44},
    {30,44}
  },
  [12] = {
    {14,25}, {15,25}, {16,25}, {17,25}, {18,25}, {6,29}, {7,29}, {8,29}, {9,29}, {10,29},
    {11,29}, {12,29}, {13,29}, {14,29}, {15,29}, {16,29}, {17,29}, {18,29}, {19,29}, {20,29},
    {21,29}, {22,29}, {23,29}, {24,29}, {25,29}, {26,29}, {4,30}, {5,30}, {6,30}, {7,30},
    {8,30}, {9,30}, {10,30}, {11,30}, {12,30}, {13,30}, {14,30}, {15,30}, {16,30}, {17,30},
    {18,30}, {19,30}, {20,30}, {21,30}, {22,30}, {23,30}, {24,30}, {25,30}, {26,30}, {27,30},
    {28,30}, {4,31}, {5,31}, {6,31}, {7,31}, {8,31}, {9,31}, {10,31}, {11,31}, {12,31},
    {13,31}, {14,31}, {15,31}, {16,31}, {17,31}, {18,31}, {19,31}, {20,31}, {21,31}, {22,31},
    {23,31}, {24,31}, {25,31}, {26,31}, {27,31}, {28,31}, {4,32}, {5,32}, {6,32}, {7,32},
    {8,32}, {9,32}, {10,32}, {11,32}, {12,32}, {13,32}, {14,32}, {15,32}, {16,32}, {17,32},
    {18,32}, {19,32}, {20,32}, {21,32}, {22,32}, {23,32}, {24,32}, {25,32}, {26,32}, {27,32},
    {28,32}, {4,33}, {5,33}, {6,33}, {7,33}, {8,33}, {9,33}, {10,33}, {11,33}, {12,33},
    {13,33}, {14,33}, {15,33}, {16,33}, {17,33}, {18,33}, {19,33}, {20,33}, {21,33}, {22,33},
    {23,33}, {24,33}, {25,33}, {26,33}, {27,33}, {28,33}, {4,34}, {5,34}, {6,34}, {7,34},
    {8,34}, {9,34}, {10,34}, {11,34}, {12,34}, {13,34}, {14,34}, {15,34}, {16,34}, {17,34},
    {18,34}, {19,34}, {20,34}, {21,34}, {22,34}, {23,34}, {24,34}, {25,34}, {26,34}, {27,34},
    {28,34}, {4,35}, {5,35}, {6,35}, {7,35}, {8,35}, {9,35}, {10,35}, {11,35}, {12,35},
    {13,35}, {14,35}, {15,35}, {16,35}, {17,35}, {18,35}, {19,35}, {20,35}, {21,35}, {22,35},
    {23,35}, {24,35}, {25,35}, {26,35}, {27,35}, {28,35}, {4,36}, {5,36}, {6,36}, {7,36},
    {8,36}, {9,36}, {10,36}, {11,36}, {12,36}, {13,36}, {14,36}, {15,36}, {16,36}, {17,36},
    {18,36}, {19,36}, {20,36}, {21,36}, {22,36}, {23,36}, {24,36}, {25,36}, {26,36}, {27,36},
    {28,36}, {4,37}, {5,37}, {6,37}, {7,37}, {8,37}, {9,37}, {10,37}, {11,37}, {12,37},
    {13,37}, {14,37}, {15,37}, {16,37}, {17,37}, {18,37}, {19,37}, {20,37}, {21,37}, {22,37},
    {23,37}, {24,37}, {25,37}, {26,37}, {27,37}, {28,37}, {4,38}, {5,38}, {6,38}, {7,38},
    {8,38}, {9,38}, {10,38}, {11,38}, {12,38}, {13,38}, {14,38}, {15,38}, {16,38}, {17,38},
    {18,38}, {19,38}, {20,38}, {21,38}, {22,38}, {23,38}, {24,38}, {25,38}, {26,38}, {27,38},
    {28,38}, {4,39}, {28,39}, {4,40}, {5,40}, {6,40}, {7,40}, {8,40}, {9,40}, {10,40},
    {11,40}, {12,40}, {13,40}, {14,40}, {15,40}, {16,40}, {17,40}, {18,40}, {19,40}, {20,40},
    {21,40}, {22,40}, {23,40}, {24,40}, {25,40}, {26,40}, {27,40}, {28,40}, {4,41}, {28,41},
    {4,42}, {5,42}, {6,42}, {7,42}, {8,42}, {9,42}, {10,42}, {11,42}, {12,42}, {13,42},
    {14,42}, {15,42}, {16,42}, {17,42}, {18,42}, {19,42}, {20,42}, {21,42}, {22,42}, {23,42},
    {24,42}, {25,42}, {26,42}, {27,42}, {28,42}
  },
  [13] = {
    {15,2}, {16,2}, {17,2}, {14,3}, {15,3}, {16,3}, {17,3}, {18,3}, {13,4}, {14,4},
    {15,4}, {16,4}, {17,4}, {18,4}, {19,4}, {13,5}, {14,5}, {15,5}, {16,5}, {17,5},
    {18,5}, {19,5}, {13,6}, {14,6}, {15,6}, {16,6}, {17,6}, {18,6}, {19,6}, {14,7},
    {15,7}, {16,7}, {17,7}, {18,7}, {15,8}, {16,8}, {17,8}
  },
  [14] = {
    {4,11}, {5,11}, {6,11}, {3,12}, {4,12}, {5,12}, {6,12}, {7,12}, {2,13}, {3,13},
    {4,13}, {5,13}, {6,13}, {7,13}, {8,13}, {2,14}, {3,14}, {4,14}, {5,14}, {6,14},
    {7,14}, {8,14}, {2,15}, {3,15}, {4,15}, {5,15}, {6,15}, {7,15}, {8,15}, {3,16},
    {4,16}, {5,16}, {6,16}, {7,16}, {4,17}, {5,17}, {6,17}
  },
  [15] = {
    {26,11}, {27,11}, {28,11}, {25,12}, {26,12}, {27,12}, {28,12}, {29,12}, {24,13}, {25,13},
    {26,13}, {27,13}, {28,13}, {29,13}, {30,13}, {24,14}, {25,14}, {26,14}, {27,14}, {28,14},
    {29,14}, {30,14}, {24,15}, {25,15}, {26,15}, {27,15}, {28,15}, {29,15}, {30,15}, {25,16},
    {26,16}, {27,16}, {28,16}, {29,16}, {26,17}, {27,17}, {28,17}
  },
  [16] = {
    {0,0}, {1,0}, {2,0}, {3,0}, {4,0}, {5,0}, {6,0}, {7,0}, {8,0}, {9,0},
    {10,0}, {11,0}, {12,0}, {13,0}, {14,0}, {15,0}, {16,0}, {17,0}, {18,0}, {19,0},
    {20,0}, {21,0}, {22,0}, {23,0}, {24,0}, {25,0}, {26,0}, {27,0}, {28,0}, {29,0},
    {30,0}, {31,0}, {32,0}, {0,1}, {32,1}, {0,2}, {32,2}, {0,3}, {32,3}, {0,4},
    {32,4}, {0,5}, {32,5}, {0,6}, {32,6}, {0,7}, {32,7}, {0,8}, {32,8}, {0,9},
    {32,9}, {0,10}, {32,10}, {0,11}, {32,11}, {0,12}, {32,12}, {0,13}, {32,13}, {0,14},
    {32,14}, {0,15}, {32,15}, {0,16}, {32,16}, {0,17}, {32,17}, {0,18}, {32,18}, {0,19},
    {32,19}, {0,20}, {32,20}, {0,21}, {32,21}, {0,22}, {32,22}, {0,23}, {32,23}, {0,24},
    {32,24}, {0,25}, {32,25}, {0,26}, {32,26}, {0,27}, {32,27}, {0,28}, {32,28}, {0,29},
    {32,29}, {0,30}, {32,30}, {0,31}, {32,31}, {0,32}, {32,32}, {0,33}, {32,33}, {0,34},
    {32,34}, {0,35}, {32,35}, {0,36}, {32,36}, {0,37}, {32,37}, {0,38}, {32,38}, {0,39},
    {32,39}, {0,40}, {32,40}, {0,41}, {32,41}, {0,42}, {32,42}, {0,43}, {32,43}, {0,44},
    {32,44}, {0,45}, {32,45}, {0,46}, {1,46}, {2,46}, {3,46}, {4,46}, {5,46}, {6,46},
    {7,46}, {8,46}, {9,46}, {10,46}, {11,46}, {12,46}, {13,46}, {14,46}, {15,46}, {16,46},
    {17,46}, {18,46}, {19,46}, {20,46}, {21,46}, {22,46}, {23,46}, {24,46}, {25,46}, {26,46},
    {27,46}, {28,46}, {29,46}, {30,46}, {31,46}, {32,46}
  },
}

local PEDAL_SPRITES = {
  push       = PEDAL_PUSH_SPRITE,
  distort    = PEDAL_DISTORT_SPRITE,
  warp       = PEDAL_WARP_SPRITE,
  ["repeat"] = PEDAL_REPEAT_SPRITE,
}

local function draw_pedal(ox, oy, name, display, bypassed, focused_knob)
  local sprite = PEDAL_SPRITES[name:lower()]
  if sprite then
    local oy_sprite = oy - 1
    local fs_lv     = bypassed and B.MED or B.FULL
    local focus_lv  = (focused_knob == 1 and 13)
                   or (focused_knob == 2 and 14)
                   or (focused_knob == 3 and 15)
                   or (focused_knob == 4 and 16)
                   or nil
    for slot, pts in pairs(sprite) do
      local sl
      if     slot == 12       then sl = fs_lv
      elseif slot == focus_lv then sl = B.FULL
      else                         sl = B.MED end
      screen.level(sl)
      for _, p in ipairs(pts) do screen.rect(ox + p[1], oy_sprite + p[2], 1, 1) end
      screen.fill()
    end
  end
  screen.font_size(8); screen.font_face(0)
  screen.level(bypassed and B.MED or B.FULL)
  screen.move(ox + 16, oy + 56); screen.text_center(display)
end

local function draw_pedalboard()
  screen.clear()

  local psel = cur_pedal_sel()
  local pd   = cur_pedal()
  local p    = pd.params[pd.psel]
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

  if view_pane[3] >= 3 then
    local fk3 = (psel == 3) and pd.psel or nil
    local fk4 = (psel == 4) and pd.psel or nil
    draw_pedal(OX1, py, PEDALS[3].name, PEDALS[3].display, params:get(PEDALS[3].enable_id) == 1, fk3)
    draw_pedal(OX2, py, PEDALS[4].name, PEDALS[4].display, params:get(PEDALS[4].enable_id) == 1, fk4)
  else
    local fk1 = (psel == 1) and pd.psel or nil
    local fk2 = (psel == 2) and pd.psel or nil
    draw_pedal(OX1, py, PEDALS[1].name, PEDALS[1].display, params:get(PEDALS[1].enable_id) == 1, fk1)
    draw_pedal(OX2, py, PEDALS[2].name, PEDALS[2].display, params:get(PEDALS[2].enable_id) == 1, fk2)
  end
  local cur_cx = ((psel % 2 == 1) and OX1 or OX2) + 16
  draw_label_cursor(cur_cx, py + 56, PEDALS[psel].display)

  screen.update()
end


-- ── Looper sprite (cabinet 82x56 at screen origin (45,4), 0-based) ─────
-- Slot dispatch:
--   [5]  bg       → always B.MED
--   [12] knob N   → B.FULL when looper_sel == N (N derived from x bbox)
--   [13] ldisp    → B.FULL when loop_state in {STOP, IDLE}
--   [14] rdisp    → B.FULL when loop_state in {REC, PLAY, DUB}
--   [15] led      → B.FULL when quant_led_lit
local LOOPER_SPRITE = {  -- 2954 px, 83x57
  [5] = {
    {0,0}, {1,0}, {2,0}, {3,0}, {4,0}, {5,0}, {6,0}, {7,0}, {8,0}, {9,0},
    {10,0}, {11,0}, {12,0}, {13,0}, {14,0}, {15,0}, {16,0}, {17,0}, {18,0}, {19,0},
    {20,0}, {21,0}, {22,0}, {23,0}, {24,0}, {25,0}, {26,0}, {27,0}, {28,0}, {29,0},
    {30,0}, {31,0}, {32,0}, {33,0}, {34,0}, {35,0}, {36,0}, {37,0}, {38,0}, {39,0},
    {40,0}, {41,0}, {42,0}, {43,0}, {44,0}, {45,0}, {46,0}, {47,0}, {48,0}, {49,0},
    {50,0}, {51,0}, {52,0}, {53,0}, {54,0}, {55,0}, {56,0}, {57,0}, {58,0}, {59,0},
    {60,0}, {61,0}, {62,0}, {63,0}, {64,0}, {65,0}, {66,0}, {67,0}, {68,0}, {69,0},
    {70,0}, {71,0}, {72,0}, {73,0}, {74,0}, {75,0}, {76,0}, {77,0}, {78,0}, {79,0},
    {80,0}, {81,0}, {82,0}, {0,1}, {82,1}, {0,2}, {82,2}, {0,3}, {82,3}, {0,4},
    {82,4}, {0,5}, {82,5}, {0,6}, {82,6}, {0,7}, {82,7}, {0,8}, {82,8}, {0,9},
    {82,9}, {0,10}, {82,10}, {0,11}, {82,11}, {0,12}, {82,12}, {0,13}, {82,13}, {0,14},
    {2,14}, {3,14}, {4,14}, {5,14}, {6,14}, {7,14}, {8,14}, {9,14}, {10,14}, {11,14},
    {12,14}, {13,14}, {14,14}, {15,14}, {16,14}, {17,14}, {18,14}, {19,14}, {20,14}, {21,14},
    {22,14}, {23,14}, {24,14}, {25,14}, {26,14}, {27,14}, {28,14}, {29,14}, {30,14}, {31,14},
    {32,14}, {33,14}, {34,14}, {35,14}, {36,14}, {37,14}, {38,14}, {39,14}, {40,14}, {42,14},
    {43,14}, {44,14}, {45,14}, {46,14}, {47,14}, {48,14}, {49,14}, {50,14}, {51,14}, {52,14},
    {53,14}, {54,14}, {55,14}, {56,14}, {57,14}, {58,14}, {59,14}, {60,14}, {61,14}, {62,14},
    {63,14}, {64,14}, {65,14}, {66,14}, {67,14}, {68,14}, {69,14}, {70,14}, {71,14}, {72,14},
    {73,14}, {74,14}, {75,14}, {76,14}, {77,14}, {78,14}, {79,14}, {80,14}, {82,14}, {0,15},
    {2,15}, {40,15}, {42,15}, {80,15}, {82,15}, {0,16}, {2,16}, {4,16}, {5,16}, {6,16},
    {7,16}, {8,16}, {9,16}, {10,16}, {11,16}, {12,16}, {13,16}, {14,16}, {15,16}, {16,16},
    {17,16}, {18,16}, {19,16}, {20,16}, {21,16}, {22,16}, {23,16}, {24,16}, {25,16}, {26,16},
    {27,16}, {28,16}, {29,16}, {30,16}, {31,16}, {32,16}, {33,16}, {34,16}, {35,16}, {36,16},
    {37,16}, {38,16}, {40,16}, {42,16}, {44,16}, {45,16}, {46,16}, {47,16}, {48,16}, {49,16},
    {50,16}, {51,16}, {52,16}, {53,16}, {54,16}, {55,16}, {56,16}, {57,16}, {58,16}, {59,16},
    {60,16}, {61,16}, {62,16}, {63,16}, {64,16}, {65,16}, {66,16}, {67,16}, {68,16}, {69,16},
    {70,16}, {71,16}, {72,16}, {73,16}, {74,16}, {75,16}, {76,16}, {77,16}, {78,16}, {80,16},
    {82,16}, {0,17}, {2,17}, {4,17}, {5,17}, {6,17}, {7,17}, {8,17}, {9,17}, {10,17},
    {11,17}, {12,17}, {13,17}, {14,17}, {15,17}, {16,17}, {17,17}, {18,17}, {19,17}, {20,17},
    {21,17}, {22,17}, {23,17}, {24,17}, {25,17}, {26,17}, {27,17}, {28,17}, {29,17}, {30,17},
    {31,17}, {32,17}, {33,17}, {34,17}, {35,17}, {36,17}, {37,17}, {38,17}, {40,17}, {42,17},
    {44,17}, {45,17}, {46,17}, {47,17}, {48,17}, {49,17}, {50,17}, {51,17}, {52,17}, {53,17},
    {54,17}, {55,17}, {56,17}, {57,17}, {58,17}, {59,17}, {60,17}, {61,17}, {62,17}, {63,17},
    {64,17}, {65,17}, {66,17}, {67,17}, {68,17}, {69,17}, {70,17}, {71,17}, {72,17}, {73,17},
    {74,17}, {75,17}, {76,17}, {77,17}, {78,17}, {80,17}, {82,17}, {0,18}, {2,18}, {4,18},
    {5,18}, {6,18}, {7,18}, {8,18}, {9,18}, {10,18}, {11,18}, {12,18}, {13,18}, {14,18},
    {15,18}, {16,18}, {17,18}, {18,18}, {19,18}, {20,18}, {21,18}, {22,18}, {23,18}, {24,18},
    {25,18}, {26,18}, {27,18}, {28,18}, {29,18}, {30,18}, {31,18}, {32,18}, {33,18}, {34,18},
    {35,18}, {36,18}, {37,18}, {38,18}, {40,18}, {42,18}, {44,18}, {45,18}, {46,18}, {47,18},
    {48,18}, {49,18}, {50,18}, {51,18}, {52,18}, {53,18}, {54,18}, {55,18}, {56,18}, {57,18},
    {58,18}, {59,18}, {60,18}, {61,18}, {62,18}, {63,18}, {64,18}, {65,18}, {66,18}, {67,18},
    {68,18}, {69,18}, {70,18}, {71,18}, {72,18}, {73,18}, {74,18}, {75,18}, {76,18}, {77,18},
    {78,18}, {80,18}, {82,18}, {0,19}, {2,19}, {4,19}, {5,19}, {6,19}, {7,19}, {8,19},
    {9,19}, {10,19}, {11,19}, {12,19}, {13,19}, {14,19}, {15,19}, {16,19}, {17,19}, {18,19},
    {19,19}, {20,19}, {21,19}, {22,19}, {23,19}, {24,19}, {25,19}, {26,19}, {27,19}, {28,19},
    {29,19}, {30,19}, {31,19}, {32,19}, {33,19}, {34,19}, {35,19}, {36,19}, {37,19}, {38,19},
    {40,19}, {42,19}, {44,19}, {45,19}, {46,19}, {47,19}, {48,19}, {49,19}, {50,19}, {51,19},
    {52,19}, {53,19}, {54,19}, {55,19}, {56,19}, {57,19}, {58,19}, {59,19}, {60,19}, {61,19},
    {62,19}, {63,19}, {64,19}, {65,19}, {66,19}, {67,19}, {68,19}, {69,19}, {70,19}, {71,19},
    {72,19}, {73,19}, {74,19}, {75,19}, {76,19}, {77,19}, {78,19}, {80,19}, {82,19}, {0,20},
    {2,20}, {4,20}, {5,20}, {6,20}, {7,20}, {8,20}, {9,20}, {10,20}, {11,20}, {12,20},
    {13,20}, {14,20}, {15,20}, {16,20}, {17,20}, {18,20}, {19,20}, {20,20}, {21,20}, {22,20},
    {23,20}, {24,20}, {25,20}, {26,20}, {27,20}, {28,20}, {29,20}, {30,20}, {31,20}, {32,20},
    {33,20}, {34,20}, {35,20}, {36,20}, {37,20}, {38,20}, {40,20}, {42,20}, {44,20}, {45,20},
    {46,20}, {47,20}, {48,20}, {49,20}, {50,20}, {51,20}, {52,20}, {53,20}, {54,20}, {55,20},
    {56,20}, {57,20}, {58,20}, {59,20}, {60,20}, {61,20}, {62,20}, {63,20}, {64,20}, {65,20},
    {66,20}, {67,20}, {68,20}, {69,20}, {70,20}, {71,20}, {72,20}, {73,20}, {74,20}, {75,20},
    {76,20}, {77,20}, {78,20}, {80,20}, {82,20}, {0,21}, {2,21}, {4,21}, {5,21}, {6,21},
    {7,21}, {8,21}, {9,21}, {10,21}, {11,21}, {12,21}, {13,21}, {14,21}, {15,21}, {16,21},
    {17,21}, {18,21}, {19,21}, {20,21}, {21,21}, {22,21}, {23,21}, {24,21}, {25,21}, {26,21},
    {27,21}, {28,21}, {29,21}, {30,21}, {31,21}, {32,21}, {33,21}, {34,21}, {35,21}, {36,21},
    {37,21}, {38,21}, {40,21}, {42,21}, {44,21}, {45,21}, {46,21}, {47,21}, {48,21}, {49,21},
    {50,21}, {51,21}, {52,21}, {53,21}, {54,21}, {55,21}, {56,21}, {57,21}, {58,21}, {59,21},
    {60,21}, {61,21}, {62,21}, {63,21}, {64,21}, {65,21}, {66,21}, {67,21}, {68,21}, {69,21},
    {70,21}, {71,21}, {72,21}, {73,21}, {74,21}, {75,21}, {76,21}, {77,21}, {78,21}, {80,21},
    {82,21}, {0,22}, {2,22}, {4,22}, {5,22}, {6,22}, {7,22}, {8,22}, {9,22}, {10,22},
    {11,22}, {12,22}, {13,22}, {14,22}, {15,22}, {16,22}, {17,22}, {18,22}, {19,22}, {20,22},
    {21,22}, {22,22}, {23,22}, {24,22}, {25,22}, {26,22}, {27,22}, {28,22}, {29,22}, {30,22},
    {31,22}, {32,22}, {33,22}, {34,22}, {35,22}, {36,22}, {37,22}, {38,22}, {40,22}, {42,22},
    {44,22}, {45,22}, {46,22}, {47,22}, {48,22}, {49,22}, {50,22}, {51,22}, {52,22}, {53,22},
    {54,22}, {55,22}, {56,22}, {57,22}, {58,22}, {59,22}, {60,22}, {61,22}, {62,22}, {63,22},
    {64,22}, {65,22}, {66,22}, {67,22}, {68,22}, {69,22}, {70,22}, {71,22}, {72,22}, {73,22},
    {74,22}, {75,22}, {76,22}, {77,22}, {78,22}, {80,22}, {82,22}, {0,23}, {2,23}, {40,23},
    {42,23}, {80,23}, {82,23}, {0,24}, {2,24}, {4,24}, {5,24}, {6,24}, {7,24}, {8,24},
    {9,24}, {10,24}, {11,24}, {12,24}, {13,24}, {14,24}, {15,24}, {16,24}, {17,24}, {18,24},
    {19,24}, {20,24}, {21,24}, {22,24}, {23,24}, {24,24}, {25,24}, {26,24}, {27,24}, {28,24},
    {29,24}, {30,24}, {31,24}, {32,24}, {33,24}, {34,24}, {35,24}, {36,24}, {37,24}, {38,24},
    {40,24}, {42,24}, {44,24}, {45,24}, {46,24}, {47,24}, {48,24}, {49,24}, {50,24}, {51,24},
    {52,24}, {53,24}, {54,24}, {55,24}, {56,24}, {57,24}, {58,24}, {59,24}, {60,24}, {61,24},
    {62,24}, {63,24}, {64,24}, {65,24}, {66,24}, {67,24}, {68,24}, {69,24}, {70,24}, {71,24},
    {72,24}, {73,24}, {74,24}, {75,24}, {76,24}, {77,24}, {78,24}, {80,24}, {82,24}, {0,25},
    {2,25}, {4,25}, {38,25}, {40,25}, {42,25}, {44,25}, {78,25}, {80,25}, {82,25}, {0,26},
    {2,26}, {4,26}, {38,26}, {40,26}, {42,26}, {44,26}, {78,26}, {80,26}, {82,26}, {0,27},
    {2,27}, {4,27}, {38,27}, {40,27}, {42,27}, {44,27}, {78,27}, {80,27}, {82,27}, {0,28},
    {2,28}, {4,28}, {38,28}, {40,28}, {42,28}, {44,28}, {78,28}, {80,28}, {82,28}, {0,29},
    {2,29}, {4,29}, {38,29}, {40,29}, {42,29}, {44,29}, {78,29}, {80,29}, {82,29}, {0,30},
    {2,30}, {4,30}, {38,30}, {40,30}, {42,30}, {44,30}, {78,30}, {80,30}, {82,30}, {0,31},
    {2,31}, {4,31}, {38,31}, {40,31}, {42,31}, {44,31}, {78,31}, {80,31}, {82,31}, {0,32},
    {2,32}, {4,32}, {38,32}, {40,32}, {42,32}, {44,32}, {78,32}, {80,32}, {82,32}, {0,33},
    {2,33}, {4,33}, {38,33}, {40,33}, {42,33}, {44,33}, {78,33}, {80,33}, {82,33}, {0,34},
    {2,34}, {4,34}, {38,34}, {40,34}, {42,34}, {44,34}, {78,34}, {80,34}, {82,34}, {0,35},
    {2,35}, {4,35}, {38,35}, {40,35}, {42,35}, {44,35}, {78,35}, {80,35}, {82,35}, {0,36},
    {2,36}, {4,36}, {38,36}, {40,36}, {42,36}, {44,36}, {78,36}, {80,36}, {82,36}, {0,37},
    {2,37}, {4,37}, {38,37}, {40,37}, {42,37}, {44,37}, {78,37}, {80,37}, {82,37}, {0,38},
    {2,38}, {4,38}, {38,38}, {40,38}, {42,38}, {44,38}, {78,38}, {80,38}, {82,38}, {0,39},
    {2,39}, {4,39}, {38,39}, {40,39}, {42,39}, {44,39}, {78,39}, {80,39}, {82,39}, {0,40},
    {2,40}, {4,40}, {38,40}, {40,40}, {42,40}, {44,40}, {78,40}, {80,40}, {82,40}, {0,41},
    {2,41}, {4,41}, {38,41}, {40,41}, {42,41}, {44,41}, {78,41}, {80,41}, {82,41}, {0,42},
    {2,42}, {4,42}, {38,42}, {40,42}, {42,42}, {44,42}, {78,42}, {80,42}, {82,42}, {0,43},
    {2,43}, {4,43}, {38,43}, {40,43}, {42,43}, {44,43}, {78,43}, {80,43}, {82,43}, {0,44},
    {2,44}, {4,44}, {38,44}, {40,44}, {42,44}, {44,44}, {78,44}, {80,44}, {82,44}, {0,45},
    {2,45}, {4,45}, {38,45}, {40,45}, {42,45}, {44,45}, {78,45}, {80,45}, {82,45}, {0,46},
    {2,46}, {4,46}, {38,46}, {40,46}, {42,46}, {44,46}, {78,46}, {80,46}, {82,46}, {0,47},
    {2,47}, {4,47}, {38,47}, {40,47}, {42,47}, {44,47}, {78,47}, {80,47}, {82,47}, {0,48},
    {2,48}, {4,48}, {38,48}, {40,48}, {42,48}, {44,48}, {78,48}, {80,48}, {82,48}, {0,49},
    {2,49}, {4,49}, {38,49}, {40,49}, {42,49}, {44,49}, {78,49}, {80,49}, {82,49}, {0,50},
    {2,50}, {4,50}, {38,50}, {40,50}, {42,50}, {44,50}, {78,50}, {80,50}, {82,50}, {0,51},
    {2,51}, {4,51}, {38,51}, {40,51}, {42,51}, {44,51}, {78,51}, {80,51}, {82,51}, {0,52},
    {2,52}, {4,52}, {5,52}, {6,52}, {7,52}, {8,52}, {9,52}, {10,52}, {11,52}, {12,52},
    {13,52}, {14,52}, {15,52}, {16,52}, {17,52}, {18,52}, {19,52}, {20,52}, {21,52}, {22,52},
    {23,52}, {24,52}, {25,52}, {26,52}, {27,52}, {28,52}, {29,52}, {30,52}, {31,52}, {32,52},
    {33,52}, {34,52}, {35,52}, {36,52}, {37,52}, {38,52}, {40,52}, {42,52}, {44,52}, {45,52},
    {46,52}, {47,52}, {48,52}, {49,52}, {50,52}, {51,52}, {52,52}, {53,52}, {54,52}, {55,52},
    {56,52}, {57,52}, {58,52}, {59,52}, {60,52}, {61,52}, {62,52}, {63,52}, {64,52}, {65,52},
    {66,52}, {67,52}, {68,52}, {69,52}, {70,52}, {71,52}, {72,52}, {73,52}, {74,52}, {75,52},
    {76,52}, {77,52}, {78,52}, {80,52}, {82,52}, {0,53}, {2,53}, {40,53}, {42,53}, {80,53},
    {82,53}, {0,54}, {2,54}, {3,54}, {4,54}, {5,54}, {6,54}, {7,54}, {8,54}, {9,54},
    {10,54}, {11,54}, {12,54}, {13,54}, {14,54}, {15,54}, {16,54}, {17,54}, {18,54}, {19,54},
    {20,54}, {21,54}, {22,54}, {23,54}, {24,54}, {25,54}, {26,54}, {27,54}, {28,54}, {29,54},
    {30,54}, {31,54}, {32,54}, {33,54}, {34,54}, {35,54}, {36,54}, {37,54}, {38,54}, {39,54},
    {40,54}, {42,54}, {43,54}, {44,54}, {45,54}, {46,54}, {47,54}, {48,54}, {49,54}, {50,54},
    {51,54}, {52,54}, {53,54}, {54,54}, {55,54}, {56,54}, {57,54}, {58,54}, {59,54}, {60,54},
    {61,54}, {62,54}, {63,54}, {64,54}, {65,54}, {66,54}, {67,54}, {68,54}, {69,54}, {70,54},
    {71,54}, {72,54}, {73,54}, {74,54}, {75,54}, {76,54}, {77,54}, {78,54}, {79,54}, {80,54},
    {82,54}, {0,55}, {82,55}, {0,56}, {1,56}, {2,56}, {3,56}, {4,56}, {5,56}, {6,56},
    {7,56}, {8,56}, {9,56}, {10,56}, {11,56}, {12,56}, {13,56}, {14,56}, {15,56}, {16,56},
    {17,56}, {18,56}, {19,56}, {20,56}, {21,56}, {22,56}, {23,56}, {24,56}, {25,56}, {26,56},
    {27,56}, {28,56}, {29,56}, {30,56}, {31,56}, {32,56}, {33,56}, {34,56}, {35,56}, {36,56},
    {37,56}, {38,56}, {39,56}, {40,56}, {41,56}, {42,56}, {43,56}, {44,56}, {45,56}, {46,56},
    {47,56}, {48,56}, {49,56}, {50,56}, {51,56}, {52,56}, {53,56}, {54,56}, {55,56}, {56,56},
    {57,56}, {58,56}, {59,56}, {60,56}, {61,56}, {62,56}, {63,56}, {64,56}, {65,56}, {66,56},
    {67,56}, {68,56}, {69,56}, {70,56}, {71,56}, {72,56}, {73,56}, {74,56}, {75,56}, {76,56},
    {77,56}, {78,56}, {79,56}, {80,56}, {81,56}, {82,56}
  },
  [12] = {
    {5,5}, {6,5}, {7,5}, {12,5}, {13,5}, {14,5}, {19,5}, {20,5}, {21,5}, {26,5},
    {27,5}, {28,5}, {33,5}, {34,5}, {35,5}, {40,5}, {41,5}, {42,5}, {47,5}, {48,5},
    {49,5}, {68,5}, {69,5}, {70,5}, {75,5}, {76,5}, {77,5}, {4,6}, {5,6}, {6,6},
    {7,6}, {8,6}, {11,6}, {12,6}, {13,6}, {14,6}, {15,6}, {18,6}, {19,6}, {20,6},
    {21,6}, {22,6}, {25,6}, {26,6}, {27,6}, {28,6}, {29,6}, {32,6}, {33,6}, {34,6},
    {35,6}, {36,6}, {39,6}, {40,6}, {41,6}, {42,6}, {43,6}, {46,6}, {47,6}, {48,6},
    {49,6}, {50,6}, {67,6}, {68,6}, {69,6}, {70,6}, {71,6}, {74,6}, {75,6}, {76,6},
    {77,6}, {78,6}, {4,7}, {5,7}, {6,7}, {7,7}, {8,7}, {11,7}, {12,7}, {13,7},
    {14,7}, {15,7}, {18,7}, {19,7}, {20,7}, {21,7}, {22,7}, {25,7}, {26,7}, {27,7},
    {28,7}, {29,7}, {32,7}, {33,7}, {34,7}, {35,7}, {36,7}, {39,7}, {40,7}, {41,7},
    {42,7}, {43,7}, {46,7}, {47,7}, {48,7}, {49,7}, {50,7}, {67,7}, {68,7}, {69,7},
    {70,7}, {71,7}, {74,7}, {75,7}, {76,7}, {77,7}, {78,7}, {4,8}, {5,8}, {6,8},
    {7,8}, {8,8}, {11,8}, {12,8}, {13,8}, {14,8}, {15,8}, {18,8}, {19,8}, {20,8},
    {21,8}, {22,8}, {25,8}, {26,8}, {27,8}, {28,8}, {29,8}, {32,8}, {33,8}, {34,8},
    {35,8}, {36,8}, {39,8}, {40,8}, {41,8}, {42,8}, {43,8}, {46,8}, {47,8}, {48,8},
    {49,8}, {50,8}, {67,8}, {68,8}, {69,8}, {70,8}, {71,8}, {74,8}, {75,8}, {76,8},
    {77,8}, {78,8}, {5,9}, {6,9}, {7,9}, {12,9}, {13,9}, {14,9}, {19,9}, {20,9},
    {21,9}, {26,9}, {27,9}, {28,9}, {33,9}, {34,9}, {35,9}, {40,9}, {41,9}, {42,9},
    {47,9}, {48,9}, {49,9}, {68,9}, {69,9}, {70,9}, {75,9}, {76,9}, {77,9}
  },
  [13] = {
    {6,26}, {7,26}, {8,26}, {9,26}, {10,26}, {11,26}, {12,26}, {13,26}, {14,26}, {15,26},
    {16,26}, {17,26}, {18,26}, {19,26}, {20,26}, {21,26}, {22,26}, {23,26}, {24,26}, {25,26},
    {26,26}, {27,26}, {28,26}, {29,26}, {30,26}, {31,26}, {32,26}, {33,26}, {34,26}, {35,26},
    {36,26}, {6,27}, {7,27}, {8,27}, {9,27}, {10,27}, {11,27}, {12,27}, {13,27}, {14,27},
    {15,27}, {16,27}, {17,27}, {18,27}, {19,27}, {20,27}, {21,27}, {22,27}, {23,27}, {24,27},
    {25,27}, {26,27}, {27,27}, {28,27}, {29,27}, {30,27}, {31,27}, {32,27}, {33,27}, {34,27},
    {35,27}, {36,27}, {6,28}, {7,28}, {8,28}, {9,28}, {10,28}, {11,28}, {12,28}, {13,28},
    {14,28}, {15,28}, {16,28}, {17,28}, {18,28}, {19,28}, {20,28}, {21,28}, {22,28}, {23,28},
    {24,28}, {25,28}, {26,28}, {27,28}, {28,28}, {29,28}, {30,28}, {31,28}, {32,28}, {33,28},
    {34,28}, {35,28}, {36,28}, {6,29}, {7,29}, {8,29}, {9,29}, {10,29}, {11,29}, {12,29},
    {13,29}, {14,29}, {15,29}, {16,29}, {17,29}, {18,29}, {19,29}, {20,29}, {21,29}, {22,29},
    {23,29}, {24,29}, {25,29}, {26,29}, {27,29}, {28,29}, {29,29}, {30,29}, {31,29}, {32,29},
    {33,29}, {34,29}, {35,29}, {36,29}, {6,30}, {7,30}, {8,30}, {9,30}, {10,30}, {11,30},
    {12,30}, {13,30}, {14,30}, {15,30}, {16,30}, {17,30}, {18,30}, {19,30}, {20,30}, {21,30},
    {22,30}, {23,30}, {24,30}, {25,30}, {26,30}, {27,30}, {28,30}, {29,30}, {30,30}, {31,30},
    {32,30}, {33,30}, {34,30}, {35,30}, {36,30}, {6,31}, {7,31}, {8,31}, {9,31}, {10,31},
    {11,31}, {12,31}, {13,31}, {14,31}, {15,31}, {16,31}, {17,31}, {18,31}, {19,31}, {20,31},
    {21,31}, {22,31}, {23,31}, {24,31}, {25,31}, {26,31}, {27,31}, {28,31}, {29,31}, {30,31},
    {31,31}, {32,31}, {33,31}, {34,31}, {35,31}, {36,31}, {6,32}, {7,32}, {8,32}, {9,32},
    {10,32}, {11,32}, {12,32}, {13,32}, {14,32}, {15,32}, {16,32}, {17,32}, {18,32}, {19,32},
    {20,32}, {21,32}, {22,32}, {23,32}, {24,32}, {25,32}, {26,32}, {27,32}, {28,32}, {29,32},
    {30,32}, {31,32}, {32,32}, {33,32}, {34,32}, {35,32}, {36,32}, {6,33}, {7,33}, {8,33},
    {9,33}, {10,33}, {11,33}, {12,33}, {13,33}, {14,33}, {15,33}, {16,33}, {17,33}, {18,33},
    {19,33}, {20,33}, {21,33}, {22,33}, {23,33}, {24,33}, {25,33}, {26,33}, {27,33}, {28,33},
    {29,33}, {30,33}, {31,33}, {32,33}, {33,33}, {34,33}, {35,33}, {36,33}, {6,34}, {7,34},
    {8,34}, {9,34}, {10,34}, {11,34}, {12,34}, {13,34}, {14,34}, {15,34}, {16,34}, {17,34},
    {18,34}, {19,34}, {20,34}, {21,34}, {22,34}, {23,34}, {24,34}, {25,34}, {26,34}, {27,34},
    {28,34}, {29,34}, {30,34}, {31,34}, {32,34}, {33,34}, {34,34}, {35,34}, {36,34}, {6,35},
    {7,35}, {8,35}, {9,35}, {10,35}, {11,35}, {12,35}, {13,35}, {14,35}, {15,35}, {16,35},
    {17,35}, {18,35}, {19,35}, {20,35}, {21,35}, {22,35}, {23,35}, {24,35}, {25,35}, {26,35},
    {27,35}, {28,35}, {29,35}, {30,35}, {31,35}, {32,35}, {33,35}, {34,35}, {35,35}, {36,35},
    {6,36}, {7,36}, {8,36}, {9,36}, {10,36}, {11,36}, {12,36}, {13,36}, {14,36}, {15,36},
    {16,36}, {17,36}, {18,36}, {19,36}, {20,36}, {21,36}, {22,36}, {23,36}, {24,36}, {25,36},
    {26,36}, {27,36}, {28,36}, {29,36}, {30,36}, {31,36}, {32,36}, {33,36}, {34,36}, {35,36},
    {36,36}, {6,37}, {7,37}, {8,37}, {9,37}, {10,37}, {11,37}, {12,37}, {13,37}, {14,37},
    {15,37}, {16,37}, {17,37}, {18,37}, {19,37}, {20,37}, {21,37}, {22,37}, {23,37}, {24,37},
    {25,37}, {26,37}, {27,37}, {28,37}, {29,37}, {30,37}, {31,37}, {32,37}, {33,37}, {34,37},
    {35,37}, {36,37}, {6,38}, {7,38}, {8,38}, {9,38}, {10,38}, {11,38}, {12,38}, {13,38},
    {14,38}, {15,38}, {16,38}, {17,38}, {18,38}, {19,38}, {20,38}, {21,38}, {22,38}, {23,38},
    {24,38}, {25,38}, {26,38}, {27,38}, {28,38}, {29,38}, {30,38}, {31,38}, {32,38}, {33,38},
    {34,38}, {35,38}, {36,38}, {6,39}, {7,39}, {8,39}, {9,39}, {10,39}, {11,39}, {12,39},
    {13,39}, {14,39}, {15,39}, {16,39}, {17,39}, {18,39}, {19,39}, {20,39}, {21,39}, {22,39},
    {23,39}, {24,39}, {25,39}, {26,39}, {27,39}, {28,39}, {29,39}, {30,39}, {31,39}, {32,39},
    {33,39}, {34,39}, {35,39}, {36,39}, {6,40}, {7,40}, {8,40}, {9,40}, {10,40}, {11,40},
    {12,40}, {13,40}, {14,40}, {15,40}, {16,40}, {17,40}, {18,40}, {19,40}, {20,40}, {21,40},
    {22,40}, {23,40}, {24,40}, {25,40}, {26,40}, {27,40}, {28,40}, {29,40}, {30,40}, {31,40},
    {32,40}, {33,40}, {34,40}, {35,40}, {36,40}, {6,41}, {7,41}, {8,41}, {9,41}, {10,41},
    {11,41}, {12,41}, {13,41}, {14,41}, {15,41}, {16,41}, {17,41}, {18,41}, {19,41}, {20,41},
    {21,41}, {22,41}, {23,41}, {24,41}, {25,41}, {26,41}, {27,41}, {28,41}, {29,41}, {30,41},
    {31,41}, {32,41}, {33,41}, {34,41}, {35,41}, {36,41}, {6,42}, {7,42}, {8,42}, {9,42},
    {10,42}, {11,42}, {12,42}, {13,42}, {14,42}, {15,42}, {16,42}, {17,42}, {18,42}, {19,42},
    {20,42}, {21,42}, {22,42}, {23,42}, {24,42}, {25,42}, {26,42}, {27,42}, {28,42}, {29,42},
    {30,42}, {31,42}, {32,42}, {33,42}, {34,42}, {35,42}, {36,42}, {6,43}, {7,43}, {8,43},
    {9,43}, {10,43}, {11,43}, {12,43}, {13,43}, {14,43}, {15,43}, {16,43}, {17,43}, {18,43},
    {19,43}, {20,43}, {21,43}, {22,43}, {23,43}, {24,43}, {25,43}, {26,43}, {27,43}, {28,43},
    {29,43}, {30,43}, {31,43}, {32,43}, {33,43}, {34,43}, {35,43}, {36,43}, {6,44}, {7,44},
    {8,44}, {9,44}, {10,44}, {11,44}, {12,44}, {13,44}, {14,44}, {15,44}, {16,44}, {17,44},
    {18,44}, {19,44}, {20,44}, {21,44}, {22,44}, {23,44}, {24,44}, {25,44}, {26,44}, {27,44},
    {28,44}, {29,44}, {30,44}, {31,44}, {32,44}, {33,44}, {34,44}, {35,44}, {36,44}, {6,45},
    {36,45}, {6,46}, {7,46}, {8,46}, {9,46}, {10,46}, {11,46}, {12,46}, {13,46}, {14,46},
    {15,46}, {16,46}, {17,46}, {18,46}, {19,46}, {20,46}, {21,46}, {22,46}, {23,46}, {24,46},
    {25,46}, {26,46}, {27,46}, {28,46}, {29,46}, {30,46}, {31,46}, {32,46}, {33,46}, {34,46},
    {35,46}, {36,46}, {6,47}, {7,47}, {8,47}, {9,47}, {10,47}, {11,47}, {12,47}, {13,47},
    {14,47}, {15,47}, {16,47}, {17,47}, {18,47}, {19,47}, {20,47}, {21,47}, {22,47}, {23,47},
    {24,47}, {25,47}, {26,47}, {27,47}, {28,47}, {29,47}, {30,47}, {31,47}, {32,47}, {33,47},
    {34,47}, {35,47}, {36,47}, {6,48}, {36,48}, {6,49}, {7,49}, {8,49}, {9,49}, {10,49},
    {11,49}, {12,49}, {13,49}, {14,49}, {15,49}, {16,49}, {17,49}, {18,49}, {19,49}, {20,49},
    {21,49}, {22,49}, {23,49}, {24,49}, {25,49}, {26,49}, {27,49}, {28,49}, {29,49}, {30,49},
    {31,49}, {32,49}, {33,49}, {34,49}, {35,49}, {36,49}, {6,50}, {7,50}, {8,50}, {9,50},
    {10,50}, {11,50}, {12,50}, {13,50}, {14,50}, {15,50}, {16,50}, {17,50}, {18,50}, {19,50},
    {20,50}, {21,50}, {22,50}, {23,50}, {24,50}, {25,50}, {26,50}, {27,50}, {28,50}, {29,50},
    {30,50}, {31,50}, {32,50}, {33,50}, {34,50}, {35,50}, {36,50}
  },
  [14] = {
    {46,26}, {47,26}, {48,26}, {49,26}, {50,26}, {51,26}, {52,26}, {53,26}, {54,26}, {55,26},
    {56,26}, {57,26}, {58,26}, {59,26}, {60,26}, {61,26}, {62,26}, {63,26}, {64,26}, {65,26},
    {66,26}, {67,26}, {68,26}, {69,26}, {70,26}, {71,26}, {72,26}, {73,26}, {74,26}, {75,26},
    {76,26}, {46,27}, {47,27}, {48,27}, {49,27}, {50,27}, {51,27}, {52,27}, {53,27}, {54,27},
    {55,27}, {56,27}, {57,27}, {58,27}, {59,27}, {60,27}, {61,27}, {62,27}, {63,27}, {64,27},
    {65,27}, {66,27}, {67,27}, {68,27}, {69,27}, {70,27}, {71,27}, {72,27}, {73,27}, {74,27},
    {75,27}, {76,27}, {46,28}, {47,28}, {48,28}, {49,28}, {50,28}, {51,28}, {52,28}, {53,28},
    {54,28}, {55,28}, {56,28}, {57,28}, {58,28}, {59,28}, {60,28}, {61,28}, {62,28}, {63,28},
    {64,28}, {65,28}, {66,28}, {67,28}, {68,28}, {69,28}, {70,28}, {71,28}, {72,28}, {73,28},
    {74,28}, {75,28}, {76,28}, {46,29}, {47,29}, {48,29}, {49,29}, {50,29}, {51,29}, {52,29},
    {53,29}, {54,29}, {55,29}, {56,29}, {57,29}, {58,29}, {59,29}, {60,29}, {61,29}, {62,29},
    {63,29}, {64,29}, {65,29}, {66,29}, {67,29}, {68,29}, {69,29}, {70,29}, {71,29}, {72,29},
    {73,29}, {74,29}, {75,29}, {76,29}, {46,30}, {47,30}, {48,30}, {49,30}, {50,30}, {51,30},
    {52,30}, {53,30}, {54,30}, {55,30}, {56,30}, {57,30}, {58,30}, {59,30}, {60,30}, {61,30},
    {62,30}, {63,30}, {64,30}, {65,30}, {66,30}, {67,30}, {68,30}, {69,30}, {70,30}, {71,30},
    {72,30}, {73,30}, {74,30}, {75,30}, {76,30}, {46,31}, {47,31}, {48,31}, {49,31}, {50,31},
    {51,31}, {52,31}, {53,31}, {54,31}, {55,31}, {56,31}, {57,31}, {58,31}, {59,31}, {60,31},
    {61,31}, {62,31}, {63,31}, {64,31}, {65,31}, {66,31}, {67,31}, {68,31}, {69,31}, {70,31},
    {71,31}, {72,31}, {73,31}, {74,31}, {75,31}, {76,31}, {46,32}, {47,32}, {48,32}, {49,32},
    {50,32}, {51,32}, {52,32}, {53,32}, {54,32}, {55,32}, {56,32}, {57,32}, {58,32}, {59,32},
    {60,32}, {61,32}, {62,32}, {63,32}, {64,32}, {65,32}, {66,32}, {67,32}, {68,32}, {69,32},
    {70,32}, {71,32}, {72,32}, {73,32}, {74,32}, {75,32}, {76,32}, {46,33}, {47,33}, {48,33},
    {49,33}, {50,33}, {51,33}, {52,33}, {53,33}, {54,33}, {55,33}, {56,33}, {57,33}, {58,33},
    {59,33}, {60,33}, {61,33}, {62,33}, {63,33}, {64,33}, {65,33}, {66,33}, {67,33}, {68,33},
    {69,33}, {70,33}, {71,33}, {72,33}, {73,33}, {74,33}, {75,33}, {76,33}, {46,34}, {47,34},
    {48,34}, {49,34}, {50,34}, {51,34}, {52,34}, {53,34}, {54,34}, {55,34}, {56,34}, {57,34},
    {58,34}, {59,34}, {60,34}, {61,34}, {62,34}, {63,34}, {64,34}, {65,34}, {66,34}, {67,34},
    {68,34}, {69,34}, {70,34}, {71,34}, {72,34}, {73,34}, {74,34}, {75,34}, {76,34}, {46,35},
    {47,35}, {48,35}, {49,35}, {50,35}, {51,35}, {52,35}, {53,35}, {54,35}, {55,35}, {56,35},
    {57,35}, {58,35}, {59,35}, {60,35}, {61,35}, {62,35}, {63,35}, {64,35}, {65,35}, {66,35},
    {67,35}, {68,35}, {69,35}, {70,35}, {71,35}, {72,35}, {73,35}, {74,35}, {75,35}, {76,35},
    {46,36}, {47,36}, {48,36}, {49,36}, {50,36}, {51,36}, {52,36}, {53,36}, {54,36}, {55,36},
    {56,36}, {57,36}, {58,36}, {59,36}, {60,36}, {61,36}, {62,36}, {63,36}, {64,36}, {65,36},
    {66,36}, {67,36}, {68,36}, {69,36}, {70,36}, {71,36}, {72,36}, {73,36}, {74,36}, {75,36},
    {76,36}, {46,37}, {47,37}, {48,37}, {49,37}, {50,37}, {51,37}, {52,37}, {53,37}, {54,37},
    {55,37}, {56,37}, {57,37}, {58,37}, {59,37}, {60,37}, {61,37}, {62,37}, {63,37}, {64,37},
    {65,37}, {66,37}, {67,37}, {68,37}, {69,37}, {70,37}, {71,37}, {72,37}, {73,37}, {74,37},
    {75,37}, {76,37}, {46,38}, {47,38}, {48,38}, {49,38}, {50,38}, {51,38}, {52,38}, {53,38},
    {54,38}, {55,38}, {56,38}, {57,38}, {58,38}, {59,38}, {60,38}, {61,38}, {62,38}, {63,38},
    {64,38}, {65,38}, {66,38}, {67,38}, {68,38}, {69,38}, {70,38}, {71,38}, {72,38}, {73,38},
    {74,38}, {75,38}, {76,38}, {46,39}, {47,39}, {48,39}, {49,39}, {50,39}, {51,39}, {52,39},
    {53,39}, {54,39}, {55,39}, {56,39}, {57,39}, {58,39}, {59,39}, {60,39}, {61,39}, {62,39},
    {63,39}, {64,39}, {65,39}, {66,39}, {67,39}, {68,39}, {69,39}, {70,39}, {71,39}, {72,39},
    {73,39}, {74,39}, {75,39}, {76,39}, {46,40}, {47,40}, {48,40}, {49,40}, {50,40}, {51,40},
    {52,40}, {53,40}, {54,40}, {55,40}, {56,40}, {57,40}, {58,40}, {59,40}, {60,40}, {61,40},
    {62,40}, {63,40}, {64,40}, {65,40}, {66,40}, {67,40}, {68,40}, {69,40}, {70,40}, {71,40},
    {72,40}, {73,40}, {74,40}, {75,40}, {76,40}, {46,41}, {47,41}, {48,41}, {49,41}, {50,41},
    {51,41}, {52,41}, {53,41}, {54,41}, {55,41}, {56,41}, {57,41}, {58,41}, {59,41}, {60,41},
    {61,41}, {62,41}, {63,41}, {64,41}, {65,41}, {66,41}, {67,41}, {68,41}, {69,41}, {70,41},
    {71,41}, {72,41}, {73,41}, {74,41}, {75,41}, {76,41}, {46,42}, {47,42}, {48,42}, {49,42},
    {50,42}, {51,42}, {52,42}, {53,42}, {54,42}, {55,42}, {56,42}, {57,42}, {58,42}, {59,42},
    {60,42}, {61,42}, {62,42}, {63,42}, {64,42}, {65,42}, {66,42}, {67,42}, {68,42}, {69,42},
    {70,42}, {71,42}, {72,42}, {73,42}, {74,42}, {75,42}, {76,42}, {46,43}, {47,43}, {48,43},
    {49,43}, {50,43}, {51,43}, {52,43}, {53,43}, {54,43}, {55,43}, {56,43}, {57,43}, {58,43},
    {59,43}, {60,43}, {61,43}, {62,43}, {63,43}, {64,43}, {65,43}, {66,43}, {67,43}, {68,43},
    {69,43}, {70,43}, {71,43}, {72,43}, {73,43}, {74,43}, {75,43}, {76,43}, {46,44}, {47,44},
    {48,44}, {49,44}, {50,44}, {51,44}, {52,44}, {53,44}, {54,44}, {55,44}, {56,44}, {57,44},
    {58,44}, {59,44}, {60,44}, {61,44}, {62,44}, {63,44}, {64,44}, {65,44}, {66,44}, {67,44},
    {68,44}, {69,44}, {70,44}, {71,44}, {72,44}, {73,44}, {74,44}, {75,44}, {76,44}, {46,45},
    {76,45}, {46,46}, {47,46}, {48,46}, {49,46}, {50,46}, {51,46}, {52,46}, {53,46}, {54,46},
    {55,46}, {56,46}, {57,46}, {58,46}, {59,46}, {60,46}, {61,46}, {62,46}, {63,46}, {64,46},
    {65,46}, {66,46}, {67,46}, {68,46}, {69,46}, {70,46}, {71,46}, {72,46}, {73,46}, {74,46},
    {75,46}, {76,46}, {46,47}, {47,47}, {48,47}, {49,47}, {50,47}, {51,47}, {52,47}, {53,47},
    {54,47}, {55,47}, {56,47}, {57,47}, {58,47}, {59,47}, {60,47}, {61,47}, {62,47}, {63,47},
    {64,47}, {65,47}, {66,47}, {67,47}, {68,47}, {69,47}, {70,47}, {71,47}, {72,47}, {73,47},
    {74,47}, {75,47}, {76,47}, {46,48}, {76,48}, {46,49}, {47,49}, {48,49}, {49,49}, {50,49},
    {51,49}, {52,49}, {53,49}, {54,49}, {55,49}, {56,49}, {57,49}, {58,49}, {59,49}, {60,49},
    {61,49}, {62,49}, {63,49}, {64,49}, {65,49}, {66,49}, {67,49}, {68,49}, {69,49}, {70,49},
    {71,49}, {72,49}, {73,49}, {74,49}, {75,49}, {76,49}, {46,50}, {47,50}, {48,50}, {49,50},
    {50,50}, {51,50}, {52,50}, {53,50}, {54,50}, {55,50}, {56,50}, {57,50}, {58,50}, {59,50},
    {60,50}, {61,50}, {62,50}, {63,50}, {64,50}, {65,50}, {66,50}, {67,50}, {68,50}, {69,50},
    {70,50}, {71,50}, {72,50}, {73,50}, {74,50}, {75,50}, {76,50}
  },
  [15] = {
    {62,6}, {64,6}, {63,7}, {62,8}, {64,8}
  },
}

local LOOPER_KNOB_BBOX = {}
do
  local cx = {6, 13, 20, 27, 34, 41, 48, 69, 76}
  for i = 1, 9 do
    LOOPER_KNOB_BBOX[i] = {x1=cx[i]-2, y1=5, x2=cx[i]+2, y2=9}
  end
end

local LOOPER_PTS = {
  knob = { {}, {}, {}, {}, {}, {}, {}, {}, {} },
  ldisp = {}, rdisp = {}, led = {}, bg = {},
}
do
  local function in_bbox(x, y, b) return x >= b.x1 and x <= b.x2 and y >= b.y1 and y <= b.y2 end
  for slot, pts in pairs(LOOPER_SPRITE) do
    for _, q in ipairs(pts) do
      if slot == 12 then
        for i = 1, 9 do
          if in_bbox(q[1], q[2], LOOPER_KNOB_BBOX[i]) then
            LOOPER_PTS.knob[i][#LOOPER_PTS.knob[i]+1] = q; break
          end
        end
      elseif slot == 13 then LOOPER_PTS.ldisp[#LOOPER_PTS.ldisp+1] = q
      elseif slot == 14 then LOOPER_PTS.rdisp[#LOOPER_PTS.rdisp+1] = q
      elseif slot == 15 then LOOPER_PTS.led[#LOOPER_PTS.led+1]     = q
      else                   LOOPER_PTS.bg[#LOOPER_PTS.bg+1]       = q end
    end
  end
end

local function draw_looper_pane()
  screen.clear()

  local p = LOOPER_DEF[looper_sel]
  draw_strip(p.cat, p.name, fmt_def_val(LOOPER_DEF, looper_sel), sync_val_level(p.id))

  if loop_state == LOOP_REC then
    draw_icon_record(LEFT_CX, ICON_Y, B.FULL)
  elseif loop_state == LOOP_DUB then
    draw_icon_dub(LEFT_CX, ICON_Y, B.FULL)
  elseif loop_state == LOOP_PLAY then
    draw_icon_play(LEFT_CX, ICON_Y, B.FULL)
  elseif loop_state == LOOP_STOP then
    draw_icon_stop(LEFT_CX, ICON_Y, B.MED)
  end

  local OX, OY      = 44, 3
  local rec_active  = (loop_state == LOOP_REC or loop_state == LOOP_PLAY or loop_state == LOOP_DUB)
  local left_active = (loop_state == LOOP_STOP)

  local function blit(lst, lv)
    if #lst == 0 then return end
    screen.level(lv)
    for _, q in ipairs(lst) do screen.rect(OX + q[1], OY + q[2], 1, 1) end
    screen.fill()
  end

  blit(LOOPER_PTS.bg, B.MED)
  for i = 1, 9 do blit(LOOPER_PTS.knob[i], (looper_sel == i) and B.FULL or B.MED) end
  blit(LOOPER_PTS.ldisp, left_active   and B.FULL or B.MED)
  blit(LOOPER_PTS.rdisp, rec_active    and B.FULL or B.MED)
  blit(LOOPER_PTS.led,   quant_led_lit and B.FULL or B.MED)

  screen.update()
end

function redraw()
  if initing then return end
  if view_group == 1 then draw_group1_pane(); return end
  if view_group == 3 then draw_pedalboard(); return end
  if view_pane[0] == 2 then draw_looper_pane(); return end
  screen.clear()
  draw_left_strip()
  draw_grillcloth()
  draw_panel()
  draw_cabinet()
  screen.update()
end

local function is_tuner_active()
  return view_group == 1 and view_pane[1] == 1
end

local function tuner_set_active(b)
  if tuner.active == b then return end
  tuner.active = b
  if b then
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
    if tuner_pitch_poll then tuner_pitch_poll:start() end
  else
    if tuner_pitch_poll then tuner_pitch_poll:stop() end
    engine.mute(0)
  end
end

local function set_view(g)
  view_group = g
  tuner_set_active(is_tuner_active())
  redraw()
end

local function set_pane(p)
  local g = view_group
  view_pane[g] = util.clamp(p, 1, GROUP_MAX[g])
  tuner_set_active(is_tuner_active())
  redraw()
end

local function metro_tick_now()
  local level  = lfo_metro_level  ~= nil and lfo_metro_level / 10.0 or params:get("metro_level") / 10.0
  local length = lfo_metro_length ~= nil and lfo_metro_length        or params:get("metro_length")
  local pitch  = lfo_metro_pitch  ~= nil and lfo_metro_pitch         or params:get("metro_pitch")
  if pitch <= 0 then return end
  local position = params:get("metro_position") - 1
  engine.metro_tick(level, pitch - 1 - 57, length, position)
end

local function metro_clock_start()
  if metro_clock then clock.cancel(metro_clock) end
  metro_clock = clock.run(function()
    if clock_running then
      clock.sync(METRO_DIV_BEATS[lfo_metro_div or params:get("metro_div")])
      while true do
        metro_tick_now()
        clock.sync(METRO_DIV_BEATS[lfo_metro_div or params:get("metro_div")])
      end
    else
      while true do
        metro_tick_now()
        local div = lfo_metro_div or params:get("metro_div")
        local bpm = tonumber(params:get("metro_bpm")) or 120
        clock.sleep(METRO_DIV_BEATS[div] * 60.0 / bpm)
      end
    end
  end)
end

local function metro_clock_stop()
  if metro_clock then clock.cancel(metro_clock); metro_clock = nil end
end

function enc(n, d)
  if view_group == 1 then
    if n == 1 then
      set_pane(view_pane[1] + d)
      return
    end
    local p = view_pane[1]
    if p == 1 then
      if n == 3 then
        local v = params:get("tuner_ref") + d * 0.1
        params:set("tuner_ref", math.floor(v * 10 + 0.5) / 10)
      end
    elseif p == 2 then
      if n == 2 then
        metro_strip_sel = util.clamp(metro_strip_sel + d, 1, #METRO_STRIP)
        redraw()
      elseif n == 3 then
        local ms = METRO_STRIP[metro_strip_sel]
        if ms.typ == "opt" then
          params:set(ms.id, util.clamp(params:get(ms.id) + d, 1, ms.nmax))
        else
          params:set(ms.id, snap_val(params:get(ms.id) + d * ms.step, ms.step))
        end
        redraw()
      end
    else
      local is_left = (p % 2) == 1
      local pair    = math.ceil(p / 2)
      local idx     = (pair - 2) * 2 + (is_left and 1 or 2)
      if n == 2 then
        lfo_strip_sel[idx] = lfo_strip_advance(idx, lfo_strip_sel[idx], d)
        redraw()
      elseif n == 3 then
        local ls  = LFO_STRIP[lfo_strip_sel[idx]]
        local id  = "lfo" .. idx .. ls.suf
        if ls.typ == "opt" then
          local nmax = ls.nmax_fn and ls.nmax_fn(idx) or ls.nmax
          if nmax > 0 then
            params:set(id, util.clamp(params:get(id) + d, 1, nmax))
          end
        else
          params:set(id, snap_val(params:get(id) + d * ls.step, ls.step))
        end
        if ls.suf == "_sync_div" then start_lfo_clock(idx) end
        redraw()
      end
    end
    return
  end

  if view_group == 3 then
    if n == 1 then
      set_pane(view_pane[3] + d)
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

  if n == 1 then
    set_pane(view_pane[0] + d)
    return
  end

  if view_pane[0] == 2 then
    if n == 2 then
      looper_sel = util.clamp(looper_sel + d, 1, #LOOPER_DEF)
      redraw()
    elseif n == 3 then
      local p = LOOPER_DEF[looper_sel]
      params:set(p.id, snap_val(params:get(p.id) + d * p.step, p.step))
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
      if view_group == 1 then set_view(0) else set_view(1) end
    end)
    return
  end

  if n == 2 then
    long_press("k2", z, function()
      if view_group == 3 and view_pane[3] == 1 then set_view(0)
      else view_pane[3] = 1; set_view(3) end
    end, function()
      if view_group == 0 then
        looper_stop_clear()
      elseif view_group == 1 then
        local p = view_pane[1]
        if p >= 3 then
          local is_left = (p % 2) == 1
          local pair    = math.ceil(p / 2)
          local idx     = (pair - 2) * 2 + (is_left and 1 or 2)
          params:set("lfo" .. idx .. "_randomize", 1)
        end
      end
    end)
    return
  end

  if n == 3 then
    long_press("k3", z, function()
      if view_group == 3 and view_pane[3] == 3 then set_view(0)
      else view_pane[3] = 3; set_view(3) end
    end, function()
      if view_group == 0 then
        looper_step()
      elseif view_group == 1 then
        local p = view_pane[1]
        if p == 1 then
          tuner.muted = not tuner.muted
          engine.mute(tuner.muted and 1 or 0)
          redraw()
        elseif p == 2 then
          local cur = params:get("metro_enable")
          params:set("metro_enable", 3 - cur)
        else
          local is_left = (p % 2) == 1
          local pair    = math.ceil(p / 2)
          local idx     = (pair - 2) * 2 + (is_left and 1 or 2)
          local cur = params:get("lfo" .. idx .. "_enable")
          params:set("lfo" .. idx .. "_enable", 3 - cur)
        end
      elseif view_group == 3 then
        local pd  = cur_pedal()
        local cur = params:get(pd.enable_id)
        params:set(pd.enable_id, 3 - cur)
      end
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

  local function sync_df_action(prefix)
    local dev_name = prefix:sub(1,1):upper() .. prefix:sub(2)
    return function(_)
      if not initing then
        sync_push_all()
        lfo_refresh_dropdowns_for_device(dev_name)
      end
      re()
    end
  end

  local function db_action(name)
    return function(v) engine[name](db_to_lin(v)); re() end
  end

  local function add_engine_ctrl(id, name, mn, mx, warp, step, default, unit)
    params:add_control(id, name, controlspec.new(mn, mx, warp, step, default, unit or ""))
    params:set_action(id, function(v) engine[id](v); re() end)
  end

  local function add_ir(id, name, setter, loader)
    params:add_file(id, name, "")
    local p = params:lookup_param(id)
    function p:string() return ir_short_name(self.path or "") end
    params:set_action(id, function(path)
      setter(path)
      if path and path ~= "" then loader(path) end
      re()
    end)
  end

  local function add_sync_params(prefix)
    params:add_separator(prefix .. "_sep_sync", "─── Synchronization ───")
    params:add_option(prefix .. "_sync_div", "Synchronization", SYNC_DIV_OPTS, 4)
    params:set_action(prefix .. "_sync_div", sync_df_action(prefix))
    params:add_option(prefix .. "_sync_feel", "Synchronization Feel", SYNC_FEEL_OPTS, 1)
    params:set_action(prefix .. "_sync_feel", sync_df_action(prefix))
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
    add_engine_ctrl("amp_volume", "Volume", 0, 10, "lin", 0.1, 5.0)
    add_engine_ctrl("amp_bass",   "Bass",   0, 10, "lin", 0.1, 5.0)
    add_engine_ctrl("amp_treble", "Treble", 0, 10, "lin", 0.1, 5.0)
    add_engine_ctrl("amp_master", "Master", 0, 10, "lin", 0.1, 7.5)
  end

  local function setup_tremolo()
    params:add_group("TREMOLO", 7)
    params:add_separator("tremolo_sep_control", "─── Control ───")
    params:add_option("tremolo_enable", "Enable", {"Bypass", "Active"}, 2)
    params:set_action("tremolo_enable", function(v) engine.tremolo_intensity(v == 2 and params:get("tremolo_intensity") or 0); re() end)
    add_engine_ctrl("tremolo_speed", "Speed", 0.1, 25, "exp", 0, 2.5, "Hz")
    params:add_control("tremolo_intensity", "Intensity", controlspec.new(0, 100, "lin", 1, 0, "%"))
    params:set_action("tremolo_intensity", function(v) if params:get("tremolo_enable") == 2 then engine.tremolo_intensity(v) end; re() end)
    add_sync_params("tremolo")
  end

  local function setup_looper()
    params:add_group("LOOPER", 26)
    params:add_separator("looper_sep_control", "─── Control ───")
    params:add_option("looper_transport", "Step Order", {"Rec·Play·Dub", "Rec·Dub·Play"}, 1)
    params:add_option("looper_play_from", "Play From", {"Start", "Cue"}, 1)
    params:set_action("looper_play_from", function(v) engine.looper_play_from(v - 1); re() end)
    params:add_option("looper_dub_style", "Mode", {"Overdub", "Overwrite", "Sample", "Resample"}, 1)
    params:set_action("looper_dub_style", function(v) engine.looper_dub_style(v - 1); re() end)
    params:add_option("looper_direction", "Direction", DIR_NAMES, 1)
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
    params:add_option("looper_medium", "Medium", {"BBD","Cassette","CD","Chip","Tape","Vinyl"}, 4)
    params:set_action("looper_medium", function(v) engine.looper_medium(v - 1); re() end)
    params:add_control("looper_imprint", "Imprint", controlspec.new(0, 100, "lin", 1, 50, "%"))
    params:set_action("looper_imprint", function(v) engine.looper_imprint(v); re() end)
    params:add_control("looper_wear", "Wear", controlspec.new(0, 100, "lin", 1, 5, "%"))
    params:set_action("looper_wear", function(v) engine.looper_wear(v); re() end)
    params:add_option("looper_bbd_tone", "M: BBD Tone", {"Bright", "Dark"}, 1)
    params:set_action("looper_bbd_tone", function(v) engine.looper_bbd_tone(v - 1) end)
    params:add_control("looper_cas_wow", "M: Cassette Wow", controlspec.new(0, 100, "lin", 1, 5, "%"))
    params:set_action("looper_cas_wow", function(v) engine.looper_wow_cas(v) end)
    params:add_control("looper_cd_errors", "M: CD Errors", controlspec.new(0, 100, "lin", 1, 0, "%"))
    params:set_action("looper_cd_errors", function(v) engine.looper_cd_errors(v) end)
    params:add_control("looper_chip_crush", "M: Chip Crush", controlspec.new(0, 100, "lin", 1, 0, "%"))
    params:set_action("looper_chip_crush", function(v) engine.looper_chip_crush(v) end)
    params:add_control("looper_tape_wow", "M: Tape Wow", controlspec.new(0, 100, "lin", 1, 5, "%"))
    params:set_action("looper_tape_wow", function(v) engine.looper_wow_tape(v) end)
    params:add_control("looper_vinyl_noise", "M: Vinyl Noise", controlspec.new(0, 100, "lin", 1, 10, "%"))
    params:set_action("looper_vinyl_noise", function(v) engine.looper_vinyl_noise(v) end)

    params:add_separator("looper_sep_sync", "─── Quantization ───")
    params:add_option("looper_quant_div", "Quantization", SYNC_DIV_OPTS, 1)
    params:set_action("looper_quant_div", function(_)
      quant_led_clock_restart()
      if not initing then lfo_refresh_dropdowns_for_device("Looper") end
      re()
    end)
    params:add_option("looper_quant_feel", "Quantization Feel", SYNC_FEEL_OPTS, 1)
    params:set_action("looper_quant_feel", function(_) quant_led_clock_restart(); re() end)

    params:add_separator("looper_sep_trigger", "─── Trigger ───")
    params:add_binary("looper_rec_play", "Rec/Play", "trigger", 0)
    params:set_action("looper_rec_play", function(v) if v == 1 then looper_step() end end)
    params:add_binary("looper_stop_clear", "Stop/Clear", "trigger", 0)
    params:set_action("looper_stop_clear", function(v) if v == 1 then looper_stop_clear() end end)
  end

  local function setup_reverb()
    params:add_group("SPRING REVERB", 6)
    params:add_separator("reverb_sep_control", "─── Control ───")
    params:add_option("reverb_enable", "Enable", {"Bypass", "Active"}, 2)
    params:set_action("reverb_enable", function(v) engine.reverb_mute(v == 2 and 0 or 1); re() end)
    add_engine_ctrl("reverb_amount",     "Amount",     0,   100, "lin", 1,   25,  "%")
    add_engine_ctrl("reverb_length",     "Length",     0.5, 5.0, "lin", 0.1, 2.5, "s")
    add_engine_ctrl("reverb_low_shelf",  "Low Shelf", -5,   5,   "lin", 0.5, 0,   "dB")
    add_engine_ctrl("reverb_high_shelf", "High Shelf",-5,   5,   "lin", 0.5, 0,   "dB")
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
    params:add_option("mic_position", "Mic Position", MIC_NAMES, 2)
    params:set_action("mic_position", function(v) engine.mic_position(v - 1); re() end)
    params:add_control("cab_level", "Cab Level", controlspec.new(-10, 10, "lin", 0.5, 0, "dB"))
    params:set_action("cab_level", db_action("cab_level"))
    add_ir("ir_l", "IR L", function(p) ir_l_path = p end, engine.load_ir_l)
    add_ir("ir_r", "IR R", function(p) ir_r_path = p end, engine.load_ir_r)
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
    add_engine_ctrl("limit_ratio",  "Ratio",  2.0, 20.0, "lin", 0.5, 4.0, ":1")
    params:add_control("limit_gain", "Gain", controlspec.new(-20, 20, "lin", 0.5, 0, "dB"))
    params:set_action("limit_gain", db_action("limit_gain"))
    add_engine_ctrl("limit_attack", "Attack", 1,   100,  "lin", 1,   10,  "ms")
    add_engine_ctrl("limit_decay",  "Decay",  50,  2000, "lin", 50,  50,  "ms")
  end

  local function setup_metro()
    params:add_group("METRO", 9)
    params:add_separator("metro_sep_control", "─── Control ───")
    params:add_option("metro_enable", "Enable", {"Off", "On"}, 1)
    params:set_action("metro_enable", function(v) metro_active = (v == 2); if metro_active then metro_clock_start() else metro_clock_stop() end; re() end)
    params:add_text("metro_bpm", "BPM", "120")
    params:add_option("metro_div", "Division", METRO_DIV_OPTS, 3)
    params:set_action("metro_div", function(_) if metro_active then metro_clock_start() end end)
    params:add_control("metro_level", "Level", controlspec.new(0, 10, "lin", 0.1, 5.0, ""))
    params:set_action("metro_level", function(_) lfo_metro_level = nil; re() end)
    params:add_option("metro_pitch", "Pitch", METRO_PITCH_NAMES, 37)
    params:set_action("metro_pitch", function(_) lfo_metro_pitch = nil; re() end)
    params:add_control("metro_length", "Length", controlspec.new(1, 500, "lin", 1, 50, "ms"))
    params:set_action("metro_length", function(_) lfo_metro_length = nil end)
    params:add_option("metro_position", "Position", {"Parallel", "Inline"}, 1)
    params:add_option("metro_scale", "Scale", SCALE_NAMES, 1)
  end

  local function setup_tuner()
    params:add_group("TUNER", 2)
    params:add_separator("tuner_sep_control", "─── Control ───")
    params:add_control("tuner_ref", "Reference", controlspec.new(420, 460, "lin", 0.1, 440.0, "Hz"))
    params:set_action("tuner_ref", function(v) tuner.ref_hz = v; re() end)
  end

  local function setup_signal_flow()
    params:add_group("SIGNAL FLOW", 2)
    params:add_separator("signal_flow_sep_control", "─── Control ───")
    params:add_option("signal_input", "Input", {"Mono", "Stereo"}, 1)
    params:set_action("signal_input", function(v) engine.signal_input(v); re() end)
  end

  local function lfo_find_filtered_idx(map, target)
    if map then
      for fi, gi in ipairs(map) do
        if gi == target then return fi end
      end
    end
    return 1
  end

  local function lfo_ui_revert(param_id, target_idx)
    local p = params:lookup_param(param_id)
    if p and p.selected ~= target_idx then
      p.selected = target_idx
      if _menu and _menu.rebuild_params then _menu.rebuild_params() end
    end
  end

  local function register_lfo(idx)
    local prefix = "lfo" .. idx

    local function refresh_visibility()
      local wf  = params:get(prefix .. "_waveform")
      local div = params:get(prefix .. "_sync_div")
      if div > 1 then
        params:hide(prefix .. "_rate")
      else
        params:show(prefix .. "_rate")
      end
      if wf == 6 then
        params:hide(prefix .. "_phase")
        params:hide(prefix .. "_rate_slew")
        params:show(prefix .. "_steps"); params:show(prefix .. "_stability")
        params:show(prefix .. "_sep_trigger"); params:show(prefix .. "_randomize")
      else
        params:show(prefix .. "_phase")
        params:show(prefix .. "_rate_slew")
        params:hide(prefix .. "_steps"); params:hide(prefix .. "_stability")
        params:hide(prefix .. "_sep_trigger"); params:hide(prefix .. "_randomize")
      end
      if _menu and _menu.rebuild_params then _menu.rebuild_params() end
    end

    local function compute_intended_global()
      local dev_filtered = params:get(prefix .. "_target_device")
      local dev_idx = (lfo_target_device_filter[idx] and lfo_target_device_filter[idx][dev_filtered]) or 1
      local param_filtered = params:get(prefix .. "_target_param")
      local g = (lfo_target_param_filter[idx] and lfo_target_param_filter[idx][param_filtered]) or 1
      if g <= 1 and DEVICE_PARAMS[dev_idx] and DEVICE_PARAMS[dev_idx][1] then
        g = DEVICE_PARAMS[dev_idx][1].global_idx
      end
      return g
    end

    params:add_group("MOD LFO " .. idx, 18)
    params:add_separator(prefix .. "_sep_control", "─── Control ───")

    params:add_option(prefix .. "_enable", "Enable", {"Off", "On"}, 1)
    params:set_action(prefix .. "_enable", function(v)
      if not initing then
        if v == 2 then
          local g = compute_intended_global()
          if g > 1 and lfo_target_owner[TARGET_PARAMS[g].id] then
            for i = 2, #TARGET_PARAMS do
              if not lfo_target_owner[TARGET_PARAMS[i].id] then g = i; break end
            end
          end
          set_lfo_target(idx, g)
        else
          set_lfo_target(idx, lfo_last_global[idx] or 1)
        end
      end
      re()
    end)

    params:add_option(prefix .. "_waveform", "Waveform", WAVEFORMS, 1)
    params:set_action(prefix .. "_waveform", function(_)
      refresh_visibility()
      if not initing then
        start_lfo_clock(idx)
        lfo_refresh_dropdowns_for_device("LFO " .. idx)
      end
      re()
    end)

    params:add_control(prefix .. "_rate", "Rate", controlspec.new(0.1, 25, "exp", 0.1, 1.0, "Hz"))
    params:set_action(prefix .. "_rate", function(_)
      lfo_mod.rate[idx] = nil
      lfo_target_base[prefix .. "_rate"] = nil
    end)

    params:add_control(prefix .. "_depth", "Depth", controlspec.new(0, 100, "lin", 1, 50, "%"))
    params:set_action(prefix .. "_depth", function(_)
      lfo_mod.depth[idx] = nil
      lfo_target_base[prefix .. "_depth"] = nil
    end)

    params:add_option(prefix .. "_dir", "Direction", DIR_OPTS, 3)

    params:add_option(prefix .. "_phase", "Phase", {"0°", "90°", "180°", "270°"}, 1)
    params:set_action(prefix .. "_phase", function(_)
      lfo_mod.phase[idx] = nil
      lfo_target_base[prefix .. "_phase"] = nil
    end)

    params:add_number(prefix .. "_steps", "Steps", 1, 16, 8)
    params:set_action(prefix .. "_steps", function(v)
      lfo_mod.steps[idx] = nil
      lfo_target_base[prefix .. "_steps"] = nil
      local s = lfo_state[idx]
      if s then s.tm_register = s.tm_register & tm_register_max(v) end
    end)

    params:add_control(prefix .. "_stability", "Stability", controlspec.new(0, 100, "lin", 1, 50, "%"))
    params:set_action(prefix .. "_stability", function(_)
      lfo_mod.stability[idx] = nil
      lfo_target_base[prefix .. "_stability"] = nil
    end)

    params:add_control(prefix .. "_rate_slew", "Rate Slew", controlspec.new(0, 5, "lin", 0.1, 0, "s"))
    params:set_action(prefix .. "_rate_slew", function(_)
      lfo_mod.rate_slew[idx] = nil
      lfo_target_base[prefix .. "_rate_slew"] = nil
    end)

    params:add_separator(prefix .. "_sep_sync", "─── Synchronization ───")

    params:add_option(prefix .. "_sync_div", "Sync", SYNC_DIV_OPTS, 1)
    params:set_action(prefix .. "_sync_div", function(_)
      lfo_mod.sync_div[idx] = nil
      lfo_target_base[prefix .. "_sync_div"] = nil
      refresh_visibility()
      if not initing then
        lfo_refresh_dropdowns_for_device("LFO " .. idx)
        start_lfo_clock(idx)
      end
    end)

    params:add_option(prefix .. "_sync_feel", "Sync Feel", SYNC_FEEL_OPTS, 1)
    params:set_action(prefix .. "_sync_feel", function(_)
      lfo_mod.sync_feel[idx] = nil
      lfo_target_base[prefix .. "_sync_feel"] = nil
    end)

    params:add_separator(prefix .. "_sep_target", "─── Target ───")

    params:add_option(prefix .. "_target_device", "Target Device", DEVICE_NAMES, 1)
    params:set_action(prefix .. "_target_device", function(filtered_v)
      if not initing then
        local cur_global = lfo_last_global[idx] or 1
        local cur_dev = TARGET_DEVICE_OF[cur_global]
        if not cur_dev then
          local dev_filtered = params:get(prefix .. "_target_device")
          cur_dev = (lfo_target_device_filter[idx] and lfo_target_device_filter[idx][dev_filtered]) or 1
        end
        local dmap = lfo_target_device_filter[idx]
        local cur_filtered = lfo_find_filtered_idx(dmap, cur_dev)
        if filtered_v > cur_filtered + 1 then filtered_v = cur_filtered + 1
        elseif filtered_v < cur_filtered - 1 then filtered_v = cur_filtered - 1 end
        local new_dev = (dmap and dmap[filtered_v]) or 1
        if new_dev ~= cur_dev then
          rebuild_lfo_target_param_dropdown(idx, new_dev)
          local new_global = 1
          if DEVICE_PARAMS[new_dev] then
            for _, entry in ipairs(DEVICE_PARAMS[new_dev]) do
              local owner = lfo_target_owner[TARGET_PARAMS[entry.global_idx].id]
              if owner == nil or owner == idx then new_global = entry.global_idx; break end
            end
          end
          set_lfo_target(idx, new_global)
        else
          lfo_ui_revert(prefix .. "_target_device", cur_filtered)
        end
      end
      re()
    end)

    local first_dev_shorts = {}
    if DEVICE_PARAMS[1] then
      for _, e in ipairs(DEVICE_PARAMS[1]) do first_dev_shorts[#first_dev_shorts + 1] = e.short end
    end
    if #first_dev_shorts == 0 then first_dev_shorts = {"-"} end
    params:add_option(prefix .. "_target_param", "Target Param", first_dev_shorts, math.min(idx, #first_dev_shorts))
    params:set_action(prefix .. "_target_param", function(filtered_v)
      if not initing then
        local cur_global = lfo_last_global[idx] or 1
        local pmap = lfo_target_param_filter[idx]
        local cur_filtered = lfo_find_filtered_idx(pmap, cur_global)
        if filtered_v > cur_filtered + 1 then filtered_v = cur_filtered + 1
        elseif filtered_v < cur_filtered - 1 then filtered_v = cur_filtered - 1 end
        local new_global = (pmap and pmap[filtered_v]) or 1
        if new_global ~= cur_global then
          set_lfo_target(idx, new_global)
        else
          lfo_ui_revert(prefix .. "_target_param", cur_filtered)
        end
      end
      re()
    end)

    params:add_separator(prefix .. "_sep_trigger", "─── Trigger ───")

    params:add_binary(prefix .. "_randomize", "Randomize", "trigger", 0)
    params:set_action(prefix .. "_randomize", function(v)
      if v == 1 and not initing then tm_randomize(idx) end
    end)
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
      quant_led_clock_restart()
      redraw()
    end

    clock.transport.stop = function()
      clock_running = false
      if metro_active then metro_clock_start() end
      sync_push_all()
      quant_led_clock_restart()
      redraw()
    end

    clock.run(function()
      local last_source = nil
      local last_bpm = 0
      while true do
        clock.sleep(0.5)

        local current_source = nil
        pcall(function() current_source = params:get("clock_source") end)
        if current_source and current_source ~= last_source then
          local default = current_source == 2 and 4 or 1
          params:set("tremolo_sync_div", default)
          params:set("warp_sync_div",    default)
          params:set("repeat_sync_div",  default)
          params:set("looper_quant_div", default)
          last_source = current_source
        end

        local bpm = math.floor(clock.get_tempo() + 0.5)
        if bpm ~= last_bpm then
          if last_bpm == 0 and bpm > 0 then
            clock_running = true
            sync_activate_defaults()
            if metro_active then metro_clock_start() end
            quant_led_clock_restart()
          elseif bpm == 0 and last_bpm > 0 then
            clock_running = false
            if metro_active then metro_clock_start() end
            quant_led_clock_restart()
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
  setup_signal_flow()
  for i = 1, #PEDALS do setup_pedal(i) end
  setup_amp()
  setup_tremolo()
  setup_looper()
  setup_reverb()
  setup_cab()
  setup_limit()
  setup_tuner()
  setup_metro()
  for i = 1, NUM_LFOS do register_lfo(i) end
  setup_pitch_poll()

  for _, t in ipairs(TARGET_PARAMS) do
    if t.id then
      local p = params:lookup_param(t.id)
      if p and p.action then
        local orig = p.action
        params:set_action(t.id, function(v)
          lfo_target_base[t.id] = v
          if lfo_target_owner[t.id] == nil then orig(v) end
        end)
      end
    end
  end

  params:bang()
  initing = false

  for i = 1, NUM_LFOS do
    local dev_filtered = params:get("lfo" .. i .. "_target_device")
    local dev_idx = (lfo_target_device_filter[i] and lfo_target_device_filter[i][dev_filtered]) or 1
    rebuild_lfo_target_param_dropdown(i, dev_idx)
    local param_filtered = params:get("lfo" .. i .. "_target_param")
    local g = (lfo_target_param_filter[i] and lfo_target_param_filter[i][param_filtered]) or 1
    if g <= 1 and DEVICE_PARAMS[dev_idx] and DEVICE_PARAMS[dev_idx][1] then
      g = DEVICE_PARAMS[dev_idx][1].global_idx
    end
    lfo_last_global[i] = g
  end

  for i = 1, NUM_LFOS do
    if params:get("lfo" .. i .. "_enable") == 2 then
      local g = lfo_last_global[i] or 1
      if g > 1 and lfo_target_owner[TARGET_PARAMS[g].id] then
        for j = 2, #TARGET_PARAMS do
          if not lfo_target_owner[TARGET_PARAMS[j].id] then g = j; break end
        end
      end
      if g > 1 then set_lfo_target(i, g) end
    end
  end

  setup_clock_watchers()
  redraw()

  clock.run(function()
    clock.sleep(0.2)
    audio.level_monitor(0)
  end)
end
