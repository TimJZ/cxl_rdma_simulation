module cust_afu_cdc_wrapper #(
    parameter BE_CH = 8,
    parameter NUM_DEBUG = 16
)(
    input logic csr_avmm_clk,
    input logic csr_avmm_rst_n,

    input logic axi4_mm_clk,
    input logic axi4_mm_rst_n,

    //from csr_avmm to axi4_mm domain
    input  logic [63:0] page_addr_0_csr,
    output logic [63:0] page_addr_0_avmm,

    input  logic [63:0] test_case_csr,
    output logic [63:0] test_case_avmm,

    input  logic start_proc_csr,
    output logic start_proc_avmm,

    input  logic end_proc_csr,
    output logic end_proc_avmm,

    input  logic m5_query_en_csr,
    output logic m5_query_en_avmm,

    input  logic [63:0] m5_interval_csr,
    output logic [63:0] m5_interval_avmm,

    input  logic [63:0] write_data_csr [7:0],
    output logic [63:0] write_data_avmm[7:0],

    input  logic [63:0] tx_header_low_csr,
    output logic [63:0] tx_header_low_avmm,

    input  logic [63:0] tx_header_high_csr,
    output logic [63:0] tx_header_high_avmm,

    input  logic [63:0] tx_start_csr,
    output logic [63:0] tx_start_avmm,

    input  logic [63:0] tx_payload_csr,
    output logic [63:0] tx_payload_avmm,

    input  logic [63:0] afu_init_csr,
    output logic [63:0] afu_init_avmm,

    input  logic [63:0] sq_addr_csr  [BE_CH-1:0],
    output logic [63:0] sq_addr_avmm [BE_CH-1:0],

    input  logic [63:0] cq_addr_csr  [BE_CH-1:0],
    output logic [63:0] cq_addr_avmm [BE_CH-1:0],

    input  logic [63:0] sq_tail_csr  [BE_CH-1:0],
    output logic [63:0] sq_tail_avmm [BE_CH-1:0],

    input  logic [63:0] cq_head_csr  [BE_CH-1:0],
    output logic [63:0] cq_head_avmm [BE_CH-1:0],

    input  logic [63:0] host_buf_addr_csr  [BE_CH-1:0],
    output logic [63:0] host_buf_addr_avmm [BE_CH-1:0],

    input  logic host_buf_addr_valid_csr  [BE_CH-1:0],
    output logic host_buf_addr_valid_avmm [BE_CH-1:0],

    input  logic update_csr,
    output logic update_avmm,

    input  logic nvme_end_proc_csr,
    output logic nvme_end_proc_avmm,

    input  logic [63:0] delay_cnt_csr,
    output logic [63:0] delay_cnt_avmm,

    input  logic [63:0] pio_bar_addr_csr,
    output logic [63:0] pio_bar_addr_avmm,

    input  logic [63:0] pio_requester_id_csr,
    output logic [63:0] pio_requester_id_avmm,

    input  logic [63:0] block_index_offset_csr,
    output logic [63:0] block_index_offset_avmm,

    //from axi4_mm to csr_avmm domain
    input  logic [63:0] read_data_avmm [7:0],
    output logic [63:0] read_data_csr  [7:0],

    input  logic [63:0] debug_pf_avmm  [NUM_DEBUG-1:0],
    output logic [63:0] debug_pf_csr   [NUM_DEBUG-1:0]
);

logic [62:0] ignore               [BE_CH+4:0];

logic [63:0] host_buf_addr_data   [BE_CH-1:0];
logic [63:0] host_buf_addr_q      [BE_CH-1:0];

logic host_buf_addr_valid_data    [BE_CH-1:0];
logic host_buf_addr_valid_q       [BE_CH-1:0];
logic host_buf_addr_valid_wrreq   [BE_CH-1:0];
logic host_buf_addr_valid_rdreq   [BE_CH-1:0];
logic host_buf_addr_valid_rdempty [BE_CH-1:0];
logic host_buf_addr_valid_rdvalid [BE_CH-1:0];
logic host_buf_addr_valid_wrfull  [BE_CH-1:0];

always_ff @(posedge csr_avmm_clk) begin
    if (!csr_avmm_rst_n) begin
        for (int i=0; i<BE_CH; i++) begin
            host_buf_addr_valid_wrreq[i] <= '0;
        end
    end
    else begin
        for (int i=0; i<BE_CH; i++) begin
            if (host_buf_addr_valid_csr[i]) begin
                host_buf_addr_valid_wrreq[i] <= 1'b1;
                host_buf_addr_valid_data[i] <= host_buf_addr_valid_csr[i];
                host_buf_addr_data[i] <= host_buf_addr_csr[i];
            end
            else begin
                host_buf_addr_valid_wrreq[i] <= 1'b0;
            end
        end
    end
end

always_ff @(posedge axi4_mm_clk) begin
    if (!axi4_mm_rst_n) begin
        // for (int i=0; i<BE_CH; i++) begin
        //     host_buf_addr_valid_rdreq[i] <= '0;
        // end
    end
    else begin
        for (int i=0; i<BE_CH; i++) begin
            if (host_buf_addr_valid_rdreq[i]) begin
                host_buf_addr_valid_rdvalid[i] <= 1'b1;
            end
            else begin
                host_buf_addr_valid_rdvalid[i] <= 1'b0;
            end
        end
    end
