`timescale 1ns / 1ps

module mram_controller_top (
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
    // Reset synchronization
    // ═══════════════════════════════════════════════════════════
    logic rst;
    assign rst = ~cpu_resetn;  // Active high reset
    
    // ═══════════════════════════════════════════════════════════
    // UART signals
    // ═══════════════════════════════════════════════════════════
    logic [7:0] rx_data;
    logic       rx_valid;
    logic       rx_error;
    
    logic [7:0] tx_data;
    logic       tx_send;
    logic       tx_busy;
    
    // ═══════════════════════════════════════════════════════════
    // MRAM Controller signals
    // ═══════════════════════════════════════════════════════════
    logic [15:0] mram_wdata;
    logic [17:0] mram_addr_in;
    logic        mram_write_req;
    logic        mram_read_req;
    logic        mram_write_done;
    logic        mram_read_done;
    logic [15:0] mram_rdata;
    
    // ═══════════════════════════════════════════════════════════
    // UART Protocol FSM
    // ═══════════════════════════════════════════════════════════
    // Protocol:
    // WRITE: 'W' + ADDR_H + ADDR_M + ADDR_L + DATA_H + DATA_L (6 bytes)
    // READ:  'R' + ADDR_H + ADDR_M + ADDR_L (4 bytes) -> reply DATA_H + DATA_L
    
    typedef enum logic [3:0] {
        IDLE,
        CMD_WRITE_ADDR_H,
        CMD_WRITE_ADDR_M,
        CMD_WRITE_ADDR_L,
        CMD_WRITE_DATA_H,
        CMD_WRITE_DATA_L,
        EXEC_WRITE,
        CMD_READ_ADDR_H,
        CMD_READ_ADDR_M,
        CMD_READ_ADDR_L,
        EXEC_READ,
        SEND_DATA_H,
        SEND_DATA_L
    } state_t;
    
    state_t state;
    
    logic [17:0] addr_buffer;
    logic [15:0] data_buffer;
    
    // ═══════════════════════════════════════════════════════════
    // UART Command FSM
    // ═══════════════════════════════════════════════════════════
    always_ff @(posedge clk) begin
        if (rst) begin
            state <= IDLE;
            mram_write_req <= 0;
            mram_read_req <= 0;
            tx_send <= 0;
            addr_buffer <= 0;
            data_buffer <= 0;
            led <= 8'h00;
        end else begin
            // Default: clear requests (but NOT tx_send, managed per state)
            mram_write_req <= 0;
            mram_read_req <= 0;
            
            case (state)
                IDLE: begin
                    tx_send <= 0;  // Ensure tx_send is low
                    if (rx_valid) begin
                        case (rx_data)
                            8'h57, 8'h77: begin // 'W' or 'w'
                                state <= CMD_WRITE_ADDR_H;
                                led <= 8'h01;  // Indicate write command
                            end
                            8'h52, 8'h72: begin // 'R' or 'r'
                                state <= CMD_READ_ADDR_H;
                                led <= 8'h02;  // Indicate read command
                            end
                            default: state <= IDLE;
                        endcase
                    end
                end
                
                // ───────── WRITE COMMAND ─────────
                CMD_WRITE_ADDR_H: begin
                    if (rx_valid) begin
                        addr_buffer[17:16] <= rx_data[1:0];
                        state <= CMD_WRITE_ADDR_M;
                    end
                end
                
                CMD_WRITE_ADDR_M: begin
                    if (rx_valid) begin
                        addr_buffer[15:8] <= rx_data;
                        state <= CMD_WRITE_ADDR_L;
                    end
                end
                
                CMD_WRITE_ADDR_L: begin
                    if (rx_valid) begin
                        addr_buffer[7:0] <= rx_data;
                        state <= CMD_WRITE_DATA_H;
                    end
                end
                
                CMD_WRITE_DATA_H: begin
                    if (rx_valid) begin
                        data_buffer[15:8] <= rx_data;
                        state <= CMD_WRITE_DATA_L;
                    end
                end
                
                CMD_WRITE_DATA_L: begin
                    if (rx_valid) begin
                        data_buffer[7:0] <= rx_data;
                        state <= EXEC_WRITE;
                    end
                end
                
                EXEC_WRITE: begin
                    mram_addr_in <= addr_buffer;
                    mram_wdata <= data_buffer;
                    mram_write_req <= 1;
                    
                    if (mram_write_done) begin
                        state <= IDLE;
                        led <= 8'h0F;  // Write complete
                    end
                end
                
                // ───────── READ COMMAND ─────────
                CMD_READ_ADDR_H: begin
                    if (rx_valid) begin
                        addr_buffer[17:16] <= rx_data[1:0];
                        state <= CMD_READ_ADDR_M;
                    end
                end
                
                CMD_READ_ADDR_M: begin
                    if (rx_valid) begin
                        addr_buffer[15:8] <= rx_data;
                        state <= CMD_READ_ADDR_L;
                    end
                end
                
                CMD_READ_ADDR_L: begin
                    if (rx_valid) begin
                        addr_buffer[7:0] <= rx_data;
                        state <= EXEC_READ;
                    end
                end
                
                EXEC_READ: begin
                    mram_addr_in <= addr_buffer;
                    mram_read_req <= 1;
                    
                    if (mram_read_done) begin
                        data_buffer <= mram_rdata;
                        state <= SEND_DATA_H;
                    end
                end
                
                SEND_DATA_H: begin
                    if (!tx_busy) begin
                        tx_data <= data_buffer[15:8];
                        tx_send <= 1;
                        state <= SEND_DATA_L;
                    end
                end
                
                SEND_DATA_L: begin
                    if (!tx_busy) begin
                        tx_data <= data_buffer[7:0];
                        tx_send <= 1;
                        state <= IDLE;
                        led <= 8'hF0;  // Read complete
                    end
                end
                
                default: state <= IDLE;
            endcase
            
            // Show error on LEDs
            if (rx_error) begin
                led <= 8'hAA;
            end
        end
    end
    
    // ═══════════════════════════════════════════════════════════
    // Module Instantiations
    // ═══════════════════════════════════════════════════════════
    
    // UART RX
    uart_rx u_uart_rx (
        .clk        (clk),
        .reset      (rst),
        .rx         (uart_rx),
        .data_out   (rx_data),
        .data_valid (rx_valid)
    );
    
    // UART TX
    uart_tx u_uart_tx (
        .clk        (clk),
        .reset      (rst),
        .data_in    (tx_data),
        .send       (tx_send),
        .tx         (uart_tx),
        .busy       (tx_busy)
    );
    
    // MRAM Controller
    mram_controller #(
        .CLK_FREQ_MHZ(100)
    ) u_mram_ctrl (
        .clk        (clk),
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

endmodule