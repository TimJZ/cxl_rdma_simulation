/*
Version: 1.0.0
Modified: 04/18/25
Purpose: control read and write channel
Description:    
04/18/25: merge write fifo and read fifo
*/


module cafu_fifo #(
    parameter RD_CH = 1,
    parameter WR_CH = 1
) (
    input logic axi4_mm_clk,
    input logic axi4_mm_rst_n,

    //To poll and process
    output logic arready_ch[RD_CH-1:0],
    input logic arvalid_ch[RD_CH-1:0],
    input logic [11:0] arid_ch[RD_CH-1:0],
    input logic [63:0] araddr_ch[RD_CH-1:0],
    input logic [5:0] aruser_ch[RD_CH-1:0],

    output logic wready_ch[WR_CH-1:0],
    input logic wvalid_ch[WR_CH-1:0],
    input logic [511:0] wdata_ch[WR_CH-1:0],
    input logic wlast_ch[WR_CH-1:0], 
    input logic [(512/8)-1:0] wstrb_ch[WR_CH-1:0],

    output logic awready_ch[WR_CH-1:0],
    input logic awvalid_ch[WR_CH-1:0],
    input logic [11:0] awid_ch[WR_CH-1:0],
    input logic [5:0] awuser_ch[WR_CH-1:0],
    input logic [63:0] awaddr_ch[WR_CH-1:0],

    //To CXL
    input logic arready,
    output logic arvalid,
    output logic [11:0] arid,
    output logic [5:0] aruser,
    output logic [63:0] araddr,

    input logic wready,
    output logic wvalid,
    output logic [511:0] wdata,
    output logic wlast, 
    output logic [(512/8)-1:0] wstrb, 

    input logic awready,
    output logic awvalid,
    output logic [11:0] awid,
    output logic [5:0] awuser,
    output logic [63:0] awaddr
);

enum logic [4:0] {
    STATE_IDLE,
    STATE_READ,
    STATE_WRITE
} state, next_state, 
eq_r_state, eq_r_next_state,
eq_w_state, eq_w_next_state;

logic [81:0] read_fifo_reg;
logic [81:0] read_fifo [15:0];
logic [4:0] read_r_ptr;
logic [4:0] read_w_ptr;
logic [4:0] read_buffer_rem;
assign read_buffer_rem = (read_w_ptr[4]==read_r_ptr[4]) ? (read_w_ptr-read_r_ptr) : ({1'b1, read_w_ptr[3:0]}-{1'b0, read_r_ptr[3:0]});
// assign rready = 1'b1;
// assign araddr = read_fifo[read_r_ptr[3:0]][63:0];
// assign aruser = read_fifo[read_r_ptr[3:0]][69:64];
// assign arid = read_fifo[read_r_ptr[3:0]][81:70];

logic [658:0] write_fifo_reg;
logic [658:0] write_fifo [15:0];
logic [4:0] write_r_ptr;
logic [4:0] write_w_ptr;
logic [4:0] write_buffer_rem;
assign write_buffer_rem = (write_w_ptr[4]==write_r_ptr[4]) ? (write_w_ptr-write_r_ptr) : ({1'b1, write_w_ptr[3:0]}-{1'b0, write_r_ptr[3:0]});
// assign bready = 1'b1;

logic aw_handshake;
logic w_handshake;

// assign awaddr = write_fifo[write_r_ptr[3:0]][63:0];
// assign awuser = write_fifo[write_r_ptr[3:0]][69:64];
// assign awid = write_fifo[write_r_ptr[3:0]][81:70];
// assign wstrb = write_fifo[write_r_ptr[3:0]][145:82];
// assign wlast = write_fifo[write_r_ptr[3:0]][146];
// assign wdata = write_fifo[write_r_ptr[3:0]][658:147];

