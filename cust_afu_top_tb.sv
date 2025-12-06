module cust_afu_top_tb 
import ed_mc_axi_if_pkg::*;
(

);

localparam CH = 2; //unused
localparam BE_CH = 2;
localparam BF_ID = 2; //host buffer (#) memory request handle 

logic axi4_mm_clk, axi4_mm_rst_n;
logic        csr_avmm_clk;
always #1 axi4_mm_clk = ~axi4_mm_clk;
always #1 csr_avmm_clk = ~csr_avmm_clk;
logic        csr_avmm_rstn;  
logic        csr_avmm_waitrequest;            
logic [63:0] csr_avmm_readdata;            
logic        csr_avmm_readdatavalid;          
logic [63:0] csr_avmm_writedata;          
logic [21:0] csr_avmm_address;              
logic        csr_avmm_write;                
logic        csr_avmm_read;                  
logic [7:0]  csr_avmm_byteenable;

logic [11:0]               arid;
logic [63:0]               araddr;  // Read addr
// logic [9:0]                arlen,
// logic [2:0]                arsize,
// logic [1:0]                arburst,
// logic [2:0]                arprot,
// logic [3:0]                arqos,
logic [5:0]                aruser;
logic                      arvalid; // Read addr valid indicator
// logic [3:0]                arcache,
// logic [1:0]                arlock,
// logic [3:0]                arregion,
logic                      arready; // IP ready to accept read address

logic [11:0]                rid;
logic [511:0]              rdata;  // Read data
logic [1:0]                rresp;  // 00 - OKAY, 10 - ERROR
logic                       rlast;
// logic                       ruser,
logic                      rvalid; // Read data valid indicator
logic                      rready;  // AFU ready to accept read data

logic [11:0]              awid;
logic [63:0]               awaddr;  // Write addr
logic                      awvalid;
logic                     awready;
logic [5:0]               awuser;
logic [511:0]              wdata;
logic [(512/8)-1:0]        wstrb;
logic                     wlast;
logic                       wvalid;
logic                     wready;

logic [11:0]                bid;
logic [1:0]               bresp;
logic                     bvalid;
logic                     bready;


logic [63:0] result; 
logic [11:0] id_buffer [16384];
logic [63:0] id_cnt;
logic [63:0] test_case;
logic [63:0] pre_test_case; 

logic [511:0] sub_queue [63:0];
logic init_set;
logic wready_0;
logic awready_0;
logic ttt = 0;


ed_mc_axi_if_pkg::t_to_mc_axi4 [MC_CHANNEL-1:0] cxlip2iafu_to_mc_axi4;
ed_mc_axi_if_pkg::t_from_mc_axi4 [MC_CHANNEL-1:0] iafu2cxlip_from_mc_axi4;

ed_mc_axi_if_pkg::t_to_mc_axi4 [MC_CHANNEL-1:0] iafu2mc_to_mc_axi4;
ed_mc_axi_if_pkg::t_from_mc_axi4 [MC_CHANNEL-1:0] mc2iafu_from_mc_axi4;

ed_mc_axi_if_pkg::t_to_mc_axi4 [MC_CHANNEL-1:0] iafu2mc_to_nvme_axi4;
ed_mc_axi_if_pkg::t_from_mc_axi4 [MC_CHANNEL-1:0] mc2iafu_from_nvme_axi4;

ed_mc_axi_if_pkg::t_to_mc_axi4   [MC_CHANNEL-1:0] nvme2iafu_to_mc_axi4; //nvme control mc
ed_mc_axi_if_pkg::t_from_mc_axi4 [MC_CHANNEL-1:0] iafu2nvme_from_mc_axi4;

ed_mc_axi_if_pkg::t_to_mc_axi4 [MC_CHANNEL-1:0] iafu2ssd_to_mc_axi4;
ed_mc_axi_if_pkg::t_from_mc_axi4 [MC_CHANNEL-1:0] ssd2iafu_from_mc_axi4;

// ed_mc_axi_if_pkg::t_to_pio_axi4 to_pio_axi4;
// ed_mc_axi_if_pkg::t_from_pio_axi4 from_pio_axi4; 

logic             pio_txc_eop        ;
logic [127:0]     pio_txc_header     ;
logic [255:0]     pio_txc_payload    ;
logic             pio_txc_sop        ;
logic             pio_txc_valid      ;
logic           	pio_to_send_cpl   ;
logic         	  pio_txc_ready	 = 1   ;

// to PIO
logic [63:0]     pio_bar_addr;
logic [63:0]     pio_requester_id; // requester id for PIO

logic            pio_sqdb_valid;
logic [63:0]     pio_sqdb_tail;
logic            pio_sqdb_ready;

logic            pio_cqdb_valid;
logic [63:0]     pio_cqdb_head;
logic            pio_cqdb_ready;

// to CAFU
logic            rd_valid[CH-1:0];
logic            rd_return_ready[CH-1:0];
logic            rd_ready[CH-1:0];
logic            rd_return_valid[CH-1:0];
logic [63:0]     rd_araddr[CH-1:0];
logic [511:0]    rd_rdata[CH-1:0];

