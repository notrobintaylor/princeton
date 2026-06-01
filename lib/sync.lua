-- princeton sync
--
-- Clock-sync data tables and helpers shared across LFO, trigger, repeat,
-- tremolo, warp and looper quantization paths.

local sync = {}

local MED  = 5
local FULL = 15

sync.DIV_OPTS  = {"Off","1/1","1/2","1/4","1/8","1/16","1/32","1/64"}
sync.DIV_BEATS = {0, 4, 2, 1, 0.5, 0.25, 0.125, 0.0625}
sync.FEEL_OPTS = {"Note","Dotted","Triplet"}
sync.FEEL_MULT = {1.0, 1.5, 2.0/3.0}
sync.METRO_DIV_OPTS  = {"1/1","1/2","1/4","1/8","1/16"}
sync.METRO_DIV_BEATS = {4, 2, 1, 0.5, 0.25}

sync.PARAM_MAP = {
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

function sync.hz_df(bpm, div_opt, feel_opt)
  if div_opt <= 1 then return nil end
  local beats = sync.DIV_BEATS[div_opt] * sync.FEEL_MULT[feel_opt]
  return bpm / (beats * 60.0)
end

local function in_range(id, hz)
  local m = sync.PARAM_MAP[id]
  return not m or m.in_range(hz)
end

function sync.val_level(id, clock_running)
  local m = sync.PARAM_MAP[id]
  if not m or not clock_running then return FULL end
  local div_opt = params:get(m.div)
  if div_opt <= 1 then return FULL end
  local hz = sync.hz_df(clock.get_tempo(), div_opt, params:get(m.feel))
  return (hz and in_range(id, hz)) and FULL or MED
end

function sync.fmt(p_id, clock_running)
  if not clock_running then return nil end
  local m = sync.PARAM_MAP[p_id]
  if not m then return nil end
  local div_opt = params:get(m.div)
  if div_opt <= 1 then return nil end
  local s = sync.DIV_OPTS[div_opt]
  local f = params:get(m.feel)
  if f == 2 then return s .. "." end
  if f == 3 then return s .. "T" end
  return s
end

function sync.push_all(initing, clock_running, override)
  if initing then return end
  local bpm = clock.get_tempo()
  for id, m in pairs(sync.PARAM_MAP) do
    local div = (override and override[m.div]) or params:get(m.div)
    if clock_running and div > 1 then
      engine[id](m.value_fn(sync.hz_df(bpm, div, (override and override[m.feel]) or params:get(m.feel))))
    else
      engine[id](params:get(id))
    end
  end
end

function sync.activate_defaults()
  if params:get("tremolo_sync_div") <= 1 then params:set("tremolo_sync_div", 4) end
  if params:get("warp_sync_div")    <= 1 then params:set("warp_sync_div",    4) end
  if params:get("repeat_sync_div")  <= 1 then params:set("repeat_sync_div",  4) end
  if params:get("looper_quant_div") <= 1 then params:set("looper_quant_div", 4) end
end

return sync
