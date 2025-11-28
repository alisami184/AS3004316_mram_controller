`timescale 1ns / 1ps

module mram_controller_tb;

    // ═══════════════════════════════════════════════════════════
    // Testbench Parameters
    // ═══════════════════════════════════════════════════════════
    parameter CLK_FREQ_MHZ = 50;
    parameter CLK_PERIOD = 1000.0 / CLK_FREQ_MHZ;
    
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
    // MRAM Simulator - SIMPLE et ROBUSTE
    // ═══════════════════════════════════════════════════════════
    logic [15:0] mram_memory [0:262143];
    logic [15:0] mram_dq_out;
    logic        read_active = 0;  // Initialize to 0
    
    // Initialize memory to prevent X
    initial begin
        for (int i = 0; i < 262144; i++) begin
            mram_memory[i] = 16'h0000;
        end
    end
    
    // Latch read_active au début du read, clear au début du write
    always @(negedge g_n or negedge w_n or negedge rst) begin
        if (!rst) begin
            read_active <= 0;
        end
        else if (!w_n) begin
            // Write commence - libère le bus
            read_active <= 0;
        end
        else if (!e_n && !g_n && w_n) begin
            // Read commence - active le bus
            read_active <= 1;
            mram_dq_out <= mram_memory[addr];
            $display("[MRAM] Read: addr=0x%05h → data=0x%04h", addr, mram_memory[addr]);
        end
    end
    
    // Bus DQ piloté par read_active (INDÉPENDANT de e_n/g_n/w_n!)
    assign dq = read_active ? mram_dq_out : 16'hZZZZ;
    
    // Write: capture sur front montant de W#
    always @(posedge w_n) begin
        if (!e_n) begin
            mram_memory[addr] <= dq;
            $display("[MRAM] Write: addr=0x%05h ← data=0x%04h", addr, dq);
        end
    end
    
    // ═══════════════════════════════════════════════════════════
    // Test Stimulus
    // ═══════════════════════════════════════════════════════════
    initial begin
        // Initialize
        rst = 0;
        write_req = 0;
        read_req = 0;
        wdata = 16'h0000;
        addr_in = 18'h00000;
        
        $display("\n=== MRAM Controller Test @ %0d MHz ===\n", CLK_FREQ_MHZ);
        
        // Reset
        repeat(3) @(posedge clk);
        rst = 1;
        repeat(2) @(posedge clk);
        
        // TEST 1: Single Write
        $display("TEST 1: Single Write");
        @(posedge clk);
        addr_in = 18'h12345;
        wdata = 16'hABCD;
        write_req = 1;
        @(posedge clk);
        write_req = 0;
        wait(write_done);
        repeat(2) @(posedge clk);
        
        // TEST 2: Single Read
        $display("TEST 2: Single Read");
        @(posedge clk);
        addr_in = 18'h12345;
        read_req = 1;
        @(posedge clk);
        read_req = 0;
        wait(read_done);
        $display("Read data: 0x%04X (expected: 0xABCD)", rdata);
        repeat(2) @(posedge clk);
        
        // TEST 3: Write-Read sequence
        $display("TEST 3: Write-Read sequence");
        @(posedge clk);
        addr_in = 18'h00001;
        wdata = 16'h1111;
        write_req = 1;
        @(posedge clk);
        write_req = 0;
        wait(write_done);
        
        @(posedge clk);
        addr_in = 18'h00001;
        read_req = 1;
        @(posedge clk);
        read_req = 0;
        wait(read_done);
        $display("Read data: 0x%04X (expected: 0x1111)", rdata);
        
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