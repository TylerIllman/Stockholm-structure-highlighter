if vim.g.loaded_stockholm then
  return
end
vim.g.loaded_stockholm = true

local sto = require("stockholm")

vim.api.nvim_create_user_command("StockholmNext", function()
  sto.cycle(1)
end, { desc = "Colour sequences by the next SS_cons line" })
vim.api.nvim_create_user_command("StockholmPrev", function()
  sto.cycle(-1)
end, { desc = "Colour sequences by the previous SS_cons line" })

local group = vim.api.nvim_create_augroup("Stockholm", { clear = true })

vim.api.nvim_create_autocmd("CursorMoved", {
  group = group,
  callback = function(ev)
    if vim.bo[ev.buf].filetype == "stockholm" then
      sto.redraw(ev.buf)
    end
  end,
})

vim.api.nvim_create_autocmd("ColorScheme", { group = group, callback = sto.define_highlights })
sto.define_highlights()

vim.api.nvim_create_autocmd("FileType", {
  group = group,
  pattern = "stockholm",
  callback = function(ev)
    local maps = sto.config.mappings
    if not maps then
      return
    end
    local function map(lhs, fn, desc)
      if lhs then
        vim.keymap.set("n", lhs, fn, { buffer = ev.buf, desc = desc })
      end
    end
    map(maps.next_structure, function() sto.cycle(1) end, "Stockholm: next structure line")
    map(maps.prev_structure, function() sto.cycle(-1) end, "Stockholm: previous structure line")
    map(maps.goto_partner, sto.goto_partner, "Stockholm: jump to paired base")
  end,
})
