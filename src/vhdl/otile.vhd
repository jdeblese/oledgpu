library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity otile is
	port (
    	clk : in std_logic;
        rst : in std_logic;
		VDD : out std_logic;
		VBAT : out std_logic;
		nRESET : out std_logic;
		SCK : out std_logic;
		SDO : out std_logic ) ;
end otile;

architecture Behavioral of otile is 
	type states is ( ST_STARTUP, ST_DISPON, ST_DISPWAIT, ST_READY, ST_BAT_OFF, ST_OFF, ST_SHUTDOWN, ST_PWR_ON, ST_BAT_ON );
    signal state, state_new : states;
    
    -- Internal replica of power signals, inverted before outputting
    signal VDD_int, VDD_new : std_logic;
    signal VBAT_int, VBAT_new : std_logic;
    
    signal nRESET_int, nRESET_new : std_logic;
    
    signal timer0, timer0_new : unsigned(23 downto 0);


	-- SPI transciever signals

	signal spistrobe, spistrobe_new : std_logic;
	signal spibusy : std_logic;

	constant spibitwidth : integer := 8;
	signal spidata, spidata_new : std_logic_vector(spibitwidth-1 downto 0);

	constant spidivby : integer := 100;  -- 1 MHz SPI Clock
	constant spidivbits : integer := 7;  -- to count to 100

begin

	transciever : entity work.spicomm
    	generic map (
        	divby => spidivby,
        	divbits => spidivbits,
            bitwidth => spibitwidth )
        port map (
        	clk => clk,
            rst => rst,
            data => spidata,
            strobe => spistrobe,
            busy => spibusy,
			sck => sck,
			sdi => '0',  -- One-way communication
			sdo => sdo );

	-- Signals drive a PFET, so are inverted
	VDD <= not VDD_int;
    VBAT <= not VBAT_int;
    nRESET <= nRESET_int;

	comb : process(state, VDD_int, VBAT_int, nRESET_int, timer0, spidata)
    	-- reset delay, VDD to VBAT, 30 us
    	constant delay1 : unsigned := to_unsigned(300, timer0'length);

		-- Startup and shutdown delay, 100 ms
    	constant delay2 : unsigned := to_unsigned(10000000, timer0'length);

		variable state_next : states;
        variable VDD_next, VBAT_next, nRESET_next : std_logic;
        variable timer0_next : unsigned(timer0'range);
		variable spistrobe_next : std_logic;
		variable spidata_next : std_logic_vector(spibitwidth-1 downto 0);
    begin
    	state_next := state;

		VDD_next := VDD_int;
        VBAT_next := VBAT_int;
        nRESET_next := nRESET_int;

		timer0_next := timer0 - "1";

		spistrobe_next := '0';
		spidata_next := spidata;

        case state is
        
        	-- While off, hold the module in reset
        	when ST_OFF =>
            	VDD_next := '0';
            	VBAT_next := '0';
                nRESET_next := '1';
                
                state_next := ST_STARTUP;
                
            -- Turn on the main power, delay, and then turn on battery power
            when ST_STARTUP =>
            	VDD_next := '1';
                timer0_next := delay1;

				state_next := ST_PWR_ON;
                
            when ST_PWR_ON =>
                nRESET_next := '0';
                
                -- Send display off command? (0xAE)
                -- Initialize display settings?
                -- Reset is fine for most things, but horizontal mode addressing might be nice (send 0x20 0x00)
                
                -- When the 300 us timer expires...
                if timer0 = to_unsigned(0, timer0'length) then
	                timer0_next := delay2;
                	state_next := ST_BAT_ON;
                end if;

			when ST_BAT_ON =>
               	nRESET_next := '1';
               	VBAT_next := '1';
                
				-- When the 100 ms timer expires...
				if timer0 = to_unsigned(0, timer0'length) then
                	state_next := ST_DISPON;
                end if;
                -- Should be followed by command 0xAF, display on

			-- Send a display on command
			when ST_DISPON =>
                spidata_next := x"AF";
                spistrobe_next := '1';
                if spibusy = '1' then
                	state_next := ST_DISPWAIT;
                end if;
                
            when ST_DISPWAIT =>
				spidata_next := (others => 'Z');
            	if spibusy = '0' then
                	state_next := ST_READY;
                end if;

			-- Display is ready for use
			when ST_READY =>


			-- Turn off battery power, wait, then turn off main power
			when ST_SHUTDOWN =>
            	-- Should be preceeded by command 0xAE, display off
               	VBAT_next := '0';

                timer0_next := delay2;
                state_next := ST_BAT_OFF;
            
			when ST_BAT_OFF =>                
                if timer0 = to_unsigned(0, timer0'length) then
                	state_next := ST_OFF;
                end if;



			when others =>

		end case;
                
        
        state_new <= state_next;

		VDD_new <= VDD_next;
        VBAT_new <= VBAT_next;
        nRESET_new <= nRESET_next;

		timer0_new <= timer0_next;

		spistrobe_new <= spistrobe_next;
		spidata_new <= spidata_next;
    end process;
    
	-- A few signals require asynchronous reset
    async : process(clk, rst)
    begin
    	-- Async reset, to ensure power is off
    	if rst = '1' then
        	VDD_int <= '0';
            VBAT_int <= '0';
    	elsif rising_edge(clk) then
        	VDD_int <= VDD_new;
            VBAT_int <= VBAT_new;
        end if;
    end process;

	-- Most signals only require a synchronous reset
    sync : process(clk, rst)
    begin
    	if rising_edge(clk) then
        	if rst = '1' then
            	state <= ST_OFF;
            else
            	state <= state_new;
                nRESET_int <= nRESET_new;
                timer0 <= timer0_new;
				spidata <= spidata_new;
				spistrobe <= spistrobe_new;
            end if;
        end if;
    end process;

end Behavioral;
