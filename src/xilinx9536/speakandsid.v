`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: Speak&SID CPC 
// Engineer: Michael Wessel
// 
// Create Date:    03/11/2019 
// Design Name: 
// Module Name:    Main 
// Target Devices: XC9536 15PC44 
// Tool versions: Xilinx WebPACK ISE 
// Description: 
//
// Dependencies: 
//
// Revision: 
// Revision 0.01 - File Created
// Additional Comments: 
//
//////////////////////////////////////////////////////////////////////////////////
module Main(

	iCPC_CLOCK, 
	oSID_CLOCK, 

	/// from CPC: 
	iIORQ,
	iRD,
	iWR,
	
	iADR,
	ioCPC_DATA, 
	ioATMEGA_DATA, 
	
	// CPC IOReq Write to FBEE or FBFE or FFxx
	oSPEECH_WRITE, 
	oSPEECH_READ, 
	oSID_RW,
	oSID_CS,
	
	// from ATMega Ctrl Lines
	iSID_ON, 
	iCPLD_STORE, 
	// signal when command loop accepts input again -> READY SIGNAL from ATMEGA
	iATMEGA_READY 
	
);


input [15:0] iADR; 
input iIORQ; 
input iRD; 
input iWR; 

input iATMEGA_READY; 

input iCPLD_STORE; 
input iSID_ON;  

output oSPEECH_WRITE; 
output oSPEECH_READ; 

output oSID_RW; 
output oSID_CS;

inout [7:0] ioCPC_DATA; 
inout [7:0] ioATMEGA_DATA;
reg   [7:0] cpc_data;
reg   [7:0] atmega_data;

wire iorq = ~ iIORQ; 
wire iord = ~ iRD; 
wire iowr = ~ iWR; 

wire read  = iorq & iord; 
wire write = iorq & iowr; 

//
//
// 

// FAEE / FBEE
wire ssa1_adr    = ! iADR[0] & ! iADR[4] &  iADR[5] & iADR[6] &            ! iADR[10] ; 

// FBDE & READ 
wire status_read  = ! iADR[0] &             ! iADR[5] & iADR[6] &  iADR[8] & ! iADR[10] & read ; 

// FAC0 - FADF 
wire sid_adr  =  !  iADR[5] &  iADR[6] & ! iADR[8] & ! iADR[10] ;

//
//
// 

output reg oSID_CLOCK = 1; 

wire oSPEECH_READ    = ssa1_adr & read ; 		
wire oSPEECH_WRITE   = ssa1_adr & write; 								

assign oSID_RW        = ~ ( iSID_ON & sid_adr  & write           ) ; 								
assign oSID_CS        = ~ ( iSID_ON & sid_adr  & ( read | write) ) ; 															  

//
// logic 
//

input iCPC_CLOCK;
reg int_clock = 0;

always @(posedge oSPEECH_WRITE) 
begin
	cpc_data <= ioCPC_DATA;
end

always @(posedge iCPLD_STORE ) 
begin
	atmega_data <= ioATMEGA_DATA;
end

always @(negedge iCPC_CLOCK ) 
begin
	int_clock <= ~ int_clock; 
end

always @(posedge int_clock ) 
begin
	oSID_CLOCK <= ~ oSID_CLOCK; 
end

assign ioATMEGA_DATA = oSPEECH_WRITE ? cpc_data : 8'bz; 

assign ioCPC_DATA  = ( oSPEECH_READ | status_read) ? (status_read ? iATMEGA_READY : atmega_data ) : 8'bz ; 

endmodule



