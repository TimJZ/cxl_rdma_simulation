// (C) 2001-2023 Intel Corporation. All rights reserved.
// Your use of Intel Corporation's design tools, logic functions and other 
// software and tools, and its AMPP partner logic functions, and any output 
// files from any of the foregoing (including device programming or simulation 
// files), and any associated documentation or information are expressly subject 
// to the terms and conditions of the Intel Program License Subscription 
// Agreement, Intel FPGA IP License Agreement, or other applicable 
// license agreement, including, without limitation, that your use is for the 
// sole purpose of programming logic devices manufactured by Intel and sold by 
// Intel or its authorized distributors.  Please refer to the applicable 
// agreement for further details.


// Copyright 2023 Intel Corporation.
//
// THIS SOFTWARE MAY CONTAIN PREPRODUCTION CODE AND IS PROVIDED BY THE
// COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED
// WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF
// MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
// DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
// LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
// CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
// SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR
// BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
// WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE
// OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE,
// EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//

module cust_afu_csr_avmm_slave 
import ed_mc_axi_if_pkg::*;
#(
    parameter BE_CH = 0,
    parameter BE_IDX = log2ceil(BE_CH),
    parameter NUM_DEBUG = 64 // Number of debug performance counters
)(
 
// AVMM Slave Interface
   input               clk,
   input               reset_n,
   input  logic [63:0] writedata,
   input  logic        read,
   input  logic        write,
   input  logic [7:0]  byteenable,
   output logic [63:0] readdata,
   output logic        readdatavalid,
   input  logic [21:0] address,
   input logic poison,
   output logic        waitrequest,

    //individual test
   output logic o_start_proc,  
   output logic o_end_proc,
   output logic [63:0] page_addr_0_out,
   output logic [63:0] test_case_out,

   input logic [63:0] addr_cnt_out,
   input logic [63:0] data_cnt_out,
   input logic [63:0] resp_cnt_out,

   input logic [63:0] read_data_out_0,
   input logic [63:0] read_data_out_1,
   input logic [63:0] read_data_out_2,
   input logic [63:0] read_data_out_3,
   input logic [63:0] read_data_out_4,
   input logic [63:0] read_data_out_5,
   input logic [63:0] read_data_out_6,
   input logic [63:0] read_data_out_7,
   output logic [63:0] write_data_out_0,
   output logic [63:0] write_data_out_1,
   output logic [63:0] write_data_out_2,
   output logic [63:0] write_data_out_3,
   output logic [63:0] write_data_out_4,
   output logic [63:0] write_data_out_5,
   output logic [63:0] write_data_out_6,
   output logic [63:0] write_data_out_7,

   output logic [63:0] tx_header_low,
   output logic [63:0] tx_header_high,
   output logic [63:0] tx_start,
   output logic [63:0] tx_payload,

   output logic [63:0] afu_init,
    //nvme controller side 
   output logic [63:0] bar_addr,
   output logic [63:0] requester_id,

   output logic [63:0] sq_addr  [BE_CH-1:0],
   output logic [63:0] cq_addr  [BE_CH-1:0],
   output logic [63:0] sq_tail  [BE_CH-1:0],
   output logic [63:0] cq_head  [BE_CH-1:0],

    //rdma params
   output logic [63:0] rdma_local_key,
   output logic [63:0] rdma_local_addr,
   output logic [63:0] rdma_remote_key,
   output logic [63:0] rdma_remote_addr,
   output logic [63:0] rdma_qpn_ds, 

   output logic update,
   output logic end_proc,

   output logic        host_buf_addr_valid  [BE_CH-1:0],
   output logic [63:0] host_buf_addr        [BE_CH-1:0],
   output logic [63:0] block_index_offset,

   output logic m5_query_en,
   output logic [63:0] m5_interval,

   input logic [63:0] debug_pf [NUM_DEBUG-1:0]
);

 // [harry] original version use 32-bit register, we only need to use 64-bit register
 // this code is imported from ex_default_csr/ex_default_csr_avmm_slave.sv
 // in ed_top_wrapper_typ2.sv, you can we move the ex_default_csr interface into the cust_afu_wrapper


logic [63:0] func_type_reg;         //0


