module uart_echo (
    input   logic           sys_clk_i,
    input   logic           sys_rst,
    input   logic           uart_rx,
    output  logic           uart_tx,
    output  logic [7:0]     led
);

    logic       reset;
    logic [7:0] rx_data;
    logic       rx_valid;
    logic       rx_error;
    logic       tx_busy;

    logic [7:0] tx_data;
    logic       tx_send;

    assign reset = ~sys_rst;

    localparam IDLE = 1'b0;
    localparam SEND = 1'b1;

    logic state;

    always_ff @(posedge sys_clk_i) begin
        if (reset) begin
            state   <= IDLE;
            tx_send <= 1'b0;
            tx_data <= 8'h00;
            led     <= 8'h00;
        end else begin
            case (state)
                IDLE: begin
                    tx_send <= 1'b0;

                    if (rx_valid) begin
                        tx_data <= rx_data;
                        led     <= rx_data;

                        if (!tx_busy) begin
                            tx_send <= 1'b1;
                            state   <= SEND;
                        end
                    end

                    if (rx_error) begin
                        led <= 8'hAA;
                    end
                end

                SEND: begin
                    tx_send <= 1'b0;
                    state   <= IDLE;
                end

                default: begin
                    state <= IDLE;
                end
            endcase
        end
    end

    // Instance UART RX
    uart_rx receiver (
        .clk(sys_clk_i),
        .reset(reset),
        .rx(uart_rx),
        .data_out(rx_data),
        .data_valid(rx_valid),
        .error(rx_error)
    );

    // Instance UART TX
    uart_tx transmitter (
        .clk(sys_clk_i),
        .reset(reset),
        .data_in(tx_data),
        .send(tx_send),
        .tx(uart_tx),
        .busy(tx_busy)
    );

endmodule