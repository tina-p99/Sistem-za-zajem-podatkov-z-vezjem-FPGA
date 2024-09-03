//---------------------------------------------------------------------------------
// ddr3_test.v
//
// This function transfers data from the input buffer to the Memory Interface
// Generator (MIG). Additionally, it can retrieve data from the MIG and store it
// in the output buffer.
//
//---------------------------------------------------------------------------------
// Copyright (c) 2023 Opal Kelly Incorporated
// 
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.
//---------------------------------------------------------------------------------


`timescale 1ns/1ps
`default_nettype none

module MIG_inter
	(
	input  wire          clk,
	input  wire          reset,
	input  wire          writes_en,
	input  wire          reads_en,
	input  wire          calib_done,
	//podatki za branje podatkov iz vhodnega fifo - input buffer
	output reg           ib_re,
	input  wire [255:0]  ib_data,
	input  wire [7:0]    ib_count,
	input  wire          ib_valid,
	input  wire          ib_empty,
	//podatki za vpisovanje podatkov v izhodni fifo - output buffer
	output reg           ob_we,
	output reg  [255:0]  ob_data,
	input  wire [6:0]    ob_count,
	input  wire          ob_full,
	
	//signali za interakcijo z MIG
	input  wire          app_rdy,
	output reg           app_en,
	output reg  [2:0]    app_cmd,
	output reg  [29:0]   app_addr,
	
	input  wire [255:0]  app_rd_data,
	input  wire          app_rd_data_end,
	input  wire          app_rd_data_valid,
	
	input  wire          app_wdf_rdy,
	output reg           app_wdf_wren,
	output reg  [255:0]  app_wdf_data,
	output reg           app_wdf_end,
	output wire [31:0]   app_wdf_mask
	);

localparam FIFO_SIZE           = 128;
localparam BURST_UI_WORD_COUNT = 2'd1;
localparam ADDRESS_INCREMENT   = 5'd8; //naslove poveèujemo za 8

//naslovi za branje in pisanje 
reg  [29:0] cmd_byte_addr_wr;
reg  [29:0] cmd_byte_addr_rd;

//signal za štetje podatkov v burstu
reg  [1:0]  burst_count;

//signali za branje/pisanje
reg         write_mode;
reg         read_mode;

reg         reset_d;

assign app_wdf_mask = 16'h0000;

always @(posedge clk) write_mode <= writes_en;
always @(posedge clk) read_mode <= reads_en;
always @(posedge clk) reset_d <= reset;


integer state;
localparam s_idle    = 0,
           s_write_0 = 10,
           s_write_1 = 11,
           s_write_2 = 12,
           s_write_3 = 13,
           s_write_4 = 14,
           s_read_0  = 20,
           s_read_1  = 21,
           s_read_2  = 22,
           s_read_3  = 23,
           s_read_4  = 24;
           
always @(posedge clk) begin
	if (reset_d) begin
		state             <= s_idle;
		burst_count       <= 2'b00;
		cmd_byte_addr_wr  <= 0;
		cmd_byte_addr_rd  <= 0;
		app_en            <= 1'b0;
		app_cmd           <= 3'b0;
		app_addr          <= 28'b0;
		app_wdf_wren      <= 1'b0;
		app_wdf_end       <= 1'b0;
	end else begin
		app_en            <= 1'b0;
		app_wdf_wren      <= 1'b0;
		app_wdf_end       <= 1'b0;
		ib_re             <= 1'b0;
		ob_we             <= 1'b0;


		case (state)
			s_idle: begin
				burst_count <= BURST_UI_WORD_COUNT-1;
				// cikel vpisovanja v SRAM se lahko zaène le èe je inicializacija SRAMa konèana in je dovolj podatkov v vhodnem FIFO
				if (calib_done==1 && write_mode==1 && (ib_count >= BURST_UI_WORD_COUNT)) begin
					app_addr <= cmd_byte_addr_wr;
					state <= s_write_0;
					// cikel branja  iz SRAM se lahko zaène le èe je inicializacija SRAMa konèana in je dovolj prostora v izhodnem FIFO
				end else if (calib_done==1 && read_mode==1 && (ob_count<(FIFO_SIZE-2-BURST_UI_WORD_COUNT) ) ) begin
					app_addr <= cmd_byte_addr_rd;
					state <= s_read_0;
				end
			end

			s_write_0: begin
				state <= s_write_1;
				ib_re <= 1'b1;      //vhodni fifo read enable
			end

			s_write_1: begin
				if(ib_valid==1) begin           //èe je prebran podatek veljaven
					app_wdf_data <= ib_data;   //nastavi vrednost za vpis v DDR
					state <= s_write_2;
				end
			end

			s_write_2: begin
				if (app_wdf_rdy == 1'b1) begin  //èe je SRAM pripravljen za prejem podatkov
					state <= s_write_3;
				end
			end

			s_write_3: begin
				app_wdf_wren <= 1'b1;           //omogoèimo pisanje v SRAM - write enable
				if (burst_count == 3'd0) begin
					app_wdf_end <= 1'b1;       // trenutni cikel ure je zadnji cikel vhodnih podatkov na app_wdf_data
				end
				if ( (app_wdf_rdy == 1'b1) & (burst_count == 3'd0) ) begin
					app_en    <= 1'b1;         //app enable omgoèi delovanje vmesnika
					app_cmd <= 3'b000;         //izbremeo operacijo pisanja 
					state <= s_write_4;
				end else if (app_wdf_rdy == 1'b1) begin 
					burst_count <= burst_count - 1'b1; 
					state <= s_write_0;
				end
			end

			s_write_4: begin
				if (app_rdy == 1'b1) begin           //MIG lahko sprejme ukaze
					cmd_byte_addr_wr <= cmd_byte_addr_wr + ADDRESS_INCREMENT;  //poveèamo naslov
					state <= s_idle;
				end else begin
					app_en    <= 1'b1;             //app enable omgoèi delovanje interfacea SRAM
					app_cmd <= 3'b000;             //izbremeo operacijo pisanja
				end
			end


			s_read_0: begin
				app_en    <= 1'b1;  //app enable omgoèi delovanje interfacea SRAM
				app_cmd <= 3'b001;  //izbremeo operacijo pisanja 
				state <= s_read_1;
			end

			s_read_1: begin
				if (app_rdy == 1'b1) begin  //MIG lahko sprejme ukaze
					cmd_byte_addr_rd <= cmd_byte_addr_rd + ADDRESS_INCREMENT;  //poveèamo naslov
					state <= s_read_2;
				end else begin
					app_en    <= 1'b1; //app enable omgoèi delovanje interfacea SRAM
					app_cmd <= 3'b001; //izbremeo operacijo pisanja
				end
			end

			s_read_2: begin
				if (app_rd_data_valid == 1'b1) begin     //oznaèuje, da je branje veljavno
					ob_data <= app_rd_data;              //prebrani podatek damo v fifo
					ob_we <= 1'b1;                       //output fifo write enable
					if (burst_count == 3'd0) begin
						state <= s_idle;
					end else begin
						burst_count <= burst_count - 1'b1; //zmanjšaj št. burstov
					end
				end
			end
		endcase
	end
end


endmodule
`default_nettype wire
