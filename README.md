# BMX

BMX is a bare-metal Commodore emulator derived from BMC64 for the Raspberry 
PI 4/5 family. 
The current focus of this project is to provide a smooth user experience on the 
Raspberry Pi 400 and 500. It should kinda feel like a modern breadbin. Support 
for Raspberry Pi <= 3 is removed and left to the original BMC64 project.

## Current Status

Development is mainly carried out on a PI 400 with a German keyboard layout
followed by a PI 500 with German keyboard layout. "Positional DE" is the default
layout on a freshly created sdcard. I expect that these two machines will run 
out of the box. Besides "Positional DE", I integrated "Positional US" in the BMX
menu. Because I dont have a US machine to test it, I consider "Positional US" as
work in progress. Other keyboard layouts are currently not supported. I removed
the "Symbolic" option in the menu, because in my opinion on a bare metal machine
it doesnt make sense.

## Building

Build, staging, installation and SD-card creation are documented in
[`BUILDING.md`](BUILDING.md).

## Features over time

Changes are documented in [`CHANGELOG.md`](CHANGELOG.md).
