# MyOS

`MyOS` is a small, experimental operating system project aimed at exploring OS development from scratch. Written in a mix of `Assembly` and `C Language`, it currently boots from a FAT12-formatted floppy disk and is capable of loading and executing a simple kernel. This project demonstrates low-level system programming techniques and provides a foundation for learning OS internals.

## Features

- Custom bootloader in Assembly
- Kernel loading from FAT12 file system
- Basic I/O via BIOS interrupts
- Disk reading and FAT12 parsing
- Built using Assembly and C language for performance and safety

## Getting Started

These instructions will help you set up the build environment, compile the code, and run MyOS on an emulator like QEMU.

### Prerequisites

- **NASM** (for assembling the bootloader)
  - On Debian: `sudo apt install nasm`
- **QEMU** (for testing the OS in an emulator)
  - On Debian: `sudo apt install qemu-system`

### Repository Structure

- **src/**: Contains all source code, organized into `bootloader` (Assembly) and `kernel` (C).
- **Makefile**: Automates the build process, assembling the bootloader, and compiling the C kernel.
- **run.sh**: A script to launch MyOS in QEMU.
- **test.img**: Floppy disk image used for testing.


