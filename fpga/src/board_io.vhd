library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity board_io is
    Port (
        clk  : in STD_LOGIC;

        btnU : in STD_LOGIC;
        btnD : in STD_LOGIC;
        btnL : in STD_LOGIC;
        btnR : in STD_LOGIC;
        btnC : in STD_LOGIC;

        sw   : in STD_LOGIC_VECTOR (15 downto 0);

        led  : out STD_LOGIC_VECTOR (15 downto 0);

        seg  : out STD_LOGIC_VECTOR (7 downto 0);
        an   : out STD_LOGIC_VECTOR (3 downto 0);

        tx_serial : out STD_LOGIC;
        rx_serial : in  STD_LOGIC
    );
end board_io;

architecture Behavioral of board_io is

signal btnU_db, btnD_db, btnL_db, btnR_db, btnC_db : std_logic;
signal btnU_p, btnD_p, btnL_p, btnR_p, btnC_p : std_logic;

signal sw_db : std_logic_vector(15 downto 0);
signal sw_p_dummy : std_logic_vector(15 downto 0);

signal led_fsm : std_logic_vector(15 downto 0);

signal d0, d1, d2, d3 : std_logic_vector(3 downto 0);
signal flash_colon : std_logic;

signal rst_game : std_logic;

-- power-on reset
signal por_cnt : unsigned(23 downto 0) := (others => '0');
signal por_rst : std_logic := '1';

-- extra debug/status from FSM
signal state_code : std_logic_vector(2 downto 0);
signal score_uart : std_logic_vector(7 downto 0);
signal high_uart  : std_logic_vector(7 downto 0);
signal last_btn   : std_logic_vector(2 downto 0);

-- UART TX
signal uart_start : std_logic := '0';
signal uart_busy  : std_logic;
signal uart_data  : std_logic_vector(7 downto 0) := (others => '0');
signal uart_tx_s  : std_logic := '1';

-- UART RX
signal rx_data       : std_logic_vector(7 downto 0);
signal rx_valid      : std_logic;

-- web-generated one-clock pulses
signal btnU_web_p    : std_logic := '0';
signal btnD_web_p    : std_logic := '0';
signal btnL_web_p    : std_logic := '0';
signal btnR_web_p    : std_logic := '0';
signal btnC_web_p    : std_logic := '0';

-- merged pulses: physical board + website
signal start_p_all   : std_logic;
signal r_p_all       : std_logic;
signal g_p_all       : std_logic;
signal y_p_all       : std_logic;
signal b_p_all       : std_logic;

-- packet sender
type tx_state_t is (
  TX_IDLE,
  TX_B0, TX_B0_WAIT,
  TX_B1, TX_B1_WAIT,
  TX_B2, TX_B2_WAIT,
  TX_B3, TX_B3_WAIT,
  TX_B4, TX_B4_WAIT,
  TX_B5, TX_B5_WAIT,
  TX_B6, TX_B6_WAIT,
  TX_B7, TX_B7_WAIT,
  TX_B8, TX_B8_WAIT
);
signal tx_state : tx_state_t := TX_IDLE;

signal frame_tick_cnt : unsigned(22 downto 0) := (others => '0');
signal frame_tick     : std_logic := '0';

