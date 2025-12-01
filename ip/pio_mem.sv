module pio_mem (
    input logic axi4_mm_clk,
    input logic axi4_mm_rst_n,

    //to pio
    input ed_mc_axi_if_pkg::t_to_pio_axi4 to_pio_axi4,
    output ed_mc_axi_if_pkg::t_from_pio_axi4 from_pio_axi4
);

logic [1023:0] pio_memory_array [63:0];

enum logic [1:0] {
    STATE_IDLE,
    STATE_READ,
    STATE_WRITE
} state, next_state;

always_ff @(posedge axi4_mm_clk) begin
    if (!axi4_mm_rst_n) begin
        state <= STATE_IDLE;
        for (int i=0; i<64; i++) begin
            pio_memory_array[i] <= (2*i+1)<<512 + 2*i;
        end
    end
    else begin
        state <= next_state;

        unique case (state)
            STATE_IDLE: begin
                // No action needed in idle state
            end
            STATE_READ: begin
                // Read operation, data is already set in next_state logic
            end
            STATE_WRITE: begin
                // Write operation, data is already set in next_state logic
                pio_memory_array[to_pio_axi4.awaddr[13:8]] <= to_pio_axi4.wdata;
            end
        endcase


        if (to_pio_axi4.arvalid && from_pio_axi4.arready) begin
            // Handle read request
            $display("PIO Read: Address = %h, Data = %h", to_pio_axi4.araddr, pio_memory_array[to_pio_axi4.araddr[13:8]]);
        end
        if (to_pio_axi4.awvalid && from_pio_axi4.awready) begin
            // Handle write request
            $display("PIO Write: Address = %h, Data = %h", to_pio_axi4.awaddr, to_pio_axi4.wdata);
        end
    end
end

always_comb begin
    next_state = STATE_IDLE;
    from_pio_axi4.arready = 0;
    from_pio_axi4.awready = 0;
    from_pio_axi4.rvalid = 0;
    from_pio_axi4.rdata = '0;
    from_pio_axi4.bvalid = 0;

    unique case (state)
        STATE_IDLE: begin
            if (to_pio_axi4.arvalid) begin
                from_pio_axi4.arready = 1;
                next_state = STATE_READ;
            end
            else if (to_pio_axi4.awvalid && to_pio_axi4.wvalid) begin
                from_pio_axi4.awready = 1;
                next_state = STATE_WRITE;
            end
            else begin
                next_state = STATE_IDLE;
            end
        end
        STATE_READ: begin
            from_pio_axi4.rvalid = 1;
            from_pio_axi4.rdata = pio_memory_array[to_pio_axi4.araddr[13:8]];
            if (to_pio_axi4.rready) begin
                next_state = STATE_IDLE;
            end
            else begin
                next_state = STATE_READ;
            end
        end
        STATE_WRITE: begin
            from_pio_axi4.bvalid = 1;
            if (to_pio_axi4.bready) begin
                next_state = STATE_IDLE;
            end
            else begin
                next_state = STATE_WRITE;
            end
        end
        default: begin
            
        end
    endcase
end



endmodule