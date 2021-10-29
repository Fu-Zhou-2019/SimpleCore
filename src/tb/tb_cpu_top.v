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
        pc_rtvec = `PC_SIZE'h0000_0080;
        #30 rst_n = 1;
        @(posedge clk)
        #8000 $finish;
    end 
    reg[31:0] instr_in;
    integer i;
    integer test_file;
    initial begin
        test_file = $fopen("C:\\Users\\wen\\Desktop\\test_insr\\rv32ui-p-lb","rb");
        for(i=0; i<5000; i=i+1) begin
            if($fread(instr_in, test_file)) begin
                $display(instr_in);
                if(i==240) begin
                $display(instr_in);
                end
                u_cpu_top.u_srams.u_itcm_ram.u_itcm_gnrl_ram.mem_r[i] =  {instr_in[7:0],instr_in[15:8],instr_in[23:16],instr_in[31:24]};
                u_cpu_top.u_srams.u_dtcm_ram.u_dtcm_gnrl_ram.mem_r[i] =  {instr_in[7:0],instr_in[15:8],instr_in[23:16],instr_in[31:24]};
            end
            else begin
                u_cpu_top.u_srams.u_itcm_ram.u_itcm_gnrl_ram.mem_r[i] <= 32'd0;
                u_cpu_top.u_srams.u_dtcm_ram.u_dtcm_gnrl_ram.mem_r[i] <= 32'd0;
            end
        end
        $fclose(test_file);
    end
    
    initial clk = 0;
    always #5 clk = ~clk; 
    
    integer j;
    initial begin
       for(j=0; j<3500; j=j+1) begin
            u_cpu_top.u_srams.u_dtcm_ram.u_dtcm_gnrl_ram.mem_r[j] = 32'd1;//0x0001
          end 
       end

endmodule
