library IEEE;
use IEEE.std_logic_1164.all;  
use IEEE.numeric_std.all;     
use IEEE.std_logic_textio.all; 
library STD;    
use STD.textio.all;

library n64;
use n64.pDDR3.all;
use n64.pSDRAM.all;

entity etb  is
end entity;

architecture arch of etb is

   constant clk_speed : integer := 62500000;
   constant baud      : integer := 10000000;
 
   signal clk1x       : std_logic := '1';
   signal clk93       : std_logic := '1';
   signal clk2x       : std_logic := '1';
   signal clkvid      : std_logic := '1';
   
   signal clk1xToggle            : std_logic := '0';
   signal clk1xToggle2X          : std_logic := '0';
   signal clk2xIndex             : std_logic := '0';
   
   -- top level replication
   signal rdram_request       : tDDDR3Single;
   signal rdram_rnw           : tDDDR3Single;    
   signal rdram_address       : tDDDR3ReqAddr;
   signal rdram_burstcount    : tDDDR3Burstcount;  
   signal rdram_writeMask     : tDDDR3BwriteMask;  
   signal rdram_dataWrite     : tDDDR3BwriteData;
   signal rdram_granted       : tDDDR3Single;
   signal rdram_done          : tDDDR3Single;
   signal rdram_dataRead      : std_logic_vector(63 downto 0);
  
   signal sdramMux_request    : tSDRAMSingle;
   signal sdramMux_rnw        : tSDRAMSingle;    
   signal sdramMux_address    : tSDRAMReqAddr;
   signal sdramMux_burstcount : tSDRAMBurstcount;  
   signal sdramMux_writeMask  : tSDRAMBwriteMask;  
   signal sdramMux_dataWrite  : tSDRAMBwriteData;
   signal sdramMux_granted    : tSDRAMSingle;
   signal sdramMux_done       : tSDRAMSingle;
   signal sdramMux_dataRead   : std_logic_vector(31 downto 0);
   
   signal bus_VI_addr         : unsigned(19 downto 0) := (others => '0');
   signal bus_VI_dataWrite    : std_logic_vector(31 downto 0) := (others => '0');
   signal bus_VI_read         : std_logic := '0';
   signal bus_VI_write        : std_logic := '0';
   signal bus_VI_dataRead     : std_logic_vector(31 downto 0);    
   signal bus_VI_done         : std_logic;      
   
     -- ddrram
   signal DDRAM_CLK           : std_logic;
   signal DDRAM_BUSY          : std_logic;
   signal DDRAM_BURSTCNT      : std_logic_vector(7 downto 0);
   signal DDRAM_ADDR          : std_logic_vector(28 downto 0);
   signal DDRAM_DOUT          : std_logic_vector(63 downto 0);
   signal DDRAM_DOUT_READY    : std_logic;
   signal DDRAM_RD            : std_logic;
   signal DDRAM_DIN           : std_logic_vector(63 downto 0);
   signal DDRAM_BE            : std_logic_vector(7 downto 0);
   signal DDRAM_WE            : std_logic;
   
   --sdram access 
   signal sdram_dataWrite     : std_logic_vector(31 downto 0);
   signal sdram_dataRead      : std_logic_vector(31 downto 0);
   signal sdram_Adr           : std_logic_vector(26 downto 0);
   signal sdram_be            : std_logic_vector(3 downto 0);
   signal sdram_rnw           : std_logic;
   signal sdram_ena           : std_logic;
   signal sdram_done          : std_logic;     
   
   -- video
   signal video_hblank        : std_logic;
   signal video_vblank        : std_logic;
   signal video_ce            : std_logic;
   signal video_interlace     : std_logic;
   signal video_r             : std_logic_vector(7 downto 0);
   signal video_g             : std_logic_vector(7 downto 0);
   signal video_b             : std_logic_vector(7 downto 0);
   
   -- savestates
   signal reset_in            : std_logic := '1';
   signal reset_out           : std_logic;
   signal loading_savestate   : std_logic;
   signal SS_reset            : std_logic := '0';
   signal SS_DataWrite        : std_logic_vector(63 downto 0) := (others => '0');
   signal SS_Adr              : unsigned(18 downto 0) := (others => '0');
   signal SS_wren             : std_logic_vector(13 downto 0) := (others => '0');
   
   -- testbench
   signal cmdCount            : integer := 0;
   type t_commandarray is array(0 to 31) of std_logic_vector(63 downto 0); 
   signal commandarray : t_commandarray := (others => (others => '0'));
   signal commandIsIdle_out : std_logic;
   
