A few MAXAM demo programs that require USIfAC I for MIDI INPUT.
Connect the MIDI BREAKOUT BOARD to the USIfAC I UART headers. These
programs have not been tested with USIfAC II - I don't own one!

NOTE that Speak&SID must be *modded* so that IOREQ READ requests to
Speak&SID can be disabled - it's port range overlaps with USIfAC
otherwise. 

For *unmodded* Speak&SID MIDI INPUT WITHOUT USIfAC, you can use the
programs in the speakandsid/ directory. For these, no USIfAC is
required, and you can directly connect the MIDI BREAKOUT BOARD to the
Speak&SID UART headers. Please note that it is not possible to use the
Speak&SID UART for MIDI INPUT and control the SpeakJet at the same
time - the SpeakJet also requires the UART, and the MIDI BAUD rate
setting is incompatible with the SpeakJet BAUD rate setting. Hence,
the only option for a MIDI-playable SpeakJet chip with Speak&SID is
the extra USIfAC for MIDI UART INPUT, and to mod the Speak&SID, as
explained.

So these don't work with a standard, unmodded Speak&SID, and require a
USIfAC; again, if you don't want to play the SpeakJet chip over MIDI,
you can just use the SYNTH.BAS program in the ../speakandsid/
directory of this repository.

So, these are the programs on "newusi.dsk": 

- JETSYNT.BAS: play the SpeakJet chip over USIfAC MIDI IN. 

- JETAYSYNT.BAS: play SpeakJet AND the CPC's internal AY soundchip
  over USIfAC MIDI IN.

- SP0SYNT: play LambdaSpeak III's SP0256-AL2 and the CPC's AY sound
  chip over USIfAC MIDI IN. Requires standard LambdaSpeak III with
  SP0256-AL2 chip option.



