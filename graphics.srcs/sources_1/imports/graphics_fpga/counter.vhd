LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.STD_LOGIC_UNSIGNED.ALL;

ENTITY counter IS
    GENERIC(max: integer);
    PORT( clk   : IN  std_logic;
          count : OUT std_logic_vector(20 downto 0));
END ENTITY counter;

ARCHITECTURE counter_a OF counter IS
BEGIN
    PROCESS (clk)
    VARIABLE cnt: std_logic_vector(20 downto 0) := (OTHERS => '0');
    BEGIN									
        IF rising_edge(clk) THEN
            cnt := cnt + '1';
            IF (cnt = max) THEN
                cnt := (OTHERS => '0');
            END IF;
        END IF;	
        count <= cnt;
    END PROCESS;
END ARCHITECTURE counter_a;


