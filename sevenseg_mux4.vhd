library IEEE;
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