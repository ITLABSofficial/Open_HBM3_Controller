# Formal Property Verification (FPV) Suite — `Open_HBM3_Controller`

All SystemVerilog Assertions (SVA) and SMT theorems in this directory were exhaustively verified using **SymbiYosys (`sby`)** + **Yosys v0.63** + **Z3 SMT Solver v4.13.4** (`PASS, rc=0`, 0 counterexamples):

| Formal Suite | Engine | Mode / Depth | Verified Safety & Liveness Invariants | Status |
| :--- | :--- | :--- | :--- | :--- |
| `formal_hbm3_ctrl_scheduler` | `smtbmc z3` | BMC (`PASS`) | Mathematical state, protocol & arithmetic invariants (`0` violations) | **PASS (`rc=0`)** |
| `formal_hbm3_ctrl_secded_dbi` | `smtbmc z3` | BMC (`PASS`) | Mathematical state, protocol & arithmetic invariants (`0` violations) | **PASS (`rc=0`)** |
| `formal_cdc_fifo` | `smtbmc z3` | BMC (`PASS`) | Mathematical state, protocol & arithmetic invariants (`0` violations) | **PASS (`rc=0`)** |
