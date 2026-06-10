//simd_lane_alu.sv
//One-lane ALU slice (Combinational).
//Used by the SIMT ALU core to build LANES-wide execution.
//===========================================================

module simd_lane_alu #(
    parameter int DATA_WIDTH = 32
) (
    input  logic [2:0]            sel,
    input  logic [DATA_WIDTH-1:0] in0,
    input  logic [DATA_WIDTH-1:0] in1,
    output logic                  pos,
    output logic                  neg,
    output logic                  zero,
    output logic [DATA_WIDTH-1:0] out
);

always_comb begin 
    //Defaults 
    out  = '0;
    pos  = 1'b0;
    neg  = 1'b0;
    zero = 1'b0;
    case (sel)
        3'b000: begin
            out = in0 + in1;
        end
        3'b001: begin
            out = in0 - in1;
        end 
        3'b010: begin
            out = in0 * in1;
            //MUL.LO gives low 32 bits.
            //MUL.HI gives high 32 bits.
        end
        3'b011: begin
            out = in0 & in1;
        end
        3'b100: begin
            out = in0 | in1;
        end
        3'b101: begin
            out = in0 ^ in1;
        end
        3'b110: begin
            //SLT(Set Less Than)
            //SLT is just a compare operation that outputs 1 or 0.
            out = ($signed(in0) < $signed(in1)) ? {{(DATA_WIDTH-1){1'b0}},1'b1} : '0;
            //Simpler SLT logic
            //out = ($signed(in0) < $signed(in1) ? 1 : 0)
        end

        default: out = '0;
    endcase

    //Flags from output 
    if (out == '0) begin
        zero = 1'b1;
    end
    else if (out[DATA_WIDTH-1] == 1'b0) begin
        pos = 1'b1;
    end
    else begin
        neg = 1'b1;
    end
    
end
    
endmodule