end

always_comb begin
    for (int i=0; i<BE_CH; i++) begin
        if (!host_buf_addr_valid_rdempty[i]) begin
            host_buf_addr_valid_rdreq[i] = 1'b1;
        end
        else begin
            host_buf_addr_valid_rdreq[i] = 1'b0;
        end

        if (host_buf_addr_valid_rdvalid[i]) begin
            host_buf_addr_valid_avmm[i] = host_buf_addr_valid_q[i];
            host_buf_addr_avmm[i] = host_buf_addr_q[i];
        end
        else begin
            host_buf_addr_valid_avmm[i] = 1'b0;
            host_buf_addr_avmm[i] = 64'b0;
        end
    end
end


fifo page_addr_cdc_inst (
  .data(page_addr_0_csr),
  .wrreq(1'b1),
  .rdreq(1'b1),
  .wrclk(csr_avmm_clk),
  .rdclk(axi4_mm_clk),
  .q(page_addr_0_avmm),
  .rdempty(),
  .wrfull()
);

fifo test_case_cdc_inst (
  .data(test_case_csr),
  .wrreq(1'b1),
  .rdreq(1'b1),
  .wrclk(csr_avmm_clk),
  .rdclk(axi4_mm_clk),
  .q(test_case_avmm),
  .rdempty(),
  .wrfull()
);

fifo start_proc_cdc_inst (
  .data({63'b0, start_proc_csr}),
  .wrreq(1'b1),
  .rdreq(1'b1),
  .wrclk(csr_avmm_clk),
  .rdclk(axi4_mm_clk),
  .q({ignore[BE_CH], start_proc_avmm}),
  .rdempty(),
  .wrfull()
);

fifo end_proc_cdc_inst (
  .data({63'b0, end_proc_csr}),
  .wrreq(1'b1),
  .rdreq(1'b1),
  .wrclk(csr_avmm_clk),
  .rdclk(axi4_mm_clk),
  .q({ignore[BE_CH+1], end_proc_avmm}),
  .rdempty(),
  .wrfull()
);

fifo m5_query_en_cdc_inst (
  .data({63'b0, m5_query_en_csr}),
  .wrreq(1'b1),
  .rdreq(1'b1),
  .wrclk(csr_avmm_clk),
  .rdclk(axi4_mm_clk),
  .q({ignore[BE_CH+2], m5_query_en_avmm}),
  .rdempty(),
  .wrfull()
);

fifo m5_interval_cdc_inst (
  .data(m5_interval_csr),
  .wrreq(1'b1),
  .rdreq(1'b1),
  .wrclk(csr_avmm_clk),
  .rdclk(axi4_mm_clk),
  .q(m5_interval_avmm),
  .rdempty(),
  .wrfull()
);

generate for (genvar i=0; i<8; i++) begin: read_write_data  
        fifo read_data_fifo (
            .data(read_data_avmm[i]),
            .wrreq(1'b1),
            .rdreq(1'b1),
            .wrclk(axi4_mm_clk),
            .rdclk(csr_avmm_clk),
            .q(read_data_csr[i]),
            .rdempty(),
            .wrfull()
        );
        fifo write_data_fifo (
            .data(write_data_csr[i]),
            .wrreq(1'b1),
            .rdreq(1'b1),
            .wrclk(csr_avmm_clk),
            .rdclk(axi4_mm_clk),
            .q(write_data_avmm[i]),
            .rdempty(),
            .wrfull()    
        );
    end 
endgenerate

fifo tx_header_low_cdc_inst (
  .data(tx_header_low_csr),
  .wrreq(1'b1),
  .rdreq(1'b1),
  .wrclk(csr_avmm_clk),
  .rdclk(axi4_mm_clk),
  .q(tx_header_low_avmm),
  .rdempty(),
  .wrfull()
);

fifo tx_header_high_cdc_inst (
  .data(tx_header_high_csr),
  .wrreq(1'b1),
  .rdreq(1'b1),
  .wrclk(csr_avmm_clk),
  .rdclk(axi4_mm_clk),
  .q(tx_header_high_avmm),
  .rdempty(),
  .wrfull()
);

fifo tx_start_cdc_inst (
  .data(tx_start_csr),
  .wrreq(1'b1),
  .rdreq(1'b1),
  .wrclk(csr_avmm_clk),
  .rdclk(axi4_mm_clk),
  .q(tx_start_avmm),
  .rdempty(),
  .wrfull()
);

fifo tx_payload_cdc_inst (
  .data(tx_payload_csr),
  .wrreq(1'b1),
  .rdreq(1'b1),
  .wrclk(csr_avmm_clk),
  .rdclk(axi4_mm_clk),
  .q(tx_payload_avmm),
  .rdempty(),
  .wrfull()
);

fifo afu_init_cdc_inst (
  .data(afu_init_csr),
  .wrreq(1'b1),
  .rdreq(1'b1),
  .wrclk(csr_avmm_clk),
  .rdclk(axi4_mm_clk),
  .q(afu_init_avmm),
  .rdempty(),
  .wrfull()
);

genvar j;
generate 
  for (j=0; j<BE_CH; j++) begin: nvme_pair
    fifo sq_addr_cdc_inst (
      .data(sq_addr_csr[j]),
      .wrreq(1'b1),
      .rdreq(1'b1),
      .wrclk(csr_avmm_clk),
      .rdclk(axi4_mm_clk),
      .q(sq_addr_avmm[j]),
      .rdempty(),
      .wrfull()
    );

    fifo cq_addr_cdc_inst (
      .data(cq_addr_csr[j]),
      .wrreq(1'b1),
      .rdreq(1'b1),
      .wrclk(csr_avmm_clk),
      .rdclk(axi4_mm_clk),
      .q(cq_addr_avmm[j]),
      .rdempty(),
      .wrfull()
    );


    fifo sq_tail_cdc_inst (
      .data(sq_tail_csr[j]),
      .wrreq(1'b1),
      .rdreq(1'b1),
      .wrclk(csr_avmm_clk),
      .rdclk(axi4_mm_clk),
      .q(sq_tail_avmm[j]),
      .rdempty(),
      .wrfull()
    );

    fifo cq_head_cdc_inst (
      .data(cq_head_csr[j]),
      .wrreq(1'b1),
      .rdreq(1'b1),
      .wrclk(csr_avmm_clk),
      .rdclk(axi4_mm_clk),
      .q(cq_head_avmm[j]),
      .rdempty(),
      .wrfull()
    );

    fifo host_buf_addr_cdc_inst (
      .data(host_buf_addr_data[j]),
      .wrreq(host_buf_addr_valid_wrreq[j]),
      .rdreq(host_buf_addr_valid_rdreq[j]),
      .wrclk(csr_avmm_clk),
      .rdclk(axi4_mm_clk),
      .q(host_buf_addr_q[j]),
      .rdempty(host_buf_addr_valid_rdempty[j]),
      .wrfull(host_buf_addr_valid_wrfull[j])
    );

    fifo host_buf_addr_valid_cdc_inst (
      .data({63'b0, host_buf_addr_valid_data[j]}),
      .wrreq(host_buf_addr_valid_wrreq[j]),
      .rdreq(host_buf_addr_valid_rdreq[j]),
      .wrclk(csr_avmm_clk),
      .rdclk(axi4_mm_clk),
      .q({ignore[j], host_buf_addr_valid_q[j]}),
      .rdempty(),
      .wrfull()
    );
  end
endgenerate

fifo update_cdc_inst (
  .data({63'b0, update_csr}),
  .wrreq(1'b1),
  .rdreq(1'b1),
  .wrclk(csr_avmm_clk),
  .rdclk(axi4_mm_clk),
  .q({ignore[BE_CH+3], update_avmm}),
  .rdempty(),
  .wrfull()
);

fifo end_cdc_inst (
  .data({63'b0, nvme_end_proc_csr}),
  .wrreq(1'b1),
  .rdreq(1'b1),
  .wrclk(csr_avmm_clk),
  .rdclk(axi4_mm_clk),
  .q({ignore[BE_CH+4], nvme_end_proc_avmm}),
  .rdempty(),
  .wrfull()
);

fifo delay_cnt_cdc_inst (
  .data(delay_cnt_csr),
  .wrreq(1'b1),
  .rdreq(1'b1),
  .wrclk(csr_avmm_clk),
  .rdclk(axi4_mm_clk),
  .q(delay_cnt_avmm),
  .rdempty(),
  .wrfull()
);

fifo pio_bar_addr_cdc_inst (
  .data(pio_bar_addr_csr),
  .wrreq(1'b1),
  .rdreq(1'b1),
  .wrclk(csr_avmm_clk),
  .rdclk(axi4_mm_clk),
  .q(pio_bar_addr_avmm),
  .rdempty(),
  .wrfull()
);

fifo pio_requester_id_cdc_inst (
  .data(pio_requester_id_csr),
  .wrreq(1'b1),
  .rdreq(1'b1),
  .wrclk(csr_avmm_clk),
  .rdclk(axi4_mm_clk),
  .q(pio_requester_id_avmm),
  .rdempty(),
  .wrfull()
);

fifo block_index_offset_cdc_inst (
  .data(block_index_offset_csr),
  .wrreq(1'b1),
  .rdreq(1'b1),
  .wrclk(csr_avmm_clk),
  .rdclk(axi4_mm_clk),
  .q(block_index_offset_avmm),
  .rdempty(),
  .wrfull()
);

generate 
  for (j=0; j<NUM_DEBUG; j++) begin: debug_sig
    fifo debug_pf_cdc_inst (
      .data(debug_pf_avmm[j]),
      .wrreq(1'b1),
      .rdreq(1'b1),
      .wrclk(axi4_mm_clk),
      .rdclk(csr_avmm_clk),
      .q(debug_pf_csr[j]),
      .rdempty(),
      .wrfull()
    );
  end
endgenerate

endmodule
