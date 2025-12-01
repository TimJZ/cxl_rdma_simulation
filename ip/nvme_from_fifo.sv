module nvme_from_fifo #(
  parameter data_width = 540
)(
  input logic [data_width-1:0] data,
  input logic wrreq,
  input logic rdreq,
  input logic wrclk,
  input logic rdclk,
  input logic aclr,
  output logic [data_width-1:0] q,
  output logic rdempty,
  output logic wrfull
);

logic [data_width-1:0] q_reg [15:0];
logic init;  // Internal signals to drive wrfull and rdempty
logic [4:0] write_pointer;
logic [4:0] read_pointer;

initial begin
  init = 1'b0;
  #100
  init = 1'b1;
end

assign wrfull = (write_pointer[4] != read_pointer[4]) && (write_pointer[3:0] == read_pointer[3:0]); // FIFO is full when write_pointer reaches max
assign rdempty = (write_pointer == read_pointer); // FIFO is empty when write_pointer equals read_pointer

// Write logic (on wrclk)
always_ff @(posedge wrclk) begin
  if (!init) begin
    write_pointer <= 4'b0;
    read_pointer <= 4'b0;
  end
  else if (aclr) begin
    write_pointer <= 4'b0;
    read_pointer <= 4'b0;
  end
  else begin
    if (wrreq & !wrfull) begin
      q_reg[write_pointer[3:0]] <= data;           // Store the input data in q_reg
      write_pointer <= write_pointer + 1;
    end
    else if (rdreq & !rdempty) begin
      q <= q_reg[read_pointer[3:0]];              // Output the stored data
      read_pointer <= read_pointer + 1;
    end
  end
end

endmodule