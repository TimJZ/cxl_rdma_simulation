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


// Copyright 2022 Intel Corporation.
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
/*                COHERENCE-COMPLIANCE VALIDATION AFU

  Description   : FPGA CXL Compliance Engine Initiator AFU
                  Speaks to the AXI-to-CCIP+ translator.
                  This afu is the initiatior
                  The axi-to-ccip+ is the responder

  initial -> 07/12/2022 -> Antony Mathew
*/


module cust_afu_wrapper
#(
  parameter MC_CH = 2
)
(
      // Clocks
  input logic  axi4_mm_clk, 

    // Resets
  input logic  axi4_mm_rst_n,
  
  // [harry] AVMM interface - imported from ex_default_csr_top
  input  logic        csr_avmm_clk,
  input  logic        csr_avmm_rstn,  
  output logic        csr_avmm_waitrequest,  
  output logic [63:0] csr_avmm_readdata,
  output logic        csr_avmm_readdatavalid,
  input  logic [63:0] csr_avmm_writedata,
  input  logic [21:0] csr_avmm_address,
  input  logic        csr_avmm_write,
  input  logic        csr_avmm_poison,
  input  logic        csr_avmm_read, 
  input  logic [7:0]  csr_avmm_byteenable,

  //test
  output logic [63:0] pio_tx_header_low,
  output logic [63:0] pio_tx_header_high,
  output logic [63:0] pio_tx_start,
  output logic [63:0] pio_tx_payload,

  //nvme controller 
  output logic o_end_proc,

  //control mc_top
  output ed_mc_axi_if_pkg::t_to_mc_axi4 [1:0] nvme2iafu_to_mc_axi4,
  input ed_mc_axi_if_pkg::t_from_mc_axi4 [1:0] iafu2nvme_from_mc_axi4,

  input ed_mc_axi_if_pkg::t_to_mc_axi4 [MC_CH-1:0] iafu2mc_to_nvme_axi4,
  output ed_mc_axi_if_pkg::t_from_mc_axi4 [MC_CH-1:0] mc2iafu_from_nvme_axi4,

  //to PIO
  output logic [63:0]     pio_bar_addr,
  output logic [63:0]     pio_requester_id, // requester id for PIO

  output logic            pio_sqdb_valid,
  output logic [63:0]     pio_sqdb_tail,
  input logic             pio_sqdb_ready,

  output logic            pio_cqdb_valid,
  output logic [63:0]     pio_cqdb_head,
  input logic             pio_cqdb_ready,

  //to CAFU
  output logic [63:0]     afu_init,
  /*
    AXI-MM interface - write address channel
  */
  output logic [11:0]               awid,   //not sure
  output logic [63:0]               awaddr, 
  output logic [9:0]                awlen,  //must tie to 10'd0
  output logic [2:0]                awsize, //must tie to 3'b110 (64B/T)
  output logic [1:0]                awburst,//must tie to 2'b00
  output logic [2:0]                awprot, //must tie to 3'b000
  output logic [3:0]                awqos,  //must tie to 4'b0000
  output logic [5:0]                awuser, //v1.2
  output logic                      awvalid,
  output logic [3:0]                awcache,//must tie to 4'b0000
  output logic [1:0]                awlock, //must tie to 2'b00
  output logic [3:0]                awregion, //must tie to 4'b0000
  output logic [5:0]                awatop,
  input                            awready,
  
  /*
    AXI-MM interface - write data channel
  */
  output logic [511:0]              wdata,
  output logic [(512/8)-1:0]        wstrb,
  output logic                      wlast,
  output logic                      wuser,  //not sure
  output logic                      wvalid,
//  output logic [7:0]                wid, //removed in v3.0.2
   input                            wready,
  
  /*
    AXI-MM interface - write response channel
  */ 
   input [11:0]                     bid,  //not sure
   input [1:0]                      bresp,  //2'b00: OKAY, 2'b01: EXOKAY, 2'b10: SLVERR
   input [3:0]                      buser,  //must tie to 4'b0000
   input                            bvalid,
  output logic                      bready,
  
  /*
    AXI-MM interface - read address channel
  */
  output logic [11:0]               arid, //not sure
  output logic [63:0]               araddr,
  output logic [9:0]                arlen,  //must tie to 10'd0
  output logic [2:0]                arsize, //must tie to 3'b110
  output logic [1:0]                arburst,  //must tie to 2'b00
  output logic [2:0]                arprot, //must tie to 3'b000
  output logic [3:0]                arqos,  //must tie to 4'b0000
  output logic [5:0]                aruser, //4'b0000": non-cacheable, 4'b0001: cacheable shared, 4'b0010: cachebale owned
  output logic                      arvalid,
  output logic [3:0]                arcache,  //must tie to 4'b0000
  output logic [1:0]                arlock, //must tie to 2'b00
  output logic [3:0]                arregion, //must tie to 4'b0000
   input                            arready,

  /*
    AXI-MM interface - read response channel
  */ 
   input [11:0]                     rid,  //not sure
   input [511:0]                    rdata,  
   input [1:0]                      rresp,  //2'b00: OKAY, 2'b01: EXOKAY, 2'b10: SLVERR
   input                            rlast,  
   input                            ruser,  //not sure
   input                            rvalid,
   output logic                     rready
);

