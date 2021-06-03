# NekoIchi
A simple risc-v CPU with a custom GPU running on an Arty A7-100T FPGA board

## NOTES:

NekoIchi is a system-on-chip which contains:
- A risc-v (rv32imf) CPU
- 256Kbytes of SYSRAM for programs
- DVI interface via PMOD on port A&B
- SDCard interface via PMOD on port C
- 256x192x8bpp VRAM for graphics
- A custom GPU
- Hardware interrupts (external/timer/breakpoint)
- UART @115200 bauds

## The CPU
NekoIchi implements MSI/MTI/MEI interrupt support (machine interrupts for software/timer/external).

For the timer interrupts, a custom 64 bit CSR register on addresses 0x800-0x801 is implemented, to be used as the 'timecmp' register. Original RISC-V documentation uses a memory mapped register scheme but that doesn't reflect well with NekoIchi internals, therefore a custom CSR was used.

Current built-in ROM image uses external interrupt enable and an interrupt handler to implement an UART driven console, which doesn't have to poll data arrival in software, and a demo 1 second timer that fires right after the ROM starts. The source can be found under test/ROM_Nekoichi.cpp file in the project https://github.com/ecilasun/riscvtool

## The GPU
The custom GPU has the following features:
- Pixel write: Can draw single bytes at any VRAM position (to be deprecated)
- DMA: GPU can drive the DMA to copy blocks of SYSRAM to VRAM
- Rasterizer: currently draws solid filled triangles
- VRAM clear: Fast VRAM clear, similar to a DMA op with source coming from a single register

The CPU talks to the GPU using a FIFO to push 32bit commands, using a memory mapped device address (0x80000000).

Currently the GPU will not stall the CPU unless the FIFO (1024 DWORD entries) is full. Submitting more commands than 1024 for each 'frame' will put the GPU and CPU into lockstep mode, I'm planning to expand the FIFO or use a different means to feed the GPU in the future.

The rasterizer currently writes to VRAM directly, but for convenience in the future, it will write to SYSRAM instead (in parallel to the CPU writes using a second port) given a base address and a clip window size (in tile dimensions) This should allow for better, hardware accessible doublebuffering of draw targets.

The rasterizer tile size is 4x1 pixels currently, and the algorthm used for 'inside' test is based around ideas from Intel's Larrabee architecture, with some custom additions to cope with integer values. There is an initial coarse tile check for 4x4 pixel regions before the 4x1 rasterizer's generated mask is written to VRAM.

## The Graphics DMA unit
Currently the DMA lives inside the GPU and is controlled by writing a command to the GPU FIFO. Some of the features of the DMA unit are listed below
- Unmasked writes: writes series of DWORDs from SYSRAM to VRAM using SYSRAM's second port to read, meaning CPU can still read/write to SYSRAM
- Zero-masked writes: same as unmasked, excepy for every zero byte encountered, the DWORD write is byte masked to skip the zeros)

## Rasterizer
The rasterizer generates solid-filled triangles, using 16 bit signed values placed in GPU registers as X-Y pairs. Currently this requires 3 registers, and the draw command takes an 8bit color alongside register indices to kick the rasterization.
Currently the reasterizer won't use bidirectional sweep algorithm for optimal fill speed, or do any parallel work, until the GPU receives its parallel workers.

## Where are the sample codes & tools?

The built-in ROM image listens to the UART port by default, with 115200baud/1s/np

This, in combination with the https://github.com/ecilasun/riscvtool should let you experiment and upload your own binaries to the SoC.

Please use ./build.sh to generate a new ROM_nekoichi.coe alongside samples; which you can then paste over the contents of the BIOS.coe file. I haven't spent time to clean up the uploader and samples yet, updates will move the tools possibly into one git repo in near future.

To upload any sample code to the SoC, use a command as in the following example after running build.sh:
./build/release/riscvtool gpupipetest.elf -sendelf 0x10000

For regular ELF binaries, the address 0x10000 is the default unless you use a custom linker script in which case you'll need to make sure the address range 0x00000000-0x00002000 is untouched (the loader lives in this region)
After an executable loads and main() starts executing, it's OK to use the aforementioned loader address range to store data.

## External IPs:

RS232 serial communication/baud generator code used from https://www.fpga4fun.com/SerialInterface.html
SPI interface used from https://github.com/jakubcabal/spi-fpga

## TODO:

- Implement GDB debugger stub (hardware support exists and should be adequate for a UART debug interface)
- Support gradient/barycentric generation for triangle primitives on the GPU
- Support fixed point (8.4? 8.8?) for primitive rasterizer on the GPU
- Allow for coordinates outside the view so that the GPU can clip (currently, CPU must clip before sending otherwise triangles will get deformed)
- Add audio support
- Add button input support
- Tackle more features for the GPU such as texturing / alpha blending (stretch goal)
- Add back support for the DDR3 SDRAM or the HyperRAM module, whichever doesn't break the design. Otherwise expand the BRAM, or move to a board with an SRAM + simple SDRAM on board
