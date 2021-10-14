//=================================================
//Description: load store ctrl unit
//Author : Hurui
//Modules: lsu_ctrl
//=================================================
`include "defines.v"

module lsu_ctrl (
    //The LSU write-back interface(to longpipe wbck)
    output lsu_o_valid,
    input lsu_o_ready,
    output [`XLEN-1:0] lsu_o_wbck_wdat,
    output [`ITAG_WIDTH-1:0] lsu_o_wbck_itag,

    //AGU to LSU-ctrl interface
    input agu_cmd_valid,
    output agu_cmd_ready,
    input agu_cmd_read,
    input [`DTCM_ADDR_WIDTH-1:0] agu_cmd_addr,
    input [`XLEN-1:0] agu_cmd_wdata,
    input [`XLEN/8-1:0] agu_cmd_wmask,
    input [`ITAG_WIDTH-1:0] agu_cmd_itag,
    input agu_cmd_usign,
    input [1:0] agu_cmd_size,
    output agu_rsp_valid,
    input agu_rsp_ready,

    //LSU to DTCM interface
    output dtcm_cmd_valid,
    input dtcm_cmd_ready,
    output dtcm_cmd_read,
    output [`DTCM_ADDR_WIDTH-1:0] dtcm_cmd_addr,
    output [`XLEN-1:0] dtcm_cmd_wdata,
    output [`XLEN/8-1:0] dtcm_cmd_wmask,
    input dtcm_rsp_valid,
    output dtcm_rsp_ready,
    input [`XLEN-1:0] dtcm_rsp_rdata,
    
    input clk,
    input rst_n
);
    wire wbck_hsked = dtcm_rsp_ready & dtcm_rsp_valid;
    assign lsu_o_valid = wbck_hsked;
    // assign lsu_o_wbck_data = {`XLEN{wbck_hsked}} & dtcm_rsp_rdata;
    wire fifo_i_ready;
    assign agu_cmd_ready = fifo_i_ready; //dtcm ready to accept new instruction when there is no existing outstand lsu instruction
    assign agu_rsp_valid = wbck_hsked;
    
    assign dtcm_cmd_valid = agu_cmd_valid;
    assign dtcm_cmd_read = agu_cmd_read;
    assign dtcm_cmd_addr = agu_cmd_addr;
    assign dtcm_cmd_wdata = agu_cmd_wdata;
    assign dtcm_cmd_wmask = agu_cmd_wmask;
    assign dtcm_rsp_ready = 1'b1; //LSU always ready to accept data from DTCM

    //third pipeline stage
    //although OITF is 2 instructions deep, we only allow 1 outstanding instruction for lsu
<<<<<<< HEAD
    wire [`ITAG_WIDTH-1:0] agu_cmd_fifo_data =  agu_cmd_itag;
=======
    wire [`ITAG_WIDTH+4-1:0] agu_cmd_fifo_data = 
                                                                                {agu_cmd_itag, 
                                                                                agu_cmd_read, 
                                                                                agu_cmd_usign, 
                                                                                agu_cmd_size};
>>>>>>> 0b4a6f86448e4f8dbead00239b44e25c06ea8eef
    wire fifo_i_valid = agu_cmd_valid;
   
    wire fifo_o_valid;
    wire fifo_o_ready = 1'b1;
    wire [`ITAG_WIDTH+4-1:0] agu_cmd_fifo_data_o;
    assign lsu_o_wbck_itag= {`ITAG_WIDTH{wbck_hsked}} & agu_cmd_fifo_data_o;
    wire [`ITAG_WIDTH-1:0] agu_cmd_itag_o;
    wire agu_cmd_read_o;
    wire [1:0] agu_cmd_size_o;
    wire agu_cmd_usign_o;
    assign {agu_cmd_itag_o,
                agu_cmd_read_o,
                agu_cmd_usign_o,
                agu_cmd_size_o} = agu_cmd_fifo_data_o;
  
    //Assume DTCM return data 1cycle later
    gnrl_pipe_stage #(
        .DW(`ITAG_WIDTH+4),
        .DP(1)//although OITF is 2 instructions deep, we only allow 1 outstanding instruction for lsu
    ) u_lsu_pipe_stage (
        .i_vld(fifo_i_valid),
        .i_rdy(fifo_i_ready),
        .i_dat(agu_cmd_fifo_data),
        .o_vld(fifo_o_valid), //rsp valid from dtcm//to check
        .o_rdy(fifo_o_ready),
        .o_dat(agu_cmd_fifo_data_o),
        .clk(clk),
        .rst_n(rst_n)
    );

    wire [`XLEN-1:0] pre_agu_rsp_wdata;
    assign pre_agu_rsp_wdata = dtcm_cmd_wdata;
    wire [`ADDR_SIZE-1:0]   pre_agu_rsp_addr;
    assign   pre_agu_rsp_addr = dtcm_cmd_addr;
    
   wire [2-1:0]     pre_agu_rsp_size;
    wire rsp_lb  = (pre_agu_rsp_size == 2'b00);
    wire rsp_lh  = (pre_agu_rsp_size == 2'b01);
    wire rsp_lw  = (pre_agu_rsp_size == 2'b10);
    wire [`XLEN-1:0] rdata_algn =  (pre_agu_rsp_wdata >> {pre_agu_rsp_addr[1:0],3'b0});
    assign lsu_o_wbck_wdat   = 
         (({`XLEN{rsp_lb }} & {{24{rdata_algn[ 7]}}, rdata_algn[ 7:0]})
          | ({`XLEN{rsp_lh }} & {{16{rdata_algn[15]}}, rdata_algn[15:0]}) 
          | ({`XLEN{rsp_lw }} & rdata_algn[31:0])) & {`XLEN{wbck_hsked}} ;
endmodule