localparam FE_CH = 8;        //number of nvme queue used
localparam BE_CH = 8;        //number of nvme queue used
localparam BE_RW_CH = 2; 
localparam BE_BUF_ID = 4;
localparam MSHR_CH = 2;      //number of mshr channel
localparam RW_CH = 2; //number of read/write channel
localparam CH_READ = RW_CH + 1;     //num of read channel connected to read fifo
localparam CH_WRITE = RW_CH + 1;    //num of write channel connected to write fifo

localparam NUM_DEBUG = 64; //number of debug signals

//read channel signal 
logic arvalid_ch [0:CH_READ-1];
logic arready_ch [0:CH_READ-1];
logic [11:0] arid_ch [0:CH_READ-1];
logic [5:0] aruser_ch[0:CH_READ-1];
logic [63:0] araddr_ch[0:CH_READ-1];

//write channel signal
logic wvalid_ch [0:CH_WRITE-1];
logic wready_ch [0:CH_WRITE-1];
logic [511:0] wdata_ch [0:CH_WRITE-1];
logic wlast_ch [0:CH_WRITE-1];
logic [(512/8)-1:0] wstrb_ch [0:CH_WRITE-1];

logic awvalid_ch [0:CH_WRITE-1];
logic awready_ch [0:CH_WRITE-1];
logic [11:0] awid_ch [0:CH_WRITE-1];
logic [5:0] awuser_ch [0:CH_WRITE-1];
logic [63:0] awaddr_ch [0:CH_WRITE-1];

// Tied to Zero for all inputs. USER Can Modify

//assign awready = 1'b0;
//assign wready  = 1'b0;
//assign arready = 1'b0;
//assign bid     = 16'h0;
//assign bresp   = 4'h0;  
//assign buser   = 4'h0;
//assign bvalid  = 1'b0;
//
//assign rid     = 16'h0; 
//assign rdata   = 512'h0;
//assign rresp   = 4'h0;
//assign rlast   = 1'b0;
//assign ruser   = 4'h0;
//assign rvalid  = 1'b0;


//  assign  awid         = '0   ; //v3.0
  //assign  awaddr       = '0   ; 
  assign  awlen        = '0   ;
  assign  awsize       = 3'b110   ; //must tie to 3'b110
  assign  awburst      = '0   ;
  assign  awprot       = '0   ;
  assign  awqos        = '0   ;
//  assign  awuser       = '0   ; //v1.2
  //assign  awvalid      = '0   ;
  assign  awcache      = '0   ;
  assign  awlock       = '0   ;
  assign  awregion     = '0   ;
  assign awatop         = '0  ; 
//  assign  wdata        = '1;    //v3.0.3
//  assign  wstrb        = '1   ; //v1.1 
//  assign  wlast        = '1   ; //v1.1
  assign  wuser        = '0   ; //set to not poison in v1.2
//  assign  wvalid       = '1   ; //v1.1
  assign  wid          = '0   ; //not sure
 assign  bready       = 1'b1   ;//v1.1
