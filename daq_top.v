
`timescale 1ns/1ps
`default_nettype none

module daq_top (
    //povezava za FrontPanel
	input  wire [4:0]   okUH,
	output wire [2:0]   okHU,
	inout  wire [31:0]  okUHU,
	inout  wire         okAA,

    //ura
	input  wire         sys_clk_p,
	input  wire         sys_clk_n,
	
	//LED
	output wire [7:0]   led,
	
	//povezava za SRAM
	inout  wire [31:0]  ddr3_dq,
	output wire [14:0]  ddr3_addr,
	output wire [2 :0]  ddr3_ba,
	output wire [0 :0]  ddr3_ck_p,
	output wire [0 :0]  ddr3_ck_n,
	output wire [0 :0]  ddr3_cke,
	output wire         ddr3_cas_n,
	output wire         ddr3_ras_n,
	output wire         ddr3_we_n,
	output wire [0 :0]  ddr3_odt,
	output wire [3 :0]  ddr3_dm,
	inout  wire [3 :0]  ddr3_dqs_p,
	inout  wire [3 :0]  ddr3_dqs_n,
	output wire         ddr3_reset_n,
	
	//analogni vhod
	input  wire         vp_in,
	input  wire         vn_in
	);


localparam BLOCK_SIZE = 128; // 512 bytes / 4 bytes per word, 
localparam FIFO_SIZE = 1023; 
localparam BUFFER_HEADROOM = 20; // rezerva za FIFO

//vpis podatkov
//localparam WRITE_DATA_NUMBER = 13312; 


//prameter potreben za javljanje konèanja kalibracije
localparam CAPABILITY = 16'h0001;

//signali za interakcijo z MIG
wire          init_calib_complete;
reg           sys_rst;

wire [29 :0]  app_addr;
wire [2  :0]  app_cmd;
wire          app_en;
wire          app_rdy;
wire [255:0]  app_rd_data;
wire          app_rd_data_end;
wire          app_rd_data_valid;
wire [255:0]  app_wdf_data;
wire          app_wdf_end;
wire [31 :0]  app_wdf_mask;
wire          app_wdf_rdy;
wire          app_wdf_wren;

wire          clk;
wire          rst;


// signali za interakcijo z FrontPanelom
wire         okClk;
wire [112:0] okHE;
wire [64:0]  okEH;

wire [31:0]  ep00wire;
wire [31:0]  ep08wire;
wire [31:0]  ep10wire;
wire [31:0]  ep34wire;

//signali za interakcijo z FIFO
wire         pipe_in_read;
wire [255:0] pipe_in_data;
wire [7:0]   pipe_in_rd_count;
wire [9:0]   pipe_in_wr_count;
wire         pipe_in_valid;
wire         pipe_in_full;
wire         pipe_in_empty;

wire         pipe_out_write;
wire [255:0] pipe_out_data;
wire [9:0]   pipe_out_rd_count;
wire [6:0]   pipe_out_wr_count;
wire         pipe_out_full;
wire         pipe_out_empty;
reg          pipe_out_ready;

wire         pi0_ep_write;
wire         po0_ep_read;
wire [31:0]  pi0_ep_dataout;
wire [31:0]  po0_ep_datain;

//signali za vpisovanje podatkov iz AD v SRAM
wire [63:0]  data;  
wire         write_SRAM_en; 
wire         write_fifo_en;  

//xadc
wire [11:0] temp_out;
wire [11:0] xadc_out;
wire new_data; 
wire clk_52MHz; 
wire clk_50MHz; 

//Za doseganje prave vzorène frekvence za AD potrebujemo 26 MHz uro, ki jo generiramo z clocking wizardom
clk_wiz_0 clk_wiz_0(
  .clk_out1(clk_52MHz),
  .clk_out2(clk_50MHz),
  .reset(rst), 
  .clk_in1(clk));