//individual test side 
logic [63:0] page_addr_0_reg;        //8
logic [63:0] test_case_reg;         //16
// logic [63:0] addr_cnt_reg;          //24
logic [63:0] requester_id_reg;      //24
// logic [63:0] data_cnt_reg;          //32
logic [63:0] block_index_offset_reg; //32
logic [63:0] resp_cnt_reg;          //40
logic [63:0] read_data_reg_0;       //48
logic [63:0] read_data_reg_1;       //56
logic [63:0] read_data_reg_2;       //64
logic [63:0] read_data_reg_3;       //72
logic [63:0] read_data_reg_4;       //80
logic [63:0] read_data_reg_5;       //88
logic [63:0] read_data_reg_6;       //96
logic [63:0] read_data_reg_7;       //104
logic [63:0] write_data_reg_0;      //112
logic [63:0] write_data_reg_1;      //120
logic [63:0] write_data_reg_2;      //128
logic [63:0] write_data_reg_3;      //136
logic [63:0] write_data_reg_4;      //144
logic [63:0] write_data_reg_5;      //152
logic [63:0] write_data_reg_6;      //160
logic [63:0] write_data_reg_7;      //168
logic [63:0] tx_header_low_reg;     //176
logic [63:0] tx_header_high_reg;    //184
logic [63:0] tx_start_reg;          //192
logic [63:0] tx_payload_reg;        //200

//nvme controller side 
logic [63:0] sq_addr_reg    [BE_CH-1:0];         //208
logic [63:0] cq_addr_reg    [BE_CH-1:0];         //216
logic [63:0] bar_addr_reg    ;              //224
logic [63:0] sq_tail_reg    [BE_CH-1:0];         //232
logic [63:0] cq_head_reg    [BE_CH-1:0];         //240
logic end_proc_reg;                         //248


//RDMA additional parameters
logic [63:0] rdma_local_key_reg;    //296
logic [63:0] rdma_local_addr_reg;   //304
logic [63:0] rdma_remote_key_reg;   //312
logic [63:0] rdma_remote_addr_reg;  //320
logic [63:0] rdma_qpn_ds_reg;       //328



//control afu_top
logic [63:0] afu_init_reg;                  //256
logic [63:0] host_buf_addr_reg  [BE_CH-1:0];     //264
logic host_buf_addr_valid_reg [BE_CH-1:0];       //same as host_buf_addr_reg 
logic [63:0] queue_index_reg;               //272

logic [63:0] m5_interval_reg;               //280
logic        m5_query_en_reg;               //288
logic [63:0] m5_addr_reg [31:0];            //[296, 552)




logic [4:0]  m5_wr_index;
logic [22:0] m5_rd_index;

assign m5_rd_index = address[21:0] - 22'd296;

//debug performance counter
logic [63:0] debug_pf_reg [NUM_DEBUG-1:0]; //[552, 552+8*num_debug)