//  assign  arid         = '0   ;//v3.0
 //assign  araddr       = '0   ;
  assign  arlen        = '0   ;
  assign  arsize       = 3'b110   ;//must tie to 3'b110
  assign  arburst      = '0   ;
  assign  arprot       = '0   ;
  assign  arqos        = '0   ;
//  assign  aruser       = '0   ; //v1.2
  //assign  arvalid      = 1'b1   ; 
  assign  arcache      = '0   ;
  assign  arlock       = '0   ;
  assign  arregion     = '0   ;
 assign  rready       = 1'b1   ;//v3.0.5

//from csr to avmm clock domain
logic [63:0] page_addr_0_csr;
logic [63:0] page_addr_0_avmm;

logic [63:0] test_case_csr;
logic [63:0] test_case_avmm;

logic start_proc_csr; 
logic start_proc_avmm;

logic end_proc_csr;
logic end_proc_avmm;

logic m5_query_en_csr;
logic m5_query_en_avmm;

logic [63:0] m5_interval_csr;
logic [63:0] m5_interval_avmm;

logic [63:0] write_data_csr [7:0];
logic [63:0] write_data_avmm [7:0];

logic [63:0] tx_header_low_csr;
logic [63:0] tx_header_low_avmm;

logic [63:0] tx_header_high_csr;
logic [63:0] tx_header_high_avmm;

logic [63:0] tx_start_csr;
logic [63:0] tx_start_avmm;

logic [63:0] tx_payload_csr;
logic [63:0] tx_payload_avmm;

logic [63:0] afu_init_csr;
logic [63:0] afu_init_avmm;

logic [63:0] sq_addr_csr  [BE_CH-1:0];
logic [63:0] sq_addr_avmm [BE_CH-1:0];

logic [63:0] cq_addr_csr  [BE_CH-1:0];
logic [63:0] cq_addr_avmm [BE_CH-1:0];

logic [63:0] sq_tail_csr  [BE_CH-1:0];
logic [63:0] sq_tail_avmm [BE_CH-1:0];

logic [63:0] cq_head_csr  [BE_CH-1:0];
logic [63:0] cq_head_avmm [BE_CH-1:0];

logic [63:0] host_buf_addr_csr  [BE_CH-1:0];
logic [63:0] host_buf_addr_avmm [BE_CH-1:0];


//RDMA additional parameters
logic [63:0] rdma_local_key_cdc;
logic [63:0] rdma_local_addr_cdc;
logic [63:0] rdma_remote_key_cdc;
logic [63:0] rdma_remote_addr_cdc;
logic [63:0] rdma_qpn_ds_cdc;

logic host_buf_addr_valid_csr   [BE_CH-1:0];
logic host_buf_addr_valid_avmm  [BE_CH-1:0];

logic update_csr; 
logic update_avmm;

logic nvme_end_proc_csr;
logic nvme_end_proc_avmm;

logic [63:0] delay_cnt_csr;
logic [63:0] delay_cnt_avmm;

logic [63:0] pio_bar_addr_csr;
logic [63:0] pio_bar_addr_avmm;

logic [63:0] pio_requester_id_csr; // requester id for PIO
logic [63:0] pio_requester_id_avmm; // requester id for PIO

logic [63:0] block_index_offset_csr;
logic [63:0] block_index_offset_avmm;

//from avmm to csr clock domain
logic [63:0] read_data_avmm [7:0];
logic [63:0] read_data_csr  [7:0];

logic [63:0] debug_pf_avmm [NUM_DEBUG-1:0]; //debug signals from nvme controller
logic [63:0] debug_pf_csr [NUM_DEBUG-1:0]; //debug signals from nvme controller

//not used
logic [63:0] addr_cnt_avmm;
logic [63:0] addr_cnt_csr;

logic [63:0] data_cnt_avmm;
logic [63:0] data_cnt_csr;

logic [63:0] resp_cnt_avmm;
logic [63:0] resp_cnt_csr;


//connect to other module
assign o_end_proc = end_proc_avmm;
assign pio_bar_addr = pio_bar_addr_avmm;
assign pio_requester_id = pio_requester_id_avmm; // requester id for PIO


