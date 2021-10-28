/*===========================================================================
    Designer   : Wen Fu
    Reference  : Humming Bird e203
    Description:  This module to implement the AGU (address generation unit 
                  for load/store , which is mostly share the datapath with 
                  ALU module to save gatecount to mininum
=============================================================================*/

`include "defines.v"

module exu_alu_lsuagu(

  //////////////////////////////////////////////////////////////
  // The Handshake Interface to AGU 

  input  agu_i_valid,                                // Handshake valid
  output agu_i_ready,                                // Handshake ready

  input  [`XLEN-1:0] agu_i_rs1,
  input  [`XLEN-1:0] agu_i_rs2,
  input  [`XLEN-1:0] agu_i_imm,
  input  [`DECINFO_AGU_WIDTH-1:0] agu_i_info,       //8-bits
  input  [`ITAG_WIDTH-1:0] agu_i_itag,

  output agu_i_longpipe,
  //input  flush_req,

  // The AGU Write-Back/Commit Interface
  output agu_o_valid,                               // Handshake valid
  input  agu_o_ready,                               // Handshake ready
  output [`XLEN-1:0] agu_o_wbck_wdat,
  output agu_cmd_usign,
  output [1:0] agu_cmd_size,

  // The Interface to LSU-ctrl
  output                  agu_cmd_valid,            // Handshake valid
  input                   agu_cmd_ready,            // Handshake ready

  output [`DTCM_ADDR_WIDTH-1:0] agu_cmd_addr,             // Bus transaction start addr 
  output                  agu_cmd_read,             // Read or write
  output [`XLEN-1:0]      agu_cmd_wdata,
  output [`XLEN/8-1:0] agu_cmd_wmask,
  output [`ITAG_WIDTH-1:0]agu_cmd_itag,

  //  Bus RSP channel
  input                        agu_rsp_valid,       // Response valid 
  output                       agu_rsp_ready,       // Response ready

  //////////////////////////////////////////////////////////////
  //  AGU must be shared with ALU.
  output [`XLEN-1:0] agu_req_alu_op1,
  output [`XLEN-1:0] agu_req_alu_op2,
  output agu_req_alu_swap,
  output agu_req_alu_add ,
  output agu_req_alu_and ,
  output agu_req_alu_or  ,
  output agu_req_alu_xor ,
  output agu_req_alu_max ,
  output agu_req_alu_min ,
  output agu_req_alu_maxu,
  output agu_req_alu_minu,
  input  [`XLEN-1:0] agu_req_alu_res,

  // The Shared-Buffer interface to ALU-Shared-Buffer
  output agu_sbf_0_ena,
  output [`XLEN-1:0] agu_sbf_0_nxt,
  input  [`XLEN-1:0] agu_sbf_0_r,

  output agu_sbf_1_ena,
  output [`XLEN-1:0] agu_sbf_1_nxt,
  input  [`XLEN-1:0] agu_sbf_1_r,

  input  clk,
  input  rst_n
  );

  // When there is a nonalu_flush which is going to flush the ALU, then we need to mask off it
  wire       sta_is_idle;                           //two stage in total, so set 1-bit
  //wire       flush_block = flush_req & sta_is_idle; 

  //wire       agu_i_load    = agu_i_info [`DECINFO_AGU_LOAD   ] & (~flush_block);
  //wire       agu_i_store   = agu_i_info [`DECINFO_AGU_STORE  ] & (~flush_block);
