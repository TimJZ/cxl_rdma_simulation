module fifo #(
  parameter DATA_WIDTH = 64,
  parameter FIFO_DEPTH = 64
)(
  input logic [DATA_WIDTH-1:0] data,
  input logic wrreq,
  input logic rdreq,
  input logic wrclk,
  input logic rdclk,
  output logic [DATA_WIDTH-1:0] q,
  output logic rdempty,
  output logic wrfull
);

logic [(DATA_WIDTH-1):0] fifo_mem [0:(FIFO_DEPTH-1)];
logic [$clog2(FIFO_DEPTH):0] wr_ptr = 0, rd_ptr = 0;

assign rdempty = (wr_ptr == rd_ptr);
assign wrfull  = ((wr_ptr - rd_ptr) == FIFO_DEPTH);

always_ff @(posedge wrclk) begin
  if (wrreq && !wrfull) begin
    fifo_mem[wr_ptr[$clog2(FIFO_DEPTH)-1:0]] <= data;
    wr_ptr <= wr_ptr + 1;
  end

  if (rdreq && !rdempty) begin
    q <= fifo_mem[rd_ptr[$clog2(FIFO_DEPTH)-1:0]];
    rd_ptr <= rd_ptr + 1;
  end
end


endmodule