library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
Library UNISIM;
use UNISIM.vcomponents.all;

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

    signal pixcol, pixcol_new : unsigned(2 downto 0);
    signal tilecol, tilecol_new : unsigned(4 downto 0);
    signal tilerow, tilerow_new : unsigned(2 downto 0);
    constant tilewidth : integer := 6;   -- Width of tile in pixels
    constant tilecount : integer := 21;  -- Tiles per row
    constant tileslack : integer := 2;   -- Extra pixel columns after last tile
    constant tileheight : integer := 8;  -- Rows per screen

    signal DOA, DOB, DIB, DOA2, DOB2, DIB2 : std_logic_vector(31 downto 0);
    signal DIPB, DIPB2 : std_logic_vector(3 downto 0);
    signal ADDRA, ADDRB, ADDRA2, ADDRB2 : std_logic_vector(13 downto 0);
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

    comb : process(state, VDD_int, VBAT_int, nRESET_int, timer0, spibusy, spidata, spicd, pointer, cmdcounter, pixcol, tilecol, tilerow, DOA, DOA2)
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
        variable pixcol_next : unsigned(pixcol'range);
        variable tilecol_next : unsigned(tilecol'range);
        variable tilerow_next : unsigned(tilerow'range);

        variable pixdata : std_logic_vector(3 downto 0);
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
        pixcol_next := pixcol;
        tilecol_next := tilecol;
        tilerow_next := tilerow;

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
                pointer_next := (others => '0');
                pixcol_next := (others => '0');
                tilecol_next := (others => '0');
                tilerow_next := (others => '0');
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
                if DOA2(15) = '1' then
                    pixdata := not DOA(3 downto 0);
                else
                    pixdata := DOA(3 downto 0);
                end if;
                spidata_next := '0' & pixdata(3) & '0' & pixdata(2) & '0' & pixdata(1) & '0' & pixdata(0);
                spistrobe_next := '1';
                spicd_next := '1';  -- Sending data to the OLED, not a command

                -- Update our position counters
                if spibusy = '1' then
                    if tilecol = to_unsigned(tilecount, tilecol'length) then  -- If we are past the final tile, in the slack
                        if pixcol = to_unsigned(tileslack - 1, pixcol'length) then
                            pixcol_next := (others => '0');
                            tilecol_next := (others => '0');
                            -- FIXME the following can be simplified under certain conditions
                            if tilerow = to_unsigned(tileheight - 1, tilerow'length) then
                                tilerow_next := (others => '0');
                            else
                                tilerow_next := tilerow + "1";
                            end if;
                        else
                            pixcol_next := pixcol + "1";
                        end if;
                    elsif pixcol = to_unsigned(tilewidth - 1, pixcol'length) then
                        pixcol_next := (others => '0');
                        tilecol_next := tilecol + "1";
                    else
                        pixcol_next := pixcol + "1";
                    end if;
                    -- For backwards-compatibility's sake
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

        pixcol_new <= pixcol_next;
        tilecol_new <= tilecol_next;
        tilerow_new <= tilerow_next;

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
                pixcol <= pixcol_new;
                tilecol <= tilecol_new;
                tilerow <= tilerow_new;
            end if;
        end if;
    end process;

    mapram : RAMB16BWER
    generic map (
        -- DATA_WIDTH_A/DATA_WIDTH_B: 0, 1, 2, 4, 9, 18, or 36
        DATA_WIDTH_A => 4,
        DATA_WIDTH_B => 0,
        -- DOA_REG/DOB_REG: Optional output register (0 or 1)
        DOA_REG => 1,
        DOB_REG => 0,
        -- EN_RSTRAM_A/EN_RSTRAM_B: Enable/disable RST
        EN_RSTRAM_A => TRUE,
        EN_RSTRAM_B => TRUE,
        -- INIT_00 to INIT_3F: Initial memory contents.
        INIT_00 => X"00008700006999e000e11120004f44c000691120001953100001f10000e195e0",
        INIT_01 => X"0008f80000d555e000f99960001111e0006999f000f5552000ca990000699960",
        INIT_02 => X"0000000000000000000000000000000000000000000000000000000000000000",
        INIT_03 => X"0000000000000000000000000000000000000000000000000000000000000000",
        INIT_04 => X"000000000052596000338420004afa20004f4f40000000000000900000000000",
        INIT_05 => X"000084200000330000888880000065000088e8800048e840000c210000012c00",
        INIT_06 => X"00008700006999e000e11120004f44c000691120001953100001f10000e195e0",
        INIT_07 => X"00085000008421000044444000012480000065000000660000ca990000699960",
        INIT_08 => X"00f991e0000888f0001999f000c211f0002111e0006999f000f444f000e1f960",
        INIT_09 => X"00e111e000f480f000f080f0001111f0001248f0000e11200001f10000f888f0",
        INIT_0A => X"00e161e000c212c000e111e00000f00000699910001ac8f000d251e0000888f0",
        INIT_0B => X"0011111000000000000f11000024800000011f00001195300008780000348430",
        INIT_0C => X"00e555900008f80000d555e000f99960001111e0006999f000f5552000000000",
        INIT_0D => X"00e111e000f008f000f0e0f00001f100001a4f00000e11200000f000007888f0",
        INIT_0E => X"00e161e000c212c000e111e00021e00000255590008008f000f44480008444f0",
        INIT_0F => X"0044f440000000000008611000007000001168000019531000086900001a4a10",
        INIT_10 => X"00e9996000000f7000b4a1e0001911f000002e200000e12000008000001555f0",
        INIT_11 => X"00e161e000c2f2c00001e080001f0f000012c210000e99e0001e00c000555e40",
        INIT_12 => X"00999ff000005800008448000088a8800024842000aaaaa000d303d000195310",
        INIT_13 => X"005a5a5000c2c2c00000e120000e996000000f200044c640005d555000555d50",
        INIT_14 => X"00a55580000070000044f44000d222d000199f900002f2c00000f00000000000",
        INIT_15 => X"0000000000e1d5e000000000000000000025a48000d5559000e55de000000000",
        INIT_16 => X"00088000000f0f0000088c2000000000008440000044c4000011d11000000000",
        INIT_17 => X"0021196000fffff000d39080007a62800084a520000444000004c40000021040",
        INIT_18 => X"004465800099f8f000f444f000f444f000f444f000f444f000f444f000f444f0",
        INIT_19 => X"0001f1000001f1000001f1000001f100001555f0001555f0001555f0001555f0",
        INIT_1A => X"0024842000e111e000e111e000e111e000e111e000e111e000f248f000e19f80",
        INIT_1B => X"000c22f000c222f00008780000e111e000e111e000e111e000e111e000c2a6d0",
        INIT_1C => X"0004658000d5e57000f5552000f5552000f5552000f5552000f5552000f55520",
        INIT_1D => X"0000f0000000f0000000f0000000f00000d555e000d555e000d555e000d555e0",
        INIT_1E => X"008a8880006999600069996000699960006999600069996000f008f000e99960",
        INIT_1F => X"00000000000844f00008690000e111e000e111e000e111e000e111e000c2e3c0",
        INIT_20 => X"0065444000044210004555700007210000465440003444200000720000354430",
        INIT_21 => X"0024300000011100007000000011110000000070000111000034443000344430",
        INIT_22 => X"0000000000000000000000000000000000000000000000000000000000000000",
        INIT_23 => X"0000000000000000000000000000000000000000000000000000000000000000",
        INIT_24 => X"0000650000025430002106600022721000171710000707000000700000000000",
        INIT_25 => X"0021000000000000000000000000000000003000001030100001240000042100",
        INIT_26 => X"0065444000044210004555700007210000465440003444200000720000354430",
        INIT_27 => X"0034442000012400001111100004210000003300000033000034443000344430",
        INIT_28 => X"0024443000444470004444700012447000244430003444700034443000344420",
        INIT_29 => X"0034443000700170007212700000007000421070004740000004740000700070",
        INIT_2A => X"0070007000700070007000700044744000444430003444700034443000344470",
        INIT_2B => X"0000000000124210000744000000012000044700006544400070007000610160",
        INIT_2C => X"0011110000243000000111000070000000111100000000700001110000012400",
        INIT_2D => X"0001110000011010001101100000740000100700000500000000200000000070",
        INIT_2E => X"0010001000100010001000100011711000111100000110100011110000011110",
        INIT_2F => X"0053135000422210000034400000700000443000001111100010001000100010",
        INIT_30 => X"0005200000223120001001000000007000100740002531000005210000511150",
        INIT_31 => X"0001010000013100001111000011111000001220000344300001227000111000",
        INIT_32 => X"0044477000244430003443000000200000210120002222200012221000445640",
        INIT_33 => X"0052525000121210002430000003442000444700001311100000124000421000",
        INIT_34 => X"0005552000007000005313500052225000244300000272100000500000000000",
        INIT_35 => X"0044444000345530000000000064444000252100003555000035553000040400",
        INIT_36 => X"0000000000474730007007000004200000355000002542000011711000075700",
        INIT_37 => X"0000500000777770000100700010007000012520000757000000720000000000",
        INIT_38 => X"0044443000447430000353000041114000455540000555000005310000013500",
        INIT_39 => X"0005150000055500000531000001350000511150001555100015311000113510",
        INIT_3A => X"0021012000411140004555400005550000053100000135000054445000344700",
        INIT_3B => X"0002553000122270003420300050005000144410001420100010241000532210",
        INIT_3C => X"0002221000110110000353000005150000455540000555000005310000013500",
        INIT_3D => X"0002020000022200000420000000240000051500000555000005310000013500",
        INIT_3E => X"0002000000020200002222200002220000042000000024000045545000052000",
        INIT_3F => X"0000000000012270001420100002020000022200000420000000240000031100",
        -- INIT_A/INIT_B: Initial values on output port
        INIT_A => X"000000000",
        INIT_B => X"000000000",
        -- INIT_FILE: Optional file used to specify initial RAM contents
        INIT_FILE => "NONE",
        -- RSTTYPE: "SYNC" or "ASYNC"
        RSTTYPE => "SYNC",
        -- RST_PRIORITY_A/RST_PRIORITY_B: "CE" or "SR"
        RST_PRIORITY_A => "CE",
        RST_PRIORITY_B => "CE",
        -- SIM_COLLISION_CHECK: Collision check enable "ALL", "WARNING_ONLY", "GENERATE_X_ONLY" or "NONE"
        SIM_COLLISION_CHECK => "ALL",
        -- SIM_DEVICE: Must be set to "SPARTAN6" for proper simulation behavior
        SIM_DEVICE => "SPARTAN6",
        -- SRVAL_A/SRVAL_B: Set/Reset value for RAM output
        SRVAL_A => X"000000000",
        SRVAL_B => X"000000000",
        -- WRITE_MODE_A/WRITE_MODE_B: "WRITE_FIRST", "READ_FIRST", or "NO_CHANGE"
        WRITE_MODE_A => "WRITE_FIRST",
        WRITE_MODE_B => "WRITE_FIRST"
    )
    port map (
        -- Port A Data: 32-bit (each) output: Port A data
        DOA => DOA,       -- 32-bit output: A port data output
        DOPA => open,     -- 4-bit output: A port parity output
        -- Port B Data: 32-bit (each) output: Port B data
        DOB => DOB,       -- 32-bit output: B port data output
        DOPB => open,     -- 4-bit output: B port parity output
        -- Port A Data: 32-bit (each) input: Port A data
        DIA => x"00000000", -- 32-bit input: A port data input
        DIPA => x"0",     -- 4-bit input: A port parity input
        -- Port B Data: 32-bit (each) input: Port B data
        DIB => DIB,       -- 32-bit input: B port data input
        DIPB => DIPB,     -- 4-bit input: B port parity input
        -- Port A Address/Control Signals: 14-bit (each) input: Port A address and control signals
        ADDRA => ADDRA,   -- 14-bit input: A port address input
        CLKA => CLK,      -- 1-bit input: A port clock input
        ENA => '1',       -- 1-bit input: A port enable input
        REGCEA => '1',    -- 1-bit input: A port register clock enable input
        RSTA => RST,      -- 1-bit input: A port register set/reset input
        WEA => "0000",    -- 4-bit input: Port A byte-wide write enable input
        -- Port B Address/Control Signals: 14-bit (each) input: Port B address and control signals
        ADDRB => ADDRB,   -- 14-bit input: B port address input
        CLKB => CLK,      -- 1-bit input: B port clock input
        ENB => '0',       -- 1-bit input: B port enable input
        REGCEB => '0',    -- 1-bit input: B port register clock enable input
        RSTB => RST,      -- 1-bit input: B port register set/reset input
        WEB => "0000"     -- 4-bit input: Port B byte-wide write enable input
    );

    ADDRA <= tilerow(0) & DOA2(7 downto 0) & std_logic_vector(pixcol) & "00";
    ADDRB <= (others => '0');
    DIB <= (others => '0');
    DIPB <= (others => '0');


    tileram : RAMB16BWER
    generic map (
        -- DATA_WIDTH_A/DATA_WIDTH_B: 0, 1, 2, 4, 9, 18, or 36
        DATA_WIDTH_A => 18,
        DATA_WIDTH_B => 0,
        -- DOA_REG/DOB_REG: Optional output register (0 or 1)
        DOA_REG => 1,
        DOB_REG => 0,
        -- EN_RSTRAM_A/EN_RSTRAM_B: Enable/disable RST
        EN_RSTRAM_A => TRUE,
        EN_RSTRAM_B => TRUE,
        -- INIT_00 to INIT_3F: Initial memory contents.
        INIT_00 => X"0020002000200020002000200020002000200020007a0048004d003080300031",
        INIT_01 => X"0020002000200020002000200020002000200020002000200020002000200020",
        INIT_02 => X"0020002000200020002000200020002000200020002000200020002000200020",
        INIT_03 => X"0020002000200020002000200020002000200020002000200020002000200020",
        INIT_04 => X"0020002000200020002000200020002000200020002000200020002000200020",
        INIT_05 => X"0020002000200020002000200020002000200020002000200020002000200020",
        INIT_06 => X"0020002000200020002000200020002000200020002000200020002000200020",
        INIT_07 => X"0020002000200020002000200020002000200020002000200020002000200020",
        INIT_08 => X"0020002000200020002000200020002000200020002000200020002000200020",
        INIT_09 => X"0020002000200020002000200020002000200020002000200020002000200020",
        INIT_0A => X"0020002000200020002000200020002000200020002000200020002000200020",
        INIT_0B => X"0020002000200020002000200020002000200020002000200020002000200020",
        INIT_0C => X"0020002000200020002000200020002000200020002000200020002000200020",
        INIT_0D => X"0020002000200020002000200020002000200020002000200020002000200020",
        INIT_0E => X"0020002000200020002000200020002000200020002000200020002000200020",
        INIT_0F => X"0020002000200020002000200020002000200020002000200020002000200020",
        -- INIT_A/INIT_B: Initial values on output port
        INIT_A => X"000000000",
        INIT_B => X"000000000",
        -- INIT_FILE: Optional file used to specify initial RAM contents
        INIT_FILE => "NONE",
        -- RSTTYPE: "SYNC" or "ASYNC"
        RSTTYPE => "SYNC",
        -- RST_PRIORITY_A/RST_PRIORITY_B: "CE" or "SR"
        RST_PRIORITY_A => "CE",
        RST_PRIORITY_B => "CE",
        -- SIM_COLLISION_CHECK: Collision check enable "ALL", "WARNING_ONLY", "GENERATE_X_ONLY" or "NONE"
        SIM_COLLISION_CHECK => "ALL",
        -- SIM_DEVICE: Must be set to "SPARTAN6" for proper simulation behavior
        SIM_DEVICE => "SPARTAN6",
        -- SRVAL_A/SRVAL_B: Set/Reset value for RAM output
        SRVAL_A => X"000000000",
        SRVAL_B => X"000000000",
        -- WRITE_MODE_A/WRITE_MODE_B: "WRITE_FIRST", "READ_FIRST", or "NO_CHANGE"
        WRITE_MODE_A => "WRITE_FIRST",
        WRITE_MODE_B => "WRITE_FIRST"
    )
    port map (
        -- Port A Data: 32-bit (each) output: Port A data
        DOA => DOA2,      -- 32-bit output: A port data output
        DOPA => open,     -- 4-bit output: A port parity output
        -- Port B Data: 32-bit (each) output: Port B data
        DOB => DOB2,      -- 32-bit output: B port data output
        DOPB => open,     -- 4-bit output: B port parity output
        -- Port A Data: 32-bit (each) input: Port A data
        DIA => x"00000000", -- 32-bit input: A port data input
        DIPA => x"0",     -- 4-bit input: A port parity input
        -- Port B Data: 32-bit (each) input: Port B data
        DIB => DIB2,      -- 32-bit input: B port data input
        DIPB => DIPB2,    -- 4-bit input: B port parity input
        -- Port A Address/Control Signals: 14-bit (each) input: Port A address and control signals
        ADDRA => ADDRA2,  -- 14-bit input: A port address input
        CLKA => CLK,      -- 1-bit input: A port clock input
        ENA => '1',       -- 1-bit input: A port enable input
        REGCEA => '1',    -- 1-bit input: A port register clock enable input
        RSTA => RST,      -- 1-bit input: A port register set/reset input
        WEA => "0000",    -- 4-bit input: Port A byte-wide write enable input
        -- Port B Address/Control Signals: 14-bit (each) input: Port B address and control signals
        ADDRB => ADDRB2,  -- 14-bit input: B port address input
        CLKB => CLK,      -- 1-bit input: B port clock input
        ENB => '0',       -- 1-bit input: B port enable input
        REGCEB => '0',    -- 1-bit input: B port register clock enable input
        RSTB => RST,      -- 1-bit input: B port register set/reset input
        WEB => "0000"     -- 4-bit input: Port B byte-wide write enable input
    );

    ADDRA2 <= "000" & std_logic_vector(tilerow(2 downto 1)) & std_logic_vector(tilecol) & "0000";
    ADDRB2 <= (others => '0');
    DIB2 <= (others => '0');
    DIPB2 <= (others => '0');

end Behavioral;