begin

   clk1x <= not clk1x after 8 ns;
   clk93 <= not clk93 after 6 ns;
   clk2x <= not clk2x after 4 ns;
   
   reset_in  <= '0' after 3000 ns;
   
   -- NTSC 53.693175 mhz => 30 ns * 33.8688 / 53.693175 / 2 = 9.4617612014 ns
   --clkvid <= not clkvid after 9462 ps;
   clkvid <= not clkvid after 8 ns;
   
    -- top level replication
    
   -- clock index
   process (clk1x)
   begin
      if rising_edge(clk1x) then
         clk1xToggle <= not clk1xToggle;
      end if;
   end process;
   
   process (clk2x)
   begin
      if rising_edge(clk2x) then
         clk1xToggle2x <= clk1xToggle;
         clk2xIndex    <= '0';
         if (clk1xToggle2x = clk1xToggle) then
            clk2xIndex <= '1';
         end if;
      end if;
   end process;
   
   iVI : entity n64.VI
   generic map
   (
      use2Xclock       => '1',
      VITEST           => '1'
   )
   port map
   (
      clk1x                => clk1x,        
      clk2x                => clk2x,        
      clkvid               => clkvid,        
      ce                   => '1',           
      reset_1x             => reset_out, 
      
      ISPAL                => '0',
      ASPECTRATIO          => "00",
      CROPBOTTOM           => "00",
      VI_BILINEAROFF       => '0',
      
      irq_out              => open,
      
      errorEna             => '0',
      errorCode            => 24x"0",
      fpscountOn           => '0',
      
      rdram_request        => rdram_request(DDR3MUX_VI),   
      rdram_rnw            => rdram_rnw(DDR3MUX_VI),       
      rdram_address        => rdram_address(DDR3MUX_VI),   
      rdram_burstcount     => rdram_burstcount(DDR3MUX_VI),
      rdram_granted        => rdram_granted(DDR3MUX_VI),      
      rdram_done           => rdram_done(DDR3MUX_VI),
      ddr3_DOUT            => DDRAM_DOUT,       
      ddr3_DOUT_READY      => DDRAM_DOUT_READY,       
      
      video_hsync          => open, 
      video_vsync          => open,  
      video_hblank         => video_hblank, 
      video_vblank         => video_vblank, 
      video_ce             => video_ce,     
      video_interlace      => video_interlace,     
      video_r              => video_r,      
      video_g              => video_g,      
      video_b              => video_b,    
                           
      bus_addr             => bus_VI_addr,     
      bus_dataWrite        => bus_VI_dataWrite,
      bus_read             => bus_VI_read,     
      bus_write            => bus_VI_write,    
      bus_dataRead         => bus_VI_dataRead, 
      bus_done             => bus_VI_done,     
      
      SS_reset             => SS_reset,
      SS_DataWrite         => SS_DataWrite,
      SS_Adr               => SS_Adr(2 downto 0),
      SS_wren              => SS_wren(9),
      SS_rden              => '0',
      SS_DataRead          => open
   ); 

   iDDR3Mux : entity n64.DDR3Mux
   generic map
   (
      use2Xclock       => '1'
   )
   port map
   (
      clk1x            => clk1x,           
      clk2x            => clk2x,           
      clk2xIndex       => clk2xIndex,  
      
      slow_in          => "0000",
      RAMSIZE8         => '1',
                                          
      ddr3_BUSY        => DDRAM_BUSY,       
      ddr3_DOUT        => DDRAM_DOUT,       
      ddr3_DOUT_READY  => DDRAM_DOUT_READY, 
      ddr3_BURSTCNT    => DDRAM_BURSTCNT,   
      ddr3_ADDR        => DDRAM_ADDR,                           
      ddr3_DIN         => DDRAM_DIN,        
      ddr3_BE          => DDRAM_BE,         
      ddr3_WE          => DDRAM_WE,         
      ddr3_RD          => DDRAM_RD,         
                                          
      rdram_request    => rdram_request,   
      rdram_rnw        => rdram_rnw,       
      rdram_address    => rdram_address,   
      rdram_burstcount => rdram_burstcount,
      rdram_writeMask  => rdram_writeMask, 
      rdram_dataWrite  => rdram_dataWrite, 
      rdram_granted    => rdram_granted,      
      rdram_done       => rdram_done,      
      rdram_dataRead   => rdram_dataRead,  

      rspfifo_req      => '0',
      rspfifo_reset    => '0',
      rspfifo_Din      => 85x"0",
      rspfifo_Wr       => '0',
      rspfifo_nearfull => open,
      rspfifo_empty    => open,
      
      rdpfifo_reset    => '0',
      rdpfifo_Din      => 92x"0",
      rdpfifo_Wr       => '0',
      rdpfifo_nearfull => open,
      rdpfifo_empty    => open,

      rdpfifoZ_reset   => '0',
      rdpfifoZ_Din     => 92x"0",
      rdpfifoZ_Wr      => '0',
      rdpfifoZ_nearfull=> open,
      rdpfifoZ_empty   => open
   );   
   
   rdram_request(0 to 6) <= 7x"0";
   
   -- extern
   iddrram_model : entity work.ddrram_model
   generic map
   (
      LOADRDRAM    => '1',
      SLOWTIMING   => 15,
      RANDOMTIMING => '0' 
   )
   port map
   (
      DDRAM_CLK        => clk2x,      
      DDRAM_BUSY       => DDRAM_BUSY,      
      DDRAM_BURSTCNT   => DDRAM_BURSTCNT,  
      DDRAM_ADDR       => DDRAM_ADDR,      
      DDRAM_DOUT       => DDRAM_DOUT,      
      DDRAM_DOUT_READY => DDRAM_DOUT_READY,
      DDRAM_RD         => DDRAM_RD,        
      DDRAM_DIN        => DDRAM_DIN,       
      DDRAM_BE         => DDRAM_BE,        
      DDRAM_WE         => DDRAM_WE        
   );
   
   iSDRamMux : entity n64.SDRamMux
   port map
   (
      clk1x                => clk1x,
                           
      error                => open,
                           
      sdram_ena            => sdram_ena,      
      sdram_rnw            => sdram_rnw,      
      sdram_Adr            => sdram_Adr,      
      sdram_be             => sdram_be,       
      sdram_dataWrite      => sdram_dataWrite,
      sdram_done           => sdram_done,     
      sdram_dataRead       => sdram_dataRead, 
                           
      sdramMux_request     => sdramMux_request,   
      sdramMux_rnw         => sdramMux_rnw,       
      sdramMux_address     => sdramMux_address,   
      sdramMux_burstcount  => sdramMux_burstcount,
      sdramMux_writeMask   => sdramMux_writeMask, 
      sdramMux_dataWrite   => sdramMux_dataWrite, 
      sdramMux_granted     => sdramMux_granted,   
      sdramMux_done        => sdramMux_done,      
      sdramMux_dataRead    => sdramMux_dataRead,
      
      rdp9fifo_reset       => '0',
      rdp9fifo_Din         => 50x"0",
      rdp9fifo_Wr          => '0',
      rdp9fifo_nearfull    => open,
      rdp9fifo_empty       => open,
      
      rdp9fifoZ_reset      => '0',
      rdp9fifoZ_Din        => 50x"0",
      rdp9fifoZ_Wr         => '0',
      rdp9fifoZ_nearfull   => open,
      rdp9fifoZ_empty      => open
   );
   
   sdramMux_request(0 to 2) <= "000";
   sdramMux_request(4) <= '0';
   
   isdram_model : entity work.sdram_model
   generic map
   (
      DOREFRESH         => '0',
      INITFILE          => "NONE",
      SCRIPTLOADING     => '1',
      FILELOADING       => '0'
   )
   port map
   (
      clk               => clk1x,
      addr              => sdram_Adr,
      req               => sdram_ena,
      rnw               => sdram_rnw,
      be                => sdram_be,
      di                => sdram_dataWrite,
      do                => sdram_dataRead,
      done              => sdram_done,
      fileSize          => open
   );
   
   iframebuffer : entity work.framebuffer
   port map
   (
      clk               => clkvid,       
      hblank            => video_hblank,  
      vblank            => video_vblank,  
      video_ce          => video_ce,
      video_interlace   => video_interlace,
      video_r           => video_r, 
      video_g           => video_g,    
      video_b           => video_b  
   );
   
   itb_savestates : entity work.tb_savestates
   generic map
   (
      LOADSTATE         => '1',
      --FILENAME          => ""
   )
   port map
   (
      clk               => clk1x,         
      reset_in          => reset_in,    
      reset_out         => reset_out,
      loading_savestate => loading_savestate,      
      SS_reset          => SS_reset,    
      SS_DataWrite      => SS_DataWrite,
      SS_Adr            => SS_Adr,      
      SS_wren           => SS_wren     
   );
   
   process -- simulate interlaced register changes 
   begin
      wait until rising_edge(video_interlace);
      bus_VI_addr      <= x"00004";
      bus_VI_dataWrite <= x"001767c0";
      bus_VI_write     <= '1';
      wait until rising_edge(clk1x);
      bus_VI_write     <= '0';
      wait until rising_edge(clk1x);
      
      wait until falling_edge(video_interlace);
      bus_VI_addr      <= x"00004";
      bus_VI_dataWrite <= x"0020ccc0";
      bus_VI_write     <= '1';
      wait until rising_edge(clk1x);
      bus_VI_write     <= '0';
      wait until rising_edge(clk1x);
   end process;  
      
   
end architecture;


