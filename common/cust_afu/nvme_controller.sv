/*
Version: 1.0.1
Modified: 2/21/25
Purpose: control CXL.cache read/write
2/21/25: add Q_CH paramter
*/
module nvme_controller 
#(
    parameter MC_CH = 2, //number of memory channel (fiexed)
    parameter RW_CH = 4, //number of read/write channel to CAFU
    parameter FE_CH = 8,  //number of front_inst, partition addr
    parameter BE_CH = 8,  //number of back_inst, partition add
    parameter BE_RW_CH = 1, //number of cxl.cache read/write channel per back_inst
    parameter BE_BUF_ID = 1, //number of maximumn buffer address per back_inst
    parameter MSHR_CH = 1, //number of MSHR channel per front_inst
    parameter NUM_DEBUG = 64 //number of debug signal, used for performance counter
)    
(
    input logic axi4_mm_clk,
    input logic axi4_mm_rst_n,

    //from csr    
    input logic [63:0]  i_sq_addr   [BE_CH-1:0],   //submission queue
    input logic [63:0]  i_cq_addr   [BE_CH-1:0],   //completion queue
    input logic [63:0]  i_sq_tail   [BE_CH-1:0],
    input logic [63:0]  i_cq_head   [BE_CH-1:0],
    input logic         i_host_buf_addr_valid   [BE_CH-1:0],
    input logic [63:0]  i_host_buf_addr         [BE_CH-1:0],
    input logic [63:0]  i_block_index_offset,

    //additional RDMA parameters
    input logic [63:0]  i_rdma_local_key,
    input logic [63:0]  i_rdma_local_addr,
    input logic [63:0]  i_rdma_remote_key,
    input logic [63:0]  i_rdma_remote_addr,
    input logic [63:0]  i_rdma_qpn_ds,

    output logic [63:0] o_debug_pf [NUM_DEBUG-1:0], //debug signal

    input logic m5_query_en,
    input logic [63:0] m5_interval,

    input logic         i_update,
    input logic         i_end_proc,

    //to mc_top
    output ed_mc_axi_if_pkg::t_to_mc_axi4 [MC_CH-1:0] nvme2iafu_to_mc_axi4,
    input ed_mc_axi_if_pkg::t_from_mc_axi4 [MC_CH-1:0] iafu2nvme_from_mc_axi4,

    //from afu_top
    input ed_mc_axi_if_pkg::t_to_mc_axi4 [MC_CH-1:0] iafu2mc_to_nvme_axi4,
    output ed_mc_axi_if_pkg::t_from_mc_axi4 [MC_CH-1:0] mc2iafu_from_nvme_axi4,

    //to PIO
    output logic            pio_sqdb_valid,
    output logic [63:0]     pio_sqdb_tail,
    input logic             pio_sqdb_ready,

    output logic            pio_cqdb_valid,
    output logic [63:0]     pio_cqdb_head,
    input logic             pio_cqdb_ready,

    //to CAFU
    input logic rready,
    input logic rvalid,
    input logic rlast,
    input logic [511:0] rdata,
    input logic [1:0] rresp,
    input logic [11:0] rid,

    input logic arready                 [RW_CH-1:0],
    output logic [63:0] araddr          [RW_CH-1:0],
    output logic arvalid                [RW_CH-1:0],
    output logic [11:0] arid            [RW_CH-1:0],
    output logic [5:0] aruser           [RW_CH-1:0],

    input logic wready                  [RW_CH-1:0],
    output logic wvalid                 [RW_CH-1:0],
    output logic [511:0] wdata          [RW_CH-1:0],
    output logic wlast                  [RW_CH-1:0], 
    output logic [(512/8)-1:0] wstrb    [RW_CH-1:0], 

    input logic awready                 [RW_CH-1:0],
    output logic awvalid                [RW_CH-1:0],
    output logic [11:0] awid            [RW_CH-1:0],
    output logic [5:0] awuser           [RW_CH-1:0],
    output logic [63:0] awaddr          [RW_CH-1:0],
    
    input logic bvalid,
    input logic [1:0] bresp,
    input logic bready,
    input logic [11:0] bid
);

// //from csr

//from pio_fifo
logic               sqdb_valid_ch     [BE_CH-1:0];
logic               sqdb_ready_ch     [BE_CH-1:0];
logic [63:0]        sqdb_tail_ch      [BE_CH-1:0];

