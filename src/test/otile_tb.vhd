library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity otile_tb is
end otile_tb;

architecture Behavioral of otile_tb is 
    constant clk_period : time := 10 ns;
    signal clk : std_logic := '0';
    
    signal rst : std_logic := '1';
begin

    clk <= not clk after clk_period / 2;

    DUT : entity work.otile
        port map (
            clk => clk,
            rst => rst,
            OLED_VDD => open,
            OLED_BAT => open,
            OLED_RST => open,
            OLED_CS => open,
            OLED_SCK => open,
            OLED_MOSI => open,
            OLED_CD => open );

    process
    begin
        wait for clk_period * 10.25;
        rst <= '0';
        wait for clk_period;

        wait;
    end process;

end Behavioral;
