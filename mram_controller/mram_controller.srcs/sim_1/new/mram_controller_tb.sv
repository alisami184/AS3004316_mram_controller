`timescale 1ns / 1ps

module mram_controller_tb;

    // ═══════════════════════════════════════════════════════════
    // Testbench Parameters
    // ═══════════════════════════════════════════════════════════
    parameter CLK_FREQ_MHZ = 50;  // Change this to test different frequencies
    parameter CLK_PERIOD = 1000.0 / CLK_FREQ_MHZ;  // in ns
    
    // ═══════════════════════════════════════════════════════════
    // DUT Signals
    // ═══════════════════════════════════════════════════════════
    logic        clk;
    logic        rst;
    logic [15:0] wdata;
    logic [17:0] addr_in;
    logic        write_req;
    logic        write_done;
    logic        e_n;
    logic        w_n;
    logic        g_n;
    logic [17:0] addr;
    logic        ub_n;
    logic        lb_n;
    wire  [15:0] dq;
    
    // ═══════════════════════════════════════════════════════════
    // Clock Generation
    // ═══════════════════════════════════════════════════════════
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end
    
    // ═══════════════════════════════════════════════════════════
    // DUT Instantiation
    // ═══════════════════════════════════════════════════════════
    mram_controller #(
        .CLK_FREQ_MHZ(CLK_FREQ_MHZ)
    ) dut (
        .clk(clk),
        .rst(rst),
        .wdata(wdata),
        .addr_in(addr_in),
        .write_req(write_req),
        .write_done(write_done),
        .e_n(e_n),
        .w_n(w_n),
        .g_n(g_n),
        .addr(addr),
        .ub_n(ub_n),
        .lb_n(lb_n),
        .dq(dq)
    );
    
    // ═══════════════════════════════════════════════════════════
    // Timing Measurement Variables
    // ═══════════════════════════════════════════════════════════
    real time_w_low_start;
    real time_w_low_duration;
    real time_addr_valid_start;
    real time_cycle_start;
    real time_cycle_duration;
    real time_recovery_duration;
    

    // ═══════════════════════════════════════════════════════════
    // Test Stimulus
    // ═══════════════════════════════════════════════════════════
    initial begin
        
        // Initialize
        rst = 1;
        write_req = 0;
        wdata = 16'h0000;
        addr_in = 18'h00000;
        
        $display("\n");
        $display("╔═══════════════════════════════════════════════════╗");
        $display("║   MRAM Write Controller Testbench                ║");
        $display("║   Clock Frequency: %3d MHz                       ║", CLK_FREQ_MHZ);
        $display("║   Clock Period: %.1f ns                          ║", CLK_PERIOD);
        $display("╚═══════════════════════════════════════════════════╝");
        $display("\n");
        
        // Reset
        repeat(3) @(posedge clk);
        rst = 0;
        repeat(2) @(posedge clk);
        
        // ═══════════════════════════════════════════════════════
        // Test 1: Single Write
        // ═══════════════════════════════════════════════════════
        $display("TEST 1: Single Write Operation");
        @(posedge clk);
        addr_in = 18'h12345;
        wdata = 16'hABCD;
        write_req = 1;
        @(posedge clk);
        write_req = 0;
        
        // Wait for write to complete
        wait(write_done);
        repeat(3) @(posedge clk);
        
        // ═══════════════════════════════════════════════════════
        // Test 2: Back-to-back Writes
        // ═══════════════════════════════════════════════════════
        $display("TEST 2: Back-to-back Write Operations");
        
        @(posedge clk);
        addr_in = 18'h00001;
        wdata = 16'h1111;
        write_req = 1;
        @(posedge clk);
        write_req = 0;
        wait(write_done);
        
        @(posedge clk);
        addr_in = 18'h00002;
        wdata = 16'h2222;
        write_req = 1;
        @(posedge clk);
        write_req = 0;
        wait(write_done);
        
        @(posedge clk);
        addr_in = 18'h00003;
        wdata = 16'h3333;
        write_req = 1;
        @(posedge clk);
        write_req = 0;
        wait(write_done);
        
        // ═══════════════════════════════════════════════════════
        // Test 3: Verify signal behavior
        // ═══════════════════════════════════════════════════════
        $display("TEST 3: Verify Control Signals");
        
        @(posedge clk);
        addr_in = 18'h3FFFF;
        wdata = 16'hFFFF;
        write_req = 1;
        @(posedge clk);
        write_req = 0;
        
        // Check that G# stays HIGH during write
        fork
            begin
                wait(!write_done);
                if (g_n !== 1'b1) begin
                    $error("❌ FAIL: G# should be HIGH during write!");
                end else begin
                    $display("✓ PASS: G# is HIGH during write (output disabled)");
                end
            end
        join_none
        
        wait(write_done);
        repeat(5) @(posedge clk);
        
        // ═══════════════════════════════════════════════════════
        // End simulation
        // ═══════════════════════════════════════════════════════
        $display("\n");
        $display("╔═══════════════════════════════════════════════════╗");
        $display("║   Simulation Complete                             ║");
        $display("╚═══════════════════════════════════════════════════╝");
        $display("\n");
        
        $finish;
    end
    
    // ═══════════════════════════════════════════════════════════
    // Timeout Watchdog
    // ═══════════════════════════════════════════════════════════
    initial begin
        #10000;
        $error("❌ TIMEOUT: Simulation ran too long!");
        $finish;
    end
    
    // ═══════════════════════════════════════════════════════════
    // Monitor data bus
    // ═══════════════════════════════════════════════════════════
    always @(dq) begin
        if (dq !== 16'hZZZZ) begin
            $display("[%0t ns] DQ bus driven: 0x%04X", $realtime, dq);
        end
    end

endmodule