logic [8:0] debug_pf_index; 
assign debug_pf_index = ( (address[21:0] - 9'h118) >> 3 ); //debug performance counter index

logic update_reg;

logic [63:0] mask ;
logic config_access;

assign mask[7:0]   = byteenable[0]? 8'hFF:8'h0; 
assign mask[15:8]  = byteenable[1]? 8'hFF:8'h0; 
assign mask[23:16] = byteenable[2]? 8'hFF:8'h0; 
assign mask[31:24] = byteenable[3]? 8'hFF:8'h0; 
assign mask[39:32] = byteenable[4]? 8'hFF:8'h0; 
assign mask[47:40] = byteenable[5]? 8'hFF:8'h0; 
assign mask[55:48] = byteenable[6]? 8'hFF:8'h0; 
assign mask[63:56] = byteenable[7]? 8'hFF:8'h0; 
assign config_access = address[21];  


//Terminating extented capability header
//  localparam EX_CAP_HEADER  = 32'h00000000;
   localparam EX_CAP_HEADER  = 64'h00000000;

always @(posedge clk) begin
    //individual test
    page_addr_0_out <= page_addr_0_reg;
    test_case_out <= test_case_reg;
    // addr_cnt_reg <= addr_cnt_out;
    // data_cnt_reg <= data_cnt_out;
    resp_cnt_reg <= resp_cnt_out;
    read_data_reg_0 <= read_data_out_0;
    read_data_reg_1 <= read_data_out_1;
    read_data_reg_2 <= read_data_out_2;
    read_data_reg_3 <= read_data_out_3;
    read_data_reg_4 <= read_data_out_4;
    read_data_reg_5 <= read_data_out_5;
    read_data_reg_6 <= read_data_out_6;
    read_data_reg_7 <= read_data_out_7;
    write_data_out_0 <= write_data_reg_0;
    write_data_out_1 <= write_data_reg_1;
    write_data_out_2 <= write_data_reg_2;
    write_data_out_3 <= write_data_reg_3;
    write_data_out_4 <= write_data_reg_4;
    write_data_out_5 <= write_data_reg_5;
    write_data_out_6 <= write_data_reg_6;
    write_data_out_7 <= write_data_reg_7;
    tx_header_low <= tx_header_low_reg;
    tx_header_high <= tx_header_high_reg;
    tx_start <= tx_start_reg;
    tx_payload <= tx_payload_reg;

    afu_init <= afu_init_reg;

    m5_query_en <= m5_query_en_reg;
    m5_interval <= m5_interval_reg;

    //nvme controller side 
    for (int i=0; i<BE_CH; i++) begin
        sq_addr      [i]   <= sq_addr_reg          [i];
        cq_addr      [i]   <= cq_addr_reg          [i];
        sq_tail      [i]   <= sq_tail_reg          [i];
        cq_head      [i]   <= cq_head_reg          [i];
        host_buf_addr[i]   <= host_buf_addr_reg    [i];
        if ((host_buf_addr_valid_reg[i]==1'b1) && (host_buf_addr_valid[i]==1'b0)) begin
            host_buf_addr_valid[i] <= 1'b1;
        end
        else begin
            host_buf_addr_valid[i] <= 1'b0;
        end
    end

    rdma_local_key  <= rdma_local_key_reg; 
    rdma_local_addr <= rdma_local_addr_reg;
    rdma_remote_key <= rdma_remote_key_reg;
    rdma_remote_addr <= rdma_remote_addr_reg;  
    rdma_qpn_ds  <= rdma_qpn_ds_reg;




    for (int i=0; i<NUM_DEBUG; i++) begin
        debug_pf_reg[i] <= debug_pf[i];
    end

    bar_addr <= bar_addr_reg;
    requester_id <= requester_id_reg;

    block_index_offset <= block_index_offset_reg;

    update <= update_reg;
    end_proc <= end_proc_reg;
    
end


//Write logic
always @(posedge clk) begin
    if (!reset_n) begin
        bar_addr_reg <= '0;
        requester_id_reg <= 8'h2a;
        block_index_offset_reg <= '0;

        for (int i=0; i<BE_CH; i++) begin
            sq_addr_reg         [i] <= '0;
            cq_addr_reg         [i] <= '0;
            sq_tail_reg         [i] <= '0;
            cq_head_reg         [i] <= '0;
            host_buf_addr_reg   [i] <= '0;
            host_buf_addr_valid_reg[i] <= 1'b0;
        end

        update_reg <= 1'b0;
        end_proc_reg <= 1'b0;
        afu_init_reg <= '0;

        rdma_local_key_reg <= '0; 
        rdma_local_addr_reg <= '0; 
        rdma_remote_key_reg <= '0;
        rdma_remote_addr_reg <= '0;
        rdma_qpn_ds_reg <= '0;
    end
    else begin
        if (write && (address == 22'h0000)) begin 
           func_type_reg <= (writedata & mask) ;
           if ((writedata & mask) == 64'd1) begin
                o_start_proc <= 1'b1;
           end
           if ((writedata & mask) == 64'd2) begin
                o_end_proc <= 1'b1;
           end
           if ((writedata & mask) == 64'd3) begin
                update_reg <= 1'b1;
           end
        end
         else if (write && (address == 22'h0008)) begin //change address
            page_addr_0_reg <= (writedata & mask);
        end
        else if (write && (address == 22'h0010)) begin //change test case
            test_case_reg <= (writedata & mask);
        end
        else if (write && (address == 22'h0018)) begin //change requester_id
            requester_id_reg <= (writedata & mask);
        end
        else if (write && (address == 22'h0020)) begin //change block_index_offset
            block_index_offset_reg <= (writedata & mask);
        end
        else if (write && (address == 22'h0070)) begin //change write_data [0]
            write_data_reg_0 <= (writedata & mask);
        end
        else if (write && (address == 22'h0078)) begin //change write_data [1]
            write_data_reg_1 <= (writedata & mask);
        end
        else if (write && (address == 22'h0080)) begin //change write_data [2]
            write_data_reg_2 <= (writedata & mask);
        end 
        else if (write && (address == 22'h0088)) begin //change write_data [3]
            write_data_reg_3 <= (writedata & mask);
        end
        else if (write && (address == 22'h0090)) begin //change write_data [4]
            write_data_reg_4 <= (writedata & mask);
        end
        else if (write && (address == 22'h0098)) begin //change write_data [5]
            write_data_reg_5 <= (writedata & mask);
        end 
        else if (write && (address == 22'h00A0)) begin //change write_data [6]
            write_data_reg_6 <= (writedata & mask);
        end
        else if (write && (address == 22'h00A8)) begin //change write_data [7]
            write_data_reg_7 <= (writedata & mask);
        end
        else if (write && (address == 22'h00B0)) begin //change tx_header_low_reg
            tx_header_low_reg <= (writedata & mask);
        end
        else if (write && (address == 22'h00B8)) begin //change tx_header_high_reg
            tx_header_high_reg <= (writedata & mask);
        end
        else if (write && (address == 22'h00C0)) begin //change tx_start_reg
            tx_start_reg <= (writedata & mask);
        end
        else if (write && (address == 22'h00C8)) begin //change tx_payload
            tx_payload_reg <= (writedata & mask);
        end
        else if (write && (address == 22'h00D0)) begin 
            sq_addr_reg [queue_index_reg[BE_IDX-1:0]] <= (writedata & mask);
        end
        else if (write && (address == 22'h00D8)) begin 
            cq_addr_reg [queue_index_reg[BE_IDX-1:0]] <= (writedata & mask);
        end
        else if (write && (address == 22'h00E0)) begin 
            bar_addr_reg <= (writedata & mask);
        end
        else if (write && (address == 22'h00E8)) begin 
            sq_tail_reg [queue_index_reg[BE_IDX-1:0]] <= (writedata & mask);
        end
        else if (write && (address == 22'h00F0)) begin 
            cq_head_reg [queue_index_reg[BE_IDX-1:0]] <= (writedata & mask);
        end 
        else if (write && (address == 22'h00F8)) begin 
            end_proc_reg <= 1'b1;
        end 
        else if (write && (address == 22'h0100)) begin 
            afu_init_reg <= (writedata & mask);
        end 
        else if (write && (address == 22'h0108)) begin 
            host_buf_addr_reg [queue_index_reg[BE_IDX-1:0]] <= (writedata & mask);
            host_buf_addr_valid_reg[queue_index_reg[BE_IDX-1:0]] <= 1'b1;
        end 
        else if (write && (address == 22'h0110)) begin 
            queue_index_reg <= (writedata & mask);
        end 
        else if (write && (address == 22'h0118)) begin 
            m5_interval_reg <= (writedata & mask);
        end
        else if (write && (address == 22'h0120)) begin 
            m5_query_en_reg <= writedata[0];
        end
        else if (write && (address == 22'h0128)) begin //offset + 37: rdma local key  
            rdma_local_key_reg <= (writedata & mask);
        end  
        else if (write && (address == 22'h0130)) begin //offset + 38: rdma local addr  
            rdma_local_addr_reg <= (writedata & mask);
        end  
        else if (write && (address == 22'h0138)) begin //offset + 39: rdma remote key  
            rdma_remote_key_reg <= (writedata & mask);
        end 
        else if (write && (address == 22'h0140)) begin //offset + 40: rdma remote addr  
            rdma_remote_addr_reg <= (writedata & mask);
        end
        else if (write && (address == 22'h0148)) begin //offset + 41: rdma qpn and ds  
            rdma_qpn_ds_reg <= (writedata & mask);
        end 
        else begin
            o_start_proc <= 1'b0;
            o_end_proc <= 1'b0;
            tx_start_reg <= 64'b0;
            //nvme controller
            sq_addr_reg <= sq_addr_reg;
            cq_addr_reg <= cq_addr_reg;
            bar_addr_reg <= bar_addr_reg;
            sq_tail_reg <= sq_tail_reg;
            cq_head_reg <= cq_head_reg;
            update_reg <= 1'b0;
            end_proc_reg <= 1'b0;
            host_buf_addr_valid_reg[queue_index_reg[BE_IDX-1:0]] <= 1'b0;
            //rdma control
            rdma_local_key_reg <= rdma_local_key_reg;
            rdma_local_addr_reg <= rdma_local_addr_reg;
            rdma_remote_key_reg <= rdma_remote_key_reg; 
            rdma_remote_addr_reg <= rdma_remote_addr_reg;
            rdma_qpn_ds_reg <= rdma_qpn_ds_reg;
        end        
    end    
end 

//Read logic
always @(posedge clk) begin
    if (!reset_n) begin
        readdata  <= 32'h0;
    end
    else begin
        if (read && (address[21:0] == 22'h0)) begin 
           readdata <= func_type_reg & mask;
        end
        else if(read && (address[21:0] == 22'h0008)) begin //read addr
           readdata <= page_addr_0_reg & mask;
        end
        else if (read && (address[21:0] == 22'h0010)) begin //read test case
            readdata <=  test_case_reg & mask;
        end
        else if (read && (address[21:0] == 22'h0018)) begin //read requester_id
            readdata <=  requester_id_reg & mask;
        end
        else if (read && (address[21:0] == 22'h0020)) begin //read data_cnt
            readdata <=  block_index_offset_reg & mask;
        end
        else if (read && (address[21:0] == 22'h0028)) begin //read resp_cnt
            readdata <=  resp_cnt_reg & mask;
        end
        else if (read && (address[21:0] == 22'h0030)) begin //read read_data [0]
            readdata <=  read_data_reg_0 & mask;
        end
        else if (read && (address[21:0] == 22'h0038)) begin //read read_data [1]
            readdata <=  read_data_reg_1 & mask;
        end
        else if (read && (address[21:0] == 22'h0040)) begin //read read_data [2]
            readdata <=  read_data_reg_2 & mask;
        end
        else if (read && (address[21:0] == 22'h0048)) begin //read read_data [3]
            readdata <=  read_data_reg_3 & mask;
        end
        else if (read && (address[21:0] == 22'h0050)) begin //read read_data [4]
            readdata <=  read_data_reg_4 & mask;
        end
        else if (read && (address[21:0] == 22'h0058)) begin //read read_data [5]
            readdata <=  read_data_reg_5 & mask;
        end
        else if (read && (address[21:0] == 22'h0060)) begin //read read_data [6]
            readdata <=  read_data_reg_6 & mask;
        end
        else if (read && (address[21:0] == 22'h0068)) begin //read read_data [7]
            readdata <=  read_data_reg_7 & mask;
        end
        else if (read && (address[21:0] == 22'h0070)) begin //read write_data [0]
            readdata <=  write_data_reg_0 & mask;
        end
        else if (read && (address[21:0] == 22'h0078)) begin //read write_data [1]
            readdata <=  write_data_reg_1 & mask;
        end
        else if (read && (address[21:0] == 22'h0080)) begin //read write_data [2]
            readdata <=  write_data_reg_2 & mask;
        end
        else if (read && (address[21:0] == 22'h0088)) begin //read write_data [3]
            readdata <=  write_data_reg_3 & mask;
        end
        else if (read && (address[21:0] == 22'h0090)) begin //read write_data [4]
            readdata <=  write_data_reg_4 & mask;
        end
        else if (read && (address[21:0] == 22'h0098)) begin //read write_data [5]
            readdata <=  write_data_reg_5 & mask;
        end
        else if (read && (address[21:0] == 22'h00A0)) begin //read write_data [6]
            readdata <=  write_data_reg_6 & mask;
        end
        else if (read && (address[21:0] == 22'h00A8)) begin //read write_data [7]
            readdata <=  write_data_reg_7 & mask;
        end
        else if (read && (address[21:0] == 22'h00B0)) begin //read tx_header_low_reg
            readdata <=  tx_header_low_reg & mask;
        end
        else if (read && (address[21:0] == 22'h00B8)) begin //read tx_header_high_reg
            readdata <=  tx_header_high_reg & mask;
        end
        else if (read && (address[21:0] == 22'h00C0)) begin //read tx_start
            readdata <=  tx_start_reg & mask;
        end
        else if (read && (address[21:0] == 22'h00C8)) begin //read tx_payload
            readdata <=  tx_payload_reg & mask;
        end
        else if(read && (address[21:0] == 22'h000D0)) begin
           readdata <= sq_addr_reg [queue_index_reg[5:0]] & mask;
        end
        else if (read && (address[21:0] == 22'h00D8)) begin 
            readdata <=  cq_addr_reg [queue_index_reg[5:0]] & mask;
        end
        else if (read && (address[21:0] == 22'h00E0)) begin 
            readdata <=  bar_addr_reg & mask;
        end
        else if (read && (address[21:0] == 22'h00E8)) begin 
            readdata <=  sq_tail_reg [queue_index_reg[5:0]] & mask;
        end
        else if (read && (address[21:0] == 22'h00F0)) begin 
            readdata <=  cq_head_reg [queue_index_reg[5:0]] & mask;
        end
        else if (read && (address[21:0] == 22'h0100)) begin 
            readdata <=  afu_init_reg & mask;
        end
        else if (read && (address[21:0] == 22'h0108)) begin 
            readdata <=  host_buf_addr_reg [queue_index_reg[5:0]] & mask;
        end
        else if (read && (address[21:0] == 22'h0110)) begin 
            readdata <=  queue_index_reg & mask;
        end
        else if (read && (address[21:0] < 22'h228)) begin
            readdata <= m5_addr_reg[m5_rd_index[5:3]] & mask;
        end
        else if (read && (address[21:0] < 22'h428)) begin 
            readdata <=  debug_pf_reg[debug_pf_index] & mask;
        end//add more params for rdma
        else if (read && (address == 22'h0128)) begin //offset + 37: rdma local key  
            readdata <= rdma_local_key_reg & mask;
        end  
        else if (read && (address == 22'h0130)) begin //offset + 38: rdma local addr  
            readdata <= rdma_local_addr_reg & mask;
        end  
        else if (read && (address == 22'h0138)) begin //offset + 39: rdma remote key  
            readdata <= rdma_remote_key_reg & mask;
        end 
        else if (read && (address == 22'h0140)) begin //offset + 40: rdma remote addr  
            readdata <= rdma_remote_addr_reg & mask;
        end
        else if (read && (address == 22'h0148)) begin //offset + 41: rdma qpn and ds  
            readdata <= rdma_qpn_ds_reg & mask;
        end
        else begin
           readdata  <= 64'h0;
        end        
    end    
end 


//Control Logic
enum int unsigned { IDLE = 0,WRITE = 2, READ = 4 } state, next_state;

always_comb begin : next_state_logic
   next_state = IDLE;
      case(state)
      IDLE    : begin 
                   if( write ) begin
                       next_state = WRITE;
                   end
                   else begin
                     if (read) begin  
                       next_state = READ;
                     end
                     else begin
                       next_state = IDLE;
                     end
                   end 
                end
      WRITE     : begin
                   next_state = IDLE;
                end
      READ      : begin
                   next_state = IDLE;
                end
      default : next_state = IDLE;
   endcase
end


always_comb begin
   case(state)
   IDLE    : begin
               waitrequest  = 1'b1;
               readdatavalid= 1'b0;
             end
   WRITE     : begin 
               waitrequest  = 1'b0;
               readdatavalid= 1'b0;
             end
   READ     : begin 
               waitrequest  = 1'b0;
               readdatavalid= 1'b1;
             end
   default : begin 
               waitrequest  = 1'b1;
               readdatavalid= 1'b0;
             end
   endcase
end

always_ff@(posedge clk) begin
   if(~reset_n)
      state <= IDLE;
   else
      state <= next_state;
end

endmodule