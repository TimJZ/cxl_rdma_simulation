

module nvme_ctrl_wrapper #(
    parameter MC_CH = 2,

    parameter BE_CH = 1,    
    parameter RW_CH = 2,
    parameter CH_ID = 1,
    parameter BUF_ID = 1,

    //cafu: [11:6] channel_id, [5:0] used by wrapper
    // parameter logic [2:0] channel_id,  //replaced by CH_ID
    //cafu arid 
    parameter logic [8:0] cafu_arid_rd_cq   = 9'd0,
    parameter logic [8:0] cafu_arid_rd_sq   = 9'd1,

    //cafu awid
    parameter logic [8:0] cafu_awid_wr_sq   = 9'd0

    //mc: [7:2] channel_id, [1:0] used by wrapper 
)
(
    input logic axi4_mm_clk,
    input logic axi4_mm_rst_n,

    //from csr 
    input logic         i_end_proc,
    input logic         i_update,
    input logic         i_host_buf_addr_valid,
    input logic [63:0]  i_host_buf_addr,
    input logic [63:0]  i_block_index_offset,
    input logic [63:0]  i_sq_addr,   //submission queue
    input logic [63:0]  i_cq_addr,   //completion queue
    input logic [63:0]  i_sq_tail,
    input logic [63:0]  i_cq_head,

    input logic [63:0]  i_delay_cnt,

    //RDMA additional parameters 
    input logic [63:0]  i_rdma_local_key,
    input logic [63:0]  i_rdma_local_addr,
    input logic [63:0]  i_rdma_remote_key,
    input logic [63:0]  i_rdma_remote_addr,
    input logic [63:0]  i_rdma_qpn_ds,

    //to front_end
    input ed_mc_axi_if_pkg::t_to_nvme_axi4    nvme_to_be_axi4,
    output ed_mc_axi_if_pkg::t_from_nvme_axi4 be_to_nvme_axi4,

    //to CAFU
    input logic             arready     [RW_CH-1:0],
    output logic [63:0]     araddr      [RW_CH-1:0],
    output logic            arvalid     [RW_CH-1:0],
    output logic [11:0]     arid        [RW_CH-1:0],
    output logic [5:0]      aruser      [RW_CH-1:0],

    input logic             rready,
    input logic             rvalid,
    input logic             rlast,
    input logic [511:0]     rdata,
    input logic [1:0]       rresp,
    input logic [11:0]      rid,

    input logic             wready      [RW_CH-1:0],
    output logic            wvalid      [RW_CH-1:0],
    output logic [511:0]    wdata       [RW_CH-1:0],
    output logic            wlast       [RW_CH-1:0], 
    output logic [(512/8)-1:0] wstrb    [RW_CH-1:0], 

    input logic             awready     [RW_CH-1:0],
    output logic            awvalid     [RW_CH-1:0],
    output logic [11:0]     awid        [RW_CH-1:0],
    output logic [5:0]      awuser      [RW_CH-1:0],
    output logic [63:0]     awaddr      [RW_CH-1:0],
    
    input logic             bvalid,
    input logic [1:0]       bresp,
    input logic             bready,
    input logic [11:0]      bid,

    //to PIO
    output logic            pio_sqdb_valid,
    output logic [63:0]     pio_sqdb_tail,
    input logic             pio_sqdb_ready,

    output logic            pio_cqdb_valid,
    output logic [63:0]     pio_cqdb_head,
    input logic             pio_cqdb_ready,

    output logic [31:0] pf_pio_sq_db,
    output logic [31:0] pf_pio_cq_db
);

back_end #(
    .BE_CH(BE_CH),
    .RW_CH(RW_CH),
    .CH_ID(CH_ID),
    .BUF_ID(BUF_ID),
    .arid_rd_cq ({CH_ID, cafu_arid_rd_cq}),
    .arid_rd_sq ({CH_ID, cafu_arid_rd_sq}),
    .awid_wr_sq ({CH_ID, cafu_awid_wr_sq})
)
back_end_inst
(
    .axi4_mm_clk            (axi4_mm_clk),
    .axi4_mm_rst_n          (axi4_mm_rst_n),

    //to csr
    .i_sq_addr              (i_sq_addr  ), 
    .i_cq_addr              (i_cq_addr  ), 
    .i_sq_tail              (i_sq_tail  ),
    .i_cq_head              (i_cq_head  ),
    .i_update               (i_update   ),
    .i_end_proc             (i_end_proc ),

    //RDMA additional parameters
    .i_rdma_local_key       (i_rdma_local_key),
    .i_rdma_local_addr      (i_rdma_local_addr),
    .i_rdma_remote_key      (i_rdma_remote_key),
    .i_rdma_remote_addr     (i_rdma_remote_addr),
    .i_rdma_qpn_ds          (i_rdma_qpn_ds),

    .i_host_buf_addr_valid  (i_host_buf_addr_valid),
    .i_host_buf_addr        (i_host_buf_addr),
    .i_block_index_offset   (i_block_index_offset),

    //to pio_fifo
    .pio_sqdb_valid           (pio_sqdb_valid ),
    .pio_sqdb_tail            (pio_sqdb_tail  ),
    .pio_sqdb_ready           (pio_sqdb_ready ),

    .pio_cqdb_valid           (pio_cqdb_valid ),
    .pio_cqdb_head            (pio_cqdb_head  ),
    .pio_cqdb_ready           (pio_cqdb_ready ),

    //to front_end
    .nvme_to_be_axi4         (nvme_to_be_axi4),
    .be_to_nvme_axi4         (be_to_nvme_axi4),

    //to cust_afu
    .arready                 (arready       [RW_CH-1:0]),       
    .araddr                  (araddr        [RW_CH-1:0]),    
    .arvalid                 (arvalid       [RW_CH-1:0]),      
    .arid                    (arid          [RW_CH-1:0]),      
    .aruser                  (aruser        [RW_CH-1:0]),    
    
    .rready                  (rready),
    .rvalid                  (rvalid),
    .rlast                   (rlast ),
    .rdata                   (rdata ),
    .rresp                   (rresp ),
    .rid                     (rid),

    .wready                  (wready        [RW_CH-1:0]),    
    .wvalid                  (wvalid        [RW_CH-1:0]),    
    .wdata                   (wdata         [RW_CH-1:0]),     
    .wlast                   (wlast         [RW_CH-1:0]),     
    .wstrb                   (wstrb         [RW_CH-1:0]),     

    .awready                 (awready       [RW_CH-1:0]),       
    .awvalid                 (awvalid       [RW_CH-1:0]),       
    .awid                    (awid          [RW_CH-1:0]),      
    .awuser                  (awuser        [RW_CH-1:0]),    
    .awaddr                  (awaddr        [RW_CH-1:0]),    
    
    .bvalid                  (bvalid),
    .bresp                   (bresp),
    .bready                  (bready),
    .bid                     (bid),

    .pf_pio_sq_db            (pf_pio_sq_db),
    .pf_pio_cq_db            (pf_pio_cq_db)
);

endmodule