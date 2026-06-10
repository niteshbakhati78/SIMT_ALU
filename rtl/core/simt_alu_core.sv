//simt_alu_core.sv
//Core SIMT datapath:
// - Instantiates one ALU per lane
// - Applies predication via lane_mask
// - Computes per-lane flages (zero_l for v1)

module simt_alu_core #(
    parameter int DATA_WIDTH = 32,
    parameter int LANES = 8
) (
    // Control
    input  logic [2:0]                       sel,
    input  logic [LANES-1:0]                 lane_mask,
    // Operands (per lane)
    input  logic [LANES-1:0][DATA_WIDTH-1:0] a,
    input  logic [LANES-1:0][DATA_WIDTH-1:0] b,
    // Result (per lane)
    output logic [LANES-1:0][DATA_WIDTH-1:0] result,
    //Flags (per lane)
    output logic [LANES-1:0]                 zero_l,
    output logic [LANES-1:0]                 pos_l,
    output logic [LANES-1:0]                 neg_l
);
    //STEP1: Wires from the raw lane ALUs (before prediction)
    logic [LANES-1:0][DATA_WIDTH-1:0] lane_out;
    logic [LANES-1:0]                 lane_zero,lane_pos,lane_neg;
    //STEP2: Instantiate one ALU per lane
    genvar gi;
    generate
        for (gi = 0; gi < LANES; gi++ ) begin : GEN_LANES
            simd_lane_alu #(
                .DATA_WIDTH(DATA_WIDTH)
            ) u_lane_alu (
                .in0(a[gi]),
                .in1(b[gi]),
                .sel(sel),
                .out(lane_out[gi]),
                .zero(lane_zero[gi]),
                .pos(lane_pos[gi]),
                .neg(lane_neg[gi])
            );
        end
    endgenerate

    //STEP3: Apply SIMT prediction at the architectural output
    // Active lane -> take lane ALU output + flags
    // Inactive lane -> pass-through a + flags from a

    always_comb begin
        for (int i = 0 ;i < LANES ; i++ ) begin
            if (lane_mask[i]) begin
                //Active lane: commit ALU result
                result[i] = lane_out[i];
                zero_l[i] = lane_zero[i];
                pos_l[i]  = lane_pos[i];
                neg_l[i]  = lane_neg[i];
            end
            else begin
                //Inactive lane: "no write" behavior as pass-through
                result[i] = a[i];
                //Flags must match pass-through value (architectural result)
                zero_l[i] = (a[i] == '0);
                pos_l[i]  = (a[i] != '0) && (a[i][DATA_WIDTH-1] == 1'b0);
                neg_l[i]  = (a[i][DATA_WIDTH-1] == 1'b1);
            end
        end
    end
    
endmodule