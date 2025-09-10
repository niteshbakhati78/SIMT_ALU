module alu_4bit (
    input logic [3:0] a, // Operand A
    input logic [3:0] b, // Operand B
    input logic [3:0] opcode, // Operation select
    output logic [3:0] result, // Output result
    output logic zero // Output zero flag (1 if result == 0)
);
    always_comb begin 
        case (opcode)
            3'b000 : result = a + b; // ADD
            3'b001 : result = a - b; // SUB
            3'b010 : result = a & b; // AND
            3'b011 : result = a | b; // OR
            3'b100 : result = a ^ b; // XOR
            3'b101 : result = (a < b) ? 4'b0001 : 4'b0000; //SLT
            3'b110 : result = a << 1; //Shift Left Logical
            3'b111 : result = a >> 1; //Shift Right Logical
            default : result = 4'b0000;
        endcase    

    
        
    end
    assign zero = (result == 4'b0000) ? 1'b1 : 1'b0; // Zero flag
    
endmodule