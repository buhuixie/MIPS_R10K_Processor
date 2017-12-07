module preg_file(
		input						clk,
		input						rst,
		input						wr_en_i,
		input	[`PRF_IDX_W-1:0]	rda_idx_i,rdb_idx_i, wr_idx_i,
		input	[63:0]				wr_data_i,


		output	logic	[63:0]		rda_data_o, rdb_data_o,

		// <12/6> ports for writeback in tb
		input	[`PRF_IDX_W-1:0]	retire_preg_idx_tb_i,
		output	logic	[63:0]		retire_areg_val_tb_o
	
		);

	logic	[`PRF_NUM-1:0][63:0]	reg_data_r;
		
	wire	[63:0]		rda_reg = reg_data_r[rda_idx_i];
	wire	[63:0]		rdb_reg = reg_data_r[rdb_idx_i];
	
	always_comb begin
		if(rda_idx_i == `ZERO_REG)
			rda_data_o = 0;
		else
			rda_data_o = rda_reg;
	end
	
		
	always_comb begin
		if(rdb_idx_i == `ZERO_REG)
			rdb_data_o = 0;
		else
			rdb_data_o = rdb_reg;
	end
	// synopsys sync_set_reset "rst"
	always_ff @(posedge clk) begin
		if(rst)
			reg_data_r <= `SD {`PRF_NUM{64'h0}};
		else if (wr_en_i)
			reg_data_r[wr_idx_i] <= `SD wr_data_i;
	end

	// <12/6> ports for writeback
	assign retire_areg_val_tb_o	= reg_data_r[retire_preg_idx_tb_i];

endmodule
