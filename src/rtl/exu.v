//=================================================
//Description: exu top
//Author : Hurui
//Modules: decode + disp + alu + commit + oitf + longp + wbck + regfile
//=================================================
`include "defines.v"

module exu (
    //output exu_active,
    //IFU IR stage to EXU interface
    input i_valid,
    output i_ready,
    input [`INSTR_SIZE-1:0] i_ir,
    input [`PC_SIZE-1:0] i_pc,
    //input i_pc_vld,
    input i_prdt_taken, 
    //input i_muldiv_b2b,
    input [`RFIDX_WIDTH-1:0] i_rs1idx, //from ifu minidec
    input [`RFIDX_WIDTH-1:0] i_rs2idx, //from ifu minidec

    //flush interface to IFU
    input pipe_flush_ack,
    output pipe_flush_req,
    output [`PC_SIZE-1:0] pipe_flush_add_op1,
    output [`PC_SIZE-1:0] pipe_flush_add_op2,

    //LSU Write-Back interface
    input lsu_wbck_i_valid,
    output lsu_wbck_i_ready,
    input [`XLEN-1:0] lsu_wbck_i_data,
    input [`ITAG_WIDTH-1:0] lsu_wbck_i_itag,
    
    output oitf_empty,
    output [`XLEN-1:0] rf2ifu_x1,
    output [`XLEN-1:0] rf2ifu_rs1,

    output dec2ifu_rden,
    output dec2ifu_rs1en,
    output [`RFIDX_WIDTH-1:0] dec2ifu_rdidx,
    //output dec2_ifu_mulhsu,
    //output dec2_ifu_div,
    //output dec2_ifu_rem,
    //output dec2_ifu_divu,
    //output dec2_ifu_remu,

    //AGU to lsu_ctrl
    output agu_cmd_valid,
    input agu_cmd_ready,
    output [`DTCM_ADDR_WIDTH-1:0] agu_cmd_addr,
    output agu_cmd_read,
    output [`ITAG_WIDTH-1:0] agu_cmd_itag,
    output [1:0] agu_cmd_size,
    output agu_cmd_usign,
    output [`XLEN-1:0] agu_cmd_wdata,
    output [`XLEN/8-1:0] agu_cmd_wmask,
    
    input agu_rsp_valid,
    output agu_rsp_ready,
    // input [`XLEN-1:0] agu_rsp_rdata,

    input clk,
    input rst_n
);

//instantiate regfile
wire [`XLEN-1:0] rf_read_src1_data;
wire [`XLEN-1:0] rf_read_src2_data;
wire [`RFIDX_WIDTH-1:0] rf_wbck_o_rdidx;
wire rf_wbck_o_ena;
wire [`XLEN-1:0] rf_wbck_o_data;
wire [`XLEN-1:0] rf_x1_data;
assign rf2ifu_rs1 = rf_read_src1_data;
exu_regfile u_exu_regfile (
    .read_src1_idx(i_rs1idx), //from ifu
    .read_src2_idx(i_rs2idx), // from ifu
    .read_src1_data(rf_read_src1_data),//to disp or ifu
    .read_src2_data(rf_read_src2_data),//to disp
    .wbck_dest_idx(rf_wbck_o_rdidx),//from wbck
    .wbck_dest_data(rf_wbck_o_data),//from wbck
    .wbck_dest_ena(rf_wbck_o_ena),//from wbck
    .x1_data(rf2ifu_x1),
    .clk(clk),
    .rst_n(rst_n)
);  

//instantiate decode
wire [`DECINFO_WIDTH-1:0] dec_info;
wire [`XLEN-1:0] dec_imm;
wire dec_rdwen;
wire [`PC_SIZE-1:0] dec_pc;
wire dec_illegal;
wire [`RFIDX_WIDTH-1:0] dec_rs1idx;
wire [`RFIDX_WIDTH-1:0] dec_rs2idx;
wire [`RFIDX_WIDTH-1:0] dec_rdidx;
wire dec_rs1en;
wire dec_rs2en;

exu_decode u_exu_decode (
    .i_instr(i_ir),//from ifu
    .i_pc(i_pc),//from ifu
    .i_prdt_taken(i_prdt_taken),//from ifu
    .dec_rs1en(dec_rs1en),//to disp
    .dec_rs2en(dec_rs2en),//to disp
    .dec_rdwen(dec_rdwen),//to disp
    .dec_rs1idx(),
    .dec_rs2idx(),
    .dec_rdidx(dec_rdidx),//to disp
    .dec_info(dec_info),//to disp
    .dec_imm(dec_imm),//to disp
    .dec_pc(dec_pc),//to disp
    .dec_illegal(dec_illegal),//to disp
    .dec_bjp(),
    .dec_jal(),
    .dec_jalr(),
    .dec_bxx(),
    .dec_jalr_rs1idx(),
    .dec_bjp_imm()
);

//instantiate disp
wire disp_oitf_ena;
wire disp_oitf_rs1en;
wire disp_oitf_rs2en;
wire disp_oitf_rdwen;
wire [`RFIDX_WIDTH-1:0] disp_oitf_rs1idx;
wire [`RFIDX_WIDTH-1:0] disp_oitf_rs2idx;
wire [`RFIDX_WIDTH-1:0] disp_oitf_rdidx;

