module afu_fifo 
import ed_mc_axi_if_pkg::*;
#(  parameter MC_CH = 2,
    parameter DQ_CH = 2,
    parameter DQ_IDX = log2ceil(DQ_CH)
)
(
    input logic axi4_mm_clk,
    input logic axi4_mm_rst_n,

    //from afu_nvme
    input ed_mc_axi_if_pkg::t_from_mc_axi4_extended [MC_CH-1:0] mc2iafu_from_nvme_axi4_ch [DQ_CH-1:0],
    output ed_mc_axi_if_pkg::t_to_mc_axi4_extended [MC_CH-1:0] iafu2mc_to_nvme_axi4_ch [DQ_CH-1:0],

    //to afu_top
    output ed_mc_axi_if_pkg::t_from_mc_axi4 [MC_CH-1:0] mc2iafu_from_nvme_axi4,
    input ed_mc_axi_if_pkg::t_to_mc_axi4 [MC_CH-1:0] iafu2mc_to_nvme_axi4,

    //m5 interface
    input logic m5_query_en,
    input logic [63:0] m5_interval,

    output logic [63:0] pf_in_flight_cmd_0,
    output logic [63:0] pf_in_flight_cmd_1
);

logic [2:0] arid_ch_0_array[255:0];
logic [2:0] arid_ch_1_array[255:0];
logic [2:0] crid_ch_0_array[255:0];
logic [2:0] crid_ch_1_array[255:0];
logic arid_ch_0_valid;
logic arid_ch_1_valid;
logic crid_ch_0_valid;
logic crid_ch_1_valid;
logic [7:0] arid_ch_0_reg;
logic [7:0] arid_ch_1_reg;
logic [7:0] crid_ch_0_reg;
logic [7:0] crid_ch_1_reg;

logic [2:0] awid_ch_0_array[255:0];
logic [2:0] awid_ch_1_array[255:0];
logic [2:0] bid_ch_0_array[255:0];
logic [2:0] bid_ch_1_array[255:0];
logic awid_ch_0_valid;
logic awid_ch_1_valid;
logic bid_ch_0_valid;
logic bid_ch_1_valid;
logic [7:0] awid_ch_0_reg;
logic [7:0] awid_ch_1_reg;
logic [7:0] bid_ch_0_reg;
logic [7:0] bid_ch_1_reg;

(* preserve_for_debug *) logic awid_ch_0_used_array [255:0];
(* preserve_for_debug *) logic awid_ch_1_used_array [255:0];

(* preserve_for_debug *) logic arid_ch_0_used_array [255:0];
(* preserve_for_debug *) logic arid_ch_1_used_array [255:0];

//M5 module
localparam ADDR_SIZE = 37;
localparam PAGE_ADDR_SIZE = 25;
localparam CNT_SIZE = 14;
localparam W = 16*1024;
localparam W_UNIT = 4096;
localparam NUM_SKETCH = W / W_UNIT;
localparam SKETCH_INDEX_SIZE = $clog2(NUM_SKETCH);
localparam COLUMN_INDEX_SIZE = $clog2(W_UNIT);
localparam NUM_HASH = 4;
localparam HASH_SIZE = $clog2(W);
localparam NUM_ENTRY = 25;
localparam INDEX_SIZE = 5;

(* preserve_for_debug *)  logic page_query_en;
(* preserve_for_debug *)  logic page_query_ready;
(* preserve_for_debug *)  logic page_mig_addr_en;
(* preserve_for_debug *)  logic [ADDR_SIZE-1:0] page_mig_addr;
(* preserve_for_debug *)  logic page_mig_addr_ready;
(* preserve_for_debug *)  logic mem_chan_rd_en;

logic [ADDR_SIZE-1:0] csr_addr_ub;
logic [ADDR_SIZE-1:0] csr_addr_lb;

logic m5_addr_valid[MC_CH-1:0];
logic m5_addr_ready[MC_CH-1:0];
ed_mc_axi_if_pkg::t_to_mc_axi4_extended m5_addr_reg;

logic [31:0] m5_delay_cnt;

m5_pkg::queue_struct_t iafu2mc_to_nvme_axi4_m5;

enum logic [2:0] {
    STATE_IDLE,
    STATE_QUERY,
    STATE_FETCH,
    STATE_ISSUE,
    STATE_WAIT
}   m5_state, m5_next_state;
(* preserve_for_debug *) logic [31:0] pf_in_flight_aw_0;
(* preserve_for_debug *) logic [31:0] pf_in_flight_aw_1;
(* preserve_for_debug *) logic [31:0] pf_in_flight_ar_0;
(* preserve_for_debug *) logic [31:0] pf_in_flight_ar_1;

