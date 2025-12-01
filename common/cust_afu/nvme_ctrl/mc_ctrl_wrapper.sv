module mc_ctrl_wrapper #(
    parameter MC_CH = 2,

    parameter MSHR_CH = 1,

    //cafu: [11:6] channel_id, [5:0] used by wrapper
    parameter logic [2:0] channel_id, 
    //cafu arid 
    parameter logic [7:0] cafu_arid_rd_buf  = 6'b1,   

    //cafu awid
    parameter logic [7:0] cafu_awid_wr_buf  = 6'd1,

    //mc: [7:2] channel_id, [1:0] used by wrapper 
    //mc arid 
    parameter logic [2:0] mc_arid_rd_tag    = 2'd0,
    parameter logic [2:0] mc_arid_rd_data   = 2'd1,
    parameter logic [2:0] mc_arid_rd_buf    = 2'd2,

    //mc awid 
    parameter logic [2:0] mc_awid_wr_tag    = 2'd0,
    parameter logic [2:0] mc_awid_wr_data   = 2'd1,
    parameter logic [2:0] mc_awid_wr_buf    = 2'd2
)
(
    input logic axi4_mm_clk,
    input logic axi4_mm_rst_n,

    //from IP
    input ed_mc_axi_if_pkg::t_to_mc_axi4_extended    [MC_CH-1:0] iafu2mc_to_nvme_axi4,
    output ed_mc_axi_if_pkg::t_from_mc_axi4_extended [MC_CH-1:0] mc2iafu_from_nvme_axi4,

    //from csr 
    input logic         i_end_proc,
    input logic         i_update,
    
    input logic [63:0]  i_delay_cnt,

    //to back_end
    output ed_mc_axi_if_pkg::t_to_nvme_axi4   fe_to_nvme_axi4,
    input ed_mc_axi_if_pkg::t_from_nvme_axi4  nvme_to_fe_axi4,

    //to MC
    output ed_mc_axi_if_pkg::t_to_mc_axi4   [1:0] nvme2iafu_to_mc_axi4 [2*MSHR_CH-1:0],
    input ed_mc_axi_if_pkg::t_from_mc_axi4  [1:0] iafu2nvme_from_mc_axi4 [2*MSHR_CH-1:0],

    //to CAFU
    input logic             arready     [MSHR_CH-1:0],
    output logic [63:0]     araddr      [MSHR_CH-1:0],
    output logic            arvalid     [MSHR_CH-1:0],
    output logic [11:0]     arid        [MSHR_CH-1:0],
    output logic [5:0]      aruser      [MSHR_CH-1:0],

    input logic             rready,
    input logic             rvalid,
    input logic             rlast,
    input logic [511:0]     rdata,
    input logic [1:0]       rresp,
    input logic [11:0]      rid,

    input logic             wready      [MSHR_CH-1:0],
    output logic            wvalid      [MSHR_CH-1:0],
    output logic [511:0]    wdata       [MSHR_CH-1:0],
    output logic            wlast       [MSHR_CH-1:0], 
    output logic [(512/8)-1:0] wstrb    [MSHR_CH-1:0], 

    input logic             awready     [MSHR_CH-1:0],
    output logic            awvalid     [MSHR_CH-1:0],
    output logic [11:0]     awid        [MSHR_CH-1:0],
    output logic [5:0]      awuser      [MSHR_CH-1:0],
    output logic [63:0]     awaddr      [MSHR_CH-1:0],
    
    input logic             bvalid,
    input logic [1:0]       bresp,
    input logic             bready,
    input logic [11:0]      bid,

    output logic [63:0]     fe_in_flight_c0,
    output logic [63:0]     fe_in_flight_c1
);

