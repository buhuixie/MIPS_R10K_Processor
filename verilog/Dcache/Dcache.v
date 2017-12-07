// ****************************************************************************
// Filename: Dcache.v
// Discription: D-cache top module, including cache controller, Dcachemem, and
// 				some simple logic
// Author: Hengfei Zhong
// Version History:
// 	intial creation: 11/24/2017
// ****************************************************************************

`timescale 1ns/100ps

module Dcache (
		input											clk,
		input											rst,

		// <12/6> STQ_C instructions
		input											sq2Dcache_is_stq_c_i,
		output	logic									Dcache2sq_stq_c_fail_o,
		output	logic									Dcache2sq_stq_c_succ_o,
		
		// ports for tb
		input			[`DCACHE_WAY_NUM-1:0]			Dcache_way_idx_tb_i,
		input			[`DCACHE_IDX_W-1:0]				Dcache_set_idx_tb_i,
		output											Dcache_blk_dty_tb_o,
		output			[`DCACHE_TAG_W-1:0]				Dcache_tag_tb_o,
		output			[63:0]							Dcache_data_tb_o,

		// core side signals
		input											cpu_id_i,

		input											lq2Dcache_en_i,
		input			[63:0]							lq2Dcache_addr_i,
		input											sq2Dcache_en_i,
		input			[63:0]							sq2Dcache_addr_i,
		input			[`DCACHE_WORD_IN_BITS-1:0]		sq2Dcache_data_i,
		
		output	logic									Dcache2lq_ack_o,
		output	logic									Dcache2lq_data_vld_o,
		output	logic									Dcache2lq_mshr_data_vld_o,
		output	logic	[`DCACHE_WORD_IN_BITS-1:0]		Dcache2lq_data_o,
		output	logic	[63:0]							Dcache2lq_addr_o,
		output	logic									Dcache2sq_ack_o,

		//output	logic									Dmshr2lq_data_vld_o,
		//output	logic	[63:0]							Dmshr2lq_addr_o,
		//output	logic	[`DCACHE_WORD_IN_BITS-1:0]		Dmshr2lq_data_o,

		// network(or bus) side signals
		input											bus2Dcache_req_ack_i,
		input											bus2Dcache_req_id_i,
		input			[`DCACHE_TAG_W-1:0]				bus2Dcache_req_tag_i,
		input			[`DCACHE_IDX_W-1:0]				bus2Dcache_req_idx_i,
		input	message_t								bus2Dcache_req_message_i,
		input											bus2Dcache_rsp_vld_i,
		input											bus2Dcache_rsp_id_i,
		input			[`DCACHE_WORD_IN_BITS-1:0]		bus2Dcache_rsp_data_i,

		output	logic									Dcache2bus_req_en_o,
		output	logic	[`DCACHE_TAG_W-1:0]				Dcache2bus_req_tag_o,
		output	logic	[`DCACHE_IDX_W-1:0]				Dcache2bus_req_idx_o,
		output	logic	[`DCACHE_WORD_IN_BITS-1:0]		Dcache2bus_req_data_o,
		output	message_t								Dcache2bus_req_message_o,

		output	logic									Dcache2bus_rsp_ack_o,
		// response to other request
		output	logic									Dcache2bus_rsp_vld_o,
		output	logic	[`DCACHE_WORD_IN_BITS-1:0]		Dcache2bus_rsp_data_o
	);


	// signals between Dcachemem and Dcache_ctrl
	logic										Dctrl2Dcache_sq_wr_en;
	logic		[`DCACHE_TAG_W-1:0]				Dctrl2Dcache_sq_wr_tag;
	logic		[`DCACHE_IDX_W-1:0]				Dctrl2Dcache_sq_wr_idx;
	logic		[`DCACHE_WORD_IN_BITS-1:0]		Dctrl2Dcache_sq_wr_data;
	logic										Dcache2Dctrl_sq_wr_hit;
	logic										Dcache2Dctrl_sq_wr_dty;
	
	logic										Dctrl2Dcache_mshr_wr_en;
	logic		[`DCACHE_TAG_W-1:0]				Dctrl2Dcache_mshr_wr_tag;
	logic		[`DCACHE_IDX_W-1:0]				Dctrl2Dcache_mshr_wr_idx;
	logic		[`DCACHE_WORD_IN_BITS-1:0]		Dctrl2Dcache_mshr_wr_data;
	logic										Dctrl2Dcache_mshr_wr_dty;

	logic										Dctrl2Dcache_mshr_st_en;
	logic		[`DCACHE_TAG_W-1:0]				Dctrl2Dcache_mshr_iss_tag;
	logic		[`DCACHE_IDX_W-1:0]				Dctrl2Dcache_mshr_iss_idx;
	logic		[`DCACHE_WORD_IN_BITS-1:0]		Dctrl2Dcache_mshr_iss_data;
	logic										Dcache2Dctrl_mshr_iss_dty;
	logic										Dcache2Dctrl_mshr_iss_hit;

	logic										Dctrl2Dcache_evict_en;
	logic		[`DCACHE_IDX_W-1:0]				Dctrl2Dcache_evict_idx;
	logic		[`DCACHE_TAG_W-1:0]				Dcache2Dctrl_evict_tag;
	logic		[`DCACHE_WORD_IN_BITS-1:0]		Dcache2Dctrl_evict_data;
	
	logic		[`DCACHE_TAG_W-1:0]				Dctrl2Dcache_lq_rd_tag;
	logic		[`DCACHE_IDX_W-1:0]				Dctrl2Dcache_lq_rd_idx;
	logic										Dcache2Dctrl_lq_rd_hit;
	logic		[`DCACHE_WORD_IN_BITS-1:0]		Dcache2Dctrl_lq_rd_data;
	
	logic										Dctrl2Dcache_bus_invld;
	logic										Dctrl2Dcache_bus_downgrade;
	logic		[`DCACHE_TAG_W-1:0]				Dctrl2Dcache_bus_tag;
	logic		[`DCACHE_IDX_W-1:0]				Dctrl2Dcache_bus_idx;
	logic		[`DCACHE_WORD_IN_BITS-1:0]		Dcache2Dctrl_bus_data;
	logic										Dcache2Dctrl_bus_hit;

	// 
	assign Dcache2lq_addr_o	= {Dctrl2Dcache_mshr_wr_tag, Dctrl2Dcache_mshr_wr_idx, 3'h0};


	// Dcachemem instantiation
	Dcachemem Dcachemem (
		.clk				(clk),
		.rst				(rst),

		// ports for tb
		.Dcache_way_idx_tb_i(Dcache_way_idx_tb_i),
		.Dcache_set_idx_tb_i(Dcache_set_idx_tb_i),
		.Dcache_blk_dty_tb_o(Dcache_blk_dty_tb_o),
		.Dcache_tag_tb_o	(Dcache_tag_tb_o),
		.Dcache_data_tb_o	(Dcache_data_tb_o),

		.sq_wr_en_i			(Dctrl2Dcache_sq_wr_en),
		.sq_wr_tag_i		(Dctrl2Dcache_sq_wr_tag),
		.sq_wr_idx_i		(Dctrl2Dcache_sq_wr_idx),
		.sq_wr_data_i		(Dctrl2Dcache_sq_wr_data),
		.sq_wr_hit_o		(Dcache2Dctrl_sq_wr_hit),
		.sq_wr_dty_o		(Dcache2Dctrl_sq_wr_dty),

		.mshr_rsp_wr_en_i	(Dctrl2Dcache_mshr_wr_en),
		.mshr_rsp_wr_tag_i	(Dctrl2Dcache_mshr_wr_tag),
		.mshr_rsp_wr_idx_i	(Dctrl2Dcache_mshr_wr_idx),
		.mshr_rsp_wr_data_i	(Dctrl2Dcache_mshr_wr_data),
		.mshr_rsp_wr_dty_o	(Dctrl2Dcache_mshr_wr_dty),

		.mshr_iss_st_en_i	(Dctrl2Dcache_mshr_st_en),
		.mshr_iss_tag_i		(Dctrl2Dcache_mshr_iss_tag),
		.mshr_iss_idx_i		(Dctrl2Dcache_mshr_iss_idx),
		.mshr_iss_data_i	(Dctrl2Dcache_mshr_iss_data),
		.mshr_iss_dty_o		(Dcache2Dctrl_mshr_iss_dty),
		.mshr_iss_hit_o		(Dcache2Dctrl_mshr_iss_hit),

		.mshr_evict_en_i	(Dctrl2Dcache_evict_en),
		.mshr_evict_idx_i	(Dctrl2Dcache_evict_idx),
		.mshr_evict_tag_o	(Dcache2Dctrl_evict_tag),
		.mshr_evict_data_o	(Dcache2Dctrl_evict_data),		

		.lq_rd_tag_i		(Dctrl2Dcache_lq_rd_tag),
		.lq_rd_idx_i		(Dctrl2Dcache_lq_rd_idx),
		.lq_rd_hit_o		(Dcache2Dctrl_lq_rd_hit),
		.lq_rd_data_o		(Dcache2Dctrl_lq_rd_data),

		.bus_invld_i		(Dctrl2Dcache_bus_invld),
		.bus_downgrade_i	(Dctrl2Dcache_bus_downgrade),
		.bus_rd_tag_i		(Dctrl2Dcache_bus_tag),
		.bus_rd_idx_i		(Dctrl2Dcache_bus_idx),
		.bus_rd_data_o		(Dcache2Dctrl_bus_data),
		.bus_rd_hit_o		(Dcache2Dctrl_bus_hit)
	);


	// Dctrl instantiation
	Dcache_ctrl Dcache_ctrl (
		.clk						(clk),
		.rst						(rst),

		.Dctrl_cpu_id_i				(cpu_id_i),

		.sq2Dctrl_is_stq_c_i		(sq2Dcache_is_stq_c_i),
		.Dctrl2sq_stq_c_fail_o		(Dcache2sq_stq_c_fail_o),
		.Dctrl2sq_stq_c_succ_o		(Dcache2sq_stq_c_succ_o),

		.lq2Dctrl_en_i				(lq2Dcache_en_i),
		.lq2Dctrl_addr_i			(lq2Dcache_addr_i),
		.Dctrl2lq_ack_o				(Dcache2lq_ack_o),
		.Dctrl2lq_data_vld_o		(Dcache2lq_data_vld_o),
		.Dctrl2lq_mshr_data_vld_o	(Dcache2lq_mshr_data_vld_o),
		.Dctrl2lq_data_o			(Dcache2lq_data_o),

		.sq2Dctrl_en_i				(sq2Dcache_en_i),
		.sq2Dctrl_addr_i			(sq2Dcache_addr_i),
		.sq2Dctrl_data_i			(sq2Dcache_data_i),
		.Dctrl2sq_ack_o				(Dcache2sq_ack_o),

		.Dcache_sq_wr_hit_i			(Dcache2Dctrl_sq_wr_hit),
		.Dcache_sq_wr_dty_i			(Dcache2Dctrl_sq_wr_dty),
		.Dcache_sq_wr_en_o			(Dctrl2Dcache_sq_wr_en),
		.Dcache_sq_wr_tag_o			(Dctrl2Dcache_sq_wr_tag),
		.Dcache_sq_wr_idx_o			(Dctrl2Dcache_sq_wr_idx),
		.Dcache_sq_wr_data_o		(Dctrl2Dcache_sq_wr_data),

		.Dcache_lq_rd_hit_i			(Dcache2Dctrl_lq_rd_hit),
		.Dcache_lq_rd_data_i		(Dcache2Dctrl_lq_rd_data),
		.Dcache_lq_rd_tag_o			(Dctrl2Dcache_lq_rd_tag),
		.Dcache_lq_rd_idx_o			(Dctrl2Dcache_lq_rd_idx),

		// to cachemem
		.mshr_rsp_wr_dty_i			(Dctrl2Dcache_mshr_wr_dty),
		.mshr_rsp_wr_en_o			(Dctrl2Dcache_mshr_wr_en),
		.mshr_rsp_wr_tag_o			(Dctrl2Dcache_mshr_wr_tag),
		.mshr_rsp_wr_idx_o			(Dctrl2Dcache_mshr_wr_idx),
		.mshr_rsp_wr_data_o			(Dctrl2Dcache_mshr_wr_data),

		// from/to cachemem
		.mshr_iss_hit_i				(Dcache2Dctrl_mshr_iss_hit),
		.mshr_iss_dty_i				(Dcache2Dctrl_mshr_iss_dty),
		.mshr_iss_st_en_o			(Dctrl2Dcache_mshr_st_en),
		.mshr_iss_tag_o				(Dctrl2Dcache_mshr_iss_tag),
		.mshr_iss_idx_o				(Dctrl2Dcache_mshr_iss_idx),
		.mshr_iss_data_o			(Dctrl2Dcache_mshr_iss_data),

		// evict from/to cachemem
		.Dcache_evict_tag_i			(Dcache2Dctrl_evict_tag),
		.Dcache_evict_data_i		(Dcache2Dctrl_evict_data),
		.Dcache_evict_en_o			(Dctrl2Dcache_evict_en),
		.Dcache_evict_idx_o			(Dctrl2Dcache_evict_idx),

		// from/to cachemem bus signals
		.Dcache_bus_data_i			(Dcache2Dctrl_bus_data),
		.Dcache_bus_hit_i			(Dcache2Dctrl_bus_hit),
		.Dcache_bus_invld_o			(Dctrl2Dcache_bus_invld),
		.Dcache_bus_downgrade_o		(Dctrl2Dcache_bus_downgrade),
		.Dcache_bus_tag_o			(Dctrl2Dcache_bus_tag),
		.Dcache_bus_idx_o			(Dctrl2Dcache_bus_idx),

		// Dctrl/bus request signals
		.bus2Dctrl_req_ack_i		(bus2Dcache_req_ack_i),
		.bus2Dctrl_req_id_i			(bus2Dcache_req_id_i),
		.bus2Dctrl_req_tag_i		(bus2Dcache_req_tag_i),
		.bus2Dctrl_req_idx_i		(bus2Dcache_req_idx_i),
		.bus2Dctrl_req_message_i	(bus2Dcache_req_message_i),
		.Dctrl2bus_req_en_o			(Dcache2bus_req_en_o),
		.Dctrl2bus_req_tag_o		(Dcache2bus_req_tag_o),
		.Dctrl2bus_req_idx_o		(Dcache2bus_req_idx_o),
		.Dctrl2bus_req_data_o		(Dcache2bus_req_data_o),
		.Dctrl2bus_req_message_o	(Dcache2bus_req_message_o),

		// Dctrl/bus response signals
		.bus2Dctrl_rsp_vld_i		(bus2Dcache_rsp_vld_i),
		.bus2Dctrl_rsp_id_i			(bus2Dcache_rsp_id_i),
		.bus2Dctrl_rsp_data_i		(bus2Dcache_rsp_data_i),
		.Dctrl2bus_rsp_ack_o		(Dcache2bus_rsp_ack_o),
		// response to other requests
		.Dctrl2bus_rsp_vld_o		(Dcache2bus_rsp_vld_o),
		.Dctrl2bus_rsp_data_o		(Dcache2bus_rsp_data_o)
	);

endmodule: Dcache

