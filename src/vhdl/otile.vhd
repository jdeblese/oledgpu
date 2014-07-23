library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity otile is
    port (
        clk : in std_logic;
        rst : in std_logic;
        OLED_VDD : out std_logic;
        OLED_BAT : out std_logic;
        OLED_RST : out std_logic;
        OLED_CS : out std_logic;
        OLED_SCK : out std_logic;
        OLED_MOSI : out std_logic;
        OLED_CD : out std_logic ) ;
end otile;

architecture Behavioral of otile is
    type states is ( ST_STARTUP, ST_DISPON, ST_DISPWAIT, ST_READY, ST_WAIT, ST_BAT_OFF, ST_OFF, ST_SHUTDOWN, ST_PWR_ON, ST_BAT_ON );
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

    -- Data/!Command flag
    signal spicd, spicd_new : std_logic;

    constant startup_len : integer := 8;
    type startup_arr is array (startup_len-1 downto 0) of std_logic_vector(spibitwidth-1 downto 0);
    constant startup_cmds : startup_arr := (
        x"8D", x"14",  -- Enable Charge Pump
        x"A6",  -- Noninverted display
        x"AF",  -- Display On
        x"A4",  -- Use RAM contents
        x"20", x"00",  -- Use horizontal addressing mode
        x"A1" );  -- Reverse direction of columns

    -- Up to 16 commands, FIXME
    signal cmdcounter, cmdcounter_new : unsigned(3 downto 0);

    -- 8 rows of 128 columns -> 10 bit counter
    signal pointer, pointer_new : unsigned(9 downto 0);

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
            sck => OLED_SCK,
            sdi => '0',  -- One-way communication
            sdo => OLED_MOSI );

    -- Signals drive a PFET, so are inverted
    OLED_VDD <= not VDD_int;
    OLED_BAT <= not VBAT_int;
    OLED_RST <= nRESET_int;

    OLED_CS <= not spibusy;
    OLED_CD <= spicd;

    comb : process(state, VDD_int, VBAT_int, nRESET_int, timer0, spibusy, spidata, spicd, pointer, cmdcounter)
        -- reset delay, VDD to VBAT, 3 us
        constant delay1 : unsigned := to_unsigned(300, timer0'length);

        -- Startup and shutdown delay, 100 ms (FIXME should be 100 ms)
        constant delay2 : unsigned := to_unsigned(10000000, timer0'length);

        -- 1 us
        constant delay3 : unsigned := to_unsigned(100, timer0'length);

        variable state_next : states;
        variable VDD_next, VBAT_next, nRESET_next : std_logic;
        variable timer0_next : unsigned(timer0'range);
        variable spistrobe_next : std_logic;
        variable spidata_next : std_logic_vector(spidata'range);
        variable spicd_next : std_logic;
        variable pointer_next : unsigned(pointer'range);
        variable cmdcounter_next : unsigned(cmdcounter'range);
    begin
        state_next := state;

        VDD_next := VDD_int;
        VBAT_next := VBAT_int;
        nRESET_next := nRESET_int;

        if timer0 > "0" then
            timer0_next := timer0 - "1";
        else
            timer0_next := (others => '0');
        end if;

        spistrobe_next := '0';
        spidata_next := spidata;
        spicd_next := spicd;

        cmdcounter_next := cmdcounter;
        pointer_next := pointer;

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

                -- When the 300 us timer expires...
                if timer0 = to_unsigned(0, timer0'length) then
                    timer0_next := delay2;
                    state_next := ST_BAT_ON;
                end if;

            when ST_BAT_ON =>
                   nRESET_next := '1';
                   VBAT_next := '1';

                cmdcounter_next := to_unsigned(startup_len, cmdcounter'length);
                pointer_next := (others => '0');

                -- When the 100 ms timer expires...
                if timer0 = to_unsigned(0, timer0'length) then
                    state_next := ST_DISPON;
                end if;

            -- Send a display on command
            when ST_DISPON =>
                spidata_next := startup_cmds(to_integer(cmdcounter) - 1);
                spistrobe_next := '1';
                spicd_next := '0';  -- Sending commands
                if spibusy = '1' then
                    cmdcounter_next := cmdcounter - "1";
                    state_next := ST_DISPWAIT;
                end if;

            when ST_DISPWAIT =>
--              spidata_next := (others => 'Z');
                if spibusy = '0' then
                    if timer0_next = "0" then
                        if cmdcounter = "0" then
                            state_next := ST_READY;
                        else
                            state_next := ST_DISPON;
                        end if;
                    end if;
                else
                    timer0_next := delay3;
                end if;

            -- Display is ready for use
            when ST_READY =>
                if pointer(0) = '1' then
                    spidata_next := '0' & pointer(4) & '0' & pointer(3) & '0' & pointer(2) & '0' & pointer(1);
                else
                    spidata_next := '0' & pointer(8) & '0' & pointer(7) & '0' & pointer(6) & '0' & pointer(5);
                end if;
                spistrobe_next := '1';
                spicd_next := '1';  -- Sending data
                if spibusy = '1' then
                    pointer_next := pointer + "1";
                    state_next := ST_WAIT;
                end if;

            when ST_WAIT =>
--              spidata_next := (others => 'Z');
                if spibusy = '0' then
                    if timer0_next = "0" then
                        state_next := ST_READY;
                    end if;
                else
                    timer0_next := delay3;
                end if;


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
        spicd_new <= spicd_next;

        cmdcounter_new <= cmdcounter_next;
        pointer_new <= pointer_next;

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
                nRESET_int <= '1';
            else
                state <= state_new;
                nRESET_int <= nRESET_new;
                timer0 <= timer0_new;
                spidata <= spidata_new;
                spistrobe <= spistrobe_new;
                spicd <= spicd_new;
                cmdcounter <= cmdcounter_new;
                pointer <= pointer_new;
            end if;
        end if;
    end process;

end Behavioral;
