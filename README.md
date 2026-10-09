# AMBA AHB-to-APB Bridge

A parameterized AHB-Lite to APB bridge supporting 4 independent APB peripherals with address decoding, wait-state handling, and AHB ERROR responses for invalid addresses.

## Why this project

Every SoC (System-on-Chip) needs a way to connect its fast CPU bus (AHB) to slower peripheral buses (APB) — UART, GPIO, timers, and similar low-bandwidth devices don't need (and shouldn't pay the silicon cost for) a high-performance bus interface. This bridge is exactly that translation layer, built and verified the way a real IP block would be.

## System context
CPU (AHB master)
          │  AHB
          ▼
  AHB-to-APB bridge
   ┌──────┼──────┬──────┐
   │  APB │      │      │
   ▼      ▼      ▼      ▼

   Periph0 Periph1 Periph2 Periph3
   (fast) (2 wait) (1 wait) (fast)


   ## Architecture: the FSM

The bridge is a 4-state machine:

| State | What happens |
|---|---|
| `IDLE` | Bridge is free (`HREADY=1`). Watches for a valid AHB request. |
| `SETUP` | APB's mandatory 1-cycle "get ready" phase — `PSEL` asserted, `PENABLE` still low. |
| `ACCESS` | `PENABLE` goes high. Holds here (inserting wait states) until the peripheral asserts `PREADY`. |
| `ERROR` | Entered if the address doesn't belong to any peripheral. Returns `HRESP=ERROR` for one cycle. |

`ACCESS` loops on itself for as many cycles as the peripheral needs (a wait state), only advancing once `PREADY=1`.

## Address map

| Peripheral | Range | Notes |
|---|---|---|
| 0 | `0x0000_0000`–`0x0000_0FFF` | fast, 0 wait states |
| 1 | `0x0000_1000`–`0x0000_1FFF` | 2 wait states (stresses the FSM hold behavior) |
| 2 | `0x0000_2000`–`0x0000_2FFF` | 1 wait state |
| 3 | `0x0000_3000`–`0x0000_3FFF` | fast, 0 wait states |
| anything else | — | rejected with `HRESP=ERROR` |

## How to run

\`\`\`bash
iverilog -o sim/bridge_sim.vvp rtl/ahb_apb_bridge.v tb/apb_peripheral_model.v tb/ahb_apb_bridge_tb.v
vvp sim/bridge_sim.vvp
\`\`\`

Expected: 6/6 tests pass. View the waveform with GTKWave or the WaveTrace extension on `sim/ahb_apb_bridge.vcd`.

## Synthesis

Synthesized cleanly with Yosys (zero errors): 466 cells total — 67 flip-flops, 339 multiplexers, remainder combinational glue logic. No inferred latches. Full breakdown in `docs/SYNTHESIS_REPORT.md`.

## Key design decisions 

- **Non-pipelined bridge**: address and data phases captured together for simplicity — `HREADY` held low for the full APB transaction rather than overlapping with the next AHB address phase.
- **Flattened `PRDATA`/`PREADY` buses**: multi-peripheral buses flattened into one wide bus, indexed with part-select (`-:`) — the standard approach real interconnect RTL uses.
- **Single-cycle ERROR response**: a fully spec-compliant error response takes 2 cycles; this simplifies to 1, documented as a known tradeoff.
