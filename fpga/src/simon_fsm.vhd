library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity simon_fsm is
  generic(
    CLK_HZ        : integer := 100_000_000;
    WDT_SEC       : integer := 16;
    SEQ_MAX       : integer := 32;
    FLASH_STEP_HZ : integer := 8
  );
  port(
    clk   : in  std_logic;
    rst   : in  std_logic;

    start_p : in std_logic;
    r_p     : in std_logic;
    g_p     : in std_logic;
    y_p     : in std_logic;
    b_p     : in std_logic;

    clear_p : in std_logic;

    led_out : out std_logic_vector(15 downto 0);

    dig3 : out std_logic_vector(3 downto 0);
    dig2 : out std_logic_vector(3 downto 0);
    dig1 : out std_logic_vector(3 downto 0);
    dig0 : out std_logic_vector(3 downto 0);

    flash_colon : out std_logic;

    state_code : out std_logic_vector(2 downto 0);
    score_out  : out std_logic_vector(7 downto 0);
    high_out   : out std_logic_vector(7 downto 0);
    last_btn   : out std_logic_vector(2 downto 0)
  );
end entity;

architecture rtl of simon_fsm is

  type state_t is (ST_INIT, ST_ON, ST_PLAY, ST_LOSE, ST_CLEAR, ST_TIMEOUT, ST_SLEEP);
  signal st : state_t := ST_INIT;

  signal gkey   : std_logic;
  signal anykey : std_logic;

  constant TICK_DIV : integer := CLK_HZ;
  signal tick_cnt : unsigned(31 downto 0) := (others => '0');
  signal tick_1s  : std_logic := '0';

  constant FLASH_DIV : integer := CLK_HZ / FLASH_STEP_HZ;
  signal flash_tick_cnt : unsigned(31 downto 0) := (others => '0');
  signal tick_flash     : std_logic := '0';

  signal wdt_cnt : unsigned(4 downto 0) := (others => '0');
  signal wdt_exp : std_logic;

  signal lfsr : std_logic_vector(7 downto 0) := x"5A";

  type seq_t is array(0 to SEQ_MAX-1) of std_logic_vector(1 downto 0);
  signal seq : seq_t := (others => (others => '0'));
  signal seq_len : integer range 0 to SEQ_MAX := 0;

  signal play_mode : std_logic := '0';  -- 0=show sequence, 1=wait user input
  signal ix_show   : integer range 0 to SEQ_MAX-1 := 0;
  signal show_on   : std_logic := '0';
  signal ix_in     : integer range 0 to SEQ_MAX-1 := 0;

  signal score     : unsigned(7 downto 0) := (others => '0');
  signal highscore : unsigned(7 downto 0) := (others => '0');

  signal score_tens : unsigned(3 downto 0) := (others => '0');
  signal score_ones : unsigned(3 downto 0) := (others => '0');
  signal high_tens  : unsigned(3 downto 0) := (others => '0');
  signal high_ones  : unsigned(3 downto 0) := (others => '0');

  signal user_valid : std_logic;
  signal user_sym   : std_logic_vector(1 downto 0);

  signal flash_colon_r    : std_logic := '0';
  signal flash_active     : std_logic := '0';
  signal flash_toggles    : unsigned(3 downto 0) := (others => '0');

  signal lose_cnt  : unsigned(1 downto 0) := (others => '0');

  signal timeout_step : integer range 0 to 31 := 0;

  signal disp_blank : std_logic := '0';

  signal last_btn_r : std_logic_vector(2 downto 0) := "000";

