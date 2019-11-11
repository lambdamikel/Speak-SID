/* 
   Speak&SID CPC, A Speech Synthesizer, SID, and GPIO Card for the Amstrad CPC
   Copyright (C) 2019 Michael Wessel 

   This program is free software; you can redistribute it and/or modify
   it under the terms of the GNU General Public License as published by
   the Free Software Foundation; either version 3 of the License, or
   (at your option) any later version.

   This program is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
   GNU General Public License for more details.

   You should have received a copy of the GNU General Public License
   along with this program; if not, write to the Free Software Foundation,
   Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301  USA

   Speak&SID CPC version 1, Copyright (C) 2019 Michael Wessel
   Speak&SID CPC comes with ABSOLUTELY NO WARRANTY. 
   This is free software, and you are welcome to redistribute it
   under certain conditions. 

*/ 

//
// Speak&SID CPC 
// v1.0 
// License: GPL 3 
// 
// (C) 2020 Michael Wessel 
// mailto:miacwess@gmail.com
// https://www.michael-wessel.info
// 

#include <avr/io.h>
#include <util/delay.h>
#include "pinDefines.h"
#include <avr/interrupt.h>
#include <stdlib.h> 
#include <avr/wdt.h>
#include <stdio.h> 

//
// Version Number 
//
 
#define VERSION 1 

//
// AVR Frequency 16 MHz 
//

#define FOSC 16000000UL 

//
// Utility Macros 
// 

#define SOFT_RESET() do { wdt_enable(WDTO_15MS); for(;;) {}} while(0) 

#define BV(bit) (1 << (bit))
#define TOGGLE_BIT(byte, bit) (byte ^= BV(bit))
#define SET_BIT(byte, bit) (byte |= BV(bit))
#define CLEAR_BIT(byte, bit) (byte &= ~BV(bit))

//
// Speak&SID State Management
// 

typedef enum { SSA1, SPEAKJET, ECHO, SID, UART, SPI, I2C, GPIO } MODE;  
static volatile MODE cur_mode = SSA1; 
static volatile MODE last_mode = SSA1;  

static volatile uint8_t disable_once = 0; 

//
// UART Default Settings 
//

static volatile uint8_t  SERIAL_BAUDRATE = 2; 
static volatile uint8_t  SERIAL_WIDTH = 8; 
static volatile uint8_t  SERIAL_PARITY = 0; 
static volatile uint8_t  SERIAL_STOP_BITS = 1; 

//
// Default SpeakJet Settings
//

#define VOLPOS 1
#define VOL 96 

#define SPEEDPOS 3
#define SPEED 114

#define PITCHPOS 5
#define PITCH 88 

#define BENDPOS 7
#define BEND 5

//
// Default SpeakJet Welcome Message 
// CPC Speak & SID 
// To produce these phoneme / allophone strings, use the SpeakJet PhraseALator 
// 

volatile uint8_t message[] = { 20, VOL, 21, SPEED, 22, PITCH, 23, BEND, 187, 187, 128, 128, 198, 128, 128, 187, 187, 128, 128, 187, 198, 8, 128, 196, 8, 132, 8, 141, 177, 8, 187, 129, 129, 191 }; 

//
// Default SpeakJet Init Message 
// 

volatile uint8_t init[] = { 20, VOL, 21, SPEED, 22, PITCH, 23, BEND }; 

#define INIT_LENGTH 8 

//
// GPIO 
// 

#define GPOPORT PORTC // PC4 - PC7 LED General Purpose Output 4 Segment BAR 
#define GPIIN   PINB  // [PB0 PB1 PB3 PB4] LED General Purpose Input 4 Bits, PB2 is SSA1 READ REQUEST (INT2)!

//
// SID PORT 
// 

#define SIDPORT PORTC
#define SIDON   PC2 // -> CPLD, combined into SID CS computed by CPLD! 

//
// AVR Status 
//

#define ATMEGAREADYPORT PORTC
#define ATMEGAREADY     PC3 

//
// CPC IO 
// 

