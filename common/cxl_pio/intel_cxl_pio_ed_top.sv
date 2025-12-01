// (C) 2001-2024 Intel Corporation. All rights reserved.
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


//----------------------------------------------------------------------------- 
//  Project Name:  intel_cxl 
//  Module Name :  intel_cxl_pio_ed_top                                 
//  Author      :  ochittur                                   
//  Date        :  Aug 22, 2022                                 
//  Description :  Top file for PIO 
//-----------------------------------------------------------------------------

//`include "intel_cxl_pio_parameters.svh"
//`default_nettype none
module intel_cxl_pio_ed_top 
import ed_mc_axi_if_pkg::*;
#(
	parameter PF1_BAR01_SIZE_VALUE = 21,
	parameter BE_CH = 8,
	parameter BE_IDX = log2ceil(BE_CH)  
)
(
     		input              	 Clk_i		     ,
     		input              	 Rstn_i		     ,
		output logic             pio_txc_eop         ,
		output logic [127:0]     pio_txc_header      ,
		output logic [255:0]     pio_txc_payload     ,
		output logic             pio_txc_sop         ,
		output logic             pio_txc_valid       ,
		output logic           	  pio_to_send_cpl    , //pio about to send output
		input  logic         	 pio_txc_ready	     ,

		//from cust_afu_wrapper
		input logic [63:0] tx_start,
		input logic [63:0] tx_header_low,
		input logic [63:0] tx_header_high,
		input logic [63:0] tx_payload,

		input logic [63:0] pio_bar_addr,
		input logic [63:0] pio_requester_id,

		input logic 			pio_sqdb_valid,
		input logic [63:0] 		pio_sqdb_tail,
		output logic 			pio_sqdb_ready,

		input logic 			pio_cqdb_valid,
		input logic [63:0] 		pio_cqdb_head,
		output logic 			pio_cqdb_ready
);

//from PIO
logic             pio_txc_eop_real       ;
logic [127:0]     pio_txc_header_real    ;
logic [255:0]     pio_txc_payload_real   ;
logic             pio_txc_sop_real       ;
logic             pio_txc_valid_real     ;
logic             pio_to_send_cpl_real   ;

//from cust_afu_wrapper
// logic             pio_txc_eop_fake     ;
logic [127:0]     pio_txc_header_fake    ;
logic [255:0]     pio_txc_payload_fake   ;
// logic             pio_txc_sop_fake       ;
// logic             pio_txc_valid_fake     ;
// logic             pio_to_send_cpl_fake   ;

(* preserve_for_debug *) logic [127:0] 	  pio_rx_header_buffer;
(* preserve_for_debug *) logic [511:0]	  pio_rx_payload_buffer;

logic [63:0] nvme_bar;

assign nvme_bar = pio_bar_addr;

enum logic [2:0] {
	STATE_IDLE,
	STATE_PREPARE,
	STATE_TX,
	STATE_WAIT,
	STATE_FINISH
} state, next_state;

logic [63:0] cnt, next_cnt;
logic [1:0] sq_or_cq;

logic [BE_IDX-1:0] sqdb_idx; //todo: change to parameter
logic [BE_IDX-1:0] cqdb_idx; //todo: change to parameter
assign sqdb_idx = pio_sqdb_tail[63-:BE_IDX];
assign cqdb_idx = pio_cqdb_head[63-:BE_IDX];

