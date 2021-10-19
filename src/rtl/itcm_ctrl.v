`include "defines.v"

module itcm_ctrl (
    //output itcm_active,
    //ifu to itcm ram interface
    input ifu2itcm_cmd_valid,
    output ifu2itcm_cmd_ready,
    input ifu2itcm_cmd_read,
    input [`ITCM_ADDR_WIDTH-1:0] ifu2itcm_cmd_addr,
    input [`ITCM_RAM_MW-1:0] ifu2itcm_cmd_wmask,
    input [`ITCM_RAM_DW-1:0] ifu2itcm_cmd_wdata,
    

    output ifu2itcm_rsp_valid,
    input ifu2itcm_rsp_ready,
    output [`ITCM_RAM_DW-1:0] ifu2itcm_rsp_rdata,

    //to itcm ram
    output itcm_ram_we,
    output [`ITCM_RAM_AW-1:0] itcm_ram_addr,
    output [`ITCM_RAM_MW-1:0] itcm_ram_wem,
    output [`ITCM_RAM_DW-1:0] itcm_ram_din,
    input [`ITCM_RAM_DW-1:0] itcm_ram_dout,
    //output ifu2itcm_holdup,
    input clk,
    input rst_n
);
    //generate handshake signals with ifu for simulation purpose
    assign ifu2itcm_cmd_ready = 1;//only ifu can access itcm, so itcm is always ready for ifu
    wire ifu2itcm_rsp_hdskd = ifu2itcm_rsp_valid & ifu2itcm_rsp_ready;
    assign ifu2itcm_rsp_rdata = {`ITCM_RAM_DW{ifu2itcm_rsp_hdskd}} & itcm_ram_dout;
    assign itcm_ram_we = ~ifu2itcm_cmd_read;
    assign itcm_ram_addr =ifu2itcm_cmd_addr[`ITCM_ADDR_WIDTH-1:2];
    assign itcm_ram_wem = ifu2itcm_cmd_wmask;
    assign itcm_ram_din = ifu2itcm_cmd_wdata;
    
    wire ifu2itcm_rsp_valid_set = ifu2itcm_cmd_valid;
    wire ifu2itcm_rsp_valid_clr = ifu2itcm_rsp_valid;
    wire ifu2itcm_rsp_valid_nxt = ifu2itcm_rsp_valid_set | (~ifu2itcm_rsp_valid_clr);
    wire ifu2itcm_rsp_valid_ena = ifu2itcm_rsp_valid_set | ifu2itcm_rsp_valid_clr;
    gnrl_dfflr #(1) ifu2itcm_rsp_valid_dfflr(ifu2itcm_rsp_valid_ena, ifu2itcm_rsp_valid_nxt, ifu2itcm_rsp_valid, clk, rst_n);
endmodule