logic            wr_valid[CH-1:0];
logic            wr_return_ready[CH-1:0];
logic            wr_ready[CH-1:0];
logic            wr_return_valid[CH-1:0];
logic [63:0]     wr_awaddr[CH-1:0];
logic [511:0]    wr_wdata[CH-1:0];
logic [63:0]     wr_wstrb[CH-1:0];

logic end_proc;
logic [15:0] sq_cid [BF_ID-1:0] [BE_CH-1:0];
logic [15:0] sq_cid_tail [BE_CH-1:0];
logic [15:0] sq_cid_head [BE_CH-1:0];
logic [63:0] sq_tail [BE_CH-1:0];

logic [63:0] queue_idx;
logic [63:0] queue_idx_1;
assign queue_idx_1 = (araddr - 64'h7080000000);
assign queue_idx = (araddr - 64'h7080000000)/16/1024;

logic [511:0] cxl_tag [1023:0]; //fake cxl memory module 
logic [511:0] cxl_data [1023:0]; //fake cxl memory module 

logic [4095:0] ssd_data [1023:0];
logic [511:0] ssd_cmd [BF_ID-1:0] [BE_CH-1:0];

logic [63:0] ssd_index;
logic [63:0] cxl_index;
logic [63:0] cxl_index_1;
logic copy_to_ssd;
logic copy_from_ssd;

logic [511:0] ssd_data_dump;
// assign ssd_data_dump = ssd_data[ssd_cmd[349:340]][511:0];
// assign cxl_index = {ssd_cmd[207:201],3'd0};
// assign ssd_index = ssd_cmd[349:340]; 

logic [63:0] pio_tx_header_low;
logic [63:0] pio_tx_header_high;
logic [63:0] pio_tx_start;
logic [63:0] pio_tx_payload;

logic [511:0] host_buf [7:0][BE_CH-1:0];
logic [BE_CH-1:0] host_buf_aw_id;
logic [BE_CH-1:0] host_buf_ar_id;

assign host_buf_aw_id = (awaddr-64'h6080000000)/1024/BF_ID;
assign host_buf_ar_id = (araddr-64'h6080000000)/1024/BF_ID;

/*---------------
Instance
---------------*/
// t2_afu_top t2_afu_top_inst(
//     .afu_clk(axi4_mm_clk),
//     .afu_rstn(axi4_mm_rst_n),
//     .cxlip2iafu_to_mc_axi4(cxlip2iafu_to_mc_axi4),
//     .iafu2mc_to_mc_axi4(),
//     .mc2iafu_from_mc_axi4(),
//     .iafu2cxlip_from_mc_axi4(iafu2cxlip_from_mc_axi4),

//     .afu_init(64'd1),

//     .ssd_clk(axi4_mm_clk),
//     .ssd_rstn(axi4_mm_rst_n),
//     .iafu2ssd_to_mc_axi4(iafu2ssd_to_mc_axi4),
//     .ssd2iafu_from_mc_axi4(ssd2iafu_from_mc_axi4)
// );

afu_top afu_top_inst(
    .afu_clk(axi4_mm_clk),
    .afu_rstn(axi4_mm_rst_n),
    .cxlip2iafu_to_mc_axi4(cxlip2iafu_to_mc_axi4),
    .iafu2mc_to_mc_axi4(iafu2mc_to_mc_axi4),

    .afu_init(64'd1),

    .mc2iafu_from_mc_axi4(mc2iafu_from_mc_axi4),
    .iafu2cxlip_from_mc_axi4(iafu2cxlip_from_mc_axi4),
    
    .nvme2iafu_to_mc_axi4(nvme2iafu_to_mc_axi4),
    .iafu2nvme_from_mc_axi4(iafu2nvme_from_mc_axi4),

    .iafu2mc_to_nvme_axi4(iafu2mc_to_nvme_axi4),
    .mc2iafu_from_nvme_axi4(mc2iafu_from_nvme_axi4)
);

// afu_top_fake afu_top_fake_inst(
//     .afu_clk(axi4_mm_clk),
//     .afu_rstn(axi4_mm_rst_n),
//     .cxlip2iafu_to_mc_axi4(cxlip2iafu_to_mc_axi4),
//     .iafu2cxlip_from_mc_axi4(iafu2cxlip_from_mc_axi4)
// );

afu_mc afu_mc_inst(
    .afu_clk(axi4_mm_clk),
    .afu_rstn(axi4_mm_rst_n),
    .iafu2mc_to_nvme_axi4(iafu2mc_to_mc_axi4),
    .mc2iafu_from_nvme_axi4(mc2iafu_from_mc_axi4)
);

// pio_mem pio_mem_inst(
//     .axi4_mm_clk(axi4_mm_clk),
//     .axi4_mm_rst_n(axi4_mm_rst_n),
    
//     .to_pio_axi4(to_pio_axi4),
//     .from_pio_axi4(from_pio_axi4)
// );

intel_cxl_pio_ed_top #(
    .BE_CH(BE_CH)
) intel_cxl_pio_ed_top_inst (
  .Clk_i(axi4_mm_clk)		     ,
  .Rstn_i(axi4_mm_rst_n)	     ,
  .pio_txc_eop(pio_txc_eop)         ,
  .pio_txc_header(pio_txc_header)      ,
  .pio_txc_payload(pio_txc_payload)     ,
  .pio_txc_sop(pio_txc_sop)         ,
  .pio_txc_valid(pio_txc_valid)       ,
  .pio_to_send_cpl(pio_to_send_cpl)    ,
  .pio_txc_ready(pio_txc_ready)	     ,
  
  .tx_start(pio_tx_start),
  .tx_header_low(pio_tx_header_low),
  .tx_header_high(pio_tx_header_high),
  .tx_payload(pio_tx_payload),

  .pio_bar_addr(pio_bar_addr),
  .pio_requester_id(pio_requester_id),

  .pio_sqdb_valid   (pio_sqdb_valid),
  .pio_sqdb_tail    (pio_sqdb_tail),
  .pio_sqdb_ready   (pio_sqdb_ready),

  .pio_cqdb_valid   (pio_cqdb_valid),
  .pio_cqdb_head    (pio_cqdb_head),
  .pio_cqdb_ready   (pio_cqdb_ready)
);

cust_afu_wrapper cust_afu_wrapper_inst
(
      // Clocks
  .axi4_mm_clk(axi4_mm_clk), 

    // Resets
  .axi4_mm_rst_n(axi4_mm_rst_n),
  
  // [harry] AVMM interface - imported from ex_default_csr_top
  .csr_avmm_clk(csr_avmm_clk),
  .csr_avmm_rstn(csr_avmm_rstn),  
  .csr_avmm_waitrequest(),  
  .csr_avmm_readdata(csr_avmm_readdata),
  .csr_avmm_readdatavalid(csr_avmm_readdatavalid),
  .csr_avmm_writedata(csr_avmm_writedata),
  .csr_avmm_address(csr_avmm_address),
  .csr_avmm_write(csr_avmm_write),
  .csr_avmm_poison(1'b1),
  .csr_avmm_read(csr_avmm_read), 
  .csr_avmm_byteenable(csr_avmm_byteenable),
  
  .pio_tx_header_low (pio_tx_header_low),
  .pio_tx_header_high (pio_tx_header_high),
  .pio_tx_start(pio_tx_start),
  .pio_tx_payload(pio_tx_payload),

  .o_end_proc(end_proc),

  //cust_afu-> mc_top
  .nvme2iafu_to_mc_axi4(nvme2iafu_to_mc_axi4),
  .iafu2nvme_from_mc_axi4(iafu2nvme_from_mc_axi4),

  .pio_bar_addr(pio_bar_addr),
  .pio_requester_id(pio_requester_id),

  .pio_sqdb_valid   (pio_sqdb_valid),
  .pio_sqdb_tail    (pio_sqdb_tail),
  .pio_sqdb_ready   (pio_sqdb_ready),

  .pio_cqdb_valid   (pio_cqdb_valid),
  .pio_cqdb_head    (pio_cqdb_head),
  .pio_cqdb_ready   (pio_cqdb_ready),

  // .to_pio_axi4      (to_pio_axi4),
  // .from_pio_axi4    (from_pio_axi4),

  //afu -> cust_afu 
  .iafu2mc_to_nvme_axi4(iafu2mc_to_nvme_axi4),
  .mc2iafu_from_nvme_axi4(mc2iafu_from_nvme_axi4),

  .afu_init(),

  /*
    AXI-MM interface - write address channel
  */
  .awid(awid),
  .awaddr(awaddr), 
  .awlen(),
  .awsize(),
  .awburst(),
  .awprot(),
  .awqos(),
  .awuser(awuser),
  .awvalid(awvalid),
  .awcache(),
  .awlock(),
  .awregion(),
  .awatop(),
  .awready(awready),
  
  /*
    AXI-MM interface - write data channel
  */
  .wdata(wdata),
  .wstrb(wstrb),
  .wlast(wlast),
  .wuser(),
  .wvalid(wvalid),
  .wready(wready),
  
  /*
    AXI-MM interface - write response channel
  */ 
  .bid(bid),
  .bresp(bresp),
  .buser(),
  .bvalid(bvalid),
  .bready(bready),
  
  /*
    AXI-MM interface - read address channel
  */
  .arid(arid),
  .araddr(araddr),
  .arlen(),
  .arsize(),
  .arburst(),
  .arprot(),
  .arqos(),
  .aruser(aruser),
  .arvalid(arvalid),
  .arcache(),
  .arlock(),
  .arregion(),
  .arready(arready),

  /*
    AXI-MM interface - read response channel
  */ 
  .rid(rid),
  .rdata(rdata),
  .rresp(rresp),
  .rlast(rlast),
  .ruser(),
  .rvalid(rvalid),
  .rready(rready)
);

task start_function_tx;
  input logic [63:0] in_value;
  begin
    /*
    change testcase
    */
    #2 
    init_set = 0;
    #2 
    init_set = 1;

    #2	csr_avmm_address = 22'h10; //write to testcase
        csr_avmm_writedata = in_value;
    #2  csr_avmm_write = 1;
    #2	csr_avmm_write = 0;

    #2	csr_avmm_address = 22'h8; //write to sub_addr_0_reg
        csr_avmm_writedata = 64'd128;
    #2  csr_avmm_write = 1;
    #2	csr_avmm_write = 0;

    #50000


    #50000
    #2	csr_avmm_address = 22'h0; //write to end_proc
        csr_avmm_writedata = 64'd1;
    #2  csr_avmm_write = 1;
    #2	csr_avmm_write = 0;

    #5000

    #20	csr_avmm_address = 22'h30; //read from read-data
    #2  csr_avmm_read = 1;
    #2	csr_avmm_read = 0;
    @(negedge csr_avmm_clk iff csr_avmm_readdatavalid);
    result = csr_avmm_readdata;
    $display("the read_data is %d", result);

    #20	csr_avmm_address = 22'h70; //read from write_data
    #2  csr_avmm_read = 1;
    #2	csr_avmm_read = 0;
    @(negedge csr_avmm_clk iff csr_avmm_readdatavalid);
    result = csr_avmm_readdata;
    $display("the write_data is %d", result);
  end
endtask

task send_read;
  input logic channel;
  input logic [51:0] addr;
  input logic [7:0] arid;
  begin
        /*
    change testcase
    */
    #2 
    init_set = 0;
    #2 
    init_set = 1;

    @(posedge axi4_mm_clk);
    cxlip2iafu_to_mc_axi4[channel].arvalid = 1'b1;
    cxlip2iafu_to_mc_axi4[channel].araddr = addr;
    cxlip2iafu_to_mc_axi4[channel].arid = arid;
    @(posedge axi4_mm_clk iff iafu2cxlip_from_mc_axi4[channel].arready);
    cxlip2iafu_to_mc_axi4[channel].arvalid = 1'b0;
    cxlip2iafu_to_mc_axi4[channel].araddr = '0;
    cxlip2iafu_to_mc_axi4[channel].arid = '0;


    #50000
    // #20	csr_avmm_address = 22'h30; //write to end_proc_reg
    //     csr_avmm_writedata = 64'd0;
    // #2  csr_avmm_write = 1;
    #2	csr_avmm_write = 0;
  end
endtask

task send_multi_read;
  input logic channel;
  input logic [51:0] addr;
  input logic [7:0] arid;
  begin
        /*
    change testcase
    */
    #2 
    init_set = 0;
    #2 
    init_set = 1;

    #1
    for (int i=0; i< 12; i++ ) begin
      cxlip2iafu_to_mc_axi4[channel].arvalid = 1'b1;
      cxlip2iafu_to_mc_axi4[channel].araddr = addr+128*i;
      cxlip2iafu_to_mc_axi4[channel].arid = arid+i;
      @(posedge axi4_mm_clk iff iafu2cxlip_from_mc_axi4[channel].arready);
    end


    cxlip2iafu_to_mc_axi4[channel].arvalid = 1'b0;
    cxlip2iafu_to_mc_axi4[channel].araddr = '0;
    cxlip2iafu_to_mc_axi4[channel].arid = '0;


    #50000
    // #20	csr_avmm_address = 22'h30; //write to end_proc_reg
    //     csr_avmm_writedata = 64'd0;
    // #2  csr_avmm_write = 1;
    #2	csr_avmm_write = 0;
  end
endtask

task send_write;
  input logic [7:0] awid;
  input logic [51:0] addr;
  input logic channel;
  input logic [511:0] wdata;
  begin
        /*
    change testcase
    */
    #2 
    init_set = 0;
    #2 
    init_set = 1;
    
    //summary: afu_top launch a write request to cust_afu_wrapper based on the input params 
    @(posedge axi4_mm_clk);
    //awvalid high & init high --> state_run_W in afu_top
    cxlip2iafu_to_mc_axi4[channel].awvalid = 1'b1;
    //everything else other than wvalid assigned to iafu2mc_to_nvme_axi4 in afu_top, then pass to cust_afu_wrapper
    cxlip2iafu_to_mc_axi4[channel].awaddr = addr;
    cxlip2iafu_to_mc_axi4[channel].awid = awid;

    cxlip2iafu_to_mc_axi4[channel].wdata = wdata;
    //wvalid wait until state_run_w then pull high 
    cxlip2iafu_to_mc_axi4[channel].wvalid = 1'b1;
    cxlip2iafu_to_mc_axi4[channel].wlast = 1'b1;
    cxlip2iafu_to_mc_axi4[channel].wstrb = '1;
    cxlip2iafu_to_mc_axi4[channel].wuser = '0;

    //awready pull high in afu_top during idle state-->meaning when the afu is back at idle, it's ready to take another request, pull everything low 
    @(posedge axi4_mm_clk iff iafu2cxlip_from_mc_axi4[channel].awready);
    cxlip2iafu_to_mc_axi4[channel].awvalid = 1'b0;
    cxlip2iafu_to_mc_axi4[channel].awaddr = '0;
    cxlip2iafu_to_mc_axi4[channel].awid = '0;

    cxlip2iafu_to_mc_axi4[channel].wdata = '0;
    cxlip2iafu_to_mc_axi4[channel].wvalid = 1'b0;
    cxlip2iafu_to_mc_axi4[channel].wlast = 1'b0;
    cxlip2iafu_to_mc_axi4[channel].wstrb = '0;
    cxlip2iafu_to_mc_axi4[channel].wuser = '0;


    #50000
    // #20	csr_avmm_address = 22'h30; //write to end_proc_reg
    //     csr_avmm_writedata = 64'd0;
    // #2  csr_avmm_write = 1;
    #2	csr_avmm_write = 0;
  end
endtask


task send_multi_write;
  input logic [7:0] awid;
  input logic [51:0] addr;
  input logic channel;
  input logic [511:0] wdata;
  begin
        /*
    change testcase
    */
    #2 
    init_set = 0;
    #2 
    init_set = 1;

    for (int i=0; i< 12; i++ ) begin
      cxlip2iafu_to_mc_axi4[channel].awvalid = 1'b1;
      cxlip2iafu_to_mc_axi4[channel].awaddr = addr + 128*i;
      cxlip2iafu_to_mc_axi4[channel].awid = awid+i;

      cxlip2iafu_to_mc_axi4[channel].wdata = wdata + i;
      cxlip2iafu_to_mc_axi4[channel].wvalid = 1'b1;
      cxlip2iafu_to_mc_axi4[channel].wlast = 1'b1;
      cxlip2iafu_to_mc_axi4[channel].wstrb = '1;
      cxlip2iafu_to_mc_axi4[channel].wuser = '0;
      @(posedge axi4_mm_clk iff iafu2cxlip_from_mc_axi4[channel].awready);
    end

    // for (int i=0; i< 4; i++ ) begin
    //   cxlip2iafu_to_mc_axi4[channel].awvalid = 1'b1;
    //   cxlip2iafu_to_mc_axi4[channel].awaddr = addr + 64*i + 52'h100000000;
    //   cxlip2iafu_to_mc_axi4[channel].awid = awid + i + 4;

    //   cxlip2iafu_to_mc_axi4[channel].wdata = wdata + i;
    //   cxlip2iafu_to_mc_axi4[channel].wvalid = 1'b1;
    //   cxlip2iafu_to_mc_axi4[channel].wlast = 1'b1;
    //   cxlip2iafu_to_mc_axi4[channel].wstrb = '1;
    //   cxlip2iafu_to_mc_axi4[channel].wuser = '0;
    //   @(posedge axi4_mm_clk iff iafu2cxlip_from_mc_axi4[channel].awready);
    // end

    cxlip2iafu_to_mc_axi4[channel].awvalid = 1'b0;
    cxlip2iafu_to_mc_axi4[channel].awaddr = '0;
    cxlip2iafu_to_mc_axi4[channel].awid = '0;

    cxlip2iafu_to_mc_axi4[channel].wdata = '0;
    cxlip2iafu_to_mc_axi4[channel].wvalid = 1'b0;
    cxlip2iafu_to_mc_axi4[channel].wlast = 1'b0;
    cxlip2iafu_to_mc_axi4[channel].wstrb = '0;
    cxlip2iafu_to_mc_axi4[channel].wuser = '0;



    #50000
    // #20	csr_avmm_address = 22'h30; //write to end_proc_reg
    //     csr_avmm_writedata = 64'd0;
    // #2  csr_avmm_write = 1;
    #2	csr_avmm_write = 0;
  end
endtask

task test_m5;
  input logic [63:0] m5_interval;
  begin
    /*
    change testcase
    */
    #2 
    init_set = 0;
    #2 
    init_set = 1;

    #2	csr_avmm_address = 22'h128; //write to m5_interval_reg
        csr_avmm_writedata = m5_interval;
    #2  csr_avmm_write = 1;
    #2	csr_avmm_write = 0;

    #2	csr_avmm_address = 22'h120; //write to m5_query_en_reg
        csr_avmm_writedata = 64'd1;
    #2  csr_avmm_write = 1;
    #2	csr_avmm_write = 0;

    #5000

    #2	csr_avmm_address = 22'h120; //write to m5_query_en_reg
        csr_avmm_writedata = 64'd0;
    #2  csr_avmm_write = 1;
    #2	csr_avmm_write = 0;

  end
endtask

initial begin
    bresp = 2'b01; //OK signal 
	  rresp = 2'b00;
    axi4_mm_clk = 0;
    csr_avmm_clk = 0;
    axi4_mm_rst_n = 0;
    csr_avmm_rstn = 0;
    
#2  axi4_mm_rst_n = 1;
    csr_avmm_rstn = 1;
    csr_avmm_byteenable = '1;
    csr_avmm_read = 0;
    csr_avmm_write = 0;
    cxlip2iafu_to_mc_axi4[0].arvalid = 1'b0;
    cxlip2iafu_to_mc_axi4[1].arvalid = 1'b0;
    cxlip2iafu_to_mc_axi4[0].awvalid = 1'b0;
    cxlip2iafu_to_mc_axi4[1].awvalid = 1'b0;
    cxlip2iafu_to_mc_axi4[0].wvalid = 1'b0;
    cxlip2iafu_to_mc_axi4[1].wvalid = 1'b0;
    cxlip2iafu_to_mc_axi4[0].bready = 1'b1;
    cxlip2iafu_to_mc_axi4[1].bready = 1'b1;
    cxlip2iafu_to_mc_axi4[0].rready = 1'b1;
    cxlip2iafu_to_mc_axi4[1].rready = 1'b1;
#2
    init_set = 0;
#2
    init_set = 1;

    // for (int i = 0; i<64; i++) begin
    //   sub_queue[i] = '0;
    // end
/*###################################
Poll test
########################################*/
$display("-----------Poll test");

for (int i=0; i<BE_CH; i++) begin
  $display("-----------queue %0d setup", i);
  #20	csr_avmm_address = 22'h110; //write to queue index
      csr_avmm_writedata = i;
  #2  csr_avmm_write = 1;
  #2	csr_avmm_write = 0;

  #20	csr_avmm_address = 22'hD0; //write to sq_addr_reg
      csr_avmm_writedata = 64'h8080000000 + 64*1024*i;
  #2  csr_avmm_write = 1;
  #2	csr_avmm_write = 0;

  #20	csr_avmm_address = 22'hD8; //write to cq_addr_reg [0, 32768]
      csr_avmm_writedata = 64'h7080000000 + 16*1024*i;
      // csr_avmm_writedata = 64'h7080000000;
  #2  csr_avmm_write = 1;
  #2	csr_avmm_write = 0;

  #20	csr_avmm_address = 22'hF0; //write to cq_head_reg
      csr_avmm_writedata = 64'd0;
  #2  csr_avmm_write = 1;
  #2	csr_avmm_write = 0;

  #20	csr_avmm_address = 22'hE8; //write to sq_tail_reg
      csr_avmm_writedata = 64'd0;
  #2  csr_avmm_write = 1;
  #2	csr_avmm_write = 0;

  #20	csr_avmm_address = 22'h0128; //write to rdma local key 
      csr_avmm_writedata = 64'h017e5a4;
  #2  csr_avmm_write = 1;
  #2	csr_avmm_write = 0;

  #20	csr_avmm_address = 22'h0130; //write to rdma local address 
      csr_avmm_writedata = 64'h60b5757db040;
  #2  csr_avmm_write = 1;
  #2	csr_avmm_write = 0;

  #20	csr_avmm_address = 22'h0138; //write to rdma remote key 
      csr_avmm_writedata = 64'h001ffbba;
  #2  csr_avmm_write = 1;
  #2	csr_avmm_write = 0;

  #20	csr_avmm_address = 22'h0140; //write to rdma remote address 
      csr_avmm_writedata = 64'h560e468070000;
  #2  csr_avmm_write = 1;
  #2	csr_avmm_write = 0;

  #20	csr_avmm_address = 22'h0148; //write to rdma qpn_ds 
      csr_avmm_writedata = 64'h03ae0000;
  #2  csr_avmm_write = 1;
  #2	csr_avmm_write = 0;



  for (int j=0; j<1; j++) begin
    #20	csr_avmm_address = 22'h108; //write to host_buf_addr_reg
        csr_avmm_writedata = 64'h6080000000 + 1024*BF_ID*i + 1024*j;
    #2  csr_avmm_write = 1;
    #2  csr_avmm_write = 0;
  end

  #20	csr_avmm_address = 22'h118; //write to delay_cnt_reg
      csr_avmm_writedata = 64'h100;
  #2  csr_avmm_write = 1;
  #2	csr_avmm_write = 0;

end



#20	csr_avmm_address = 22'h0; //write to update
	  csr_avmm_writedata = 64'd3;
#2  csr_avmm_write = 1;
#2	csr_avmm_write = 0;


// cache conflict 1
$display("\n*************start function 1***************\n");
#10
send_write(.awid(7), .addr(52'h6070000000 + 52'h1810000000 + 512 + 64), .channel(1), .wdata(8));

// // cache conflict
// $display("\n*************start function***************\n");
// #10
// send_write(.awid(2), .addr(52'h6070000000 + 52'h1810000000 + 512 + 512 + 512 + 64 + 64), .channel(0), .wdata(5));

$display("\n*************start function 2***************\n");
#10
send_write(.awid(9), .addr(52'h6070000000 + 52'h1a10000000 + 512 + 64 + 64), .channel(1), .wdata(10));
 
// $display("\n*************start function***************\n");
// #10
// send_read(.arid(3), .addr(52'h6070000000 + 52'h1810000000 + 512  + 64), .channel(1));

// $display("\n*************start function***************\n");
// #10
// send_write(.awid(8), .addr(52'h6070000000 + 52'h1810000000 + 64), .channel(1), .wdata(8));

// $display("\n*************start function***************\n");
// #10
// send_read(.arid(7), .addr(52'h6070000000 + 52'h1810000000 + 512  + 64), .channel(0));


// $display("\n*************start function***************\n");
// #10
// send_multi_write(.awid(7), .addr(52'h6070000000 + 52'h1810000000 + 512), .channel(0), .wdata(15));

// $display("\n*************start function***************\n");
// #10
// send_multi_read(.arid(3), .addr(52'h6070000000 + 52'h1a10000000 + 512), .channel(1));

  // $display("\n*************start function***************\n");
  // #10
  // test_m5(.m5_interval(64'd100)); //test m5 interval

  #1000


    #20	csr_avmm_address = 22'h118; //read from read-data
    #2  csr_avmm_read = 1;
    #2	csr_avmm_read = 0;
    @(negedge csr_avmm_clk iff csr_avmm_readdatavalid);
    result = csr_avmm_readdata;
    $display("the read_data is %d", result);

#20
$stop;

end

logic [63:0] data_size;
int i;

logic [31:0] pf_pci_bar_id;
assign pf_pci_bar_id = pio_txc_header[127:96];

always_ff @(posedge axi4_mm_clk) begin
  if (!axi4_mm_rst_n) begin
    arready <= 1'b0;
    rvalid <= 1'b0;
    // init_set<= 1'b0;
    for (int i = 0; i<1024; i++) begin
      cxl_tag[i] <= '0;
      cxl_data[i] <= '0;
      ssd_data[i] <= '0;
    end

    awready <= 1'b0;
    wready <= 1'b0;
    bvalid <= 1'b0;
    for (int j = 0; j<BE_CH; j++) begin
      for (int k=0; k<BF_ID; k++) begin
        sq_cid[k][j] <= '0;
      end
      // sq_cid[j] <= 16'h1001; //same as hard coded in front end
      sq_tail[j] <= 64'h0;
      sq_cid_head[j] <= '0;
      sq_cid_tail[j] <= '0;
    end
  end
  else begin
    //write doorbell
    copy_from_ssd <= 1'b0;
    copy_to_ssd   <= 1'b0;
    if (pio_txc_valid & pio_txc_ready) begin
      for (int i = 0; i < BE_CH; i++) begin
        if (pio_txc_header[127:96] == pio_bar_addr + 4096 + (8 * (i + 1) + 4)) begin //write to cq doorbell
          sq_cid_head[i] <= sq_cid_head[i] + 1;
        end
        else if (pio_txc_header[127:96] == pio_bar_addr + 4096 + (8 * (i + 1))) begin  //write to sq_doorbell
          if (ssd_cmd[i][sq_cid_tail[i]][15:0] == 16'h0002) begin  // SSD read
            copy_from_ssd <= 1'b1;
            for (int j = 0; j < 8; j++) begin
              cxl_data[{ssd_cmd[i][sq_cid_tail[i]][207:201], j[2:0]}] <=
                  ssd_data[ssd_cmd[i][sq_cid_tail[i]][349:340]][(512*(j+1)-1) -: 512];
            end
          end else begin  // SSD write
            copy_to_ssd <= 1'b1;
            for (int j = 0; j < 8; j++) begin
              ssd_data[ssd_cmd[i][sq_cid_tail[i]][349:340]][(512*(j+1)-1) -: 512] <=
                  cxl_data[{ssd_cmd[i][sq_cid_tail[i]][207:201], j[2:0]}];
            end
          end

          sq_tail[i] <= sq_tail[i] + 1;
          sq_cid[i][sq_cid_tail[i]]  <= ssd_cmd[i][sq_cid_tail[i]][31:16];
          sq_cid_tail[i] <= sq_cid_tail[i] + 1;
        end
      end
    end
    else begin
      copy_to_ssd <= 1'b0;
      copy_from_ssd <= 1'b0;
    end

    if (arvalid & arready) begin
      arready <= 1'b0;
      
      if ((araddr >= 64'h4080000000) && (araddr < 64'h4180000000)) begin //read tag addr
        rvalid <= 1'b1;
        rdata <= cxl_tag[araddr[15:6]];
        rlast <= 1'b1;
        rid <= arid;
        $display("read tag");
      end
      else if ((araddr >= 64'h4180000000) && (araddr < 64'h6080000000 + 1024*BE_CH*BF_ID)) begin  //read data
        rvalid <= 1'b1;
        rdata <= cxl_data[araddr[15:6]];
        rlast <= 1'b1;
        rid <= arid;
        cxl_index_1 <= araddr[15:6];
      end
      else if ((araddr >= 64'h6080000000) && (araddr <= 64'h6080000000 + 1024*BE_CH*BF_ID)) begin //read host buffer
        rvalid <= 1'b1;
        rdata <= host_buf[host_buf_ar_id][araddr[8:6]];
        rlast <= 1'b1;
        rid <= arid;
      end
      else if ((araddr >= 64'h7080000000) && (araddr <= 64'h7080000000 + 64*16*1024)) begin   //completion queue entry
        rvalid <= 1'b1;
        unique case (sq_cid_head[queue_idx][1:0])
          2'b00: rdata <= {128'h0, 128'h0, 128'h0, {15'b0, 1'b1, sq_cid[queue_idx][sq_cid_head[queue_idx]], 96'h0}};
          2'b01: rdata <= {128'h0, 128'h0, {15'b0, 1'b1, sq_cid[queue_idx][sq_cid_head[queue_idx]], 96'h0}, 128'h0}; 
          2'b10: rdata <= {128'h0, {15'b0, 1'b1, sq_cid[queue_idx][sq_cid_head[queue_idx]], 96'h0}, 128'h0, 128'h0};
          2'b11: rdata <= {{15'b0, 1'b1, sq_cid[queue_idx][sq_cid_head[queue_idx]], 96'h0}, 128'h0, 128'h0, 128'h0};
        endcase
        rlast <= 1'b1;
        rid <= arid;
      end
      else begin
        rvalid <= 1'b1;
        rdata <= 64'd100;
        rlast <= 1'b1;
        rid <= arid;
      end
    end
    else if (arvalid) begin
      arready <= 1'b1;
    end

    if (rready & rvalid) begin
      rvalid <= 1'b0;
    end

    if (awready & awvalid) begin
      awready <= 1'b0;
    end
    else if (awvalid) begin
      awready <= 1'b1;
    end

    if (wready & wvalid) begin
      if ((awaddr >= 64'h4080000000) && (awaddr < 64'h4180000000)) begin  //write to tag
        cxl_tag[awaddr[15:6]] <= wdata;
      end
      else if ((awaddr >= 64'h4180000000) && (awaddr < 64'h6080000000)) begin  //write to data
        cxl_data[awaddr[15:6]] <= wdata;
        cxl_index_1 <= araddr[15:6];
      end
      else if ((awaddr >= 64'h6080000000) && (awaddr <= 64'h6080000000 + 1024*BE_CH*BF_ID)) begin  //host buffer
        host_buf[host_buf_aw_id][awaddr[8:6]] <= wdata;
      end
      else if ((awaddr >= 64'h8080000000) && (awaddr < 64'h8080000000 + 64*1024*BE_CH)) begin //write to submission queue
        for (int i = 0; i < BE_CH; i++) begin
          if (awaddr[23:16] == i) begin
            ssd_cmd[i][sq_cid_tail[i]] <= wdata;
          end
        end
      end
      wready <= 1'b0;
      bvalid <= 1'b1;
      bid <= awid;
    end
    else if (wvalid) begin
      wready <= 1'b1;
    end

    if (bvalid & bready) begin
      bvalid <= 1'b0;
    end
  end
end


always_ff @(posedge axi4_mm_clk) begin
  //write signal
  if (awready & awvalid) begin
    $display("write adress");
    $display("awuser: %b", awuser);
    $display("awid: %d", awid);
    $display("--------------");
  end

  if (wready & wvalid) begin
    //check data going into local dram cache (through AXI-MM)
      $display("write data %h at addr %h, wstrb: %h", wdata, awaddr, wstrb);
      if (wlast) begin
        $display("write last");
      end
      $display("--------------");
  end

  if (bready & bvalid) begin
    $display("write response");
    $display("b id: %d", bid);
    $display("--------------");
  end


  //read signal
  if (arready & arvalid) begin
      $display("read address");
      $display("araddr: %h", araddr);
      $display("aruser: %b", aruser);
      $display("arid: %d", arid);
      $display("--------------");
    // end
  end

  if (rready & rvalid) begin
    $display("read data: %h", rdata);
    $display("read id: %d", rid);
    if (rlast) begin
      $display("read last");
    end
    $display("--------------");
  end

  if (pio_txc_valid & pio_txc_ready) begin
    $display("send pio packet: %h, %d", pio_txc_header, pio_txc_payload);
    $display("--------------");
  end

  if (cxlip2iafu_to_mc_axi4[0].arvalid && iafu2cxlip_from_mc_axi4[0].arready) begin
      $display("ar[0] handshake");
      $display("arid is %d, araddr is %h", cxlip2iafu_to_mc_axi4[0].arid, cxlip2iafu_to_mc_axi4[0].araddr);
  end
  if (cxlip2iafu_to_mc_axi4[1].arvalid && iafu2cxlip_from_mc_axi4[1].arready) begin
      $display("ar[1] handshake");
      $display("arid is %d, araddr is %h", cxlip2iafu_to_mc_axi4[1].arid, cxlip2iafu_to_mc_axi4[1].araddr);
  end
  if (cxlip2iafu_to_mc_axi4[0].rready && iafu2cxlip_from_mc_axi4[0].rvalid) begin
      $display("r[0] handshake");
      $display("crid is %d, rdata is %h", iafu2cxlip_from_mc_axi4[0].rid, iafu2cxlip_from_mc_axi4[0].rdata);
  end
  if (cxlip2iafu_to_mc_axi4[1].rready && iafu2cxlip_from_mc_axi4[1].rvalid) begin
      $display("r[1] handshake");
      $display("crid is %d, rdata is %h", iafu2cxlip_from_mc_axi4[1].rid, iafu2cxlip_from_mc_axi4[1].rdata);
  end
  if (cxlip2iafu_to_mc_axi4[0].awvalid && iafu2cxlip_from_mc_axi4[0].awready) begin
      $display("aw[0] handshake");
      $display("awid is %d, awaddr is %h", cxlip2iafu_to_mc_axi4[0].awid, cxlip2iafu_to_mc_axi4[0].awaddr);
  end
  if (cxlip2iafu_to_mc_axi4[1].awvalid && iafu2cxlip_from_mc_axi4[1].awready) begin
      $display("aw[1] handshake");
      $display("awid is %d, awaddr is %h", cxlip2iafu_to_mc_axi4[1].awid, cxlip2iafu_to_mc_axi4[1].awaddr);
  end
  if (cxlip2iafu_to_mc_axi4[0].wvalid && iafu2cxlip_from_mc_axi4[0].wready) begin
      $display("w[0] handshake");
  end
  if (cxlip2iafu_to_mc_axi4[1].wvalid && iafu2cxlip_from_mc_axi4[1].wready) begin
      $display("w[1] handshake");
  end
  if (cxlip2iafu_to_mc_axi4[0].bready && iafu2cxlip_from_mc_axi4[0].bvalid) begin
      $display("b[0] handshake");
      $display("bid is %d", iafu2cxlip_from_mc_axi4[0].bid);
  end
  if (cxlip2iafu_to_mc_axi4[1].bready && iafu2cxlip_from_mc_axi4[1].bvalid) begin
      $display("b[1] handshake");
      $display("bid is %d", iafu2cxlip_from_mc_axi4[1].bid);
  end
end

endmodule