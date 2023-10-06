//============================================================================
//  N64 for MiSTer
//  Copyright (C) 2023 Robert Peip
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 2 of the License, or (at your option)
//  any later version.
//
//  This program is distributed in the hope that it will be useful, but WITHOUT
//  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
//  FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
//  more details.
//
//  You should have received a copy of the GNU General Public License along
//  with this program; if not, write to the Free Software Foundation, Inc.,
//  51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
//============================================================================

module emu
(
	//Master input clock
	input         CLK_50M,

	//Async reset from top-level module.
	//Can be used as initial reset.
	input         RESET,

	//Must be passed to hps_io module
	inout  [48:0] HPS_BUS,

	//Base video clock. Usually equals to CLK_SYS.
	output        CLK_VIDEO,

	//Multiple resolutions are supported using different CE_PIXEL rates.
	//Must be based on CLK_VIDEO
	output        CE_PIXEL,

	//Video aspect ratio for HDMI. Most retro systems have ratio 4:3.
	//if VIDEO_ARX[12] or VIDEO_ARY[12] is set then [11:0] contains scaled size instead of aspect ratio.
	output [12:0] VIDEO_ARX,
	output [12:0] VIDEO_ARY,

	output  [7:0] VGA_R,
	output  [7:0] VGA_G,
	output  [7:0] VGA_B,
	output        VGA_HS,
	output        VGA_VS,
	output        VGA_DE,    // = ~(VBlank | HBlank)
	output        VGA_F1,
	output [1:0]  VGA_SL,
	output        VGA_SCALER, // Force VGA scaler
	output        VGA_DISABLE, // analog out is off

	input  [11:0] HDMI_WIDTH,
	input  [11:0] HDMI_HEIGHT,
   output        HDMI_FREEZE,

`ifdef MISTER_FB
	// Use framebuffer in DDRAM
	// FB_FORMAT:
	//    [2:0] : 011=8bpp(palette) 100=16bpp 101=24bpp 110=32bpp
	//    [3]   : 0=16bits 565 1=16bits 1555
	//    [4]   : 0=RGB  1=BGR (for 16/24/32 modes)
	//
	// FB_STRIDE either 0 (rounded to 256 bytes) or multiple of pixel size (in bytes)
	output        FB_EN,
	output  [4:0] FB_FORMAT,
	output [11:0] FB_WIDTH,
	output [11:0] FB_HEIGHT,
	output [31:0] FB_BASE,
	output [13:0] FB_STRIDE,
	input         FB_VBL,
	input         FB_LL,
	output        FB_FORCE_BLANK,

`ifdef MISTER_FB_PALETTE
	// Palette control for 8bit modes.
	// Ignored for other video modes.
	output        FB_PAL_CLK,
	output  [7:0] FB_PAL_ADDR,
	output [23:0] FB_PAL_DOUT,
	input  [23:0] FB_PAL_DIN,
	output        FB_PAL_WR,
`endif
`endif

	output        LED_USER,  // 1 - ON, 0 - OFF.

	// b[1]: 0 - LED status is system status OR'd with b[0]
	//       1 - LED status is controled solely by b[0]
	// hint: supply 2'b00 to let the system control the LED.
	output  [1:0] LED_POWER,
	output  [1:0] LED_DISK,

	// I/O board button press simulation (active high)
	// b[1]: user button
	// b[0]: osd button
	output  [1:0] BUTTONS,

	input         CLK_AUDIO, // 24.576 MHz
	output [15:0] AUDIO_L,
	output [15:0] AUDIO_R,
	output        AUDIO_S,   // 1 - signed audio samples, 0 - unsigned
	output  [1:0] AUDIO_MIX, // 0 - no mix, 1 - 25%, 2 - 50%, 3 - 100% (mono)

	//ADC
	inout   [3:0] ADC_BUS,

	//SD-SPI
	output        SD_SCK,
	output        SD_MOSI,
	input         SD_MISO,
	output        SD_CS,
	input         SD_CD,

	//High latency DDR3 RAM interface
	//Use for non-critical time purposes
	output        DDRAM_CLK,
	input         DDRAM_BUSY,
	output  [7:0] DDRAM_BURSTCNT,
	output [28:0] DDRAM_ADDR,
	input  [63:0] DDRAM_DOUT,
	input         DDRAM_DOUT_READY,
	output        DDRAM_RD,
	output [63:0] DDRAM_DIN,
	output  [7:0] DDRAM_BE,
	output        DDRAM_WE,

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

`ifdef MISTER_DUAL_SDRAM
	//Secondary SDRAM
	//Set all output SDRAM_* signals to Z ASAP if SDRAM2_EN is 0
	input         SDRAM2_EN,
	output        SDRAM2_CLK,
	output [12:0] SDRAM2_A,
	output  [1:0] SDRAM2_BA,
	inout  [15:0] SDRAM2_DQ,
	output        SDRAM2_nCS,
	output        SDRAM2_nCAS,
	output        SDRAM2_nRAS,
	output        SDRAM2_nWE,
`endif

	input         UART_CTS,
	output        UART_RTS,
	input         UART_RXD,
	output        UART_TXD,
	output        UART_DTR,
	input         UART_DSR,

	// Open-drain User port.
	// 0 - D+/RX
	// 1 - D-/TX
	// 2..6 - USR2..USR6
	// Set USER_OUT to 1 to read from USER_IN.
	input   [6:0] USER_IN,
	output  [6:0] USER_OUT,

	input         OSD_STATUS
);