logic               cqdb_valid_ch     [BE_CH-1:0];
logic               cqdb_ready_ch     [BE_CH-1:0];
logic [63:0]        cqdb_head_ch      [BE_CH-1:0];

logic [31:0]        pf_pio_sq_db      [BE_CH-1:0];
logic [31:0]        pf_pio_cq_db      [BE_CH-1:0];

//to cafu_fifo
//read channel signal
logic arvalid_ch [MSHR_CH*FE_CH-1:0];
logic arready_ch [MSHR_CH*FE_CH-1:0];
logic [11:0] arid_ch [MSHR_CH*FE_CH-1:0];
logic [5:0] aruser_ch[MSHR_CH*FE_CH-1:0];
logic [63:0] araddr_ch[MSHR_CH*FE_CH-1:0];

//write channel signal
logic wvalid_ch [MSHR_CH*FE_CH-1:0];
logic wready_ch [MSHR_CH*FE_CH-1:0];
logic [511:0] wdata_ch [MSHR_CH*FE_CH-1:0];
logic wlast_ch [MSHR_CH*FE_CH-1:0];
logic [(512/8)-1:0] wstrb_ch [MSHR_CH*FE_CH-1:0];

logic awvalid_ch [MSHR_CH*FE_CH-1:0];
logic awready_ch [MSHR_CH*FE_CH-1:0];
logic [11:0] awid_ch [MSHR_CH*FE_CH-1:0];
logic [5:0] awuser_ch [MSHR_CH*FE_CH-1:0];
logic [63:0] awaddr_ch [MSHR_CH*FE_CH-1:0];


//read channel signal
logic arvalid_ch_1          [FE_CH+BE_CH*BE_RW_CH-1:0];
logic arready_ch_1          [FE_CH+BE_CH*BE_RW_CH-1:0];
logic [11:0] arid_ch_1      [FE_CH+BE_CH*BE_RW_CH-1:0];
logic [5:0] aruser_ch_1     [FE_CH+BE_CH*BE_RW_CH-1:0];
logic [63:0] araddr_ch_1    [FE_CH+BE_CH*BE_RW_CH-1:0];

//write channel signal

logic wvalid_ch_1               [FE_CH+BE_CH*BE_RW_CH-1:0];
logic wready_ch_1               [FE_CH+BE_CH*BE_RW_CH-1:0];
logic [511:0] wdata_ch_1        [FE_CH+BE_CH*BE_RW_CH-1:0];
logic wlast_ch_1                [FE_CH+BE_CH*BE_RW_CH-1:0];
logic [(512/8)-1:0] wstrb_ch_1  [FE_CH+BE_CH*BE_RW_CH-1:0];

logic awvalid_ch_1              [FE_CH+BE_CH*BE_RW_CH-1:0];
logic awready_ch_1              [FE_CH+BE_CH*BE_RW_CH-1:0];
logic [11:0] awid_ch_1          [FE_CH+BE_CH*BE_RW_CH-1:0];
logic [5:0] awuser_ch_1         [FE_CH+BE_CH*BE_RW_CH-1:0];
logic [63:0] awaddr_ch_1        [FE_CH+BE_CH*BE_RW_CH-1:0];

//to mc_fifo
ed_mc_axi_if_pkg::t_from_mc_axi4_extended [MC_CH-1:0] mc2iafu_from_nvme_axi4_ch [FE_CH-1:0];
ed_mc_axi_if_pkg::t_to_mc_axi4_extended  [MC_CH-1:0] iafu2mc_to_nvme_axi4_ch [FE_CH-1:0];

//connect to mc_top
ed_mc_axi_if_pkg::t_to_mc_axi4 [1:0] nvme2iafu_to_mc_axi4_ch [2*MSHR_CH*FE_CH-1:0];
ed_mc_axi_if_pkg::t_from_mc_axi4 [1:0] iafu2nvme_from_mc_axi4_ch [2*MSHR_CH*FE_CH-1:0];

ed_mc_axi_if_pkg::t_to_mc_axi4 [1:0] nvme2iafu_to_mc_axi4_ch_1 [FE_CH-1:0];
ed_mc_axi_if_pkg::t_from_mc_axi4 [1:0] iafu2nvme_from_mc_axi4_ch_1 [FE_CH-1:0];

