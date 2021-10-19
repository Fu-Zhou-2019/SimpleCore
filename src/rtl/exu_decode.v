/*
Description:
    Decode module
    Assume rv32IM
    no x0 accerleration
    no custom extention
Author: Hu Rui
Modules: exu_decode
*/


`include "defines.v"

module exu_decode (
    input[`INSTR_SIZE-1: 0] i_instr,
    input[`PC_SIZE-1:0] i_pc,
    input i_prdt_taken,
    
    //regfile ralated
    output dec_rs1en,
    output dec_rs2en,
    output dec_rdwen,
    output [`RFIDX_WIDTH-1:0] dec_rs1idx,
    output [`RFIDX_WIDTH-1:0] dec_rs2idx,
    output [`RFIDX_WIDTH-1:0] dec_rdidx,
    output [`DECINFO_WIDTH-1:0] dec_info,
    output [`XLEN-1:0] dec_imm,
    output [`PC_SIZE-1:0] dec_pc,
    output dec_illegal,
    
    //bjp instructions related
    output dec_bjp,
    output dec_jal,
    output dec_jalr,
    output dec_bxx,

    output [`RFIDX_WIDTH-1:0] dec_jalr_rs1idx,
    output [`XLEN-1:0] dec_bjp_imm
);

//=================================================
//regfile related signals
wire need_rs1 = ~(rv32_lui | rv32_auipc | rv32_jal) ;
wire need_rs2 = rv32_branch | rv32_store | rv32_op;
wire need_rd = ~(rv32_branch | rv32_store);

wire[`RFIDX_WIDTH-1:0] rs1_idx = i_instr[19:15];
wire[`RFIDX_WIDTH-1:0] rs2_idx = i_instr[24:20];
wire[`RFIDX_WIDTH-1:0] rd_idx = i_instr[11:7];
wire rs1_x0 = rs1_idx == {`RFIDX_WIDTH{1'b0}};
wire rd_x0 = rd_idx == {`RFIDX_WIDTH{1'b0}};
wire rs1_x31 = rs1_idx == {`RFIDX_WIDTH{1'b1}};
wire rs2_x31 = rs1_idx == {`RFIDX_WIDTH{1'b1}};
wire rd_x31 = rd_idx == {`RFIDX_WIDTH{1'b1}};

//=================================================
//opcode & func3 & func7 signals
wire opcode_1_0_00 = i_instr[1:0] == 2'b00;
wire opcode_1_0_11 = i_instr[1:0] == 2'b11;


wire opcode_4_2_000 = i_instr[4:2] == 3'b000;
wire opcode_4_2_001 = i_instr[4:2] == 3'b001;
wire opcode_4_2_011 = i_instr[4:2] == 3'b011;
wire opcode_4_2_100 = i_instr[4:2] == 3'b100;
wire opcode_4_2_101 = i_instr[4:2] == 3'b101;
wire opcode_4_2_111 = i_instr[4:2] == 3'b111;

wire opcode_6_5_00 = i_instr[6:5] == 2'b00;
wire opcode_6_5_01 = i_instr[6:5] == 2'b01;
wire opcode_6_5_11 = i_instr[6:5] == 2'b11;

wire func3_000 = i_instr[14:12] == 3'b000;
wire func3_001 = i_instr[14:12] == 3'b001;
wire func3_010 = i_instr[14:12] == 3'b010;
wire func3_011 = i_instr[14:12] == 3'b011;
wire func3_100 = i_instr[14:12] == 3'b100;
wire func3_101 = i_instr[14:12] == 3'b101;
wire func3_110 = i_instr[14:12] == 3'b110;
wire func3_111 = i_instr[14:12] == 3'b111;

wire func7_0000000 = i_instr[31:25] == 7'b000_0000;
wire func7_0000001 = i_instr[31:25] == 7'b000_0001;
wire func7_0100000 = i_instr[31:25] == 7'b010_0000;
wire func7_1111111 = i_instr[31:25] == 7'b111_1111;

//=================================================
//grouping by opcode
wire rv32_lui = opcode_4_2_101 & opcode_6_5_01;
wire rv32_auipc = opcode_4_2_101 & opcode_6_5_00 ;
wire rv32_jal = opcode_4_2_011 & opcode_6_5_11;
wire rv32_jalr = opcode_4_2_001 & opcode_6_5_11;

wire rv32_branch = opcode_4_2_000 & opcode_6_5_11;
wire rv32_load = opcode_4_2_000 & opcode_6_5_00 &opcode_1_0_11;
wire rv32_store = opcode_4_2_000 & opcode_6_5_01 & opcode_1_0_11;
wire rv32_op_imm = opcode_4_2_100 & opcode_6_5_00;
wire rv32_op = opcode_4_2_100 & opcode_6_5_01;//including muldiv

//=================================================
//branch instructions
wire rv32_beq = rv32_branch & func3_000;
wire rv32_bne = rv32_branch & func3_001;
wire rv32_blt = rv32_branch & func3_100;
wire rv32_bge = rv32_branch & func3_101;
wire rv32_bltu = rv32_branch & func3_110;
wire rv32_bgeu = rv32_branch & func3_111;

//=================================================
//decode info of BJP group
wire bjp_op = rv32_branch | rv32_jal | rv32_jalr;

wire [`DECINFO_BJP_WIDTH-1:0] bjp_info_bus;
assign bjp_info_bus[`DECINFO_GRP] = `DECINFO_GRP_BJP; //group
assign bjp_info_bus[`DECINFO_BJP_JUMP] = rv32_jal | rv32_jalr;
assign bjp_info_bus[`DECINFO_BJP_BPRDT] = i_prdt_taken;
assign bjp_info_bus[`DECINFO_BJP_BEQ] = rv32_beq;
assign bjp_info_bus[`DECINFO_BJP_BNE] = rv32_bne;
assign bjp_info_bus[`DECINFO_BJP_BLT] = rv32_blt;
assign bjp_info_bus[`DECINFO_BJP_BGE] = rv32_bge;
assign bjp_info_bus[`DECINFO_BJP_BLTU] = rv32_bltu;
assign bjp_info_bus[`DECINFO_BJP_BGEU] = rv32_bgeu;
assign bjp_info_bus[`DECINFO_BJP_BXX] = rv32_branch;

//=================================================
//ALU instructions
wire rv32_addi = rv32_op_imm & func3_000;
wire rv32_slti = rv32_op_imm & func3_010;
wire rv32_sltiu = rv32_op_imm & func3_011;
wire rv32_xori = rv32_op_imm & func3_100;
wire rv32_ori = rv32_op_imm & func3_110;
wire rv32_andi = rv32_op_imm & func3_111;
wire rv32_slli = rv32_op_imm & func3_001 & func7_0000000;
wire rv32_srli = rv32_op_imm & func3_101 & func7_0000000;
wire rv32_srai = rv32_op_imm & func3_101 &func7_0100000;
wire rv32_op_imm_sxxi  = rv32_slli | rv32_srli | rv32_srai;
wire rv32_nop = rv32_addi & rs1_x0 & rd_x0 & (~(|i_instr[31:20]));// use addi x0, x0, 0 for nop instruction

wire rv32_add = rv32_op & func3_000 & func7_0000000;
wire rv32_sub = rv32_op & func3_000 & func7_0100000;
wire rv32_sll = rv32_op & func3_001 & func7_0000000;
wire rv32_slt = rv32_op & func3_010 & func7_0000000;
wire rv32_sltu = rv32_op & func3_011 & func7_0000000;
wire rv32_xor = rv32_op & func3_100 & func7_0000000;
wire rv32_srl = rv32_op & func3_101 & func7_0000000;
wire rv32_sra = rv32_op & func3_101 & func7_0100000;
wire rv32_or = rv32_op & func3_110 & func7_0000000;
wire rv32_and = rv32_op & func3_111 & func7_0000000;

wire rv32_mul = rv32_op & func3_000 & func7_0000001;
wire rv32_mulh = rv32_op & func3_001 & func7_0000001;
wire rv32_mulhsu = rv32_op & func3_010 & func7_0000001;
wire rv32_mulhu = rv32_op & func3_011 & func7_0000001;
wire rv32_div = rv32_op & func3_100 & func7_0000001;
wire rv32_divu = rv32_op & func3_101 & func7_0000001;
wire rv32_rem = rv32_op & func3_110 & func7_0000001;
wire rv32_remu = rv32_op & func3_111 & func7_0000001;

//=================================================
//decode info of 1cycle ALU group(excluding MULDIV)
wire alu_op = (~rv32_shamt_illegal)
                & (rv32_lui
                | rv32_auipc
                | rv32_op_imm
                | (rv32_op & ~func7_0000001) //exclude muldiv
                );

wire [`DECINFO_ALU_WIDTH-1:0] alu_info_bus;
assign alu_info_bus[`DECINFO_GRP] = `DECINFO_GRP_ALU;
assign alu_info_bus[`DECINFO_ALU_ADD] = rv32_add | rv32_addi | rv32_auipc;
assign alu_info_bus[`DECINFO_ALU_SUB] = rv32_sub;//there is no subi
assign alu_info_bus[`DECINFO_ALU_SLT] = rv32_slt | rv32_slti;
assign alu_info_bus[`DECINFO_ALU_SLTU] = rv32_sltu | rv32_sltiu;
assign alu_info_bus[`DECINFO_ALU_XOR] = rv32_xor | rv32_xori;
assign alu_info_bus[`DECINFO_ALU_OR] = rv32_or | rv32_ori;
assign alu_info_bus[`DECINFO_ALU_AND] = rv32_and | rv32_andi;
assign alu_info_bus[`DECINFO_ALU_SLL] = rv32_sll | rv32_slli;
assign alu_info_bus[`DECINFO_ALU_SRL] = rv32_srl | rv32_srli;
assign alu_info_bus[`DECINFO_ALU_SRA] = rv32_sra | rv32_srai;
assign alu_info_bus[`DECINFO_ALU_LUI] = rv32_lui;
assign alu_info_bus[`DECINFO_ALU_OP2IMM] = need_imm;
assign alu_info_bus[`DECINFO_ALU_OP1PC] =rv32_auipc;
assign alu_info_bus[`DECINFO_ALU_NOP] = rv32_nop;

//=================================================
//decode info of MUL/DIV ALU group
wire muldiv_op = rv32_op & func7_0000001;

wire [`DECINFO_MULDIV_WIDTH-1:0] muldiv_info_bus;
assign muldiv_info_bus[`DECINFO_GRP] = `DECINFO_GRP_MULDIV;
assign muldiv_info_bus[`DECINFO_MULDIV_MUL] = rv32_mul;
assign muldiv_info_bus[`DECINFO_MULDIV_MULH] = rv32_mulh;
assign muldiv_info_bus[`DECINFO_MULDIV_MULHSU] = rv32_mulhsu;
assign muldiv_info_bus[`DECINFO_MULDIV_MULHU] = rv32_mulhu;
assign muldiv_info_bus[`DECINFO_MULDIV_DIV] = rv32_div;
assign muldiv_info_bus[`DECINFO_MULDIV_DIVU] = rv32_divu;
assign muldiv_info_bus[`DECINFO_MULDIV_REM] = rv32_rem;
assign muldiv_info_bus[`DECINFO_MULDIV_REMU] = rv32_remu;
//assign muldiv_info_bus[`DECINFO_MULDIV_B2B] = i_mul_div_b2b;


//=================================================
//load/store instructions
wire rv32_lb = rv32_load & func3_000;
wire rv32_lh = rv32_load & func3_001;
wire rv32_lw = rv32_load & func3_010;
wire rv32_lbu = rv32_load & func3_100;
wire rv32_lhu = rv32_load & func3_101;

wire rv32_sb = rv32_store & func3_000;
wire rv32_sh = rv32_store & func3_001;
wire rv32_sw = rv32_store & func3_010;

//=================================================
//decode info of load/store group
wire ls_op = rv32_load | rv32_store;
wire [1:0] lsu_info_size = i_instr[13:12];
wire lsu_info_usign = i_instr[14];

wire [`DECINFO_AGU_WIDTH-1:0] agu_info_bus;
assign agu_info_bus[`DECINFO_GRP] = `DECINFO_GRP_AGU;
assign agu_info_bus[`DECINFO_AGU_LOAD] = rv32_load;
assign agu_info_bus[`DECINFO_AGU_STORE] = rv32_store;
assign agu_info_bus[`DECINFO_AGU_SIZE] = lsu_info_size;//0 for byte, 1for half word, 2 for word
assign agu_info_bus[`DECINFO_AGU_USIGN] = lsu_info_usign;
assign agu_info_bus[`DECINFO_AGU_OP2IMM] = need_imm;



//=================================================
//immediate
wire rv32_imm_sel_i = rv32_jalr | rv32_op_imm | rv32_load;
wire rv32_imm_sel_s = rv32_store;
wire rv32_imm_sel_b = rv32_branch;
wire rv32_imm_sel_u = rv32_lui | rv32_auipc;
wire rv32_imm_sel_j = rv32_jal;
wire need_imm = ~rv32_op;
wire[`XLEN-1:0] rv32_i_imm =  {{20{i_instr[31]}},i_instr[31:20]};
wire[`XLEN-1:0] rv32_s_imm = {{20{i_instr[31]}},i_instr[31], i_instr[30:25],i_instr[11:8], i_instr[7]};
wire[`XLEN-1:0] rv32_b_imm = {{20{i_instr[31]}},
                                                 i_instr[7], 
                                                 i_instr[30:25], 
                                                 i_instr[11:8], 
                                                 1'b0};
wire[`XLEN-1:0] rv32_u_imm ={i_instr[31:12],
                                                12'b0};
wire[`XLEN-1:0] rv32_j_imm = {{11{i_instr[31]}},
                                                i_instr[31],
                                                i_instr[19:12],
                                                i_instr[20],
                                                i_instr[30:25],
                                                i_instr[24:21],
                                                1'b0};

//=================================================
//illegal
wire all_zeros_illegal = opcode_1_0_00 
                                    & opcode_4_2_000 
                                    & opcode_6_5_00
                                    & rd_x0
                                    & func3_000
                                    & i_instr[15] == 1'b0;
wire all_ones_illegal = opcode_1_0_11
                                    & opcode_4_2_111
                                    & opcode_6_5_11
                                    & rd_x31
                                    & func3_111
                                    & rs1_x31
                                    & rs2_x31
                                    & func7_1111111;
wire rv32_shamt_illegal = rv32_op_imm_sxxi & (i_instr[24] != 0);
wire rv32_legal_ops = alu_op | muldiv_op | ls_op | bjp_op;



//=================================================
//output
assign dec_rs1idx = rs1_idx;
assign dec_rs2idx = rs2_idx;
assign dec_rs1en = need_rs1;
assign dec_rs2en = need_rs2;
assign dec_rdidx = rd_idx;
assign dec_rdwen = need_rd & (~dec_illegal);
assign dec_jalr_rs1idx = rs1_idx;
assign dec_pc = i_pc;
assign dec_imm = ({`XLEN{rv32_imm_sel_i}} & rv32_i_imm)
                            | ({`XLEN{rv32_imm_sel_s}} & rv32_s_imm)
                            | ({`XLEN{rv32_imm_sel_b}} & rv32_b_imm)
                            | ({`XLEN{rv32_imm_sel_u}} & rv32_u_imm)
                            | ({`XLEN{rv32_imm_sel_j}} & rv32_j_imm);
assign dec_illegal = all_ones_illegal
                                | all_zeros_illegal
                                | rv32_shamt_illegal
                                | ~rv32_legal_ops;
assign dec_jal = rv32_jal;
assign dec_jalr = rv32_jalr;
assign dec_bjp = bjp_op;
assign dec_bjp_imm =({`XLEN{rv32_jalr}} & rv32_i_imm)
                            | ({`XLEN{rv32_branch}} & rv32_b_imm)
                            | ({`XLEN{rv32_jal}} & rv32_j_imm);
assign dec_bxx = rv32_branch;
assign dec_info = {{`DECINFO_WIDTH{bjp_op}}&
                            {{`DECINFO_WIDTH-`DECINFO_BJP_WIDTH{1'b0}},bjp_info_bus}}
                            | ({`DECINFO_WIDTH{alu_op}} & 
                            {{`DECINFO_WIDTH-`DECINFO_ALU_WIDTH{1'b0}},
                            alu_info_bus})
                            | ({`DECINFO_WIDTH{muldiv_op}} & 
                            {{`DECINFO_WIDTH-`DECINFO_MULDIV_WIDTH{1'b0}},
                            muldiv_info_bus})
                            |({`DECINFO_WIDTH{ls_op}} & 
                            {{`DECINFO_WIDTH-`DECINFO_AGU_WIDTH{1'b0}},
                            agu_info_bus});

endmodule