assign HDMI_FREEZE = 1'b0;

assign AUDIO_S   = 1;
assign AUDIO_MIX = status[8:7];

assign LED_USER  = cart_download | bk_pending;
assign LED_DISK  = 0;
assign LED_POWER = 0;
assign BUTTONS   = 0;
assign VGA_SCALER= 0;

assign ADC_BUS  = 'Z;
assign USER_OUT = '1;
assign {UART_RTS, UART_TXD, UART_DTR} = 0;
assign {SD_SCK, SD_MOSI, SD_CS} = 'Z;
assign {SDRAM_DQ, SDRAM_A, SDRAM_BA, SDRAM_CLK, SDRAM_CKE, SDRAM_DQML, SDRAM_DQMH, SDRAM_nWE, SDRAM_nCAS, SDRAM_nRAS, SDRAM_nCS} = 'Z;

assign VIDEO_ARX = (status[47:46] == 0) ? 12'd4 : (status[47:46] == 1) ? 12'd16 : status[19:18] - 1'd1;
assign VIDEO_ARY = (status[47:46] == 0) ? 12'd3 : (status[47:46] == 1) ? 12'd9 : 12'd0;

///////////////////////  CLOCK/RESET  ///////////////////////////////////

wire clk_1x;
wire clk_93;
wire clk_2x;
wire clk_vid;
wire pll_locked;

pll pll
(
	.refclk(CLK_50M),
	.rst(0),
	.outclk_0(clk_1x),
	.outclk_1(clk_93),
	.outclk_2(clk_2x),
   .locked(pll_locked)
);

pll2 pll2
(
	.refclk(CLK_50M),
	.rst(0),
	.outclk_0(clk_vid)
);

wire reset_or = RESET | buttons[1] | status[0] | cart_download;

////////////////////////////  HPS I/O  //////////////////////////////////

// Status Bit Map: (0..31 => "O", 32..63 => "o")
// 0         1         2         3          4         5         6          7         8         9
// 01234567890123456789012345678901 23456789012345678901234567890123 45678901234567890123456789012345
// todo
// 

