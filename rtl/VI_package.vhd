library IEEE;
use IEEE.std_logic_1164.all;  
use IEEE.numeric_std.all;     

package pVI is

   type tvideoout_settings is record
      CTRL_TYPE       : unsigned(1 downto 0);
      CTRL_SERRATE    : std_logic;
      X_SCALE_FACTOR  : unsigned(11 downto 0);
      VI_WIDTH        : unsigned(11 downto 0);
      isPAL           : std_logic;
      videoSizeY      : unsigned(9 downto 0);
		aspectRatio     : unsigned(1 downto 0);
      cropBottom      : unsigned(1 downto 0);
   end record;
   
   type tvideoout_reports is record
      vsync                   : std_logic;
      inVsync                 : std_logic;
      interlacedDisplayField  : std_logic;
      newLine                 : std_logic;
      newFrame                : std_logic;
      VI_CURRENT              : unsigned(8 downto 0);
   end record;
   
   type tvideoout_request is record
      fetch                   : std_logic;
      lineInNext              : unsigned(8 downto 0);
      xpos                    : integer range 0 to 1023;
      lineDisp                : unsigned(8 downto 0);
   end record;    
   
   type tvideoout_out is record
      hsync          : std_logic;
      vsync          : std_logic;
      hblank         : std_logic;
      vblank         : std_logic;
      ce             : std_logic;
      interlace      : std_logic;
      r              : std_logic_vector(7 downto 0);
      g              : std_logic_vector(7 downto 0);
      b              : std_logic_vector(7 downto 0);
   end record; 
   
   type tfetchelement is record
      r   : unsigned(7 downto 0);
      g   : unsigned(7 downto 0);
      b   : unsigned(7 downto 0);
      c   : unsigned(2 downto 0);
   end record;   
   
   type tfetchshift is array(0 to 4) of tfetchelement;
   
   type tfetcharray_AA is array(0 to 5) of tfetchelement;
   type tfetcharray_DD is array(0 to 7) of tfetchelement;
  
   type tcolor is array(0 to 2) of unsigned(7 downto 0);
   
   type tfetchArray is array(0 to 2) of unsigned(31 downto 0);
   type tfetchArray9 is array(0 to 2) of unsigned(1 downto 0);
   
   type taddr9offset is array(0 to 2) of integer range 0 to 15;
   
end package;