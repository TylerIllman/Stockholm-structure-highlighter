# Changelog

## Unreleased

- Colours are now keyed by the pair's two columns, so a pair shared by several `SS_cons*` lines in an alignment has the same colour in every line, and pairs that differ get different colours. In `stem` mode a stem takes the colour of its outermost pair. The numbering starts with the active structure line (the one under the cursor, or the default), so its pairs get the colours in order and pairs found only in other lines get new colours after them.

## 0.1.0

- Initial release: pair highlighting, stem mode, partner jump, pair readout, multiple structure lines
  per alignment, multi-alignment files, interleaved blocks and pseudoknot letters.
