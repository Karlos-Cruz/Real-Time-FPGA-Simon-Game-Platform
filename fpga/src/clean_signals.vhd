----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 03/05/2026 06:08:54 PM
-- Design Name: 
-- Module Name: clean_signals - Behavioral
-- Project Name: 
-- Target Devices: 
-- Tool Versions: 
-- Description: 
-- 
-- Dependencies: 
-- 
-- Revision:
-- Revision 0.01 - File Created
-- Additional Comments:
-- 
----------------------------------------------------------------------------------


library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;


entity clean_signals is

------------------------
  generic(
    CLK_HZ          : integer := 100_000_000;  -- Basys-3 default clock (100 MHz)
    DEBOUNCE_MS     : integer := 20            -- typical button debounce ~20ms
  );
  ------------------------------

  port(
    clk    : in  std_logic;

    -- raw inputs (from board_io ports)
    btnU   : in  std_logic;
    btnD   : in  std_logic;
    btnL   : in  std_logic;
    btnR   : in  std_logic;
    btnC   : in  std_logic;

    sw     : in  std_logic_vector(15 downto 0);

    -- debounced levels (stable)
    btnU_db : out std_logic;
    btnD_db : out std_logic;
    btnL_db : out std_logic;
    btnR_db : out std_logic;
    btnC_db : out std_logic;

    sw_db   : out std_logic_vector(15 downto 0);

    -- one-clock pulses on press (rising edge of debounced)
    btnU_p : out std_logic;
    btnD_p : out std_logic;
    btnL_p : out std_logic;
    btnR_p : out std_logic;
    btnC_p : out std_logic;

    -- useful pulses for switches too (optional, but handy)
    sw_p   : out std_logic_vector(15 downto 0)
  );
end clean_signals;

architecture Behavioral of clean_signals is

  -- ===== helper: ceil(log2(n)) =====
  function clog2(n : integer) return integer is
    variable r : integer := 0;
    variable v : integer := n - 1;
  begin
    while v > 0 loop
      v := v / 2;
      r := r + 1;
    end loop;
    return r;
  end function;
-----------------
  constant DEBOUNCE_CYCLES : integer := (CLK_HZ / 1000) * DEBOUNCE_MS;
  constant CNT_BITS : integer := clog2(DEBOUNCE_CYCLES);


  -- ===== internal signals =====
  -- synchronizers
  signal btnU_s1, btnU_s2 : std_logic := '0';
  signal btnD_s1, btnD_s2 : std_logic := '0';
  signal btnL_s1, btnL_s2 : std_logic := '0';
  signal btnR_s1, btnR_s2 : std_logic := '0';
  signal btnC_s1, btnC_s2 : std_logic := '0';

  signal sw_s1, sw_s2 : std_logic_vector(15 downto 0) := (others => '0');

  -- debounced states (regs)
  signal btnU_db_r, btnD_db_r, btnL_db_r, btnR_db_r, btnC_db_r : std_logic := '0';
  signal sw_db_r : std_logic_vector(15 downto 0) := (others => '0');

  -- previous debounced states (for edge detect)
  signal btnU_db_prev, btnD_db_prev, btnL_db_prev, btnR_db_prev, btnC_db_prev : std_logic := '0';
  signal sw_db_prev : std_logic_vector(15 downto 0) := (others => '0');

  -- debounce counters
  -----------------
  signal cntU : unsigned(CNT_BITS-1 downto 0) := (others => '0');
  signal cntD : unsigned(CNT_BITS-1 downto 0) := (others => '0');
  signal cntL : unsigned(CNT_BITS-1 downto 0) := (others => '0');
 signal cntR : unsigned(CNT_BITS-1 downto 0) := (others => '0');
 signal cntC : unsigned(CNT_BITS-1 downto 0) := (others => '0');

------------
 type cnt_arr is array (15 downto 0) of unsigned(CNT_BITS-1 downto 0);
  signal cntSW : cnt_arr := (others => (others => '0'));



