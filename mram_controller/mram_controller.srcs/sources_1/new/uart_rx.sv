module uart_rx (
    input   logic       clk,
    input   logic       reset,
    input   logic       rx,
    output  logic [7:0] data_out,
    output  logic       data_valid
);

    localparam CLK_FREQ = 100_000_000;
    localparam BAUD_RATE = 115200;
    localparam TICKS_PER_BIT = CLK_FREQ / BAUD_RATE;
    localparam TICKS_HALF_BIT = TICKS_PER_BIT / 2;

    localparam IDLE  = 3'b000;
    localparam START = 3'b001;
    localparam DATA  = 3'b010;
    localparam STOP  = 3'b011;
    localparam VALID = 3'b100;
    localparam ERROR_STATE = 3'b101;

    logic [2:0] state;
    logic [26:0] baud_counter;
    logic [2:0] bit_index;
    logic [7:0] data_shift;

    // 3-stage synchronization
    logic rx_sync1, rx_sync2, rx_sync3;

    // Anti-bounce filter
    logic [3:0] rx_filter;
    logic       rx_filtered;

    always_ff @(posedge clk) begin
        if (reset) begin
            rx_sync1    <= 1'b1;
            rx_sync2    <= 1'b1;
            rx_sync3    <= 1'b1;
            rx_filter   <= 4'hF;
            rx_filtered <= 1'b1;
        end else begin
            // Synchronization
            rx_sync1 <= rx;
            rx_sync2 <= rx_sync1;
            rx_sync3 <= rx_sync2;

            // Filter: offset and majority
            rx_filter <= {rx_filter[2:0], rx_sync3};

            if (rx_filter == 4'b0000 || rx_filter == 4'b0001 ||
                rx_filter == 4'b0010 || rx_filter == 4'b0100 || rx_filter == 4'b1000) begin
                rx_filtered <= 1'b0;
            end else if (rx_filter == 4'b1111 || rx_filter == 4'b1110 ||
                         rx_filter == 4'b1101 || rx_filter == 4'b1011 || rx_filter == 4'b0111) begin
                rx_filtered <= 1'b1;
            end
        end
    end

    always @(posedge clk) begin
        if (reset) begin
            state           <= IDLE;
            baud_counter    <= 27'b0;
            bit_index       <= 3'b0;
            data_shift      <= 8'b0;
            data_out        <= 8'b0;
            data_valid      <= 1'b0;
        end else begin
            data_valid  <= 1'b0;

            case (state)
                IDLE: begin
                    baud_counter    <= 27'b0;
                    bit_index       <= 3'b0;

                    // Wait for start bit
                    if (rx_filtered == 1'b0) begin
                        state           <= START;
                        baud_counter    <= 27'b0;
                    end
                end

                START: begin
                    if (baud_counter < TICKS_HALF_BIT - 1) begin
                        baud_counter <= baud_counter + 1;
                    end else begin
                        baud_counter <= 27'b0;

                        // Check the stability of the first bit
                        if (rx_filtered == 1'b0) begin
                            state <= DATA;
                        end else begin
                            // False start - back to IDLE
                            state <= ERROR_STATE;
                        end
                    end
                end

                DATA: begin
                    if (baud_counter < TICKS_PER_BIT - 1) begin
                        baud_counter <= baud_counter + 1;
                    end else begin
                        baud_counter <= 27'b0;

                        // Sample in the middle
                        data_shift[bit_index] <= rx_filtered;

                        if (bit_index < 7) begin
                            bit_index <= bit_index + 1;
                        end else begin
                            bit_index   <= 3'b0;
                            state       <= STOP;
                        end
                    end
                end

                STOP: begin
                    if (baud_counter < TICKS_PER_BIT - 1) begin
                        baud_counter <= baud_counter + 1;
                    end else begin
                        baud_counter <= 27'b0;

                        // Check the stop bit
                        if (rx_filtered == 1'b1) begin
                            data_out    <= data_shift;
                            state       <= VALID;
                        end else begin
                            // Frame error
                            state <= ERROR_STATE;
                        end
                    end
                end

                VALID: begin
                    data_valid  <= 1'b1;
                    state       <= IDLE;
                end

                ERROR_STATE: begin
                    // Wait the line to be 1 before going back to IDLE
                    if (rx_filtered == 1'b1) begin
                        state <= IDLE;
                    end
                end

                default: begin
                    state <= IDLE;
                end
            endcase
        end
    end

endmodule