`include "build_id.v"
parameter CONF_STR = {
	"N64;SS3C000000:1000000;",
   "FS1,N64z64n64v64,Load;",
   "-;",
	"D0R[40],Reload Backup RAM;",
	"D0R[41],Save Backup RAM;",
	"D0O[42],Autosave,On,Off;",
   //"-;",
	//"O[36],Savestates to SDCard,On,Off;",
	//"O[3],Autoincrement Slot,Off,On;",
	//"O[38:37],Savestate Slot,1,2,3,4;",
	//"RH,Save state (Alt-F1);",
	//"RI,Restore state (F1);",
	"-;",
   //"O[59:58],Gamepads,1,2,3,4;",
   "O[51:50],Pad 1 Pak,None,CPAK,Rumble;",
   "O[53:52],Pad 2 Pak,None,CPAK,Rumble;",
   "O[55:54],Pad 3 Pak,None,CPAK,Rumble;",
   "O[57:56],Pad 4 Pak,None,CPAK,Rumble;",
   "O[60],Swap Analog<->DPAD,Off,On;",
	"-;",
   "O[30],Texture Filter,On,Off;",
   "O[31],Dithering,On,Off;",
   "O[32],VI Bilinear,On,Off;",
   "O[33],VI Gamma,On,Off;",
   "O[34],VI Dedither,On,Off;",
   "O[35],VI Antialias,On,Off;",
   "-;",
   "O[2],Error Overlay,Off,On;",
   "O[28],FPS Overlay,Off,On;",
   "O[8:7],Stereo Mix,None,25%,50%,100%;",
	"O[47:46],Aspect Ratio,4:3,16:9,Full Screen;",
   "O[45:44],Crop Bottom,None,8,16,24;",
   "-;",
   
   "P2,System settings;",
	"P2-;",
   "P2-,From N64-database;",
	"P2O[64],Auto Detect,On,Off;",
   "P2O[70],RAM size,8MByte,4MByte;",
   "P2O[80:79],System Type,NTSC,PAL;",
	"P2O[68:65],CIC,6101,6102,7101,7102,6103,7103,6105,7105,6106,7106,8303,8401,5167,DDUS;",
   "P2O[71],ControllerPak,Off,On;",
   "P2R[81],Format CPAK now;",
   "P2O[72],RumblePak,Off,On;",
   "P2O[73],TransferPak,Off,On;",
   "P2O[74],RTC,Off,On;",
   "P2O[77:75],Save Type,None,EEPROM4,EEPROM16,SRAM32,SRAM96,Flash;",
   "-;",
   
   "P3,Debug settings;",
   "P3O[43],Data Cache,On,Off;",
   "P3O[29],Data FORCE WB,Off,On;",
   "P3O[27:24],Cache Delay,0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15;",
   "P3O[23:20],DDR3 Delay,0,16,24,32,40,48,56,64,72,80,88,96,104,112;",
   "P3O[11],Write Bit 9,On,Off;",
   "P3O[12],Read Bit 9,On,Off;",
   "P3O[13],Wait Bit 9,On,Off;",
   "P3O[14],Write Z,On,Off;",
   "P3O[15],Read Z,On,Off;",
   "P3O[1],Swap Interlaced,Off,On;",
   "-;",
   
	"R0,Reset;",
   "J1,A,B,Start,L,R,Z,C Up,C Right,C Down,C Left;",
	"jn,A,B,Start,L,R,Z,C Up,C Right,C Down,C Left;",
	"I,",
	"Load=DPAD Up|Save=Down|Slot=L+R,",
	"Active Slot 1,",
	"Active Slot 2,",
	"Active Slot 3,",
	"Active Slot 4,",
	"Save to state 1,",
	"Restore state 1,",
	"Save to state 2,",
	"Restore state 2,",
	"Save to state 3,",
	"Restore state 3,",
	"Save to state 4,",
	"Restore state 4;",
	"V,v",`BUILD_DATE
};

wire  [1:0] buttons;
wire [127:0] status;
wire        forced_scandoubler;

wire [19:0] joy;
wire [19:0] joy_unmod;
wire [19:0] joy2;
wire [19:0] joy3;
wire [19:0] joy4;

