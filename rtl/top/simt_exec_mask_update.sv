// simt_exec_mask_update.sv  (Phase 2.5)
// Composition block: Phase 1 (SIMT ALU) + Phase 2 (Predicate Mask Unit)
// - Executes an instruction using simt_alu with lane_mask_in
// - Extracts per-lane condition bits from SLT result: cond[i] = result[i][0]
// - Computes next lane mask using predicate_mask_unit
//
// This is the first "execution-driven control-flow" datapath:
//   (a,b,mask) -> execute compare -> cond[] -> compute mask_next

module simt_exec_mask_update #(
    parameter int DATA_WIDTH = 32,
    parameter int LANES = 8
) (
    input  logic                             clk,
    input  logic                             rst,
    //"Transaction" control (keep consistant with Phase 1 wrapper)
    input  logic                             in_valid,
    output logic                             in_ready, // Simple pass-through for now
    output logic                             out_valid,
    input  logic                             out_ready, // Not used in V1(Kept for future use) 
    //Execute control
    input  logic [2:0]                       sel,
    input  logic [LANES-1:0]                 lane_mask_in,
    //Operands
    input  logic [LANES-1:0][DATA_WIDTH-1:0] a,
    input  logic [LANES-1:0][DATA_WIDTH-1:0] b,
    //Mask update control
    input  logic                             mask_enable, //enable mask update
    input  logic                             invert, //0: then-path, 1:else-path
    //Outputs
    output logic [LANES-1:0][DATA_WIDTH-1:0] result,
    output logic [LANES-1:0]                 zero_l,
    output logic [LANES-1:0]                 pos_l,
    output logic [LANES-1:0]                 neg_l,
    output logic [LANES-1:0]                 cond, //extracted condition bits
    output logic [LANES-1:0]                 lane_mask_next,
    output logic                             any_active_next
);

    //Phase 1: Execute
    // We assume simt_alu wrapper has these ports:
    //   clk, rst, in_valid, in_ready, out_valid, out_ready, sel, lane_mask, a, b, result, zero_l, pos_l, neg_l
    simt_alu #(
        .DATA_WIDTH(DATA_WIDTH),
        .LANES(LANES)
    ) U_EXEC (
        .clk(clk),
        .rst(rst),
        .in_valid(in_valid),
        .in_ready(in_ready),
        .out_valid(out_valid),
        .out_ready(out_ready),
        .sel(sel),
        .lane_mask(lane_mask_in),
        .a(a),
        .b(b),
        .result(result),
        .zero_l(zero_l),
        .pos_l(pos_l),
        .neg_l(neg_l)
    );

    // Condition extraction (Phase 2.5 glue)
    // For SLT, each lane result is either 0...0 or 0...1
    // We treat bit0 as the condition boolean.

    always_comb begin 
        for (int i = 0 ; i < LANES ; i++ ) begin
            cond[i] = (sel == 3'b110) ? result[i][0] : 1'b0;
        end
    end

    //Gate PMU update to "real" transactions.
    logic pmu_en;
    assign pmu_en = mask_enable & out_valid;

    // Phase 2: Mask update
    // Compute next mask from current mask and condition vector.

    predicate_mask_unit #(
        .LANES(LANES)
    ) U_PMU (
        .lane_mask_in(lane_mask_in),
        .cond(cond),
        .invert(invert),
        .enable(pmu_en),
        .lane_mask_out(lane_mask_next),
        .any_active(any_active_next)
    );
    
    
endmodule