#define FROMCPC PINA
#define TOCPC   PORTA

//
// Control SpeakJet and CPLD
// 

#define CTRLIN  PIND 
#define CTRLOUT PORTD

#define JETRDY      PD2 // D0 
#define JETSPEAKING PD5 // D1 
#define JETHALFFULL PD6 // D2 

#define SPEAKRESET  PD7 // SpeakJet RESET

#define SPEAKWR   PD3 
#define SPEAKRD   PB2
#define CPLDSTORE PD4

//
// CPLD Store 
// 

#define LOAD_CPLD SET_BIT(CTRLOUT, CPLDSTORE); CLEAR_BIT(CTRLOUT, CPLDSTORE); _delay_us(5) 

//
// CPC <-> AVR Communication 
// 

#define ENABLE_INPUT  DDRA = 0b00000000;            
#define ENABLE_OUTPUT DDRA = 0b11111111;            

#define DATA_FROM_CPC(data) ENABLE_INPUT;  SET_BIT(ATMEGAREADYPORT, ATMEGAREADY); loop_until_bit_is_set(CTRLIN, SPEAKWR); data = FROMCPC; loop_until_bit_is_clear(CTRLIN, SPEAKWR); CLEAR_BIT(ATMEGAREADYPORT, ATMEGAREADY); 

#define DATA_TO_CPC(data)   ENABLE_OUTPUT; TOCPC = data; LOAD_CPLD; ENABLE_INPUT 

//
// Amstrad SSA-1 SBY / LRQ Emulation 
//

#define _LRQ PA6  // bit 6
#define SBY  PA7  // bit 7 

#define SPEECH_IDLE_LOADME()      ENABLE_OUTPUT; CLEAR_BIT(TOCPC, _LRQ);   SET_BIT(TOCPC, SBY); LOAD_CPLD; ENABLE_INPUT
#define SPEECH_BUSY()             ENABLE_OUTPUT;   SET_BIT(TOCPC, _LRQ); CLEAR_BIT(TOCPC, SBY); LOAD_CPLD; ENABLE_INPUT 
#define SPEECH_SPEAKING_LOADME()  ENABLE_OUTPUT; CLEAR_BIT(TOCPC, _LRQ); CLEAR_BIT(TOCPC, SBY); LOAD_CPLD; ENABLE_INPUT 

// 
// Wait for SpeakJet Ready
//

#define WAIT_FOR_SPEAKREADY loop_until_bit_is_set(CTRLIN, JETRDY) 

//
// SSA-1 Speak Buffer 
//

#define SIZE 128
#define BUFMAX SIZE-2

volatile uint8_t speak_ready = 1; 
volatile uint8_t emulated_buffer_size = 0; 
volatile uint8_t ms_count = 0; 

#define SIGNAL_DELAY_MAX 90
#define SIGNAL_DELAY_TIME 10

volatile uint8_t length = 0; 
volatile uint8_t buffer[SIZE]; 

//
// SP0256-AL2 Allophone to SpeakJet Allophone Mapping
//

volatile uint8_t allo_map[0x40]; 

