library IEEE;
use IEEE.std_logic_1164.all;  
use IEEE.numeric_std.all; 

library mem;
use work.pVI.all;

entity VI_videoout is
   generic
   (
      use2Xclock                       : in  std_logic;
      VITEST                           : in  std_logic
   );          
   port           
   (           
      clk1x                            : in  std_logic;
      clk2x                            : in  std_logic;
      clkvid                           : in  std_logic;
      ce                               : in  std_logic;
      reset_1x                         : in  std_logic;
                  
      ISPAL                            : in  std_logic;
		ASPECTRATIO                      : in  unsigned(1 downto 0);
      CROPBOTTOM                       : in  unsigned(1 downto 0);
      VI_BILINEAROFF                   : in  std_logic;
      VI_GAMMAOFF                      : in  std_logic;
      VI_DEDITHEROFF                   : in  std_logic;
      VI_AAOFF                         : in  std_logic;
                  
      errorEna                         : in  std_logic;
      errorCode                        : in  unsigned(23 downto 0);
                  
      fpscountOn                       : in  std_logic;
      fpscountBCD                      : in  unsigned(7 downto 0);  
                  
      VI_CTRL_TYPE                     : in unsigned(1 downto 0);
      VI_CTRL_AA_MODE                  : in unsigned(1 downto 0);
      VI_CTRL_SERRATE                  : in std_logic;
      VI_CTRL_GAMMA_ENABLE             : in std_logic;
      VI_CTRL_DEDITHER_FILTER_ENABLE   : in std_logic;
      VI_ORIGIN                        : in unsigned(23 downto 0);
      VI_WIDTH                         : in unsigned(11 downto 0);
      VI_X_SCALE_FACTOR                : in unsigned(11 downto 0);
      VI_X_SCALE_OFFSET                : in unsigned(11 downto 0);
      VI_Y_SCALE_FACTOR                : in unsigned(11 downto 0);
      VI_Y_SCALE_OFFSET                : in unsigned(11 downto 0);
      VI_V_VIDEO_START                 : in unsigned(9 downto 0);
      VI_V_VIDEO_END                   : in unsigned(9 downto 0);
      VI_H_VIDEO_START                 : in unsigned(9 downto 0);
      VI_H_VIDEO_END                   : in unsigned(9 downto 0);
                  
      newLine                          : out std_logic;
      VI_CURRENT                       : out unsigned(9 downto 0);
                  
      rdram_request                    : out std_logic := '0';
      rdram_rnw                        : out std_logic := '0'; 
      rdram_address                    : out unsigned(27 downto 0):= (others => '0');
      rdram_burstcount                 : out unsigned(9 downto 0):= (others => '0');
      rdram_granted                    : in  std_logic;
      rdram_done                       : in  std_logic;
      ddr3_DOUT                        : in  std_logic_vector(63 downto 0);
      ddr3_DOUT_READY                  : in  std_logic;
                  
      sdram_request                    : out std_logic := '0';
      sdram_rnw                        : out std_logic := '0'; 
      sdram_address                    : out unsigned(26 downto 0):= (others => '0');
      sdram_burstcount                 : out unsigned(7 downto 0):= (others => '0');
      sdram_granted                    : in  std_logic;
      sdram_done                       : in  std_logic;
      sdram_dataRead                   : in  std_logic_vector(31 downto 0);
      sdram_valid                      : in  std_logic;
                  
      video_hsync                      : out std_logic := '0';
      video_vsync                      : out std_logic := '0';
      video_hblank                     : out std_logic := '0';
      video_vblank                     : out std_logic := '0';
      video_ce                         : out std_logic;
      video_interlace                  : out std_logic;
      video_r                          : out std_logic_vector(7 downto 0);
      video_g                          : out std_logic_vector(7 downto 0);
      video_b                          : out std_logic_vector(7 downto 0);
                  
      SS_VI_CURRENT                    : in unsigned(9 downto 0);
      SS_nextHCount                    : in unsigned(11 downto 0)
   );
end entity;

