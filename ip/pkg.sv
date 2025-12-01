package ed_mc_axi_if_pkg;
// ================================================================================================
 /* structs for bit widths
  
    APRIL 14 2023 - these are set based on Darren's current CXL IP HAS draft ch3.3 values
 */
// @@copy for common_afu_pkg@@start
  localparam MC_AXI_WAC_REGION_BW  =  4; // awregion
  localparam MC_AXI_WAC_ADDR_BW    = 52; // awaddr  - using bits 51:6 of 64-bits, also grabbing the lower 6 bits?
  localparam MC_AXI_WAC_USER_BW    =  1; // awuser
  localparam MC_AXI_WAC_ID_BW      =  8; // awid    - feb2024 - changed from 12
  localparam MC_AXI_WAC_BLEN_BW    = 10; // awlen
  
  localparam MC_AXI_WDC_DATA_BW = 512; // wwdata
  localparam MC_AXI_WDC_USER_BW =  1;  // wuser  // currently only poison
  
  localparam MC_AXI_WDC_STRB_BW = MC_AXI_WDC_DATA_BW / 8; // wstrb
  
  localparam MC_AXI_WRC_ID_BW   =  8; // bid   - feb2024 - changed from 12
  localparam MC_AXI_WRC_USER_BW =  1; // buser
  
  localparam MC_AXI_RAC_REGION_BW  =  4; // arregion
  localparam MC_AXI_RAC_ID_BW      =  8; // arid    - feb2024 - changed from 12
  localparam MC_AXI_RAC_ADDR_BW    = 52; // araddr  - using bits 51:6 of 64-bits, also grabbing the lower 6 bits?
  localparam MC_AXI_RAC_BLEN_BW    = 10; // arlen
  localparam MC_AXI_RAC_USER_BW    =  1; // aruser
  
  localparam MC_AXI_RRC_ID_BW        =   8; // rid   - feb2024 - changed from 12
  localparam MC_AXI_RRC_DATA_BW      = 512; // rdata
  localparam MC_EMIF_AMM_RRC_DATA_BW = 576; // rdata from EMIF AMM.

// ================================================================================================
// struct for read response channel response field
// ================================================================================================
  typedef struct packed {
	logic poison;
  } t_rd_rsp_user;

  localparam MC_AXI_RRC_USER_BW = $bits( t_rd_rsp_user );
  
// ================================================================================================
// AXI signals from BBS to MC
// ================================================================================================
  typedef struct packed {
    logic   bready;
    logic   rready;
	
	logic [MC_AXI_WAC_ID_BW-1:0]                 awid;
	logic [MC_AXI_WAC_ADDR_BW-1:0]               awaddr;
	logic [MC_AXI_WAC_BLEN_BW-1:0]               awlen;
	logic [2:0]   awsize;
	logic [1:0]        awburst;
	logic [2:0]         awprot;
	logic [3:0]          awqos;
	logic                                        awvalid;
	logic [3:0]      awcache;
	logic [1:0]         awlock;
	logic [MC_AXI_WAC_REGION_BW-1:0]             awregion;
	logic [MC_AXI_WAC_USER_BW-1:0]               awuser;
	
    logic [MC_AXI_WDC_DATA_BW-1:0] wdata;
	logic [MC_AXI_WDC_STRB_BW-1:0] wstrb;
	logic                          wlast;
	logic                          wvalid;
	logic [MC_AXI_WDC_USER_BW-1:0] wuser; // currently only poison
	
	logic [MC_AXI_RAC_ID_BW-1:0]                 arid;
	logic [MC_AXI_RAC_ADDR_BW-1:0]               araddr;
	logic [MC_AXI_RAC_BLEN_BW-1:0]               arlen;
    logic [2:0]   arsize;
    logic [1:0]        arburst;
    logic [2:0]         arprot;
    logic [3:0]          arqos;
	logic                                        arvalid;
    logic [3:0]      arcache;
    logic [1:0]        arlock;
    logic [MC_AXI_RAC_REGION_BW-1:0]             arregion;
    logic [MC_AXI_RAC_USER_BW-1:0]               aruser;
  } t_to_mc_axi4;

  typedef struct packed {
    logic   bready;
    logic   rready;
	
	logic [MC_AXI_WAC_ID_BW:0]                 awid;
	logic [MC_AXI_WAC_ADDR_BW-1:0]               awaddr;
	logic [MC_AXI_WAC_BLEN_BW-1:0]               awlen;
	logic [2:0]   awsize;
	logic [1:0]        awburst;
	logic [2:0]         awprot;
	logic [3:0]          awqos;
	logic                                        awvalid;
	logic [3:0]      awcache;
	logic [1:0]         awlock;
	logic [MC_AXI_WAC_REGION_BW-1:0]             awregion;
	logic [MC_AXI_WAC_USER_BW-1:0]               awuser;
	
    logic [MC_AXI_WDC_DATA_BW-1:0] wdata;
	logic [MC_AXI_WDC_STRB_BW-1:0] wstrb;
	logic                          wlast;
	logic                          wvalid;
	logic [MC_AXI_WDC_USER_BW-1:0] wuser; // currently only poison
	
	logic [MC_AXI_RAC_ID_BW:0]                 arid;
	logic [MC_AXI_RAC_ADDR_BW-1:0]               araddr;
	logic [MC_AXI_RAC_BLEN_BW-1:0]               arlen;
    logic [2:0]   arsize;
    logic [1:0]        arburst;
    logic [2:0]         arprot;
    logic [3:0]          arqos;
	logic                                        arvalid;
    logic [3:0]      arcache;
    logic [1:0]        arlock;
    logic [MC_AXI_RAC_REGION_BW-1:0]             arregion;
    logic [MC_AXI_RAC_USER_BW-1:0]               aruser;
  } t_to_mc_axi4_extended;
  
  localparam TO_MC_AXI4_BW = $bits(t_to_mc_axi4);
  
