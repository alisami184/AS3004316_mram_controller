`timescale 1ns / 1ps

module mram_controller #(
    parameter CLK_FREQ_MHZ = 100
)(
    input  logic        clk,
    input  logic        rst,
    
    // Host interface
    input  logic [15:0] wdata,
    input  logic [17:0] addr_in,
    input  logic        write_req,
    input  logic        read_req,
    output logic        write_done,
    output logic        read_done,
    output logic [15:0] rdata,
    
    // MRAM pins
    output logic        e_n,
    output logic        w_n,
    output logic        g_n,
    output logic [17:0] addr,
    output logic        ub_n,
    output logic        lb_n,
    inout  logic [15:0] dq
);

    // ═══════════════════════════════════════════════════════════
    // TIMING CALCULATIONS
    // ═══════════════════════════════════════════════════════════
    localparam real CLK_PERIOD_NS = 1000.0 / CLK_FREQ_MHZ;
    
    // WRITE timings
    localparam real ADDR_TO_W_HIGH_NS = 18.0;  // tAVWH
    localparam real WRITE_CYCLE_NS    = 35.0;  // tAVAV

    localparam int W_PULSE_CYCLES = int'($ceil(ADDR_TO_W_HIGH_NS / CLK_PERIOD_NS));
    localparam int TOTAL_CYCLES = int'($ceil(WRITE_CYCLE_NS / CLK_PERIOD_NS));

    // READ timings
    localparam real READ_G_LOW_NS  = 15.0;   // tGLQV
    localparam real READ_CYCLE_NS  = 35.0;   // tAVAV
    localparam int READ_G_CYCLES     = int'($ceil(READ_G_LOW_NS / CLK_PERIOD_NS));
    localparam int READ_TOTAL_CYCLES = int'($ceil(READ_CYCLE_NS / CLK_PERIOD_NS));
    

    // ═══════════════════════════════════════════════════════════
    // FSM 
    // ═══════════════════════════════════════════════════════════
    typedef enum logic [1:0] {
        IDLE        = 2'b00,  
        WRITE_CYCLE = 2'b01, 
        READ_CYCLE  = 2'b10    
    } state_t;
    
    state_t state;
    
    // ═══════════════════════════════════════════════════════════
    // Registers
    // ═══════════════════════════════════════════════════════════
    logic [15:0] data_reg;
    logic [17:0] addr_reg;
    logic [7:0]  cycle_count;
    logic        drive_data;

    assign dq = drive_data ? data_reg : 16'hZZZZ;
    
    // ═══════════════════════════════════════════════════════════
    // FSM Sequential Logic
    // ═══════════════════════════════════════════════════════════
    always_ff @(posedge clk) begin
        if (rst) begin
            state <= IDLE;
            cycle_count <= '0;
            data_reg <= '0;
            addr_reg <= '0;
        end else begin
            case (state)
                IDLE: begin
                    if (write_req) begin
                        data_reg <= wdata;
                        addr_reg <= addr_in;
                        cycle_count <= '0;
                        state <= WRITE_CYCLE;
                    end
                    else if (read_req) begin
                        addr_reg <= addr_in;
                        cycle_count <= '0;
                        state <= READ_CYCLE;
                    end
                end
                
                WRITE_CYCLE: begin
                    cycle_count <= cycle_count + 1;
                    
                    // Complete write cycle (W# pulse + recovery)
                    if (cycle_count >= TOTAL_CYCLES - 1) begin
                        state <= IDLE;
                    end
                end

                READ_CYCLE: begin
                    cycle_count <= cycle_count + 1;
                    // Capturer data pendant que G# est LOW
                    if (cycle_count == READ_G_CYCLES - 1)
                        rdata <= dq;
                    if (cycle_count >= READ_TOTAL_CYCLES - 1) begin
                        state <= IDLE;
                    end
                end
            endcase
        end
    end
    
    // ═══════════════════════════════════════════════════════════
    // Output Logic - THE CRITICAL PART
    // ═══════════════════════════════════════════════════════════
    always_comb begin
        // Defaults
        e_n = 1'b1;
        w_n = 1'b1;
        g_n = 1'b1;
        ub_n = 1'b0;
        lb_n = 1'b0;
        addr = addr_reg;
        drive_data = 1'b0;
        write_done = 1'b0;
        read_done = 1'b0;
        
        case (state)
            IDLE: begin
                write_done = 1'b1;
                read_done  = 1'b1;
            end
            
            WRITE_CYCLE: begin
                // ┌─────────────────────────────────────────────┐
                // │ Phase 1: W# LOW (write pulse)               │
                // │ Duration: tAVWH = 18ns minimum              │
                // │ - Address valid from cycle 0                │
                // │ - Data valid from cycle 0                   │
                // │ - E# LOW to enable chip                     │
                // │ - W# LOW to write                           │
                // │ - G# HIGH (output disabled for write)       │
                // └─────────────────────────────────────────────┘
                if (cycle_count < W_PULSE_CYCLES) begin
                    e_n = 1'b0;        // Chip enabled
                    w_n = 1'b0;        // ⚡ WRITE ACTIVE
                    g_n = 1'b1;        // Output disabled
                    drive_data = 1'b1; // Drive DQ bus with write data
                end
                // ┌─────────────────────────────────────────────┐
                // │ Phase 2: W# HIGH (recovery)                 │
                // │ Duration: tWHAX = 12ns minimum              │
                // │ Plus extra time to meet tAVAV = 35ns total  │
                // │ - Address still valid (tWHAX requirement)   │
                // │ - Data held stable (tWHDX = 0ns OK)         │
                // │ - E# can stay LOW or go HIGH                │
                // │ - W# HIGH (write complete)                  │
                // └─────────────────────────────────────────────┘
                else begin
                    e_n = 1'b1;        // Keep chip enabled
                    w_n = 1'b1;        // Write complete
                    g_n = 1'b1;        // Output still disabled
                    drive_data = 1'b1; // Hold data stable (tWHDX=0 but good practice)
                end
            end
            READ_CYCLE: begin
                if (cycle_count < READ_G_CYCLES) begin
                    e_n = 1'b0;        // Chip enabled
                    w_n = 1'b1;        // Not writing
                    g_n = 1'b0;        // ⚡ READ ACTIVE
                    drive_data = 1'b0; // Do not drive DQ bus
                end
                else begin
                    e_n = 1'b1;        
                    w_n = 1'b1;        
                    g_n = 1'b1;        // Read complete
                    drive_data = 1'b0; 
                end
            end
        endcase
    end

endmodule
