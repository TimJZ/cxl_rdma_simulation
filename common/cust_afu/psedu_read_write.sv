/*
Version: 5.0.1
Modified: 24/01/24
Purpose: simulate read/write
test_case:  
0. idle

Timing method = T(last data recv) - T(first request)
1. NC RD random #num_request requests at once, host
2. CO RD random #num_request requests at once, host
3. CS RD random #num_request requests at once, host
4. NC RD random #num_request requests at once, HDM, device bias
5. CO RD random #num_request requests at once, HDM, device bias
6. CS RD random #num_request requests at once, HDM, device bias
7. NC RD random #num_request requests at once, HDM, host bias
8. CO RD random #num_request requests at once, HDM, host bias
9. CS RD random #num_request requests at once, HDM, host bias

//switch on wready and awready version
Timing method = T(last b channel response recv) - T(first request)
10. NC WR random #num_request requests, host
11. CO WR random #num_request requests, host
12. NCP WR random #num_request requests, host
13. NC WR random #num_request requests, HDM, device bias
14. CO WR random #num_request requests, HDM, device bias
15. NCP WR random #num_request requests, HDM, device bias
16. NC WR random #num_request requests, HDM, host bias
17. CO WR random #num_request requests, HDM, host bias
18. NCP WR random #num_request requests, HDM, host bias

73. barrier
74. flush single DCOH host cache
75. flush entire DCOH host cache
76. flush entire DCOH device cache
*/
module psedu_read_write (
    input logic axi4_mm_clk,
    input logic axi4_mm_rst_n,
    
    input logic start_proc,
    input logic end_proc,
    input logic [63:0] page_addr_0,
    input logic [63:0] test_case,
    output logic [63:0] read_data [7:0],
    input logic [63:0] write_data [7:0],

    input logic rvalid,
    input logic rlast,
    input logic [511:0] rdata,
    input logic [1:0] rresp,
    input logic arready,
    input logic wready,
    input logic awready,
    input logic bvalid,
    input logic [1:0] bresp,
    output logic arvalid,
    output logic [11:0] arid,
    output logic [5:0] aruser,
    input logic rready,
    output logic awvalid,
    output logic [11:0] awid,
    output logic [5:0] awuser,
    output logic wvalid,
    output logic [511:0] wdata,
    output logic wlast, 
    output logic [(512/8)-1:0] wstrb, 
    input logic bready, 
    // input logic [11:0] bid,
    output logic [63:0] araddr,
    output logic [63:0] awaddr
);

    enum logic [4:0] {
        STATE_IDLE,
        STATE_R_WAIT,
        STATE_W_WAIT,
        STATE_ADDR,
        STATE_DATA,
        STATE_R64,
        STATE_W64,
        STATE_WRES,
        STATE_R_DONE,
        STATE_W_DONE,
        STATE_EXCEP
    } state;

    logic [63:0] random_offset_32K;
    logic [63:0] random_offset_128K;
    logic [63:0] random_offset_1M;
    logic [63:0] random_offset_4M;
    logic [63:0] random_offset_16M;
    logic [63:0] random_offset_32M;
    logic [63:0] rw_cnt;
    // assign rready = 1'b1;
    // assign bready = 1'b1;
/*---------------------------------
functions
-----------------------------------*/


/*---------------------------------
state machine
-----------------------------------*/
    always_ff @(posedge axi4_mm_clk) begin
        if (!axi4_mm_rst_n) begin
            state <= STATE_IDLE;
            arvalid <= '0;
            aruser <= '0;
            arid <= '0;
            awvalid <= '0;
            awuser <= '0;
            awid <= '0;
            wvalid <= '0;
            wdata <= '0;
            wlast <= '0;
            wstrb <= '0;
            rw_cnt <= '0;
        end
        else if (end_proc) begin
            state <= STATE_IDLE;
            arvalid <= '0;
            aruser <= '0;
            arid <= '0;
            awvalid <= '0;
            awuser <= '0;
            awid <= '0;
            wvalid <= '0;
            wlast <= '0;
            wdata <= '0; 
            wstrb <= '0;
            rw_cnt <= '0;
        end
        else begin
            unique case (test_case)
