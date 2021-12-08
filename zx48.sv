
module zx48_top
(
	//Master input clock
	input         CLOCK_27,

	
	

	output  [5:0] VGA_R,
	output  [5:0] VGA_G,
	output  [5:0] VGA_B,
	output        VGA_HS,
	output        VGA_VS,
	
	output        LED,  // 1 - ON, 0 - OFF.

	
	output        AUDIO_L,
	output        AUDIO_R,
	
	//SDRAM interface with lower latency
	output        SDRAM_CLK,
	output        SDRAM_CKE,
	output [12:0] SDRAM_A,
	output  [1:0] SDRAM_BA,
	inout  [15:0] SDRAM_DQ,
	output        SDRAM_DQML,
	output        SDRAM_DQMH,
	output        SDRAM_nCS,
	output        SDRAM_nCAS,
	output        SDRAM_nRAS,
	output        SDRAM_nWE,

   input         SPI_SCK,
   output        SPI_DO,
   input         SPI_DI,
   input         SPI_SS2,
   input         SPI_SS3,
   input         CONF_DATA0,

	input         UART_RX,
	output        UART_TX,
	output [9:0]  DAC_L,
	output [9:0]  DAC_R
	);

`include "build_id.v" 
localparam CONF_STR =
{
	"zx48;;",
	"S0,VHD;",
	"O1,Model,48K,+2;",
	"O2,DivMMC automapper,Enabled,Disabled;",
	"T0,Reset;",
	"V,v1.2 ",`BUILD_DATE
};

wire [ 1:0] buttons;
wire [31:0] status;
wire [10:0] ps2_key;
wire [15:0] joystick_0;
wire [15:0] joystick_1;

wire [31:0] sd_lba;
wire [ 8:0] sd_buff_addr;
wire [ 7:0] sd_buff_dout;
wire [ 7:0] sd_buff_din;
wire        sd_rd;
wire        sd_wr;
wire        sd_ack;
wire        sd_ack_conf;
wire        sd_buff_wr;

wire        sdclk;
wire        sdss;
wire        sdmosi;
wire        sdmiso;

wire        vsdmiso;

wire [63:0] img_size;
wire        img_mounted;
wire        img_readonly;

wire[26:0] ioctl_addr;
wire[ 7:0] ioctl_dout;
wire       ioctl_download;
wire       ioctl_wr;

wire forced_scandoubler;

mist_io #(.STRLEN($size(CONF_STR)>>3)) mist_io
(
	.clk_sys       (clk_sys),
	.conf_str      (CONF_STR),

   .SPI_SCK       (SPI_SCK),
   .CONF_DATA0    (CONF_DATA0),
   .SPI_SS2       (SPI_SS2),
   .SPI_DO        (SPI_DO),
   .SPI_DI        (SPI_DI),

	.status        (status),

	.ps2_key       (ps2_key),

	.joystick_0    (joystick_0),
	.joystick_1    (joystick_1),

	.sd_lba        (sd_lba),
	.sd_rd         (sd_rd),
	.sd_wr         (sd_wr),
	.sd_ack        (sd_ack),
	.sd_ack_conf   (sd_ack_conf),
	.sd_buff_addr  (sd_buff_addr),
	.sd_buff_dout  (sd_buff_dout),
	.sd_buff_din   (sd_buff_din),
	.sd_buff_wr    (sd_buff_wr),
	
	.img_mounted   (img_mounted),
	//.img_readonly(img_readonly),
	.img_size      (img_size),

	.ioctl_download(ioctl_download),
	.ioctl_wr      (ioctl_wr      ),
	.ioctl_addr    (ioctl_addr    ),
	.ioctl_dout    (ioctl_dout    ),

	.buttons       (buttons),
	.scandoubler_disable(forced_scandoubler)
);



//-------------------------------------------------------------------------------------------------

assign sdmiso = vsd_sel ? vsdmiso : SD_MISO;

reg vsd_sel = 0;
always @(posedge clk_sys) if(img_mounted) vsd_sel <= |img_size;

sd_card sd_card
(
	.clk_sys(clk_sys),
	.reset(~reset),

	.sdhc(1),

	.sd_lba(sd_lba),
	.sd_rd(sd_rd),
	.sd_wr(sd_wr),
	.sd_ack(sd_ack),
	.sd_ack_conf(sd_ack_conf),

	.sd_buff_addr(sd_buff_addr),
	.sd_buff_dout(sd_buff_dout),
	.sd_buff_din(sd_buff_din),
	.sd_buff_wr(sd_buff_wr),

	.clk_spi(clk_sys),

	.sck(sdclk),
	.ss(sdss | ~vsd_sel),
	.mosi(sdmosi),
	.miso(vsdmiso)
);

