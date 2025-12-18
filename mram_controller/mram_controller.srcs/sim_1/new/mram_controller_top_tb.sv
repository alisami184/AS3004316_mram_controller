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
    parameter CLK_FREQ_MHZ = 50;
    parameter CLK_PERIOD = 1000.0 / CLK_FREQ_MHZ;
    
    // ═══════════════════════════════════════════════════════════
    // Clock Generation
    // ═══════════════════════════════════════════════════════════
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end
    
    // DUT
    mram_controller_top #(
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
    // MRAM Simulator
    // ═══════════════════════════════════════════════════════════
    logic [15:0] mram_memory [0:262143];
    logic [15:0] mram_dq_out;
    logic        read_active = 0;
    
    initial begin
        for (int i = 0; i < 262144; i++) begin
            mram_memory[i] = 16'h0000;
        end
    end
    
    always @(negedge g or negedge w or negedge cpu_resetn) begin
        if (!cpu_resetn) begin
            read_active <= 0;
        end
        else if (!w) begin
            read_active <= 0;
        end
        else if (!e && !g && w) begin
            read_active <= 1;
            mram_dq_out <= mram_memory[mram_addr];
            $display("[MRAM] Read: addr=0x%05h → data=0x%04h", mram_addr, mram_memory[mram_addr]);
        end
    end
    
    assign dq = read_active ? mram_dq_out : 16'hZZZZ;
    
    always @(posedge w) begin
        if (!e) begin
            mram_memory[mram_addr] <= dq;
            $display("[MRAM] Write: addr=0x%05h ← data=0x%04h", mram_addr, dq);
        end
    end
    
    // ═══════════════════════════════════════════════════════════
    // UART Tasks
    // ═══════════════════════════════════════════════════════════
    localparam BAUD_PERIOD = 8680;  // ns for 115200 baud
    
    task uart_send(input [7:0] data);
        integer i;
        begin
            uart_rx = 0;
            #BAUD_PERIOD;
            for (i = 0; i < 8; i = i + 1) begin
                uart_rx = data[i];
                #BAUD_PERIOD;
            end
            uart_rx = 1;
            #BAUD_PERIOD;
        end
    endtask
    
    task uart_receive(output [7:0] data);
        integer i;
        begin
            // Wait for start bit (falling edge on uart_tx)
            wait(uart_tx == 1);  // ← Attend ligne IDLE (repos)
            @(negedge uart_tx);  // ← Maintenant c'est forcément le start bit!
            $display("[TB UART_RX] Start bit detected at %0t", $time);
            
            // Wait to sample in the MIDDLE of the first data bit
            #(BAUD_PERIOD + BAUD_PERIOD/2);
            
            // Receive 8 data bits (LSB first)
            for (i = 0; i < 8; i = i + 1) begin
                data[i] = uart_tx;
                #BAUD_PERIOD;
            end
            
            $display("[TB UART_RX] Received byte 0x%02h at %0t", data, $time);
            
            // Wait for stop bit
            #BAUD_PERIOD;
        end
    endtask
    
    // ═══════════════════════════════════════════════════════════
    // Test
    // ═══════════════════════════════════════════════════════════
    logic [7:0] rx_byte_h, rx_byte_l;
    logic [15:0] received_data;
    
    initial begin
        // Init
        cpu_resetn = 0;
        uart_rx = 1;
        
        #100;
        cpu_resetn = 1;
        #100;
        
        $display("\n=================================================");
        $display("TEST 1: WRITE 0xABCD to address 0x00123");
        $display("=================================================");
        
        uart_send(8'h57);  // 'W'
        #1000;
        uart_send(8'h00);  // ADDR_H (bits [17:16])
        #1000;
        uart_send(8'h01);  // ADDR_M (bits [15:8])
        #1000;
        uart_send(8'h23);  // ADDR_L (bits [7:0])
        #1000;
        uart_send(8'hAB);  // DATA_H
        #1000;
        uart_send(8'hCD);  // DATA_L
        
        wait(led == 8'hFF);
        #1000;
        
        $display("Write complete! Memory[0x00123] = 0x%04h", mram_memory[18'h00123]);
        
        if (mram_memory[18'h00123] == 16'hABCD) begin
            $display("✓ WRITE TEST PASSED!");
        end else begin
            $display("✗ WRITE TEST FAILED!");
        end
        
        $display("\n=================================================");
        $display("TEST 2: READ from address 0x00123");
        $display("=================================================");
        
        uart_send(8'h52);  // 'R'
        #1000;
        uart_send(8'h00);  // ADDR_H (bits [17:16])
        #1000;
        uart_send(8'h01);  // ADDR_M (bits [15:8])
        #1000;
        uart_send(8'h23);  // ADDR_L (bits [7:0])
        
        // Receive 2 bytes via UART TX (wait for both sequentially)
        uart_receive(rx_byte_h);
        uart_receive(rx_byte_l);
        
        received_data = {rx_byte_h, rx_byte_l};
        
        wait(led == 8'hF0);
        #1000;
        
        $display("Read complete! Received data = 0x%04h (expected 0xABCD)", received_data);
        
        if (received_data == 16'hABCD) begin
            $display("✓ READ TEST PASSED!");
        end else begin
            $display("✗ READ TEST FAILED!");
        end
        
        $display("\n=================================================");
        $display("TEST 3: WRITE then READ different address");
        $display("=================================================");
        
        // Write 0x1234 to 0x00456
        uart_send(8'h57);  // 'W'
        #1000;
        uart_send(8'h00);  // ADDR_H (bits [17:16])
        #1000;
        uart_send(8'h04);  // ADDR_M (bits [15:8])
        #1000;
        uart_send(8'h56);  // ADDR_L (bits [7:0])
        #1000;
        uart_send(8'h12);  // DATA_H
        #1000;
        uart_send(8'h34);  // DATA_L
        
        wait(led == 8'hFF);
        #1000;
        
        $display("Write complete! Memory[0x00456] = 0x%04h", mram_memory[18'h00456]);
        
        // Read back
        uart_send(8'h52);  // 'R'
        #1000;
        uart_send(8'h00);  // ADDR_H (bits [17:16])
        #1000;
        uart_send(8'h04);  // ADDR_M (bits [15:8])
        #1000;
        uart_send(8'h56);  // ADDR_L (bits [7:0])
        
        // Receive 2 bytes sequentially
        uart_receive(rx_byte_h);
        uart_receive(rx_byte_l);
        
        received_data = {rx_byte_h, rx_byte_l};
        
        wait(led == 8'hF0);
        #1000;
        
        $display("Read complete! Received data = 0x%04h (expected 0x1234)", received_data);
        
        if (received_data == 16'h1234) begin
            $display("✓ WRITE-READ TEST PASSED!");
        end else begin
            $display("✗ WRITE-READ TEST FAILED!");
        end
        
        $display("\n=================================================");
        $display("ALL TESTS COMPLETE!");
        $display("=================================================\n");
        
        #1000;
        $finish;
    end
    
    // Timeout
    initial begin
        #10000000;
        $error("TIMEOUT");
        $finish;
    end

endmodule