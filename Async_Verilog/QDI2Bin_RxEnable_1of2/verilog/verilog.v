////////////////////////////////////////////////////////////
// Uses e1of2 DI encoded input from a QDI circuit
// to communicate with verilog parent module.
// Added rxe for use with Throughput_vs_Tokens module.
////////////////////////////////////////////////////////////

module QDI2Bin_RxEnable_1of2(dout, valid, rxe, Le, L, RESET, VDD, GND);

output      dout;   // signal to verilog 1-bit binary encoded output
output      valid;  // signal to verilog when circuit input is valid
input       rxe;    // Rx Enabled from verilog - must be high for Le to fall low
output      Le;     // Left enabLe to circuit  - falls low when valid data present
input [1:0] L;      // Left input from circuit - e1of4 DI encoded 
input RESET;
inout VDD, GND;

////////////////////////////////////////////////////////////
//     Registers Driving Output
////////////////////////////////////////////////////////////
reg dout, valid, Le;
parameter D1 = 0; // Delay 1 - Backward latency up
parameter D2 = 0; // Delay 2 - Backward latency down

////////////////////////////////////////////////////////////
//	Main Description
////////////////////////////////////////////////////////////
initial begin
    dout   <= 1'bz;
    valid  <= 1'b0;
    Le     <= 1'b1;
end

always @(negedge RESET) begin
    Le    <= #D2 1'b0;
    valid <= 1'b0;
    dout  <= 1'bz;
end

always @(posedge RESET) begin
    Le    <= #D1 1'b1;
    valid <= 1'b0;
    dout  <= 1'bz;
end

always @(negedge |L) begin
    valid  <= 1'b0;
    Le     <= #D1 1'b1;
end

always @(posedge |L) begin
    valid <= 1'b1;
    wait(rxe);
    case (L)
        2'b01: dout <= 1'b0;
        2'b10: dout <= 1'b1;
        2'b0x: dout <= 1'b0;   // Avoid error message @ STV's
        2'bx0: dout <= 1'b1;   // Avoid error message @ STV's
	    default begin
	       $display("QDI2Bin1of2: Received invalid DI code from circuit: %b. Check for errors @time %t ps", L, $time);
	       dout <= 1'bx;
	    end
    endcase
    Le    <= #D2 1'b0;
end

endmodule
////////////////////////////////////////////////////////////