//connect nvme_admin
ed_mc_axi_if_pkg::t_to_nvme_axi4    [FE_CH-1:0] fe_to_nvme_axi4;
ed_mc_axi_if_pkg::t_from_nvme_axi4  [FE_CH-1:0] nvme_to_fe_axi4;

ed_mc_axi_if_pkg::t_from_nvme_axi4    [BE_CH-1:0] be_to_nvme_axi4;
ed_mc_axi_if_pkg::t_to_nvme_axi4  [BE_CH-1:0] nvme_to_be_axi4;


logic [63:0] i_delay_cnt = '0;

genvar i;



/*-----------------------
Instances 
-----------------------*/
//between wrapper and afu_top
afu_fifo #(.MC_CH(MC_CH), .DQ_CH(FE_CH)) afu_fifo_inst(
    .axi4_mm_clk(axi4_mm_clk),
    .axi4_mm_rst_n(axi4_mm_rst_n),

    //to wrapper
    .mc2iafu_from_nvme_axi4_ch(mc2iafu_from_nvme_axi4_ch),
    .iafu2mc_to_nvme_axi4_ch(iafu2mc_to_nvme_axi4_ch),

    //to mc_top
    .mc2iafu_from_nvme_axi4(mc2iafu_from_nvme_axi4),
    .iafu2mc_to_nvme_axi4(iafu2mc_to_nvme_axi4),  //only use rready, bready

    .m5_query_en(m5_query_en),
    .m5_interval(m5_interval),

    .pf_in_flight_cmd_0(),
    .pf_in_flight_cmd_1()
);


