library IEEE;
use IEEE.std_logic_1164.all;  
use IEEE.numeric_std.all; 

entity Gamepad is
   port 
   (
      clk1x                : in  std_logic;
      reset                : in  std_logic;
      
      second_ena           : in  std_logic;
     
      PADCOUNT             : in  std_logic_vector(1 downto 0); -- count - 1
      PADTYPE0             : in  std_logic_vector(1 downto 0); -- 00 = nothing, 01 = transfer, 10 = rumble
      PADTYPE1             : in  std_logic_vector(1 downto 0);
      PADTYPE2             : in  std_logic_vector(1 downto 0);
      PADTYPE3             : in  std_logic_vector(1 downto 0);
      PADDPADSWAP          : in  std_logic;
      CPAKFORMAT           : in  std_logic;
      PADSLOW              : in  std_logic;
      
      command_start        : in  std_logic;                    -- high for 1 clock cycle when a new command is issued from PIF. toPad_ena will also be high, sending the first byte with data containing the command ID 
      command_padindex     : in  unsigned(1 downto 0);         -- pad number 0..3
      command_sendCnt      : in  unsigned(5 downto 0);         -- amount of bytes to be sent to the pad. First byte is the command, then follows payload
      command_receiveCnt   : in  unsigned(5 downto 0);         -- amount of bytes expected to be read back to PIF after sending all bytes
   
      toPad_ena            : in  std_logic;                    -- high for 1 cycle when a new byte is to be written to the pad
      toPad_data           : in  std_logic_vector(7 downto 0); -- byte written to pad
      toPad_ready          : out std_logic := '0';             -- can be used to tell the PIF it has to wait before sending more data to the pad
                           
      toPIF_timeout        : out std_logic := '0';                                  -- set to 1 for one cycle when no pad is connected/detected
      toPIF_ena            : out std_logic := '0';                                  -- set to 1 for one cycle when new data is send to PIF
      toPIF_data           : out std_logic_vector(7 downto 0) := (others => '0');   -- byte from controller send back to PIF

      pad_A                : in  std_logic_vector(3 downto 0);
      pad_B                : in  std_logic_vector(3 downto 0);
      pad_Z                : in  std_logic_vector(3 downto 0);
      pad_START            : in  std_logic_vector(3 downto 0);
      pad_DPAD_UP          : in  std_logic_vector(3 downto 0);
      pad_DPAD_DOWN        : in  std_logic_vector(3 downto 0);
      pad_DPAD_LEFT        : in  std_logic_vector(3 downto 0);
      pad_DPAD_RIGHT       : in  std_logic_vector(3 downto 0);
      pad_L                : in  std_logic_vector(3 downto 0);
      pad_R                : in  std_logic_vector(3 downto 0);
      pad_C_UP             : in  std_logic_vector(3 downto 0);
      pad_C_DOWN           : in  std_logic_vector(3 downto 0);
      pad_C_LEFT           : in  std_logic_vector(3 downto 0);
      pad_C_RIGHT          : in  std_logic_vector(3 downto 0);
      pad_0_analog_h       : in  std_logic_vector(7 downto 0);
      pad_0_analog_v       : in  std_logic_vector(7 downto 0);      
      pad_1_analog_h       : in  std_logic_vector(7 downto 0);
      pad_1_analog_v       : in  std_logic_vector(7 downto 0);      
      pad_2_analog_h       : in  std_logic_vector(7 downto 0);
      pad_2_analog_v       : in  std_logic_vector(7 downto 0);      
      pad_3_analog_h       : in  std_logic_vector(7 downto 0);
      pad_3_analog_v       : in  std_logic_vector(7 downto 0);
      
      rumble               : out std_logic_vector(3 downto 0) := (others => '0');
      
      cpak_change          : out std_logic := '0';
      
      sdram_request        : out std_logic := '0';
      sdram_rnw            : out std_logic := '0'; 
      sdram_address        : out unsigned(26 downto 0):= (others => '0');
      sdram_burstcount     : out unsigned(7 downto 0):= (others => '0');
      sdram_writeMask      : out std_logic_vector(3 downto 0) := (others => '0'); 
      sdram_dataWrite      : out std_logic_vector(31 downto 0) := (others => '0');
      sdram_done           : in  std_logic;
      sdram_dataRead       : in  std_logic_vector(31 downto 0)
   );
