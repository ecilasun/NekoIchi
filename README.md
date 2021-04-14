# NekoIchi
A simple risc-v CPU  running on an Arty Z7-20 FPGA board

Please note that the riscvtool repo is aimed at my other risc-v CPU with UART, so I haven't taken time to add support for this non-UART machine.
I'm working on adding UART support by enabling the PL (the ARM cores) which apparently have the only connection to the on-board USB-UART bridge, and have to act as bypass for the FPGA)

Once that's working, it should be possible to use riscvtool to upload binaries and share the BIOS between the two risc-v SoC versions.
