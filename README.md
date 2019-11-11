# Speak & SID

A Speech Synthesizer and SID Soundcard for the Amstrad CPC

## Some Pictures 

![PCB 1](images/speaksid-pcb-1-a.JPG)  
![PCB 2](images/speaksid-pcb-1-b.JPG)  
![Breadboard 1](images/breadboard-1.JPG)
![Breadboard 2](images/breadboard-2.JPG)
![PCB](images/speakjet-pcb.jpg)

## Some YouTube Videos 

- [Second SID Player Demo - Line Out Recording and LED Lightshow](https://youtu.be/FXDS3pdf-w8) 
- [First PCB Version \& SID Player Demo](https://youtu.be/xVo5ycUuM5Q)
- [Breadboard Prototype - First SID BASIC Test](https://youtu.be/dJlccupSALY) 
- [Breadboard Prototype - Amstrad SSA-1 Emulation Test](https://youtu.be/zLsgOHT1fmA)

## License

GPL 3 

## Requirements 

This project was developed using
[WinAVR.](http://winavr.sourceforge.net/) In addition, the [AVR
Programming Libraries](https://github.com/hexagon5un/AVR-Programming)
from Elliot Williams' book "Make: AVR Programming" are being used. A
copy of the library is also included in the [src folder of this
project.](src/atmega8535/)

## Building 

Use `make`. The provided `Makefile` template is again from Elliot Williams' book. See above. 

## Acknowledgements

- Elliot Wiliams for his book "Make: AVR Programming" and [corresponding sources /AVR Programming Libraries.](https://github.com/hexagon5un/AVR-Programming) 

- [DaDMaN from the CPC Wiki Forum](http://www.cpcwiki.eu/forum/amstrad-cpc-hardware/new-amstrad-cpc-sound-board-(aka-sonique-sound-board)-sid-part-(wip)/) for providing the Z80 source code of his branch of Simon Owen's Z80 SID Player.

- [Simon Owen](https://simonowen.com/sam/sidplay/) for the [Z80 SID Player.](https://github.com/simonowen/sidplay)

## Firmware Update / Flash 

The firmware can be updated without having to remove the ATMega uC from the socket. The SPI pins / header of Speak&SID can be used for updating the firmware. 

I am using the USBtinyISP programmer. Just connect the progammer's SPI pins with the corresponding Speak&SID SPI pins, using DuPont cables: MOSI <-> MOSI, MISO <-> MISO, SCK <-> SCK, and GND <-> GND. Note that VCC might not be required. If your connecting to VCC, make sure to FIRST power on the CPC and Speak&SID BEFORE plugging in the USB cable into your computer, otherwise the USB port is powering the CPC. VCC should not be required for programming. With the proper connections in place and the CPC and Speak&SID up and running, use the provided `make flash` (entered into a `command.com` shell) from the `Makefile` **whilst holding the Speak&SID Reset button pushed down until the programming process has finished.** The firmware HEX file is small, so it only takes about 20 seconds to programm the firmware. 

## Firmware Documentation 

Soon. 

