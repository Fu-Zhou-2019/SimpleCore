//=================================================
//Description: EXU final write back module
// arbitrate the write back request to regfile(alu or longpipe)
//Author : Hurui
//Modules: exu_wbck
//=================================================
`include "defines.v"

module exu_wbck (
    // ALU-write_back interface
    input alu_wbck_i_valid, 
    output alu_wbck_i_ready,
    input [`XLEN-1:0] alu_wbck_i_data,
    input [`RFIDX_WIDTH-1:0] alu_wbck_i_rdidx,

    // Long pipe-write_back interface
    input longp_wbck_i_valid,
    output longp_wbck_i_ready,
    input [`XLEN-1:0] longp_wbck_i_data,
    input [`RFIDX_WIDTH-1:0] longp_wbck_i_rdidx,
    //final arbitrated write-back interface to regfile
    output rf_wbck_o_ena,
    output [`XLEN-1:0] rf_wbck_o_data,
    output [`RFIDX_WIDTH-1:0] rf_wbck_o_rdidx
);
    //long pipe(multicycle) instructions have higher wbck priority over 1cycle ALU instructions
    wire wbck_ready4alu = (~longp_wbck_i_valid);
    wire wbck_sel_alu = alu_wbck_i_valid & wbck_ready4alu;//handshake with alu

    wire wbck_ready4longp = 1'b1;
    wire wbck_sel_longp = longp_wbck_i_valid & wbck_ready4longp;

    //final wbck interface
    wire wbck_i_ready;
    wire wbck_i_valid;
    wire [`XLEN-1:0] wbck_i_data;
    wire [`RFIDX_WIDTH-1:0] wbck_i_rdidx;

    assign alu_wbck_i_ready = wbck_i_ready & wbck_ready4alu;
    assign longp_wbck_i_ready = wbck_i_ready & wbck_ready4longp;

    assign wbck_i_valid = wbck_sel_alu? alu_wbck_i_valid : longp_wbck_i_valid;
    assign wbck_i_data = wbck_sel_alu? alu_wbck_i_data : longp_wbck_i_data;
    assign wbck_i_rdidx = wbck_sel_alu? alu_wbck_i_rdidx : longp_wbck_i_rdidx;

    wire rf_wbck_o_ready;
    assign rf_wbck_o_ready = 1'b1; //regfile is always ready to write
    assign wbck_i_ready = rf_wbck_o_ready;
    wire rf_wbck_o_valid = wbck_i_valid;
    assign rf_wbck_o_ena = rf_wbck_o_valid & rf_wbck_o_ready;
    assign rf_wbck_o_rdidx = wbck_i_rdidx;
    assign rf_wbck_o_data = wbck_i_data;
    
endmodule