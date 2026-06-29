-- princeton
--
-- Amp sim based on a combo.
-- Tuner, effects and looper.

engine.name = "Princeton"

local initing = true

local sprites = include("lib/sprites")
local cabinet = include("lib/cabinet")
local sync    = include("lib/sync")
local scales  = include("lib/scales")
local tuner   = include("lib/tuner")
local looper  = include("lib/looper")
local looper_params = include("lib/looper_params")
local looper_ui = include("lib/looper_ui")
local lfo     = include("lib/lfo")
local env     = include("lib/env")
local trigs   = include("lib/trigger")
local lifecycle = include("lib/lifecycle")

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
  { id="looper_quant_div",  name="Quantize",      default=1,   min=1, max=8, step=1, db=false, cat="Looper", options={"Off","1/1","1/2","1/4","1/8","1/16","1/32","1/64"} },
  { id="looper_quant_feel", name="Quantize Feel", default=1,   min=1, max=3, step=1, db=false, cat="Looper", options={"Note","Dotted","Triplet"} },
}
local MIC_NAMES  = { "Center", "Middle", "Edge" }
local DIR_NAMES  = looper_params.DIR_NAMES

local sel = 1

local function amp_is_bypassed()
  return params:get("amp_enable") == 1
end


local view_group = 0
local view_pane  = {[0]=1, [1]=1, [3]=1}
local gui_mode   = 1   -- 1=Studio, 2=Stage, 3=Off
local perf_sel   = 1   -- selected device in performance view
local perf_param = {}  -- per-device selected param index
local refresh_tuner    -- forward decl; syncs tuner.active to the current view/device
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
    subsynth   = "push",
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
    subsynth   = "distort",
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

local clock_running = true
local db_to_lin = function(db) return 10 ^ (db / 20) end


-- ── Triggers ────────────────────────────────────────────────────


local TARGET_PARAMS = {
  {label="Off"},
  {label="Gate: Threshold",    id="gate_thresh",       mn=-80,  mx=0,     st=0.5,  send=function(v) engine.gate_thresh(v) end},
  {label="Gate: Attack",       id="gate_attack",       mn=0.1,  mx=2500,  st=0.1,  send=function(v) engine.gate_attack(v) end},
  {label="Gate: Hold",         id="gate_hold",         mn=1,    mx=2500,  st=1,    send=function(v) engine.gate_hold(math.floor(v)) end},
  {label="Gate: Release",      id="gate_release",      mn=1,    mx=2500,  st=1,    send=function(v) engine.gate_release(v) end},
  {label="Gate: Range",        id="gate_range",        mn=-75,  mx=0,     st=0.5,  send=function(v) engine.gate_range(v) end},
  {label="Gate: Margin",       id="gate_hyst",         mn=0,    mx=25,    st=0.5,  send=function(v) engine.gate_hyst(v) end},
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
  {label="Looper: Speed",      id="looper_speed",      mn=-100, mx=100,   st=1,    send=function(v)
    local ratio
    if params:get("looper_speed_control") == 1 then
      if v < 0 then ratio = 0.5 elseif v > 0 then ratio = 2.0 else ratio = 1.0 end
    else ratio = 2^(v/100) end
    engine.looper_speed(ratio)
  end},
  {label="Looper: Imprint",    id="looper_imprint",    mn=0,    mx=100,   st=1,    send=function(v) engine.looper_imprint(math.floor(v)) end},
  {label="Looper: Wear",       id="looper_wear",       mn=0,    mx=100,   st=1,    send=function(v) engine.looper_wear(math.floor(v)) end},
  {label="Looper: Cassette Wow", id="looper_wow_cas",    mn=0,    mx=100,   st=1,    send=function(v) engine.looper_wow_cas(math.floor(v)) end},
  {label="Looper: CD Errors",  id="looper_cd_errors",  mn=0,    mx=100,   st=1,    send=function(v) engine.looper_cd_errors(math.floor(v)) end},
  {label="Looper: Chip Crush", id="looper_chip_crush", mn=0,    mx=100,   st=1,    send=function(v) engine.looper_chip_crush(math.floor(v)) end},
  {label="Looper: Tape Wow",   id="looper_wow_tape",   mn=0,    mx=100,   st=1,    send=function(v) engine.looper_wow_tape(math.floor(v)) end},
  {label="Reverb: Amount",     id="reverb_amount",     mn=0,    mx=100,   st=1,    send=function(v) engine.reverb_amount(math.floor(v)) end},
  {label="Reverb: Length",     id="reverb_length",     mn=0.5,  mx=5.0,   st=0.1,  send=function(v) engine.reverb_length(v) end},
  {label="Reverb: Low Shelf",  id="reverb_low_shelf",  mn=-5,   mx=5,     st=0.5,  send=function(v) engine.reverb_low_shelf(v) end},
  {label="Reverb: High Shelf", id="reverb_high_shelf", mn=-5,   mx=5,     st=0.5,  send=function(v) engine.reverb_high_shelf(v) end},
  {label="Cab: Cab Level",     id="cab_level",         mn=-10,  mx=10,    st=0.5,  send=function(v) engine.cab_level(db_to_lin(v)) end},
  {label="Limit: Threshold",   id="limit_threshold",   mn=-40,  mx=0,     st=0.5,  send=function(v) engine.limit_threshold(db_to_lin(v)) end},
  {label="Limit: Ratio",       id="limit_ratio",       mn=2.0,  mx=20.0,  st=0.5,  send=function(v) engine.limit_ratio(v) end},
  {label="Limit: Attack",      id="limit_attack",      mn=1,    mx=100,   st=1,    send=function(v) engine.limit_attack(math.floor(v)) end},
  {label="Limit: Decay",       id="limit_decay",       mn=50,   mx=2000,  st=50,   send=function(v) engine.limit_decay(math.floor(v)) end},
  {label="Limit: Gain",        id="limit_gain",        mn=-20,  mx=20,    st=0.5,  send=function(v) engine.limit_gain(db_to_lin(v)) end},
  {label="Metro: Division",    id="metro_div",         mn=1,    mx=5,     st=1,    send=function(v) lfo.metro.div = math.floor(v+0.5) end},
  {label="Metro: Level",       id="metro_level",       mn=0,    mx=10,    st=0.1,  send=function(v) lfo.metro.level = v end},
  {label="Metro: Length",      id="metro_length",      mn=1,    mx=500,   st=1,    send=function(v) lfo.metro.length = math.floor(v + 0.5) end},
  {label="Metro: Root",        id="metro_root",        mn=0,    mx=12,    st=1,    send=function(v)
    local p = math.floor(v + 0.5)
    if p <= 0 then lfo.metro.root = 0; return end
    local tonic = ((lfo.target_base["metro_root"] or params:get("metro_root")) - 1) % 12
    lfo.metro.root = scales.quantize_root(p, tonic, params:get("metro_scale"))
  end},
  {label="Metro: Register",    id="metro_register",    mn=1,    mx=8,     st=1,    send=function(v) lfo.metro.register = math.floor(v + 0.5) end},
  {label="Metro: Scale",       id="metro_scale",       mn=1,    mx=8,     st=1,    send=function(v) lfo.metro.scale  = math.floor(v + 0.5) end},
  {label="Metro: Chords",      id="metro_chords",      mn=1,    mx=4,     st=1,    send=function(v) lfo.metro.chords = math.floor(v + 0.5) end},
  {label="Metro: Scale Play",  id="metro_scale_play",  mn=1,    mx=8,     st=1,    send=function(v) lfo.metro.play   = math.floor(v + 0.5) end},
  {label="Metro: Scale Degree",id="metro_degree",      mn=1,    mx=15,    st=1,    send=function(v) lfo.metro.degree = math.floor(v + 0.5) end},
  {label="LFO 1: Rate",        id="lfo1_rate",         mn=0.1,  mx=25,    st=0.1,  send=function(v) lfo.mod.rate[1]  = v end},
  {label="LFO 2: Rate",        id="lfo2_rate",         mn=0.1,  mx=25,    st=0.1,  send=function(v) lfo.mod.rate[2]  = v end},
  {label="LFO 3: Rate",        id="lfo3_rate",         mn=0.1,  mx=25,    st=0.1,  send=function(v) lfo.mod.rate[3]  = v end},
  {label="LFO 4: Rate",        id="lfo4_rate",         mn=0.1,  mx=25,    st=0.1,  send=function(v) lfo.mod.rate[4]  = v end},
  {label="LFO 5: Rate",        id="lfo5_rate",         mn=0.1,  mx=25,    st=0.1,  send=function(v) lfo.mod.rate[5]  = v end},
  {label="LFO 6: Rate",        id="lfo6_rate",         mn=0.1,  mx=25,    st=0.1,  send=function(v) lfo.mod.rate[6]  = v end},
  {label="LFO 7: Rate",        id="lfo7_rate",         mn=0.1,  mx=25,    st=0.1,  send=function(v) lfo.mod.rate[7]  = v end},
  {label="LFO 8: Rate",        id="lfo8_rate",         mn=0.1,  mx=25,    st=0.1,  send=function(v) lfo.mod.rate[8]  = v end},
  {label="LFO 1: Depth",       id="lfo1_depth",        mn=0,    mx=100,   st=1,    send=function(v) lfo.mod.depth[1] = v end},
  {label="LFO 2: Depth",       id="lfo2_depth",        mn=0,    mx=100,   st=1,    send=function(v) lfo.mod.depth[2] = v end},
  {label="LFO 3: Depth",       id="lfo3_depth",        mn=0,    mx=100,   st=1,    send=function(v) lfo.mod.depth[3] = v end},
  {label="LFO 4: Depth",       id="lfo4_depth",        mn=0,    mx=100,   st=1,    send=function(v) lfo.mod.depth[4] = v end},
  {label="LFO 5: Depth",       id="lfo5_depth",        mn=0,    mx=100,   st=1,    send=function(v) lfo.mod.depth[5] = v end},
  {label="LFO 6: Depth",       id="lfo6_depth",        mn=0,    mx=100,   st=1,    send=function(v) lfo.mod.depth[6] = v end},
  {label="LFO 7: Depth",       id="lfo7_depth",        mn=0,    mx=100,   st=1,    send=function(v) lfo.mod.depth[7] = v end},
  {label="LFO 8: Depth",       id="lfo8_depth",        mn=0,    mx=100,   st=1,    send=function(v) lfo.mod.depth[8] = v end},
  {label="Tremolo: Sync Div",  id="tremolo_sync_div",  mn=2,    mx=8,     st=1,    send=function(v)
    local new_v = math.floor(v+0.5)
    if lfo.sync_override["tremolo_sync_div"] ~= new_v then
      lfo.sync_override["tremolo_sync_div"] = new_v
      sync.push_all(initing, clock_running, lfo.sync_override)
    end
  end},
  {label="Tremolo: Sync Feel", id="tremolo_sync_feel", mn=1,    mx=3,     st=1,    send=function(v)
    local new_v = math.floor(v+0.5)
    if lfo.sync_override["tremolo_sync_feel"] ~= new_v then
      lfo.sync_override["tremolo_sync_feel"] = new_v
      sync.push_all(initing, clock_running, lfo.sync_override)
    end
  end},
  {label="Warp: Sync Div",     id="warp_sync_div",     mn=2,    mx=8,     st=1,    send=function(v)
    local new_v = math.floor(v+0.5)
    if lfo.sync_override["warp_sync_div"] ~= new_v then
      lfo.sync_override["warp_sync_div"] = new_v
      sync.push_all(initing, clock_running, lfo.sync_override)
    end
  end},
  {label="Warp: Sync Feel",    id="warp_sync_feel",    mn=1,    mx=3,     st=1,    send=function(v)
    local new_v = math.floor(v+0.5)
    if lfo.sync_override["warp_sync_feel"] ~= new_v then
      lfo.sync_override["warp_sync_feel"] = new_v
      sync.push_all(initing, clock_running, lfo.sync_override)
    end
  end},
  {label="Repeat: Sync Div",   id="repeat_sync_div",   mn=2,    mx=8,     st=1,    send=function(v)
    local new_v = math.floor(v+0.5)
    if lfo.sync_override["repeat_sync_div"] ~= new_v then
      lfo.sync_override["repeat_sync_div"] = new_v
      sync.push_all(initing, clock_running, lfo.sync_override)
    end
  end},
  {label="Repeat: Sync Feel",  id="repeat_sync_feel",  mn=1,    mx=3,     st=1,    send=function(v)
    local new_v = math.floor(v+0.5)
    if lfo.sync_override["repeat_sync_feel"] ~= new_v then
      lfo.sync_override["repeat_sync_feel"] = new_v
      sync.push_all(initing, clock_running, lfo.sync_override)
    end
  end},
  {label="Looper: Quantize",   id="looper_quant_div",  mn=2,    mx=8,     st=1,    send=function(v)
    local new_v = math.floor(v+0.5)
    if lfo.sync_override["looper_quant_div"] ~= new_v then
      lfo.sync_override["looper_quant_div"] = new_v
      looper.quant_led_restart()
    end
  end},
  {label="Looper: Quantize Feel", id="looper_quant_feel", mn=1,    mx=3,     st=1,    send=function(v)
    local new_v = math.floor(v+0.5)
    if lfo.sync_override["looper_quant_feel"] ~= new_v then
      lfo.sync_override["looper_quant_feel"] = new_v
      looper.quant_led_restart()
    end
  end},
}