end entity;

architecture arch of Gamepad is

   signal INITDONE         : std_logic := '0';

   type tState is
   (
      IDLE,
      WAITSLOW,
      
      RESPONSETYPE0,
      RESPONSETYPE1,
      RESPONSETYPE2,
      
      RESPONSEPAD0,
      RESPONSEPAD1,
      RESPONSEPAD2,
      RESPONSEPAD3,
      
      PAK_READADDR1,
      PAK_READADDR2,
      PAKCRC,
      
      PAKREAD_WAITFIRST,
      PAKREAD_READSDRAM,
      PAKREAD_WRITEPIF,
      PAKREAD_CHECKNEXT,
      
      PAKWRITE_READPIF,
      PAKWRITE_WRITESDRAM,
      PAKWRITE_CHECKNEXT,
      PAKWRITE_WAITWRITE,
      
      SENDEMPTY
   );
   signal state                     : tState := IDLE;
   signal stateNext                 : tState := IDLE;
   
   signal slowcnt                   : unsigned(11 downto 0) := (others => '0');
   signal slowNextByteEna           : std_logic;
   signal sendcount                 : unsigned(5 downto 0) := (others => '0');
   signal receivecount              : unsigned(5 downto 0) := (others => '0');
   
   signal PADTYPE                   : std_logic_vector(1 downto 0);
   
   signal pad_muxed_A               : std_logic;
   signal pad_muxed_B               : std_logic;
   signal pad_muxed_C               : std_logic;
   signal pad_muxed_START           : std_logic;
   signal pad_muxed_DPAD_UP         : std_logic;
   signal pad_muxed_DPAD_DOWN       : std_logic;
   signal pad_muxed_DPAD_LEFT       : std_logic;
   signal pad_muxed_DPAD_RIGHT      : std_logic;
   signal pad_muxed_L               : std_logic;
   signal pad_muxed_R               : std_logic;
   signal pad_muxed_C_UP            : std_logic;
   signal pad_muxed_C_DOWN          : std_logic;
   signal pad_muxed_C_LEFT          : std_logic;
   signal pad_muxed_C_RIGHT         : std_logic;
                                   
   signal pad_muxed_analogH         : std_logic_vector(7 downto 0);
   signal pad_muxed_analogV         : std_logic_vector(7 downto 0);
   
   -- PAKs
   signal pakwrite                  : std_logic;
   signal pakaddr                   : std_logic_vector(15 downto 0) := (others => '0');
   signal pakvalue                  : std_logic_vector(7 downto 0);
   
   signal pakcrc_count              : unsigned(2 downto 0);
   signal pakcrc_value              : std_logic_vector(7 downto 0);
   signal pakcrc_last               : std_logic;
   
   type tCPAKINITState is
   (
      PAKINIT_IDLE,
      PAKINIT_WRITESDRAM,
      PAKINIT_WAITSDRAM
   );
   signal PAKINITState              : tCPAKINITState := PAKINIT_IDLE;
   signal pakinit_addr              : unsigned(14 downto 0) := (others => '0');
   signal pakinit_data              : std_logic_vector(31 downto 0);
   
