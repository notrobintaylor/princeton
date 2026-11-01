-- scope: a modulation source's memory, a ring buffer of what it sent (time, value), drawn right
-- (now) to left so the editor shows what the source really does.
-- A Trig stores events instead (1 fired, 0 skipped by Probability), read back with scope.recent.

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

-- Each column takes the newest swing sent by its time (sample & hold, as at the target) and joins its
-- neighbour vertically, so jumps stay jumps and curves stay round. The middle is the base, -1 to 1 fills the height.
function scope.draw(sc, ox, top, w, h_px, win, lv)
  local now  = util.time()
  local span = h_px - 1
  screen.level(lv or FULL)
  local h, left, prev_y = sc.head, sc.n, nil
  for x = w - 1, 0, -1 do
    local tx = now - win * (w - 1 - x) / (w - 1)
    while left > 0 and sc.t[h] > tx do
      h = (h - 2) % N + 1
      left = left - 1
    end
    if left == 0 then break end
    local y = top + math.floor((1 - util.clamp(sc.v[h], -1, 1)) * span / 2 + 0.5)
    if prev_y then
      local y0 = math.min(y, prev_y)
      screen.rect(ox + x, y0, 1, math.abs(y - prev_y) + 1)
    else
      screen.rect(ox + x, y, 1, 1)
    end
    prev_y = y
  end
  screen.fill()
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
