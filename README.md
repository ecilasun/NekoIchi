# NekoIchi
A simple risc-v CPU with a custom GPU running on an Arty A7-100T FPGA board

## NOTES:

NekoIchi is a system-on-chip which contains:
- A risc-v (rv32imf) CPU
- 256MBytes of DDR3 RAM
- 128Kbytes of GRAM (graphics memory)
- 64KBytes of ARAM (audio memory), doubles as BOOT ROM
- 128bit, 256 line cache (4K page size) on the DDR3 bus (no separate I$ and D$ at this point)
- DVI interface via PMOD ports A&B
- SDCard interface via PMOD port C
- Stereo audio output via PMOD port D
- Two 256x192x8bpp (indexed color) internal offscreen VRAM regions for graphics scanout
- A custom GPU that can DMA betwen GRAM and VRAM, modify palette colors etc
- A custom APU that can DMA between ARAM and sound output device, control volume, apply effects or synthesize sound (WiP)
- Hardware interrupts (external/timer/breakpoint) and exceptions (illegal instruction)
- UART @115200 bauds

## The CPU
NekoIchi implements machine interrupts via MSI/MTI/MEI interrupt support (machine interrupts for software/timer/external).

For the timer interrupts, a custom 64 bit CSR register on addresses 0x800-0x801 is implemented, to be used as the 'timecmp' register. Original RISC-V documentation uses a memory mapped register scheme but that doesn't reflect well with NekoIchi internals, therefore a custom CSR was used.

The ROM images, sample code and a port of DOOM that can run on this CPU can be found here: https://github.com/ecilasun/riscvtool

The current CPU version also supports illegal instruction exceptions for code running outside an interrupt handler (i.e. most user code)

The default ROM image does not currently support any of these features, and will only access the SDCard, read switches and start ELF binaries found on the card, as well as listen to UART for any incoming executables.

## The GPU
The custom GPU has the following features:
- GRAM write: Can output a DWORD to any GRAM address location
- DMA: GPU can drive the DMA to copy blocks of GRAM to VRAM
- VRAM clear: Fast VRAM clear, similar to a DMA op with source coming from a single register
- VRAM page select: GPU can select which VRAM page is the current scanout buffer and which one gets to be the DMA target

The CPU talks to the GPU using a FIFO to push 32bit commands, using a memory mapped device address.

Currently the GPU will not stall the CPU unless the FIFO (1024 DWORD entries) is full. Submitting more commands than 1024 for each 'frame' will put the GPU and CPU into lockstep mode. If so desired, the GRAM write mechanism can be used to signal the CPU that the GPU has reached a point where it can accept more commands, therefore removing the need to lock-step the CPU.

As of this time, there is no rasterizer unit. This will be achieved by a different means in the near future.

## The Graphics DMA unit
Currently the DMA unit that lives inside the GPU is controlled by writing a command to the GPU FIFO, which supplies it with a source and target address register pair and a 'mask' flag. The mask flag can be used to do one of the following:
- Unmasked writes: writes series of DWORDs from GRAM to VRAM using GRAM's second port to read, meaning CPU can still read/write to GRAM
- Zero-masked writes: same as unmasked, excepy for every zero byte encountered, the DWORD write is byte masked to skip the zeros)

NOTE: The GPU has no DMA access to DDR3 RAM as of this moment

## Where are the sample codes & tools?

The built-in ROM image listens to the UART port by default, with 115200baud/1s/np for binary uploads. It will also list any ELF files on the storage medium and let the user select/run one using the leftmost three push buttons on the Arty A7 board.

This, in combination with the https://github.com/ecilasun/riscvtool should let you experiment with, and upload your own binaries to the SoC.

Please use 'make' command in the ROMs directory to generate a new ROMnekoichi.coe, which you can then paste over the contents of the BIOS.coe file in the source directory of this project.

To upload any sample code to the SoC, use a command as in the following example after running 'make' in the samples directory:
./build/release/riscvtool samples/modplayer.elf -sendelf 0x10000 /dev/ttyUSB1

For regular ELF binaries, the load address 0x10000 is the default unless you use a custom linker script. In that case you'll need to make sure the address range 0x20000000-0x2000FFFF is untouched (the loader lives in the ARAM and runs from there, so try not to overwrite it before your app loads) After an ELF loads and starts up, it's free to use the ARAM region for any purpose, including executing code from it (the instruction reads, data loads and writes to this region will be uncached). The exact same is valid for the GRAM region also (0x10000000-0x1001FFFF)

After an executable loads and main() starts executing, it's OK to use the aforementioned loader address range to store data.

## External IPs:

RISC-V processor implemented using RISC-V ISA documentations found at https://riscv.org/
RS232 serial communication/baud generator code used from https://www.fpga4fun.com/SerialInterface.html
SPI interface used from https://github.com/jakubcabal/spi-fpga

## TO DO:
- Split instruction cache from data cache if possible
- Implement pipelining
- Add a second CPU core
- Implement commands for the APU (doesn't do much now except DMA, make it also auto-stream audio to the sound output, DSP FX etc)
- Tackle more features for the GPU such as rasterization with texturing / alpha blending and maybe shaders?

## PARTIALLY DONE:
- Implement GDB debugger stub (hardware support exists and should be adequate for a UART debug interface)

## DONE
- Make the CPU faster -> Added a cache in front of the DDR3 to make code execute much faster (x6.3 times)
- Run DOOM at interactive rates
- Implement a PC side keyboard/mouse interface that can send data through the UART -> wrote a keyserver app (in riscvtool)
- Allow for coordinates outside the view so that the GPU can clip (currently, CPU must clip before sending otherwise triangles will get deformed)
- Add button input support
- Add back support for the DDR3 SDRAM or the HyperRAM module, whichever doesn't break the design. Otherwise expand the BRAM, or move to a board with an SRAM + simple SDRAM on board (DDR3 was added)
- Add audio support

## DEPRECATED
- Triangle rasterizer
