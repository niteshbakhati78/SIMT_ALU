`timescale 1ns/1ps

module tb_exec_mask_update #(
    parameter int NUM_TESTS = 10000,
    parameter int DATA_WIDTH = 32,
    parameter int LANES = 8
);

    // PHASE A: Clock/ Reset Generation

    logic clk = 1'b0;
    initial begin : generate_clock
        forever #5 clk <= ~clk;
    end

    //PHASE B : DUT Interface Signals
    // Tip: Name these exactly like DUT ports so you can use "DUT(.*)".

    logic rst;
    logic in_valid;
    logic in_ready;
    logic out_valid;
    logic out_ready;
    logic [2:0] sel;
    logic [LANES-1:0] lane_mask_in;
    logic [LANES-1:0][DATA_WIDTH-1:0] a,b;
    logic mask_enable;
    logic invert;
    logic [LANES-1:0][DATA_WIDTH-1:0] result;
    logic [LANES-1:0] zero_l, pos_l, neg_l;
    logic [LANES-1:0] cond;
    logic done;


    //PHASE C : Expected / Scoreboard Storage
    // We compute expected values in MONITOR and store them here.
    // CHECKER compares DUT outputs against these expected values later.

    logic [LANES-1:0] lane_mask_next;
    logic [LANES-1:0] any_active_next;

    //PHASE D : Instantiate DUT
    // Tip: Use .* only if your TB signal names match DUT port names exactly.

    simt_exec_mask_update #(
        .DATA_WIDTH(DATA_WIDTH),
        .LANES(LANES)
    ) DUT (
        .clk(clk),
        .rst(rst),
        .in_valid(in_valid),
        .in_ready(in_ready),
        .out_valid(out_valid),
        .out_ready(out_ready),
        .sel(sel),
        .lane_mask_in(lane_mask_in),
        .a(a),
        .b(b),
        .mask_enable(mask_enable),
        .invert(invert),
        .result(result),
        .zero_l(zero_l),
        .pos_l(pos_l),
        .neg_l(neg_l),
        .cond(cond),
        .lane_mask_next(lane_mask_next),
        .any_active_next(any_active_next)
    );


    //PHASE E : Reference Model Functions (Golden Model)
    // Rule of thumb:
    //  - Keep the golden model SIMPLE and obviously correct.
    //  - Do not copy/paste DUT RTL into the model (that can hide bugs).

    function automatic logic lane_slt(
        input logic [DATA_WIDTH-1:0] x,
        input logic [DATA_WIDTH-1:0] y
    );
        return ($signed(x) < $signed(y));
        
    endfunction


    //PHASE F: Stimulus Driver
    // Responsibilities:
    //  1) Apply reset sequence.
    //  2) Drive randomized transactions.
    //  3) Control in_valid/out_ready.
    //

    initial begin : stimulus
        //defaults
        rst <= 1'b0;
        in_valid <= 1'b0;
        out_valid <= 1'b0;
        sel <= 3'b110;
        lane_mask_in <= '0;
        a <= '0;
        b <= '0;
        mask_enable <= 1'b0; 
        invert <= 1'b0;
        done  <= 1'b0;   

        void'($urandom(32'hFACECAFE));

        // RESET (OPTIONAL)
        repeat (2) @(posedge clk);
        rst <= 1'b1;
        @(posedge clk);
        rst <= 1'b0;

        $display("PHASE 2.5: Starting %0d randomized tests...", NUM_TESTS);
        for (int t = 0 ; t < NUM_TESTS ; t++ ) begin
            @(negedge clk);
            //Force SLT for this phase
            sel <= 3'b110;

            lane_mask_in <= $urandom();
            mask_enable  <= $urandom_range(0,1);
            invert <= $urandom_range(0,1);

            for ( int i = 0 ; i < LANES ; i++ ) begin
                a[i] <= $urandom();
                b[i] <= $urandom();
            end

            in_valid <= 1'b1;

            @(negedge clk);
            in_valid <= 1'b0;
            if((t % 1000) == 0) $display(" ...%0d/%0d driven", t, NUM_TESTS);
        end

        @(negedge clk);
        done <= 1'b1;
        $display("PHASE 2.5: Stimulus completed.");
    end

    //PHASE G : Monitor / Expected Computation
    // Responsibilities:
    //  1) Observe inputs used for a transaction.
    //  2) Compute expected outputs using the reference model.
    //  3) Store results into exp_* variables for the checker.



    //PHASE H : Checker 
    // Responsibilities:
    //  1) Compare DUT outputs against exp_*.
    //  2) Use !== to catch X/Z mismatches.
    //  3) Stop early if too many errors.
    //
    // For future phases:
    //  - Keep this structure; only replace what you compare.
    initial begin : check_outputs
        int errors = 0;
        int checks = 0;
        @(posedge clk);

        forever begin
            @(posedge clk);

            if (in_valid) begin
                logic [LANES-1:0] cond_true;
                logic [LANES-1:0] exp_mask_next;
                logic [LANES-1:0] exp_any_active;

                //Build "true" condition per lane (only meaningful for active lanes)
                for (int i = 0 ; i < LANES ; i++ ) begin
                    cond_true[i] = (lane_mask_in[i]) ? lane_slt(a[i], b[i]) : 1'b0;
                end

                //Expected next mask
                if(mask_enable) begin
                    exp_mask_next = lane_mask_in & (invert ? ~cond_true : cond_true);
                end
                else begin
                    exp_mask_next = lane_mask_in;
                end
                exp_any_active = (exp_mask_next != '0);
                checks++;

                //Check lane_mask_next and any_active_next
                if (lane_mask_next !== exp_mask_next) begin
                    $error("MASK_NEXT mismatch: exp=%b got=%b | mask_in=%b cond_true=%b inv=%0d en=%0d",exp_mask_next, lane_mask_next, lane_mask_in, cond_true, invert, mask_enable);
                    errors++;
                end
                if (any_active_next !== exp_any_active) begin
                    $error("ANY_ACTIVE_NEXT mismatch: exp=%b got=%b | mask_next=%b",exp_any_active, any_active_next, lane_mask_next);
                    errors++;
                end
                // Optional: check cond for active lanes only
                for (int i = 0; i < LANES; i++) begin
                    if (lane_mask_in[i]) begin
                        if (cond[i] !== cond_true[i]) begin
                            $error("COND mismatch lane %0d: exp=%b got=%b | a=%h b=%h",i, cond_true[i], cond[i], a[i], b[i]);
                            errors++;
                        end
                    end
                end
            end
            if (done) begin
                $display("====================================");
                $display("PHASE 2.5 SUMMARY");
                $display("  Checks run : %0d", checks);
                $display("  Errors     : %0d", errors);
                if (errors == 0) $display("  RESULT     : PASS");
                else             $display("  RESULT     : FAIL");
                $display("====================================");
                $finish;
            end
        end
    end
    
    
endmodule