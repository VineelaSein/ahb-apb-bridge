// =============================================================================
// Module      : apb_peripheral_model
// Description : A tiny APB slave used only for testing the bridge.
//               It's a simple 16-register memory. WAIT_CYCLES lets us
//               simulate a "slow" peripheral that inserts wait states,
//               which is exactly the scenario that stresses the bridge FSM.
// =============================================================================

module apb_peripheral_model #(
    parameter DATA_WIDTH   = 32,
    parameter WAIT_CYCLES  = 0   // 0 = always ready, >0 = adds delay before PREADY
)(
    input  wire                   PCLK,
    input  wire                   PRESETn,
    input  wire                   PSEL,
    input  wire                   PENABLE,
    input  wire [31:0]            PADDR,
    input  wire                   PWRITE,
    input  wire [DATA_WIDTH-1:0]  PWDATA,
    output reg  [DATA_WIDTH-1:0]  PRDATA,
    output reg                    PREADY
);

    reg [DATA_WIDTH-1:0] mem [0:15];
    integer wait_cnt;

    always @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            PREADY   <= 1'b0;
            PRDATA   <= {DATA_WIDTH{1'b0}};
            wait_cnt <= 0;
        end else begin
            if (PSEL && PENABLE) begin
                if (wait_cnt < WAIT_CYCLES) begin
                    PREADY   <= 1'b0;
                    wait_cnt <= wait_cnt + 1;
                end else begin
                    PREADY <= 1'b1;
                    if (PWRITE)
                        mem[PADDR[5:2]] <= PWDATA;
                    else
                        PRDATA <= mem[PADDR[5:2]];
                    wait_cnt <= 0;
                end
            end else begin
                PREADY   <= 1'b0;
                wait_cnt <= 0;
            end
        end
    end

endmodule