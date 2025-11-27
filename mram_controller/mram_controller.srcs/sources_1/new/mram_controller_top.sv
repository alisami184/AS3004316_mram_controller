`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: ali ait hassou
// 
// Create Date: 11/27/2025 10:59:02 AM
// Design Name: 
// Module Name: mram_controller_top
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module mram_controller_top(

    );
    
    

    mram_controller #(
        .CLK_FREQ_MHZ(CLK_FREQ_MHZ)
    ) dut (
        .clk(clk),
        .rst(rst),
        .wdata(wdata),
        .addr_in(addr_in),
        .write_req(write_req),
        .read_req(read_req),
        .write_done(write_done),
        .read_done(read_done),
        .rdata(rdata),
        .e_n(e_n),
        .w_n(w_n),
        .g_n(g_n),
        .addr(addr),
        .ub_n(ub_n),
        .lb_n(lb_n),
        .dq(dq)
    );
endmodule