architecture arch of VI_videoout is

   function to_unsigned(a : string) return unsigned is
      variable ret : unsigned(a'length*8-1 downto 0);
   begin
      for i in 1 to a'length loop
         ret((a'length - i)*8+7 downto (a'length - i)*8) := to_unsigned(character'pos(a(i)), 8);
      end loop;
      return ret;
   end function to_unsigned;
   
   function conv_number(a : unsigned) return unsigned is
      variable ret : unsigned((a'length * 2) -1 downto 0);
   begin
      for i in 0 to (a'length / 4)-1 loop
         if (a(((i * 4) + 3) downto (i * 4)) < 10) then
            ret(((i * 8) + 7) downto (i * 8)) := resize(a(((i * 4) + 3) downto (i * 4)), 8) + 16#30#;
         else
            ret(((i * 8) + 7) downto (i * 8)) := resize(a(((i * 4) + 3) downto (i * 4)), 8) + 16#37#;
         end if;
      end loop;
      return ret;
   end function conv_number;

   signal videoout_settings       : tvideoout_settings;
   signal videoout_reports        : tvideoout_reports;
   signal videoout_out            : tvideoout_out; 
   signal videoout_request        : tvideoout_request;  

   -- processing
   signal rdram_storeAddr     : unsigned(8 downto 0);
   signal rdram_store         : std_logic_vector(2 downto 0);   
   
   signal rdram9_storeAddr    : unsigned(5 downto 0);
   signal rdram9_store        : std_logic_vector(2 downto 0);
   
   signal addr9_offset        : taddr9offset;
   signal startProc           : std_logic; 
   signal procPtr             : std_logic_vector(2 downto 0);
   signal procDone            : std_logic; 
   signal startOut            : std_logic; 
   signal fracYout            : unsigned(4 downto 0);
   
   signal fetchAddr           : unsigned(9 downto 0);
   signal fetchAddr9          : unsigned(9 downto 0);
   type tfetchDataArray is array(0 to 2) of std_logic_vector(31 downto 0);
   signal fetchDataArray      : tfetchDataArray;
   signal fetchdata           : tfetchArray;
   type tfetchDataArray9 is array(0 to 2) of std_logic_vector(1 downto 0);
   signal fetchDataArray9     : tfetchDataArray9;
   signal fetchdata9          : tfetchArray9;
                              
   signal proc_pixel          : std_logic;
   signal proc_border         : std_logic;
   signal proc_x              : unsigned(9 downto 0);        
   signal proc_y              : unsigned(9 downto 0);
   signal proc_pixel_Mid      : tfetchelement;
   signal proc_pixels_AA      : tfetcharray_AA;
   signal proc_pixels_DD      : tfetcharray_DD;

   signal filter_pixel        : std_logic;
   signal filter_x_out        : unsigned(9 downto 0);        
   signal filter_y_out        : unsigned(9 downto 0);
   signal filter_color        : tfetchelement;

   signal filterram_addr_A    : std_logic_vector(10 downto 0);
   signal filterram_addr_B    : std_logic_vector(10 downto 0);
   signal filterram_di_A      : std_logic_vector(23 downto 0);
   signal filterram_do_B      : std_logic_vector(23 downto 0);
   
   signal filterAddr          : unsigned(10 downto 0);
      
   signal out_pixel           : std_logic;
   signal out_x               : unsigned(9 downto 0);        
   signal out_y               : unsigned(9 downto 0);
   signal out_color           : unsigned(23 downto 0);
   
   signal outram_addr_A       : std_logic_vector(10 downto 0);
   signal outram_addr_B       : std_logic_vector(10 downto 0);
   signal outram_di_A         : std_logic_vector(23 downto 0);
   signal outram_do_B         : std_logic_vector(23 downto 0);
   
   signal videoout_readAddr   : unsigned(10 downto 0);

   -- overlay
   signal overlay_data        : std_logic_vector(23 downto 0);
   signal overlay_ena         : std_logic;
   
   signal fpstext             : unsigned(15 downto 0);
   signal overlay_fps_data    : std_logic_vector(23 downto 0);
   signal overlay_fps_ena     : std_logic;
   
   signal errortext           : unsigned(47 downto 0);
   signal overlay_error_data  : std_logic_vector(23 downto 0);
   signal overlay_error_ena   : std_logic;   
   
begin 
  
   video_hsync          <= videoout_out.hsync;         
   video_vsync          <= videoout_out.vsync;         
   video_hblank         <= videoout_out.hblank;        
   video_vblank         <= videoout_out.vblank;        
   video_ce             <= videoout_out.ce;             
   video_interlace      <= videoout_out.interlace;             
   video_r              <= videoout_out.r;             
   video_g              <= videoout_out.g;             
   video_b              <= videoout_out.b;  

   videoout_settings.CTRL_TYPE      <= VI_CTRL_TYPE;
   videoout_settings.CTRL_SERRATE   <= VI_CTRL_SERRATE;
   videoout_settings.X_SCALE_FACTOR <= VI_X_SCALE_FACTOR;
   videoout_settings.VI_WIDTH       <= VI_WIDTH;
   videoout_settings.isPAL          <= ISPAL;
   videoout_settings.videoSizeY     <= VI_V_VIDEO_END - VI_V_VIDEO_START - to_integer(videoout_settings.cropBottom & "0000");
   videoout_settings.aspectRatio    <= ASPECTRATIO;
	videoout_settings.cropBottom     <= CROPBOTTOM;
   
   newLine    <= videoout_reports.newLine;
   VI_CURRENT <= videoout_reports.VI_CURRENT & '0'; -- todo: need to find when interlace sets bit 0, can't be instant, otherwise Kroms CPU tests would hang in infinite loop  
   
   iVI_linefetch : entity work.VI_linefetch
   port map
   (
      clk1x              => clk1x,              
      clk2x              => clk2x,              
      reset              => reset_1x,           
                                        
      VI_CTRL_TYPE       => VI_CTRL_TYPE,     
      VI_CTRL_SERRATE    => VI_CTRL_SERRATE,  
      VI_ORIGIN          => VI_ORIGIN,        
      VI_WIDTH           => VI_WIDTH,         
      VI_X_SCALE_FACTOR  => VI_X_SCALE_FACTOR,
      VI_Y_SCALE_FACTOR  => VI_Y_SCALE_FACTOR,
      VI_Y_SCALE_OFFSET  => VI_Y_SCALE_OFFSET,
                        
      newFrame           => videoout_reports.newFrame,
      lineNr             => videoout_request.lineInNext,
      fetch              => videoout_request.fetch,
      
      addr9_offset       => addr9_offset,
      startProc          => startProc,
      procPtr            => procPtr,
      procDone           => procDone,
      startOut           => startOut,
      fracYout           => fracYout,
      
      rdram_request      => rdram_request,   
      rdram_rnw          => rdram_rnw,       
      rdram_address      => rdram_address,   
      rdram_burstcount   => rdram_burstcount,
      rdram_granted      => rdram_granted,   
      rdram_done         => rdram_done,      
      ddr3_DOUT_READY    => ddr3_DOUT_READY, 
      rdram_store        => rdram_store,     
      rdram_storeAddr    => rdram_storeAddr,
      
      sdram_request      => sdram_request,    
      sdram_rnw          => sdram_rnw,        
      sdram_address      => sdram_address,    
      sdram_burstcount   => sdram_burstcount, 
      sdram_granted      => sdram_granted,    
      sdram_done         => sdram_done,       
      sdram_valid        => sdram_valid,      
      rdram9_store       => rdram9_store,     
      rdram9_storeAddr   => rdram9_storeAddr
   );
   
   glinerams: for i in 0 to 2 generate
      signal addr9_corrected : unsigned(9 downto 0);
   begin
      ilineram: entity mem.dpram_dif
      generic map 
      ( 
         addr_width_a  => 9,
         data_width_a  => 64,
         addr_width_b  => 10,
         data_width_b  => 32
      )
      port map
      (
         clock_a     => clk2x,
         address_a   => std_logic_vector(rdram_storeAddr),
         data_a      => ddr3_DOUT,
         wren_a      => (ddr3_DOUT_READY and rdram_store(i)),
         
         clock_b     => clk1x,
         address_b   => std_logic_vector(fetchAddr),
         data_b      => 32x"0",
         wren_b      => '0',
         q_b         => fetchDataArray(i)
      );   
      
      addr9_corrected <= fetchAddr9 + addr9_offset(i);
      
      ilineram9: entity mem.dpram_dif
      generic map 
      ( 
         addr_width_a  => 6,
         data_width_a  => 32,
         addr_width_b  => 10,
         data_width_b  => 2
      )
      port map
      (
         clock_a     => clk1x,
         address_a   => std_logic_vector(rdram9_storeAddr),
         data_a      => sdram_dataRead,
         wren_a      => (sdram_valid and rdram9_store(i)),
         
         clock_b     => clk1x,
         address_b   => std_logic_vector(addr9_corrected),
         data_b      => 2x"0",
         wren_b      => '0',
         q_b         => fetchDataArray9(i)
      );   
   end generate;
   
   fetchdata(0) <= unsigned(fetchDataArray(0)) when (procPtr(2) = '1') else
                   unsigned(fetchDataArray(1)) when (procPtr(0) = '1') else
                   unsigned(fetchDataArray(2));
                 
   fetchdata(1) <= unsigned(fetchDataArray(1)) when (procPtr(2) = '1') else
                   unsigned(fetchDataArray(2)) when (procPtr(0) = '1') else
                   unsigned(fetchDataArray(0));
              
   fetchdata(2) <= unsigned(fetchDataArray(2)) when (procPtr(2) = '1') else
                   unsigned(fetchDataArray(0)) when (procPtr(0) = '1') else
                   unsigned(fetchDataArray(1));
   
   fetchdata9(0) <= unsigned(fetchDataArray9(0)) when (procPtr(2) = '1') else
                    unsigned(fetchDataArray9(1)) when (procPtr(0) = '1') else
                    unsigned(fetchDataArray9(2));
                 
   fetchdata9(1) <= unsigned(fetchDataArray9(1)) when (procPtr(2) = '1') else
                    unsigned(fetchDataArray9(2)) when (procPtr(0) = '1') else
                    unsigned(fetchDataArray9(0));
              
   fetchdata9(2) <= unsigned(fetchDataArray9(2)) when (procPtr(2) = '1') else
                    unsigned(fetchDataArray9(0)) when (procPtr(0) = '1') else
                    unsigned(fetchDataArray9(1));
   
   iVI_lineProcess : entity work.VI_lineProcess
   port map
   (
      clk1x              => clk1x,         
      reset              => reset_1x,         
                         
      VI_CTRL_TYPE       => VI_CTRL_TYPE,  
      VI_WIDTH           => VI_WIDTH,      
                         
      newFrame           => videoout_reports.newFrame,          
      startProc          => startProc,     
      procDone           => procDone,     
                         
      fetchAddr          => fetchAddr,     
      fetchdata          => fetchdata,
      fetchAddr9         => fetchAddr9,
      fetchdata9         => fetchdata9,
                         
      proc_pixel         => proc_pixel,    
      proc_border        => proc_border,    
      proc_x             => proc_x,              
      proc_y             => proc_y,        
      proc_pixel_Mid     => proc_pixel_Mid,
      proc_pixels_AA     => proc_pixels_AA,
      proc_pixels_DD     => proc_pixels_DD
   );
   
   iVI_filter: entity work.VI_filter
   port map
   (
      clk1x                            => clk1x, 
      reset                            => reset_1x,
      
      VI_DEDITHEROFF                   => VI_DEDITHEROFF,
      VI_AAOFF                         => VI_AAOFF,
      
      VI_CTRL_AA_MODE                  => VI_CTRL_AA_MODE,
      VI_CTRL_DEDITHER_FILTER_ENABLE   => VI_CTRL_DEDITHER_FILTER_ENABLE,
                    
      proc_pixel                       => proc_pixel,    
      proc_border                      => proc_border,    
      proc_x                           => proc_x,         
      proc_y                           => proc_y,        
      proc_pixel_Mid                   => proc_pixel_Mid,
      proc_pixels_AA                   => proc_pixels_AA,
      proc_pixels_DD                   => proc_pixels_DD,
                        
      filter_pixel                     => filter_pixel,
      filter_x_out                     => filter_x_out, 
      filter_y_out                     => filter_y_out, 
      filter_color                     => filter_color
   );
   
   filterram_addr_A <= filter_y_out(0) & std_logic_vector(filter_x_out);
   filterram_di_A   <= std_logic_vector(filter_color.r) & std_logic_vector(filter_color.g) & std_logic_vector(filter_color.b);

   ifilterRAM: entity mem.dpram
   generic map 
   ( 
      addr_width  => 11,
      data_width  => 24
   )
   port map
   (
      clock_a     => clk1x,
      address_a   => filterram_addr_A,
      data_a      => filterram_di_A,
      wren_a      => filter_pixel,
      
      clock_b     => clk1x,
      address_b   => filterram_addr_B,
      data_b      => 24x"0",
      wren_b      => '0',
      q_b         => filterram_do_B
   );   
   
   filterram_addr_B <= std_logic_vector(filterAddr);
   
   iVI_outProcess : entity work.VI_outProcess
   port map
   (
      clk1x                   => clk1x,           
      reset                   => reset_1x,        
      
      ISPAL                   => ISPAL,
      VI_BILINEAROFF          => VI_BILINEAROFF,
      VI_GAMMAOFF             => VI_GAMMAOFF,
                        
      VI_CTRL_GAMMA_ENABLE    => VI_CTRL_GAMMA_ENABLE,
      VI_H_VIDEO_START        => VI_H_VIDEO_START,
      VI_H_VIDEO_END          => VI_H_VIDEO_END,  
      VI_X_SCALE_FACTOR       => VI_X_SCALE_FACTOR,
      VI_X_SCALE_OFFSET       => VI_X_SCALE_OFFSET,
                              
      newFrame                => videoout_reports.newFrame,             
      startOut                => startOut,        
      fracYout                => fracYout,        
                              
      filter_y                => filter_y_out(0),
      filterAddr              => filterAddr,      
      filterData              => unsigned(filterram_do_B),      
                              
      out_pixel               => out_pixel,       
      out_x                   => out_x,               
      out_y                   => out_y,           
      out_color               => out_color       
   );
   
   outram_addr_A <= out_y(0) & std_logic_vector(out_x);
   outram_di_A   <= std_logic_vector(out_color);

   ioutRAM: entity mem.dpram
   generic map 
   ( 
      addr_width  => 11,
      data_width  => 24
   )
   port map
   (
      clock_a     => clk1x,
      address_a   => outram_addr_A,
      data_a      => outram_di_A,
      wren_a      => out_pixel,
      
      clock_b     => clk1x,
      address_b   => outram_addr_B,
      data_b      => 24x"0",
      wren_b      => '0',
      q_b         => outram_do_B
   );   
   
   outram_addr_B <= std_logic_vector(videoout_readAddr);

   ivi_videoout_sync : entity work.vi_videoout_sync
   generic map
   (
      VITEST           => VITEST
   )
   port map
   (
      clk1x                   => clk1x,
      ce                      => ce,   
      reset                   => reset_1x,
               
      videoout_settings       => videoout_settings,
      videoout_reports        => videoout_reports,                 
                                                                      
      videoout_request        => videoout_request, 
      videoout_readAddr       => videoout_readAddr,  
      videoout_pixelRead      => outram_do_B,   
   
      overlay_data            => overlay_data,
      overlay_ena             => overlay_ena,                     
                   
      videoout_out            => videoout_out,

      SS_VI_CURRENT           => SS_VI_CURRENT,
      SS_nextHCount           => SS_nextHCount
   );  
   
   -- texts
   fpstext( 7 downto 0) <= resize(fpscountBCD(3 downto 0), 8) + 16#30#;
   fpstext(15 downto 8) <= resize(fpscountBCD(7 downto 4), 8) + 16#30#;
   
   ioverlayFPS : entity work.VI_overlay generic map (2, 4, 4, x"0000FF")
   port map
   (
      clk                    => clk1x,
      ce                     => videoout_out.ce,
      ena                    => fpscountOn,                    
      i_pixel_out_x          => videoout_request.xpos,
      i_pixel_out_y          => to_integer(videoout_request.lineDisp),
      o_pixel_out_data       => overlay_fps_data,
      o_pixel_out_ena        => overlay_fps_ena,
      textstring             => fpstext
   );
   
   errortext( 7 downto  0) <= resize(errorCode( 3 downto  0), 8) + 16#30# when (errorCode( 3 downto  0) < 10) else resize(errorCode( 3 downto  0), 8) + 16#37#;
   errortext(15 downto  8) <= resize(errorCode( 7 downto  4), 8) + 16#30# when (errorCode( 7 downto  4) < 10) else resize(errorCode( 7 downto  4), 8) + 16#37#;
   errortext(23 downto 16) <= resize(errorCode(11 downto  8), 8) + 16#30# when (errorCode(11 downto  8) < 10) else resize(errorCode(11 downto  8), 8) + 16#37#;
   errortext(31 downto 24) <= resize(errorCode(15 downto 12), 8) + 16#30# when (errorCode(15 downto 12) < 10) else resize(errorCode(15 downto 12), 8) + 16#37#;
   errortext(39 downto 32) <= resize(errorCode(19 downto 16), 8) + 16#30# when (errorCode(19 downto 16) < 10) else resize(errorCode(19 downto 16), 8) + 16#37#;
   errortext(47 downto 40) <= resize(errorCode(23 downto 20), 8) + 16#30# when (errorCode(23 downto 20) < 10) else resize(errorCode(23 downto 20), 8) + 16#37#;
   ioverlayError : entity work.VI_overlay generic map (7, 4, 44, x"0000FF")
   port map
   (
      clk                    => clk1x,
      ce                     => videoout_out.ce,
      ena                    => errorEna,                    
      i_pixel_out_x          => videoout_request.xpos,
      i_pixel_out_y          => to_integer(videoout_request.lineDisp),
      o_pixel_out_data       => overlay_error_data,
      o_pixel_out_ena        => overlay_error_ena,
      textstring             => x"45" & errortext
   ); 
   
   overlay_ena <= overlay_fps_ena or overlay_error_ena;
   
   overlay_data <= overlay_fps_data   when (overlay_fps_ena = '1') else
                   overlay_error_data when (overlay_error_ena = '1') else
                   (others => '0');
   
end architecture;