wire disp_o_alu_valid;
wire [`XLEN-1:0] disp_o_alu_rs1;
wire [`XLEN-1:0] disp_o_alu_rs2;
wire disp_o_alu_rdwen;
wire [`RFIDX_WIDTH-1:0] disp_o_alu_rdidx;
wire [`DECINFO_WIDTH-1:0] disp_o_alu_info;
wire [`XLEN-1:0] disp_o_alu_imm;
wire [`PC_SIZE-1:0] disp_o_alu_pc;
wire [`ITAG_WIDTH-1:0] disp_o_alu_itag;
wire disp_o_alu_ilegl;

wire oitfrd_match_disprs1;
wire oitfrd_match_disprs2;
wire oitfrd_match_disprd;
wire disp_oitf_ready;
wire [`ITAG_WIDTH-1:0] disp_oitf_ptr;
wire disp_o_alu_ready;
wire disp_o_alu_longpipe;

exu_disp u_exu_disp (
    .oitf_empty(oitf_empty),//from oitf
    .disp_i_valid(i_valid),//from ifu
    .disp_i_ready(i_ready),//to ifu
    .disp_i_rs1idx(i_rs1idx),//from ifu rs1idx_r
    .disp_i_rs2idx(i_rs1idx),//from ifu rs2idx_r
    .disp_i_rs1en(dec_rs1en),//from dec
    .disp_i_rs2en(dec_rs2en),//from dec
    .disp_i_rdwen(dec_rdwen),//from dec
    .disp_i_rdidx(dec_rdidx), // form dec
    .disp_i_rs1(rf_read_src1_data),//from reg
    .disp_i_rs2(rf_read_src2_data),//from reg
    .disp_i_info(dec_info),//from dec
    .disp_i_imm(dec_imm),//from dec
    .disp_i_pc(dec_pc),//from dec
    .disp_ilegl(dec_illegal),//from dec

    .disp_o_alu_valid(disp_o_alu_valid),//to alu
    .disp_o_alu_ready(disp_o_alu_ready),//from alu
    .disp_o_alu_longpipe(disp_o_alu_longpipe),//from alu
    .disp_o_alu_rs1(disp_o_alu_rs1),//to alu
    .disp_o_alu_rs2(disp_o_alu_rs2),//to alu
    .disp_o_alu_rdwen(disp_o_alu_rdwen),//to alu
    .disp_o_alu_rdidx(disp_o_alu_rdidx),//to alu
    .disp_o_alu_info(disp_o_alu_info),//to alu
    .disp_o_alu_imm(disp_o_alu_imm),//to alu
    .disp_o_alu_pc(disp_o_alu_pc),//to alu
    .disp_o_alu_itag(disp_o_alu_itag),//to alu
    .disp_o_alu_ilegl(disp_o_alu_ilegl),//to alu

    .oitfrd_match_disprs1(oitfrd_match_disprs1),//from oitf
    .oitfrd_match_disprs2(oitfrd_match_disprs2),//from oitf
    .oitfrd_match_disprd(oitfrd_match_disprd),//from oitf
    .disp_oitf_ptr(disp_oitf_ptr),//from oitf
    .disp_oitf_ena(disp_oitf_ena),//to oitf
    .disp_oitf_ready(disp_oitf_ready),// from oitf
    .disp_oitf_rs1en(disp_oitf_rs1en),//to oitf
    .disp_oitf_rs2en(disp_oitf_rs2en),//to oitf
    .disp_oitf_rdwen(disp_oitf_rdwen),//to oitf
    .disp_oitf_rs1idx(disp_oitf_rs1idx),//to oitf
    .disp_oitf_rs2idx(disp_oitf_rs2idx),//to oitf
    .disp_oitf_rdidx(disp_oitf_rdidx)//to oitf
);

