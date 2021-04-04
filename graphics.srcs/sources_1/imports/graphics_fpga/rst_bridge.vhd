LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;

ENTITY rst_bridge IS
  GENERIC( G_ARST_POLARITY : std_logic := '1';
           G_SRST_POLARITY : std_logic := '1');
  PORT( arst_in  : IN  std_logic;
        sclk_in  : IN  std_logic;
        srst_out : OUT std_logic);
END ENTITY rst_bridge;

ARCHITECTURE rst_bridge_a OF rst_bridge IS
  SIGNAL srst_d0_r : std_logic;
  SIGNAL srst_d1_r : std_logic;

  ATTRIBUTE ASYNC_REG : string;
  ATTRIBUTE ASYNC_REG OF srst_d0_r, srst_d1_r: SIGNAL IS "TRUE"; 
BEGIN

  reset_dff : PROCESS(arst_in, sclk_in)
  BEGIN
    IF (arst_in = G_ARST_POLARITY) THEN
        srst_d0_r <= G_SRST_POLARITY;
        srst_d1_r <= G_SRST_POLARITY;
    ELSIF rising_edge(sclk_in) THEN
        srst_d0_r <= NOT G_SRST_POLARITY;
        srst_d1_r <= srst_d0_r;
    END IF;
  END PROCESS;

  srst_out <= srst_d1_r;

end architecture rst_bridge_a;