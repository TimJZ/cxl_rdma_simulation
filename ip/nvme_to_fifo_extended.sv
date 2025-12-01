module nvme_to_fifo_extended#(
    data_width = 771
) (
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



logic [data_width-1:0] q_reg;
logic init;  // Internal signals to drive wrfull and rdempty

initial begin
  init = 1'b0;
  #100
  init = 1'b1;
end

// Write logic (on wrclk)
always_ff @(posedge wrclk) begin
  if (!init) begin
    wrfull <= 1'b0;
    rdempty <= 1'b1;
  end
  else begin
    if (wrreq & !wrfull) begin
      wrfull <= 1'b1;      // FIFO is now full after writing
      rdempty <= 1'b0;     // FIFO is not empty after writing
      q_reg <= data;           // Store the input data in q_reg
    end
    else if (rdreq & !rdempty) begin
      wrfull <= 1'b0;      // FIFO is not full after reading
      rdempty <= 1'b1;     // FIFO is empty after reading
      q <= q_reg;              // Output the stored data
    end
  end
end

endmodule