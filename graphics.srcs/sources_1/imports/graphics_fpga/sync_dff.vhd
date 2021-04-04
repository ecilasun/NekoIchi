LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;

ENTITY sync_dff IS
    PORT( async_in : IN  std_logic;
          sclk_in  : IN  std_logic;
          sync_out : OUT std_logic);
END ENTITY sync_dff;

ARCHITECTURE sync_dff_a OF sync_dff IS
  SIGNAL sync_d0_r : std_logic;
  SIGNAL sync_d1_r : std_logic;

  ATTRIBUTE ASYNC_REG : string;
  ATTRIBUTE ASYNC_REG of sync_d0_r, sync_d1_r: SIGNAL IS "TRUE"; 
BEGIN
    sync_dff : PROCESS(sclk_in)
    BEGIN
      IF rising_edge(sclk_in) THEN
          sync_d0_r <= async_in;
          sync_d1_r <= sync_d0_r;
      END IF;
    END PROCESS;

  sync_out <= sync_d1_r;

END ARCHITECTURE sync_dff_a;