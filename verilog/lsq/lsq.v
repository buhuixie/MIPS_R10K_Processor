// ****************************************************************************
// Filename: lsq.v
// Discription: 
// Author: Shijing, Lu Liu
// Version History: 
// intial creation: 11/06/2017
// ***************************************************************************

module lsq (
		input								clk,
		input								rst,

		// store signals
		input			[`ADDR_W-1:0]		addr_i,
		input			[63:0]				st_data_i,
		input								st_vld_i,
		input			[`SQ_IDX_W-1:0]		sq_idx_i,
		input								rob_st_retire_en_i,
		input			[`ROB_IDX_W:0]		rob_head_i,
		input								dp_en_i,
		input								id_stc_mem_i, // is store conditional inst

		// load signals
		input			[`ROB_IDX_W:0]		rob_idx_i,
		input			[`PRF_IDX_W-1:0]	dest_tag_i,
		input								ld_vld_i,
		input			[`SQ_IDX_W-1:0]		rs_ld_position_i,
		input								rs_ld_is_ldl_i,
		input			[`SQ_IDX_W-1:0]		ex_ld_position_i,

		// Dcache signals
		input								Dcache_hit_i,
		input			[63:0]				Dcache_data_i,
		input			[`ADDR_W-1:0]		Dcache_mshr_addr_i,
		input								Dcache_mshr_ld_ack_i,
		input								Dcache_mshr_st_ack_i,
		input								Dcache_mshr_vld_i,
		input								Dcache_mshr_stall_i,
		input								Dcache_stc_success_i,
		input								Dcache_stc_fail_i,

		// branch recovery signals
		input			[`BR_MASK_W-1:0]	bs_br_mask_i,
		input			[`SQ_IDX_W:0]		bs_sq_tail_recovery_i,
		input								rob_br_recovery_i,
		input								rob_br_pred_correct_i,
		input			[`BR_MASK_W-1:0]	rob_br_tag_fix_i,
		input								fu_br_done_i,

		// output signals
		output	logic	[`SQ_IDX_W:0]		lsq_sq_tail_o,
		output	logic						lsq_ld_iss_en_o,
		output	logic	[`ADDR_W-1:0]		lsq2Dcache_ld_addr_o,
		output	logic						lsq2Dcache_ld_en_o,
		output	logic	[63:0]				lsq2Dcache_st_addr_o,
		output	logic	[63:0]				lsq2Dcache_st_data_o,
		output	logic						lsq2Dcache_st_en_o,
		output	logic						lsq2Dcache_stc_flag_o,
		output	logic						lsq_ld_done_o,
		output	logic						lsq_st_done_o,
		output	logic	[63:0]				lsq_data_o,
		output	logic	[`ROB_IDX_W:0]		lsq_rob_idx_o,
		output	logic	[`PRF_IDX_W-1:0]	lsq_dest_tag_o,
		output	logic	[`BR_MASK_W-1:0]	lsq_br_mask_o,
		output	logic						lsq_lq_com_rdy_o,
		output	logic						lsq_stc_com_rdy_o,
		output	logic						lsq_sq_full_o
);

	// ------------------ Internal Signals ---------------------
	parameter IDLE		= 2'b00,
		  INVALID	= 2'b01,
		  BUSY		= 2'b10;

	// store queue registers
	logic	[`SQ_ENT_NUM-1:0][`ADDR_W-1:0]		st_addr_r;
	logic	[`SQ_ENT_NUM-1:0]					st_addr_vld_r;
	logic	[`SQ_ENT_NUM-1:0][63:0]				st_data_r;
	logic	[`SQ_ENT_NUM-1:0][`ROB_IDX_W:0]		st_rob_idx_r;
	logic	[`SQ_ENT_NUM-1:0][`PRF_IDX_W-1:0]	st_dest_tag_r;
	logic	[`SQ_ENT_NUM-1:0]					st_retire_rdy_r;
	logic	[`SQ_ENT_NUM-1:0]					stc_flag_r;
	logic										stc_acknowledged_r;
	logic										stc_success_hold_r;
	logic										stc_fail_hold_r;
	logic	[`SQ_IDX_W:0]						sq_head_q_r;
	logic	[`SQ_IDX_W:0]						sq_retire_head_q_r;
	logic	[`SQ_IDX_W:0]						sq_tail_q_r;
	logic	[`SQ_IDX_W-1:0]						sq_head_r;
	logic	[`SQ_IDX_W-1:0]						sq_retire_head_r;
	logic	[`SQ_IDX_W-1:0]						sq_tail_r;
	logic										sq_head_msb_r;
	logic										sq_retire_head_msb_r;
	logic										sq_tail_msb_r;

	// load queue registers
	logic	[`LQ_IDX_W:0]						lq_head_q_r;
	logic	[`LQ_IDX_W:0]						lq_tail_q_r;
	logic	[`LQ_IDX_W-1:0]						lq_head_r;
	logic	[`LQ_IDX_W-1:0]						lq_tail_r;
	logic										lq_head_msb_r;
	logic										lq_tail_msb_r;
	logic	[`LQ_ENT_NUM-1:0][`ADDR_W-1:0]		lq_addr_r;
	logic	[`LQ_ENT_NUM-1:0][63:0]				lq_data_r;
	logic	[`LQ_ENT_NUM-1:0]					lq_vld_r;
	logic	[`LQ_ENT_NUM-1:0]					lq_rdy_r;
	logic	[`LQ_ENT_NUM-1:0][`ROB_IDX_W:0]		lq_rob_idx_r;
	logic	[`LQ_ENT_NUM-1:0][`PRF_IDX_W-1:0]	lq_dest_tag_r;
	logic	[`LQ_ENT_NUM-1:0][`BR_MASK_W-1:0]	lq_br_mask_r;

	logic	[63:0]								ld_addr_hold_r;
	logic	[63:0]								ld_addr_hold_r_nxt;
	logic	[`ROB_IDX_W:0]						ld_rob_idx_hold_r;
	logic	[`ROB_IDX_W:0]						ld_rob_idx_hold_r_nxt;
	logic	[`PRF_IDX_W-1:0]					ld_dest_tag_hold_r;
	logic	[`PRF_IDX_W-1:0]					ld_dest_tag_hold_r_nxt;
	logic	[`BR_MASK_W-1:0]					ld_br_mask_hold_r;
	logic	[`BR_MASK_W-1:0]					ld_br_mask_hold_r_nxt;
	logic	[1:0]								ld_hold_r_state;
	logic	[1:0]								ld_hold_r_state_nxt;

	// store queue signals
	logic	[`SQ_IDX_W:0]						sq_head_q_r_nxt;
	logic	[`SQ_IDX_W:0]						sq_retire_head_q_r_nxt;
	logic	[`SQ_IDX_W:0]						sq_tail_q_r_nxt;
	logic	[`SQ_ENT_NUM-1:0]					st_addr_vld_r_nxt;
	logic	[`SQ_ENT_NUM-1:0]					st_retire_rdy_r_nxt;
	logic										sq_retire_en;
	logic	[`SQ_ENT_NUM-1:0]					stc_flag_r_nxt;
	logic	[63:0]								st2ld_forward_data;
	logic	[63:0]								st2ld_forward_data1;
	logic	[63:0]								st2ld_forward_data2;
	logic										st2ld_forward_vld;
	logic										st2ld_forward_vld1;
	logic										st2ld_forward_vld2;
	logic										ld_iss_en;
	logic										stc_com_rdy;

	// load queue signals
	logic	[`LQ_IDX_W:0]						lq_head_q_r_nxt;
	logic	[`LQ_IDX_W:0]						lq_tail_q_r_nxt;
	logic	[`LQ_ENT_NUM-1:0]					lq_vld_r_nxt;
	logic	[`LQ_ENT_NUM-1:0]					lq_rdy_r_nxt;
	logic	[`LQ_ENT_NUM-1:0][63:0]				lq_data_r_nxt;
	logic	[`LQ_ENT_NUM-1:0][`BR_MASK_W-1:0]	lq_br_mask_r_nxt;
	logic										lq_head_match;
	logic										lq_full;
	logic										ld_miss;
	logic										lq_com_rdy;

	// --------------------- Store Queue ------------------------------
	assign sq_head_msb_r = sq_head_q_r[`SQ_IDX_W];
	assign sq_head_r = sq_head_q_r[`SQ_IDX_W-1:0];
	assign sq_retire_head_msb_r = sq_retire_head_q_r[`SQ_IDX_W];
	assign sq_retire_head_r = sq_retire_head_q_r[`SQ_IDX_W-1:0];
	assign sq_tail_msb_r = sq_tail_q_r[`SQ_IDX_W];
	assign sq_tail_r = sq_tail_q_r[`SQ_IDX_W-1:0];

	assign sq_head_q_r_nxt = sq_retire_en ? (sq_head_q_r + 1) : sq_head_q_r;

	assign sq_retire_head_q_r_nxt = rob_st_retire_en_i ? (sq_retire_head_q_r + 1) : sq_retire_head_q_r;

	assign sq_tail_q_r_nxt = rob_br_recovery_i ? bs_sq_tail_recovery_i :
							 dp_en_i ? (sq_tail_q_r + 1) : sq_tail_q_r;

	assign lsq_sq_tail_o = sq_tail_q_r;

	assign lsq_ld_iss_en_o = ld_iss_en && ~lq_full && ~Dcache_mshr_stall_i && 
							 ~(ld_vld_i && ~lsq_ld_done_o && ~Dcache_mshr_ld_ack_i)
							 && (ld_hold_r_state == IDLE);

	assign lsq2Dcache_st_addr_o = st_addr_r[sq_head_r];

	assign lsq2Dcache_st_data_o = lsq2Dcache_stc_flag_o ? 64'b1 : st_data_r[sq_head_r];

	assign lsq2Dcache_stc_flag_o = stc_flag_r[sq_head_r] & lsq2Dcache_st_en_o;

	assign lsq2Dcache_st_en_o = (rob_st_retire_en_i && ~stc_flag_r[sq_head_r]) || st_retire_rdy_r[sq_head_r] 
								|| (stc_flag_r[sq_head_r] && (st_rob_idx_r[sq_head_r] == rob_head_i) && 
								~stc_acknowledged_r && st_addr_vld_r[sq_head_r] && (sq_head_q_r != sq_tail_q_r));

	assign sq_retire_en = ((rob_st_retire_en_i | st_retire_rdy_r[sq_head_r]) & Dcache_mshr_st_ack_i)
						  | (rob_st_retire_en_i & stc_flag_r[sq_head_r]);

	assign stc_com_rdy = Dcache_stc_success_i | Dcache_stc_fail_i;

	assign lsq_stc_com_rdy_o = stc_com_rdy | stc_success_hold_r | stc_fail_hold_r;

	assign lsq_st_done_o = st_vld_i & ~stc_flag_r[sq_idx_i];

	assign lsq_sq_full_o = ((sq_head_r == sq_tail_r) && (sq_head_msb_r != sq_tail_msb_r));

	always_comb begin
		st_addr_vld_r_nxt = st_addr_vld_r;
		if (dp_en_i)
			st_addr_vld_r_nxt[sq_tail_r] = 1'b0;
		
		if (st_vld_i)
			st_addr_vld_r_nxt[sq_idx_i] = 1'b1;

		if (sq_retire_en)
			st_addr_vld_r_nxt[sq_head_r] = 1'b0;

	end

	always_comb begin
		stc_flag_r_nxt = stc_flag_r;
		if (dp_en_i & id_stc_mem_i)
			stc_flag_r_nxt[sq_tail_r] = 1'b1;
		else if (dp_en_i)
			stc_flag_r_nxt[sq_tail_r] = 1'b0;

		if (sq_retire_en)
			stc_flag_r_nxt[sq_head_r] = 1'b0;
	end

	always_comb begin
		st_retire_rdy_r_nxt = st_retire_rdy_r;

		if (rob_st_retire_en_i && ~stc_flag_r[sq_head_r] && (~Dcache_mshr_st_ack_i || (sq_head_q_r != sq_retire_head_q_r)))
			st_retire_rdy_r_nxt[sq_retire_head_r] = 1'b1;

		if (sq_retire_en)
			st_retire_rdy_r_nxt[sq_head_r] = 1'b0;
	end

	// synopsys sync_set_reset "rst"
	always_ff @(posedge clk) begin
		if(rst) begin/////
			st_addr_r			<= `SD {`SQ_ENT_NUM{64'b0}};
			st_data_r			<= `SD {`SQ_ENT_NUM{64'b0}};
		end else if (st_vld_i) begin
			st_addr_r[sq_idx_i]		<= `SD addr_i;
			st_data_r[sq_idx_i]		<= `SD stc_flag_r[sq_idx_i] ? 64'b1 : st_data_i;
			st_rob_idx_r[sq_idx_i]	<= `SD rob_idx_i;
			st_dest_tag_r[sq_idx_i]	<= `SD dest_tag_i;
		end
	end

	// synopsys sync_set_reset "rst"
	always_ff @(posedge clk) begin
		if (rst)
			stc_acknowledged_r	<= `SD 1'b0;
		else if (stc_flag_r[sq_head_r] & Dcache_mshr_st_ack_i)
			stc_acknowledged_r	<= `SD 1'b1;
		else if (sq_retire_en)
			stc_acknowledged_r	<= `SD 1'b0;
	end

	// synopsys sync_set_reset "rst"
	always_ff @(posedge clk) begin
		if (rst) begin
			stc_success_hold_r	<= `SD 1'b0;
			stc_fail_hold_r		<= `SD 1'b0;
		end else if (stc_com_rdy & fu_br_done_i) begin
			stc_success_hold_r	<= `SD Dcache_stc_success_i;
			stc_fail_hold_r		<= `SD Dcache_stc_fail_i;
		end else if (lsq_stc_com_rdy_o & ~fu_br_done_i) begin
			stc_success_hold_r	<= `SD 1'b0;
			stc_fail_hold_r		<= `SD 1'b0;
		end
	end

	// synopsys sync_set_reset "rst"
	always_ff @(posedge clk) begin
		if (rst) begin
			sq_head_q_r			<= `SD 0;
			sq_tail_q_r			<= `SD 0;
			sq_retire_head_q_r	<= `SD 0;//
			st_addr_vld_r		<= `SD 0;
			st_retire_rdy_r		<= `SD 0;
			stc_flag_r			<= `SD 0;
		end else begin
			sq_head_q_r			<= `SD sq_head_q_r_nxt;
			sq_tail_q_r			<= `SD sq_tail_q_r_nxt;
			sq_retire_head_q_r	<= `SD sq_retire_head_q_r_nxt;//
			st_addr_vld_r		<= `SD st_addr_vld_r_nxt;
			st_retire_rdy_r		<= `SD st_retire_rdy_r_nxt;
			stc_flag_r			<= `SD stc_flag_r_nxt;
		end
	end

	// age logic
	// generate ld_iss_en (check the addresses of all older stores are known)
	integer i;
	always_comb begin
		ld_iss_en = 1'b1;


		for (i = 0; i < `SQ_ENT_NUM; i = i + 1) begin
			if ((rs_ld_position_i >= sq_head_r) && (~lsq_sq_full_o || (rs_ld_position_i != sq_tail_r))) begin
				if ((i >= sq_head_r) && (i < rs_ld_position_i) && (~st_addr_vld_r[i] || (rs_ld_is_ldl_i && stc_flag_r[i])))
					ld_iss_en = 1'b0;
			end else begin
				if (((i < rs_ld_position_i) || (i >= sq_head_r)) && (~st_addr_vld_r[i] || (rs_ld_is_ldl_i && stc_flag_r[i])))
					ld_iss_en = 1'b0;
			end
		end
	end

	// generate forward_vld and forward_data
	integer j;
	always_comb begin
		st2ld_forward_data1 = 64'b0;
		st2ld_forward_data2 = 64'b0;
		st2ld_forward_vld1 = 1'b0;
		st2ld_forward_vld2 = 1'b0;
		if (ld_vld_i) begin
			for (j = 0; j < `SQ_ENT_NUM; j = j + 1) begin
				if ((ex_ld_position_i >= sq_head_r) && (~lsq_sq_full_o || (ex_ld_position_i != sq_tail_r))) begin
					if ((j >= sq_head_r) && (j < ex_ld_position_i) && (addr_i == st_addr_r[j]) && ~stc_flag_r[j]) begin
						st2ld_forward_data1 = st_data_r[j];
						st2ld_forward_vld1 = 1'b1;
					end
				end else begin
					if ((j < ex_ld_position_i) && (addr_i == st_addr_r[j]) && ~stc_flag_r[j]) begin
						st2ld_forward_data1 = st_data_r[j];
						st2ld_forward_vld1 = 1'b1;
					end else if ((j >= sq_head_r) && (addr_i == st_addr_r[j]) && ~stc_flag_r[j]) begin
						st2ld_forward_data2 = st_data_r[j];
						st2ld_forward_vld2 = 1'b1;
					end
				end
			end
		end
		st2ld_forward_data = st2ld_forward_vld1 ? st2ld_forward_data1 : st2ld_forward_data2;
		st2ld_forward_vld = st2ld_forward_vld1 | st2ld_forward_vld2;
	end

	// ---------------------- Load Queue ----------------------------
	always_comb begin//TODO: zero delay LOOP here !!!
		if (Dcache_mshr_ld_ack_i) begin
			ld_hold_r_state_nxt		= IDLE;
			ld_addr_hold_r_nxt		= 0;
			ld_rob_idx_hold_r_nxt	= 0;
			ld_dest_tag_hold_r_nxt	= 0;
			ld_br_mask_hold_r_nxt	= 0;
		end else if (rob_br_recovery_i && ((ld_br_mask_hold_r & rob_br_tag_fix_i) != 0)) begin
			ld_hold_r_state_nxt		= INVALID;
			ld_addr_hold_r_nxt		= 0;
			ld_rob_idx_hold_r_nxt	= 0;
			ld_dest_tag_hold_r_nxt	= 0;
			ld_br_mask_hold_r_nxt	= 0;
		end else if (ld_vld_i & ~lsq_ld_done_o) begin
			ld_hold_r_state_nxt		= BUSY;
			ld_addr_hold_r_nxt		= addr_i;
			ld_rob_idx_hold_r_nxt	= rob_idx_i;
			ld_dest_tag_hold_r_nxt	= dest_tag_i;
			ld_br_mask_hold_r_nxt	= rob_br_pred_correct_i ? (bs_br_mask_i & ~rob_br_tag_fix_i) : bs_br_mask_i;
		end else begin
			ld_hold_r_state_nxt		= ld_hold_r_state;
			ld_addr_hold_r_nxt		= ld_addr_hold_r;
			ld_rob_idx_hold_r_nxt	= ld_rob_idx_hold_r;
			ld_dest_tag_hold_r_nxt	= ld_dest_tag_hold_r;
			ld_br_mask_hold_r_nxt	= rob_br_pred_correct_i ? (ld_br_mask_hold_r & ~rob_br_tag_fix_i) : ld_br_mask_hold_r;
		end
	end

	// synopsys sync_set_reset "rst"
	always_ff @(posedge clk) begin
		if (rst) begin
			ld_hold_r_state			<= `SD IDLE;
			ld_addr_hold_r			<= `SD 0;
			ld_rob_idx_hold_r		<= `SD 0;
			ld_dest_tag_hold_r		<= `SD 0;
			ld_br_mask_hold_r		<= `SD 0;
		end else begin
			ld_hold_r_state			<= `SD ld_hold_r_state_nxt;
			ld_addr_hold_r			<= `SD ld_addr_hold_r_nxt;
			ld_rob_idx_hold_r		<= `SD ld_rob_idx_hold_r_nxt;
			ld_dest_tag_hold_r		<= `SD ld_dest_tag_hold_r_nxt;
			ld_br_mask_hold_r		<= `SD ld_br_mask_hold_r_nxt;
		end
	end

	assign lq_head_msb_r = lq_head_q_r[`LQ_IDX_W];
	assign lq_head_r = lq_head_q_r[`LQ_IDX_W-1:0];
	assign lq_tail_msb_r = lq_tail_q_r[`LQ_IDX_W];
	assign lq_tail_r = lq_tail_q_r[`LQ_IDX_W-1:0];

	assign lq_head_q_r_nxt = (((lq_com_rdy && ~fu_br_done_i && ~lsq_stc_com_rdy_o) || ~lq_vld_r[lq_head_r])
							 && (lq_head_q_r != lq_tail_q_r)) ? lq_head_q_r + 1 : lq_head_q_r;//

	assign lq_tail_q_r_nxt = ld_miss ? lq_tail_q_r + 1 : lq_tail_q_r;// 12.9

	assign lq_head_match = Dcache_mshr_vld_i && (Dcache_mshr_addr_i == lq_addr_r[lq_head_r]);

	assign lq_com_rdy = (lq_head_match || lq_rdy_r[lq_head_r]) && (lq_head_q_r != lq_tail_q_r);

	assign lsq_lq_com_rdy_o = lq_com_rdy & lq_vld_r[lq_head_r];

	assign lsq_ld_done_o = (Dcache_hit_i | st2ld_forward_vld) & ld_vld_i & ~Dcache_mshr_vld_i;

	assign ld_miss = (ld_vld_i || ((ld_hold_r_state == BUSY) && ~(rob_br_recovery_i && ((ld_br_mask_hold_r & rob_br_tag_fix_i) != 0))))
			 && ~Dcache_hit_i && ~st2ld_forward_vld && Dcache_mshr_ld_ack_i;//

	assign lsq2Dcache_ld_addr_o = ld_vld_i ? addr_i : ld_addr_hold_r;

	assign lsq2Dcache_ld_en_o = (ld_vld_i || (ld_hold_r_state != IDLE)) && ~lsq_lq_com_rdy_o && ~Dcache_mshr_vld_i;

	assign lsq_data_o = (Dcache_stc_success_i | stc_success_hold_r) ? 64'b1 :
						(Dcache_stc_fail_i | stc_fail_hold_r) ? 64'b0 :
						(lq_head_match && lq_vld_r[lq_head_r] && (lq_head_q_r != lq_tail_q_r)) ? Dcache_data_i :
		                (lq_rdy_r[lq_head_r] && lq_vld_r[lq_head_r] && (lq_head_q_r != lq_tail_q_r)) ? lq_data_r[lq_head_r] :
						st2ld_forward_vld ? st2ld_forward_data :
						Dcache_hit_i ? Dcache_data_i : 64'b0;

	assign lsq_rob_idx_o = lsq_stc_com_rdy_o ? st_rob_idx_r[sq_head_r] :
						   lsq_lq_com_rdy_o ? lq_rob_idx_r[lq_head_r] : rob_idx_i;

	assign lsq_dest_tag_o = lsq_stc_com_rdy_o ? st_dest_tag_r[sq_head_r] :
						    lsq_lq_com_rdy_o ? lq_dest_tag_r[lq_head_r] : dest_tag_i;

	assign lsq_br_mask_o = lsq_lq_com_rdy_o ? lq_br_mask_r[lq_head_r] : bs_br_mask_i;

	assign lq_full = (lq_head_r == lq_tail_r) && (lq_head_msb_r != lq_tail_msb_r);

	always_comb begin
		lq_vld_r_nxt = lq_vld_r;
		lq_rdy_r_nxt = lq_rdy_r;
		lq_data_r_nxt = lq_data_r;

		if (rob_br_recovery_i) begin
			for (int k = 0; k < `LQ_ENT_NUM; k = k + 1) begin
				if (((lq_br_mask_r[k] & rob_br_tag_fix_i) != 0) && lq_vld_r[k])
					lq_vld_r_nxt[k]		= 1'b0;
			end
		end
		
		if (ld_miss) begin
			lq_rdy_r_nxt[lq_tail_r]		= 1'b0;
			lq_vld_r_nxt[lq_tail_r]		= 1'b1;
		end

		if (Dcache_mshr_vld_i) begin
			for (int k = 0; k < `LQ_ENT_NUM; k = k + 1) begin
				if (lq_addr_r[k] == Dcache_mshr_addr_i && ~lq_rdy_r[k]) begin
					lq_rdy_r_nxt[k] 	= 1'b1;
					lq_data_r_nxt[k]	= Dcache_data_i;
				end
			end
		end
	end

	always_comb begin
		lq_br_mask_r_nxt = lq_br_mask_r;

		if (rob_br_recovery_i) begin
			for (int k = 0; k < `LQ_ENT_NUM; k = k + 1) begin
				if ((lq_br_mask_r[k] & rob_br_tag_fix_i) != 0)
					lq_br_mask_r_nxt[k]		= 0;
			end
		end else if (rob_br_pred_correct_i) begin
			for (int k = 0; k < `LQ_ENT_NUM; k = k + 1) begin
				lq_br_mask_r_nxt[k]		= lq_br_mask_r[k] & ~rob_br_tag_fix_i;
			end
		end

		if (ld_miss & rob_br_pred_correct_i) begin
			lq_br_mask_r_nxt[lq_tail_r]	= ld_vld_i ? (bs_br_mask_i & ~rob_br_tag_fix_i) : (ld_br_mask_hold_r & ~rob_br_tag_fix_i);
		end else if (ld_miss) begin
			lq_br_mask_r_nxt[lq_tail_r]	= ld_vld_i ? bs_br_mask_i : ld_br_mask_hold_r;
		end
	end


	// synopsys sync_set_reset "rst"
	always_ff @(posedge clk) begin
		if (rst) begin
			lq_head_q_r		<= `SD 0;
			lq_tail_q_r		<= `SD 0;
		end else begin
			lq_head_q_r		<= `SD lq_head_q_r_nxt;
			lq_tail_q_r		<= `SD lq_tail_q_r_nxt;
		end
	end

	// synopsys sync_set_reset "rst"
	always_ff @(posedge clk) begin
		if (rst) begin
			lq_vld_r		<= `SD {`LQ_ENT_NUM{1'b1}};
			lq_rdy_r		<= `SD 0;
			lq_data_r		<= `SD {`LQ_ENT_NUM{64'h0}};
			lq_br_mask_r	<= `SD {`LQ_ENT_NUM{`BR_MASK_W'b0}};
		end else begin
			lq_vld_r		<= `SD lq_vld_r_nxt;
			lq_rdy_r		<= `SD lq_rdy_r_nxt;
			lq_data_r		<= `SD lq_data_r_nxt;
			lq_br_mask_r	<= `SD lq_br_mask_r_nxt;
		end
	end

	// synopsys sync_set_reset "rst"
	always_ff @(posedge clk) begin
		if (rst) begin
			lq_addr_r				<= `SD {`LQ_ENT_NUM{64'h0}};
			lq_rob_idx_r				<= `SD {`LQ_ENT_NUM{6'h0}};
			lq_dest_tag_r				<= `SD {`LQ_ENT_NUM{6'h0}};
		end else if (ld_miss) begin
			lq_addr_r[lq_tail_r]		<= `SD ld_vld_i ? addr_i : ld_addr_hold_r;
			lq_rob_idx_r[lq_tail_r]		<= `SD ld_vld_i ? rob_idx_i : ld_rob_idx_hold_r;
			lq_dest_tag_r[lq_tail_r]	<= `SD ld_vld_i ? dest_tag_i : ld_dest_tag_hold_r;
		end
	end

endmodule