begin

  gkey   <= r_p or g_p or y_p or b_p;
  anykey <= start_p or gkey;

  wdt_exp <= '1' when wdt_cnt >= to_unsigned(WDT_SEC, wdt_cnt'length) else '0';

  user_valid <= gkey;
  user_sym <= "00" when r_p='1' else
              "01" when g_p='1' else
              "10" when y_p='1' else
              "11";

  flash_colon <= flash_colon_r;

  score_out <= std_logic_vector(score);
  high_out  <= std_logic_vector(highscore);
  last_btn  <= last_btn_r;

  ------------------------------------------------------------------------------
  -- state export
  process(st, play_mode)
  begin
    case st is
      when ST_INIT =>
        state_code <= "111";

      when ST_ON =>
        state_code <= "000";

      when ST_PLAY =>
        if play_mode='0' then
          state_code <= "001"; -- showing sequence
        else
          state_code <= "010"; -- player turn
        end if;

      when ST_LOSE =>
        state_code <= "011";

      when ST_CLEAR =>
        state_code <= "100";

      when ST_TIMEOUT =>
        state_code <= "101";

      when ST_SLEEP =>
        state_code <= "110";

      when others =>
        state_code <= "000";
    end case;
  end process;

  ------------------------------------------------------------------------------
  -- 1-second tick
  process(clk)
  begin
    if rising_edge(clk) then
      if rst='1' then
        tick_cnt <= (others => '0');
        tick_1s  <= '0';
      else
        tick_1s <= '0';
        if tick_cnt = to_unsigned(TICK_DIV-1, tick_cnt'length) then
          tick_cnt <= (others => '0');
          tick_1s  <= '1';
        else
          tick_cnt <= tick_cnt + 1;
        end if;
      end if;
    end if;
  end process;

  ------------------------------------------------------------------------------
  -- faster tick for flashing / timeout animation
  process(clk)
  begin
    if rising_edge(clk) then
      if rst='1' then
        flash_tick_cnt <= (others => '0');
        tick_flash <= '0';
      else
        tick_flash <= '0';
        if flash_tick_cnt = to_unsigned(FLASH_DIV-1, flash_tick_cnt'length) then
          flash_tick_cnt <= (others => '0');
          tick_flash <= '1';
        else
          flash_tick_cnt <= flash_tick_cnt + 1;
        end if;
      end if;
    end if;
  end process;

  ------------------------------------------------------------------------------
  -- main FSM
  process(clk)
    variable next_sym : std_logic_vector(1 downto 0);
    variable expected : std_logic_vector(1 downto 0);
  begin
    if rising_edge(clk) then
      if rst='1' then
        st <= ST_INIT;

        wdt_cnt <= (others => '0');
        lfsr <= x"5A";

        seq_len <= 0;
        play_mode <= '0';
        ix_show <= 0;
        show_on <= '0';
        ix_in <= 0;

        score <= (others => '0');
        highscore <= (others => '0');

        flash_colon_r <= '0';
        flash_active <= '0';
        flash_toggles <= (others => '0');

        lose_cnt <= (others => '0');

        timeout_step <= 0;
        disp_blank <= '0';

        last_btn_r <= "000";

      else
        ------------------------------------------------------------------------
        -- LFSR always running
        lfsr <= lfsr(6 downto 0) & (lfsr(7) xor lfsr(5) xor lfsr(4) xor lfsr(3));

        ------------------------------------------------------------------------
        -- Watchdog
        if (st = ST_ON) or (st = ST_PLAY and play_mode='1') then
          if anykey='1' or clear_p='1' then
            wdt_cnt <= (others => '0');
          elsif tick_1s='1' and wdt_cnt < to_unsigned(31, wdt_cnt'length) then
            wdt_cnt <= wdt_cnt + 1;
          end if;
        else
          wdt_cnt <= (others => '0');
        end if;

        ------------------------------------------------------------------------
        -- colon flash engine
        if flash_active='1' then
          if tick_flash='1' then
            if flash_toggles = 0 then
              flash_active  <= '0';
              flash_colon_r <= '0';
            else
              flash_colon_r <= not flash_colon_r;
              flash_toggles <= flash_toggles - 1;
            end if;
          end if;
        else
          flash_colon_r <= '0';
        end if;

        case st is

          when ST_INIT =>
            score <= (others => '0');
            highscore <= (others => '0');
            seq_len <= 0;
            play_mode <= '0';
            ix_show <= 0;
            show_on <= '0';
            ix_in <= 0;

            flash_colon_r <= '0';
            flash_active <= '0';
            flash_toggles <= (others => '0');

            lose_cnt <= (others => '0');

            timeout_step <= 0;
            disp_blank <= '0';

            last_btn_r <= "000";

            st <= ST_ON;

          when ST_ON =>
            disp_blank <= '0';

            if clear_p='1' then
              st <= ST_CLEAR;

            elsif start_p='1' then
              last_btn_r <= "101"; -- start
              score <= (others => '0');

              seq_len <= 1;
              next_sym := lfsr(1 downto 0);
              seq(0) <= next_sym;

              play_mode <= '0';
              ix_show <= 0;
              show_on <= '1';
              ix_in <= 0;

              st <= ST_PLAY;

            elsif wdt_exp='1' then
              timeout_step <= 0;
              disp_blank <= '0';
              st <= ST_TIMEOUT;
            end if;

          when ST_PLAY =>
            disp_blank <= '0';

            if clear_p='1' then
              last_btn_r <= "110"; -- clear
              if score > highscore then
                highscore <= score;

                flash_active <= '1';
                flash_colon_r <= '1';
                flash_toggles <= to_unsigned(5, flash_toggles'length);
              end if;

              st <= ST_CLEAR;
              play_mode <= '0';
              show_on <= '0';

            elsif play_mode='0' then
              -- showing sequence
              if tick_1s='1' then
                show_on <= not show_on;

                if show_on='0' then
                  if ix_show = seq_len-1 then
                    play_mode <= '1';
                    ix_in <= 0;
                    show_on <= '0';

                    flash_active <= '1';
                    flash_colon_r <= '1';
                    flash_toggles <= to_unsigned(1, flash_toggles'length);
                  else
                    ix_show <= ix_show + 1;
                  end if;
                end if;
              end if;

            else
              -- waiting for user input
              if wdt_exp='1' then
                timeout_step <= 0;
                disp_blank <= '0';
                play_mode <= '0';
                show_on <= '0';
                st <= ST_TIMEOUT;

              elsif user_valid='1' then
                if r_p='1' then
                  last_btn_r <= "001"; -- red / left
                elsif g_p='1' then
                  last_btn_r <= "010"; -- green / right
                elsif y_p='1' then
                  last_btn_r <= "011"; -- yellow / up
                elsif b_p='1' then
                  last_btn_r <= "100"; -- blue / down
                end if;

                expected := seq(ix_in);

                if user_sym = expected then
                  if ix_in = seq_len-1 then
                    score <= score + 1;

                    if (score + 1) > highscore then
                      highscore <= score + 1;

                      flash_active <= '1';
                      flash_colon_r <= '1';
                      flash_toggles <= to_unsigned(5, flash_toggles'length);
                    end if;

                    if seq_len < SEQ_MAX then
                      next_sym := lfsr(1 downto 0);
                      seq(seq_len) <= next_sym;
                      seq_len <= seq_len + 1;
                    end if;

                    play_mode <= '0';
                    ix_show <= 0;
                    show_on <= '1';
                    ix_in <= 0;

                  else
                    ix_in <= ix_in + 1;
                  end if;

                else
                  if score > highscore then
                    highscore <= score;

                    flash_active <= '1';
                    flash_colon_r <= '1';
                    flash_toggles <= to_unsigned(5, flash_toggles'length);
                  end if;

                  lose_cnt <= (others => '0');
                  st <= ST_LOSE;
                  play_mode <= '0';
                  show_on <= '0';
                end if;
              end if;
            end if;

          when ST_LOSE =>
            disp_blank <= '0';

            if tick_1s='1' then
              if lose_cnt = "00" then
                lose_cnt <= lose_cnt + 1;
              else
                st <= ST_CLEAR;
                lose_cnt <= (others => '0');
              end if;
            end if;

          when ST_CLEAR =>
            disp_blank <= '0';
            score <= (others => '0');
            seq_len <= 0;
            play_mode <= '0';
            ix_show <= 0;
            show_on <= '0';
            ix_in <= 0;
            st <= ST_ON;

          when ST_TIMEOUT =>
            if tick_flash='1' then
              disp_blank <= not disp_blank;

              if timeout_step < 31 then
                timeout_step <= timeout_step + 1;
              else
                timeout_step <= 0;
                disp_blank <= '0';
                st <= ST_SLEEP;
              end if;
            end if;

          when ST_SLEEP =>
            if tick_flash='1' then
              disp_blank <= not disp_blank;
            end if;

            if anykey='1' then
              disp_blank <= '0';
              st <= ST_ON;
            end if;

        end case;
      end if;
    end if;
  end process;

  ------------------------------------------------------------------------------
  -- LED output
  process(st, play_mode, show_on, seq, ix_show, wdt_cnt, timeout_step)
    variable leds : std_logic_vector(15 downto 0);
    variable sym  : std_logic_vector(1 downto 0);
    variable offn : integer;
  begin
    leds := (others => '0');

    if st = ST_ON then
      leds := (others => '1');

      offn := to_integer(wdt_cnt);
      if offn > 16 then
        offn := 16;
      end if;

      for i in 0 to 15 loop
        if i < offn then
          leds(15 - i) := '0';
        end if;
      end loop;

    elsif (st = ST_PLAY and play_mode='1') then
      leds := (others => '1');

      offn := to_integer(wdt_cnt);
      if offn > 16 then
        offn := 16;
      end if;

      for i in 0 to 15 loop
        if i < offn then
          leds(15 - i) := '0';
        end if;
      end loop;

    elsif st = ST_LOSE then
      leds := (others => '1');

    elsif (st = ST_PLAY and play_mode='0' and show_on='1') then
      sym := seq(ix_show);

      -- LD15..LD12 = RED
      -- LD11..LD8  = GREEN
      -- LD7..LD4   = YELLOW
      -- LD3..LD0   = BLUE
      case sym is
        when "00" =>
          leds(15 downto 12) := (others => '1');
        when "01" =>
          leds(11 downto 8)  := (others => '1');
        when "10" =>
          leds(7 downto 4)   := (others => '1');
        when others =>
          leds(3 downto 0)   := (others => '1');
      end case;

    elsif st = ST_TIMEOUT then
      leds := (others => '0');

      if timeout_step <= 15 then
        leds(timeout_step) := '1';
      else
        leds(31 - timeout_step) := '1';
      end if;

    else
      leds := (others => '0');
    end if;

    led_out <= leds;
  end process;

  ------------------------------------------------------------------------------
  -- Decimal display conversion
  score_tens <= to_unsigned(to_integer(score) / 10, 4);
  score_ones <= to_unsigned(to_integer(score) mod 10, 4);

  high_tens  <= to_unsigned(to_integer(highscore) / 10, 4);
  high_ones  <= to_unsigned(to_integer(highscore) mod 10, 4);

  dig0 <= "1111" when disp_blank='1' else
          "0000" when (rst='1' or st=ST_INIT or st=ST_SLEEP) else
          std_logic_vector(score_ones);

  dig1 <= "1111" when disp_blank='1' else
          "0000" when (rst='1' or st=ST_INIT or st=ST_SLEEP) else
          std_logic_vector(score_tens);

  dig2 <= "1111" when disp_blank='1' else
          "0000" when (rst='1' or st=ST_INIT or st=ST_SLEEP) else
          std_logic_vector(high_ones);

  dig3 <= "1111" when disp_blank='1' else
          "0000" when (rst='1' or st=ST_INIT or st=ST_SLEEP) else
          std_logic_vector(high_tens);

end architecture;
