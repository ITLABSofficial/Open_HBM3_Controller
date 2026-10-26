# Open_HBM3_Controller: Hardware Integration & Pinout Guide
**JEDEC JESD238 Standard HBM3 Memory Controller IP Core**

---

## 1. Top-Level Module Instantiation

The `hbm3_top` module implements a 16-pseudo-channel (PC) HBM3 memory controller. It accepts host requests via parallel transaction ports (or optional AXI5 bridges) and outputs standard DFI 5.0 signals to an HBM3 PHY.

### SystemVerilog Instantiation Template

```systemverilog
hbm3_top #(
    .NUM_PC      (16),     // 16 Independent Pseudo-Channels
    .ROWBITS     (16),     // 64K Rows per Bank
    .NBANK_AW    (4),      // 16 Banks per Pseudo-Channel
    .COLBITS     (6)       // 64 Columns per Row
) u_hbm3_ctrl (
    // Clock and Reset
    .clk                  (ctrl_clk_575mhz),     // DFI / Controller Core Clock
    .rst_n                (sys_rst_n),           // Active-low synchronous reset

    // Host Request Interface
    .req_valid            (host_req_valid),      // Request strobe
    .req_ready            (host_req_ready),      // Controller ready to accept command
    .req_write            (host_req_write),      // 1: Write transaction, 0: Read
    .req_addr             (host_req_addr[31:0]), // Encoded memory address
    .req_wdata            (host_req_wdata[255:0]),// 256-bit burst write data

    // Host Response Interface
    .rsp_valid            (host_rsp_valid),      // Read data valid strobe
    .rsp_rdata            (host_rsp_rdata[255:0]),// 256-bit burst read data
    .rsp_pc               (host_rsp_pc[3:0]),    // Target pseudo-channel ID
    .busy                 (ctrl_busy),           // High when queues are executing

    // SECDED ECC Telemetry
    .ecc_corrected_sticky   (ecc_corrected_flags[15:0]),   // Single-bit corrected
    .ecc_uncorrectable_sticky(ecc_uncorrectable_flags[15:0]),// Double-bit detected

    // DFI 5.0 PHY Macro Bus
    .cmd_valid            (dfi_cmd_valid),
    .cmd_type             (dfi_cmd_type[1:0]),
    .cmd_bank             (dfi_cmd_bank[3:0]),
    .cmd_row              (dfi_cmd_row[15:0]),
    .cmd_col              (dfi_cmd_col[5:0]),
    .cmd_wdata            (dfi_cmd_wdata[255:0]),
    .cmd_wdbi             (dfi_cmd_wdbi[7:0]),
    .cmd_wecc             (dfi_cmd_wecc[6:0]),
    .cmd_rdata            (dfi_phy_rdata[255:0]),
    .cmd_rdbi             (dfi_phy_rdbi[7:0]),
    .cmd_recc_stat        (dfi_phy_ecc_stat[1:0])
);
```

---

## 2. Memory Address Mapping

The controller maps the incoming 32-bit linear address into physical DRAM coordinates to maximize pseudo-channel and bank parallelism:

```
+─────────────────────────────────────────────────────────────────────────────+
|                         HBM3 ADDRESS DECODING BITFIELD                      |
|                                                                             |
|  [31:30]     [29:26]             [25:10]           [9:6]           [5:0]    |
| Reserved   Pseudo-Channel        Row Address       Bank ID      Column ID   |
|  (2 bits)     (4 bits)            (16 bits)        (4 bits)      (6 bits)   |
|                PC 0..15          65,536 Rows      16 Banks      64 Columns  |
+─────────────────────────────────────────────────────────────────────────────+
```

### Addressing Strategy
- **Bank Interleaving**: Consecutive cacheline accesses increment the `Bank ID` field, allowing multiple banks to process activate and precharge sequences in parallel without pipeline bubbles.
- **Pseudo-Channel Distribution**: Address bits `[29:26]` route traffic to one of 16 independent channel schedulers, eliminating cross-channel head-of-line blocking.

---

## 3. Voltage Regulator Specifications & Power Supply Network

The memory controller digital core operates within the digital logic power domain, with dedicated clean rails for PHY and interposer pads.

| Supply Rail | Target Voltage | Tolerance | Maximum Ripple | Nominal Power | Function |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **`VDD_CORE` (Sky130)** | **1.80 V / 1.00 V** | **$\pm 5.0\%$** | **$< 20\text{ mV}$** | **$1.42\text{ W}$** | Digital command queues, ECC, schedulers. |
| **`VDD_CORE` (7nm)** | **0.75 V** | **$\pm 3.0\%$** | **$< 12\text{ mV}$** | **$0.42\text{ W}$** | High-density predictive FinFET core. |
| **`VDD_PHY`** | **0.90 V** | **$\pm 2.5\%$** | **$< 10\text{ mV}$** | **$4.20\text{ W}$** | DFI command/address transmitter pads. |

### Decoupling Guidelines
- Place a minimum of $470\text{ nF}$ high-frequency 0201 MLCC decoupling capacitors within $500\ \mu\text{m}$ of the digital logic power ring.
- Keep voltage droop below $45\text{ mV}$ during simultaneous 16-channel read-to-write turnaround cycles.

---

## 4. Temperature-Compensated Refresh (TC-Refresh)

HBM3 DRAM cells exhibit exponential leakage current increases with rising temperature. The controller automatically tunes refresh intervals based on on-die thermal telemetry:

| Junction Temperature ($T_j$) | Refresh Mode | $t_{REFI}$ Duration | Refresh Rate Multiplier |
| :--- | :--- | :--- | :--- |
| **$T_j < 85^\circ\text{C}$** | Standard Refresh | **$3.90\ \mu\text{s}$** | **$1.0\times$ (Normal)** |
| **$85^\circ\text{C} \le T_j < 95^\circ\text{C}$** | Accelerated Refresh | **$1.95\ \mu\text{s}$** | **$2.0\times$ (Double Rate)** |
| **$95^\circ\text{C} \le T_j < 105^\circ\text{C}$** | High-Temp Refresh | **$0.975\ \mu\text{s}$** | **$4.0\times$ (Quad Rate)** |
| **$T_j \ge 105^\circ\text{C}$** | Emergency Thermal Throttle | **$0.488\ \mu\text{s}$** + Clocks Gated | **$8.0\times$ + Core Throttle** |

---

## 5. SECDED ECC Fault Handling Protocol

The controller integrates word-level **Hamming(39,32) Single Error Correction, Double Error Detection (SECDED)**:
1. **Single-Bit Fault**:
   - The hardware syndrome identifies the faulty bit position and inverts it in the output data path within 0 extra clock cycles.
   - The sticky bit `ecc_corrected_sticky[pc]` is latched high and an interrupt is raised to the host kernel driver.
2. **Double-Bit Uncorrectable Fault**:
   - The controller asserts `ecc_uncorrectable_sticky[pc]`.
   - The host is notified with an uncorrectable memory abort exception, preventing silent data corruption (SDC).