begin

  -- outputs
  btnU_db <= btnU_db_r;
  btnD_db <= btnD_db_r;
  btnL_db <= btnL_db_r;
  btnR_db <= btnR_db_r;
  btnC_db <= btnC_db_r;

  sw_db   <= sw_db_r;

  -- pulses (1 clock) on rising edge of debounced
  btnU_p <= btnU_db_r and (not btnU_db_prev);
  btnD_p <= btnD_db_r and (not btnD_db_prev);
  btnL_p <= btnL_db_r and (not btnL_db_prev);
  btnR_p <= btnR_db_r and (not btnR_db_prev);
  btnC_p <= btnC_db_r and (not btnC_db_prev);

  gen_sw_p : for i in 0 to 15 generate
    sw_p(i) <= sw_db_r(i) and (not sw_db_prev(i));
  end generate;

  -- ===== main process =====
  process(clk)
  begin
    if rising_edge(clk) then

      -- 1) Synchronizers (2 FF each)
      btnU_s1 <= btnU;  btnU_s2 <= btnU_s1;
      btnD_s1 <= btnD;  btnD_s2 <= btnD_s1;
      btnL_s1 <= btnL;  btnL_s2 <= btnL_s1;
      btnR_s1 <= btnR;  btnR_s2 <= btnR_s1;
      btnC_s1 <= btnC;  btnC_s2 <= btnC_s1;

      sw_s1 <= sw;
      sw_s2 <= sw_s1;

      -- save previous debounced (for edge detect)
      btnU_db_prev <= btnU_db_r;
      btnD_db_prev <= btnD_db_r;
      btnL_db_prev <= btnL_db_r;
      btnR_db_prev <= btnR_db_r;
      btnC_db_prev <= btnC_db_r;

      sw_db_prev <= sw_db_r;

      -- 2) Debounce buttons (counter-based)
      -- BTN U
      if btnU_s2 = btnU_db_r then
        cntU <= (others => '0');
      else
      ------
        if cntU = to_unsigned(DEBOUNCE_CYCLES-1, CNT_BITS) then
        -----
          btnU_db_r <= btnU_s2;
          cntU <= (others => '0');
        else
          cntU <= cntU + 1;
        end if;
      end if;

      -- BTN D
      if btnD_s2 = btnD_db_r then
        cntD <= (others => '0');
      else
        if cntD = to_unsigned(DEBOUNCE_CYCLES-1, CNT_BITS) then
          btnD_db_r <= btnD_s2;
          cntD <= (others => '0');
        else
          cntD <= cntD + 1;
        end if;
      end if;

      -- BTN L
      if btnL_s2 = btnL_db_r then
        cntL <= (others => '0');
      else
      ------------------
        if cntL = to_unsigned(DEBOUNCE_CYCLES-1, CNT_BITS) then
          btnL_db_r <= btnL_s2;
          cntL <= (others => '0');
        else
          cntL <= cntL + 1;
        end if;
      end if;

      -- BTN R
      if btnR_s2 = btnR_db_r then
        cntR <= (others => '0');
      else
      ------------------
        if cntR = to_unsigned(DEBOUNCE_CYCLES-1, CNT_BITS) then
          btnR_db_r <= btnR_s2;
          cntR <= (others => '0');
        else
          cntR <= cntR + 1;
        end if;
      end if;

      -- BTN C (Start)
      if btnC_s2 = btnC_db_r then
        cntC <= (others => '0');
      else
        if cntC = to_unsigned(DEBOUNCE_CYCLES-1, CNT_BITS) then
          btnC_db_r <= btnC_s2;
          cntC <= (others => '0');
        else
          cntC <= cntC + 1;
        end if;
      end if;

      -- 3) Debounce switches too (optional but helps for the CLEAR switch)
      for i in 0 to 15 loop
        if sw_s2(i) = sw_db_r(i) then
          cntSW(i) <= (others => '0');
        else
          if cntSW(i) = to_unsigned(DEBOUNCE_CYCLES-1, CNT_BITS) then
            sw_db_r(i) <= sw_s2(i);
            cntSW(i) <= (others => '0');
          else
            cntSW(i) <= cntSW(i) + 1;
          end if;
        end if;
      end loop;

    end if;
  end process;