//CSR block
cust_afu_csr_avmm_slave #(
  .BE_CH(BE_CH),
  .NUM_DEBUG(NUM_DEBUG)
)cust_afu_csr_avmm_slave_inst(
    .clk          (csr_avmm_clk),
    .reset_n      (csr_avmm_rstn),
    .writedata    (csr_avmm_writedata),
    .read         (csr_avmm_read),
    .write        (csr_avmm_write),
    .byteenable   (csr_avmm_byteenable),
    .readdata     (csr_avmm_readdata),
    .readdatavalid(csr_avmm_readdatavalid),
    .address      (csr_avmm_address),
    .poison       (csr_avmm_poison),
    .waitrequest  (csr_avmm_waitrequest),

    //test
    .o_start_proc   (start_proc_csr),
    .o_end_proc     (end_proc_csr),
    .page_addr_0_out(page_addr_0_csr),
    .test_case_out  (test_case_csr),//see above for definition

    .addr_cnt_out   (addr_cnt_csr),
    .data_cnt_out   (data_cnt_csr),
    .resp_cnt_out   (resp_cnt_csr),

    .read_data_out_0 (read_data_csr[0]),
    .read_data_out_1 (read_data_csr[1]),
    .read_data_out_2 (read_data_csr[2]),
    .read_data_out_3 (read_data_csr[3]),
    .read_data_out_4 (read_data_csr[4]),
    .read_data_out_5 (read_data_csr[5]),
    .read_data_out_6 (read_data_csr[6]),
    .read_data_out_7 (read_data_csr[7]),
    .write_data_out_0(write_data_csr[0]),
    .write_data_out_1(write_data_csr[1]),
    .write_data_out_2(write_data_csr[2]),
    .write_data_out_3(write_data_csr[3]),
    .write_data_out_4(write_data_csr[4]),
    .write_data_out_5(write_data_csr[5]),
    .write_data_out_6(write_data_csr[6]),
    .write_data_out_7(write_data_csr[7]),

    .tx_header_low  (tx_header_low_csr),
    .tx_header_high (tx_header_high_csr),
    .tx_start       (tx_start_csr),
    .tx_payload     (tx_payload_csr),

    .afu_init       (afu_init_csr),

    //nvme controller
    .sq_addr              (sq_addr_csr),
    .cq_addr              (cq_addr_csr),
    .sq_tail              (sq_tail_csr),
    .cq_head              (cq_head_csr),
    .host_buf_addr_valid  (host_buf_addr_valid_csr),
    .host_buf_addr        (host_buf_addr_csr),
    .block_index_offset   (block_index_offset_csr),

    //rdma, directly to NVMe controller through cdc 
    .rdma_local_key(rdma_local_key_cdc),
    .rdma_local_addr(rdma_local_addr_cdc),
    .rdma_remote_key(rdma_remote_key_cdc),
    .rdma_remote_addr(rdma_remote_addr_cdc),
    .rdma_qpn_ds(rdma_qpn_ds_cdc),

    .bar_addr             (pio_bar_addr_csr  ),
    .requester_id         (pio_requester_id_csr), // requester id for PIO

    .update               (update_csr),
    .end_proc             (nvme_end_proc_csr),

    //m5
    .m5_query_en          (m5_query_en_csr),
    .m5_interval          (m5_interval_csr),

    //debug
    .debug_pf             (debug_pf_csr)
);