void init_allophones() {

  /* 00h PA1   PAUSE        6.4ms       20h /AW/  Out        254.8ms */

  allo_map[0x00] = 0;
  allo_map[0x20] = 136; 

  /* 01h PA2   PAUSE       25.6ms       21h /DD2/ Do          72.1ms */

  allo_map[0x01] = 4; 
  allo_map[0x21] = 174;  // or 175 ? 

  /* 02h PA3   PAUSE       44.8ms       22h /GG3/ Wig        110.5ms */

  allo_map[0x02] = 5; 
  allo_map[0x22] = 180; 

  /* 03h PA4   PAUSE       96.0ms       23h /VV/  Vest       127.4ms */

  allo_map[0x03] = 1; 
  allo_map[0x23] = 166; 

  /* 04h PA5   PAUSE      198.4ms       24h /GG1/ Got         72.1ms */

  allo_map[0x04] = 2; 
  allo_map[0x24] = 179; 

  /* 05h /OY/  Boy        291.2ms       25h /SH/  Ship       198.4ms */

  allo_map[0x05] = 156; 
  allo_map[0x25] = 189; 

  /* 06h /AY/  Sky        172.9ms       26h /ZH/  Azure      134.1ms */

  allo_map[0x06] = 157; 
  allo_map[0x26] = 168; 

  /* 07h /EH/  End         54.6ms       27h /RR2/ Brain       81.9ms */

  allo_map[0x07] = 131; 
  allo_map[0x27] = 148; 

  /* 08h /KK3/ Comb        76.8ms       28h /FF/  Food       108.8ms */

  allo_map[0x08] = 195; 
  allo_map[0x28] = 177;

  /* 09h /PP/  Pow        147.2ms       29h /KK2/ Sky        134.4ms */

  allo_map[0x09] = 199;  // 198 ? 
  allo_map[0x29] = 194; 

  /* 0Ah /JH/  Dodge       98.4ms       2Ah /KK1/ Can't      115.2ms */

  allo_map[0x0a] = 165; 
  allo_map[0x2a] = 194; 

  /* 0Bh /NN1/ Thin       172.9ms       2Bh /ZZ/  Zoo        148.6ms */

  allo_map[0x0b] = 142; 
  allo_map[0x2b] = 167; 

  /* 0Ch /IH/  Sit         45.5ms       2Ch /NG/  Anchor     200.2ms */

  allo_map[0x0c] = 129; 
  allo_map[0x2c] = 143; 

  /* 0Dh /TT2/ To          96.0ms       2Dh /LL/  Lake        81.9ms */

  allo_map[0x0d] = 192; 
  allo_map[0x2d] = 145; 

  /* 0Eh /RR1/ Rural      127.4ms       2Eh /WW/  Wool       145.6ms */

  allo_map[0x0e] = 148; 
  allo_map[0x2e] = 147; 

  /* 0Fh /AX/  Succeed     54.6ms       2Fh /XR/  Repair     245.7ms */

  allo_map[0x0f] = 133; 
  allo_map[0x2f] = 150; 

  /* 10h /MM/  Milk       182.0ms       30h /WH/  Whig       145.2ms */

  allo_map[0x10] = 140; 
  allo_map[0x30] = 185; 

  /* 11h /TT1/ Part        76.8ms       31h /YY1/ Yes         91.0ms */

  allo_map[0x11] = 191; 
  allo_map[0x31] = 158; 

  /* 12h /DH1/ They       136.5ms       32h /CH/  Church     147.2ms */

  allo_map[0x12] = 169; 
  allo_map[0x32] = 182; 

  /* 13h /IY/  See        172.9ms       33h /ER1/ Letter     109.2ms */

  allo_map[0x13] = 128; 
  allo_map[0x33] = 148;  // ???? 

  /* 14h /EY/  Beige      200.2ms       34h /ER2/ Fir        209.3ms */

  allo_map[0x14] = 130; 
  allo_map[0x34] = 151; 

  /* 15h /DD1/ Could       45.5ms       35h /OW/  Beau       172.9ms */

  allo_map[0x15] = 176; 
  allo_map[0x35] = 137; 

  /* 16h /UW1/ To          63.7ms       36h /DH2/ Bath       182.0ms */

  allo_map[0x16] = 192; 
  allo_map[0x36] = 169; 

  /* 17h /AO/  Aught       72.8ms       37h /SS/  Vest        64.0ms */

  allo_map[0x17] = 135; 
  allo_map[0x37] = 187; 

  /* 18h /AA/  Hot         63.7ms       38h /NN2/ No         136.5ms */

  allo_map[0x18] = 136; 
  allo_map[0x38] = 142; 

  /* 19h /YY2/ Yes        127.4ms       39h /HH2/ Hoe        126.0ms */

  allo_map[0x19] = 158; 
  allo_map[0x39] = 183; 

  /* 1Ah /AE/  Hat         81.9ms       3Ah /OR/  Store      236.6ms */

  allo_map[0x1a] = 132; 
  allo_map[0x3a] = 153; 

  /* 1Bh /HH1/ He          89.6ms       3Bh /AR/  Alarm      200.2ms */

  allo_map[0x1b] = 183; 
  allo_map[0x3b] = 134; 

  /* 1Ch /BB1/ Business    36.4ms       3Ch /YR/  Clear      245.7ms */

  allo_map[0x1c] = 170; 
  allo_map[0x3c] = 149; 

  /* 1Dh /TH/  Thin       128.0ms       3Dh /GG2/ Guest       69.4ms */

  allo_map[0x1d] = 190; 
  allo_map[0x3d] = 178; 

  /* 1Eh /UH/  Book        72.8ms       3Eh /EL/  Saddle     136.5ms */

  allo_map[0x1e] = 138; 
  allo_map[0x3e] = 159; 

  /* 1Fh /UW2/ Food       172.9ms       3Fh /BB2/ Business    50.2ms */

  allo_map[0x1f] = 139; 
  allo_map[0x3f] = 170; // or 171 ??

}

