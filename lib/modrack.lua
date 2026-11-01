-- modrack: the Mod Rack, where modulation appears on demand: hold K1+K3 on a parameter and the
-- chooser patches the next free LFO, Sense, Walk or Trig to it (Remove resets it to factory state).
-- Under the hood it is fixed slots with one target per source and one owner per target.

local modrack = {}

local scope       = include("lib/scope")
local sprites_mod = include("lib/sprites_mod")

local MED, FULL = 5, 15

local lfo, env, seq, trigs, cabinet
local TARGET_PARAMS, RACK_PANES
local draw_strip, redraw_fn, open_source, fmt_value

local view     = "edit"   -- "empty" | "edit"
local chooser  = nil      -- while open: { id, dev, title, name, opts, sel }

local KINDS = {
  lfo  = { name = "LFO",   b = function() return lfo.binding() end },
  seq  = { name = "Walk",  b = function() return seq.binding() end },
  env  = { name = "Sense", b = function() return env.binding() end },
  trig = { name = "Trig",  b = function() return trigs.binding() end },
}

local function binding(kind) return KINDS[kind].b() end
local function mod_of(kind) return ({ lfo = lfo, seq = seq, env = env, trig = trigs })[kind] end
local function last_g(kind, idx) return binding(kind).last_global[idx] or 1 end
local function enabled(kind, idx) return params:get(kind .. idx .. "_enable") == 2 end

local function target_label(kind, idx)
  local t = binding(kind).targets[last_g(kind, idx)]
  return t and t.label or "-"
end

local function fit(s, w)
  if screen.text_extents(s) <= w then return s end
  while #s > 1 and screen.text_extents(s .. ".") > w do s = s:sub(1, -2) end
  return s .. "."
end

