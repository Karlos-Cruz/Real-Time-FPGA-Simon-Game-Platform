----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 03/10/2026 05:52:22 PM
-- Design Name: 
-- Module Name: uart_tx - Behavioral
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

entity uart_tx is
  generic(
    CLKS_PER_BIT : integer := 868  -- 100 MHz / 115200 ? 868
  );
  port(
    clk     : in  std_logic;
    rst     : in  std_logic;
    start   : in  std_logic;
    data_in : in  std_logic_vector(7 downto 0);
    tx      : out std_logic;
    busy    : out std_logic
  );
end entity;

architecture Behavioral of uart_tx is
  type state_t is (IDLE, START_BIT, DATA_BITS, STOP_BIT);
  signal st : state_t := IDLE;

  signal clk_cnt  : integer range 0 to CLKS_PER_BIT-1 := 0;
  signal bit_idx  : integer range 0 to 7 := 0;
  signal shreg    : std_logic_vector(7 downto 0) := (others => '0');

  signal tx_r   : std_logic := '1';
  signal busy_r : std_logic := '0';
begin

  tx   <= tx_r;
  busy <= busy_r;

  process(clk)
  begin
    if rising_edge(clk) then
      if rst='1' then
        st      <= IDLE;
        clk_cnt <= 0;
        bit_idx <= 0;
        shreg   <= (others => '0');
        tx_r    <= '1';
        busy_r  <= '0';

      else
        case st is
          when IDLE =>
            tx_r   <= '1';
            busy_r <= '0';
            clk_cnt <= 0;
            bit_idx <= 0;

            if start='1' then
              shreg   <= data_in;
              busy_r  <= '1';
              st      <= START_BIT;
            end if;

          when START_BIT =>
            tx_r <= '0';
            if clk_cnt = CLKS_PER_BIT-1 then
              clk_cnt <= 0;
              st <= DATA_BITS;
            else
              clk_cnt <= clk_cnt + 1;
            end if;

          when DATA_BITS =>
            tx_r <= shreg(bit_idx);
            if clk_cnt = CLKS_PER_BIT-1 then
              clk_cnt <= 0;
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
            tx_r <= '1';
            if clk_cnt = CLKS_PER_BIT-1 then
              clk_cnt <= 0;
              busy_r <= '0';
              st <= IDLE;
            else
              clk_cnt <= clk_cnt + 1;
            end if;
        end case;
      end if;
    end if;
  end process;

end architecture;
