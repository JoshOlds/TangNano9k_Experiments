# TangNano9k FPGA Experiments

This repository contains a collection of Verilog modules and experiments developed for the TangNano9k FPGA board, roughly following the [Lushay Labs tutorial series](https://learn.lushaylabs.com/tang-nano-series/). Each module demonstrates different FPGA concepts and capabilities using open-source tools.

## Project Structure

The repository is organized into separate folders, each containing a standalone FPGA module or buildable experiment. Each folder represents a different concept or functionality that can be built and deployed to the TangNano9k board.

## Prerequisites

To build and run these experiments, you'll need:

- [TangNano9k FPGA Board](https://api.lushaylabs.com/tang-nano-9k)
- [OSS-CAD-Suite](https://github.com/YosysHQ/oss-cad-suite-build) - A collection of open source tools for FPGA development
  - Includes Yosys, nextpnr, and other essential tools
- USB-C cable for programming the board

## Building Projects

See the [Lushay Labs guide](https://learn.lushaylabs.com/getting-setup-with-the-tang-nano-9k/#the-open-source-toolchain) for instructions on how to use the VSCode plugin to build and flash these projects!

Once setup, you should 'Open Folder' in VSCode to open just the folder for the experiment you would like to build (ie. `./2-UART/`). If you try to build from the root directory, you will have module conflicts.

## Project Contents

- `1-GettingStarted/` - Initial setup and basic counter implementation
- `2-UART` - A full-duplex UART module capable of 1M Baud, plus associated Python test scripts.

