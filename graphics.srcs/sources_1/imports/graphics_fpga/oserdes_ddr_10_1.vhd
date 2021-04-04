LIBRARY IEEE;
LIBRARY UNISIM;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.NUMERIC_STD.ALL;
USE UNISIM.VCOMPONENTS.ALL;

ENTITY oserdes_ddr_10_1 IS
    PORT( clk_i     : IN  std_logic;
          clk_x5_i  : IN  std_logic;
          arst_i    : IN  std_logic;
          pdata_i   : IN  std_logic_vector(9 downto 0);
          sdata_p_o : OUT std_logic;
          sdata_n_o : OUT std_logic);
END ENTITY oserdes_ddr_10_1;

ARCHITECTURE oserdes_ddr_10_1_a OF oserdes_ddr_10_1 IS
  SIGNAL rst_x    : std_logic;
  SIGNAL sdout_x  : std_logic;
  SIGNAL shift1_x : std_logic;
  SIGNAL shift2_x : std_logic;
BEGIN
  oserdes_arst_inst : ENTITY work.rst_bridge
      PORT MAP( arst_in  => arst_i,
                sclk_in  => clk_i,
                srst_out => rst_x);

  oserdes2_master_inst : OSERDESE2
      GENERIC MAP( DATA_RATE_OQ   => "DDR",
                   DATA_RATE_TQ   => "SDR",
                   DATA_WIDTH     => 10,
                   SERDES_MODE    => "MASTER",
                   TBYTE_CTL      => "FALSE",
                   TBYTE_SRC      => "FALSE",
                   TRISTATE_WIDTH => 1)
      PORT MAP(OFB       => OPEN,
               OQ        => sdout_x,
               SHIFTOUT1 => OPEN,
               SHIFTOUT2 => OPEN,
               TBYTEOUT  => OPEN,
               TFB       => OPEN,
               TQ        => OPEN,
               CLK       => clk_x5_i,
               CLKDIV    => clk_i,
               D1        => pdata_i(0),
               D2        => pdata_i(1),
               D3        => pdata_i(2),
               D4        => pdata_i(3),
               D5        => pdata_i(4),
               D6        => pdata_i(5),
               D7        => pdata_i(6),
               D8        => pdata_i(7),
               OCE       => '1',
               RST       => rst_x,
               SHIFTIN1  => shift1_x,
               SHIFTIN2  => shift2_x,
               T1        => '0',
               T2        => '0',
               T3        => '0',
               T4        => '0',
               TBYTEIN   => '0',
               TCE       => '0'); 

  oserdes2_slave_inst : OSERDESE2
      GENERIC MAP( DATA_RATE_OQ   => "DDR",
                   DATA_RATE_TQ   => "SDR",
                   DATA_WIDTH     => 10,
                   SERDES_MODE    => "SLAVE",
                   TBYTE_CTL      => "FALSE",
                   TBYTE_SRC      => "FALSE",
                   TRISTATE_WIDTH => 1)
      PORT MAP( OFB       => OPEN,
                OQ        => OPEN,
                SHIFTOUT1 => shift1_x,
                SHIFTOUT2 => shift2_x,
                TBYTEOUT  => OPEN,
                TFB       => OPEN,
                TQ        => OPEN,
                CLK       => clk_x5_i,
                CLKDIV    => clk_i,
                D1        => '0',
                D2        => '0',
                D3        => pdata_i(8),
                D4        => pdata_i(9),
                D5        => '0',
                D6        => '0',
                D7        => '0',
                D8        => '0',
                OCE       => '1',
                RST       => rst_x,
                SHIFTIN1  => '0',
                SHIFTIN2  => '0',
                T1        => '0',
                T2        => '0',
                T3        => '0',
                T4        => '0',
                TBYTEIN   => '0',
                TCE       => '0');

  tmds_obufds_inst: OBUFDS
      GENERIC MAP(IOSTANDARD => "TMDS_33")
      PORT MAP( O  => sdata_p_o,
                OB => sdata_n_o,
                I  => sdout_x);
END ARCHITECTURE oserdes_ddr_10_1_a;