//
// Init UART 
//

void uart_on0(uint8_t rate, uint8_t width, uint8_t parity, uint8_t stop_bits) {

  SERIAL_BAUDRATE = rate; 
  SERIAL_WIDTH = width; 
  SERIAL_PARITY = parity; 
  SERIAL_STOP_BITS = stop_bits; 

  uint32_t baud_rate = 0; 

  switch (rate) {
  case 0 : baud_rate = 2400; break; // 2400 
  case 1 : baud_rate = 4800; break; // 4800 
  case 2 : baud_rate = 9600; break; // 9600 
  case 3 : baud_rate = 14400; break;  // 14400 
  case 4 : baud_rate = 19200; break;  // 19200
  case 5 : baud_rate = 28800; break;  // 28800
  case 6 : baud_rate = 31250; break;  // 31250 MIDI ! NEW
  case 7 : baud_rate = 38400; break;  // 38400 
  case 8 : baud_rate = 57600; break;  // 57600 
  case 9 : baud_rate = 76800; break;  // 76800 
  case 10 : baud_rate = 115200; break;  // 115200 
  case 11 : baud_rate = 208333; break;  // 208333
  case 12 : baud_rate = 250000; break;  // 250000
  case 13 : baud_rate = 312500; break;  // 312500
  case 14 : baud_rate = 416667; break;  // 416667
  case 15 : baud_rate = 625000; break;  // 625000
  case 16 : baud_rate = 1250000; break;  // 1250000 
  default : baud_rate = 9600; // 9600 
  }
 
  uint16_t baud_setting = FOSC/16/baud_rate - 1; 

  UBRRH = (unsigned char)(baud_setting>>8);
  UBRRL = (unsigned char) baud_setting;

  uint8_t data = 0; 

  switch (parity) { 
  case 0 :                                      break; // no parity 
  case 1 : data |= (1 << UPM1) | (1 << UPM0) ; break; // odd parity 
  case 2 : data |= (1 << UPM1)               ; break; // even parity 
  default : break; 
  }

  switch (stop_bits) { 
  case 1 :                       break; // 1 stop bit
  case 2 : data |= (1 << USBS); break; // 2 stop bit
  default : break; 
  }


  switch (width) {
  case 8 : data |= (1 << UCSZ0) | (1 << UCSZ1); break; // 8bit 
  case 7 : data |=                (1 << UCSZ1); break; // 7bit 
  case 6 : data |= (1 << UCSZ0)               ; break; // 6bit 
  case 5 :                                        break; // 5bit 

  default : data |= (1 << UCSZ0) | (1 << UCSZ1);       // 8bit  

  }

  UCSRC = (1 << URSEL) | data; 
  UCSRA = 0x00; 
  
}

void uart_off(void) {    
  UCSRB = 0;
}

//
// UART RX Vector 
// 

volatile uint8_t read_pos = 0; 
volatile uint8_t write_pos = 0; 

