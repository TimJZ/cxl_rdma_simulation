module afu_mc

import ed_mc_axi_if_pkg::*;
(
    input logic afu_clk,
    input logic afu_rstn,
    //from afu_top 
    input ed_mc_axi_if_pkg::t_to_mc_axi4 [MC_CHANNEL-1:0] iafu2mc_to_nvme_axi4,
    output ed_mc_axi_if_pkg::t_from_mc_axi4 [MC_CHANNEL-1:0] mc2iafu_from_nvme_axi4
);

enum logic [2:0] {
    STATE_IDLE,
    STATE_RESP
}   state_r0, state_r0_next, state_r1, state_r1_next, state_w0, state_w0_next, state_w1, state_w1_next;

logic [7:0] rid_reg[1:0];
logic [7:0] bid_reg[1:0];

logic [511:0] afu_mc_reg [1023:0];
logic [511:0] rdata_reg;

always_ff @(posedge afu_clk) begin
    if (!afu_rstn) begin
        state_r0 <= STATE_IDLE;
        state_r1 <= STATE_IDLE;
        state_w0 <= STATE_IDLE;
        state_w1 <= STATE_IDLE;
    end
    else begin
        state_r0 <= state_r0_next;
        state_r1 <= state_r1_next;
        state_w0 <= state_w0_next;
        state_w1 <= state_w1_next;

        if (iafu2mc_to_nvme_axi4[0].arvalid && mc2iafu_from_nvme_axi4[0].arready) begin
            rid_reg[0] <= iafu2mc_to_nvme_axi4[0].arid;
            rdata_reg <= afu_mc_reg[iafu2mc_to_nvme_axi4[0].araddr[15:6]];
            $display("MC ar[0] handshake");
            $display("arid is %d, araddr is %h", iafu2mc_to_nvme_axi4[0].arid, iafu2mc_to_nvme_axi4[0].araddr);
        end
        if (iafu2mc_to_nvme_axi4[1].arvalid && mc2iafu_from_nvme_axi4[1].arready) begin
            rid_reg[1] <= iafu2mc_to_nvme_axi4[1].arid;
            rdata_reg <= afu_mc_reg[iafu2mc_to_nvme_axi4[1].araddr[15:6]];
            $display("MC ar[1] handshake");
            $display("arid is %d, araddr is %h", iafu2mc_to_nvme_axi4[1].arid, iafu2mc_to_nvme_axi4[1].araddr);
        end

        if (iafu2mc_to_nvme_axi4[0].awvalid && mc2iafu_from_nvme_axi4[0].awready) begin
            bid_reg[0] <= iafu2mc_to_nvme_axi4[0].awid;
            afu_mc_reg[iafu2mc_to_nvme_axi4[0].awaddr[15:6]] <= iafu2mc_to_nvme_axi4[0].wdata;
            $display("MC aw[0] handshake");
            $display("awid is %d, awaddr is %h", iafu2mc_to_nvme_axi4[0].awid, iafu2mc_to_nvme_axi4[0].awaddr);
            $display("wdata is %h", iafu2mc_to_nvme_axi4[0].wdata);
        end
        if (iafu2mc_to_nvme_axi4[1].awvalid && mc2iafu_from_nvme_axi4[1].awready) begin
            bid_reg[1] <= iafu2mc_to_nvme_axi4[1].awid;
            afu_mc_reg[iafu2mc_to_nvme_axi4[1].awaddr[15:6]] <= iafu2mc_to_nvme_axi4[1].wdata;
            $display("MC aw[1] handshake");
            $display("awid is %d, awaddr is %h", iafu2mc_to_nvme_axi4[1].awid, iafu2mc_to_nvme_axi4[1].awaddr);
            $display("wdata is %h", iafu2mc_to_nvme_axi4[1].wdata);
        end

        if (iafu2mc_to_nvme_axi4[0].rready && mc2iafu_from_nvme_axi4[0].rvalid) begin
            $display("rdata is %h", mc2iafu_from_nvme_axi4[0].rdata);
        end

        if (iafu2mc_to_nvme_axi4[1].rready && mc2iafu_from_nvme_axi4[1].rvalid) begin
            $display("rdata is %h", mc2iafu_from_nvme_axi4[1].rdata);
        end

    end