//funkcija za prižiganje LED
function [7:0] xem7310_led;
input [7:0] a;
integer i;
begin
	for(i=0; i<8; i=i+1) begin: u
		xem7310_led[i] = (a[i]==1'b1) ? (1'b0) : (1'bz);
	end
end
endfunction

//ledice prižgemo ko je omogoèen prenos podakov na raèunalnik
//omogoèen zajem podatkov
//ko je možen vpis podatkov v SRAM in 
//ko je kalibracija zakljuèena
assign led = xem7310_led({4'hf,ep00wire[0],ep08wire[0],app_wdf_rdy,init_calib_complete});

//MIG reset
//MIG zajteva najmanj 5 ns reset pulse
//uporabimo 1 okClk cikel ure 9.92 ns
reg [31:0] rst_cnt;
initial rst_cnt = 32'b0;
always @(posedge okClk) begin
	if(rst_cnt < 32'h0000_0001) begin 
		rst_cnt <= rst_cnt + 1;		  
		sys_rst <= 1'b1;
	end
	else begin
		sys_rst <= 1'b0;
	end
end


//modul za vpis zajetih podatkov v SDRAM
 write_control write_control(
   .clk(clk),
   .rst(rst),
   .wr_en(ep08wire[0]),
   .new_data(new_data),
   .trig(ep10wire),
   .data_in(xadc_out),
   .data_out(data),
   .write_fifo_en(write_fifo_en),
   .write_SRAM_en(write_SRAM_en),
   .write_end(ep34wire)
   );

// MIG User Interface
mig_7series_0 mig_7series_0 (
	.ddr3_addr                      (ddr3_addr),
	.ddr3_ba                        (ddr3_ba),
	.ddr3_cas_n                     (ddr3_cas_n),
	.ddr3_ck_n                      (ddr3_ck_n),
	.ddr3_ck_p                      (ddr3_ck_p),
	.ddr3_cke                       (ddr3_cke),
	.ddr3_ras_n                     (ddr3_ras_n),
	.ddr3_reset_n                   (ddr3_reset_n),
	.ddr3_we_n                      (ddr3_we_n),
	.ddr3_dq                        (ddr3_dq),
	.ddr3_dqs_n                     (ddr3_dqs_n),
	.ddr3_dqs_p                     (ddr3_dqs_p),
	.init_calib_complete            (init_calib_complete),
	
	.ddr3_dm                        (ddr3_dm),
	.ddr3_odt                       (ddr3_odt),
	
	.app_addr                       (app_addr),
	.app_cmd                        (app_cmd),
	.app_en                         (app_en),
	.app_wdf_data                   (app_wdf_data),
	.app_wdf_end                    (app_wdf_end),
	.app_wdf_wren                   (app_wdf_wren),
	.app_rd_data                    (app_rd_data),
	.app_rd_data_end                (app_rd_data_end),
	.app_rd_data_valid              (app_rd_data_valid),
	.app_rdy                        (app_rdy),
	.app_wdf_rdy                    (app_wdf_rdy),
	.app_sr_req                     (1'b0),
	.app_sr_active                  (),
	.app_ref_req                    (1'b0),
	.app_ref_ack                    (),
	.app_zq_req                     (1'b0),
	.app_zq_ack                     (),
	.ui_clk                         (clk),
	.ui_clk_sync_rst                (rst),
	
	.app_wdf_mask                   (app_wdf_mask),
	
	.sys_clk_p                      (sys_clk_p),
	.sys_clk_n                      (sys_clk_n),
	.device_temp_i                  (temp_out),
	
	.sys_rst                        (sys_rst)
	);


// modul za zapis in branje SRAM preko MIG
MIG_inter MIG_inter (
	.clk                (clk),
	.reset              (ep00wire[2] | rst),
	.reads_en           (ep00wire[0]),
	.writes_en          (write_SRAM_en),
	.calib_done         (init_calib_complete),

	.ib_re              (pipe_in_read),
	.ib_data            (pipe_in_data),
	.ib_count           (pipe_in_rd_count),
	.ib_valid           (pipe_in_valid),
	.ib_empty           (pipe_in_empty),
	
	.ob_we              (pipe_out_write),
	.ob_data            (pipe_out_data),
	.ob_count           (pipe_out_wr_count),
	.ob_full            (pipe_out_full),
	
	.app_rdy            (app_rdy),
	.app_en             (app_en),
	.app_cmd            (app_cmd),
	.app_addr           (app_addr),
	
	.app_rd_data        (app_rd_data),
	.app_rd_data_end    (app_rd_data_end),
	.app_rd_data_valid  (app_rd_data_valid),
	
	.app_wdf_rdy        (app_wdf_rdy),
	.app_wdf_wren       (app_wdf_wren),
	.app_wdf_data       (app_wdf_data),
	.app_wdf_end        (app_wdf_end),
	.app_wdf_mask       (app_wdf_mask)
	);

//Preverjanje, ali je v izhodnem sistemu FIFO dovolj prostora za pošiljanje drugega bloka.
always @(posedge okClk) begin
	if(pipe_out_rd_count >= BLOCK_SIZE) begin
		pipe_out_ready <= 1'b1;
	end
	else begin
		pipe_out_ready <= 1'b0;
	end
end


//Front Panel 
wire [65*4-1:0]  okEHx;
frontpanel_0 frontpanel_0(
	//okWireIn
	.wi00_ep_dataout(ep00wire),
	//okWireIn
	.wi08_ep_dataout(ep08wire),
	//okWireIn
	.wi10_ep_dataout(ep10wire),
	//okWireIn
    .wo20_ep_datain({31'h00, init_calib_complete}),
	//okWireOut
    .wo3e_ep_datain(CAPABILITY),
    //okWireOut
    .wo34_ep_datain(ep34wire),
	//okBTPipeOut
    .btpoa0_ep_datain(po0_ep_datain),
    .btpoa0_ep_read(po0_ep_read),
    .btpoa0_ep_blockstrobe(),
    .btpoa0_ep_ready(pipe_out_ready),
	//host interface
	.okUH(okUH),
	.okHU(okHU),
	.okUHU(okUHU),
	.okAA(okAA),
	.okClk(okClk)
	); 

//vhodni FIFO
fifo_generator_0 fifo_generator_0  (
	.rst(rst | ep00wire[2]),
	.wr_clk(clk),
	.rd_clk(clk),
	.din(data), 
	.wr_en(write_fifo_en),
	.rd_en(pipe_in_read),
	.dout(pipe_in_data), 
	.full(pipe_in_full),
	.empty(pipe_in_empty),
	.valid(pipe_in_valid),
	.rd_data_count(pipe_in_rd_count), 
	.wr_data_count(pipe_in_wr_count));

//izhodni FIFO
fifo_generator_4 fifo_generator_4 (
	.rst(ep00wire[2]),
	.wr_clk(clk),
	.rd_clk(okClk),
	.din(pipe_out_data),
	.wr_en(pipe_out_write),
	.rd_en(po0_ep_read),
	.dout(po0_ep_datain), 
	.full(pipe_out_full),
	.empty(pipe_out_empty),
	.valid(),
	.rd_data_count(pipe_out_rd_count), 
	.wr_data_count(pipe_out_wr_count)); 
	
//modul za zajem podatkov XADC
 XADC_capture XADC_capture(
   .clk(clk_52MHz),
   .vp_in(vp_in),
   .vn_in(vn_in),
   .rst(rst), 
   .xadc_out(xadc_out),
   .temp_out(temp_out),
   .new_data(new_data)
   );
	
endmodule
`default_nettype wire
