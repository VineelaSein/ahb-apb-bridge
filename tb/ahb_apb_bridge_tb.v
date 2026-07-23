`timescale 1ns/1ps

module ahb_apb_bridge_tb;

    parameter NUM_PERIPH  = 4;
    parameter DATA_WIDTH  = 32;
    parameter ADDR_WIDTH  = 32;

    reg                     HCLK;
    reg                     HRESETn;
    reg                     HSEL;
    reg  [ADDR_WIDTH-1:0]   HADDR;
    reg                     HWRITE;
    reg  [1:0]              HTRANS;
    reg  [DATA_WIDTH-1:0]   HWDATA;
    wire [DATA_WIDTH-1:0]   HRDATA;
    wire                    HREADY;
    wire [1:0]              HRESP;

    wire [NUM_PERIPH-1:0]              PSEL;
    wire                                PENABLE;
    wire [ADDR_WIDTH-1:0]               PADDR;
    wire                                PWRITE;
    wire [DATA_WIDTH-1:0]               PWDATA;
    wire [NUM_PERIPH*DATA_WIDTH-1:0]    PRDATA_FLAT;
    wire [NUM_PERIPH-1:0]              PREADY;

    integer errors;
    reg [DATA_WIDTH-1:0] rdata;

    // ---------------- Clock generation: 100MHz (10ns period) ----------------
    initial HCLK = 0;
    always #5 HCLK = ~HCLK;

    // ---------------- DUT ----------------
    ahb_apb_bridge #(
        .NUM_PERIPH(NUM_PERIPH),
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH)
    ) dut (
        .HCLK(HCLK), .HRESETn(HRESETn),
        .HSEL(HSEL), .HADDR(HADDR), .HWRITE(HWRITE),
        .HTRANS(HTRANS), .HWDATA(HWDATA),
        .HRDATA(HRDATA), .HREADY(HREADY), .HRESP(HRESP),
        .PSEL(PSEL), .PENABLE(PENABLE), .PADDR(PADDR),
        .PWRITE(PWRITE), .PWDATA(PWDATA),
        .PRDATA_FLAT(PRDATA_FLAT), .PREADY(PREADY)
    );

    // ---------------- 4 peripheral models, each with different speed ----------------
    genvar i;
    generate
        for (i = 0; i < NUM_PERIPH; i = i + 1) begin : PERIPH
            localparam WC = (i == 1) ? 2 : (i == 2) ? 1 : 0;
            apb_peripheral_model #(
                .DATA_WIDTH(DATA_WIDTH),
                .WAIT_CYCLES(WC)
            ) u_periph (
                .PCLK(HCLK), .PRESETn(HRESETn),
                .PSEL(PSEL[i]), .PENABLE(PENABLE),
                .PADDR(PADDR), .PWRITE(PWRITE), .PWDATA(PWDATA),
                .PRDATA(PRDATA_FLAT[(i+1)*DATA_WIDTH-1 -: DATA_WIDTH]),
                .PREADY(PREADY[i])
            );
        end
    endgenerate

    // ---------------- AHB master driver task ----------------
    reg [1:0] last_hresp;

    task ahb_transfer;
        input  [ADDR_WIDTH-1:0] addr;
        input                   write;
        input  [DATA_WIDTH-1:0] wdata;
        output [DATA_WIDTH-1:0] rd;
        begin
            @(negedge HCLK);
            HSEL   = 1'b1;
            HADDR  = addr;
            HWRITE = write;
            HTRANS = 2'b10; // NONSEQ
            HWDATA = wdata;

            @(negedge HCLK); // address/data now latched by bridge (was in IDLE)
            HTRANS = 2'b00;  // drop so we don't retrigger while waiting

            while (HREADY !== 1'b1) @(negedge HCLK);

            rd         = HRDATA;
            last_hresp = HRESP;
            HSEL       = 1'b0;
        end
    endtask

    // ---------------- Stimulus ----------------
    initial begin
        $dumpfile("sim/ahb_apb_bridge.vcd");
        $dumpvars(0, ahb_apb_bridge_tb);

        errors  = 0;
        HRESETn = 0;
        HSEL    = 0;
        HADDR   = 0;
        HWRITE  = 0;
        HTRANS  = 2'b00;
        HWDATA  = 0;

        repeat (3) @(negedge HCLK);
        HRESETn = 1;

        ahb_transfer(32'h0000_0004, 1'b1, 32'hDEAD_BEEF, rdata);
        ahb_transfer(32'h0000_0004, 1'b0, 32'h0000_0000, rdata);
        if (rdata !== 32'hDEAD_BEEF) begin
            $display("FAIL: Peripheral 0 readback mismatch. Got %h, expected DEADBEEF", rdata);
            errors = errors + 1;
        end else
            $display("PASS: Peripheral 0 write/read OK (data=%h)", rdata);

        ahb_transfer(32'h0000_1008, 1'b1, 32'hCAFE_1234, rdata);
        ahb_transfer(32'h0000_1008, 1'b0, 32'h0000_0000, rdata);
        if (rdata !== 32'hCAFE_1234) begin
            $display("FAIL: Peripheral 1 readback mismatch. Got %h, expected CAFE1234", rdata);
            errors = errors + 1;
        end else
            $display("PASS: Peripheral 1 write/read OK with wait states (data=%h)", rdata);

        ahb_transfer(32'h0000_200C, 1'b1, 32'h1111_2222, rdata);
        ahb_transfer(32'h0000_200C, 1'b0, 32'h0000_0000, rdata);
        if (rdata !== 32'h1111_2222) begin
            $display("FAIL: Peripheral 2 readback mismatch. Got %h, expected 11112222", rdata);
            errors = errors + 1;
        end else
            $display("PASS: Peripheral 2 write/read OK (data=%h)", rdata);

        ahb_transfer(32'h0000_3000, 1'b1, 32'hABCD_EF01, rdata);
        ahb_transfer(32'h0000_3000, 1'b0, 32'h0000_0000, rdata);
        if (rdata !== 32'hABCD_EF01) begin
            $display("FAIL: Peripheral 3 readback mismatch. Got %h, expected ABCDEF01", rdata);
            errors = errors + 1;
        end else
            $display("PASS: Peripheral 3 write/read OK (data=%h)", rdata);

        // --- Test 5: invalid address must return HRESP=ERROR ---
        ahb_transfer(32'h0001_0000, 1'b0, 32'h0000_0000, rdata); // way outside 0x0000-0x3FFF
        if (last_hresp !== 2'b01) begin
            $display("FAIL: expected HRESP=ERROR for invalid address, got %b", last_hresp);
            errors = errors + 1;
        end else
            $display("PASS: invalid address correctly returned HRESP=ERROR");

        // --- Test 6: rapid back-to-back transactions, no extra idle gaps ---
        ahb_transfer(32'h0000_0000, 1'b1, 32'hAAAA_0000, rdata);
        ahb_transfer(32'h0000_3004, 1'b1, 32'hBBBB_0001, rdata);
        ahb_transfer(32'h0000_0000, 1'b0, 32'h0000_0000, rdata);
        if (rdata !== 32'hAAAA_0000) begin
            $display("FAIL: back-to-back P0 readback mismatch, got %h", rdata);
            errors = errors + 1;
        end
        ahb_transfer(32'h0000_3004, 1'b0, 32'h0000_0000, rdata);
        if (rdata !== 32'hBBBB_0001) begin
            $display("FAIL: back-to-back P3 readback mismatch, got %h", rdata);
            errors = errors + 1;
        end
        if (errors == 0)
            $display("PASS: back-to-back transactions with no idle gaps handled correctly");

        repeat (5) @(negedge HCLK);

        if (errors == 0)
            $display("\n===== ALL TESTS PASSED =====");
        else
            $display("\n===== %0d TEST(S) FAILED =====", errors);

        $finish;
    end

endmodule