generate
    for (i=0; i<FE_CH; i++) begin : cafu_fifo_layer_0
        cafu_fifo #(
            .RD_CH(MSHR_CH),
            .WR_CH(MSHR_CH)
        )
        cafu_fifo_inst(
            .axi4_mm_clk(axi4_mm_clk),
            .axi4_mm_rst_n(axi4_mm_rst_n),

            .arready_ch(arready_ch[MSHR_CH*(i+1)-1:MSHR_CH*i]),
            .arvalid_ch(arvalid_ch[MSHR_CH*(i+1)-1:MSHR_CH*i]),
            .arid_ch(arid_ch[MSHR_CH*(i+1)-1:MSHR_CH*i]),
            .araddr_ch(araddr_ch[MSHR_CH*(i+1)-1:MSHR_CH*i]),
            .aruser_ch(aruser_ch[MSHR_CH*(i+1)-1:MSHR_CH*i]),

            .wready_ch(wready_ch[MSHR_CH*(i+1)-1:MSHR_CH*i]),
            .wvalid_ch(wvalid_ch[MSHR_CH*(i+1)-1:MSHR_CH*i]),
            .wdata_ch(wdata_ch[MSHR_CH*(i+1)-1:MSHR_CH*i]),
            .wlast_ch(wlast_ch[MSHR_CH*(i+1)-1:MSHR_CH*i]),
            .wstrb_ch(wstrb_ch[MSHR_CH*(i+1)-1:MSHR_CH*i]),

            .awready_ch(awready_ch[MSHR_CH*(i+1)-1:MSHR_CH*i]),
            .awvalid_ch(awvalid_ch[MSHR_CH*(i+1)-1:MSHR_CH*i]),
            .awid_ch(awid_ch[MSHR_CH*(i+1)-1:MSHR_CH*i]),
            .awuser_ch(awuser_ch[MSHR_CH*(i+1)-1:MSHR_CH*i]),
            .awaddr_ch(awaddr_ch[MSHR_CH*(i+1)-1:MSHR_CH*i]),

            .arready(arready_ch_1[i]),
            .arvalid(arvalid_ch_1[i]),
            .arid(arid_ch_1[i]),
            .aruser(aruser_ch_1[i]),
            .araddr(araddr_ch_1[i]),

            .wready(wready_ch_1[i]),
            .wvalid(wvalid_ch_1[i]),
            .wdata(wdata_ch_1[i]),
            .wlast(wlast_ch_1[i]),
            .wstrb(wstrb_ch_1[i]),

            .awready(awready_ch_1[i]),
            .awvalid(awvalid_ch_1[i]),
            .awid(awid_ch_1[i]),
            .awuser(awuser_ch_1[i]),
            .awaddr(awaddr_ch_1[i])
        );
    end

    for (i=0; i<2; i++) begin : cafu_fifo_layer_1
        cafu_fifo #(
            .RD_CH((FE_CH+BE_CH*BE_RW_CH)/2),
            .WR_CH((FE_CH+BE_CH*BE_RW_CH)/2)
        )
        cafu_fifo_inst(
            .axi4_mm_clk(axi4_mm_clk),
            .axi4_mm_rst_n(axi4_mm_rst_n),

            .arready_ch(arready_ch_1[(FE_CH+BE_CH*BE_RW_CH)*(i+1)/2-1:(FE_CH+BE_CH*BE_RW_CH)*i/2]),
            .arvalid_ch(arvalid_ch_1[(FE_CH+BE_CH*BE_RW_CH)*(i+1)/2-1:(FE_CH+BE_CH*BE_RW_CH)*i/2]),
            .arid_ch(arid_ch_1[(FE_CH+BE_CH*BE_RW_CH)*(i+1)/2-1:(FE_CH+BE_CH*BE_RW_CH)*i/2]),
            .araddr_ch(araddr_ch_1[(FE_CH+BE_CH*BE_RW_CH)*(i+1)/2-1:(FE_CH+BE_CH*BE_RW_CH)*i/2]),
            .aruser_ch(aruser_ch_1[(FE_CH+BE_CH*BE_RW_CH)*(i+1)/2-1:(FE_CH+BE_CH*BE_RW_CH)*i/2]),

            .wready_ch(wready_ch_1[(FE_CH+BE_CH*BE_RW_CH)*(i+1)/2-1:(FE_CH+BE_CH*BE_RW_CH)*i/2]),
            .wvalid_ch(wvalid_ch_1[(FE_CH+BE_CH*BE_RW_CH)*(i+1)/2-1:(FE_CH+BE_CH*BE_RW_CH)*i/2]),
            .wdata_ch(wdata_ch_1[(FE_CH+BE_CH*BE_RW_CH)*(i+1)/2-1:(FE_CH+BE_CH*BE_RW_CH)*i/2]),
            .wlast_ch(wlast_ch_1[(FE_CH+BE_CH*BE_RW_CH)*(i+1)/2-1:(FE_CH+BE_CH*BE_RW_CH)*i/2]),
            .wstrb_ch(wstrb_ch_1[(FE_CH+BE_CH*BE_RW_CH)*(i+1)/2-1:(FE_CH+BE_CH*BE_RW_CH)*i/2]),

            .awready_ch(awready_ch_1[(FE_CH+BE_CH*BE_RW_CH)*(i+1)/2-1:(FE_CH+BE_CH*BE_RW_CH)*i/2]),
            .awvalid_ch(awvalid_ch_1[(FE_CH+BE_CH*BE_RW_CH)*(i+1)/2-1:(FE_CH+BE_CH*BE_RW_CH)*i/2]),
            .awid_ch(awid_ch_1[(FE_CH+BE_CH*BE_RW_CH)*(i+1)/2-1:(FE_CH+BE_CH*BE_RW_CH)*i/2]),
            .awuser_ch(awuser_ch_1[(FE_CH+BE_CH*BE_RW_CH)*(i+1)/2-1:(FE_CH+BE_CH*BE_RW_CH)*i/2]),
            .awaddr_ch(awaddr_ch_1[(FE_CH+BE_CH*BE_RW_CH)*(i+1)/2-1:(FE_CH+BE_CH*BE_RW_CH)*i/2]),

            .arready(arready[i]),
            .arvalid(arvalid[i]),
            .arid(arid[i]),
            .aruser(aruser[i]),
            .araddr(araddr[i]),

            .wready(wready[i]),
            .wvalid(wvalid[i]),
            .wdata(wdata[i]),
            .wlast(wlast[i]),
            .wstrb(wstrb[i]),

            .awready(awready[i]),
            .awvalid(awvalid[i]),
            .awid(awid[i]),
            .awuser(awuser[i]),
            .awaddr(awaddr[i])
        );
    end
endgenerate


