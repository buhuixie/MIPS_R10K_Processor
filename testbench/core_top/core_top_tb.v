//*****************************************************************************
// Filename: core_top_tb.v
// Discription: testbench for core_top.v
// Author: group 5
// Version History
//   <12/1> initial creation: single core tb, for correctness submission
//   <12/1> TODO: Add ports to support after synth output files
//*****************************************************************************
`timescale 1ns/100ps

`define		PRINT_ROB_WHOLE		1

module core_top_tb;

	logic			clk;
	logic			rst;

	logic	[1:0]	proc2mem_command;
	logic	[63:0]	proc2mem_addr;
	logic	[63:0]	proc2mem_data;

	logic 	[3:0]	mem2proc_response;
	logic	[63:0]	mem2proc_data;
	logic 	[3:0]	mem2proc_tag;

	logic	[3:0]	core_retired_instrs;
	logic	[3:0]	core_error_status;

	// ports for writeback all dty data from Dcache to mem
	logic		[`DCACHE_WAY_NUM-1:0]	Dcache_way_idx_tb_i;
	logic		[`DCACHE_IDX_W-1:0]		Dcache_set_idx_tb_i;
	logic								Dcache_blk_dty_tb_o;
	logic		[`DCACHE_TAG_W-1:0]		Dcache_tag_tb_o;
	logic		[63:0]					Dcache_data_tb_o;
	

	logic			core_retire_wr_en;

	logic	[31:0]	clock_count;
	logic	[31:0]	instr_count;
	int				wb_fileno;
	int				rs_fileno;
	int				rob_fileno;

	// instr string
	logic	[`RS_ENT_NUM-1:0][8*8:0]	rs_instr_str;
	logic	[`ROB_W-1:0][8*8:0]			rob_instr_str;

	// DUT
	core_top core_top	(
		.clk				(clk),
		.rst				(rst),

		.mem2proc_response_i(mem2proc_response),
		.mem2proc_data_i	(mem2proc_data),
		.mem2proc_tag_i		(mem2proc_tag),
	
		.proc2mem_command_o	(proc2mem_command),
		.proc2mem_addr_o	(proc2mem_addr),
		.proc2mem_data_o	(proc2mem_data),

		.core_retired_instrs(core_retired_instrs),
		.core_error_status	(core_error_status),
		
		// ports for mem write back
		.Dcache_way_idx_tb_i(Dcache_way_idx_tb_i),
		.Dcache_set_idx_tb_i(Dcache_set_idx_tb_i),
		.Dcache_blk_dty_tb_o(Dcache_blk_dty_tb_o),
		.Dcache_tag_tb_o	(Dcache_tag_tb_o),
		.Dcache_data_tb_o	(Dcache_data_tb_o)
	);

	// instantiate main memory
	mem memory	(
			// Inputs
			.clk				(clk),
			.proc2mem_command	(proc2mem_command),
			.proc2mem_addr		(proc2mem_addr),
			.proc2mem_data		(proc2mem_data),

			 // Outputs
			.mem2proc_response (mem2proc_response),
			.mem2proc_data     (mem2proc_data),
			.mem2proc_tag      (mem2proc_tag)
		   );

	assign core_retire_wr_en = core_top.core0.rob.rob_head_retire_rdy_o && 
							   (core_top.core0.rob.rob2arch_map_logic_dest_o != `ZERO_REG);

	// Generate System Clock
	always
	begin
		#(`VERILOG_CLOCK_PERIOD/2.0);
		clk = ~clk;
	end

	// Task to display # of elapsed clock edges
	logic				freeze_clk_count;

	task show_clk_count;
		real cpi;

		begin
			cpi = (clock_count + 1.0) / (instr_count + 1); // halt insn
			$display("@@  %0d cycles / %0d instrs = %f CPI\n@@",
			clock_count+1, instr_count+1, cpi);
			$display("@@  %4.2f ns total time to execute\n@@\n",
			clock_count*`VIRTUAL_CLOCK_PERIOD);
		end
	endtask  // task show_clk_count


	// Show contents of a range of Unified Memory, in both hex and decimal
	task show_mem_with_decimal;
		input [31:0] start_addr;
		input [31:0] end_addr;

		int showing_data;
		begin
			freeze_clk_count	= 1;
			#1
			// write dirty data block back to memroy
			for (int i = 0; i < `DCACHE_SET_NUM; i++) begin
				for (int j = 0; j < `DCACHE_WAY_NUM; j++) begin
					Dcache_way_idx_tb_i	= j;
					Dcache_set_idx_tb_i	= i;
					#1
					if (Dcache_blk_dty_tb_o)
						memory.unified_memory[{Dcache_tag_tb_o,Dcache_set_idx_tb_i}] = Dcache_data_tb_o;
				end
			end
			$display("@@@");
			showing_data=0;
			for(int k=start_addr;k<=end_addr; k=k+1)
				if (memory.unified_memory[k] != 0)
				begin
					$display("@@@ mem[%5d] = %x : %0d", k*8,	memory.unified_memory[k], 
																memory.unified_memory[k]);
					showing_data=1;
				end
				else if(showing_data!=0)
				begin
					$display("@@@");
					showing_data=0;
				end
			$display("@@@");
		end
	endtask  // task show_mem_with_decimal
	
	initial
	begin
		`ifdef DUMP
		  $vcdplusdeltacycleon;
		  $vcdpluson();
		  $vcdplusmemon(memory.unified_memory);
		`endif
		  
		clk = 1'b0;
		rst = 1'b0;
		freeze_clk_count = 1'b0;

		// Pulse the reset signal
		$display("@@\n@@\n@@  %t  Asserting System reset......", $realtime);
		rst = 1'b1;
		@(posedge clk);
		@(posedge clk);

		$readmemh("./program.mem", memory.unified_memory);

		@(posedge clk);
		@(posedge clk);
		`SD;
		// This reset is at an odd time to avoid the pos & neg clock edges

		rst = 1'b0;
		$display("@@  %t  Deasserting System reset......\n@@\n@@", $realtime);

		wb_fileno = $fopen("writeback.out");

		rs_fileno = $fopen("rs.out");

		rob_fileno= $fopen("rob.out");

		//Open header AFTER throwing the reset otherwise the reset state is displayed
		//print_header("                                                                            D-MEM Bus &\n");
		//print_header("Cycle:      IF      |     ID      |     EX      |     MEM     |     WB      Reg Result");
	end

	// task for printing rs
	task print_rs;
		$fdisplay(rs_fileno, "@@@");
		$fdisplay(rs_fileno, "@@@");
		$fdisplay(rs_fileno, "@@@ At c%-1d:", clock_count);
		$fdisplay(rs_fileno, "@@@ The content of RS is:");
		//
		$fdisplay(rs_fileno, "@@@      TAGA  | RDYA |  TAGB  | RDYB |DEST_TAG| FU_SEL|   IR     |ROB_IDX|BR_MASK| AVAIL  | Instr");
		for (int i = 0; i < `RS_ENT_NUM; i = i + 1) begin
			$fdisplay(rs_fileno, "@@@ %-3d:  %d   |   %b  |   %d   |   %b  |   %d   |   %d   | %h |  %d   | %b |   %b    | %-2s", i, 
				core_top.core0.rs.opa_tag_vec[i], core_top.core0.rs.opa_rdy_vec[i],
				core_top.core0.rs.opb_tag_vec[i], core_top.core0.rs.opb_rdy_vec[i], 
				core_top.core0.rs.dest_tag_vec[i], core_top.core0.rs.fu_sel_vec[i],
				core_top.core0.rs.IR_vec[i], core_top.core0.rs.rob_idx_vec[i][`ROB_IDX_W-1:0], 
				core_top.core0.rs.br_mask_vec[i], core_top.core0.rs.avail_vec[i],rs_instr_str[i]);
		end

		$fdisplay(rs_fileno, "@@@ Status of schedule vector: %b", core_top.core0.rs.exunit_schedule_r);
		$fdisplay(rs_fileno, "@@@ CDB status: valid = %b, tag = %d", core_top.core0.rs.cdb_vld_i, core_top.core0.rs.cdb_tag_i);
		$fdisplay(rs_fileno, "@@@ rs_full_o = %b", core_top.core0.rs.rs_full_o);
		if (core_top.core0.rs.rs_iss_vld) begin
			$fdisplay(rs_fileno, "@@@ #Issue# RS: %d | instr: %s", core_top.core0.rs.iss_idx, 
																   rs_instr_str[core_top.core0.rs.iss_idx]);
			$fdisplay(rs_fileno, "@@@ opa_tag = %d, opb_tag = %d, dest_tag = %d, fu_sel = %d, IR = %h, rob_idx = %d, br_mask = %b",
				core_top.core0.rs.rs_iss_opa_tag, core_top.core0.rs.rs_iss_opb_tag, 
				core_top.core0.rs.rs_iss_dest_tag, core_top.core0.rs.rs_iss_fu_sel, 
				core_top.core0.rs.rs_iss_IR, core_top.core0.rs.rs_iss_rob_idx, 
				core_top.core0.rs.rs_iss_br_mask);
			$fdisplay(rs_fileno, "@@@ Schedule vector of issued instr: %b", 
									core_top.core0.rs.rs_ent_schedule_vec[core_top.core0.rs.iss_idx]);
		end else
			$fdisplay(rs_fileno, "@@@ #None# No instructions can be issued this cycle");
	endtask // task print_rs

	task print_rob;
		$fdisplay(rob_fileno, "@@@");
		$fdisplay(rob_fileno, "@@@");
		$fdisplay(rob_fileno, "@@@ At c%-1d:", clock_count);
		$fdisplay(rob_fileno, "@@@ The content of ROB is:");
		$fdisplay(rob_fileno, "@@@     Tnew | Told | dest | Done | rd_wr | br | br p&t |        PC        |      t-PC        | br_mask |    IR     |  Instr ");
		// print whole rob
		if (`PRINT_ROB_WHOLE == 1) begin
			for (int i = 0; i < `ROB_W; i++) begin
				if (i == core_top.core0.rob.head_r[`HT_W-1:0]) begin
					$fdisplay(rob_fileno, "@@@ h%-2d: p%d |  p%d |  r%d |   %b  |  %b %b  |  %b |   %b%b   | %h | %h |  %b  | %h  |  %-0s ", i, 
						core_top.core0.rob.dest_tag_r[i], core_top.core0.rob.old_dest_tag_r[i], core_top.core0.rob.logic_dest_r[i], 
						core_top.core0.rob.done_r[i], core_top.core0.rob.rd_mem_r[i], core_top.core0.rob.wr_mem_r[i], core_top.core0.rob.br_flag_r[i],
						core_top.core0.rob.br_pretaken_r[i], core_top.core0.rob.br_taken_r[i], core_top.core0.rob.PC_r[i], core_top.core0.rob.br_target_r[i], 
						core_top.core0.rob.br_mask_r[i],core_top.core0.rob.IR_r[i],rob_instr_str[i]);
				end else if (i == core_top.core0.rob.tail_r[`HT_W-1:0]) begin
					$fdisplay(rob_fileno, "@@@ t%-2d: p%d |  p%d |  r%d |   %b  |  %b %b  |  %b |   %b%b   | %h | %h |  %b  | %h  |  %-0s ", i, 
						core_top.core0.rob.dest_tag_r[i], core_top.core0.rob.old_dest_tag_r[i], core_top.core0.rob.logic_dest_r[i], 
						core_top.core0.rob.done_r[i], core_top.core0.rob.rd_mem_r[i], core_top.core0.rob.wr_mem_r[i], core_top.core0.rob.br_flag_r[i],
						core_top.core0.rob.br_pretaken_r[i], core_top.core0.rob.br_taken_r[i], core_top.core0.rob.PC_r[i], core_top.core0.rob.br_target_r[i], 
						core_top.core0.rob.br_mask_r[i],core_top.core0.rob.IR_r[i],rob_instr_str[i]);
				end else begin
					$fdisplay(rob_fileno, "@@@  %-2d: p%d |  p%d |  r%d |   %b  |  %b %b  |  %b |   %b%b   | %h | %h |  %b  | %h  |  %-0s ", i, 
						core_top.core0.rob.dest_tag_r[i], core_top.core0.rob.old_dest_tag_r[i], core_top.core0.rob.logic_dest_r[i], 
						core_top.core0.rob.done_r[i], core_top.core0.rob.rd_mem_r[i], core_top.core0.rob.wr_mem_r[i], core_top.core0.rob.br_flag_r[i],
						core_top.core0.rob.br_pretaken_r[i], core_top.core0.rob.br_taken_r[i], core_top.core0.rob.PC_r[i], core_top.core0.rob.br_target_r[i], 
						core_top.core0.rob.br_mask_r[i],core_top.core0.rob.IR_r[i],rob_instr_str[i]);
				end
			end
		end else begin // print valid rob
			for (int i = core_top.core0.rob.head_r[`HT_W-1:0]; i!=core_top.core0.rob.tail_r[`HT_W-1:0]; i++) begin
				if(i>=`ROB_W)
    		        i = i%`ROB_W;
				$fdisplay(rob_fileno, "@@@ %-2d: p%d |  p%d |  r%d |   %b  |  %b %b  |  %b |   %b%b   | %h | %h |  %b  | %h  |  %-0s ", i, 
					core_top.core0.rob.dest_tag_r[i], core_top.core0.rob.old_dest_tag_r[i], core_top.core0.rob.logic_dest_r[i], 
					core_top.core0.rob.done_r[i], core_top.core0.rob.rd_mem_r[i], core_top.core0.rob.wr_mem_r[i], core_top.core0.rob.br_flag_r[i],
					core_top.core0.rob.br_pretaken_r[i], core_top.core0.rob.br_taken_r[i], core_top.core0.rob.PC_r[i], core_top.core0.rob.br_target_r[i], 
					core_top.core0.rob.br_mask_r[i],core_top.core0.rob.IR_r[i],rob_instr_str[i]);
			end
		end
		// print head and tail pointer
		$fdisplay(rob_fileno, "@@@ #pointer# head: %d | tail: %d | disp_en: %b", core_top.core0.rob.head_r[`HT_W-1:0], 
			core_top.core0.rob.tail_r[`HT_W-1:0], core_top.core0.rob.rob_dispatch_en_i);
		if (core_top.core0.rob.fu2rob_done_signal_i) begin
			$fdisplay(rob_fileno, "@@@ #done# fu done: %d | rob done entry: %d", core_top.core0.rob.fu2rob_done_signal_i,
				core_top.core0.rob.fu2rob_idx_i[`ROB_IDX_W-1:0]);
		end
		if (core_top.core0.rob.rob_head_retire_rdy_o)
			$fdisplay(rob_fileno, "@@@ #retire# retiring rob head at this cycle");
		if (core_top.core0.rob.br_recovery_rdy_o)
			$fdisplay(rob_fileno, "@@@ #br_recovery# recovering to rob entry: %d", core_top.core0.rob.tail_r_nxt[`HT_W-1:0]);

	endtask // task print_rob



	// Count the number of posedges and number of instructions completed
	// till simulation ends
	always @(posedge clk or posedge rst)
	begin
		if(rst)
		begin
			clock_count <= `SD 0;
			instr_count <= `SD 0;
		end
		else
		if (~freeze_clk_count) begin
			clock_count <= `SD (clock_count + 1);
			instr_count <= `SD (instr_count + core_retired_instrs);
		end
	end 

	always @(negedge clk)
	begin
		if(rst)
			$display(	"@@\n@@  %t : System STILL at reset, can't show anything\n@@",
						$realtime);
		else
		begin
			// print rs and rob at every cycle during negedge
			`SD
			print_rs;
			print_rob;
		  	`SD;
		  
		    // print the piepline stuff via c code to the pipeline.out

			// print the writeback information to writeback.out
			if(core_retired_instrs>0) begin
				if(core_retire_wr_en)
					$fdisplay(	wb_fileno, "PC=%x, REG[%d]=%x",
								core_top.core0.rob.PC_r[core_top.core0.rob.head_r[`HT_W-1:0]],
								core_top.core0.rob.logic_dest_r[core_top.core0.rob.head_r[`HT_W-1:0]],
								core_top.core0.preg_file.reg_data_r[core_top.core0.rob.dest_tag_r[core_top.core0.rob.head_r[`HT_W-1:0]]]);
				else
					$fdisplay(wb_fileno, "PC=%x, ---",core_top.core0.rob.PC_r[core_top.core0.rob.head_r[`HT_W-1:0]]);
			end

			//if (core_top.core0.rob.rob_halt_o) begin
			//		$fdisplay(wb_fileno, "PC=%x, ---",core_top.core0.rob.PC_r[core_top.core0.rob.head_r[`HT_W-1:0]]);
			//end

			// deal with any halting conditions
			if(core_error_status!=`NO_ERROR)
			begin
				$display(	"@@@ Unified Memory contents hex on left, decimal on right: ");
							show_mem_with_decimal(0,`MEM_64BIT_LINES - 1); 
				// 8Bytes per line, 16kB total

				$display("@@  %t : System halted\n@@", $realtime);

				case(core_error_status)
					`HALTED_ON_MEMORY_ERROR:  
						$display(	"@@@ System halted on memory error");
					`HALTED_ON_HALT:          
						$display(	"@@@ System halted on HALT instruction");
					`HALTED_ON_ILLEGAL:
						$display(	"@@@ System halted on illegal instruction");
					default: 
						$display(	"@@@ System halted on unknown error code %x",
									core_error_status);
				endcase
				$display("@@@\n@@");
				show_clk_count;
				//print_close(); // close the pipe_print output file
				//$fclose(wb_fileno);
				//$fclose(rs_fileno);
				//$fclose(rob_fileno);
				#100 $finish;
			end
		end  // if(rst)
	end

	
	initial begin // for step by step debug
		for (int i = 0; i < 25000; i++) begin
			@(negedge clk);
		end
		$display("@@@\n@@");
		show_clk_count;
		//print_close(); // close the pipe_print output file
		//$fclose(wb_fileno);
		//$fclose(rs_fileno);
		//$fclose(rob_fileno);
		#100 $finish;
	end


	always_comb begin
		for (int i = 0; i < `RS_ENT_NUM; i = i + 1) begin
			rs_instr_str[i] = get_instr_string(core_top.core0.rs.IR_vec[i],~core_top.core0.rs.avail_vec[i]);
		end
		for (int i = 0; i < `ROB_W; i = i + 1) begin
		
			rob_instr_str[i] = 	get_instr_string(core_top.core0.rob.IR_r[i],core_top.core0.rob.vld_r[i]);
		end
	end

	// function to get instr string
	function [8*8:0] get_instr_string;
	input [31:0] IR;
	input        instr_valid;
	begin
		if (!instr_valid)
			get_instr_string = "-";
		else if (IR==`NOOP_INST)
			get_instr_string = "nop";
		else
			case (IR[31:26])
				6'h00: get_instr_string = (IR == 32'h555) ? "halt" : "call_pal";
				6'h08: get_instr_string = "lda";
				6'h09: get_instr_string = "ldah";
				6'h0a: get_instr_string = "ldbu";
				6'h0b: get_instr_string = "ldqu";
				6'h0c: get_instr_string = "ldwu";
				6'h0d: get_instr_string = "stw";
				6'h0e: get_instr_string = "stb";
				6'h0f: get_instr_string = "stqu";
				6'h10: // INTA_GRP
				begin
					case (IR[11:5])
						7'h00: get_instr_string = "addl";
						7'h02: get_instr_string = "s4addl";
						7'h09: get_instr_string = "subl";
						7'h0b: get_instr_string = "s4subl";
						7'h0f: get_instr_string = "cmpbge";
						7'h12: get_instr_string = "s8addl";
						7'h1b: get_instr_string = "s8subl";
						7'h1d: get_instr_string = "cmpult";
						7'h20: get_instr_string = "addq";
						7'h22: get_instr_string = "s4addq";
						7'h29: get_instr_string = "subq";
						7'h2b: get_instr_string = "s4subq";
						7'h2d: get_instr_string = "cmpeq";
						7'h32: get_instr_string = "s8addq";
						7'h3b: get_instr_string = "s8subq";
						7'h3d: get_instr_string = "cmpule";
						7'h40: get_instr_string = "addlv";
						7'h49: get_instr_string = "sublv";
						7'h4d: get_instr_string = "cmplt";
						7'h60: get_instr_string = "addqv";
						7'h69: get_instr_string = "subqv";
						7'h6d: get_instr_string = "cmple";
						default: get_instr_string = "invalid";
					endcase
				end
				6'h11: // INTL_GRP
				begin
					case (IR[11:5])
						7'h00: get_instr_string = "and";
						7'h08: get_instr_string = "bic";
						7'h14: get_instr_string = "cmovlbs";
						7'h16: get_instr_string = "cmovlbc";
						7'h20: get_instr_string = "bis";
						7'h24: get_instr_string = "cmoveq";
						7'h26: get_instr_string = "cmovne";
						7'h28: get_instr_string = "ornot";
						7'h40: get_instr_string = "xor";
						7'h44: get_instr_string = "cmovlt";
						7'h46: get_instr_string = "cmovge";
						7'h48: get_instr_string = "eqv";
						7'h61: get_instr_string = "amask";
						7'h64: get_instr_string = "cmovle";
						7'h66: get_instr_string = "cmovgt";
						7'h6c: get_instr_string = "implver";
						default: get_instr_string = "invalid";
					endcase
				end
				6'h12: // INTS_GRP
				begin
					case(IR[11:5])
						7'h02: get_instr_string = "mskbl";
						7'h06: get_instr_string = "extbl";
						7'h0b: get_instr_string = "insbl";
						7'h12: get_instr_string = "mskwl";
						7'h16: get_instr_string = "extwl";
						7'h1b: get_instr_string = "inswl";
						7'h22: get_instr_string = "mskll";
						7'h26: get_instr_string = "extll";
						7'h2b: get_instr_string = "insll";
						7'h30: get_instr_string = "zap";
						7'h31: get_instr_string = "zapnot";
						7'h32: get_instr_string = "mskql";
						7'h34: get_instr_string = "srl";
						7'h36: get_instr_string = "extql";
						7'h39: get_instr_string = "sll";
						7'h3b: get_instr_string = "insql";
						7'h3c: get_instr_string = "sra";
						7'h52: get_instr_string = "mskwh";
						7'h57: get_instr_string = "inswh";
						7'h5a: get_instr_string = "extwh";
						7'h62: get_instr_string = "msklh";
						7'h67: get_instr_string = "inslh";
						7'h6a: get_instr_string = "extlh";
						7'h72: get_instr_string = "mskqh";
						7'h77: get_instr_string = "insqh";
						7'h7a: get_instr_string = "extqh";
						default: get_instr_string = "invalid";
					endcase
				end
				6'h13: // INTM_GRP
				begin
					case (IR[11:5])
						7'h01: get_instr_string = "mull";
						7'h20: get_instr_string = "mulq";
						7'h30: get_instr_string = "umulh";
						7'h40: get_instr_string = "mullv";
						7'h60: get_instr_string = "mulqv";
						default: get_instr_string = "invalid";
					endcase
				end
				6'h14: get_instr_string = "itfp"; // unimplemented
				6'h15: get_instr_string = "fltv"; // unimplemented
				6'h16: get_instr_string = "flti"; // unimplemented
				6'h17: get_instr_string = "fltl"; // unimplemented
				6'h1a: get_instr_string = "jsr";
				6'h1c: get_instr_string = "ftpi";
				6'h20: get_instr_string = "ldf";
				6'h21: get_instr_string = "ldg";
				6'h22: get_instr_string = "lds";
				6'h23: get_instr_string = "ldt";
				6'h24: get_instr_string = "stf";
				6'h25: get_instr_string = "stg";
				6'h26: get_instr_string = "sts";
				6'h27: get_instr_string = "stt";
				6'h28: get_instr_string = "ldl";
				6'h29: get_instr_string = "ldq";
				6'h2a: get_instr_string = "ldll";
				6'h2b: get_instr_string = "ldql";
				6'h2c: get_instr_string = "stl";
				6'h2d: get_instr_string = "stq";
				6'h2e: get_instr_string = "stlc";
				6'h2f: get_instr_string = "stqc";
				6'h30: get_instr_string = "br";
				6'h31: get_instr_string = "fbeq";
				6'h32: get_instr_string = "fblt";
				6'h33: get_instr_string = "fble";
				6'h34: get_instr_string = "bsr";
				6'h35: get_instr_string = "fbne";
				6'h36: get_instr_string = "fbge";
				6'h37: get_instr_string = "fbgt";
				6'h38: get_instr_string = "blbc";
				6'h39: get_instr_string = "beq";
				6'h3a: get_instr_string = "blt";
				6'h3b: get_instr_string = "ble";
				6'h3c: get_instr_string = "blbs";
				6'h3d: get_instr_string = "bne";
				6'h3e: get_instr_string = "bge";
				6'h3f: get_instr_string = "bgt";
				default: get_instr_string = "invalid";
			endcase
		end
	endfunction


endmodule: core_top_tb

