# NekoIchi
A simple risc-v CPU  running on an Arty Z7-20 FPGA board

## NOTES:

NekoIchi contains a riscv (rv32imf) CPU with 128Kbytes of SYSRAM for programs, and a 256x192x8bpp VRAM for graphics. It contains a custom GPU that can draw single pixels, DMA long blocks from SYSRAM to VRAM, draw solid filled triangles, and fast-clear the VRAM.

The CPU talks to the GPU using a FIFO to push 32bit commands. Currently the GPU will not stall the CPU unless the FIFO (1024 DWORD entries) is full. Doing a lot of single pixel writes would fill it up, so I'm planning to remove single pixel writes in the future.

The rasterizer currently writes to VRAM directly, but for convenience in the future, it will write to SYSRAM (in parallel to the CPU writes using a second port) given a base address and a clip window size (in tile dimensions)

The rasterizer tile size is 4x1 pixels currently, and the algorthm used for 'inside' test is based around ideas from Intel's Larrabee architecture, with some custom additions to cope with integer values.

P.S. I'm currently baking a fixed ROM image using my riscvtool (https://github.com/ecilasun/riscvtool) so if you wish to make changes to the built-in BIOS please sync to it and use ./build.sh to generate a new ROM_nekoichi.coe which you can then paste over the contents of the BIOS.coe file.

## External IPs:

Utilizes https://github.com/bpeptena/graphics_fpga for the DVI output.

## TODO:

- Support gradient/barycentric generation for triangle primitives
- Support fixed point (8.4? 8.8?) for primitive rasterizer
- Allow for coordinates outside the view so that the GPU can clip (currently, CPU must clip before sending otherwise triangles will get deformed)
- Possibly port back to Spartan 7 instead of using a Zynq-7000 board (only chosen because of larger logic count and larger internal BRAM)
- Tackle more features for the GPU such as texturing / alpha blending (stretch goal)
- Add audio support
- Add button input support
