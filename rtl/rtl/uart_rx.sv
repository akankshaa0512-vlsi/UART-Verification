module uart_rx (
    input            clk,
    input            rst,
    input            rx_in,
    output reg [7:0] rx_data,
    output reg       rx_done
);

    parameter CLK_FREQ  = 50000000;
    parameter BAUD_RATE = 9600;
    parameter BAUD_DIV  = CLK_FREQ / BAUD_RATE;
    parameter HALF_DIV  = BAUD_DIV / 2;

    parameter IDLE  = 2'b00;
    parameter START = 2'b01;
    parameter DATA  = 2'b10;
    parameter STOP  = 2'b11;

    reg [1:0]  state;
    reg [12:0] baud_count;
    reg [2:0]  bit_index;
    reg [7:0]  rx_shift;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state      <= IDLE;
            rx_data    <= 8'b0;
            rx_done    <= 1'b0;
            baud_count <= 0;
            bit_index  <= 0;
            rx_shift   <= 0;
        end
        else begin
            rx_done <= 1'b0;

            case (state)
                IDLE: begin
                    baud_count <= 0;
                    bit_index  <= 0;
                    if (rx_in == 1'b0)
                        state <= START;
                end

                START: begin
                    if (baud_count < HALF_DIV - 1)
                        baud_count <= baud_count + 1;
                    else begin
                        baud_count <= 0;
                        if (rx_in == 1'b0)
                            state <= DATA;
                        else
                            state <= IDLE;
                    end
                end

                DATA: begin
                    if (baud_count < BAUD_DIV - 1)
                        baud_count <= baud_count + 1;
                    else begin
                        baud_count <= 0;
                        rx_shift[bit_index] <= rx_in;
                        if (bit_index < 7)
                            bit_index <= bit_index + 1;
                        else begin
                            bit_index <= 0;
                            state     <= STOP;
                        end
                    end
                end

                STOP: begin
                    if (baud_count < BAUD_DIV - 1)
                        baud_count <= baud_count + 1;
                    else begin
                        baud_count <= 0;
                        if (rx_in == 1'b1) begin
                            rx_data <= rx_shift;
                            rx_done <= 1'b1;
                        end
                        state <= IDLE;
                    end
                end
            endcase
        end
    end

endmodule