//instantiate alu
wire alu_cmt_i_valid;
wire [`XLEN-1:0] alu_cmt_i_imm;
wire alu_cmt_i_bjp;
wire alu_cmt_i_ilegl;
wire alu_cmt_i_bjp_prdt;
wire alu_cmt_i_bjp_rslv;
wire alu_wbck_i_valid;
wire [`XLEN-1:0] alu_wbck_i_data;
wire [`RFIDX_WIDTH-1:0] alu_wbck_i_rdidx;
wire alu_cmt_i_ready;
wire alu_wbck_i_ready;
wire [`PC_SIZE-1:0] alu_cmt_i_pc;

exu_alu u_exu_alu (
    .i_valid(disp_o_alu_valid),//from disp
    .i_ready(disp_o_alu_ready),//to disp
    .i_longpipe(disp_o_alu_longpipe),//to disp
    .i_itag(disp_o_alu_itag),//from disp
    .i_rs1(disp_o_alu_rs1),//from disp
    .i_rs2(disp_o_alu_rs2),//from disp
    .i_imm(disp_o_alu_imm),//from disp
    .i_info(disp_o_alu_info),//from disp
    .i_pc(disp_o_alu_pc),//from disp

    .i_pc_vld(),//from ifu
    .i_rdidx(disp_o_alu_rdidx),//from disp
    .i_rdwen(disp_o_alu_rdwen),//from disp
    .i_ilegl(disp_o_alu_ilegl),//from disp
    //.flush_req(),

    .cmt_o_valid(alu_cmt_i_valid),//to commit
    .cmt_o_ready(alu_cmt_i_ready),//from commit 
    .cmt_o_pc(alu_cmt_i_pc),//to commit
    .cmt_o_imm(alu_cmt_i_imm),//to commit
    .cmt_o_bjp(alu_cmt_i_bjp),//to commit
    .cmt_o_ifu_ilegl(alu_cmt_i_ilegl),//to commit
    .cmt_o_bjp_prdt(alu_cmt_i_bjp_prdt),//to commit
    .cmt_o_bjp_rslv(alu_cmt_i_bjp_rslv),//to commit
    
    .wbck_o_valid(alu_wbck_i_valid),// to wbck
    .wbck_o_ready(alu_wbck_i_ready),//from wbck
    .wbck_o_wdat(alu_wbck_i_data),// to wbck
    .wbck_o_rdidx(alu_wbck_i_rdidx),// to wbck

    .mdv_nob2b(),
    .agu_cmd_valid(agu_cmd_valid),//to lsu
    .agu_cmd_ready(agu_cmd_ready),//from lsu
    .agu_cmd_addr(agu_cmd_addr),//to lsu
    .agu_cmd_read(agu_cmd_read),//to lsu
    .agu_cmd_wdata(agu_cmd_wdata),//to lsu
    .agu_cmd_wmask(agu_cmd_wmask),//to lsu
    .agu_cmd_size(agu_cmd_size),
    .agu_cmd_usign(agu_cmd_usign),
    // .agu_cmd_back2agu(),
    .agu_cmd_itag(agu_cmd_itag),//to lsu
    .agu_rsp_valid(agu_rsp_valid),//from lsu
    .agu_rsp_ready(agu_rsp_ready),//to lsu
    // .agu_rsp_rdata(agu_rsp_rdata),//from lsu

    .clk(clk),
    .rst_n(rst_n)
);

//instantiate commit 

exu_commit u_exu_commit (
    .nonflush_cmt_ena(),
    .alu_cmt_i_valid(alu_cmt_i_valid),//from alu
    .alu_cmt_i_ready(alu_cmt_i_ready),//to alu
    .alu_cmt_i_imm(alu_cmt_i_imm),//from alu
    .alu_cmt_i_bjp(alu_cmt_i_bjp),//from alu
    .alu_cmt_i_bjp_prdt(alu_cmt_i_bjp_prdt),//from alu
    .alu_cmt_i_bjp_rslv(alu_cmt_i_bjp_rslv),//from alu
    .alu_cmt_i_pc(alu_cmt_i_pc),//from alu
    .alu_cmt_i_ilegl(alu_cmt_i_ilegl),//from alu
    .pipe_flush_ack(pipe_flush_ack),//from ifu
    .pipe_flush_req(pipe_flush_req),// to ifu
    .pipe_flush_add_op1(pipe_flush_add_op1),// to ifu
    .pipe_flush_add_op2(pipe_flush_add_op2)// to ifu
);

