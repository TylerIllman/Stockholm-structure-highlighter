-- Run with: nvim --headless -u NONE -l tests/run.lua
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(root)
vim.cmd("runtime plugin/stockholm.lua")
vim.cmd("runtime ftdetect/stockholm.lua")

local failures = 0
local function check(name, cond)
  if cond then
    print("ok   " .. name)
  else
    failures = failures + 1
    print("FAIL " .. name)
  end
end

local sto = require("stockholm")

local function parse(lines)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  return sto._parse(buf), buf
end

-- Single alignment with a plain SS_cons line.
do
  local state = parse({
    "# STOCKHOLM 1.0",
    "seqA  GGGAAACCCUU",
    "seqB  GGGAAACCCUU",
    "#=GC SS_cons <<<...>>>..",
    "//",
  })
  local rec = state.records[1]
  local struct = rec.structs["SS_cons"]
  check("one record", #state.records == 1)
  check("three pairs found", struct.npairs == 3)
  check("outermost pair partners", struct.partner[1] == 9 and struct.partner[9] == 1)
  check("innermost pair partners", struct.partner[3] == 7)
  check("one stem", struct.stem_id[1] == struct.stem_id[2] and struct.stem_id[2] == struct.stem_id[3])
end

-- Named SS_cons_* lines, several per record, and several records.
do
  local state = parse({
    "# STOCKHOLM 1.0",
    "seq1  ACGUACGU",
    "#=GC SS_cons_Rfam_X  ::::::::",
    "#=GC SS_cons_CaCoFold_X  <<..>>..",
    "//",
    "# STOCKHOLM 1.0",
    "seq2  ACGUACGU",
    "#=GC SS_cons_other  (((..)))",
    "//",
  })
  check("two records", #state.records == 2)
  check("both structure lines kept", #state.records[1].order == 2)
  check("default skips placeholder-only line", state.records[1].default == "SS_cons_CaCoFold_X")
  check("records are independent", state.records[2].structs["SS_cons_other"].npairs == 3)
end

-- Pseudoknot letters pair independently of brackets.
do
  local state = parse({
    "seq  ACGUACGUAC",
    "#=GC SS_cons  <<AA..>>aa",
  })
  local struct = state.records[1].structs["SS_cons"]
  check("pseudoknot partners", struct.partner[3] == 10 and struct.partner[4] == 9)
  check("bracket partners", struct.partner[1] == 8 and struct.partner[2] == 7)
end

-- Interleaved blocks share one global column space.
do
  local state = parse({
    "# STOCKHOLM 1.0",
    "seq  AAAA",
    "#=GC SS_cons  <<..",
    "",
    "seq  UUUU",
    "#=GC SS_cons  ..>>",
    "//",
  })
  local struct = state.records[1].structs["SS_cons"]
  check("pairs span blocks", struct.partner[1] == 8 and struct.partner[2] == 7)
  check("block offsets", state.records[1].blocks[2].off == 4)
end

-- A pair shared by several structure lines keeps one colour; pairs that differ get new ones.
do
  local state = parse({
    "seq   ACGUACGUAC",
    "#=GC SS_cons_a  <<<..>>>..",
    "#=GC SS_cons_b  <<<..>>.>.",
  })
  local rec = state.records[1]
  local colors = sto._colors_for(rec, "SS_cons_a")
  local a, b = colors["SS_cons_a"].pair, colors["SS_cons_b"].pair
  -- Pairs 2-7 and 3-6 are shared. Pair 1-8 in line a becomes 1-9 in line b.
  check("shared pair has the same colour", a[2] == b[2] and a[3] == b[3])
  check("shared pair colours match at both ends", a[2] == a[7])
  check("different pairs get different colours", a[1] ~= b[1])
  check("every pair is coloured in both lines", a[1] ~= nil and b[1] ~= nil)
  check("stem colour is the colour of its outermost pair", colors["SS_cons_b"].stem[3] == b[2])
  check("active structure is numbered first, in column order", a[1] == 1 and a[2] == 2 and a[3] == 3)

  local other = sto._colors_for(rec, "SS_cons_b")
  check("numbering follows the active structure", other["SS_cons_b"].pair[1] == 1)
  check("sharing still holds when the active line changes", other["SS_cons_a"].pair[2] == other["SS_cons_b"].pair[2])
end

-- Filetype detection.
do
  vim.cmd("enew")
  vim.cmd("file test.sto")
  vim.cmd("filetype detect")
  check("sto filetype detected", vim.bo.filetype == "stockholm")
end

-- Setup merges options.
do
  sto.setup({ color_mode = "stem", mappings = { goto_partner = "gP" } })
  check("setup overrides colour mode", sto.config.color_mode == "stem")
  check("setup keeps other mappings", sto.config.mappings.next_structure == "]s")
end

if failures > 0 then
  print(failures .. " test(s) failed")
  os.exit(1)
end
print("all tests passed")
