LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.NUMERIC_STD.ALL;

ENTITY tmds_encoder IS
    PORT( clk_i   : IN  std_logic;                    -- pixel clock
          pixel_i : IN  std_logic_vector(7 downto 0); -- pixel data
          ctrl_i  : IN  std_logic_vector(1 downto 0); -- control data
          de_i    : IN  std_logic;                    -- pixel data enable (not blanking)
          tmds_o  : OUT std_logic_vector(9 downto 0));
END ENTITY tmds_encoder;

ARCHITECTURE tmds_encoder_a OF tmds_encoder IS
    SIGNAL qm_xor     : std_logic_vector(8 downto 0) := (others=>'0');
    SIGNAL qm_xnor    : std_logic_vector(8 downto 0) := (others=>'0');
    SIGNAL ones_pixel : unsigned(3 downto 0) := (others=>'0');
    SIGNAL qm         : std_logic_vector(8 downto 0) := (others=>'0');
  
    SIGNAL de_r       : std_logic := '0';
    SIGNAL ctrl_r     : std_logic_vector(1 downto 0) := (others=>'0');
    SIGNAL qm_r       : std_logic_vector(8 downto 0) := (others=>'0');
    SIGNAL ones_qm_x  : unsigned(3 downto 0) := (others=>'0');
    SIGNAL bias_r     : integer range -8 to 8 := 0; -- 5 bits
    SIGNAL diff       : integer range -8 to 8 := 0; -- 5 bits
    SIGNAL tmds_r     : std_logic_vector(9 downto 0) := (others=>'0');
BEGIN
  -- First stage: Transition minimized encoding

  qm_xor(0) <= pixel_i(0);
  qm_xor(8) <= '1';
  encode_xor: FOR n IN 1 to 7 GENERATE
  BEGIN
      qm_xor(n) <= qm_xor(n-1) XOR pixel_i(n);
  END GENERATE;

  qm_xnor(0) <= pixel_i(0);
  qm_xnor(8) <= '0';
  encode_xnor: FOR n IN 1 to 7 GENERATE
  BEGIN
      qm_xnor(n) <= qm_xnor(n-1) XNOR pixel_i(n);
  END GENERATE;

  -- count the number of ones in the symbol
  ones_pixel_p: PROCESS(pixel_i)
  VARIABLE sum : unsigned(3 downto 0);
  BEGIN
    sum := (OTHERS => '0');
    FOR n IN 0 to 7 LOOP
        sum := sum + to_integer(unsigned(pixel_i(n downto n)));
    END LOOP;
    ones_pixel <= sum;
  END PROCESS;

  -- select encoding based on number of ones
  qm <= qm_xnor WHEN ((ones_pixel > 4) OR (ones_pixel = 4 AND pixel_i(0) = '0')) ELSE qm_xor;

  -- Second stage: Fix DC bias
  qm_r_p: PROCESS(clk_i)
  BEGIN
      IF (rising_edge(clk_i)) THEN
          de_r   <= de_i;
          ctrl_r <= ctrl_i;
          qm_r   <= qm;
      END IF;
  END PROCESS;

  -- count the number of ones in the encoded symbol
  ones_qm_p : PROCESS(qm_r)
  VARIABLE sum : unsigned(3 downto 0);
  BEGIN
      sum := (OTHERS => '0');
      FOR n IN 0 to 7 LOOP
          sum := sum + to_integer(unsigned(qm_r(n downto n)));
      END LOOP;
      ones_qm_x <= sum;
  END PROCESS;

  -- Calculate the difference between the number of ones (n1) and number of zeros (n0) in the encoded symbol
  diff <= to_integer(ones_qm_x & '0') - 8; -- n1 - n0 = 2 * n1 - 8

  tmds_p : PROCESS(clk_i)
  BEGIN
    IF (rising_edge(clk_i)) THEN
        IF (de_r = '0') THEN
            CASE ctrl_r IS
                WHEN "00"   => tmds_r <= "1101010100";
                WHEN "01"   => tmds_r <= "0010101011";
                WHEN "10"   => tmds_r <= "0101010100";
                WHEN OTHERS => tmds_r <= "1010101011";
            END CASE;
            bias_r <= 0;
        ELSE
            IF ((bias_r = 0) OR (diff = 4)) THEN
                IF (qm_r(8) = '0') THEN
                    tmds_r <= "10" & (not qm_r(7 downto 0));
                    bias_r <= bias_r - diff;
                ELSE
                    tmds_r <= "01" & qm_r(7 downto 0);
                    bias_r <= bias_r + diff;
                END IF;
            ELSE
                IF ((bias_r > 0) and (diff > 4)) OR ((bias_r < 0) and (diff < 4)) THEN
                    tmds_r <= '1' & qm_r(8) & (NOT qm_r(7 downto 0));
                    if (qm_r(8) = '0') THEN
                        bias_r <= bias_r - diff;
                    ELSE
                        bias_r <= bias_r - diff + 2;
                    END IF;
                ELSE
                    tmds_r <= '0' & qm_r;
                    IF (qm_r(8) = '0') THEN
                        bias_r <= bias_r + diff;
                    ELSE
                        bias_r <= bias_r + diff - 2;
                    END IF;
                END IF;
            END IF;
        END IF;
    END IF;
  END PROCESS;

  tmds_o <= tmds_r;

END ARCHITECTURE tmds_encoder_a;