ISR(USART_RX_vect) {
  if (! ((write_pos+1 == read_pos -1) || (write_pos == SIZE-1 && read_pos == 1))) {    
    buffer[write_pos] = UDR; 
    write_pos++; 
    write_pos %= SIZE; 
  }
}

// 
// UART Function 
// 

void uart_init(void) {
  uart_off(); 
  UCSRB = (1<<TXEN) | (1<<RXEN) | (1 << RXCIE); 
  uart_on0(SERIAL_BAUDRATE, SERIAL_WIDTH, SERIAL_PARITY, SERIAL_STOP_BITS); 
}


void uart_transmit( unsigned char data ) {
  while ( !( UCSRA & (1<<UDRE)) );
  WAIT_FOR_SPEAKREADY; 
  UDR = data;
}

void uart_print_string(const char myString[]) {
  uint8_t i = 0;
  while (myString[i]) {
    uart_transmit(myString[i]);
    i++;
  }
}

//
// Timers for SSA-1 LRQ / SBY Signal Emulation
// 

void stop_timer() {  
  TCCR0 &= ~(1 << CS02);
  TCCR0 &= ~(1 << CS00);
}

void start_timer() {
  SET_BIT(TCCR0, CS02);
  SET_BIT(TCCR0, CS00); 
  ms_count = 0; 
}

void stop() {
  stop_timer(); 
}

void cont() {
  length = INIT_LENGTH; 
  emulated_buffer_size = 0; 
  start_timer(); 
  ms_count = 0; 
  SPEECH_IDLE_LOADME(); 
}

//
// Speak Buffer
//  

void speak_buffer() {

  stop();   
  uart_print_string(init); 
  
  for (int i = INIT_LENGTH; i < length; i++) {
    uint8_t data = buffer[i];
    data = data < 0x40 ? allo_map[data] : data; 
    uart_transmit(data); 
  } 
  cont(); 
  
}

//
// SpeakJet Ready Signal via Interrupt 0 
// 

ISR (INT0_vect) {  // SPEAKJET READY PD2 INT0 
  
  if (bit_is_set(CTRLIN, JETRDY)) {
    speak_ready = 0; 
  } else {
    speak_ready = 1; 
  }
}

//
// CPC IOREQ & READ via Interrupt 2 
// 

ISR (INT2_vect) {  // SSA1 SPEECH READ REQ

  if (! disable_once) {
    uint8_t data = 0; 
    if (cur_mode == SPEAKJET) { 
      // PD2, PD5, PD6 
      data = ((CTRLIN & 0b00000100) >> 2) | ((CTRLIN & 0b01100000) >> 4); 
      DATA_TO_CPC(data); 
    } else if (cur_mode == GPIO) {
      data = (GPIIN & 0b00000011) | ((GPIIN & 0b00011000) >> 1); 
      DATA_TO_CPC(data); 
    } 
  }
}

//
// Timer for SP0256-AL2 LRQ / SBY Signal Emulation 
// 

ISR (TIMER0_COMP_vect) {  // timer0 overflow interrupt
  if (length > INIT_LENGTH ) {

    ms_count++; 

    if (ms_count == SIGNAL_DELAY_TIME) {
      SPEECH_IDLE_LOADME();       
    } else if (ms_count == SIGNAL_DELAY_MAX) {
      ms_count = 0;   
      speak_buffer(); 
    }
  }
}

//
// Reset Functions
// 

void speakjet_reset(void) {
  CLEAR_BIT(CTRLOUT, SPEAKRESET); 
  _delay_ms(10); 
  SET_BIT(CTRLOUT, SPEAKRESET); 
}

void process_reset(void) {
  speakjet_reset(); 
  SOFT_RESET();   
}

//
// SpeakJet Change Settings 
// 

void test_voice(void) {
  uart_print_string(message);
}

void change_voice(uint8_t pos, uint8_t value) {
  init[pos] = value; 
  message[pos] = value; 
  test_voice(); 
}

//
// Main 
//
 