genvar i;
genvar z;
generate
    for (i=0; i<MC_CH; i=i+1) begin
        logic [520:0] rfifo_data;
        logic rfifo_wrreq   ;
        logic rfifo_rdreq   ;
        logic rfifo_full    ;
        logic rfifo_empty   ;

        logic [8:0] wfifo_data;
        logic wfifo_wrreq   ;
        logic wfifo_rdreq   ;
        logic wfifo_full    ;
        logic wfifo_empty   ;

        ed_mc_axi_if_pkg::t_to_mc_axi4_extended ififo_data;
        ed_mc_axi_if_pkg::t_to_mc_axi4_extended ififo_q;
        logic ififo_wrreq   ;
        logic ififo_rdreq   ;
        logic ififo_full    ;
        logic ififo_empty   ;

        logic arid_used_array [255:0];
        logic awid_used_array [255:0];
        logic [31:0] awid_inflight;
        logic [31:0] arid_inflight;
        // logic [DQ_IDX-1:0] rfifo_dq_idx;
        // logic [DQ_IDX-1:0] wfifo_dq_idx; 
        if (i==0) begin
            assign arid_used_array = arid_ch_0_used_array;
            assign awid_used_array = awid_ch_0_used_array;
            assign awid_inflight = pf_in_flight_aw_0;
            assign arid_inflight = pf_in_flight_ar_0;
        end
        else begin
            assign arid_used_array = arid_ch_1_used_array;
            assign awid_used_array = awid_ch_1_used_array;
            assign awid_inflight = pf_in_flight_aw_1;
            assign arid_inflight = pf_in_flight_ar_1;
        end

        logic [7:0] arid_index;
        logic [7:0] awid_index;

        logic arid_status;
        logic awid_status;

        logic m5_addr_valid_ch;
        logic m5_addr_ready_ch;

        logic m5_valid;

        assign m5_addr_valid_ch = m5_addr_valid[i];
        assign m5_addr_ready[i] = m5_addr_ready_ch;

        enum logic [1:0] {
            STATE_IDLE,
            STATE_CHECK,
            STATE_RUN
        } r_state, r_next_state, 
        w_state, w_next_state, 
        i_state, i_next_state,
        r_state_1, r_next_state_1, 
        w_state_1, w_next_state_1,
        i_state_1, i_next_state_1;

        logic ignore_0, ignore_1;

        //to wrapper
        ed_mc_axi_if_pkg::t_from_mc_axi4_extended mc2iafu_from_nvme_axi4_ch_i [DQ_CH-1:0]; 
        ed_mc_axi_if_pkg::t_to_mc_axi4_extended iafu2mc_to_nvme_axi4_ch_i [DQ_CH-1:0]; 

        ed_mc_axi_if_pkg::t_from_mc_axi4_extended mc2iafu_from_nvme_axi4_ch_i_mux; 

        //to IP
        ed_mc_axi_if_pkg::t_from_mc_axi4 mc2iafu_from_nvme_axi4_i;
        ed_mc_axi_if_pkg::t_to_mc_axi4 iafu2mc_to_nvme_axi4_i;

        assign mc2iafu_from_nvme_axi4[i] = mc2iafu_from_nvme_axi4_i;
        assign iafu2mc_to_nvme_axi4_i = iafu2mc_to_nvme_axi4[i];

        //TODO
        for (z = 0; z < DQ_CH; z++) begin : gen_block
            assign iafu2mc_to_nvme_axi4_ch[z][i] = iafu2mc_to_nvme_axi4_ch_i[z];
        end

        afu_rfifo_async r_fifo_inst(
            .data   (rfifo_data     ),
            .wrreq  (rfifo_wrreq    ),
            .rdreq  (rfifo_rdreq    ),
            .wrclk  (axi4_mm_clk),
            .rdclk  (axi4_mm_clk),
            .aclr   (1'b0),
            .q      ({mc2iafu_from_nvme_axi4_i.rdata, ignore_0, mc2iafu_from_nvme_axi4_i.rid}),
            .wrfull (rfifo_full     ),
            .rdempty(rfifo_empty    )
        );

        afu_wfifo_async w_fifo_inst(
            .data   (wfifo_data     ),
            .wrreq  (wfifo_wrreq    ),
            .rdreq  (wfifo_rdreq    ),
            .wrclk  (axi4_mm_clk),
            .rdclk  (axi4_mm_clk),
            .aclr   (1'b0),
            .q      ({ignore_1, mc2iafu_from_nvme_axi4_i.bid}),
            .wrfull (wfifo_full     ),
            .rdempty(wfifo_empty    )
        );

        nvme_to_fifo_extended i_fifo_inst(
            .data   (ififo_data     ),
            .wrreq  (ififo_wrreq    ),
            .rdreq  (ififo_rdreq    ),
            .wrclk  (axi4_mm_clk),
            .rdclk  (axi4_mm_clk),
            .aclr   (1'b0),
            .q      (ififo_q        ),
            .wrfull (ififo_full     ),
            .rdempty(ififo_empty    )
        );

        //input fifo enqueue
        always_ff @(posedge axi4_mm_clk) begin
            if (!axi4_mm_rst_n) begin
                ififo_data <= '0;
                m5_valid <= 1'b0;
                i_state <= STATE_IDLE;
            end
            else begin
                i_state <= i_next_state;

                arid_status <= arid_used_array[arid_index];
                awid_status <= awid_used_array[awid_index];

                unique case(i_state)
                    STATE_IDLE: begin
                        if (!ififo_full) begin
                            if (iafu2mc_to_nvme_axi4_i.arvalid) begin
                                ififo_data.bready <= iafu2mc_to_nvme_axi4_i.bready;
                                ififo_data.rready <= iafu2mc_to_nvme_axi4_i.rready;
                                
                                ififo_data.awid <= {1'b0, iafu2mc_to_nvme_axi4_i.awid};
                                ififo_data.awaddr <= iafu2mc_to_nvme_axi4_i.awaddr;
                                ififo_data.awlen <= iafu2mc_to_nvme_axi4_i.awlen;
                                ififo_data.awsize <= iafu2mc_to_nvme_axi4_i.awsize;
                                ififo_data.awburst <= iafu2mc_to_nvme_axi4_i.awburst;
                                ififo_data.awprot <= iafu2mc_to_nvme_axi4_i.awprot;
                                ififo_data.awqos <= iafu2mc_to_nvme_axi4_i.awqos;
                                ififo_data.awvalid <= iafu2mc_to_nvme_axi4_i.awvalid;
                                ififo_data.awcache <= iafu2mc_to_nvme_axi4_i.awcache;
                                ififo_data.awlock <= iafu2mc_to_nvme_axi4_i.awlock;
                                ififo_data.awregion <= iafu2mc_to_nvme_axi4_i.awregion;
                                ififo_data.awuser <= iafu2mc_to_nvme_axi4_i.awuser;

                                ififo_data.wdata <= iafu2mc_to_nvme_axi4_i.wdata;
                                ififo_data.wstrb <= iafu2mc_to_nvme_axi4_i.wstrb;
                                ififo_data.wlast <= iafu2mc_to_nvme_axi4_i.wlast;
                                ififo_data.wvalid <= iafu2mc_to_nvme_axi4_i.wvalid;
                                ififo_data.wuser <= iafu2mc_to_nvme_axi4_i.wuser;

                                ififo_data.arid <= {1'b0, iafu2mc_to_nvme_axi4_i.arid};
                                ififo_data.araddr <= iafu2mc_to_nvme_axi4_i.araddr;
                                ififo_data.arlen <= iafu2mc_to_nvme_axi4_i.arlen;
                                ififo_data.arsize <= iafu2mc_to_nvme_axi4_i.arsize;
                                ififo_data.arburst <= iafu2mc_to_nvme_axi4_i.arburst;
                                ififo_data.arprot <= iafu2mc_to_nvme_axi4_i.arprot;
                                ififo_data.arqos <= iafu2mc_to_nvme_axi4_i.arqos;
                                ififo_data.arvalid <= iafu2mc_to_nvme_axi4_i.arvalid;
                                ififo_data.arcache <= iafu2mc_to_nvme_axi4_i.arcache;
                                ififo_data.arlock <= iafu2mc_to_nvme_axi4_i.arlock;
                                ififo_data.arregion <= iafu2mc_to_nvme_axi4_i.arregion;
                                ififo_data.aruser <= iafu2mc_to_nvme_axi4_i.aruser;

                                arid_index <= iafu2mc_to_nvme_axi4_i.arid;
                            end
                            else if (iafu2mc_to_nvme_axi4_i.awvalid) begin
                                ififo_data.bready <= iafu2mc_to_nvme_axi4_i.bready;
                                ififo_data.rready <= iafu2mc_to_nvme_axi4_i.rready;
                                
                                ififo_data.awid <= {1'b0, iafu2mc_to_nvme_axi4_i.awid};
                                ififo_data.awaddr <= iafu2mc_to_nvme_axi4_i.awaddr;
                                ififo_data.awlen <= iafu2mc_to_nvme_axi4_i.awlen;
                                ififo_data.awsize <= iafu2mc_to_nvme_axi4_i.awsize;
                                ififo_data.awburst <= iafu2mc_to_nvme_axi4_i.awburst;
                                ififo_data.awprot <= iafu2mc_to_nvme_axi4_i.awprot;
                                ififo_data.awqos <= iafu2mc_to_nvme_axi4_i.awqos;
                                ififo_data.awvalid <= iafu2mc_to_nvme_axi4_i.awvalid;
                                ififo_data.awcache <= iafu2mc_to_nvme_axi4_i.awcache;
                                ififo_data.awlock <= iafu2mc_to_nvme_axi4_i.awlock;
                                ififo_data.awregion <= iafu2mc_to_nvme_axi4_i.awregion;
                                ififo_data.awuser <= iafu2mc_to_nvme_axi4_i.awuser;

                                ififo_data.wdata <= iafu2mc_to_nvme_axi4_i.wdata;
                                ififo_data.wstrb <= iafu2mc_to_nvme_axi4_i.wstrb;
                                ififo_data.wlast <= iafu2mc_to_nvme_axi4_i.wlast;
                                ififo_data.wvalid <= iafu2mc_to_nvme_axi4_i.wvalid;
                                ififo_data.wuser <= iafu2mc_to_nvme_axi4_i.wuser;

                                ififo_data.arid <= {1'b0, iafu2mc_to_nvme_axi4_i.arid};
                                ififo_data.araddr <= iafu2mc_to_nvme_axi4_i.araddr;
                                ififo_data.arlen <= iafu2mc_to_nvme_axi4_i.arlen;
                                ififo_data.arsize <= iafu2mc_to_nvme_axi4_i.arsize;
                                ififo_data.arburst <= iafu2mc_to_nvme_axi4_i.arburst;
                                ififo_data.arprot <= iafu2mc_to_nvme_axi4_i.arprot;
                                ififo_data.arqos <= iafu2mc_to_nvme_axi4_i.arqos;
                                ififo_data.arvalid <= iafu2mc_to_nvme_axi4_i.arvalid;
                                ififo_data.arcache <= iafu2mc_to_nvme_axi4_i.arcache;
                                ififo_data.arlock <= iafu2mc_to_nvme_axi4_i.arlock;
                                ififo_data.arregion <= iafu2mc_to_nvme_axi4_i.arregion;
                                ififo_data.aruser <= iafu2mc_to_nvme_axi4_i.aruser;

                                awid_index <= iafu2mc_to_nvme_axi4_i.awid;
                            end
                            else if (m5_addr_valid_ch) begin
                                ififo_data <= m5_addr_reg;
                                m5_valid <= 1'b1;
                            end
                        end
                    end
                    STATE_CHECK: begin
                        
                    end
                    STATE_RUN: begin
                        m5_valid <= 1'b0;
                    end
                    default: begin
                    
                    end
                endcase
            end
        end

        //input fifo dequeue
        always_ff @(posedge axi4_mm_clk) begin
            if (!axi4_mm_rst_n) begin
                i_state_1 <= STATE_IDLE;
            end
            else begin
                i_state_1 <= i_next_state_1;
                unique case(i_state_1)
                    STATE_IDLE: begin
                        
                    end
                    STATE_CHECK: begin

                    end
                    STATE_RUN: begin

                    end
                    default: begin
                    
                    end
                endcase
            end
        end

        //READ FIFO
        always_ff @(posedge axi4_mm_clk) begin
            if (!axi4_mm_rst_n) begin
                r_state_1 <= STATE_IDLE;
                rfifo_data <= '0;
                // rfifo_dq_idx <= '0;
            end
            else begin
                r_state_1 <= r_next_state_1;
                unique case(r_state_1)
                    STATE_IDLE: begin
                        if (!rfifo_full) begin
                            for (int j=0; j<DQ_CH; j++) begin
                                if (mc2iafu_from_nvme_axi4_ch_i[j].rvalid) begin
                                    rfifo_data <= {mc2iafu_from_nvme_axi4_ch_i[j].rdata, mc2iafu_from_nvme_axi4_ch_i[j].rid};
                                    // rfifo_dq_idx <= j;
                                    break;
                                end
                            end
                        end
                    end
                    STATE_RUN: begin

                    end
                    default: begin
                    
                    end
                endcase
            end
        end

        always_ff @(posedge axi4_mm_clk) begin
            if (!axi4_mm_rst_n) begin
                r_state <= STATE_IDLE;
            end
            else begin
                r_state <= r_next_state;
            end
        end

        //WRITE FIFO
        always_ff @(posedge axi4_mm_clk) begin
            if (!axi4_mm_rst_n) begin
                w_state_1 <= STATE_IDLE;
                wfifo_data <= '0;
                // wfifo_dq_idx <= '0;
            end
            else begin
                w_state_1 <= w_next_state_1;
                unique case(w_state_1)
                    STATE_IDLE: begin
                        if (!wfifo_full) begin
                            for (int j=0; j<DQ_CH; j++) begin
                                if (mc2iafu_from_nvme_axi4_ch_i[j].bvalid) begin
                                    wfifo_data <= {mc2iafu_from_nvme_axi4_ch_i[j].bid};
                                    // wfifo_dq_idx <= j;
                                    break;
                                end
                            end
                        end
                    end
                    STATE_RUN: begin

                    end
                    default: begin
                    
                    end
                endcase
            end
        end

        always_ff @(posedge axi4_mm_clk) begin
            if (!axi4_mm_rst_n) begin
                w_state <= STATE_IDLE;
            end
            else begin
                w_state <= w_next_state;
            end
        end

/*---------------------------------------------
Combination logic 
-------------------------------------------------*/
        always_comb begin
            //---------------------------------------------
            rfifo_wrreq  = 1'b0;

            for (int j=0; j<DQ_CH; j++) begin
                iafu2mc_to_nvme_axi4_ch_i[j].rready = 1'b0;
                iafu2mc_to_nvme_axi4_ch_i[j].bready = 1'b0;
            end

            unique case(r_state_1)
                STATE_IDLE: begin
                    if (!rfifo_full) begin
                        for (int j=0; j<DQ_CH; j++) begin
                            if (mc2iafu_from_nvme_axi4_ch_i[j].rvalid) begin
                                iafu2mc_to_nvme_axi4_ch_i[j].rready = 1'b1;
                                break;
                            end
                        end
                    end
                end
                STATE_RUN: begin
                    // iafu2mc_to_nvme_axi4_ch_i[rfifo_dq_idx].rready = 1'b1;
                    if (rfifo_data[8:0] == 9'h100) begin
                        rfifo_wrreq  = 1'b0;
                    end
                    else begin
                        rfifo_wrreq  = 1'b1;
                    end
                end
                default: begin
                
                end
            endcase

            //---------------------------------------------
            rfifo_rdreq = 1'b0;
            mc2iafu_from_nvme_axi4_i.rvalid = 1'b0;
            unique case(r_state) 
                STATE_IDLE: begin
                    if (!rfifo_empty) begin
                        rfifo_rdreq = 1'b1;
                    end
                end

                STATE_RUN: begin
                    mc2iafu_from_nvme_axi4_i.rvalid = 1'b1;
                end
                default: begin

                end
            endcase

            //---------------------------------------------
            wfifo_wrreq  = 1'b0;
            unique case(w_state_1)
                STATE_IDLE: begin
                    if (!wfifo_full) begin
                        for (int j=0; j<DQ_CH; j++) begin
                            if (mc2iafu_from_nvme_axi4_ch_i[j].bvalid) begin
                                // iafu2mc_to_nvme_axi4_ch_i[j].bready = 1'b1;
                                break;
                            end
                        end
                    end
                end
                STATE_RUN: begin
                    // iafu2mc_to_nvme_axi4_ch_i[wfifo_dq_idx].bready = 1'b1;
                    wfifo_wrreq  = 1'b1;
                end
                default: begin
                
                end
            endcase

            //---------------------------------------------
            wfifo_rdreq = 1'b0;
            mc2iafu_from_nvme_axi4_i.bvalid = 1'b0;
            unique case(w_state) 
                STATE_IDLE: begin
                    if (!wfifo_empty) begin
                        wfifo_rdreq = 1'b1;
                    end
                end

                STATE_RUN: begin
                    mc2iafu_from_nvme_axi4_i.bvalid = 1'b1;
                end
                default: begin

                end
            endcase

            //----------------------------------------------
            ififo_wrreq = 1'b0;
            mc2iafu_from_nvme_axi4_i.arready = 1'b0;
            mc2iafu_from_nvme_axi4_i.awready = 1'b0;
            mc2iafu_from_nvme_axi4_i.wready  = 1'b0;

            m5_addr_ready_ch = 1'b0;

            unique case(i_state) 
                STATE_IDLE: begin
                    // if (!ififo_full) begin
                        // if (iafu2mc_to_nvme_axi4_i.arvalid) begin
                        //     mc2iafu_from_nvme_axi4_i.arready = 1'b1;
                        // end
                        // else if (iafu2mc_to_nvme_axi4_i.awvalid) begin
                        //     mc2iafu_from_nvme_axi4_i.awready = 1'b1;
                        //     mc2iafu_from_nvme_axi4_i.wready  = 1'b1;
                        // end
                    // end
                end
                STATE_CHECK: begin
                    if (m5_valid) begin
                        m5_addr_ready_ch = 1'b1;
                    end
                end
                STATE_RUN: begin
                    if (ififo_data.arvalid) begin
                        if (m5_valid) begin
                            ififo_wrreq = 1'b1;
                        end
                        else if (arid_status) begin  //arid is being used

                        end
                        else begin
                            mc2iafu_from_nvme_axi4_i.arready = 1'b1;
                            ififo_wrreq = 1'b1;
                        end
                    end
                    else begin
                        if (awid_status) begin  //awid is being used

                        end
                        else begin
                            mc2iafu_from_nvme_axi4_i.awready = 1'b1;
                            mc2iafu_from_nvme_axi4_i.wready  = 1'b1;
                            ififo_wrreq = 1'b1;
                        end
                    end
                end
                default: begin

                end
            endcase



            //----------------------------------------------
            for (int j=0; j<DQ_CH; j++) begin
                mc2iafu_from_nvme_axi4_ch_i[j] = mc2iafu_from_nvme_axi4_ch[j][i];
            end

            for (int j=0; j<DQ_CH; j++) begin
                iafu2mc_to_nvme_axi4_ch_i[j].arid      = ififo_q.arid;
                iafu2mc_to_nvme_axi4_ch_i[j].araddr    = ififo_q.araddr;
                iafu2mc_to_nvme_axi4_ch_i[j].arlen     = ififo_q.arlen;
                iafu2mc_to_nvme_axi4_ch_i[j].arsize    = ififo_q.arsize;
                iafu2mc_to_nvme_axi4_ch_i[j].arburst   = ififo_q.arburst;
                iafu2mc_to_nvme_axi4_ch_i[j].arprot    = ififo_q.arprot;
                iafu2mc_to_nvme_axi4_ch_i[j].arqos     = ififo_q.arqos;
                iafu2mc_to_nvme_axi4_ch_i[j].arvalid   = 1'b0;
                iafu2mc_to_nvme_axi4_ch_i[j].arcache   = ififo_q.arcache;
                iafu2mc_to_nvme_axi4_ch_i[j].arlock    = ififo_q.arlock;
                iafu2mc_to_nvme_axi4_ch_i[j].arregion  = ififo_q.arregion;
                iafu2mc_to_nvme_axi4_ch_i[j].aruser    = ififo_q.aruser; 

                iafu2mc_to_nvme_axi4_ch_i[j].awid      = ififo_q.awid;
                iafu2mc_to_nvme_axi4_ch_i[j].awaddr    = ififo_q.awaddr;
                iafu2mc_to_nvme_axi4_ch_i[j].awlen     = ififo_q.awlen;
                iafu2mc_to_nvme_axi4_ch_i[j].awsize    = ififo_q.awsize;
                iafu2mc_to_nvme_axi4_ch_i[j].awburst   = ififo_q.awburst;
                iafu2mc_to_nvme_axi4_ch_i[j].awprot    = ififo_q.awprot;
                iafu2mc_to_nvme_axi4_ch_i[j].awqos     = ififo_q.awqos;
                iafu2mc_to_nvme_axi4_ch_i[j].awvalid   = 1'b0;
                iafu2mc_to_nvme_axi4_ch_i[j].awcache   = ififo_q.awcache;
                iafu2mc_to_nvme_axi4_ch_i[j].awlock    = ififo_q.awlock;
                iafu2mc_to_nvme_axi4_ch_i[j].awregion  = ififo_q.awregion;
                iafu2mc_to_nvme_axi4_ch_i[j].awuser    = ififo_q.awuser;

                iafu2mc_to_nvme_axi4_ch_i[j].wdata     = ififo_q.wdata;
                iafu2mc_to_nvme_axi4_ch_i[j].wstrb     = ififo_q.wstrb;
                iafu2mc_to_nvme_axi4_ch_i[j].wlast     = ififo_q.wlast;
                iafu2mc_to_nvme_axi4_ch_i[j].wvalid    = 1'b0;
                iafu2mc_to_nvme_axi4_ch_i[j].wuser     = ififo_q.wuser;
            end

            ififo_rdreq = 1'b0;
            mc2iafu_from_nvme_axi4_ch_i_mux.arready = 1'b0;
            mc2iafu_from_nvme_axi4_ch_i_mux.awready = 1'b0;
            mc2iafu_from_nvme_axi4_ch_i_mux.wready = 1'b0;

            unique case (i_state_1)
                STATE_IDLE: begin
                    if (!ififo_empty) begin
                        ififo_rdreq = 1'b1;
                    end
                end
                STATE_RUN: begin
                    //fifo2ch AR channel 
                    // unique case(ififo_q.araddr[11:9])
                    //     3'b000: begin 
                    //         iafu2mc_to_nvme_axi4_ch_i[0].arvalid    = ififo_q.arvalid;
                    //         mc2iafu_from_nvme_axi4_ch_i_mux.arready        = mc2iafu_from_nvme_axi4_ch_i[0].arready;
                    //     end
                    //     3'b001: begin 
                    //         iafu2mc_to_nvme_axi4_ch_i[1].arvalid    = ififo_q.arvalid;
                    //         mc2iafu_from_nvme_axi4_ch_i_mux.arready        = mc2iafu_from_nvme_axi4_ch_i[1].arready;
                    //     end
                    //     3'b010: begin 
                    //         iafu2mc_to_nvme_axi4_ch_i[2].arvalid    = ififo_q.arvalid;
                    //         mc2iafu_from_nvme_axi4_ch_i_mux.arready        = mc2iafu_from_nvme_axi4_ch_i[2].arready;
                    //     end
                    //     3'b011: begin 
                    //         iafu2mc_to_nvme_axi4_ch_i[3].arvalid    = ififo_q.arvalid;
                    //         mc2iafu_from_nvme_axi4_ch_i_mux.arready        = mc2iafu_from_nvme_axi4_ch_i[3].arready;
                    //     end
                    //     3'b100: begin 
                    //         iafu2mc_to_nvme_axi4_ch_i[4].arvalid    = ififo_q.arvalid;
                    //         mc2iafu_from_nvme_axi4_ch_i_mux.arready        = mc2iafu_from_nvme_axi4_ch_i[4].arready;
                    //     end
                    //     3'b101: begin 
                    //         iafu2mc_to_nvme_axi4_ch_i[5].arvalid    = ififo_q.arvalid;
                    //         mc2iafu_from_nvme_axi4_ch_i_mux.arready        = mc2iafu_from_nvme_axi4_ch_i[5].arready;
                    //     end
                    //     3'b110: begin 
                    //         iafu2mc_to_nvme_axi4_ch_i[6].arvalid    = ififo_q.arvalid;
                    //         mc2iafu_from_nvme_axi4_ch_i_mux.arready        = mc2iafu_from_nvme_axi4_ch_i[6].arready;
                    //     end
                    //     3'b111: begin 
                    //         iafu2mc_to_nvme_axi4_ch_i[7].arvalid    = ififo_q.arvalid;
                    //         mc2iafu_from_nvme_axi4_ch_i_mux.arready        = mc2iafu_from_nvme_axi4_ch_i[7].arready;
                    //     end
                    //     default: begin

                    //     end
                    // endcase

                    // unique case(ififo_q.araddr[10:9])
                    //     2'b00: begin 
                    //         iafu2mc_to_nvme_axi4_ch_i[0].arvalid    = ififo_q.arvalid;
                    //         mc2iafu_from_nvme_axi4_ch_i_mux.arready        = mc2iafu_from_nvme_axi4_ch_i[0].arready;
                    //     end
                    //     2'b01: begin 
                    //         iafu2mc_to_nvme_axi4_ch_i[1].arvalid    = ififo_q.arvalid;
                    //         mc2iafu_from_nvme_axi4_ch_i_mux.arready        = mc2iafu_from_nvme_axi4_ch_i[1].arready;
                    //     end
                    //     2'b10: begin 
                    //         iafu2mc_to_nvme_axi4_ch_i[2].arvalid    = ififo_q.arvalid;
                    //         mc2iafu_from_nvme_axi4_ch_i_mux.arready        = mc2iafu_from_nvme_axi4_ch_i[2].arready;
                    //     end
                    //     2'b11: begin 
                    //         iafu2mc_to_nvme_axi4_ch_i[3].arvalid    = ififo_q.arvalid;
                    //         mc2iafu_from_nvme_axi4_ch_i_mux.arready        = mc2iafu_from_nvme_axi4_ch_i[3].arready;
                    //     end
                    //     default: begin

                    //     end
                    // endcase
                    // unique case(ififo_q.araddr[9])
                    //     1'b0: begin 
                    //         iafu2mc_to_nvme_axi4_ch_i[0].arvalid    = ififo_q.arvalid;
                    //         mc2iafu_from_nvme_axi4_ch_i_mux.arready        = mc2iafu_from_nvme_axi4_ch_i[0].arready;
                    //     end
                    //     1'b1: begin 
                    //         iafu2mc_to_nvme_axi4_ch_i[1].arvalid    = ififo_q.arvalid;
                    //         mc2iafu_from_nvme_axi4_ch_i_mux.arready        = mc2iafu_from_nvme_axi4_ch_i[1].arready;
                    //     end
                    //     default: begin

                    //     end
                    // endcase
                    iafu2mc_to_nvme_axi4_ch_i[7].arvalid    = ififo_q.arvalid;
                    mc2iafu_from_nvme_axi4_ch_i_mux.arready        = mc2iafu_from_nvme_axi4_ch_i[7].arready;

                    //fifo2ch AW channel
                    // unique case(ififo_q.awaddr[11:9])
                    //     3'b000: begin 
                    //         iafu2mc_to_nvme_axi4_ch_i[0].awvalid    = ififo_q.awvalid;
                    //         mc2iafu_from_nvme_axi4_ch_i_mux.awready        = mc2iafu_from_nvme_axi4_ch_i[0].awready;
                    //     end
                    //     3'b001: begin 
                    //         iafu2mc_to_nvme_axi4_ch_i[1].awvalid    = ififo_q.awvalid;
                    //         mc2iafu_from_nvme_axi4_ch_i_mux.awready        = mc2iafu_from_nvme_axi4_ch_i[1].awready;
                    //     end
                    //     3'b010: begin 
                    //         iafu2mc_to_nvme_axi4_ch_i[2].awvalid    = ififo_q.awvalid;
                    //         mc2iafu_from_nvme_axi4_ch_i_mux.awready        = mc2iafu_from_nvme_axi4_ch_i[2].awready;
                    //     end
                    //     3'b011: begin 
                    //         iafu2mc_to_nvme_axi4_ch_i[3].awvalid    = ififo_q.awvalid;
                    //         mc2iafu_from_nvme_axi4_ch_i_mux.awready        = mc2iafu_from_nvme_axi4_ch_i[3].awready;
                    //     end
                    //     3'b100: begin 
                    //         iafu2mc_to_nvme_axi4_ch_i[4].awvalid    = ififo_q.awvalid;
                    //         mc2iafu_from_nvme_axi4_ch_i_mux.awready        = mc2iafu_from_nvme_axi4_ch_i[4].awready;
                    //     end
                    //     3'b101: begin 
                    //         iafu2mc_to_nvme_axi4_ch_i[5].awvalid    = ififo_q.awvalid;
                    //         mc2iafu_from_nvme_axi4_ch_i_mux.awready        = mc2iafu_from_nvme_axi4_ch_i[5].awready;
                    //     end
                    //     3'b110: begin 
                    //         iafu2mc_to_nvme_axi4_ch_i[6].awvalid    = ififo_q.awvalid;
                    //         mc2iafu_from_nvme_axi4_ch_i_mux.awready        = mc2iafu_from_nvme_axi4_ch_i[6].awready;
                    //     end
                    //     3'b111: begin 
                    //         iafu2mc_to_nvme_axi4_ch_i[7].awvalid    = ififo_q.awvalid;
                    //         mc2iafu_from_nvme_axi4_ch_i_mux.awready        = mc2iafu_from_nvme_axi4_ch_i[7].awready;
                    //     end
                    //     default: begin

                    //     end
                    // endcase

                    // unique case(ififo_q.awaddr[10:9])
                    //     2'b00: begin 
                    //         iafu2mc_to_nvme_axi4_ch_i[0].awvalid    = ififo_q.awvalid;
                    //         mc2iafu_from_nvme_axi4_ch_i_mux.awready        = mc2iafu_from_nvme_axi4_ch_i[0].awready;
                    //     end
                    //     2'b01: begin 
                    //         iafu2mc_to_nvme_axi4_ch_i[1].awvalid    = ififo_q.awvalid;
                    //         mc2iafu_from_nvme_axi4_ch_i_mux.awready        = mc2iafu_from_nvme_axi4_ch_i[1].awready;
                    //     end
                    //     2'b10: begin 
                    //         iafu2mc_to_nvme_axi4_ch_i[2].awvalid    = ififo_q.awvalid;
                    //         mc2iafu_from_nvme_axi4_ch_i_mux.awready        = mc2iafu_from_nvme_axi4_ch_i[2].awready;
                    //     end
                    //     2'b11: begin 
                    //         iafu2mc_to_nvme_axi4_ch_i[3].awvalid    = ififo_q.awvalid;
                    //         mc2iafu_from_nvme_axi4_ch_i_mux.awready        = mc2iafu_from_nvme_axi4_ch_i[3].awready;
                    //     end
                    //     default: begin

                    //     end
                    // endcase
                    // unique case(ififo_q.awaddr[9])
                    //     1'b0: begin 
                    //         iafu2mc_to_nvme_axi4_ch_i[0].awvalid    = ififo_q.awvalid;
                    //         mc2iafu_from_nvme_axi4_ch_i_mux.awready        = mc2iafu_from_nvme_axi4_ch_i[0].awready;
                    //     end
                    //     1'b1: begin 
                    //         iafu2mc_to_nvme_axi4_ch_i[1].awvalid    = ififo_q.awvalid;
                    //         mc2iafu_from_nvme_axi4_ch_i_mux.awready        = mc2iafu_from_nvme_axi4_ch_i[1].awready;
                    //     end
                    //     default: begin

                    //     end
                    // endcase
                    iafu2mc_to_nvme_axi4_ch_i[7].awvalid    = ififo_q.awvalid;
                    mc2iafu_from_nvme_axi4_ch_i_mux.awready        = mc2iafu_from_nvme_axi4_ch_i[7].awready;

                    //fifo2ch W channel
                    // unique case(ififo_q.awaddr[11:9])
                    //     3'b000: begin 
                    //         iafu2mc_to_nvme_axi4_ch_i[0].wvalid  = ififo_q.wvalid;
                    //         mc2iafu_from_nvme_axi4_ch_i_mux.wready         = mc2iafu_from_nvme_axi4_ch_i[0].wready;
                    //     end
                    //     3'b001: begin 
                    //         iafu2mc_to_nvme_axi4_ch_i[1].wvalid  = ififo_q.wvalid;
                    //         mc2iafu_from_nvme_axi4_ch_i_mux.wready         = mc2iafu_from_nvme_axi4_ch_i[1].wready;
                    //     end
                    //     3'b010: begin 
                    //         iafu2mc_to_nvme_axi4_ch_i[2].wvalid  = ififo_q.wvalid;
                    //         mc2iafu_from_nvme_axi4_ch_i_mux.wready         = mc2iafu_from_nvme_axi4_ch_i[2].wready;
                    //     end
                    //     3'b011: begin 
                    //         iafu2mc_to_nvme_axi4_ch_i[3].wvalid  = ififo_q.wvalid;
                    //         mc2iafu_from_nvme_axi4_ch_i_mux.wready         = mc2iafu_from_nvme_axi4_ch_i[3].wready;
                    //     end
                    //     3'b100: begin 
                    //         iafu2mc_to_nvme_axi4_ch_i[4].wvalid  = ififo_q.wvalid;
                    //         mc2iafu_from_nvme_axi4_ch_i_mux.wready         = mc2iafu_from_nvme_axi4_ch_i[4].wready;
                    //     end
                    //     3'b101: begin 
                    //         iafu2mc_to_nvme_axi4_ch_i[5].wvalid  = ififo_q.wvalid;
                    //         mc2iafu_from_nvme_axi4_ch_i_mux.wready         = mc2iafu_from_nvme_axi4_ch_i[5].wready;
                    //     end
                    //     3'b110: begin 
                    //         iafu2mc_to_nvme_axi4_ch_i[6].wvalid  = ififo_q.wvalid;
                    //         mc2iafu_from_nvme_axi4_ch_i_mux.wready         = mc2iafu_from_nvme_axi4_ch_i[6].wready;
                    //     end
                    //     3'b111: begin 
                    //         iafu2mc_to_nvme_axi4_ch_i[7].wvalid  = ififo_q.wvalid;
                    //         mc2iafu_from_nvme_axi4_ch_i_mux.wready         = mc2iafu_from_nvme_axi4_ch_i[7].wready;
                    //     end
                    //     default: begin

                    //     end
                    // endcase

                    // unique case(ififo_q.awaddr[10:9])
                    //     2'b00: begin 
                    //         iafu2mc_to_nvme_axi4_ch_i[0].wvalid  = ififo_q.wvalid;
                    //         mc2iafu_from_nvme_axi4_ch_i_mux.wready         = mc2iafu_from_nvme_axi4_ch_i[0].wready;
                    //     end
                    //     2'b01: begin 
                    //         iafu2mc_to_nvme_axi4_ch_i[1].wvalid  = ififo_q.wvalid;
                    //         mc2iafu_from_nvme_axi4_ch_i_mux.wready         = mc2iafu_from_nvme_axi4_ch_i[1].wready;
                    //     end
                    //     2'b10: begin 
                    //         iafu2mc_to_nvme_axi4_ch_i[2].wvalid  = ififo_q.wvalid;
                    //         mc2iafu_from_nvme_axi4_ch_i_mux.wready         = mc2iafu_from_nvme_axi4_ch_i[2].wready;
                    //     end
                    //     2'b11: begin 
                    //         iafu2mc_to_nvme_axi4_ch_i[3].wvalid  = ififo_q.wvalid;
                    //         mc2iafu_from_nvme_axi4_ch_i_mux.wready         = mc2iafu_from_nvme_axi4_ch_i[3].wready;
                    //     end
                    //     default: begin

                    //     end
                    // endcase
                    // unique case(ififo_q.awaddr[9])
                    //     1'b0: begin 
                    //         iafu2mc_to_nvme_axi4_ch_i[0].wvalid  = ififo_q.wvalid;
                    //         mc2iafu_from_nvme_axi4_ch_i_mux.wready         = mc2iafu_from_nvme_axi4_ch_i[0].wready;
                    //     end
                    //     1'b1: begin 
                    //         iafu2mc_to_nvme_axi4_ch_i[1].wvalid  = ififo_q.wvalid;
                    //         mc2iafu_from_nvme_axi4_ch_i_mux.wready         = mc2iafu_from_nvme_axi4_ch_i[1].wready;
                    //     end
                    //     default: begin

                    //     end
                    // endcase
                    iafu2mc_to_nvme_axi4_ch_i[7].wvalid  = ififo_q.wvalid;
                    mc2iafu_from_nvme_axi4_ch_i_mux.wready         = mc2iafu_from_nvme_axi4_ch_i[7].wready;

                end
                default: begin

                end
            endcase

            //fifo2ip R channel
            // mc2iafu_from_nvme_axi4_i.rdata   = rfifo[rfifo_r_ptr[3:0]][519:8];
            // mc2iafu_from_nvme_axi4_i.rid     = rfifo[rfifo_r_ptr[3:0]][7:0];
            mc2iafu_from_nvme_axi4_i.rlast   = 1'b1;
            mc2iafu_from_nvme_axi4_i.ruser   = 1'b0;
            mc2iafu_from_nvme_axi4_i.rresp   = cafu_common_pkg::eresp_CAFU_OKAY;
 
            //fifo2ip B channel
            // mc2iafu_from_nvme_axi4_i.bid     = wfifo[wfifo_r_ptr[3:0]][7:0];
            mc2iafu_from_nvme_axi4_i.buser   = 1'b0;
            mc2iafu_from_nvme_axi4_i.bresp   = cafu_common_pkg::eresp_CAFU_OKAY;


        /*---------------------------------------
        State Machine
        ---------------------------------------*/
            r_next_state_1 = STATE_IDLE;
            unique case(r_state_1)
                STATE_IDLE: begin
                    if (!rfifo_full) begin
                        for (int j=0; j<DQ_CH; j++) begin
                            if (mc2iafu_from_nvme_axi4_ch_i[j].rvalid && iafu2mc_to_nvme_axi4_ch_i[j].rready) begin
                                r_next_state_1 = STATE_RUN;
                                break;
                            end
                        end
                    end
                end
                STATE_RUN: begin
                    r_next_state_1 = STATE_IDLE;
                end
                default: begin
                
                end
            endcase

            //---------------------------------------------
            r_next_state = STATE_IDLE;
            unique case(r_state) 
                STATE_IDLE: begin
                    if (!rfifo_empty) begin
                        r_next_state = STATE_RUN;
                    end
                    else begin
                        r_next_state = STATE_IDLE;
                    end
                end

                STATE_RUN: begin
                    if (iafu2mc_to_nvme_axi4_i.rready) begin
                        r_next_state = STATE_IDLE;
                    end
                    else begin
                        r_next_state = STATE_RUN;
                    end
                end
                default: begin

                end
            endcase

            //---------------------------------------------
            w_next_state = STATE_IDLE;
            unique case(w_state) 
                STATE_IDLE: begin
                    if (!wfifo_empty) begin
                        w_next_state = STATE_RUN;
                    end
                    else begin
                        w_next_state = STATE_IDLE;
                    end
                end

                STATE_RUN: begin
                    if (iafu2mc_to_nvme_axi4_i.bready) begin
                        w_next_state = STATE_IDLE;
                    end
                    else begin
                        w_next_state = STATE_RUN;
                    end
                end
                default: begin

                end
            endcase

            //---------------------------------------------
            w_next_state_1 = STATE_IDLE;
            unique case(w_state_1)
                STATE_IDLE: begin
                    if (!wfifo_full) begin
                        for (int j=0; j<DQ_CH; j++) begin
                            if (mc2iafu_from_nvme_axi4_ch_i[j].bvalid) begin
                                iafu2mc_to_nvme_axi4_ch_i[j].bready = 1'b1;
                                w_next_state_1 = STATE_RUN;
                                break;
                            end
                        end
                    end
                end
                STATE_RUN: begin
                    w_next_state_1 = STATE_IDLE;
                end
                default: begin
                
                end
            endcase


            //------------------------------------------------
            //ififo enqueue does not require fifo
            i_next_state = STATE_IDLE;
            unique case (i_state)
                STATE_IDLE: begin
                    if (!ififo_full) begin
                        if (iafu2mc_to_nvme_axi4_i.arvalid || iafu2mc_to_nvme_axi4_i.awvalid || m5_addr_valid_ch) begin
                            i_next_state = STATE_CHECK;
                        end
                    end
                end
                STATE_CHECK: begin
                    i_next_state = STATE_RUN;
                end
                STATE_RUN: begin
                    i_next_state = STATE_IDLE;
                    if (ififo_data.arvalid) begin
                        if (m5_valid) begin
                            i_next_state = STATE_IDLE;
                        end
                        else if (arid_status) begin  //arid is being used
                            i_next_state = STATE_RUN;
                        end
                        else begin
                            i_next_state = STATE_IDLE;
                        end
                    end
                    else begin
                        if (awid_status) begin  //awid is being used
                            i_next_state = STATE_RUN;
                        end
                        else begin
                            i_next_state = STATE_IDLE;
                        end
                    end
                end
                default: begin
                
                end
            endcase

            //------------------------------------------------
            i_next_state_1 = STATE_IDLE;
            unique case (i_state_1)
                STATE_IDLE: begin
                    if (!ififo_empty) begin
                        i_next_state_1 = STATE_RUN;
                    end
                end
                STATE_RUN: begin
                    if ((ififo_q.arvalid && mc2iafu_from_nvme_axi4_ch_i_mux.arready) || (ififo_q.awvalid && mc2iafu_from_nvme_axi4_ch_i_mux.awready)) begin
                        i_next_state_1 = STATE_IDLE;
                    end
                    else begin
                        i_next_state_1 = STATE_RUN;
                    end
                end
                default: begin
                
                end
            endcase
        end
    end 
endgenerate


//m5 module

always_comb begin
    if (iafu2mc_to_nvme_axi4[0].arvalid == 1'b1) begin
            iafu2mc_to_nvme_axi4_m5.araddr = iafu2mc_to_nvme_axi4[0].araddr;
            iafu2mc_to_nvme_axi4_m5.arvalid = iafu2mc_to_nvme_axi4[0].arvalid;
            iafu2mc_to_nvme_axi4_m5.arready = mc2iafu_from_nvme_axi4[0].arready;
    end
    else begin
            iafu2mc_to_nvme_axi4_m5.araddr = iafu2mc_to_nvme_axi4[1].araddr;
            iafu2mc_to_nvme_axi4_m5.arvalid = iafu2mc_to_nvme_axi4[1].arvalid;
            iafu2mc_to_nvme_axi4_m5.arready = mc2iafu_from_nvme_axi4[1].arready;
    end
end

// hot_tracker_top
//     #(
//     // common parameter
//     .ADDR_SIZE(ADDR_SIZE),
//     .DATA_SIZE(PAGE_ADDR_SIZE),
//     .CNT_SIZE(CNT_SIZE),

//     // CM-sketch parameter
//     .W(W),
//     .W_UNIT(W_UNIT),
//     .NUM_SKETCH(NUM_SKETCH),
//     .SKETCH_INDEX_SIZE(SKETCH_INDEX_SIZE),
//     .COLUMN_INDEX_SIZE(COLUMN_INDEX_SIZE),  
//     .NUM_HASH(NUM_HASH),
//     .HASH_SIZE(HASH_SIZE),

//     // sorted CAM parameter
//     .NUM_ENTRY(NUM_ENTRY),
//     .INDEX_SIZE(INDEX_SIZE)
// )
// page_hot_tracker_top
// (
//     .clk                      (axi4_mm_clk),
//     .rstn                     (axi4_mm_rst_n),

//     .to_tracker_struct        (iafu2mc_to_nvme_axi4_m5),

//     // hot tracker interface
//     .query_en                 (page_query_en),
//     .query_ready              (page_query_ready),

//     .mig_addr_en              (page_mig_addr_en),
//     .mig_addr                 (page_mig_addr),
//     .mig_addr_ready           (page_mig_addr_ready),
//     .mem_chan_rd_en           (mem_chan_rd_en),

//     .csr_addr_ub              (csr_addr_ub),
//     .csr_addr_lb              (csr_addr_lb)
// );      

assign page_mig_addr_ready = 1'b1;

assign m5_addr_reg.bready = 1'b0;
assign m5_addr_reg.rready = 1'b0;
assign m5_addr_reg.awid = '0;
assign m5_addr_reg.awaddr = '0;
assign m5_addr_reg.awlen = '0;
assign m5_addr_reg.awsize = cafu_common_pkg::esize_CAFU_512;
assign m5_addr_reg.awburst = cafu_common_pkg::eburst_CAFU_FIXED;
assign m5_addr_reg.awprot = cafu_common_pkg::eprot_CAFU_UNPRIV_SECURE_DATA;
assign m5_addr_reg.awqos =  cafu_common_pkg::eqos_CAFU_BEST_EFFORT;
assign m5_addr_reg.awvalid = 1'b0;
assign m5_addr_reg.awcache = cafu_common_pkg::ecache_aw_CAFU_DEVICE_NON_BUFFERABLE;
assign m5_addr_reg.awlock = cafu_common_pkg::elock_CAFU_NORMAL;
assign m5_addr_reg.awregion = '0;
assign m5_addr_reg.awuser = '0;
assign m5_addr_reg.wdata = '0;
assign m5_addr_reg.wstrb = '0;
assign m5_addr_reg.wlast = 1'b0;
assign m5_addr_reg.wvalid = 1'b0;
assign m5_addr_reg.wuser = '0;
assign m5_addr_reg.arid = 9'h100; //used as prefetch id
// assign m5_addr_reg.araddr = '0; // address is set in STATE_FETCH
assign m5_addr_reg.arlen = '0;
assign m5_addr_reg.arsize = cafu_common_pkg::esize_CAFU_512; 
assign m5_addr_reg.arburst = cafu_common_pkg::eburst_CAFU_FIXED;
assign m5_addr_reg.arprot = cafu_common_pkg::eprot_CAFU_UNPRIV_SECURE_DATA;
assign m5_addr_reg.arqos = cafu_common_pkg::eqos_CAFU_BEST_EFFORT;
assign m5_addr_reg.arvalid = 1'b1;
assign m5_addr_reg.arcache = cafu_common_pkg::ecache_ar_CAFU_DEVICE_NON_BUFFERABLE;
assign m5_addr_reg.arlock = cafu_common_pkg::elock_CAFU_NORMAL;
assign m5_addr_reg.arregion = '0;
assign m5_addr_reg.aruser = '0;

always_ff @(posedge axi4_mm_clk) begin
    if (!axi4_mm_rst_n) begin
        m5_state <= STATE_IDLE;
        m5_delay_cnt <= '0;
    end
    else begin
        m5_state <= m5_next_state;

        unique case (m5_state)
            STATE_IDLE: begin
                m5_delay_cnt <= '0;
            end
            STATE_QUERY: begin
                
            end
            STATE_FETCH: begin
                if (page_mig_addr_en) begin
                    m5_addr_reg.araddr <= page_mig_addr;
                end
            end
            STATE_WAIT: begin
                m5_delay_cnt <= m5_delay_cnt + 1;
            end
            default: begin

            end
        endcase
    end
end

always_comb begin
    page_query_en = 1'b0;
    for (int i=0; i<MC_CH; i++) begin
        m5_addr_valid[i] = 1'b0;
    end
    m5_next_state = STATE_IDLE;

    unique case (m5_state)
        STATE_IDLE: begin
            if (m5_query_en) begin
                m5_next_state = STATE_QUERY;
            end
            else begin
                m5_next_state = STATE_IDLE;
            end
        end
        STATE_QUERY: begin
            page_query_en = 1'b1;
            m5_next_state = STATE_FETCH;
        end
        STATE_FETCH: begin
            if (page_mig_addr_en) begin
                m5_next_state = STATE_ISSUE;
            end
            else begin
                m5_next_state = STATE_FETCH;
            end
        end
        STATE_ISSUE: begin
            m5_addr_valid[0] = 1'b1;
            if (m5_addr_ready[0]) begin
                m5_next_state = STATE_WAIT;
            end
            else begin
                m5_next_state = STATE_ISSUE;
            end
        end
        STATE_WAIT: begin
            if (m5_delay_cnt == m5_interval) begin
                m5_next_state = STATE_IDLE;
            end
            else begin
                m5_next_state = STATE_WAIT;
            end
        end
        default: begin

        end
    endcase
end



/*--------------------------------------------
Performance counters
--------------------------------------------*/

(* preserve_for_debug *) logic [31:0] pf_ar_handshake_0;
(* preserve_for_debug *) logic [31:0] pf_ar_handshake_1;
(* preserve_for_debug *) logic [31:0] pf_aw_handshake_0;
(* preserve_for_debug *) logic [31:0] pf_aw_handshake_1;
(* preserve_for_debug *) logic [31:0] pf_r_handshake_0;
(* preserve_for_debug *) logic [31:0] pf_r_handshake_1;
(* preserve_for_debug *) logic [31:0] pf_b_handshake_0;
(* preserve_for_debug *) logic [31:0] pf_b_handshake_1;

(* preserve_for_debug *) logic [31:0] pf_arid_sum_0;
(* preserve_for_debug *) logic [31:0] pf_arid_sum_1;
(* preserve_for_debug *) logic [31:0] pf_rid_sum_0;
(* preserve_for_debug *) logic [31:0] pf_rid_sum_1;

(* preserve_for_debug *) logic [31:0] pf_awid_sum_0;
(* preserve_for_debug *) logic [31:0] pf_awid_sum_1;
(* preserve_for_debug *) logic [31:0] pf_bid_sum_0;
(* preserve_for_debug *) logic [31:0] pf_bid_sum_1;

// (* preserve_for_debug *) logic [31:0] pf_in_flight_aw_0;
// (* preserve_for_debug *) logic [31:0] pf_in_flight_aw_1;
// (* preserve_for_debug *) logic [31:0] pf_in_flight_ar_0;
// (* preserve_for_debug *) logic [31:0] pf_in_flight_ar_1;

// logic [2:0] arid_ch_0_array[255:0];
// logic [2:0] arid_ch_1_array[255:0];
// logic [2:0] crid_ch_0_array[255:0];
// logic [2:0] crid_ch_1_array[255:0];
// logic arid_ch_0_valid;
// logic arid_ch_1_valid;
// logic crid_ch_0_valid;
// logic crid_ch_1_valid;
// logic [7:0] arid_ch_0_reg;
// logic [7:0] arid_ch_1_reg;
// logic [7:0] crid_ch_0_reg;
// logic [7:0] crid_ch_1_reg;

// (* preserve_for_debug *) logic arid_ch_0_used_array [255:0];
// (* preserve_for_debug *) logic arid_ch_1_used_array [255:0];

// logic [2:0] awid_ch_0_array[255:0];
// logic [2:0] awid_ch_1_array[255:0];
// logic [2:0] bid_ch_0_array[255:0];
// logic [2:0] bid_ch_1_array[255:0];
// logic awid_ch_0_valid;
// logic awid_ch_1_valid;
// logic bid_ch_0_valid;
// logic bid_ch_1_valid;
// logic [7:0] awid_ch_0_reg;
// logic [7:0] awid_ch_1_reg;
// logic [7:0] bid_ch_0_reg;
// logic [7:0] bid_ch_1_reg;

// (* preserve_for_debug *) logic awid_ch_0_used_array [255:0];
// (* preserve_for_debug *) logic awid_ch_1_used_array [255:0];


always_ff @(posedge axi4_mm_clk) begin
    if (!axi4_mm_rst_n) begin
        pf_ar_handshake_0   <= '0;
        pf_ar_handshake_1   <= '0;
        pf_aw_handshake_0   <= '0;
        pf_aw_handshake_1   <= '0;
        pf_r_handshake_0    <= '0;
        pf_r_handshake_1    <= '0;
        pf_b_handshake_0    <= '0;
        pf_b_handshake_1    <= '0;

        pf_arid_sum_0       <= '0;
        pf_arid_sum_1       <= '0;
        pf_rid_sum_0        <= '0;
        pf_rid_sum_1        <= '0;

        pf_awid_sum_0       <= '0;
        pf_awid_sum_1       <= '0;
        pf_bid_sum_0       <= '0;
        pf_bid_sum_1       <= '0;

        pf_in_flight_aw_0   <= '0;
        pf_in_flight_aw_1   <= '0;
        pf_in_flight_ar_0   <= '0;
        pf_in_flight_ar_1   <= '0;
    end
    else begin
        pf_in_flight_ar_0 <= pf_ar_handshake_0 - pf_r_handshake_0;
        pf_in_flight_ar_1 <= pf_ar_handshake_1 - pf_r_handshake_1;
        pf_in_flight_aw_0 <= pf_aw_handshake_0 - pf_b_handshake_0;
        pf_in_flight_aw_1 <= pf_aw_handshake_1 - pf_b_handshake_1;

        pf_in_flight_cmd_0 <= pf_in_flight_ar_0 + pf_in_flight_aw_0;
        pf_in_flight_cmd_1 <= pf_in_flight_ar_1 + pf_in_flight_aw_1;

        if (iafu2mc_to_nvme_axi4[0].arvalid && mc2iafu_from_nvme_axi4[0].arready) begin
            pf_ar_handshake_0 <= pf_ar_handshake_0 + 1'b1;
            pf_arid_sum_0   <= pf_arid_sum_0 + iafu2mc_to_nvme_axi4[0].arid;
        end
        
        if (iafu2mc_to_nvme_axi4[0].awvalid && mc2iafu_from_nvme_axi4[0].awready) begin
            pf_aw_handshake_0 <= pf_aw_handshake_0 + 1'b1;
            pf_awid_sum_0   <= pf_awid_sum_0 + iafu2mc_to_nvme_axi4[0].awid;
        end

        if (iafu2mc_to_nvme_axi4[0].rready && mc2iafu_from_nvme_axi4[0].rvalid) begin
            pf_r_handshake_0 <= pf_r_handshake_0 + 1'b1;
            pf_rid_sum_0    <= pf_rid_sum_0 + mc2iafu_from_nvme_axi4[0].rid;
        end

        if (iafu2mc_to_nvme_axi4[0].bready && mc2iafu_from_nvme_axi4[0].bvalid) begin
            pf_b_handshake_0 <= pf_b_handshake_0 + 1'b1;
            pf_bid_sum_0    <= pf_bid_sum_0 + mc2iafu_from_nvme_axi4[0].bid;
        end

        if (iafu2mc_to_nvme_axi4[1].arvalid && mc2iafu_from_nvme_axi4[1].arready) begin
            pf_ar_handshake_1 <= pf_ar_handshake_1 + 1'b1;
            pf_arid_sum_1   <= pf_arid_sum_1 + iafu2mc_to_nvme_axi4[1].arid;
        end

        if (iafu2mc_to_nvme_axi4[1].awvalid && mc2iafu_from_nvme_axi4[1].awready) begin
            pf_aw_handshake_1 <= pf_aw_handshake_1 + 1'b1;
            pf_awid_sum_1   <= pf_awid_sum_1 + iafu2mc_to_nvme_axi4[1].awid;
        end

        if (iafu2mc_to_nvme_axi4[1].rready && mc2iafu_from_nvme_axi4[1].rvalid) begin
            pf_r_handshake_1 <= pf_r_handshake_1 + 1'b1;
            pf_rid_sum_1    <= pf_rid_sum_1 + mc2iafu_from_nvme_axi4[1].rid;
        end

        if (iafu2mc_to_nvme_axi4[1].bready && mc2iafu_from_nvme_axi4[1].bvalid) begin
            pf_b_handshake_1 <= pf_b_handshake_1 + 1'b1;
            pf_bid_sum_1    <= pf_bid_sum_1 + mc2iafu_from_nvme_axi4[1].bid;
        end

        // if ((iafu2mc_to_nvme_axi4[0].arvalid && mc2iafu_from_nvme_axi4[0].arready) ||
        //     (iafu2mc_to_nvme_axi4[0].awvalid && mc2iafu_from_nvme_axi4[0].awready)) begin
        //     pf_in_flight_cmd_0_eq <= pf_in_flight_cmd_0_eq + 1'b1;
        // end
        // if ((iafu2mc_to_nvme_axi4[1].arvalid && mc2iafu_from_nvme_axi4[1].arready) ||
        //     (iafu2mc_to_nvme_axi4[1].awvalid && mc2iafu_from_nvme_axi4[1].awready)) begin
        //     pf_in_flight_cmd_1_eq <= pf_in_flight_cmd_1_eq + 1'b1;
        // end
        // if ((mc2iafu_from_nvme_axi4[0].rvalid && iafu2mc_to_nvme_axi4[0].rready) ||
        //     (mc2iafu_from_nvme_axi4[0].bvalid && iafu2mc_to_nvme_axi4[0].bready)) begin
        //     pf_in_flight_cmd_0_dq <= pf_in_flight_cmd_0_dq + 1'b1;
        // end
        // if ((mc2iafu_from_nvme_axi4[1].rvalid && iafu2mc_to_nvme_axi4[1].rready) ||
        //     (mc2iafu_from_nvme_axi4[1].bvalid && iafu2mc_to_nvme_axi4[1].bready)) begin
        //     pf_in_flight_cmd_1_dq <= pf_in_flight_cmd_1_dq + 1'b1;
        // end
    end
end

always_ff @(posedge axi4_mm_clk) begin
    if (!axi4_mm_rst_n) begin 
        for (int i=0; i<256; i++) begin
            arid_ch_0_array[i] <= '0;
            arid_ch_1_array[i] <= '0;
            crid_ch_0_array[i] <= '0;
            crid_ch_1_array[i] <= '0;

            arid_ch_0_used_array[i] <= 1'b0;
            arid_ch_1_used_array[i] <= 1'b0;

            awid_ch_0_array[i] <= '0;
            awid_ch_1_array[i] <= '0;
            bid_ch_0_array[i] <= '0;
            bid_ch_1_array[i] <= '0;

            awid_ch_0_used_array[i] <= 1'b0;
            awid_ch_1_used_array[i] <= 1'b0;
        end

        arid_ch_0_valid <= 1'b0;
        arid_ch_1_valid <= 1'b0;
        crid_ch_0_valid <= 1'b0;
        crid_ch_1_valid <= 1'b0;
        arid_ch_0_reg <= '0;
        arid_ch_1_reg <= '0;
        crid_ch_0_reg <= '0;
        crid_ch_1_reg <= '0;

        awid_ch_0_valid <= 1'b0;
        awid_ch_1_valid <= 1'b0;
        bid_ch_0_valid <= 1'b0;
        bid_ch_1_valid <= 1'b0;
        awid_ch_0_reg <= '0;
        awid_ch_1_reg <= '0;
        bid_ch_0_reg <= '0;
        bid_ch_1_reg <= '0;
    end
    else begin
        if (iafu2mc_to_nvme_axi4[0].arvalid && mc2iafu_from_nvme_axi4[0].arready) begin
            arid_ch_0_valid <= 1'b1;
            arid_ch_0_reg <= iafu2mc_to_nvme_axi4[0].arid;
        end
        else begin
            arid_ch_0_valid <= 1'b0;
        end

        if (iafu2mc_to_nvme_axi4[1].arvalid && mc2iafu_from_nvme_axi4[1].arready) begin
            arid_ch_1_valid <= 1'b1;
            arid_ch_1_reg <= iafu2mc_to_nvme_axi4[1].arid;
        end
        else begin
            arid_ch_1_valid <= 1'b0;
        end

        if (mc2iafu_from_nvme_axi4[0].rvalid && iafu2mc_to_nvme_axi4[0].rready) begin
            crid_ch_0_valid <= 1'b1;
            crid_ch_0_reg <= mc2iafu_from_nvme_axi4[0].rid;
        end
        else begin
            crid_ch_0_valid <= 1'b0;
        end

        if (mc2iafu_from_nvme_axi4[1].rvalid && iafu2mc_to_nvme_axi4[1].rready) begin
            crid_ch_1_valid <= 1'b1;
            crid_ch_1_reg <= mc2iafu_from_nvme_axi4[1].rid;
        end
        else begin
            crid_ch_1_valid <= 1'b0;
        end

        if (iafu2mc_to_nvme_axi4[0].awvalid && mc2iafu_from_nvme_axi4[0].awready) begin
            awid_ch_0_valid <= 1'b1;
            awid_ch_0_reg <= iafu2mc_to_nvme_axi4[0].awid;
        end
        else begin
            awid_ch_0_valid <= 1'b0;
        end

        if (iafu2mc_to_nvme_axi4[1].awvalid && mc2iafu_from_nvme_axi4[1].awready) begin
            awid_ch_1_valid <= 1'b1;
            awid_ch_1_reg <= iafu2mc_to_nvme_axi4[1].awid;
        end
        else begin
            awid_ch_1_valid <= 1'b0;
        end

        if (mc2iafu_from_nvme_axi4[0].bvalid && iafu2mc_to_nvme_axi4[0].bready) begin
            bid_ch_0_valid <= 1'b1;
            bid_ch_0_reg <= mc2iafu_from_nvme_axi4[0].bid;
        end
        else begin
            bid_ch_0_valid <= 1'b0;
        end

        if (mc2iafu_from_nvme_axi4[1].bvalid && iafu2mc_to_nvme_axi4[1].bready) begin
            bid_ch_1_valid <= 1'b1;
            bid_ch_1_reg <= mc2iafu_from_nvme_axi4[1].bid;
        end
        else begin
            bid_ch_1_valid <= 1'b0;
        end

        //------ram logic 
        if (arid_ch_0_valid) begin
            arid_ch_0_array[arid_ch_0_reg] <= arid_ch_0_array[arid_ch_0_reg] + 1'b1;
        end

        if (arid_ch_1_valid) begin
            arid_ch_1_array[arid_ch_1_reg] <= arid_ch_1_array[arid_ch_1_reg] + 1'b1;
        end

        if (crid_ch_0_valid) begin
            crid_ch_0_array[crid_ch_0_reg] <= crid_ch_0_array[crid_ch_0_reg] - 1'b1;
        end

        if (crid_ch_1_valid) begin
            crid_ch_1_array[crid_ch_1_reg] <= crid_ch_1_array[crid_ch_1_reg] - 1'b1;
        end

        if (awid_ch_0_valid) begin
            awid_ch_0_array[awid_ch_0_reg] <= awid_ch_0_array[awid_ch_0_reg] + 1'b1;
        end

        if (awid_ch_1_valid) begin
            awid_ch_1_array[awid_ch_1_reg] <= awid_ch_1_array[awid_ch_1_reg] + 1'b1;
        end

        if (bid_ch_0_valid) begin
            bid_ch_0_array[bid_ch_0_reg] <= bid_ch_0_array[bid_ch_0_reg] - 1'b1;
        end

        if (bid_ch_1_valid) begin
            bid_ch_1_array[bid_ch_1_reg] <= bid_ch_1_array[bid_ch_1_reg] - 1'b1;
        end

        //compare logic 
        for (int i=0; i<256; i++) begin
            if (arid_ch_0_array[i][0] != crid_ch_0_array[i][0]) begin
                arid_ch_0_used_array[i] <= 1'b1;
            end
            else begin
                arid_ch_0_used_array[i] <= 1'b0;
            end

            if (arid_ch_1_array[i][0] != crid_ch_1_array[i][0]) begin
                arid_ch_1_used_array[i] <= 1'b1;
            end
            else begin
                arid_ch_1_used_array[i] <= 1'b0;
            end

            if (awid_ch_0_array[i][0] != bid_ch_0_array[i][0]) begin
                awid_ch_0_used_array[i] <= 1'b1;
            end
            else begin
                awid_ch_0_used_array[i] <= 1'b0;
            end

            if (awid_ch_1_array[i][0] != bid_ch_1_array[i][0]) begin
                awid_ch_1_used_array[i] <= 1'b1;
            end
            else begin
                awid_ch_1_used_array[i] <= 1'b0;
            end
        end
    end
end

endmodule