end

always_comb begin: r0
    mc2iafu_from_nvme_axi4[0].rdata = rdata_reg;
    unique case(state_r0)
        STATE_IDLE: begin
            mc2iafu_from_nvme_axi4[0].rvalid = 1'b0;
            mc2iafu_from_nvme_axi4[0].arready = 1'b1;
            if (iafu2mc_to_nvme_axi4[0].arvalid) begin
                state_r0_next = STATE_RESP;
            end
            else begin
                state_r0_next = STATE_IDLE;
            end
            mc2iafu_from_nvme_axi4[0].rresp = 2'b00;
            mc2iafu_from_nvme_axi4[0].rid = rid_reg[0];
            mc2iafu_from_nvme_axi4[0].rlast = 1'b0;
            mc2iafu_from_nvme_axi4[0].ruser = 1'b0; //TODO: not sure
        end
        STATE_RESP: begin
            mc2iafu_from_nvme_axi4[0].arready = 1'b0;
            mc2iafu_from_nvme_axi4[0].rvalid = 1'b1;
            mc2iafu_from_nvme_axi4[0].rresp = 2'b00;
            mc2iafu_from_nvme_axi4[0].rid = rid_reg[0];
            mc2iafu_from_nvme_axi4[0].rlast = 1'b1;
            mc2iafu_from_nvme_axi4[0].ruser = 1'b0; //TODO: not sure
            if (mc2iafu_from_nvme_axi4[0].rvalid & iafu2mc_to_nvme_axi4[0].rready) begin
                state_r0_next = STATE_IDLE;
            end
            else begin
                state_r0_next = STATE_RESP;
            end
        end
        default: begin
            state_r0_next = STATE_IDLE;
            mc2iafu_from_nvme_axi4[0].arready = 1'b0;
            mc2iafu_from_nvme_axi4[0].rvalid = 1'b0;
            mc2iafu_from_nvme_axi4[0].rresp = 2'b00;
            mc2iafu_from_nvme_axi4[0].rid = rid_reg[0];
            mc2iafu_from_nvme_axi4[0].rlast = 1'b0;
            mc2iafu_from_nvme_axi4[0].ruser = 1'b0; //TODO: not sure
        end
    endcase
end

always_comb begin: r1
    mc2iafu_from_nvme_axi4[1].rdata = rdata_reg;
    unique case(state_r1)
        STATE_IDLE: begin
            mc2iafu_from_nvme_axi4[1].rvalid = 1'b0;
            mc2iafu_from_nvme_axi4[1].arready = 1'b1;
            if (iafu2mc_to_nvme_axi4[1].arvalid) begin
                state_r1_next = STATE_RESP;
            end
            else begin
                state_r1_next = STATE_IDLE;
            end
            mc2iafu_from_nvme_axi4[1].rresp = 2'b00;
            mc2iafu_from_nvme_axi4[1].rid = rid_reg[1];
            mc2iafu_from_nvme_axi4[1].rlast = 1'b0;
            mc2iafu_from_nvme_axi4[1].ruser = 1'b0; //TODO: not sure
        end
        STATE_RESP: begin
            mc2iafu_from_nvme_axi4[1].arready = 1'b0;
            mc2iafu_from_nvme_axi4[1].rvalid = 1'b1;
            if (mc2iafu_from_nvme_axi4[1].rvalid & iafu2mc_to_nvme_axi4[1].rready) begin
                state_r1_next = STATE_IDLE;
            end
            else begin
                state_r1_next = STATE_RESP;
            end
            mc2iafu_from_nvme_axi4[1].rresp = 2'b00;
            mc2iafu_from_nvme_axi4[1].rid = rid_reg[1];
            mc2iafu_from_nvme_axi4[1].rlast = 1'b1;
            mc2iafu_from_nvme_axi4[1].ruser = 1'b0; //TODO: not sure
        end
        default: begin
            state_r1_next = STATE_IDLE;
            mc2iafu_from_nvme_axi4[1].arready = 1'b0;
            mc2iafu_from_nvme_axi4[1].rvalid = 1'b0;
            mc2iafu_from_nvme_axi4[1].rresp = 2'b00;
            mc2iafu_from_nvme_axi4[1].rid = rid_reg[1];
            mc2iafu_from_nvme_axi4[1].rlast = 1'b0;
            mc2iafu_from_nvme_axi4[1].ruser = 1'b0; //TODO: not sure
        end
    endcase
