`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: lirmm
// Engineer: ali ait hassou
// 
// Create Date: 26/11/2025 06:19:48 PM
// Design Name: mram controller
// Module Name: mram_controller
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


module mram_controller(
// sys interface
input  logic        sys_clk,
input  logic        sys_rst,

// data interface
input  logic [15:0] wdata,
input  logic [21:0] addr_i,
input  logic        we,  
output logic [15:0] rdata,


// memory interface check as3004316 datasheet
output logic        e,
output logic        g,
output logic        w,
output logic [21:0] addr,
output logic        ub,
output logic        lb,
output logic [15:0] data_out,
output logic [15:0] data_in
    );
    // fsm for write & read & signal control
    
endmodule
