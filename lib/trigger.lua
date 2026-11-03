local sync      = include("lib/sync")
local modtarget = include("lib/modtarget")
local scope     = include("lib/scope")

-- trigger: four Trigs, fingers over the switches; on each beat of their rate (or the clock) Chance
-- decides whether to fire an action from TRIG_TARGETS (princeton.lua). A Stepped Random LFO with a Trig
-- on it stops running freely and steps only when fired (refresh_suspend counts the Trigs holding it).
local trigs = {}

local MED  = 5
local FULL = 15

trigs.N           = 4
trigs.mod         = { rate = {}, chance = {}, sync_div = {}, sync_feel = {} }
trigs.clock_gen   = {}
trigs.last_global = {}
trigs.applied_lfo = {}
trigs.strip_fn    = {}
trigs.fn          = {}
trigs.strip_sel   = {1, 1, 1, 1}
trigs.last_fire   = {}
trigs.last_skip   = {}
trigs.scope       = {}

trigs.target_owner         = {}
trigs.target_device_filter = {}
trigs.target_param_filter  = {}

for i = 1, trigs.N do trigs.last_global[i] = 1; trigs.scope[i] = scope.new() end

local looper, lfo
local is_initing, is_clock_running
local binding

function trigs.strip_fn.sync_active(idx) return params:get("trig"..idx.."_sync_div") > 1 end

