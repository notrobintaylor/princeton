local sync      = include("lib/sync")
local modtarget = include("lib/modtarget")
local scope     = include("lib/scope")

-- lfo: eight hands on eight knobs, each swaying a parameter around its base in one of six shapes
-- (Stepped Random is a Turing Machine-style shift register). They tick in Lua at a rate matched to
-- the target's step size (2-30 Hz), and modulating another LFO, Count or Trig writes overlays, never params.
local lfo = {}

local MED  = 5
local FULL = 15

lfo.NUM       = 8
lfo.SHAPES = {"Sine", "Triangle", "Saw", "Square", "Smooth Random", "Stepped Random"}
lfo.DIR_OPTS  = {"+", "-", "+/-"}

local NUM_LFOS  = lfo.NUM
local SHAPES = lfo.SHAPES
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

-- Cached LFO param ids: PID[idx].rate is "lfo"..idx.."_rate" built once, then looked up.
-- An LFO ticks up to 30 times a second, and concatenating on every tick would feed the garbage collector.
local PID = setmetatable({}, { __index = function(t, idx)
  local names = setmetatable({}, { __index = function(n, field)
    local id = "lfo" .. idx .. "_" .. field
    rawset(n, field, id)
    return id
  end })
  rawset(t, idx, names)
  return names
end })

lfo.random        = { suspend_count = {}, suspended = {} }

lfo.state                = {}
lfo.clock_gen            = {}
lfo.target_base          = {}
lfo.target_owner         = {}
lfo.orig_name            = {}
lfo.last_global          = {}
lfo.last_sent            = {}
lfo.target_device_filter = {}
lfo.target_param_filter  = {}

-- ── Scope ──────────────────────────────────────────────────────
-- The scope shows what an LFO does: every swing it sends is ring-buffered with a timestamp,
-- normalised to the widest swing, so a target that clips shows a flattened curve.
lfo.scope = {}

local function scope_reset(idx) scope.reset(lfo.scope[idx]) end
local function scope_push(idx, now, v) scope.push(lfo.scope[idx], now, v) end
function lfo.scope_reset(idx) scope_reset(idx) end

local TARGET_PARAMS, DEVICE_NAMES, DEVICE_PARAMS, TARGET_DEVICE_OF
local is_clock_running, is_initing, on_sync_override_change, get_trigs_mod
local on_target_change
local binding

function lfo.is_sync_active(idx) return params:get(PID[idx].sync_div)  > 1 end
function lfo.is_step_random(idx) return params:get(PID[idx].shape) == 6 end

