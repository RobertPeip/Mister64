library IEEE;
use IEEE.std_logic_1164.all;  
use IEEE.numeric_std.all; 

library mem;

entity VI is
   generic
   (
      use2Xclock       : in  std_logic;
      VITEST           : in  std_logic := '0'
   );
   port 
   (
      clk1x            : in  std_logic;
      clk2x            : in  std_logic;
      clkvid           : in  std_logic;
      ce               : in  std_logic;
      reset_1x         : in  std_logic;
      
      irq_out          : out std_logic := '0';
      
      second_ena       : out std_logic := '0';
      
      ISPAL            : in  std_logic;
		ASPECTRATIO      : in  unsigned(1 downto 0);
      CROPBOTTOM       : in  unsigned(1 downto 0);
      VI_BILINEAROFF   : in  std_logic;
      VI_GAMMAOFF      : in  std_logic;
      VI_DEDITHEROFF   : in  std_logic;
      VI_AAOFF         : in  std_logic;
      
      errorEna         : in  std_logic;
      errorCode        : in  unsigned(23 downto 0);
      fpscountOn       : in  std_logic;
      
      rdram_request    : out std_logic := '0';
      rdram_rnw        : out std_logic := '0'; 
      rdram_address    : out unsigned(27 downto 0):= (others => '0');
      rdram_burstcount : out unsigned(9 downto 0):= (others => '0');
      rdram_granted    : in  std_logic;
      rdram_done       : in  std_logic;
      ddr3_DOUT        : in  std_logic_vector(63 downto 0);
      ddr3_DOUT_READY  : in  std_logic;
      
      sdram_request    : out std_logic := '0';
      sdram_rnw        : out std_logic := '0'; 
      sdram_address    : out unsigned(26 downto 0):= (others => '0');
      sdram_burstcount : out unsigned(7 downto 0):= (others => '0');
      sdram_granted    : in  std_logic;
      sdram_done       : in  std_logic;
      sdram_dataRead   : in  std_logic_vector(31 downto 0);
      sdram_valid      : in  std_logic;
      
      video_hsync      : out std_logic := '0';
      video_vsync      : out std_logic := '0';
      video_hblank     : out std_logic := '0';
      video_vblank     : out std_logic := '0';
      video_ce         : out std_logic;
      video_interlace  : out std_logic;
      video_r          : out std_logic_vector(7 downto 0);
      video_g          : out std_logic_vector(7 downto 0);
      video_b          : out std_logic_vector(7 downto 0);
      
      bus_addr         : in  unsigned(19 downto 0); 
      bus_dataWrite    : in  std_logic_vector(31 downto 0);
      bus_read         : in  std_logic;
      bus_write        : in  std_logic;
      bus_dataRead     : out std_logic_vector(31 downto 0) := (others => '0');
      bus_done         : out std_logic := '0';
      
      SS_reset         : in  std_logic;
      SS_DataWrite     : in  std_logic_vector(63 downto 0);
      SS_Adr           : in  unsigned(2 downto 0);
      SS_wren          : in  std_logic;
      SS_rden          : in  std_logic;
      SS_DataRead      : out std_logic_vector(63 downto 0)
   );
end entity;

