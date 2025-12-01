// (C) 2001-2024 Intel Corporation. All rights reserved.
// Your use of Intel Corporation's design tools, logic functions and other 
// software and tools, and its AMPP partner logic functions, and any output 
// files from any of the foregoing (including device programming or simulation 
// files), and any associated documentation or information are expressly subject 
// to the terms and conditions of the Intel Program License Subscription 
// Agreement, Intel FPGA IP License Agreement, or other applicable 
// license agreement, including, without limitation, that your use is for the 
// sole purpose of programming logic devices manufactured by Intel and sold by 
// Intel or its authorized distributors.  Please refer to the applicable 
// agreement for further details.


// Copyright 2023 Intel Corporation.
//
// THIS SOFTWARE MAY CONTAIN PREPRODUCTION CODE AND IS PROVIDED BY THE
// COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED
// WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF
// MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
// DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
// LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
// CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
// SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR
// BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
// WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE
// OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE,
// EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//
///////////////////////////////////////////////////////////////////////




module afu_top

import ed_mc_axi_if_pkg::*;
(
    
      input  logic                                             afu_clk,
      input  logic                                             afu_rstn,
     // April 2023 - Supporting out of order responses with AXI4
      input  ed_mc_axi_if_pkg::t_to_mc_axi4    [MC_CHANNEL-1:0] cxlip2iafu_to_mc_axi4,
      output ed_mc_axi_if_pkg::t_to_mc_axi4    [MC_CHANNEL-1:0] iafu2mc_to_mc_axi4 ,
      input  ed_mc_axi_if_pkg::t_from_mc_axi4  [MC_CHANNEL-1:0] mc2iafu_from_mc_axi4,
      output ed_mc_axi_if_pkg::t_from_mc_axi4  [MC_CHANNEL-1:0] iafu2cxlip_from_mc_axi4,

      input logic [63:0] afu_init,
      
      //signal to NVMe controller
      input  ed_mc_axi_if_pkg::t_to_mc_axi4    [MC_CHANNEL-1:0] nvme2iafu_to_mc_axi4,
      output ed_mc_axi_if_pkg::t_from_mc_axi4 [MC_CHANNEL-1:0] iafu2nvme_from_mc_axi4,

      output ed_mc_axi_if_pkg::t_to_mc_axi4 [MC_CHANNEL-1:0] iafu2mc_to_nvme_axi4 ,
      input ed_mc_axi_if_pkg::t_from_mc_axi4 [MC_CHANNEL-1:0] mc2iafu_from_nvme_axi4
);

      logic afu_init_reg;

      ed_mc_axi_if_pkg::t_to_mc_axi4 cxlip2iafu_to_mc_axi4_reg [1:0];

      enum logic [2:0] {
            STATE_IDLE,
            STATE_RUN_W,
            STATE_RUN_R,
            STATE_RUN_W_WAIT,
            STATE_RUN_R_WAIT
      } state[1:0], next_state[1:0];

      always_ff @(posedge afu_clk) begin
            if (!afu_rstn) begin
                  afu_init_reg <= 1'b0;
            end
            else begin
                  if (afu_init[0] == 1'b1) begin
                        afu_init_reg <= 1'b1;
                  end
            end
      end

      always_comb begin
            iafu2mc_to_mc_axi4 = nvme2iafu_to_mc_axi4;
            iafu2nvme_from_mc_axi4 = mc2iafu_from_mc_axi4;
      end

      always_ff @(posedge afu_clk) begin
            for (int i=0; i<2; i++) begin
                  if (!afu_rstn) begin
                        state[i] <= STATE_IDLE;
                  end
                  else begin
                        state[i] <= next_state[i];
                  end

                  unique case (state[i]) 
                        STATE_IDLE: begin
                              cxlip2iafu_to_mc_axi4_reg[i] <= cxlip2iafu_to_mc_axi4[i];
                        end
                        default: begin

                        end
                  endcase
            end
      end
      
      always_comb begin
            for (int i=0; i<2; i++) begin
                  next_state[i] = STATE_IDLE;

                  iafu2cxlip_from_mc_axi4[i].arready = 1'b0;
                  iafu2cxlip_from_mc_axi4[i].awready = 1'b0;
                  iafu2cxlip_from_mc_axi4[i].wready  = 1'b0;

                  iafu2cxlip_from_mc_axi4[i].bid       = mc2iafu_from_nvme_axi4[i].bid;
                  iafu2cxlip_from_mc_axi4[i].bresp     = mc2iafu_from_nvme_axi4[i].bresp;
                  iafu2cxlip_from_mc_axi4[i].bvalid    = mc2iafu_from_nvme_axi4[i].bvalid;
                  iafu2cxlip_from_mc_axi4[i].buser     = mc2iafu_from_nvme_axi4[i].buser;

                  iafu2cxlip_from_mc_axi4[i].rid       = mc2iafu_from_nvme_axi4[i].rid;
                  iafu2cxlip_from_mc_axi4[i].rdata     = mc2iafu_from_nvme_axi4[i].rdata;
                  iafu2cxlip_from_mc_axi4[i].rresp     = mc2iafu_from_nvme_axi4[i].rresp;
                  iafu2cxlip_from_mc_axi4[i].rvalid    = mc2iafu_from_nvme_axi4[i].rvalid;
                  iafu2cxlip_from_mc_axi4[i].rlast     = mc2iafu_from_nvme_axi4[i].rlast;
                  iafu2cxlip_from_mc_axi4[i].ruser     = mc2iafu_from_nvme_axi4[i].ruser;

                  iafu2mc_to_nvme_axi4[i].bready      = cxlip2iafu_to_mc_axi4[i].bready; //resp channel directly connect to ip
                  iafu2mc_to_nvme_axi4[i].rready      = cxlip2iafu_to_mc_axi4[i].rready;

                  iafu2mc_to_nvme_axi4[i].awid        = cxlip2iafu_to_mc_axi4_reg[i].awid;
                  iafu2mc_to_nvme_axi4[i].awaddr      = cxlip2iafu_to_mc_axi4_reg[i].awaddr;
                  iafu2mc_to_nvme_axi4[i].awlen       = cxlip2iafu_to_mc_axi4_reg[i].awlen;
                  iafu2mc_to_nvme_axi4[i].awsize      = cxlip2iafu_to_mc_axi4_reg[i].awsize;
                  iafu2mc_to_nvme_axi4[i].awburst     = cxlip2iafu_to_mc_axi4_reg[i].awburst;
                  iafu2mc_to_nvme_axi4[i].awprot      = cxlip2iafu_to_mc_axi4_reg[i].awprot;
                  iafu2mc_to_nvme_axi4[i].awqos       = cxlip2iafu_to_mc_axi4_reg[i].awqos;
                  iafu2mc_to_nvme_axi4[i].awvalid     = 1'b0;
                  iafu2mc_to_nvme_axi4[i].awcache     = cxlip2iafu_to_mc_axi4_reg[i].awcache;
                  iafu2mc_to_nvme_axi4[i].awlock      = cxlip2iafu_to_mc_axi4_reg[i].awlock;
                  iafu2mc_to_nvme_axi4[i].awregion    = cxlip2iafu_to_mc_axi4_reg[i].awregion;
                  iafu2mc_to_nvme_axi4[i].awuser      = cxlip2iafu_to_mc_axi4_reg[i].awuser;

                  iafu2mc_to_nvme_axi4[i].wdata       = cxlip2iafu_to_mc_axi4_reg[i].wdata;
                  iafu2mc_to_nvme_axi4[i].wstrb       = cxlip2iafu_to_mc_axi4_reg[i].wstrb;
                  iafu2mc_to_nvme_axi4[i].wlast       = cxlip2iafu_to_mc_axi4_reg[i].wlast;
                  iafu2mc_to_nvme_axi4[i].wvalid      = '0;
                  iafu2mc_to_nvme_axi4[i].wuser       = cxlip2iafu_to_mc_axi4_reg[i].wuser;

                  iafu2mc_to_nvme_axi4[i].arid        = cxlip2iafu_to_mc_axi4_reg[i].arid;
                  iafu2mc_to_nvme_axi4[i].araddr      = cxlip2iafu_to_mc_axi4_reg[i].araddr;
                  iafu2mc_to_nvme_axi4[i].arlen       = cxlip2iafu_to_mc_axi4_reg[i].arlen;
                  iafu2mc_to_nvme_axi4[i].arsize      = cxlip2iafu_to_mc_axi4_reg[i].arsize;
                  iafu2mc_to_nvme_axi4[i].arburst     = cxlip2iafu_to_mc_axi4_reg[i].arburst;
                  iafu2mc_to_nvme_axi4[i].arprot      = cxlip2iafu_to_mc_axi4_reg[i].arprot;
                  iafu2mc_to_nvme_axi4[i].arqos       = cxlip2iafu_to_mc_axi4_reg[i].arqos;
                  iafu2mc_to_nvme_axi4[i].arvalid     = 1'b0;
                  iafu2mc_to_nvme_axi4[i].arcache     = cxlip2iafu_to_mc_axi4_reg[i].arcache;
                  iafu2mc_to_nvme_axi4[i].arlock      = cxlip2iafu_to_mc_axi4_reg[i].arlock;
                  iafu2mc_to_nvme_axi4[i].arregion    = cxlip2iafu_to_mc_axi4_reg[i].arregion;
                  iafu2mc_to_nvme_axi4[i].aruser      = cxlip2iafu_to_mc_axi4_reg[i].aruser;

                  unique case (state[i]) 
                        STATE_IDLE: begin
                              iafu2cxlip_from_mc_axi4[i].arready = 1'b1;
                              iafu2cxlip_from_mc_axi4[i].awready = 1'b1;
                              iafu2cxlip_from_mc_axi4[i].wready  = 1'b1;
                              if (cxlip2iafu_to_mc_axi4[i].awvalid) begin
                                    if (afu_init_reg == 1'b0) begin //not initialized yet
                                          next_state[i] = STATE_RUN_W_WAIT;
                                    end
                                    else begin
                                          next_state[i] = STATE_RUN_W;
                                    end
                              end
                              else if (cxlip2iafu_to_mc_axi4[i].arvalid) begin
                                    if (afu_init_reg == 1'b0) begin //not initialized yet
                                          next_state[i] = STATE_RUN_R_WAIT;
                                    end
                                    else begin
                                          next_state[i] = STATE_RUN_R;
                                    end
                              end
                              else begin
                                    next_state[i] = STATE_IDLE;
                              end
                        end
                        STATE_RUN_W: begin
                              iafu2mc_to_nvme_axi4[i].awvalid     = 1'b1;
                              iafu2mc_to_nvme_axi4[i].wvalid      = 1'b1;
                              if (mc2iafu_from_nvme_axi4[i].awready) begin
                                    next_state[i] = STATE_IDLE;
                              end
                              else begin
                                    next_state[i] = STATE_RUN_W;
                              end
                        end
                        STATE_RUN_W_WAIT: begin
                              iafu2cxlip_from_mc_axi4[i].bid       = cxlip2iafu_to_mc_axi4_reg[i].awid;
                              iafu2cxlip_from_mc_axi4[i].bvalid    = 1'b1;
                              if (cxlip2iafu_to_mc_axi4[i].bready) begin
                                    next_state[i] = STATE_IDLE;
                              end
                              else begin
                                    next_state[i] = STATE_RUN_W_WAIT;
                              end
                        end
                        STATE_RUN_R: begin
                              iafu2mc_to_nvme_axi4[i].arvalid   = 1'b1;
                              if (mc2iafu_from_nvme_axi4[i].arready) begin
                                    next_state[i] = STATE_IDLE;
                              end
                              else begin
                                    next_state[i] = STATE_RUN_R;
                              end
                        end
                        STATE_RUN_R_WAIT: begin
                              iafu2cxlip_from_mc_axi4[i].rid       = cxlip2iafu_to_mc_axi4_reg[i].arid;
                              iafu2cxlip_from_mc_axi4[i].rvalid    = 1'b1;
                              if (cxlip2iafu_to_mc_axi4[i].rready) begin
                                    next_state[i] = STATE_IDLE;
                              end
                              else begin
                                    next_state[i] = STATE_RUN_R_WAIT;
                              end
                        end
                        default: begin

                        end
                  endcase
            end
      end
      
//performance counter

(* preserve_for_debug *) logic [31:0] nvme_ar_cnt_0;
(* preserve_for_debug *) logic [31:0] nvme_ar_cnt_1;
(* preserve_for_debug *) logic [31:0] nvme_aw_cnt_0;
(* preserve_for_debug *) logic [31:0] nvme_aw_cnt_1;
(* preserve_for_debug *) logic [31:0] nvme_r_cnt_0;
(* preserve_for_debug *) logic [31:0] nvme_r_cnt_1;
(* preserve_for_debug *) logic [31:0] nvme_b_cnt_0;
(* preserve_for_debug *) logic [31:0] nvme_b_cnt_1;

(*preserve_for_debug  *) logic [31:0] afu_ar_cnt_0;
(*preserve_for_debug  *) logic [31:0] afu_ar_cnt_1;
(*preserve_for_debug  *) logic [31:0] afu_aw_cnt_0;
(*preserve_for_debug  *) logic [31:0] afu_aw_cnt_1;
(*preserve_for_debug  *) logic [31:0] afu_r_cnt_0;
(*preserve_for_debug  *) logic [31:0] afu_r_cnt_1;
(*preserve_for_debug  *) logic [31:0] afu_b_cnt_0;
(*preserve_for_debug  *) logic [31:0] afu_b_cnt_1;

(*preserve_for_debug  *) logic [31:0] mc_ar_cnt_0;
(*preserve_for_debug  *) logic [31:0] mc_ar_cnt_1;
(*preserve_for_debug  *) logic [31:0] mc_aw_cnt_0;
(*preserve_for_debug  *) logic [31:0] mc_aw_cnt_1;
(*preserve_for_debug  *) logic [31:0] mc_r_cnt_0;
(*preserve_for_debug  *) logic [31:0] mc_r_cnt_1;
(*preserve_for_debug  *) logic [31:0] mc_b_cnt_0;
(*preserve_for_debug  *) logic [31:0] mc_b_cnt_1;

logic [7:0] ar_ch_cnt_array_0 [7:0];
logic [7:0] ar_ch_cnt_array_1 [7:0];
(*preserve_for_debug*) logic [2:0] ar_ch_index_0;
(*preserve_for_debug*) logic [2:0] ar_ch_index_1;
(*preserve_for_debug*) logic [7:0]  ar_ch_cnt_0;
(*preserve_for_debug*) logic [7:0]  ar_ch_cnt_1;

logic [7:0] aw_ch_cnt_array_0 [7:0];
logic [7:0] aw_ch_cnt_array_1 [7:0];
(*preserve_for_debug*) logic [2:0] aw_ch_index_0;
(*preserve_for_debug*) logic [2:0] aw_ch_index_1;
(*preserve_for_debug*) logic [7:0]  aw_ch_cnt_0;
(*preserve_for_debug*) logic [7:0]  aw_ch_cnt_1;

logic [7:0] r_ch_cnt_array_0 [7:0];
logic [7:0] r_ch_cnt_array_1 [7:0];
(*preserve_for_debug*) logic [2:0] r_ch_index_0;
(*preserve_for_debug*) logic [2:0] r_ch_index_1;
(*preserve_for_debug*) logic [7:0]  r_ch_cnt_0;
(*preserve_for_debug*) logic [7:0]  r_ch_cnt_1;

logic [7:0] b_ch_cnt_array_0 [7:0];
logic [7:0] b_ch_cnt_array_1 [7:0];
(*preserve_for_debug*) logic [2:0] b_ch_index_0;
(*preserve_for_debug*) logic [2:0] b_ch_index_1;
(*preserve_for_debug*) logic [7:0]  b_ch_cnt_0;
(*preserve_for_debug*) logic [7:0]  b_ch_cnt_1;

logic [7:0] arid_array_0 [63:0];
logic [7:0] arid_array_1 [63:0];
logic [5:0] arid_wr_ptr_0;
logic [5:0] arid_wr_ptr_1;
(*preserve_for_debug*) logic [5:0] arid_index_0;
(*preserve_for_debug*) logic [5:0] arid_index_1;
(*preserve_for_debug*) logic [7:0] arid_reg_0;
(*preserve_for_debug*) logic [7:0] arid_reg_1;

logic [7:0] awid_array_0 [63:0];
logic [7:0] awid_array_1 [63:0];
logic [5:0] awid_wr_ptr_0;
logic [5:0] awid_wr_ptr_1;
(*preserve_for_debug*) logic [5:0] awid_index_0;
(*preserve_for_debug*) logic [5:0] awid_index_1;
(*preserve_for_debug*) logic [7:0] awid_reg_0;
(*preserve_for_debug*) logic [7:0] awid_reg_1;

logic [7:0] rid_array_0 [63:0];
logic [7:0] rid_array_1 [63:0];
logic [5:0] rid_wr_ptr_0;
logic [5:0] rid_wr_ptr_1;
(*preserve_for_debug*) logic [5:0] rid_index_0;
(*preserve_for_debug*) logic [5:0] rid_index_1;
(*preserve_for_debug*) logic [7:0] rid_reg_0;
(*preserve_for_debug*) logic [7:0] rid_reg_1;

logic [7:0] bid_array_0 [63:0];
logic [7:0] bid_array_1 [63:0];
logic [5:0] bid_wr_ptr_0;
logic [5:0] bid_wr_ptr_1;
(*preserve_for_debug*) logic [5:0] bid_index_0;
(*preserve_for_debug*) logic [5:0] bid_index_1;
(*preserve_for_debug*) logic [7:0] bid_reg_0;
(*preserve_for_debug*) logic [7:0] bid_reg_1;

always_ff@(posedge afu_clk) begin
      if ((!afu_rstn) || (!afu_init_reg)) begin
            nvme_ar_cnt_0 <= '0;
            nvme_ar_cnt_1 <= '0;
            nvme_aw_cnt_0 <= '0;
            nvme_aw_cnt_1 <= '0;
            nvme_r_cnt_0 <= '0;
            nvme_r_cnt_1 <= '0;
            nvme_b_cnt_0 <= '0;
            nvme_b_cnt_1 <= '0;

            afu_ar_cnt_0 <= '0;
            afu_ar_cnt_1 <= '0;
            afu_aw_cnt_0 <= '0;
            afu_aw_cnt_1 <= '0;
            afu_r_cnt_0 <= '0;
            afu_r_cnt_1 <= '0;
            afu_b_cnt_0 <= '0;
            afu_b_cnt_1 <= '0;

            mc_ar_cnt_0 <= '0;
            mc_ar_cnt_1 <= '0;
            mc_aw_cnt_0 <= '0;
            mc_aw_cnt_1 <= '0;
            mc_r_cnt_0 <= '0;
            mc_r_cnt_1 <= '0;
            mc_b_cnt_0 <= '0;
            mc_b_cnt_1 <= '0;

            r_ch_index_0 <= '0;
            r_ch_index_1 <= '0;
            b_ch_index_0 <= '0;
            b_ch_index_1 <= '0;
            ar_ch_index_0 <= '0;
            ar_ch_index_1 <= '0;
            aw_ch_index_0 <= '0;
            aw_ch_index_1 <= '0;

            for (int i=0; i<8; i++) begin
                  ar_ch_cnt_array_0[i] <= '0;
                  ar_ch_cnt_array_1[i] <= '0;
                  aw_ch_cnt_array_0[i] <= '0;
                  aw_ch_cnt_array_1[i] <= '0;
                  r_ch_cnt_array_0[i] <= '0;
                  r_ch_cnt_array_1[i] <= '0;
                  b_ch_cnt_array_0[i] <= '0;
                  b_ch_cnt_array_1[i] <= '0;
            end

            //-------------------------------
            arid_wr_ptr_0 <= '0;
            arid_wr_ptr_1 <= '0;
            arid_index_0 <= '0;
            arid_index_1 <= '0;

            awid_wr_ptr_0 <= '0;
            awid_wr_ptr_1 <= '0;
            awid_index_0 <= '0;
            awid_index_1 <= '0;

            rid_wr_ptr_0 <= '0;
            rid_wr_ptr_1 <= '0;
            rid_index_0 <= '0;
            rid_index_1 <= '0;

            bid_wr_ptr_0 <= '0;
            bid_wr_ptr_1 <= '0;
            bid_index_0 <= '0;
            bid_index_1 <= '0;
      end
      else begin
            if (iafu2mc_to_nvme_axi4[0].arvalid && mc2iafu_from_nvme_axi4[0].arready) begin
                  nvme_ar_cnt_0 <= nvme_ar_cnt_0 + 1;
            end
            if (iafu2mc_to_nvme_axi4[1].arvalid && mc2iafu_from_nvme_axi4[1].arready) begin
                  nvme_ar_cnt_1 <= nvme_ar_cnt_1 + 1;
            end
            if (iafu2mc_to_nvme_axi4[0].awvalid && mc2iafu_from_nvme_axi4[0].awready) begin
                  nvme_aw_cnt_0 <= nvme_aw_cnt_0 + 1;
            end
            if (iafu2mc_to_nvme_axi4[1].awvalid && mc2iafu_from_nvme_axi4[1].awready) begin
                  nvme_aw_cnt_1 <= nvme_aw_cnt_1 + 1;
            end
            if (mc2iafu_from_nvme_axi4[0].rvalid && iafu2mc_to_nvme_axi4[0].rready) begin
                  nvme_r_cnt_0 <= nvme_r_cnt_0 + 1;
            end
            if (mc2iafu_from_nvme_axi4[1].rvalid && iafu2mc_to_nvme_axi4[1].rready) begin
                  nvme_r_cnt_1 <= nvme_r_cnt_1 + 1;
            end
            if (mc2iafu_from_nvme_axi4[0].bvalid && iafu2mc_to_nvme_axi4[0].bready) begin
                  nvme_b_cnt_0 <= nvme_b_cnt_0 + 1;
            end
            if (mc2iafu_from_nvme_axi4[1].bvalid && iafu2mc_to_nvme_axi4[1].bready) begin
                  nvme_b_cnt_1 <= nvme_b_cnt_1 + 1;
            end

            //------------------------------
            if (nvme2iafu_to_mc_axi4[0].arvalid && iafu2nvme_from_mc_axi4[0].arready) begin
                  afu_ar_cnt_0 <= afu_ar_cnt_0 + 1;
            end
            if (nvme2iafu_to_mc_axi4[1].arvalid && iafu2nvme_from_mc_axi4[1].arready) begin
                  afu_ar_cnt_1 <= afu_ar_cnt_1 + 1;
            end
            if (nvme2iafu_to_mc_axi4[0].awvalid && iafu2nvme_from_mc_axi4[0].awready) begin
                  afu_aw_cnt_0 <= afu_aw_cnt_0 + 1;
            end
            if (nvme2iafu_to_mc_axi4[1].awvalid && iafu2nvme_from_mc_axi4[1].awready) begin
                  afu_aw_cnt_1 <= afu_aw_cnt_1 + 1;
            end
            if (iafu2nvme_from_mc_axi4[0].rvalid && nvme2iafu_to_mc_axi4[0].rready) begin
                  afu_r_cnt_0 <= afu_r_cnt_0 + 1;
            end
            if (iafu2nvme_from_mc_axi4[1].rvalid && nvme2iafu_to_mc_axi4[1].rready) begin
                  afu_r_cnt_1 <= afu_r_cnt_1 + 1;
            end
            if (iafu2nvme_from_mc_axi4[0].bvalid && nvme2iafu_to_mc_axi4[0].bready) begin
                  afu_b_cnt_0 <= afu_b_cnt_0 + 1;
            end
            if (iafu2nvme_from_mc_axi4[1].bvalid && nvme2iafu_to_mc_axi4[1].bready) begin
                  afu_b_cnt_1 <= afu_b_cnt_1 + 1;
            end

            //------------------------------
            if (iafu2mc_to_mc_axi4[0].arvalid && mc2iafu_from_mc_axi4[0].arready) begin
                  mc_ar_cnt_0 <= mc_ar_cnt_0 + 1;
                  ar_ch_cnt_array_0[iafu2mc_to_mc_axi4[0].arid[7:5]] <= ar_ch_cnt_array_0[iafu2mc_to_mc_axi4[0].arid[7:5]] + 1;
                  arid_array_0[arid_wr_ptr_0] <= iafu2mc_to_mc_axi4[0].arid;
                  arid_wr_ptr_0 <= arid_wr_ptr_0 + 1;
            end
            if (iafu2mc_to_mc_axi4[1].arvalid && mc2iafu_from_mc_axi4[1].arready) begin
                  mc_ar_cnt_1 <= mc_ar_cnt_1 + 1;
                  ar_ch_cnt_array_1[iafu2mc_to_mc_axi4[1].arid[7:5]] <= ar_ch_cnt_array_1[iafu2mc_to_mc_axi4[1].arid[7:5]] + 1;
                  arid_array_1[arid_wr_ptr_1] <= iafu2mc_to_mc_axi4[1].arid;
                  arid_wr_ptr_1 <= arid_wr_ptr_1 + 1;
            end
            if (iafu2mc_to_mc_axi4[0].awvalid && mc2iafu_from_mc_axi4[0].awready) begin
                  mc_aw_cnt_0 <= mc_aw_cnt_0 + 1;
                  aw_ch_cnt_array_0[iafu2mc_to_mc_axi4[0].awid[7:5]] <= aw_ch_cnt_array_0[iafu2mc_to_mc_axi4[0].awid[7:5]] + 1;
                  awid_array_0[awid_wr_ptr_0] <= iafu2mc_to_mc_axi4[0].awid;
                  awid_wr_ptr_0 <= awid_wr_ptr_0 + 1;
            end
            if (iafu2mc_to_mc_axi4[1].awvalid && mc2iafu_from_mc_axi4[1].awready) begin
                  mc_aw_cnt_1 <= mc_aw_cnt_1 + 1;
                  aw_ch_cnt_array_1[iafu2mc_to_mc_axi4[1].awid[7:5]] <= aw_ch_cnt_array_1[iafu2mc_to_mc_axi4[1].awid[7:5]] + 1;
                  awid_array_1[awid_wr_ptr_1] <= iafu2mc_to_mc_axi4[1].awid;
                  awid_wr_ptr_1 <= awid_wr_ptr_1 + 1;
            end
            if (mc2iafu_from_mc_axi4[0].rvalid && iafu2mc_to_mc_axi4[0].rready) begin
                  mc_r_cnt_0 <= mc_r_cnt_0 + 1;
                  r_ch_cnt_array_0[mc2iafu_from_mc_axi4[0].rid[7:5]] <= r_ch_cnt_array_0[mc2iafu_from_mc_axi4[0].rid[7:5]] + 1;
                  rid_array_0[rid_wr_ptr_0] <= mc2iafu_from_mc_axi4[0].rid;
                  rid_wr_ptr_0 <= rid_wr_ptr_0 + 1;
            end
            if (mc2iafu_from_mc_axi4[1].rvalid && iafu2mc_to_mc_axi4[1].rready) begin
                  mc_r_cnt_1 <= mc_r_cnt_1 + 1;
                  r_ch_cnt_array_1[mc2iafu_from_mc_axi4[1].rid[7:5]] <= r_ch_cnt_array_1[mc2iafu_from_mc_axi4[1].rid[7:5]] + 1;
                  rid_array_1[rid_wr_ptr_1] <= mc2iafu_from_mc_axi4[1].rid;
                  rid_wr_ptr_1 <= rid_wr_ptr_1 + 1;
            end
            if (mc2iafu_from_mc_axi4[0].bvalid && iafu2mc_to_mc_axi4[0].bready) begin
                  mc_b_cnt_0 <= mc_b_cnt_0 + 1;
                  b_ch_cnt_array_0[mc2iafu_from_mc_axi4[0].bid[7:5]] <= b_ch_cnt_array_0[mc2iafu_from_mc_axi4[0].bid[7:5]] + 1;
                  bid_array_0[bid_wr_ptr_0] <= mc2iafu_from_mc_axi4[0].bid;
                  bid_wr_ptr_0 <= bid_wr_ptr_0 + 1;
            end
            if (mc2iafu_from_mc_axi4[1].bvalid && iafu2mc_to_mc_axi4[1].bready) begin
                  mc_b_cnt_1 <= mc_b_cnt_1 + 1;
                  b_ch_cnt_array_1[mc2iafu_from_mc_axi4[1].bid[7:5]] <= b_ch_cnt_array_1[mc2iafu_from_mc_axi4[1].bid[7:5]] + 1;
                  bid_array_1[bid_wr_ptr_1] <= mc2iafu_from_mc_axi4[1].bid;
                  bid_wr_ptr_1 <= bid_wr_ptr_1 + 1;
            end

            r_ch_cnt_0 <= r_ch_cnt_array_0[r_ch_index_0];
            r_ch_cnt_1 <= r_ch_cnt_array_1[r_ch_index_1];
            b_ch_cnt_0 <= b_ch_cnt_array_0[b_ch_index_0];
            b_ch_cnt_1 <= b_ch_cnt_array_1[b_ch_index_1];
            ar_ch_cnt_0 <= ar_ch_cnt_array_0[ar_ch_index_0];
            ar_ch_cnt_1 <= ar_ch_cnt_array_1[ar_ch_index_1];
            aw_ch_cnt_0 <= aw_ch_cnt_array_0[aw_ch_index_0];
            aw_ch_cnt_1 <= aw_ch_cnt_array_1[aw_ch_index_1];
            r_ch_index_0 <= r_ch_index_0 + 1;
            r_ch_index_1 <= r_ch_index_1 + 1;
            b_ch_index_0 <= b_ch_index_0 + 1;
            b_ch_index_1 <= b_ch_index_1 + 1;
            ar_ch_index_0 <= ar_ch_index_0 + 1;
            ar_ch_index_1 <= ar_ch_index_1 + 1;
            aw_ch_index_0 <= aw_ch_index_0 + 1;
            aw_ch_index_1 <= aw_ch_index_1 + 1;


            arid_reg_0 <= arid_array_0[arid_index_0];
            if (arid_wr_ptr_0 != 0) begin
                  if (arid_index_0 + 1 == arid_wr_ptr_0) begin
                        arid_index_0 <= 0;
                  end
                  else begin
                        arid_index_0 <= arid_index_0 + 1;
                  end
            end

            arid_reg_1 <= arid_array_1[arid_index_1];
            if (arid_wr_ptr_1 != 0) begin
                  if (arid_index_1 + 1 == arid_wr_ptr_1) begin
                        arid_index_1 <= 0;
                  end
                  else begin
                        arid_index_1 <= arid_index_1 + 1;
                  end
            end

            awid_reg_0 <= awid_array_0[awid_index_0];
            if (awid_wr_ptr_0 != 0) begin
                  if (awid_index_0 + 1 == awid_wr_ptr_0) begin
                        awid_index_0 <= 0;
                  end
                  else begin
                        awid_index_0 <= awid_index_0 + 1;
                  end
            end

            awid_reg_1 <= awid_array_1[awid_index_1];
            if (awid_wr_ptr_1 != 0) begin
                  if (awid_index_1 + 1 == awid_wr_ptr_1) begin
                        awid_index_1 <= 0;
                  end
                  else begin
                        awid_index_1 <= awid_index_1 + 1;
                  end
            end

            rid_reg_0 <= rid_array_0[rid_index_0];
            if (rid_wr_ptr_0 != 0) begin
                  if (rid_index_0 + 1 == rid_wr_ptr_0) begin
                        rid_index_0 <= 0;
                  end
                  else begin
                        rid_index_0 <= rid_index_0 + 1;
                  end
            end

            rid_reg_1 <= rid_array_1[rid_index_1];
            if (rid_wr_ptr_1 != 0) begin
                  if (rid_index_1 + 1 == rid_wr_ptr_1) begin
                        rid_index_1 <= 0;
                  end
                  else begin
                        rid_index_1 <= rid_index_1 + 1;
                  end
            end

            bid_reg_0 <= bid_array_0[bid_index_0];
            if (bid_wr_ptr_0 != 0) begin
                  if (bid_index_0 + 1 == bid_wr_ptr_0) begin
                        bid_index_0 <= 0;
                  end
                  else begin
                        bid_index_0 <= bid_index_0 + 1;
                  end
            end

            bid_reg_1 <= bid_array_1[bid_index_1];
            if (bid_wr_ptr_1 != 0) begin
                  if (bid_index_1 + 1 == bid_wr_ptr_1) begin
                        bid_index_1 <= 0;
                  end
                  else begin
                        bid_index_1 <= bid_index_1 + 1;
                  end
            end
      end
end

endmodule