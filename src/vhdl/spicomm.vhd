library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity spicomm is
	Generic (
    	divbits : integer;
        divby : integer;
        bitwidth : integer := 8 );
	Port (
    	clk : in std_logic;
        rst : in std_logic;
        data : in std_logic_vector(bitwidth-1 downto 0);
    	strobe : in std_logic;
        busy : out std_logic;
		sck : out std_logic;
		sdi : in std_logic;
		sdo : out std_logic );
end spicomm;

architecture Behavioral of spicomm is
	-- Clock-related signals
    signal clkdiv, clkdiv_new : unsigned(divbits-1 downto 0);
    signal bitcount, bitcount_new : unsigned(bitwidth-1 downto 0);  -- FIXME should be log2(bitwidth)

	-- Shifter-related signals
    signal shifter, shifter_new : std_logic_vector(bitwidth-1 downto 0);
    signal sdo_int, sdo_new : std_logic;

	-- Controller-related signals
    type states is (ST_WAIT, ST_SETUP, ST_SCKLO, ST_SCKHI, ST_DONE, ST_OUT);
    signal state, state_new : states;
	signal busy_int, busy_new : std_logic;
begin

	busy <= busy_int;
	sdo <= sdo_int;

	comb : process(sdi, strobe, state, shifter, busy_int, sdo_int, clkdiv, bitcount, data)
    	variable state_next : states;
        variable shifter_next : std_logic_vector(shifter'range);
        variable busy_next : std_logic;
        variable sdo_next : std_logic;
        variable clkdiv_next : unsigned(clkdiv'range);
        variable bitcount_next : unsigned(bitcount'range);
    begin
    	state_next := state;
        shifter_next := shifter;
        busy_next := busy_int;
        sdo_next := sdo_int;
        clkdiv_next := clkdiv;
        bitcount_next := bitcount;
        
--      data <= (others => 'Z');
        sck <= '1';
        
        case state is
        
        	when ST_WAIT =>
            	if strobe = '1' then
                	state_next := ST_SETUP;
            		shifter_next := data;
                end if;
            
            when ST_SETUP =>
            	busy_next := '1';
                clkdiv_next := to_unsigned(0, clkdiv'length);
                bitcount_next := to_unsigned(0, bitcount'length);
            	-- Shift out MSb
            	shifter_next := shifter(data'high-1 downto 0) & '0';
                sdo_next := shifter(data'high);
                
                state_next := ST_SCKLO;
                
            when ST_SCKLO =>
            	sck <= '0';
                clkdiv_next := clkdiv + "1";
                
                if clkdiv = to_unsigned(divby/2-1, divbits) then
                	state_next := ST_SCKHI;
                end if;
                
            -- FIXME when is SDI shifted in? Falling edge?
                
            when ST_SCKHI =>
            	sck <= '1';
                clkdiv_next := clkdiv + "1";
                
                if clkdiv = to_unsigned(divby-1, divbits) then
					clkdiv_next := (others => '0');
					-- Read bit in from sdi on falling edge of sck
	            	shifter_next := shifter(data'high-1 downto 0) & sdi;
	                sdo_next := shifter(data'high);
                    bitcount_next := bitcount + "1";

					if bitcount = to_unsigned(bitwidth-1, bitcount'length) then
                    	state_next := ST_DONE;
                    else
						state_next := ST_SCKLO;
	                end if;
                end if;
                
            when ST_DONE =>
            	busy_next := '0';
                state_next := ST_OUT;
                
            when ST_OUT =>
            	-- output is available on pins for one clock cycle, must be latched on the clock rising edge after busy falling edge
--            	data <= shifter;
                state_next := ST_WAIT;
                
            when others =>
        end case;
        
        state_new <= state_next;
        shifter_new <= shifter_next;
        busy_new <= busy_next;
        sdo_new <= sdo_next;
        clkdiv_new <= clkdiv_next;
        bitcount_new <= bitcount_next;
    end process;

	sync : process(clk)
    begin
    	if rising_edge(clk) then
        	if rst = '1' then
            	state <= ST_WAIT;
            else
            	state <= state_new;
		        shifter <= shifter_new;
        		busy_int <= busy_new;
		        sdo_int <= sdo_new;
		        clkdiv <= clkdiv_new;
		        bitcount <= bitcount_new;
            end if;
        end if;
    end process;
                

end Behavioral;
