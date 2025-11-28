`timescale 1ns / 1ps

module mram_controller #(
    parameter CLK_FREQ_MHZ = 50
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
    localparam int WRITE_TOTAL_CYCLES = int'($ceil(WRITE_CYCLE_NS / CLK_PERIOD_NS));

    // READ timings
    localparam real READ_G_LOW_NS  = 15.0;   // tGLQV
    localparam real READ_CYCLE_NS  = 35.0;   // tAVAV
    
    localparam int READ_G_CYCLES     = int'($ceil(READ_G_LOW_NS / CLK_PERIOD_NS));
    localparam int READ_TOTAL_CYCLES = int'($ceil(READ_CYCLE_NS / CLK_PERIOD_NS));
    

    // ═══════════════════════════════════════════════════════════
    // FSM 
    // ═══════════════════════════════════════════════════════════
    typedef enum logic [2:0] {
        IDLE       = 3'b000,  
        WRITE      = 3'b001,
        WRITE_DONE = 3'b010,
        READ       = 3'b011,
        READ_DONE  = 3'b100
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
    always_ff @(posedge clk or negedge rst) begin
        if (!rst) begin
            state <= IDLE;
            cycle_count <= '0;
            data_reg <= '0;
            addr_reg <= '0;
            rdata <= 16'h0000;
        end else begin
            case (state)
                IDLE: begin
                    cycle_count <= '0;
                    if (write_req) begin
                        data_reg <= wdata;
                        addr_reg <= addr_in;
                        state <= WRITE;
                    end
                    else if (read_req) begin
                        addr_reg <= addr_in;
                        state <= READ;
                    end
                end
                
                // ┌─────────────────────────────────────────────┐
                // │ WRITE STATE                                 │
                // │ - Cycle 0 to W_PULSE_CYCLES: W# LOW         │
                // │ - After: W# HIGH (recovery)                 │
                // │ - Total: WRITE_TOTAL_CYCLES                 │
                // └─────────────────────────────────────────────┘
                WRITE: begin
                    cycle_count <= cycle_count + 1;
                    
                    if (cycle_count >= WRITE_TOTAL_CYCLES - 1) begin
                        state <= WRITE_DONE;
                    end
                end
                
                WRITE_DONE: begin
                    if (read_req) begin
                        addr_reg <= addr_in;
                        cycle_count <= '0;
                        state <= READ;
                    end else if (write_req) begin
                        data_reg <= wdata;
                        addr_reg <= addr_in;
                        state <= WRITE;
                    end
                    else
                        state <= IDLE;
                end

                // ┌─────────────────────────────────────────────┐
                // │ READ STATE                                  │
                // │ - Cycle 0 to READ_G_CYCLES: G# LOW          │
                // │ - Capture data when stable                  │
                // │ - Total: READ_TOTAL_CYCLES                  │
                // └─────────────────────────────────────────────┘
                READ: begin
                    cycle_count <= cycle_count + 1;
                    
                    // Capture data after G# has been low
                    if (cycle_count == READ_G_CYCLES) begin
                        rdata <= dq;
                    end
                    
                    if (cycle_count >= READ_TOTAL_CYCLES - 1) begin
                        state <= READ_DONE;
                    end
                end
                
                READ_DONE: begin
                    if (write_req) begin 
                        data_reg <= wdata;
                        addr_reg <= addr_in;
                        cycle_count <= '0;
                        state <= WRITE;
                    end else if (read_req) begin
                        addr_reg <= addr_in;
                        state <= READ;
                    end else
                        state <= IDLE;
                end
            endcase
        end
    end
    
    // ═══════════════════════════════════════════════════════════
    // Output Logic
    // ═══════════════════════════════════════════════════════════
    always_comb begin
        // Defaults
        e_n = 1'b1;
        w_n = 1'b1;
        g_n = 1'b1;
        ub_n = 1'b0;  // Both bytes enabled
        lb_n = 1'b0;
        addr = addr_reg;
        drive_data = 1'b0;
        write_done = 1'b0;
        read_done = 1'b0;
        
        case (state)
            IDLE: begin
                // All signals default
            end
            
            WRITE: begin
                e_n = 1'b0;        // Chip enabled
                g_n = 1'b1;        // Output disabled
                drive_data = 1'b1; // Drive DQ bus
                
                // W# LOW for first W_PULSE_CYCLES, then HIGH
                if (cycle_count < W_PULSE_CYCLES) begin
                    w_n = 1'b0;    // Write pulse
                end else begin
                    w_n = 1'b1;    // Recovery
                end
            end
            
            WRITE_DONE: begin
                write_done = 1'b1;
            end
            
            READ: begin
                e_n = 1'b0;        // Chip enabled
                w_n = 1'b1;        // Not writing
                drive_data = 1'b0; // Don't drive DQ
                
                // G# LOW for first READ_G_CYCLES, then HIGH
                if (cycle_count < READ_G_CYCLES) begin
                    g_n = 1'b0;    // Output enabled
                end else begin
                    g_n = 1'b1;    // Output disabled
                end
            end
            
            READ_DONE: begin
                read_done = 1'b1;
            end
        endcase
    end

endmodule