//instantiate oitf
wire [`ITAG_WIDTH-1:0] oitf_ret_ptr;
wire oitf_ret_ena;
wire [`RFIDX_WIDTH-1:0] oitf_ret_rdidx;
wire oitf_ret_rdwen;
exu_oitf u_exu_oitf (
    .disp_ready(disp_oitf_ready),//to disp
    .disp_ena(disp_oitf_ena),//from disp
    .dis_ptr(disp_oitf_ptr),//to disp
    .ret_ena(oitf_ret_ena),//to longp
    .ret_ptr(oitf_ret_ptr),//to longp
    .ret_rdidx(oitf_ret_rdidx),//to longp
    .ret_rdwen(oitf_ret_rdwen),//to longp
    .disp_i_rs1en(disp_oitf_rs1en),//from disp
    .disp_i_rs2en(disp_oitf_rs2en),//from disp
    .disp_i_rdwen(disp_oitf_rdwen),//from disp
    .disp_i_rs1idx(disp_oitf_rs1idx),//from disp
    .disp_i_rs2idx(disp_oitf_rs2idx),//from disp
    .disp_i_rdidx(disp_oitf_rdidx),//from disp
    .oitfrd_match_disprs1(oitfrd_match_disprs1),//to disp
    .oitfrd_match_disprs2(oitfrd_match_disprs2),//to disp
    .oitfrd_match_disprd(oitfrd_match_disprd),//to disp
    .oitf_empty(oitf_empty), //output 
    .clk(clk),
    .rst_n(rst_n)
);

//instantiate longp
wire longp_wbck_o_valid;
wire [`XLEN-1:0] longp_wbck_o_data;
wire [`RFIDX_WIDTH-1:0] longp_wbck_o_rdidx;
wire longp_wbck_o_ready;

exu_longpwbck u_exu_longpwbck (
    .lsu_wbck_i_valid(lsu_wbck_i_valid),//from lsu
    .lsu_wbck_i_ready(lsu_wbck_i_ready),//to lsu
    .lsu_wbck_i_data(lsu_wbck_i_data),//from lsu
    .lsu_wbck_i_itag(lsu_wbck_i_itag),//from lsu
    .longp_wbck_o_valid(longp_wbck_o_valid),//to wbck
    .longp_wbck_o_ready(longp_wbck_o_ready),//from wbck
    .longp_wbck_o_data(longp_wbck_o_data),//to wbck
    .longp_wbck_o_rdidx(longp_wbck_o_rdidx),// to wbck
    .oitf_empty(oitf_empty),//from oitf
    .oitf_ret_ptr(oitf_ret_ptr),//from oitf
    .oitf_ret_rdwen(oitf_ret_rdwen),//from oitf
    .oitf_ret_ena(oitf_ret_ena),//from oitf
    .oitf_ret_rdidx(oitf_ret_rdidx)//from oitf
);


//instantiate wbck
exu_wbck u_exu_wbck (
    .alu_wbck_i_valid(alu_wbck_i_valid),//from alu
    .alu_wbck_i_ready(alu_wbck_i_ready),//to alu
    .alu_wbck_i_data(alu_wbck_i_data),//from alu
    .alu_wbck_i_rdidx(alu_wbck_i_rdidx),//from alu

    .longp_wbck_i_valid(longp_wbck_o_valid),//from longp
    .longp_wbck_i_ready(longp_wbck_o_ready),//to longp
    .longp_wbck_i_data(longp_wbck_o_data),//from longp
    .longp_wbck_i_rdidx(longp_wbck_o_rdidx),//from longp

    .rf_wbck_o_ena(rf_wbck_o_ena),//to regfile
    .rf_wbck_o_data(rf_wbck_o_data),//to regfile
    .rf_wbck_o_rdidx(rf_wbck_o_rdidx)//to regfile
);
    
endmodule