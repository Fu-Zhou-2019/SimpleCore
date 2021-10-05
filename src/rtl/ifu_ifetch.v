//=====================================================================
//
// Designer   : LI Jiarui
//
// Description:
//  The ifetch module to generate next PC and bus request
//
// General logic:
// 1. for first instruction fetch after RESET, use top module input 'pc_rtvec' for pc value for first instruction fetch.
//    users may assign different values to control PC default reset value.
// 2. all SimpleCore instructions are in 32 bit, hence the next PC in sequential fetch should be PC+4
// 3. for branch instruction, use target jump address predicted in 'ifu_bpu.v'
// 4. for instruction from EXU pipeline flush, use address from EXU as new PC
//
// ====================================================================
`include "defines.v"

module ifu_ifetch(
  output[`PC_SIZE-1:0] inspect_pc,
  input  [`PC_SIZE-1:0] pc_rtvec,  

  // Fetch Interface to memory system (ITCM), internal protocol
  // Instruction Fetch Request channel
  output ifu_req_valid, // Handshake valid
  input  ifu_req_ready, // Handshake ready
  // Note: the req-addr can be unaligned with the length indicated by req_len signal.
  // The targetd ITCM ctrl module will handle the unalign cases and split-and-merge works

  output [`PC_SIZE-1:0] ifu_req_pc, // Fetch PC
  output ifu_req_seq, // This request is a sequential instruction fetch, all is in 32 bit
  // output ifu_req_seq_rv32, // This request is incremented 32bits fetch
  output [`PC_SIZE-1:0] ifu_req_last_pc, // The last accessed PC address (i.e., pc_r)
  
  // Insrtuction Fetch Response channel
  input  ifu_rsp_valid, // Response valid 
  output ifu_rsp_ready, // Response ready
  input  ifu_rsp_err,   // Response error
  // Note: the RSP channel always return a valid instruction fetched from the fetching start PC address.
  // The targetd (ITCM, ICache or Sys-MEM) ctrl module will handle the unalign cases and split-and-merge works
  input  [`INSTR_SIZE-1:0] ifu_rsp_instr, // Response instruction
  // The Instruction Register stage to EXU interface
  output [`INSTR_SIZE-1:0] ifu_o_ir,// The instruction register
  output [`PC_SIZE-1:0] ifu_o_pc,   // The PC register along with
  output ifu_o_pc_vld,
  output [`RFIDX_WIDTH-1:0] ifu_o_rs1idx,
  output [`RFIDX_WIDTH-1:0] ifu_o_rs2idx,
  output ifu_o_prdt_taken,               // The Bxx is predicted as taken
  //output ifu_o_misalgn,                  // The fetch misalign 
  //output ifu_o_buserr,                   // The fetch bus error
  //output ifu_o_muldiv_b2b,               // The mul/div back2back case
  output ifu_o_valid, // Handshake signals with EXU stage
  input  ifu_o_ready,

  output  pipe_flush_ack, // pipeline flush acknowledge
  input   pipe_flush_req, // pipeline flush request
  input   [`PC_SIZE-1:0] pipe_flush_add_op1,  
  input   [`PC_SIZE-1:0] pipe_flush_add_op2,
  input  oitf_empty,
  input  [`XLEN-1:0] rf2ifu_x1,
  input  [`XLEN-1:0] rf2ifu_rs1,
  input  dec2ifu_rs1en,
  input  dec2ifu_rden,
  input  [`RFIDX_WIDTH-1:0] dec2ifu_rdidx,
  // currently multiplication/division are unsupported
  //input  dec2ifu_mulhsu,
  //input  dec2ifu_div   ,
  //input  dec2ifu_rem   ,
  //input  dec2ifu_divu  ,
  //input  dec2ifu_remu  ,

  input  clk,
  input  rst_n
  );

  wire ifu_req_hsked  = (ifu_req_valid & ifu_req_ready) ;
  wire ifu_rsp_hsked  = (ifu_rsp_valid & ifu_rsp_ready) ;
  wire ifu_ir_o_hsked = (ifu_o_valid & ifu_o_ready) ;
  wire pipe_flush_hsked = pipe_flush_req & pipe_flush_ack;

  
 // The rst_flag is the synced version of rst_n
 //    * rst_n is asserted 
 // The rst_flag will be clear when
 //    * rst_n is de-asserted 
  wire reset_flag_r;
  gnrl_dffrs #(1) reset_flag_dffrs (1'b0, reset_flag_r, clk, rst_n);
 //
 // The reset_req valid is set when 
 //    * Currently reset_flag is asserting
 // The reset_req valid is clear when 
 //    * Currently reset_req is asserting
 //    * Currently the flush can be accepted by IFU
  wire reset_req_r;
  wire reset_req_set = (~reset_req_r) & reset_flag_r;
  wire reset_req_clr = reset_req_r & ifu_req_hsked;
  wire reset_req_ena = reset_req_set | reset_req_clr;
  wire reset_req_nxt = reset_req_set | (~reset_req_clr);

  gnrl_dfflr #(1) reset_req_dfflr (reset_req_ena, reset_req_nxt, reset_req_r, clk, rst_n);

  wire ifu_reset_req = reset_req_r;





 
  // The halt ack generation
  /*
  wire halt_ack_set;
  wire halt_ack_clr;
  wire halt_ack_ena;
  wire halt_ack_r;
  wire halt_ack_nxt;
*/
     // The halt_ack will be set when
     // 1. Currently halt_req is asserting
     // 2. Currently halt_ack is not asserting
     // 3. Currently the ifetch REQ channel is ready, means there is no oustanding transactions
  wire ifu_no_outs;
  //assign halt_ack_set = ifu_halt_req & (~halt_ack_r) & ifu_no_outs;
     // The halt_ack_r valid is cleared when 
     //    * Currently halt_ack is asserting
     //    * Currently halt_req is de-asserting
  //assign halt_ack_clr = halt_ack_r & (~ifu_halt_req);

  //assign halt_ack_ena = halt_ack_set | halt_ack_clr;
  //assign halt_ack_nxt = halt_ack_set | (~halt_ack_clr);

  //gnrl_dfflr #(1) halt_ack_dfflr (halt_ack_ena, halt_ack_nxt, halt_ack_r, clk, rst_n);

  //assign ifu_halt_ack = halt_ack_r;


   // The flush ack signal generation
   //   Ideally the flush is acked when the ifetch interface is ready or there is rsponse valid 
   //   But to cut the comb loop between EXU and IFU, we always accept the flush, when it is not really acknowledged, we use a delayed flush indication to remember this flush
   //   Note: Even if there is a delayed flush pending there, we still can accept new flush request
   assign pipe_flush_ack = 1'b1;

   wire dly_flush_set;
   wire dly_flush_clr;
   wire dly_flush_ena;
   wire dly_flush_nxt;

   // The dly_flush will be set when there is a flush requst is coming, but the ifu is not ready to accept new fetch request
   wire dly_flush_r;
   assign dly_flush_set = pipe_flush_req & (~ifu_req_hsked);
   
   // The dly_flush_r valid is cleared when the delayed flush is issued
   assign dly_flush_clr = dly_flush_r & ifu_req_hsked;
   assign dly_flush_ena = dly_flush_set | dly_flush_clr;
   assign dly_flush_nxt = dly_flush_set | (~dly_flush_clr);

   gnrl_dfflr #(1) dly_flush_dfflr (dly_flush_ena, dly_flush_nxt, dly_flush_r, clk, rst_n);

   wire dly_pipe_flush_req = dly_flush_r;
   wire pipe_flush_req_real = pipe_flush_req | dly_pipe_flush_req;


  // The IR register to be used in EXU for decoding
  wire ir_valid_set;
  wire ir_valid_clr;
  wire ir_valid_ena;
  wire ir_valid_r;
  wire ir_valid_nxt;

  wire ir_pc_vld_set;
  wire ir_pc_vld_clr;
  wire ir_pc_vld_ena;
  wire ir_pc_vld_r;
  wire ir_pc_vld_nxt;


  // The ir valid is set when there is new instruction fetched AND no flushing 
  wire ifu_rsp_need_replay;
  wire pc_newpend_r;
  wire ifu_ir_i_ready;
  assign ir_valid_set  = ifu_rsp_hsked & (~pipe_flush_req_real) & (~ifu_rsp_need_replay);
  assign ir_pc_vld_set = pc_newpend_r & ifu_ir_i_ready & (~pipe_flush_req_real) & (~ifu_rsp_need_replay);
  
  // The ir valid is cleared when it is accepted by EXU stage OR flushing 
  assign ir_valid_clr  = ifu_ir_o_hsked | (pipe_flush_hsked & ir_valid_r);
  assign ir_pc_vld_clr = ir_valid_clr;

  assign ir_valid_ena  = ir_valid_set  | ir_valid_clr;
  assign ir_valid_nxt  = ir_valid_set  | (~ir_valid_clr);
  assign ir_pc_vld_ena = ir_pc_vld_set | ir_pc_vld_clr;
  assign ir_pc_vld_nxt = ir_pc_vld_set | (~ir_pc_vld_clr);

  gnrl_dfflr #(1) ir_valid_dfflr (ir_valid_ena, ir_valid_nxt, ir_valid_r, clk, rst_n);
  gnrl_dfflr #(1) ir_pc_vld_dfflr (ir_pc_vld_ena, ir_pc_vld_nxt, ir_pc_vld_r, clk, rst_n);

  // IFU-IR loaded with the returned instruction from the IFetch RSP channel
  wire [`INSTR_SIZE-1:0] ifu_ir_nxt = ifu_rsp_instr;
  
  // IFU-PC loaded with the current PC
  wire ifu_err_nxt = ifu_rsp_err;

  // IFU-IR and IFU-PC as the datapath register, only loaded and toggle when the valid reg is set
  wire ifu_err_r;
  gnrl_dfflr #(1) ifu_err_dfflr(ir_valid_set, ifu_err_nxt, ifu_err_r, clk, rst_n);
  wire prdt_taken;  
  wire ifu_prdt_taken_r;
  gnrl_dfflr #(1) ifu_prdt_taken_dfflr (ir_valid_set, prdt_taken, ifu_prdt_taken_r, clk, rst_n);
  wire ifu_muldiv_b2b_nxt;
  wire ifu_muldiv_b2b_r;
  gnrl_dfflr #(1) ir_muldiv_b2b_dfflr (ir_valid_set, ifu_muldiv_b2b_nxt, ifu_muldiv_b2b_r, clk, rst_n);
     
  //To save power the H-16bits only loaded when it is 32bits length instrution, however all SimpleCore instruction is in 32 bit
  
  /*  =============== Original ==================
  wire [`INSTR_SIZE-1:0] ifu_ir_r;// The instruction register
  wire minidec_rv32;
  wire ir_hi_ena = ir_valid_set & minidec_rv32;
  wire ir_lo_ena = ir_valid_set;
  gnrl_dfflr #(`INSTR_SIZE/2) ifu_hi_ir_dfflr (ir_hi_ena, ifu_ir_nxt[31:16], ifu_ir_r[31:16], clk, rst_n);
  gnrl_dfflr #(`INSTR_SIZE/2) ifu_lo_ir_dfflr (ir_lo_ena, ifu_ir_nxt[15: 0], ifu_ir_r[15: 0], clk, rst_n);
  */

  // ******************* Modified **********************
  wire [`INSTR_SIZE-1:0] ifu_ir_r;// The instruction register
  ir_ena = ir_valid_set;
  gnrl_dfflr #('INSTR_SIZE/2) ifu_ir_dfflr (ir_ena, ifu_ir_nxt[31:16], ifu_ir_r[31:16], clk, rst_n);

  wire minidec_rs1en;
  wire minidec_rs2en;
  wire [`RFIDX_WIDTH-1:0] minidec_rs1idx;
  wire [`RFIDX_WIDTH-1:0] minidec_rs2idx;

  wire [`PC_SIZE-1:0] pc_r;
  wire [`PC_SIZE-1:0] ifu_pc_nxt = pc_r; // generate next oc
  wire [`PC_SIZE-1:0] ifu_pc_r;
  gnrl_dfflr #(`PC_SIZE) ifu_pc_dfflr (ir_pc_vld_set, ifu_pc_nxt,  ifu_pc_r, clk, rst_n);

  assign ifu_o_ir  = ifu_ir_r;
  assign ifu_o_pc  = ifu_pc_r;

  assign ifu_o_rs1idx = ir_rs1idx_r;
  assign ifu_o_rs2idx = ir_rs2idx_r;
  assign ifu_o_prdt_taken = ifu_prdt_taken_r;
  //assign ifu_o_muldiv_b2b = ifu_muldiv_b2b_r;

  assign ifu_o_valid  = ir_valid_r;
  assign ifu_o_pc_vld = ir_pc_vld_r;

  // The IFU-IR stage will be ready when it is empty or under-clearing
  assign ifu_ir_i_ready   = (~ir_valid_r) | ir_valid_clr;

  

  // JALR instruction dependency check
  wire ir_empty = ~ir_valid_r;
  wire ir_rs1en = dec2ifu_rs1en;
  wire ir_rden = dec2ifu_rden;
  wire [`RFIDX_WIDTH-1:0] ir_rdidx = dec2ifu_rdidx;
  wire [`RFIDX_WIDTH-1:0] minidec_jalr_rs1idx;
  wire jalr_rs1idx_cam_irrdidx = ir_rden & (minidec_jalr_rs1idx == ir_rdidx) & ir_valid_r;

  /* currently multiplication/division are unsupported
  // MULDIV BACK2BACK Fusing
  // To detect the sequence of MULH[[S]U] rdh, rs1, rs2;    MUL rdl, rs1, rs2
  // To detect the sequence of     DIV[U] rdq, rs1, rs2; REM[U] rdr, rs1, rs2  
  wire minidec_mul ;
  wire minidec_div ;
  wire minidec_rem ;
  wire minidec_divu;
  wire minidec_remu;
  assign ifu_muldiv_b2b_nxt = 
      (
          // For multiplicaiton, only the MUL instruction following
          //    MULH/MULHU/MULSU can be treated as back2back
          ( minidec_mul & dec2ifu_mulhsu)
          // For divider and reminder instructions, only the following cases
          //    can be treated as back2back
          //      * DIV--REM
          //      * REM--DIV
          //      * DIVU--REMU
          //      * REMU--DIVU
        | ( minidec_div  & dec2ifu_rem)
        | ( minidec_rem  & dec2ifu_div)
        | ( minidec_divu & dec2ifu_remu)
        | ( minidec_remu & dec2ifu_divu)
      )
      // The last rs1 and rs2 indexes are same as this instruction
      & (ir_rs1idx_r == ir_rs1idx_nxt)
      & (ir_rs2idx_r == ir_rs2idx_nxt)
      // The last rs1 and rs2 indexes are not same as last RD index
      & (~(ir_rs1idx_r == ir_rdidx))
      & (~(ir_rs2idx_r == ir_rdidx))
      ;
   */

  // Next PC generation
  wire minidec_bjp;
  wire minidec_jal;
  wire minidec_jalr;
  wire minidec_bxx;
  wire [`XLEN-1:0] minidec_bjp_imm;

  // The mini-decoder to check instruciton length and branch type 
  ifu_minidec u_ifu_minidec (
      .instr       (ifu_ir_nxt         ),

      .dec_rs1en   (minidec_rs1en      ),
      .dec_rs2en   (minidec_rs2en      ),
      .dec_rs1idx  (minidec_rs1idx     ),
      .dec_rs2idx  (minidec_rs2idx     ),

      //.dec_rv32    (minidec_rv32       ), //instruction is all in 32 bit
      .dec_bjp     (minidec_bjp        ),
      .dec_jal     (minidec_jal        ),
      .dec_jalr    (minidec_jalr       ),
      .dec_bxx     (minidec_bxx        ),

      //.dec_mulhsu  (),
      //.dec_mul     (minidec_mul ),
      //.dec_div     (minidec_div ),
      //.dec_rem     (minidec_rem ),
      //.dec_divu    (minidec_divu),
      //.dec_remu    (minidec_remu),

      .dec_jalr_rs1idx (minidec_jalr_rs1idx),
      .dec_bjp_imm (minidec_bjp_imm    )
  );

  wire bpu_wait;
  wire [`PC_SIZE-1:0] prdt_pc_add_op1;  
  wire [`PC_SIZE-1:0] prdt_pc_add_op2;

  ifu_bpu u_ifu_bpu(
    .pc                       (pc_r),
   
    .dec_jal                  (minidec_jal  ),
    .dec_jalr                 (minidec_jalr ),
    .dec_bxx                  (minidec_bxx  ),
    .dec_bjp_imm              (minidec_bjp_imm  ),
    .dec_jalr_rs1idx          (minidec_jalr_rs1idx  ),

    .dec_i_valid              (ifu_rsp_valid),
    .ir_valid_clr             (ir_valid_clr),
                
    .oitf_empty               (oitf_empty),
    .ir_empty                 (ir_empty  ),
    .ir_rs1en                 (ir_rs1en  ),

    .jalr_rs1idx_cam_irrdidx  (jalr_rs1idx_cam_irrdidx),
  
    .bpu_wait                 (bpu_wait       ),  
    .prdt_taken               (prdt_taken     ),  
    .prdt_pc_add_op1          (prdt_pc_add_op1),  
    .prdt_pc_add_op2          (prdt_pc_add_op2),

    .bpu2rf_rs1_ena           (bpu2rf_rs1_ena),
    .rf2bpu_x1                (rf2ifu_x1    ),
    .rf2bpu_rs1               (rf2ifu_rs1   ),

    .clk                      (clk  ) ,
    .rst_n                    (rst_n )                 
  );
  
  /*
  // If the instruciton is 32bits length, increament 4, otherwise 2
  //wire [2:0] pc_incr_ofst = minidec_rv32 ? 3'd4 : 3'd2;
  */

  // all SimpleCore instruction is in 32 bit, hence increament is always 4
  wire [2:0] pc_incr_ofst = 3'd4;

  wire [`PC_SIZE-1:0] pc_nxt_pre;
  wire [`PC_SIZE-1:0] pc_nxt;

  wire bjp_req = minidec_bjp & prdt_taken;

  wire ifetch_replay_req;

  wire [`PC_SIZE-1:0] pc_add_op1 = 
                            `ifndef E203_TIMING_BOOST//}
                               pipe_flush_req  ? pipe_flush_add_op1 :
                               dly_pipe_flush_req  ? pc_r :
                            `endif//}
                               ifetch_replay_req  ? pc_r :
                               bjp_req ? prdt_pc_add_op1    :
                               ifu_reset_req   ? pc_rtvec :
                                                 pc_r;

  wire [`SIZE-1:0] pc_add_op2 =  
                            /*`ifndef E203_TIMING_BOOST//}
                               pipe_flush_req  ? pipe_flush_add_op2 :
                               dly_pipe_flush_req  ? `PC_SIZE'b0 :
                            `endif//} */
                               ifetch_replay_req  ? `PC_SIZE'b0 :
                               bjp_req ? prdt_pc_add_op2    :
                               ifu_reset_req   ? `PC_SIZE'b0 :
                                                 pc_incr_ofst ;

  assign ifu_req_seq = (~pipe_flush_req_real) & (~ifu_reset_req) & (~ifetch_replay_req) & (~bjp_req);
  // assign ifu_req_seq_rv32 = minidec_rv32;  // since all instruction is in 32 bit
  assign ifu_req_last_pc = pc_r;
//1
  assign pc_nxt_pre = pc_add_op1 + pc_add_op2;
  
  `ifndef TIMING_BOOST//}
  assign pc_nxt = {pc_nxt_pre[`PC_SIZE-1:1],1'b0};
  `else//}{
  //to check: there is no pipe_flush_pc
  assign pc_nxt = 
               pipe_flush_req ? {pipe_flush_pc[`PC_SIZE-1:1],1'b0} :
               dly_pipe_flush_req ? {pc_r[`PC_SIZE-1:1],1'b0} :
               {pc_nxt_pre[`PC_SIZE-1:1],1'b0};
  `endif//}

  // The Ifetch issue new ifetch request when
  //  1. it is a bjp insturction
  //  2. it does not need to wait
  //  3. it is not a replay-set cycle
  //  4. there is no halt_request
  wire ifu_new_req = (~bpu_wait) & (~reset_flag_r) & (~ifu_rsp_need_replay);


  // The fetch request valid is triggering when
  //      * New ifetch request
  //      * or The flush-request is pending
  wire ifu_req_valid_pre = ifu_new_req | ifu_reset_req | pipe_flush_req_real | ifetch_replay_req;
 
 
  // The new request ready condition is:
  //   * No outstanding reqeusts
  //   * Or if there is outstanding, but it is reponse valid back
  wire out_flag_clr;
  wire out_flag_r;
  wire new_req_condi = (~out_flag_r) | out_flag_clr;
  assign ifu_no_outs   = (~out_flag_r) | ifu_rsp_valid;
        // Here we use the rsp_valid rather than the out_flag_clr (ifu_rsp_hsked) because
        //   as long as the rsp_valid is asserting then means last request have returned the
        //   response back, in WFI case, we cannot expect it to be handshaked (otherwise deadlock)

  assign ifu_req_valid = ifu_req_valid_pre & new_req_condi;

  //wire ifu_rsp2ir_ready = (ifu_rsp_replay | pipe_flush_req_real) ? 1'b1 : (ifu_ir_i_ready & (~bpu_wait));
  wire ifu_rsp2ir_ready = (pipe_flush_req_real) ? 1'b1 : (ifu_ir_i_ready & ifu_req_ready & (~bpu_wait));

  // Response channel only ready when:
  //   * IR is ready to accept new instructions
  assign ifu_rsp_ready = ifu_rsp2ir_ready;

  // The PC will need to be updated when ifu req channel handshaked or a flush is incoming
  wire pc_ena = ifu_req_hsked | pipe_flush_hsked;

  gnrl_dfflr #(`PC_SIZE) pc_dfflr (pc_ena, pc_nxt, pc_r, clk, rst_n);


 assign inspect_pc = pc_r;


  assign ifu_req_pc    = pc_nxt;

     // The out_flag will be set if there is a new request handshaked
  wire out_flag_set = ifu_req_hsked;
     // The out_flag will be cleared if there is a request response handshaked
  assign out_flag_clr = ifu_rsp_hsked;
  wire out_flag_ena = out_flag_set | out_flag_clr;
     // If meanwhile set and clear, then set preempt
  wire out_flag_nxt = out_flag_set | (~out_flag_clr);

  gnrl_dfflr #(1) out_flag_dfflr (out_flag_ena, out_flag_nxt, out_flag_r, clk, rst_n);

       // The pc_newpend will be set if there is a new PC loaded
  wire pc_newpend_set = pc_ena;
     // The pc_newpend will be cleared if have already loaded into the IR-PC stage
  wire pc_newpend_clr = ir_pc_vld_set;
  wire pc_newpend_ena = pc_newpend_set | pc_newpend_clr;
     // If meanwhile set and clear, then set preempt
  wire pc_newpend_nxt = pc_newpend_set | (~pc_newpend_clr);

  gnrl_dfflr #(1) pc_newpend_dfflr (pc_newpend_ena, pc_newpend_nxt, pc_newpend_r, clk, rst_n);


  assign ifu_rsp_need_replay = 1'b0;
  assign ifetch_replay_req = 1'b0;

  `ifndef FPGA_SOURCE//{
  `ifndef DISABLE_SV_ASSERTION//{
//synopsys translate_off

CHECK_IFU_REQ_VALID_NO_X:
  assert property (@(posedge clk) disable iff (~rst_n)
                     (ifu_req_valid !== 1'bx)
                  )
  else $fatal ("\n Error: Oops, detected X value for ifu_req_valid !!! This should never happen. \n");

//synopsys translate_on
`endif//}
`endif//}

endmodule

