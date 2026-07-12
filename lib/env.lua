local env = {}
local modtarget = include("lib/modtarget")

local MED  = 5
local FULL = 15

env.NUM      = 2
env.DIR_OPTS = {"+", "-"}

env.last_global          = {}
env.last_value           = {}
env.target_device_filter = {}
env.target_param_filter  = {}
env.polls                = {}
env.strip_sel            = {1, 1}

local TARGET_PARAMS, DEVICE_NAMES, DEVICE_PARAMS, TARGET_DEVICE_OF
local lfo, is_initing, is_pane_visible_l, is_pane_visible_r, redraw_pane, on_target_change
local binding

local OWN_PREFIX = "env_"
local function owner_tag(idx) return OWN_PREFIX .. idx end

env.STRIP = {
  {name="Depth",     suf="_depth",        typ="ctrl", step=1, fmt=function(v,i) return string.format("%d%%", math.floor(v)) end},
  {name="Direction", suf="_dir",          typ="opt",  nmax=2, fmt=function(v,i) return env.DIR_OPTS[v] end},
  {name="Slew",      suf="_slew",         typ="ctrl", step=1, fmt=function(v,i) return string.format("%dms", math.floor(v)) end},
  {name="Device",    suf="_target_device", typ="opt",  nmax_fn=function(i) return #(env.target_device_filter[i] or {}) end,
    fmt=function(v,i)
      local dmap = env.target_device_filter[i]
      local di   = dmap and dmap[v]
      if di == 0 then return "-" end
      return (di and DEVICE_NAMES[di]) or "?"
    end},
  {name="Parameter", suf="_target_param",  typ="opt",  nmax_fn=function(i) return #(env.target_param_filter[i] or {}) end,
    fmt=function(v,i)
      local pmap = env.target_param_filter[i]
      local gi   = pmap and pmap[v]
      if gi and gi > 1 and TARGET_PARAMS[gi] then return TARGET_PARAMS[gi].label:match(": (.+)$") or TARGET_PARAMS[gi].label end
      return "-"
    end},
}

