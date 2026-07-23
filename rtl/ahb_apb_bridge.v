// =============================================================================
// Module      : ahb_apb_bridge
// Description : AHB-Lite to APB Bridge supporting multiple APB peripherals.
//               Converts a pipelined-style AHB request into the 2-phase
//               APB protocol (SETUP -> ACCESS), inserting wait states
//               whenever the addressed peripheral is not ready (PREADY=0).
//
//               Design choice: this is a NON-PIPELINED bridge. The AHB
//               address phase and data phase are treated together for
//               simplicity (HREADY is deasserted the whole time the bridge
//               is busy talking to APB). A fully pipelined bridge would
//               allow AHB's next address phase to overlap with this
//               transaction's data phase - that's a natural "how would you
//               improve this" interview follow-up.
//
// Address map (each peripheral gets a 4KB window):
//   Peripheral 0 : 0x0000_0000 - 0x0000_0FFF
//   Peripheral 1 : 0x0000_1000 - 0x0000_1FFF
//   Peripheral 2 : 0x0000_2000 - 0x0000_2FFF
//   Peripheral 3 : 0x0000_3000 - 0x0000_3FFF
// =============================================================================

module ahb_apb_bridge #(
    parameter NUM_PERIPH  = 4,
    parameter ADDR_WIDTH  = 32,
    parameter DATA_WIDTH  = 32
)(
    // ---------------- AHB (slave) interface ----------------
    input  wire                     HCLK,
    input  wire                     HRESETn,
    input  wire                     HSEL,
    input  wire [ADDR_WIDTH-1:0]    HADDR,
    input  wire                     HWRITE,
    input  wire [1:0]               HTRANS,     // 2'b10=NONSEQ, 2'b11=SEQ (both = real transfer)
    input  wire [DATA_WIDTH-1:0]    HWDATA,
    output reg  [DATA_WIDTH-1:0]    HRDATA,
    output reg                      HREADY,
    output reg  [1:0]               HRESP,      // 2'b00 = OKAY

    // ---------------- APB (master) interface ----------------
    // Flattened buses: peripheral i occupies bits [(i+1)*WIDTH-1 : i*WIDTH]
    output reg  [NUM_PERIPH-1:0]           PSEL,
    output reg                             PENABLE,
    output reg  [ADDR_WIDTH-1:0]           PADDR,
    output reg                             PWRITE,
    output reg  [DATA_WIDTH-1:0]           PWDATA,
    input  wire [NUM_PERIPH*DATA_WIDTH-1:0] PRDATA_FLAT,
    input  wire [NUM_PERIPH-1:0]           PREADY
);

    // ---------------- FSM state encoding ----------------
    localparam IDLE   = 2'b00;
    localparam SETUP  = 2'b01;
    localparam ACCESS = 2'b10;
    localparam ERROR  = 2'b11;

    // HRESP encodings (AHB-Lite standard)
    localparam RESP_OKAY  = 2'b00;
    localparam RESP_ERROR = 2'b01;

    reg [1:0] state, next_state;

    // Latched transaction info
    reg [ADDR_WIDTH-1:0] addr_reg;
    reg                  write_reg;
    reg [DATA_WIDTH-1:0] wdata_reg;
    reg [$clog2(NUM_PERIPH)-1:0] periph_sel;

    // Is this an AHB address phase we should accept?
    wire valid_transfer = HSEL & HTRANS[1]; // covers NONSEQ(10) and SEQ(11)

    // ---------------- Address decoder ----------------
    // Top bits of HADDR pick which peripheral (4KB windows -> bits [13:12])
    function [$clog2(NUM_PERIPH)-1:0] decode_addr;
        input [ADDR_WIDTH-1:0] addr;
        begin
            decode_addr = addr[13:12]; // supports up to 4 peripherals as wired
        end
    endfunction

    // Valid range is 0x0000_0000 - 0x0000_3FFF (4 x 4KB windows = 16KB total).
    // Any address with a set bit above bit 13 is outside every peripheral's
    // window and must be rejected with an AHB ERROR response.
    function is_valid_addr;
        input [ADDR_WIDTH-1:0] addr;
        begin
            is_valid_addr = (addr[ADDR_WIDTH-1:14] == 0);
        end
    endfunction

    // ---------------- Sequential state + register update ----------------
    always @(posedge HCLK or negedge HRESETn) begin
        if (!HRESETn) begin
            state      <= IDLE;
            addr_reg   <= {ADDR_WIDTH{1'b0}};
            write_reg  <= 1'b0;
            wdata_reg  <= {DATA_WIDTH{1'b0}};
            periph_sel <= {$clog2(NUM_PERIPH){1'b0}};
        end else begin
            state <= next_state;

            // Latch the transaction the cycle we accept it in IDLE
            if (state == IDLE && valid_transfer) begin
                addr_reg   <= HADDR;
                write_reg  <= HWRITE;
                wdata_reg  <= HWDATA; // simplification: data captured with address
                periph_sel <= decode_addr(HADDR);
            end
        end
    end

    // ---------------- Next-state logic ----------------
    always @(*) begin
        next_state = state;
        case (state)
            IDLE: begin
                if (valid_transfer) begin
                    if (is_valid_addr(HADDR))
                        next_state = SETUP;
                    else
                        next_state = ERROR; // address outside all peripheral windows
                end
            end
            ERROR: begin
                next_state = IDLE; // single-cycle error response, then back to normal
            end
            SETUP: begin
                // APB rule: SETUP phase always lasts exactly one cycle
                next_state = ACCESS;
            end
            ACCESS: begin
                if (PREADY[periph_sel])
                    next_state = IDLE;   // peripheral finished -> done
                else
                    next_state = ACCESS; // peripheral not ready -> wait state
            end
            default: next_state = IDLE;
        endcase
    end

    // ---------------- Output logic ----------------
    always @(*) begin
        // Safe defaults
        PSEL    = {NUM_PERIPH{1'b0}};
        PENABLE = 1'b0;
        PADDR   = addr_reg;
        PWRITE  = write_reg;
        PWDATA  = wdata_reg;
        HREADY  = 1'b0;
        HRESP   = 2'b00;
        HRDATA  = {DATA_WIDTH{1'b0}};

        case (state)
            IDLE: begin
                HREADY = 1'b1; // bridge free, AHB can start a new transfer
            end
            SETUP: begin
                PSEL[periph_sel] = 1'b1;
                PENABLE          = 1'b0; // setup phase: PENABLE must be low
                HREADY           = 1'b0; // AHB must wait
            end
            ACCESS: begin
                PSEL[periph_sel] = 1'b1;
                PENABLE          = 1'b1; // access phase: PENABLE goes high
                if (PREADY[periph_sel]) begin
                    HREADY = 1'b1; // transaction complete this cycle
                    HRDATA = PRDATA_FLAT[(periph_sel+1)*DATA_WIDTH-1 -: DATA_WIDTH];
                end else begin
                    HREADY = 1'b0; // still waiting on peripheral
                end
            end
            ERROR: begin
                HREADY = 1'b1;         // single-cycle error, then AHB can proceed
                HRESP  = RESP_ERROR;   // tell the CPU this address was invalid
            end
        endcase
    end

endmodule