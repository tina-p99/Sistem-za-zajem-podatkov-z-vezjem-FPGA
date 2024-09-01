
`timescale 1ns/1ps
`default_nettype none

module write_control
	(
	input  wire         clk,
	input  wire         rst,
	input  wire         wr_en,
	input  wire         new_data,
	input  wire[31:0]   trig,
	input  wire [11:0]  data_in,
	output reg [63:0]	data_out,
	output reg 			write_fifo_en,
	output reg 			write_SRAM_en,
	output reg 			write_end

    );

//vpis podatkov
localparam WRITE_DATA_NUMBER = 13312; 

//signali za vpisovanje podatkov iz AD v SRAM

reg [31:0]  wr_counter = 0; 
integer     time_stamp = 0; 
integer     data_num = 0; 
reg 		_new_data; 
reg [15:0]  xadc_out_old;


integer state = 0;
localparam idle  = 0,
           trigger = 10,
           write = 11,
           wr_end = 12;

//ob vsakem ciklu ure pove�amo �asovni �ig
always @(posedge clk) begin
    if (rst) begin
        time_stamp <= 0; 
    end else begin
        time_stamp <= time_stamp + 1;
    end
end 

//pripravi podatke za vpis
always @(posedge clk) begin
    if (rst) begin
        data_out <= 63'd0; 
        write_fifo_en <= 0;
        data_num <= 0; 
        write_end <= 31'h00000000; 
        write_SRAM_en <= 0;
        wr_counter <= 0;
    end
    
    //ob vsakem ciklu ure shranimo stare vrednosti 
    _new_data <= new_data;  //signala ki sporoča kdaj pridejo novi podatki iz ADC
    xadc_out_old <= data_in;   //stare vrednosti iz ADC
    
    write_fifo_en <= 0;
    write_SRAM_en <= 0;
     
    case (state)
    //v neaktivnem stanju čakamo na pobudo uporabnika za začetek zapisa 
    //signal write_pred novim zapisom nastavimo na 0
    idle: begin
        if (wr_en) begin
                state <= trigger; 
            end else begin
            write_end <= 31'h00000000; 
        end
    end
    
    //v stanju trigger čakamo da izhodni podatki AD doseželjo željeno vrednost triggerja
    trigger: begin
        if((data_in >= trig && xadc_out_old < trig) || (data_in <= trig && xadc_out_old > trig)) begin
            state <= write;
        end
    end

    //vpišemo 13000 podatkov iz AD pretvornika z vpisi v fifo
    //na vsake 4 fifo vpise sprožimo vpis v SRAM
    write: begin
        if(data_num < WRITE_DATA_NUMBER) begin
            if (new_data == 1 && _new_data == 0) begin 
                data_out <= {time_stamp, {20'h00000, data_in}}; 
                write_fifo_en <= 1;
                data_num <= data_num + 1;
                if (wr_counter < 3) begin
                    wr_counter <= wr_counter + 1;
                 end 
                 else begin
                    wr_counter <= 0;
                    write_SRAM_en <= 1; 
                 end
            end 
        end else begin
            state <= wr_end; 
            end
    end
    
    //po koncu vpisa sporočimo s signaom write_end da je vpis končan
    //ko je tudi s strani programa potrjen konec vpisa z signalom wr_en lahko preidemo v nekativno stanje in čakamo na nov vpis
    wr_end: begin
        write_end <= 31'h00000001;
        data_num <= 0;
        if(wr_en == 0) begin
            state <= idle; 
        end
    end
    
    endcase
end


endmodule
`default_nettype wire
