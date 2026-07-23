# Synthesis Report — AHB-to-APB Bridge

## Tool
Yosys (open-source synthesis suite) — generic cell library (`techmap`)

## Command
```bash
yosys -s synth/synth.ys
```

## Result: Synthesizable with zero errors

## Gate-level statistics
| Cell type | Count | What it represents |
|---|---|---|
| `$_DFFE_PN0P_` (flip-flops) | 67 | Registers: `state` (2b), `addr_reg` (32b), `write_reg` (1b), `wdata_reg` (32b), `periph_sel` (2b) |
| `$_MUX_` (multiplexers) | 339 | Combinational selection logic from FSM `case` statements |
| `$_AND_` | 19 | Combinational AND logic |
| `$_OR_` | 16 | Combinational OR logic |
| `$_NOT_` | 15 | Inverters |
| `$_XOR_` | 10 | XOR logic (equality comparisons, address decode) |
| **Total cells** | **466** | |

## Interpretation
- The flip-flop count directly corresponds to the design's state-holding elements — no unexpected latches were inferred (Yosys reported "No latch inferred" for every signal during the `proc` pass), confirming clean, fully-specified combinational logic.
- The high MUX count relative to arithmetic cells reflects that this is a **control-dominated design** (FSM + decoding), not a datapath-heavy design like an ALU — an expected and defensible profile for a bus bridge.
- This is a **generic gate-level synthesis** (not mapped to a real fabrication process). Real silicon-accurate area (µm²), timing (ns), and power numbers require mapping to an actual standard-cell library — that level of physical implementation detail is covered in Project 2 (RTL-to-GDSII flow).

## Files
- `synth/synth.ys` — synthesis script
- `synth/ahb_apb_bridge_netlist.v` — generic gate-level netlist output (git-ignored, regenerate by running the script)