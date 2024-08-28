# nwdrone

## Host Prerequisites

- [Zig](https://ziglang.org/)
- [Yarn](https://yarnpkg.com/)
  - [Node](https://nodejs.org/en)

## Target Prerequisites

- [pigpio](https://abyz.me.uk/rpi/pigpio/download.html)
  - Installed by default on all modern versions of Raspberry Pi OS
- [libpixyusb](https://docs.pixycam.com/wiki/doku.php?id=wiki:v1:building_the_libpixyusb_example_on_linux)
  - libusb (`apt install libusb-1.0-0-dev`)
  - boost (`apt install libboost-all-dev`)

## Build

- `zig build`
  - `zig build -h` shows all possible options (important being `-Dplatform`)
  - What you probably want is `zig build -Dplatform=rpi0 -Dstrip=true --release=any --summary all`

## Extras

- `zig build test` to run all unit tests
- `zig build docs` to generate documentation (in `zig-out/docs`)

## Project Structure

- `src`
  - `control`
    - "High"-level abstraction utilizing `device`s, such as stability, control, navigation, and others
  - `device`
    - Device-level abstraction, for example, specific hardware device communication (MPU6050, Pixy, etc.)
  - `hw`
    - Hardware/low-level operations, for example, specific hardware interfaces (PWM, I2C, etc.)
  - `lib`
    - Zig-based libraries, for example, OS interaction, math helpers, etc.
  - `remote`
    - Utilities for remote operation of the drone, such as the webserver, communication handling, etc.
  - `drone.zig`
    - Global drone control operations, mostly safety
  - `main.zig`
    - Program entrypoint, where all hardware is initialized and the main loop function exists
  - `tests.zig`
    - Root testing point to import all files containing tests
- `lib`
  - External or non-Zig based libraries required for project functionality
