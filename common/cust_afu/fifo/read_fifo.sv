/*
Version: 1.2.2
Modified: 08/01/24
Purpose: control read channel
Description:    
07/11/24: add CH parameter
08/02/24: fix latch

Note: Modified based on old version of 1.2.4
*/


module read_fifo #(parameter CH = 1) (
    input logic axi4_mm_clk,
    input logic axi4_mm_rst_n,

    //To poll and process
    output logic arready_ch[CH-1:0],
    input logic arvalid_ch[CH-1:0],
    input logic [11:0] arid_ch[CH-1:0],
    input logic [63:0] araddr_ch[CH-1:0],
    input logic [5:0] aruser_ch[CH-1:0],

    //To CXL
    input logic rvalid,
    input logic rlast,
    input logic [1:0] rresp,
    input logic [511:0] rdata,
    output logic rready,

    input logic arready,
    output logic arvalid,
    output logic [11:0] arid,
    output logic [5:0] aruser,
    output logic [63:0] araddr
);

enum logic [4:0] {
    STATE_IDLE,
    STATE_READ
} state, next_state;

logic [81:0] read_fifo [15:0];
logic [4:0] r_ptr;
logic [4:0] w_ptr;
logic [4:0] buffer_rem;
assign buffer_rem = (w_ptr[4]==r_ptr[4]) ? (w_ptr-r_ptr) : ({1'b1, w_ptr[3:0]}-{1'b0, r_ptr[3:0]});
assign rready = 1'b1;
assign araddr = read_fifo[r_ptr[3:0]][63:0];
assign aruser = read_fifo[r_ptr[3:0]][69:64];
assign arid = read_fifo[r_ptr[3:0]][81:70];

int i;

//receive read request
always_ff @(posedge axi4_mm_clk) begin
    if (!axi4_mm_rst_n) begin
        w_ptr <= 5'b0;
        arready_ch <= '{default: 1'b0};
    end
    else begin
        arready_ch <= '{default: 1'b0};
        if (buffer_rem < 5'd16) begin
            for (i=0; i < CH; i++) begin
                if (arvalid_ch[i] & !arready_ch[i]) begin
                    arready_ch[i] <= 1'b1;
                    read_fifo[w_ptr[3:0]] <= {arid_ch[i], aruser_ch[i], araddr_ch[i]};
                    w_ptr <= w_ptr + 5'b1;
                    break;
                end
            end 
        end
    end
end

//send read request 
always_ff @(posedge axi4_mm_clk) begin
    if (!axi4_mm_rst_n) begin
        state <= STATE_IDLE;
        r_ptr <= 5'b0;
    end
    else begin
        state <= next_state;
        if (state == STATE_READ) begin
            if (arready & arvalid) begin
                r_ptr <= r_ptr + 5'd1;
            end
        end 
    end
end

always_comb begin
    unique case(state)
        STATE_IDLE: begin
            if (buffer_rem > 5'd0) begin
                next_state = STATE_READ;
            end
            else begin
                next_state = STATE_IDLE;
            end
        end
        STATE_READ: begin
            if (arready & arvalid) begin
                if (buffer_rem > 5'd1) begin
                    next_state = STATE_READ;
                end
                else begin
                    next_state = STATE_IDLE;
                end
            end
            else begin
                next_state = STATE_READ;
            end
        end

        default: begin
            next_state = STATE_IDLE;
        end
    endcase
end

always_comb begin : READ
    arvalid = 1'b0;
    unique case(state)
        STATE_READ: begin
            arvalid = 1'b1;
        end
        default: begin

        end
    endcase
end

endmodule