architecture arch of VI is

   -- 0x04400000 VI_STATUS
   signal VI_CTRL_TYPE                    : unsigned(1 downto 0):= (others => '0');    -- (RW) : [1:0] type[0 - 1](pixel size)  0 : blank(no data, no sync)  1 : reserved 2 : 5 / 5 / 5 / 3 ("16" bit) 3 : 8 / 8 / 8 / 8 (32 bit)
   signal VI_CTRL_GAMMA_DITHER_ENABLE     : std_logic := '0';                          -- [2] gamma_dither_enable(normally on, unless "special effect")
   signal VI_CTRL_GAMMA_ENABLE            : std_logic := '0';                          -- [3] gamma_enable(normally on, unless MPEG / JPEG)
   signal VI_CTRL_DIVOT_ENABLE            : std_logic := '0';                          -- [4] divot_enable(normally on if antialiased,unless decal lines) 
   signal VI_CTRL_VBUS_CLOCK_ENABLE       : std_logic := '0';                          -- [5] VBUS_CLOCK_ENABLE
   signal VI_CTRL_SERRATE                 : std_logic := '0';                          -- [6] serrate(always on if interlaced, off if not)
   signal VI_CTRL_TEST_MODE               : std_logic := '0';                          -- [7] TEST_MODE
   signal VI_CTRL_AA_MODE                 : unsigned(1 downto 0):= (others => '0');    -- [9:8] anti - alias(aa) mode[1:0] 0: aa & resamp(always fetch extra lines) 1 : aa & resamp(fetch extra lines if needed) 2 : resamp only(treat as all fully covered 3 : neither(replicate pixels, no interpolate)
   signal VI_CTRL_Reserved10              : std_logic := '0';                          -- [10] reserved
   signal VI_CTRL_KILL_WE                 : std_logic := '0';                          -- [11] KILL_WE
   signal VI_CTRL_PIXEL_ADVANCE           : unsigned(3 downto 0):= (others => '0');    -- ?
   signal VI_CTRL_DEDITHER_FILTER_ENABLE  : std_logic := '0';                          -- [16] DEDITHER_FILTER_ENABLE, 1 = Dedither filter is enabled (normally used for 16-bit framebuffers; this may cause vertical banding if anti-aliasing is disabled, 0 = Dedither filter is disabled (normally used for 32-bit color) 

   signal VI_ORIGIN                       : unsigned(23 downto 0) := (others => '0');  -- 0x04400004 (RW): [23:0] frame buffer origin in bytes
   signal VI_WIDTH                        : unsigned(11 downto 0) := (others => '0');  -- 0x04400008 (RW): [11:0] frame buffer line width in pixels 
   signal VI_INTR                         : unsigned( 9 downto 0) := (others => '0');  -- 0x0440000C (RW): [9:0] interrupt when current half-line = V_INTR
   signal VI_CURRENT                      : unsigned( 9 downto 0) := (others => '0');  -- 0x04400010 (RW): [9:0] current half line, sampled once per line (the lsb of V_CURRENT is constant within a field, and in interlaced modes gives the field number - which is constant for non - interlaced modes)  - Writes clears interrupt line
   signal VI_BURST_HWIDTH                 : unsigned( 7 downto 0) := (others => '0');  -- 0x04400014 (RW): [7:0] horizontal sync width in pixels
   signal VI_BURST_BURSTWIDTH             : unsigned( 7 downto 0) := (others => '0');  -- 0x04400014 (RW): [15:8] color burst width in pixels
   signal VI_BURST_VWIDTH                 : unsigned( 3 downto 0) := (others => '0');  -- 0x04400014 (RW): [19:16] vertical sync width in half lines 
   signal VI_BURST_START                  : unsigned( 9 downto 0) := (others => '0');  -- 0x04400014 (RW): [29:20] start of color burst in pixels from h - sync
   signal VI_V_SYNC                       : unsigned( 9 downto 0) := (others => '0');  -- 0x04400018 (RW): [9:0] number of half-lines per field
   signal VI_H_SYNC_WIDTH                 : unsigned(11 downto 0) := (others => '0');  -- 0x0440001C (RW): [11:0] total duration of a line in 1/4 pixel
   signal VI_H_SYNC_LEAP                  : unsigned( 4 downto 0) := (others => '0');  -- 0x0440001C (RW): [20:16] a 5 - bit leap pattern used for PAL only(h_sync_period)
   signal VI_LEAP_A                       : unsigned(11 downto 0) := (others => '0');  -- 0x04400020 (RW): [11:0] identical to h_sync_period
   signal VI_LEAP_B                       : unsigned(11 downto 0) := (others => '0');  -- 0x04400020 (RW): [27:16] identical to h_sync_period
   signal VI_H_VIDEO_END                  : unsigned( 9 downto 0) := (others => '0');  -- 0x04400024 (RW): [9:0] end of active video in screen pixels
   signal VI_H_VIDEO_START                : unsigned( 9 downto 0) := (others => '0');  -- 0x04400024 (RW): [25:16] start of active video in screen pixels
   signal VI_V_VIDEO_END                  : unsigned( 9 downto 0) := (others => '0');  -- 0x04400028 (RW): [9:0] end of active video in screen half-lines
   signal VI_V_VIDEO_START                : unsigned( 9 downto 0) := (others => '0');  -- 0x04400028 (RW): [25:16] start of active video in screen half - lines
   signal VI_V_BURST_END                  : unsigned( 9 downto 0) := (others => '0');  -- 0x0440002C (RW): [9:0] end of color burst enable in half-lines
   signal VI_V_BURST_START                : unsigned( 9 downto 0) := (others => '0');  -- 0x0440002C (RW): [25:16] start of color burst enable in half - lines
   signal VI_X_SCALE_FACTOR               : unsigned(11 downto 0) := (others => '0');  -- 0x04400030 (RW): [11:0] 1/horizontal scale up factor (2.10 format)
   signal VI_X_SCALE_OFFSET               : unsigned(11 downto 0) := (others => '0');  -- 0x04400030 (RW): [27:16] horizontal subpixel offset(2.10 format)
   signal VI_Y_SCALE_FACTOR               : unsigned(11 downto 0) := (others => '0');  -- 0x04400034 (RW): [11:0] 1/vertical scale up factor (2.10 format)
   signal VI_Y_SCALE_OFFSET               : unsigned(11 downto 0) := (others => '0');  -- 0x04400034 (RW): [27:16] vertical subpixel offset(2.10 format)
   signal VI_TEST_ADDR                    : unsigned( 6 downto 0) := (others => '0');  -- 0x04400038 (RW): [6:0] TEST_ADDR<6:0>: Diagnostics only, usage unknown 
   signal VI_STAGED_DATA                  : unsigned(31 downto 0) := (others => '0');  -- 0x0440003C (RW): [31:0] STAGED_DATA<31:0>: Diagnostics only, usage unknown 

   signal newLine                         : std_logic;
   
   -- fps counter
   signal fpscountBCD               : unsigned(7 downto 0) := (others => '0');
   signal fpscountBCD_next          : unsigned(7 downto 0) := (others => '0');
   signal fps_SecondCounter         : integer range 0 to 62499999 := 0;
   signal fps_VI_ORIGIN_last        : unsigned(23 downto 0) := (others => '0');
   signal fps_vsync                 : std_logic := '0';

   -- savestates
   type t_ssarray is array(0 to 7) of std_logic_vector(63 downto 0);
   signal ss_in  : t_ssarray := (others => (others => '0'));  
   signal ss_out : t_ssarray := (others => (others => '0')); 

begin 

   process (clk1x)
   begin
      if rising_edge(clk1x) then
      
         if (reset_1x = '1') then
            
            bus_done             <= '0';
            irq_out              <= '0';

            VI_CTRL_TYPE                   <= unsigned(ss_in(0)(1 downto 0));  
            VI_CTRL_GAMMA_DITHER_ENABLE    <= ss_in(0)(2);
            VI_CTRL_GAMMA_ENABLE           <= ss_in(0)(3);
            VI_CTRL_DIVOT_ENABLE           <= ss_in(0)(4);
            VI_CTRL_VBUS_CLOCK_ENABLE      <= ss_in(0)(5);
            VI_CTRL_SERRATE                <= ss_in(0)(6);
            VI_CTRL_TEST_MODE              <= ss_in(0)(7);
            VI_CTRL_AA_MODE                <= unsigned(ss_in(0)(9 downto 8));  
            VI_CTRL_Reserved10             <= ss_in(0)(10);
            VI_CTRL_KILL_WE                <= ss_in(0)(11);
            VI_CTRL_PIXEL_ADVANCE          <= unsigned(ss_in(0)(15 downto 12));  
            VI_CTRL_DEDITHER_FILTER_ENABLE <= ss_in(0)(62);
            
            VI_ORIGIN                      <= unsigned(ss_in(0)(39 downto 16));  
            VI_WIDTH                       <= unsigned(ss_in(0)(51 downto 40));             
            VI_INTR                        <= unsigned(ss_in(0)(61 downto 52));
            --VI_CURRENT                     <= unsigned(ss_in(1)(9 downto 0));             
            VI_BURST_HWIDTH                <= unsigned(ss_in(1)(17 downto 10));             
            VI_BURST_BURSTWIDTH            <= unsigned(ss_in(1)(25 downto 18));             
            VI_BURST_VWIDTH                <= unsigned(ss_in(1)(29 downto 26));             
            VI_BURST_START                 <= unsigned(ss_in(1)(39 downto 30));             
            VI_V_SYNC                      <= unsigned(ss_in(1)(49 downto 40));   
            VI_TEST_ADDR                   <= unsigned(ss_in(1)(56 downto 50)); 
            VI_H_SYNC_WIDTH                <= unsigned(ss_in(2)(11 downto  0));             
            VI_H_SYNC_LEAP                 <= unsigned(ss_in(2)(20 downto 16));             
            VI_LEAP_A                      <= unsigned(ss_in(2)(32 downto 21));             
            VI_LEAP_B                      <= unsigned(ss_in(2)(48 downto 37)); 
            VI_H_VIDEO_END                 <= unsigned(ss_in(3)( 9 downto  0));             
            VI_H_VIDEO_START               <= unsigned(ss_in(3)(25 downto 16));             
            VI_V_VIDEO_END                 <= unsigned(ss_in(3)(35 downto 26));             
            VI_V_VIDEO_START               <= unsigned(ss_in(3)(51 downto 42));   
            VI_V_BURST_END                 <= unsigned(ss_in(4)(9 downto 0));             
            VI_V_BURST_START               <= unsigned(ss_in(4)(25 downto 16));             
            VI_X_SCALE_FACTOR              <= unsigned(ss_in(5)(11 downto  0));             
            VI_X_SCALE_OFFSET              <= unsigned(ss_in(5)(27 downto 16));             
            VI_Y_SCALE_FACTOR              <= unsigned(ss_in(5)(43 downto 32));             
            VI_Y_SCALE_OFFSET              <= unsigned(ss_in(5)(59 downto 48));                         
            VI_STAGED_DATA                 <= unsigned(ss_in(4)(63 downto 32));  

            fpscountBCD_next               <= (others => '0');            

         elsif (ce = '1') then
         
            bus_done     <= '0';
            bus_dataRead <= (others => '0');
            
            if (newLine = '1' and VI_CURRENT = VI_INTR) then
               irq_out <= '1';
            end if;

            -- bus read
            if (bus_read = '1') then
               bus_done <= '1';
               case (bus_addr(19 downto 2) & "00") is
                  when x"00000" => 
                     bus_dataRead(1 downto 0)   <= std_logic_vector(VI_CTRL_TYPE); 
                     bus_dataRead(2)            <= VI_CTRL_GAMMA_DITHER_ENABLE; 
                     bus_dataRead(3)            <= VI_CTRL_GAMMA_ENABLE; 
                     bus_dataRead(4)            <= VI_CTRL_DIVOT_ENABLE; 
                     bus_dataRead(5)            <= VI_CTRL_VBUS_CLOCK_ENABLE; 
                     bus_dataRead(6)            <= VI_CTRL_SERRATE; 
                     bus_dataRead(7)            <= VI_CTRL_TEST_MODE; 
                     bus_dataRead(9 downto 8)   <= std_logic_vector(VI_CTRL_AA_MODE); 
                     bus_dataRead(10)           <= VI_CTRL_Reserved10; 
                     bus_dataRead(11)           <= VI_CTRL_KILL_WE; 
                     bus_dataRead(15 downto 12) <= std_logic_vector(VI_CTRL_PIXEL_ADVANCE); 
                     bus_dataRead(16)           <= VI_CTRL_DEDITHER_FILTER_ENABLE; 
                     
                  when x"00004" => bus_dataRead(23 downto  0) <= std_logic_vector(VI_ORIGIN          );    
                  when x"00008" => bus_dataRead(11 downto  0) <= std_logic_vector(VI_WIDTH           );    
                  when x"0000C" => bus_dataRead( 9 downto  0) <= std_logic_vector(VI_INTR            );    
                  when x"00010" => bus_dataRead( 9 downto  0) <= std_logic_vector(VI_CURRENT         );    
                  when x"00014" => bus_dataRead( 7 downto  0) <= std_logic_vector(VI_BURST_HWIDTH    );    
                                   bus_dataRead(15 downto  8) <= std_logic_vector(VI_BURST_BURSTWIDTH);    
                                   bus_dataRead(19 downto 16) <= std_logic_vector(VI_BURST_VWIDTH    );    
                                   bus_dataRead(29 downto 20) <= std_logic_vector(VI_BURST_START     );    
                  when x"00018" => bus_dataRead( 9 downto  0) <= std_logic_vector(VI_V_SYNC          );    
                  when x"0001C" => bus_dataRead(11 downto  0) <= std_logic_vector(VI_H_SYNC_WIDTH    );    
                                   bus_dataRead(20 downto 16) <= std_logic_vector(VI_H_SYNC_LEAP     );    
                  when x"00020" => bus_dataRead(11 downto  0) <= std_logic_vector(VI_LEAP_A          );    
                                   bus_dataRead(27 downto 16) <= std_logic_vector(VI_LEAP_B          );    
                  when x"00024" => bus_dataRead( 9 downto  0) <= std_logic_vector(VI_H_VIDEO_END     );    
                                   bus_dataRead(25 downto 16) <= std_logic_vector(VI_H_VIDEO_START   );    
                  when x"00028" => bus_dataRead( 9 downto  0) <= std_logic_vector(VI_V_VIDEO_END     );    
                                   bus_dataRead(25 downto 16) <= std_logic_vector(VI_V_VIDEO_START   );    
                  when x"0002C" => bus_dataRead( 9 downto  0) <= std_logic_vector(VI_V_BURST_END     );    
                                   bus_dataRead(25 downto 16) <= std_logic_vector(VI_V_BURST_START   );    
                  when x"00030" => bus_dataRead(11 downto  0) <= std_logic_vector(VI_X_SCALE_FACTOR  );    
                                   bus_dataRead(27 downto 16) <= std_logic_vector(VI_X_SCALE_OFFSET  );    
                  when x"00034" => bus_dataRead(11 downto  0) <= std_logic_vector(VI_Y_SCALE_FACTOR  );    
                                   bus_dataRead(27 downto 16) <= std_logic_vector(VI_Y_SCALE_OFFSET  );  
                  when x"00038" => bus_dataRead( 6 downto  0) <= std_logic_vector(VI_TEST_ADDR       );  
                  when x"0003C" => bus_dataRead(31 downto  0) <= std_logic_vector(VI_STAGED_DATA     );  
                  when others   => null;                  
               end case;
            end if;
            
            -- bus write
            if (bus_write = '1') then
               bus_done <= '1';
               
               case (bus_addr(19 downto 2) & "00") is
                  when x"00000" => 
                     VI_CTRL_TYPE                     <= unsigned(bus_dataWrite(1 downto 0)); 
                     VI_CTRL_GAMMA_DITHER_ENABLE      <= bus_dataWrite(2);           
                     VI_CTRL_GAMMA_ENABLE             <= bus_dataWrite(3);           
                     VI_CTRL_DIVOT_ENABLE             <= bus_dataWrite(4);           
                     VI_CTRL_VBUS_CLOCK_ENABLE        <= bus_dataWrite(5);           
                     VI_CTRL_SERRATE                  <= bus_dataWrite(6);           
                     VI_CTRL_TEST_MODE                <= bus_dataWrite(7);           
                     VI_CTRL_AA_MODE                  <= unsigned(bus_dataWrite(9 downto 8)); 
                     VI_CTRL_Reserved10               <= bus_dataWrite(10);          
                     VI_CTRL_KILL_WE                  <= bus_dataWrite(11);          
                     VI_CTRL_PIXEL_ADVANCE            <= unsigned(bus_dataWrite(15 downto 12));
                     VI_CTRL_DEDITHER_FILTER_ENABLE   <= bus_dataWrite(16); 
                     
                  when x"00004" => VI_ORIGIN           <= unsigned(bus_dataWrite(23 downto  0));    
                  when x"00008" => VI_WIDTH            <= unsigned(bus_dataWrite(11 downto  0));    
                  when x"0000C" => VI_INTR             <= unsigned(bus_dataWrite( 9 downto  0));    
                  when x"00010" => irq_out <= '0';  
                  when x"00014" => VI_BURST_HWIDTH     <= unsigned(bus_dataWrite( 7 downto  0));    
                                   VI_BURST_BURSTWIDTH <= unsigned(bus_dataWrite(15 downto  8));    
                                   VI_BURST_VWIDTH     <= unsigned(bus_dataWrite(19 downto 16));    
                                   VI_BURST_START      <= unsigned(bus_dataWrite(29 downto 20));    
                  when x"00018" => VI_V_SYNC           <= unsigned(bus_dataWrite( 9 downto  0));    
                  when x"0001C" => VI_H_SYNC_WIDTH     <= unsigned(bus_dataWrite(11 downto  0));    
                                   VI_H_SYNC_LEAP      <= unsigned(bus_dataWrite(20 downto 16));    
                  when x"00020" => VI_LEAP_A           <= unsigned(bus_dataWrite(11 downto  0));    
                                   VI_LEAP_B           <= unsigned(bus_dataWrite(27 downto 16));    
                  when x"00024" => VI_H_VIDEO_END      <= unsigned(bus_dataWrite( 9 downto  0));    
                                   VI_H_VIDEO_START    <= unsigned(bus_dataWrite(25 downto 16));    
                  when x"00028" => VI_V_VIDEO_END      <= unsigned(bus_dataWrite( 9 downto  0));    
                                   VI_V_VIDEO_START    <= unsigned(bus_dataWrite(25 downto 16));    
                  when x"0002C" => VI_V_BURST_END      <= unsigned(bus_dataWrite( 9 downto  0));    
                                   VI_V_BURST_START    <= unsigned(bus_dataWrite(25 downto 16));    
                  when x"00030" => VI_X_SCALE_FACTOR   <= unsigned(bus_dataWrite(11 downto  0));    
                                   VI_X_SCALE_OFFSET   <= unsigned(bus_dataWrite(27 downto 16));    
                  when x"00034" => VI_Y_SCALE_FACTOR   <= unsigned(bus_dataWrite(11 downto  0));    
                                   VI_Y_SCALE_OFFSET   <= unsigned(bus_dataWrite(27 downto 16));  
                  when x"00038" => VI_TEST_ADDR        <= unsigned(bus_dataWrite( 6 downto  0));  
                  when x"0003C" => VI_STAGED_DATA      <= unsigned(bus_dataWrite(31 downto  0));  
                  when others   => null;                  
               end case;
            end if;
            
            -- fps counter
            fps_vsync <= video_vsync;
            if (video_vsync = '1' and fps_vsync = '0') then
               fps_VI_ORIGIN_last <= VI_ORIGIN;
               if (VI_ORIGIN /= fps_VI_ORIGIN_last) then
                  if (fpscountBCD_next(3 downto 0) = x"9") then
                     fpscountBCD_next(7 downto 4) <= fpscountBCD_next(7 downto 4) + 1;
                     fpscountBCD_next(3 downto 0) <= x"0";
                  else
                     fpscountBCD_next(3 downto 0) <= fpscountBCD_next(3 downto 0) + 1;
                  end if;
               end if;
            end if;
            
            second_ena <= '0';
            if (fps_SecondCounter = 62499999) then
               fps_SecondCounter <= 0;
               second_ena        <= '1';
               fpscountBCD       <= fpscountBCD_next;
               fpscountBCD_next  <= (others => '0');       
            else
               fps_SecondCounter <= fps_SecondCounter + 1;            
            end if;

         end if;
      end if;
   end process;
   
   
   iVI_videoout : entity work.VI_videoout
   generic map
   (
      use2Xclock       => use2Xclock,
      VITEST           => VITEST
   )
   port map
   (
      clk1x                            => clk1x,
      clk2x                            => clk2x,
      clkvid                           => clkvid,
      ce                               => ce,
      reset_1x                         => reset_1x,
            
      ISPAL                            => ISPAL,
		ASPECTRATIO                      => ASPECTRATIO,
      CROPBOTTOM                       => CROPBOTTOM,
      VI_BILINEAROFF                   => VI_BILINEAROFF,
      VI_GAMMAOFF                      => VI_GAMMAOFF,
      VI_DEDITHEROFF                   => VI_DEDITHEROFF,
      VI_AAOFF                         => VI_AAOFF,
            
      errorEna                         => errorEna, 
      errorCode                        => errorCode,
                  
      fpscountOn                       => fpscountOn, 
      fpscountBCD                      => fpscountBCD,
                  
      VI_CTRL_TYPE                     => VI_CTRL_TYPE,
      VI_CTRL_AA_MODE                  => VI_CTRL_AA_MODE,
      VI_CTRL_SERRATE                  => VI_CTRL_SERRATE,
      VI_CTRL_GAMMA_ENABLE             => VI_CTRL_GAMMA_ENABLE,
      VI_CTRL_DEDITHER_FILTER_ENABLE   => VI_CTRL_DEDITHER_FILTER_ENABLE,
      VI_ORIGIN                        => VI_ORIGIN,   
      VI_WIDTH                         => VI_WIDTH,  
      VI_X_SCALE_FACTOR                => VI_X_SCALE_FACTOR,
      VI_X_SCALE_OFFSET                => VI_X_SCALE_OFFSET,
      VI_Y_SCALE_FACTOR                => VI_Y_SCALE_FACTOR,
      VI_Y_SCALE_OFFSET                => VI_Y_SCALE_OFFSET,
      VI_V_VIDEO_START                 => VI_V_VIDEO_START,
      VI_V_VIDEO_END                   => VI_V_VIDEO_END,  
      VI_H_VIDEO_START                 => VI_H_VIDEO_START,
      VI_H_VIDEO_END                   => VI_H_VIDEO_END,  
                  
      newLine                          => newLine,
      VI_CURRENT                       => VI_CURRENT,
                  
      rdram_request                    => rdram_request,   
      rdram_rnw                        => rdram_rnw,       
      rdram_address                    => rdram_address,   
      rdram_burstcount                 => rdram_burstcount,
      rdram_granted                    => rdram_granted,      
      rdram_done                       => rdram_done,  
      ddr3_DOUT                        => ddr3_DOUT,       
      ddr3_DOUT_READY                  => ddr3_DOUT_READY,
            
      sdram_request                    => sdram_request,   
      sdram_rnw                        => sdram_rnw,       
      sdram_address                    => sdram_address,   
      sdram_burstcount                 => sdram_burstcount,
      sdram_granted                    => sdram_granted,   
      sdram_done                       => sdram_done,      
      sdram_dataRead                   => sdram_dataRead,  
      sdram_valid                      => sdram_valid,     
                                       
      video_hsync                      => video_hsync, 
      video_vsync                      => video_vsync,  
      video_hblank                     => video_hblank, 
      video_vblank                     => video_vblank, 
      video_ce                         => video_ce,     
      video_interlace                  => video_interlace,     
      video_r                          => video_r,      
      video_g                          => video_g,      
      video_b                          => video_b,
                  
      SS_VI_CURRENT                    => unsigned(ss_in(1)(9 downto 0)),
      SS_nextHCount                    => unsigned(ss_in(6)(43 downto 32))
   );
   
--##############################################################
--############################### savestates
--##############################################################

   process (clk1x)
   begin
      if (rising_edge(clk1x)) then
      
         if (SS_reset = '1') then
         
            for i in 0 to 7 loop
               ss_in(i) <= (others => '0');
            end loop;
            
         elsif (SS_wren = '1') then
            ss_in(to_integer(SS_Adr)) <= SS_DataWrite;
         end if;
         
         if (SS_rden = '1') then
            SS_DataRead <= ss_out(to_integer(SS_Adr));
         end if;
      
      end if;
   end process;

end architecture;