// ================================================================================================
  typedef struct packed {
    logic   awready;
    logic    wready;
    logic   arready;
	
	logic [MC_AXI_WRC_ID_BW-1:0]           bid;
	logic [1:0]   bresp;
	logic                                  bvalid;
	logic [MC_AXI_WRC_USER_BW-1:0]         buser;

	logic [MC_AXI_RRC_ID_BW-1:0]           rid;
	logic [MC_AXI_RRC_DATA_BW-1:0]         rdata;
	logic [1:0]   rresp;
	logic                                  rvalid;
	logic                                  rlast;
    //logic [MC_AXI_RRC_USER_BW-1:0]         ruser;
	t_rd_rsp_user                          ruser;
  } t_from_mc_axi4;
  
    typedef struct packed {
    logic   awready;
    logic    wready;
    logic   arready;
	
	logic [MC_AXI_WRC_ID_BW:0]           bid;
	logic [1:0]   bresp;
	logic                                  bvalid;
	logic [MC_AXI_WRC_USER_BW-1:0]         buser;

	logic [MC_AXI_RRC_ID_BW:0]           rid;
	logic [MC_AXI_RRC_DATA_BW-1:0]         rdata;
	logic [1:0]   rresp;
	logic                                  rvalid;
	logic                                  rlast;
    //logic [MC_AXI_RRC_USER_BW-1:0]         ruser;
	t_rd_rsp_user                          ruser;
  } t_from_mc_axi4_extended;

  localparam FROM_MC_AXI4_BW = $bits(t_from_mc_axi4);
  localparam FROM_MC_AXI4_BW_PARM = $bits(t_from_mc_axi4);
  localparam MC_CHANNEL = 2;
// ================================================================================================


  typedef struct packed {
    //issue channel
    logic         ssd_rq_valid;
    logic         ssd_rq_type;  // 0: read, 1: write
    logic[63:0]   ssd_rq_addr;
    logic[63:0]   ssd_rq_hash;
    logic[11:0]   ssd_rq_fe_id;    //fe_id

    //resonse channel
    logic         ssd_cp_ready;

    //ack channel (only for write)
    logic         ssd_bf_ready;
    
    logic         ssd_ack_valid;
    logic [11:0]  ssd_ack_be_id;

    //release channel
    logic         ssd_rl_valid;
    logic [11:0]  ssd_rl_be_id;
  } t_to_nvme_axi4;

  typedef struct packed {
    //issue channel
    logic         ssd_rq_ready;
    
    //resonse channel
    logic         ssd_cp_valid;
    logic [63:0]  ssd_cp_addr;      //address of the host memory buffer
    logic [11:0]  ssd_cp_fe_id;     //fe_id
    logic [11:0]  ssd_cp_be_id;

    //ack channel (only for write)
    logic         ssd_bf_valid;
    logic [63:0]  ssd_bf_addr;  //address of the host memory buffer
    logic [11:0]  ssd_bf_be_id;
    logic [11:0]  ssd_bf_fe_id;

    logic         ssd_ack_ready;

    //release channel
    logic         ssd_rl_ready;
  } t_from_nvme_axi4;

  function automatic int log2ceil(input int val);
      int i;
      begin
          log2ceil = 0;
          for (i = val - 1; i > 0; i = i >> 1)
              log2ceil++;
      end
  endfunction
  
  typedef struct packed {
    //issue channel
    logic arvalid;
    logic [63:0] araddr;

    logic awvalid;
    logic [63:0] awaddr;
    
    logic wvalid;
    logic [1023:0] wdata;

    //resonse channel
    logic rready;
    logic bready;
  } t_to_pio_axi4;

  typedef struct packed {
    //issue channel
    logic arready;
    logic awready;
    logic wready;

    //resonse channel
    logic rvalid;
    logic [1023:0] rdata;

    logic bvalid;
  } t_from_pio_axi4;
  
endpackage : ed_mc_axi_if_pkg


package m5_pkg;
    // 34 + 2 = 36 bits
    typedef struct packed {
        logic [33:0] araddr;
        logic arvalid;
        logic arready;
    } queue_struct_t;
endpackage


package ed_cxlip_top_pkg;
    // 34 + 2 = 36 bits
    typedef struct packed {
        logic [33:0] araddr;
        logic arvalid;
        logic arready;
    } queue_struct_t;
endpackage


