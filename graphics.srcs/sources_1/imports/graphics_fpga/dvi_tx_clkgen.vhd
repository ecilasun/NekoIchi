LIBRARY IEEE;
LIBRARY UNISIM;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.NUMERIC_STD.ALL;
USE UNISIM.VCOMPONENTS.ALL;

ENTITY dvi_tx_clkgen IS
    PORT( clk_i       : in  std_logic;   -- 125 MHz reference clock
          arst_i      : in  std_logic;   -- asynchronous reset (from board pin)
          locked_o    : out std_logic;   -- synchronous to reference clock
          pixel_clk_o : out std_logic;   -- pixel clock
          sclk_o      : out std_logic;   -- serdes clock (framing clock)
          sclk_x5_o   : out std_logic);  -- serdes clock x5 (bit clock)
END ENTITY dvi_tx_clkgen;

ARCHITECTURE dvi_tx_clkgen_a OF dvi_tx_clkgen IS

  SIGNAL clkfb_x            : std_logic;
  SIGNAL refrst_x           : std_logic;
  SIGNAL mmcm_locked_x      : std_logic;
  SIGNAL mmcm_locked_sync_x : std_logic;
  SIGNAL mmcm_rst_r         : std_logic;
  SIGNAL bufr_rst_r         : std_logic;
  SIGNAL pixel_clk_x        : std_logic;
  SIGNAL sclk_x5_x          : std_logic;

  TYPE fsm_mmcm_rst_t is (WAIT_LOCK, LOCKED);
  SIGNAL state_mmcm_rst : fsm_mmcm_rst_t := WAIT_LOCK;

BEGIN
  -- The reset bridge will make sure we can use the async rst
  -- safely in the reference clock domain
  refrst_inst : ENTITY work.rst_bridge
    PORT MAP( arst_in  => arst_i,
              sclk_in  => clk_i,
              srst_out => refrst_x);

  -- sync MMCM lock signal to the reference clock domain
  sync_mmcm_locked_inst : ENTITY work.sync_dff
    PORT MAP( async_in => mmcm_locked_x,
              sclk_in  => clk_i,
              sync_out => mmcm_locked_sync_x);

  -- Need to generate an MMCM reset pulse >= 5 ns (Xilinx DS191).
  -- We can use the reference clock to create the pulse. The fsm
  -- below will only work is the reference clk frequency is < 200MHz.
  -- The BUFR needs to be reset any time the MMCM acquires lock.
  fsm_mmcm_rst : PROCESS(refrst_x, clk_i)
  BEGIN
    IF (refrst_x = '1') THEN
        state_mmcm_rst <= WAIT_LOCK;
        mmcm_rst_r <= '1';
        bufr_rst_r <= '0';
    ELSIF rising_edge(clk_i) THEN
        mmcm_rst_r <= '0';
        bufr_rst_r <= '0';
        CASE state_mmcm_rst IS
            WHEN WAIT_LOCK =>
                IF (mmcm_locked_sync_x = '1') THEN
                    bufr_rst_r     <= '1';
                    state_mmcm_rst <= LOCKED;
                END IF;
            WHEN LOCKED =>
                IF (mmcm_locked_sync_x = '0') THEN
                    mmcm_rst_r     <= '1';
                    state_mmcm_rst <= WAIT_LOCK;
                END IF;
            END CASE;
    END IF;
  END PROCESS;

  
  mmcme2_adv_inst : MMCME2_ADV
    GENERIC MAP( BANDWIDTH          => "OPTIMIZED",
                 CLKFBOUT_MULT_F    => 12.0,
                 CLKFBOUT_PHASE     => 0.0,
                 CLKIN1_PERIOD      => 8.0,
      
                 -- Pixel clock: 150MHz. Use these values for 1920x1080
                 --CLKOUT0_DIVIDE_F   => 1.0,
                 --CLKOUT1_DIVIDE     => 5,  
        
                 ---- Pixel clock: 75MHz. Use these values for 1280x720
                 --CLKOUT0_DIVIDE_F   => 2.0,
                 --CLKOUT1_DIVIDE     => 10,
              
                 ---- Pixel clock: 25MHz. Use these values for 640x480
                 CLKOUT0_DIVIDE_F   => 6.0,
                 CLKOUT1_DIVIDE     => 30,
   
   
                 COMPENSATION       => "ZHOLD",
                 DIVCLK_DIVIDE      => 2,
                 REF_JITTER1        => 0.0)
    PORT MAP( CLKOUT0      => sclk_x5_x,
              CLKOUT0B     => OPEN,
              CLKOUT1      => pixel_clk_x,
              CLKOUT1B     => OPEN,
              CLKOUT2      => OPEN,
              CLKOUT2B     => OPEN,
              CLKOUT3      => OPEN,
              CLKOUT3B     => OPEN,
              CLKOUT4      => OPEN,
              CLKOUT5      => OPEN,
              CLKOUT6      => OPEN,
              CLKFBOUT     => clkfb_x,
              CLKFBOUTB    => OPEN,

              CLKIN1       => clk_i,
              CLKIN2       => '0',
              CLKFBIN      => clkfb_x,
              CLKINSEL     => '1',

              DCLK         => '0',
              DEN          => '0',
              DWE          => '0',
              DADDR        => (OTHERS => '0'),
              DI           => (OTHERS => '0'),
              DO           => OPEN,
              DRDY         => OPEN,
        
              PSCLK        => '0',
              PSEN         => '0',
              PSINCDEC     => '0',
              PSDONE       => OPEN,
        
              LOCKED       => mmcm_locked_x,
              PWRDWN       => '0',
              RST          => mmcm_rst_r,
              CLKFBSTOPPED => OPEN,
              CLKINSTOPPED => OPEN);

  bufio_inst : BUFIO
    PORT MAP( O => sclk_x5_o, 
              I => sclk_x5_x);

  -- If the clock to the BUFR is stopped, then a reset (CLR) 
  -- must be applied after the clock returns (see Xilinx UG472)
  bufr_inst : BUFR
    GENERIC MAP( BUFR_DIVIDE => "5",
                 SIM_DEVICE  => "7SERIES")
    PORT MAP( O   => sclk_o,
              CE  => '1',
              CLR => bufr_rst_r,
              I   => sclk_x5_x);

  -- The tools will issue a warning that pixel clock is not 
  -- phase aligned to sclk_x, sclk_x5_x. We can safely
  -- ignore it as we don't care about the phase relationship
  -- of the pixel clock to the sampling clocks.
  bufg_inst : BUFG
    PORT MAP( O => pixel_clk_o,
              I => pixel_clk_x);

  locked_p : PROCESS(mmcm_locked_x, clk_i)
  BEGIN
    IF (mmcm_locked_x = '0') THEN
        locked_o <= '0';
    ELSIF rising_edge(clk_i) THEN
        -- Raise locked only after BUFR has been reset
        IF (bufr_rst_r = '1') THEN
            locked_o <= '1';
        END IF;
    END IF;
  END PROCESS;

END ARCHITECTURE dvi_tx_clkgen_a;