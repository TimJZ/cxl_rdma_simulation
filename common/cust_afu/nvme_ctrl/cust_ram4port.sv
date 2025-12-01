module cust_ram4port(
    input logic [770:0] data_a,
    input logic [2:0] write_address_a,
    input logic wren_a,

    output logic [770:0] q_a,
    output logic [770:0] q_b,
    input logic [2:0] read_address_a,
    input logic [2:0] read_address_b,

    input logic clock
);

logic [770:0] mem [7:0];

always_ff @(posedge clock) begin
    if (wren_a) begin
        mem[write_address_a] <= data_a; // Write data to port A
    end
end

always_ff @(posedge clock) begin
    q_a <= mem[read_address_a]; // Read data from port A
    q_b <= mem[read_address_b]; // Read data from port B
end

endmodule