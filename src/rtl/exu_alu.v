/*===========================================================================
    Designer   : Wen Fu
    Reference  : Humming Bird     
    Description: It's the top module of ALU. This module implement the compute function unit
                 and the AGU (address generate unit) for LSU is also handled by ALU
                 additionaly, the shared-impelmentation of MUL and DIV instruction 
                 is also shared by ALU in E200
                 AGU : address generate unit for load/store instrctions
=============================================================================*/


`include "defines.v"

module exu_alu(

  //////////////////////////////////////////////////////////////
  // The operands and decode info from dispatch
  //////////////////////////////////////////////////////////////
  input  i_valid, 
  output i_ready, 

  output i_longpipe,                                // Indicate this instruction is issued as a long pipe instruction
                     
  input  [`ITAG_WIDTH-1:0] i_itag,
  input  [`XLEN-1:0] i_rs1,
  input  [`XLEN-1:0] i_rs2,
  input  [`XLEN-1:0] i_imm,
  input  [`DECINFO_WIDTH-1:0]  i_info,  
  input  [`PC_SIZE-1:0] i_pc,
  //input  [`INSTR_SIZE-1:0] i_instr,
  input  i_pc_vld,
  input  [`RFIDX_WIDTH-1:0] i_rdidx,
  input  i_rdwen,
  input  i_ilegl,



  //////////////////////////////////////////////////////////////
  //////////////////////////////////////////////////////////////
  // The Commit Interface
  output cmt_o_valid,                               // Handshake valid
  input  cmt_o_ready,                               // Handshake ready
  output cmt_o_pc_vld,  
  output [`PC_SIZE-1:0] cmt_o_pc,  
  //output [`INSTR_SIZE-1:0] cmt_o_instr,  
  output [`XLEN-1:0]    cmt_o_imm,                 // The resolved ture/false
    //   The Branch and Jump Commit
  //output cmt_o_rv32,                               // The predicted ture/false  
  output cmt_o_bjp,
  output cmt_o_ifu_misalgn,
  output cmt_o_ifu_ilegl,
  output cmt_o_bjp_prdt,                            // The predicted ture/false  
  output cmt_o_bjp_rslv,                            // The resolved ture/false
    //   The AGU Exception 

  //////////////////////////////////////////////////////////////
  // The ALU Write-Back Interface
  //////////////////////////////////////////////////////////////
  output wbck_o_valid,                              // Handshake valid
  input  wbck_o_ready,                              // Handshake ready
  output [`XLEN-1:0] wbck_o_wdat,
  output [`RFIDX_WIDTH-1:0] wbck_o_rdidx,
  input  mdv_nob2b,


  //////////////////////////////////////////////////////////////
  //////////////////////////////////////////////////////////////
  // The AGU ICB Interface to LSU-ctrl
  //    * Bus cmd channel
  output                         agu_cmd_valid,     // Handshake valid
  input                          agu_cmd_ready,    // Handshake ready
  output [`DTCM_ADDR_WIDTH-1:0]        agu_cmd_addr,           // Bus transaction start addr 
  output                         agu_cmd_read,      // Read or write
  output [`XLEN-1:0]             agu_cmd_wdata, 
  output [`XLEN/8-1:0] agu_cmd_wmask,
  output [1:0]                   agu_cmd_size,
  output                          agu_cmd_usign,
  //output                         agu_cmd_back2agu, 
  output [`ITAG_WIDTH -1:0]       agu_cmd_itag,
  //    * Bus RSP channel
  input                          agu_rsp_valid,     // Response valid 
  output                         agu_rsp_ready,     // Response ready
  // input  [`XLEN-1:0]             agu_rsp_rdata,

  input  clk,
  input  rst_n
  );

  //////////////////////////////////////////////////////////////
  // Dispatch to different sub-modules according to their types

  wire ifu_excp_op = i_ilegl;
  wire alu_op = (~ifu_excp_op) & (i_info[`DECINFO_GRP] == `DECINFO_GRP_ALU); 
  wire agu_op = (~ifu_excp_op) & (i_info[`DECINFO_GRP] == `DECINFO_GRP_AGU); 
  wire bjp_op = (~ifu_excp_op) & (i_info[`DECINFO_GRP] == `DECINFO_GRP_BJP); 

  wire mdv_op = (~ifu_excp_op) & (i_info[`DECINFO_GRP] == `DECINFO_GRP_MULDIV); 


  // The ALU incoming instruction may go to several different targets:
  //   * The ALUDATAPATH if it is a regular ALU instructions
  //   * The Branch-cmp if it is a BJP instructions
  //   * The AGU if it is a load/store relevant instructions
  //   * The MULDIV if it is a MUL/DIV relevant instructions and MULDIV
  //       is reusing the ALU adder

  wire mdv_i_valid = i_valid & mdv_op;
  wire agu_i_valid = i_valid & agu_op;
  wire alu_i_valid = i_valid & alu_op;
  wire bjp_i_valid = i_valid & bjp_op;
  wire ifu_excp_i_valid = i_valid & ifu_excp_op;

  wire mdv_i_ready;
  wire agu_i_ready;
  wire alu_i_ready;
  wire bjp_i_ready;
  wire ifu_excp_i_ready;

  assign i_ready =   (agu_i_ready & agu_op)
                   | (mdv_i_ready & mdv_op)
                   | (alu_i_ready & alu_op)
                   | (ifu_excp_i_ready & ifu_excp_op)
                   | (bjp_i_ready & bjp_op)
                     ;

  wire agu_i_longpipe;
 // wire mdv_i_longpipe;


  assign i_longpipe = (agu_i_longpipe & agu_op)    
                   // | (mdv_i_longpipe & mdv_op) 
                   ;

  
  //////////////////////////////////////////////////////////////
  // Instantiate the BJP module
  //
  wire bjp_o_valid; 
  wire bjp_o_ready; 
  wire [`XLEN-1:0] bjp_o_wbck_wdat;
  wire bjp_o_wbck_err;
  wire bjp_o_cmt_bjp;
  wire bjp_o_cmt_prdt;
  wire bjp_o_cmt_rslv;

  wire [`XLEN-1:0] bjp_req_alu_op1;
  wire [`XLEN-1:0] bjp_req_alu_op2;
  wire bjp_req_alu_cmp_eq ;
  wire bjp_req_alu_cmp_ne ;
  wire bjp_req_alu_cmp_lt ;
  wire bjp_req_alu_cmp_ge ;
  wire bjp_req_alu_cmp_ltu;
  wire bjp_req_alu_cmp_geu;
  wire bjp_req_alu_add;
  wire bjp_req_alu_cmp_res;
  wire [`XLEN-1:0] bjp_req_alu_add_res;

  wire  [`XLEN-1:0]           bjp_i_rs1  = {`XLEN         {bjp_op}} & i_rs1;
  wire  [`XLEN-1:0]           bjp_i_rs2  = {`XLEN         {bjp_op}} & i_rs2;
  wire  [`XLEN-1:0]           bjp_i_imm  = {`XLEN         {bjp_op}} & i_imm;
  wire  [`DECINFO_WIDTH-1:0]  bjp_i_info = {`DECINFO_WIDTH{bjp_op}} & i_info;  
  wire  [`PC_SIZE-1:0]        bjp_i_pc   = {`PC_SIZE      {bjp_op}} & i_pc;  

  exu_alu_bjp u_exu_alu_bjp(
      .bjp_i_valid         (bjp_i_valid         ),
      .bjp_i_ready         (bjp_i_ready         ),
      .bjp_i_rs1           (bjp_i_rs1           ),
      .bjp_i_rs2           (bjp_i_rs2           ),
      .bjp_i_info          (bjp_i_info[`DECINFO_BJP_WIDTH-1:0]),
      .bjp_i_imm           (bjp_i_imm           ),
      .bjp_i_pc            (bjp_i_pc            ),

      .bjp_o_valid         (bjp_o_valid      ),
      .bjp_o_ready         (bjp_o_ready      ),
      .bjp_o_wbck_wdat     (bjp_o_wbck_wdat  ),
      .bjp_o_wbck_err      (bjp_o_wbck_err   ),

      .bjp_o_cmt_bjp       (bjp_o_cmt_bjp    ),
      .bjp_o_cmt_prdt      (bjp_o_cmt_prdt   ),
      .bjp_o_cmt_rslv      (bjp_o_cmt_rslv   ),

      .bjp_req_alu_op1     (bjp_req_alu_op1       ),
      .bjp_req_alu_op2     (bjp_req_alu_op2       ),
      .bjp_req_alu_cmp_eq  (bjp_req_alu_cmp_eq    ),
      .bjp_req_alu_cmp_ne  (bjp_req_alu_cmp_ne    ),
      .bjp_req_alu_cmp_lt  (bjp_req_alu_cmp_lt    ),
      .bjp_req_alu_cmp_ge  (bjp_req_alu_cmp_ge    ),
      .bjp_req_alu_cmp_ltu (bjp_req_alu_cmp_ltu   ),
      .bjp_req_alu_cmp_geu (bjp_req_alu_cmp_geu   ),
      .bjp_req_alu_add     (bjp_req_alu_add       ),
      .bjp_req_alu_cmp_res (bjp_req_alu_cmp_res   ),
      .bjp_req_alu_add_res (bjp_req_alu_add_res   ),

      .clk                 (clk),
      .rst_n               (rst_n)
  );



  
  //////////////////////////////////////////////////////////////
  // Instantiate the AGU module
  //
  wire agu_o_valid; 
  wire agu_o_ready; 
  
  wire [`XLEN-1:0] agu_o_wbck_wdat;
  wire agu_o_wbck_err;   
  
  
  wire [`XLEN-1:0] agu_req_alu_op1;
  wire [`XLEN-1:0] agu_req_alu_op2;
  wire agu_req_alu_swap;
  wire agu_req_alu_add ;
  wire agu_req_alu_and ;
  wire agu_req_alu_or  ;
  wire agu_req_alu_xor ;
  wire agu_req_alu_max ;
  wire agu_req_alu_min ;
  wire agu_req_alu_maxu;
  wire agu_req_alu_minu;
  wire [`XLEN-1:0] agu_req_alu_res;
     
  wire agu_sbf_0_ena;
  wire [`XLEN-1:0] agu_sbf_0_nxt;
  wire [`XLEN-1:0] agu_sbf_0_r;
  wire agu_sbf_1_ena;
  wire [`XLEN-1:0] agu_sbf_1_nxt;
  wire [`XLEN-1:0] agu_sbf_1_r;

  wire  [`XLEN-1:0]           agu_i_rs1  = {`XLEN         {agu_op}} & i_rs1;
  wire  [`XLEN-1:0]           agu_i_rs2  = {`XLEN         {agu_op}} & i_rs2;
  wire  [`XLEN-1:0]           agu_i_imm  = {`XLEN         {agu_op}} & i_imm;
  wire  [`DECINFO_WIDTH-1:0]  agu_i_info = {`DECINFO_WIDTH{agu_op}} & i_info;  
  wire  [`ITAG_WIDTH-1:0]     agu_i_itag = {`ITAG_WIDTH   {agu_op}} & i_itag;  


  exu_alu_lsuagu u_exu_alu_lsuagu(

      .agu_i_valid         (agu_i_valid     ),
      .agu_i_ready         (agu_i_ready     ),
      .agu_i_rs1           (agu_i_rs1       ),
      .agu_i_rs2           (agu_i_rs2       ),
      .agu_i_imm           (agu_i_imm       ),
      .agu_i_info          (agu_i_info[`DECINFO_AGU_WIDTH-1:0]),
      .agu_i_longpipe      (agu_i_longpipe  ),
      .agu_i_itag          (agu_i_itag      ),

      //.flush_req           (flush_req      ),

      .agu_o_valid         (agu_o_valid         ),
      .agu_o_ready         (agu_o_ready         ),
      .agu_o_wbck_wdat     (agu_o_wbck_wdat     ),
      
      .agu_cmd_valid   (agu_cmd_valid   ),
      .agu_cmd_ready   (agu_cmd_ready   ),
      .agu_cmd_addr    (agu_cmd_addr    ),
      .agu_cmd_read    (agu_cmd_read    ),
      .agu_cmd_wdata   (agu_cmd_wdata   ),
      .agu_cmd_wmask (agu_cmd_wmask),
      .agu_cmd_size    (agu_cmd_size    ),
      //.agu_cmd_back2agu(agu_cmd_back2agu),
      .agu_cmd_usign   (agu_cmd_usign   ),
      .agu_cmd_itag    (agu_cmd_itag    ),
      .agu_rsp_valid   (agu_rsp_valid   ),
      .agu_rsp_ready   (agu_rsp_ready   ),
      //.agu_rsp_err     (agu_rsp_err     ),
      //.agu_rsp_rdata   (agu_rsp_rdata   ),
                                                
      .agu_req_alu_op1     (agu_req_alu_op1     ),
      .agu_req_alu_op2     (agu_req_alu_op2     ),
      .agu_req_alu_swap    (agu_req_alu_swap    ),
      .agu_req_alu_add     (agu_req_alu_add     ),
      .agu_req_alu_and     (agu_req_alu_and     ),
      .agu_req_alu_or      (agu_req_alu_or      ),
      .agu_req_alu_xor     (agu_req_alu_xor     ),
      .agu_req_alu_max     (agu_req_alu_max     ),
      .agu_req_alu_min     (agu_req_alu_min     ),
      .agu_req_alu_maxu    (agu_req_alu_maxu    ),
      .agu_req_alu_minu    (agu_req_alu_minu    ),
      .agu_req_alu_res     (agu_req_alu_res     ),
                                                
      .agu_sbf_0_ena       (agu_sbf_0_ena       ),
      .agu_sbf_0_nxt       (agu_sbf_0_nxt       ),
      .agu_sbf_0_r         (agu_sbf_0_r         ),
                                                
      .agu_sbf_1_ena       (agu_sbf_1_ena       ),
      .agu_sbf_1_nxt       (agu_sbf_1_nxt       ),
      .agu_sbf_1_r         (agu_sbf_1_r         ),
     
      .clk                 (clk),
      .rst_n               (rst_n)
  );

  //////////////////////////////////////////////////////////////
  // Instantiate the regular ALU module
  //
  wire alu_o_valid; 
  wire alu_o_ready; 
  wire [`XLEN-1:0] alu_o_wbck_wdat;
  wire alu_o_wbck_err;   


  wire alu_req_alu_add ;
  wire alu_req_alu_sub ;
  wire alu_req_alu_xor ;
  wire alu_req_alu_sll ;
  wire alu_req_alu_srl ;
  wire alu_req_alu_sra ;
  wire alu_req_alu_or  ;
  wire alu_req_alu_and ;
  wire alu_req_alu_slt ;
  wire alu_req_alu_sltu;
  wire alu_req_alu_lui ;
  wire [`XLEN-1:0] alu_req_alu_op1;
  wire [`XLEN-1:0] alu_req_alu_op2;
  wire [`XLEN-1:0] alu_req_alu_res;

  wire  [`XLEN-1:0]           alu_i_rs1  = {`XLEN         {alu_op}} & i_rs1;
  wire  [`XLEN-1:0]           alu_i_rs2  = {`XLEN         {alu_op}} & i_rs2;
  wire  [`XLEN-1:0]           alu_i_imm  = {`XLEN         {alu_op}} & i_imm;
  wire  [`DECINFO_WIDTH-1:0]  alu_i_info = {`DECINFO_WIDTH{alu_op}} & i_info;  
  wire  [`PC_SIZE-1:0]        alu_i_pc   = {`PC_SIZE      {alu_op}} & i_pc;  

  exu_alu_rglr u_exu_alu_rglr(

      .alu_i_valid         (alu_i_valid     ),
      .alu_i_ready         (alu_i_ready     ),
      .alu_i_rs1           (alu_i_rs1           ),
      .alu_i_rs2           (alu_i_rs2           ),
      .alu_i_info          (alu_i_info[`DECINFO_ALU_WIDTH-1:0]),
      .alu_i_imm           (alu_i_imm           ),
      .alu_i_pc            (alu_i_pc            ),

      .alu_o_valid         (alu_o_valid         ),
      .alu_o_ready         (alu_o_ready         ),
      .alu_o_wbck_wdat     (alu_o_wbck_wdat     ),
   
      .alu_req_alu_add     (alu_req_alu_add       ),
      .alu_req_alu_sub     (alu_req_alu_sub       ),
      .alu_req_alu_xor     (alu_req_alu_xor       ),
      .alu_req_alu_sll     (alu_req_alu_sll       ),
      .alu_req_alu_srl     (alu_req_alu_srl       ),
      .alu_req_alu_sra     (alu_req_alu_sra       ),
      .alu_req_alu_or      (alu_req_alu_or        ),
      .alu_req_alu_and     (alu_req_alu_and       ),
      .alu_req_alu_slt     (alu_req_alu_slt       ),
      .alu_req_alu_sltu    (alu_req_alu_sltu      ),
      .alu_req_alu_lui     (alu_req_alu_lui       ),
      .alu_req_alu_op1     (alu_req_alu_op1       ),
      .alu_req_alu_op2     (alu_req_alu_op2       ),
      .alu_req_alu_res     (alu_req_alu_res       ),

      .clk                 (clk           ),
      .rst_n               (rst_n         ) 
  );
  // Instantiate the MULDIV module
  wire [`XLEN-1:0]           mdv_i_rs1  = {`XLEN         {mdv_op}} & i_rs1;
  wire [`XLEN-1:0]           mdv_i_rs2  = {`XLEN         {mdv_op}} & i_rs2;
  wire [`XLEN-1:0]           mdv_i_imm  = {`XLEN         {mdv_op}} & i_imm;
  wire [`DECINFO_WIDTH-1:0]  mdv_i_info = {`DECINFO_WIDTH{mdv_op}} & i_info;  
  wire  [`ITAG_WIDTH-1:0]    mdv_i_itag = {`ITAG_WIDTH   {mdv_op}} & i_itag;  

  wire mdv_o_valid; 
  wire mdv_o_ready;
  wire [`XLEN-1:0] mdv_o_wbck_wdat;
  wire mdv_o_wbck_err;

  wire [`ALU_ADDER_WIDTH-1:0] muldiv_req_alu_op1;
  wire [`ALU_ADDER_WIDTH-1:0] muldiv_req_alu_op2;
  wire                             muldiv_req_alu_add ;
  wire                             muldiv_req_alu_sub ;
  wire [`ALU_ADDER_WIDTH-1:0] muldiv_req_alu_res;

  wire          muldiv_sbf_0_ena;
  wire [33-1:0] muldiv_sbf_0_nxt;
  wire [33-1:0] muldiv_sbf_0_r;

  wire          muldiv_sbf_1_ena;
  wire [33-1:0] muldiv_sbf_1_nxt;
  wire [33-1:0] muldiv_sbf_1_r;
/*
  exu_alu_muldiv u_exu_alu_muldiv(
      .mdv_nob2b           (mdv_nob2b),

      .muldiv_i_valid      (mdv_i_valid    ),
      .muldiv_i_ready      (mdv_i_ready    ),
                           
      .muldiv_i_rs1        (mdv_i_rs1      ),
      .muldiv_i_rs2        (mdv_i_rs2      ),
      .muldiv_i_imm        (mdv_i_imm      ),
      .muldiv_i_info       (mdv_i_info[`DECINFO_MULDIV_WIDTH-1:0]),
      .muldiv_i_longpipe   (mdv_i_longpipe ),
      .muldiv_i_itag       (mdv_i_itag     ),
                          

      .flush_pulse         (flush_pulse    ),

      .muldiv_o_valid      (mdv_o_valid    ),
      .muldiv_o_ready      (mdv_o_ready    ),
      .muldiv_o_wbck_wdat  (mdv_o_wbck_wdat),
      .muldiv_o_wbck_err   (mdv_o_wbck_err ),

      .muldiv_req_alu_op1  (muldiv_req_alu_op1),
      .muldiv_req_alu_op2  (muldiv_req_alu_op2),
      .muldiv_req_alu_add  (muldiv_req_alu_add),
      .muldiv_req_alu_sub  (muldiv_req_alu_sub),
      .muldiv_req_alu_res  (muldiv_req_alu_res),
      
      .muldiv_sbf_0_ena    (muldiv_sbf_0_ena  ),
      .muldiv_sbf_0_nxt    (muldiv_sbf_0_nxt  ),
      .muldiv_sbf_0_r      (muldiv_sbf_0_r    ),
     
      .muldiv_sbf_1_ena    (muldiv_sbf_1_ena  ),
      .muldiv_sbf_1_nxt    (muldiv_sbf_1_nxt  ),
      .muldiv_sbf_1_r      (muldiv_sbf_1_r    ),

      .clk                 (clk               ),
      .rst_n               (rst_n             ) 
  );
*/




  //////////////////////////////////////////////////////////////
  // Instantiate the Shared Datapath module
  //
  wire alu_req_alu = alu_op & i_rdwen;// Regular ALU only req datapath when it need to write-back
  wire muldiv_req_alu = mdv_op;// Since MULDIV have no point to let rd=0, so always need ALU datapath
  wire bjp_req_alu = bjp_op;// Since BJP may not write-back, but still need ALU datapath
  wire agu_req_alu = agu_op;// Since AGU may have some other features, so always need ALU datapath

  exu_alu_dpath u_exu_alu_dpath(
      .alu_req_alu         (alu_req_alu           ),    
      .alu_req_alu_add     (alu_req_alu_add       ),
      .alu_req_alu_sub     (alu_req_alu_sub       ),
      .alu_req_alu_xor     (alu_req_alu_xor       ),
      .alu_req_alu_sll     (alu_req_alu_sll       ),
      .alu_req_alu_srl     (alu_req_alu_srl       ),
      .alu_req_alu_sra     (alu_req_alu_sra       ),
      .alu_req_alu_or      (alu_req_alu_or        ),
      .alu_req_alu_and     (alu_req_alu_and       ),
      .alu_req_alu_slt     (alu_req_alu_slt       ),
      .alu_req_alu_sltu    (alu_req_alu_sltu      ),
      .alu_req_alu_lui     (alu_req_alu_lui       ),
      .alu_req_alu_op1     (alu_req_alu_op1       ),
      .alu_req_alu_op2     (alu_req_alu_op2       ),
      .alu_req_alu_res     (alu_req_alu_res       ),
           
      .bjp_req_alu         (bjp_req_alu           ),
      .bjp_req_alu_op1     (bjp_req_alu_op1       ),
      .bjp_req_alu_op2     (bjp_req_alu_op2       ),
      .bjp_req_alu_cmp_eq  (bjp_req_alu_cmp_eq    ),
      .bjp_req_alu_cmp_ne  (bjp_req_alu_cmp_ne    ),
      .bjp_req_alu_cmp_lt  (bjp_req_alu_cmp_lt    ),
      .bjp_req_alu_cmp_ge  (bjp_req_alu_cmp_ge    ),
      .bjp_req_alu_cmp_ltu (bjp_req_alu_cmp_ltu   ),
      .bjp_req_alu_cmp_geu (bjp_req_alu_cmp_geu   ),
      .bjp_req_alu_add     (bjp_req_alu_add       ),
      .bjp_req_alu_cmp_res (bjp_req_alu_cmp_res   ),
      .bjp_req_alu_add_res (bjp_req_alu_add_res   ),
             
      .agu_req_alu         (agu_req_alu           ),
      .agu_req_alu_op1     (agu_req_alu_op1       ),
      .agu_req_alu_op2     (agu_req_alu_op2       ),
      .agu_req_alu_swap    (agu_req_alu_swap      ),
      .agu_req_alu_add     (agu_req_alu_add       ),
      .agu_req_alu_and     (agu_req_alu_and       ),
      .agu_req_alu_or      (agu_req_alu_or        ),
      .agu_req_alu_xor     (agu_req_alu_xor       ),
      .agu_req_alu_max     (agu_req_alu_max       ),
      .agu_req_alu_min     (agu_req_alu_min       ),
      .agu_req_alu_maxu    (agu_req_alu_maxu      ),
      .agu_req_alu_minu    (agu_req_alu_minu      ),
      .agu_req_alu_res     (agu_req_alu_res       ),
             
      .agu_sbf_0_ena       (agu_sbf_0_ena         ),
      .agu_sbf_0_nxt       (agu_sbf_0_nxt         ),
      .agu_sbf_0_r         (agu_sbf_0_r           ),
            
      .agu_sbf_1_ena       (agu_sbf_1_ena         ),
      .agu_sbf_1_nxt       (agu_sbf_1_nxt         ),
      .agu_sbf_1_r         (agu_sbf_1_r           ),      


      .muldiv_req_alu      (muldiv_req_alu    ),

      .muldiv_req_alu_op1  (muldiv_req_alu_op1),
      .muldiv_req_alu_op2  (muldiv_req_alu_op2),
      .muldiv_req_alu_add  (muldiv_req_alu_add),
      .muldiv_req_alu_sub  (muldiv_req_alu_sub),
      .muldiv_req_alu_res  (muldiv_req_alu_res),
      
      .muldiv_sbf_0_ena    (muldiv_sbf_0_ena  ),
      .muldiv_sbf_0_nxt    (muldiv_sbf_0_nxt  ),
      .muldiv_sbf_0_r      (muldiv_sbf_0_r    ),
     
      .muldiv_sbf_1_ena    (muldiv_sbf_1_ena  ),
      .muldiv_sbf_1_nxt    (muldiv_sbf_1_nxt  ),
      .muldiv_sbf_1_r      (muldiv_sbf_1_r    ),


      .clk                 (clk           ),
      .rst_n               (rst_n         ) 
    );

  wire ifu_excp_o_valid;
  wire ifu_excp_o_ready;
  wire [`XLEN-1:0] ifu_excp_o_wbck_wdat;
  wire ifu_excp_o_wbck_err;

  assign ifu_excp_i_ready = ifu_excp_o_ready;
  assign ifu_excp_o_valid = ifu_excp_i_valid;
  assign ifu_excp_o_wbck_wdat = `XLEN'b0;
  assign ifu_excp_o_wbck_err  = 1'b1;// IFU illegal instruction always treat as error

  //////////////////////////////////////////////////////////////
  // Aribtrate the Result and generate output interfaces
  // 
  wire o_valid;
  wire o_ready;

  wire o_sel_ifu_excp = ifu_excp_op;
  wire o_sel_alu = alu_op;
  wire o_sel_bjp = bjp_op;

  wire o_sel_agu = agu_op;

  wire o_sel_mdv = mdv_op;


  assign o_valid =     (o_sel_alu      & alu_o_valid     )
                     | (o_sel_bjp      & bjp_o_valid     )
                     | (o_sel_agu      & agu_o_valid     )
                     | (o_sel_ifu_excp & ifu_excp_o_valid)
                     | (o_sel_mdv      & mdv_o_valid     )
                     ;

  assign ifu_excp_o_ready = o_sel_ifu_excp & o_ready;
  assign alu_o_ready      = o_sel_alu & o_ready;
  assign agu_o_ready      = o_sel_agu & o_ready;
  assign mdv_o_ready      = o_sel_mdv & o_ready;

  assign bjp_o_ready      = o_sel_bjp & o_ready;

  assign wbck_o_wdat = 
                    ({`XLEN{o_sel_alu}} & alu_o_wbck_wdat)
                  | ({`XLEN{o_sel_bjp}} & bjp_o_wbck_wdat)
                  | ({`XLEN{o_sel_agu}} & agu_o_wbck_wdat)
                  | ({`XLEN{o_sel_mdv}} & mdv_o_wbck_wdat)
                  | ({`XLEN{o_sel_ifu_excp}} & ifu_excp_o_wbck_wdat)
                  ;

  assign wbck_o_rdidx = i_rdidx; 
  wire wbck_o_rdwen = i_rdwen;                  

  //  Each Instruction need to commit or write-back
  //   * The write-back only needed when the unit need to write-back
  //     the result (need to write RD), and it is not a long-pipe uop
  //     (need to be write back by its long-pipe write-back, not here)
  //   * Each instruction need to be commited 
  wire o_need_wbck = wbck_o_rdwen & (~i_longpipe);
  wire o_need_cmt  = 1'b1;
  assign o_ready = 
           (o_need_cmt  ? cmt_o_ready  : 1'b1)  
         & (o_need_wbck ? wbck_o_ready : 1'b1); 

  assign wbck_o_valid = o_need_wbck & o_valid & (o_need_cmt  ? cmt_o_ready  : 1'b1);
  assign cmt_o_valid  = o_need_cmt  & o_valid & (o_need_wbck ? wbck_o_ready : 1'b1);
  // 
  //  The commint interface have some special signals
  //assign cmt_o_instr   = i_instr;  
  assign cmt_o_pc   = i_pc;  
  assign cmt_o_imm  = i_imm;
  //assign cmt_o_rv32 = i_info[`DECINFO_RV32]; 
    // The cmt_o_pc_vld is used by the commit stage to check
    // if current instruction is outputing a valid current PC
    //   to guarante the commit to flush pipeline safely, this
    //   vld only be asserted when:
    //     * There is a valid instruction here
    //        --- otherwise, the commit stage may use wrong PC
    //             value to stored in DPC or EPC
  assign cmt_o_pc_vld      = i_pc_vld;

  assign cmt_o_bjp         = o_sel_bjp & bjp_o_cmt_bjp;
  assign cmt_o_bjp_prdt    = o_sel_bjp & bjp_o_cmt_prdt;
  assign cmt_o_bjp_rslv    = o_sel_bjp & bjp_o_cmt_rslv;
  assign cmt_o_ifu_ilegl   = i_ilegl;

endmodule                                      
                                               
                                               
                                               
