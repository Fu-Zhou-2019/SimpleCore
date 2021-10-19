//=================================================
//Description: write back module to arbitrate the write-back request from all long pipe modules
//only load/store wbck through long pipe, mul/div wbck through alu
//Author : Hurui
//Modules: exu_longpwbck
//=================================================
`include "defines.v"

module exu_longpwbck (
    //LSU write-back interface
    input lsu_wbck_i_valid,
    output lsu_wbck_i_ready,
    input [`XLEN-1:0] lsu_wbck_i_data,
    input [`ITAG_WIDTH-1:0] lsu_wbck_i_itag,

    //long pipe write back to final write back interface
    output longp_wbck_o_valid,
    input longp_wbck_o_ready,
    output [`XLEN-1:0] longp_wbck_o_data,
    output [`RFIDX_WIDTH-1:0] longp_wbck_o_rdidx,
    //itag of the toppest entry of OITF
    input oitf_empty,
    input [`ITAG_WIDTH-1:0] oitf_ret_ptr,
    input oitf_ret_rdwen,
    output oitf_ret_ena,
    input [`RFIDX_WIDTH-1:0] oitf_ret_rdidx
);
//longpipe wirte back follow the order of OITF
//only when the retiring instruction match the toppest itag of OITF
//only lsu instructions(ld/st) wbck through long-pipe
//only load instructions need write back
wire wbck_ready4lsu = (lsu_wbck_i_itag == oitf_ret_ptr) & (~oitf_empty);
// wire wbck_sel_lsu = lsu_wbck_i_valid & wbck_ready4lsu;

// The final arbitrated Write-back interface
wire need_wbck = oitf_ret_rdwen;
wire wbck_i_ready = need_wbck? longp_wbck_o_ready:1'b1;
assign lsu_wbck_i_ready = wbck_ready4lsu & wbck_i_ready;
wire wbck_i_valid = lsu_wbck_i_valid;//({1{wbck_sel_lsu}} & 

assign longp_wbck_o_valid = need_wbck & wbck_i_valid;
assign longp_wbck_o_data = lsu_wbck_i_data;
assign longp_wbck_o_rdidx = oitf_ret_rdidx;
assign oitf_ret_ena = wbck_i_valid & wbck_i_ready;
endmodule

