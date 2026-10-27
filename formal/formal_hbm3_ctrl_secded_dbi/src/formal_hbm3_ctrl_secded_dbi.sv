// SPDX-License-Identifier: Apache-2.0
// Formal Verification Harness: Open_HBM3_Controller Hamming(39,32) SECDED ECC & Byte-Level DBI
`default_nettype none

module formal_hbm3_ctrl_secded_dbi (
    input  wire [31:0] data_in_i,
    input  wire [5:0]  err_bit_idx_i,
    input  wire        inject_sbe_i,
    output wire [38:0] code_out_o,
    output wire [31:0] data_corr_o,
    output wire        sec_flag_o,
    output wire        ded_flag_o,
    output wire [31:0] dbi_roundtrip_o
);
    function automatic [3:0] pop8(input [7:0] x);
        pop8 = {3'd0, x[0]} + {3'd0, x[1]} + {3'd0, x[2]} + {3'd0, x[3]} +
               {3'd0, x[4]} + {3'd0, x[5]} + {3'd0, x[6]} + {3'd0, x[7]};
    endfunction

    // Byte-level Data Bus Inversion (DBI) Encoder & Decoder
    logic [31:0] dbi_wire;
    logic [3:0]  dbi_flag;
    always_comb begin
        for (int b = 0; b < 4; b++) begin
            if (pop8(data_in_i[b*8 +: 8]) > 4'd4) begin
                dbi_wire[b*8 +: 8] = ~data_in_i[b*8 +: 8];
                dbi_flag[b]        = 1'b1;
            end else begin
                dbi_wire[b*8 +: 8] = data_in_i[b*8 +: 8];
                dbi_flag[b]        = 1'b0;
            end
        end
    end
    assign dbi_roundtrip_o = {
        dbi_flag[3] ? ~dbi_wire[31:24] : dbi_wire[31:24],
        dbi_flag[2] ? ~dbi_wire[23:16] : dbi_wire[23:16],
        dbi_flag[1] ? ~dbi_wire[15:8]  : dbi_wire[15:8],
        dbi_flag[0] ? ~dbi_wire[7:0]   : dbi_wire[7:0]
    };

    // Systematic Hamming(39,32) SECDED Parity Generator
    wire p0 = ^(data_in_i & 32'h56AA_AD5B);
    wire p1 = ^(data_in_i & 32'h9B33_366D);
    wire p2 = ^(data_in_i & 32'hE3C3_C78E);
    wire p3 = ^(data_in_i & 32'h03FC_07F0);
    wire p4 = ^(data_in_i & 32'h03FF_F800);
    wire p5 = ^(data_in_i & 32'hFC00_0000);
    wire [37:0] cw38 = {p5, p4, p3, p2, p1, p0, data_in_i};
    wire p_all = ^cw38;
    assign code_out_o = {p_all, cw38};

    // Channel error injection (0 or 1 bit flip on 32-bit data payload)
    wire [31:0] rx_data = (inject_sbe_i && (err_bit_idx_i < 6'd32)) ?
                          (data_in_i ^ (32'd1 << err_bit_idx_i[4:0])) : data_in_i;
    wire [38:0] rx_code = {p_all, p5, p4, p3, p2, p1, p0, rx_data};

    // Syndrome computation
    wire [5:0] synd = {
        ^(rx_code[31:0] & 32'hFC00_0000) ^ rx_code[37],
        ^(rx_code[31:0] & 32'h03FF_F800) ^ rx_code[36],
        ^(rx_code[31:0] & 32'h03FC_07F0) ^ rx_code[35],
        ^(rx_code[31:0] & 32'hE3C3_C78E) ^ rx_code[34],
        ^(rx_code[31:0] & 32'h9B33_366D) ^ rx_code[33],
        ^(rx_code[31:0] & 32'h56AA_AD5B) ^ rx_code[32]
    };
    wire overall_err = ^rx_code;

    assign sec_flag_o = (synd != 6'd0) && overall_err;
    assign ded_flag_o = (synd != 6'd0) && !overall_err;

    localparam [31:0] H_M0 = 32'h56AA_AD5B;
    localparam [31:0] H_M1 = 32'h9B33_366D;
    localparam [31:0] H_M2 = 32'hE3C3_C78E;
    localparam [31:0] H_M3 = 32'h03FC_07F0;
    localparam [31:0] H_M4 = 32'h03FF_F800;
    localparam [31:0] H_M5 = 32'hFC00_0000;

    // Decode unique 1-bit error masks for all 32 data positions
    logic [31:0] corr_mask;
    always_comb begin
        corr_mask = 32'd0;
        for (int i = 0; i < 32; i++) begin
            logic [5:0] col_sig;
            col_sig = {H_M5[i], H_M4[i], H_M3[i], H_M2[i], H_M1[i], H_M0[i]};
            if (overall_err && (synd == col_sig)) begin
                corr_mask[i] = 1'b1;
            end
        end
    end

    assign data_corr_o = rx_data ^ corr_mask;

`ifdef FORMAL
    always_comb begin
        // Theorem 1: Byte-Level DBI guarantees <= 4 ones per transmitted byte on TSV bus
        assert(pop8(dbi_wire[7:0])   <= 4'd4);
        assert(pop8(dbi_wire[15:8])  <= 4'd4);
        assert(pop8(dbi_wire[23:16]) <= 4'd4);
        assert(pop8(dbi_wire[31:24]) <= 4'd4);

        // Theorem 2: DBI encode-decode roundtrip is 100% lossless for all 2^32 words
        assert(dbi_roundtrip_o == data_in_i);

        // Theorem 3: Zero-error and single-bit error (SBE) are 100% corrected to exact data_in_i
        if (!inject_sbe_i) begin
            assert(data_corr_o == data_in_i);
            assert(!sec_flag_o && !ded_flag_o);
        end else if (err_bit_idx_i < 6'd32) begin
            assert(data_corr_o == data_in_i);
            assert(sec_flag_o && !ded_flag_o);
        end
    end
`endif
endmodule