end Behavioral;library IEEE;
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

    flash_colon : out std_logic
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

  -- colon flash control
  signal flash_colon_r    : std_logic := '0';
  signal flash_active     : std_logic := '0';
  signal flash_toggles    : unsigned(3 downto 0) := (others => '0');

  signal lose_cnt  : unsigned(1 downto 0) := (others => '0');

  -- timeout animation
  signal timeout_step : integer range 0 to 31 := 0;

  -- display blanking
  signal disp_blank : std_logic := '0';

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

      else
        ------------------------------------------------------------------------
        -- LFSR always running
        lfsr <= lfsr(6 downto 0) & (lfsr(7) xor lfsr(5) xor lfsr(4) xor lfsr(3));

        ------------------------------------------------------------------------
        -- Watchdog:
        -- active in ST_ON and also while waiting for player input in ST_PLAY
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
        -- colon flash engine (finite flashes only)
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

            st <= ST_ON;

          when ST_ON =>
            disp_blank <= '0';

            if clear_p='1' then
              st <= ST_CLEAR;

            elsif start_p='1' then
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
              if score > highscore then
                highscore <= score;

                -- high score: multiple flashes
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

                    -- one flash when it becomes player turn
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
                expected := seq(ix_in);

                if user_sym = expected then
                  if ix_in = seq_len-1 then
                    score <= score + 1;

                    if (score + 1) > highscore then
                      highscore <= score + 1;

                      -- high score: multiple flashes
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
            -- timeout animation: sweep + score flash
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
            -- 00:00 flashing forever until any key / start key
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
      -- watchdog countdown in idle
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
      -- watchdog countdown while waiting for player input
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

      -- 0..15 = left to right
      -- 16..31 = right to left
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

  -- In SLEEP, force 00:00 and flash it forever with disp_blank
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

end architecture;library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity sevenseg_mux4 is
  generic(
    CLK_HZ     : integer := 100000000;
    REFRESH_HZ : integer := 1000
  );
  port(
    clk  : in  std_logic;
    rst  : in  std_logic;

    d3 : in std_logic_vector(3 downto 0);
    d2 : in std_logic_vector(3 downto 0);
    d1 : in std_logic_vector(3 downto 0);
    d0 : in std_logic_vector(3 downto 0);

    flash_colon : in std_logic;

    seg : out std_logic_vector(7 downto 0);
    an  : out std_logic_vector(3 downto 0)
  );
end sevenseg_mux4;

architecture Behavioral of sevenseg_mux4 is

  constant DIV : integer := CLK_HZ / (REFRESH_HZ * 4);

  signal cnt : unsigned(31 downto 0) := (others => '0');
  signal sel : unsigned(1 downto 0)  := (others => '0');

  signal nib  : std_logic_vector(3 downto 0) := (others => '0');
  signal seg7 : std_logic_vector(6 downto 0) := (others => '1');

  signal digit_ix : integer range 0 to 3 := 0;

begin

  ------------------------------------------------------------------------------
  -- Refresh counter
  process(clk)
  begin
    if rising_edge(clk) then
      if rst='1' then
        cnt <= (others => '0');
        sel <= (others => '0');
      else
        if cnt = to_unsigned(DIV-1, cnt'length) then
          cnt <= (others => '0');
          sel <= sel + 1;
        else
          cnt <= cnt + 1;
        end if;
      end if;
    end if;
  end process;

  ------------------------------------------------------------------------------
  -- Digit select
  process(sel, d0, d1, d2, d3)
  begin
    case sel is
      when "00" =>
        nib <= d0;
        an <= "1110";
        digit_ix <= 0;

      when "01" =>
        nib <= d1;
        an <= "1101";
        digit_ix <= 1;

      when "10" =>
        nib <= d2;
        an <= "1011";
        digit_ix <= 2;

      when others =>
        nib <= d3;
        an <= "0111";
        digit_ix <= 3;
    end case;
  end process;

  ------------------------------------------------------------------------------
  -- Hex to 7-segment decode
  process(nib)
  begin
    case nib is
      when "0000" => seg7 <= "1000000"; -- 0
      when "0001" => seg7 <= "1111001"; -- 1
      when "0010" => seg7 <= "0100100"; -- 2
      when "0011" => seg7 <= "0110000"; -- 3
      when "0100" => seg7 <= "0011001"; -- 4
      when "0101" => seg7 <= "0010010"; -- 5
      when "0110" => seg7 <= "0000010"; -- 6
      when "0111" => seg7 <= "1111000"; -- 7
      when "1000" => seg7 <= "0000000"; -- 8
      when "1001" => seg7 <= "0010000"; -- 9
      when others => seg7 <= "1111111"; -- blank
    end case;
  end process;

  ------------------------------------------------------------------------------
  -- Decimal point used as simulated colon
  process(seg7, digit_ix, flash_colon)
  begin
    if flash_colon='1' then
      if digit_ix=1 or digit_ix=2 then
        seg <= '0' & seg7;  -- dp ON on middle digits
      else
        seg <= '1' & seg7;  -- dp OFF
      end if;
    else
      seg <= '1' & seg7;    -- dp OFF
    end if;
  end process;

end Behavioral;