wire [15:0] joystick_analog_l0;
wire [15:0] joystick_analog_l1;
wire [15:0] joystick_analog_l2;
wire [15:0] joystick_analog_l3;

wire [10:0] ps2_key;

wire [127:0] status_in = {status[127:39],ss_slot,status[36:0]};
wire [15:0] status_menumask = 16'd0;

wire DIRECT_VIDEO;

wire        ioctl_download;
wire [26:0] ioctl_addr;
wire [15:0] ioctl_dout;
wire        ioctl_wr;
wire  [7:0] ioctl_index;
reg         ioctl_wait = 0;

reg [7:0] info_index;
reg info_req;

wire  [8:0] sd_lba;
wire        sd_rd;
wire        sd_wr;
wire        sd_ack;
wire  [7:0] sd_buff_addr;
wire [15:0] sd_buff_dout;
wire [15:0] sd_buff_din;
wire        sd_buff_wr;
wire        img_mounted;
wire        img_readonly;
wire [31:0] img_size;

wire [3:0] rumble;

hps_io #(.CONF_STR(CONF_STR), .WIDE(1)) hps_io
(
	.clk_sys(clk_1x),
	.HPS_BUS(HPS_BUS),
	.EXT_BUS(),

	.buttons(buttons),
	.forced_scandoubler(forced_scandoubler),

   .ioctl_addr(ioctl_addr),
	.ioctl_dout(ioctl_dout),
	.ioctl_wr(ioctl_wr),
	.ioctl_download(ioctl_download),
	.ioctl_index(ioctl_index),
	.ioctl_wait(ioctl_wait),

   .joystick_0(joy_unmod),
	.joystick_1(joy2),
	.joystick_2(joy3),
	.joystick_3(joy4),
	.ps2_key(ps2_key),

	.status(status),
	.status_in(status_in),
	//.status_set(statusUpdate),
	.status_set(0),
	.status_menumask(status_menumask),
	.info_req(info_req),
	.info(info_index),
   
   .joystick_l_analog_0(joystick_analog_l0), 
   .joystick_l_analog_1(joystick_analog_l1),
   .joystick_l_analog_2(joystick_analog_l2),
   .joystick_l_analog_3(joystick_analog_l3),
   
   .joystick_0_rumble(rumble[0] ? 16'hFFFF : 16'h0000),
   .joystick_1_rumble(rumble[1] ? 16'hFFFF : 16'h0000),
   .joystick_2_rumble(rumble[2] ? 16'hFFFF : 16'h0000),
   .joystick_3_rumble(rumble[3] ? 16'hFFFF : 16'h0000),
   
   .sd_lba('{sd_lba}),
	.sd_rd(sd_rd),
	.sd_wr(sd_wr),
	.sd_ack(sd_ack),
	.sd_buff_addr(sd_buff_addr),
	.sd_buff_dout(sd_buff_dout),
	.sd_buff_din('{sd_buff_din}),
	.sd_buff_wr(sd_buff_wr),

	.img_mounted(img_mounted),
	.img_readonly(img_readonly),
	.img_size(img_size),
   
   .direct_video(DIRECT_VIDEO)
);

assign joy = joy_unmod; //joy_unmod[14] ? 20'b0 : joy_unmod;

////////////////////////////  PIFROM download  ///////////////////////////////////

reg  [9:0] pifrom_wraddress;
reg [31:0] pifrom_wrdata;   
reg        pifrom_wren;   
reg        pifrom_download;


always @(posedge clk_1x) begin

   pifrom_download   <= ioctl_download & (ioctl_index[5:0] == 0);

	pifrom_wren <= 0;
	if(pifrom_download) begin
      if (ioctl_wr) begin
         if(~ioctl_addr[1]) begin
            pifrom_wrdata[31:24] <= ioctl_dout[7:0];
            pifrom_wrdata[23:16] <= ioctl_dout[15:8];
            pifrom_wraddress    <= {ioctl_index[6], ioctl_addr[10:2]};                                  
         end else begin
            pifrom_wrdata[15:8] <= ioctl_dout[7:0];
            pifrom_wrdata[7:0]  <= ioctl_dout[15:8];
            pifrom_wren          <= 1;
         end
      end
	end
   
end

////////////////////////////  SDRAM  ///////////////////////////////////

reg [26:0] ramdownload_wraddr;
reg [31:0] ramdownload_wrdata;
reg        ramdownload_wr;
wire       ramdownload_ready;
reg        cart_download;
reg        cart_loaded = 0;

localparam CART_START = 8388608;

always @(posedge clk_1x) begin

   cart_download     <= ioctl_download & (ioctl_index[5:0] == 1);

	ramdownload_wr <= 0;
	if(cart_download) begin
      cart_loaded <= 1;
      if (ioctl_wr) begin
         if(~ioctl_addr[1]) begin
            ramdownload_wrdata[15:0] <= ioctl_dout;
            ramdownload_wraddr <= ioctl_addr[26:0] + CART_START[26:0];                                  
         end else begin
            ramdownload_wrdata[31:16] <= ioctl_dout;
            ramdownload_wr            <= 1;
            ioctl_wait                <= 1;
         end
      end
      if(ramdownload_ready) ioctl_wait <= 0;
   end else begin 
      ioctl_wait <= 0;
	end
   
end

wire        sdram_ena;
wire        sdram_rnw;
wire [26:0] sdram_Adr;
wire  [3:0] sdram_be;
wire [31:0] sdram_dataWrite;
wire        sdram_done;  
wire [31:0] sdram_dataRead;

sdram sdram
(
	.*,
	.init(~pll_locked),
	.clk(clk_1x),

	.ch1_addr(sdram_Adr),
	.ch1_din(sdram_dataWrite),
	.ch1_dout(sdram_dataRead),
	.ch1_req(sdram_ena),
	.ch1_rnw(sdram_rnw),
	.ch1_be(sdram_be),
	.ch1_ready(sdram_done),

	.ch2_addr (ramdownload_wraddr),
	.ch2_din  (ramdownload_wrdata),
	.ch2_dout (),
	.ch2_req  (ramdownload_wr),
	.ch2_rnw  (1'b0),
	.ch2_ready(ramdownload_ready),

	.ch3_addr(27'b0),
	.ch3_din(16'b0),
	.ch3_dout(),
	.ch3_req(1'b0),
	.ch3_rnw(1'b1),
	.ch3_ready()
);

///////////////////////////  SAVESTATE  /////////////////////////////////

wire [1:0] ss_slot;
wire [7:0] ss_info;
wire ss_save, ss_load, ss_info_req;
wire statusUpdate;

savestate_ui savestate_ui
(
	.clk            (clk_1x        ),
	.ps2_key        (ps2_key[10:0] ),
	.allow_ss       (cart_loaded   ),
	//.joySS          (joy_unmod[14] ),
	.joySS          (0             ),
	.joyRight       (joy_unmod[0]  ),
	.joyLeft        (joy_unmod[1]  ),
	.joyDown        (joy_unmod[2]  ),
	.joyUp          (joy_unmod[3]  ),
	.joyRewind      (0             ),
	.rewindEnable   (0             ), 
	.status_slot    (status[38:37] ),
	.autoincslot    (status[3]     ),
	.OSD_saveload   (status[18:17] ),
	.ss_save        (ss_save       ),
	.ss_load        (ss_load       ),
	.ss_info_req    (info_req      ),
	.ss_info        (info_index    ),
	.statusUpdate   (statusUpdate  ),
	.selected_slot  (ss_slot       )
);
defparam savestate_ui.INFO_TIMEOUT_BITS = 25;

///////////////////////// SAVE/LOAD  /////////////////////////////

wire  bk_pending;

wire bk_load     = status[40] | (cart_download & img_mounted);
wire bk_save     = status[41] | (OSD_STATUS & ~OSD_STATUS_1 & ~status[42]);

reg use_img;
reg OSD_STATUS_1 = 0;

always @(posedge clk_1x) begin
	reg old_downloading;
   
   OSD_STATUS_1 <= OSD_STATUS;

	old_downloading <= cart_download;
	if(~old_downloading & cart_download) use_img <= 0;

	if(img_mounted && img_size && !img_readonly) begin
		use_img <= 1;
	end
end

////////////////////////////  SYSTEM  ///////////////////////////////////

wire HBlank;
wire VBlank;
wire Interlaced;

assign DDRAM_CLK = clk_2x;
//assign DDRAM_CLK = clk_1x;

wire [1:0] eepromtype = (status[77:75] == 3'b001) ? 2'b01 : 
                        (status[77:75] == 3'b010) ? 2'b10 :
                        2'b00; 

n64top 
#(
   .use2Xclock(1'b1)
)
n64top
(
   .clk1x(clk_1x),          
   .clk93(clk_93),          
   //.clk93(clk_1x),          
   .clk2x(clk_2x),          
   //.clk2x(clk_1x),          
   .clkvid(clk_vid),
   .reset(reset_or),
   .pause(OSD_STATUS),
   .errorCodesOn(status[2]),
   .fpscountOn(status[28]),
   
   .ISPAL(status[79]),
	.ASPECTRATIO(status[47:46]),
   .CROPBOTTOM(status[45:44]),
   .VI_BILINEAROFF(status[32]),
   .VI_GAMMAOFF(status[33]),
   .VI_DEDITHEROFF(status[34]),
   .VI_AAOFF(status[35]),
   
   .CICTYPE(status[68:65]),
   .RAMSIZE8(~status[70]),
   .DATACACHEON(~status[43]),
   .DATACACHESLOW(status[27:24]),
   .DATACACHEFORCEWEB(status[29]),
   .DDR3SLOW(status[23:20]),
   .DISABLEFILTER(status[30]),
   .DISABLEDITHER(status[31]),
   
   .write9(!status[11]), 
   .read9(!status[12]),  
   .wait9(!status[13]), 
   .writeZ(!status[14]),
   .readZ(!status[15]),
   
   // savestates              
   .increaseSSHeaderCount (!status[36]),
   .save_state            (0), //(ss_save),
   .load_state            (ss_load),
   .savestate_number      (ss_slot),
   .state_loaded          (),
   
   // PIFROM download port
   .pifrom_wraddress (pifrom_wraddress),
   .pifrom_wrdata    (pifrom_wrdata   ),
   .pifrom_wren      (pifrom_wren     ),
   
   // RDRAM
   .ddr3_BUSY        (DDRAM_BUSY      ),
   .ddr3_BURSTCNT    (DDRAM_BURSTCNT  ),
   .ddr3_ADDR        (DDRAM_ADDR      ),
   .ddr3_DOUT        (DDRAM_DOUT      ),
   .ddr3_DOUT_READY  (DDRAM_DOUT_READY),
   .ddr3_RD          (DDRAM_RD        ),
   .ddr3_DIN         (DDRAM_DIN       ),
   .ddr3_BE          (DDRAM_BE        ),
   .ddr3_WE          (DDRAM_WE        ),
   
   // ROM+SRAM+FLASH
   .cartAvailable    (cart_loaded    ),
   .sdram_ena        (sdram_ena      ),
   .sdram_rnw        (sdram_rnw      ),
   .sdram_Adr        (sdram_Adr      ),
   .sdram_be         (sdram_be       ),
   .sdram_dataWrite  (sdram_dataWrite),
   .sdram_done       (sdram_done     ),
   .sdram_dataRead   (sdram_dataRead ),
      
   // pad
   .PADCOUNT         (3'd3),//(status[59:58]),
   .PADTYPE0         (status[51:50]),
   .PADTYPE1         (status[53:52]),
   .PADTYPE2         (status[55:54]),
   .PADTYPE3         (status[57:56]),
   .PADDPADSWAP      (status[60]),
   .rumble           (rumble),
   .pad_A            ({joy4[ 4],joy3[ 4],joy2[ 4],joy[ 4]}),
   .pad_B            ({joy4[ 5],joy3[ 5],joy2[ 5],joy[ 5]}),
   .pad_Z            ({joy4[ 9],joy3[ 9],joy2[ 9],joy[ 9]}),
   .pad_START        ({joy4[ 6],joy3[ 6],joy2[ 6],joy[ 6]}),
   .pad_DPAD_UP      ({joy4[ 3],joy3[ 3],joy2[ 3],joy[ 3]}),
   .pad_DPAD_DOWN    ({joy4[ 2],joy3[ 2],joy2[ 2],joy[ 2]}),
   .pad_DPAD_LEFT    ({joy4[ 1],joy3[ 1],joy2[ 1],joy[ 1]}),
   .pad_DPAD_RIGHT   ({joy4[ 0],joy3[ 0],joy2[ 0],joy[ 0]}),
   .pad_L            ({joy4[ 7],joy3[ 7],joy2[ 7],joy[ 7]}),
   .pad_R            ({joy4[ 8],joy3[ 8],joy2[ 8],joy[ 8]}),
   .pad_C_UP         ({joy4[10],joy3[10],joy2[10],joy[10]}),
   .pad_C_DOWN       ({joy4[12],joy3[12],joy2[12],joy[12]}),
   .pad_C_LEFT       ({joy4[13],joy3[13],joy2[13],joy[13]}),
   .pad_C_RIGHT      ({joy4[11],joy3[11],joy2[11],joy[11]}),
   .pad_0_analog_h   (joystick_analog_l0[7:0]),
   .pad_0_analog_v   (joystick_analog_l0[15:8]),
   .pad_1_analog_h   (joystick_analog_l1[7:0]),
   .pad_1_analog_v   (joystick_analog_l1[15:8]),
   .pad_2_analog_h   (joystick_analog_l2[7:0]),
   .pad_2_analog_v   (joystick_analog_l2[15:8]),
   .pad_3_analog_h   (joystick_analog_l3[7:0]),
   .pad_3_analog_v   (joystick_analog_l3[15:8]),
   
   // audio
   .sound_out_left   (AUDIO_L),
   .sound_out_right  (AUDIO_R),  
   
   // Saves
   .SAVETYPE         (status[77:75]),
   .EEPROMTYPE       (eepromtype),
   .CONTROLLERPAK    (status[71]),
   .CPAKFORMAT       (status[81]),
   
   .save             (bk_save),
   .load             (bk_load),
   .mounted          (use_img),
   .changePending    (bk_pending),
   .save_ongoing     (),
   .save_rd          (sd_rd),
   .save_wr          (sd_wr),
   .save_lba         (sd_lba),
   .save_ack         (sd_ack), 
   .save_write       (sd_buff_wr),
   .save_addr        (sd_buff_addr),
   .save_dataIn      (sd_buff_dout),
   .save_dataOut     (sd_buff_din),
   
   // video out   
   .video_hsync      (VGA_HS),
   .video_vsync      (VGA_VS),
   .video_hblank     (HBlank),
   .video_vblank     (VBlank),
   .video_ce         (CE_PIXEL),
   .video_interlace  (Interlaced),
   .video_r          (VGA_R),
   .video_g          (VGA_G),
   .video_b          (VGA_B)
);

assign CLK_VIDEO = clk_1x;
assign VGA_DE = ~(HBlank | VBlank);
assign VGA_F1 = Interlaced ^ status[1];
assign VGA_SL = 0;
assign VGA_DISABLE = 0;


endmodule

      
      

  
      
       
        
        
        