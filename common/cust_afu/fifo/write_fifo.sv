/*
Version: 1.2.2
Modified: 07/11/24
Purpose: control write channel
Description:    
07/11/24: add CH parameter

Note: Modified based on old version of 1.2.4
*/

module write_fifo #(parameter CH = 1) (
    input logic axi4_mm_clk,
    input logic axi4_mm_rst_n,

    //To process 
    output logic wready_ch[0:CH-1],
    input logic wvalid_ch[0:CH-1],
    input logic [511:0] wdata_ch[0:CH-1],
    input logic wlast_ch[0:CH-1], 
    input logic [(512/8)-1:0] wstrb_ch[0:CH-1], 

    output logic awready_ch[0:CH-1],
    input logic awvalid_ch[0:CH-1],
    input logic [11:0] awid_ch[0:CH-1],
    input logic [5:0] awuser_ch[0:CH-1],
    input logic [63:0] awaddr_ch[0:CH-1],

    //To CXL
    input logic wready,
    output logic wvalid,
    output logic [511:0] wdata,
    output logic wlast, 
    output logic [(512/8)-1:0] wstrb, 

    input logic awready,
    output logic awvalid,
    output logic [11:0] awid,
    output logic [5:0] awuser,
    output logic [63:0] awaddr,

    input logic bvalid,
    input logic [11:0] bid,
    input logic [1:0] bresp,
    output logic bready
);

enum logic [4:0] {
    STATE_IDLE,
    STATE_WRITE
} state, next_state;

logic [658:0] write_fifo [15:0];
logic [4:0] r_ptr;
logic [4:0] w_ptr;
logic [4:0] buffer_rem;
assign buffer_rem = (w_ptr[4]==r_ptr[4]) ? (w_ptr-r_ptr) : ({1'b1, w_ptr[3:0]}-{1'b0, r_ptr[3:0]});
assign bready = 1'b1;

logic aw_handshake;
logic w_handshake;

assign awaddr = write_fifo[r_ptr[3:0]][63:0];
assign awuser = write_fifo[r_ptr[3:0]][69:64];
assign awid = write_fifo[r_ptr[3:0]][81:70];
assign wstrb = write_fifo[r_ptr[3:0]][145:82];
assign wlast = write_fifo[r_ptr[3:0]][146];
assign wdata = write_fifo[r_ptr[3:0]][658:147];

int i;

//receive read request
always_ff @(posedge axi4_mm_clk) begin
    if (!axi4_mm_rst_n) begin
        w_ptr <= 5'b0;
        awready_ch <= '{default: 1'b0};
        wready_ch <= '{default: 1'b0};
    end
    else begin
        awready_ch <= '{default: 1'b0};
        wready_ch <= '{default: 1'b0};
        if (buffer_rem < 5'd16) begin
            for (i=0; i<CH; i++) begin
                if (awvalid_ch[i] & !awready_ch[i]) begin
                    awready_ch[i] <= 1'b1;
                    wready_ch[i] <= 1'b1;
                    write_fifo[w_ptr[3:0]] <= {wdata_ch[i], wlast_ch[i], wstrb_ch[i], awid_ch[i], awuser_ch[i], awaddr_ch[i]};
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
        unique case (state)
            STATE_IDLE: begin
                aw_handshake <= 1'b0;
                w_handshake <= 1'b0;
            end

            STATE_WRITE: begin
                if (awvalid & awready) begin
                    aw_handshake <= 1'b1;
                end
                if (wvalid & wready) begin
                    w_handshake <= 1'b1;
                end

                if (awready & wready) begin
                    r_ptr <= r_ptr + 5'd1;
                end
                else if (wvalid == 1'b0) begin
                    if (awready) begin
                        r_ptr <= r_ptr + 5'd1;
                    end
                    else begin
                        r_ptr <= r_ptr;
                    end
                end
                else if (awvalid == 1'b0) begin
                    if (wready) begin
                        r_ptr <= r_ptr + 5'd1;
                    end
                    else begin
                        r_ptr <= r_ptr;
                    end
                end
                else begin
                    r_ptr <= r_ptr;
                end
            end

            default: begin

            end
        endcase
    end
end

always_comb begin
    unique case(state)
        STATE_IDLE: begin
            if (buffer_rem > 5'd0) begin
                next_state = STATE_WRITE;
            end
            else begin
                next_state = STATE_IDLE;
            end
        end
        STATE_WRITE: begin
            if (awready & wready) begin
                next_state = STATE_IDLE;
            end
            else if (wvalid == 1'b0) begin
                if (awready) begin
                    next_state = STATE_IDLE;
                end
                else begin
                    next_state = STATE_WRITE;
                end
            end
            else if (awvalid == 1'b0) begin
                if (wready) begin
                    next_state = STATE_IDLE;
                end
                else begin
                    next_state = STATE_WRITE;
                end
            end
            else begin
                next_state = STATE_WRITE;
            end
        end

        default: begin
            next_state = STATE_IDLE;
        end
    endcase
end

always_comb begin : READ
    awvalid = 1'b0;
    wvalid = 1'b0;
    unique case(state)
        STATE_WRITE: begin
            if (aw_handshake) begin
                awvalid = 1'b0;
            end
            else begin
                awvalid = 1'b1;
            end
            if (w_handshake) begin
                wvalid = 1'b0;
            end
            else begin
                wvalid = 1'b1;
            end
        end
        default: begin

        end
    endcase
end

endmodule