end

always_comb begin: w0
    mc2iafu_from_nvme_axi4[0].bid = bid_reg[0];
    mc2iafu_from_nvme_axi4[0].buser = 1'b0; //TODO: not sure
    unique case(state_w0)
        STATE_IDLE: begin
            mc2iafu_from_nvme_axi4[0].bvalid = 1'b0;
            mc2iafu_from_nvme_axi4[0].awready = 1'b1;
            mc2iafu_from_nvme_axi4[0].wready = 1'b1;
            if (iafu2mc_to_nvme_axi4[0].awvalid) begin
                state_w0_next = STATE_RESP;
            end
            else begin
                state_w0_next = STATE_IDLE;
            end
        end
        STATE_RESP: begin
            mc2iafu_from_nvme_axi4[0].awready = 1'b0;
            mc2iafu_from_nvme_axi4[0].wready = 1'b0;
            mc2iafu_from_nvme_axi4[0].bvalid = 1'b1;
            if (mc2iafu_from_nvme_axi4[0].bvalid & iafu2mc_to_nvme_axi4[0].bready) begin
                state_w0_next = STATE_IDLE;
            end
            else begin
                state_w0_next = STATE_RESP;
            end
        end
        default: begin
            state_w0_next = STATE_IDLE;
            mc2iafu_from_nvme_axi4[0].awready = 1'b0;
            mc2iafu_from_nvme_axi4[0].wready = 1'b0;
            mc2iafu_from_nvme_axi4[0].bvalid = 1'b0;
        end
    endcase
end

always_comb begin: w1
    mc2iafu_from_nvme_axi4[1].bid = bid_reg[1];
    mc2iafu_from_nvme_axi4[1].buser = 1'b0; //TODO: not sure
    unique case(state_w1)
        STATE_IDLE: begin
            mc2iafu_from_nvme_axi4[1].bvalid = 1'b0;
            mc2iafu_from_nvme_axi4[1].awready = 1'b1;
            mc2iafu_from_nvme_axi4[1].wready = 1'b1;
            if (iafu2mc_to_nvme_axi4[1].awvalid) begin
                state_w1_next = STATE_RESP;
            end
            else begin
                state_w1_next = STATE_IDLE;
            end
        end
        STATE_RESP: begin
            mc2iafu_from_nvme_axi4[1].awready = 1'b0;
            mc2iafu_from_nvme_axi4[1].wready = 1'b0;
            mc2iafu_from_nvme_axi4[1].bvalid = 1'b1;
            if (mc2iafu_from_nvme_axi4[1].bvalid & iafu2mc_to_nvme_axi4[1].bready) begin
                state_w1_next = STATE_IDLE;
            end
            else begin
                state_w1_next = STATE_RESP;
            end
        end
        default: begin
            state_w1_next = STATE_IDLE;
            mc2iafu_from_nvme_axi4[1].awready = 1'b0;
            mc2iafu_from_nvme_axi4[1].wready = 1'b0;
            mc2iafu_from_nvme_axi4[1].bvalid = 1'b0;
        end
    endcase
end

endmodule