//receive read request
always_ff @(posedge axi4_mm_clk) begin
    if (!axi4_mm_rst_n) begin
        eq_r_state <= STATE_IDLE;
        read_w_ptr <= 5'b0;
        arready_ch <= '{default: 1'b0};
    end
    else begin
        arready_ch <= '{default: 1'b0};
        eq_r_state <= eq_r_next_state;

        unique case (eq_r_state) 
            STATE_IDLE: begin
                if (read_buffer_rem < 5'd16) begin
                    for (int i=0; i < RD_CH; i++) begin
                        if (arvalid_ch[i]) begin
                            arready_ch[i] <= 1'b1;
                            read_fifo_reg <= {arid_ch[i], aruser_ch[i], araddr_ch[i]};
                            break;
                        end
                    end 
                end
            end

            STATE_READ: begin
                read_fifo[read_w_ptr[3:0]] <= read_fifo_reg;
                read_w_ptr <= read_w_ptr + 5'b1;
            end
            default: begin

            end
        endcase
    end
end

always_comb begin
    eq_r_next_state = STATE_IDLE;

    unique case (eq_r_state)
        STATE_IDLE: begin
            if (read_buffer_rem < 5'd16) begin
                for (int i=0; i < RD_CH; i++) begin
                    if (arvalid_ch[i]) begin
                        eq_r_next_state = STATE_READ;
                        break;
                    end
                end 
            end
            else begin
                eq_r_next_state = STATE_IDLE;
            end
        end
        STATE_READ: begin
            eq_r_next_state = STATE_IDLE;
        end
        default: begin
            eq_r_next_state = STATE_IDLE;
        end
    endcase
end

//receive write request
always_ff @(posedge axi4_mm_clk) begin
    if (!axi4_mm_rst_n) begin
        eq_w_state <= STATE_IDLE;
        write_w_ptr <= 5'b0;
        awready_ch <= '{default: 1'b0};
        wready_ch <= '{default: 1'b0};
    end
    else begin
        eq_w_state <= eq_w_next_state;
        awready_ch <= '{default: 1'b0};
        wready_ch <= '{default: 1'b0};

        unique case (eq_w_state) 
            STATE_IDLE: begin
                if (write_buffer_rem < 5'd16) begin
                    for (int i=0; i < WR_CH; i++) begin
                        if (awvalid_ch[i]) begin
                            awready_ch[i] <= 1'b1;
                            wready_ch[i] <= 1'b1;
                            write_fifo_reg <= {wdata_ch[i], wlast_ch[i], wstrb_ch[i], awid_ch[i], awuser_ch[i], awaddr_ch[i]};
                            break;
                        end
                    end 
                end
            end
            STATE_WRITE: begin
                write_fifo[write_w_ptr[3:0]] <= write_fifo_reg;
                write_w_ptr <= write_w_ptr + 5'b1;
            end
            default: begin

            end
        endcase
    end
end

always_comb begin
    eq_w_next_state = STATE_IDLE;

    unique case (eq_w_state)
        STATE_IDLE: begin
            if (write_buffer_rem < 5'd16) begin
                for (int i=0; i < WR_CH; i++) begin
                    if (awvalid_ch[i]) begin
                        eq_w_next_state = STATE_WRITE;
                        break;
                    end
                end 
            end
            else begin
                eq_w_next_state = STATE_IDLE;
            end
        end
        STATE_WRITE: begin
            eq_w_next_state = STATE_IDLE;
        end
        default: begin
            eq_w_next_state = STATE_IDLE;
        end
    endcase
end

//send read/write request 
always_ff @(posedge axi4_mm_clk) begin
    if (!axi4_mm_rst_n) begin
        state <= STATE_IDLE;
        read_r_ptr <= 5'b0;
        write_r_ptr <= 5'b0;
    end
    else begin
        state <= next_state;

        araddr <= read_fifo[read_r_ptr[3:0]][63:0];
        aruser <= read_fifo[read_r_ptr[3:0]][69:64];
        arid <= read_fifo[read_r_ptr[3:0]][81:70];

        awaddr <= write_fifo[write_r_ptr[3:0]][63:0];
        awuser <= write_fifo[write_r_ptr[3:0]][69:64];
        awid <= write_fifo[write_r_ptr[3:0]][81:70];
        wstrb <= write_fifo[write_r_ptr[3:0]][145:82];
        wlast <= write_fifo[write_r_ptr[3:0]][146];
        wdata <= write_fifo[write_r_ptr[3:0]][658:147];

        if (state == STATE_READ) begin
            if (arready & arvalid) begin
                read_r_ptr <= read_r_ptr + 5'd1;
            end
        end
        if (state == STATE_WRITE) begin
            if (awready & awvalid) begin
                write_r_ptr <= write_r_ptr + 5'd1;
            end
        end 
    end
end

always_comb begin
    unique case(state)
        STATE_IDLE: begin
            if (write_buffer_rem > 5'd0) begin
                next_state = STATE_WRITE;
            end
            else if (read_buffer_rem > 5'd0) begin
                next_state = STATE_READ;
            end
            else begin
                next_state = STATE_IDLE;
            end
        end
        STATE_READ: begin
            if (arready & arvalid) begin
                next_state = STATE_IDLE;
            end
            else begin
                next_state = STATE_READ;
            end
        end
        STATE_WRITE: begin
            if (awready & awvalid) begin
                next_state = STATE_IDLE;
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

always_comb begin : READ_WRITE
    arvalid = 1'b0;
    awvalid = 1'b0;
    wvalid = 1'b0;
    unique case(state)
        STATE_READ: begin
            arvalid = 1'b1;
        end
        STATE_WRITE: begin
            awvalid = 1'b1;
            wvalid = 1'b1;
        end
        default: begin

        end
    endcase
end

// //performance counter
// (* preserve_for_debug *) logic [31:0] ar_cnt;
// (* preserve_for_debug *) logic [31:0] aw_cnt;
// (* preserve_for_debug *) logic [31:0] r_cnt;
// (* preserve_for_debug *) logic [31:0] b_cnt;
// (* preserve_for_debug *) logic [31:0] read_max_delay;
// (* preserve_for_debug *) logic [31:0] write_max_delay;
// (* preserve_for_debug *) logic [31:0] read_min_delay;
// (* preserve_for_debug *) logic [31:0] write_min_delay;

// logic [11:0] arid_reg;
// logic [11:0] awid_reg;
// logic [31:0] delay_reg;

// always_ff@(posedge axi4_mm_clk) begin
//     if (!axi4_mm_rst_n) begin
//         pc_state <= STATE_IDLE;
//         read_max_delay <= '0;
//         write_max_delay <= '0;
//         read_min_delay <= '1;
//         write_min_delay <= '1;
//         ar_cnt <= 32'b0;
//         aw_cnt <= 32'b0;
//         r_cnt <= 32'b0;
//         b_cnt <= 32'b0;
//     end
//     else begin
//         if (arvalid & arready) begin
//             ar_cnt <= ar_cnt + 1'b1;
//         end
//         if (awvalid & awready) begin
//             aw_cnt <= aw_cnt + 1'b1;
//         end
//         if (rvalid & rready) begin
//             r_cnt <= r_cnt + 1'b1;
//         end
//         if (bvalid & bready) begin
//             b_cnt <= b_cnt + 1'b1;
//         end

//         if (pc_state == STATE_IDLE) begin
//             delay_reg <= 32'b0;
//             if (arvalid & arready) begin
//                 pc_state <= STATE_READ;
//                 arid_reg <= arid;
//             end
//             else if (awvalid & awready) begin
//                 pc_state <= STATE_WRITE;
//                 awid_reg <= awid;
//             end
//         end
//         else if (pc_state == STATE_READ) begin
//             delay_reg <= delay_reg + 1'b1;
//             if (rvalid & rready) begin
//                 if (rid == arid_reg) begin
//                     pc_state <= STATE_IDLE;
//                     if (delay_reg > read_max_delay) begin
//                         read_max_delay <= delay_reg;
//                     end
//                     if (delay_reg < read_min_delay) begin
//                         read_min_delay <= delay_reg;
//                     end
//                 end
//                 else begin
//                     pc_state <= STATE_READ;
//                 end
//             end
//         end
//         else if (pc_state == STATE_WRITE) begin
//             delay_reg <= delay_reg + 1'b1;
//             if (bvalid & bready) begin
//                 if (bid == awid_reg) begin
//                     pc_state <= STATE_IDLE;
//                     if (delay_reg > write_max_delay) begin
//                         write_max_delay <= delay_reg;
//                     end
//                     if (delay_reg < write_min_delay) begin
//                         write_min_delay <= delay_reg;
//                     end
//                 end
//                 else begin
//                     pc_state <= STATE_WRITE;
//                 end
//             end
//         end
//     end
// end



endmodule