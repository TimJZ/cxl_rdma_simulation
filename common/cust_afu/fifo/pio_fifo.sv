module pio_fifo 
import ed_mc_axi_if_pkg::*;
#(
    parameter DQ_CH,
    parameter DQ_IDX = log2ceil(DQ_CH)
)
(
    input logic axi4_mm_clk,
    input logic axi4_mm_rst_n,

    //to pio
    output logic            sqdb_valid,
    output logic [63:0]     sqdb_tail,
    input logic             sqdb_ready,

    output logic            cqdb_valid,
    output logic [63:0]     cqdb_head,
    input logic             cqdb_ready,

    //to back_end
    input logic             sqdb_valid_ch     [DQ_CH-1:0],
    input logic [63:0]      sqdb_tail_ch      [DQ_CH-1:0],
    output logic            sqdb_ready_ch     [DQ_CH-1:0],

    input logic             cqdb_valid_ch     [DQ_CH-1:0],
    input logic [63:0]      cqdb_head_ch      [DQ_CH-1:0],
    output logic            cqdb_ready_ch     [DQ_CH-1:0]
);

enum logic [4:0] {
    STATE_IDLE,
    STATE_RUN,
    STATE_RUN_1
} state[1:0], next_state[1:0];

logic [DQ_IDX-1:0] sq_arbiter_sel;
logic [DQ_IDX-1:0] cq_arbiter_sel;