begin

  ------------------------------------------------------------------------------
  -- Power-on reset
  process(clk)
  begin
    if rising_edge(clk) then
      if por_cnt = to_unsigned(5000000, por_cnt'length) then
        por_rst <= '0';
      else
        por_cnt <= por_cnt + 1;
        por_rst <= '1';
      end if;
    end if;
  end process;

  rst_game <= por_rst or sw_db(0);

  ------------------------------------------------------------------------------
  -- Input cleaning
  u_clean : entity work.clean_signals
    generic map(
      CLK_HZ => 100000000,
      DEBOUNCE_MS => 2
    )
    port map(
      clk => clk,

      btnU => btnU,
      btnD => btnD,
      btnL => btnL,
      btnR => btnR,
      btnC => btnC,

      sw => sw,

      btnU_db => btnU_db,
      btnD_db => btnD_db,
      btnL_db => btnL_db,
      btnR_db => btnR_db,
      btnC_db => btnC_db,

      sw_db => sw_db,

      btnU_p => btnU_p,
      btnD_p => btnD_p,
      btnL_p => btnL_p,
      btnR_p => btnR_p,
      btnC_p => btnC_p,

      sw_p => sw_p_dummy
    );

  ------------------------------------------------------------------------------
  -- UART receiver
  u_uart_rx : entity work.uart_rx
    generic map(
      CLKS_PER_BIT => 868
    )
    port map(
      clk        => clk,
      rst        => rst_game,
      rx         => rx_serial,
      data_out   => rx_data,
      data_valid => rx_valid
    );

  ------------------------------------------------------------------------------
  -- Decode bytes from website/bridge into one-clock pulses
  -- Expected ASCII:
  -- 'L' = left/red
  -- 'R' = right/green
  -- 'U' = up/yellow
  -- 'D' = down/blue
  -- 'C' = center/start
  process(clk)
  begin
    if rising_edge(clk) then
      if rst_game='1' then
        btnU_web_p <= '0';
        btnD_web_p <= '0';
        btnL_web_p <= '0';
        btnR_web_p <= '0';
        btnC_web_p <= '0';
      else
        btnU_web_p <= '0';
        btnD_web_p <= '0';
        btnL_web_p <= '0';
        btnR_web_p <= '0';
        btnC_web_p <= '0';

        if rx_valid='1' then
          case rx_data is
            when x"4C" => btnL_web_p <= '1'; -- 'L'
            when x"52" => btnR_web_p <= '1'; -- 'R'
            when x"55" => btnU_web_p <= '1'; -- 'U'
            when x"44" => btnD_web_p <= '1'; -- 'D'
            when x"43" => btnC_web_p <= '1'; -- 'C'
            when others => null;
          end case;
        end if;
      end if;
    end if;
  end process;

  ------------------------------------------------------------------------------
  -- Merge physical + website controls
  start_p_all <= btnC_p or btnC_web_p;
  r_p_all     <= btnL_p or btnL_web_p;
  g_p_all     <= btnR_p or btnR_web_p;
  y_p_all     <= btnU_p or btnU_web_p;
  b_p_all     <= btnD_p or btnD_web_p;

  ------------------------------------------------------------------------------
  -- Simon FSM
  u_fsm : entity work.simon_fsm
    port map(
      clk => clk,
      rst => rst_game,

      start_p => start_p_all,

      r_p => r_p_all,
      g_p => g_p_all,
      y_p => y_p_all,
      b_p => b_p_all,

      clear_p => sw_db(1),

      led_out => led_fsm,

      dig3 => d3,
      dig2 => d2,
      dig1 => d1,
      dig0 => d0,

      flash_colon => flash_colon,

      state_code => state_code,
      score_out  => score_uart,
      high_out   => high_uart,
      last_btn   => last_btn
    );

  led <= led_fsm;

  ------------------------------------------------------------------------------
  -- 7-segment display
  u_display : entity work.sevenseg_mux4
    port map(
      clk => clk,
      rst => rst_game,

      d3 => d3,
      d2 => d2,
      d1 => d1,
      d0 => d0,

      flash_colon => flash_colon,

      seg => seg,
      an => an
    );

  ------------------------------------------------------------------------------
  -- UART transmitter
  u_uart_tx : entity work.uart_tx
    generic map(
      CLKS_PER_BIT => 868
    )
    port map(
      clk     => clk,
      rst     => rst_game,
      start   => uart_start,
      data_in => uart_data,
      tx      => uart_tx_s,
      busy    => uart_busy
    );

  tx_serial <= uart_tx_s;

  ------------------------------------------------------------------------------
  -- frame tick ~ every 50 ms
  process(clk)
  begin
    if rising_edge(clk) then
      if rst_game='1' then
        frame_tick_cnt <= (others => '0');
        frame_tick <= '0';
      else
        frame_tick <= '0';
        if frame_tick_cnt = to_unsigned(5000000-1, frame_tick_cnt'length) then
          frame_tick_cnt <= (others => '0');
          frame_tick <= '1';
        else
          frame_tick_cnt <= frame_tick_cnt + 1;
        end if;
      end if;
    end if;
  end process;

  ------------------------------------------------------------------------------
  -- Packet format:
  -- 0xAA
  -- state_code in bits[2:0]
  -- score
  -- highscore
  -- last_btn in bits[2:0]
  -- flash_colon in bit0
  -- led[15:8]
  -- led[7:0]
  -- 0x55
  process(clk)
  begin
    if rising_edge(clk) then
      if rst_game='1' then
        tx_state    <= TX_IDLE;
        uart_start  <= '0';
        uart_data   <= (others => '0');

      else
        uart_start <= '0';

        case tx_state is
          when TX_IDLE =>
            if frame_tick='1' then
              tx_state <= TX_B0;
            end if;

          when TX_B0 =>
            if uart_busy='0' then
              uart_data  <= x"AA";
              uart_start <= '1';
              tx_state   <= TX_B0_WAIT;
            end if;

          when TX_B0_WAIT =>
            if uart_busy='0' then
              tx_state <= TX_B1;
            end if;

          when TX_B1 =>
            if uart_busy='0' then
              uart_data  <= "00000" & state_code;
              uart_start <= '1';
              tx_state   <= TX_B1_WAIT;
            end if;

          when TX_B1_WAIT =>
            if uart_busy='0' then
              tx_state <= TX_B2;
            end if;

          when TX_B2 =>
            if uart_busy='0' then
              uart_data  <= score_uart;
              uart_start <= '1';
              tx_state   <= TX_B2_WAIT;
            end if;

          when TX_B2_WAIT =>
            if uart_busy='0' then
              tx_state <= TX_B3;
            end if;

          when TX_B3 =>
            if uart_busy='0' then
              uart_data  <= high_uart;
              uart_start <= '1';
              tx_state   <= TX_B3_WAIT;
            end if;

          when TX_B3_WAIT =>
            if uart_busy='0' then
              tx_state <= TX_B4;
            end if;

          when TX_B4 =>
            if uart_busy='0' then
              uart_data  <= "00000" & last_btn;
              uart_start <= '1';
              tx_state   <= TX_B4_WAIT;
            end if;

          when TX_B4_WAIT =>
            if uart_busy='0' then
              tx_state <= TX_B5;
            end if;

          when TX_B5 =>
            if uart_busy='0' then
              uart_data  <= "0000000" & flash_colon;
              uart_start <= '1';
              tx_state   <= TX_B5_WAIT;
            end if;

          when TX_B5_WAIT =>
            if uart_busy='0' then
              tx_state <= TX_B6;
            end if;

          when TX_B6 =>
            if uart_busy='0' then
              uart_data  <= led_fsm(15 downto 8);
              uart_start <= '1';
              tx_state   <= TX_B6_WAIT;
            end if;

          when TX_B6_WAIT =>
            if uart_busy='0' then
              tx_state <= TX_B7;
            end if;

          when TX_B7 =>
            if uart_busy='0' then
              uart_data  <= led_fsm(7 downto 0);
              uart_start <= '1';
              tx_state   <= TX_B7_WAIT;
            end if;

          when TX_B7_WAIT =>
            if uart_busy='0' then
              tx_state <= TX_B8;
            end if;

          when TX_B8 =>
            if uart_busy='0' then
              uart_data  <= x"55";
              uart_start <= '1';
              tx_state   <= TX_B8_WAIT;
            end if;

          when TX_B8_WAIT =>
            if uart_busy='0' then
              tx_state <= TX_IDLE;
            end if;

        end case;
      end if;
    end if;
  end process;

end Behavioral;
