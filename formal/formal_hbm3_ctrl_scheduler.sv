// SPDX-License-Identifier: Apache-2.0
// Formal Verification Harness: Open_HBM3_Controller JEDEC Bank Timing & Refresh Priority Scheduler
`default_nettype none

module formal_hbm3_ctrl_scheduler (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       req_valid_i,
    input  wire       req_page_hit_i,
    input  wire       ref_due_i,
    output logic [2:0] bank_state_o,
    output logic       cmd_act_o,
    output logic       cmd_rdwr_o,
    output logic       cmd_pre_o,
    output logic       cmd_ref_o
);
    localparam [2:0] BK_IDLE    = 3'd0;
    localparam [2:0] BK_ACT_WAIT = 3'd1;
    localparam [2:0] BK_ACTIVE  = 3'd2;
    localparam [2:0] BK_PRE_WAIT = 3'd3;
    localparam [2:0] BK_REFRESH = 3'd4;

    // Scaled formal JEDEC timing counters (tRCD=3, tRP=3, tRAS=5, tRFC=4)
    logic [2:0] state;
    logic [3:0] timer;
    logic [3:0] ras_timer;

    assign bank_state_o = state;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state     <= BK_IDLE;
            timer     <= 4'd0;
            ras_timer <= 4'd0;
            cmd_act_o  <= 1'b0;
            cmd_rdwr_o <= 1'b0;
            cmd_pre_o  <= 1'b0;
            cmd_ref_o  <= 1'b0;
        end else begin
            cmd_act_o  <= 1'b0;
            cmd_rdwr_o <= 1'b0;
            cmd_pre_o  <= 1'b0;
            cmd_ref_o  <= 1'b0;

            if (timer > 4'd0) timer <= timer - 4'd1;
            if (ras_timer > 4'd0) ras_timer <= ras_timer - 4'd1;

            case (state)
                BK_IDLE: begin
                    if (ref_due_i) begin
                        state     <= BK_REFRESH;
                        timer     <= 4'd3;
                        cmd_ref_o <= 1'b1;
                    end else if (req_valid_i) begin
                        state     <= BK_ACT_WAIT;
                        timer     <= 4'd2; // tRCD guard
                        ras_timer <= 4'd4; // tRAS guard
                        cmd_act_o <= 1'b1;
                    end
                end
                BK_ACT_WAIT: begin
                    if (timer == 4'd0) begin
                        state <= BK_ACTIVE;
                    end
                end
                BK_ACTIVE: begin
                    if (ref_due_i && (ras_timer == 4'd0)) begin
                        state     <= BK_PRE_WAIT;
                        timer     <= 4'd2; // tRP guard
                        cmd_pre_o <= 1'b1;
                    end else if (req_valid_i && req_page_hit_i) begin
                        cmd_rdwr_o <= 1'b1;
                    end else if (req_valid_i && !req_page_hit_i && (ras_timer == 4'd0)) begin
                        state     <= BK_PRE_WAIT;
                        timer     <= 4'd2; // tRP guard
                        cmd_pre_o <= 1'b1;
                    end
                end
                BK_PRE_WAIT: begin
                    if (timer == 4'd0) begin
                        state <= BK_IDLE;
                    end
                end
                BK_REFRESH: begin
                    if (timer == 4'd0) begin
                        state <= BK_IDLE;
                    end
                end
                default: state <= BK_IDLE;
            endcase
        end
    end

`ifdef FORMAL
    initial assume(!rst_n);

    always @(posedge clk) begin
        if (rst_n) begin
            // Invariant 1: Command One-Hot / At-Most-One-Command per cycle on DFI bus
            assert(($countones({cmd_act_o, cmd_rdwr_o, cmd_pre_o, cmd_ref_o})) <= 1);
            // Invariant 2: Read/Write column command never issues before tRCD expires
            if (cmd_rdwr_o) begin
                assert($past(state) == BK_ACTIVE);
            end
            // Invariant 3: Precharge never violates minimum tRAS active window
            if (cmd_pre_o) begin
                assert($past(ras_timer) == 4'd0);
            end
            // Invariant 4: Refresh only launches from closed-row BK_IDLE state
            if (cmd_ref_o) begin
                assert($past(state) == BK_IDLE);
            end
        end
    end
`endif
endmodule
