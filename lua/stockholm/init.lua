--- stockholm.nvim: highlight base pairs in Stockholm (.sto) alignments.
local M = {}

M.config = {
  -- "pair": every base pair gets its own colour. "stem": every helix gets one colour.
  color_mode = "pair",
  -- Buffer-local mappings for stockholm buffers. Set an entry (or the whole table) to false to skip it.
  mappings = {
    next_structure = "]s",
    prev_structure = "[s",
    goto_partner = "gp",
  },
}

--- Optional configuration. The plugin works without calling this.
---@param opts table|nil
function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})
end

local ns = vim.api.nvim_create_namespace("stockholm")

local NCOLORS = 120

local function hsl_to_hex(h, sat, l)
  local function f(n)
    local k = (n + h / 30) % 12
    local a = sat * math.min(l, 1 - l)
    local v = l - a * math.max(-1, math.min(k - 3, 9 - k, 1))
    return math.floor(v * 255 + 0.5)
  end
  return string.format("#%02x%02x%02x", f(0), f(8), f(4))
end

local OPEN = { ["<"] = ">", ["("] = ")", ["["] = "]", ["{"] = "}" }
for i = 0, 25 do
  OPEN[string.char(65 + i)] = string.char(97 + i)
end
local CLOSE = {}
for open, close in pairs(OPEN) do
  CLOSE[close] = open
end

-- Colours are spread around the hue wheel by the golden angle so that consecutive ids
-- always differ strongly; lightness alternates to separate ids that land on close hues.
function M.define_highlights()
  for i = 1, NCOLORS do
    local hue = (i * 137.508) % 360
    local l = (i % 2 == 0) and 0.72 or 0.82
    vim.api.nvim_set_hl(0, "StoPair" .. i, { bg = hsl_to_hex(hue, 0.75, l), fg = "#1e1e1e", default = true })
  end
  vim.api.nvim_set_hl(0, "StoPairCursor", { bg = "#000000", fg = "#ffffff", bold = true, default = true })
  vim.api.nvim_set_hl(0, "StoActive", { link = "Comment", default = true })
  vim.api.nvim_set_hl(0, "StoReadout", { link = "DiagnosticInfo", default = true })
end

-- Pairs up one structure string using a stack per bracket type.
local function pair_up(global)
  local stacks, partner, pair_id, next_id = {}, {}, {}, 0
  for g = 1, #global do
    local ch = global:sub(g, g)
    if OPEN[ch] then
      next_id = next_id + 1
      stacks[ch] = stacks[ch] or {}
      table.insert(stacks[ch], g)
      pair_id[g] = next_id
    elseif CLOSE[ch] then
      local stack = stacks[CLOSE[ch]]
      local o = stack and table.remove(stack)
      if o then
        partner[o], partner[g] = g, o
        pair_id[g] = pair_id[o]
      end
    end
  end
  -- Consecutive stacked pairs (i, j) and (i + 1, j - 1) belong to the same stem.
  local stem_id, nstems = {}, 0
  for g = 1, #global do
    local c = partner[g]
    if c and c > g then
      if partner[g - 1] == c + 1 and stem_id[g - 1] then
        stem_id[g] = stem_id[g - 1]
      else
        nstems = nstems + 1
        stem_id[g] = nstems
      end
      stem_id[c] = stem_id[g]
    end
  end
  return { partner = partner, pair_id = pair_id, stem_id = stem_id, npairs = next_id }
end

