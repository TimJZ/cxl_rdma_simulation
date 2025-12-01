/*
Module: afu_nvme
Purpose: control nvme operations
Date: 4/19/25
Version: 2.0
Log:    12/17/24 modify to cxl cache version
        4/19/25 merge wfifo and rfifo
*/

module afu_nvme

import ed_cxlip_top_pkg::*;
import ed_mc_axi_if_pkg::*;
import cafu_common_pkg::*;
#(parameter CH = 2) //number of read/write channel
(
    input logic afu_clk,
    input logic afu_rstn,

    //to IAFU
    input ed_mc_axi_if_pkg::t_to_mc_axi4 [MC_CHANNEL-1:0] iafu2mc_to_nvme_axi4,
    output ed_mc_axi_if_pkg::t_from_mc_axi4 [MC_CHANNEL-1:0] mc2iafu_from_nvme_axi4,

    //to CAFU
    input logic i_end_proc,
    input logic [63:0] i_delay_cnt,

    output logic        rd_valid[CH-1:0],
    output logic        rd_return_ready[CH-1:0],
    input logic         rd_ready[CH-1:0],
    input logic         rd_return_valid[CH-1:0],
    output logic [63:0] rd_araddr[CH-1:0],
    input logic [511:0] rd_rdata[CH-1:0],

    output logic            wr_valid[CH-1:0],
    output logic            wr_return_ready[CH-1:0],
    input logic             wr_ready[CH-1:0],
    input logic             wr_return_valid[CH-1:0],
    output logic [63:0]     wr_awaddr[CH-1:0],
    output logic [511:0]    wr_wdata[CH-1:0],
    output logic [63:0]     wr_wstrb[CH-1:0]
);

enum logic [2:0] {
    STATE_IDLE,
    STATE_CHECK,
    STATE_CAFU_R,
    STATE_WAIT_R,
    STATE_RESP_R,
    STATE_CAFU_W,
    STATE_WAIT_W,
    STATE_RESP_W
}   state_r[1:0], state_r_next[1:0];


logic wrreq_r[1:0];
logic rdreq_r[1:0];
logic rdempty_r[1:0];
logic wrfull_r[1:0];
ed_mc_axi_if_pkg::t_to_mc_axi4 rfifo_data [1:0];
ed_mc_axi_if_pkg::t_to_mc_axi4 rfifo_q [1:0];

assign rfifo_data[0] = iafu2mc_to_nvme_axi4[0];
assign rfifo_data[1] = iafu2mc_to_nvme_axi4[1];

