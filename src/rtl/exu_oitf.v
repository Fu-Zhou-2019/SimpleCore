//=================================================
//Description: EXU OITF module
// The OITF(Outstanding Instruction Track FIFO) track load/store(multicycle) instructions' status and information
//Author : Hurui
//Modules: exu_oitf
//=================================================
`include "defines.v"

module exu_oitf (
    output disp_ready,

    input disp_ena, //from disp
    input ret_ena,      // from longpwb

    output [`ITAG_WIDTH-1:0] dis_ptr,
    output [`ITAG_WIDTH-1:0] ret_ptr,

    output [`RFIDX_WIDTH-1:0] ret_rdidx,
    output ret_rdwen,
    //output ret [`PC_SIZE-1:0] ret_pc,//we don't support exception yet, so unecessary to return pc

    input disp_i_rs1en,
    input disp_i_rs2en,
    input disp_i_rdwen,
    input [`RFIDX_WIDTH-1:0] disp_i_rs1idx,
    input [`RFIDX_WIDTH-1:0] disp_i_rs2idx,
    input [`RFIDX_WIDTH-1:0] disp_i_rdidx,
    //input [`PC_SIZE-1:0] disp_i_pc,
    
    //dependent info to disp
    output oitfrd_match_disprs1,
    output oitfrd_match_disprs2,
    output oitfrd_match_disprd,

    output oitf_empty,
    input clk,
    input rst_n
);
    wire [`OITF_DEPTH-1:0] vld_set;
    wire [`OITF_DEPTH-1:0] vld_clr;
    wire [`OITF_DEPTH-1:0] vld_ena;
    wire [`OITF_DEPTH-1:0] vld_nxt;
    wire [`OITF_DEPTH-1:0] vld_r;
    wire [`OITF_DEPTH-1:0] rdwen_r;
    wire [`RFIDX_WIDTH-1:0] rdidx_r[`OITF_DEPTH-1:0];
    //wire [`PC_SIZE-1:0] pc_r[`OITF_DEPTH-1:0];
    //check full/empty and fifo ptrs(alc ptr & ret ptr)
    wire alc_ptr_ena = disp_ena; //write point enable
    wire ret_ptr_ena = ret_ena; //read point enable

    wire oitf_full; //oitf empty is one of the output ports

    wire [`ITAG_WIDTH-1:0] alc_ptr_r;
    wire [`ITAG_WIDTH-1:0] ret_ptr_r;

    generate
        if(`OITF_DEPTH > 1) begin: depth_gt1
            // alc ptr(head of fifo)
            wire alc_ptr_flg_r;
            wire alc_ptr_flg_nxt = ~alc_ptr_flg_r;
            wire alc_ptr_flg_ena = (alc_ptr_r == ($unsigned(`OITF_DEPTH-1))) & alc_ptr_ena;
            gnrl_dfflr #(1) alc_ptr_flg_dfflr(alc_ptr_flg_ena, alc_ptr_flg_nxt, alc_ptr_flg_r, clk, rst_n);


            wire [`ITAG_WIDTH-1:0] alc_ptr_nxt ;
            assign alc_ptr_nxt = alc_ptr_flg_ena ? `ITAG_WIDTH'b0: (alc_ptr_r + 1'b1);
            gnrl_dfflr #(`ITAG_WIDTH) alc_ptr_dfflr(alc_ptr_ena, alc_ptr_nxt, alc_ptr_r, clk, rst_n);
            
            // ret ptr(tail of fifo)
            wire ret_ptr_flg_r;
            wire ret_ptr_flg_nxt = ~ret_ptr_flg_r;
            wire ret_ptr_flg_ena = (ret_ptr_r == ($unsigned(`OITF_DEPTH-1))) & ret_ptr_ena;
            gnrl_dfflr #(1) ret_ptr_flg_dfflr(ret_ptr_flg_ena, ret_ptr_flg_nxt, ret_ptr_flg_r, clk, rst_n);
            wire [`ITAG_WIDTH-1:0] ret_ptr_nxt;
            assign ret_ptr_nxt= ret_ptr_flg_ena? `ITAG_WIDTH'b0:(ret_ptr_r + 1'b1);

            gnrl_dfflr #(`ITAG_WIDTH) ret_ptr_dfflr(ret_ptr_ena, ret_ptr_nxt, ret_ptr_r, clk, rst_n);
            
            assign oitf_empty = (alc_ptr_r == ret_ptr_r) & (ret_ptr_flg_r == alc_ptr_flg_r);
            assign oitf_full = (alc_ptr_r == ret_ptr_r) & (~(ret_ptr_flg_r == alc_ptr_flg_r));
        end
        else begin: depth_eq1
            assign alc_ptr_r = 1'b0;
            assign ret_ptr_r = 1'b0;
            assign oitf_empty = ~vld_r[0];
            assign oitf_full = vld_r[0];
        end
    endgenerate
    assign dis_ptr = alc_ptr_r;
    assign ret_ptr = ret_ptr_r;
    
    //ready to accept new instruction only when oitf not full(actually it is ok if an instruction is retiring but we choose to ignore such case)
    assign disp_ready = ~oitf_full;

    //store incoming instruction info and check dependency
    wire [`OITF_DEPTH-1:0] rd_match_rs1idx;
    wire [`OITF_DEPTH-1:0] rd_match_rs2idx;
    wire [`OITF_DEPTH-1:0] rd_match_rdidx;

    genvar i;
    generate
        for(i=0; i<`OITF_DEPTH;i=i+1) begin:oitf_entries
            assign vld_set[i] = alc_ptr_ena & (alc_ptr_r == i);
            assign vld_clr[i] = ret_ptr_ena & (ret_ptr_r == i);
            assign vld_ena[i] = vld_set[i] | vld_clr[i];
            assign vld_nxt[i] = vld_set[i] | (~vld_clr[i]);

            gnrl_dfflr #(1) vld_dfflr(vld_ena[i], vld_nxt[i], vld_r[i], clk, rst_n);
            gnrl_dfflr #(`RFIDX_WIDTH) rdidx_dffl(vld_set[i], disp_i_rdidx, rdidx_r[i],clk, rst_n);
            gnrl_dfflr #(1) rdwen_dffl(vld_set[i], disp_i_rdwen, rdwen_r[i], clk, rst_n);


            assign rd_match_rs1idx[i] = vld_r[i] & rdwen_r[i] & disp_i_rs1en & (rdidx_r[i] == disp_i_rs1idx);
            assign rd_match_rs2idx[i] = vld_r[i] & rdwen_r[i] & disp_i_rs2en & (rdidx_r[i] == disp_i_rs2idx);
            assign rd_match_rdidx[i] = vld_r[i] & rdwen_r[i] & disp_i_rdwen & (rdidx_r[i] == disp_i_rdidx);
        end
    endgenerate

    assign oitfrd_match_disprs1 = |rd_match_rs1idx;
    assign oitfrd_match_disprs2 = |rd_match_rs2idx;
    assign oitfrd_match_disprd = |rd_match_rdidx;
    
    assign ret_rdidx = rdidx_r[ret_ptr];
    assign ret_rdwen = rdwen_r[ret_ptr];
endmodule