front_end 
#(
    .MSHR_CH(MSHR_CH),
    .MC_CH(MC_CH),

    .CH_ID(channel_id),

    .arid_rd_tag    (mc_arid_rd_tag),
    .arid_rd_data   (mc_arid_rd_data),
    .awid_wr_tag    (mc_awid_wr_tag),
    .awid_wr_data   (mc_awid_wr_data),

    .arid_rd_buf_cafu    (cafu_arid_rd_buf),
    .awid_wr_buf_cafu    (cafu_awid_wr_buf),

    .arid_rd_buf_mc    (mc_arid_rd_buf),
    .awid_wr_buf_mc    (mc_awid_wr_buf)
)
front_end_inst
(
    .axi4_mm_clk            (axi4_mm_clk),
    .axi4_mm_rst_n          (axi4_mm_rst_n),

    //to csr
    .i_end_proc             (i_end_proc),

    //to mc_fifo
    .nvme2iafu_to_mc_axi4   (nvme2iafu_to_mc_axi4),
    .iafu2nvme_from_mc_axi4 (iafu2nvme_from_mc_axi4),

    //to afu_nvme
    .iafu2mc_to_nvme_axi4   (iafu2mc_to_nvme_axi4),
    .mc2iafu_from_nvme_axi4 (mc2iafu_from_nvme_axi4),

    //to back_end
    .fe_to_nvme_axi4         (fe_to_nvme_axi4),
    .nvme_to_fe_axi4         (nvme_to_fe_axi4), 

    //to cust_afu
    .arready                 (arready   [MSHR_CH-1:0]),       
    .araddr                  (araddr    [MSHR_CH-1:0]),    
    .arvalid                 (arvalid   [MSHR_CH-1:0]),      
    .arid                    (arid      [MSHR_CH-1:0]),      
    .aruser                  (aruser    [MSHR_CH-1:0]),   
    
    .rready                  (rready),
    .rvalid                  (rvalid),
    .rlast                   (rlast ),
    .rdata                   (rdata ),
    .rresp                   (rresp ),
    .rid                     (rid),
    
    .wready                  (wready    [MSHR_CH-1:0]),    
    .wvalid                  (wvalid    [MSHR_CH-1:0]),    
    .wdata                   (wdata     [MSHR_CH-1:0]),     
    .wlast                   (wlast     [MSHR_CH-1:0]),     
    .wstrb                   (wstrb     [MSHR_CH-1:0]),     
    
    .awready                 (awready   [MSHR_CH-1:0]),       
    .awvalid                 (awvalid   [MSHR_CH-1:0]),       
    .awid                    (awid      [MSHR_CH-1:0]),      
    .awuser                  (awuser    [MSHR_CH-1:0]),    
    .awaddr                  (awaddr    [MSHR_CH-1:0]),    
    
    .bvalid                  (bvalid),
    .bresp                   (bresp),
    .bready                  (bready),
    .bid                     (bid)
);    

//peroformance counter
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

// always_ff @(posedge axi4_mm_clk) begin
//     if (!axi4_mm_rst_n) begin
//         num_ar_handshake_0      <=  64'd0;
//         num_aw_handshake_0      <=  64'd0;
//         num_r_handshake_0       <=  64'd0;
//         num_b_handshake_0        <=  64'd0;

//         num_ar_handshake_1      <=  64'd0;
//         num_aw_handshake_1      <=  64'd0;
//         num_r_handshake_1       <=  64'd0;
//         num_b_handshake_1        <=  64'd0;
//     end
//     else begin
//         if (nvme2iafu_to_mc_axi4[0].arvalid && iafu2nvme_from_mc_axi4[0].arready) begin
//             num_ar_handshake_0 <= num_ar_handshake_0 + 64'd1;
//         end

//         if (nvme2iafu_to_mc_axi4[1].arvalid && iafu2nvme_from_mc_axi4[1].arready) begin
//             num_ar_handshake_1 <= num_ar_handshake_1 + 64'd1;
//         end

//         if (nvme2iafu_to_mc_axi4[0].awvalid && iafu2nvme_from_mc_axi4[0].awready) begin
//             num_aw_handshake_0 <= num_aw_handshake_0 + 64'd1;
//         end

//         if (nvme2iafu_to_mc_axi4[1].awvalid && iafu2nvme_from_mc_axi4[1].awready) begin
//             num_aw_handshake_1 <= num_aw_handshake_1 + 64'd1;
//         end

//         if (nvme2iafu_to_mc_axi4[0].rready && iafu2nvme_from_mc_axi4[0].rvalid) begin
//             num_r_handshake_0 <= num_r_handshake_0 + 64'd1;
//         end

//         if (nvme2iafu_to_mc_axi4[1].rready && iafu2nvme_from_mc_axi4[1].rvalid) begin
//             num_r_handshake_1 <= num_r_handshake_1 + 64'd1;
//         end

//         if (nvme2iafu_to_mc_axi4[0].bready && iafu2nvme_from_mc_axi4[0].bvalid) begin
//             num_b_handshake_0 <= num_b_handshake_0 + 64'd1;
//         end

//         if (nvme2iafu_to_mc_axi4[1].bready && iafu2nvme_from_mc_axi4[1].bvalid) begin
//             num_b_handshake_1 <= num_b_handshake_1 + 64'd1;
//         end
//     end
// end


endmodule