function env.strip_advance(idx, current, d)
  if d == 0 then return current end
  return util.clamp(current + (d > 0 and 1 or -1), 1, #env.STRIP)
end

function env.is_enabled(idx) return params:get("env"..idx.."_enable") == 2 end

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

function env.rebuild_target_param_dropdown(idx, dev_idx)
  modtarget.rebuild_param(binding, idx, dev_idx)
end

function env.rebuild_target_dropdown(idx)
  modtarget.rebuild(binding, idx)
end

function env.rebuild_all_target_dropdowns()
  modtarget.rebuild_all(binding)
end

local function apply_to_target(idx)
  if is_initing() then return end
  if params:get("env"..idx.."_enable") ~= 2 then return end
  local target_idx = env.last_global[idx] or 1
  if target_idx == 1 then return end
  local t = TARGET_PARAMS[target_idx]
  if not t or not t.id or not t.send then return end
  if lfo.target_owner[t.id] ~= owner_tag(idx) then return end

  local base = lfo.target_base[t.id]
  if base == nil then base = params:get(t.id) end

  local v_un = env.last_value[idx] or 0
  if v_un < 0 then v_un = 0 elseif v_un > 1 then v_un = 1 end
  local depth = params:get("env"..idx.."_depth")
  local dir   = params:get("env"..idx.."_dir")
  local d     = depth / 100
  local range = t.mx - t.mn
  local off   = (dir == 1) and (v_un * d * range) or (-v_un * d * range)

  local val = util.clamp(base + off, t.mn, t.mx)
  val = math.floor(val / t.st + 0.5) * t.st
  t.send(val)
end

function env.set_target(idx, new_global_idx)
  modtarget.set_target(binding, idx, new_global_idx)
end

local function half_visible(idx)
  if not is_pane_visible_l or not is_pane_visible_r then return false end
  if idx == 1 then return is_pane_visible_l() end
  return is_pane_visible_r()
end

function env.start_polls()
  for i = 1, env.NUM do
    if env.polls[i] then env.polls[i]:stop() end
    local ii = i
    local p = poll.set("env" .. ii .. "_value", function(v)
      env.last_value[ii] = v or 0
      apply_to_target(ii)
      if half_visible(ii) and redraw_pane then redraw_pane() end
    end)
    if p then
      p.time = 1 / 30
      env.polls[ii] = p
      if env.is_enabled(ii) then p:start() end
    end
  end
end

function env.poll_set_active(idx, on)
  local p = env.polls[idx]
  if not p then return end
  if on then p:start() else p:stop() end
end

function env.draw_half(ox, oy, idx, focused)
  local cx       = ox + 16
  local mid      = oy + 24
  local enabled  = env.is_enabled(idx)
  local lv       = enabled and FULL or MED
  screen.level(lv)
  screen.rect(cx - 14, mid, 28, 1); screen.fill()
  if enabled then
    local v = env.last_value[idx] or 0
    if v < 0 then v = 0 elseif v > 1 then v = 1 end
    local depth = params:get("env"..idx.."_depth")
    local dir   = params:get("env"..idx.."_dir")
    local h     = math.floor(util.clamp(v * (depth / 100) * 3, 0, 1) * 22 + 0.5)
    if h > 0 then
      screen.level(FULL)
      if dir == 1 then screen.rect(cx - 14, mid - h, 28, h)
      else             screen.rect(cx - 14, mid + 1, 28, h) end
      screen.fill()
    end
  end
  screen.font_size(8); screen.font_face(0)
  screen.level(lv)
  screen.move(cx, oy + 56); screen.text_center("Sense " .. idx)
end

function env.init(deps)
  TARGET_PARAMS     = deps.TARGET_PARAMS
  DEVICE_NAMES      = deps.DEVICE_NAMES
  DEVICE_PARAMS     = deps.DEVICE_PARAMS
  TARGET_DEVICE_OF  = deps.TARGET_DEVICE_OF
  lfo               = deps.lfo
  is_initing       = deps.is_initing
  is_pane_visible_l = deps.is_pane_visible_l
  is_pane_visible_r = deps.is_pane_visible_r
  redraw_pane       = deps.redraw_pane
  on_target_change  = deps.on_target_change

  for i = 1, env.NUM do
    env.last_global[i] = 1
    env.last_value[i]  = 0
    env.target_device_filter[i] = {}
    for di = 1, #DEVICE_NAMES do env.target_device_filter[i][di] = di end
    env.target_param_filter[i] = {}
    if DEVICE_PARAMS[1] then
      for j, e in ipairs(DEVICE_PARAMS[1]) do env.target_param_filter[i][j] = e.global_idx end
    end
  end

  binding = {
    num              = env.NUM,
    none_option      = true,
    prefix           = function(i) return "env" .. i end,
    owner            = lfo.target_owner,
    tag              = owner_tag,
    devices          = DEVICE_NAMES,
    device_params    = DEVICE_PARAMS,
    target_device_of = TARGET_DEVICE_OF,
    targets          = TARGET_PARAMS,
    label_of         = function(e) return e.short end,
    device_filter    = env.target_device_filter,
    param_filter     = env.target_param_filter,
    last_global      = env.last_global,
    visible          = function(g) local t = TARGET_PARAMS[g]; return t ~= nil and target_visible(t.id) end,
    enabled          = env.is_enabled,
    on_claim         = function(g)
      local id = TARGET_PARAMS[g].id
      lfo.target_base[id] = params:get(id)
      lfo.mark_modulated(id)
    end,
    on_release       = function(g)
      local t = TARGET_PARAMS[g]
      lfo.unmark_modulated(t.id)
      local base = lfo.target_base[t.id]
      if base == nil then base = params:get(t.id) end
      if t.send then t.send(base) end
    end,
    on_rebuilt       = function()
      for i = 1, lfo.NUM do lfo.rebuild_target_dropdown(i) end
      if on_target_change then on_target_change() end
      if _menu and _menu.rebuild_params then _menu.rebuild_params() end
    end,
  }
end

return env
