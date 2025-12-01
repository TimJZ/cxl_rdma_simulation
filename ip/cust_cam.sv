module cust_cam #(
    parameter DEPTH = 16,
    parameter ADDR_WIDTH = $clog2(DEPTH),
    parameter DATA_WIDTH = 64
)
(
    input  logic         clk,
    input  logic         rst_n,

    //write interface
    input  logic [ADDR_WIDTH-1:0]   wr_addr,
    input  logic [DATA_WIDTH-1:0]   wr_data,
    input  logic                    wr_req,

    //read interface
    input logic [ADDR_WIDTH-1:0]    rd_addr,
    input logic                     rd_req,
    output logic [DATA_WIDTH-1:0]   rd_data
);


logic [DATA_WIDTH-1:0] mem [0:DEPTH-1];

always_ff @(posedge clk) begin
    if (!rst_n) begin
        rd_data <= '0;
    end else begin
        if (rd_req) begin
            rd_data <= mem[rd_addr];
        end

        if (wr_req) begin
            mem[wr_addr] <= wr_data;
        end
    end
end

endmodule : cust_cam