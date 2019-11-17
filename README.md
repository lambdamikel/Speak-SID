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

## Status LEDs 

![PCB](images/leds.jpg)

POWER 
Obvious

READY 
: Lights up when Speak&SID is waiting for / expecting input from port `&FBEE`. 

SPJRDY
: Lights up when SpeakJet is ready. See [SpeakJet manual](manuals/speakjet-usermanual.pdf) for details. 

SPJSPK 
: Lights up when SpeakJet is speaking. See [SpeakJet manual](manuals/speakjet-usermanual.pdf) for details. 

SPBUF 
: Lights up when SpeakJet's input buffer is half full. See [SpeakJet manual](manuals/speakjet-usermanual.pdf) for details. 

SIDON
: Lights up then Speak&SID is in SID mode.

OUT1, OUT2, OUT3, OUT4 
: Status of Speak&SID's general purpose output (GPO) pins. 

## DIP Switches


## Firmware Documentation 

The best documentation is the [ATMega source code itself.](src/atmega8535/speaksid/speaksid.c) 

After powerup or reset, Speak&SID is in 


