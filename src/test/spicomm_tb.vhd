library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity spicomm_tb is
end spicomm_tb;

architecture Behavioral of spicomm_tb is
	constant clk_period : time := 10 ns;
	signal clk : std_logic := '0';

	signal rst : std_logic := '1';

	constant bitwidth : integer := 8;
	signal spidata : std_logic_vector(bitwidth-1 downto 0);

	signal spistrobe : std_logic := '0';
	signal spibusy : std_logic;

	constant divby : integer := 100;  -- 1 MHz SPI Clock
	constant divbits : integer := 7;  -- to count to 100

	signal sck, sdo : std_logic;
begin

	clk <= not clk after clk_period / 2;

	DUT : entity work.spicomm
    	generic map (
        	divby => divby,
        	divbits => divbits,
            bitwidth => bitwidth )
        port map (
        	clk => clk,
            rst => rst,
            data => spidata,
            strobe => spistrobe,
            busy => spibusy,
			sck => sck,
			sdi => not sdo,
			sdo => sdo );

	test : process
		variable data : std_logic_vector(spidata'range);
	begin
		wait for clk_period * 10.25;
		rst <= '0';
		wait for clk_period;

		for D in 0 to 255 loop
			data := std_logic_vector(to_unsigned(D,bitwidth));
			spidata <= data;
			spistrobe <= '1';
			wait for clk_period;
			spistrobe <= '0';
			spidata <= (others => 'Z');
			wait for clk_period;  -- One tick for initialization

			for B in 7 downto 0 loop
				assert spibusy = '1' report "SPI should be indicating busy" severity error;
				wait for clk_period * (divby/2 - 1);
				assert sck = '0' report "SCK should be low" severity error;
				wait for clk_period;
				assert sck = '1' report "SCK should be high" severity error;
				assert sdo = data(B) report "SDO doesn't match DATA" severity error;
				wait for clk_period * (divby/2);
			end loop;

			wait for clk_period;  -- One tick to get past busy state
			assert spibusy = '0' report "SPI should be done by now" severity error;
			assert spidata = not data report "Received data doesn't match" severity error;
			wait for clk_period;  -- One tick to get past output state
			assert spidata = (others => 'Z') report "Output should be in HiZ state" severity error;
			wait for clk_period * divby;  -- Separate the transmissions
			
		end loop;

		wait;
	end process;

end Behavioral;