//between mc_top and wrapper
generate
    for (i=0; i<FE_CH; i++) begin : mc_fifo_layer
        mc_fifo #(
            .CH(2*MSHR_CH)
        ) 
        mc_fifo_inst
        (
            .axi4_mm_clk(axi4_mm_clk),
            .axi4_mm_rst_n(axi4_mm_rst_n),

            .nvme2iafu_to_mc_axi4_ch(nvme2iafu_to_mc_axi4_ch[2*MSHR_CH*(i+1)-1:2*MSHR_CH*i]),
            .iafu2nvme_from_mc_axi4_ch(iafu2nvme_from_mc_axi4_ch[2*MSHR_CH*(i+1)-1:2*MSHR_CH*i]),

            .nvme2iafu_to_mc_axi4(nvme2iafu_to_mc_axi4_ch_1[i]),
            .iafu2nvme_from_mc_axi4(iafu2nvme_from_mc_axi4_ch_1[i])
        );
    end

    mc_fifo #(
        .CH(FE_CH)
    ) 
    mc_fifo_inst
    (
        .axi4_mm_clk(axi4_mm_clk),
        .axi4_mm_rst_n(axi4_mm_rst_n),

        .nvme2iafu_to_mc_axi4_ch(nvme2iafu_to_mc_axi4_ch_1),
        .iafu2nvme_from_mc_axi4_ch(iafu2nvme_from_mc_axi4_ch_1),

        .nvme2iafu_to_mc_axi4(nvme2iafu_to_mc_axi4),
        .iafu2nvme_from_mc_axi4(iafu2nvme_from_mc_axi4)
    );
endgenerate

//between wrapper and pio
pio_fifo #(
    .DQ_CH(BE_CH)
)
pio_fifo_inst(
    .axi4_mm_clk(axi4_mm_clk),
    .axi4_mm_rst_n(axi4_mm_rst_n),

    .sqdb_valid   (pio_sqdb_valid),
    .sqdb_ready   (pio_sqdb_ready),
    .sqdb_tail    (pio_sqdb_tail ),

    .cqdb_valid   (pio_cqdb_valid ),
    .cqdb_ready   (pio_cqdb_ready ),
    .cqdb_head    (pio_cqdb_head  ),

    .sqdb_valid_ch (sqdb_valid_ch),
    .sqdb_ready_ch (sqdb_ready_ch),
    .sqdb_tail_ch  (sqdb_tail_ch),

    .cqdb_valid_ch (cqdb_valid_ch),
    .cqdb_ready_ch (cqdb_ready_ch),
    .cqdb_head_ch  (cqdb_head_ch)
);

nvme_admin #(
    .FE_CH(FE_CH), //number of front_end channel
    .BE_CH(BE_CH) //number of back_end channel
)
nvme_admin_inst (
    .clk(axi4_mm_clk),
    .rst_n(axi4_mm_rst_n),

    .fe_to_nvme_axi4(fe_to_nvme_axi4),
    .nvme_to_fe_axi4(nvme_to_fe_axi4),
    
    .be_to_nvme_axi4(be_to_nvme_axi4),
    .nvme_to_be_axi4(nvme_to_be_axi4)
);


