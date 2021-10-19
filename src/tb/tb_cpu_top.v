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
    reg[31:0] instr_in;
    integer i;
    integer test_file;
    initial begin
        test_file = $fopen("C:\\Users\\wen\\Desktop\\cpu\\SimpleCore\\test_instr\\test_insr\\rv32ui-p-and.bin","rb");
        for(i=0; i<32769; i=i+1) begin
            $display("%h", instr_in);
            if($fread(instr_in, test_file))
                u_cpu_top.u_srams.u_itcm_ram.u_itcm_gnrl_ram.mem_r[i] <= {instr_in[7:0],instr_in[15:8],instr_in[23:16],instr_in[31:24]};           
            else
                u_cpu_top.u_srams.u_itcm_ram.u_itcm_gnrl_ram.mem_r[i] <= 32'd0;
        end
        $fclose(test_file);
    end
    
    initial begin
        rst_n = 0;
        pc_rtvec =32'h00000000;
        #35 rst_n = 1;
        @(posedge clk)
        #50000 $finish;
    end 
    
    initial clk = 0;
    always #5 clk = ~clk; 
endmodule

