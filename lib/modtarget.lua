local modtarget = {}

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

  modtarget.rebuild_all(b)
  if b.on_rebuilt then b.on_rebuilt() end
end

return modtarget
