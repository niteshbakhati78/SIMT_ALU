module alu_4bit_tb;
    logic [3:0] a,b;
    logic [2:0] opcode;
    logic [3:0] result;
    logic zero;
    alu_4bit dut (
        .a(a), 
        .b(b),
        .opcode(opcode),
        .result(result),
        .zero(zero)
    );
    initial begin
        // Initialize test values
        a = 4'b0101; // 5
        b = 4'b0011; // 3
        $display("Time\tOpcode\tA\tB\tResult\tZero");
        opcode = 3'b000; #10; $display("%0t\tADD\t%b\t%b\t%b\t%b", $time, a, b, result, zero);
        opcode = 3'b001; #10; $display("%0t\tADD\t%b\t%b\t%b\t%b", $time, a, b, result, zero);
        opcode = 3'b010; #10; $display("%0t\tADD\t%b\t%b\t%b\t%b", $time, a, b, result, zero);
        opcode = 3'b011; #10; $display("%0t\tADD\t%b\t%b\t%b\t%b", $time, a, b, result, zero);
        opcode = 3'b100; #10; $display("%0t\tADD\t%b\t%b\t%b\t%b", $time, a, b, result, zero);
        opcode = 3'b101; #10; $display("%0t\tADD\t%b\t%b\t%b\t%b", $time, a, b, result, zero);
        opcode = 3'b110; #10; $display("%0t\tADD\t%b\t%b\t%b\t%b", $time, a, b, result, zero);
        opcode = 3'b111; #10; $display("%0t\tADD\t%b\t%b\t%b\t%b", $time, a, b, result, zero);

        $finish;
    end    



    
endmodule