-- modtarget: who modulates whom; LFO, Sense, Trig and Walk claim targets, one owner each, so menu
-- lists show only free targets and a list position is not a stable name. Each source therefore saves its
-- target's id in a hidden param (<prefix>_target_id) that restore_from_ids() resolves after a PSET load.

local modtarget = {}

local UNKNOWN = "?"   -- set before loading: "this PSET carries no target ids yet"
modtarget.UNKNOWN = UNKNOWN

local function owner_key(b, g)
  local t = b.targets[g]
  return t and t.id
end

local function owner_ok(b, idx, g)
  local key   = owner_key(b, g)
  local owner = key and b.owner[key]
  return owner == nil or owner == b.tag(idx)
end

local function available(b, idx, g)
  return b.visible(g) and owner_ok(b, idx, g)
end

local function id_param(b, idx) return b.prefix(idx) .. "_target_id" end

function modtarget.rebuild_param(b, idx, dev_idx)
  local p = params:lookup_param(b.prefix(idx) .. "_target_param")
  if not p then return end
  local opts, map = {}, {}
  local dps = dev_idx and b.device_params[dev_idx]
  if dps then
    for _, entry in ipairs(dps) do
      if available(b, idx, entry.global_idx) then
        opts[#opts + 1] = b.label_of(entry)
        map[#map + 1]   = entry.global_idx
      end
    end
  end
  if #opts == 0 then opts = {"-"}; map = {1} end
  b.param_filter[idx] = map
  p.options = opts
  p.count   = #opts
  local cur, nf = b.last_global[idx] or 1, 1
  for fi, gi in ipairs(map) do if gi == cur then nf = fi; break end end
  p.selected = nf
end

function modtarget.rebuild_device(b, idx)
  local p = params:lookup_param(b.prefix(idx) .. "_target_device")
  if not p then return end
  local opts, map = {}, {}
  if b.none_option then opts[1] = "-"; map[1] = 0 end
  for di = 1, #b.devices do
    if not (b.device_excluded and b.device_excluded(idx, di)) then
      local has_available = false
      local dps = b.device_params[di]
      if dps then
        for _, entry in ipairs(dps) do
          if owner_ok(b, idx, entry.global_idx) then has_available = true; break end
        end
      end
      if has_available then
        opts[#opts + 1] = b.devices[di]
        map[#map + 1]   = di
      end
    end
  end
  if #opts == 0 then opts = {"-"}; map = {1} end
  b.device_filter[idx] = map
  p.options = opts
  p.count   = #opts
  local cur_dev, nf = b.target_device_of[b.last_global[idx] or 1] or (b.none_option and 0 or 1), 1
  for fi, di in ipairs(map) do if di == cur_dev then nf = fi; break end end
  p.selected = nf
end

function modtarget.rebuild(b, idx)
  modtarget.rebuild_device(b, idx)
  local cur_dev = b.target_device_of[b.last_global[idx] or 1]
  if not cur_dev then
    local df = params:get(b.prefix(idx) .. "_target_device")
    cur_dev  = (b.device_filter[idx] and b.device_filter[idx][df]) or (b.none_option and 0 or 1)
  end
  modtarget.rebuild_param(b, idx, cur_dev)
end

function modtarget.rebuild_all(b)
  for i = 1, b.num do modtarget.rebuild(b, i) end
end

function modtarget.set_target(b, idx, new_global)
  local prev = b.last_global[idx] or 1
  local tag  = b.tag(idx)

  if prev > 1 then
    local key = owner_key(b, prev)
    if key and b.owner[key] == tag then
      b.owner[key] = nil
      if b.on_release then b.on_release(prev, idx) end
    end
  end

  b.last_global[idx] = new_global

  if new_global > 1 then
    local key = owner_key(b, new_global)
    if key and not b.owner[key] then
      b.owner[key] = tag
      if b.on_claim then b.on_claim(new_global, idx) end
    end
  end

  -- record the target id, except while a PSET loads: the PSET brings its own
  local pid = id_param(b, idx)
  if params.lookup[pid] and not params.pset_loading then
    params:set(pid, owner_key(b, new_global) or "")
  end

  modtarget.rebuild_all(b)
  if b.on_rebuilt then b.on_rebuilt() end
end

-- The three functions below take the bindings list explicitly. include() loads a fresh copy of this
-- module per library, so a registry kept in here would only see one of them.

-- Before a PSET loads: mark every id unknown, so an old PSET without ids can be recognised.
function modtarget.mark_unknown(bindings)
  for _, b in ipairs(bindings) do
    for i = 1, b.num do
      local pid = id_param(b, i)
      if params.lookup[pid] then params:set(pid, UNKNOWN) end
    end
  end
end

-- After loading: release every source that has an id, then reclaim each by id. Two passes, because
-- otherwise one source could still hold a target that another is about to claim.
function modtarget.restore_from_ids(bindings)
  local want = {}
  for _, b in ipairs(bindings) do
    for i = 1, b.num do
      local pid = id_param(b, i)
      local id  = params.lookup[pid] and params:get(pid) or UNKNOWN
      if id ~= UNKNOWN then
        local g = 1
        for gi, t in ipairs(b.targets) do
          if t.id == id then g = gi; break end
        end
        want[#want + 1] = { b = b, i = i, g = g }
        modtarget.set_target(b, i, 1)
      end
    end
  end
  for _, w in ipairs(want) do
    if w.b.set then w.b.set(w.i, w.g) else modtarget.set_target(w.b, w.i, w.g) end
  end
  -- old PSETs: fill in the id from the loaded state, ready for the next save
  for _, b in ipairs(bindings) do
    for i = 1, b.num do
      local pid = id_param(b, i)
      if params.lookup[pid] and params:get(pid) == UNKNOWN then
        params:set(pid, owner_key(b, b.last_global[i] or 1) or "")
      end
    end
  end
end

-- Create the hidden target-id params for all bindings (once in init, after the sources).
function modtarget.add_id_params(bindings)
  for _, b in ipairs(bindings) do
    for i = 1, b.num do
      local pid = id_param(b, i)
      params:add_text(pid, pid, owner_key(b, b.last_global[i] or 1) or "")
      params:hide(pid)
    end
  end
end

return modtarget
