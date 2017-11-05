module fu_main(
		input clk;
		input rst;
		
		input		[63:0]				rob2fu_PC_i,
		input 		[`ROB_IDX_W-1:0]	rs2fu_rob_idx_i,
		input 		[63:0]				rs2fu_ra_value_i,
		input		[63:0]				rs2fu_rb_value_i,
		input		[`PRF_IDX_W-1:0]	rs2fu_dest_tag_i,
		input		[31:0]				rs2fu_IR_i,
		input		[`FU_SEL_W-1:0]		rs2fu_sel_i,

		output							fu2preg_wr_en_o,
		output 		[`PRF_IDX_W-1:0]	fu2preg_wr_idx_o,
		output 		[63:0]				fu2preg_wr_value_o,
		output							fu2rob_done_o,
		output		[`ROB_IDX_W-1:0]	fu2rob_idx_o,
		output							fu2rob_br_taken_o,
		output		[63:0]				fu2rob_br_target_o,
		output 		[`PRF_IDX_W-1:0]	fu_cdb_broad_o
	);

	logic		[`PRF_IDX_W-1:0]	cdb_tag_r,cdb_tag_r_nxt;
	logic		[`EX_UNIT_W-1:0]	ex_unit_en;
	logic		[`HT_W-1:0]			rob_num_r;
	
	logic		[63:0]				int_alu_result;
	logic							int_alu_done;
	logic		[`PRF_IDX_W-1:0]	int_alu_dest_tag;
	logic		[`HT_W-1:0]			int_alu_rob_idx;
	
	logic							br_alu_done;
	logic		[63:0]				br_target;
	logic							br_taken;
	logic		[`HT_W-1:0] 		br_rob_idx;
	
	logic		[63:0]				mult_result;
	logic							mult_done;
	logic		[`HT_W-1:0]			mult_rob_idx;
	logic		[`PRF_IDX_W-1:0]	mult_dest_reg;
	
	//wire [63:0] mem_disp = { {48{rs2fu_IR_i[15]}}, rs2fu_IR_i[15:0] };
	//wire [63:0] br_disp  = { {41{rs2fu_IR_i[20]}}, rs2fu_IR_i[20:0], 2'b00 };
	assign fu2preg_wr_en_o		= int_alu_done | mult_done;
	assign fu2preg_wr_idx_o		= (int_alu_done & int_alu_dest_tag) | (mult_done & mult_dest_tag);
	assign fu2preg_wr_value_o	= int_alu_done ? int_alu_result :
								  mult_alu_done ? mult_alu_result : 0;

	assign fu2rob_done_o 		= int_alu_done | br_alu_done | mult_done;	
	assign fu2rob_idx_o			= br_alu_done ? br_rob_idx : 
								  mult_done ? mult_rob_idx : 
	   							  int_alu_done ? int_alu_rob_idx : 0;
	assign fu2rob_br_taken_o	= br_alu_done ? br_taken : 0;
	assign fu2rob_br_target_o	= br_alu_done ? br_target : 0;
	assign fu_cdb_broad_o		= cdb_tag_r;

	assign cdb_tag_r_nxt		= (int_alu_done & int_alu_dest_tag) | (mult_done & mult_dest_tag);  
	
	always_comb begin
		case (rs2fu_sel_i)
			`FU_SEL_NONE:	ex_unit_en = `EX_UNIT_W'b00000;
			`FU_SEL_ALU :	ex_unit_en = `EX_UNIT_W'b00001;
			`FU_SEL_BR:		ex_unit_en = `EX_UNIT_W'b00010;
			`FU_SEL_MULT:	ex_unit_en = `EX_UNIT_W'b00100;
			`FU_SEL_LOAD:	ex_unit_en = `EX_UNIT_W'b01000;
			`FU_SEL_STORE:	ex_unit_en = `EX_UNIT_W'b10000;
			default:		ex_unit_en = `EX_UNIT_W'b00000;
		endcase

	end	
	
	always_ff @(posedge clk) begin
		if (rst)
			cdb_tag_r <= `SD 0;
		else
			cdb_tag_r <= `SD cdb_tag_nxt;	
	end

	int_alu int_alu1 (
			.clk,
			.rst,
			.start_i(ex_unit_en[0]),
			.opa_i(rs2fu_ra_value_i),
			.opb_i(rs2fu_rb_value_i),
			.inst_i(rs2fu_IR_i),
			.dest_tag_i(rs2fu_dest_tag_i),
			.rob_idx_i(rs2fu_rob_idx_i)
			.result_o(int_alu_result),
			.dest_tag_o(int_alu_dest_tag),
			.rob_idx_o(int_alu_rob_idx),
			.done_o(int_alu_done)
			);
	
	
	br_alu br_alu1 (
			.clk,
			.rst,
			.start_i(ex_unit_en[1])
			.npc_i(rob2fu_PC_i),
			.opa_i(rs2fu_ra_value_i),
			.inst_i(rs2fu_IR_i),
			.rob_idx_i(rs2fu_rob_idx_i),
			.done_o(br_alu_done),
			.br_target_o(br_target),
			.br_result_o(br_taken),
			.rob_idx_o(br_rob_idx)
			);
	
	mult mult1 (
			.clk,
			.rst,
			.start_i(ex_unit_en[2])
			.opa_i(rs2fu_ra_value_i),
			.opb_i(rs2fu_rb_value_i),
			.inst_i(rs2fu_IR_i),
			.rob_idx_i(rs2fu_rob_idx_i),
			.dest_tag_i(rs2fu_dest_tag_i),
			.product(mult_result),
			.rob_idx_o(mult_rob_idx),
			.done(mult_done)	
			);
	
	
endmodule
