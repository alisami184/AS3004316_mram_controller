module uart_tx #(
parameter CLK_FREQ = 100_000_000,
parameter BAUD_RATE = 115200
)(
    input   logic       clk,
    input   logic       reset,
    input   logic [7:0] data_in,
    input   logic       send,
    output  logic       tx,
    output  logic       busy
);

    // UART parameters
    localparam TICKS_PER_BIT = CLK_FREQ / BAUD_RATE; // ~868 per ticks

    // States of the state machine
    localparam IDLE  = 2'b00;
    localparam START = 2'b01;
    localparam DATA  = 2'b10;
    localparam STOP  = 2'b11;

    logic [1:0]     state;
    logic [26:0]    baud_counter;
    logic [2:0]     bit_index;
    logic [7:0]     data_reg;

    always_ff @(posedge clk) begin
        if (reset) begin
            state           <= IDLE;
            tx              <= 1'b1;
            busy            <= 1'b0;
            baud_counter    <= 27'b0;
            bit_index       <= 3'b0;
            data_reg        <= 8'b0;
        end else begin
            case (state)
                IDLE: begin
                    tx              <= 1'b1;
                    busy            <= 1'b0;
                    baud_counter    <= 27'b0;
                    bit_index       <= 3'b0;

                    if (send) begin
                        data_reg    <= data_in;
                        state       <= START;
                        busy        <= 1'b1;
                    end
                end

                START: begin
                    tx <= 1'b0;

                    if (baud_counter < TICKS_PER_BIT - 1) begin
                        baud_counter <= baud_counter + 1;
                    end else begin
                        baud_counter    <= 27'b0;
                        state           <= DATA;
                    end
                end

                DATA: begin
                    tx <= data_reg[bit_index];  // Envoyer le bit courant (LSB first)

                    if (baud_counter < TICKS_PER_BIT - 1) begin
                        baud_counter <= baud_counter + 1;
                    end else begin
                        baud_counter <= 27'b0;

                        if (bit_index < 7) begin
                            bit_index <= bit_index + 1;
                        end else begin
                            bit_index   <= 3'b0;
                            state       <= STOP;
                        end
                    end
                end

                STOP: begin
                    tx <= 1'b1;

                    if (baud_counter < TICKS_PER_BIT - 1) begin
                        baud_counter <= baud_counter + 1;
                    end else begin
                        baud_counter    <= 27'b0;
                        state           <= IDLE;
                        busy            <= 1'b0;
                    end
                end

                default: begin
                    state <= IDLE;
                end
            endcase
        end
    end

endmodule
