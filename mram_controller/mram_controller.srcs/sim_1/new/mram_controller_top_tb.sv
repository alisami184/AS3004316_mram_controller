`timescale 1ns / 1ps

module mram_controller_top_tb;

    // Signals
    logic        clk;
    logic        cpu_resetn;
    logic        uart_rx;
    logic        uart_tx;
    logic [7:0]  led;
    logic        e, w, g, ub, lb;
    logic [17:0] mram_addr;
    wire  [15:0] dq;
    
    
    // ═══════════════════════════════════════════════════════════
    // Testbench Parameters
    // ═══════════════════════════════════════════════════════════
    
    parameter CLK_FREQ_MHZ = 100;
    parameter CLK_PERIOD = 1000.0 / CLK_FREQ_MHZ;
    // ═══════════════════════════════════════════════════════════
    // Clock Generation
    // ═══════════════════════════════════════════════════════════
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end
    
    
    // DUT
    mram_controller_top  #(
        .CLK_FREQ_MHZ(CLK_FREQ_MHZ)
    ) dut (
        .clk        (clk),
        .cpu_resetn (cpu_resetn),
        .uart_rx    (uart_rx),
        .uart_tx    (uart_tx),
        .led        (led),
        .e          (e),
        .w          (w),
        .g          (g),
        .ub         (ub),
        .lb         (lb),
        .mram_addr  (mram_addr),
        .dq         (dq)
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
    always @(negedge g or negedge w or negedge cpu_resetn) begin
        if (!cpu_resetn) begin
            read_active <= 0;
        end
        else if (!w) begin
            // Write commence - libère le bus
            read_active <= 0;
        end
        else if (!e && !g && w) begin
            // Read commence - active le bus
            read_active <= 1;
            mram_dq_out <= mram_memory[mram_addr];
            $display("[MRAM] Read: addr=0x%05h → data=0x%04h", mram_addr, mram_memory[mram_addr]);
        end
    end
    
    // Bus DQ piloté par read_active (INDÉPENDANT de e_n/g_n/w_n!)
    assign dq = read_active ? mram_dq_out : 16'hZZZZ;
    
    // Write: capture sur front montant de W#
    always @(posedge w) begin
        if (!e) begin
            mram_memory[mram_addr] <= dq;
            $display("[MRAM] Write: addr=0x%05h ← data=0x%04h", mram_addr, dq);
        end
    end
    
    // ═══════════════════════════════════════════════════════════
    // UART Send Task (115200 baud)
    // ═══════════════════════════════════════════════════════════
    localparam BAUD_PERIOD = 8680;  // ns
    
    task uart_send(input [7:0] data);
        integer i;
        begin
            // Start bit
            uart_rx = 0;
            #BAUD_PERIOD;
            
            // Data bits (LSB first)
            for (i = 0; i < 8; i = i + 1) begin
                uart_rx = data[i];
                #BAUD_PERIOD;
            end
            
            // Stop bit
            uart_rx = 1;
            #BAUD_PERIOD;
        end
    endtask
    
    // ═══════════════════════════════════════════════════════════
    // Test
    // ═══════════════════════════════════════════════════════════
    initial begin
        // Init
        cpu_resetn = 0;
        uart_rx = 1;
        
        #100;
        cpu_resetn = 1;
        #100;
        
        $display("=================================================");
        $display("Test: WRITE 0xABCD to address 0x00123");
        $display("=================================================");
        
        // Envoyer: 'W' + 0x01 + 0x23 + 0xAB + 0xCD
        $display("[TEST] Sending 'W'");
        uart_send(8'h57);
        #1000;
        
        $display("[TEST] Sending ADDR_H = 0x01");
        uart_send(8'h01);
        #1000;
        
        $display("[TEST] Sending ADDR_L = 0x23");
        uart_send(8'h23);
        #1000;
        
        $display("[TEST] Sending DATA_H = 0xAB");
        uart_send(8'hAB);
        #1000;
        
        $display("[TEST] Sending DATA_L = 0xCD");
        uart_send(8'hCD);
        
        // Attendre write done
        wait(led == 8'hFF);
        #1000;
        
        $display("=================================================");
        $display("Write complete! LED = 0x%02h", led);
        $display("Memory[0x00123] = 0x%04h (expected 0xABCD)", mram_memory[18'h00123]);
        $display("=================================================");
        
        if (mram_memory[18'h00123] == 16'hABCD) begin
            $display("✓ TEST PASSED!");
        end else begin
            $display("✗ TEST FAILED!");
        end
        
        #1000;
        $finish;
    end
    
    // Timeout
    initial begin
        #5000000;
        $error("TIMEOUT");
        $finish;
    end

endmodule