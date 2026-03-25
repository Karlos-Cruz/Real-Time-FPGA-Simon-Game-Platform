----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 03/10/2026 09:02:04 PM
-- Design Name: 
-- Module Name: uart_rx - Behavioral
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

entity uart_rx is
  generic(
    CLKS_PER_BIT : integer := 868  -- 100 MHz / 115200
  );
  port(
    clk       : in  std_logic;
    rst       : in  std_logic;
    rx        : in  std_logic;
    data_out  : out std_logic_vector(7 downto 0);
    data_valid: out std_logic
  );
end entity;

architecture Behavioral of uart_rx is
  type state_t is (IDLE, START_BIT, DATA_BITS, STOP_BIT);
  signal st : state_t := IDLE;

  signal clk_cnt    : integer range 0 to CLKS_PER_BIT-1 := 0;
  signal bit_idx    : integer range 0 to 7 := 0;
  signal rx_shift   : std_logic_vector(7 downto 0) := (others => '0');
  signal data_r     : std_logic_vector(7 downto 0) := (others => '0');
  signal valid_r    : std_logic := '0';
begin

  data_out   <= data_r;
  data_valid <= valid_r;

  process(clk)
  begin
    if rising_edge(clk) then
      if rst='1' then
        st      <= IDLE;
        clk_cnt <= 0;
        bit_idx <= 0;
        rx_shift <= (others => '0');
        data_r  <= (others => '0');
        valid_r <= '0';

      else
        valid_r <= '0';

        case st is
          when IDLE =>
            clk_cnt <= 0;
            bit_idx <= 0;

            -- detect start bit
            if rx='0' then
              st <= START_BIT;
            end if;

          when START_BIT =>
            -- sample in the middle of start bit
            if clk_cnt = (CLKS_PER_BIT/2) then
              if rx='0' then
                clk_cnt <= 0;
                st <= DATA_BITS;
              else
                st <= IDLE;
              end if;
            else
              clk_cnt <= clk_cnt + 1;
            end if;

          when DATA_BITS =>
            if clk_cnt = CLKS_PER_BIT-1 then
              clk_cnt <= 0;
              rx_shift(bit_idx) <= rx;

              if bit_idx = 7 then
                bit_idx <= 0;
                st <= STOP_BIT;
              else
                bit_idx <= bit_idx + 1;
              end if;
            else
              clk_cnt <= clk_cnt + 1;
            end if;

          when STOP_BIT =>
            if clk_cnt = CLKS_PER_BIT-1 then
              clk_cnt <= 0;
              data_r <= rx_shift;
              valid_r <= '1';
              st <= IDLE;
            else
              clk_cnt <= clk_cnt + 1;
            end if;
        end case;
      end if;
    end if;
  end process;

end architecture;

