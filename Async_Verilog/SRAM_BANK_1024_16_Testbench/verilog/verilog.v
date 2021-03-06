//Verilog HDL for "Verilog", "BER_Testbench" "verilog"
module SRAM_BANK_1024_16_Testbench(A, Ae, RW, RWe, 
				               WriteData, WriteDataEn, 
				               ReadData,  ReadDataEn, 
 			 	               BitErrors, RESET, VDD,  VSS);
inout VDD, VSS;
input [7:0] WriteDataEn;
input [31:0] ReadData;
input RWe;
input [4:0] Ae;

output [19:0] A;
output [1:0] RW;
output [31:0] WriteData;
output [7:0] ReadDataEn;
output [15:0] BitErrors;
output RESET;

////////////////////////////////////////////////
// Parameters
////////////////////////////////////////////////
parameter RST_HOLD=1000;
parameter OP_WAIT=1000;

// Must be multiple of 2 or need to
// manually add Bin2QDI_1of2 Decoder
localparam DW=16;  // Data Bus Width [Binary]
localparam AW=10;  // Address Bus Width [Binary]
////////////////////////////////////////////////
//  Registers driving output & output decoders
////////////////////////////////////////////////
reg RESET;
reg [DW-1:0] BitErrorReg;
reg [AW-1:0] AddrReg;
reg [DW-1:0] WriteDataReg;
reg goCTL;
reg goCTLW;
reg RWReg;

////////////////////////////////////////////////
//  Registers storing data from input encoders
////////////////////////////////////////////////
reg  [DW-1:0] ReadDataReg;
wire [DW-1:0] dataRx;
wire [(DW/2)-1:0] readDataValid;

reg [DW-1:0] lastDataWritten;
reg DataWasRead;

/////////////////////////////////////////////////////////////////////////////////////////////////
// Output Decoders / Input Encoders
/////////////////////////////////////////////////////////////////////////////////////////////////
  Bin2QDI_1of2          RWDecoder                  (RW,        RWReg,         goCTL,      RWe,         RESET, VDD, VSS);  
  Bin2QDI_1of4          AddrDecoder  [(AW/2)-1:0]  (A,         AddrReg,       goCTL,      Ae,          RESET, VDD, VSS);
  Bin2QDI_1of4          WriteDecoder [(DW/2)-1:0]  (WriteData, WriteDataReg,  goCTLW,     WriteDataEn, RESET, VDD, VSS); 
  QDI2Bin_1of4          ReadEncoder  [(DW/2)-1:0]  (dataRx,    readDataValid, ReadDataEn, ReadData,    RESET, VDD, VSS);

////////////////////////////////////////
//     TB Task Definitions
////////////////////////////////////////
task BankWrite;
    input [AW-1:0] address;
    input [DW-1:0] data;
    begin
        $display("Testbench: %t ps - Writing 0x%h to address 0x%h...", $time, data, address);  
        RWReg        <= 1'b0;
        AddrReg      <= address;
        WriteDataReg <= data;
        goCTL        <= 1'b1;
        goCTLW       <= 1'b1;
        BitErrorReg  <= 16'b0;  
        fork
            wait(~|WriteDataEn);    
            wait(~RWe);
			wait(~|Ae);
        join
		lastDataWritten <= data;
		goCTL           <= 1'b0;
		goCTLW	      	<= 1'b0;
        fork
            wait(&Ae);
            wait(RWe);
			wait(&WriteDataEn);
        join
        $display("Testbench: %t ps - Write submission complete", $time);
    end
endtask

task BankRead;
    input [AW-1:0] address;
    input [DW-1:0] expectData;
    begin
        $display("Testbench: %t ps -  Reading address 0x%h...",$time, address);
        BitErrorReg <= {DW{1'b0}};  
        RWReg       <= 1'b1;
        AddrReg     <= address;
        goCTL       <= 1'b1;
        DataWasRead <= 1'b0;
        fork
            wait(~RWe);
			wait(~|Ae);
        join
        goCTL <= 1'b0;
        fork
            begin
                wait(DataWasRead);
	            BitErrorReg <= ReadDataReg^expectData;
			end
		    wait(RWe);
            wait(&ReadDataEn);  
  		join
  end
endtask

task Reset;
    begin
        #1; // Allow initial and final conditions to be interchangable
        $display("Testbench:  %t ps - Asserting Reset...", $time); 
        RESET <= 1'b0;
    	#RST_HOLD;
        $display("Testbench:  %t ps - De-Asserting Reset...", $time); 
    	RESET <= 1'b1;
    	#RST_HOLD;  
    end
endtask

task Init;
    begin
        RESET     		    <= 1'b1;
        goCTL        		<= 1'b0;
        goCTLW       		<= 1'b0;
        RWReg        		<= 1'b0;
        AddrReg      		<= {AW{1'b0}};
        BitErrorReg       	<= {DW{1'b0}};
        ReadDataReg      	<= {DW{1'b0}};
        WriteDataReg 	   	<= {DW{1'b0}};
		lastDataWritten 	<= {DW{1'b0}};
    end
endtask

/////////////////////////////////////////////////////////////////////////////////////
//	Main Description
/////////////////////////////////////////////////////////////////////////////////////
initial begin
    Init;
    Reset;
    BankRead ({AW{1'b0}}, lastDataWritten); #OP_WAIT;  // Read Address0, expect to read all zeros;
    BankWrite({AW{1'b0}}, 16'hFFFF);  	    #OP_WAIT;
    BankRead({AW{1'b0}},  lastDataWritten); #OP_WAIT;  
    BankWrite({AW{1'b0}}, 16'h0000); 	    #OP_WAIT; 
    BankRead({AW{1'b0}},  lastDataWritten); #OP_WAIT;
    #RST_HOLD;   
    $finish;  
end

////////////////////////////////////////
//   Rx Always Blocks
////////////////////////////////////////
always @(posedge &readDataValid) begin
     ReadDataReg <= dataRx;
     $display("Testbench: %t ps - Read data 0x%h", $time, dataRx);
	if (^dataRx == 1'bx) begin
	    $display("Testbench: %t ps - Invalid Data 0x%h.", $time, dataRx);
	end
    DataWasRead <= 1'b1;
end
endmodule