cust_afu_cdc_wrapper #(
  .BE_CH(BE_CH),
  .NUM_DEBUG(NUM_DEBUG)
) cust_afu_cdc_wrapper_inst(
    .csr_avmm_clk(csr_avmm_clk),
    .csr_avmm_rst_n(csr_avmm_rstn),

    .axi4_mm_clk(axi4_mm_clk),
    .axi4_mm_rst_n(axi4_mm_rst_n),

    //from csr to axi4_mm domain

    .page_addr_0_csr(page_addr_0_csr),
    .page_addr_0_avmm(page_addr_0_avmm),

    .test_case_csr(test_case_csr),
    .test_case_avmm(test_case_avmm),

    .start_proc_csr(start_proc_csr),
    .start_proc_avmm(start_proc_avmm),

    .end_proc_csr(end_proc_csr),
    .end_proc_avmm(end_proc_avmm),

    .m5_query_en_csr(m5_query_en_csr),
    .m5_query_en_avmm(m5_query_en_avmm),

    .m5_interval_csr(m5_interval_csr),
    .m5_interval_avmm(m5_interval_avmm),

    .write_data_csr(write_data_csr),
    .write_data_avmm(write_data_avmm),

    .tx_header_low_csr(tx_header_low_csr),
    .tx_header_low_avmm(tx_header_low_avmm),

    .tx_header_high_csr(tx_header_high_csr),
    .tx_header_high_avmm(tx_header_high_avmm),

    .tx_start_csr(tx_start_csr),
    .tx_start_avmm(tx_start_avmm),

    .tx_payload_csr(tx_payload_csr),
    .tx_payload_avmm(tx_payload_avmm),

    .afu_init_csr(afu_init_csr),
    .afu_init_avmm(afu_init_avmm),

    .sq_addr_csr(sq_addr_csr),
    .sq_addr_avmm(sq_addr_avmm),

    .cq_addr_csr(cq_addr_csr),
    .cq_addr_avmm(cq_addr_avmm),

    .sq_tail_csr(sq_tail_csr),
    .sq_tail_avmm(sq_tail_avmm),

    .cq_head_csr(cq_head_csr),
    .cq_head_avmm(cq_head_avmm),

    .host_buf_addr_csr(host_buf_addr_csr),
    .host_buf_addr_avmm(host_buf_addr_avmm),

    .host_buf_addr_valid_csr(host_buf_addr_valid_csr),
    .host_buf_addr_valid_avmm(host_buf_addr_valid_avmm),

    .update_csr(update_csr),
    .update_avmm(update_avmm),

    .nvme_end_proc_csr(nvme_end_proc_csr),
    .nvme_end_proc_avmm(nvme_end_proc_avmm),

    .delay_cnt_csr(delay_cnt_csr),
    .delay_cnt_avmm(delay_cnt_avmm),

    .pio_bar_addr_csr(pio_bar_addr_csr),
    .pio_bar_addr_avmm(pio_bar_addr_avmm),

    .pio_requester_id_csr(pio_requester_id_csr), // requester id for PIO
    .pio_requester_id_avmm(pio_requester_id_avmm), // requester id

    .block_index_offset_csr(block_index_offset_csr),
    .block_index_offset_avmm(block_index_offset_avmm),


    //from axi4_mm to csr domain

    .read_data_avmm(read_data_avmm),
    .read_data_csr(read_data_csr),

    .debug_pf_avmm(debug_pf_avmm),
    .debug_pf_csr(debug_pf_csr)
);

psedu_read_write psedu_read_write_inst(
    .axi4_mm_clk  (axi4_mm_clk),
    .axi4_mm_rst_n(axi4_mm_rst_n),

    .start_proc   (start_proc_avmm),
    .end_proc     (end_proc_avmm),
    .page_addr_0  (page_addr_0_avmm),
    .test_case    (test_case_avmm),
    .read_data    (read_data_avmm),
    .write_data   (write_data_avmm),

    .rvalid       (rvalid),
    .rlast        (rlast),
    .rdata        (rdata),
    .rresp        (rresp),
    .rready       (rready),

    .araddr       (araddr_ch  [0]),
    .arready      (arready_ch [0]),
    .arvalid      (arvalid_ch [0]),
    .aruser       (aruser_ch  [0]),
    .arid         (arid_ch    [0]),

    .wready       (wready_ch  [0]),
    .wvalid       (wvalid_ch  [0]),
    .wdata        (wdata_ch   [0]),
    .wlast        (wlast_ch   [0]),
    .wstrb        (wstrb_ch   [0]),

    .awaddr       (awaddr_ch  [0]),
    .awready      (awready_ch [0]),
    .awvalid      (awvalid_ch [0]),
    .awid         (awid_ch    [0]),
    .awuser       (awuser_ch  [0]),


    .bvalid       (bvalid),
    .bresp        (bresp),
    .bready       (bready)
);



