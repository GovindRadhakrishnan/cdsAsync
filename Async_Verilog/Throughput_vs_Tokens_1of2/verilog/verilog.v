module Throughput_vs_Tokens_1of2(Tx, Txe, Rx, Rxe,
                                  RESET, VDD, GND);
inout VDD, GND;
output RESET;
output [1:0] Tx;
input Txe;
input [1:0] Rx;
output Rxe;
////////////////////////////////////////////////////////////////////////////////
// All parameters can be overridden using CDF variables
parameter RST_HOLD=1000;
parameter FILE_OUT="Throughput_vs_Tokens.csv";
parameter FILE_TMP="TvT_tmp.csv";
parameter D1=0;			  // Delay param - Forward latency up
parameter D2=0;			  // Delay param - Forward latency down
parameter MAX_TOKENS=30;  // Static slack of the pipeline being measured
parameter SS_TOKENS=30;   // # tokens used to maintain steady state
parameter START_TOKENS=1; // # tokens to start measuring with
parameter INC_TOKENS=1;   // # tokens to increment by for each point
parameter FINISH=0;       // If 1, end the simulation when this module completes
////////////////////////////////////////////////////////////////////////////////
integer resultsFile, tmpFile;
real thru_measure_start;  // Throughput measure start time
real thru_measure_end;    // Throughput measure end time
real throughput;          // Throughput result

integer RxTokenCount;
integer Tokens2Tx;
reg allTokensRxd;
reg RxdTokReg; 
reg absorbAllReg;
////////////////////////////////////////////////
reg resetReg;
reg goReg;
reg RxEnReg;
reg TxReg;

reg RxReg;
wire dataRx;
wire validRx;
////////////////////////////////////////////////
Bin2QDI_1of2          Transmit (Tx,     TxReg,   goReg,   Txe,   resetReg, VDD, GND);
QDI2Bin_RxEnable_1of2 Receive  (dataRx, validRx, RxEnReg, Rxe,   Rx,  resetReg, VDD, GND);
assign RESET = resetReg;
////////////////////////////////////////////////
task Reset;
    begin
        #1; /* Allow initial and final conditions to be interchangable
	    (Not interchangeable if sim starts with reset asserted...)  */
        $display("%M: %t ps  Asserting Reset...", $time); 
        resetReg <= 1'b0;
        RxEnReg <= 1'b1;
        #RST_HOLD;
        $display("%M: %t ps - De-asserting Reset...", $time); 
        resetReg <= 1'b1;
        #RST_HOLD;
        RxTokenCount = 0;
    end
endtask 

task Init;
    begin
        RxTokenCount = 0;
        Tokens2Tx = START_TOKENS;

        resetReg  <= 1'b1;
        goReg     <= 1'b0;
        RxEnReg   <= 1'b0;
        TxReg     <= 1'b1;
        RxReg     <= 1'b0;
        RxdTokReg <= 1'b0;
        allTokensRxd <= 1'b0;
        absorbAllReg <= 1'b0;

        resultsFile = $fopen(FILE_OUT, "w");
        $fdisplay(resultsFile, "#Tokens, Throughput [MHz]");
        $fclose(resultsFile);

        tmpFile = $fopen(FILE_TMP, "w");
        $fdisplay(tmpFile, "#Tokens, Current Throughput [MHz], Time last Token was Rx'd [ps]");
        $fclose(tmpFile);
    end
endtask

task SendTokens;
    input data;
    input isRandom;
    integer isRandom;
    integer currTokenNo;
    begin
        currTokenNo=0;
        while(currTokenNo < Tokens2Tx) begin
            wait(Txe); 
            TxReg <= (isRandom) ? $random() : data;
            goReg <= #D1 1'b1;
            wait(|Tx);
            currTokenNo=currTokenNo+1;
            $strobe("%M: %t ps - Sent token %d, data = %b.", $time, currTokenNo, TxReg);
            wait(~goReg);
        end
    end
endtask