wire SD_CS;
wire SD_SCK;
wire SD_MOSI;
wire SD_MISO;

assign SD_CS   = sdss   |  vsd_sel;
assign SD_SCK  = sdclk  & ~vsd_sel;
assign SD_MOSI = sdmosi & ~vsd_sel;

reg sd_act;

always @(posedge clk_sys) begin
	reg old_mosi, old_miso;
	integer timeout = 0;

	old_mosi <= sdmosi;
	old_miso <= sdmiso;

	sd_act <= 0;
	if(timeout < 1000000) begin
		timeout <= timeout + 1;
		sd_act <= 1;
	end

	if((old_mosi ^ sdmosi) || (old_miso ^ sdmiso)) timeout <= 0;
end

//-------------------------------------------------------------------------------------------------

wire clk_sys,clk_sd;
wire locked;

pll pll
(
	.inclk0  (CLOCK_27),
	.areset  (0      ),
	.locked  (locked ),
	.c0      (clk_sys), // 56 MHz
	.c1      (clk_sd )  // 14 MHz
);

//-------------------------------------------------------------------------------------------------

reg ps2k10d, kstrobe;
always @(posedge clk_sys) begin ps2k10d <= ps2_key[10]; kstrobe <= ps2k10d != ps2_key[10]; end

wire reset = ~(status[0] | buttons[1] | ioctl_download);
wire model = status[1];
wire nomap = status[2];

wire[ 1:0] blank;
wire[ 1:0] sync;
wire[23:0] rgb;

wire ear = ~UART_RX;
wire[9:0] laudio;
wire[9:0] raudio;

wire kpress = ~ps2_key[9];
wire[7:0] kcode = ps2_key[7:0];
wire[1:0] kleds;

wire[5:0] jstick = joystick_0[5:0]; // | joystick_1[5:0]) : 6'd0;

wire       iniBusy = ioctl_download;
wire       iniWr = ioctl_wr;
wire[ 7:0] iniD = ioctl_dout;
wire[15:0] iniA = ioctl_addr[15:0];

zx48 ZX48
(
	.clock  (clk_sys),
	.reset  (reset  ),
	.model  (model  ),
	.nomap  (nomap  ),
	.locked (locked ),
	.blank  (blank  ),
	.sync   (sync   ),
	.rgb    (rgb    ),
	.pce    (ce_pix ),
	.ear    (ear    ),
	.laudio (laudio ),
	.raudio (raudio ),
	.kstrobe(kstrobe),
	.kpress (kpress ),
	.kcode  (kcode  ),
	.kleds  (kleds  ),
	.jstick (jstick ),
	.usdCk  (sdclk  ),
	.usdCs  (sdss   ),
	.usdMiso(sdmiso ),
	.usdMosi(sdmosi ),
	.iniBusy(iniBusy),
	.iniWr  (iniWr  ),
	.iniD   (iniD   ),
	.iniA   (iniA   )
);

//-------------------------------------------------------------------------------------------------

wire ce_pix;

video_mixer #(.LINE_LENGTH(720)) video_mixer
(
	.*,

	.ce_pix(ce_pix),
   .ce_pix_actual(ce_pix),
   .scandoubler_disable(forced_scandoubler),
	.hq2x(),
	.mono(0),
	.scanlines(),
	.ypbpr(),
   .ypbpr_full(0),
   .line_start(0),


	.R(rgb[23:18]),
	.G(rgb[15:10]),
	.B(rgb[7:2]),
	.HSync(sync[0]),
	.VSync(sync[1]),
	.HBlank(blank[0]),
	.VBlank(blank[1])
	

);


//assign VGA_DE    = ~|blank;
//assign VGA_HS    = sync[0];
//assign VGA_VS    = sync[1];
//assign VGA_R     = rgb[23:16];
//assign VGA_G     = rgb[15: 8];
//assign VGA_B     = rgb[ 7: 0];

assign LED       = vsd_sel & sd_act;

assign DAC_L   = { 2'd0, laudio, 4'd0 };
assign DAC_R   = { 2'd0, raudio, 4'd0 };

//-------------------------------------------------------------------------------------------------
endmodule
//-------------------------------------------------------------------------------------------------