for i = 1, lfo.NUM do
  TARGET_PARAMS[#TARGET_PARAMS+1] = {label="LFO "..i..": Phase",     id="lfo"..i.."_phase",     mn=1, mx=4,   st=1,   send=function(v) lfo.mod.phase[i]     = math.floor(v + 0.5) end}
  TARGET_PARAMS[#TARGET_PARAMS+1] = {label="LFO "..i..": Steps",     id="lfo"..i.."_steps",     mn=1, mx=16,  st=1,   send=function(v) lfo.mod.steps[i]     = math.floor(v + 0.5) end}
  TARGET_PARAMS[#TARGET_PARAMS+1] = {label="LFO "..i..": Stability", id="lfo"..i.."_stability", mn=0, mx=100, st=1,   send=function(v) lfo.mod.stability[i] = v end}
  TARGET_PARAMS[#TARGET_PARAMS+1] = {label="LFO "..i..": Rate Slew", id="lfo"..i.."_rate_slew", mn=0, mx=5,   st=0.1, send=function(v) lfo.mod.rate_slew[i] = v end}
  TARGET_PARAMS[#TARGET_PARAMS+1] = {label="LFO "..i..": Sync Div",  id="lfo"..i.."_sync_div",  mn=2, mx=8,   st=1,   send=function(v) lfo.mod.sync_div[i]  = math.floor(v + 0.5) end}
  TARGET_PARAMS[#TARGET_PARAMS+1] = {label="LFO "..i..": Sync Feel", id="lfo"..i.."_sync_feel", mn=1, mx=3,   st=1,   send=function(v) lfo.mod.sync_feel[i] = math.floor(v + 0.5) end}
end

for i = 1, trigs.N do
  TARGET_PARAMS[#TARGET_PARAMS+1] = {label="Trigger "..i..": Rate",        id="trig"..i.."_rate",        mn=0.1, mx=25,  st=0.1, send=function(v) trigs.mod.rate[i]        = v end}
  TARGET_PARAMS[#TARGET_PARAMS+1] = {label="Trigger "..i..": Probability", id="trig"..i.."_probability", mn=0,   mx=100, st=1,   send=function(v) trigs.mod.probability[i] = v end}
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

local TRIG_TARGETS = (function()
  local t = {
    { label = "Off" },
    { label = "Push: Toggle",    id = "trig_push_toggle",    action = function() params:set("push_enable",    3 - params:get("push_enable"))    end },
    { label = "Distort: Toggle", id = "trig_distort_toggle", action = function() params:set("distort_enable", 3 - params:get("distort_enable")) end },
    { label = "Warp: Toggle",    id = "trig_warp_toggle",    action = function() params:set("warp_enable",    3 - params:get("warp_enable"))    end },
    { label = "Repeat: Toggle",  id = "trig_repeat_toggle",  action = function() params:set("repeat_enable",  3 - params:get("repeat_enable"))  end },
    { label = "Amp: Toggle",     id = "trig_amp_toggle",     action = function() params:set("amp_enable",     3 - params:get("amp_enable"))     end },
    { label = "Tremolo: Toggle", id = "trig_tremolo_toggle", action = function() params:set("tremolo_enable", 3 - params:get("tremolo_enable")) end },
    { label = "Looper: Rec",     id = "trig_looper_rec",     action = function() looper.step() end },
    { label = "Looper: Clear",   id = "trig_looper_clear",   action = function() looper.force_clear() end },
    { label = "Reverb: Toggle",  id = "trig_reverb_toggle",  action = function() params:set("reverb_enable",  3 - params:get("reverb_enable"))  end },
    { label = "Limit: Toggle",   id = "trig_limit_toggle",   action = function() params:set("limit_enable",   3 - params:get("limit_enable"))   end },
  }
  for i = 1, lfo.NUM do
    t[#t + 1] = { label = "LFO " .. i .. ": Randomize", id = "trig_lfo" .. i .. "_randomize", lfo_idx = i,
                  action = function() params:set("lfo" .. i .. "_randomize", 1) end }
  end
  return t
end)()

local metro_active = false
local metro_clock  = nil
local metro_step   = 0

local k_clock = {}


local B = { DIM=0, MED=5, FULL=15 }

local GROUP_MAX = {[0]=2, [1]=16, [3]=4}

local METRO_STRIP = {
  {name="Division", id="metro_div",     typ="opt",  nmax=5,  fmt=function(v) return sync.METRO_DIV_OPTS[v] end},
  {name="Root",     id="metro_root",     typ="opt", nmax=12, fmt=function(v) return scales.NOTE_NAMES[v] end},
  {name="Register", id="metro_register", typ="opt", nmax=8,  fmt=function(v) return tostring(v - 1) end},
  {name="Scale",    id="metro_scale",    typ="opt",  nmax=8,  fmt=function(v) return scales.SCALE_NAMES[v] end},
  {name="Degree",   id="metro_degree",     typ="opt", nmax=15, fmt=function(v) return tostring(v) end},
  {name="Play",     id="metro_scale_play", typ="opt", nmax=8, fmt=function(v) return ({"Off","Fwd","Rev","3rds","4ths","5ths","7ths","Rnd"})[v] end},
  {name="Chords",   id="metro_chords",     typ="opt", nmax=4, fmt=function(v) return ({"Off","Octaves","Power","Triads"})[v] end},
  {name="Level",    id="metro_level",   typ="ctrl", step=0.1, fmt=function(v) return string.format("%.1f",v) end},
  {name="Length",   id="metro_length",  typ="ctrl", step=1,  fmt=function(v) return string.format("%dms",math.floor(v)) end},
  {name="Position", id="metro_position", typ="opt",  nmax=2,  fmt=function(v) return ({"Parallel","Inline"})[v] end},
}

local function fmt_unit(v, p)
  if p.unit then
    return p.step < 1 and string.format("%.1f%s", v, p.unit) or string.format("%d%s", math.floor(v), p.unit)
  end
  return string.format("%.1f", v)
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
  local s = sync.fmt(id, clock_running)
  if s then return s end
  if p.db   then return string.format("%.1fdB", v) end
  return fmt_unit(v, p)
end
local function fmt_val(idx) return fmt_def_val(PARAMS_DEF, idx) end

-- reverse lookup so any param id renders exactly as in its studio view
local PARAM_DEF_OF = {}
for i, e in ipairs(PARAMS_DEF) do PARAM_DEF_OF[e.id] = { def = PARAMS_DEF, idx = i } end
for i, e in ipairs(LOOPER_DEF) do PARAM_DEF_OF[e.id] = { def = LOOPER_DEF, idx = i } end
local PARAM_PED_OF = {}
for _, pd in ipairs(PEDALS) do
  for _, e in ipairs(pd.params) do PARAM_PED_OF[e.id] = e end
end

local function fmt_param(id)
  if id == "tuner_ref" then return string.format("%.1f Hz", params:get(id)) end
  local d = PARAM_DEF_OF[id]
  if d then return fmt_def_val(d.def, d.idx) end
  local pe = PARAM_PED_OF[id]
  if pe then
    local s = sync.fmt(id, clock_running)
    if s then return s end
    local v = params:get(id)
    if pe.options then return pe.options[v] end
    return fmt_unit(v, pe)
  end
  return params:string(id)
end

local function snap_val(v, step)
  if step == 1 then return math.floor(v + 0.5)
  else return math.floor(v * 10 + 0.5) / 10 end
end

-- one editing path for every view: device params carry a tuned step in the DEF
-- tables; edit_param applies it (plus the sync-division redirect) so the main
-- view, pedalboard, looper pane and stage view all edit a param identically.
-- params without a DEF step (gate/limit/cab/tuner) fall back to params:delta,
-- which is exactly how they behave in the PARAMS menu.
local PARAM_STEP = {}
for _, e in ipairs(PARAMS_DEF) do PARAM_STEP[e.id] = e.step end
for _, e in ipairs(LOOPER_DEF) do PARAM_STEP[e.id] = e.step end
for _, pd in ipairs(PEDALS) do
  for _, e in ipairs(pd.params) do PARAM_STEP[e.id] = e.step end
end
PARAM_STEP["tuner_ref"] = 0.1   -- tuner has a custom strip edit, no DEF entry

local function edit_param(id, d)
  local m = sync.PARAM_MAP[id]
  if m and params:get(m.div) > 1 then
    params:set(m.div, util.clamp(params:get(m.div) + (d > 0 and 1 or -1), 2, #sync.DIV_OPTS))
    return
  end
  local step = PARAM_STEP[id]
  if step then
    params:set(id, snap_val(params:get(id) + d * step, step))
  else
    params:delta(id, d)
  end
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
  screen.level(B.DIM); screen.rect(0, 0, cabinet.LEFT_W, 64); screen.fill()
  screen.font_size(8); screen.font_face(0)
  screen.level(B.MED);  screen.move(cabinet.LEFT_CX,  8); screen.text_center(cat)
  -- name: multi-part names always split onto two lines (for consistency)
  local name2
  local sp = name:find(" ")
  if sp then name, name2 = name:sub(1, sp - 1), name:sub(sp + 1) end
  local vy = 26
  screen.level(B.MED); screen.move(cabinet.LEFT_CX, 17); screen.text_center(name)
  if name2 then
    screen.level(B.MED); screen.move(cabinet.LEFT_CX, 26); screen.text_center(name2)
    vy = 35
  end
  -- unify value/unit: drop decimals on percent values, then no space before the unit
  if val_str then
    val_str = val_str:gsub("(%-?%d+)%.%d+(%s*%%)", "%1%2")  -- percent steps in whole %, so no decimals
    val_str = val_str:gsub("(%d)%s+([%a%%])", "%1%2")       -- "440.0 Hz"->"440.0Hz", "50 %"->"50%"
  end
  screen.level(val_lv); screen.move(cabinet.LEFT_CX, vy); screen.text_center(val_str)
  if val_str2 then
    screen.level(val_lv); screen.move(cabinet.LEFT_CX, vy + 9); screen.text_center(val_str2)
  end
end

local function draw_looper_state_icon()
  if     looper.state == looper.REC  then draw_icon_record(cabinet.LEFT_CX, cabinet.ICON_Y, B.FULL)
  elseif looper.state == looper.DUB  then draw_icon_dub(cabinet.LEFT_CX, cabinet.ICON_Y, B.FULL)
  elseif looper.state == looper.PLAY then draw_icon_play(cabinet.LEFT_CX, cabinet.ICON_Y, B.FULL)
  elseif looper.state == looper.STOP then draw_icon_stop(cabinet.LEFT_CX, cabinet.ICON_Y, B.MED)
  end
end

local function draw_left_strip()
  local cm = params:get("cab_mode")
  if PARAMS_DEF[sel] and PARAMS_DEF[sel].id == "mic_position" and cm == 1 then
    screen.level(B.DIM); screen.rect(0, 0, cabinet.LEFT_W, 64); screen.fill()
    screen.font_size(8); screen.font_face(0)
    screen.level(B.MED)
    screen.move(cabinet.LEFT_CX,  8); screen.text_center("Cab & Mic")
    screen.move(cabinet.LEFT_CX, 17); screen.text_center("Simulation")
    screen.move(cabinet.LEFT_CX, 26); screen.text_center("Bypass")
  else
    draw_strip(PARAMS_DEF[sel].cat, PARAMS_DEF[sel].name, fmt_val(sel), sync.val_level(PARAMS_DEF[sel].id, clock_running))
  end

  draw_looper_state_icon()
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
  local OX1     = cabinet.CAB.x
  local OX2     = cabinet.CAB.x + cabinet.CAB.w - 33
  local py      = 4

  if pair == 1 then
    tuner.draw_half(OX1, py, is_left)
    draw_metro_half(OX2, py, not is_left)
    if is_left then
      draw_strip("Tuner", "Reference", fmt_param("tuner_ref"), B.FULL)
    else
      local ms = METRO_STRIP[metro_strip_sel]
      draw_strip("Metro", ms.name, ms.fmt(params:get(ms.id)), B.FULL)
    end
  elseif pair == 2 then
    env.draw_half(OX1, py, 1, is_left)
    env.draw_half(OX2, py, 2, not is_left)
    local idx       = is_left and 1 or 2
    local strip_idx = env.strip_sel[idx]
    local es        = env.STRIP[strip_idx]
    local id  = "env" .. idx .. es.suf
    local v1  = es.fmt(params:get(id), idx)
    local v2  = nil
    if es.suf == "_target_param" then
      local sp = v1:find(" ")
      if sp then v1, v2 = v1:sub(1, sp - 1), v1:sub(sp + 1) end
    end
    draw_strip("Sense " .. idx, es.name, v1, B.FULL, v2)
  elseif pair >= 7 then
    local trig_l = (pair - 7) * 2 + 1
    local trig_r = trig_l + 1
    trigs.draw_half(OX1, py, trig_l, is_left)
    trigs.draw_half(OX2, py, trig_r, not is_left)
    local idx       = is_left and trig_l or trig_r
    local strip_idx = trigs.strip_fn.resolve(idx, trigs.strip_sel[idx])
    local ts        = trigs.STRIP[strip_idx]
    local id  = "trig" .. idx .. ts.suf
    local v1  = ts.fmt(params:get(id), idx)
    draw_strip("Trigger " .. idx, ts.name, v1, B.FULL)
  else
    local lfo_l = (pair - 3) * 2 + 1
    local lfo_r = lfo_l + 1
    lfo.draw_half(OX1, py, lfo_l, is_left)
    lfo.draw_half(OX2, py, lfo_r, not is_left)
    local idx       = is_left and lfo_l or lfo_r
    local strip_idx = lfo.strip_resolve(idx, lfo_strip_sel[idx])
    local ls        = lfo.STRIP[strip_idx]
    local id  = "lfo" .. idx .. ls.suf
    local v1  = ls.fmt(params:get(id), idx)
    local v2  = nil
    if ls.suf == "_waveform" or ls.suf == "_target_param" then
      local sp = v1:find(" ")
      if sp then v1, v2 = v1:sub(1, sp - 1), v1:sub(sp + 1) end
    end
    draw_strip("LFO " .. idx, ls.name, v1, B.FULL, v2)
  end

  local cur_cx = (is_left and OX1 or OX2) + 16
  local cur_label
  if pair == 1 then
    cur_label = is_left and "Tuner" or "Metro"
  elseif pair == 2 then
    cur_label = "Sense " .. (is_left and 1 or 2)
  elseif pair >= 7 then
    local trig_l = (pair - 7) * 2 + 1
    cur_label = "Trig " .. (is_left and trig_l or (trig_l + 1))
  else
    local lfo_l = (pair - 3) * 2 + 1
    cur_label = "LFO " .. (is_left and lfo_l or (lfo_l + 1))
  end
  draw_label_cursor(cur_cx, py + 56, cur_label)

  screen.update()
end

local function draw_pedalboard()
  screen.clear()

  local psel = cur_pedal_sel()
  local pd   = cur_pedal()
  local p    = pd.params[pd.psel]
  local v    = params:get(p.id)
  local vstr = sync.fmt(p.id, clock_running)
  if not vstr then
    if p.options then vstr = p.options[v]
    else vstr = fmt_unit(v, p) end
  end
  draw_strip(pd.name, p.name, vstr, sync.val_level(p.id, clock_running))

  -- ── Two pedals, snapped to CAB edges ────────────────────────────
  local OX1 = cabinet.CAB.x
  local OX2 = cabinet.CAB.x + cabinet.CAB.w - 33
  local py  = 4

  if view_pane[3] >= 3 then
    local fk3 = (psel == 3) and pd.psel or nil
    local fk4 = (psel == 4) and pd.psel or nil
    sprites.draw_pedal(OX1, py, PEDALS[3].name, PEDALS[3].display, params:get(PEDALS[3].enable_id) == 1, fk3)
    sprites.draw_pedal(OX2, py, PEDALS[4].name, PEDALS[4].display, params:get(PEDALS[4].enable_id) == 1, fk4)
  else
    local fk1 = (psel == 1) and pd.psel or nil
    local fk2 = (psel == 2) and pd.psel or nil
    sprites.draw_pedal(OX1, py, PEDALS[1].name, PEDALS[1].display, params:get(PEDALS[1].enable_id) == 1, fk1)
    sprites.draw_pedal(OX2, py, PEDALS[2].name, PEDALS[2].display, params:get(PEDALS[2].enable_id) == 1, fk2)
  end
  local cur_cx = ((psel % 2 == 1) and OX1 or OX2) + 16
  draw_label_cursor(cur_cx, py + 56, PEDALS[psel].display)

  screen.update()
end

local function draw_looper_pane()
  looper_ui.draw_pane()
end

local PERF_DEVICES = {
  { abbr="TNR", name="Tuner",     active=function() return not tuner.muted end,
    params={"tuner_ref"} },
  { abbr="GTE", name="Gate",      enable="gate_enable",
    params={"gate_thresh","gate_attack","gate_hold","gate_release","gate_range","gate_hyst","gate_detect"} },
  { abbr="PSH", name="Push",      enable="push_enable",
    params={"push_gain","push_tone","push_level","push_mix"} },
  { abbr="DST", name="Distort",   enable="distort_enable",
    params={"distort_gain","distort_tone","distort_level","distort_lowcut"} },
  { abbr="WRP", name="Warp",      enable="warp_enable",
    params={"warp_rate","warp_depth","warp_rise","warp_mix","warp_sync_div","warp_sync_feel"} },
  { abbr="RPT", name="Repeat",    enable="repeat_enable",
    params={"repeat_time","repeat_feedback","repeat_level","repeat_characteristic","repeat_sync_div","repeat_sync_feel"} },
  { abbr="AMP", name="Amp",       enable="amp_enable",
    params={"amp_volume","amp_bass","amp_treble","amp_master"} },
  { abbr="TRM", name="Tremolo",   enable="tremolo_enable",
    params={"tremolo_speed","tremolo_intensity","tremolo_sync_div","tremolo_sync_feel"} },
  { abbr="LPR", name="Looper",    active=function() return looper.state ~= looper.IDLE end,
    params={"looper_medium","looper_wear","looper_direction","looper_dub_level","looper_level","looper_fade_level","looper_speed","looper_quant_div","looper_quant_feel"} },
  { abbr="RVB", name="Reverb",    enable="reverb_enable",
    params={"reverb_amount","reverb_length","reverb_low_shelf","reverb_high_shelf"} },
  { abbr="CAB", name="Cab & Mic", enable="cab_mode",
    params={"mic_position","cab_level"} },
  { abbr="LMT", name="Limit",     enable="limit_enable",
    params={"limit_threshold","limit_ratio","limit_attack","limit_decay","limit_gain"} },
}

local function perf_active(dev)
  if dev.active then return dev.active() end
  return params:get(dev.enable) == 2
end
local PERF_COLS, PERF_ROWS = 4, 3   -- 3x4; set to 6, 2 for 2x6
local PERF_ROW_SPREAD = 3            -- top row up, bottom row down, toward the screen edges

local function perf_pid()
  local dev = PERF_DEVICES[perf_sel]
  return dev.params[perf_param[perf_sel] or 1]
end

-- serpentine placement: odd rows run right-to-left, so the signal path snakes
-- and the row transitions (DST->WRP, TRM->LPR) drop straight down
local function perf_pos(d)
  local i   = d - 1
  local row = math.floor(i / PERF_COLS)
  local col = i % PERF_COLS
  if row % 2 == 1 then col = PERF_COLS - 1 - col end
  return col, row
end

local function perf_row_y(gy, ch, row) return gy + row * ch + (row - 1) * PERF_ROW_SPREAD end

local function draw_perf_flow(gx, gy, cw, ch)
  screen.level(B.MED)
  local function cx(c)   return gx + c * cw + math.floor(cw / 2) end
  local function rowy(r) return perf_row_y(gy, ch, r) end
  local function cy(r)   return rowy(r) + math.floor(ch / 2) end
  -- input: from the top edge down into the first block (TNR)
  local ic = perf_pos(1)
  screen.move(cx(ic), 0); screen.line(cx(ic), rowy(0) + 2); screen.stroke()
  -- connectors following the serpentine signal path 1 -> 12
  for d = 1, #PERF_DEVICES - 1 do
    local c1, r1 = perf_pos(d)
    local c2, r2 = perf_pos(d + 1)
    if r1 == r2 then
      local lc, rc = math.min(c1, c2), math.max(c1, c2)
      screen.move(gx + lc * cw + cw - 1, cy(r1)); screen.line(gx + rc * cw + 1, cy(r1)); screen.stroke()
    else
      screen.move(cx(c1), rowy(r1) + ch - 2); screen.line(cx(c1), rowy(r2) + 2); screen.stroke()
    end
  end
  -- output: from the last block (LMT) straight down to the bottom edge
  local oc, orow = perf_pos(#PERF_DEVICES)
  screen.move(cx(oc), rowy(orow) + ch - 2); screen.line(cx(oc), 63); screen.stroke()
end

local function draw_performance()
  screen.clear()
  -- left: studio-style readout for the selected device
  local dev = PERF_DEVICES[perf_sel]
  if dev.abbr == "LPR" then
    local li = perf_param[perf_sel] or 1
    local lp = LOOPER_DEF[li]
    draw_strip(lp.cat, lp.name, fmt_def_val(LOOPER_DEF, li), sync.val_level(lp.id, clock_running))
    draw_looper_state_icon()
  elseif dev.abbr == "TNR" then
    local cx  = cabinet.LEFT_CX
    local tlv = tuner.muted and B.MED or B.FULL
    local pid = perf_pid()
    draw_strip(dev.name, params:lookup_param(pid).name, fmt_param(pid), B.FULL)
    screen.font_size(16); screen.font_face(0); screen.level(tlv)
    screen.move(cx, 46); screen.text_center(tuner.note)
    screen.font_size(8)
    if tuner.note ~= "--" then
      screen.level(tlv)
      screen.move(cx + 12, 36); screen.text(tostring(tuner.octave))
      tuner.draw_arrow(cx, 58, tuner.arrow)
    end
  else
    local pid = perf_pid()
    draw_strip(dev.name, params:lookup_param(pid).name, fmt_param(pid), B.FULL)
  end
  -- right: 12 device blocks in the cabinet footprint
  screen.font_size(8); screen.font_face(0)
  local cw = math.floor(cabinet.CAB.w / PERF_COLS)
  local ch = math.floor(cabinet.CAB.h / PERF_ROWS)
  local gx = cabinet.CAB.x + math.floor((cabinet.CAB.w - cw * PERF_COLS) / 2)
  local gy = cabinet.CAB.y + math.floor((cabinet.CAB.h - ch * PERF_ROWS) / 2)
  draw_perf_flow(gx, gy, cw, ch)
  for d = 1, #PERF_DEVICES do
    local col, row = perf_pos(d)
    local x   = gx + col * cw
    local y   = perf_row_y(gy, ch, row)
    local dv  = PERF_DEVICES[d]
    screen.level(d == perf_sel and B.FULL or B.MED)
    screen.rect(x + 1, y + 2, cw - 2, ch - 4); screen.stroke()  -- 1px shorter top+bottom for the flow gap
    screen.level(perf_active(dv) and B.FULL or B.MED)
    local tw = screen.text_extents(dv.abbr)
    screen.move(math.floor(x + (cw - tw) / 2), y + ch / 2 + 2); screen.text(dv.abbr)
  end
  screen.update()
end

local function perf_enc(n, d)
  if n == 1 then
    perf_sel = util.clamp(perf_sel + d, 1, #PERF_DEVICES)
  elseif n == 2 then
    local dev = PERF_DEVICES[perf_sel]
    perf_param[perf_sel] = util.clamp((perf_param[perf_sel] or 1) + d, 1, #dev.params)
  elseif n == 3 then
    edit_param(perf_pid(), d)
  end
  if refresh_tuner then refresh_tuner() end
  redraw()
end

function redraw()
  if initing then return end
  if gui_mode == 3 then screen.clear(); screen.update(); return end
  if gui_mode == 2 then draw_performance(); return end
  if view_group == 1 then draw_group1_pane(); return end
  if view_group == 3 then draw_pedalboard(); return end
  if view_pane[0] == 2 then draw_looper_pane(); return end
  screen.clear()
  draw_left_strip()
  cabinet.draw_grillcloth(params:get("cab_mode"), PARAMS_DEF[sel] and PARAMS_DEF[sel].id == "mic_position", params:get("mic_position") - 1)
  cabinet.draw_panel(sel, params:get("signal_input") == 2, amp_is_bypassed())
  cabinet.draw_cabinet()
  screen.update()
end

local function is_tuner_active()
  if gui_mode ~= 1 then return gui_mode == 2 and PERF_DEVICES[perf_sel].abbr == "TNR" end
  return view_group == 1 and view_pane[1] == 1
end

refresh_tuner = function() tuner.set_active(is_tuner_active()) end


local function set_view(g)
  view_group = g
  tuner.set_active(is_tuner_active())
  redraw()
end

local function set_pane(p)
  local g = view_group
  view_pane[g] = util.clamp(p, 1, GROUP_MAX[g])
  tuner.set_active(is_tuner_active())
  redraw()
end

local function metro_tick_now()
  local level    = lfo.metro.level    ~= nil and lfo.metro.level / 10.0 or params:get("metro_level") / 10.0
  local length   = lfo.metro.length   ~= nil and lfo.metro.length        or params:get("metro_length")
  local root     = lfo.metro.root     ~= nil and lfo.metro.root          or params:get("metro_root")
  local register = lfo.metro.register ~= nil and lfo.metro.register      or params:get("metro_register")
  if root <= 0 then return end
  local scale_idx = lfo.metro.scale  ~= nil and lfo.metro.scale  or params:get("metro_scale")
  local play      = lfo.metro.play   ~= nil and lfo.metro.play   or params:get("metro_scale_play")
  local kind      = lfo.metro.chords ~= nil and lfo.metro.chords or params:get("metro_chords")
  local position  = params:get("metro_position") - 1
  local base      = (register - 1) * 12 + root

  local stepping  = (scale_idx >= 2 and play >= 2)
  local degree    = 1
  if scale_idx >= 2 then
    local base_deg   = stepping and scales.play_degree(scale_idx, play, metro_step) or 1
    local degree_off = (lfo.metro.degree ~= nil and lfo.metro.degree or params:get("metro_degree")) - 1
    degree = base_deg + degree_off
  end

  for _, off in ipairs(scales.chord_tones(scale_idx, degree, kind)) do
    local p = util.clamp(base + off, 1, 108)
    engine.metro_tick(level, p - 1 - 57, length, position)
  end

  if stepping then metro_step = metro_step + 1 end
end

local function metro_clock_start()
  if metro_clock then clock.cancel(metro_clock) end
  metro_step = 0
  metro_clock = clock.run(function()
    if clock_running then
      clock.sync(sync.METRO_DIV_BEATS[lfo.metro.div or params:get("metro_div")])
      while true do
        metro_tick_now()
        clock.sync(sync.METRO_DIV_BEATS[lfo.metro.div or params:get("metro_div")])
      end
    else
      while true do
        metro_tick_now()
        local div = lfo.metro.div or params:get("metro_div")
        local bpm = tonumber(params:get("metro_bpm")) or 120
        clock.sleep(sync.METRO_DIV_BEATS[div] * 60.0 / bpm)
      end
    end
  end)
end

local function metro_clock_stop()
  if metro_clock then clock.cancel(metro_clock); metro_clock = nil end
end

function enc(n, d)
  if gui_mode == 3 then return end
  if gui_mode == 2 then perf_enc(n, d); return end
  if view_group == 1 then
    if n == 1 then
      set_pane(view_pane[1] + d)
      return
    end
    local p = view_pane[1]
    if p == 1 then
      if n == 3 then edit_param("tuner_ref", d) end
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
    elseif p == 3 or p == 4 then
      local idx = (p == 3) and 1 or 2
      if n == 2 then
        env.strip_sel[idx] = env.strip_advance(idx, env.strip_sel[idx], d)
        redraw()
      elseif n == 3 then
        local es  = env.STRIP[env.strip_sel[idx]]
        local id  = "env" .. idx .. es.suf
        if es.typ == "opt" then
          local nmax = es.nmax_fn and es.nmax_fn(idx) or es.nmax
          if nmax > 0 then
            params:set(id, util.clamp(params:get(id) + d, 1, nmax))
          end
        else
          params:set(id, snap_val(params:get(id) + d * es.step, es.step))
        end
        redraw()
      end
    elseif p >= 13 then
      local is_left = (p % 2) == 1
      local pair    = math.ceil(p / 2)
      local idx     = (pair - 7) * 2 + (is_left and 1 or 2)
      if n == 2 then
        trigs.strip_sel[idx] = trigs.strip_fn.advance(idx, trigs.strip_sel[idx], d)
        redraw()
      elseif n == 3 then
        local ts  = trigs.STRIP[trigs.strip_sel[idx]]
        local id  = "trig" .. idx .. ts.suf
        if ts.typ == "opt" then
          local nmax = ts.nmax_fn and ts.nmax_fn(idx) or ts.nmax
          if nmax > 0 then
            params:set(id, util.clamp(params:get(id) + d, 1, nmax))
          end
        else
          params:set(id, snap_val(params:get(id) + d * ts.step, ts.step))
        end
        if ts.suf == "_sync_div" then trigs.fn.start_clock(idx) end
        redraw()
      end
    else
      local is_left = (p % 2) == 1
      local pair    = math.ceil(p / 2)
      local idx     = (pair - 3) * 2 + (is_left and 1 or 2)
      if n == 2 then
        lfo_strip_sel[idx] = lfo.strip_advance(idx, lfo_strip_sel[idx], d)
        redraw()
      elseif n == 3 then
        local ls  = lfo.STRIP[lfo_strip_sel[idx]]
        local id  = "lfo" .. idx .. ls.suf
        if ls.typ == "opt" then
          local nmax = ls.nmax_fn and ls.nmax_fn(idx) or ls.nmax
          if nmax > 0 then
            params:set(id, util.clamp(params:get(id) + d, 1, nmax))
          end
        else
          params:set(id, snap_val(params:get(id) + d * ls.step, ls.step))
        end
        if ls.suf == "_sync_div" then lfo.start_clock(idx) end
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
      edit_param(pd.params[pd.psel].id, d)
      redraw()
    end
    return
  end

  if n == 1 then
    set_pane(view_pane[0] + d)
    return
  end

  if view_pane[0] == 2 then
    looper_ui.enc(n, d)
    return
  end

  if n == 2 then
    sel = util.clamp(sel + d, 1, #PARAMS_DEF)
    redraw()
  elseif n == 3 then
    edit_param(PARAMS_DEF[sel].id, d)
    redraw()
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

local function perf_key(n, z)
  local dev = PERF_DEVICES[perf_sel]
  if n == 2 then
    long_press("k2", z, function() end, function()
      if dev.abbr == "LPR" then looper.stop_clear() end
    end)
  elseif n == 3 then
    long_press("k3", z, function() end, function()
      if dev.abbr == "LPR" then
        looper.step()
      elseif dev.abbr == "TNR" then
        tuner.muted = not tuner.muted
        engine.mute(tuner.muted and 1 or 0)
        redraw()
      elseif dev.enable then
        params:set(dev.enable, 3 - params:get(dev.enable))
      end
    end)
  end
end

function key(n, z)
  if gui_mode == 3 then return end
  if gui_mode == 2 then perf_key(n, z); return end
  if n == 1 then
    long_press("k1", z, function()
      if view_group == 1 then set_view(0) else set_view(1) end
    end)
    return
  end

  if n == 2 then
    long_press("k2", z, function()
      if view_group == 3 and view_pane[3] <= 2 then set_view(0)
      else view_pane[3] = 1; set_view(3) end
    end, function()
      if view_group == 0 then
        looper.stop_clear()
      elseif view_group == 1 then
        local p = view_pane[1]
        if p >= 5 and p <= 12 then
          local is_left = (p % 2) == 1
          local pair    = math.ceil(p / 2)
          local idx     = (pair - 3) * 2 + (is_left and 1 or 2)
          params:set("lfo" .. idx .. "_randomize", 1)
        end
      end
    end)
    return
  end

  if n == 3 then
    long_press("k3", z, function()
      if view_group == 3 and view_pane[3] >= 3 then set_view(0)
      else view_pane[3] = 3; set_view(3) end
    end, function()
      if view_group == 0 then
        looper.step()
      elseif view_group == 1 then
        local p = view_pane[1]
        if p == 1 then
          tuner.muted = not tuner.muted
          engine.mute(tuner.muted and 1 or 0)
          redraw()
        elseif p == 2 then
          local cur = params:get("metro_enable")
          params:set("metro_enable", 3 - cur)
        elseif p == 3 or p == 4 then
          local idx = (p == 3) and 1 or 2
          local cur = params:get("env" .. idx .. "_enable")
          params:set("env" .. idx .. "_enable", 3 - cur)
        elseif p >= 5 and p <= 12 then
          local is_left = (p % 2) == 1
          local pair    = math.ceil(p / 2)
          local idx     = (pair - 3) * 2 + (is_left and 1 or 2)
          local cur = params:get("lfo" .. idx .. "_enable")
          params:set("lfo" .. idx .. "_enable", 3 - cur)
        elseif p >= 13 then
          local is_left = (p % 2) == 1
          local pair    = math.ceil(p / 2)
          local idx     = (pair - 7) * 2 + (is_left and 1 or 2)
          local cur = params:get("trig" .. idx .. "_enable")
          params:set("trig" .. idx .. "_enable", 3 - cur)
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
  if not params._orig_read then
    params._orig_read = params.read
    params.pset_loading = false
    params.read = function(self, ...)
      params.pset_loading = true
      local ok, err = pcall(params._orig_read, self, ...)
      params.pset_loading = false
      if not ok then error(err) end
    end
  end
  audio.level_monitor(0)
  looper.init({
    is_clock_running = function() return clock_running end,
    get_override     = function() return lfo.sync_override end,
    is_pane_visible  = function() return view_group == 0 and view_pane[0] == 2 end,
  })
  looper_ui.init({
    draw_strip      = draw_strip,
    fmt_val         = function(i) return fmt_def_val(LOOPER_DEF, i) end,
    LOOPER_DEF      = LOOPER_DEF,
    val_level       = function(id) return sync.val_level(id, clock_running) end,
    draw_state_icon = draw_looper_state_icon,
    B               = B,
    looper          = looper,
    LOOPER_PTS      = sprites.LOOPER_PTS,
    edit_param      = edit_param,
  })
  lfo.init({
    TARGET_PARAMS    = TARGET_PARAMS,
    DEVICE_NAMES     = DEVICE_NAMES,
    DEVICE_PARAMS    = DEVICE_PARAMS,
    TARGET_DEVICE_OF = TARGET_DEVICE_OF,
    is_clock_running = function() return clock_running end,
    is_initing      = function() return initing end,
    on_sync_override_change = function(target_id)
      sync.push_all(initing, clock_running, lfo.sync_override)
      if target_id == "looper_quant_div" or target_id == "looper_quant_feel" then
        looper.quant_led_restart()
      end
    end,
    get_trigs_mod    = function() return trigs.mod end,
    on_target_change = function() env.rebuild_all_target_dropdowns() end,
  })
  env.init({
    TARGET_PARAMS    = TARGET_PARAMS,
    DEVICE_NAMES     = DEVICE_NAMES,
    DEVICE_PARAMS    = DEVICE_PARAMS,
    TARGET_DEVICE_OF = TARGET_DEVICE_OF,
    lfo              = lfo,
    is_initing      = function() return initing end,
    is_pane_visible_l = function() return view_group == 1 and view_pane[1] == 3 end,
    is_pane_visible_r = function() return view_group == 1 and view_pane[1] == 4 end,
    redraw_pane      = function() if not initing then redraw() end end,
  })
  trigs.init({
    looper           = looper,
    lfo              = lfo,
    targets          = TRIG_TARGETS,
    is_initing      = function() return initing end,
    is_clock_running = function() return clock_running end,
  })
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
        sync.push_all(initing, clock_running, lfo.sync_override)
        lfo.refresh_dropdowns_for_device(dev_name)
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

  local function add_sync_params(prefix)
    params:add_separator(prefix .. "_sep_sync", "─── Synchronization ───")
    params:add_option(prefix .. "_sync_div", "Sync", sync.DIV_OPTS, 4)
    params:set_action(prefix .. "_sync_div", sync_df_action(prefix))
    params:add_option(prefix .. "_sync_feel", "Sync Feel", sync.FEEL_OPTS, 1)
    params:set_action(prefix .. "_sync_feel", sync_df_action(prefix))
  end

  local function setup_pedal(idx)
    local ped = PEDALS[idx]
    local prefix = ped.name:lower()
    local has_sync = false
    for _, p in ipairs(ped.params) do
      if sync.PARAM_MAP[p.id] then has_sync = true; break end
    end
    params:add_group(ped.name:upper(), 6 + (has_sync and 3 or 0))
    params:add_separator(prefix .. "_sep_control", "─── Control ───")
    params:add_option(ped.enable_id, "Enable", {"Bypass", "Active"}, 1)
    params:set_action(ped.enable_id, function(v)
      if ped.subsynth then lifecycle.set(ped.subsynth, v == 2)
      else engine[ped.bypass_cmd](2 - v) end
      re()
    end)
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
    looper_params.setup({
      re                   = re,
      db_to_lin            = db_to_lin,
      is_initing           = function() return initing end,
      on_quant_div_changed = function() lfo.refresh_dropdowns_for_device("Looper") end,
      speed_is_owned       = function() return lfo.target_owner["looper_speed"] ~= nil end,
      looper               = looper,
      embedded             = true,
    })
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

  local CAB_MODE_ALL = {"mic_position", "cab_level"}
  local CAB_MODE_VISIBLE = {
    [1] = {},
    [2] = {mic_position=true, cab_level=true},
  }

  local function setup_cab()
    params:add_group("CAB & MIC", 4)
    params:add_separator("cab_sep_control", "─── Control ───")
    params:add_option("cab_mode", "Mode", {"Bypass", "Cab & Mic Sim"}, 2)
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
  end

  local function setup_limit()
    params:add_group("LIMIT", 7)
    params:add_separator("limit_sep_control", "─── Control ───")
    params:add_option("limit_enable", "Enable", {"Bypass", "Active"}, 1)
    params:set_action("limit_enable", function(v) engine.limit_bypass(2 - v); re() end)
    params:add_control("limit_threshold", "Threshold", controlspec.new(-40, 0, "lin", 0.5, -10, "dB"))
    params:set_action("limit_threshold", db_action("limit_threshold"))
    add_engine_ctrl("limit_ratio",  "Ratio",  2.0, 20.0, "lin", 0.5, 4.0, ": 1")
    add_engine_ctrl("limit_attack", "Attack", 1,   100,  "lin", 1,   10,  "ms")
    add_engine_ctrl("limit_decay",  "Decay",  50,  2000, "lin", 50,  50,  "ms")
    params:add_control("limit_gain", "Gain", controlspec.new(-20, 20, "lin", 0.5, 0, "dB"))
    params:set_action("limit_gain", db_action("limit_gain"))
  end

  local function setup_gate()
    params:add_group("NOISE GATE", 9)
    params:add_separator("gate_sep_control", "─── Control ───")
    params:add_option("gate_enable", "Enable", {"Bypass", "Active"}, 1)
    params:set_action("gate_enable", function(v) if v == 2 then engine.gate_on() else engine.gate_off() end; re() end)
    params:add_control("gate_thresh", "Threshold", controlspec.new(-80, 0, "lin", 0.5, -50, "dB"))
    params:set_action("gate_thresh", function(v) engine.gate_thresh(v); re() end)
    add_engine_ctrl("gate_attack",  "Attack",  0.1, 2500, "exp", 0, 1,   "ms")
    add_engine_ctrl("gate_hold",    "Hold",    1,   2500, "exp", 0, 20,  "ms")
    add_engine_ctrl("gate_release", "Release", 1,   2500, "exp", 0, 100, "ms")
    params:add_control("gate_range", "Range", controlspec.new(-75, 0, "lin", 0.5, -75, "dB"))
    params:set_action("gate_range", function(v) engine.gate_range(v); re() end)
    add_engine_ctrl("gate_hyst", "Margin", 0, 25, "lin", 0.5, 0, "dB")
    params:add_option("gate_detect", "Detection", {"Peak", "RMS"}, 1)
    params:set_action("gate_detect", function(v) engine.gate_detect(v - 1); re() end)
  end

  local function setup_metro()
    params:add_group("METRO", 15)
    params:add_separator("metro_sep_control", "─── Control ───")
    params:add_option("metro_enable", "Enable", {"Off", "On"}, 1)
    params:set_action("metro_enable", function(v) metro_active = (v == 2); if metro_active then metro_clock_start() else metro_clock_stop() end; re() end)
    params:add_text("metro_bpm", "BPM", "120")
    params:add_option("metro_div", "Division", sync.METRO_DIV_OPTS, 3)
    params:set_action("metro_div", function(_) if metro_active then metro_clock_start() end end)

    params:add_separator("metro_sep_voice", "─── Voice ───")
    params:add_option("metro_root", "Root", scales.NOTE_NAMES, 1)
    params:set_action("metro_root", function(_) lfo.metro.root = nil; re() end)
    params:add_option("metro_register", "Register", {"0","1","2","3","4","5","6","7"}, 4)
    params:set_action("metro_register", function(_) lfo.metro.register = nil; re() end)
    params:add_option("metro_scale", "Scale", scales.SCALE_NAMES, 1)
    params:set_action("metro_scale", function(v)
      lfo.metro.scale = nil
      if v == 1 then params:hide("metro_scale_play"); params:hide("metro_degree")
      else            params:show("metro_scale_play"); params:show("metro_degree") end
      if _menu and _menu.rebuild_params then _menu.rebuild_params() end
      re()
    end)
    params:add_number("metro_degree", "Scale Degree", 1, 15, 1)
    params:set_action("metro_degree", function(_) lfo.metro.degree = nil end)
    params:add_option("metro_scale_play", "Scale Play",
      {"Off", "Forward", "Reverse", "Interval (Thirds)", "Interval (Fourths)", "Interval (Fifths)", "Interval (Sevenths)", "Random"}, 1)
    params:set_action("metro_scale_play", function(_) lfo.metro.play = nil; metro_step = 0 end)
    params:add_option("metro_chords", "Chords", {"Off", "Octaves", "Power Chords", "Triads"}, 1)
    params:set_action("metro_chords", function(_) lfo.metro.chords = nil end)

    params:add_separator("metro_sep_sound", "─── Sound ───")
    params:add_control("metro_level", "Level", controlspec.new(0, 10, "lin", 0.1, 5.0, ""))
    params:set_action("metro_level", function(_) lfo.metro.level = nil; re() end)
    params:add_control("metro_length", "Length", controlspec.new(1, 500, "lin", 1, 50, "ms"))
    params:set_action("metro_length", function(_) lfo.metro.length = nil end)
    params:add_option("metro_position", "Position", {"Parallel", "Inline"}, 1)
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

  local function find_filtered_idx(map, target)
    if map then
      for fi, gi in ipairs(map) do
        if gi == target then return fi end
      end
    end
    return 1
  end

  local function ui_revert(param_id, target_idx)
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
      local dev_idx = (lfo.target_device_filter[idx] and lfo.target_device_filter[idx][dev_filtered]) or 1
      local param_filtered = params:get(prefix .. "_target_param")
      local g = (lfo.target_param_filter[idx] and lfo.target_param_filter[idx][param_filtered]) or 1
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
          local own = g > 1 and lfo.target_owner[TARGET_PARAMS[g].id]
          if own and own ~= idx then
            for i = 2, #TARGET_PARAMS do
              if not lfo.target_owner[TARGET_PARAMS[i].id] then g = i; break end
            end
          end
          lfo.set_target(idx, g)
        else
          lfo.set_target(idx, lfo.last_global[idx] or 1)
        end
      end
      re()
    end)

    params:add_option(prefix .. "_waveform", "Waveform", lfo.WAVEFORMS, 1)
    params:set_action(prefix .. "_waveform", function(_)
      refresh_visibility()
      if not initing then
        lfo.start_clock(idx)
        lfo.refresh_dropdowns_for_device("LFO " .. idx)
        trigs.fn.refresh_dropdowns_for_lfo(idx)
      end
      re()
    end)

    params:add_control(prefix .. "_rate", "Rate", controlspec.new(0.1, 25, "exp", 0.1, 1.0, "Hz"))
    params:set_action(prefix .. "_rate", function(_)
      lfo.mod.rate[idx] = nil
      lfo.target_base[prefix .. "_rate"] = nil
    end)

    params:add_control(prefix .. "_depth", "Depth", controlspec.new(0, 100, "lin", 1, 50, "%"))
    params:set_action(prefix .. "_depth", function(_)
      lfo.mod.depth[idx] = nil
      lfo.target_base[prefix .. "_depth"] = nil
    end)

    params:add_option(prefix .. "_dir", "Direction", lfo.DIR_OPTS, 3)

    params:add_option(prefix .. "_phase", "Phase", {"0°", "90°", "180°", "270°"}, 1)
    params:set_action(prefix .. "_phase", function(_)
      lfo.mod.phase[idx] = nil
      lfo.target_base[prefix .. "_phase"] = nil
    end)

    params:add_number(prefix .. "_steps", "Steps", 1, 16, 8)
    params:set_action(prefix .. "_steps", function(v)
      lfo.mod.steps[idx] = nil
      lfo.target_base[prefix .. "_steps"] = nil
      local s = lfo.state[idx]
      if s then s.tm_register = s.tm_register & lfo.tm_register_max(v) end
    end)

    params:add_control(prefix .. "_stability", "Stability", controlspec.new(0, 100, "lin", 1, 50, "%"))
    params:set_action(prefix .. "_stability", function(_)
      lfo.mod.stability[idx] = nil
      lfo.target_base[prefix .. "_stability"] = nil
    end)

    params:add_control(prefix .. "_rate_slew", "Rate Slew", controlspec.new(0, 5, "lin", 0.1, 0, "s"))
    params:set_action(prefix .. "_rate_slew", function(_)
      lfo.mod.rate_slew[idx] = nil
      lfo.target_base[prefix .. "_rate_slew"] = nil
    end)

    params:add_separator(prefix .. "_sep_sync", "─── Synchronization ───")

    params:add_option(prefix .. "_sync_div", "Sync", sync.DIV_OPTS, 1)
    params:set_action(prefix .. "_sync_div", function(_)
      lfo.mod.sync_div[idx] = nil
      lfo.target_base[prefix .. "_sync_div"] = nil
      refresh_visibility()
      if not initing then
        lfo.refresh_dropdowns_for_device("LFO " .. idx)
        lfo.start_clock(idx)
      end
    end)

    params:add_option(prefix .. "_sync_feel", "Sync Feel", sync.FEEL_OPTS, 1)
    params:set_action(prefix .. "_sync_feel", function(_)
      lfo.mod.sync_feel[idx] = nil
      lfo.target_base[prefix .. "_sync_feel"] = nil
    end)

    params:add_separator(prefix .. "_sep_target", "─── Target ───")

    params:add_option(prefix .. "_target_device", "Target Device", {"-"}, 1)
    params:set_action(prefix .. "_target_device", function(filtered_v)
      if not initing then
        local cur_global = lfo.last_global[idx] or 1
        local cur_dev = TARGET_DEVICE_OF[cur_global] or 0
        local dmap = lfo.target_device_filter[idx]
        local cur_filtered = find_filtered_idx(dmap, cur_dev)
        if not params.pset_loading then
          if filtered_v > cur_filtered + 1 then filtered_v = cur_filtered + 1
          elseif filtered_v < cur_filtered - 1 then filtered_v = cur_filtered - 1 end
        end
        local new_dev = (dmap and dmap[filtered_v]) or 1
        if new_dev ~= cur_dev or params.pset_loading then
          lfo.rebuild_target_param_dropdown(idx, new_dev)
          local new_global = 1
          if DEVICE_PARAMS[new_dev] then
            for _, entry in ipairs(DEVICE_PARAMS[new_dev]) do
              local owner = lfo.target_owner[TARGET_PARAMS[entry.global_idx].id]
              if owner == nil or owner == idx then new_global = entry.global_idx; break end
            end
          end
          lfo.set_target(idx, new_global)
        else
          ui_revert(prefix .. "_target_device", cur_filtered)
        end
      end
      re()
    end)

    params:add_option(prefix .. "_target_param", "Target Param", {"-"}, 1)
    params:set_action(prefix .. "_target_param", function(filtered_v)
      if not initing then
        local cur_global = lfo.last_global[idx] or 1
        local pmap = lfo.target_param_filter[idx]
        local cur_filtered = find_filtered_idx(pmap, cur_global)
        if not params.pset_loading then
          if filtered_v > cur_filtered + 1 then filtered_v = cur_filtered + 1
          elseif filtered_v < cur_filtered - 1 then filtered_v = cur_filtered - 1 end
        end
        local new_global = (pmap and pmap[filtered_v]) or 1
        if new_global ~= cur_global then
          lfo.set_target(idx, new_global)
        else
          ui_revert(prefix .. "_target_param", cur_filtered)
        end
      end
      re()
    end)

    params:add_separator(prefix .. "_sep_trigger", "─── Trigger ───")

    params:add_binary(prefix .. "_randomize", "Randomize", "trigger", 0)
    params:set_action(prefix .. "_randomize", function(v)
      if v == 1 and not initing then lfo.tm_randomize(idx) end
    end)
  end

  local function register_env(idx)
    local prefix = "env" .. idx

    local function compute_intended_global()
      local dev_filtered = params:get(prefix .. "_target_device")
      local dev_idx = (env.target_device_filter[idx] and env.target_device_filter[idx][dev_filtered]) or 1
      local param_filtered = params:get(prefix .. "_target_param")
      local g = (env.target_param_filter[idx] and env.target_param_filter[idx][param_filtered]) or 1
      if g <= 1 and DEVICE_PARAMS[dev_idx] and DEVICE_PARAMS[dev_idx][1] then
        g = DEVICE_PARAMS[dev_idx][1].global_idx
      end
      return g
    end

    params:add_group("MOD SENSE " .. idx, 8)
    params:add_separator(prefix .. "_sep_control", "─── Control ───")

    params:add_option(prefix .. "_enable", "Enable", {"Off", "On"}, 1)
    params:set_action(prefix .. "_enable", function(v)
      if not initing then
        if v == 2 then
          local g = compute_intended_global()
          local own = g > 1 and lfo.target_owner[TARGET_PARAMS[g].id]
          if own and own ~= "env_" .. idx then
            for i = 2, #TARGET_PARAMS do
              if not lfo.target_owner[TARGET_PARAMS[i].id] then g = i; break end
            end
          end
          env.set_target(idx, g)
        else
          env.set_target(idx, env.last_global[idx] or 1)
        end
        env.poll_set_active(idx, v == 2)
      end
      re()
    end)

    params:add_control(prefix .. "_depth", "Depth", controlspec.new(0, 100, "lin", 1, 50, "%"))

    params:add_option(prefix .. "_dir", "Direction", env.DIR_OPTS, 1)

    params:add_control(prefix .. "_slew", "Slew", controlspec.new(1, 500, "lin", 1, 50, "ms"))
    params:set_action(prefix .. "_slew", function(v)
      local s = v / 1000
      engine[prefix .. "_attack"](s)
      engine[prefix .. "_release"](s)
    end)

    params:add_separator(prefix .. "_sep_target", "─── Target ───")

    params:add_option(prefix .. "_target_device", "Target Device", {"-"}, 1)
    params:set_action(prefix .. "_target_device", function(filtered_v)
      if not initing then
        local cur_global = env.last_global[idx] or 1
        local cur_dev = TARGET_DEVICE_OF[cur_global] or 0
        local dmap = env.target_device_filter[idx]
        local cur_filtered = 1
        if dmap then
          for fi, gi in ipairs(dmap) do if gi == cur_dev then cur_filtered = fi; break end end
        end
        if not params.pset_loading then
          if filtered_v > cur_filtered + 1 then filtered_v = cur_filtered + 1
          elseif filtered_v < cur_filtered - 1 then filtered_v = cur_filtered - 1 end
        end
        local new_dev = (dmap and dmap[filtered_v]) or 1
        if new_dev ~= cur_dev or params.pset_loading then
          env.rebuild_target_param_dropdown(idx, new_dev)
          local new_global = 1
          if DEVICE_PARAMS[new_dev] then
            for _, entry in ipairs(DEVICE_PARAMS[new_dev]) do
              local owner = lfo.target_owner[TARGET_PARAMS[entry.global_idx].id]
              if owner == nil or owner == "env_" .. idx then new_global = entry.global_idx; break end
            end
          end
          env.set_target(idx, new_global)
        else
          local p = params:lookup_param(prefix .. "_target_device")
          if p and p.selected ~= cur_filtered then
            p.selected = cur_filtered
            if _menu and _menu.rebuild_params then _menu.rebuild_params() end
          end
        end
      end
      re()
    end)

    params:add_option(prefix .. "_target_param", "Target Param", {"-"}, 1)
    params:set_action(prefix .. "_target_param", function(filtered_v)
      if not initing then
        local cur_global = env.last_global[idx] or 1
        local pmap = env.target_param_filter[idx]
        local cur_filtered = 1
        if pmap then
          for fi, gi in ipairs(pmap) do if gi == cur_global then cur_filtered = fi; break end end
        end
        if not params.pset_loading then
          if filtered_v > cur_filtered + 1 then filtered_v = cur_filtered + 1
          elseif filtered_v < cur_filtered - 1 then filtered_v = cur_filtered - 1 end
        end
        local new_global = (pmap and pmap[filtered_v]) or 1
        if new_global ~= cur_global then
          env.set_target(idx, new_global)
        else
          local p = params:lookup_param(prefix .. "_target_param")
          if p and p.selected ~= cur_filtered then
            p.selected = cur_filtered
            if _menu and _menu.rebuild_params then _menu.rebuild_params() end
          end
        end
      end
      re()
    end)
  end

  local function register_trigger(idx)
    local prefix = "trig" .. idx

    local function refresh_visibility()
      local div = params:get(prefix .. "_sync_div")
      if div > 1 then params:hide(prefix .. "_rate")
      else            params:show(prefix .. "_rate") end
      if _menu and _menu.rebuild_params then _menu.rebuild_params() end
    end

    local default_dev = 1
    local dev_shorts = {}
    if trigs.DEVICE_PARAMS[default_dev] then
      for _, e in ipairs(trigs.DEVICE_PARAMS[default_dev]) do
        dev_shorts[#dev_shorts + 1] = e.label
      end
    end
    if #dev_shorts == 0 then dev_shorts = {"-"} end

    params:add_group("MOD TRIGGER " .. idx, 10)
    params:add_separator(prefix .. "_sep_control", "─── Control ───")

    params:add_option(prefix .. "_enable", "Enable", {"Off", "On"}, 1)
    params:set_action(prefix .. "_enable", function(_)
      if not initing then trigs.fn.set_enable(idx) end
      re()
    end)

    params:add_control(prefix .. "_probability", "Probability", controlspec.new(0, 100, "lin", 1, 100, "%"))
    params:set_action(prefix .. "_probability", function(_)
      trigs.mod.probability[idx] = nil
      lfo.target_base[prefix .. "_probability"] = nil
      re()
    end)

    params:add_control(prefix .. "_rate", "Rate", controlspec.new(0.1, 25, "exp", 0.1, 1.0, "Hz"))
    params:set_action(prefix .. "_rate", function(_)
      trigs.mod.rate[idx] = nil
      lfo.target_base[prefix .. "_rate"] = nil
    end)

    params:add_separator(prefix .. "_sep_sync", "─── Synchronization ───")

    params:add_option(prefix .. "_sync_div", "Sync", sync.DIV_OPTS, 1)
    params:set_action(prefix .. "_sync_div", function(_)
      refresh_visibility()
      if not initing then trigs.fn.start_clock(idx) end
      re()
    end)

    params:add_option(prefix .. "_sync_feel", "Sync Feel", sync.FEEL_OPTS, 1)

    params:add_separator(prefix .. "_sep_target", "─── Target ───")

    params:add_option(prefix .. "_target_device", "Device", trigs.DEVICES, default_dev)
    params:set_action(prefix .. "_target_device", function(filtered_v)
      if not initing then
        local cur_global = trigs.last_global[idx] or 1
        local cur_dev = trigs.TARGET_DEVICE_OF[cur_global]
        if not cur_dev then
          local dev_filtered = params:get(prefix .. "_target_device")
          cur_dev = (trigs.target_device_filter[idx] and trigs.target_device_filter[idx][dev_filtered]) or 1
        end
        local dmap = trigs.target_device_filter[idx]
        local cur_filtered = find_filtered_idx(dmap, cur_dev)
        if not params.pset_loading then
          if filtered_v > cur_filtered + 1 then filtered_v = cur_filtered + 1
          elseif filtered_v < cur_filtered - 1 then filtered_v = cur_filtered - 1 end
        end
        local new_dev = (dmap and dmap[filtered_v]) or 1
        if new_dev ~= cur_dev or params.pset_loading then
          trigs.fn.rebuild_target_param_dropdown(idx, new_dev)
          local new_global = 1
          if trigs.DEVICE_PARAMS[new_dev] then
            for _, entry in ipairs(trigs.DEVICE_PARAMS[new_dev]) do
              local tid = trigs.TARGETS[entry.global_idx].id
              local owner = tid and trigs.target_owner[tid]
              if owner == nil or owner == idx then new_global = entry.global_idx; break end
            end
          end
          trigs.fn.set_target(idx, new_global)
        else
          ui_revert(prefix .. "_target_device", cur_filtered)
        end
      end
      re()
    end)

    params:add_option(prefix .. "_target_param", "Target", dev_shorts, 1)
    params:set_action(prefix .. "_target_param", function(filtered_v)
      if not initing then
        local cur_global = trigs.last_global[idx] or 1
        local pmap = trigs.target_param_filter[idx]
        local cur_filtered = find_filtered_idx(pmap, cur_global)
        if not params.pset_loading then
          if filtered_v > cur_filtered + 1 then filtered_v = cur_filtered + 1
          elseif filtered_v < cur_filtered - 1 then filtered_v = cur_filtered - 1 end
        end
        local new_global = (pmap and pmap[filtered_v]) or 1
        if new_global ~= cur_global then
          trigs.fn.set_target(idx, new_global)
        else
          ui_revert(prefix .. "_target_param", cur_filtered)
        end
      end
      re()
    end)
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
      sync.activate_defaults()
      if metro_active then metro_clock_start() end
      sync.push_all(initing, clock_running, lfo.sync_override)
      looper.quant_led_restart()
      redraw()
    end

    clock.transport.stop = function()
      clock_running = false
      if metro_active then metro_clock_start() end
      sync.push_all(initing, clock_running, lfo.sync_override)
      looper.quant_led_restart()
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
            sync.activate_defaults()
            if metro_active then metro_clock_start() end
            looper.quant_led_restart()
          elseif bpm == 0 and last_bpm > 0 then
            clock_running = false
            if metro_active then metro_clock_start() end
            looper.quant_led_restart()
          end
          last_bpm = bpm
          sync.push_all(initing, clock_running, lfo.sync_override)
          redraw()
        end
        if bpm > 0 and params:get("metro_bpm") ~= tostring(bpm) then
          params:set("metro_bpm", tostring(bpm))
        end
      end
    end)
  end

  local function setup_gui()
    params:add_group("GUI", 1)
    params:add_option("gui", "GUI", {"Studio", "Stage", "Off"}, 1)
    params:set_action("gui", function(v) gui_mode = v; if refresh_tuner then refresh_tuner() end; redraw() end)
  end

  -- ── Param registration ───────────────────────────────────────
  params:add_separator("princeton_header", "─── PRINCETON ───")
  setup_gui()
  setup_signal_flow()
  setup_gate()
  for i = 1, #PEDALS do setup_pedal(i) end
  setup_amp()
  setup_tremolo()
  setup_looper()
  setup_reverb()
  setup_cab()
  setup_limit()
  setup_tuner()
  setup_metro()
  for i = 1, env.NUM do register_env(i) end
  for i = 1, lfo.NUM do register_lfo(i) end
  for i = 1, trigs.N do register_trigger(i) end
  tuner.init()

  local function target_active(id)
    local owner = lfo.target_owner[id]
    if owner == nil then return false end
    if type(owner) == "number" then return lfo.is_enabled(owner) end
    local n = type(owner) == "string" and owner:match("^env_(%d+)$")
    return n ~= nil and env.is_enabled(tonumber(n))
  end

  for _, t in ipairs(TARGET_PARAMS) do
    if t.id then
      local p = params:lookup_param(t.id)
      if p and p.action then
        local orig = p.action
        params:set_action(t.id, function(v)
          lfo.target_base[t.id] = v
          if t.id == "looper_speed" or not target_active(t.id) then orig(v) end
        end)
      end
    end
  end

  params:bang()
  initing = false

  do
    local mods = {}
    for i = 1, env.NUM do mods[#mods + 1] = { idx = i, set = env.set_target } end
    for i = 1, lfo.NUM do mods[#mods + 1] = { idx = i, set = lfo.set_target } end
    for _, m in ipairs(mods) do
      m.set(m.idx, 1)
    end
  end

  env.start_polls()

  for i = 1, trigs.N do
    trigs.fn.set_target(i, trigs.last_global[i] or 1)
    trigs.fn.set_enable(i)
  end

  setup_clock_watchers()
  redraw()

  clock.run(function()
    clock.sleep(0.2)
    audio.level_monitor(0)
  end)

  clock.run(function()
    while true do
      clock.sleep(1/25)
      if _G.screenstream_active then
        redraw()
        local ok, d = pcall(screen.peek, 0, 0, 128, 64)
        if ok and type(d) == "string" and #d == 8192 then
          local f = io.open("/dev/shm/norns_screen.raw.tmp", "wb")
          if f then
            f:write(d)
            f:close()
            os.rename("/dev/shm/norns_screen.raw.tmp", "/dev/shm/norns_screen.raw")
          end
        end
      end
    end
  end)
end
