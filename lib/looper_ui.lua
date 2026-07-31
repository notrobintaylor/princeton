-- looper_ui: the looper pane (render + encoder) and its selection state,
-- shared by princeton and media. Uses the Norns globals `screen` and `redraw`;
-- host-specific pieces come via init(ctx):
--   ctx.draw_strip(cat,name,val,lv)
--   ctx.fmt_val(idx)        -- formatted value string for LOOPER_DEF[idx]
--   ctx.LOOPER_DEF          -- looper param display table (.cat/.name/.id per entry)
--   ctx.val_level(id)       -- value brightness (sync/mod aware)
--   ctx.draw_state_icon()   -- looper transport icon
--   ctx.draw_overlay()      -- optional: host overlay into the frame (princeton: H1 // H2)
--   ctx.B                   -- brightness levels {DIM,MED,FULL}
--   ctx.looper              -- loop state machine (state, quant_led_lit)
--   ctx.LOOPER_PTS          -- partitioned looper sprite (from sprites_looper)
--   ctx.edit_param(id,d)    -- shared param editor
local looper_ui = {}

looper_ui.sel = 1   -- selected looper param

local ctx

function looper_ui.init(c) ctx = c end

function looper_ui.draw_pane()
  local B      = ctx.B
  local pts    = ctx.LOOPER_PTS
  local looper = ctx.looper
  local sel    = looper_ui.sel
  screen.clear()

  local p = ctx.LOOPER_DEF[sel]
  ctx.draw_strip(p.cat, p.name, ctx.fmt_val(sel), ctx.val_level(p.id))

  ctx.draw_state_icon()

  local OX, OY      = 44, 3
  local rec_active  = (looper.state == looper.REC or looper.state == looper.PLAY or looper.state == looper.DUB)
  local left_active = (looper.state == looper.STOP)

  local function blit(lst, lv)
    if #lst == 0 then return end
    screen.level(lv)
    for _, q in ipairs(lst) do screen.rect(OX + q[1], OY + q[2], 1, 1) end
    screen.fill()
  end

  blit(pts.bg, B.MED)
  for i = 1, 9 do blit(pts.knob[i], (sel == i) and B.FULL or B.MED) end
  blit(pts.ldisp, left_active          and B.FULL or B.MED)
  blit(pts.rdisp, rec_active           and B.FULL or B.MED)
  blit(pts.led,   looper.quant_led_lit and B.FULL or B.MED)

  -- optional host overlay drawn into the same frame (princeton: H1 // H2 status)
  if ctx.draw_overlay then ctx.draw_overlay() end

  screen.update()
end

function looper_ui.enc(n, d)
  if n == 2 then
    looper_ui.sel = util.clamp(looper_ui.sel + d, 1, #ctx.LOOPER_DEF)
    redraw()
  elseif n == 3 then
    ctx.edit_param(ctx.LOOPER_DEF[looper_ui.sel].id, d)
    redraw()
  end
end

return looper_ui
