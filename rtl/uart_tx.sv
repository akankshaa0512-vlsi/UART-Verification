module uart_tx (
    input        clk,
    input        rst,
    input        tx_start,
    input  [7:0] tx_data,
    output reg   tx_out,
    output reg   tx_done
);

    parameter CLK_FREQ  = 50000000;
    parameter BAUD_RATE = 9600;
    parameter BAUD_DIV  = CLK_FREQ / BAUD_RATE;

    parameter IDLE  = 2'b00;
    parameter START = 2'b01;
    parameter DATA  = 2'b10;
    parameter STOP  = 2'b11;

    reg [1:0]  state;
    reg [12:0] baud_count;
    reg [2:0]  bit_index;
    reg [7:0]  tx_shift;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state      <= IDLE;
            tx_out     <= 1'b1;
            tx_done    <= 1'b0;
            baud_count <= 0;
            bit_index  <= 0;
            tx_shift   <= 0;
        end
        else begin
            tx_done <= 1'b0;

            case (state)
                IDLE: begin
                    tx_out     <= 1'b1;
                    baud_count <= 0;
                    bit_index  <= 0;
                    if (tx_start) begin
                        state    <= START;
                        tx_shift <= tx_data;
                    end
                end

                START: begin
                    tx_out <= 1'b0;
                    if (baud_count < BAUD_DIV - 1)
                        baud_count <= baud_count + 1;
                    else begin
                        baud_count <= 0;
                        state      <= DATA;
                    end
                end

                DATA: begin
                    tx_out <= tx_shift[bit_index];
                    if (baud_count < BAUD_DIV - 1)
                        baud_count <= baud_count + 1;
                    else begin
                        baud_count <= 0;
                        if (bit_index < 7)
                            bit_index <= bit_index + 1;
                        else begin
                            bit_index <= 0;
                            state     <= STOP;
                        end
                    end
                end

                STOP: begin
                    tx_out <= 1'b1;
                    if (baud_count < BAUD_DIV - 1)
                        baud_count <= baud_count + 1;
                    else begin
                        baud_count <= 0;
                        tx_done    <= 1'b1;
                        state      <= IDLE;
                    end
                end
            endcase
        end
    end

endmodule
