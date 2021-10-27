//=================================================
//Description: general purpose EXU register file module
//Author : Hurui
//Modules: exu_regfile
//=================================================
`include "defines.v"

module exu_regfile (
    input [`RFIDX_WIDTH-1:0] read_src1_idx,
    input [`RFIDX_WIDTH-1:0] read_src2_idx,
    output [`XLEN-1:0] read_src1_data,
    output [`XLEN-1:0] read_src2_data,
    
    input [`RFIDX_WIDTH-1:0] wbck_dest_idx,
    input [`XLEN-1:0] wbck_dest_data,
    input wbck_dest_ena,

    output [`XLEN-1:0] x1_data,

    input clk,
    input rst_n
);

wire [`XLEN-1:0] rf_r[`RFREG_NUM-1:0];
wire [`RFREG_NUM-1:0] rf_wen;

genvar i;
generate
    for(i=0; i<`RFREG_NUM; i=i+1) begin:regfile
        if(i==0) begin:x0
            assign rf_wen[i] = 1'b0;
            assign rf_r[i] = `XLEN'b0;          
        end        
        else begin:not_x0
            assign rf_wen[i] = wbck_dest_ena & (wbck_dest_idx == i);
            gnrl_dfflr #(`XLEN) rf_dfflr(rf_wen[i], wbck_dest_data, rf_r[i], clk, rst_n);
        end
    end
endgenerate
assign read_src1_data = rf_r[read_src1_idx];
assign read_src2_data = rf_r[read_src2_idx];
assign x1_data = rf_r[1];// accelerate x1
endmodule