-- scope: a modulation source's memory, a ring buffer of what it sent (time, value), drawn right
-- (now) to left so the editor shows what the source really does.
-- A Trig stores events instead (1 fired, 0 skipped by Chance), read back with scope.recent.

local scope = {}

local N, FULL = 384, 15

function scope.new() return { t = {}, v = {}, head = 0, n = 0 } end

function scope.reset(sc)
  if sc then sc.head, sc.n = 0, 0 end
end

function scope.push(sc, now, v)
  local h = sc.head % N + 1
  sc.head, sc.t[h], sc.v[h] = h, now, v
  if sc.n < N then sc.n = sc.n + 1 end
end

-- An antialiased line through one height per column (ys[i] in pixel rows, fractions allowed, nil
-- leaves a gap). Each column reaches halfway to its neighbours, and a pixel it only partly covers
-- glows dimmer, so slopes look smooth on 16 brightness steps instead of stair-stepped.
function scope.line(ox, ys, w, lv)
  local buckets = {}
  for i = 0, w - 1 do
    local y = ys[i]
    if y then
      local a, b = ys[i - 1], ys[i + 1]
      local lo, hi = y, y
      if a then lo, hi = math.min(lo, (a + y) / 2), math.max(hi, (a + y) / 2) end
      if b then lo, hi = math.min(lo, (b + y) / 2), math.max(hi, (b + y) / 2) end
      for r = math.floor(lo), math.ceil(hi) do
        local cover = math.min(r + 0.5, hi + 0.5) - math.max(r - 0.5, lo - 0.5)
        local l = math.floor(lv * math.min(1, cover) + 0.5)
        if l > 0 then
          local bk = buckets[l]
          if not bk then bk = {}; buckets[l] = bk end
          bk[#bk + 1] = ox + i; bk[#bk + 1] = r
        end
      end
    end
  end
  for l, bk in pairs(buckets) do
    screen.level(l)
    for k = 1, #bk, 2 do screen.rect(bk[k], bk[k + 1], 1, 1) end
    screen.fill()
  end
end

-- Each column reads the swing at its moment, between the two values sent around it, and the line
-- joins them; hold keeps the older value instead (Stepped Random jumps rather than glides).
-- The middle is the base, -1 to 1 fills the height.
function scope.draw(sc, ox, top, w, h_px, win, lv, hold)
  local now  = util.time()
  local span = h_px - 1
  local h, left, newer, ys = sc.head, sc.n, nil, {}
  for x = w - 1, 0, -1 do
    local tx = now - win * (w - 1 - x) / (w - 1)
    while left > 0 and sc.t[h] > tx do
      newer = h
      h = (h - 2) % N + 1
      left = left - 1
    end
    if left == 0 then break end
    local v = sc.v[h]
    if newer and not hold and sc.t[newer] > sc.t[h] then
      v = v + (sc.v[newer] - v) * (tx - sc.t[h]) / (sc.t[newer] - sc.t[h])
    end
    ys[x] = top + (1 - util.clamp(v, -1, 1)) * span / 2
  end
  scope.line(ox, ys, w, lv or FULL)
end

-- For sprites that draw themselves: each column's value (sample & hold as above), nil before the source had sent anything.
-- Column 0 is one window ago, w-1 is now.
function scope.sample(sc, now, win, w)
  local out = {}
  local h, left = sc.head, sc.n
  for x = w - 1, 0, -1 do
    local tx = now - win * (w - 1 - x) / (w - 1)
    while left > 0 and sc.t[h] > tx do
      h = (h - 2) % N + 1
      left = left - 1
    end
    if left == 0 then break end
    out[x] = sc.v[h]
  end
  return out
end

-- The last n events, oldest first: { v = 1|0, t = time }.
function scope.recent(sc, n)
  local out, h = {}, sc.head
  for i = math.min(n, sc.n), 1, -1 do
    out[i] = { v = sc.v[h], t = sc.t[h] }
    h = (h - 2) % N + 1
  end
  return out
end

return scope
