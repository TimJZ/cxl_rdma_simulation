/*
Module: nvme_admin
Purpose: control front_end and back_end interface
Date: 04/18/25
*/


module nvme_admin
import ed_mc_axi_if_pkg::*;
#(
    parameter FE_CH = 1,
    parameter BE_CH = 1,
    parameter FE_IDX = log2ceil(FE_CH),
    parameter BE_IDX = log2ceil(BE_CH)
)   
(
    input  logic                               clk,
    input  logic                               rst_n,
    // Front-end interface
    input  ed_mc_axi_if_pkg::t_to_nvme_axi4   [FE_CH-1:0]         fe_to_nvme_axi4,
    output ed_mc_axi_if_pkg::t_from_nvme_axi4 [FE_CH-1:0]         nvme_to_fe_axi4,
    // Back-end interface
    input  ed_mc_axi_if_pkg::t_from_nvme_axi4 [BE_CH-1:0]         be_to_nvme_axi4,
    output ed_mc_axi_if_pkg::t_to_nvme_axi4   [BE_CH-1:0]         nvme_to_be_axi4
);
    ed_mc_axi_if_pkg::t_to_nvme_axi4 rq_fifo_data;
    ed_mc_axi_if_pkg::t_to_nvme_axi4 rq_fifo_q;
    logic rq_fifo_wrreq;
    logic rq_fifo_rdreq;
    logic rq_fifo_rdempty;
    logic rq_fifo_wrfull;

    ed_mc_axi_if_pkg::t_from_nvme_axi4 cp_fifo_data;
    ed_mc_axi_if_pkg::t_from_nvme_axi4 cp_fifo_q;
    logic cp_fifo_wrreq;
    logic cp_fifo_rdreq;
    logic cp_fifo_rdempty;
    logic cp_fifo_wrfull;

    ed_mc_axi_if_pkg::t_from_nvme_axi4 bk_fifo_data;
    ed_mc_axi_if_pkg::t_from_nvme_axi4 bk_fifo_q;
    logic bk_fifo_wrreq;
    logic bk_fifo_rdreq;
    logic bk_fifo_rdempty;
    logic bk_fifo_wrfull;

    ed_mc_axi_if_pkg::t_to_nvme_axi4 ack_fifo_data;
    ed_mc_axi_if_pkg::t_to_nvme_axi4 ack_fifo_q;
    logic ack_fifo_wrreq;
    logic ack_fifo_rdreq;
    logic ack_fifo_rdempty;
    logic ack_fifo_wrfull;

    ed_mc_axi_if_pkg::t_to_nvme_axi4 rl_fifo_data;
    ed_mc_axi_if_pkg::t_to_nvme_axi4 rl_fifo_q;
    logic rl_fifo_wrreq;
    logic rl_fifo_rdreq;
    logic rl_fifo_rdempty;
    logic rl_fifo_wrfull;

    enum logic [2:0] {  
        STATE_IDLE,
        STATE_WAIT,
        STATE_ENQUEUE,
        STATE_DEQUEUE
    } state_rq_in, next_state_rq_in, state_rq_out, next_state_rq_out, 
    state_cp_in, next_state_cp_in, state_cp_out, next_state_cp_out,
    state_bk_in, next_state_bk_in, state_bk_out, next_state_bk_out,
    state_ack_in, next_state_ack_in, state_ack_out, next_state_ack_out,
    state_rl_in, next_state_rl_in, state_rl_out, next_state_rl_out;

    nvme_admin_to_fifo nvme_rq_fifo_inst(
        .data(rq_fifo_data),    //  fifo_input.datain
        .wrreq(rq_fifo_wrreq),   //            .wrreq
        .rdreq(rq_fifo_rdreq),   //            .rdreq
        .wrclk(clk),   //            .wrclk
        .rdclk(clk),   //            .rdclk
        .q(rq_fifo_q),       // fifo_output.dataout
        .rdempty(rq_fifo_rdempty), //            .rdempty
        .wrfull(rq_fifo_wrfull)   //            .wrfull
    );

    nvme_admin_from_fifo nvme_cp_fifo_inst(
        .data(cp_fifo_data),    //  fifo_input.datain
        .wrreq(cp_fifo_wrreq),   //            .wrreq
        .rdreq(cp_fifo_rdreq),   //            .rdreq
        .wrclk(clk),   //            .wrclk
        .rdclk(clk),   //            .rdclk
        .q(cp_fifo_q),       // fifo_output.dataout
        .rdempty(cp_fifo_rdempty), //            .rdempty
        .wrfull(cp_fifo_wrfull)   //            .wrfull
    );

    nvme_admin_from_fifo nvme_bf_fifo_inst(
        .data(bk_fifo_data),    //  fifo_input.datain
        .wrreq(bk_fifo_wrreq),   //            .wrreq
        .rdreq(bk_fifo_rdreq),   //            .rdreq
        .wrclk(clk),   //            .wrclk
        .rdclk(clk),   //            .rdclk
        .q(bk_fifo_q),       // fifo_output.dataout
        .rdempty(bk_fifo_rdempty), //            .rdempty
        .wrfull(bk_fifo_wrfull)   //            .wrfull
    );

    nvme_admin_to_fifo nvme_ack_fifo_inst(
        .data(ack_fifo_data),    //  fifo_input.datain
        .wrreq(ack_fifo_wrreq),   //            .wrreq
        .rdreq(ack_fifo_rdreq),   //            .rdreq
        .wrclk(clk),   //            .wrclk
        .rdclk(clk),   //            .rdclk
        .q(ack_fifo_q),       // fifo_output.dataout
        .rdempty(ack_fifo_rdempty), //            .rdempty
        .wrfull(ack_fifo_wrfull)   //            .wrfull
    );

    nvme_admin_to_fifo nvme_rl_fifo_inst(
        .data(rl_fifo_data),    //  fifo_input.datain
        .wrreq(rl_fifo_wrreq),   //            .wrreq
        .rdreq(rl_fifo_rdreq),   //            .rdreq
        .wrclk(clk),   //            .wrclk
        .rdclk(clk),   //            .rdclk
        .q(rl_fifo_q),       // fifo_output.dataout
        .rdempty(rl_fifo_rdempty), //            .rdempty
        .wrfull(rl_fifo_wrfull)   //            .wrfull
    );

    /*------------------------------------------
    Front-end interface logic
    --------------------------------------------*/
    //ENQUEUE state: enqueue the request from front-end to rq_fifo 
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            state_rq_in <= STATE_IDLE;
            rq_fifo_data <= '0;
        end
        else begin
            state_rq_in <= next_state_rq_in;

            unique case(state_rq_in)
                STATE_IDLE: begin
                    if (!rq_fifo_wrfull) begin
                        for (int i=0; i<FE_CH; i++) begin
                            if (fe_to_nvme_axi4[i].ssd_rq_valid) begin
                                rq_fifo_data.ssd_rq_valid <= fe_to_nvme_axi4[i].ssd_rq_valid;
                                rq_fifo_data.ssd_rq_type  <= fe_to_nvme_axi4[i].ssd_rq_type;
                                rq_fifo_data.ssd_rq_addr  <= fe_to_nvme_axi4[i].ssd_rq_addr;
                                rq_fifo_data.ssd_rq_hash  <= fe_to_nvme_axi4[i].ssd_rq_hash;
                                rq_fifo_data.ssd_rq_fe_id <= {fe_to_nvme_axi4[i].ssd_rq_fe_id[11:FE_IDX], i[FE_IDX-1:0]};
                                break;
                            end
                        end
                    end
                end
                STATE_ENQUEUE: begin
                    
                end
                default: begin

                end
            endcase
        end
    end

    always_comb begin
        next_state_rq_in = STATE_IDLE;
        unique case(state_rq_in)
            STATE_IDLE: begin
                if (!rq_fifo_wrfull) begin
                    for (int i=0; i<FE_CH; i++) begin
                        if (fe_to_nvme_axi4[i].ssd_rq_valid) begin
                            next_state_rq_in = STATE_ENQUEUE;
                            break;
                        end
                    end
                end
            end
            STATE_ENQUEUE: begin
                next_state_rq_in = STATE_IDLE;
            end
            default: begin

            end
        endcase
    end

    // always_comb begin
    //     rq_fifo_wrreq = 1'b0;

    //     for (int i=0; i<FE_CH; i++) begin
    //         nvme_to_fe_axi4[i].ssd_rq_ready = 1'b0;
    //     end

    //     unique case(state_rq_in)
    //         STATE_IDLE: begin
    //             if (!rq_fifo_wrfull) begin
    //                 for (int i=0; i<FE_CH; i++) begin
    //                     if (fe_to_nvme_axi4[i].ssd_rq_valid) begin
    //                         nvme_to_fe_axi4[i].ssd_rq_ready = 1'b1;
    //                         break;
    //                     end
    //                 end
    //             end
    //         end
    //         STATE_ENQUEUE: begin
    //             rq_fifo_wrreq = 1'b1;
    //         end
    //         default: begin

    //         end
    //     endcase
    // end

    //DEQUEUE state: dequeue the request from rq_fifo to back-end
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            state_rq_out <= STATE_IDLE;
        end else begin
            state_rq_out <= next_state_rq_out;

            unique case(state_rq_out)
                STATE_IDLE: begin
                    
                end
                STATE_DEQUEUE: begin
                    
                end
                default: begin

                end
            endcase
        end
    end

    always_comb begin
        next_state_rq_out = STATE_IDLE;
        unique case(state_rq_out)
            STATE_IDLE: begin
                if (!rq_fifo_rdempty) begin
                    next_state_rq_out = STATE_DEQUEUE;
                end
            end
            STATE_DEQUEUE: begin
                next_state_rq_out = STATE_DEQUEUE;
                for (int i=1; i<2; i++) begin
                    if (be_to_nvme_axi4[i].ssd_rq_ready) begin
                        next_state_rq_out = STATE_IDLE;
                        break;
                    end
                end
            end
            default: begin

            end
        endcase
    end

    // always_comb begin
    //     rq_fifo_rdreq = 1'b0;
    //     for (int i=0; i<BE_CH; i++) begin
    //         nvme_to_be_axi4[i].ssd_rq_valid = 1'b0;
    //     end

    //     unique case(state_rq_out)
    //         STATE_IDLE: begin
    //             if (!rq_fifo_rdempty) begin
    //                 rq_fifo_rdreq = 1'b1;
    //             end
    //         end
    //         STATE_DEQUEUE: begin
    //             for (int i=0; i<BE_CH; i++) begin
    //                 if (be_to_nvme_axi4[i].ssd_rq_ready) begin
    //                     nvme_to_be_axi4[i].ssd_rq_valid = 1'b1;
    //                     nvme_to_be_axi4[i].ssd_rq_type = rq_fifo_q.ssd_rq_type;
    //                     nvme_to_be_axi4[i].ssd_rq_addr = rq_fifo_q.ssd_rq_addr;
    //                     nvme_to_be_axi4[i].ssd_rq_hash = rq_fifo_q.ssd_rq_hash;
    //                     nvme_to_be_axi4[i].ssd_rq_fe_id   = rq_fifo_q.ssd_rq_fe_id;
    //                     break;
    //                 end
    //             end
    //         end
    //         default: begin

    //         end
    //     endcase
    // end

    /*------------------------------------------
    Back-end interface logic
    --------------------------------------------*/
    //ENQUEUE state: enqueue the response from back-end to cp_fifo
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            state_cp_in <= STATE_IDLE;
            cp_fifo_data <= '0;
        end else begin
            state_cp_in <= next_state_cp_in;

            unique case(state_cp_in)
                STATE_IDLE: begin
                    if (!cp_fifo_wrfull) begin
                        for (int i=0; i<BE_CH; i++) begin
                            if (be_to_nvme_axi4[i].ssd_cp_valid) begin
                                cp_fifo_data.ssd_cp_valid <= be_to_nvme_axi4[i].ssd_cp_valid;
                                cp_fifo_data.ssd_cp_addr  <= be_to_nvme_axi4[i].ssd_cp_addr;
                                cp_fifo_data.ssd_cp_fe_id <= be_to_nvme_axi4[i].ssd_cp_fe_id;
                                cp_fifo_data.ssd_cp_be_id <= {{(12-BE_IDX){1'b0}}, i[BE_IDX-1:0]};
                                break;
                            end
                        end
                    end
                end
                STATE_ENQUEUE: begin
                    
                end
                default: begin

                end
            endcase
        end
    end

    always_comb begin
        next_state_cp_in = STATE_IDLE;

        unique case(state_cp_in)
            STATE_IDLE: begin
                if (!cp_fifo_wrfull) begin
                    for (int i=0; i<BE_CH; i++) begin
                        if (be_to_nvme_axi4[i].ssd_cp_valid) begin
                            next_state_cp_in = STATE_ENQUEUE;
                            break;
                        end
                    end
                end
            end
            STATE_ENQUEUE: begin
                next_state_cp_in = STATE_IDLE;
            end
            default: begin

            end
        endcase
    end

    // always_comb begin
    //     cp_fifo_wrreq = 1'b0;

    //     for (int i=0; i<BE_CH; i++) begin
    //         nvme_to_be_axi4[i].ssd_cp_ready = 1'b0;
    //     end

    //     unique case(state_cp_in)
    //         STATE_IDLE: begin
    //             if (!cp_fifo_wrfull) begin
    //                 for (int i=0; i<BE_CH; i++) begin
    //                     if (be_to_nvme_axi4[i].ssd_cp_valid) begin
    //                         nvme_to_be_axi4[i].ssd_cp_ready = 1'b1;
    //                         break;
    //                     end
    //                 end
    //             end
    //         end
    //         STATE_ENQUEUE: begin
    //             cp_fifo_wrreq = 1'b1;
    //         end
    //         default: begin

    //         end
    //     endcase
    // end

    //DEQUEUE state: dequeue the response from cp_fifo to front-end
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            state_cp_out <= STATE_IDLE;
        end else begin
            state_cp_out <= next_state_cp_out;

            unique case(state_cp_out)
                STATE_IDLE: begin
                    
                end
                STATE_DEQUEUE: begin
                    
                end
                default: begin

                end
            endcase
        end
    end


    always_comb begin
        next_state_cp_out = STATE_IDLE;
        unique case(state_cp_out)
            STATE_IDLE: begin
                if (!cp_fifo_rdempty) begin
                    next_state_cp_out = STATE_DEQUEUE;
                end
            end
            STATE_DEQUEUE: begin
                if (fe_to_nvme_axi4[cp_fifo_q.ssd_cp_fe_id[FE_IDX-1:0]].ssd_cp_ready) begin
                    next_state_cp_out = STATE_IDLE;
                end
                else begin
                    next_state_cp_out = STATE_DEQUEUE;
                end
            end
            default: begin

            end
        endcase
    end

    // always_comb begin
    //     cp_fifo_rdreq = 1'b0;
    //     for (int i=0; i<FE_CH; i++) begin
    //         nvme_to_fe_axi4[i].ssd_cp_valid = 1'b0;
    //     end

    //     unique case(state_cp_out)
    //         STATE_IDLE: begin
    //             if (!cp_fifo_rdempty) begin
    //                 cp_fifo_rdreq = 1'b1;
    //             end
    //         end
    //         STATE_DEQUEUE: begin
    //             if (fe_to_nvme_axi4[cp_fifo_q.ssd_cp_fe_id[2:0]].ssd_cp_ready) begin
    //                 nvme_to_fe_axi4[cp_fifo_q.ssd_cp_fe_id[2:0]].ssd_cp_valid = 1'b1;
    //                 nvme_to_fe_axi4[cp_fifo_q.ssd_cp_fe_id[2:0]].ssd_cp_fe_id   = cp_fifo_q.ssd_cp_fe_id;
    //             end
    //         end
    //         default: begin

    //         end
    //     endcase
    // end

    /*------------------------------------------
    Back forwarding interface logic
    --------------------------------------------*/
    //ENQUEUE state: enqueue the response from back-end to bf_fifo

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            state_bk_in <= STATE_IDLE;
            bk_fifo_data <= '0;
        end else begin
            state_bk_in <= next_state_bk_in;

            unique case(state_bk_in)
                STATE_IDLE: begin
                    if (!bk_fifo_wrfull) begin
                        for (int i=0; i<BE_CH; i++) begin
                            if (be_to_nvme_axi4[i].ssd_bf_valid) begin
                                bk_fifo_data.ssd_bf_valid <= be_to_nvme_axi4[i].ssd_bf_valid;
                                bk_fifo_data.ssd_bf_addr  <= be_to_nvme_axi4[i].ssd_bf_addr;
                                bk_fifo_data.ssd_bf_be_id <= {{(12-BE_IDX){1'b0}}, i[BE_IDX-1:0]};
                                bk_fifo_data.ssd_bf_fe_id <= be_to_nvme_axi4[i].ssd_bf_fe_id;
                                break;
                            end
                        end
                    end
                end
                STATE_ENQUEUE: begin
                    
                end
                default: begin

                end
            endcase
        end
    end

    always_comb begin
        next_state_bk_in = STATE_IDLE;

        unique case(state_bk_in)
            STATE_IDLE: begin
                if (!bk_fifo_wrfull) begin
                    for (int i=0; i<BE_CH; i++) begin
                        if (be_to_nvme_axi4[i].ssd_bf_valid) begin
                            next_state_bk_in = STATE_ENQUEUE;
                            break;
                        end
                    end
                end
            end
            STATE_ENQUEUE: begin
                next_state_bk_in = STATE_IDLE;              
            end
            default: begin

            end
        endcase
    end

    // always_comb begin
    //     bk_fifo_wrreq = 1'b0;

    //     for (int i=0; i<BE_CH; i++) begin
    //         nvme_to_be_axi4[i].ssd_bf_ready = 1'b0;
    //     end

    //     unique case(state_bk_in)
    //         STATE_IDLE: begin
    //             if (!bk_fifo_wrfull) begin
    //                 for (int i=0; i<BE_CH; i++) begin
    //                     if (be_to_nvme_axi4[i].ssd_bf_valid) begin
    //                         nvme_to_be_axi4[i].ssd_bf_ready = 1'b1;
    //                         break;
    //                     end
    //                 end
    //             end
    //         end
    //         STATE_ENQUEUE: begin
    //             bk_fifo_wrreq = 1'b1;
    //         end
    //         default: begin

    //         end
    //     endcase
    // end

    //DEQUEUE state: dequeue the response from bf_fifo to front-end
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            state_bk_out <= STATE_IDLE;
        end else begin
            state_bk_out <= next_state_bk_out;

            unique case(state_bk_out)
                STATE_IDLE: begin
                    
                end
                STATE_DEQUEUE: begin
                    
                end
                default: begin

                end
            endcase
        end
    end

    always_comb begin
        next_state_bk_out = STATE_IDLE;
        unique case(state_bk_out)
            STATE_IDLE: begin
                if (!bk_fifo_rdempty) begin
                    next_state_bk_out = STATE_DEQUEUE;
                end
            end
            STATE_DEQUEUE: begin
                if (fe_to_nvme_axi4[bk_fifo_q.ssd_bf_fe_id[FE_IDX-1:0]].ssd_bf_ready) begin
                    next_state_bk_out = STATE_IDLE;
                end
                else begin
                    next_state_bk_out = STATE_DEQUEUE;
                end
            end
            default: begin

            end
        endcase
    end

    // always_comb begin
    //     bk_fifo_rdreq = 1'b0;
    //     for (int i=0; i<FE_CH; i++) begin
    //         nvme_to_fe_axi4[i].ssd_bf_valid = 1'b0;
    //     end

    //     unique case(state_bk_out)
    //         STATE_IDLE: begin
    //             if (!bk_fifo_rdempty) begin
    //                 bk_fifo_rdreq = 1'b1;
    //             end
    //         end
    //         STATE_DEQUEUE: begin
    //             if (fe_to_nvme_axi4[bk_fifo_q.ssd_bf_fe_id[2:0]].ssd_bf_ready) begin
    //                 nvme_to_fe_axi4[bk_fifo_q.ssd_bf_fe_id[2:0]].ssd_bf_valid  = 1'b1;
    //                 nvme_to_fe_axi4[bk_fifo_q.ssd_bf_fe_id[2:0]].ssd_bf_addr   = bk_fifo_q.ssd_bf_addr;
    //                 nvme_to_fe_axi4[bk_fifo_q.ssd_bf_fe_id[2:0]].ssd_bf_be_id  = bk_fifo_q.ssd_bf_be_id;
    //                 nvme_to_fe_axi4[bk_fifo_q.ssd_bf_fe_id[2:0]].ssd_bf_fe_id  = bk_fifo_q.ssd_bf_fe_id;
    //             end
    //         end
    //         default: begin

    //         end
    //     endcase
    // end

    /*------------------------------------------
    Acknowledge interface logic
    --------------------------------------------*/
    //ENQUEUE state: enqueue the response from front-end to ack_fifo
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            state_ack_in <= STATE_IDLE;
            ack_fifo_data <= '0;
        end else begin
            state_ack_in <= next_state_ack_in;

            unique case(state_ack_in)
                STATE_IDLE: begin
                    if (!ack_fifo_wrfull) begin
                        for (int i=0; i<FE_CH; i++) begin
                            if (fe_to_nvme_axi4[i].ssd_ack_valid) begin
                                ack_fifo_data <= fe_to_nvme_axi4[i];
                                break;
                            end
                        end
                    end
                end
                STATE_ENQUEUE: begin
                    
                end
                default: begin

                end
            endcase
        end
    end

    always_comb begin
        next_state_ack_in = STATE_IDLE;

        unique case(state_ack_in)
            STATE_IDLE: begin
                if (!ack_fifo_wrfull) begin
                    for (int i=0; i<FE_CH; i++) begin
                        if (fe_to_nvme_axi4[i].ssd_ack_valid) begin
                            next_state_ack_in = STATE_ENQUEUE;
                            break;
                        end
                    end
                end
            end
            STATE_ENQUEUE: begin
                next_state_ack_in = STATE_IDLE;              
            end
            default: begin

            end
        endcase
    end

    // always_comb begin
    //     ack_fifo_wrreq = 1'b0;

    //     for (int i=0; i<FE_CH; i++) begin
    //         nvme_to_fe_axi4[i].ssd_ack_ready = 1'b0;
    //     end

    //     unique case(state_ack_in)
    //         STATE_IDLE: begin
    //             if (!ack_fifo_wrfull) begin
    //                 for (int i=0; i<FE_CH; i++) begin
    //                     if (fe_to_nvme_axi4[i].ssd_ack_valid) begin
    //                         nvme_to_fe_axi4[i].ssd_ack_ready = 1'b1;
    //                         break;
    //                     end
    //                 end
    //             end
    //         end
    //         STATE_ENQUEUE: begin
    //             ack_fifo_wrreq = 1'b1;
    //         end
    //         default: begin

    //         end
    //     endcase
    // end

    //DEQUEUE state: dequeue the response from ack_fifo to back-end
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            state_ack_out <= STATE_IDLE;
        end else begin
            state_ack_out <= next_state_ack_out;

            unique case(state_ack_out)
                STATE_IDLE: begin
                    
                end
                STATE_DEQUEUE: begin
                    
                end
                default: begin

                end
            endcase
        end
    end

    always_comb begin
        next_state_ack_out = STATE_IDLE;
        unique case(state_ack_out)
            STATE_IDLE: begin
                if (!ack_fifo_rdempty) begin
                    next_state_ack_out = STATE_DEQUEUE;
                end
            end
            STATE_DEQUEUE: begin
                if (be_to_nvme_axi4[ack_fifo_q.ssd_ack_be_id[BE_IDX-1:0]].ssd_ack_ready) begin
                    next_state_ack_out = STATE_IDLE;
                end
                else begin
                    next_state_ack_out = STATE_DEQUEUE;
                end
            end
            default: begin

            end
        endcase
    end

    // always_comb begin
    //     ack_fifo_rdreq = 1'b0;
    //     for (int i=0; i<BE_CH; i++) begin
    //         nvme_to_be_axi4[i].ssd_ack_valid = 1'b0;
    //     end

    //     unique case(state_ack_out)
    //         STATE_IDLE: begin
    //             if (!ack_fifo_rdempty) begin
    //                 ack_fifo_rdreq = 1'b1;
    //             end
    //         end
    //         STATE_DEQUEUE: begin
    //             if (be_to_nvme_axi4[ack_fifo_q.ssd_ack_be_id[2:0]].ssd_ack_ready) begin
    //                 nvme_to_be_axi4[ack_fifo_q.ssd_ack_be_id[2:0]].ssd_ack_valid = 1'b1;
    //                 nvme_to_be_axi4[ack_fifo_q.ssd_ack_be_id[2:0]].ssd_ack_be_id = ack_fifo_q.ssd_ack_be_id;
    //             end
    //         end
    //         default: begin

    //         end
    //     endcase
    // end


    /*------------------------------------------
    Release interface logic
    --------------------------------------------*/
    //ENQUEUE state: enqueue the release from front-end to rl_fifo
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            state_rl_in <= STATE_IDLE;
            rl_fifo_data <= '0;
        end else begin
            state_rl_in <= next_state_rl_in;

            unique case(state_rl_in)
                STATE_IDLE: begin
                    if (!rl_fifo_wrfull) begin
                        for (int i=0; i<FE_CH; i++) begin
                            if (fe_to_nvme_axi4[i].ssd_rl_valid) begin
                                rl_fifo_data <= fe_to_nvme_axi4[i];
                                break;
                            end
                        end
                    end
                end
                STATE_ENQUEUE: begin
                    
                end
                default: begin

                end
            endcase
        end
    end

    always_comb begin
        next_state_rl_in = STATE_IDLE;

        unique case(state_rl_in)
            STATE_IDLE: begin
                if (!rl_fifo_wrfull) begin
                    for (int i=0; i<FE_CH; i++) begin
                        if (fe_to_nvme_axi4[i].ssd_rl_valid) begin
                            next_state_rl_in = STATE_ENQUEUE;
                            break;
                        end
                    end
                end
            end
            STATE_ENQUEUE: begin
                next_state_rl_in = STATE_IDLE;              
            end
            default: begin

            end
        endcase
    end

    // always_comb begin
    //     rl_fifo_wrreq = 1'b0;

    //     for (int i=0; i<FE_CH; i++) begin
    //         nvme_to_fe_axi4[i].ssd_rl_ready = 1'b0;
    //     end

    //     unique case(state_rl_in)
    //         STATE_IDLE: begin
    //             if (!rl_fifo_wrfull) begin
    //                 for (int i=0; i<FE_CH; i++) begin
    //                     if (fe_to_nvme_axi4[i].ssd_rl_valid) begin
    //                         nvme_to_fe_axi4[i].ssd_rl_ready = 1'b1;
    //                         break;
    //                     end
    //                 end
    //             end
    //         end
    //         STATE_ENQUEUE: begin
    //             rl_fifo_wrreq = 1'b1;
    //         end
    //         default: begin

    //         end
    //     endcase
    // end

    //DEQUEUE state: dequeue the response from rl_fifo to back-end
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            state_rl_out <= STATE_IDLE;
        end else begin
            state_rl_out <= next_state_rl_out;

            unique case(state_rl_out)
                STATE_IDLE: begin
                    
                end
                STATE_DEQUEUE: begin
                    
                end
                default: begin

                end
            endcase
        end
    end

    always_comb begin
        next_state_rl_out = STATE_IDLE;
        unique case(state_rl_out)
            STATE_IDLE: begin
                if (!rl_fifo_rdempty) begin
                    next_state_rl_out = STATE_DEQUEUE;
                end
            end
            STATE_DEQUEUE: begin
                if (be_to_nvme_axi4[rl_fifo_q.ssd_rl_be_id[BE_IDX-1:0]].ssd_rl_ready) begin
                    next_state_rl_out = STATE_IDLE;
                end
                else begin
                    next_state_rl_out = STATE_DEQUEUE;
                end
            end
            default: begin

            end
        endcase
    end

    // always_comb begin
    //     rl_fifo_rdreq = 1'b0;
    //     for (int i=0; i<BE_CH; i++) begin
    //         nvme_to_be_axi4[i].ssd_rl_valid = 1'b0;
    //     end

    //     unique case(state_rl_out)
    //         STATE_IDLE: begin
    //             if (!rl_fifo_rdempty) begin
    //                 rl_fifo_rdreq = 1'b1;
    //             end
    //         end
    //         STATE_DEQUEUE: begin
    //             if (be_to_nvme_axi4[rl_fifo_q.ssd_rl_be_id[2:0]].ssd_rl_ready) begin
    //                 nvme_to_be_axi4[rl_fifo_q.ssd_rl_be_id[2:0]].ssd_rl_valid = 1'b1;
    //                 nvme_to_be_axi4[rl_fifo_q.ssd_rl_be_id[2:0]].ssd_rl_be_id = rl_fifo_q.ssd_rl_be_id;
    //             end
    //         end
    //         default: begin

    //         end
    //     endcase
    // end


    /*------------------------------------------
    Combinational logic 
    --------------------------------------------*/

    always_comb begin
    //------------------------------------------------------
        rq_fifo_wrreq = 1'b0;

        for (int i=0; i<FE_CH; i++) begin
            nvme_to_fe_axi4[i].ssd_rq_ready = 1'b0;
        end

        unique case(state_rq_in)
            STATE_IDLE: begin
                if (!rq_fifo_wrfull) begin
                    for (int i=0; i<FE_CH; i++) begin
                        if (fe_to_nvme_axi4[i].ssd_rq_valid) begin
                            nvme_to_fe_axi4[i].ssd_rq_ready = 1'b1;
                            break;
                        end
                    end
                end
            end
            STATE_ENQUEUE: begin
                rq_fifo_wrreq = 1'b1;
            end
            default: begin

            end
        endcase

    //------------------------------------------------------
        rq_fifo_rdreq = 1'b0;
        for (int i=0; i<BE_CH; i++) begin
            nvme_to_be_axi4[i].ssd_rq_valid = 1'b0;
            nvme_to_be_axi4[i].ssd_rq_type  = '0;
            nvme_to_be_axi4[i].ssd_rq_addr  = '0;
            nvme_to_be_axi4[i].ssd_rq_hash  = '0;
            nvme_to_be_axi4[i].ssd_rq_fe_id = '0;
        end

        unique case(state_rq_out)
            STATE_IDLE: begin
                if (!rq_fifo_rdempty) begin
                    rq_fifo_rdreq = 1'b1;
                end
            end
            STATE_DEQUEUE: begin
                for (int i=1; i<2; i++) begin
                    if (be_to_nvme_axi4[i].ssd_rq_ready) begin
                        nvme_to_be_axi4[i].ssd_rq_valid = 1'b1;
                        nvme_to_be_axi4[i].ssd_rq_type = rq_fifo_q.ssd_rq_type;
                        nvme_to_be_axi4[i].ssd_rq_addr = rq_fifo_q.ssd_rq_addr;
                        nvme_to_be_axi4[i].ssd_rq_hash = rq_fifo_q.ssd_rq_hash;
                        nvme_to_be_axi4[i].ssd_rq_fe_id   = rq_fifo_q.ssd_rq_fe_id;
                        break;
                    end
                end
            end
            default: begin

            end
        endcase

    //------------------------------------------------------
        cp_fifo_wrreq = 1'b0;

        for (int i=0; i<BE_CH; i++) begin
            nvme_to_be_axi4[i].ssd_cp_ready = 1'b0;
        end

        unique case(state_cp_in)
            STATE_IDLE: begin
                if (!cp_fifo_wrfull) begin
                    for (int i=0; i<BE_CH; i++) begin
                        if (be_to_nvme_axi4[i].ssd_cp_valid) begin
                            nvme_to_be_axi4[i].ssd_cp_ready = 1'b1;
                            break;
                        end
                    end
                end
            end
            STATE_ENQUEUE: begin
                cp_fifo_wrreq = 1'b1;
            end
            default: begin

            end
        endcase

    //------------------------------------------------------
        cp_fifo_rdreq = 1'b0;
        for (int i=0; i<FE_CH; i++) begin
            nvme_to_fe_axi4[i].ssd_cp_valid = 1'b0;
            nvme_to_fe_axi4[i].ssd_cp_addr  = '0;
            nvme_to_fe_axi4[i].ssd_cp_fe_id = '0;
            nvme_to_fe_axi4[i].ssd_cp_be_id = '0;
        end

        unique case(state_cp_out)
            STATE_IDLE: begin
                if (!cp_fifo_rdempty) begin
                    cp_fifo_rdreq = 1'b1;
                end
            end
            STATE_DEQUEUE: begin
                if (fe_to_nvme_axi4[cp_fifo_q.ssd_cp_fe_id[FE_IDX-1:0]].ssd_cp_ready) begin
                    nvme_to_fe_axi4[cp_fifo_q.ssd_cp_fe_id[FE_IDX-1:0]].ssd_cp_valid = 1'b1;
                    nvme_to_fe_axi4[cp_fifo_q.ssd_cp_fe_id[FE_IDX-1:0]].ssd_cp_addr    = cp_fifo_q.ssd_cp_addr;
                    nvme_to_fe_axi4[cp_fifo_q.ssd_cp_fe_id[FE_IDX-1:0]].ssd_cp_fe_id   = cp_fifo_q.ssd_cp_fe_id;
                    nvme_to_fe_axi4[cp_fifo_q.ssd_cp_fe_id[FE_IDX-1:0]].ssd_cp_be_id   = cp_fifo_q.ssd_cp_be_id;
                end
            end
            default: begin

            end
        endcase

    //------------------------------------------------------
        bk_fifo_wrreq = 1'b0;

        for (int i=0; i<BE_CH; i++) begin
            nvme_to_be_axi4[i].ssd_bf_ready = 1'b0;
        end

        unique case(state_bk_in)
            STATE_IDLE: begin
                if (!bk_fifo_wrfull) begin
                    for (int i=0; i<BE_CH; i++) begin
                        if (be_to_nvme_axi4[i].ssd_bf_valid) begin
                            nvme_to_be_axi4[i].ssd_bf_ready = 1'b1;
                            break;
                        end
                    end
                end
            end
            STATE_ENQUEUE: begin
                bk_fifo_wrreq = 1'b1;
            end
            default: begin

            end
        endcase

    //------------------------------------------------------
        bk_fifo_rdreq = 1'b0;
        for (int i=0; i<FE_CH; i++) begin
            nvme_to_fe_axi4[i].ssd_bf_valid = 1'b0;
            nvme_to_fe_axi4[i].ssd_bf_addr  = '0;
            nvme_to_fe_axi4[i].ssd_bf_be_id = '0;
            nvme_to_fe_axi4[i].ssd_bf_fe_id = '0;
        end

        unique case(state_bk_out)
            STATE_IDLE: begin
                if (!bk_fifo_rdempty) begin
                    bk_fifo_rdreq = 1'b1;
                end
            end
            STATE_DEQUEUE: begin
                if (fe_to_nvme_axi4[bk_fifo_q.ssd_bf_fe_id[FE_IDX-1:0]].ssd_bf_ready) begin
                    nvme_to_fe_axi4[bk_fifo_q.ssd_bf_fe_id[FE_IDX-1:0]].ssd_bf_valid  = 1'b1;
                    nvme_to_fe_axi4[bk_fifo_q.ssd_bf_fe_id[FE_IDX-1:0]].ssd_bf_addr   = bk_fifo_q.ssd_bf_addr;
                    nvme_to_fe_axi4[bk_fifo_q.ssd_bf_fe_id[FE_IDX-1:0]].ssd_bf_be_id  = bk_fifo_q.ssd_bf_be_id;
                    nvme_to_fe_axi4[bk_fifo_q.ssd_bf_fe_id[FE_IDX-1:0]].ssd_bf_fe_id  = bk_fifo_q.ssd_bf_fe_id;
                end
            end
            default: begin

            end
        endcase
    
    //------------------------------------------------------
        ack_fifo_wrreq = 1'b0;

        for (int i=0; i<FE_CH; i++) begin
            nvme_to_fe_axi4[i].ssd_ack_ready = 1'b0;
        end

        unique case(state_ack_in)
            STATE_IDLE: begin
                if (!ack_fifo_wrfull) begin
                    for (int i=0; i<FE_CH; i++) begin
                        if (fe_to_nvme_axi4[i].ssd_ack_valid) begin
                            nvme_to_fe_axi4[i].ssd_ack_ready = 1'b1;
                            break;
                        end
                    end
                end
            end
            STATE_ENQUEUE: begin
                ack_fifo_wrreq = 1'b1;
            end
            default: begin

            end
        endcase

    //------------------------------------------------------
        ack_fifo_rdreq = 1'b0;
        for (int i=0; i<BE_CH; i++) begin
            nvme_to_be_axi4[i].ssd_ack_valid = 1'b0;
            nvme_to_be_axi4[i].ssd_ack_be_id = 12'b0;
        end

        unique case(state_ack_out)
            STATE_IDLE: begin
                if (!ack_fifo_rdempty) begin
                    ack_fifo_rdreq = 1'b1;
                end
            end
            STATE_DEQUEUE: begin
                if (be_to_nvme_axi4[ack_fifo_q.ssd_ack_be_id[BE_IDX-1:0]].ssd_ack_ready) begin
                    nvme_to_be_axi4[ack_fifo_q.ssd_ack_be_id[BE_IDX-1:0]].ssd_ack_valid = 1'b1;
                    nvme_to_be_axi4[ack_fifo_q.ssd_ack_be_id[BE_IDX-1:0]].ssd_ack_be_id = ack_fifo_q.ssd_ack_be_id;
                end
            end
            default: begin

            end
        endcase
    //------------------------------------------------------
        rl_fifo_wrreq = 1'b0;

        for (int i=0; i<FE_CH; i++) begin
            nvme_to_fe_axi4[i].ssd_rl_ready = 1'b0;
        end

        unique case(state_rl_in)
            STATE_IDLE: begin
                if (!rl_fifo_wrfull) begin
                    for (int i=0; i<FE_CH; i++) begin
                        if (fe_to_nvme_axi4[i].ssd_rl_valid) begin
                            nvme_to_fe_axi4[i].ssd_rl_ready = 1'b1;
                            break;
                        end
                    end
                end
            end
            STATE_ENQUEUE: begin
                rl_fifo_wrreq = 1'b1;
            end
            default: begin

            end
        endcase
    //------------------------------------------------------
        rl_fifo_rdreq = 1'b0;
        for (int i=0; i<BE_CH; i++) begin
            nvme_to_be_axi4[i].ssd_rl_valid = 1'b0;
            nvme_to_be_axi4[i].ssd_rl_be_id = 12'b0;
        end

        unique case(state_rl_out)
            STATE_IDLE: begin
                if (!rl_fifo_rdempty) begin
                    rl_fifo_rdreq = 1'b1;
                end
            end
            STATE_DEQUEUE: begin
                if (be_to_nvme_axi4[rl_fifo_q.ssd_rl_be_id[BE_IDX-1:0]].ssd_rl_ready) begin
                    nvme_to_be_axi4[rl_fifo_q.ssd_rl_be_id[BE_IDX-1:0]].ssd_rl_valid = 1'b1;
                    nvme_to_be_axi4[rl_fifo_q.ssd_rl_be_id[BE_IDX-1:0]].ssd_rl_be_id = rl_fifo_q.ssd_rl_be_id;
                end
            end
            default: begin

            end
        endcase
    end



endmodule : nvme_admin