local looper_ui = {}

function looper_ui.new(ctx, into)
  local U = into or {}
  U.sel = 1

  function U.draw_pane()
  local B      = ctx.B
  local pts    = ctx.LOOPER_PTS
  local looper = ctx.looper
  local sel    = U.sel
  screen.clear()

  local p = ctx.LOOPER_DEF[sel]
  ctx.draw_strip(ctx.label or p.cat, p.name, ctx.fmt_val(sel), ctx.val_level(p.id))

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

  if ctx.draw_overlay then ctx.draw_overlay() end

  screen.update()
  end

  function U.enc(n, d)
    if n == 2 then
      U.sel = util.clamp(U.sel + d, 1, #ctx.LOOPER_DEF)
      redraw()
    elseif n == 3 then
      ctx.edit_param(ctx.LOOPER_DEF[U.sel].id, d)
      redraw()
    end
  end

  return U
end

function looper_ui.init(c) return looper_ui.new(c, looper_ui) end

return looper_ui