-- Parses the buffer into records (one per "//"-terminated alignment). A record holds
-- blocks (interleaved chunks of the alignment), and one structure per SS_cons* line.
local function parse(buf)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local records, rows = {}, {}
  local rec, block

  local function flush_block()
    if block and #block.rows > 0 then
      rec.blocks[#rec.blocks + 1] = block
    end
    block = nil
  end

  local function flush_record()
    flush_block()
    if not rec or #rec.blocks == 0 then
      rec = nil
      return
    end
    local offset, globals = 0, {}
    for _, b in ipairs(rec.blocks) do
      b.off, b.len = offset, b.rows[1].len
      offset = offset + b.len
      for name, data in pairs(b.ss) do
        globals[name] = globals[name] or {}
        globals[name][#globals[name] + 1] = { off = b.off, data = data }
      end
    end
    rec.structs = {}
    for _, name in ipairs(rec.order) do
      local chars = {}
      for _, part in ipairs(globals[name]) do
        chars[part.off + 1] = part.data
      end
      -- Pad blocks lacking this structure so offsets stay aligned.
      local pieces = {}
      for _, b in ipairs(rec.blocks) do
        pieces[#pieces + 1] = chars[b.off + 1] or string.rep(".", b.len)
      end
      rec.structs[name] = pair_up(table.concat(pieces))
    end
    -- Default structure: the first one that actually contains pairs.
    rec.default = rec.order[1]
    for _, name in ipairs(rec.order) do
      if rec.structs[name].npairs > 0 then
        rec.default = name
        break
      end
    end
    records[#records + 1] = rec
    rec = nil
  end

  for i, line in ipairs(lines) do
    if line:match("^//") then
      flush_record()
    elseif line:match("^%s*$") then
      flush_block()
    else
      local prefix, name, data, kind
      prefix, name, data = line:match("^(#=GC%s+(SS_cons%S*)%s+)(%S+)")
      if prefix then
        kind = "ss"
      else
        prefix, data = line:match("^(#=GR%s+%S+%s+SS%s+)(%S+)")
        if prefix then
          kind = "gr"
        elseif not line:match("^#") then
          prefix, data = line:match("^(%S+%s+)(%S+)")
          kind = "seq"
        end
      end
      if prefix then
        rec = rec or { blocks = {}, order = {}, start = i }
        block = block or { rows = {}, ss = {}, rec = rec }
        local row = { lnum = i - 1, pre = #prefix, len = #data, kind = kind, name = name, block = block }
        block.rows[#block.rows + 1] = row
        rows[i - 1] = row
        if kind == "ss" then
          if not block.ss[name] then
            block.ss[name] = data
            if not vim.tbl_contains(rec.order, name) then
              rec.order[#rec.order + 1] = name
            end
          end
        end
      end
    end
  end
  flush_record()

  return { rows = rows, records = records }
end

M._parse = parse

local cache = {}
-- Structure chosen by the user per record, keyed by buffer and record start line.
local chosen = {}

local function get_state(buf)
  local tick = vim.api.nvim_buf_get_changedtick(buf)
  local entry = cache[buf]
  if not entry or entry.tick ~= tick then
    entry = { tick = tick, state = parse(buf) }
    cache[buf] = entry
  end
  return entry.state
end

local function active_name(buf, rec)
  local name = chosen[buf] and chosen[buf][rec.start]
  if name and rec.structs[name] then
    return name
  end
  return rec.default
end

local function set_chosen(buf, rec, name)
  chosen[buf] = chosen[buf] or {}
  chosen[buf][rec.start] = name
end

-- Structure used to colour a row: SS lines use their own, everything else the active one.
local function row_struct(buf, row)
  local rec = row.block.rec
  if row.kind == "ss" then
    return rec.structs[row.name]
  end
  local name = active_name(buf, rec)
  return name and rec.structs[name]
end

-- Columns (block + column within block) to emphasise for the cursor and its partner.
local function cursor_columns(buf, state, win)
  local lnum, col = unpack(vim.api.nvim_win_get_cursor(win))
  local info = state.rows[lnum - 1]
  if not info then
    return nil
  end
  local c = col - info.pre + 1
  if c < 1 or c > info.len then
    return nil
  end
  local struct = row_struct(buf, info)
  local g = info.block.off + c
  local other = struct and struct.partner[g]
  if not other then
    return nil
  end
  local marks = { { block = info.block, c = c } }
  local other_block = info.block
  for _, block in ipairs(info.block.rec.blocks) do
    if other > block.off and other <= block.off + block.len then
      marks[2] = { block = block, c = other - block.off }
      other_block = block
    end
  end

  -- Bases at both ends of the pair, read from a sequence line in each block.
  local function base(block, col)
    local row = (info.kind == "seq" and block == info.block) and info or nil
    for _, r in ipairs(block.rows) do
      if not row and r.kind == "seq" then
        row = r
      end
    end
    if not row then
      return "?"
    end
    local text = vim.api.nvim_buf_get_lines(buf, row.lnum, row.lnum + 1, false)[1] or ""
    local ch = text:sub(row.pre + col, row.pre + col)
    return ch ~= "" and ch or "?"
  end
  local lo, hi = math.min(g, other), math.max(g, other)
  local lo_block, hi_block = info.block, other_block
  if g > other then
    lo_block, hi_block = other_block, info.block
  end
  marks.readout = {
    struct = struct,
    text = string.format(
      " pair %d: col %d ↔ col %d (%s–%s) ",
      struct.pair_id[g], lo, hi, base(lo_block, lo - lo_block.off), base(hi_block, hi - hi_block.off)
    ),
  }
  return marks
end

-- Moving onto a structure line makes it the one used to colour the sequences.
local function follow_cursor(buf, state, win)
  local lnum = vim.api.nvim_win_get_cursor(win)[1]
  local info = state.rows[lnum - 1]
  if info and info.kind == "ss" then
    set_chosen(buf, info.block.rec, info.name)
  end
end

local active

vim.api.nvim_set_decoration_provider(ns, {
  on_win = function(_, win, buf)
    if vim.bo[buf].filetype ~= "stockholm" then
      active = nil
      return false
    end
    local state = get_state(buf)
    if win == vim.api.nvim_get_current_win() then
      follow_cursor(buf, state, win)
    end
    active = { state = state, cursor = cursor_columns(buf, state, win) }
    return true
  end,
  on_line = function(_, _, buf, lnum)
    local info = active and active.state.rows[lnum]
    if not info then
      return
    end
    local struct = row_struct(buf, info)
    if struct then
      local off = info.block.off
      local pair_id = (vim.g.stockholm_color_mode or M.config.color_mode) == "stem" and struct.stem_id or struct.pair_id
      for c = 1, info.len do
        local id = pair_id[off + c]
        if id then
          vim.api.nvim_buf_set_extmark(buf, ns, lnum, info.pre + c - 1, {
            end_col = info.pre + c,
            hl_group = "StoPair" .. ((id - 1) % NCOLORS + 1),
            ephemeral = true,
            priority = 100,
          })
        end
      end
    end
    if info.kind == "ss" then
      local virt = {}
      if info.name == active_name(buf, info.block.rec) then
        virt[#virt + 1] = { " ◀ colours sequences", "StoActive" }
      end
      local readout = active.cursor and active.cursor.readout
      if readout and readout.struct == info.block.rec.structs[info.name] then
        virt[#virt + 1] = { readout.text, "StoReadout" }
      end
      if #virt > 0 then
        vim.api.nvim_buf_set_extmark(buf, ns, lnum, 0, {
          virt_text = virt,
          virt_text_pos = "eol",
          ephemeral = true,
        })
      end
    end
    for _, mark in ipairs(active.cursor or {}) do
      if mark.block == info.block and mark.c <= info.len then
        vim.api.nvim_buf_set_extmark(buf, ns, lnum, info.pre + mark.c - 1, {
          end_col = info.pre + mark.c,
          hl_group = "StoPairCursor",
          ephemeral = true,
          priority = 200,
        })
      end
    end
  end,
})

-- Cycles which SS_cons* line colours the sequences of the alignment under the cursor.
function M.cycle(delta)
  local buf = vim.api.nvim_get_current_buf()
  local state = get_state(buf)
  local info = state.rows[vim.api.nvim_win_get_cursor(0)[1] - 1]
  if not info then
    -- Fall back to the record containing the cursor line.
    local lnum = vim.api.nvim_win_get_cursor(0)[1]
    for _, rec in ipairs(state.records) do
      if rec.start <= lnum then
        info = { block = { rec = rec } }
      end
    end
  end
  if not info then
    return
  end
  local rec = info.block.rec
  local current = active_name(buf, rec)
  local idx = 1
  for i, name in ipairs(rec.order) do
    if name == current then
      idx = i
    end
  end
  local name = rec.order[(idx - 1 + delta) % #rec.order + 1]
  set_chosen(buf, rec, name)
  vim.notify("Stockholm: colouring sequences by " .. name)
  M.redraw(buf)
end

-- Moves the cursor to the base paired with the one under it.
function M.goto_partner()
  local buf = vim.api.nvim_get_current_buf()
  local state = get_state(buf)
  local lnum, col = unpack(vim.api.nvim_win_get_cursor(0))
  local info = state.rows[lnum - 1]
  local c = info and col - info.pre + 1
  if not info or c < 1 or c > info.len then
    return
  end
  local struct = row_struct(buf, info)
  local other = struct and struct.partner[info.block.off + c]
  if not other then
    vim.notify("Stockholm: no pair under the cursor")
    return
  end
  for _, block in ipairs(info.block.rec.blocks) do
    if other > block.off and other <= block.off + block.len then
      local target = (block == info.block) and info or nil
      for _, r in ipairs(block.rows) do
        if not target and r.kind == info.kind and r.name == info.name then
          target = r
        end
      end
      target = target or block.rows[1]
      vim.api.nvim_win_set_cursor(0, { target.lnum + 1, target.pre + (other - block.off) - 1 })
      return
    end
  end
end

function M.redraw(buf)
  if not pcall(vim.api.nvim__redraw, { buf = buf, valid = false }) then
    vim.cmd("redraw!")
  end
end

return M
