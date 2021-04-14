LIBRARY IEEE;
LIBRARY UNISIM;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.NUMERIC_STD.ALL;
USE UNISIM.VCOMPONENTS.ALL;
USE work.graphics.ALL;

ENTITY rgb_pattern IS
    port( clk_i       : IN  std_logic;
          hsync_i     : IN  std_logic;
          vsync_i     : IN  std_logic;
          blank_i     : IN  std_logic;
          pixel_pos   : IN  std_logic_vector(20 downto 0); -- 1920*1080 needs minimum 21 bits
          hsync_o     : OUT std_logic;
          vsync_o     : OUT std_logic;
          blank_o     : OUT std_logic;
          red_i       : in std_logic_vector(7 downto 0);
          green_i     : in std_logic_vector(7 downto 0);
          blue_i      : in std_logic_vector(7 downto 0); 
          red_o       : OUT std_logic_vector(7 downto 0);
          green_o     : OUT std_logic_vector(7 downto 0);
          blue_o      : OUT std_logic_vector(7 downto 0) );
END ENTITY rgb_pattern;

ARCHITECTURE rgb_pattern_a OF rgb_pattern IS

BEGIN

  draw: process(clk_i)
  BEGIN
      IF (rising_edge(clk_i)) THEN
          hsync_o <= hsync_i;
          vsync_o <= vsync_i;
      
          IF (blank_i = '0') THEN  
              red_o   <= red_i;
              green_o <= green_i;
              blue_o  <= blue_i; 
              blank_o <= '0';
          ELSE
              red_o   <= (OTHERS => '0');
              green_o <= (OTHERS => '0');
              blue_o  <= (OTHERS => '0');   
              blank_o <= '1';
          END IF;
      END IF;
  END PROCESS;
END ARCHITECTURE rgb_pattern_a;