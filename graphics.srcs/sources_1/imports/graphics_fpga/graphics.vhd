LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;

PACKAGE graphics IS
    TYPE colors IS ARRAY (natural range <>) OF std_logic_vector(23 downto 0);
END PACKAGE graphics;

PACKAGE BODY graphics IS

FUNCTION vertical_lines(pos_x: integer range 0 to 525) RETURN integer IS
VARIABLE index: integer range 0 to 640 := 0;
BEGIN
    CASE pos_x IS
        WHEN   0 to 79  => index := 0;
        WHEN  80 to 159 => index := 1;
        WHEN 160 to 239 => index := 2;
        WHEN 240 to 319 => index := 3;
        WHEN 320 to 399 => index := 4;
        WHEN 400 to 479 => index := 5;
        WHEN 480 to 559 => index := 6;
        WHEN 560 to 640 => index := 7;
        WHEN OTHERS => index := 0;
     END CASE;
     RETURN index;
END FUNCTION vertical_lines;

FUNCTION horizontal_lines(pos_y: integer range 0 to 640) RETURN integer IS
VARIABLE index: integer range 0 to 640 := 0;
BEGIN
    CASE pos_y IS
        WHEN   0 to 79  => index := 0;
        WHEN  80 to 159 => index := 1;
        WHEN 160 to 239 => index := 2;
        WHEN 240 to 319 => index := 3;
        WHEN 320 to 399 => index := 4;
        WHEN 400 to 480 => index := 5;
        WHEN OTHERS => index := 0;
     END CASE;
     RETURN index;
END FUNCTION horizontal_lines;

FUNCTION pixel(pos_x      : integer range 0 to 800;
               pos_y      : integer range 0 to 525;
               pos_x_pix  : integer range 0 to 800;
               pos_y_pix  : integer range 0 to 525;
               color_pix  : std_logic_vector(23 downto 0); 
               color_back : std_logic_vector(23 downto 0))
               RETURN std_logic_vector IS
               VARIABLE rgb: std_logic_vector(23 downto 0);
BEGIN
    IF (pos_x = pos_x_pix AND pos_y = pos_y_pix) THEN
        rgb := color_pix;
    ELSE
        rgb := color_back;
    END IF;
    RETURN rgb;
END FUNCTION pixel;

FUNCTION square(pos_x        : integer range 0 to 800;
                pos_y        : integer range 0 to 525;
                pos_x_square : integer range 0 to 800;
                pos_y_square : integer range 0 to 800;
                dimension    : integer range 0 to 480;
                color_square : std_logic_vector(23 downto 0);
                color_back   : std_logic_vector(23 downto 0))
                RETURN std_logic_vector IS
                VARIABLE rgb: std_logic_vector(23 downto 0); 
BEGIN
    IF ((pos_x >= pos_x_square AND pos_x <= pos_x_square + dimension) AND
        (pos_y >= pos_y_square AND pos_y <= pos_y_square + dimension)) THEN    
        rgb := color_square;
    ELSE
        rgb := color_back;
    END IF;
    RETURN rgb;
END FUNCTION square;

FUNCTION rectangle( pos_x      : integer range 0 to 800;
                    pos_y      : integer range 0 to 525;
                    pos_x_rect : integer range 0 to 800;
                    pos_y_rect : integer range 0 to 800;
                    length     : integer range 0 to 640;
                    width      : integer range 0 to 480; 
                    color_rect : std_logic_vector(23 downto 0);
                    color_back : std_logic_vector(23 downto 0))
                    RETURN std_logic_vector IS
                    VARIABLE rgb: std_logic_vector(23 downto 0); 
BEGIN
    IF ((pos_x >= pos_x_rect AND pos_x <= pos_x_rect + length) AND
       (pos_y >= pos_y_rect AND pos_y <= pos_y_rect + width)) THEN    
        rgb := color_rect;
    ELSE
        rgb := color_back;
    END IF;
    RETURN rgb;
END FUNCTION rectangle;

END PACKAGE BODY graphics;
