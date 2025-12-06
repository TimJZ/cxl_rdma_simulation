/*
Module: back_end
Purpose: control SSD side state machine
receive memory request from the MSHR
return host buffer address

Date: 10/14/25
12/17/24: support single request
10/14/25: support multiple requests 
*/

module back_end
import ed_mc_axi_if_pkg::*;
#(
    parameter BE_CH                 = 1, //number of back_end instances
    parameter BE_IDX                = log2ceil(BE_CH),
    parameter RW_CH                 = 2, //number of read/write channel to CAFU
    parameter CH_ID                 = 0,
    parameter BUF_ID                = 8, // Number of buffers
    parameter BUF_IDX               = log2ceil(BUF_ID),

    parameter arid_rd_cq = 3,
    parameter awid_wr_sq = 3,
    parameter arid_rd_sq = 4
)
(
    input logic axi4_mm_clk,
    input logic axi4_mm_rst_n,

    //from csr    
    input logic [63:0]  i_sq_addr,   //submission queue
    input logic [63:0]  i_cq_addr,   //completion queue
    input logic [63:0]  i_sq_tail,
    input logic [63:0]  i_cq_head,
    input logic         i_update,
    input logic         i_end_proc,

    //RDMA additional parameters 
    //Assumption: index always 0 (1 submission per request), 
    input logic [63:0]  i_rdma_local_key,
    input logic [63:0]  i_rdma_local_addr,
    input logic [63:0]  i_rdma_remote_key,
    input logic [63:0]  i_rdma_remote_addr,
    input logic [63:0]  i_rdma_qpn_ds,


    input logic         i_host_buf_addr_valid,      //host buffer address is valid
    input logic [63:0]  i_host_buf_addr,            //host buffer address
    input logic [63:0]  i_block_index_offset,

    //to PIO
    output logic            pio_sqdb_valid,
    output logic [63:0]     pio_sqdb_tail,
    input logic             pio_sqdb_ready,

    output logic            pio_cqdb_valid,
    output logic [63:0]     pio_cqdb_head,
    input logic             pio_cqdb_ready,

    //from front_end
    input  ed_mc_axi_if_pkg::t_to_nvme_axi4         nvme_to_be_axi4,
    output ed_mc_axi_if_pkg::t_from_nvme_axi4       be_to_nvme_axi4,

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
    input logic [11:0] bid,


    output logic [31:0] pf_pio_sq_db,
    output logic [31:0] pf_pio_cq_db
);

    enum logic [4:0] {
        STATE_IDLE,
        STATE_CHECK,
        STATE_CHECK_DONE,
        STATE_WRITE_SQ,
        STATE_WRITE_SQ_DONE,
        STATE_READ_SQ,
        STATE_READ_SQ_DONE,
        STATE_READ_CQ,
        STATE_READ_CQ_DONE,
        STATE_WAIT_SQDB,
        STATE_WAIT_SQDB_DONE,
        STATE_WAIT_CQDB,
        STATE_WAIT_CQDB_DONE,
        STATE_FINISH,
        STATE_STALL,
        STATE_RD_BUF, //read host_buffer_array to get the host buffer address
        STATE_RL_BUF  //release buffer before return to idle
    } sq_state, next_sq_state,
      cq_state, next_cq_state;

    logic [63:0] sq_tail;
    logic [63:0] cq_head;
    logic [63:0] sq_addr;
    logic [63:0] cq_addr;
    
    //RDMA additional registers
    logic [63:0] rdma_local_key;
    logic [63:0] rdma_local_addr;
    logic [63:0] rdma_remote_key;
    logic [63:0] rdma_remote_addr;
    logic [63:0] rdma_qpn_ds;

    ed_mc_axi_if_pkg::t_to_nvme_axi4 nvme_to_be_axi4_sq_reg;

    logic [BUF_IDX-1:0] buffer_idx; //idx assigned to each buffer

    logic [15:0]    sq_cid; //sq_cid cannot be ffff; format: [fe_id, buf_id]

    logic [15:0]    cq_cid;
    logic [8:0]     cq_cid_index;
    logic [8:0]     cq_phase_index;
    logic [12:0]    cq_fe_id;
    logic           cq_fe_type;
    
    logic [63:0]    ssd_logic_block_index;

    logic in_proc_cmd; //indicate if there is any command in process

    
    logic [63:0] host_buf_fifo_data;
    logic        host_buf_fifo_wrreq;
    logic        host_buf_fifo_rdreq;
    logic [63:0] host_buf_fifo_q;
    logic        host_buf_fifo_rdempty;
    logic        host_buf_fifo_wrfull;

    logic [63:0] release_host_buf_addr; //released host buffer address from MSHR
    logic        release_host_buf_addr_valid;

    logic [BUF_IDX-1:0] host_buf_array_wraddr;
    logic [63:0]        host_buf_array_wrdata;
    logic               host_buf_array_wrreq;
    logic               host_buf_array_rdreq;
    logic [BUF_IDX-1:0] host_buf_array_rdaddr;
    logic [63:0]        host_buf_array_rddata;

    logic               proc_array_wrreq;
    logic [BUF_IDX-1:0] proc_array_wraddr;
    logic [12:0]        proc_array_wrdata;
    logic               proc_array_rdreq;
    logic [BUF_IDX-1:0] proc_array_rdaddr;
    logic [12:0]        proc_array_rddata;


    //endianess swaping logic for 32 bit case
    function automatic logic [31:0] swap32(input logic [31:0] x);
        swap32 = { x[7:0], x[15:8], x[23:16], x[31:24] };
    endfunction

    //64 bit case
    function automatic logic [63:0] swap64(input logic [63:0] x);
        swap64 = { x[7:0],  x[15:8],  x[23:16],  x[31:24],
                x[39:32], x[47:40], x[55:48], x[63:56] };
    endfunction

    assign pio_sqdb_tail = {54'b0, sq_tail[9:0]};
    assign pio_cqdb_head = {54'b0, cq_head[9:0]};

    assign cq_cid_index =   {cq_head[1:0],7'b1101111}; //check the sq_cid
    assign cq_phase_index = {cq_head[1:0],7'b1110000}; //only check phase bit, not sq_cid

    assign ssd_logic_block_index = i_block_index_offset + nvme_to_be_axi4_sq_reg.ssd_rq_addr[36:9];

    assign in_proc_cmd = sq_tail != cq_head;

    assign host_buf_array_rdaddr = cq_cid[BUF_IDX-1:0];
    assign proc_array_rdaddr = cq_cid[BUF_IDX-1:0];

    assign cq_fe_id = proc_array_rddata[11:0];
    assign cq_fe_type = proc_array_rddata[12];

    logic phase_bit;
    assign phase_bit = rdata[cq_phase_index];

    (* preserve_for_debug *) logic [31:0] sq_cid_0        ;
    (* preserve_for_debug *) logic [31:0] sq_cid_1        ;
/*---------------------------------
functions
-----------------------------------*/
    fifo host_buf_fifo_inst (
        .data       (host_buf_fifo_data),
        .wrreq      (host_buf_fifo_wrreq),
        .rdreq      (host_buf_fifo_rdreq),
        .wrclk      (axi4_mm_clk),
        .rdclk      (axi4_mm_clk),
        .q          (host_buf_fifo_q),
        .rdempty    (host_buf_fifo_rdempty),
        .wrfull     (host_buf_fifo_wrfull)
    );

    cust_cam #(
        .DEPTH     (BUF_ID)
    ) host_buf_array_inst (
        .clk       (axi4_mm_clk),
        .rst_n     (axi4_mm_rst_n),

        .wr_addr   (host_buf_array_wraddr),
        .wr_data   (host_buf_array_wrdata),
        .wr_req    (host_buf_array_wrreq),

        .rd_addr   (host_buf_array_rdaddr),
        .rd_req    (host_buf_array_rdreq),
        .rd_data   (host_buf_array_rddata)
    );

    cust_cam #(
        .DEPTH      (BUF_ID),
        .DATA_WIDTH (13)  //ssd_rq_type[1] + ssd_rq_fe_id [12]
    ) proc_array_inst (
        .clk       (axi4_mm_clk),
        .rst_n     (axi4_mm_rst_n),

        .wr_addr   (proc_array_wraddr),
        .wr_data   (proc_array_wrdata),
        .wr_req    (proc_array_wrreq),

        .rd_addr   (proc_array_rdaddr),
        .rd_req    (proc_array_rdreq),
        .rd_data   (proc_array_rddata)
    );

/*---------------------------------
Logic
-----------------------------------*/   
    always_ff @(posedge axi4_mm_clk) begin
        if (!axi4_mm_rst_n) begin
            sq_state <= STATE_IDLE;
            cq_state <= STATE_IDLE;

            sq_tail <= '0;
            cq_head <= '0;
            sq_addr <= '0;
            cq_addr <= '0;
            sq_cid <= 16'h1001;

            rdma_local_key <= '0;
            rdma_local_addr <= '0;
            rdma_remote_key <= '0;
            rdma_remote_addr <= '0;
            rdma_qpn_ds <= '0;

            buffer_idx <= '0;

            host_buf_array_wraddr <= '1;
            proc_array_wraddr <= '0;
        end
        else begin
            sq_state <= next_sq_state;
            cq_state <= next_cq_state;

            if (i_update) begin
                sq_tail <= i_sq_tail;
                cq_head <= i_cq_head;
                sq_addr <= i_sq_addr;
                cq_addr <= i_cq_addr;
                rdma_local_key <= i_rdma_local_key;
                rdma_local_addr <= i_rdma_local_addr;
                rdma_remote_key <= i_rdma_remote_key;
                rdma_remote_addr <= i_rdma_remote_addr;
                rdma_qpn_ds <= i_rdma_qpn_ds;
            end

            if (i_host_buf_addr_valid) begin
                host_buf_fifo_data <= {{(8-BE_IDX){1'b0}}, buffer_idx, i_host_buf_addr[55:0]}; //[63:56] buffer idx, [55:0] host buffer address
                host_buf_fifo_wrreq <= 1'b1;
                
                host_buf_array_wrdata <= {{(8-BE_IDX){1'b0}}, buffer_idx, i_host_buf_addr[55:0]};
                host_buf_array_wrreq  <= 1'b1;

                buffer_idx <= buffer_idx + 1; //each buffer get a unique idx
                host_buf_array_wraddr <= host_buf_array_wraddr + 1;
            end
            else if (release_host_buf_addr_valid) begin
                host_buf_fifo_data <= release_host_buf_addr;
                host_buf_fifo_wrreq <= 1'b1;
                host_buf_array_wrreq <= 1'b0;
            end
            else begin
                host_buf_fifo_wrreq <= 1'b0;
                host_buf_array_wrreq <= 1'b0;
            end

            unique case (sq_state)
                STATE_IDLE: begin
                    proc_array_wrreq <= 1'b0;
                    if (nvme_to_be_axi4.ssd_rq_valid && be_to_nvme_axi4.ssd_rq_ready) begin
                        nvme_to_be_axi4_sq_reg <= nvme_to_be_axi4;
                    end
                end
                STATE_CHECK: begin

                end
                STATE_CHECK_DONE: begin

                end
                STATE_WRITE_SQ: begin
                    // if (awvalid[0] & awready[0]) begin
                    //     sq_tail <= sq_tail + 64'd1;
                    // end
                end
                STATE_WRITE_SQ_DONE: begin

                end
                STATE_READ_SQ: begin
                    if (arvalid[0] & arready[0]) begin
                        sq_tail <= sq_tail + 64'd1;
                    end
                end
                STATE_READ_SQ_DONE: begin
                    if (rvalid & rready) begin
                        if (rid == arid_rd_sq) begin
                            sq_cid_0 <= rdata[31:16];
                            sq_cid_1 <= sq_cid_0;
                        end
                    end
                end
                
                STATE_WAIT_SQDB: begin

                end
                STATE_WAIT_SQDB_DONE: begin
                    if (!pio_sqdb_ready) begin //send out sq doorbell, finish submission of the request
                        // sq_tail <= sq_tail + 64'd1;

                        proc_array_wraddr <= host_buf_fifo_q[BUF_ID-1+56:56]; //buffer idx
                        proc_array_wrdata <= {nvme_to_be_axi4_sq_reg.ssd_rq_type, nvme_to_be_axi4_sq_reg.ssd_rq_fe_id};
                        proc_array_wrreq <= 1'b1;
                    end
                end
                default: begin

                end
            endcase

            unique case (cq_state) 
                STATE_IDLE: begin

                end
                STATE_READ_CQ: begin

                end
                STATE_READ_CQ_DONE: begin
                    if (rvalid & rready) begin
                        if (rid == arid_rd_cq) begin
                            // if (rdata[cq_cid_index-:16] == sq_cid) begin  //cid match, cq completed
                            if (rdata[cq_phase_index] != cq_head[10]) begin //phase bit match, cq completed
                                cq_head <= cq_head + 64'd1;
                                // if (sq_cid == 16'hfffe) begin
                                //     sq_cid <= 16'h0000; //reset cid
                                // end
                                // else begin
                                //     sq_cid <= sq_cid + 16'd1;
                                // end
                                cq_cid <= rdata[cq_cid_index-:16];
                            end
                        end
                    end
                end
                STATE_WAIT_CQDB: begin

                end
                STATE_WAIT_CQDB_DONE: begin

                end
                STATE_RD_BUF: begin

                end
                STATE_FINISH: begin
                    // if (be_to_nvme_axi4.ssd_cp_valid && nvme_to_be_axi4.ssd_cp_ready) begin
                    //     cq_head <= cq_head + 64'd1;
                    // end
                end
                default: begin

                end
            endcase

        end
    end

    always_comb begin
        for (int i=0; i<RW_CH; i++) begin
            arvalid[i] = 1'b0;
            araddr[i] = 64'b0;
            arid[i] = 12'b0;
            aruser[i] = 6'b0;

            awvalid[i] = 1'b0;
            awaddr[i] = 64'b0;
            awid[i] = 12'b0;
            awuser[i] = 6'b0;

            wvalid[i] = 1'b0;
            wdata[i] = 512'b0;
            wstrb[i] = 64'b0;
            wlast[i] = 1'b0;
        end

        pio_sqdb_valid = 1'b0;
        pio_cqdb_valid = 1'b0;
        
        //be_to_nvme_axi4 outputs
        be_to_nvme_axi4.ssd_rq_ready = 1'b0;
        
        be_to_nvme_axi4.ssd_cp_valid = 1'b0;
        be_to_nvme_axi4.ssd_cp_addr  = 64'b0;
        be_to_nvme_axi4.ssd_cp_fe_id = 12'b0;
        be_to_nvme_axi4.ssd_cp_be_id = 12'b0;
        
        be_to_nvme_axi4.ssd_bf_valid = 1'b0;
        be_to_nvme_axi4.ssd_bf_addr  = 64'b0;
        be_to_nvme_axi4.ssd_bf_be_id = 12'b0;
        be_to_nvme_axi4.ssd_bf_fe_id = 12'b0;

        be_to_nvme_axi4.ssd_ack_ready = 1'b0;

        be_to_nvme_axi4.ssd_rl_ready = 1'b0;

        //host_buf signal
        host_buf_fifo_rdreq = 1'b0;
        host_buf_array_rdreq = 1'b0;

        release_host_buf_addr_valid = 1'b0;
        release_host_buf_addr = host_buf_array_rddata;

        proc_array_rdreq = 1'b0;

        unique case (sq_state)
            STATE_IDLE: begin
                be_to_nvme_axi4.ssd_rq_ready = !host_buf_fifo_rdempty; //ready to accept new request when have host buffer address
                if (nvme_to_be_axi4.ssd_rq_valid && be_to_nvme_axi4.ssd_rq_ready) begin
                    host_buf_fifo_rdreq = 1'b1;
                end
            end
            STATE_CHECK: begin
                if (nvme_to_be_axi4_sq_reg.ssd_rq_type == 1'b0) begin //read request, skip check

                end
                else begin  //write request, send bf signal 
                    be_to_nvme_axi4.ssd_bf_valid = 1'b1;
                    be_to_nvme_axi4.ssd_bf_addr  = host_buf_fifo_q;  //host_buffer index + host_buffer address 
                    be_to_nvme_axi4.ssd_bf_be_id = {{(8-BE_IDX){1'b0}}, sq_tail[3:0], CH_ID[BE_IDX-1:0]};
                    be_to_nvme_axi4.ssd_bf_fe_id = nvme_to_be_axi4_sq_reg.ssd_rq_fe_id;
                end
            end
            STATE_CHECK_DONE: begin
                if (nvme_to_be_axi4_sq_reg.ssd_rq_type == 1'b0) begin //read request, skip check

                end
                else begin //write request, wait ack signal 
                    be_to_nvme_axi4.ssd_ack_ready = 1'b1;
                end
            end
            STATE_WRITE_SQ: begin
                awaddr[0] = sq_addr + {48'b0,sq_tail[9:0],6'b0};
                awvalid[0] = 1'b1;
                awid[0] = awid_wr_sq;
                awuser[0] = 6'b000000; //non cacheable, host bias, D2H write

                wvalid[0] = 1'b1;
                if (nvme_to_be_axi4_sq_reg.ssd_rq_type == 1'b0) begin //read request
                    wdata[0] = {64'h0,
                            64'h0000000000000000,
                            ssd_logic_block_index,             //TODO: change SLBA
                            64'h0,
                            {8'b0, host_buf_fifo_q[55:0]},
                            64'h0,
                            64'h0,
                            {16'h0000,16'h0001,nvme_to_be_axi4_sq_reg.ssd_rq_fe_id[7:0],host_buf_fifo_q[63:56],16'h0002}};  //TODO: change CID
                end
                else begin  //write request
                    wdata[0] = {64'h0, //[not used]
                            64'h0000000000000000,   //[NLB, no flags, ...]
                            ssd_logic_block_index,             //[SLBA] TODO: change SLBA
                            64'h0, //[not used]
                            {8'b0, host_buf_fifo_q[55:0]}, //[DPTR]
                            64'h0,//[not used]
                            64'h0,//[not used]
                            {16'h0000,16'h0001,nvme_to_be_axi4_sq_reg.ssd_rq_fe_id[7:0],host_buf_fifo_q[63:56],16'h0001}};  //[NSID, CID, flag, opcode]TODO: change CID
                end
                wstrb[0] = 64'hffffffffffffffff;
                wlast[0] = 1'b1;
            end

            // STATE_WRITE_SQ: begin
            //     //adapted version for RDMA WQE 
            //     //First write address, sq_tail last 10 bits used as index, preivously shifted by 6 --> multiplied by 64 (NVMe WQE size)
            //     //Unchanged for now: assume 64 Bytes per WQE, 1 WQEBB with 4 segments: 1 control, 1 remote and 2 data 
            //     awaddr[0] = sq_addr + {48'b0,sq_tail[9:0],6'b0};
            //     //unchanged 
            //     awvalid[0] = 1'b1;
            //     awid[0] = awid_wr_sq;
            //     //awuser[0] = 6'b100000; //non cacheable, host bias, D2D write
            //     awuser[0] = 6'b000000; //non cacheable, host bias, D2H write

            //     wvalid[0] = 1'b1;
            //     if (nvme_to_be_axi4_sq_reg.ssd_rq_type == 1'b0) begin //read request
            //         wdata[0] = {64'h0,
            //                 64'h0000000000000000,
            //                 ssd_logic_block_index,             //TODO: change SLBA
            //                 64'h0,
            //                 {8'b0, host_buf_fifo_q[55:0]},
            //                 64'h0,
            //                 64'h0,
            //                 {16'h0000,16'h0001,nvme_to_be_axi4_sq_reg.ssd_rq_fe_id[7:0],host_buf_fifo_q[63:56],16'h0002}};  //TODO: change CID
            //     end
            //     else begin  //write request --> write RDMA WQE
            //         //Big endian format
            //         //64 Bytes: 16 Bytes control, 16 Bytes remote, 16 Bytes data pointer 
            //         wdata[0] = {
            //             32'h08000000,                               //control segment: opcode for RDMA write in big endian 4B
            //             swap32(rdma_qpn_ds[31:0]),                    //control segment: QPN and DS & swap 4B
            //             8'b0,                                        //control segment:  signature = 0 1B
            //             16'b0,                                       //control segment:  dci_stream_chaneel = 0 2B 
            //             8'h08,                                       //control segment:  fm_ce_se = 8'h08 (RDMA write signaled) 1B
            //             32'b0,                                      //control segment:  imm_id = 0 4B end of control segment
                        
            //             swap64(rdma_remote_addr),                    //remote segment: remote address 8B     
            //             swap32(rdma_remote_key[31:0]),               //remote segment: local key 4B
            //             32'b0,                                      //remote segment:  unused 4B end of remote segment

            //             32'h00020000,                               //data pointer segment: byte count 4B assume 512 Bytes to send
            //             swap32(rdma_local_key[31:0]),               //data pointer segment: local address 4B
            //             swap64(rdma_local_addr),                    //data pointer segment: local key 8B end of data pointer segment
            //             128'b0                                      //padding to make 64 Bytes total
                        
            //         };
            //     end
            //     wstrb[0] = 64'hffffffffffffffff;
            //     wlast[0] = 1'b1;
            // end

            STATE_WRITE_SQ_DONE: begin

            end
            STATE_READ_SQ: begin
                arvalid[0] = 1'b1;
                araddr[0] = sq_addr + {48'b0,sq_tail[9:0],6'b0};
                arid[0] = arid_rd_sq;
                aruser[0] = 6'b000000; //non cachenable, D2H read
            end
            STATE_READ_SQ_DONE: begin

            end
            STATE_WAIT_SQDB: begin
                pio_sqdb_valid = 1'b1;
            end
            STATE_WAIT_SQDB_DONE: begin

            end
            default: begin

            end
        endcase

        unique case (cq_state)
            STATE_IDLE: begin

            end
            STATE_READ_CQ: begin
                arvalid[1] = 1'b1;
                araddr[1] = cq_addr + {50'b0,cq_head[9:2],6'b0};
                arid[1] = arid_rd_cq;
                aruser[1] = 6'b000000; //non cachenable, D2H read
            end
            STATE_READ_CQ_DONE: begin

            end
            STATE_WAIT_CQDB: begin
                pio_cqdb_valid = 1'b1;
            end
            STATE_WAIT_CQDB_DONE: begin

            end
            STATE_RD_BUF: begin
                host_buf_array_rdreq = 1'b1;
                proc_array_rdreq = 1'b1;
            end
            STATE_FINISH: begin
                be_to_nvme_axi4.ssd_cp_valid = 1'b1;
                be_to_nvme_axi4.ssd_cp_addr = {8'b0, host_buf_array_rddata}; //return raw address
                be_to_nvme_axi4.ssd_cp_fe_id = cq_fe_id;
                be_to_nvme_axi4.ssd_cp_be_id = {{(8-BE_IDX){1'b0}}, sq_tail[3:0], CH_ID[BE_IDX-1:0]};
            end
            STATE_STALL: begin
                be_to_nvme_axi4.ssd_rl_ready = 1'b1;
            end
            STATE_RL_BUF: begin
                release_host_buf_addr_valid = 1'b1;
            end
            default: begin
            
            end
        endcase
    end

/*---------------------------------
state machine
-----------------------------------*/
    always_comb begin
        unique case (sq_state)
            STATE_IDLE: begin
                if (nvme_to_be_axi4.ssd_rq_valid && be_to_nvme_axi4.ssd_rq_ready) begin
                    next_sq_state = STATE_CHECK;
                end
                else begin
                    next_sq_state = STATE_IDLE;
                end
            end
            STATE_CHECK: begin
                if (nvme_to_be_axi4_sq_reg.ssd_rq_type == 1'b0) begin
                    next_sq_state = STATE_CHECK_DONE;
                end
                else begin
                    if (be_to_nvme_axi4.ssd_bf_valid && nvme_to_be_axi4.ssd_bf_ready) begin
                        next_sq_state = STATE_CHECK_DONE;
                    end
                    else begin
                        next_sq_state = STATE_CHECK;
                    end
                end
            end
            STATE_CHECK_DONE: begin
                if (nvme_to_be_axi4_sq_reg.ssd_rq_type == 1'b0) begin
                    next_sq_state = STATE_WRITE_SQ;
                end
                else begin
                    if (nvme_to_be_axi4.ssd_ack_valid && be_to_nvme_axi4.ssd_ack_ready) begin
                        next_sq_state = STATE_WRITE_SQ;
                    end
                    else begin
                        next_sq_state = STATE_CHECK_DONE;
                    end
                end
            end
            STATE_WRITE_SQ: begin
                if (awvalid[0] && awready[0]) begin
                    next_sq_state = STATE_WRITE_SQ_DONE;
                end 
                else begin
                    next_sq_state = STATE_WRITE_SQ;
                end
            end
            STATE_WRITE_SQ_DONE: begin
                if (bvalid && bready) begin
                    if (bid == awid_wr_sq) begin
                        // next_state = STATE_WAIT_SQDB;
                        next_sq_state = STATE_READ_SQ;
                    end
                    else begin
                        next_sq_state = STATE_WRITE_SQ_DONE;
                    end
                end
                else begin
                    next_sq_state = STATE_WRITE_SQ_DONE;
                end
            end
            STATE_READ_SQ: begin
                if (arvalid[0] & arready[0]) begin
                    next_sq_state = STATE_READ_SQ_DONE;
                end
                else begin
                    next_sq_state = STATE_READ_SQ;
                end
            end
            STATE_READ_SQ_DONE: begin
                if (rvalid & rready) begin
                    if (rid == arid_rd_sq) begin
                        next_sq_state = STATE_WAIT_SQDB;
                    end
                    else begin
                        next_sq_state = STATE_READ_SQ_DONE;
                    end
                end
                else begin
                    next_sq_state = STATE_READ_SQ_DONE;
                end
            end
            STATE_WAIT_SQDB: begin
                if (pio_sqdb_valid & pio_sqdb_ready) begin
                    next_sq_state = STATE_WAIT_SQDB_DONE;
                end
                else begin
                    next_sq_state = STATE_WAIT_SQDB;
                end
            end
            STATE_WAIT_SQDB_DONE: begin
                if (!pio_sqdb_ready) begin //send out sq doorbell, finish submission of the request
                    next_sq_state = STATE_IDLE; 
                end
                else begin
                    next_sq_state = STATE_WAIT_SQDB_DONE;
                end
            end
            default: begin
                next_sq_state = STATE_IDLE;
            end
        endcase


        unique case (cq_state)
            STATE_IDLE: begin
                if (in_proc_cmd) begin
                    next_cq_state = STATE_READ_CQ;
                end
                else begin
                    next_cq_state = STATE_IDLE;
                end
            end
            STATE_READ_CQ: begin
                if (arvalid[1] & arready[1]) begin
                    next_cq_state = STATE_READ_CQ_DONE;
                end
                else begin
                    next_cq_state = STATE_READ_CQ;
                end
            end
            STATE_READ_CQ_DONE: begin
                if (rvalid & rready) begin
                    if (rid == arid_rd_cq) begin
                        // if (rdata[cq_cid_index-:16] == sq_cid) begin  //cid match, cq completed
                        if (rdata[cq_phase_index] != cq_head[10]) begin //phase bit match, cq completed
                            next_cq_state = STATE_WAIT_CQDB;
                        end
                        else begin  //have not finished, continue poll
                            next_cq_state = STATE_READ_CQ;
                        end
                    end
                    else begin
                        next_cq_state = STATE_READ_CQ_DONE;
                    end
                end
                else begin
                    next_cq_state = STATE_READ_CQ_DONE;
                end
            end
            STATE_WAIT_CQDB: begin
                if (pio_cqdb_valid & pio_cqdb_ready) begin
                    next_cq_state = STATE_WAIT_CQDB_DONE;
                end
                else begin
                    next_cq_state = STATE_WAIT_CQDB;
                end
            end
            STATE_WAIT_CQDB_DONE: begin
                if (!pio_cqdb_ready) begin
                    next_cq_state = STATE_RD_BUF;
                end
                else begin
                    next_cq_state = STATE_WAIT_CQDB_DONE;
                end
            end
            STATE_RD_BUF: begin //get the host buffer address first
                next_cq_state = STATE_FINISH;
            end
            STATE_FINISH: begin
                if (be_to_nvme_axi4.ssd_cp_valid && nvme_to_be_axi4.ssd_cp_ready) begin
                    if (cq_fe_type == 1'b0) begin  //read request need to wait for release signal
                        next_cq_state = STATE_STALL;
                    end
                    else begin  //write request no need to wait for release signal
                        next_cq_state = STATE_RL_BUF;
                    end
                end
                else begin
                    next_cq_state = STATE_FINISH;
                end
            end
            STATE_STALL: begin
                if (nvme_to_be_axi4.ssd_rl_valid && be_to_nvme_axi4.ssd_rl_ready) begin
                    next_cq_state = STATE_RL_BUF;
                end
                else begin
                    next_cq_state = STATE_STALL;
                end
            end
            STATE_RL_BUF: begin
                next_cq_state = STATE_IDLE;
            end
            default: begin

            end
        endcase
    end       

/*---------------------------------
Performance Counter
-----------------------------------*/
    (* preserve_for_debug *) logic [31:0] pc_back_end_hanshake;
    // (* preserve_for_debug *) logic [31:0] pf_pio_sq_db;
    // (* preserve_for_debug *) logic [31:0] pf_pio_cq_db;

    always_ff @(posedge axi4_mm_clk) begin
        if (!axi4_mm_rst_n) begin
            pc_back_end_hanshake <= '0;
            pf_pio_sq_db <= '0;
            pf_pio_cq_db <= '0;
        end
        else begin
            if (nvme_to_be_axi4.ssd_rq_valid && be_to_nvme_axi4.ssd_rq_ready) begin
                pc_back_end_hanshake <= pc_back_end_hanshake + 1;
            end

            if (pio_sqdb_valid && pio_sqdb_ready) begin
                pf_pio_sq_db <= pf_pio_sq_db + 1;
            end

            if (pio_cqdb_valid && pio_cqdb_ready) begin
                pf_pio_cq_db <= pf_pio_cq_db + 1;
            end
        end
    end

    // (* preserve_for_debug *) logic [31:0] STATE_WRITE_SQ_NUM        ;  
    // (* preserve_for_debug *) logic [31:0] STATE_WRITE_SQ_DONE_NUM   ;      
    // (* preserve_for_debug *) logic [31:0] STATE_READ_CQ_NUM         ;  
    // (* preserve_for_debug *) logic [31:0] STATE_READ_CQ_DONE_NUM    ;      
    // (* preserve_for_debug *) logic [31:0] STATE_WAIT_SQDB_NUM       ;  
    // (* preserve_for_debug *) logic [31:0] STATE_WAIT_SQDB_DONE_NUM  ;          
    // (* preserve_for_debug *) logic [31:0] STATE_WAIT_CQDB_NUM       ;  
    // (* preserve_for_debug *) logic [31:0] STATE_WAIT_CQDB_DONE_NUM  ;          
    // (* preserve_for_debug *) logic [31:0] STATE_FINISH_NUM          ;  
    
    // (* preserve_for_debug *) logic [31:0] STATE_WRITE_SQ_CNT        ;  
    // (* preserve_for_debug *) logic [31:0] STATE_WRITE_SQ_DONE_CNT   ;      
    // (* preserve_for_debug *) logic [31:0] STATE_READ_CQ_CNT         ;  
    // (* preserve_for_debug *) logic [31:0] STATE_READ_CQ_DONE_CNT    ;      
    // (* preserve_for_debug *) logic [31:0] STATE_WAIT_SQDB_CNT       ;  
    // (* preserve_for_debug *) logic [31:0] STATE_WAIT_SQDB_DONE_CNT  ;          
    // (* preserve_for_debug *) logic [31:0] STATE_WAIT_CQDB_CNT       ;  
    // (* preserve_for_debug *) logic [31:0] STATE_WAIT_CQDB_DONE_CNT  ;          
    // (* preserve_for_debug *) logic [31:0] STATE_FINISH_CNT          ;  


    // always_ff @(posedge axi4_mm_clk) begin
    //     if (!axi4_mm_rst_n) begin
    //         STATE_WRITE_SQ_NUM        <= '0;
    //         STATE_WRITE_SQ_DONE_NUM   <= '0;
    //         STATE_READ_CQ_NUM         <= '0;
    //         STATE_READ_CQ_DONE_NUM    <= '0;
    //         STATE_WAIT_SQDB_NUM       <= '0;
    //         STATE_WAIT_SQDB_DONE_NUM  <= '0;
    //         STATE_WAIT_CQDB_NUM       <= '0;
    //         STATE_WAIT_CQDB_DONE_NUM  <= '0;
    //         STATE_FINISH_NUM          <= '0;

    //         STATE_WRITE_SQ_CNT        <= '0;
    //         STATE_WRITE_SQ_DONE_CNT   <= '0;
    //         STATE_READ_CQ_CNT         <= '0;
    //         STATE_READ_CQ_DONE_CNT    <= '0;
    //         STATE_WAIT_SQDB_CNT       <= '0;
    //         STATE_WAIT_SQDB_DONE_CNT  <= '0;
    //         STATE_WAIT_CQDB_CNT       <= '0;
    //         STATE_WAIT_CQDB_DONE_CNT  <= '0;
    //         STATE_FINISH_CNT          <= '0;
    //     end
    //     else begin
    //         unique case(state)
    //             STATE_WRITE_SQ: begin
    //                 if (next_state != state) begin
    //                     STATE_WRITE_SQ_NUM <= STATE_WRITE_SQ_NUM + 1;
    //                 end
    //                 STATE_WRITE_SQ_CNT <= STATE_WRITE_SQ_CNT + 1;
    //             end
    //             STATE_WRITE_SQ_DONE: begin
    //                 if (next_state != state) begin
    //                     STATE_WRITE_SQ_DONE_NUM <= STATE_WRITE_SQ_DONE_NUM + 1;
    //                 end
    //                 STATE_WRITE_SQ_DONE_CNT <= STATE_WRITE_SQ_DONE_CNT + 1;
    //             end
    //             STATE_READ_CQ: begin
    //                 if (next_state != state) begin
    //                     STATE_READ_CQ_NUM <= STATE_READ_CQ_NUM + 1;
    //                 end
    //                 STATE_READ_CQ_CNT <= STATE_READ_CQ_CNT + 1;
    //             end
    //             STATE_READ_CQ_DONE: begin
    //                 if (next_state != state) begin
    //                     STATE_READ_CQ_DONE_NUM <= STATE_READ_CQ_DONE_NUM + 1;
    //                 end
    //                 STATE_READ_CQ_DONE_CNT <= STATE_READ_CQ_DONE_CNT + 1;
    //             end
    //             STATE_WAIT_SQDB: begin
    //                 if (next_state != state) begin
    //                     STATE_WAIT_SQDB_NUM <= STATE_WAIT_SQDB_NUM + 1;
    //                 end
    //                 STATE_WAIT_SQDB_CNT <= STATE_WAIT_SQDB_CNT + 1;
    //             end
    //             STATE_WAIT_SQDB_DONE: begin
    //                 if (next_state != state) begin
    //                     STATE_WAIT_SQDB_DONE_NUM <= STATE_WAIT_SQDB_DONE_NUM + 1;
    //                 end
    //                 STATE_WAIT_SQDB_DONE_CNT <= STATE_WAIT_SQDB_DONE_CNT + 1;
    //             end
    //             STATE_WAIT_CQDB: begin
    //                 if (next_state != state) begin
    //                     STATE_WAIT_CQDB_NUM <= STATE_WAIT_CQDB_NUM + 1;
    //                 end
    //                 STATE_WAIT_CQDB_CNT <= STATE_WAIT_CQDB_CNT + 1;
    //             end
    //             STATE_WAIT_CQDB_DONE: begin
    //                 if (next_state != state) begin
    //                     STATE_WAIT_CQDB_DONE_NUM <= STATE_WAIT_CQDB_DONE_NUM + 1;
    //                 end
    //                 STATE_WAIT_CQDB_DONE_CNT <= STATE_WAIT_CQDB_DONE_CNT + 1;
    //             end
    //             STATE_FINISH: begin
    //                 if (next_state != state) begin
    //                     STATE_FINISH_NUM <= STATE_FINISH_NUM + 1;
    //                 end
    //                 STATE_FINISH_CNT <= STATE_FINISH_CNT + 1;
    //             end
    //             default: begin

    //             end
    //         endcase
    //     end
    // end

endmodule


// unique case (state)
//     STATE_IDLE: begin

//     end
//     STATE_WRITE_SQ: begin

//     end
//     STATE_WRITE_SQ_DONE: begin

//     end
//     STATE_READ_CQ: begin

//     end
//     STATE_READ_CQ_DONE: begin

//     end
//     STATE_WAIT_SQDB: begin

//     end
//     STATE_WAIT_SQDB_DONE: begin

//     end
//     STATE_WAIT_CQDB: begin

//     end
//     STATE_WAIT_CQDB_DONE: begin

//     end
//     STATE_FINISH: begin

//     end
//     default: begin

//     end
// endcase