genvar i;
generate 
    for (i=0; i<2; i++) begin : afu_nvme_ch
        //merge rfifo and wfifo
        nvme_fifo nvme_fifo_inst(
            .data(rfifo_data[i]),    //  fifo_input.datain
            .wrreq(wrreq_r[i]),   //            .wrreq
            .rdreq(rdreq_r[i]),   //            .rdreq
            .wrclk(afu_clk),   //            .wrclk
            .rdclk(afu_clk),   //            .rdclk
            .q(rfifo_q[i]),       // fifo_output.dataout
            .rdempty(rdempty_r[i]), //            .rdempty
            .wrfull(wrfull_r[i])   //            .wrfull
        );

        assign rd_araddr[i] = {12'b0, rfifo_q[i].araddr};
        assign wr_awaddr[i] = {12'b0, rfifo_q[i].awaddr};
        assign wr_wdata[i] = rfifo_q[i].wdata;
        assign wr_wstrb[i] = rfifo_q[i].wstrb;

        always_ff @(posedge afu_clk) begin
            if (!afu_rstn) begin
                state_r[i] <= STATE_IDLE;
            end
            else if (i_end_proc) begin
                state_r[i] <= STATE_IDLE;
            end
            else begin
                state_r[i] <= state_r_next[i];
            end
        end

        always_comb begin
            mc2iafu_from_nvme_axi4[i].arready = !wrfull_r[i];
            mc2iafu_from_nvme_axi4[i].awready = !wrfull_r[i];
            mc2iafu_from_nvme_axi4[i].wready = !wrfull_r[i];
            //read channel
            
            //set default
            state_r_next[i] = STATE_IDLE;
            rdreq_r[i] = 1'b0;

            mc2iafu_from_nvme_axi4[i].rvalid = 1'b0;
            mc2iafu_from_nvme_axi4[i].rid = 8'b0;
            mc2iafu_from_nvme_axi4[i].rlast = 1'b0;
            mc2iafu_from_nvme_axi4[i].ruser = 1'b0; //TODO: not sure
            mc2iafu_from_nvme_axi4[i].rdata = 512'b0;
            mc2iafu_from_nvme_axi4[i].rresp = cafu_common_pkg::eresp_CAFU_OKAY;  //SIMU
            rd_valid[i] = 1'b0;
            rd_return_ready[i] = 1'b0;

            mc2iafu_from_nvme_axi4[i].bid = 8'b0;
            mc2iafu_from_nvme_axi4[i].buser = 1'b0; //TODO: not sure
            mc2iafu_from_nvme_axi4[i].bvalid = 1'b0;
            mc2iafu_from_nvme_axi4[i].bresp = cafu_common_pkg::eresp_CAFU_OKAY;
            wr_valid[i] = 1'b0;
            wr_return_ready[i] = 1'b0;

            //control fifo read
            if (wrfull_r[i]) begin
                wrreq_r[i] = 1'b0;
            end
            else begin
                if (iafu2mc_to_nvme_axi4[i].arvalid) begin
                    wrreq_r[i] = 1'b1;
                end
                else if (iafu2mc_to_nvme_axi4[i].awvalid) begin
                    wrreq_r[i] = 1'b1;
                end
                else begin
                    wrreq_r[i] = 1'b0;
                end
            end
            
            //control state machine
            unique case(state_r[i])
                STATE_IDLE: begin
                    if (!rdempty_r[i]) begin
                        state_r_next[i] = STATE_CHECK;
                        rdreq_r[i] = 1'b1;
                    end
                    else begin
                        state_r_next[i] = STATE_IDLE;
                        rdreq_r[i] = 1'b0;
                    end            
                end
                STATE_CHECK: begin
                    if (rfifo_q[i].arvalid) begin
                        state_r_next[i] = STATE_CAFU_R;
                    end
                    else if (rfifo_q[i].awvalid) begin
                        state_r_next[i] = STATE_CAFU_W;
                    end
                    else begin
                        state_r_next[i] = STATE_IDLE;
                    end
                end
                STATE_CAFU_R: begin
                    rd_valid[i] = 1'b1;
                    if (rd_ready[i] && rd_valid[i]) begin
                        state_r_next[i] = STATE_WAIT_R;
                    end
                    else begin
                        state_r_next[i] = STATE_CAFU_R;
                    end       
                end
                STATE_WAIT_R: begin
                    rd_return_ready[i] = 1'b1;
                    if (rd_return_ready[i] && rd_return_valid[i]) begin
                        state_r_next[i] = STATE_RESP_R;
                    end
                    else begin
                        state_r_next[i] = STATE_WAIT_R;
                    end
                end
                STATE_RESP_R: begin
                    mc2iafu_from_nvme_axi4[i].rdata = rd_rdata[i];
                    mc2iafu_from_nvme_axi4[i].rvalid = 1'b1;
                    mc2iafu_from_nvme_axi4[i].rid = rfifo_q[i].arid;
                    mc2iafu_from_nvme_axi4[i].rlast = 1'b1;
                    mc2iafu_from_nvme_axi4[i].ruser = 1'b0; //TODO: not sure
                    if (mc2iafu_from_nvme_axi4[i].rvalid & iafu2mc_to_nvme_axi4[i].rready) begin
                        state_r_next[i] = STATE_IDLE;
                    end
                    else begin
                        state_r_next[i] = STATE_RESP_R;
                    end
                end

                STATE_CAFU_W: begin
                    wr_valid[i] = 1'b1;
                    if (wr_valid[i] && wr_ready[i]) begin
                        state_r_next[i] = STATE_WAIT_W;
                    end
                    else begin
                        state_r_next[i] = STATE_CAFU_W;
                    end       
                end
                STATE_WAIT_W: begin
                    wr_return_ready[i] = 1'b1;
                    if (wr_return_ready[i] && wr_return_valid[i]) begin
                        state_r_next[i] = STATE_RESP_W;
                    end
                    else begin
                        state_r_next[i] = STATE_WAIT_W;
                    end
                end
                STATE_RESP_W: begin
                    mc2iafu_from_nvme_axi4[i].bvalid = 1'b1;
                    mc2iafu_from_nvme_axi4[i].bid = rfifo_q[i].awid;
                    mc2iafu_from_nvme_axi4[i].buser = 1'b0; //TODO: not sure
                    if (mc2iafu_from_nvme_axi4[i].bvalid & iafu2mc_to_nvme_axi4[i].bready) begin
                        state_r_next[i] = STATE_IDLE;
                    end
                    else begin
                        state_r_next[i] = STATE_RESP_W;
                    end
                end

                default: begin

                end
            endcase
        end
    end
endgenerate

endmodule