begin 

   PADTYPE <= PADTYPE0 when (command_padindex = "00") else 
              PADTYPE1 when (command_padindex = "01") else 
              PADTYPE2 when (command_padindex = "10") else 
              PADTYPE3;
              
   pad_muxed_A          <= pad_A(to_integer(command_padindex));         
   pad_muxed_B          <= pad_B(to_integer(command_padindex));         
   pad_muxed_C          <= pad_Z(to_integer(command_padindex));         
   pad_muxed_START      <= pad_START(to_integer(command_padindex));     
   pad_muxed_DPAD_UP    <= pad_DPAD_UP(to_integer(command_padindex));   
   pad_muxed_DPAD_DOWN  <= pad_DPAD_DOWN(to_integer(command_padindex)); 
   pad_muxed_DPAD_LEFT  <= pad_DPAD_LEFT(to_integer(command_padindex)); 
   pad_muxed_DPAD_RIGHT <= pad_DPAD_RIGHT(to_integer(command_padindex));
   pad_muxed_L          <= pad_L(to_integer(command_padindex));      
   pad_muxed_R          <= pad_R(to_integer(command_padindex));      
   pad_muxed_C_UP       <= pad_C_UP(to_integer(command_padindex));   
   pad_muxed_C_DOWN     <= pad_C_DOWN(to_integer(command_padindex)); 
   pad_muxed_C_LEFT     <= pad_C_LEFT(to_integer(command_padindex)); 
   pad_muxed_C_RIGHT    <= pad_C_RIGHT(to_integer(command_padindex));
   
   process (all)
   begin
      case (command_padindex) is
         when "00"   => pad_muxed_analogH <= pad_0_analog_h; pad_muxed_analogV <= std_logic_vector(-signed(pad_0_analog_v));
         when "01"   => pad_muxed_analogH <= pad_1_analog_h; pad_muxed_analogV <= std_logic_vector(-signed(pad_1_analog_v));
         when "10"   => pad_muxed_analogH <= pad_2_analog_h; pad_muxed_analogV <= std_logic_vector(-signed(pad_2_analog_v));
         when others => pad_muxed_analogH <= pad_3_analog_h; pad_muxed_analogV <= std_logic_vector(-signed(pad_3_analog_v));
      end case;   
   end process;
              
   --slowNextByteEna <= slowcnt(slowcnt'left) when (PADSLOW = '1') else slowcnt(2);
   slowNextByteEna <= '1' when (slowcnt = 1986 and PADSLOW = '1') else 
                      '1' when (slowcnt = 1970 and PADSLOW = '0') else 
                      '0';
           
   ipif_cpakinit : entity work.pif_cpakinit
   port map
   (
      clk       => clk1x,
      address   => std_logic_vector(pakinit_addr(6 downto 0)),
      data      => pakinit_data
   );
   
   sdram_burstcount <= x"01";
           
   process (clk1x)
   begin
      if rising_edge(clk1x) then
      
         toPIF_timeout <= '0';
         toPIF_ena     <= '0';
         sdram_request <= '0';
         cpak_change   <= '0';
         
         if (slowNextByteEna = '1') then
            slowcnt <= (others => '0');
         else
            slowcnt <= slowcnt + 1;
         end if;
         
         -- init PAK area
         case (PAKINITState) is      
               
            when PAKINIT_IDLE => null;
               if (second_ena = '1' and INITDONE = '0') then
                  INITDONE     <= '1';
                  PAKINITState <= PAKINIT_WRITESDRAM;
               end if;
               if (CPAKFORMAT = '1') then
                  PAKINITState <= PAKINIT_WRITESDRAM;
                  pakinit_addr <= (others => '0');
               end if;
            
            when PAKINIT_WRITESDRAM =>
               PAKINITState    <= PAKINIT_WAITSDRAM;
               sdram_request   <= '1';
               sdram_rnw       <= '0';
               sdram_writeMask <= "1111";
               sdram_address   <= resize(unsigned(pakinit_addr & "00"), 27) + to_unsigned(16#500000#, 27);
               if (pakinit_addr(12 downto 0) < 128) then
                  sdram_dataWrite <= pakinit_data;
               else
                  sdram_dataWrite <= (others => '0');
               end if;
               pakinit_addr    <= pakinit_addr + 1;
               if (pakinit_addr = 15x"7FFF") then
                  PAKINITState <= PAKINIT_IDLE;
               end if;

            when PAKINIT_WAITSDRAM =>
               if (sdram_done = '1') then
                  PAKINITState <= PAKINIT_WRITESDRAM;
               end if;
               
         end case;
         
         if (PADTYPE0 /= "10") then rumble(0) <= '0'; end if;
         if (PADTYPE1 /= "10") then rumble(1) <= '0'; end if;
         if (PADTYPE2 /= "10") then rumble(2) <= '0'; end if;
         if (PADTYPE3 /= "10") then rumble(3) <= '0'; end if;

         case (state) is
            
            when IDLE =>
               toPad_ready    <= '1';
               slowcnt        <= (others => '0');
               sendcount      <= command_sendCnt - 1;
               pakcrc_value   <= (others => '0');
               if (command_start = '1') then
                  state       <= WAITSLOW;
                  toPad_ready <= '0';
                  if (command_padindex > unsigned(PADCOUNT)) then
                     toPIF_timeout <= '1';
                     stateNext     <= IDLE;
                  else
                     if (toPad_data = x"00" or toPad_data = x"FF") then -- type check
                        stateNext <= RESPONSETYPE0;
                     elsif (toPad_data = x"01") then -- pad response
                        stateNext <= RESPONSEPAD0;
                     elsif (toPad_data = x"02") then -- pad read
                        stateNext <= PAK_READADDR1;
                        pakwrite  <= '0';
                     elsif (toPad_data = x"03") then -- pad write
                        stateNext <= PAK_READADDR1;
                        pakwrite  <= '1';
                     end if;
                  end if;
               end if;
               
            when WAITSLOW =>
               if (slowNextByteEna = '1') then
                  state       <= stateNext;
                  toPad_ready <= '1';
               end if;
             
----------------------------- type -------------------------------
            when RESPONSETYPE0 =>
               if (slowNextByteEna = '1') then
                  if (command_receiveCnt > 1) then
                     state <= RESPONSETYPE1;
                  else
                     state <= IDLE;
                  end if;
                  toPIF_ena  <= '1';
               end if;
               
               toPIF_data <= x"05";
            
            when RESPONSETYPE1 =>   
               if (slowNextByteEna = '1') then
                  if (command_receiveCnt > 2) then
                     state <= RESPONSETYPE2;
                  else
                     state <= IDLE;
                  end if;
                  toPIF_ena  <= '1';
               end if;
               
               toPIF_data <= x"00";
            
            when RESPONSETYPE2 => 
               if (slowNextByteEna = '1') then
                  receivecount <= to_unsigned(4, receivecount'length);
                  if (command_receiveCnt > 3) then
                     state <= SENDEMPTY;
                  else
                     state <= IDLE;
                  end if;
                  toPIF_ena  <= '1';
               end if;
               
               if (PADTYPE = "01" or PADTYPE = "10") then
                  toPIF_data <= x"01";
               else
                  toPIF_data <= x"02";
               end if;
            
----------------------------- pad buttons/axis -------------------------------
            when RESPONSEPAD0 =>  
               if (slowNextByteEna = '1') then
                  if (command_receiveCnt > 1) then
                     state <= RESPONSEPAD1;
                  else
                     state <= IDLE;
                  end if;
                  toPIF_ena  <= '1';
               end if;
            
               toPIF_data(7) <= pad_muxed_A;         
               toPIF_data(6) <= pad_muxed_B;         
               toPIF_data(5) <= pad_muxed_C;         
               toPIF_data(4) <= pad_muxed_START;     
               toPIF_data(3) <= pad_muxed_DPAD_UP;   
               toPIF_data(2) <= pad_muxed_DPAD_DOWN; 
               toPIF_data(1) <= pad_muxed_DPAD_LEFT; 
               toPIF_data(0) <= pad_muxed_DPAD_RIGHT;
               
               if (PADDPADSWAP = '1') then
                  toPIF_data(3) <= '0';
                  toPIF_data(2) <= '0';
                  toPIF_data(1) <= '0';
                  toPIF_data(0) <= '0';
                  if (signed(pad_muxed_analogH) >=  64) then toPIF_data(0) <= '1'; end if;
                  if (signed(pad_muxed_analogH) <= -64) then toPIF_data(1) <= '1'; end if;
                  if (signed(pad_muxed_analogV) >=  64) then toPIF_data(3) <= '1'; end if;
                  if (signed(pad_muxed_analogV) <= -64) then toPIF_data(2) <= '1'; end if;
               end if;
            
            
            when RESPONSEPAD1 => 
               if (slowNextByteEna = '1') then
                  if (command_receiveCnt > 2) then
                     state <= RESPONSEPAD2;
                  else
                     state <= IDLE;
                  end if;
                  toPIF_ena  <= '1';
               end if;
            
               toPIF_data(7 downto 6) <= "00";      
               toPIF_data(5) <= pad_muxed_L;      
               toPIF_data(4) <= pad_muxed_R;      
               toPIF_data(3) <= pad_muxed_C_UP;   
               toPIF_data(2) <= pad_muxed_C_DOWN; 
               toPIF_data(1) <= pad_muxed_C_LEFT; 
               toPIF_data(0) <= pad_muxed_C_RIGHT;

            when RESPONSEPAD2 => 
               if (slowNextByteEna = '1') then
                  if (command_receiveCnt > 3) then
                     state <= RESPONSEPAD3;
                  else
                     state <= IDLE;
                  end if;
                  toPIF_ena  <= '1';
               end if;
            
               toPIF_data <= pad_muxed_analogH;
            
               if (PADDPADSWAP = '1') then
                  if    (pad_muxed_DPAD_LEFT  = '1' and pad_muxed_DPAD_UP = '0' and pad_muxed_DPAD_DOWN = '0') then toPIF_data <= std_logic_vector(to_signed(-85,8));
                  elsif (pad_muxed_DPAD_RIGHT = '1' and pad_muxed_DPAD_UP = '0' and pad_muxed_DPAD_DOWN = '0') then toPIF_data <= std_logic_vector(to_signed(85,8));
                  elsif (pad_muxed_DPAD_LEFT  = '1')                                                           then toPIF_data <= std_logic_vector(to_signed(-69,8));
                  elsif (pad_muxed_DPAD_RIGHT = '1')                                                           then toPIF_data <= std_logic_vector(to_signed(69,8));
                  else toPIF_data <= (others => '0'); end if;
               end if;
            
            when RESPONSEPAD3 =>  
               if (slowNextByteEna = '1') then
                  receivecount <= to_unsigned(5, receivecount'length);
                  if (command_receiveCnt > 4) then
                     state <= SENDEMPTY;
                  else
                     state <= IDLE;
                  end if;
                  toPIF_ena  <= '1';
               end if;
            
               toPIF_data <= pad_muxed_analogV;
            
               if (PADDPADSWAP = '1') then
                  if    (pad_muxed_DPAD_UP   = '1' and pad_muxed_DPAD_LEFT = '0' and pad_muxed_DPAD_RIGHT = '0') then toPIF_data <= std_logic_vector(to_signed(85,8));
                  elsif (pad_muxed_DPAD_DOWN = '1' and pad_muxed_DPAD_LEFT = '0' and pad_muxed_DPAD_RIGHT = '0') then toPIF_data <= std_logic_vector(to_signed(-85,8));
                  elsif (pad_muxed_DPAD_UP   = '1')                                                              then toPIF_data <= std_logic_vector(to_signed(69,8));
                  elsif (pad_muxed_DPAD_DOWN = '1')                                                              then toPIF_data <= std_logic_vector(to_signed(-69,8));
                  else toPIF_data <= (others => '0'); end if;
               end if;
               
----------------------------- PAK common -------------------------------
               when PAK_READADDR1 =>
                  if (sendcount = 0) then
                     state         <= IDLE;
                     toPIF_timeout <= '1';
                  end if;
                  if (toPad_ena = '1') then
                     state                <= WAITSLOW;
                     toPad_ready          <= '0';
                     stateNext            <= PAK_READADDR2;
                     sendcount            <= sendcount - 1;
                     pakaddr(15 downto 8) <= toPad_data;
                  end if;

               when PAK_READADDR2 =>
                  if (sendcount = 0) then
                     state         <= IDLE;
                     toPIF_timeout <= '1';
                  end if;
                  if (toPad_ena = '1') then
                     state                <= WAITSLOW;
                     toPad_ready          <= '0';
                     sendcount            <= sendcount - 1;
                     if (pakwrite = '0') then
                        stateNext <= PAKREAD_WAITFIRST;
                     else
                        stateNext <= PAKWRITE_READPIF;
                     end if;
                     pakaddr(7 downto 5)  <= toPad_data(7 downto 5);
                  end if;
                  
               -- PAK CRC
               when PAKCRC =>
                  pakcrc_count <= pakcrc_count + 1;
                  if (pakcrc_count = 7) then
                     pakcrc_last <= '0'; 
                     if (pakcrc_last = '0') then
                        if (pakwrite = '1') then
                           state <= PAKWRITE_CHECKNEXT;
                        else
                           state <= PAKREAD_CHECKNEXT;
                        end if;
                     end if;
                  end if;
                  
                  if (pakcrc_value(7) = '1') then
                     pakcrc_value <= (pakcrc_value(6 downto 0) & pakvalue(7)) xor x"85";
                  else
                     pakcrc_value <= (pakcrc_value(6 downto 0) & pakvalue(7));
                  end if;
                  pakvalue <= pakvalue(6 downto 0) & '0';
                  
----------------------------- PAK read -------------------------------
               when PAKREAD_WAITFIRST =>
                  if (slowNextByteEna = '1') then
                     state <= PAKREAD_READSDRAM;
                  end if;

               when PAKREAD_READSDRAM => 
                  state           <= PAKREAD_WRITEPIF;
                  sdram_request   <= '1';
                  sdram_rnw       <= '1';
                  sdram_address   <= resize(command_padindex & unsigned(pakaddr(14 downto 2)) & "00", 27) + to_unsigned(16#500000#, 27);
                  
               when PAKREAD_WRITEPIF =>
                  if (sdram_done = '1') then
                     state          <= WAITSLOW;
                     toPad_ready    <= '0';
                     stateNext      <= PAKCRC;
                     toPIF_ena      <= '1';
                  
                     pakcrc_count   <= (others => '0');
                     pakcrc_last    <= '0';
                     if (pakaddr(4 downto 0) = 5x"1F") then -- last byte will need one additional round of crc with input value 00
                        pakcrc_last <= '1';
                     end if;
                     if (PADTYPE = "10") then -- rumble
                        if (unsigned(pakaddr) >= 16#8000# and unsigned(pakaddr) < 16#9000#) then
                           toPIF_data     <= x"80";
                           pakvalue       <= x"80";
                        else
                           toPIF_data     <= x"00";
                           pakvalue       <= x"00";
                        end if;
                     else --cpak
                        if (pakaddr(15) = '1') then
                           toPIF_data     <= x"00";
                           pakvalue       <= x"00";
                        else
                           case (pakaddr(1 downto 0)) is
                              when "00" => toPIF_data <= sdram_dataRead( 7 downto  0); pakvalue <= sdram_dataRead( 7 downto  0);
                              when "01" => toPIF_data <= sdram_dataRead(15 downto  8); pakvalue <= sdram_dataRead(15 downto  8);
                              when "10" => toPIF_data <= sdram_dataRead(23 downto 16); pakvalue <= sdram_dataRead(23 downto 16);
                              when "11" => toPIF_data <= sdram_dataRead(31 downto 24); pakvalue <= sdram_dataRead(31 downto 24);
                              when others => null;
                           end case;
                        end if;
                     end if;
                     pakaddr(4 downto 0) <= std_logic_vector(unsigned(pakaddr(4 downto 0)) + 1);
                  end if;
                  
               when PAKREAD_CHECKNEXT =>
                  if (pakaddr(4 downto 0) = 5x"0") then
                     state          <= WAITSLOW;
                     toPad_ready    <= '0';
                     stateNext      <= IDLE;
                     toPIF_data     <= pakcrc_value;
                     toPIF_ena      <= '1';
                  else
                     state <= PAKREAD_READSDRAM;
                  end if;
                  
----------------------------- PAK write -------------------------------
               when PAKWRITE_READPIF =>
                  if (sendcount = 0) then
                     state         <= IDLE;
                     toPIF_timeout <= '1';
                  end if;
                  if (toPad_ena = '1') then
                     state          <= PAKWRITE_WRITESDRAM;
                     toPad_ready    <= '0';
                     sendcount      <= sendcount - 1;
                     pakvalue       <= toPad_data;
                     pakaddr(4 downto 0) <= std_logic_vector(unsigned(pakaddr(4 downto 0)) + 1);
                     if (PADTYPE = "10") then -- rumble
                        if (pakaddr = x"C000") then
                           rumble(to_integer(command_padindex(1 downto 0))) <= toPad_data(0);
                        end if;
                     else -- cpak
                        if (pakaddr(15) = '0') then
                           cpak_change     <= '1';
                           sdram_request   <= '1';
                        end if;
                     end if;
                  end if;
                  
                  sdram_rnw       <= '0';
                  sdram_address   <= resize(command_padindex & unsigned(pakaddr(14 downto 2)) & "00", 27) + to_unsigned(16#500000#, 27);
                  sdram_dataWrite <= toPad_data & toPad_data & toPad_data & toPad_data;
                  case (pakaddr(1 downto 0)) is
                     when "00" => sdram_writeMask <= "0001";
                     when "01" => sdram_writeMask <= "0010";
                     when "10" => sdram_writeMask <= "0100";
                     when "11" => sdram_writeMask <= "1000";
                     when others => null;
                  end case;
                  
               when PAKWRITE_WRITESDRAM =>
                  stateNext <= PAKCRC;
                  if (sdram_done = '1' or pakaddr(15) = '1' or PADTYPE = "10") then
                     state          <= PAKCRC;
                     pakcrc_count   <= (others => '0');
                     pakcrc_last    <= '0';
                     if (sendcount = 0) then -- last byte will need one additional round of crc with input value 00
                        state       <= WAITSLOW;
                        pakcrc_last <= '1';   
                     end if;
                  end if;

               when PAKWRITE_CHECKNEXT =>
                  if (sendcount = 0) then
                     state          <= PAKWRITE_WAITWRITE;
                  else
                     state      <= WAITSLOW;
                     stateNext  <= PAKWRITE_READPIF;
                  end if;
                  
               when PAKWRITE_WAITWRITE =>
                  if (slowNextByteEna = '1') then
                     state          <= WAITSLOW;
                     toPad_ready    <= '0';
                     stateNext      <= IDLE;
                     toPIF_data     <= pakcrc_value;
                     toPIF_ena      <= '1';
                  end if;
            
----------------------------- error case of too much data requested -------------------------------
            when SENDEMPTY =>
               if (slowNextByteEna = '1') then
                  toPIF_ena  <= '1';
                  receivecount <= receivecount + 1;
                  if (receivecount >= command_receiveCnt) then
                     state <= IDLE;
                  end if;
               end if;
               
               toPIF_data <= x"00";

         end case;
      
         if (reset = '1') then
            state  <= IDLE;
            rumble <= (others => '0');
         end if;
         
      end if; -- clock
   end process;
   
end architecture;





