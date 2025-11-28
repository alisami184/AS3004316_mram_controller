`timescale 1ns / 1ps

module mram_controller_top #(
    parameter CLK_FREQ_MHZ = 50
)(
    // Clock and Reset
    input  logic        clk,
    input  logic        cpu_resetn,
    
    // UART
    input  logic        uart_rx,
    output logic        uart_tx,
    
    // Debug LEDs
    output logic [7:0]  led,
    
    // MRAM FMC Interface
    output logic        e,
    output logic        w,
    output logic        g,
    output logic        ub,
    output logic        lb,
    output logic [17:0] mram_addr,
    inout  logic [15:0] dq
);

    // ═══════════════════════════════════════════════════════════
    // Reset
    // ═══════════════════════════════════════════════════════════
    logic rst;
    assign rst = ~cpu_resetn;  // Active high
    
    // ═══════════════════════════════════════════════════════════
    // UART RX
    // ═══════════════════════════════════════════════════════════
    logic [7:0] rx_data;
    logic       rx_valid;
    
    uart_rx #(
        .CLK_FREQ(CLK_FREQ_MHZ * 1_000_000),
        .BAUD_RATE(115200)
    ) u_uart_rx (
        .clk        (clk),
        .reset      (rst),
        .rx         (uart_rx),
        .data_out   (rx_data),
        .data_valid (rx_valid)
    );
    
    assign uart_tx = 1'b1;  // Pas de TX pour l'instant
    
    // ═══════════════════════════════════════════════════════════
    // MRAM Controller Interface
    // ═══════════════════════════════════════════════════════════
    logic [15:0] mram_wdata;
    logic [17:0] mram_addr_in;
    logic        mram_write_req;
    logic        mram_write_done;
    
    mram_controller #(
        .CLK_FREQ_MHZ(CLK_FREQ_MHZ)
    ) u_mram (
        .clk        (clk),
        .rst        (~rst),
        .wdata      (mram_wdata),
        .addr_in    (mram_addr_in),
        .write_req  (mram_write_req),
        .read_req   (1'b0),           // Pas de read
        .write_done (mram_write_done),
        .read_done  (),               // Non connecté
        .rdata      (),               // Non connecté
        .e_n        (e),
        .w_n        (w),
        .g_n        (g),
        .addr       (mram_addr),
        .ub_n       (ub),
        .lb_n       (lb),
        .dq         (dq)
    );
    
    // ═══════════════════════════════════════════════════════════
    // FSM Simple pour WRITE
    // ═══════════════════════════════════════════════════════════
    // Protocole: 'W' + ADDR_H + ADDR_L + DATA_H + DATA_L (5 bytes)
    
    typedef enum logic [2:0] {
        IDLE,
        GET_ADDR_H,
        GET_ADDR_L,
        GET_DATA_H,
        GET_DATA_L,
        EXEC_WRITE,
        WRITE_DONE
    } state_t;
    
    state_t state;
    
    logic [17:0] addr_buffer;
    logic [15:0] data_buffer;
    logic        req_sent;  // Track if pulse was sent
    
    always_ff @(posedge clk) begin
        if (rst) begin
            state <= IDLE;
            mram_write_req <= 0;
            addr_buffer <= 0;
            data_buffer <= 0;
            req_sent <= 0;
            led <= 8'h00;
        end else begin
            // Clear request by default
            mram_write_req <= 0;
            
            case (state)
                IDLE: begin
                    if (rx_valid) begin
                        if (rx_data == 8'h57 || rx_data == 8'h77) begin  // 'W' ou 'w'
                            state <= GET_ADDR_H;
                            led <= 8'h01;  // Command reçu
                        end
                    end
                end
                
                GET_ADDR_H: begin
                    if (rx_valid) begin
                        addr_buffer[17:8] <= {8'h00, rx_data[1:0]};
                        state <= GET_ADDR_L;
                        led <= 8'h02;
                    end
                end
                
                GET_ADDR_L: begin
                    if (rx_valid) begin
                        addr_buffer[7:0] <= rx_data;
                        state <= GET_DATA_H;
                        led <= 8'h03;
                    end
                end
                
                GET_DATA_H: begin
                    if (rx_valid) begin
                        data_buffer[15:8] <= rx_data;
                        state <= GET_DATA_L;
                        led <= 8'h04;
                    end
                end
                
                GET_DATA_L: begin
                    if (rx_valid) begin
                        data_buffer[7:0] <= rx_data;
                        state <= EXEC_WRITE;
                        led <= 8'h05;
                    end
                end
                
                EXEC_WRITE: begin
                    mram_addr_in <= addr_buffer;
                    mram_wdata <= data_buffer;
                    
                    // Generate single-cycle pulse
                    if (!req_sent) begin
                        mram_write_req <= 1;
                        req_sent <= 1;
                        led <= 8'h0F;  // Write en cours
                    end
                    
                    if (mram_write_done) begin
                        state <= WRITE_DONE;
                    end
                end
                
                WRITE_DONE: begin
                    req_sent <= 0;  // Reset flag for next write
                    led <= 8'hFF;   // Write terminé!
                    state <= IDLE;
                end
                
                default: state <= IDLE;
            endcase
        end
    end

endmodule