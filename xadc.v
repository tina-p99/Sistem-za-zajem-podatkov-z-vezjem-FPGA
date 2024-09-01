`timescale 1ns / 1ps

module XADC_capture(
   input clk,
   input rst,
   //pini za vhodno analogno napetost
   input vp_in,
   input vn_in,
   //izhoda AD pretvornika
   output [11:0] xadc_out,
   output [11:0] temp_out,
   //signal ki sporoèa nov podatek iz ADC
   output new_data
   );
   
   wire enable;
   wire ready;
   wire [15:0] data;            //signal za branje iz DRP
   reg [6:0] Address_in = 0;    //naslov za DRP 
   reg [11:0] xadc_data = 0;    //registra za shranjevanje izhodnih vrednosti ADC
   reg [11:0] temp_data = 0;
   reg _ready = 0;              //signal ki sporoèa, kdaj so novi podatki iz ADC pripravljeni za branje 
   wire busy;                   //signal ki sporoèa da je ADC zaseden
   wire channel_out;            //signal ki sporoèa kateri vhod se pretvarja v ADC
   wire eos;                    //signal ob koncu zajema vseh kanalov ADC
    
//xadc instantiation connect the eoc_out .den_in to get continuous conversion

    xadc_wiz_0 xadc(
          .daddr_in(Address_in),        // Address bus for the dynamic reconfiguration port
          .dclk_in(clk),                // Clock input for the dynamic reconfiguration port
          .den_in(enable),              // Enable Signal for the dynamic reconfiguration port
          .di_in(0),                    // Input data bus for the dynamic reconfiguration port
          .dwe_in(0),                   // Write Enable for the dynamic reconfiguration port
          .reset_in(0),                 // Reset signal for the System Monitor control logic
          .busy_out(busy),              // ADC Busy signal
          .channel_out(channel_out),    // Channel Selection Outputs
          .do_out(data),                // Output data bus for dynamic reconfiguration port
          .drdy_out(ready),             // Data ready signal for the dynamic reconfiguration port
          .eoc_out(enable),             // End of Conversion Signal
          .eos_out(eos),                // End of Sequence Signal
          .ot_out(),                    // Over-Temperature alarm output
          .vccaux_alarm_out(),          // VCCAUX-sensor alarm output
          .vccint_alarm_out(),          //  VCCINT-sensor alarm output
          .user_temp_alarm_out(),       // Temperature-sensor alarm output
          .alarm_out(),                 // OR'ed output of all the Alarms    
          .vp_in(vp_in),               // Dedicated Analog Input Pair
          .vn_in(vn_in));
          
integer state = 0;
localparam s_idle  = 0,
           temp_rd = 10,
           adc_rd = 11;
           
assign xadc_out = xadc_data;
assign temp_out = temp_data;
assign new_data = eos;
 
 always @(posedge clk) begin    
 if(rst)begin
    temp_data <= 0; 
    xadc_data <= 0;
    Address_in <= 0; 
    state <= 0; 
    
 end
 
    _ready <= ready;
       
    case (state)
                s_idle: begin
                    state <= temp_rd;
                end
                
                //ob vsaki pretvorbi preberemo vrednost temperature in vhodne analogne napetosti zaporedno 
                
                temp_rd: begin
                    if(ready == 1 && _ready == 0) begin
                        temp_data <= data[15:4];
                        Address_in <= 7'h03; //naslov za Vp/Vn kanal 
                        state <= adc_rd;
                    end
                    else begin
                    state <= temp_rd;
                    end
                end
    
                adc_rd: begin
                    if(ready == 1 && _ready == 0) begin
                        xadc_data <= data[15:4];
                        Address_in <= 7'h00; //naslov za temp kanal
                        state <= temp_rd;
                    end
                    else begin
                    state <= adc_rd;
                    end
                end
         endcase
    end
  


endmodule
