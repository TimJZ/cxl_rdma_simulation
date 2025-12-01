/*
Version: 1.0.0
Modified: 02/21/25
Purpose: control mc read/write channel
Description:    
02/21/25: initial version
*/


module mc_fifo #(
    parameter CH = 2,
    parameter CH_IDX = $clog2(CH) + 1
)
(
    input logic axi4_mm_clk,
    input logic axi4_mm_rst_n,
   
    //To front end
    input ed_mc_axi_if_pkg::t_to_mc_axi4 [1:0] nvme2iafu_to_mc_axi4_ch [CH-1:0],
    output ed_mc_axi_if_pkg::t_from_mc_axi4 [1:0] iafu2nvme_from_mc_axi4_ch [CH-1:0],

    //To memory controller
    output ed_mc_axi_if_pkg::t_to_mc_axi4 [1:0] nvme2iafu_to_mc_axi4,
    input ed_mc_axi_if_pkg::t_from_mc_axi4 [1:0] iafu2nvme_from_mc_axi4
);

ed_mc_axi_if_pkg::t_from_mc_axi4    t_iafu2nvme_from_mc_axi4_ch_i [1:0][CH-1:0];

genvar i;

generate
    for (i=0; i<2; i=i+1) begin: mc_fifo_ch
        ed_mc_axi_if_pkg::t_to_mc_axi4 nvme2iafu_to_mc_axi4_ch_i [CH-1:0];
        ed_mc_axi_if_pkg::t_from_mc_axi4 iafu2nvme_from_mc_axi4_ch_i [CH-1:0];

        assign t_iafu2nvme_from_mc_axi4_ch_i[i] = iafu2nvme_from_mc_axi4_ch_i;

        logic [59:0] rfifo_data;
        logic [59:0] rfifo_q;
        logic rfifo_wrreq   ;
        logic rfifo_rdreq   ;
        logic rfifo_full    ;
        logic rfifo_empty   ;

        logic [636:0] wfifo_data;
        logic [636:0] wfifo_q;
        logic wfifo_wrreq   ;
        logic wfifo_rdreq   ;
        logic wfifo_full    ;
        logic wfifo_empty   ;

        logic [CH_IDX-1:0] rfifo_index;
        logic [CH_IDX-1:0] wfifo_index;

        enum logic [1:0] {
            STATE_IDLE,
            STATE_LOAD,
            STATE_RUN
        } r_state, r_next_state, w_state, w_next_state, r_state_1, r_next_state_1, w_state_1, w_next_state_1;

        // mc_rfifo r_fifo_inst(
        //     .data   (rfifo_data     ),
        //     .wrreq  (rfifo_wrreq    ),
        //     .rdreq  (rfifo_rdreq    ),
        //     .clock  (axi4_mm_clk),
        //     .aclr   (1'b0),
        //     // .q      ({nvme2iafu_to_mc_axi4[i].arid, nvme2iafu_to_mc_axi4[i].araddr}),
        //     .q      (rfifo_q       ),
        //     .usedw  (),
        //     .full   (rfifo_full     ),
        //     .empty  (rfifo_empty    )
        // );

        // mc_wfifo w_fifo_inst(
        //     .data   (wfifo_data     ),
        //     .wrreq  (wfifo_wrreq    ),
        //     .rdreq  (wfifo_rdreq    ),
        //     .clock  (axi4_mm_clk),
        //     .aclr   (1'b0),
        //     // .q      ({nvme2iafu_to_mc_axi4[i].wdata, nvme2iafu_to_mc_axi4[i].wlast, nvme2iafu_to_mc_axi4[i].wstrb, nvme2iafu_to_mc_axi4[i].awid, nvme2iafu_to_mc_axi4[i].awaddr}),
        //     .q      (wfifo_q       ),
        //     .usedw  (),
        //     .full   (wfifo_full     ),
        //     .empty  (wfifo_empty    )
        // );

        mc_fifo_asyr r_fifo_inst(
            .data   (rfifo_data     ),
            .wrreq  (rfifo_wrreq    ),
            .rdreq  (rfifo_rdreq    ),
            .wrclk  (axi4_mm_clk),
            .rdclk  (axi4_mm_clk),
            .aclr   (1'b0),
            // .q      ({nvme2iafu_to_mc_axi4[i].arid, nvme2iafu_to_mc_axi4[i].araddr}),
            .q      (rfifo_q        ),
            .rdempty(rfifo_empty    ),
            .wrfull (rfifo_full     )
        );

        mc_fifo_asyn w_fifo_inst(
            .data   (wfifo_data     ),
            .wrreq  (wfifo_wrreq    ),
            .rdreq  (wfifo_rdreq    ),
            .wrclk  (axi4_mm_clk),
            .rdclk  (axi4_mm_clk),
            .aclr   (1'b0),
            // .q      ({nvme2iafu_to_mc_axi4[i].wdata, nvme2iafu_to_mc_axi4[i].wlast, nvme2iafu_to_mc_axi4[i].wstrb, nvme2iafu_to_mc_axi4[i].awid, nvme2iafu_to_mc_axi4[i].awaddr}),
            .q      (wfifo_q        ),
            .rdempty(wfifo_empty    ),
            .wrfull (wfifo_full     )
        );

        /*------------------
        Read Channel
        ------------------*/
        //receive port 
        always_ff @(posedge axi4_mm_clk) begin
            if (!axi4_mm_rst_n) begin
                r_state_1 <= STATE_IDLE;
                rfifo_data <= '0;
                for (int j=0; j<CH; j++) begin
                    iafu2nvme_from_mc_axi4_ch_i[j].arready  <= 1'b0;
                end
                rfifo_index <= '0;
            end
            else begin
                r_state_1 <= r_next_state_1;
                unique case(r_state_1)
                    STATE_IDLE: begin
                        if (!rfifo_full) begin
                            if (nvme2iafu_to_mc_axi4_ch_i[rfifo_index].arvalid) begin
                                rfifo_data <= {nvme2iafu_to_mc_axi4_ch_i[rfifo_index].arid, nvme2iafu_to_mc_axi4_ch_i[rfifo_index].araddr};
                                iafu2nvme_from_mc_axi4_ch_i[rfifo_index].arready  <= 1'b1;
                            end

                            if (rfifo_index == CH-1) begin
                                rfifo_index <= '0;
                            end
                            else begin
                                rfifo_index <= rfifo_index + 1'b1;
                            end
                        end
                    end
                    STATE_RUN: begin
                        for (int j=0; j<CH; j++) begin
                            iafu2nvme_from_mc_axi4_ch_i[j].arready  <= 1'b0;
                        end
                    end
                    default: begin

                    end
                endcase
            end
        end

        //issue port
        always_ff @(posedge axi4_mm_clk) begin
            if (!axi4_mm_rst_n) begin
                r_state <= STATE_IDLE;
            end
            else begin
                r_state <= r_next_state;
            end
        end

        /*------------------
        Write Channel
        ------------------*/
        //receive port 
        always_ff @(posedge axi4_mm_clk) begin
            if (!axi4_mm_rst_n) begin
                w_state_1 <= STATE_IDLE;
                wfifo_data <= '0;
                for (int j=0; j<CH; j++) begin
                    iafu2nvme_from_mc_axi4_ch_i[j].awready  <= 1'b0;
                    iafu2nvme_from_mc_axi4_ch_i[j].wready   <= 1'b0;
                end

                wfifo_index <= '0;
            end
            else begin
                w_state_1 <= w_next_state_1;
                unique case(w_state_1)
                    STATE_IDLE: begin
                        if (!wfifo_full) begin
                            if (nvme2iafu_to_mc_axi4_ch_i[wfifo_index].awvalid) begin
                                wfifo_data <= {nvme2iafu_to_mc_axi4_ch_i[wfifo_index].wdata, nvme2iafu_to_mc_axi4_ch_i[wfifo_index].wlast, nvme2iafu_to_mc_axi4_ch_i[wfifo_index].wstrb, nvme2iafu_to_mc_axi4_ch_i[wfifo_index].awid, nvme2iafu_to_mc_axi4_ch_i[wfifo_index].awaddr};
                                iafu2nvme_from_mc_axi4_ch_i[wfifo_index].awready  <= 1'b1;
                                iafu2nvme_from_mc_axi4_ch_i[wfifo_index].wready   <= 1'b1;
                            end

                            if (wfifo_index == CH-1) begin
                                wfifo_index <= '0;
                            end
                            else begin
                                wfifo_index <= wfifo_index + 1'b1;
                            end
                        end
                    end
                    STATE_RUN: begin
                        for (int j=0; j<CH; j++) begin
                            iafu2nvme_from_mc_axi4_ch_i[j].awready  <= 1'b0;
                            iafu2nvme_from_mc_axi4_ch_i[j].wready   <= 1'b0;
                        end
                    end
                    default: begin

                    end
                endcase
            end
        end


        //issue port
        always_ff @(posedge axi4_mm_clk) begin
            if (!axi4_mm_rst_n) begin
                w_state <= STATE_IDLE;
            end
            else begin
                w_state <= w_next_state;
            end
        end

        //read channel 
        assign nvme2iafu_to_mc_axi4[i].arid    = rfifo_q[59:52];
        assign nvme2iafu_to_mc_axi4[i].araddr  = rfifo_q[51:0];
        assign nvme2iafu_to_mc_axi4[i].arlen   = 10'd0;
        assign nvme2iafu_to_mc_axi4[i].arsize  = 0;
        assign nvme2iafu_to_mc_axi4[i].arburst = 0;
        assign nvme2iafu_to_mc_axi4[i].arprot  = 0;
        assign nvme2iafu_to_mc_axi4[i].arqos   = 0;
        // assign nvme2iafu_to_mc_axi4[i].arvalid = 1'b0;
        assign nvme2iafu_to_mc_axi4[i].arcache = 0;
        assign nvme2iafu_to_mc_axi4[i].arlock  = 0;
        assign nvme2iafu_to_mc_axi4[i].arregion    =   4'b0000;
        assign nvme2iafu_to_mc_axi4[i].aruser  = 1'b0;


        assign nvme2iafu_to_mc_axi4[i].bready  = 1'b1;
        assign nvme2iafu_to_mc_axi4[i].rready  = 1'b1;

        assign nvme2iafu_to_mc_axi4[i].awid    = wfifo_q[59:52];
        assign nvme2iafu_to_mc_axi4[i].awaddr  = wfifo_q[51:0];
        // assign nvme2iafu_to_mc_axi4[i].awid     = wfifo_awid;
        // assign nvme2iafu_to_mc_axi4[i].awaddr   = wfifo_awaddr;
        assign nvme2iafu_to_mc_axi4[i].awlen   = 10'd0;
        assign nvme2iafu_to_mc_axi4[i].awsize  = '0;
        assign nvme2iafu_to_mc_axi4[i].awburst = '0;
        assign nvme2iafu_to_mc_axi4[i].awprot  = '0;
        assign nvme2iafu_to_mc_axi4[i].awqos   = '0;
        // assign nvme2iafu_to_mc_axi4[i].awvalid = 1'b0;
        assign nvme2iafu_to_mc_axi4[i].awcache = '0;
        assign nvme2iafu_to_mc_axi4[i].awlock  = '0;
        assign nvme2iafu_to_mc_axi4[i].awregion    = 4'b0000;
        assign nvme2iafu_to_mc_axi4[i].awuser  = 1'b0;

        assign nvme2iafu_to_mc_axi4[i].wdata   = wfifo_q[636:125];
        assign nvme2iafu_to_mc_axi4[i].wstrb   = wfifo_q[123:60];
        assign nvme2iafu_to_mc_axi4[i].wlast   = wfifo_q[124];
        // assign nvme2iafu_to_mc_axi4[i].wdata   = wfifo_wdata;
        // assign nvme2iafu_to_mc_axi4[i].wstrb   = wfifo_wstrb;
        // assign nvme2iafu_to_mc_axi4[i].wlast   = wfifo_wlast;
        // assign nvme2iafu_to_mc_axi4[i].wvalid  = 1'b0;
        assign nvme2iafu_to_mc_axi4[i].wuser   = 1'b0;

/*------------------
Combination logic 
------------------*/
        always_comb begin            
            //setup 
            for (int j=0; j<CH; j++) begin
                nvme2iafu_to_mc_axi4_ch_i[j] = nvme2iafu_to_mc_axi4_ch[j][i];
            end

            //------------------------------------
            rfifo_wrreq = 1'b0;
            r_next_state_1 = STATE_IDLE;

            unique case(r_state_1)
                STATE_IDLE: begin
                    if (!rfifo_full) begin
                        if (nvme2iafu_to_mc_axi4_ch_i[rfifo_index].arvalid) begin
                            r_next_state_1 = STATE_RUN;
                        end
                    end
                end
                STATE_RUN: begin
                    rfifo_wrreq = 1'b1;
                    r_next_state_1 = STATE_IDLE;
                end
                default: begin

                end
            endcase

            //---------------------
            w_next_state_1 = STATE_IDLE;
            wfifo_wrreq = 1'b0;
            unique case(w_state_1)
                STATE_IDLE: begin
                    if (!wfifo_full) begin
                        if (nvme2iafu_to_mc_axi4_ch_i[wfifo_index].awvalid) begin
                            w_next_state_1 = STATE_RUN;
                        end
                    end
                end
                STATE_RUN: begin
                    w_next_state_1 = STATE_IDLE;
                    wfifo_wrreq = 1'b1;
                end
                default: begin

                end
            endcase

            //---------------------
            w_next_state = STATE_IDLE;
            wfifo_rdreq = 1'b0;
            nvme2iafu_to_mc_axi4[i].awvalid = 1'b0;
            nvme2iafu_to_mc_axi4[i].wvalid = 1'b0;

            unique case(w_state) 
                STATE_IDLE: begin
                    if (!wfifo_empty) begin
                        w_next_state = STATE_RUN;
                        wfifo_rdreq = 1'b1;
                    end
                    else begin
                        w_next_state = STATE_IDLE;
                    end
                end

                STATE_RUN: begin
                    nvme2iafu_to_mc_axi4[i].awvalid = 1'b1;
                    nvme2iafu_to_mc_axi4[i].wvalid = 1'b1;
                    if (iafu2nvme_from_mc_axi4[i].awready) begin
                        w_next_state = STATE_IDLE;
                    end
                    else begin
                        w_next_state = STATE_RUN;
                    end
                end
                default: begin

                end
            endcase

            //---------------------
            r_next_state = STATE_IDLE;
            rfifo_rdreq = 1'b0;
            nvme2iafu_to_mc_axi4[i].arvalid = 1'b0;

            unique case(r_state) 
                STATE_IDLE: begin
                    if (!rfifo_empty) begin
                        r_next_state = STATE_RUN;
                        rfifo_rdreq = 1'b1;
                    end
                    else begin
                        r_next_state = STATE_IDLE;
                    end
                end

                STATE_RUN: begin                   
                    nvme2iafu_to_mc_axi4[i].arvalid = 1'b1;
                    if (iafu2nvme_from_mc_axi4[i].arready) begin
                        r_next_state = STATE_IDLE;
                    end
                    else begin
                        r_next_state = STATE_RUN;
                    end
                end
                default: begin

                end
            endcase
        end

        // (* preserve_for_debug *) logic [31:0] rfifo_cnt;
        // (* preserve_for_debug *) logic [31:0] wfifo_cnt;

        // always_ff @(posedge axi4_mm_clk) begin
        //     if (!axi4_mm_rst_n) begin
        //         rfifo_cnt <= '0;
        //         wfifo_cnt <= '0;
        //     end
        //     else begin
        //         if (r_state_1 == STATE_RUN) begin
        //             rfifo_cnt <= rfifo_cnt + 1'b1;
        //         end
        //         if (w_state_1 == STATE_RUN) begin
        //             wfifo_cnt <= wfifo_cnt + 1'b1;
        //         end
        //     end
        // end
    end
endgenerate

always_comb begin
    for (int j=0; j<CH; j++) begin
        for (int k=0; k<2; k++) begin
            iafu2nvme_from_mc_axi4_ch[j][k].awready = t_iafu2nvme_from_mc_axi4_ch_i[k][j].awready;
            iafu2nvme_from_mc_axi4_ch[j][k].wready  = t_iafu2nvme_from_mc_axi4_ch_i[k][j].wready ;
            iafu2nvme_from_mc_axi4_ch[j][k].arready = t_iafu2nvme_from_mc_axi4_ch_i[k][j].arready;

            iafu2nvme_from_mc_axi4_ch[j][k].bid     = iafu2nvme_from_mc_axi4[k].bid    ;
            iafu2nvme_from_mc_axi4_ch[j][k].bresp   = iafu2nvme_from_mc_axi4[k].bresp  ;
            iafu2nvme_from_mc_axi4_ch[j][k].bvalid  = iafu2nvme_from_mc_axi4[k].bvalid ;
            iafu2nvme_from_mc_axi4_ch[j][k].buser   = iafu2nvme_from_mc_axi4[k].buser  ;
            
            iafu2nvme_from_mc_axi4_ch[j][k].rid     = iafu2nvme_from_mc_axi4[k].rid    ;
            iafu2nvme_from_mc_axi4_ch[j][k].rdata   = iafu2nvme_from_mc_axi4[k].rdata  ;
            iafu2nvme_from_mc_axi4_ch[j][k].rresp   = iafu2nvme_from_mc_axi4[k].rresp  ;
            iafu2nvme_from_mc_axi4_ch[j][k].rvalid  = iafu2nvme_from_mc_axi4[k].rvalid ;
            iafu2nvme_from_mc_axi4_ch[j][k].rlast   = iafu2nvme_from_mc_axi4[k].rlast  ;
            iafu2nvme_from_mc_axi4_ch[j][k].ruser   = iafu2nvme_from_mc_axi4[k].ruser  ;
        end
    end
end

// always_ff @(posedge axi4_mm_clk) begin
//     for (int j=0; j<CH; j++) begin
//         for (int k=0; k<2; k++) begin
//             iafu2nvme_from_mc_axi4_ch[j][k].bid     <= iafu2nvme_from_mc_axi4[k].bid    ;
//             iafu2nvme_from_mc_axi4_ch[j][k].bresp   <= iafu2nvme_from_mc_axi4[k].bresp  ;
//             iafu2nvme_from_mc_axi4_ch[j][k].bvalid  <= iafu2nvme_from_mc_axi4[k].bvalid ;
//             iafu2nvme_from_mc_axi4_ch[j][k].buser   <= iafu2nvme_from_mc_axi4[k].buser  ;
            
//             iafu2nvme_from_mc_axi4_ch[j][k].rid     <= iafu2nvme_from_mc_axi4[k].rid    ;
//             iafu2nvme_from_mc_axi4_ch[j][k].rdata   <= iafu2nvme_from_mc_axi4[k].rdata  ;
//             iafu2nvme_from_mc_axi4_ch[j][k].rresp   <= iafu2nvme_from_mc_axi4[k].rresp  ;
//             iafu2nvme_from_mc_axi4_ch[j][k].rvalid  <= iafu2nvme_from_mc_axi4[k].rvalid ;
//             iafu2nvme_from_mc_axi4_ch[j][k].rlast   <= iafu2nvme_from_mc_axi4[k].rlast  ;
//             iafu2nvme_from_mc_axi4_ch[j][k].ruser   <= iafu2nvme_from_mc_axi4[k].ruser  ;
//         end
//     end
// end

/*-------------------------------
Performance Counter
---------------------------------*/
// (*preserve_for_debug*) logic [31:0] ar_cnt_0;
// (*preserve_for_debug*) logic [31:0] ar_cnt_1;
// (*preserve_for_debug*) logic [31:0] aw_cnt_0;
// (*preserve_for_debug*) logic [31:0] aw_cnt_1;
// (*preserve_for_debug*) logic [31:0] r_cnt_0;
// (*preserve_for_debug*) logic [31:0] r_cnt_1;
// (*preserve_for_debug*) logic [31:0] b_cnt_0;
// (*preserve_for_debug*) logic [31:0] b_cnt_1;

// always_ff @(posedge axi4_mm_clk) begin
//     if (!axi4_mm_rst_n) begin
//         ar_cnt_0 <= 32'b0;
//         ar_cnt_1 <= 32'b0;
//         aw_cnt_0 <= 32'b0;
//         aw_cnt_1 <= 32'b0;
//         r_cnt_0 <= 32'b0;
//         r_cnt_1 <= 32'b0;
//         b_cnt_0 <= 32'b0;
//         b_cnt_1 <= 32'b0;
//     end
//     else begin
//         if (nvme2iafu_to_mc_axi4[0].arvalid & iafu2nvme_from_mc_axi4[0].arready) begin
//             ar_cnt_0 <= ar_cnt_0 + 1'b1;
//         end
//         if (nvme2iafu_to_mc_axi4[1].arvalid & iafu2nvme_from_mc_axi4[1].arready) begin
//             ar_cnt_1 <= ar_cnt_1 + 1'b1;
//         end
//         if (nvme2iafu_to_mc_axi4[0].awvalid & iafu2nvme_from_mc_axi4[0].awready) begin
//             aw_cnt_0 <= aw_cnt_0 + 1'b1;
//         end
//         if (nvme2iafu_to_mc_axi4[1].awvalid & iafu2nvme_from_mc_axi4[1].awready) begin
//             aw_cnt_1 <= aw_cnt_1 + 1'b1;
//         end
//         if (iafu2nvme_from_mc_axi4[0].rvalid & nvme2iafu_to_mc_axi4[0].rready) begin
//             r_cnt_0 <= r_cnt_0 + 1'b1;
//         end
//         if (iafu2nvme_from_mc_axi4[1].rvalid & nvme2iafu_to_mc_axi4[1].rready) begin
//             r_cnt_1 <= r_cnt_1 + 1'b1;
//         end
//         if (iafu2nvme_from_mc_axi4[0].bvalid & nvme2iafu_to_mc_axi4[0].bready) begin
//             b_cnt_0 <= b_cnt_0 + 1'b1;
//         end
//         if (iafu2nvme_from_mc_axi4[1].bvalid & nvme2iafu_to_mc_axi4[1].bready) begin
//             b_cnt_1 <= b_cnt_1 + 1'b1;
//         end
//     end
// end



endmodule