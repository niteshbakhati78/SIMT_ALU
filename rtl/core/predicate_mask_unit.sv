// predicate_mask_unit.sv  (Phase 2)
// Updates the active lane mask based on a per-lane condition.
// - enable=0 : pass-through lane_mask_in
// - enable=1 : lane_mask_out = lane_mask_in & (invert ? ~cond : cond)
// - any_active indicates if any lane remains active after update

module predicate_mask_unit #(
    parameter int LANES = 8
) (
    input  logic [LANES-1:0] lane_mask_in,
    input  logic [LANES-1:0] cond,
    input  logic             invert,
    input  logic             enable,
    output logic [LANES-1:0] lane_mask_out,
    output logic             any_active
);

    logic [LANES-1:0] cond_sel;

    always_comb begin
        //Choose condition or its inverse (then-path vs else-path)
        cond_sel = invert ? ~cond : cond;

        //Apply update only when enabled

        if(enable) begin
            lane_mask_out = lane_mask_in & cond_sel;
        end
        else begin
            lane_mask_out = lane_mask_in;
        end

        //Useful later for control-flow: is this path empty?
        any_active = (lane_mask_out != '0);
    end
    
endmodule