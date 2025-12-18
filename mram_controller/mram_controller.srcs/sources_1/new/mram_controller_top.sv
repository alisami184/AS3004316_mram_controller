`timescale 1ns / 1ps

module mram_controller_top #(
    parameter CLK_FREQ_MHZ = 100
)(
    // Clock and Reset
    input  logic        sys_clk_i,
    input  logic        sys_rst,
    
    // UART
    input  logic        uart_rx,
    output logic        uart_tx,
    
    // Debug LEDs
    output logic [7:0]  led,
    output logic        clk_out,
    
    // VADJ Configuration
    output logic [1:0] set_vadj,
    output logic       vadj_en,
    
    // MRAM FMC Interface
    output logic        e,
    output logic        w,
    output logic        g,
    output logic        ub,
    output logic        lb,
    output logic [17:0] mram_addr,
    inout  logic [15:0] dq
);

    // Configuration VADJ = 3.3V
    assign set_vadj = 2'b11;  // 11 = 3.3V
    assign vadj_en = 1'b1;    // Enable regulator
    // ═══════════════════════════════════════════════════════════
    // Clock Divider: 100MHz → 50MHz
    // ═══════════════════════════════════════════════════════════
    logic clk_50 = 0;
    
    always_ff @(posedge sys_clk_i) begin
        clk_50 <= ~clk_50;
    end
    
    logic clk_out = 0;

    localparam int DIVIDE_BY = 100;      // 100 MHz / 100 = 1 MHz
    localparam int HALF_PERIOD = DIVIDE_BY/2;
    
    logic [$clog2(HALF_PERIOD)-1:0] cnt = 0;
    
    always_ff @(posedge sys_clk_i) begin
        if (cnt == HALF_PERIOD-1) begin
            cnt     <= 0;
            clk_out <= ~clk_out;   // toggle → crée l'horloge divisée
        end else begin
            cnt <= cnt + 1;
        end
    end


    // ═══════════════════════════════════════════════════════════
    // Reset
    // ═══════════════════════════════════════════════════════════
    logic rst;
    assign rst = ~sys_rst;  // Active high
    
    // ═══════════════════════════════════════════════════════════
    // UART RX
    // ═══════════════════════════════════════════════════════════
    logic [7:0] rx_data;
    logic       rx_valid;
    
    uart_rx #(
        .CLK_FREQ(CLK_FREQ_MHZ * 1_000_000),
        .BAUD_RATE(115200)
    ) u_uart_rx (
        .clk        (sys_clk_i),
        .reset      (rst),
        .rx         (uart_rx),
        .data_out   (rx_data),
        .data_valid (rx_valid)
    );
    
    // ═══════════════════════════════════════════════════════════
    // UART TX
    // ═══════════════════════════════════════════════════════════
    logic [7:0] tx_data;
    logic       tx_send;
    logic       tx_busy;
    
    uart_tx #(
        .CLK_FREQ(CLK_FREQ_MHZ * 1_000_000),
        .BAUD_RATE(115200)
    ) u_uart_tx (
        .clk        (sys_clk_i),
        .reset      (rst),
        .data_in    (tx_data),
        .send       (tx_send),
        .tx         (uart_tx),
        .busy       (tx_busy)
    );
    
    // ═══════════════════════════════════════════════════════════
    // MRAM Controller Interface
    // ═══════════════════════════════════════════════════════════
    logic [15:0] mram_wdata;
    logic [17:0] mram_addr_in;
    logic        mram_write_req;
    logic        mram_read_req;
    logic        mram_write_done;
    logic        mram_read_done;
    logic [15:0] mram_rdata;
    
    mram_controller #(
        .CLK_FREQ_MHZ(CLK_FREQ_MHZ)
    ) u_mram (
        .clk        (sys_clk_i),
        .rst        (rst),
        .wdata      (mram_wdata),
        .addr_in    (mram_addr_in),
        .write_req  (mram_write_req),
        .read_req   (mram_read_req),
        .write_done (mram_write_done),
        .read_done  (mram_read_done),
        .rdata      (mram_rdata),
        .e_n        (e),
        .w_n        (w),
        .g_n        (g),
        .addr       (mram_addr),
        .ub_n       (ub),
        .lb_n       (lb),
        .dq         (dq)
    );
    
    // ═══════════════════════════════════════════════════════════
    // FSM pour WRITE et READ
    // ═══════════════════════════════════════════════════════════
    // Protocole WRITE: 'W' + ADDR_H + ADDR_M + ADDR_L + DATA_H + DATA_L (6 bytes)
    // Protocole READ:  'R' + ADDR_H + ADDR_M + ADDR_L (4 bytes) → réponse DATA_H + DATA_L
    
    typedef enum logic [4:0] {
        IDLE,
        // WRITE path
        W_GET_ADDR_H,
        W_GET_ADDR_M,
        W_GET_ADDR_L,
        W_GET_DATA_H,
        W_GET_DATA_L,
        W_EXEC,
        W_DONE,
        // READ path
        R_GET_ADDR_H,
        R_GET_ADDR_M,
        R_GET_ADDR_L,
        R_EXEC,
        R_SEND_DATA_H,
        R_WAIT_TX_BUSY_H,
        R_WAIT_TX_DONE_H,
        R_SEND_DATA_L,
        R_WAIT_TX_BUSY_L,
        R_WAIT_TX_DONE_L,
        R_DONE
    } state_t;
    
    state_t state;
    
    logic [17:0] addr_buffer;
    logic [15:0] data_buffer;
    logic        req_sent;
    logic        rx_valid_prev;  // For edge detection
    
    wire rx_valid_edge = rx_valid && !rx_valid_prev;  // Rising edge
    
    always_ff @(posedge sys_clk_i) begin
        if (rst) begin
            state <= IDLE;
            mram_write_req <= 0;
            mram_read_req <= 0;
            tx_send <= 0;
            addr_buffer <= 0;
            data_buffer <= 0;
            req_sent <= 0;
            rx_valid_prev <= 0;
            led <= 8'h00;
        end else begin
            // Track rx_valid for edge detection
            rx_valid_prev <= rx_valid;
            
            // Clear requests by default
            mram_write_req <= 0;
            mram_read_req <= 0;
            
            case (state)
                // ═══════════════════════════════════════════════
                // IDLE - Attendre commande
                // ═══════════════════════════════════════════════
                IDLE: begin
                    tx_send <= 0;
                    led <= {4'h0, rx_valid, rx_valid_prev, rx_valid_edge, 1'b1};
                    if (rx_valid_edge) begin
                        case (rx_data)
                            8'h57, 8'h77: begin // 'W' ou 'w'
                                state <= W_GET_ADDR_H;
                            end
                            8'h52, 8'h72: begin // 'R' ou 'r'
                                state <= R_GET_ADDR_H;
                            end
                            default: state <= IDLE;
                        endcase
                    end
                    else begin
                        state <= IDLE;
                    end
                end
                
                // ═══════════════════════════════════════════════
                // WRITE PATH
                // ═══════════════════════════════════════════════
                W_GET_ADDR_H: begin
                    led <= 8'h02;
                    if (rx_valid_edge) begin
                        addr_buffer[17:16] <= rx_data[1:0];
                        state <= W_GET_ADDR_M;
                    end
                end
                
                W_GET_ADDR_M: begin
                    led <= 8'h03;
                    if (rx_valid_edge) begin
                        addr_buffer[15:8] <= rx_data;
                        state <= W_GET_ADDR_L;
                    end
                end
                
                W_GET_ADDR_L: begin
                    led <= 8'h04;
                    if (rx_valid_edge) begin
                        addr_buffer[7:0] <= rx_data;
                        state <= W_GET_DATA_H;
                    end
                end
                
                W_GET_DATA_H: begin
                    led <= 8'h05;
                    if (rx_valid_edge) begin
                        data_buffer[15:8] <= rx_data;
                        state <= W_GET_DATA_L;
                    end
                end
                
                W_GET_DATA_L: begin
                    led <= 8'h06;
                    if (rx_valid_edge) begin
                        data_buffer[7:0] <= rx_data;
                        state <= W_EXEC;
                    end
                end
                
                W_EXEC: begin
                    mram_addr_in <= addr_buffer;
                    mram_wdata <= data_buffer;
                    led <= 8'h07;
                    
                    if (!req_sent) begin
                        mram_write_req <= 1;
                        req_sent <= 1;
                    end
                    
                    if (mram_write_done) begin
                        state <= W_DONE;
                    end
                end
                
                W_DONE: begin
                    req_sent <= 0;
                    led <= 8'hFF;
                    state <= IDLE;
                end
                
                // ═══════════════════════════════════════════════
                // READ PATH
                // ═══════════════════════════════════════════════
                R_GET_ADDR_H: begin
                    led <= 8'h10;
                    if (rx_valid_edge) begin
                        addr_buffer[17:16] <= rx_data[1:0];
                        state <= R_GET_ADDR_M;
                        $display("[TOP READ] Got ADDR_H=0x%02h at %0t", rx_data, $time);
                    end
                end
                
                R_GET_ADDR_M: begin
                    led <= 8'h11;
                    if (rx_valid_edge) begin
                        addr_buffer[15:8] <= rx_data;
                        state <= R_GET_ADDR_L;
                        $display("[TOP READ] Got ADDR_M=0x%02h at %0t", rx_data, $time);
                    end
                end
                
                R_GET_ADDR_L: begin
                    led <= 8'h12;
                    if (rx_valid_edge) begin
                        addr_buffer[7:0] <= rx_data;
                        state <= R_EXEC;
                        $display("[TOP READ] Got ADDR_L=0x%02h, full addr=0x%05h at %0t", rx_data, {addr_buffer[17:8], rx_data}, $time);
                    end
                end
                
                R_EXEC: begin
                    mram_addr_in <= addr_buffer;
                    led <= 8'h13;
                    
                    if (!req_sent) begin
                        mram_read_req <= 1;
                        req_sent <= 1;
                        $display("[TOP READ] Sending read_req for addr=0x%05h at %0t", addr_buffer, $time);
                    end
                    
                    if (mram_read_done) begin
                        data_buffer <= mram_rdata;
                        state <= R_SEND_DATA_H;
                        $display("[TOP READ] Got read_done, rdata=0x%04h, storing to data_buffer at %0t", mram_rdata, $time);
                    end
                end
                
                R_SEND_DATA_H: begin
                    led <= 8'hF0;
                    if (!tx_busy) begin
                        tx_data <= data_buffer[15:8];
                        tx_send <= 1;
                        state <= R_WAIT_TX_BUSY_H;
                        $display("[TOP READ] Sending DATA_H=0x%02h (from data_buffer=0x%04h), tx_busy=%b at %0t", data_buffer[15:8], data_buffer, tx_busy, $time);
                    end
                end
                
                R_WAIT_TX_BUSY_H: begin
                     tx_send <= 0;
                     led <= 8'hF1;
                     if (tx_busy) begin
                         state <= R_WAIT_TX_DONE_H;
                         $display("[TOP READ] TX_H started (tx_busy=1) at %0t", $time);
                     end
                end
                
                R_WAIT_TX_DONE_H: begin
                    led <= 8'hF1;
                    if (!tx_busy) begin
                        state <= R_SEND_DATA_L;
                        $display("[TOP READ] TX_H done (tx_busy=0), ready for DATA_L. data_buffer=0x%04h at %0t", data_buffer, $time);
                    end
                end
                
                R_SEND_DATA_L: begin
                    led <= 8'hF2;
                    if (!tx_busy) begin
                        tx_data <= data_buffer[7:0];
                        tx_send <= 1;
                        state <= R_WAIT_TX_BUSY_L;
                        $display("[TOP READ] Sending DATA_L=0x%02h (from data_buffer=0x%04h), tx_busy=%b at %0t", data_buffer[7:0], data_buffer, tx_busy, $time);
                    end
                end
                
                R_WAIT_TX_BUSY_L: begin
                    led <= 8'hF2;
                     tx_send <= 0;
                     if (tx_busy) begin
                         state <= R_WAIT_TX_DONE_L;
                         $display("[TOP READ] TX_L started (tx_busy=1) at %0t", $time);
                     end
                end
                
                R_WAIT_TX_DONE_L: begin
                    led <= 8'hF2;
                    if (!tx_busy) begin
                        state <= R_DONE;
                        $display("[TOP READ] TX_L done (tx_busy=0), going to DONE at %0t", $time);
                    end
                end
                
                R_DONE: begin
                    tx_send <= 0;
                    req_sent <= 0;
                    led <= 8'hF0;
                    state <= IDLE;
                    $display("[TOP READ] Complete, returning to IDLE at %0t", $time);
                end
                
                default: state <= IDLE;
            endcase
        end
    end

endmodule