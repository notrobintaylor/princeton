local sync      = include("lib/sync")
local sprites   = include("lib/sprites")
local modtarget = include("lib/modtarget")

local lfo = {}

local MED  = 5
local FULL = 15

lfo.NUM       = 8
lfo.WAVEFORMS = {"Sine", "Triangle", "Saw", "Square", "Smooth Random", "Stepped Random"}
lfo.DIR_OPTS  = {"+", "-", "+/-"}

local NUM_LFOS  = lfo.NUM
local WAVEFORMS = lfo.WAVEFORMS
local DIR_OPTS  = lfo.DIR_OPTS

lfo.mod = {
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
lfo.count         = { level = nil, length = nil, root = nil, register = nil, div = nil }
lfo.sync_override = {}
lfo.random        = { suspend_count = {}, suspended = {} }

lfo.state                = {}
lfo.clocks               = {}
lfo.target_base          = {}
lfo.target_owner         = {}
lfo.orig_name            = {}
lfo.last_global          = {}
lfo.target_device_filter = {}
lfo.target_param_filter  = {}

local TARGET_PARAMS, DEVICE_NAMES, DEVICE_PARAMS, TARGET_DEVICE_OF
local is_clock_running, is_initing, on_sync_override_change, get_trigs_mod
local on_target_change
local binding

function lfo.is_sync_active(idx) return params:get("lfo"..idx.."_sync_div")  > 1 end
function lfo.is_step_random(idx) return params:get("lfo"..idx.."_waveform") == 6 end

lfo.STRIP = {
  {name="Waveform",  suf="_waveform",     typ="opt",  nmax=6, fmt=function(v,i) return WAVEFORMS[v] end},
  {name="Rate",      suf="_rate",         typ="ctrl", step=0.1, fmt=function(v,i) return string.format("%.1fHz",v) end,
   visible_when=function(idx) return not lfo.is_sync_active(idx) end},
  {name="Depth",     suf="_depth",        typ="ctrl", step=1,   fmt=function(v,i) return string.format("%d%%",math.floor(v)) end},
  {name="Direction", suf="_dir",          typ="opt",  nmax=3, fmt=function(v,i) return DIR_OPTS[v] end},
  {name="Phase",     suf="_phase",        typ="opt",  nmax=4, fmt=function(v,i) return ({"0°","90°","180°","270°"})[v] end,
   visible_when=function(idx) return not lfo.is_step_random(idx) end},
  {name="Sync",      suf="_sync_div",     typ="opt",  nmax=8, fmt=function(v,i) return sync.DIV_OPTS[v] end},
  {name="Sync Feel", suf="_sync_feel",    typ="opt",  nmax=3, fmt=function(v,i) return sync.FEEL_OPTS[v] end,
   visible_when=function(idx) return lfo.is_sync_active(idx) end},
  {name="Rate Slew", suf="_rate_slew",    typ="ctrl", step=0.1, fmt=function(v,i) return string.format("%.1fs",v) end,
   visible_when=function(idx) return not lfo.is_step_random(idx) end},
  {name="Steps",     suf="_steps",        typ="ctrl", step=1,   fmt=function(v,i) return tostring(math.floor(v)) end,
   visible_when=function(idx) return lfo.is_step_random(idx) end},
  {name="Stability", suf="_stability",    typ="ctrl", step=1,   fmt=function(v,i) return string.format("%d%%",math.floor(v)) end,
   visible_when=function(idx) return lfo.is_step_random(idx) end},
  {name="Device",    suf="_target_device", typ="opt",  nmax_fn=function(i) return #(lfo.target_device_filter[i] or {}) end,
   fmt=function(v,i)
     local dmap = lfo.target_device_filter[i]
     local di   = dmap and dmap[v]
     if di == 0 then return "-" end
     return (di and DEVICE_NAMES[di]) or "?"
   end},
  {name="Parameter", suf="_target_param",  typ="opt",  nmax_fn=function(i) return #(lfo.target_param_filter[i] or {}) end,
   fmt=function(v,i)
     local pmap = lfo.target_param_filter[i]
     local gi   = pmap and pmap[v]
     if gi and gi > 1 and TARGET_PARAMS[gi] then return TARGET_PARAMS[gi].label:match(": (.+)$") or TARGET_PARAMS[gi].label end
     return "-"
   end},
}

function lfo.strip_visible(idx, strip_i)
  local entry = lfo.STRIP[strip_i]
  return entry and (not entry.visible_when or entry.visible_when(idx))
end

function lfo.strip_resolve(idx, current)
  if lfo.strip_visible(idx, current) then return current end
  for i = current + 1, #lfo.STRIP do
    if lfo.strip_visible(idx, i) then return i end
  end
  for i = current - 1, 1, -1 do
    if lfo.strip_visible(idx, i) then return i end
  end
  return current
end

function lfo.strip_advance(idx, current, d)
  if d == 0 then return current end
  local step = d > 0 and 1 or -1
  local next_idx = current + step
  while next_idx >= 1 and next_idx <= #lfo.STRIP do
    if lfo.strip_visible(idx, next_idx) then return next_idx end
    next_idx = next_idx + step
  end
  return current
end

local function tm_register_max(steps)
  if steps <= 0 then return 0 end
  return (1 << steps) - 1
end

local function lfo_g(field, idx)
  return lfo.mod[field][idx] or params:get("lfo"..idx.."_"..field)
end

local LFO_TICK_MIN = 1/30
local LFO_TICK_MAX = 0.5

local function lfo_adaptive_dt(idx, rate)
  local t = TARGET_PARAMS[lfo.last_global[idx] or 1]
  if not t or not t.st or not t.mn or not t.mx then return LFO_TICK_MIN end
  local depth = lfo.mod.depth[idx] ~= nil and lfo.mod.depth[idx] or params:get("lfo"..idx.."_depth")
  local span  = (t.mx - t.mn) * (depth / 100)
  if span <= 0 then return LFO_TICK_MAX end
  local dt = t.st / (math.max(0.05, rate) * span)
  if dt < LFO_TICK_MIN then return LFO_TICK_MIN end
  if dt > LFO_TICK_MAX then return LFO_TICK_MAX end
  return dt
end

local function lfo_phase_offset(idx)
  local opt = lfo_g("phase", idx)
  if opt == 2 then return 0.25
  elseif opt == 3 then return 0.5
  elseif opt == 4 then return 0.75
  end
  return 0
end

local function compute_v_unsigned(idx)
  local s = lfo.state[idx]
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
  if not lfo.orig_name[target_id] then lfo.orig_name[target_id] = p.name end
  if not string.find(p.name, "%(M%)") then
    p.name = "(M) " .. lfo.orig_name[target_id]
  end
  if _menu and _menu.rebuild_params then _menu.rebuild_params() end
end

local function unmark_modulated(target_id)
  if not target_id then return end
  local idx = params.lookup[target_id]
  if not idx or not lfo.orig_name[target_id] then return end
  params.params[idx].name = lfo.orig_name[target_id]
  if _menu and _menu.rebuild_params then _menu.rebuild_params() end
end

lfo.mark_modulated   = mark_modulated
lfo.unmark_modulated = unmark_modulated

local function target_visible(target_id)
  if target_id == "tremolo_sync_div" or target_id == "tremolo_sync_feel" then return params:get("tremolo_sync_div") > 1 end
  if target_id == "warp_sync_div"    or target_id == "warp_sync_feel"    then return params:get("warp_sync_div")    > 1 end
  if target_id == "repeat_sync_div"  or target_id == "repeat_sync_feel"  then return params:get("repeat_sync_div")  > 1 end
  if target_id == "looper_quant_div" or target_id == "looper_quant_feel" then return params:get("looper_quant_div") > 1 end
  local n, suf = target_id:match("^lfo(%d+)_(.+)$")
  if n then
    local target_lfo    = tonumber(n)
    local target_wf     = params:get("lfo"..target_lfo.."_waveform")
    local target_synced = params:get("lfo"..target_lfo.."_sync_div") > 1
    if suf == "rate"      then return not target_synced end
    if suf == "phase" or suf == "rate_slew"  then return target_wf ~= 6 end
    if suf == "steps" or suf == "stability"  then return target_wf == 6 end
    if suf == "sync_div" or suf == "sync_feel" then return target_synced end
  end
  local ns, sufs = target_id:match("^seq(%d+)_(.+)$")
  if ns then
    local target_synced = params:get("seq"..tonumber(ns).."_sync_div") > 1
    if sufs == "rate"     then return not target_synced end
    if sufs == "sync_div" or sufs == "sync_feel" then return target_synced end
  end
  return true
end

function lfo.rebuild_target_param_dropdown(idx, dev_idx)
  modtarget.rebuild_param(binding, idx, dev_idx)
end

function lfo.rebuild_target_dropdown(idx)
  modtarget.rebuild(binding, idx)
end

-- When a synced param (repeat_time, tremolo_speed, warp_rate) is a mod target,
-- the audible value is the sync-derived one, not the raw param. Center the
-- modulation on that so the LFO wiggles around the synced time, not the low
-- manual base. Mirrors sync.push_all's override-aware div/feel resolution.
local function synced_base(id)
  local m = sync.PARAM_MAP[id]
  if not (m and is_clock_running()) then return nil end
  local div = lfo.sync_override[m.div] or params:get(m.div)
  if div <= 1 then return nil end
  local feel = lfo.sync_override[m.feel] or params:get(m.feel)
  local hz = sync.hz_df(clock.get_tempo(), div, feel)
  return hz and m.value_fn(hz) or nil
end

local function effective_base(id)
  return synced_base(id) or lfo.target_base[id] or params:get(id)
end

local function apply_to_target(idx)
  if is_initing() then return end
  if params:get("lfo"..idx.."_enable") ~= 2 then return end
  local target_idx = lfo.last_global[idx] or 1
  if target_idx == 1 then return end
  local t = TARGET_PARAMS[target_idx]
  if not t or not t.id or not t.send then return end
  if lfo.target_owner[t.id] ~= idx then return end

  local base = effective_base(t.id)

  local v_un = compute_v_unsigned(idx)
  local depth = lfo.mod.depth[idx] ~= nil and lfo.mod.depth[idx] or params:get("lfo"..idx.."_depth")
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

function lfo.clear_override(target_id)
  local n = target_id:match("^lfo(%d+)_rate$")
  if n then
    local i = tonumber(n)
    lfo.mod.rate[i] = nil
    lfo.mod.rate_slewed[i] = nil
    return
  end
  n = target_id:match("^lfo(%d+)_depth$")
  if n then lfo.mod.depth[tonumber(n)] = nil; return end
  local nn, field = target_id:match("^lfo(%d+)_(.+)$")
  if nn and lfo.mod[field] then
    lfo.mod[field][tonumber(nn)] = nil
    return
  end
  if target_id == "count_level"    then lfo.count.level    = nil; return end
  if target_id == "count_length"   then lfo.count.length   = nil; return end
  if target_id == "count_root"     then lfo.count.root     = nil; return end
  if target_id == "count_register" then lfo.count.register = nil; return end
  if target_id == "count_div"      then lfo.count.div      = nil; return end
  if target_id == "count_scale"      then lfo.count.scale  = nil; return end
  if target_id == "count_chords"     then lfo.count.chords = nil; return end
  if target_id == "count_scale_play" then lfo.count.play   = nil; return end
  if target_id == "count_degree"     then lfo.count.degree = nil; return end
  if lfo.sync_override[target_id] ~= nil then
    lfo.sync_override[target_id] = nil
    on_sync_override_change(target_id)
  end
  local n_trig, field_trig = target_id:match("^trig(%d+)_(.+)$")
  local trigs_mod = get_trigs_mod()
  if n_trig and trigs_mod[field_trig] then
    trigs_mod[field_trig][tonumber(n_trig)] = nil
    return
  end
end

function lfo.start_clock(idx)
  if lfo.clocks[idx] then clock.cancel(lfo.clocks[idx]); lfo.clocks[idx] = nil end
  if is_initing() then return end
  if params:get("lfo"..idx.."_enable") ~= 2 then
    local ti = lfo.last_global[idx] or 1
    if ti > 1 and TARGET_PARAMS[ti] and TARGET_PARAMS[ti].id then
      lfo.clear_override(TARGET_PARAMS[ti].id)
    end
    return
  end
  local target_idx = lfo.last_global[idx] or 1
  if target_idx == 1 then return end
  local t = TARGET_PARAMS[target_idx]
  if not t or not t.id or lfo.target_owner[t.id] ~= idx then return end

  lfo.clocks[idx] = clock.run(function()
    while true do
      local cur_target = lfo.last_global[idx] or 1
      if cur_target == 1 then break end
      local wf = params:get("lfo"..idx.."_waveform")

      if wf == 6 then
        if lfo.random.suspended[idx] then
          clock.sleep(0.1)
        else
          local sync_div_opt = lfo_g("sync_div", idx)
          if sync_div_opt > 1 and is_clock_running() then
            local beats = sync.DIV_BEATS[sync_div_opt] * sync.FEEL_MULT[lfo_g("sync_feel", idx)]
            clock.sync(beats)
          else
            local target_rate = lfo.mod.rate[idx] ~= nil and lfo.mod.rate[idx] or params:get("lfo"..idx.."_rate")
            local slew = lfo_g("rate_slew", idx)
            local rate
            if slew > 0 and lfo.mod.rate[idx] ~= nil then
              if lfo.mod.rate_slewed[idx] == nil then lfo.mod.rate_slewed[idx] = target_rate end
              local dt_step = 1 / math.max(0.05, lfo.mod.rate_slewed[idx])
              local coeff = math.min(1, dt_step / slew)
              lfo.mod.rate_slewed[idx] = lfo.mod.rate_slewed[idx] + (target_rate - lfo.mod.rate_slewed[idx]) * coeff
              rate = lfo.mod.rate_slewed[idx]
            else
              lfo.mod.rate_slewed[idx] = nil
              rate = target_rate
            end
            clock.sleep(1 / math.max(0.05, rate))
          end
          local s = lfo.state[idx]
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
          apply_to_target(idx)
        end
      else
        local sync_div_opt = lfo_g("sync_div", idx)
        local rate, target_rate, slew
        if sync_div_opt > 1 and is_clock_running() then
          local beats = sync.DIV_BEATS[sync_div_opt] * sync.FEEL_MULT[lfo_g("sync_feel", idx)]
          rate = clock.get_tempo() / (60 * beats)
          lfo.mod.rate_slewed[idx] = nil
        else
          target_rate = lfo.mod.rate[idx] ~= nil and lfo.mod.rate[idx] or params:get("lfo"..idx.."_rate")
          slew = lfo_g("rate_slew", idx)
          if slew > 0 and lfo.mod.rate[idx] ~= nil then
            if lfo.mod.rate_slewed[idx] == nil then lfo.mod.rate_slewed[idx] = target_rate end
            rate = lfo.mod.rate_slewed[idx]
          else
            lfo.mod.rate_slewed[idx] = nil
            rate = target_rate
            slew = nil
          end
        end
        local dt = lfo_adaptive_dt(idx, rate)
        clock.sleep(dt)
        if slew then
          local coeff = math.min(1, dt / slew)
          rate = rate + (target_rate - rate) * coeff
          lfo.mod.rate_slewed[idx] = rate
        end
        local s = lfo.state[idx]
        local prev_phase = s.phase
        s.phase = (s.phase + dt * rate) % 1
        if wf == 5 then
          if s.phase < prev_phase then
            s.smooth_rand_target = math.random()
          end
          local alpha = math.min(1, dt * rate * 4)
          s.smooth_rand_v = s.smooth_rand_v + (s.smooth_rand_target - s.smooth_rand_v) * alpha
        end
        apply_to_target(idx)
      end
    end
    lfo.clocks[idx] = nil
  end)
end

function lfo.is_enabled(idx)
  return params:get("lfo"..idx.."_enable") == 2
end

function lfo.set_target(idx, new_global_idx)
  modtarget.set_target(binding, idx, new_global_idx)
  lfo.start_clock(idx)
end

function lfo.refresh_dropdowns_for_device(dev_name)
  for other = 1, NUM_LFOS do
    local other_target_global = lfo.last_global[other] or 1
    if other_target_global > 1 then
      local cur_dev = TARGET_DEVICE_OF[other_target_global]
      if cur_dev and DEVICE_NAMES[cur_dev] == dev_name then
        lfo.rebuild_target_param_dropdown(other, cur_dev)
        local new_filter = lfo.target_param_filter[other]
        local still_present = false
        if new_filter then
          for _, gi in ipairs(new_filter) do
            if gi == other_target_global then still_present = true; break end
          end
        end
        if not still_present then
          local fallback = (new_filter and new_filter[1]) or 1
          lfo.set_target(other, fallback)
        end
      end
    end
  end
end

function lfo.tm_randomize(idx)
  local s = lfo.state[idx]
  local m = tm_register_max(params:get("lfo"..idx.."_steps"))
  if m == 0 then return end
  s.tm_register = math.random(0, m)
  apply_to_target(idx)
end

function lfo.tm_register_max(steps) return tm_register_max(steps) end

function lfo.draw_half(ox, oy, idx, focused)
  local cx      = ox + 16
  local mid     = oy + 28
  local enabled = params:get("lfo" .. idx .. "_enable") == 2
  local wf      = params:get("lfo" .. idx .. "_waveform")
  local icon_lv = enabled and FULL or MED
  sprites.draw_waveform_icon(cx, mid, wf, icon_lv)
  screen.font_size(8); screen.font_face(0)
  screen.level(icon_lv)
  screen.move(cx, oy + 56); screen.text_center("LFO " .. idx)
end

function lfo.init(deps)
  TARGET_PARAMS    = deps.TARGET_PARAMS
  DEVICE_NAMES     = deps.DEVICE_NAMES
  DEVICE_PARAMS    = deps.DEVICE_PARAMS
  TARGET_DEVICE_OF = deps.TARGET_DEVICE_OF
  is_clock_running             = deps.is_clock_running
  is_initing                  = deps.is_initing
  on_sync_override_change      = deps.on_sync_override_change
  get_trigs_mod                = deps.get_trigs_mod
  on_target_change             = deps.on_target_change

  for i = 1, NUM_LFOS do
    lfo.random.suspend_count[i] = 0
    lfo.random.suspended[i] = false
    lfo.state[i] = { phase = 0, smooth_rand_v = 0.5, smooth_rand_target = 0.5, tm_register = 0 }
    lfo.last_global[i] = 1
    lfo.target_device_filter[i] = {}
    for di = 1, #DEVICE_NAMES do lfo.target_device_filter[i][di] = di end
    lfo.target_param_filter[i] = {}
    if DEVICE_PARAMS[1] then
      for j, e in ipairs(DEVICE_PARAMS[1]) do lfo.target_param_filter[i][j] = e.global_idx end
    end
  end

  binding = {
    num              = NUM_LFOS,
    none_option      = true,
    prefix           = function(i) return "lfo" .. i end,
    owner            = lfo.target_owner,
    tag              = function(i) return i end,
    devices          = DEVICE_NAMES,
    device_params    = DEVICE_PARAMS,
    target_device_of = TARGET_DEVICE_OF,
    targets          = TARGET_PARAMS,
    label_of         = function(e) return e.short end,
    device_filter    = lfo.target_device_filter,
    param_filter     = lfo.target_param_filter,
    last_global      = lfo.last_global,
    visible          = function(g) local t = TARGET_PARAMS[g]; return t ~= nil and target_visible(t.id) end,
    device_excluded  = function(idx, di) return DEVICE_NAMES[di] == "LFO " .. idx end,
    enabled          = lfo.is_enabled,
    on_claim         = function(g)
      local id = TARGET_PARAMS[g].id
      lfo.target_base[id] = params:get(id)
      mark_modulated(id)
    end,
    on_release       = function(g)
      local t = TARGET_PARAMS[g]
      unmark_modulated(t.id)
      if t.send then t.send(effective_base(t.id)) end
      lfo.clear_override(t.id)
    end,
    on_rebuilt       = function()
      if on_target_change then on_target_change() end
      if _menu and _menu.rebuild_params then _menu.rebuild_params() end
    end,
  }
end

return lfo
