// =====================================
//Simulation model of SRAM
//Author:     HuRui
//Modules:    sim_ram
//assume legal address
//=====================================

module sim_ram#(
    parameter DP = 512,//depth
    parameter DW = 32,//data width
    parameter MW= 4,//mask width
    parameter AW = 32,//address width
    parameter FORCE_X2ZERO = 0,
    parameter ITCM = 0,//instantiate as ITCM RAM
    parameter DTCM = 0 //instantiate as DTCM RAM
) (
    input  clk,
    input[DW-1:0] din,
    input[AW-1:0] addr,
    input we,
    input[MW-1:0] wem,//write enable mask
    output[DW-1:0] dout
);
    reg [DW-1:0] mem_r[0:DP-1];
    reg [AW-1:0] addr_r;
    wire [MW-1:0] wen;
    wire ren;
    wire [DW-1:0] dout_pre;
    integer j;

    assign ren = ~we;
    assign wen = ({MW{we}} & wem);

    //the output will holdup
    always @(posedge clk ) begin
        if(ren) begin
            addr_r <= addr;
        end
    end
  
    genvar i;
    generate
        for(i = 0; i<MW; i = i + 1) begin
            if((8*i+8) > DW) begin
                always @(posedge clk) begin
                    if (wen[i]) begin
                        mem_r[addr][DW-1:8*i] <= din[DW-1:8*i];
                    end
                end
            end
            else begin
                always @(posedge clk) begin
                    if (wen[i]) begin
                        mem_r[addr][8*i+7:8*i] <= din[8*i+7:8*i];
                    end
                end
            end
        end
    endgenerate
    
    assign dout = mem_r[addr_r];
        
    generate
        if(FORCE_X2ZERO == 1) begin: force_x_to_zero
          for (i = 0; i < DW; i = i+1) begin:force_x_gen 
              `ifndef SYNTHESIS//{
             assign dout[i] = (dout_pre[i] === 1'bx) ? 1'b0 : dout_pre[i];
              `else//}{
             assign dout[i] = dout_pre[i];
              `endif//}
          end
        end
        else begin:no_force_x_to_zero
         assign dout = dout_pre;
        end
    endgenerate
            
    /*
    initial begin
        if (ITCM==1) begin
            mem_r[1] = 32'b0000000_00000_00000_000_00001_011_0111;//lui x1, 0x0000_0000
            mem_r[2] = 32'b0000000_00100_00001_010_00001_000_0011;//lw x1, 0x1234_5678
            mem_r[3] = 32'b0000000_00000_00000_000_00100_011_0111;//lui x4, 0
            mem_r[4] = 32'b0000000_00001_00100_000_01000_010_0011;//sb x4, x1, 8
            mem_r[5] = 32'b0000000_00001_00100_001_01000_010_0011;//sh x4, x1, 8
            mem_r[6] = 32'b0000000_00001_00100_010_01000_010_0011;//sw x4, x1, 8
        end
    end
    
   initial begin
       if (DTCM==1) begin 
           mem_r[0] = 32'd1;//0x0001
           mem_r[1] = 32'h1234_5678;
           mem_r[2] = 32'b00000000_00000000_00000001_00000001;//0x0011
           mem_r[3] = 32'b00000001_00000001_00000001_00000001;//0x1111
       end
   end
   */
endmodule