void init_main(void) {

  //
  // Init SP0256-AL2 Allophone -> SpeakJet Translation Table 
  // 

  init_allophones();

  //
  // Timer for SP0 Signal Emulation (RDY, SBY) 
  // 

  SET_BIT(TCCR0, WGM01);  // Set the Timer Mode to CTC
  OCR0 = 0xF9;   // Set the value that you want to count to
  SET_BIT(TIMSK, OCIE0);  //Set the ISR COMPA vect

  // INT0 = PD2 = SPEAKJET READY INTERRUPT CHANGE ENABLE
  // MCUCSR = (1<<ISC00) | (1<<ISC01);
  // GICR = (1<<INT0);
  // GIFR = (1<<INTF0); 

  //
  // Configure AVR GPIO Ports 
  // 

  // DDR REGISTERS - 1 = OUTPUT, O = INPUT 
  DDRA = 0b00000000;            
  // 0 - 1 : GPIO IN[0:1], 2 - SSA1 READRQ, 3 - 4 GPIO IN[2:3], 5 - 7 SPI 
  DDRB = 0b11100000;    
  // 0, 1 I2C, 2 = SIDON, 3 = ATMega Loop Ready for Commands, 4 - 7 GPIO Output LED Segment Bar 
  DDRC = 0b11111111;            
  // 0 - 1 RXD TDX, 2 SpeakReady, 3 CPC IOWRREQ, 4 STORE CPLD, 5 - 6 SpeakJet D1, D2, 7 SpeakJet RESET OUTPUT!
  DDRD = 0b10010010;            

  //
  // SpeakJet Reset, Turn Off SID 
  // AVR cannot Reset the SID registers 
  // CPC needs to do that!
  // 

  SET_BIT(CTRLOUT, SPEAKRESET); 
  CLEAR_BIT(SIDPORT, SIDON);

  // INT2 = PB2 = SSA1 IOREAD REQUEST 
  MCUCSR = (1<<ISC2);
  GICR = (1<<INT2);
  GIFR = (1<<INTF2);

  sei();

  uart_init(); 
  test_voice();

  cur_mode  = SSA1; 
  last_mode = SSA1;  

  //
  // Fill Buffer with SpeakJet Preamble Bytes (Voice Speed Volume etc.) 
  // 

  buffer[0] = 20;
  buffer[1] = 96;
  buffer[2] = 21;
  buffer[3] = 114;
  buffer[4] = 22;
  buffer[5] = 88;
  buffer[6] = 23;
  buffer[7] = 5; 

  length = INIT_LENGTH; 

  disable_once = 0; 

}

