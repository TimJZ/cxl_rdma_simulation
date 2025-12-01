/*
Module: front_end
Purpose: control memory side state machine
10/22/25: new version, decouple MSHR and front_end logic, support more cache miss

Date: 10/22/25
*/

module front_end #(
  parameter MSHR_CH = 16
)
(

);


genvar i; 

front_end_process front_end_process_inst (

);

front_end_cafu front_end_cafu_inst (

);

front_end_afu front_end_afu_inst (

);

generate for (i=0; i<MSHR_CH; i++) begin : mshr_inst
    logic [51:0] phy_addr;    //
    logic [51:0] cache_index; //

    logic [511:0] mshr_data;
    logic conflict;

    logic rd_tag;
    logic wr_tag;
    logic rd_buf;

    logic mshr_valid;
    logic mshr_ready;
    logic mshr_busy; //occupied

    logic arvalid;
    logic arready;
    logic [11:0] arid;
    logic [63:0] araddr;
    logic [5:0] aruser;

    logic [11:0] rid;
    logic [511:0] rdata;
    logic rvalid;
    logic rready;

    logic awvalid;
    logic awready;
    logic 
end
endgenerate 










endmodule


