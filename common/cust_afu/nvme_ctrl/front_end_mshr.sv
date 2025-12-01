/*
Module: mshr
Purpose: processing memory requests
Date: 10/28/25
*/

module mshr #(
    parameter CH_ID = 0,
    
    parameter MC_CH = 2,
    parameter RW_CH = 2,
    parameter CAFU_CH = 2
)
(
    input logic axi4_mm_clk,
    input logic axi4_mm_rst_n,

    //from front_end
    input logic     fe_to_mshr_valid,
    output logic    mshr_to_fe_ready,
    output logic    mshr_to_fe_busy,

    //to memory controller
    output ed_mc_axi_if_pkg::t_to_mc_axi4 [MC_CH-1:0] nvme2iafu_to_mc_axi4,
    input ed_mc_axi_if_pkg::t_from_mc_axi4 [MC_CH-1:0] iafu2nvme_from_mc_axi4,

    //to backend
    output  ed_mc_axi_if_pkg::t_to_nvme_axi4     fe_to_nvme_axi4,
    input   ed_mc_axi_if_pkg::t_from_nvme_axi4   nvme_to_fe_axi4,

    //to CAFU
    input logic             arready[RW_CH-1:0],
    output logic [63:0]     araddr[RW_CH-1:0],
    output logic            arvalid[RW_CH-1:0],
    output logic [11:0]     arid[RW_CH-1:0],
    output logic [5:0]      aruser[RW_CH-1:0],

    input logic             rready,
    input logic             rvalid,
    input logic             rlast,
    input logic [511:0]     rdata,
    input logic [1:0]       rresp,
    input logic [11:0]      rid,

    input logic             wready[RW_CH-1:0],
    output logic            wvalid[RW_CH-1:0],
    output logic [511:0]    wdata[RW_CH-1:0],
    output logic            wlast[RW_CH-1:0], 
    output logic [(512/8)-1:0] wstrb[RW_CH-1:0], 

    input logic             awready[RW_CH-1:0],
    output logic            awvalid[RW_CH-1:0],
    output logic [11:0]     awid[RW_CH-1:0],
    output logic [5:0]      awuser[RW_CH-1:0],
    output logic [63:0]     awaddr[RW_CH-1:0],
    
    input logic             bvalid,
    input logic [1:0]       bresp,
    input logic             bready,
    input logic [11:0]      bid
);

    enum logic [5:0] {  
        STATE_IDLE,
        STATE_CHECK,
        STATE_FORWARD,
        
        STATE_PRE_PROC, //before read tag complete
        STATE_PRE_PROC_DONE,

        STATE_RD_TAG,
        STATE_RD_TAG_DONE,
        STATE_RD_TAG_DONE_1,
        STATE_WR_TAG,
        STATE_WR_TAG_DONE,
        STATE_RD_SSD, //10
        STATE_RD_SSD_DONE,
        STATE_RD_SSD_RD_HOST,
        STATE_RD_SSD_RD_HOST_DONE,
        STATE_RD_SSD_WR_DEV,
        STATE_RD_SSD_WR_DEV_DONE,
        STATE_WR_SSD_ACK,
        STATE_WR_SSD_ACK_DONE,
        STATE_WR_SSD_RD_DEV,
        STATE_WR_SSD_RD_DEV_DONE,
        STATE_WR_SSD_WR_HOST, //20
        STATE_WR_SSD_WR_HOST_DONE,
        STATE_WR_SSD,
        STATE_WR_SSD_DONE,
        STATE_WR_SSD_RD_HOST,
        STATE_WR_SSD_RD_HOST_DONE,

        STATE_RD_SSD_RL,   //relase the backend SSD
        // STATE_WR_SSD_RL,   //relase the backend SSD
        STATE_PROC_DATA,

        STATE_RESP
    } state[3:0], next_state[3:0],
    mshr_p_state[MSHR_CH-1:0], next_mshr_p_state[MSHR_CH-1:0],
    mshr_t_state[MSHR_CH-1:0], next_mshr_t_state[MSHR_CH-1:0],
    mshr_d_state[MSHR_CH-1:0], next_mshr_d_state[MSHR_CH-1:0],
    mshr_r_state[MSHR_CH-1:0], next_mshr_r_state[MSHR_CH-1:0],
    fe_rq_state, next_fe_rq_state,
    fe_ack_state, next_fe_ack_state,
    fe_rl_state, next_fe_rl_state;

    ed_mc_axi_if_pkg::t_to_mc_axi4_extended p_data_a;
    ed_mc_axi_if_pkg::t_to_mc_axi4_extended p_q_a;
    ed_mc_axi_if_pkg::t_to_mc_axi4_extended p_data_b;
    ed_mc_axi_if_pkg::t_to_mc_axi4_extended p_q_b;
    logic [3:0] p_write_address_a;
    logic [3:0] p_write_address_b;
    logic [3:0] p_read_address_a;
    logic [3:0] p_read_address_b;
    logic p_wrren_a;
    logic p_wrren_b;

    logic [3:0] p_read_address_a_old;

    //--------------------------------
    logic [63:0] addr_reg;
    logic [63:0] hash_reg;
    logic [511:0] tag_reg_full;
    logic [63:0] tag_reg;
    logic valid_match;

    logic [63:0] araddr_reg;
    logic [63:0] awaddr_reg;
    logic [511:0] wdata_reg;
    logic [63:0] wstrb_reg;

    logic [3:0] buf_rd_cnt;
    logic [3:0] buf_rd_rt_cnt;
    logic [3:0] buf_wr_cnt;
    logic [3:0] buf_wr_rt_cnt;
    logic [511:0] buf_reg;

    ed_mc_axi_if_pkg::t_from_nvme_axi4   nvme_to_fe_axi4_reg_wr; //register for write request
    ed_mc_axi_if_pkg::t_from_nvme_axi4   nvme_to_fe_axi4_reg_rd; //register for read request

    ed_mc_axi_if_pkg::t_to_mc_axi4 [MC_CH-1:0] nvme2iafu_to_mc_axi4_ch_0;
    ed_mc_axi_if_pkg::t_from_mc_axi4 [MC_CH-1:0] iafu2nvme_from_mc_axi4_ch_0;

    //--------------------------------
    //1. read tag, then proc data
    logic tag2data_valid;   
    logic tag2data_ready;

    //2. after proc data, check to write tag
    logic data2tag_valid;   
    logic data2tag_ready;

    logic data2fifo_valid;
    logic data2fifo_ready;

    //3. all complte, empty fifo
    logic tag2fifo_valid;
    logic tag2fifo_ready;

    logic data_write_valid; //have write operation, need to check tag update


    logic [1:0] resp_state_cnt; //wait for 4 cycle to check if fifo has new write 

    ed_mc_axi_if_pkg::t_to_mc_axi4_extended p_q_a_reg;
    ed_mc_axi_if_pkg::t_to_mc_axi4_extended p_q_b_reg;

    ed_mc_axi_if_pkg::t_to_mc_axi4 [MC_CH-1:0] nvme2iafu_to_mc_axi4_ch_1;
    ed_mc_axi_if_pkg::t_from_mc_axi4 [MC_CH-1:0] iafu2nvme_from_mc_axi4_ch_1;

    //--------------------------------
    //response fifo
    logic wrreq_rp_w[1:0];
    logic rdreq_rp_w[1:0];
    logic rdempty_rp_w[1:0];
    logic wrfull_rp_w[1:0];
    logic aclr_rp_w [1:0];
    ed_mc_axi_if_pkg::t_from_mc_axi4 rp_wfifo_data [1:0];
    ed_mc_axi_if_pkg::t_from_mc_axi4 rp_wfifo_q [1:0];

    logic wrreq_rp_r[1:0];
    logic rdreq_rp_r[1:0];
    logic rdempty_rp_r[1:0];
    logic wrfull_rp_r[1:0];
    logic aclr_rp_r [1:0];
    ed_mc_axi_if_pkg::t_from_mc_axi4 rp_rfifo_data [1:0];
    ed_mc_axi_if_pkg::t_from_mc_axi4 rp_rfifo_q [1:0];

    logic [51:0] addr_index_reg;
    logic [3:0] resp_w_ptr;
    logic [1:0] w_ch;
    
    //--------------------------------
    logic [1:0] pfifo_awvalid_ch;
    logic [1:0] pfifo_awready_ch;

    //--------------------------------
    ed_mc_axi_if_pkg::t_to_mc_axi4_extended [MC_CH-1:0] iafu2mc_to_nvme_axi4_ch_i;
    ed_mc_axi_if_pkg::t_from_mc_axi4_extended [MC_CH-1:0] mc2iafu_from_nvme_axi4_ch_i;


    //--------------------------------
    logic             arready_ch ;
    logic [63:0]     araddr_ch  ;
    logic            arvalid_ch ;
    logic [11:0]     arid_ch    ;
    logic [5:0]      aruser_ch  ;

    logic             wready_ch  ;
    logic            wvalid_ch  ;
    logic [511:0]    wdata_ch   ;
    logic            wlast_ch   ;
    logic [(512/8)-1:0] wstrb_ch;

    logic             awready_ch ;
    logic            awvalid_ch ;
    logic [11:0]     awid_ch    ;
    logic [5:0]      awuser_ch  ;
    logic [63:0]     awaddr_ch  ;

    //--------------------------------
    logic rd_ssd_cp;    //receive rd_ssd cp signal
    logic wr_ssd_cp;    //receive wr_ssd cp signal
    logic wr_ssd_valid; //has dirty miss, need to wr_ssd


    // //--------------------------------
    // logic [1023:0] pio_mem_buffer;
    // ed_mc_axi_if_pkg::t_to_pio_axi4 to_pio_axi4_ch;
    // ed_mc_axi_if_pkg::t_from_pio_axi4 from_pio_axi4_ch;

    //--------------------------------
    logic pre_proc_valid; //1: tag has been read; 0: tag not read yet;
    logic pre_proc_wrong; //1: tag mismatch, flush pre_read data; 0: tag match, continue operation
    logic pre_proc_done; //1: pre_proc done, 0: pre_proc not done yet
    logic pre_proc_flush; //1: resp fifo has been flushed; 0: has not yet been flushed.
    logic [2:0] pre_proc_issue_cnt; //number of pre_proc issued 
    logic [2:0] pre_proc_resp_cnt;  //number of pre_proc response
    logic [2:0] pre_proc_resp_cnt_r_ch [1:0];
    logic [2:0] pre_proc_resp_cnt_w_ch [1:0];


    //-----------------------------------------------
    assign nvme2iafu_to_mc_axi4[2*i] = nvme2iafu_to_mc_axi4_ch_0;
    assign iafu2nvme_from_mc_axi4_ch_0 = iafu2nvme_from_mc_axi4[2*i];
    assign nvme2iafu_to_mc_axi4[2*i+1] = nvme2iafu_to_mc_axi4_ch_1;
    assign iafu2nvme_from_mc_axi4_ch_1 = iafu2nvme_from_mc_axi4[2*i+1];

    assign pfifo_awvalid_ch = pfifo_awvalid[i];
    assign pfifo_awready_ch = pfifo_awready[i];
    
    assign mc2iafu_from_nvme_axi4_ch[i] = mc2iafu_from_nvme_axi4_ch_i;
    assign iafu2mc_to_nvme_axi4_ch_i = iafu2mc_to_nvme_axi4_ch[i];

    //--------------------------------
    assign arready_ch = arready[i];
    assign araddr[i] = araddr_ch;
    assign arvalid[i] = arvalid_ch;
    assign arid[i] = arid_ch;
    assign aruser[i] = aruser_ch;

    assign wready_ch = wready[i];
    assign wvalid[i] = wvalid_ch;
    assign wdata[i] = wdata_ch;
    assign wlast[i] = wlast_ch;
    assign wstrb[i] = wstrb_ch;

    assign awready_ch = awready[i];
    assign awvalid[i] = awvalid_ch;
    assign awid[i] = awid_ch;
    assign awuser[i] = awuser_ch;
    assign awaddr[i] = awaddr_ch;

    /*---------------------------------
    Dispatch Queue
    -----------------------------------*/
    //write port b not used
    cust_ram4port processor_queue_inst(
        .data_a(p_data_a),
        .write_address_a(p_write_address_a[2:0]),
        .wren_a(p_wrren_a),

        .q_a(p_q_a),
        .q_b(p_q_b),
        .read_address_a(p_read_address_a[2:0]),
        .read_address_b(p_read_address_b[2:0]),

        .clock(axi4_mm_clk)
    );

    always_ff @(posedge axi4_mm_clk) begin
        if (!axi4_mm_rst_n) begin
            mshr_p_state[i] <= STATE_IDLE;
            pfifo_busy[i]  <= 1'b0;
            pfifo_addr[i]  <= '0;
            p_data_a    <= '0;
            p_write_address_a <= '0;
            // pfifo_awready_reg[i] <= 1'b0;
        end
        else begin
            mshr_p_state[i] <= next_mshr_p_state[i];

            unique case(mshr_p_state[i])
                STATE_IDLE: begin
                    p_write_address_a <= '0;
                    if (pfifo_awvalid[i][0]) begin
                        pfifo_busy[i] <= 1'b1;
                        pfifo_addr[i] <= rfifo_q_addr_reg[0];
                        p_data_a <= rfifo_q_reg[0];
                        // pfifo_awready_reg[i] <= 1'b0;
                    end
                    else if (pfifo_awvalid[i][1]) begin
                        pfifo_busy[i] <= 1'b1;
                        pfifo_addr[i] <= rfifo_q_addr_reg[1];
                        p_data_a <= rfifo_q_reg[1];
                        // pfifo_awready_reg[i] <= 1'b1;
                    end
                    else begin
                        pfifo_busy[i] <= 1'b0;
                    end
                end
                STATE_CHECK: begin
                    p_write_address_a <= p_write_address_a + 4'd1;
                end
                STATE_FORWARD: begin
                    if (data2fifo_valid) begin

                    end
                    else if (p_write_address_a[3] == 1'b1) begin //pfifo is full, stop receving request

                    end
                    else begin
                        if (pfifo_awvalid[i][0]) begin
                            if (rfifo_q_addr_reg[0][51:9] == pfifo_addr[i][51:9]) begin
                                p_data_a <= rfifo_q_reg[0];
                                // pfifo_awready_reg[i] <= 1'b0;
                            end
                            else begin

                            end
                        end
                        else if (pfifo_awvalid[i][1]) begin
                            if (rfifo_q_addr_reg[1][51:9] == pfifo_addr[i][51:9]) begin
                                p_data_a <= rfifo_q_reg[1];
                                // pfifo_awready_reg[i] <= 1'b1;
                            end
                            else begin

                            end
                        end
                        else begin

                        end
                    end
                end
                STATE_RESP: begin
                    if (tag2fifo_valid) begin
                        p_write_address_a <= 4'b0;
                        pfifo_busy[i] <= 1'b0;
                    end
                end
                default: begin

                end
            endcase
        end
    end
    /*---------------------------------
    Read/write tag and SSD
    -----------------------------------*/
    always_ff @(posedge axi4_mm_clk) begin
        if (!axi4_mm_rst_n) begin
            mshr_t_state[i] <= STATE_IDLE;
            addr_reg            <= 64'd0;
            hash_reg            <= 64'd0;
            valid_match         <= 1'b0;
            buf_rd_cnt          <= 4'd0;
            buf_rd_rt_cnt       <= 4'd0;       
            buf_wr_cnt          <= 4'd0;   
            buf_wr_rt_cnt       <= 4'd0; 

            tag_reg             <= 64'd0;
            tag_reg_full        <= 512'd0;      
            
            rd_ssd_cp <= 1'b0;
            wr_ssd_cp <= 1'b0;
            wr_ssd_valid <= 1'b0;  
        end
        else begin
            mshr_t_state[i] <= next_mshr_t_state[i];
            
            if (nvme_to_fe_axi4_ch[i].ssd_cp_valid) begin
                if ((nvme_to_fe_axi4_ch[i].ssd_cp_fe_id[11:10] == i[1:0]) && (nvme_to_fe_axi4_ch[i].ssd_cp_fe_id[9] == 1'b0)) begin
                    nvme_to_fe_axi4_reg_rd <= nvme_to_fe_axi4_ch[i];
                    rd_ssd_cp <= 1'b1;
                end
            end

            if (nvme_to_fe_axi4_ch[i].ssd_bf_valid) begin
                if ((nvme_to_fe_axi4_ch[i].ssd_bf_fe_id[11:10] == i[1:0]) && (nvme_to_fe_axi4_ch[i].ssd_bf_fe_id[9] == 1'b1)) begin
                    nvme_to_fe_axi4_reg_wr <= nvme_to_fe_axi4_ch[i];
                end
            end

            if (nvme_to_fe_axi4_ch[i].ssd_cp_valid) begin
                if ((nvme_to_fe_axi4_ch[i].ssd_cp_fe_id[11:10] == i[1:0]) && (nvme_to_fe_axi4_ch[i].ssd_cp_fe_id[9] == 1'b1)) begin
                    nvme_to_fe_axi4_reg_wr <= nvme_to_fe_axi4_ch[i];
                    wr_ssd_cp <= 1'b1;
                end
            end

            unique case(mshr_t_state[i])
                STATE_IDLE: begin
                    buf_rd_cnt      <= 4'd0;
                    buf_rd_rt_cnt   <= 4'd0;       
                    buf_wr_cnt      <= 4'd0;   
                    buf_wr_rt_cnt   <= 4'd0;  
                    
                    rd_ssd_cp <= 1'b0;
                    wr_ssd_cp <= 1'b0;
                    wr_ssd_valid <= 1'b0;
                    
                    pre_proc_valid <= 1'b0;
                    pre_proc_wrong <= 1'b0;

                    //TODO: replace hash with real hash function
                    if (p_write_address_a != 4'b0) begin
                        addr_reg <= pfifo_addr[i];
                        hash_reg <= {40'd0, pfifo_addr[i][32:9]};

                        if (tag_reg[52] == 1'b1) begin //valid bit is 1
                            if (tag_reg[51:9] == pfifo_addr[i][51:9]) begin //addr match
                                valid_match <= 1'b1;
                                pre_proc_wrong <= 1'b0; //tag match, continue operation
                                pre_proc_valid <= 1'b1; //tag has been read
                            end
                        end
                    end
                end
                STATE_RD_TAG: begin
                    
                end
                STATE_RD_TAG_DONE: begin
                    if (iafu2nvme_from_mc_axi4_ch_0[hash_reg[3]].rvalid && nvme2iafu_to_mc_axi4_ch_0[hash_reg[3]].rready) begin
                        if (iafu2nvme_from_mc_axi4_ch_0[hash_reg[3]].rid == {CH_ID, 1'b0, i[0], arid_rd_tag}) begin
                            tag_reg <= iafu2nvme_from_mc_axi4_ch_0[hash_reg[3]].rdata[63+64*hash_reg[2:0]-:64];
                            tag_reg_full <= iafu2nvme_from_mc_axi4_ch_0[hash_reg[3]].rdata;
                        end
                    end
                end
                STATE_RD_TAG_DONE_1: begin
                    pre_proc_valid <= 1'b1; //tag has been read
                    if (tag_reg[52] == 1'b1) begin //valid bit is 1
                        if (tag_reg[51:9] == addr_reg[51:9]) begin //addr match
                            valid_match <= 1'b1;
                            pre_proc_wrong <= 1'b0; //tag match, continue operation
                        end
                        else begin
                            if (tag_reg[53] == 1'b1) begin//dirty bit is 1 but addr not the same
                                wr_ssd_valid <= 1'b1; //need to write back to SSD
                            end
                            else begin  //not dirty
                                
                            end
                            valid_match <= 1'b0;
                            pre_proc_wrong <= 1'b1; //tag mismatch, flush pre_read data
                        end
                    end
                    else begin
                        valid_match <= 1'b0;
                        pre_proc_wrong <= 1'b1; //tag not valid, flush pre_read data
                    end
                end
                STATE_WR_TAG: begin
                    if (data_write_valid == 1'b0) begin
                        tag_reg <= {10'b0, 1'b0, 1'b1, addr_reg[51:9], 9'b0};
                    end
                    else begin
                        tag_reg <= {10'b0, 1'b1, 1'b1, addr_reg[51:9], 9'b0};
                    end
                end
                STATE_WR_TAG_DONE: begin

                end
                STATE_RD_SSD: begin
                
                end
                STATE_RD_SSD_DONE: begin
                    // if (nvme_to_fe_axi4_ch[i].ssd_cp_valid) begin
                    //     if ((nvme_to_fe_axi4_ch[i].ssd_cp_fe_id[11:10] == i[1:0]) && (nvme_to_fe_axi4_ch[i].ssd_cp_fe_id[9] == 1'b0)) begin
                    //         nvme_to_fe_axi4_reg_rd <= nvme_to_fe_axi4_ch[i];
                    //     end
                    // end
                end
                STATE_RD_SSD_RD_HOST: begin
                    if (arvalid[i] && arready[i]) begin
                        buf_rd_cnt <= buf_rd_cnt + 4'd1;
                    end
                end
                STATE_RD_SSD_RD_HOST_DONE: begin
                    if (rvalid && rready) begin
                        if (rid == {CH_ID, i[0], arid_rd_buf_cafu}) begin
                            buf_reg <= rdata;
                            buf_rd_rt_cnt <= buf_rd_rt_cnt + 4'd1;
                        end
                    end
                end
                STATE_RD_SSD_WR_DEV: begin
                    if (nvme2iafu_to_mc_axi4_ch_0[buf_wr_cnt[0]].awvalid && iafu2nvme_from_mc_axi4_ch_0[buf_wr_cnt[0]].awready) begin
                        buf_wr_cnt <= buf_wr_cnt + 4'd1;
                    end
                end
                STATE_RD_SSD_WR_DEV_DONE: begin
                    if (iafu2nvme_from_mc_axi4_ch_0[buf_wr_rt_cnt[0]].bvalid && nvme2iafu_to_mc_axi4_ch_0[buf_wr_rt_cnt[0]].bready) begin
                        if (iafu2nvme_from_mc_axi4_ch_0[buf_wr_rt_cnt[0]].bid == {CH_ID, 1'b0, i[0], awid_wr_buf_mc}) begin
                            buf_wr_rt_cnt <= buf_wr_rt_cnt + 4'd1;
                        end
                    end
                end
                STATE_WR_SSD_ACK: begin

                end
                STATE_WR_SSD_ACK_DONE: begin
                    // if (nvme_to_fe_axi4_ch[i].ssd_bf_valid) begin
                    //     if ((nvme_to_fe_axi4_ch[i].ssd_bf_fe_id[11:10] == i[1:0]) && (nvme_to_fe_axi4_ch[i].ssd_bf_fe_id[9] == 1'b1)) begin
                    //         nvme_to_fe_axi4_reg_wr <= nvme_to_fe_axi4_ch[i];
                    //     end
                    // end
                end
                STATE_WR_SSD_RD_DEV: begin
                    if (nvme2iafu_to_mc_axi4_ch_0[buf_rd_cnt[0]].arvalid && iafu2nvme_from_mc_axi4_ch_0[buf_rd_cnt[0]].arready) begin
                        buf_rd_cnt <= buf_rd_cnt + 4'd1;
                    end
                end
                STATE_WR_SSD_RD_DEV_DONE: begin
                    if (iafu2nvme_from_mc_axi4_ch_0[buf_rd_rt_cnt[0]].rvalid && nvme2iafu_to_mc_axi4_ch_0[buf_rd_rt_cnt[0]].rready) begin
                        if (iafu2nvme_from_mc_axi4_ch_0[buf_rd_rt_cnt[0]].rid == {CH_ID, 1'b0, i[0], arid_rd_buf_mc}) begin
                            buf_rd_rt_cnt <= buf_rd_rt_cnt + 4'd1;
                            buf_reg <=  iafu2nvme_from_mc_axi4_ch_0[buf_rd_rt_cnt[0]].rdata;
                        end
                    end
                end
                STATE_WR_SSD_WR_HOST: begin
                    if (awvalid[i] && awready[i]) begin
                        buf_wr_cnt <= buf_wr_cnt + 4'd1;
                    end
                    
                    if (bvalid && bready) begin
                        if (bid == {CH_ID, i[0], awid_wr_buf_cafu}) begin
                            buf_wr_rt_cnt <= buf_wr_rt_cnt + 4'd1;
                        end
                    end
                end
                STATE_WR_SSD_WR_HOST_DONE: begin
                    if (bvalid && bready) begin
                        if (bid == {CH_ID, i[0], awid_wr_buf_cafu}) begin
                            buf_wr_rt_cnt <= buf_wr_rt_cnt + 4'd1;
                        end
                    end
                end
                STATE_WR_SSD: begin
                    buf_rd_cnt      <= 4'd0;
                    buf_rd_rt_cnt   <= 4'd0;       
                    buf_wr_cnt      <= 4'd0;   
                    buf_wr_rt_cnt   <= 4'd0;  
                end
                STATE_WR_SSD_DONE: begin
                    // if (nvme_to_fe_axi4_ch[i].ssd_cp_valid) begin
                    //     if ((nvme_to_fe_axi4_ch[i].ssd_cp_fe_id[11:10] == i[1:0]) && (nvme_to_fe_axi4_ch[i].ssd_cp_fe_id[9] == 1'b1)) begin
                    //         nvme_to_fe_axi4_reg_wr <= nvme_to_fe_axi4_ch[i];
                    //     end
                    // end
                end

                default: begin

                end
            endcase
        end
    end

    /*---------------------------------
    Read/write data
    -----------------------------------*/
    always_ff @(posedge axi4_mm_clk) begin
        if (!axi4_mm_rst_n) begin
            mshr_d_state[i] <= STATE_IDLE;
            p_read_address_a <= 4'd0;
            data_write_valid <= 1'b0;
            resp_state_cnt <= 2'd0;
        end
        else begin
            mshr_d_state[i] <= next_mshr_d_state[i];

            unique case(mshr_d_state[i])
                STATE_IDLE: begin
                    pre_proc_done <= 1'b0;
                    pre_proc_issue_cnt <= 3'b0;
                    resp_state_cnt <= 2'd0;
                    p_read_address_a <= 4'd0;
                end
                STATE_PRE_PROC: begin

                end
                STATE_PRE_PROC_DONE: begin
                    if (tag2data_valid && tag2data_ready) begin
                        pre_proc_done <= 1'b1; //pre_proc done, can proc data
                        data_write_valid <= 1'b0;
                        if (pre_proc_valid && pre_proc_wrong) begin //if the tag mismatch
                            p_read_address_a <= 4'd0; //reset read address
                        end
                    end
                end
                STATE_PROC_DATA: begin
                    p_q_a_reg <= p_q_a;
                    p_read_address_a <= p_read_address_a + 4'd1;
                    p_read_address_a_old <= p_read_address_a;
                end
                STATE_FORWARD: begin
                    if (p_q_a_reg.awvalid) begin
                        if (pre_proc_done) begin
                            data_write_valid <= 1'b1;
                        end
                    end
                    
                    if (!pre_proc_done) begin
                        if (p_q_a_reg.awvalid) begin
                            if (pre_proc_valid) begin
                                p_read_address_a <= p_read_address_a_old; //write request need to be reverted
                            end
                        end

                        if (nvme2iafu_to_mc_axi4_ch_1[p_q_a_reg.araddr[6]].arvalid && iafu2nvme_from_mc_axi4_ch_1[p_q_a_reg.araddr[6]].arready) begin
                            pre_proc_issue_cnt <= pre_proc_issue_cnt + 3'd1;
                        end
                    end
                end
                STATE_CHECK: begin
                    resp_state_cnt <= 2'd0;
                end
                STATE_RESP: begin
                    resp_state_cnt <= resp_state_cnt + 4'd1;
                    if (resp_state_cnt == 2'd3) begin
                        pre_proc_done <= 1'b0;
                    end
                end
                default: begin

                end
            endcase
        end
    end

    /*---------------------------------
    Receive response
    -----------------------------------*/
    for (j=0; j<2; j++) begin : resp_ch
        nvme_from_fifo nvme_from_b_fifo_inst(
            .data(rp_wfifo_data[j]),    //  fifo_input.datain
            .wrreq(wrreq_rp_w[j]),   //            .wrreq
            .rdreq(rdreq_rp_w[j]),   //            .rdreq
            .wrclk(axi4_mm_clk),   //            .wrclk
            .rdclk(axi4_mm_clk),   //            .rdclk
            .aclr(aclr_rp_w[j]),
            .q(rp_wfifo_q[j]),       // fifo_output.dataout
            .rdempty(rdempty_rp_w[j]), //            .rdempty
            .wrfull(wrfull_rp_w[j])   //            .wrfull
        );

        nvme_from_fifo nvme_from_r_fifo_inst(
            .data(rp_rfifo_data[j]),    //  fifo_input.datain
            .wrreq(wrreq_rp_r[j]),   //            .wrreq
            .rdreq(rdreq_rp_r[j]),   //            .rdreq
            .wrclk(axi4_mm_clk),   //            .wrclk
            .rdclk(axi4_mm_clk),   //            .rdclk
            .aclr(aclr_rp_r[j]), 
            .q(rp_rfifo_q[j]),       // fifo_output.dataout
            .rdempty(rdempty_rp_r[j]), //            .rdempty
            .wrfull(wrfull_rp_r[j])   //            .wrfull
        );

        always_comb begin
            wrreq_rp_w[j] = 1'b0;
            wrreq_rp_r[j] = 1'b0;

            //assume only bvalid or rvalid can be true at the same time
            if (iafu2nvme_from_mc_axi4_ch_1[j].bvalid && nvme2iafu_to_mc_axi4_ch_1[j].bready) begin
                if (iafu2nvme_from_mc_axi4_ch_1[j].bid[7:3] == {CH_ID[2:0], 1'b1, i[0]}) begin
                    wrreq_rp_w[j] = 1'b1;
                end
            end

            if (iafu2nvme_from_mc_axi4_ch_1[j].rvalid && nvme2iafu_to_mc_axi4_ch_1[j].rready) begin
                if (iafu2nvme_from_mc_axi4_ch_1[j].rid[7:3] == {CH_ID[2:0], 1'b1, i[0]}) begin
                    wrreq_rp_r[j] = 1'b1;
                end
            end
        end

        always_ff @(posedge axi4_mm_clk) begin
            if ((!axi4_mm_rst_n) || (data2tag_valid == 1'b1)) begin
                pre_proc_resp_cnt_r_ch[j] <= 3'd0;
                pre_proc_resp_cnt_w_ch[j] <= 3'd0;
            end
            else begin
                if (iafu2nvme_from_mc_axi4_ch_1[j].bvalid && nvme2iafu_to_mc_axi4_ch_1[j].bready) begin
                    if (iafu2nvme_from_mc_axi4_ch_1[j].bid[7:3] == {CH_ID[2:0], 1'b1, i[0]}) begin
                        if (!pre_proc_done) begin
                            pre_proc_resp_cnt_w_ch[j] <= pre_proc_resp_cnt_w_ch[j] + 3'd1;
                        end
                    end
                end

                if (iafu2nvme_from_mc_axi4_ch_1[j].rvalid && nvme2iafu_to_mc_axi4_ch_1[j].rready) begin
                    if (iafu2nvme_from_mc_axi4_ch_1[j].rid[7:3] == {CH_ID[2:0], 1'b1, i[0]}) begin
                        if (!pre_proc_done) begin
                            pre_proc_resp_cnt_r_ch[j] <= pre_proc_resp_cnt_r_ch[j] + 3'd1;
                        end
                    end
                end
            end 
        end
    end

    /*---------------------------------
    Response state machine
    -----------------------------------*/
    always_ff @(posedge axi4_mm_clk) begin
        if (!axi4_mm_rst_n) begin
            mshr_r_state[i] <= STATE_IDLE;
            w_ch <= 2'b0;
            resp_w_ptr <= 4'd0; 
            pre_proc_resp_cnt <= 4'd0;
            pre_proc_flush <= 1'b0;
        end
        else begin
            mshr_r_state[i] <= next_mshr_r_state[i];

            unique case(mshr_r_state[i])
                STATE_IDLE: begin
                    if (data2tag_valid == 1'b1) begin
                        resp_w_ptr <= 4'd0;
                        pre_proc_flush <= 1'b0;
                    end
                    
                    pre_proc_resp_cnt <= pre_proc_resp_cnt_r_ch[0] + pre_proc_resp_cnt_r_ch[1] + pre_proc_resp_cnt_w_ch[0] + pre_proc_resp_cnt_w_ch[1];

                    if (!pre_proc_flush && pre_proc_done) begin
                        pre_proc_flush <= 1'b1;
                    end

                    if (!rdempty_rp_w[0]) begin
                        w_ch <= 2'b00;
                    end
                    else if (!rdempty_rp_w[1]) begin
                        w_ch <= 2'b01;
                    end
                    else if (!rdempty_rp_r[0]) begin
                        w_ch <= 2'b10;
                    end
                    else if (!rdempty_rp_r[1]) begin
                        w_ch <= 2'b11;
                    end
                end
                STATE_CHECK: begin

                end
                STATE_PROC_DATA: begin
                    p_q_b_reg <= p_q_b;
                end
                STATE_RESP: begin
                    if (next_mshr_r_state[i] == STATE_IDLE) begin
                        resp_w_ptr <= resp_w_ptr + 4'd1;
                    end
                end
                default: begin

                end
            endcase
        end
    end

    /*---------------------------------
    Combinational logic 
    -----------------------------------*/
    always_comb begin
    //--------------------------------- pfifo input         channel 2
        pfifo_awready[i][0] = 1'b0;
        pfifo_awready[i][1] = 1'b0;
        p_wrren_a = 1'b0;
        p_wrren_b = 1'b0;   //port B not used
        data2fifo_ready = 1'b0;
        tag2fifo_ready = 1'b0;

        unique case(mshr_p_state[i])
            STATE_IDLE: begin
                if (pfifo_awvalid[i][0]) begin
                    pfifo_awready[i][0] = 1'b1;
                end
                else if (pfifo_awvalid[i][1]) begin
                    pfifo_awready[i][1] = 1'b1;
                end
                else begin

                end
            end

            STATE_CHECK: begin
                // unique case(pfifo_awready_reg[i])
                //     1'b0: pfifo_awready[i][0] = 1'b1;
                //     1'b1: pfifo_awready[i][1] = 1'b1;
                // endcase
                p_wrren_a = 1'b1;
            end

            STATE_FORWARD: begin //TODO: need signal to go to response state
                
            end

            STATE_RESP: begin
                tag2fifo_ready = 1'b1;
            end

            default: begin

            end
        endcase

    //--------------------------------- read tag            channel 3
        //default
        arvalid_ch    = 1'b0;
        araddr_ch     = 64'b0;
        arid_ch       = 12'b0;
        aruser_ch     = 6'b0;

        awvalid_ch    = 1'b0;
        awaddr_ch     = 64'b0;
        awid_ch       = 12'b0;
        awuser_ch     = 6'b0;

        wvalid_ch     = 1'b0;
        wdata_ch      = 512'b0;
        wstrb_ch      = 64'b0;
        wlast_ch      = 1'b0;


        for (int k=0; k<2; k++) begin
            nvme2iafu_to_mc_axi4_ch_0[k].bready  = 1'b1;
            nvme2iafu_to_mc_axi4_ch_0[k].rready  = 1'b1;
        
            nvme2iafu_to_mc_axi4_ch_0[k].awid    = 8'd0;
            nvme2iafu_to_mc_axi4_ch_0[k].awaddr  = 52'd0;
            nvme2iafu_to_mc_axi4_ch_0[k].awlen   = 10'd0;
            nvme2iafu_to_mc_axi4_ch_0[k].awsize  = cafu_common_pkg::esize_CAFU_512;
            nvme2iafu_to_mc_axi4_ch_0[k].awburst = cafu_common_pkg::eburst_CAFU_FIXED;
            nvme2iafu_to_mc_axi4_ch_0[k].awprot  = cafu_common_pkg::eprot_CAFU_UNPRIV_SECURE_DATA;
            nvme2iafu_to_mc_axi4_ch_0[k].awqos   = cafu_common_pkg::eqos_CAFU_BEST_EFFORT;
            nvme2iafu_to_mc_axi4_ch_0[k].awvalid = 1'b0;
            nvme2iafu_to_mc_axi4_ch_0[k].awcache = cafu_common_pkg::ecache_aw_CAFU_DEVICE_NON_BUFFERABLE;
            nvme2iafu_to_mc_axi4_ch_0[k].awlock  = cafu_common_pkg::elock_CAFU_NORMAL;
            nvme2iafu_to_mc_axi4_ch_0[k].awregion    = 4'b0000;
            nvme2iafu_to_mc_axi4_ch_0[k].awuser  = 1'b0;
            nvme2iafu_to_mc_axi4_ch_0[k].wdata   = 512'd0;
            nvme2iafu_to_mc_axi4_ch_0[k].wstrb   = 64'd0;
            nvme2iafu_to_mc_axi4_ch_0[k].wlast   = 1'b0;
            nvme2iafu_to_mc_axi4_ch_0[k].wvalid  = 1'b0;
            nvme2iafu_to_mc_axi4_ch_0[k].wuser   = 1'b0;
        
            nvme2iafu_to_mc_axi4_ch_0[k].arid    = 8'd0;
            nvme2iafu_to_mc_axi4_ch_0[k].araddr  = 64'd0;
            nvme2iafu_to_mc_axi4_ch_0[k].arlen   = 10'd0;
            nvme2iafu_to_mc_axi4_ch_0[k].arsize  = cafu_common_pkg::esize_CAFU_512; 
            nvme2iafu_to_mc_axi4_ch_0[k].arburst = cafu_common_pkg::eburst_CAFU_FIXED;
            nvme2iafu_to_mc_axi4_ch_0[k].arprot  = cafu_common_pkg::eprot_CAFU_UNPRIV_SECURE_DATA;
            nvme2iafu_to_mc_axi4_ch_0[k].arqos   = cafu_common_pkg::eqos_CAFU_BEST_EFFORT;
            nvme2iafu_to_mc_axi4_ch_0[k].arvalid = 1'b0;
            nvme2iafu_to_mc_axi4_ch_0[k].arcache = cafu_common_pkg::ecache_ar_CAFU_DEVICE_NON_BUFFERABLE;
            nvme2iafu_to_mc_axi4_ch_0[k].arlock  = cafu_common_pkg::elock_CAFU_NORMAL;
            nvme2iafu_to_mc_axi4_ch_0[k].arregion    =   4'b0000;
            nvme2iafu_to_mc_axi4_ch_0[k].aruser  = 1'b0;
        end

        fe_to_nvme_axi4_ch[i].ssd_rq_valid = 1'b0;
        fe_to_nvme_axi4_ch[i].ssd_rq_type = 1'b0;   //0 is read, 1 is write
        fe_to_nvme_axi4_ch[i].ssd_rq_addr = 64'd0;
        fe_to_nvme_axi4_ch[i].ssd_rq_hash = 64'd0;
        fe_to_nvme_axi4_ch[i].ssd_rq_fe_id  = 12'd0;
        fe_to_nvme_axi4_ch[i].ssd_cp_ready = 1'b0;
        fe_to_nvme_axi4_ch[i].ssd_bf_ready = 1'b0;
        fe_to_nvme_axi4_ch[i].ssd_ack_valid = 1'b0;
        fe_to_nvme_axi4_ch[i].ssd_ack_be_id = 12'd0;
        fe_to_nvme_axi4_ch[i].ssd_rl_valid = 1'b0;
        fe_to_nvme_axi4_ch[i].ssd_rl_be_id = 12'd0;

        tag2fifo_valid = 1'b0;
        tag2data_valid = 1'b0;
        data2tag_ready = 1'b0;

        unique case(mshr_t_state[i])
            STATE_IDLE: begin
                
            end
            STATE_RD_TAG: begin
                nvme2iafu_to_mc_axi4_ch_0[hash_reg[3]].arid    = {CH_ID, 1'b0, i[0], arid_rd_tag};
                nvme2iafu_to_mc_axi4_ch_0[hash_reg[3]].araddr  = cxl_tag_addr + {hash_reg[57:3], 3'd0, 3'd0};
                nvme2iafu_to_mc_axi4_ch_0[hash_reg[3]].arvalid = 1'b1;
            end
            STATE_RD_TAG_DONE: begin
                
            end
            STATE_WR_TAG: begin
                nvme2iafu_to_mc_axi4_ch_0[hash_reg[3]].awvalid = 1'b1;
                nvme2iafu_to_mc_axi4_ch_0[hash_reg[3]].awaddr = cxl_tag_addr + {hash_reg[57:3], 3'd0, 3'd0}; //address must be 64B aligned
                nvme2iafu_to_mc_axi4_ch_0[hash_reg[3]].awid = {CH_ID, 1'b0, i[0], awid_wr_tag};

                if (data_write_valid == 1'b0) begin //read request
                    unique case (hash_reg[2:0]) 
                        3'b000: begin
                            nvme2iafu_to_mc_axi4_ch_0[hash_reg[3]].wdata = {tag_reg_full[511:64], 10'b0, 1'b0, 1'b1, addr_reg[51:9], 9'b0}; 
                            nvme2iafu_to_mc_axi4_ch_0[hash_reg[3]].wstrb = 64'h00000000000000ff;      //only need to write 8B
                        end
                        3'b001: begin
                            nvme2iafu_to_mc_axi4_ch_0[hash_reg[3]].wdata = {tag_reg_full[511:128], 10'b0, 1'b0, 1'b1, addr_reg[51:9], 9'b0, tag_reg_full[63:0]}; 
                            nvme2iafu_to_mc_axi4_ch_0[hash_reg[3]].wstrb = 64'h000000000000ff00;      //only need to write 8B
                        end
                        3'b010: begin
                            nvme2iafu_to_mc_axi4_ch_0[hash_reg[3]].wdata = {tag_reg_full[511:192], 10'b0, 1'b0, 1'b1, addr_reg[51:9], 9'b0, tag_reg_full[127:0]}; 
                            nvme2iafu_to_mc_axi4_ch_0[hash_reg[3]].wstrb = 64'h0000000000ff0000;      //only need to write 8B
                        end
                        3'b011: begin
                            nvme2iafu_to_mc_axi4_ch_0[hash_reg[3]].wdata = {tag_reg_full[511:256], 10'b0, 1'b0, 1'b1, addr_reg[51:9], 9'b0, tag_reg_full[191:0]}; 
                            nvme2iafu_to_mc_axi4_ch_0[hash_reg[3]].wstrb = 64'h00000000ff000000;    //only need to write 8B
                        end
                        3'b100: begin
                            nvme2iafu_to_mc_axi4_ch_0[hash_reg[3]].wdata = {tag_reg_full[511:320], 10'b0, 1'b0, 1'b1, addr_reg[51:9], 9'b0, tag_reg_full[255:0]}; 
                            nvme2iafu_to_mc_axi4_ch_0[hash_reg[3]].wstrb = 64'h000000ff00000000;    //only need to write 8B
                        end
                        3'b101: begin
                            nvme2iafu_to_mc_axi4_ch_0[hash_reg[3]].wdata = {tag_reg_full[511:384], 10'b0, 1'b0, 1'b1, addr_reg[51:9], 9'b0, tag_reg_full[319:0]}; 
                            nvme2iafu_to_mc_axi4_ch_0[hash_reg[3]].wstrb = 64'h0000ff0000000000;    //only need to write 8B
                        end
                        3'b110: begin
                            nvme2iafu_to_mc_axi4_ch_0[hash_reg[3]].wdata = {tag_reg_full[511:448], 10'b0, 1'b0, 1'b1, addr_reg[51:9], 9'b0, tag_reg_full[383:0]}; 
                            nvme2iafu_to_mc_axi4_ch_0[hash_reg[3]].wstrb = 64'h00ff000000000000;    //only need to write 8B
                        end
                        3'b111: begin
                            nvme2iafu_to_mc_axi4_ch_0[hash_reg[3]].wdata = {10'b0, 1'b0, 1'b1, addr_reg[51:9], 9'b0, tag_reg_full[447:0]}; 
                            nvme2iafu_to_mc_axi4_ch_0[hash_reg[3]].wstrb = 64'hff00000000000000;    //only need to write 8B
                        end
                    endcase
                end
                else begin  //write request
                    unique case (hash_reg[2:0]) 
                        3'b000: begin
                            nvme2iafu_to_mc_axi4_ch_0[hash_reg[3]].wdata = {tag_reg_full[511:64], 10'b0, 1'b1, 1'b1, addr_reg[51:9], 9'b0}; 
                            nvme2iafu_to_mc_axi4_ch_0[hash_reg[3]].wstrb = 64'h00000000000000ff;      //only need to write 8B
                        end
                        3'b001: begin
                            nvme2iafu_to_mc_axi4_ch_0[hash_reg[3]].wdata = {tag_reg_full[511:128], 10'b0, 1'b1, 1'b1, addr_reg[51:9], 9'b0, tag_reg_full[63:0]}; 
                            nvme2iafu_to_mc_axi4_ch_0[hash_reg[3]].wstrb = 64'h000000000000ff00;      //only need to write 8B
                        end
                        3'b010: begin
                            nvme2iafu_to_mc_axi4_ch_0[hash_reg[3]].wdata = {tag_reg_full[511:192], 10'b0, 1'b1, 1'b1, addr_reg[51:9], 9'b0, tag_reg_full[127:0]}; 
                            nvme2iafu_to_mc_axi4_ch_0[hash_reg[3]].wstrb = 64'h0000000000ff0000;      //only need to write 8B
                        end
                        3'b011: begin
                            nvme2iafu_to_mc_axi4_ch_0[hash_reg[3]].wdata = {tag_reg_full[511:256], 10'b0, 1'b1, 1'b1, addr_reg[51:9], 9'b0, tag_reg_full[191:0]}; 
                            nvme2iafu_to_mc_axi4_ch_0[hash_reg[3]].wstrb = 64'h00000000ff000000;    //only need to write 8B
                        end
                        3'b100: begin
                            nvme2iafu_to_mc_axi4_ch_0[hash_reg[3]].wdata = {tag_reg_full[511:320], 10'b0, 1'b1, 1'b1, addr_reg[51:9], 9'b0, tag_reg_full[255:0]}; 
                            nvme2iafu_to_mc_axi4_ch_0[hash_reg[3]].wstrb = 64'h000000ff00000000;    //only need to write 8B
                        end
                        3'b101: begin
                            nvme2iafu_to_mc_axi4_ch_0[hash_reg[3]].wdata = {tag_reg_full[511:384], 10'b0, 1'b1, 1'b1, addr_reg[51:9], 9'b0, tag_reg_full[319:0]}; 
                            nvme2iafu_to_mc_axi4_ch_0[hash_reg[3]].wstrb = 64'h0000ff0000000000;    //only need to write 8B
                        end
                        3'b110: begin
                            nvme2iafu_to_mc_axi4_ch_0[hash_reg[3]].wdata = {tag_reg_full[511:448], 10'b0, 1'b1, 1'b1, addr_reg[51:9], 9'b0, tag_reg_full[383:0]}; 
                            nvme2iafu_to_mc_axi4_ch_0[hash_reg[3]].wstrb = 64'h00ff000000000000;    //only need to write 8B
                        end
                        3'b111: begin
                            nvme2iafu_to_mc_axi4_ch_0[hash_reg[3]].wdata = {10'b0, 1'b1, 1'b1, addr_reg[51:9], 9'b0, tag_reg_full[447:0]}; 
                            nvme2iafu_to_mc_axi4_ch_0[hash_reg[3]].wstrb = 64'hff00000000000000;    //only need to write 8B
                        end
                    endcase
                end
                nvme2iafu_to_mc_axi4_ch_0[hash_reg[3]].wvalid = 1'b1;
                nvme2iafu_to_mc_axi4_ch_0[hash_reg[3]].wlast = 1'b1;
            end
            STATE_WR_TAG_DONE: begin

            end
            STATE_RD_SSD: begin
                fe_to_nvme_axi4_ch[i].ssd_rq_valid = 1'b1;
                fe_to_nvme_axi4_ch[i].ssd_rq_type = 1'b0;
                fe_to_nvme_axi4_ch[i].ssd_rq_addr = addr_reg;
                fe_to_nvme_axi4_ch[i].ssd_rq_hash = hash_reg;
                fe_to_nvme_axi4_ch[i].ssd_rq_fe_id   = {i[1:0], 1'b0, 6'd0, CH_ID[2:0]}; //[11:10] mshr_id, [9]: 0 read, 1 write, [2:0] channel id
            end
            STATE_RD_SSD_DONE: begin
                fe_to_nvme_axi4_ch[i].ssd_cp_ready = 1'b1;
            end
            STATE_RD_SSD_RD_HOST: begin
                if (buf_rd_cnt != 4'd8) begin
                    arvalid_ch = 1'b1;
                end
                else begin
                    arvalid_ch = 1'b0;
                end

                araddr_ch   = nvme_to_fe_axi4_reg_rd.ssd_cp_addr + {buf_rd_cnt[3:0], 6'd0};
                aruser_ch   = 6'b000000;  //d2h, nc read
                arid_ch     = {CH_ID, i[0], arid_rd_buf_cafu};
            end
            STATE_RD_SSD_RD_HOST_DONE: begin
                
            end
            STATE_RD_SSD_WR_DEV: begin
                if (buf_wr_cnt != 4'd8) begin
                    nvme2iafu_to_mc_axi4_ch_0[buf_wr_cnt[0]].awvalid = 1'b1;
                    nvme2iafu_to_mc_axi4_ch_0[buf_wr_cnt[0]].wvalid = 1'b1;
                end
                else begin
                    nvme2iafu_to_mc_axi4_ch_0[buf_wr_cnt[0]].awvalid = 1'b0;
                    nvme2iafu_to_mc_axi4_ch_0[buf_wr_cnt[0]].wvalid = 1'b0;
                end

                nvme2iafu_to_mc_axi4_ch_0[buf_wr_cnt[0]].awaddr = cxl_data_addr+ {hash_reg[54:0], buf_wr_cnt[2:0], 6'd0};
                nvme2iafu_to_mc_axi4_ch_0[buf_wr_cnt[0]].awid = {CH_ID, 1'b0, i[0], awid_wr_buf_mc};

                nvme2iafu_to_mc_axi4_ch_0[buf_wr_cnt[0]].wdata = buf_reg;
                nvme2iafu_to_mc_axi4_ch_0[buf_wr_cnt[0]].wstrb = 64'hffffffffffffffff;
                nvme2iafu_to_mc_axi4_ch_0[buf_wr_cnt[0]].wlast = 1'b1;
            end
            STATE_RD_SSD_WR_DEV_DONE: begin
                
            end
            STATE_WR_SSD_ACK: begin
                fe_to_nvme_axi4_ch[i].ssd_rq_valid = 1'b1;
                fe_to_nvme_axi4_ch[i].ssd_rq_type = 1'b1;
                fe_to_nvme_axi4_ch[i].ssd_rq_addr = tag_reg;
                fe_to_nvme_axi4_ch[i].ssd_rq_hash = hash_reg;
                fe_to_nvme_axi4_ch[i].ssd_rq_fe_id   = {i[1:0], 1'b1, 6'd0, CH_ID[2:0]}; // [11:10] mshr_id, [9]: 0 read, 1 write, [2:0] channel id
            end
            STATE_WR_SSD_ACK_DONE: begin
                fe_to_nvme_axi4_ch[i].ssd_bf_ready = 1'b1;
            end
            STATE_WR_SSD_RD_DEV: begin
                if (buf_rd_cnt != 4'd8) begin
                    nvme2iafu_to_mc_axi4_ch_0[buf_rd_cnt[0]].arvalid = 1'b1;
                end
                else begin
                    nvme2iafu_to_mc_axi4_ch_0[buf_rd_cnt[0]].arvalid = 1'b0;
                end
                
                nvme2iafu_to_mc_axi4_ch_0[buf_rd_cnt[0]].arid = {CH_ID, 1'b0, i[0], arid_rd_buf_mc};
                nvme2iafu_to_mc_axi4_ch_0[buf_rd_cnt[0]].araddr = cxl_data_addr+ {hash_reg[54:0], buf_rd_cnt[2:0], 6'd0};
            end
            STATE_WR_SSD_RD_DEV_DONE: begin
            
            end
            STATE_WR_SSD_WR_HOST: begin
                if (buf_wr_cnt != 4'd8) begin
                    awvalid_ch = 1'b1;
                    wvalid_ch = 1'b1;
                end
                else begin
                    awvalid_ch = 1'b0;
                    wvalid_ch = 1'b0;
                end

                awaddr_ch   = nvme_to_fe_axi4_reg_wr.ssd_bf_addr + {buf_wr_cnt[3:0], 6'd0};
                awid_ch     = {CH_ID, i[0], awid_wr_buf_cafu};
                awuser_ch   = 6'b000000; //d2h, nc write

                wdata_ch    = buf_reg;
                wstrb_ch    = 64'hffffffffffffffff;
                wlast_ch    = 1'b1;
            end
            STATE_WR_SSD_WR_HOST_DONE: begin
            
            end
            STATE_WR_SSD: begin
                fe_to_nvme_axi4_ch[i].ssd_ack_valid = 1'b1;
                fe_to_nvme_axi4_ch[i].ssd_ack_be_id = nvme_to_fe_axi4_reg_wr.ssd_bf_be_id;
            end
            STATE_WR_SSD_DONE: begin
                fe_to_nvme_axi4_ch[i].ssd_cp_ready = 1'b1;
            end
            STATE_WR_SSD_RD_HOST: begin
                arvalid_ch  = 1'b1;
                araddr_ch   = nvme_to_fe_axi4_reg_wr.ssd_bf_addr + {4'b0111, 6'd0};
                aruser_ch   = 6'b000000;  //d2h, nc read
                arid_ch     = {CH_ID, i[0], arid_rd_buf_cafu};
            end
            STATE_WR_SSD_RD_HOST_DONE: begin

            end
            STATE_PROC_DATA: begin
                tag2data_valid = 1'b1;
            end
            STATE_CHECK: begin //check if need to write tag
                data2tag_ready = 1'b1;
            end
            STATE_RESP: begin
                tag2fifo_valid = 1'b1;
            end
            STATE_RD_SSD_RL: begin
                fe_to_nvme_axi4_ch[i].ssd_rl_valid = 1'b1;
                fe_to_nvme_axi4_ch[i].ssd_rl_be_id = nvme_to_fe_axi4_reg_rd.ssd_cp_be_id;
            end
            // STATE_WR_SSD_RL: begin
            //     fe_to_nvme_axi4_ch[i].ssd_rl_valid = 1'b1;
            //     fe_to_nvme_axi4_ch[i].ssd_rl_be_id = nvme_to_fe_axi4_reg_wr.ssd_cp_be_id;
            // end
            default: ;
        endcase

    //--------------------------------- read/write data     channel 4
        data2fifo_valid = 1'b0;
        data2tag_valid = 1'b0;
        tag2data_ready = 1'b0;

        for (int k=0; k<2; k++) begin
            nvme2iafu_to_mc_axi4_ch_1[k].bready  = 1'b1;
            nvme2iafu_to_mc_axi4_ch_1[k].rready  = 1'b1;
            
            nvme2iafu_to_mc_axi4_ch_1[k].awid    = 8'd0;
            nvme2iafu_to_mc_axi4_ch_1[k].awaddr  = 52'd0;
            nvme2iafu_to_mc_axi4_ch_1[k].awlen   = 10'd0;
            nvme2iafu_to_mc_axi4_ch_1[k].awsize  = cafu_common_pkg::esize_CAFU_512;
            nvme2iafu_to_mc_axi4_ch_1[k].awburst = cafu_common_pkg::eburst_CAFU_FIXED;
            nvme2iafu_to_mc_axi4_ch_1[k].awprot  = cafu_common_pkg::eprot_CAFU_UNPRIV_SECURE_DATA;
            nvme2iafu_to_mc_axi4_ch_1[k].awqos   = cafu_common_pkg::eqos_CAFU_BEST_EFFORT;
            nvme2iafu_to_mc_axi4_ch_1[k].awvalid = 1'b0;
            nvme2iafu_to_mc_axi4_ch_1[k].awcache = cafu_common_pkg::ecache_aw_CAFU_DEVICE_NON_BUFFERABLE;
            nvme2iafu_to_mc_axi4_ch_1[k].awlock  = cafu_common_pkg::elock_CAFU_NORMAL;
            nvme2iafu_to_mc_axi4_ch_1[k].awregion    = 4'b0000;
            nvme2iafu_to_mc_axi4_ch_1[k].awuser  = 1'b0;

            nvme2iafu_to_mc_axi4_ch_1[k].wdata   = 512'd0;
            nvme2iafu_to_mc_axi4_ch_1[k].wstrb   = 64'd0;
            nvme2iafu_to_mc_axi4_ch_1[k].wlast   = 1'b0;
            nvme2iafu_to_mc_axi4_ch_1[k].wvalid  = 1'b0;
            nvme2iafu_to_mc_axi4_ch_1[k].wuser   = 1'b0;
            
            nvme2iafu_to_mc_axi4_ch_1[k].arid    = 8'd0;
            nvme2iafu_to_mc_axi4_ch_1[k].araddr  = 64'd0;
            nvme2iafu_to_mc_axi4_ch_1[k].arlen   = 10'd0;
            nvme2iafu_to_mc_axi4_ch_1[k].arsize  = cafu_common_pkg::esize_CAFU_512; 
            nvme2iafu_to_mc_axi4_ch_1[k].arburst = cafu_common_pkg::eburst_CAFU_FIXED;
            nvme2iafu_to_mc_axi4_ch_1[k].arprot  = cafu_common_pkg::eprot_CAFU_UNPRIV_SECURE_DATA;
            nvme2iafu_to_mc_axi4_ch_1[k].arqos   = cafu_common_pkg::eqos_CAFU_BEST_EFFORT;
            nvme2iafu_to_mc_axi4_ch_1[k].arvalid = 1'b0;
            nvme2iafu_to_mc_axi4_ch_1[k].arcache = cafu_common_pkg::ecache_ar_CAFU_DEVICE_NON_BUFFERABLE;
            nvme2iafu_to_mc_axi4_ch_1[k].arlock  = cafu_common_pkg::elock_CAFU_NORMAL;
            nvme2iafu_to_mc_axi4_ch_1[k].arregion    =   4'b0000;
            nvme2iafu_to_mc_axi4_ch_1[k].aruser  = 1'b0;
        end

        unique case(mshr_d_state[i])
            STATE_IDLE: begin
                // tag2data_ready = 1'b1;
            end
            STATE_PRE_PROC: begin

            end
            STATE_PRE_PROC_DONE: begin
                tag2data_ready = 1'b1;
            end
            STATE_CHECK: begin
                
            end
            STATE_PROC_DATA: begin
                
            end
            STATE_FORWARD: begin
                if (p_q_a_reg.awvalid) begin
                    if (pre_proc_done) begin
                        nvme2iafu_to_mc_axi4_ch_1[p_q_a_reg.awaddr[6]].awvalid = 1'b1;
                        nvme2iafu_to_mc_axi4_ch_1[p_q_a_reg.awaddr[6]].awaddr = cxl_data_addr + {hash_reg[54:0], p_q_a_reg.awaddr[8:6], 6'd0};
                        nvme2iafu_to_mc_axi4_ch_1[p_q_a_reg.awaddr[6]].awid = {CH_ID[2:0], 1'b1, i[0], p_read_address_a_old[2:0]};

                        nvme2iafu_to_mc_axi4_ch_1[p_q_a_reg.awaddr[6]].wdata = p_q_a_reg.wdata;
                        nvme2iafu_to_mc_axi4_ch_1[p_q_a_reg.awaddr[6]].wstrb = p_q_a_reg.wstrb;
                        nvme2iafu_to_mc_axi4_ch_1[p_q_a_reg.awaddr[6]].wvalid = 1'b1;
                        nvme2iafu_to_mc_axi4_ch_1[p_q_a_reg.awaddr[6]].wlast = 1'b1;
                    end
                    else begin

                    end
                end
                else if (p_q_a_reg.arvalid) begin
                    nvme2iafu_to_mc_axi4_ch_1[p_q_a_reg.araddr[6]].arvalid = 1'b1;
                    nvme2iafu_to_mc_axi4_ch_1[p_q_a_reg.araddr[6]].araddr = cxl_data_addr + {hash_reg[54:0], p_q_a_reg.araddr[8:6], 6'd0};
                    nvme2iafu_to_mc_axi4_ch_1[p_q_a_reg.araddr[6]].arid = {CH_ID[2:0], 1'b1, i[0], p_read_address_a_old[2:0]};
                end
                else begin //somthing wrong
                    
                end
            end
            STATE_RESP: begin
                data2fifo_valid = 1'b1;
                if (resp_state_cnt == 2'd3) begin
                    data2tag_valid = 1'b1;
                end
            end
            default: begin

            end
        endcase

    //--------------------------------- Receive part        channel 5
        rp_wfifo_data[0] = iafu2nvme_from_mc_axi4_ch_1[0];
        rp_wfifo_data[1] = iafu2nvme_from_mc_axi4_ch_1[1];
        rp_wfifo_data[0].rvalid = 1'b0;
        rp_wfifo_data[1].rvalid = 1'b0;

        rp_rfifo_data[0] = iafu2nvme_from_mc_axi4_ch_1[0];
        rp_rfifo_data[1] = iafu2nvme_from_mc_axi4_ch_1[1];
        rp_rfifo_data[0].bvalid = 1'b0;
        rp_rfifo_data[1].bvalid = 1'b0;

        rdreq_rp_w[0] = 1'b0;
        rdreq_rp_w[1] = 1'b0;
        rdreq_rp_r[0] = 1'b0;
        rdreq_rp_r[1] = 1'b0;

        p_read_address_b = 4'd0;
        
        aclr_rp_r[0] = 1'b0;
        aclr_rp_r[1] = 1'b0;
        aclr_rp_w[0] = 1'b0;
        aclr_rp_w[1] = 1'b0; 

        for (int k=0; k<2; k++) begin
            mc2iafu_from_nvme_axi4_ch_i[k].arready = arready_r[k];
            mc2iafu_from_nvme_axi4_ch_i[k].awready = awready_r[k];
            mc2iafu_from_nvme_axi4_ch_i[k].wready =  wready_r[k];

            mc2iafu_from_nvme_axi4_ch_i[k].rvalid = 1'b0;
            mc2iafu_from_nvme_axi4_ch_i[k].rid = 9'b0;
            mc2iafu_from_nvme_axi4_ch_i[k].rlast = 1'b0;
            mc2iafu_from_nvme_axi4_ch_i[k].ruser = 1'b0; //TODO: not sure
            mc2iafu_from_nvme_axi4_ch_i[k].rdata = 512'b0;
            mc2iafu_from_nvme_axi4_ch_i[k].rresp = cafu_common_pkg::eresp_CAFU_OKAY;  //SIMU

            mc2iafu_from_nvme_axi4_ch_i[k].bid = 9'b0;
            mc2iafu_from_nvme_axi4_ch_i[k].buser = 1'b0; //TODO: not sure
            mc2iafu_from_nvme_axi4_ch_i[k].bvalid = 1'b0;
            mc2iafu_from_nvme_axi4_ch_i[k].bresp = cafu_common_pkg::eresp_CAFU_OKAY;
        end

        unique case(mshr_r_state[i])
            STATE_IDLE: begin
                if (!pre_proc_flush) begin
                    if (pre_proc_done && pre_proc_wrong) begin //need to flush fifo
                        aclr_rp_r[0] = 1'b1;
                        aclr_rp_r[1] = 1'b1;
                        aclr_rp_w[0] = 1'b1;
                        aclr_rp_w[1] = 1'b1; 
                    end
                    else begin //do not need to flush fifo
                        
                    end
                end
                else begin
                    if (!rdempty_rp_w[0]) begin
                        rdreq_rp_w[0] = 1'b1;
                    end
                    else if (!rdempty_rp_w[1]) begin
                        rdreq_rp_w[1] = 1'b1;
                    end
                    else if (!rdempty_rp_r[0]) begin
                        rdreq_rp_r[0] = 1'b1;
                    end
                    else if (!rdempty_rp_r[1]) begin
                        rdreq_rp_r[1] = 1'b1;
                    end
                end
            end

            STATE_CHECK: begin
                unique case(w_ch)
                    2'b00: begin
                        p_read_address_b = rp_wfifo_q[0].bid[2:0];
                    end
                    2'b01: begin
                        p_read_address_b = rp_wfifo_q[1].bid[2:0];
                    end
                    2'b10: begin
                        p_read_address_b = rp_rfifo_q[0].rid[2:0];
                    end
                    2'b11: begin
                        p_read_address_b = rp_rfifo_q[1].rid[2:0];
                    end
                endcase
            end

            STATE_PROC_DATA: begin
                
            end

            STATE_RESP: begin
                if (p_q_b_reg.awvalid) begin
                    mc2iafu_from_nvme_axi4_ch_i[p_q_b_reg.awaddr[6]].bvalid = 1'b1;
                    mc2iafu_from_nvme_axi4_ch_i[p_q_b_reg.awaddr[6]].bid = p_q_b_reg.awid;
                    mc2iafu_from_nvme_axi4_ch_i[p_q_b_reg.awaddr[6]].buser = 1'b0;
                end
                else if (p_q_b_reg.arvalid) begin
                    mc2iafu_from_nvme_axi4_ch_i[p_q_b_reg.araddr[6]].rvalid = 1'b1;
                    mc2iafu_from_nvme_axi4_ch_i[p_q_b_reg.araddr[6]].rid = p_q_b_reg.arid;
                    if (w_ch == 2'b10) begin
                        mc2iafu_from_nvme_axi4_ch_i[p_q_b_reg.araddr[6]].rdata = rp_rfifo_q[0].rdata;
                    end
                    else begin
                        mc2iafu_from_nvme_axi4_ch_i[p_q_b_reg.araddr[6]].rdata = rp_rfifo_q[1].rdata;
                    end
                    mc2iafu_from_nvme_axi4_ch_i[p_q_b_reg.araddr[6]].rlast = 1'b1;
                    mc2iafu_from_nvme_axi4_ch_i[p_q_b_reg.araddr[6]].ruser = 1'b0;
                end
                else begin //somthing wrong
                    
                end
            end

            default: begin

            end
        endcase

    /*---------------------------------
    State Machine Logic 
    -----------------------------------*/

    //-------------------------------------------- State machine for channel 2
        next_mshr_p_state[i] = STATE_IDLE;
        unique case(mshr_p_state[i])
            STATE_IDLE: begin
                if (pfifo_awvalid[i][0]) begin
                    next_mshr_p_state[i] = STATE_CHECK;
                end
                else if (pfifo_awvalid[i][1]) begin
                    next_mshr_p_state[i] = STATE_CHECK;
                end
                else begin
                    next_mshr_p_state[i] = STATE_IDLE;
                end
            end

            STATE_CHECK: begin
                next_mshr_p_state[i] = STATE_FORWARD;
            end

            STATE_FORWARD: begin //TODO: need signal to go to response state
                data2fifo_ready = 1'b1;
                if (data2fifo_valid) begin

                end
                else if (p_write_address_a[3] == 1'b1) begin //pfifo is full, stop receving request

                end
                else begin
                    if (pfifo_awvalid[i][0]) begin
                        if (rfifo_q_addr_reg[0][51:9] == pfifo_addr[i][51:9]) begin
                            pfifo_awready[i][0] = 1'b1;
                        end
                    end
                    else if (pfifo_awvalid[i][1]) begin
                        if (rfifo_q_addr_reg[1][51:9] == pfifo_addr[i][51:9]) begin
                            pfifo_awready[i][1] = 1'b1;
                        end
                    end
                end

                if (data2fifo_valid) begin
                    next_mshr_p_state[i] = STATE_RESP;
                end
                else if (p_write_address_a[3] == 1'b1) begin//pfifo is full, stop receving request
                    next_mshr_p_state[i] = STATE_FORWARD;
                end
                else begin
                    if (pfifo_awvalid[i][0]) begin
                        if (rfifo_q_addr_reg[0][51:9] == pfifo_addr[i][51:9]) begin
                            next_mshr_p_state[i] = STATE_CHECK;
                        end
                        else begin
                            next_mshr_p_state[i] = STATE_FORWARD;
                        end
                    end
                    else if (pfifo_awvalid[i][1]) begin
                        if (rfifo_q_addr_reg[1][51:9] == pfifo_addr[i][51:9]) begin
                            next_mshr_p_state[i] = STATE_CHECK;
                        end
                        else begin
                            next_mshr_p_state[i] = STATE_FORWARD;
                        end
                    end
                    else begin
                        next_mshr_p_state[i] = STATE_FORWARD;
                    end
                end
            end

            STATE_RESP: begin
                if (tag2fifo_valid) begin
                    next_mshr_p_state[i] = STATE_IDLE;
                end
                else begin
                    next_mshr_p_state[i] = STATE_RESP;
                end
            end

            default: begin

            end
        endcase

    //-------------------------------------------- State Machine for channel 3
        next_mshr_t_state[i] = STATE_IDLE;
        unique case(mshr_t_state[i])
            STATE_IDLE: begin
                if (p_write_address_a != 4'd0) begin
                    if (tag_reg[52] == 1'b1) begin //valid bit is 1
                        if (tag_reg[51:9] == pfifo_addr[i][51:9]) begin //addr match
                            next_mshr_t_state[i] = STATE_PROC_DATA;
                        end
                        else begin
                            next_mshr_t_state[i] = STATE_RD_TAG;
                        end
                    end
                    else begin
                        next_mshr_t_state[i] = STATE_RD_TAG;
                    end
                end
                else begin
                    next_mshr_t_state[i] = STATE_IDLE;
                end
            end
            STATE_RD_TAG: begin
                if (nvme2iafu_to_mc_axi4_ch_0[hash_reg[3]].arvalid && iafu2nvme_from_mc_axi4_ch_0[hash_reg[3]].arready) begin
                    next_mshr_t_state[i] = STATE_RD_TAG_DONE;
                end
                else begin
                    next_mshr_t_state[i] = STATE_RD_TAG;
                end
            end
            STATE_RD_TAG_DONE: begin
                if (iafu2nvme_from_mc_axi4_ch_0[hash_reg[3]].rvalid && nvme2iafu_to_mc_axi4_ch_0[hash_reg[3]].rready) begin
                    if (iafu2nvme_from_mc_axi4_ch_0[hash_reg[3]].rid == {CH_ID, 1'b0, i[0], arid_rd_tag}) begin
                        next_mshr_t_state[i] = STATE_RD_TAG_DONE_1;
                    end
                    else begin
                        next_mshr_t_state[i] = STATE_RD_TAG_DONE;
                    end
                end
                else begin
                    next_mshr_t_state[i] = STATE_RD_TAG_DONE;
                end
            end
            STATE_RD_TAG_DONE_1: begin
                if (tag_reg[52] == 1'b1) begin //valid bit is 1
                    if (tag_reg[51:9] == addr_reg[51:9]) begin //addr match
                        next_mshr_t_state[i] = STATE_PROC_DATA;
                    end
                    else begin
                        if (tag_reg[53] == 1'b1) begin//dirty bit is 1 but addr not the same
                            next_mshr_t_state[i] = STATE_WR_SSD_ACK;
                        end
                        else begin  //not dirty
                            next_mshr_t_state[i] = STATE_RD_SSD;
                        end
                    end
                end
                else begin //valid bit is 0
                    next_mshr_t_state[i] = STATE_RD_SSD;
                end               
            end
            STATE_WR_TAG: begin
                if (nvme2iafu_to_mc_axi4_ch_0[hash_reg[3]].awvalid && iafu2nvme_from_mc_axi4_ch_0[hash_reg[3]].awready) begin
                    next_mshr_t_state[i] = STATE_WR_TAG_DONE;
                end
                else begin
                    next_mshr_t_state[i] = STATE_WR_TAG;
                end
            end
            STATE_WR_TAG_DONE: begin
                if (iafu2nvme_from_mc_axi4_ch_0[hash_reg[3]].bvalid && nvme2iafu_to_mc_axi4_ch_0[hash_reg[3]].bready) begin
                    if (iafu2nvme_from_mc_axi4_ch_0[hash_reg[3]].bid == {CH_ID, 1'b0, i[0], awid_wr_tag}) begin
                        next_mshr_t_state[i] = STATE_RESP;
                    end
                    else begin
                        next_mshr_t_state[i] = STATE_WR_TAG_DONE;
                    end
                end
                else begin
                    next_mshr_t_state[i] = STATE_WR_TAG_DONE;
                end
            end
            STATE_RD_SSD: begin
                if (fe_to_nvme_axi4_ch[i].ssd_rq_valid && nvme_to_fe_axi4_ch[i].ssd_rq_ready) begin
                    if (wr_ssd_valid) begin //dirty, need both wr_ssd_cp and rd_ssd_cp
                        next_mshr_t_state[i] = STATE_WR_SSD_DONE;
                    end
                    else begin  //clean, just go to rd_ssd_done
                        next_mshr_t_state[i] = STATE_RD_SSD_DONE;
                    end
                end
                else begin
                    next_mshr_t_state[i] = STATE_RD_SSD;
                end
            end
            STATE_RD_SSD_DONE: begin
                // if (nvme_to_fe_axi4_ch[i].ssd_cp_valid && fe_to_nvme_axi4_ch[i].ssd_cp_ready) begin
                //     if ((nvme_to_fe_axi4_ch[i].ssd_cp_fe_id[11:10] == i[1:0]) && (nvme_to_fe_axi4_ch[i].ssd_cp_fe_id[9] == 1'b0)) begin
                //         next_mshr_t_state[i] = STATE_RD_SSD_RD_HOST;
                //     end
                //     else begin
                //         next_mshr_t_state[i] = STATE_RD_SSD_DONE;
                //     end
                // end
                // else begin
                //     next_mshr_t_state[i] = STATE_RD_SSD_DONE;
                // end
                if (rd_ssd_cp) begin
                    next_mshr_t_state[i] = STATE_RD_SSD_RD_HOST;
                end
                else begin
                    next_mshr_t_state[i] = STATE_RD_SSD_DONE;
                end
            end
            STATE_RD_SSD_RD_HOST: begin
                if (arvalid_ch && arready_ch) begin
                    next_mshr_t_state[i] = STATE_RD_SSD_RD_HOST_DONE;
                end
                else begin
                    next_mshr_t_state[i] = STATE_RD_SSD_RD_HOST;
                end
            end
            STATE_RD_SSD_RD_HOST_DONE: begin
                if (rvalid && rready) begin
                    if (rid == {CH_ID, i[0], arid_rd_buf_cafu}) begin
                        next_mshr_t_state[i] = STATE_RD_SSD_WR_DEV;
                    end
                    else begin
                        next_mshr_t_state[i] = STATE_RD_SSD_RD_HOST_DONE;
                    end
                end
                else begin
                    next_mshr_t_state[i] = STATE_RD_SSD_RD_HOST_DONE;
                end
            end
            STATE_RD_SSD_WR_DEV: begin
                if (nvme2iafu_to_mc_axi4_ch_0[buf_wr_cnt[0]].awvalid && iafu2nvme_from_mc_axi4_ch_0[buf_wr_cnt[0]].awready) begin
                    next_mshr_t_state[i] = STATE_RD_SSD_WR_DEV_DONE;
                end
                else begin
                    next_mshr_t_state[i] = STATE_RD_SSD_WR_DEV;
                end
            end
            STATE_RD_SSD_WR_DEV_DONE: begin
                if (iafu2nvme_from_mc_axi4_ch_0[buf_wr_rt_cnt[0]].bvalid && nvme2iafu_to_mc_axi4_ch_0[buf_wr_rt_cnt[0]].bready) begin
                    if (iafu2nvme_from_mc_axi4_ch_0[buf_wr_rt_cnt[0]].bid == {CH_ID, 1'b0, i[0], awid_wr_buf_mc}) begin
                        if (buf_wr_rt_cnt == 4'd7) begin
                            next_mshr_t_state[i] = STATE_RD_SSD_RL;
                        end
                        else begin
                            next_mshr_t_state[i] = STATE_RD_SSD_RD_HOST;
                        end
                    end
                    else begin
                        next_mshr_t_state[i] = STATE_RD_SSD_WR_DEV_DONE;
                    end
                end
                else begin
                    next_mshr_t_state[i] = STATE_RD_SSD_WR_DEV_DONE;
                end
            end
            STATE_RD_SSD_RL: begin
                if (nvme_to_fe_axi4_ch[i].ssd_rl_ready) begin
                    next_mshr_t_state[i] = STATE_PROC_DATA;
                end
                else begin
                    next_mshr_t_state[i] = STATE_RD_SSD_RL;
                end
            end
            STATE_WR_SSD_ACK: begin
                if (nvme_to_fe_axi4_ch[i].ssd_rq_ready) begin
                    next_mshr_t_state[i] = STATE_WR_SSD_ACK_DONE;
                end
                else begin
                    next_mshr_t_state[i] = STATE_WR_SSD_ACK;
                end
            end
            STATE_WR_SSD_ACK_DONE: begin
                if (nvme_to_fe_axi4_ch[i].ssd_bf_valid) begin
                    if ((nvme_to_fe_axi4_ch[i].ssd_bf_fe_id[11:10] == i[1:0]) && (nvme_to_fe_axi4_ch[i].ssd_bf_fe_id[9] == 1'b1)) begin
                        next_mshr_t_state[i] = STATE_WR_SSD_RD_DEV;
                    end
                    else begin
                        next_mshr_t_state[i] = STATE_WR_SSD_ACK_DONE;
                    end
                end
                else begin
                    next_mshr_t_state[i] = STATE_WR_SSD_ACK_DONE;
                end
            end
            STATE_WR_SSD_RD_DEV: begin
                if (nvme2iafu_to_mc_axi4_ch_0[buf_rd_cnt[0]].arvalid && iafu2nvme_from_mc_axi4_ch_0[buf_rd_cnt[0]].arready) begin
                    next_mshr_t_state[i] = STATE_WR_SSD_RD_DEV_DONE;
                end
                else begin
                    next_mshr_t_state[i] = STATE_WR_SSD_RD_DEV;
                end
            end
            STATE_WR_SSD_RD_DEV_DONE: begin
                if (iafu2nvme_from_mc_axi4_ch_0[buf_rd_rt_cnt[0]].rvalid && nvme2iafu_to_mc_axi4_ch_0[buf_rd_rt_cnt[0]].rready) begin
                    if (iafu2nvme_from_mc_axi4_ch_0[buf_rd_rt_cnt[0]].rid == {CH_ID, 1'b0, i[0], arid_rd_buf_mc}) begin
                        next_mshr_t_state[i] = STATE_WR_SSD_WR_HOST;
                    end
                    else begin
                        next_mshr_t_state[i] = STATE_WR_SSD_RD_DEV_DONE;
                    end
                end
                else begin
                    next_mshr_t_state[i] = STATE_WR_SSD_RD_DEV_DONE;
                end
            end
            STATE_WR_SSD_WR_HOST: begin
                if (awvalid_ch && awready_ch) begin
                    next_mshr_t_state[i] = STATE_WR_SSD_WR_HOST_DONE;
                end
                else begin
                    next_mshr_t_state[i] = STATE_WR_SSD_WR_HOST;
                end
            end
            STATE_WR_SSD_WR_HOST_DONE: begin
                if (bvalid && bready) begin
                    if (bid == {CH_ID, i[0], awid_wr_buf_cafu}) begin
                        if (buf_wr_rt_cnt == 4'd7) begin
                            next_mshr_t_state[i] = STATE_WR_SSD;
                        end
                        else begin
                            next_mshr_t_state[i] = STATE_WR_SSD_RD_DEV;
                        end
                    end
                    else begin
                        next_mshr_t_state[i] = STATE_WR_SSD_WR_HOST_DONE;
                    end
                end
                else begin
                    next_mshr_t_state[i] = STATE_WR_SSD_WR_HOST_DONE;
                end
            end
            STATE_WR_SSD: begin
                if (nvme_to_fe_axi4_ch[i].ssd_ack_ready) begin
                    // next_mshr_t_state[i] = STATE_WR_SSD_DONE;
                    // next_mshr_t_state[i] = STATE_RD_SSD;    //go directly to RD_SSD
                    next_mshr_t_state[i] = STATE_WR_SSD_RD_HOST;
                end
                else begin
                    next_mshr_t_state[i] = STATE_WR_SSD;
                end
            end
            STATE_WR_SSD_DONE: begin
                // if (nvme_to_fe_axi4_ch[i].ssd_cp_valid) begin
                //     if ((nvme_to_fe_axi4_ch[i].ssd_cp_fe_id[11:10] == i[1:0]) && (nvme_to_fe_axi4_ch[i].ssd_cp_fe_id[9] == 1'b1)) begin
                //         next_mshr_t_state[i] = STATE_WR_SSD_RL;
                //     end
                //     else begin
                //         next_mshr_t_state[i] = STATE_WR_SSD_DONE;
                //     end
                // end
                // else begin
                //     next_mshr_t_state[i] = STATE_WR_SSD_DONE;
                // end
                if (rd_ssd_cp && wr_ssd_cp) begin
                    // next_mshr_t_state[i] = STATE_WR_SSD_RL;
                    next_mshr_t_state[i] = STATE_RD_SSD_RD_HOST;
                end
                else begin
                    next_mshr_t_state[i] = STATE_WR_SSD_DONE;
                end
            end
            // STATE_WR_SSD_RL: begin
            //     if (nvme_to_fe_axi4_ch[i].ssd_rl_ready) begin
            //         next_mshr_t_state[i] = STATE_RD_SSD_RD_HOST;
            //     end
            //     else begin
            //         next_mshr_t_state[i] = STATE_WR_SSD_RL;
            //     end
            // end
            STATE_WR_SSD_RD_HOST: begin
                if (arvalid_ch && arready_ch) begin
                    next_mshr_t_state[i] = STATE_WR_SSD_RD_HOST_DONE;
                end
                else begin
                    next_mshr_t_state[i] = STATE_WR_SSD_RD_HOST;
                end
            end
            STATE_WR_SSD_RD_HOST_DONE: begin
                if (rvalid && rready) begin
                    if (rid == {CH_ID, i[0], arid_rd_buf_cafu}) begin
                        next_mshr_t_state[i] = STATE_RD_SSD;
                    end
                    else begin
                        next_mshr_t_state[i] = STATE_WR_SSD_RD_HOST_DONE;
                    end
                end
                else begin
                    next_mshr_t_state[i] = STATE_WR_SSD_RD_HOST_DONE;
                end
            end
            STATE_PROC_DATA: begin
                if (tag2data_ready) begin
                    next_mshr_t_state[i] = STATE_CHECK;
                end
                else begin
                    next_mshr_t_state[i] = STATE_PROC_DATA;
                end
            end
            STATE_CHECK: begin
                if (data2tag_valid) begin
                    if (valid_match) begin
                        if (tag_reg[53] == 1'b1) begin //dirty bit is 1
                            next_mshr_t_state[i] = STATE_RESP;
                        end
                        else begin //dirty bit is 0
                            if (data_write_valid) begin
                                next_mshr_t_state[i] = STATE_WR_TAG;
                            end
                            else begin
                                next_mshr_t_state[i] = STATE_RESP;
                            end
                        end
                    end
                    else begin
                        next_mshr_t_state[i] = STATE_WR_TAG;
                    end
                end
                else begin
                    next_mshr_t_state[i] = STATE_CHECK;
                end
            end
            STATE_RESP: begin
                if (tag2fifo_ready) begin
                    next_mshr_t_state[i] = STATE_IDLE;
                end
                else begin
                    next_mshr_t_state[i] = STATE_RESP;
                end
            end
            default: next_mshr_t_state[i] = STATE_IDLE;
        endcase

    //-------------------------------------------- State Machine for channel 4
        next_mshr_d_state[i] = STATE_IDLE;
        unique case(mshr_d_state[i])
            STATE_IDLE: begin
                // if (tag2data_valid) begin
                //     next_mshr_d_state[i] = STATE_CHECK;
                // end
                // else begin
                //     next_mshr_d_state[i] = STATE_IDLE;
                // end
                if (!pre_proc_valid) begin
                    if (p_write_address_a != 4'd0) begin
                        next_mshr_d_state[i] = STATE_PRE_PROC;
                    end
                    else begin
                        next_mshr_d_state[i] = STATE_IDLE;
                    end
                end
                else begin
                    next_mshr_d_state[i] = STATE_IDLE;
                end
            end
            STATE_PRE_PROC: begin
                if (pre_proc_valid) begin //tag has been read
                    if (pre_proc_issue_cnt == pre_proc_resp_cnt) begin //all preproc completed
                        next_mshr_d_state[i] = STATE_PRE_PROC_DONE;
                    end
                    else begin
                        next_mshr_d_state[i] = STATE_PRE_PROC;
                    end    
                end
                else begin //tag has not been read
                    if (p_read_address_a != p_write_address_a) begin   //if not fifo empty, keep issuing new request
                        next_mshr_d_state[i] = STATE_PROC_DATA;
                    end
                    else begin
                        next_mshr_d_state[i] = STATE_PRE_PROC;
                    end
                end
            end
            STATE_PRE_PROC_DONE: begin
                if (tag2data_valid) begin //data is ready for processing
                    next_mshr_d_state[i] = STATE_CHECK;
                end
                else begin
                    next_mshr_d_state[i] = STATE_PRE_PROC_DONE;
                end
            end
            STATE_CHECK: begin
                if (p_read_address_a != p_write_address_a) begin   //if not fifo empty, keep issuing new request
                    next_mshr_d_state[i] = STATE_PROC_DATA;
                end
                else begin  //if fifo empty, wait until resp = issue
                    if (p_read_address_a == resp_w_ptr) begin
                        next_mshr_d_state[i] = STATE_RESP;
                    end
                    else begin
                        next_mshr_d_state[i] = STATE_CHECK;
                    end
                end
            end
            STATE_PROC_DATA: begin
                next_mshr_d_state[i] = STATE_FORWARD;
            end
            STATE_FORWARD: begin
                if (p_q_a_reg.awvalid) begin
                    if (pre_proc_done) begin
                        if (iafu2nvme_from_mc_axi4_ch_1[p_q_a_reg.awaddr[6]].awready) begin
                            next_mshr_d_state[i] = STATE_CHECK;
                        end
                        else begin
                            next_mshr_d_state[i] = STATE_FORWARD;
                        end
                    end
                    else begin //still preproc
                        if (pre_proc_valid) begin
                            next_mshr_d_state[i] = STATE_PRE_PROC;
                        end
                        else begin
                            next_mshr_d_state[i] = STATE_FORWARD;
                        end
                    end
                end
                else if (p_q_a_reg.arvalid) begin
                    if (iafu2nvme_from_mc_axi4_ch_1[p_q_a_reg.araddr[6]].arready) begin
                        if (pre_proc_done) begin
                            next_mshr_d_state[i] = STATE_CHECK;
                            end
                        else begin
                            next_mshr_d_state[i] = STATE_PRE_PROC;
                        end
                    end
                    else begin
                        next_mshr_d_state[i] = STATE_FORWARD;
                    end
                end
                else begin //somthing wrong
                    next_mshr_d_state[i] = STATE_IDLE;
                end
            end
            STATE_RESP: begin
                if (resp_state_cnt == 2'd3) begin
                    if (data2tag_ready) begin
                        next_mshr_d_state[i] = STATE_IDLE;
                    end
                    else begin
                        next_mshr_d_state[i] = STATE_RESP;
                    end
                end
                else begin
                    if (p_read_address_a != p_write_address_a) begin
                        next_mshr_d_state[i] = STATE_CHECK;
                    end
                    else begin
                        next_mshr_d_state[i] = STATE_RESP;
                    end
                end
            end
            default: begin

            end
        endcase

    //-------------------------------------------- State Machine for channel 5
        next_mshr_r_state[i] = STATE_IDLE;
        unique case(mshr_r_state[i])
            STATE_IDLE: begin
                if (!pre_proc_flush) begin
                    if (pre_proc_done && pre_proc_wrong) begin //need to flush fifo
                        next_mshr_r_state[i] = STATE_IDLE;
                    end
                    else begin //do not need to flush fifo
                        next_mshr_r_state[i] = STATE_IDLE;
                    end
                end
                else begin
                    if (!rdempty_rp_w[0]) begin
                        next_mshr_r_state[i] = STATE_CHECK;
                    end
                    else if (!rdempty_rp_w[1]) begin
                        next_mshr_r_state[i] = STATE_CHECK;
                    end
                    else if (!rdempty_rp_r[0]) begin
                        next_mshr_r_state[i] = STATE_CHECK;
                    end
                    else if (!rdempty_rp_r[1]) begin
                        next_mshr_r_state[i] = STATE_CHECK;
                    end
                    else begin
                        next_mshr_r_state[i] = STATE_IDLE;
                    end
                end
            end

            STATE_CHECK: begin
                next_mshr_r_state[i] = STATE_PROC_DATA;
            end

            STATE_PROC_DATA: begin
                next_mshr_r_state[i] = STATE_RESP;
            end

            STATE_RESP: begin
                if (p_q_b_reg.awvalid) begin
                    if (iafu2mc_to_nvme_axi4_ch_i[p_q_b_reg.awaddr[6]].bready) begin
                        next_mshr_r_state[i] = STATE_IDLE;
                    end
                    else begin
                        next_mshr_r_state[i] = STATE_RESP;
                    end
                end
                else if (p_q_b_reg.arvalid) begin
                    if (iafu2mc_to_nvme_axi4_ch_i[p_q_b_reg.araddr[6]].rready) begin
                        next_mshr_r_state[i] = STATE_IDLE;
                    end
                    else begin
                        next_mshr_r_state[i] = STATE_RESP;
                    end
                end
                else begin //somthing wrong
                    next_mshr_r_state[i] = STATE_IDLE;
                end
            end

            default: begin

            end
        endcase
    end
endmodule: mshr