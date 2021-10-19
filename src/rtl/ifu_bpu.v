//=====================================================================
// Author: LI Jiarui
//
// Description:
//  Branch Prediction Unit of IFU
//  To conduct branch prediction of B/J instructions captured after ifu_minidec
//  Static Predictions only 
// ====================================================================
`include "defines.v"

module ifu_bpu(

  // Current PC of instruction
  input  [`PC_SIZE-1:0] pc,

  // The mini-decoded info 
  input  dec_jal,  
  input  dec_jalr,
  input  dec_bxx,  // Conditional branch/jump 
  input  [`XLEN-1:0] dec_bjp_imm, // immediate number operation
  input  [`RFIDX_WIDTH-1:0] dec_jalr_rs1idx,

  // The Instruction Register index and OITF status to be used for checking dependency
  // if SimpleCore actually needs OITF
  input  oitf_empty, //Oustanding Instructions Track FIFO to hold all the non-ALU long pipeline instruction's status and information
  input  ir_rs1en,
  input  jalr_rs1idx_match_irrdidx,
  
  // The add op to next-pc adder
  output bpu_wait,  
  output prdt_taken,  // predict if taken, BTFN
  output [`PC_SIZE-1:0] prdt_pc_add_op1,  
  output [`PC_SIZE-1:0] prdt_pc_add_op2,

  input  dec_i_valid,

  // The RS1 to read regfile
  input  ir_nop_instr,
  input  [`XLEN-1:0] rf2bpu_x1,
  input  [`XLEN-1:0] rf2bpu_rs1,

  input  clk,
  input  rst_n
);

  /*
  // Static branch prediction logics of BPU
  //   * JAL: The target address of JAL is calculated based on current PC value
  //          and offset, and JAL is unconditionally always jump
  //
  //   * JALR with rs1 == x0: The target address of JALR is calculated based on
  //          x0+offset, and JALR is unconditionally always jump
  //
  //   * JALR with rs1 = x1: The x1 register value is directly wired from regfile
  //          when the x1 have no dependency with ongoing instructions by checking
  //          two conditions:
  //            ** (1) The OTIF in EXU must be empty 
  //            ** (2) The instruction in IR have no x1 as destination register
  //          * If there is dependency, then hold up IFU until the dependency is cleared
  //
  //   * JALR with rs1 != x0 or x1: The target address of JALR need to be resolved
  //          at EXU stage, hence have to be forced halted, wait the EXU to be
  //          empty and then read the regfile to grab the value of xN.
  //          This will exert 1 cycle performance lost for JALR instruction
  //
  //   * Bxxx(BTFN): Conditional branch is always predicted as taken if it is backward
  //          jump, and not-taken if it is forward jump. The target address of JAL
  //          is calculated based on current PC value and offset
  */
  
  // The JAL and JALR always jump, only when bxxx backward is predicted as taken  (BTFN) 
  // when immediate number offset is negative, aka the top sign is 1, represents backward jump
  // discriminated by: dec_bjp_imm[`XLEN-1]
  assign prdt_taken   = (dec_jal | dec_jalr | (dec_bxx & dec_bjp_imm[`XLEN-1]));  

  // The JALR with rs1 == x1 have dependency or xN have dependency
  wire dec_jalr_rs1x0 = (dec_jalr_rs1idx == `RFIDX_WIDTH'd0);    //discriminate rs1 index is x0
  wire dec_jalr_rs1x1 = (dec_jalr_rs1idx == `RFIDX_WIDTH'd1);    //discriminate rs1 index is x1
  wire dec_jalr_rs1xn = (~dec_jalr_rs1x0) & (~dec_jalr_rs1x1);   //discriminate rs1 index is xn, which is any other register than x0 and x1.


  /*
  Dependency check:
     ** x1 is DEPENDENT when:
        1. OITF is NOT empty, indicates long instruction being excuted
        2. Index of target write-back register of current instruction in IR is x1, indicates ReadAfterWrite dependency  
     ** xn is DEPENDENT when:
        1. OITF is NOT empty, indicates long instruction being excuted
        2. IR is NOT empty(not nop instruction), indicates instruction in IR may be able to write back to xn. 
  */
  wire jalr_rs1x1_dep = dec_i_valid & dec_jalr & dec_jalr_rs1x1 & ((~oitf_empty) | (jalr_rs1idx_match_irrdidx));
  wire jalr_rs1xn_dep = dec_i_valid & dec_jalr & dec_jalr_rs1xn & ((~oitf_empty) | (~ir_nop_instr));

  /*
  To set when bpu needs to wait.
  1. x1 dependency exists
  2. xn dependency exists
  3. At clock period of reading xn from RegFile using ReadPort1 in RegFile, here to stop IFU from generating next PC till dependency discharged and xn is read from RegFile
  */
  assign bpu_wait = jalr_rs1x1_dep | jalr_rs1xn_dep;

  /* 
  all PC shares the same ADDER to save area 
  To get target jump address, add PC and immediate number representation of offset 
  ADDER operation 1:
  1. for bxx/jal instruction, use self PC for target jump address
  2. for jalr instruction, the base address comes from its rs1 index operation which reads from RegFile
     2.1 if rs1 index x0, use interger 0 (according to RISC-V definition)
     2.2 if rs1 index x1, wire x1 from exu_RegFile
          to avoid writing current excuting instruction in EXU back to x1 causing ReadAfterWrite Dependency, BPU needs to discriminate:
               2.2.1 current excuting instruction not writing back to x1
               2.2.2 OITF is empty
     2.3 if rs1 index xn (any register other than x0 and x1), read xn from ReadPort1 from RegFile (Discriminate ReadPort1 is available and has no conflict)
           to avoid writing current excuting instruction in EXU back to xn causing ReadAfterWrite Dependency, BPU needs to discriminate:   
               2.2.1 EXU currently has no excuting instruction
  */
  assign prdt_pc_add_op1 = (dec_bxx | dec_jal) ? pc[`PC_SIZE-1:0]                       // 1
                         : (dec_jalr & dec_jalr_rs1x0) ? `PC_SIZE'b0                    // 2.1
                         : (dec_jalr & dec_jalr_rs1x1) ? rf2bpu_x1[`PC_SIZE-1:0]        // 2.2
                         : rf2bpu_rs1[`PC_SIZE-1:0];                                    // 2.3
 
  // ADDER operation 2, represent offset by immediate number
  assign prdt_pc_add_op2 = dec_bjp_imm[`PC_SIZE-1:0];  

endmodule
