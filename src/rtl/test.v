`include "defines.v"

module ifu_ifetch(
   output[`PC_SIZE-1:0] inspect_pc,             //unused
   input  [`PC_SIZE-1:0] pc_rtvec,              //init pc
   //output pc_vld,
   output ifu_req_valid, 
   input  ifu_req_ready,
   output [`PC_SIZE-1:0] ifu_req_pc,
   input  ifu_rsp_valid, 
   output ifu_rsp_ready, 
   input  [`INSTR_SIZE-1:0] ifu_rsp_instr, 

   output [`INSTR_SIZE-1:0] ifu_o_ir,           // The instruction register
   output [`PC_SIZE-1:0] ifu_o_pc,
   output [`RFIDX_WIDTH-1:0] ifu_o_rs1idx,
   output [`RFIDX_WIDTH-1:0] ifu_o_rs2idx,
   output ifu_o_prdt_taken,                     // The Bxx is predicted as taken
   output ifu_o_valid,                          // Handshake signals with EXU stage
   input  ifu_o_ready,

   output  pipe_flush_ack,                      // pipeline flush acknowledge
   input   pipe_flush_req,                      // pipeline flush request
   input   [`PC_SIZE-1:0] pipe_flush_add_op1,  
   input   [`PC_SIZE-1:0] pipe_flush_add_op2,
   input  oitf_empty,
   input  [`XLEN-1:0] rf2ifu_x1,
   input  [`XLEN-1:0] rf2ifu_rs1,
   input  dec2ifu_rs1en,
   input  dec2ifu_rden,
   input  [`RFIDX_WIDTH-1:0] dec2ifu_rdidx,

   input  clk,
   input  rst_n
);
   
   wire [`PC_SIZE-1:0] pc_r;
   wire prdt_taken;
   wire ir_nop_instr_r;

   //instantiate minidec
   wire minidec_bjp;
   wire minidec_jal;
   wire minidec_jalr;
   wire minidec_bxx;
   wire [`XLEN-1:0] minidec_bjp_imm;
   wire [`RFIDX_WIDTH-1:0] minidec_jalr_rs1idx;
   wire minidec_rs1en;  
   wire minidec_rs2en;
   wire [`RFIDX_WIDTH-1:0] minidec_rs1idx;
   wire [`RFIDX_WIDTH-1:0] minidec_rs2idx;
   ifu_minidec u_ifu_minidec (
      .instr       (ifu_rsp_instr         ),
      .dec_rs1en   (minidec_rs1en      ),
      .dec_rs2en   (minidec_rs2en      ),
      .dec_rs1idx  (minidec_rs1idx     ),
      .dec_rs2idx  (minidec_rs2idx     ),
      .dec_bjp     (minidec_bjp        ),
      .dec_jal     (minidec_jal        ),
      .dec_jalr    (minidec_jalr       ),
      .dec_bxx     (minidec_bxx        ),

      .dec_jalr_rs1idx (minidec_jalr_rs1idx),
      .dec_bjp_imm (minidec_bjp_imm)
   );

   //instantiate bpu
   wire bpu_wait;
   wire [`PC_SIZE-1:0] prdt_pc_add_op1;  
   wire [`PC_SIZE-1:0] prdt_pc_add_op2;
   wire jalr_rs1idx_match_irrdidx = dec2ifu_rden & (minidec_jalr_rs1idx == dec2ifu_rdidx);
   ifu_bpu u_ifu_bpu(
      .pc                           (pc_r),
      .dec_jal                      (minidec_jal  ),
      .dec_jalr                     (minidec_jalr ),
      .dec_bxx                      (minidec_bxx  ),
      .dec_bjp_imm                  (minidec_bjp_imm  ),
      .dec_jalr_rs1idx              (minidec_jalr_rs1idx  ),
      .dec_i_valid                  (ifu_rsp_valid),
      .oitf_empty                   (oitf_empty),
      .ir_rs1en                     (dec2ifu_rs1en  ),
      .jalr_rs1idx_match_irrdidx    (jalr_rs1idx_match_irrdidx),
      .bpu_wait                     (bpu_wait       ),  
      .prdt_taken                   (prdt_taken     ),  
      .prdt_pc_add_op1              (prdt_pc_add_op1),  
      .prdt_pc_add_op2              (prdt_pc_add_op2),
      .ir_nop_instr                 (ir_nop_instr_r),
      .rf2bpu_x1                    (rf2ifu_x1    ),
      .rf2bpu_rs1                   (rf2ifu_rs1   ),
      .clk                          (clk  ) ,
      .rst_n                        (rst_n )                 
   );

   wire ifu_o_hsked = (ifu_o_valid & ifu_o_ready);             //instruction accepted by exu
   assign ifu_req_valid = ~reset_flag_r;
   wire ifu_req_hsked  = (ifu_req_valid & ifu_req_ready);
   wire ifu_rsp_hsked  = (ifu_rsp_valid & ifu_rsp_ready);
   assign pipe_flush_ack = 1'b1;                               //always accept pipeflush

 // The rst_flag is the synced version of rst_n. rst_n is asserted. 
 // The rst_flag will be clear when rst_n is de-asserted 
  wire reset_flag_r;
  gnrl_dffrs #(1) reset_flag_dffrs (1'b0, reset_flag_r, clk, rst_n);


 // The reset_req valid is set when Currently reset_flag is asserting
 // The reset_req valid is clear when Currently reset_req is asserting
 // Currently the flush can be accepted by IFU
  wire reset_req_r;
  wire reset_req_set = (~reset_req_r) & reset_flag_r;
  wire reset_req_clr = reset_req_r & ifu_req_hsked;
  wire reset_req_ena = reset_req_set | reset_req_clr;
  wire reset_req_nxt = reset_req_set | (~reset_req_clr);
  gnrl_dfflr #(1) reset_req_dfflr (reset_req_ena, reset_req_nxt, reset_req_r, clk, rst_n);
  wire ifu_reset_req = reset_req_r;

   //if-ex interface
   wire pc_hold_req = (~ifu_o_hsked) | bpu_wait;                                //handshake with exu failed or hazard
   wire [`INSTR_SIZE-1:0] ifu_ir_r;
   wire instr_nop_req = (bpu_wait & ifu_o_hsked) | pipe_flush_req;
   wire [`INSTR_SIZE-1:0] ifu_ir_nxt = instr_nop_req ? `INSTR_NOP:ifu_rsp_instr;//inject nop when current instruction is accepted by exu and bpu_wait asserted
   wire [`PC_SIZE-1:0] ifu_pc_nxt = pc_r;
   wire [`PC_SIZE-1:0] ifu_pc_r;
   wire [`RFIDX_WIDTH-1:0] ir_rs1idx_r;
   wire [`RFIDX_WIDTH-1:0] ir_rs2idx_r;
   wire ifu_prdt_taken_r;
   wire ifu_exu_ena = ifu_o_hsked;
   //ifu_pc, rs1idx, rs2idx, prdt_taken allowed to change once the instruction is accepted by exu
   gnrl_dfflr #(`PC_SIZE) ifu_pc_dfflr (ifu_exu_ena, ifu_pc_nxt,  ifu_pc_r, clk, rst_n);
   gnrl_dfflr #(`RFIDX_WIDTH) ifu_rs1idx_dfflr (ifu_exu_ena, minidec_rs1idx,  ir_rs1idx_r, clk, rst_n);
   gnrl_dfflr #(`RFIDX_WIDTH) ifu_rs2idx_dfflr (ifu_exu_ena, minidec_rs2idx,  ir_rs2idx_r, clk, rst_n);
   gnrl_dfflr #(1) ifu_prdt_taken_dfflr (ifu_exu_ena, prdt_taken, ifu_prdt_taken_r, clk, rst_n);
   gnrl_dfflr #(`INSTR_SIZE) ifu_ir_dfflr (ifu_exu_ena, ifu_ir_nxt, ifu_ir_r, clk, rst_n);
   assign ifu_o_ir  = ifu_ir_r;           //output to exu
   assign ifu_o_pc  = ifu_pc_r;           //ouput to exu
   
   // ir_nop_instr register(pipeling bubble)
   // indicating the instr in IR reg is a nop instr
   wire ir_nop_instr_set = instr_nop_req;//to check
   wire ir_nop_instr_clr = ir_nop_instr_r;
   wire ir_nop_instr_ena = ir_nop_instr_set | ir_nop_instr_clr;
   wire ir_nop_instr_nxt = ir_nop_instr_set | (~ir_nop_instr_clr);
   
   gnrl_dfflr #(1) ir_nop_instr_dfflr (ir_nop_instr_ena, ir_nop_instr_nxt, ir_nop_instr_r, clk, rst_n);

   assign ifu_o_rs1idx = ir_rs1idx_r;
   assign ifu_o_rs2idx = ir_rs2idx_r;
   assign ifu_o_prdt_taken = ifu_prdt_taken_r;
   assign ifu_o_valid  = ~reset_flag_r;

   // Next PC generation
   wire bjp_req = minidec_bjp & prdt_taken;
   wire [`PC_SIZE-1:0] pc_add_op1 = 
                                 reset_req_r ? pc_rtvec:
                                 pc_hold_req   ? pc_r :
                                 pipe_flush_req  ? pipe_flush_add_op1 :
                                 bjp_req ? prdt_pc_add_op1    :
                                                   pc_r;

   wire [`PC_SIZE-1:0] pc_add_op2 =  
                                 reset_req_r ? `PC_SIZE'b0:
                                 pc_hold_req   ? `PC_SIZE'b0 :
                                 pipe_flush_req  ? pipe_flush_add_op2 :
                                 bjp_req ? prdt_pc_add_op2    :
                                  `PC_SIZE'd4 ;

   wire [`PC_SIZE-1:0] pc_nxt_pre = pc_add_op1 + pc_add_op2;
   wire [`PC_SIZE-1:0] pc_nxt = {pc_nxt_pre[`PC_SIZE-1:2],2'b00};
   gnrl_dfflr #(`PC_SIZE) pc_dfflr (1'b1, pc_nxt, pc_r, clk, rst_n);
   assign ifu_rsp_ready = 1'b1;
   assign inspect_pc = pc_r;
   assign ifu_req_pc = pc_nxt;
   endmodule

