# TangNano9k FPGA Experiments

This repository contains a collection of Verilog modules and experiments developed for the TangNano9k FPGA board, following the Lushay Labs tutorial series. Each module demonstrates different FPGA concepts and capabilities using open-source tools.

## Project Structure

The repository is organized into separate folders, each containing a standalone FPGA module or experiment. Each folder represents a different concept or functionality that can be built and deployed to the TangNano9k board.

## Prerequisites

To build and run these experiments, you'll need:

- [TangNano9k FPGA Board](https://api.lushaylabs.com/tang-nano-9k)
- [OSS-CAD-Suite](https://github.com/YosysHQ/oss-cad-suite-build) - A collection of open source tools for FPGA development
  - Includes Yosys, nextpnr, and other essential tools
- USB-C cable for programming the board

## Building Projects

Each project folder contains Verilog source files that can be built using the OSS-CAD-Suite tools. The general build process involves:

1. Synthesis using Yosys
2. Place and Route using nextpnr-gowin
3. Bitstream generation using gowin_pack

See the Lushay Labs guide for instructions on how to use the VSCode plugin to build and flash these projects!

## Project Contents

- `1-GettingStarted/` - Initial setup and basic counter implementation
- `2-UART` - A full-duplex UART module capable of 1M Baud, plus associated Python test scripts.