wire       agu_i_load    = agu_i_info [`DECINFO_AGU_LOAD   ];
wire       agu_i_store   = agu_i_info [`DECINFO_AGU_STORE  ];
  wire [1:0] agu_i_size    = agu_i_info [`DECINFO_AGU_SIZE   ];
  wire       agu_i_usign   = agu_i_info [`DECINFO_AGU_USIGN  ];

  wire agu_i_size_b  = (agu_i_size == 2'b00);
  wire agu_i_size_hw = (agu_i_size == 2'b01);
  wire agu_i_size_w  = (agu_i_size == 2'b10);

  wire state_last_exit_ena;
 
  localparam STATE_WIDTH = 1;

  wire state_ena;
  wire [STATE_WIDTH-1:0] state_nxt;
  wire [STATE_WIDTH-1:0] state_r;

  // State 0: The idle state, means there is no any oustanding ifetch request
  localparam STATE_IDLE = 1'd0;

  // Define some common signals and reused later to save gatecounts
  assign sta_is_idle    = (state_r == STATE_IDLE);
   
  // The state will only toggle when each state is meeting the condition to exit:
  assign state_ena = 1'b0;

  // The next-state is onehot mux to select different entries
  assign state_nxt =({STATE_WIDTH{1'b0}});

  gnrl_dfflr #(STATE_WIDTH) state_dfflr (state_ena, state_nxt, state_r, clk, rst_n);
 
  wire  sta_is_last = 1'b0; 
  assign state_last_exit_ena = 1'b0;
 
  /////////////////////////////////////////////////////////////////////////////////
  // Implement the leftover 0 buffer
  wire leftover_ena;
  wire [`XLEN-1:0] leftover_nxt;
  wire [`XLEN-1:0] leftover_r;
  wire leftover_err_nxt;
  wire leftover_err_r;

  wire [`XLEN-1:0] leftover_1_r;
  wire leftover_1_ena;
  wire [`XLEN-1:0] leftover_1_nxt;
  /*leftover buffer
  assign leftover_ena = agu_rsp_hsked & (1'b0);
  assign leftover_nxt = {`XLEN{1'b0}};                                 
  assign leftover_err_nxt = 1'b0 ;
 
  // The instantiation of leftover buffer is actually shared with the ALU SBF-0 Buffer
  assign agu_sbf_0_ena = leftover_ena;
  assign agu_sbf_0_nxt = leftover_nxt;
  assign leftover_r    = agu_sbf_0_r;

  // The error bit is implemented here
  gnrl_dfflr #(1) leftover_err_dfflr (leftover_ena, leftover_err_nxt, leftover_err_r, clk, rst_n);
  
  assign leftover_1_ena = 1'b0 ;
  assign leftover_1_nxt = agu_req_alu_res;
  //
  // The instantiation of last_addr buffer is actually shared with the ALU SBF-1 Buffer
  assign agu_sbf_1_ena   = leftover_1_ena;
  assign agu_sbf_1_nxt   = leftover_1_nxt;
  assign leftover_1_r = agu_sbf_1_r;
*/

  assign agu_req_alu_add  = 1'b0 | sta_is_idle;
  assign agu_req_alu_op1 =  sta_is_idle ? agu_i_rs1: `XLEN'd0 ;

  wire [`XLEN-1:0] agu_addr_gen_op2 = agu_i_imm;
  assign agu_req_alu_op2 =  sta_is_idle   ? agu_addr_gen_op2 : `XLEN'd0 ;

  assign agu_req_alu_swap = 1'b0;
  assign agu_req_alu_and  = 1'b0;
  assign agu_req_alu_or   = 1'b0;
  assign agu_req_alu_xor  = 1'b0;
  assign agu_req_alu_max  = 1'b0;
  assign agu_req_alu_min  = 1'b0;
  assign agu_req_alu_maxu = 1'b0;
  assign agu_req_alu_minu = 1'b0;


/////////////////////////////////////////////////////////////////////////////////
// Implement the AGU op handshake ready signal
  assign agu_i_ready =( 1'b0) ? state_last_exit_ena : (agu_cmd_ready & agu_o_ready) ;
  
  // The aligned load/store instruction will be dispatched to LSU as long pipeline  instructions
  assign agu_i_longpipe = agu_i_load | agu_i_store;
  
  /////////////////////////////////////////////////////////////////////////////////
  // Implement the Write-back interfaces (unaligned and AMO instructions) 

  assign agu_o_valid =   agu_i_valid & agu_cmd_ready;
  assign agu_o_wbck_wdat = {`XLEN{1'b0 }};

  assign agu_rsp_ready = 1'b1;
  
  assign agu_cmd_valid = agu_i_valid & agu_o_ready ;
  assign agu_cmd_addr = agu_req_alu_res[`DTCM_ADDR_WIDTH-1:0];

  assign agu_cmd_read = agu_i_load;
     // The AGU CMD Wdata sources:

  wire [`XLEN-1:0] algnst_wdata   = 
                                    ({`XLEN{agu_i_size_b }} & {4{agu_i_rs2[ 7:0]}})
                                  | ({`XLEN{agu_i_size_hw}} & {2{agu_i_rs2[15:0]}})
                                  | ({`XLEN{agu_i_size_w }} & {1{agu_i_rs2[31:0]}});
  assign agu_cmd_wmask =          ({`XLEN/8{agu_i_size_b }} & (4'b0001 <<  {agu_cmd_addr[1],1'b0}))
          | ({`XLEN/8{agu_i_size_hw}} & (4'b0011 << {agu_cmd_addr[1],1'b0}))
          | ({`XLEN/8{agu_i_size_w }} & (4'b1111));
       
  assign agu_cmd_wdata = algnst_wdata;
  //assign agu_cmd_back2agu = 1'b0 ;
           
  assign agu_cmd_itag     = agu_i_itag;
  assign agu_cmd_usign    = agu_i_usign;
  assign agu_cmd_size     = agu_i_size;
endmodule       