//nvme controller
nvme_controller #(
  .MC_CH(2),  //fixed
  .RW_CH(RW_CH), //fixed
  .FE_CH(FE_CH),
  .BE_CH(BE_CH),
  .BE_RW_CH(BE_RW_CH),
  .BE_BUF_ID(BE_BUF_ID),
  .MSHR_CH(MSHR_CH),
  .NUM_DEBUG(NUM_DEBUG)
)
nvme_controller_inst
(
    .axi4_mm_clk            (axi4_mm_clk),
    .axi4_mm_rst_n          (axi4_mm_rst_n),

    //to CSR
    .i_sq_addr              (sq_addr_avmm), 
    .i_cq_addr              (cq_addr_avmm),
    .i_sq_tail              (sq_tail_avmm),
    .i_cq_head              (cq_head_avmm),
    .i_host_buf_addr_valid  (host_buf_addr_valid_avmm),
    .i_host_buf_addr        (host_buf_addr_avmm),
    .i_block_index_offset   (block_index_offset_avmm),

    //rdma
    .i_rdma_local_key(rdma_local_key_cdc),
    .i_rdma_local_addr(rdma_local_addr_cdc),
    .i_rdma_remote_key(rdma_remote_key_cdc),
    .i_rdma_remote_addr(rdma_remote_addr_cdc),
    .i_rdma_qpn_ds(rdma_qpn_ds_cdc),

    .o_debug_pf             (debug_pf_avmm),

    .m5_query_en            (m5_query_en_avmm),
    .m5_interval            (m5_interval_avmm),

    // .i_delay_cnt(delay_cnt_out),

    .i_update               (update_avmm),
    .i_end_proc             (end_proc_avmm),

    //to MC
    .nvme2iafu_to_mc_axi4   (nvme2iafu_to_mc_axi4),
    .iafu2nvme_from_mc_axi4 (iafu2nvme_from_mc_axi4),

    //to IAFU
    .iafu2mc_to_nvme_axi4   (iafu2mc_to_nvme_axi4),
    .mc2iafu_from_nvme_axi4 (mc2iafu_from_nvme_axi4),

    //to PIO
    .pio_sqdb_valid         (pio_sqdb_valid),
    .pio_sqdb_tail          (pio_sqdb_tail),
    .pio_sqdb_ready         (pio_sqdb_ready),

    .pio_cqdb_valid         (pio_cqdb_valid),
    .pio_cqdb_head          (pio_cqdb_head),
    .pio_cqdb_ready         (pio_cqdb_ready),


    //to AXI
    .rvalid                 (rvalid),
    .rready                 (rready),
    .rlast                  (rlast),
    .rdata                  (rdata),
    .rresp                  (rresp),
    .rid                    (rid),

    .araddr                 (araddr_ch   [1:RW_CH]),
    .arready                (arready_ch  [1:RW_CH]),
    .arvalid                (arvalid_ch  [1:RW_CH]),
    .arid                   (arid_ch     [1:RW_CH]),
    .aruser                 (aruser_ch   [1:RW_CH]),
    
    .wready                 (wready_ch   [1:RW_CH]),
    .wvalid                 (wvalid_ch   [1:RW_CH]),
    .wdata                  (wdata_ch    [1:RW_CH]),
    .wlast                  (wlast_ch    [1:RW_CH]),
    .wstrb                  (wstrb_ch    [1:RW_CH]),

    .awaddr                 (awaddr_ch   [1:RW_CH]),
    .awready                (awready_ch  [1:RW_CH]),
    .awvalid                (awvalid_ch  [1:RW_CH]),
    .awid                   (awid_ch     [1:RW_CH]),
    .awuser                 (awuser_ch   [1:RW_CH]),
    
    .bvalid                 (bvalid),
    .bresp                  (bresp),
    .bready                 (bready),
    .bid                    (bid)
);