trigs.STRIP = {
  {name="Chance",      suf="_chance",        typ="ctrl", step=1,   fmt=function(v,i) return string.format("%d%%",math.floor(v)) end},
  {name="Rate",        suf="_rate",          typ="ctrl", step=0.1, fmt=function(v,i) return string.format("%.1fHz",v) end,
   visible_when=function(idx) return not trigs.strip_fn.sync_active(idx) end},
  {name="Sync",        suf="_sync_div",      typ="opt",  nmax=#sync.DIV_OPTS, fmt=function(v,i) return sync.DIV_OPTS[v] end},
  {name="Sync Feel",   suf="_sync_feel",     typ="opt",  nmax=3,   fmt=function(v,i) return sync.FEEL_OPTS[v] end},
  {name="Device",      suf="_target_device", typ="opt",  nmax_fn=function(i) return #(trigs.target_device_filter[i] or {}) end,
   fmt=function(v,i)
     local dmap = trigs.target_device_filter[i]
     return (dmap and trigs.DEVICES[dmap[v]]) or "?"
   end},
  {name="Target",      suf="_target_param",  typ="opt",  nmax_fn=function(i) return #(trigs.target_param_filter[i] or {}) end,
   fmt=function(v,i)
     local pmap = trigs.target_param_filter[i]
     local gi   = pmap and pmap[v]
     if not gi or gi == 1 then return "-" end
     local t = trigs.TARGETS[gi]
     return t and (t.label:match(": (.+)$") or t.label) or "-"
   end},
}

function trigs.strip_fn.visible(idx, strip_i)
  local entry = trigs.STRIP[strip_i]
  return entry and (not entry.visible_when or entry.visible_when(idx))
end

function trigs.strip_fn.resolve(idx, current)
  if trigs.strip_fn.visible(idx, current) then return current end
  for i = current + 1, #trigs.STRIP do
    if trigs.strip_fn.visible(idx, i) then return i end
  end
  for i = current - 1, 1, -1 do
    if trigs.strip_fn.visible(idx, i) then return i end
  end
  return current
end

function trigs.strip_fn.advance(idx, current, d)
  if d == 0 then return current end
  local step = d > 0 and 1 or -1
  local next_idx = current + step
  while next_idx >= 1 and next_idx <= #trigs.STRIP do
    if trigs.strip_fn.visible(idx, next_idx) then return next_idx end
    next_idx = next_idx + step
  end
  return current
end

function trigs.fn.refresh_suspend(idx)
  local desired_lfo = nil
  if params:get("trig"..idx.."_enable") == 2 then
    local g = trigs.last_global[idx] or 1
    if trigs.TARGETS[g] then desired_lfo = trigs.TARGETS[g].lfo_idx end
  end
  local applied = trigs.applied_lfo[idx]
  if desired_lfo == applied then return end
  if applied then
    lfo.random.suspend_count[applied] = lfo.random.suspend_count[applied] - 1
    if lfo.random.suspend_count[applied] <= 0 then
      lfo.random.suspend_count[applied] = 0
      lfo.random.suspended[applied] = false
      lfo.start_clock(applied)
    end
  end
  if desired_lfo then
    lfo.random.suspend_count[desired_lfo] = lfo.random.suspend_count[desired_lfo] + 1
    if lfo.random.suspend_count[desired_lfo] == 1 then
      lfo.random.suspended[desired_lfo] = true
      lfo.start_clock(desired_lfo)
    end
  end
  trigs.applied_lfo[idx] = desired_lfo
end

-- Fire: run the action and remember when. The clock calls it when Chance says yes; K2 in the rack fires unconditionally.
function trigs.fn.fire(idx)
  trigs.last_fire[idx] = util.time()
  scope.push(trigs.scope[idx], trigs.last_fire[idx], 1)
  local entry = trigs.TARGETS[trigs.last_global[idx] or 1]
  if entry and entry.action and (not entry.lfo_idx or lfo.is_step_random(entry.lfo_idx)) then
    entry.action()
  end
end

function trigs.fn.start_clock(idx)
  trigs.clock_gen[idx] = (trigs.clock_gen[idx] or 0) + 1
  local my = trigs.clock_gen[idx]
  if is_initing() then return end
  if params:get("trig"..idx.."_enable") ~= 2 then return end
  clock.run(function()
    while true do
      local sync_div_opt = trigs.mod.sync_div[idx] ~= nil and trigs.mod.sync_div[idx] or params:get("trig"..idx.."_sync_div")
      if sync_div_opt > 1 and is_clock_running() then
        local feel_opt = trigs.mod.sync_feel[idx] ~= nil and trigs.mod.sync_feel[idx] or params:get("trig"..idx.."_sync_feel")
        local beats = sync.DIV_BEATS[sync_div_opt] * sync.FEEL_MULT[feel_opt]
        clock.sync(beats)
      else
        local rate = trigs.mod.rate[idx] ~= nil and trigs.mod.rate[idx] or params:get("trig"..idx.."_rate")
        clock.sleep(1 / math.max(0.05, rate))
      end
      if trigs.clock_gen[idx] ~= my then return end
      local prob = trigs.mod.chance[idx] ~= nil and trigs.mod.chance[idx] or params:get("trig"..idx.."_chance")
      if prob > 0 and (prob >= 100 or math.random() * 100 < prob) then
        trigs.fn.fire(idx)
      else
        trigs.last_skip[idx] = util.time()
        scope.push(trigs.scope[idx], trigs.last_skip[idx], 0)
      end
    end
  end)
end

function trigs.fn.set_target(idx, new_global)
  modtarget.set_target(binding, idx, new_global)
  trigs.fn.refresh_suspend(idx)
end

function trigs.fn.set_enable(idx)
  trigs.fn.refresh_suspend(idx)
  trigs.fn.start_clock(idx)
end

function trigs.fn.rebuild_target_param_dropdown(idx, dev_idx)
  modtarget.rebuild_param(binding, idx, dev_idx)
end

function trigs.fn.refresh_dropdowns_for_lfo(lfo_idx)
  modtarget.rebuild_all(binding)
  if _menu and _menu.rebuild_params then _menu.rebuild_params() end
end

-- The Trig's recent history: every roll with its time, 1 fired, 0 skipped by Chance.
-- The rack shows the last eight.
function trigs.scope_live(idx)
  local sc = trigs.scope[idx]
  return sc and sc.n > 0 and params:get("trig"..idx.."_enable") == 2
end

function trigs.scope_reset(idx) scope.reset(trigs.scope[idx]) end


function trigs.init(deps)
  looper           = deps.looper
  lfo              = deps.lfo
  is_initing      = deps.is_initing
  is_clock_running = deps.is_clock_running

  trigs.TARGETS = deps.targets

  -- grouped like the continuous targets: the label "Device: Action" yields both
  trigs.DEVICES, trigs.DEVICE_PARAMS = (function()
    local devices = { "-" }
    local dparams = { [1] = { { label = "-", global_idx = 1 } } }
    for i = 2, #trigs.TARGETS do
      local t = trigs.TARGETS[i]
      local dev_name, short_name = t.label:match("^(.-): (.+)$")
      if dev_name then
        local di
        for ix, dn in ipairs(devices) do
          if dn == dev_name then di = ix; break end
        end
        if not di then
          devices[#devices + 1] = dev_name
          di = #devices
          dparams[di] = {}
        end
        dparams[di][#dparams[di] + 1] = { label = short_name, global_idx = i }
      end
    end
    return devices, dparams
  end)()

  trigs.TARGET_DEVICE_OF = {}
  for di, plist in pairs(trigs.DEVICE_PARAMS) do
    for _, e in ipairs(plist) do trigs.TARGET_DEVICE_OF[e.global_idx] = di end
  end

  for i = 1, trigs.N do
    trigs.target_device_filter[i] = {}
    for di = 1, #trigs.DEVICES do trigs.target_device_filter[i][di] = di end
    trigs.target_param_filter[i] = {1}
  end

  binding = {
    set              = function(i, g) trigs.fn.set_target(i, g) end,
    num              = trigs.N,
    prefix           = function(i) return "trig" .. i end,
    owner            = trigs.target_owner,
    tag              = function(i) return i end,
    devices          = trigs.DEVICES,
    device_params    = trigs.DEVICE_PARAMS,
    target_device_of = trigs.TARGET_DEVICE_OF,
    targets          = trigs.TARGETS,
    label_of         = function(e) return e.label end,
    device_filter    = trigs.target_device_filter,
    param_filter     = trigs.target_param_filter,
    last_global      = trigs.last_global,
    visible          = function(g)
      local t = trigs.TARGETS[g]
      if not t then return false end
      if t.lfo_idx then return lfo.is_step_random(t.lfo_idx) end
      return true
    end,
    enabled          = function(i) return params:get("trig" .. i .. "_enable") == 2 end,
    on_rebuilt       = function()
      if _menu and _menu.rebuild_params then _menu.rebuild_params() end
    end,
  }
end

function trigs.binding() return binding end

return trigs
