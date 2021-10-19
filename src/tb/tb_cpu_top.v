`timescale 1ns/1ps

`include "../rtl/defines.v"



module tb_cpu_top;
    reg clk;
    reg rst_n;
    reg[`PC_SIZE-1:0] pc_rtvec; 
    
    cpu_top u_cpu_top(
    .pc_rtvec(pc_rtvec),
    .clk(clk),
    .rst_n(rst_n)
    );
    
    initial begin
        rst_n = 0;
        pc_rtvec = {{`PC_SIZE-3{1'b0}},3'b100};
        #35 rst_n = 1;
        @(posedge clk)
        #500 $finish;
    end 
    
    initial clk = 0;
    always #5 clk = ~clk; 
endmodule

