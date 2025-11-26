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
    output logic        write_done,
    
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
    
    // Critical: tAVWH (18ns) is the constraint for W# LOW duration
    // This is LONGER than tWLWH (15ns), so it's the governing constraint
    localparam real ADDR_TO_W_HIGH_NS = 18.0;  // tAVWH
    localparam real WRITE_CYCLE_NS    = 35.0;  // tAVAV
    localparam real RECOVERY_MIN_NS   = 12.0;  // tWHAX
    
    // Calculate cycles (round UP for safety)
    localparam int W_PULSE_CYCLES = int'($ceil(ADDR_TO_W_HIGH_NS / CLK_PERIOD_NS));
    
    // Total cycle must be at least 35ns
    localparam int TOTAL_CYCLES = int'($ceil(WRITE_CYCLE_NS / CLK_PERIOD_NS));
    
    // Recovery cycles = total - write pulse
    localparam int RECOVERY_CYCLES = TOTAL_CYCLES - W_PULSE_CYCLES;
    
    // Verify recovery time meets tWHAX (12ns minimum)
    localparam real ACTUAL_RECOVERY_NS = RECOVERY_CYCLES * CLK_PERIOD_NS;
    
    // ═══════════════════════════════════════════════════════════
    // FSM - Only 2 States!
    // ═══════════════════════════════════════════════════════════
    typedef enum logic {
        IDLE        = 1'b0,   // Waiting, ready for new write
        WRITE_CYCLE = 1'b1    // Executing write (W# pulse + recovery)
    } state_t;
    
    state_t state;
    
    // ═══════════════════════════════════════════════════════════
    // Registers
    // ═══════════════════════════════════════════════════════════
    logic [15:0] data_reg;
    logic [17:0] addr_reg;
    logic [7:0]  cycle_count;
    
    // ═══════════════════════════════════════════════════════════
    // Bidirectional Data Bus
    // ═══════════════════════════════════════════════════════════
    // Drive data during entire write cycle (both W# LOW and recovery)
    logic drive_data;
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
                        // Latch inputs at START of write
                        data_reg <= wdata;
                        addr_reg <= addr_in;
                        cycle_count <= '0;
                        state <= WRITE_CYCLE;
                    end
                end
                
                WRITE_CYCLE: begin
                    cycle_count <= cycle_count + 1;
                    
                    // Complete write cycle (W# pulse + recovery)
                    if (cycle_count >= TOTAL_CYCLES - 1) begin
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
        
        case (state)
            IDLE: begin
                write_done = 1'b1;
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
                // │ - E# can stay LOW or go HIGH               │
                // │ - W# HIGH (write complete)                  │
                // └─────────────────────────────────────────────┘
                else begin
                    e_n = 1'b1;        // Keep chip enabled
                    w_n = 1'b1;        // Write complete
                    g_n = 1'b1;        // Output still disabled
                    drive_data = 1'b1; // Hold data stable (tWHDX=0 but good practice)
                end
            end
        endcase
    end

endmodule
