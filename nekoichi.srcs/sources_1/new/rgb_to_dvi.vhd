LIBRARY IEEE;
LIBRARY UNISIM;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.NUMERIC_STD.ALL;
USE UNISIM.VCOMPONENTS.ALL;

ENTITY rgb_to_dvi IS
    PORT( sclk_i      : IN  std_logic;
          sclk_x5_i   : IN  std_logic;
          pixel_clk_i : IN  std_logic;
          arst_i      : IN  std_logic;
            
          red_i       : IN  std_logic_vector(7 downto 0);
          green_i     : IN  std_logic_vector(7 downto 0);
          blue_i      : IN  std_logic_vector(7 downto 0);
          hsync_i     : IN  std_logic;
          vsync_i     : IN  std_logic;
          blank_i     : IN  std_logic;
        
          dvi_clk_p_o : OUT std_logic;
          dvi_clk_n_o : OUT std_logic;
          dvi_tx0_p_o : OUT std_logic;
          dvi_tx0_n_o : OUT std_logic;
          dvi_tx1_p_o : OUT std_logic;
          dvi_tx1_n_o : OUT std_logic;
          dvi_tx2_p_o : OUT std_logic;
          dvi_tx2_n_o : OUT std_logic);
END ENTITY rgb_to_dvi;

ARCHITECTURE rgb_to_dvi_a OF rgb_to_dvi IS
  TYPE tmds_array IS array (natural range <>) OF std_logic_vector(9 downto 0);
  SIGNAL tmds_x : tmds_array(0 to 2) := (OTHERS => (OTHERS => '0'));
  SIGNAL c0 : std_logic_vector(1 downto 0) := (OTHERS => '0');
  SIGNAL c1 : std_logic_vector(1 downto 0) := (OTHERS => '0');
  SIGNAL c2 : std_logic_vector(1 downto 0) := (OTHERS => '0');
  SIGNAL de : std_logic := '0';
BEGIN
  de <= NOT blank_i;
  c0 <= (vsync_i & hsync_i);
  tmds_0_inst : ENTITY work.tmds_encoder
      PORT MAP( clk_i   => pixel_clk_i,
                pixel_i => blue_i,
                ctrl_i  => c0,
                de_i    => de,
                tmds_o  => tmds_x(0));
                
  tmds_1_inst : ENTITY work.tmds_encoder
      PORT MAP( clk_i   => pixel_clk_i,
                pixel_i => green_i,
                ctrl_i  => c1,
                de_i    => de,
                tmds_o  => tmds_x(1));

  tmds_2_inst : ENTITY work.tmds_encoder
      PORT MAP( clk_i   => pixel_clk_i,
                pixel_i => red_i,
                ctrl_i  => c2,
                de_i    => de,
                tmds_o  => tmds_x(2));

  oserdes_tx0_inst : ENTITY work.oserdes_ddr_10_1
      PORT MAP( clk_i     => sclk_i,
                clk_x5_i  => sclk_x5_i,
                arst_i    => arst_i,
                pdata_i   => tmds_x(0),
                sdata_p_o => dvi_tx0_p_o,
                sdata_n_o => dvi_tx0_n_o);

  oserdes_tx1_inst : ENTITY work.oserdes_ddr_10_1
    port map(
      clk_i     => sclk_i,
      clk_x5_i  => sclk_x5_i,
      arst_i    => arst_i,
      pdata_i   => tmds_x(1),
      sdata_p_o => dvi_tx1_p_o,
      sdata_n_o => dvi_tx1_n_o
    );

  oserdes_tx2_inst : ENTITY work.oserdes_ddr_10_1
      PORT MAP( clk_i     => sclk_i,
                clk_x5_i  => sclk_x5_i,
                arst_i    => arst_i,
                pdata_i   => tmds_x(2),
                sdata_p_o => dvi_tx2_p_o,
                sdata_n_o => dvi_tx2_n_o);

  oserdes_clk_inst : ENTITY work.oserdes_ddr_10_1
      PORT MAP( clk_i     => sclk_i,
                clk_x5_i  => sclk_x5_i,
                arst_i    => arst_i,
                pdata_i   => "0000011111", -- clock doesn't need tmds encoding, just output a pulse
                sdata_p_o => dvi_clk_p_o,
                sdata_n_o => dvi_clk_n_o);
END ARCHITECTURE rgb_to_dvi_a;