/* Send a token while simultaneously receiving a token
* so current token count is maintained in the pipeline */
task MaintainTokens;
    input data;
    input isRandom;
    integer isRandom;
    integer currTokenNo;
    begin
        $display("%M: %t ps - Maintaining SS tokens", $time);
        currTokenNo=0;
        while(currTokenNo < SS_TOKENS) begin
            fork
                wait(validRx);
                wait(Txe);
            join
            TxReg <= (isRandom) ? $random() : data;
            goReg <= #D1 1'b1;
            wait(|Tx);        // Make sure token is sent
            currTokenNo=currTokenNo+1;
            $display("%M: %t ps - Sent token %d of %d, data = %b.", $time, currTokenNo, SS_TOKENS, TxReg);
            wait(~goReg);     // Tx Acknowledge Received
      		RxEnReg <= 1'b1;  // Okay to Acknowledge the Rx token now
		    wait(RxdTokReg);
            wait(~RxdTokReg);
        end  // end while
    end // end begin
endtask
task AbsorbTokens;
    begin
        absorbAllReg <= 1'b1;
        RxEnReg <= 1'b1;
        wait(allTokensRxd);
        allTokensRxd <= 1'b0;
        absorbAllReg <= 1'b0;
        RxEnReg <= 1'b0;
    end
endtask

// Send, Maintain, and Absorb Tokens
task SMATokens; 
    input data;
    input isRandom;
    integer isRandom;
    begin
        SendTokens(data, isRandom);
        MaintainTokens(data, isRandom);
        AbsorbTokens;
    end
endtask 

////////////////////////////////////////////////
// Main Description 
////////////////////////////////////////////////
initial begin
    Init;
    Reset;
    while (Tokens2Tx < MAX_TOKENS) begin
        SMATokens(1'b1, 0);    // 0 = Send the value, 1 = Send Random Data
        Tokens2Tx = Tokens2Tx + INC_TOKENS;
        #RST_HOLD;
    end
    if (FINISH) begin
        #RST_HOLD;
        $finish();
    end
end


////////////////////////////////////////////////
// Main Receiver Description 
////////////////////////////////////////////////
always @(posedge validRx) begin
    RxTokenCount=RxTokenCount+1;
    if (RxTokenCount==1) begin
        thru_measure_start=$time;
    end 

    /* Output note to temporary file whenever token is received */
    if((RxTokenCount>1) && (RxTokenCount < SS_TOKENS-1)) begin
        thru_measure_end=$time;
        throughput = 1.0e6/((thru_measure_end - thru_measure_start) / (RxTokenCount-1));
        tmpFile = $fopen(FILE_TMP, "a");
        $fdisplay(tmpFile, "%d, %g, %t", Tokens2Tx, throughput, thru_measure_end);
        $fclose(tmpFile);
    end

    if (RxTokenCount==SS_TOKENS-1) begin
        thru_measure_end=$time;
        /* 
         * Measuring over 4 tokens, the average period is:
         * ((RxTime1-RxTime0) + (RxTime2-RxTime1) + (RxTime3-TxTime2)) / 3
         * which simplifies to (RxTime3-RxTime0)/3.
         */
        throughput = 1.0e6/((thru_measure_end - thru_measure_start) / (RxTokenCount-1));
        resultsFile = $fopen(FILE_OUT, "a");
        $fdisplay(resultsFile, "%d, %g",Tokens2Tx, throughput);
        $fclose(resultsFile);     
        $display("%M: Throughput=%g MHz with %d tokens in pipeline",throughput, Tokens2Tx);  
    end    
    wait(RxEnReg);
    RxReg <= dataRx;
    RxdTokReg <= 1'b1;

    $display("%M: %t ps - Received token %d, data = %b", $time, RxTokenCount, RxReg); 

    if (RxTokenCount == Tokens2Tx + SS_TOKENS) begin
        RxTokenCount = 0;
        allTokensRxd <= 1'b1;
    end
end
////////////////////////////////////////////////
always @(negedge Txe) begin
    goReg <= #D2 1'b0;
end
////////////////////////////////////////////////
always @(negedge validRx) begin
    RxdTokReg <= 1'b0;
    if (~absorbAllReg) begin
        RxEnReg <= 1'b0;
    end
end

endmodule