lfo.STRIP = {
  {name="Shape",     suf="_shape",        typ="opt",  nmax=6, fmt=function(v,i) return SHAPES[v] end},
  {name="Rate",      suf="_rate",         typ="ctrl", step=0.1, fmt=function(v,i) return string.format("%.1fHz",v) end,
   visible_when=function(idx) return not lfo.is_sync_active(idx) end},
  {name="Depth",     suf="_depth",        typ="ctrl", step=1,   fmt=function(v,i) return string.format("%d%%",math.floor(v)) end},
  {name="Direction", suf="_dir",          typ="opt",  nmax=3, fmt=function(v,i) return DIR_OPTS[v] end},
  {name="Phase",     suf="_phase",        typ="opt",  nmax=4, fmt=function(v,i) return ({"0°","90°","180°","270°"})[v] end,
   visible_when=function(idx) return not lfo.is_step_random(idx) end},
  {name="Division",suf="_sync_div",     typ="opt",  nmax=#sync.DIV_OPTS, fmt=function(v,i) return sync.DIV_OPTS[v] end},
  {name="Feel", suf="_sync_feel",    typ="opt",  nmax=3, fmt=function(v,i) return sync.FEEL_OPTS[v] end,
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
  return lfo.mod[field][idx] or params:get(PID[idx][field])
end

local LFO_TICK_MIN = 1/30
local LFO_TICK_MAX = 0.5

local function lfo_adaptive_dt(idx, rate)
  local t = TARGET_PARAMS[lfo.last_global[idx] or 1]
  if not t or not t.st or not t.mn or not t.mx then return LFO_TICK_MIN end
  local depth = lfo.mod.depth[idx] ~= nil and lfo.mod.depth[idx] or params:get(PID[idx].depth)
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

local function compute_v_unsigned(idx, phase)
  local s = lfo.state[idx]
  local wf = params:get(PID[idx].shape)
  local p = ((phase or s.phase) + lfo_phase_offset(idx)) % 1
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

-- A modulated target wears an (M) before its name in the params menu.
-- The original name is remembered so it returns on release.
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

-- Targets that do nothing in their device's current setting stay off the list.
-- A sync division shows only while sync is on, a free rate only while it is off.
local function target_visible(target_id)
  if target_id == "tremolo_sync_div" or target_id == "tremolo_sync_feel" then return params:get("tremolo_sync_div") > 1 end
  if target_id == "warp_sync_div"    or target_id == "warp_sync_feel"    then return params:get("warp_sync_div")    > 1 end
  if target_id == "repeat_sync_div"  or target_id == "repeat_sync_feel"  then return params:get("repeat_sync_div")  > 1 end
  if target_id == "looper_quant_div" or target_id == "looper_quant_feel" then return params:get("looper_quant_div") > 1 end
  local n, suf = target_id:match("^lfo(%d+)_(.+)$")
  if n then
    local target_lfo    = tonumber(n)
    local target_shape     = params:get("lfo"..target_lfo.."_shape")
    local target_synced = params:get("lfo"..target_lfo.."_sync_div") > 1
    if suf == "rate"      then return not target_synced end
    if suf == "phase" or suf == "rate_slew"  then return target_shape ~= 6 end
    if suf == "steps" or suf == "stability"  then return target_shape == 6 end
    if suf == "sync_div" or suf == "sync_feel" then return target_synced end
  end
  local ns, sufs = target_id:match("^seq(%d+)_(.+)$")
  if ns then
    local target_synced = params:get("seq"..tonumber(ns).."_sync_div") > 1
    if sufs == "rate"     then return not target_synced end
    if sufs == "sync_div" or sufs == "sync_feel" then return target_synced end
  end
  local nt, suft = target_id:match("^trig(%d+)_(.+)$")
  if nt and (suft == "sync_div" or suft == "sync_feel") then
    return params:get("trig"..tonumber(nt).."_sync_div") > 1
  end
  return true
end

function lfo.rebuild_target_param_dropdown(idx, dev_idx)
  modtarget.rebuild_param(binding, idx, dev_idx)
end

function lfo.rebuild_target_dropdown(idx)
  modtarget.rebuild(binding, idx)
end

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

-- The scope draws the swing around the base, -1 to 1 of the widest swing Depth and Direction allow,
-- so a clamped target shows as a flattened curve. It skips the target's step rounding: the picture
-- shows the shape, not the staircase a coarse parameter makes of it.
local function scope_swing(idx, t, base, v_un)
  local d = (lfo.mod.depth[idx] ~= nil and lfo.mod.depth[idx] or params:get(PID[idx].depth)) / 100
  local dir = params:get(PID[idx].dir)
  local range = t.mx - t.mn
  local off
  if dir == 1 then     off = v_un * d * range
  elseif dir == 2 then off = -v_un * d * range
  else                 off = (v_un * 2 - 1) * d * range / 2
  end
  local swing = (dir == 3 and 0.5 or 1) * d * range
  if swing <= 0 then return 0 end
  return util.clamp((util.clamp(base + off, t.mn, t.mx) - base) / swing, -1, 1)
end

-- Between two ticks the scope gets in-between points from the phase, as many as the window needs to
-- look round; a slow tick on a coarse target would otherwise draw a triangle as a few corners.
local scope_window
local function scope_fill(idx, prev_phase, prev_v, dt, rate)
  local target_idx = lfo.last_global[idx] or 1
  local t = TARGET_PARAMS[target_idx]
  if target_idx == 1 or not t or not t.id or t.mx <= t.mn or lfo.target_owner[t.id] ~= idx then return end
  local k = util.clamp(math.ceil(dt * 160 / scope_window(idx)), 1, 16)
  if k < 2 then return end
  local base, now = effective_base(t.id), util.time()
  local wf = params:get(PID[idx].shape)
  for j = 1, k - 1 do
    local f = j / k
    local v_un = wf == 5 and prev_v + (lfo.state[idx].smooth_rand_v - prev_v) * f
                 or compute_v_unsigned(idx, prev_phase + dt * rate * f)
    scope_push(idx, now - dt * (1 - f), scope_swing(idx, t, base, v_un))
  end
end

local function apply_to_target(idx)
  if is_initing() then return end
  if params:get(PID[idx].enable) ~= 2 then return end
  local target_idx = lfo.last_global[idx] or 1
  if target_idx == 1 then return end
  local t = TARGET_PARAMS[target_idx]
  if not t or not t.id or not t.send then return end
  if lfo.target_owner[t.id] ~= idx then return end

  local base = effective_base(t.id)

  local v_un = compute_v_unsigned(idx)
  local depth = lfo.mod.depth[idx] ~= nil and lfo.mod.depth[idx] or params:get(PID[idx].depth)
  local dir = params:get(PID[idx].dir)
  local d = depth / 100
  local range = t.mx - t.mn

  local off
  if dir == 1 then     off = v_un * d * range
  elseif dir == 2 then off = -v_un * d * range
  else                 off = (v_un * 2 - 1) * d * range / 2
  end

  local val = util.clamp(base + off, t.mn, t.mx)
  val = math.floor(val / t.st + 0.5) * t.st
  local now = util.time()
  if range > 0 then scope_push(idx, now, scope_swing(idx, t, base, v_un)) end
  -- A slow LFO often lands on the same step for many ticks, so repeats are skipped.
  -- After half a second it resends anyway, in case something else has moved the target meanwhile.
  local last = lfo.last_sent[idx]
  if last and last.id == t.id and last.val == val and now - last.at < 0.5 then return end
  lfo.last_sent[idx] = { id = t.id, val = val, at = now }
  t.send(val)
end

-- Drops a target's overlay once no source drives it, so its own param applies again.
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
  lfo.clock_gen[idx] = (lfo.clock_gen[idx] or 0) + 1
  local my = lfo.clock_gen[idx]
  scope_reset(idx)
  if is_initing() then return end
  if params:get(PID[idx].enable) ~= 2 then
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

  clock.run(function()
    while true do
      if lfo.clock_gen[idx] ~= my then return end
      local cur_target = lfo.last_global[idx] or 1
      if cur_target == 1 then break end
      local wf = params:get(PID[idx].shape)

      if wf == 6 then
        if lfo.random.suspended[idx] then
          clock.sleep(0.1)
        else
          local sync_div_opt = lfo_g("sync_div", idx)
          if sync_div_opt > 1 and is_clock_running() then
            local beats = sync.DIV_BEATS[sync_div_opt] * sync.FEEL_MULT[lfo_g("sync_feel", idx)]
            clock.sync(beats)
          else
            local target_rate = lfo.mod.rate[idx] ~= nil and lfo.mod.rate[idx] or params:get(PID[idx].rate)
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
          if lfo.clock_gen[idx] ~= my then return end
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
          target_rate = lfo.mod.rate[idx] ~= nil and lfo.mod.rate[idx] or params:get(PID[idx].rate)
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
        if lfo.clock_gen[idx] ~= my then return end
        if slew then
          local coeff = math.min(1, dt / slew)
          rate = rate + (target_rate - rate) * coeff
          lfo.mod.rate_slewed[idx] = rate
        end
        local s = lfo.state[idx]
        local prev_phase, prev_v = s.phase, s.smooth_rand_v
        s.phase = (s.phase + dt * rate) % 1
        if wf == 5 then
          if s.phase < prev_phase then
            s.smooth_rand_target = math.random()
          end
          local alpha = math.min(1, dt * rate * 4)
          s.smooth_rand_v = s.smooth_rand_v + (s.smooth_rand_target - s.smooth_rand_v) * alpha
        end
        if params:get(PID[idx].enable) == 2 then scope_fill(idx, prev_phase, prev_v, dt, rate) end
        apply_to_target(idx)
      end
    end
  end)
end

-- K2 in the rack: restart the cycle (phase 0, plus the LFO's Phase offset).
function lfo.reset(idx)
  lfo.state[idx].phase = 0
  apply_to_target(idx)
end

function lfo.is_enabled(idx)
  return params:get(PID[idx].enable) == 2
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
  local m = tm_register_max(params:get(PID[idx].steps))
  if m == 0 then return end
  s.tm_register = math.random(0, m)
  apply_to_target(idx)
end

function lfo.tm_register_max(steps) return tm_register_max(steps) end

-- Scope window: two periods so the shape reads as a shape, sixteen steps for the register.
-- It follows the rate actually running (slewed, modulated or clocked), so rate modulation shows as squeeze and stretch.

function scope_window(idx)
  local rate
  local sync_div_opt = lfo_g("sync_div", idx)
  if sync_div_opt > 1 and is_clock_running() then
    rate = clock.get_tempo() / (60 * sync.DIV_BEATS[sync_div_opt] * sync.FEEL_MULT[lfo_g("sync_feel", idx)])
  else
    rate = lfo.mod.rate_slewed[idx] or lfo.mod.rate[idx] or params:get(PID[idx].rate)
  end
  local cycles = params:get(PID[idx].shape) == 6 and 16 or 2
  return util.clamp(cycles / math.max(0.05, rate), 0.2, 12)
end

function lfo.scope_live(idx)
  local sc = lfo.scope[idx]
  return sc and sc.n > 0 and params:get(PID[idx].enable) == 2 and (lfo.last_global[idx] or 1) > 1
end

-- Drawing lives in lib/scope; w and h set the window (also used small, in the rack list).
-- lv is the curve's brightness.
function lfo.draw_scope(ox, top, idx, w, h_px, lv)
  scope.draw(lfo.scope[idx], ox, top, w, h_px, scope_window(idx), lv, params:get(PID[idx].shape) == 6)
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
    lfo.scope[i] = scope.new()
    lfo.last_global[i] = 1
    lfo.target_device_filter[i] = {}
    for di = 1, #DEVICE_NAMES do lfo.target_device_filter[i][di] = di end
    lfo.target_param_filter[i] = {}
    if DEVICE_PARAMS[1] then
      for j, e in ipairs(DEVICE_PARAMS[1]) do lfo.target_param_filter[i][j] = e.global_idx end
    end
  end

  binding = {
    set              = function(i, g) lfo.set_target(i, g) end,
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

function lfo.binding() return binding end

return lfo