cafu_fifo #(
    .RD_CH(CH_READ),
    .WR_CH(CH_WRITE)
)
cafu_fifo_inst(
    .axi4_mm_clk  (axi4_mm_clk),
    .axi4_mm_rst_n(axi4_mm_rst_n),

    .arready_ch   (arready_ch),
    .arvalid_ch   (arvalid_ch),
    .arid_ch      (arid_ch),
    .araddr_ch    (araddr_ch),
    .aruser_ch    (aruser_ch),

    .wready_ch    (wready_ch),
    .wvalid_ch    (wvalid_ch),
    .wdata_ch     (wdata_ch),
    .wlast_ch     (wlast_ch),
    .wstrb_ch     (wstrb_ch),

    .awready_ch   (awready_ch),
    .awvalid_ch   (awvalid_ch),
    .awid_ch      (awid_ch),
    .awuser_ch    (awuser_ch),
    .awaddr_ch    (awaddr_ch),

    .arready      (arready),
    .arvalid      (arvalid),
    .arid         (arid),
    .aruser       (aruser),
    .araddr       (araddr),

    .wready       (wready),
    .wvalid       (wvalid),
    .wdata        (wdata),
    .wlast        (wlast),
    .wstrb        (wstrb),

    .awready      (awready),
    .awvalid      (awvalid),
    .awid         (awid),
    .awuser       (awuser),
    .awaddr       (awaddr)
);

(* preserve_for_debug *) logic [31:0] ar_cnt;
(* preserve_for_debug *) logic [31:0] aw_cnt;
(* preserve_for_debug *) logic [31:0] r_cnt;
(* preserve_for_debug *) logic [31:0] b_cnt;

always_ff @(posedge axi4_mm_clk) begin
  if (!axi4_mm_rst_n) begin
    ar_cnt <= '0;
    aw_cnt <= '0;
    r_cnt  <= '0;
    b_cnt  <= '0;
  end else begin
    if (arvalid && arready) ar_cnt <= ar_cnt + 1;
    if (awvalid && awready) aw_cnt <= aw_cnt + 1;
    if (rvalid && rready) r_cnt <= r_cnt + 1;
    if (bvalid && bready) b_cnt <= b_cnt + 1;
  end
end

endmodule


`ifdef QUESTA_INTEL_OEM
`pragma questa_oem_00 "EtAh8aN7m2BPKOTfO5tEAbNSD19BnNEklF4xQRY7YZ2oRe/8wDIRx8XCKuwkXQtjYcM5gRXSD6c+oGX77mfnvlAGw9KTmnXPBu3GU7e3qFjUTrXWlEAN76gMqJTePk91Iv2qtpAKuY2LJHLiowUVDoSuAt1Csh1O2u7qDzQRIaeVL/AJWYDMfWERE2K26wZcHHB8eTbMnhSND4m01aQODfKXixyUFYBUVJCy/gZrUwC/COVkHU40sJ5GuE1N0VE9aSSfgrrrGktfkSpPjVt+6vh4HQWnJKN/Lzk9oLSt1YLysf4dnGsynk5SDuZ6x0/ML5ubbSJVc2tgfUQwmLerlUi4bx1nUsqrq/XH3R3dANFxbqzbmpKGXMvqgb46n9Sm37rY4V/TYZFd4PzsLiyNDHYKdmnJvewxrFm/uLgERXzkW7lcD8KAcvUUAaz4Z4C2zY5+qyc9GNCb7RltAE5tYC7liWkMk4z8BnG2dlufPlefmUQxzKaSCbT//Vli6sDXBFM3D9suAASp02oo2BhDWdvFyy4pq0iWjukOdB3EikBjEhsO21PYCzWzqbJIdlJFSDW6SRUfFXdGUxxEFI+6M1p5Xv62vo3vJ8NGZFEbvOvExF+4yuN0UKpuJHAGlNGe+PmM5t8B7Zg42sjnL6BO9coYVmwaZpVMsVG4a6Bih2wyQyUDM+Cd8emewQyVnoM+mgxnFNl6CQj95XQajtj1yByTKjuKxokeGiPq3NCQ3hgOWESoSoYZwtb+gE86VbYMp8zzZY5D48aITm6wffPYQOy8ptHbOOYX2cTrFQtnKNtC9aTyiZcsumTRcqRrY9wXfEIEawlIhNSxaZccRwMmgp0LlsIrB/C7bfyOUM0KhlX08n+4+cYFeqB2nJS12LfMBaiOVRDLMpND1lHDDJpNtAd3by3ADzjZ563qTDTG1aJ14tfktADcuFUKjTsy9ZM74qHlAxxESSLyJORVAqqQ5533UJBV6W0BVXBwKWPJbT2NineVOGPZKKx4ewKvcIUu"
`endif