generate
    for (i=0; i<FE_CH; i++) begin : front_end_layer
        mc_ctrl_wrapper #(
            .MC_CH(2),
            .MSHR_CH(MSHR_CH),

            .channel_id(i),
            
            .cafu_arid_rd_buf   (2),
            .cafu_awid_wr_buf   (2),

            .mc_arid_rd_tag     (3), //just for debug
            .mc_arid_rd_data    (1),
            .mc_arid_rd_buf     (2),

            .mc_awid_wr_tag     (3),
            .mc_awid_wr_data    (1),
            .mc_awid_wr_buf     (2)
        )
        mc_ctrl_wrapper_inst(
            .axi4_mm_clk(axi4_mm_clk),
            .axi4_mm_rst_n(axi4_mm_rst_n),

            //from IP
            .iafu2mc_to_nvme_axi4(iafu2mc_to_nvme_axi4_ch[i]),
            .mc2iafu_from_nvme_axi4(mc2iafu_from_nvme_axi4_ch[i]),

            //from csr
            .i_end_proc             (i_end_proc   ),
            .i_update               (i_update     ),

            .i_delay_cnt            (i_delay_cnt),

            //to back_end
            .fe_to_nvme_axi4        (fe_to_nvme_axi4[i]),
            .nvme_to_fe_axi4        (nvme_to_fe_axi4[i]),

            //to mc
            .nvme2iafu_to_mc_axi4   (nvme2iafu_to_mc_axi4_ch[2*MSHR_CH*(i+1)-1:2*MSHR_CH*i]),
            .iafu2nvme_from_mc_axi4 (iafu2nvme_from_mc_axi4_ch[2*MSHR_CH*(i+1)-1:2*MSHR_CH*i]),

            //to cafu
            .arready                 (arready_ch       [MSHR_CH*(i+1)-1:MSHR_CH*i]),       
            .araddr                  (araddr_ch        [MSHR_CH*(i+1)-1:MSHR_CH*i]),    
            .arvalid                 (arvalid_ch       [MSHR_CH*(i+1)-1:MSHR_CH*i]),      
            .arid                    (arid_ch          [MSHR_CH*(i+1)-1:MSHR_CH*i]),      
            .aruser                  (aruser_ch        [MSHR_CH*(i+1)-1:MSHR_CH*i]),  
            
            .rready                  (rready),
            .rvalid                  (rvalid),
            .rlast                   (rlast ),
            .rdata                   (rdata ),
            .rresp                   (rresp ),
            .rid                     (rid),
            
            .wready                  (wready_ch        [MSHR_CH*(i+1)-1:MSHR_CH*i]),    
            .wvalid                  (wvalid_ch        [MSHR_CH*(i+1)-1:MSHR_CH*i]),    
            .wdata                   (wdata_ch         [MSHR_CH*(i+1)-1:MSHR_CH*i]),     
            .wlast                   (wlast_ch         [MSHR_CH*(i+1)-1:MSHR_CH*i]),     
            .wstrb                   (wstrb_ch         [MSHR_CH*(i+1)-1:MSHR_CH*i]),     

            .awready                 (awready_ch       [MSHR_CH*(i+1)-1:MSHR_CH*i]),       
            .awvalid                 (awvalid_ch       [MSHR_CH*(i+1)-1:MSHR_CH*i]),       
            .awid                    (awid_ch          [MSHR_CH*(i+1)-1:MSHR_CH*i]),      
            .awuser                  (awuser_ch        [MSHR_CH*(i+1)-1:MSHR_CH*i]),    
            .awaddr                  (awaddr_ch        [MSHR_CH*(i+1)-1:MSHR_CH*i]),    
            
            .bvalid                  (bvalid),
            .bresp                   (bresp),
            .bready                  (bready),
            .bid                     (bid),

            .fe_in_flight_c0          (o_debug_pf[2*i]),
            .fe_in_flight_c1          (o_debug_pf[2*i+1])
        );
    end


    for (i=0; i<BE_CH; i++) begin : back_end_layer
        nvme_ctrl_wrapper #(
            .MC_CH(2),

            .BE_CH(BE_CH),
            .RW_CH(BE_RW_CH),
            .CH_ID(i),
            .BUF_ID(BE_BUF_ID),    
            
            .cafu_arid_rd_cq    (0),
            .cafu_arid_rd_sq    (1),
            .cafu_awid_wr_sq    (0)
        )
        nvme_ctrl_wrapper_inst(
            .axi4_mm_clk(axi4_mm_clk),
            .axi4_mm_rst_n(axi4_mm_rst_n),

            //from csr
            .i_end_proc             (i_end_proc   ),
            .i_update               (i_update     ),
            .i_host_buf_addr_valid  (i_host_buf_addr_valid[i]),
            .i_host_buf_addr        (i_host_buf_addr[i]),
            .i_block_index_offset   (i_block_index_offset),
            .i_sq_addr              (i_sq_addr[i] ), 
            .i_cq_addr              (i_cq_addr[i] ), 
            .i_sq_tail              (i_sq_tail[i] ),
            .i_cq_head              (i_cq_head[i] ),
            //additional RDMA parameters
            .i_rdma_local_key       (i_rdma_local_key),
            .i_rdma_local_addr      (i_rdma_local_addr),
            .i_rdma_remote_key      (i_rdma_remote_key),   
            .i_rdma_remote_addr     (i_rdma_remote_addr),
            .i_rdma_qpn_ds          (i_rdma_qpn_ds),
            
            .i_delay_cnt            (i_delay_cnt),

            //to front_end
            .nvme_to_be_axi4       (nvme_to_be_axi4[i]),
            .be_to_nvme_axi4       (be_to_nvme_axi4[i]),

            //to cafu
            .arready                 (arready_ch_1       [FE_CH+BE_RW_CH*(i+1)-1:FE_CH+BE_RW_CH*i]),       
            .araddr                  (araddr_ch_1        [FE_CH+BE_RW_CH*(i+1)-1:FE_CH+BE_RW_CH*i]),    
            .arvalid                 (arvalid_ch_1       [FE_CH+BE_RW_CH*(i+1)-1:FE_CH+BE_RW_CH*i]),      
            .arid                    (arid_ch_1          [FE_CH+BE_RW_CH*(i+1)-1:FE_CH+BE_RW_CH*i]),      
            .aruser                  (aruser_ch_1        [FE_CH+BE_RW_CH*(i+1)-1:FE_CH+BE_RW_CH*i]),    
            
            .rready                  (rready),
            .rvalid                  (rvalid),
            .rlast                   (rlast ),
            .rdata                   (rdata ),
            .rresp                   (rresp ),
            .rid                     (rid),

            .wready                  (wready_ch_1        [FE_CH+BE_RW_CH*(i+1)-1:FE_CH+BE_RW_CH*i]),    
            .wvalid                  (wvalid_ch_1        [FE_CH+BE_RW_CH*(i+1)-1:FE_CH+BE_RW_CH*i]),    
            .wdata                   (wdata_ch_1         [FE_CH+BE_RW_CH*(i+1)-1:FE_CH+BE_RW_CH*i]),     
            .wlast                   (wlast_ch_1         [FE_CH+BE_RW_CH*(i+1)-1:FE_CH+BE_RW_CH*i]),     
            .wstrb                   (wstrb_ch_1         [FE_CH+BE_RW_CH*(i+1)-1:FE_CH+BE_RW_CH*i]),     

            .awready                 (awready_ch_1       [FE_CH+BE_RW_CH*(i+1)-1:FE_CH+BE_RW_CH*i]),       
            .awvalid                 (awvalid_ch_1       [FE_CH+BE_RW_CH*(i+1)-1:FE_CH+BE_RW_CH*i]),       
            .awid                    (awid_ch_1          [FE_CH+BE_RW_CH*(i+1)-1:FE_CH+BE_RW_CH*i]),      
            .awuser                  (awuser_ch_1        [FE_CH+BE_RW_CH*(i+1)-1:FE_CH+BE_RW_CH*i]),    
            .awaddr                  (awaddr_ch_1        [FE_CH+BE_RW_CH*(i+1)-1:FE_CH+BE_RW_CH*i]),    

            .bvalid                  (bvalid),
            .bresp                   (bresp),
            .bready                  (bready),
            .bid                     (bid),

            //to pio
            .pio_sqdb_valid         (sqdb_valid_ch  [i]),
            .pio_sqdb_tail          (sqdb_tail_ch   [i]),
            .pio_sqdb_ready         (sqdb_ready_ch  [i]),

            .pio_cqdb_valid         (cqdb_valid_ch  [i]),
            .pio_cqdb_head          (cqdb_head_ch   [i]),
            .pio_cqdb_ready         (cqdb_ready_ch  [i]),

            .pf_pio_sq_db           (pf_pio_sq_db[i]),
            .pf_pio_cq_db           (pf_pio_cq_db[i])
        );
    end
