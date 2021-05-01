# NekoIchi
A simple risc-v CPU with a custom GPU running on an Arty A7-100T FPGA board

## NOTES:

NekoIchi is a system-on-chip which contains:
- A risc-v (rv32imf) CPU
- 128Kbytes of SYSRAM for programs
- 256x192x8bpp VRAM for graphics
- A custom GPU
- UART @115200 bauds

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

## Where are the sample codes & tools?

The built-in ROM image listens to the UART port by default, with 115200baud/1s/np

This, in combination with the https://github.com/ecilasun/riscvtool should let you experiment and upload your own binaries to the SoC.

Please use ./build.sh to generate a new ROM_nekoichi.coe alongside samples; which you can then paste over the contents of the BIOS.coe file. I haven't spent time to clean up the uploader and samples yet, updates will move the tools possibly into one git repo in near future.

## External IPs:

RS232 serial communication/baud generator code used from https://www.fpga4fun.com/SerialInterface.html

## TODO:

- Support gradient/barycentric generation for triangle primitives
- Support fixed point (8.4? 8.8?) for primitive rasterizer
- Allow for coordinates outside the view so that the GPU can clip (currently, CPU must clip before sending otherwise triangles will get deformed)
- Possibly port back to Spartan 7 instead of using a Zynq-7000 board (only chosen because of larger logic count and larger internal BRAM)
- Tackle more features for the GPU such as texturing / alpha blending (stretch goal)
- Add audio support
- Add button input support
- Connect more board IOs to memory mapped addresses (buttons/LEDs/GPIO/Ethernet)
- Start using the HyperRAM module for more storage (because DDR3 uses way too many LUTs/FFs)