//SQDB
always_ff @(posedge axi4_mm_clk) begin
    if (!axi4_mm_rst_n) begin
        state[0] <= STATE_IDLE;
        sq_arbiter_sel <= '0;

        sqdb_valid    <= 1'b0;
        for (int i=0; i<DQ_CH; i++) begin
            sqdb_ready_ch[i] <= 1'b0;
        end
    end
    else begin
        state[0] <= next_state[0];

        unique case(state[0])
            STATE_IDLE: begin
                for (int i=0; i<DQ_CH; i++) begin
                    if (sqdb_valid_ch[i]) begin
                        sq_arbiter_sel <= i;
                        sqdb_valid    <= sqdb_valid_ch[i];
                        sqdb_tail     <= {i[DQ_IDX-1:0], {(32-DQ_IDX){1'b0}}, sqdb_tail_ch[i][31:0]};
                        break;
                    end
                end
                for (int i=0; i<DQ_CH; i++) begin
                    sqdb_ready_ch[i] <= 1'b0;
                end
            end
            STATE_RUN: begin
                if (sqdb_valid && sqdb_ready) begin
                    sqdb_valid <= 1'b0;
                end

                sqdb_ready_ch[sq_arbiter_sel] <= sqdb_ready;
            end
            STATE_RUN_1: begin
                sqdb_ready_ch[sq_arbiter_sel] <= sqdb_ready;
            end
        endcase
    end
end

// always_comb begin
//     sqdb_valid        = 1'b0;
//     sqdb_tail         = 64'b0;

//     for (int i=0; i<DQ_CH; i++) begin
//         sqdb_ready_ch[i]     = 1'b0;
//     end

//     unique case(state[0])
//         STATE_IDLE: begin

//         end
//         STATE_RUN: begin
//             // sqdb_valid    = sqdb_valid_ch[sq_arbiter_sel];
//             // sqdb_tail     = {sq_arbiter_sel, 30'b0, sqdb_tail_ch[sq_arbiter_sel][31:0]};

//             // for (int i = 0; i < DQ_CH; i++) begin
//             //     sqdb_ready_ch[i] = '0;
//             // end
//             // sqdb_ready_ch[sq_arbiter_sel] = sqdb_ready;
//             unique case(sq_arbiter_sel)
//                 2'b00: begin 
//                     sqdb_valid    = sqdb_valid_ch[0];
//                     sqdb_tail     = {2'b00, 30'b0, sqdb_tail_ch[0][31:0]};
//                     sqdb_ready_ch[0] = sqdb_ready;
//                 end
//                 2'b01: begin
//                     sqdb_valid    = sqdb_valid_ch[1];
//                     sqdb_tail     = {2'b01, 30'b0, sqdb_tail_ch[1][31:0]};
//                     sqdb_ready_ch[1] = sqdb_ready;
//                 end
//                 2'b10: begin 
//                     sqdb_valid    = sqdb_valid_ch[2];
//                     sqdb_tail     = {2'b10, 30'b0, sqdb_tail_ch[2][31:0]};
//                     sqdb_ready_ch[2] = sqdb_ready;
//                 end
//                 2'b11: begin
//                     sqdb_valid    = sqdb_valid_ch[3];
//                     sqdb_tail     = {2'b11, 30'b0, sqdb_tail_ch[3][31:0]};
//                     sqdb_ready_ch[3] = sqdb_ready;
//                 end
//                 default: begin

//                 end
//             endcase
//         end
//         default: begin

//         end
//     endcase

// end


always_comb begin
    next_state[0] = STATE_IDLE;
    unique case(state[0])
        STATE_IDLE: begin
            next_state[0] = STATE_IDLE;
            for (int i=0; i<DQ_CH; i++) begin
                if (sqdb_valid_ch[i]) begin
                    next_state[0] = STATE_RUN;
                    break;
                end
            end
        end
        STATE_RUN: begin
            if (sqdb_valid && sqdb_ready) begin
                next_state[0] = STATE_RUN_1;
            end
            else begin
                next_state[0] = STATE_RUN;
            end
        end
        STATE_RUN_1: begin
            if (!sqdb_ready) begin
                next_state[0] = STATE_IDLE;
            end
            else begin
                next_state[0] = STATE_RUN_1;
            end
        end
        default: begin

        end
    endcase
end

//CQDB
always_ff @(posedge axi4_mm_clk) begin
    if (!axi4_mm_rst_n) begin
        state[1] <= STATE_IDLE;
        cq_arbiter_sel <= '0;

        cqdb_valid <= 1'b0;
        for (int i=0; i<DQ_CH; i++) begin
            cqdb_ready_ch[i] <= 1'b0;
        end
    end
    else begin
        state[1] <= next_state[1];

        unique case(state[1])
            STATE_IDLE: begin
                for (int i=0; i<DQ_CH; i++) begin
                    if (cqdb_valid_ch[i]) begin
                        cq_arbiter_sel <= i;
                        cqdb_valid    <= cqdb_valid_ch[i];
                        cqdb_head     <= {i[DQ_IDX-1:0], {(32-DQ_IDX){1'b0}}, cqdb_head_ch[i][31:0]};
                        break;
                    end
                end
                for (int i=0; i<DQ_CH; i++) begin
                    cqdb_ready_ch[i] <= 1'b0;
                end
            end
            STATE_RUN: begin
                if (cqdb_valid && cqdb_ready) begin
                    cqdb_valid <= 1'b0;
                end
                cqdb_ready_ch[cq_arbiter_sel] <= cqdb_ready;
            end
            STATE_RUN_1: begin
                cqdb_ready_ch[cq_arbiter_sel] <= cqdb_ready;
            end
            default: begin

            end
        endcase
    end
end

// always_comb begin
//     cqdb_valid        = 1'b0;
//     cqdb_head         = 64'b0;

//     for (int i=0; i<DQ_CH; i++) begin
//         cqdb_ready_ch[i]     = 1'b0;
//     end

//     unique case(state[1])
//         STATE_IDLE: begin

//         end
//         STATE_RUN: begin
//             // cqdb_valid    = cqdb_valid_ch[cq_arbiter_sel];
//             // cqdb_head     = {cq_arbiter_sel, 30'b0, cqdb_head_ch[cq_arbiter_sel][31:0]};

//             // for (int i = 0; i < DQ_CH; i++) begin
//             //     cqdb_ready_ch[i] = '0;
//             // end    
//             // cqdb_ready_ch[cq_arbiter_sel] = cqdb_ready;
//             unique case(cq_arbiter_sel)
//                 2'b00: begin 
//                     cqdb_valid    = cqdb_valid_ch[0];
//                     cqdb_head     = {2'b00, 30'b0, cqdb_head_ch[0][31:0]};
//                     cqdb_ready_ch[0] = cqdb_ready;
//                 end
//                 2'b01: begin
//                     cqdb_valid    = cqdb_valid_ch[1];
//                     cqdb_head     = {2'b01, 30'b0, cqdb_head_ch[1][31:0]};
//                     cqdb_ready_ch[1] = cqdb_ready;
//                 end
//                 2'b10: begin
//                     cqdb_valid    = cqdb_valid_ch[2];
//                     cqdb_head     = {2'b10, 30'b0, cqdb_head_ch[2][31:0]};
//                     cqdb_ready_ch[2] = cqdb_ready;
//                 end
//                 2'b11: begin
//                     cqdb_valid    = cqdb_valid_ch[3];
//                     cqdb_head     = {2'b11, 30'b0, cqdb_head_ch[3][31:0]};
//                     cqdb_ready_ch[3] = cqdb_ready;
//                 end
//                 default: begin

//                 end
//             endcase
//         end
//         default: begin

//         end
//     endcase

// end


always_comb begin
    next_state[1] = STATE_IDLE;
    unique case(state[1])
        STATE_IDLE: begin
            next_state[1] = STATE_IDLE;
            for (int i=0; i<DQ_CH; i++) begin
                if (cqdb_valid_ch[i]) begin
                    next_state[1] = STATE_RUN;
                    break;
                end
            end
        end
        STATE_RUN: begin
            if (cqdb_valid && cqdb_ready) begin
                next_state[1] = STATE_RUN_1;
            end
            else begin
                next_state[1] = STATE_RUN;
            end
        end
        STATE_RUN_1: begin
            if (!cqdb_ready) begin
                next_state[1] = STATE_IDLE;
            end
            else begin
                next_state[1] = STATE_RUN_1;
            end
        end
        default: begin

        end
    endcase
end



endmodule