endgenerate

/*---------------------------------
Performance Counter
-----------------------------------*/
(* preserve_for_debug *) logic [63:0] num_ar_handshake_0;
(* preserve_for_debug *) logic [63:0] num_aw_handshake_0;
(* preserve_for_debug *) logic [63:0] num_r_handshake_0;
(* preserve_for_debug *) logic [63:0] num_b_handshake_0;

(* preserve_for_debug *) logic [63:0] num_ar_handshake_1;
(* preserve_for_debug *) logic [63:0] num_aw_handshake_1;
(* preserve_for_debug *) logic [63:0] num_r_handshake_1;
(* preserve_for_debug *) logic [63:0] num_b_handshake_1;

// (* preserve_for_debug *) logic [63:0] same_time_happe_0;
// (* preserve_for_debug *) logic [63:0] same_time_happe_1;

// (* preserve_for_debug *) logic [63:0] pf_pio_sq_db_sum;
// (* preserve_for_debug *) logic [63:0] pf_pio_cq_db_sum;

always_ff @(posedge axi4_mm_clk) begin
    if (!axi4_mm_rst_n) begin
        num_ar_handshake_0      <=  64'd0;
        num_aw_handshake_0      <=  64'd0;
        num_r_handshake_0       <=  64'd0;
        num_b_handshake_0        <=  64'd0;

        num_ar_handshake_1      <=  64'd0;
        num_aw_handshake_1      <=  64'd0;
        num_r_handshake_1       <=  64'd0;
        num_b_handshake_1        <=  64'd0;

        // same_time_happe_0       <= 64'd0;
        // same_time_happe_1       <= 64'd0;

        // pf_pio_sq_db_sum         <= 64'd0;
        // pf_pio_cq_db_sum         <= 64'd0;
    end
    else begin
        if (nvme2iafu_to_mc_axi4[0].arvalid && iafu2nvme_from_mc_axi4[0].arready) begin
            num_ar_handshake_0 <= num_ar_handshake_0 + 64'd1;
        end

        if (nvme2iafu_to_mc_axi4[1].arvalid && iafu2nvme_from_mc_axi4[1].arready) begin
            num_ar_handshake_1 <= num_ar_handshake_1 + 64'd1;
        end

        if (nvme2iafu_to_mc_axi4[0].awvalid && iafu2nvme_from_mc_axi4[0].awready) begin
            num_aw_handshake_0 <= num_aw_handshake_0 + 64'd1;
        end

        if (nvme2iafu_to_mc_axi4[1].awvalid && iafu2nvme_from_mc_axi4[1].awready) begin
            num_aw_handshake_1 <= num_aw_handshake_1 + 64'd1;
        end

        if (nvme2iafu_to_mc_axi4[0].rready && iafu2nvme_from_mc_axi4[0].rvalid) begin
            num_r_handshake_0 <= num_r_handshake_0 + 64'd1;
        end

        if (nvme2iafu_to_mc_axi4[1].rready && iafu2nvme_from_mc_axi4[1].rvalid) begin
            num_r_handshake_1 <= num_r_handshake_1 + 64'd1;
        end

        if (nvme2iafu_to_mc_axi4[0].bready && iafu2nvme_from_mc_axi4[0].bvalid) begin
            num_b_handshake_0 <= num_b_handshake_0 + 64'd1;
        end

        if (nvme2iafu_to_mc_axi4[1].bready && iafu2nvme_from_mc_axi4[1].bvalid) begin
            num_b_handshake_1 <= num_b_handshake_1 + 64'd1;
        end

        // if ((nvme2iafu_to_mc_axi4[0].arvalid && iafu2nvme_from_mc_axi4[0].arready) && (nvme2iafu_to_mc_axi4[0].awvalid && iafu2nvme_from_mc_axi4[0].awready)) begin
        //     same_time_happe_0 <= same_time_happe_0 + 64'd1;
        // end

        // if ((nvme2iafu_to_mc_axi4[1].arvalid && iafu2nvme_from_mc_axi4[1].arready) && (nvme2iafu_to_mc_axi4[1].awvalid && iafu2nvme_from_mc_axi4[1].awready)) begin
        //     same_time_happe_1 <= same_time_happe_1 + 64'd1;
        // end

        // pf_pio_sq_db_sum <= pf_pio_sq_db[0] + pf_pio_sq_db[1] + pf_pio_sq_db[2] + pf_pio_sq_db[3] +
        //                     pf_pio_sq_db[4] + pf_pio_sq_db[5] + pf_pio_sq_db[6] + pf_pio_sq_db[7];

        // pf_pio_cq_db_sum <= pf_pio_cq_db[0] + pf_pio_cq_db[1] + pf_pio_cq_db[2] + pf_pio_cq_db[3] +
        //                     pf_pio_cq_db[4] + pf_pio_cq_db[5] + pf_pio_cq_db[6] + pf_pio_cq_db[7];
    end
end



endmodule