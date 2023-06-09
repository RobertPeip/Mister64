local filecontent = {}
local input = io.open("pifrom.bin", "rb")
local dwordsum = 0
local dwordpos = 0
while true do
   local byte = input:read(1)
   if not byte then 
         if (dwordpos > 0) then
            filecontent[#filecontent + 1] = dwordsum
         end
      break 
   end
   dwordsum = (dwordsum * 256) + string.byte(byte)
   dwordpos = dwordpos + 1
   if (dwordpos == 4) then
      filecontent[#filecontent + 1] = dwordsum
      dwordpos = 0
      dwordsum = 0
   end
end
input:close()

local outfile=io.open("../../../rtl/pifrom.vhd","w")
io.output(outfile)

io.write("library IEEE;\n")
io.write("use IEEE.std_logic_1164.all;\n") 
io.write("use IEEE.numeric_std.all;\n")
io.write("\n")
io.write("entity pifrom is\n")
io.write("   port\n")
io.write("   (\n")
io.write("      clk     : in std_logic;\n")
io.write("      address : in std_logic_vector(8 downto 0);\n")
io.write("      data    : out std_logic_vector(31 downto 0)\n")
io.write("   );\n")
io.write("end entity;\n")
io.write("\n")
io.write("architecture arch of pifrom is\n")
io.write("\n")
io.write("   type t_rom is array(0 to 511) of std_logic_vector(31 downto 0);\n")
io.write("   signal rom : t_rom := ( \n")

for i = 1, 512 do
   local endianswitch = "00000000"
   if (filecontent[i] ~= nil) then
      endianswitch = string.format("%08X", filecontent[i])
   end
   
   io.write("      x\"")
   --io.write(string.sub(endianswitch, 7, 8))
   --io.write(string.sub(endianswitch, 5, 6))
   --io.write(string.sub(endianswitch, 3, 4))
   --io.write(string.sub(endianswitch, 1, 2))
   io.write(string.sub(endianswitch, 1, 2))
   io.write(string.sub(endianswitch, 3, 4))
   io.write(string.sub(endianswitch, 5, 6))
   io.write(string.sub(endianswitch, 7, 8))
   io.write("\"")
   if (i < 512) then
      io.write(",")
   end
   io.write("\n")
end

io.write("   );\n")
io.write("\n")
io.write("begin\n")
io.write("\n")
io.write("   process (clk) \n")
io.write("   begin\n")
io.write("      if rising_edge(clk) then\n")
io.write("         data <= rom(to_integer(unsigned(address)));\n")
io.write("      end if;\n")
io.write("   end process;\n")
io.write("\n")
io.write("end architecture;\n")

io.close(outfile)