/*--------------
latency test
----------------*/
                64'd1, 64'd2, 64'd3, 64'd4, 64'd5, 64'd6, 64'd7, 64'd8, 64'd9: begin //RD request
                    if (state == STATE_IDLE) begin
                        if (start_proc == 1'b1) begin
                            state <= STATE_ADDR;
                            unique case (test_case)
                                64'd1: begin
                                    aruser <= 6'b000000; //non-cacheable
                                end
                                64'd3: begin
                                    aruser <= 6'b000001; //cacheable shared
                                end
                                64'd2: begin
                                    aruser <= 6'b000010; //cacheable owned
                                end
                                64'd4: begin
                                    aruser <= 6'b110000; //non-cacheable
                                end
                                64'd6: begin
                                    aruser <= 6'b110001; //cacheable shared
                                end
                                64'd5: begin
                                    aruser <= 6'b110010; //cacheable owned
                                end
                                64'd7: begin
                                    aruser <= 6'b100000; //non-cacheable
                                end
                                64'd9: begin
                                    aruser <= 6'b100001; //cacheable shared
                                end
                                64'd8: begin
                                    aruser <= 6'b100010; //cacheable owned
                                end

                                default: begin
                                    aruser <= 6'b000000; //non-cacheable
                                end
                            endcase

                            arid <= 12'd0;
                            arvalid <= 1'b1;
                        end
                        else begin
                            state <= STATE_IDLE;
                        end
                    end
                    else if (state == STATE_ADDR) begin
                        if (arready) begin
                            state <= STATE_R_DONE;
                            arvalid <= 1'b0;                           
                        end
                        else begin
                            state <= STATE_ADDR;
                            arid <= arid;
                            aruser <= aruser;
                            arvalid <= 1'b1;
                        end
                    end
                    else begin
                        state <= state;
                        arvalid <= 1'b0;
                    end
                end

                64'd10, 64'd11, 64'd12, 64'd13, 64'd14, 64'd15, 64'd16, 64'd17, 64'd18: begin //all WR sequential 16 times
                    if (state == STATE_IDLE) begin
                        if (start_proc == 1'b1) begin
                            state <= STATE_ADDR;
                            //address
                            awid <= 12'd1;
                            awvalid <= 1'b1;
                            unique case (test_case)
                                64'd10: begin
                                    awuser <= 6'b000000; //non-cacheable
                                end        
                                64'd11: begin
                                    awuser <= 6'b000001; //cacheable own
                                end
                                64'd12: begin
                                    awuser <= 6'b000010; //non-cacheable push
                                end
                                64'd13: begin
                                    awuser <= 6'b110000; //non-cacheable
                                end        
                                64'd14: begin
                                    awuser <= 6'b110001; //cacheable own
                                end
                                64'd15: begin
                                    awuser <= 6'b110010; //non-cacheable push
                                end
                                64'd16: begin
                                    awuser <= 6'b100000; //non-cacheable
                                end        
                                64'd17: begin
                                    awuser <= 6'b100001; //cacheable own
                                end
                                64'd18: begin
                                    awuser <= 6'b100010; //non-cacheable push
                                end

                                default: begin
                                    awuser <= 6'b000000; //non-cacheable
                                end
                            endcase

                            //data
                            wvalid <= 1'b1;
                            wdata <= {write_data[7], write_data[6],write_data[5],write_data[4],write_data[3],write_data[2],write_data[1],write_data[0]};
                            wlast <= 1'b1;
                            wstrb <= 64'hffffffffffffffff;
                        end
                        else begin
                            state <= STATE_IDLE;
                        end
                    end
                    else if (state == STATE_ADDR) begin
                        //change status
                        if (awready & wready) begin
                            state <= STATE_W_DONE;
                            awvalid <= 1'b0;
                            wvalid <= 1'b0;
                        end
                        else if (wvalid == 1'b0) begin
                            if (awready) begin
                                state <= STATE_W_DONE;
                                awvalid <= 1'b0;
                                wvalid <= 1'b0;
                            end
                            else begin
                                state <= STATE_ADDR;
                            end
                        end
                        else if (awvalid == 1'b0) begin
                            if (wready) begin
                                state <= STATE_W_DONE;
                                awvalid <= 1'b0;
                                wvalid <= 1'b0;
                            end
                            else begin
                                state <= STATE_ADDR; 
                            end
                        end
                        else begin
                            //change address
                            if (awready) begin
                                awvalid <= 1'b0;
                            end
                            else begin
                                awvalid <= awvalid;
                            end
                            //change data
                            if (wready) begin
                                wvalid <= 1'b0; 
                                wlast <= 1'b0;
                                wstrb <= 64'h0;
                                wdata <= '0;
                            end
                            else begin
                                wvalid <= wvalid;
                                wlast <= wlast;
                                wstrb <= wstrb;
                                wdata <= wdata;
                            end
                            state <= STATE_ADDR;
                        end
                    end
                    else if (state == STATE_W_DONE) begin
                        if (bvalid & bready) begin
                            // if (bid == 12'd1) begin
                            //     state <= STATE_R_DONE;
                            // end
                            // else begin
                            //     state <= STATE_W_DONE;
                            // end
                            state <= STATE_R_DONE;
                        end
                        else begin
                            state <= STATE_W_DONE;
                        end
                    end
                    else begin
                        state <= state; 
                        awvalid <= 1'b0;
                    end
                end

                64'd73,64'd74,64'd75,64'd76: begin
                    if (state == STATE_IDLE) begin
                        if (start_proc == 1'b1) begin
                            state <= STATE_ADDR;
                            awvalid <= 1'b1;
                            if (test_case == 64'd73) begin //barrier
                                awuser <= 6'b000011; 
                            end
                            else if (test_case == 64'd74) begin //flush single DCOH cache line
                                awuser <= 6'b000100; 
                            end
                            else if (test_case == 64'd75) begin //flush entire DCOH host cache
                                awuser <= 6'b000101; 
                            end
                            else if (test_case == 64'd76) begin //flush entire DCOH device cache
                                awuser <= 6'b000110; 
                            end
                            else begin //should never enter this case
                                awuser <= 6'b111111; 
                            end
                        end
                        else begin
                            state <= STATE_IDLE;
                        end
                    end
                    else if (state == STATE_ADDR) begin
                        if (awready) begin
                            state <= STATE_DATA;
                            awvalid <= 1'b0;
                            wvalid <= 1'b1;
                            wlast <= 1'b1;
                            wstrb <= 64'h0;
                        end
                        else begin
                            state <= STATE_ADDR;
                            awvalid <= 1'b1;
                        end
                    end
                    else if (state == STATE_DATA) begin
                        if (wready) begin
                            state <= STATE_WRES;
                            wvalid <= 1'b0;
                            wlast <= 1'b0;
                            wstrb <= 64'h0;
                        end
                        else begin
                            state <= STATE_DATA;
                            wvalid <= 1'b1;
                            wlast <= 1'b1;
                            wstrb <= wstrb; 
                        end
                    end
                    else if (state == STATE_WRES) begin
                        if (bvalid) begin
                            state <= STATE_W_WAIT;
                        end
                        else begin
                            state <= STATE_WRES;
                        end
                    end
                    else if (state == STATE_W_WAIT) begin
                        if (!bvalid) begin
                            state <= STATE_W_DONE;
                        end
                        else begin
                            state <= STATE_W_WAIT;
                        end
                    end
                    else begin
                        state <= state; 
                        awvalid <= 1'b0;
                    end       
                end

                default: begin
                    state <= state; 
                    awvalid <= 1'b0;
                    arvalid <= 1'b0;
                end
            endcase
        end
    end

    always_ff @(posedge axi4_mm_clk) begin
        if (rvalid & rready) begin
            {read_data[7], read_data[6], read_data[5], read_data[4],read_data[3],read_data[2],read_data[1],read_data[0]} <= rdata;
        end
    end

    always_comb begin
        araddr = page_addr_0;
        awaddr = page_addr_0;
    end

endmodule