int main(void) {

  uint8_t data = 0; 

  init_main(); 

  while (1) {

    last_mode = cur_mode; 

    if (! disable_once ) {

      // don't overwrite value that was requested, 
      // e.g. from get_mode: we will have one
      // chance to read it

      switch (cur_mode) {

      case SSA1 : 
	if (emulated_buffer_size == 0) {
	  SPEECH_IDLE_LOADME();
	} else {
	  SPEECH_SPEAKING_LOADME();
	}
	break; 

      default : break; 

      }
    }

    disable_once = 0; 

    DATA_FROM_CPC(data); 
   
    if (data == 255) {
	// command byte? 
	DATA_FROM_CPC(data); 

	if (data != 255) { 

	CLEAR_BIT(SIDPORT, SIDON);
	
	switch (data) {
	case 0 : process_reset(); break; 
	case 1 : speakjet_reset(); continue; break; 

	case 2 : cur_mode = SPEAKJET; break; 
	case 3 : cur_mode = SSA1; break;
	case 4 : 
	  cur_mode = SID; 
	  ENABLE_INPUT;
	  SET_BIT(SIDPORT, SIDON);
	  while (1) {
	    loop_until_bit_is_set(CTRLIN, SPEAKWR); 
	    DATA_FROM_CPC(data); 
	    loop_until_bit_is_clear(CTRLIN, SPEAKWR); 
	    if (data == 255) {
	      break; 
	    } 
	    data = (data & 15) << 4;  
	    SET_BIT(data, SIDON);
	    GPOPORT = data; 
	  }
	  break; 	  	 
	
	case 5 : cur_mode = UART; break; 
	case 6 : cur_mode = SPI; break; 
	case 7 : cur_mode = I2C; break; 
	case 8 : cur_mode = GPIO; break; 
	case 9 : cur_mode = ECHO; break; 

        // non mode-changing: exit with continue; break; : 

	case 10 : test_voice(); continue; break; 	  

	case 20 : 
	  DATA_FROM_CPC(data); 
	  change_voice(VOLPOS, data); 
	  continue; 
	  break; 

	case 21 : 
	  DATA_FROM_CPC(data); 
	  change_voice(SPEEDPOS, data); 
	  continue; 
	  break; 

	case 22 : 
	  DATA_FROM_CPC(data); 
	  change_voice(PITCHPOS, data); 
	  continue; 
	  break; 

	case 23 : 
	  DATA_FROM_CPC(data); 
	  change_voice(BENDPOS, data); 
	  continue; 
	  break; 

	case 30 : // get mode 
	  // allow reading ONCE: 
	  disable_once = 1; 
	  DATA_TO_CPC(cur_mode);
	  continue; 
	  break; 

	case 40: 
	  // read number of bytes 
	  data = (write_pos < read_pos) ? write_pos + (SIZE - read_pos) : write_pos - read_pos; 
	  DATA_TO_CPC(data); 
	  disable_once = 1; 
	  continue; 
	  break; 	

	case 41: 
	  // get next byte in buffer
	  if (read_pos != write_pos) {
	    DATA_TO_CPC(buffer[read_pos]); 
	    read_pos ++; 
	    read_pos %= SIZE; 
	    disable_once = 1; 
	  }
	  continue; 
	  break; 	  

	case 50 : // set BAUDRATE
	  DATA_FROM_CPC(SERIAL_BAUDRATE); 
	  uart_init(); 
	  continue; 
	  break; 

	case 51 : // set WIDTH
	  DATA_FROM_CPC(SERIAL_WIDTH); 
	  uart_init(); 
	  continue; 
	  break; 

	case 52 : // set PARITY
	  DATA_FROM_CPC(SERIAL_PARITY); 
	  uart_init(); 
	  continue; 
	  break; 

	case 53 : // set STOP BITS 
	  DATA_FROM_CPC(SERIAL_STOP_BITS); 
	  uart_init(); 
	  continue; 
	  break; 

	case 99 : // get version
	  // allow reading ONCE: 
	  disable_once = 1; 
	  DATA_TO_CPC(VERSION);
	  continue; 
	  break; 

	case 100 : 
	  // WAIT 5 seconds 
	  _delay_ms(5000); 
	  continue;
	  break; 

	case 255 : break; 

	default : break; 	  

	}
      }
    }

    if (cur_mode == last_mode) {

      switch (cur_mode) {

      case ECHO: 
	DATA_TO_CPC(data); 
	break; 

      case SPEAKJET: 

	uart_transmit(data); 	
	break; 

      case SSA1 : 
	
	SPEECH_BUSY(); 
	stop_timer(); 

	// _delay_us(15); 
	_delay_us(5); 

	start_timer(); 
    
	buffer[length++] = data;
	emulated_buffer_size = 1; 
    
	if (length == BUFMAX)  {
	  speak_buffer(); 
	} 

	break; 

      case SID : 
	// is never reached! 
	// SID mode has its own listener loop, 
	// merely for LED lightshow 
	break; 

      case UART : 
	uart_transmit(data); 	
	break; 

      case SPI : 
	// TODO - add some generic SPI functions
	break; 

      case I2C : 
	// TODO - add some generic I2C functions
	break; 

      case GPIO : 
	// output WRITE request -> to output port, only lower nibble
	GPOPORT = (data & 15) << 4; 
	break; 
		
      }      
    }
  }

  return 0;

}

