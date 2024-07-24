# nwdrone

## Host Prerequisites

- Zig *(shocker)*

## Target Prerequisites

- [libpixyusb](https://docs.pixycam.com/wiki/doku.php?id=wiki:v1:building_the_libpixyusb_example_on_linux)
  - libusb (`apt install libusb-1.0-0-dev`)
  - boost (`apt install libboost-all-dev`)

## Build

- `zig build`
  - `zig build -h` shows all possible options (important being `-Dplatform`)

## Extras

- `zig build test` to run all unit tests
- `zig build docs` to generate documentation (in `zig-out/docs`)

## Project Structure

- `src`
  - `device`
    - Device-level abstraction, for example, specific hardware device communication (MPU6050, Pixy, etc.)
  - `hw`
    - Hardware/low-level operations, for example, specific hardware interfaces (PWM, I2C, etc.)
  - `lib`
    - Zig-based libraries, mostly for OS interaction
  - `drone.zig`
    - Global drone control operations, mostly safety
  - `main.zig`
    - Program entrypoint, where all hardware is initialized and the main loop function exists
  - `tests.zig`
    - Root testing point to import all files containing tests
- `lib`
  - External or non-Zig based libraries required for project functionality