-- ── What is in the rack ────────────────────────────────────────
-- The panes (indices into RACK_PANES) of all patched sources, in rack order.
function modrack.active()
  local t = {}
  for p, src in ipairs(RACK_PANES) do
    if KINDS[src.kind] and last_g(src.kind, src.idx) > 1 then t[#t + 1] = p end
  end
  return t
end

function modrack.view() return view end
function modrack.show_empty() view = "empty"; chooser = nil end
function modrack.show_edit() view = "edit"; chooser = nil end

-- E1 in the editor: step to the previous or next patched source.
function modrack.neighbour(cur_pane, d)
  local act = modrack.active()
  if #act == 0 then return nil end
  local pos
  for i, p in ipairs(act) do if p == cur_pane then pos = i end end
  if not pos then
    for i, p in ipairs(act) do if p > cur_pane then pos = d > 0 and i - 1 or i; break end end
    pos = pos or #act
  end
  return act[util.clamp(pos + (d > 0 and 1 or -1), 1, #act)]
end

-- ── Spawning and removing ──────────────────────────────────────
local function reachable(kind, idx, g)
  local b = binding(kind)
  if not b.visible(g) then return false end
  if b.device_excluded and b.device_excluded(idx, b.target_device_of[g]) then return false end
  return true
end

local function free_slot(kind, g)
  local b = binding(kind)
  for i = 1, b.num do
    if (b.last_global[i] or 1) == 1 and reachable(kind, i, g) then return i end
  end
end

-- The first free Trig action of a device ("Push" -> "Push: Toggle").
local function trig_target_for(dev)
  if not dev then return nil end
  local pre = dev .. ": "
  for g, t in ipairs(trigs.TARGETS) do
    if t.id and t.label:sub(1, #pre) == pre and trigs.target_owner[t.id] == nil
       and binding("trig").visible(g) then
      return g
    end
  end
end

-- Factory reset for everything the slot owns except its target, which it has already released.
local function reset_source(kind, idx)
  local prefix = kind .. idx .. "_"
  for i = 1, params.count do
    local p  = params.params[i]
    local id = p.id
    if id and id:sub(1, #prefix) == prefix and not id:find("_target_") and id ~= prefix .. "enable" then
      local def = p.controlspec and p.controlspec.default or p.default
      if type(def) == "number" and params:get(id) ~= def then pcall(params.set, params, id, def) end
    end
  end
end

function modrack.remove(kind, idx)
  if enabled(kind, idx) then params:set(kind .. idx .. "_enable", 1) end
  binding(kind).set(idx, 1)
  reset_source(kind, idx)
  local m = mod_of(kind)
  if m.scope_reset then m.scope_reset(idx) end
end

local function spawn(kind, idx, g)
  binding(kind).set(idx, g)
  if not enabled(kind, idx) then params:set(kind .. idx .. "_enable", 2) end
  open_source(kind, idx)
end

-- ── Nothing patched ────────────────────────────────────────────
function modrack.draw_empty()
  screen.clear()
  screen.font_size(8); screen.font_face(0)
  screen.level(FULL); screen.move(64, 30); screen.text_center("Empty")
  screen.level(MED);  screen.move(64, 44); screen.text_center("hold K1+K3 on a param")
  screen.update()
end

-- ── One source, full size (editor) ────────────────────────────
-- The editor shows one source full size in the device box, the chooser's picture now running live.
-- Its target sits in one text line below a hairline.
local function frame_box()
  local CAB, top = cabinet.CAB, cabinet.TOP
  cabinet.frame(CAB.x, top, CAB.w, cabinet.H, MED)
  screen.level(3); screen.rect(CAB.x + 3, top + 49, CAB.w - 6, 1); screen.fill()
  return CAB.x + 3, top + 3, CAB.w - 6, 44, CAB.x + math.floor(CAB.w / 2), top + 57
end

function modrack.draw_source(kind, idx, sel_step, label)
  local CAB = cabinet.CAB
  local x, y, w, h, cx, base = frame_box()
  local on  = enabled(kind, idx)
  local lv  = on and FULL or MED
  local now = util.time()
  label = fit(label or target_label(kind, idx), CAB.w - 8)
  if kind == "seq" then
    local steps = {}
    for k = 1, seq.MAX_STEPS do steps[k] = params:get("seq" .. idx .. "_step_" .. k) / 100 end
    local cur = on and seq.state[idx] and seq.state[idx].step_pos
    sprites_mod.walk(x, y, w, h, steps, params:get("seq" .. idx .. "_steps"), cur, sel_step, lv)
  elseif kind == "env" then
    local win = sprites_mod.SENSE_WIN
    if env.scope_live(idx) then
      sprites_mod.sense(x, y, w, h, scope.sample(env.scope[idx], now, win, w), lv)
    else
      scope.draw_idle(x, y, w, h)
    end
  elseif kind == "trig" then
    local slots = trigs.scope_live(idx) and scope.recent(trigs.scope[idx], sprites_mod.TRIG_SLOTS) or {}
    sprites_mod.trig(x, y, w, h, slots, now, lv)
  elseif lfo.scope_live(idx) then
    lfo.draw_scope(x, y, idx, w, h, lv)
  else
    scope.draw_idle(x, y, w, h)
  end
  screen.font_size(8); screen.font_face(0)
  screen.level(lv)
  screen.move(cx, base); screen.text_center(label)
end

-- ── Chooser ────────────────────────────────────────────────────
-- The chooser asks what should move this parameter (Modulate, Sense, Walk) and whether a Trig
-- should switch its device; an existing source offers Edit and Remove instead, a full kind says "full".
local KIND_LABEL = { lfo = "Modulate", seq = "Walk", env = "Sense", trig = "Trigger" }

function modrack.chooser_open() return chooser ~= nil end
function modrack.chooser_close() chooser = nil end

-- id: the focused parameter (need not be a mod target); dev: its device's name.
function modrack.open_chooser(id, dev)
  local g, label
  for gi, t in ipairs(TARGET_PARAMS) do
    if t.id and t.id == id then g, label = gi, t.label; break end
  end
  local dev_l, name_l
  if label then dev_l, name_l = label:match("^(.-): (.+)$") end
  dev = dev_l or dev
  if not name_l and params.lookup[id] then name_l = params:lookup_param(id).name end
  local opts = {}
  local owner = g and lfo.target_owner[id]
  if owner ~= nil then
    for _, kind in ipairs({ "lfo", "seq", "env" }) do
      local b = binding(kind)
      for i = 1, b.num do
        if b.tag(i) == owner then
          opts[#opts + 1] = { act = "edit",   kind = kind, idx = i, label = "Edit" }
          opts[#opts + 1] = { act = "remove", kind = kind, idx = i, label = "Remove" }
        end
      end
    end
  else
    for _, kind in ipairs({ "lfo", "env", "seq" }) do
      opts[#opts + 1] = { act = "spawn", kind = kind, idx = g and free_slot(kind, g), g = g,
                          label = KIND_LABEL[kind], why = g and "full" or "-" }
    end
  end
  -- Trigs already patched to this device: edit or remove.
  local pre, has_trig = (dev or "") .. ": ", false
  for i = 1, trigs.N do
    local t = trigs.TARGETS[trigs.last_global[i] or 1]
    if (trigs.last_global[i] or 1) > 1 and t and t.label:sub(1, #pre) == pre then
      has_trig = true
      opts[#opts + 1] = { act = "edit",   kind = "trig", idx = i, label = "Edit",   device = true }
      opts[#opts + 1] = { act = "remove", kind = "trig", idx = i, label = "Remove", device = true }
    end
  end
  local tg = trig_target_for(dev)
  if tg or not has_trig then
    opts[#opts + 1] = { act = "spawn", kind = "trig", idx = tg and free_slot("trig", tg), g = tg,
                        label = KIND_LABEL.trig, why = tg and "full" or "-", device = true }
  end
  chooser = { id = id, dev = dev or "", name = name_l or "", opts = opts, sel = 1 }
  for i, o in ipairs(opts) do
    if o.idx then chooser.sel = i; break end
  end
  return true
end

function modrack.chooser_enc(n, d)
  if n == 1 then return end
  chooser.sel = util.clamp(chooser.sel + util.clamp(d, -1, 1), 1, #chooser.opts)
  redraw_fn()
end

function modrack.chooser_confirm()
  local o = chooser.opts[chooser.sel]
  if not o.idx then return end
  chooser = nil
  if o.act == "spawn" then spawn(o.kind, o.idx, o.g)
  elseif o.act == "edit" then open_source(o.kind, o.idx)
  else modrack.remove(o.kind, o.idx) end
  redraw_fn()
end

-- The chooser fills the device box with a sprite of each option and its name; E3 browses, K3 spawns.
-- The strip, not the box, says which device and parameter are being patched.
function modrack.draw_chooser()
  local o = chooser.opts[chooser.sel]
  local CAB = cabinet.CAB
  screen.clear()
  screen.font_size(8); screen.font_face(0)
  -- Redraw the strip; for a Trig only the device, since it never touches the parameter.
  if o.device then
    draw_strip(chooser.dev, "", "")
  else
    draw_strip(chooser.dev, chooser.name, fmt_value(chooser.id))
  end
  local x, y, w, h, cx, base = frame_box()
  sprites_mod.draw(o.kind, x, y, w, h, o.idx and FULL or 2)
  if not o.idx then
    local tw, my = screen.text_extents(o.why), y + math.floor(h / 2)
    screen.level(0); screen.rect(cx - math.floor(tw / 2) - 3, my - 7, tw + 6, 11); screen.fill()
    screen.level(MED); screen.move(cx, my + 1); screen.text_center(o.why)
  end
  local lbl = o.label
  screen.level(o.idx and FULL or MED); screen.move(cx, base); screen.text_center(lbl)
  local lx = cx - math.floor(screen.text_extents(lbl) / 2)
  screen.level(FULL); screen.rect(lx - 2, base - 5, 1, 1); screen.fill()
  screen.update()
end

function modrack.init(deps)
  lfo, env, seq, trigs = deps.lfo, deps.env, deps.seq, deps.trigs
  cabinet       = deps.cabinet
  TARGET_PARAMS = deps.TARGET_PARAMS
  RACK_PANES    = deps.RACK_PANES
  draw_strip    = deps.draw_strip
  fmt_value     = deps.fmt_value
  redraw_fn     = deps.redraw
  open_source   = deps.open_source
end

return modrack
