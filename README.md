# artyz720riscv

A simple risc-v CPU (rv32im) running on an Arty Z7-20 FPGA board.

Utilizes https://github.com/bpeptena/graphics_fpga for the DVI output.

Development depot for a simple GPU and more risc-v features.

# Notes

The current state of this core, still under development, is as follows:

- Uses hardware multipliers for MUL instructions (6 clocks to retire)
- Uses restoring divide algorithm for DIV/REM instructions (36 clocks to retire)
- Implements the rv32im spec minus EBREAK/SYS calls (TBD)
- Drives DVI via the IP mentioned in the title section
- Expands SYSRAM to 128Kbytes vs 64Kbytes
- Doesn't contain any SDCard or UART
  - The pass-through via Zynq processor is not done yet
  - Have to use block designer for this, it's anything but portable
- Currently code is hardcoded in SYSRAM at boot time
  - Once the UART / SDCard is wired it'll be possible to load code again
