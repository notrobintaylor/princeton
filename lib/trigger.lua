local sync      = include("lib/sync")
local sprites   = include("lib/sprites")
local modtarget = include("lib/modtarget")

local trigs = {}

local MED  = 5
local FULL = 15

trigs.N           = 4
trigs.mod         = { rate = {}, probability = {} }
trigs.clocks      = {}
trigs.last_global = {}
trigs.applied_lfo = {}
trigs.strip_fn    = {}
trigs.fn          = {}
trigs.strip_sel   = {1, 1, 1, 1}

trigs.target_owner         = {}
trigs.target_device_filter = {}
trigs.target_param_filter  = {}

for i = 1, trigs.N do trigs.last_global[i] = i + 1 end

local NUM_LFOS = 8

local looper, lfo
local is_initing, is_clock_running
local binding

function trigs.strip_fn.sync_active(idx) return params:get("trig"..idx.."_sync_div") > 1 end

trigs.STRIP = {
  {name="Probability", suf="_probability",   typ="ctrl", step=1,   fmt=function(v,i) return string.format("%d%%",math.floor(v)) end},
  {name="Rate",        suf="_rate",          typ="ctrl", step=0.1, fmt=function(v,i) return string.format("%.1fHz",v) end,
   visible_when=function(idx) return not trigs.strip_fn.sync_active(idx) end},
  {name="Sync",        suf="_sync_div",      typ="opt",  nmax=8,   fmt=function(v,i) return sync.DIV_OPTS[v] end},
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

trigs.TARGETS = {
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
for i = 1, NUM_LFOS do
  trigs.TARGETS[#trigs.TARGETS+1] = {
    label = "LFO "..i..": Randomize", id = "trig_lfo"..i.."_randomize", lfo_idx = i,
    action = function() params:set("lfo"..i.."_randomize", 1) end
  }
end

trigs.DEVICES, trigs.DEVICE_PARAMS = (function()
  local devices = { "Off" }
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

function trigs.fn.start_clock(idx)
  if trigs.clocks[idx] then clock.cancel(trigs.clocks[idx]); trigs.clocks[idx] = nil end
  if is_initing() then return end
  if params:get("trig"..idx.."_enable") ~= 2 then return end
  trigs.clocks[idx] = clock.run(function()
    while true do
      local sync_div_opt = params:get("trig"..idx.."_sync_div")
      if sync_div_opt > 1 and is_clock_running() then
        local feel_opt = params:get("trig"..idx.."_sync_feel")
        local beats = sync.DIV_BEATS[sync_div_opt] * sync.FEEL_MULT[feel_opt]
        clock.sync(beats)
      else
        local rate = trigs.mod.rate[idx] ~= nil and trigs.mod.rate[idx] or params:get("trig"..idx.."_rate")
        clock.sleep(1 / math.max(0.05, rate))
      end
      local prob = trigs.mod.probability[idx] ~= nil and trigs.mod.probability[idx] or params:get("trig"..idx.."_probability")
      if prob > 0 and (prob >= 100 or math.random() * 100 < prob) then
        local g = trigs.last_global[idx] or 1
        local entry = trigs.TARGETS[g]
        if entry and entry.action and (not entry.lfo_idx or lfo.is_step_random(entry.lfo_idx)) then
          entry.action()
        end
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

function trigs.draw_half(ox, oy, idx, focused)
  local cx      = ox + 16
  local enabled = params:get("trig"..idx.."_enable") == 2
  local icon_lv = enabled and FULL or MED
  sprites.draw_trigger_icon(cx, oy + 28, icon_lv)
  screen.font_size(8); screen.font_face(0)
  screen.level(icon_lv)
  screen.move(cx, oy + 56); screen.text_center("Trig " .. idx)
end

function trigs.init(deps)
  looper           = deps.looper
  lfo              = deps.lfo
  is_initing      = deps.is_initing
  is_clock_running = deps.is_clock_running

  for i = 1, trigs.N do
    trigs.target_device_filter[i] = {}
    for di = 1, #trigs.DEVICES do trigs.target_device_filter[i][di] = di end
    trigs.target_param_filter[i] = {1}
  end

  binding = {
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

return trigs