always_ff @(posedge Clk_i) begin
	if (!Rstn_i) begin
		state <= STATE_IDLE;
		cnt <= 64'd0;
		pio_rx_header_buffer <= '0;
		pio_rx_payload_buffer <= '0;
		pio_txc_header_fake <= '0;
		pio_txc_payload_fake <= '0;
		sq_or_cq <= 2'b00;
	end
	else begin
		state <= next_state;
		cnt <= next_cnt;
		
		if (pio_sqdb_valid & pio_sqdb_ready) begin
			// unique case(pio_sqdb_tail[63:61])
			// 	3'b00: 	pio_txc_header_fake <= {nvme_bar+4096+8, 32'h0, pio_requester_id[15:0], 16'h000F,32'h60000001};
			// 	3'b01:	pio_txc_header_fake <= {nvme_bar+4096+16,32'h0, pio_requester_id[15:0], 16'h000F,32'h60000001};
			// 	3'b10:	pio_txc_header_fake <= {nvme_bar+4096+24,32'h0, pio_requester_id[15:0], 16'h000F,32'h60000001};
			// 	3'b11:	pio_txc_header_fake <= {nvme_bar+4096+32,32'h0, pio_requester_id[15:0], 16'h000F,32'h60000001};
			// 	3'b100:	pio_txc_header_fake <= {nvme_bar+4096+40,32'h0, pio_requester_id[15:0], 16'h000F,32'h60000001};
			// 	3'b101:	pio_txc_header_fake <= {nvme_bar+4096+48,32'h0, pio_requester_id[15:0], 16'h000F,32'h60000001};
			// 	3'b110:	pio_txc_header_fake <= {nvme_bar+4096+56,32'h0, pio_requester_id[15:0], 16'h000F,32'h60000001};
			// 	3'b111:	pio_txc_header_fake <= {nvme_bar+4096+64,32'h0, pio_requester_id[15:0], 16'h000F,32'h60000001};
			// endcase
			pio_txc_header_fake <= {nvme_bar+4096+8+ (sqdb_idx * 8), 32'h0, pio_requester_id[15:0], 16'h000F,32'h60000001};
			pio_txc_payload_fake <= {224'h0, pio_sqdb_tail[31:0]};
			sq_or_cq <= 2'b00;
		end
		else if (pio_cqdb_valid & pio_cqdb_ready) begin
			// unique case (pio_cqdb_head[63:61])
			// 	3'b00:	pio_txc_header_fake <= {nvme_bar+4096+12,32'h0, pio_requester_id[15:0], 16'h000F,32'h60000001};
			// 	3'b01:	pio_txc_header_fake <= {nvme_bar+4096+20,32'h0, pio_requester_id[15:0], 16'h000F,32'h60000001};
			// 	3'b10:	pio_txc_header_fake <= {nvme_bar+4096+28,32'h0, pio_requester_id[15:0], 16'h000F,32'h60000001};
			// 	3'b11:	pio_txc_header_fake <= {nvme_bar+4096+36,32'h0, pio_requester_id[15:0], 16'h000F,32'h60000001};
			// 	3'b100:	pio_txc_header_fake <= {nvme_bar+4096+44,32'h0, pio_requester_id[15:0], 16'h000F,32'h60000001};
			// 	3'b101:	pio_txc_header_fake <= {nvme_bar+4096+52,32'h0, pio_requester_id[15:0], 16'h000F,32'h60000001};
			// 	3'b110:	pio_txc_header_fake <= {nvme_bar+4096+60,32'h0, pio_requester_id[15:0], 16'h000F,32'h60000001};
			// 	3'b111:	pio_txc_header_fake <= {nvme_bar+4096+68,32'h0, pio_requester_id[15:0], 16'h000F,32'h60000001};
			// endcase
			pio_txc_header_fake <= {nvme_bar+4096+12 + (cqdb_idx * 8), 32'h0, pio_requester_id[15:0], 16'h000F,32'h60000001};
			pio_txc_payload_fake <= {224'h0, pio_cqdb_head[31:0]};
			sq_or_cq <= 2'b01;
		end
		else if (tx_start[0]) begin
			pio_txc_header_fake <= {tx_header_high, tx_header_low};
			pio_txc_payload_fake <= {192'h0, tx_payload};
			sq_or_cq <= 2'b10;
		end
	end
end

always_comb begin
	next_state = STATE_IDLE;
	next_cnt = cnt;

	pio_txc_eop     =     pio_txc_eop_real;
	pio_txc_header  =     pio_txc_header_real;
	pio_txc_payload =     pio_txc_payload_real;
	pio_txc_sop     =     pio_txc_sop_real;
	pio_txc_valid   =     pio_txc_valid_real;
	pio_to_send_cpl	= 	  pio_to_send_cpl_real;

	pio_sqdb_ready = 1'b0;
	pio_cqdb_ready = 1'b0;

	unique case(state) 
		STATE_IDLE: begin
			next_cnt = 64'd0;

			if (pio_sqdb_valid) begin
				pio_sqdb_ready = 1'b1;
			end
			else if (pio_cqdb_valid) begin
				pio_cqdb_ready = 1'b1;
			end

			if (pio_sqdb_valid | pio_cqdb_valid | tx_start[0]) begin
				next_state = STATE_PREPARE;
			end
			else begin
				next_state = STATE_IDLE;
			end
		end
		STATE_PREPARE: begin
			unique case(sq_or_cq) 
				2'b00: pio_sqdb_ready = 1'b1;
				2'b01: pio_cqdb_ready = 1'b1;
				default: begin

				end
			endcase

			pio_txc_eop     =     1'b1;
			pio_txc_header  =     pio_txc_header_fake;
			pio_txc_payload =     pio_txc_payload_fake;
			pio_txc_sop     =     1'b1;
			pio_txc_valid   =     1'b0;
			if (cnt >= 64'd2) begin
				pio_to_send_cpl	= 	  1'b1;
			end
			else begin
				pio_to_send_cpl	= 	  1'b0;
			end

			next_cnt = cnt + 64'd1;
			if (cnt == 64'd3) begin
				next_state = STATE_TX;
			end
			else begin
				next_state = STATE_PREPARE;
			end
		end
		STATE_TX: begin
			unique case(sq_or_cq) 
				2'b00: pio_sqdb_ready = 1'b1;
				2'b01: pio_cqdb_ready = 1'b1;
				default: begin

				end
			endcase

			pio_txc_eop     =     1'b1;
			pio_txc_header  =     pio_txc_header_fake;
			pio_txc_payload =     pio_txc_payload_fake;
			pio_txc_sop     =     1'b1;
			pio_txc_valid   =     1'b1;
			pio_to_send_cpl	= 	  1'b1;
			if (pio_txc_valid && pio_txc_ready) begin
				next_state = STATE_WAIT;
			end
			else begin
				next_state = STATE_TX;
			end
		end
		STATE_WAIT: begin
			unique case(sq_or_cq) 
				2'b00: pio_sqdb_ready = 1'b1;
				2'b01: pio_cqdb_ready = 1'b1;
				default: begin

				end
			endcase

			next_cnt = cnt + 64'd1;
			if (cnt == 64'd32) begin
				next_state = STATE_FINISH;
			end
			else begin
				next_state = STATE_WAIT;
			end
		end
		STATE_FINISH: begin
			next_state = STATE_IDLE;
		end
		default: begin

		end
	endcase
end

endmodule //intel_cxl_pio_ed_top