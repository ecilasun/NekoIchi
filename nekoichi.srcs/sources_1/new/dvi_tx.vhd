LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.NUMERIC_STD.ALL;

ENTITY dvi_tx IS
    PORT( clk_i         : in  std_logic; -- 125 MHz system clock
          rst_i         : in  std_logic; -- Any board button
          dvi_clk_p_o   : out std_logic;
          dvi_clk_n_o   : out std_logic;
          dvi_tx0_p_o   : out std_logic;
          dvi_tx0_n_o   : out std_logic;
          dvi_tx1_p_o   : out std_logic;
          dvi_tx1_n_o   : out std_logic;
          dvi_tx2_p_o   : out std_logic;
          dvi_tx2_n_o   : out std_logic;
   SIGNAL red           : in std_logic_vector(7 downto 0);
   SIGNAL green         : in std_logic_vector(7 downto 0);
   SIGNAL blue          : in std_logic_vector(7 downto 0);
          counter_x     : out std_logic_vector(11 downto 0);
          counter_y     : out std_logic_vector(11 downto 0);
          pixel_clock   : out std_logic;
   SIGNAL vsync_signal  : out std_logic);
END ENTITY dvi_tx;

ARCHITECTURE dvi_tx_a OF dvi_tx IS
  SIGNAL sclk_x        : std_logic;
  SIGNAL sclk_x5_x     : std_logic;
  SIGNAL pixel_clk_x   : std_logic;
  SIGNAL mmcm_locked_x : std_logic;
  SIGNAL hsync_x       : std_logic;
  SIGNAL vsync_x       : std_logic;
  SIGNAL blank_x       : std_logic;
  SIGNAL hsync_r0_x    : std_logic;
  SIGNAL vsync_r0_x    : std_logic;
  SIGNAL blank_r0_x    : std_logic;
  SIGNAL rst_no_lock   : std_logic;
  SIGNAL count         : std_logic_vector(20 downto 0);
  SIGNAL red_x         : std_logic_vector(7 downto 0);
  SIGNAL green_x       : std_logic_vector(7 downto 0);
  SIGNAL blue_x        : std_logic_vector(7 downto 0);
BEGIN

   pixel_clock <= pixel_clk_x;

   dvi_tx_clkgen_inst : ENTITY work.dvi_tx_clkgen
       PORT MAP( clk_i         => clk_i,
                 arst_i        => rst_i,
                 locked_o      => mmcm_locked_x,
                 pixel_clk_o   => pixel_clk_x,
                 sclk_o        => sclk_x,
                 sclk_x5_o     => sclk_x5_x);

   rgb_timing_inst : ENTITY work.rgb_timing
       PORT MAP( clk_i   => pixel_clk_x,
                 hsync_o => hsync_x,
                 vsync_o => vsync_x,
                 blank_o => blank_x,
                 counter_x => counter_x,
                 counter_y => counter_y,
                 vsynctrigger_o => vsync_signal );
     
   counter_inst: ENTITY work.counter
      GENERIC MAP(max => 800*525)
      PORT MAP( clk   => pixel_clk_x,
                count => count);
        
   rgb_pattern_inst : ENTITY work.rgb_pattern
       PORT MAP( clk_i     => pixel_clk_x,
                 hsync_i   => hsync_x,
                 vsync_i   => vsync_x,
                 blank_i   => blank_x,
                 pixel_pos => count,
                 hsync_o   => hsync_r0_x,
                 vsync_o   => vsync_r0_x,
                 blank_o   => blank_r0_x,
                 red_i     => red,
                 green_i   => green,
                 blue_i    => blue,
                 red_o     => red_x,
                 green_o   => green_x,
                 blue_o    => blue_x );

   rst_no_lock <= (rst_i OR (NOT mmcm_locked_x));

   rgb_to_dvi_inst : ENTITY work.rgb_to_dvi
       PORT MAP( sclk_i      => sclk_x,
                 sclk_x5_i   => sclk_x5_x,
                 pixel_clk_i => pixel_clk_x,
                 arst_i      => rst_no_lock,
                   
                 red_i       => red_x,
                 green_i     => green_x,
                 blue_i      => blue_x,
                 hsync_i     => hsync_r0_x,
                 vsync_i     => vsync_r0_x,
                 blank_i     => blank_r0_x,
            
                 dvi_clk_p_o => dvi_clk_p_o,
                 dvi_clk_n_o => dvi_clk_n_o,
                 dvi_tx0_p_o => dvi_tx0_p_o,
                 dvi_tx0_n_o => dvi_tx0_n_o,
                 dvi_tx1_p_o => dvi_tx1_p_o,
                 dvi_tx1_n_o => dvi_tx1_n_o,
                 dvi_tx2_p_o => dvi_tx2_p_o,
                 dvi_tx2_n_o => dvi_tx2_n_o);
END ARCHITECTURE dvi_tx_a;
