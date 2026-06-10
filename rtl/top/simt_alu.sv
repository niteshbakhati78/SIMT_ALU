//simt_alu.sv (Top Wrapper)
//Phase1 v1:
// - always in_ready = 1
// - out_valid mirrors in_valid
// - combinational datapath through simt_alu_core
// - out_ready unesed in v1 (added in v2 with buffering)

module simt_alu #(
    parameter int DATA_WIDTH = 32,
    parameter int LANES = 8
) (
    input  logic clk,
    input  logic rst,

    //Handshake in
    input  logic in_valid,
    output logic in_ready,

    //Handshake out
    output logic out_valid,
    input  logic out_ready,

    //Wrap instreuction inputs
    input  logic [2:0] sel,
    input  logic [LANES-1:0] lane_mask,
    input  logic [LANES-1:0][DATA_WIDTH-1:0] a,
    input  logic [LANES-1:0][DATA_WIDTH-1:0] b,

    //Wrap results outputs
    output logic [LANES-1:0][DATA_WIDTH-1:0] result,
    output logic [LANES-1:0] zero_l,
    output logic [LANES-1:0] pos_l,
    output logic [LANES-1:0] neg_l 
);

    //v1: no internal storage, so we never need to stall input
    assign in_ready = 1'b1;

    //v1: output is valid whenever input is valid
    assign out_valid = in_valid;

    //Note: out_ready is not used in v1. In v2 we will add a register/skid buffer
    //so the unit can hold results when downstream is not ready.

    // Core SIMT Computation

    simt_alu_core#(
        .DATA_WIDTH(DATA_WIDTH),
        .LANES(LANES)
    ) u_core (
        .sel(sel),
        .lane_mask(lane_mask),
        .a(a),
        .b(b),
        .result(result),
        .zero_l(zero_l),
        .pos_l(pos_l),
        .neg_l(neg_l)
    );
    
endmodule