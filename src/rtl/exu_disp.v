//=================================================
//Description: EXU Dispatch module
// dispatch instructions to ALU(all instructions) and OITF(multi-cycle instructions)
//Author : Hurui
//Modules: exu_disp
//=================================================
`include "defines.v"

module exu_disp (
    input oitf_empty,
    input disp_i_valid,         //handshake valid from ifu
    output disp_i_ready,     //handshake ready to ifu
    
    // signals from decode module
    //input disp_i_rs1x0,
    //input disp_i_rs2x0,
    input disp_i_rs1en,
    input disp_i_rs2en,
    input disp_i_rdwen,
    input [`RFIDX_WIDTH-1:0] disp_i_rs1idx,
    input [`RFIDX_WIDTH-1:0] disp_i_rs2idx,
    input [`RFIDX_WIDTH-1:0] disp_i_rdidx,
    input [`XLEN-1:0] disp_i_rs1,
    input [`XLEN-1:0] disp_i_rs2,
    input [`DECINFO_WIDTH-1:0] disp_i_info,
    input [`XLEN-1:0] disp_i_imm,
    input [`PC_SIZE-1:0] disp_i_pc,
    input disp_ilegl,

    //dispatch to ALU
    output disp_o_alu_valid,
    input disp_o_alu_ready,

    input disp_o_alu_longpipe, //from ALU, indicating a multicycle instruction
    
    output [`XLEN-1:0] disp_o_alu_rs1,
    output [`XLEN-1:0] disp_o_alu_rs2,
    output disp_o_alu_rdwen,
    output [`RFIDX_WIDTH-1:0] disp_o_alu_rdidx,
    output [`DECINFO_WIDTH-1:0] disp_o_alu_info,
    output [`XLEN-1:0] disp_o_alu_imm,
    output [`PC_SIZE-1:0] disp_o_alu_pc,
    output [`ITAG_WIDTH-1:0] disp_o_alu_itag, // from OITF
    output disp_o_alu_ilegl,
    
    //dispatch to OITF
    input oitfrd_match_disprs1, // oitf raw dependent
    input oitfrd_match_disprs2, // oitf raw dependent 
    input oitfrd_match_disprd,  // oitf waw dependent
    input [`ITAG_WIDTH-1:0] disp_oitf_ptr, 

    output disp_oitf_ena,
    input disp_oitf_ready,
    
    output  disp_oitf_rs1en,
    output disp_oitf_rs2en,
    output disp_oitf_rdwen,

    output [`RFIDX_WIDTH-1:0] disp_oitf_rs1idx,
    output [`RFIDX_WIDTH-1:0] disp_oitf_rs2idx,
    output [`RFIDX_WIDTH-1:0] disp_oitf_rdidx
);

//wire [`DECINFO_GRP_WIDTH-1:0] disp_i_info_grp = disp_i_info[`DECOINFO_GRP];
//every instruction need to be dispatched to ALU
// wire disp_alu = 1;
//wire disp_alu_longp_prdt = (disp_i_info_grp == `DECINFO_GRP_AGU);//ToCheck:what about muldiv?difference between disp_alu_longp_real?
//wire disp_alu_longp_real = disp_o_alu_longpipe;//from alu(load/store and mul/div)

//dependent 
wire raw_dep = oitfrd_match_disprs1 | oitfrd_match_disprs2;
wire waw_dep = oitfrd_match_disprd;
wire dep = raw_dep | waw_dep;

wire disp_condition = (~dep)
                                    & (disp_o_alu_longpipe ? disp_oitf_ready: 1'b1);
//handshake
wire disp_i_valid_pos = disp_condition & disp_i_valid;
assign disp_i_ready = disp_condition & disp_o_alu_ready;
assign disp_o_alu_valid = disp_i_valid_pos;

//dispatch to alu
assign disp_o_alu_rs1 = disp_i_rs1;
assign disp_o_alu_rs2 = disp_i_rs2;
assign disp_o_alu_rdwen = disp_i_rdwen;
assign disp_o_alu_rdidx = disp_i_rdidx;
assign disp_o_alu_info = disp_i_info;

assign disp_oitf_ena = disp_o_alu_valid & disp_o_alu_ready & disp_o_alu_longpipe;

assign disp_o_alu_imm = disp_i_imm;
assign disp_o_alu_pc = disp_i_pc;
assign disp_o_alu_itag = disp_oitf_ptr;//from oitf
assign disp_o_alu_ilegl = disp_ilegl;

//dispatch to oitf
assign disp_oitf_rs1en = disp_i_rs1en;
assign disp_oitf_rs2en = disp_i_rs2en;
assign disp_oitf_rdwen = disp_i_rdwen;
assign disp_oitf_rs1idx = disp_i_rs1idx;
assign disp_oitf_rs2idx = disp_i_rs2idx;
assign disp_oitf_rdidx = disp_i_rdidx;
endmodule