`timescale 1ns / 1ps

module mram_controller_tb;

    // ═══════════════════════════════════════════════════════════
    // Testbench Parameters
    // ═══════════════════════════════════════════════════════════
    parameter CLK_FREQ_MHZ = 100;  // Change this to test different frequencies
    parameter CLK_PERIOD = 1000.0 / CLK_FREQ_MHZ;  // in ns
    
    // ═══════════════════════════════════════════════════════════
    // DUT Signals
    // ═══════════════════════════════════════════════════════════
    logic        clk;
    logic        rst;
    logic [15:0] wdata;
    logic [17:0] addr_in;
    logic        write_req;
    logic        read_req;
    logic        write_done;
    logic        read_done;
    logic [15:0] rdata;
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
        .read_req(read_req),
        .write_done(write_done),
        .read_done(read_done),
        .rdata(rdata),
        .e_n(e_n),
        .w_n(w_n),
        .g_n(g_n),
        .addr(addr),
        .ub_n(ub_n),
        .lb_n(lb_n),
        .dq(dq)
    );
    
    // ═══════════════════════════════════════════════════════════
    // MRAM Simulator (simple model for testbench)
    // ═══════════════════════════════════════════════════════════
    logic [15:0] mram_memory [0:262143]; // 4Mbit = 256K x 16
    logic [15:0] mram_dq_out;
    logic mram_drive;
    
    // MRAM drives DQ when reading (E# LOW, G# LOW, W# HIGH)
    assign mram_drive = (!e_n && !g_n && w_n);
    assign dq = mram_drive ? mram_dq_out : 16'hZZZZ;
    
    // MRAM behavior
    always_ff @(posedge clk) begin
        // Write to memory
        if (!e_n && !w_n) begin
            mram_memory[addr] <= dq;
        end
        
        // Read from memory
        if (!e_n && !g_n && w_n) begin
            mram_dq_out <= mram_memory[addr];
        end
    end
    
    // ═══════════════════════════════════════════════════════════
    // Test Stimulus
    // ═══════════════════════════════════════════════════════════
    initial begin

        // Initialize
        rst = 1;
        write_req = 0;
        read_req = 0;
        wdata = 16'h0000;
        addr_in = 18'h00000;
        
        $display("\n=== MRAM Controller Test @ %0d MHz ===\n", CLK_FREQ_MHZ);
        
        // Reset
        repeat(3) @(posedge clk);
        rst = 0;
        repeat(2) @(posedge clk);
        
        // ═══════════════════════════════════════════════════════
        // Test 1: Single Write
        // ═══════════════════════════════════════════════════════
        $display("TEST 1: Single Write");
        @(posedge clk);
        addr_in = 18'h12345;
        wdata = 16'hABCD;
        write_req = 1;
        @(posedge clk);
        write_req = 0;
        wait(write_done);
        repeat(2) @(posedge clk);
        
        // ═══════════════════════════════════════════════════════
        // Test 2: Single Read
        // ═══════════════════════════════════════════════════════
        $display("TEST 2: Single Read");
        @(posedge clk);
        addr_in = 18'h12345;
        read_req = 1;
        @(posedge clk);
        read_req = 0;
        wait(read_done);
        $display("Read data: 0x%04X (expected: 0xABCD)", rdata);
        repeat(2) @(posedge clk);
        
        // ═══════════════════════════════════════════════════════
        // Test 3: Write then Read sequence
        // ═══════════════════════════════════════════════════════
        $display("TEST 3: Write-Read sequence");
        
        // Write 0x1111 @ 0x00001
        @(posedge clk);
        addr_in = 18'h00001;
        wdata = 16'h1111;
        write_req = 1;
        @(posedge clk);
        write_req = 0;
        wait(write_done);
        
        // Read back
        @(posedge clk);
        addr_in = 18'h00001;
        read_req = 1;
        @(posedge clk);
        read_req = 0;
        wait(read_done);
        $display("Read data: 0x%04X (expected: 0x1111)", rdata);
        
        // ═══════════════════════════════════════════════════════
        // Test 4: Multiple consecutive reads
        // ═══════════════════════════════════════════════════════
        $display("TEST 4: Multiple reads");
        
        // Write test pattern
        for (int i = 0; i < 4; i++) begin
            @(posedge clk);
            addr_in = 18'h00100 + i;
            wdata = 16'hA000 + i;
            write_req = 1;
            @(posedge clk);
            write_req = 0;
            wait(write_done);
        end
        
        // Read back test pattern
        for (int i = 0; i < 4; i++) begin
            @(posedge clk);
            addr_in = 18'h00100 + i;
            read_req = 1;
            @(posedge clk);
            read_req = 0;
            wait(read_done);
            $display("Read[%0d]: 0x%04X (expected: 0x%04X)", i, rdata, 16'hA000 + i);
        end
        
        // ═══════════════════════════════════════════════════════
        // End
        // ═══════════════════════════════════════════════════════
        repeat(5) @(posedge clk);
        $display("\n=== Test Complete ===\n");
        $finish;
    end
    
    // Timeout
    initial begin
        #10000;
        $error("TIMEOUT");
        $finish;
    end

endmodule