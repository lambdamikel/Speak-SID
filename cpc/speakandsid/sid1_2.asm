; ./pasmo.exe --amsdos sidplay.asm sidplay.bin

; SID Player v1.2, by Simon Owen
;
; WWW http//simonowen.com/sam/sidplay/
; Modified by DaDMaN from the CPC Wiki Forum for SONIQUE Sound Board
; Modified by Michael Wessel for Speak&SID 
;
; Emulates a 6510 CPU to play most C64 SID tunes in real time.
; Requires Quazar SID interface board (see www.quazar.clara.net)
;
; Load PSID file at &10000 and call &d000 to play
; POKE &d002,tune-number (default=0, for SID default)
; POKE &d003,key-mask (binary 0,0,Esc,Right,Left,Down,Up,Space)
; DPOKE &d004,pre-buffer-frames (default=25, for 0.5 seconds)
;
; Features:
;   - Full 6510 emulation in Z80
;   - PAL (50Hz), NTSC (60Hz) and 100Hz playback speeds
;   - Support PSID files up to 64K
;   - Both polled and timer-driven players
;
; RSID files and sound samples are not supported.
NOLIST
  write direct "a:spksid2.bin"

base          equ  &d000           ; Player based at 53248

buffer_blocks equ  25 ; 25              ; number of frames to pre-buffer
buffer_low    equ  50              ; low limit before screen disable

;status        equ  249             ; Status port for active interrupts (input)
;line          equ  249             ; Line interrupt (output)
;midi          equ  253             ; MIDI port
;lmpr          equ  250             ; Low Memory Page Register
;hmpr          equ  251             ; High Memory Page Register
;border        equ  254             ; Bits 5 and 3-0 hold border colour (output)
;keyboard      equ  254             ; Main keyboard matrix (input)
;rom0_off      equ  %00100000       ; LMPR bit to disable ROM0

;low_page      equ  3               ; LMPR during emulation
;high_page     equ  5               ; HMPR during emulation
;buffer_page   equ  7               ; base page for SID buffering

ret_ok        equ  0               ; no error (space to exit)
;ret_space     equ  ret_ok          ; space
;ret_up        equ  1               ; cursor up
;ret_down      equ  2               ; cursor down
;ret_left      equ  3                cursor left
;ret_right     equ  4               ; cursor right
;ret_esc       equ  5               ; esc
ret_badfile   equ  6               ; missing or invalid file
ret_rsid      equ  7               ; RSID files unsupported
ret_timer     equ  8               ; unsupported timer frequency
ret_brk       equ  9               ; BRK unsupported

m6502_nmi     equ  &fffa           ; nmi vector address
m6502_reset   equ  &fffc           ; reset vector address
m6502_int     equ  &fffe           ; int vector address (also for BRK)

c64_irq_vec   equ  &0314           ; C64 IRQ vector
c64_irq_cont  equ  &ea31           ; C64 ROM IRQ chaining
c64_cia_timer equ  &dc04           ; C64 CIA#1 timer

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

               org  base
;               dump $
;               autoexec             ; set the code file as auto-executing

               jr   start

song          defb 0               ; 0=default song from SID header
key_mask      defb %00000000       ; exit keys to ignore
pre_buffer    defw buffer_blocks   ; pre-buffer 1 second

start:         di

               ld   (old_stack+1),sp
               ld   sp,new_stack
               
; Desconectamos las ROMS y establecemos el modo 1
               ld   c,%10001101
               ld   b,&7f
               out (c),c

; #0000-#7fff   Páginas 3 y 4
;               ld   a,low_page+rom0_off
;               out  (lmpr),a        ; page in tune

; Tenemos el sid cargado en la dirección #4000
               ld   hl,&4000         ; SID file header
               ld   a,(hl)
               cp   "R"             ; RSID signature?
               ld   c,ret_rsid
               jp   z,exit_player
               cp   "P"             ; new PSID signature?
               jr   nz,old_file

               ld   de,sid_header
               ld   bc,22
               ldir                 ; copy header to master copy
old_file:      ;ex   af,af'          ; save Z flag for new file

               ld   ix,sid_header
               ld   a,(ix)
               cp   "P"
               ld   c,ret_badfile
               jp   nz,exit_player

; Mueve el emulador de c64 a la página 6
; en nuestro caso corrompe el sid
; #0000-#7fff   Páginas 5 y 6
;               ld   a,high_page+rom0_off
;               out  (lmpr),a
;               ld   hl,&d000
;               ld   de,&d000-&8000
;               ld   bc,&1000
;               ldir                 ; copy player

; El mapa de memoria es:
; #0000-#7fff   Páginas 3 y 4 <-(SID)
;              ld   a,low_page+rom0_off
;              out  (lmpr),a        ; page tune back in
; #8000-#ffff   Páginas 5 y 6 <-(Emulador)
;              ld   a,high_page
;              out  (hmpr),a        ; activate player copy

; IX apunta a la cabecera del sid
               ld   h,(ix+10)       ; init address
               ld   l,(ix+11)
               ld   (init_addr),hl
               ld   h,(ix+12)       ; play address
               ld   l,(ix+13)
               ld   (play_addr),hl

               ld   h,(ix+6)        ; data offset (big-endian)
               ld   l,(ix+7)
               ld   d,(ix+8)        ; load address (or zero)
               ld   e,(ix+9)

        			 LD   BC,&4000
               ADD  HL,BC

               ld   a,d
               or   e
               jr   nz,got_load     ; jump if address valid
               ld   e,(hl)          ; take address from start of data
               inc  l               ; (already little endian)
               ld   d,(hl)
               inc  l
got_load:

;               ex   af,af'
;               jr   nz,no_reloc

; Se mueve el SID a su dirección de carga en el c64
; At this point we have  HL=sid_data DE=load_addr
        ;LD  DE,&0b00
				;LD HL,&407e ;&76 Solo en este caso
				LDIR
;               ld   b,h
;               ld   c,l
;               ld   hl,&ffff
;               and  a
;               sbc  hl,de
;               add  hl,bc
;               ld   de,&ffff
;               ld   bc,&2000
;               lddr                 ; relocate e000-ffff
;               ld   bc,-&1000
;               add  hl,bc
;               ex   de,hl
;               add  hl,bc
;               ex   de,hl
;               ld   bc,&d000
;               lddr                 ; relocate 0000-cfff
no_reloc:
               ld   h,0
               ld   l,h
clear_zp:      ld   (hl),h
               inc  l
               jr   nz,clear_zp

               ld   b,(ix+15)       ; songs available
               ld   c,(ix+17)       ; default start song
               ld   a,(song)        ; user requested song
               and  a               ; zero?
               jr   z,use_default   ; use default if so
               inc  b               ; max+1
               cp   b               ; song in range?
               jr   c,got_song      ; use if it is
use_default:   ld   a,c
got_song:      ld   (play_song),a   ; save song to play

               ld   hl,sid_header+21  ; end of speed bit array
speed_lp:      ld   c,1             ; start with bit 0
speed_lp2:     dec  a
               jr   z,got_speed
               rl   c               ; shift up bit to check
               jr   nc,speed_lp2
               dec  hl
               jr   speed_lp
got_speed:     ld   a,(hl)
               and  c
               ld   (ntsc_tune),a

               call play_tune
               ld   c,a
               exx

               di
               im   1
               call sid_reset

               exx
exit_player:
;			    ld   b,0
; Dejamos la RAM del Sam Coupe en su estado inicial
; #0000-#7fff   Páginas 31 y 0
;               ld   a,31
;               out  (lmpr),a
; #8000-#ffff   Páginas 1 y 2
;               ld   a,1
;               out  (hmpr),a
;               xor  a
;               out  (border),a
old_stack:     ld   sp,0
               ei
               ret

sid_header:    defs 22              ; copy of start of SID header

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; Tune player

play_tune:     
; El buffer del audio generado lo almacenaremos en la RAM secundaria del CPC
               ld   hl,&0000

               ld   (blocks),hl     ; no buffered blocks
               ld   (c64_cia_timer),hl  ; no timer frequency
               ld   (c64_irq_vec),hl    ; no irq handler for timer
               ld   h,&f0
               ld   (head),hl       ; head/tail at buffer start
               ld   (tail),hl

               call reorder_decode  ; optimise decode table

               ld   a,(play_song)   ; song to play
               dec  a               ; player expects A=song-1
               ld   hl,(init_addr)  ; tune init function
               call execute         ; initialise player
               and  a
               ret  nz              ; return any error

               call sid_reset       ; reset the SID
               call record_block    ; record initial SID state

               ld   hl,(play_addr)  ; tune player poll address
               ld   a,h
               or   l
               jr   nz,buffer_loop  ; non-zero means we have one

               ld   hl,(c64_irq_vec); use custom handler
               ld   a,&40           ; rti 6502 opcode
               ld   (c64_irq_cont),a ; no ROM IRQ continuation
               ld   (play_addr),hl  ; store play address

buffer_loop:   ld   hl,(blocks)     ; current block count
               ld   de,(pre_buffer) ; blocks to pre-buffer
               and  a
               sbc  hl,de
               jr   nc,buffer_done

               xor  a
               ld   hl,(play_addr)  ; poll or interrupt addr
               call execute
               and  a
               ret  nz              ; return any errors

               call record_block    ; record the state
               jr   buffer_loop     ; loop buffering more

buffer_done:   call set_speed       ; set player speed
               call enable_player   ; enable interrupt-driven player

sleep_loop: 
;               di
;               ; Esperamos el refresco de pantalla
;               LD B,#F5
; wait_vbl
;               IN A,(C)
;               RRA
;               JR NC,wait_vbl
;               ei
               halt                 ;JGN wait for a block to play

               

play_loop:
                CALL wait50hz      ;JGN
;               ld   a,(key_mask)    ; keys to ignore
;               ld   b,a
;
;               ld   a,&f7
;               in   a,(status)      ; read extended keys
;               or   b
;               and  %00100000       ; check Esc
;               ld   a,ret_esc
;               ret  z               ; exit if pressed
;
;               ld   a,&7f           ; bottom row
;               in   a,(keyboard)    ; read keyboard
;               or   b
;               rra                  ; check Space
;               ld   a,ret_space
;               ret  nc              ; exit if space pressed
;
;               ld   a,&ff           ; cursor keys + cntrl
;               in   a,(keyboard)
;               or   b               ; mask keys to ignore
;               rra                  ; key bit 0 (cntrl)
;               rra                  ; key bit 1 (up)
;               ld   c,a 
;               ld   a,ret_up
;               ret  nc              ; return if pressed
;               inc  a
;               rr   c               ; key bit 2 (down)
;               ret  nc              ; return if pressed
;               inc  a
;               rr   c               ; key bit 3 (left)
;               ret  nc              ; return if pressed
;               inc  a
;               rr   c               ; key bit 3 (right)
;               ret  nc              ; return if pressed
;
;               ld   a,&f7
;               in   a,(keyboard)
;               rra
;               ld   c,a
;               call nc,set_100hz
;               bit  3,c
;               call z,set_50hz
;               ld   a,&ef
;               in   a,(keyboard)
;               bit  4,a
;               call z,set_60hz

               ld   hl,(blocks)     ; check buffered blocks
               ld   de,1023;4095         ; 4095 ;buffer_original*4 <--- 32768/32-1   ; maximum we can buffer
               and  a
               sbc  hl,de
               jr   nc,sleep_loop   ; jump back to wait if full

               xor  a
               ld   hl,(play_addr)
               call execute         ; execute 1 frame
               and  a               ; execution error?
               ret  nz              ; return if so

               call record_block    ; record the new SID state
               jp   play_loop       ; JGN generate more data

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; 6510 emulation

execute:       ex   de,hl           ; PC stays in DE throughout
               ld   iy,0            ; X=0, Y=0
               ld   ix,main_loop    ; decode loop after non-read/write

               ld   b,a             ; set A from Z80 A
               xor  a               ; clear carry
               ld   c,a             ; set Z, clear N
               ex   af,af'

               exx
               ld   hl,&01ff        ; 6502 stack pointer in HL'
               ld   d,%00000100     ; interrupts disabled
               ld   e,0             ; clear V
               exx

read_write_loop:
write_loop:    ld   a,h
               cp   &d4             ; SID based at &d400
               jr   z,sid_write

main_loop:     ld   a,(de)          ; fetch opcode
               inc  de              ; PC=PC+1
               ld   l,a
               ld   h,decode_table/256
               ld   a,(hl)          ; handler low
               inc  h
               ld   h,(hl)          ; handler high
               ld   l,a
               jp   (hl)            ; execute!

sid_write:     ld   a,(hl)
               set  6,l
               xor  (hl)
               jr   z,main_loop
               res  6,l
               set  5,l
               or   (hl)
               ld   (hl),a
               res  5,l
               ld   a,(hl)
               set  6,l
               ld   (hl),a
               jp   (ix)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; Interrupt handling

gap1          equ  &d200-$         ; error if previous code is
               defs gap1            ; too big for available gap!

im2_table:     defs 257             ; 256 overlapped WORDs

im2_handler:   push af

;/*JGN
line_step1:    ld   a,&05           ;d32a
               dec  a
               bit  7,a
               jr   nz,playsnd
               ld   (line_step1+1),a
ret_int:       pop  af
               ei
               ret
;JGN*/
;                in   a,(status)      ; read status to check interrupts
;                rra
;                jr   nc,line_int
;                bit  3,a
;                jr   z,midi_int
;                bit  2,a
;                jr   nz,int_exit
;  
;  frame_int     ld   a,(line_num)
;                and  a               ; zero?
;                jr   z,int_hit       ; frame int only for 50Hz
;                cp   step5_60Hz      ; 2nd step in border for 60Hz
;                jr   z,midi_start
;  line_start    cp   0               ; (self-modified value)
;                jr   z,line_set
;  line_end      cp   0               ; (self-modified value)
;                jr   nz,int_exit     ; skip frame interrupt
;                ld   a,(line_start+1); first step
;                jr   line_set        ; loop interrupt sequence
;  
;  line_int      ld   a,(line_num)
;  line_step1    sub  0               ; (self-modified value)
;  line_set      out  (line),a
;                ld   (line_num),a
; int_hit       ;in   a,(lmpr)
;               push af
; #0000-#7fff   Páginas 7 y 8
;               ld   a,buffer_page+rom0_off
;               out  (lmpr),a
playsnd       ;JGN
               push bc
               push de
               push hl
;                ld   a,(contador)
;                inc  a
;                cp   5
;                jr nz,seguir
;/*JGN
int_val:       ld   a,&05            ;d33a
               ld   (line_step1+1),a
;JGN*/
               call play_block
;                xor  a
; seguir         ld (contador),a
               pop  hl
               pop  de
               pop  bc
;               pop  af
;               out  (lmpr),a
int_exit:      pop  af
               ei
               reti

;/*JGN               
wait50hz:
              ld   a,(line_step1+1)
;               cp   &01
               or   a
               jr   nz,wait50hz
               ret

;               di
;               ; Esperamos el refresco de pantalla
;               LD B,#F5
;wait_vbl
;               IN A,(C)
;               RRA
;               JR NC,wait_vbl
;               ei
;ret
;JGN*/              
               
;contador       defb 0
;  midi_start
;  line_step2    sub  0               ; adjust line for next step
;                 ld   (line_num),a
;                 ld   a,10
;                 jr   midi_next       ; assumes NZ from sub above
;  midi_int      ld   a,0
;                 dec  a
;  midi_next     ld   (midi_int+1),a
;                 jr   z,int_hit
;                 out  (midi),a
;                 jr   int_exit
;  line_num      defb 0


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; Instruction implementations

i_nop         equ  main_loop
i_undoc_1     equ  main_loop
i_undoc_3:     inc  de              ; 3-byte NOP
i_undoc_2:     inc  de              ; 2-byte NOP
               jp   (ix)


i_bpl:         inc  c
               dec  c
               jp   p,i_branch      ; branch if plus
               inc  de
               jp   (ix)

i_bmi:         inc  c
               dec  c
               jp   m,i_branch      ; branch if minus
               inc  de
               jp   (ix)

i_bvc:         exx
               bit  6,e
               exx
               jr   z,i_branch      ; branch if V clear
               inc  de
               jp   (ix)

i_bvs:         exx
               bit  6,e
               exx
               jr   nz,i_branch     ; branch if V set
               inc  de
               jp   (ix)

i_bcc:         ex   af,af'
               jr   nc,i_branch_ex  ; branch if C clear
               ex   af,af'
               inc  de
               jp   (ix)

i_bcs:         ex   af,af'
               jr   c,i_branch_ex   ; branch if C set
               ex   af,af'
               inc  de
               jp   (ix)

i_beq:         inc  c
               dec  c
               jr   z,i_branch      ; branch if zero
               inc  de
               jp   (ix)

i_bne:         inc  c
               dec  c
               jr   nz,i_branch     ; branch if not zero
               inc  de
               jp   (ix)

i_branch_ex:   ex   af,af'
i_branch:      ld   a,(de)
               inc  de
               ld   l,a             ; offset low
               rla                  ; set carry with sign
               sbc  a,a             ; form high byte for offset
               ld   h,a
               add  hl,de           ; PC=PC+e
               ex   de,hl
               jp   (ix)


i_jmp_a:       ex   de,hl           ; JMP nn
               ld   e,(hl)
               inc  hl
               ld   d,(hl)
               jp   (ix)

i_jmp_i:       ex   de,hl           ; JMP (nn)
               ld   e,(hl)
               inc  hl
               ld   d,(hl)
               ex   de,hl
               ld   e,(hl)
               inc  l               ; 6502 bug wraps within page, *OR*
;              inc  hl              ; 65C02 spans pages correctly
               ld   d,(hl)
               jp   (ix)

i_jsr:         ex   de,hl           ; JSR nn
               ld   e,(hl)          ; subroutine low
               inc  hl              ; only 1 inc - we push ret-1
               ld   d,(hl)          ; subroutine high
               ld   a,h             ; PCh
               exx
               ld   (hl),a          ; push ret-1 high byte
               dec  l               ; S--
               exx
               ld   a,l             ; PCl
               exx
               ld   (hl),a          ; push ret-1 low byte
               dec  l               ; S--
               exx
               jp   (ix)

i_rts:         exx                  ; RTS
               inc  l               ; S++
               ld   a,ret_ok
               ret  z               ; finish if stack empty
               ld   a,(hl)          ; PC LSB
               exx
               ld   e,a
               exx
               inc  l               ; S++
               ld   a,(hl)          ; PC MSB
               exx
               ld   d,a
               inc  de              ; PC++ (strange but true)
               jp   (ix)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; C64 I/O range

gap2          equ  &d400-$         ; error if previous code is
               defs gap2            ; too big for available gap!

; C64 SID register go here, followed by a second set recording changes
sid_regs:      defs 32
sid_changes:   defs 32
prev_regs:     defs 32
last_regs:     defs 32              ; last values written to SID

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

i_clc:         and  a               ; clear carry
               ex   af,af'
               jp   (ix)

i_sec:         scf                  ; set carry
               ex   af,af'
               jp   (ix)

i_cli:         exx                  ; clear interrupt disable
               res  2,d
               exx
               jp   (ix)

i_sei:         exx                  ; set interrupt disable
               set  2,d
               exx
               jp   (ix)

i_clv:         exx                  ; clear overflow
               ld   e,0
               exx
               jp   (ix)

i_cld:         exx                  ; clear decimal mode
               res  3,d
               exx
               xor  a               ; NOP
               ld   (adc_daa),a     ; use binary mode for adc
               ld   (sbc_daa),a     ; use binary mode for sbc
               jp   (ix)

i_sed:         exx
               set  3,d
               exx
               ld   a,&27           ; DAA
               ld   (adc_daa),a     ; use decimal mode for adc
               ld   (sbc_daa),a     ; use decimal mode for sbc
               jp   (ix)


i_brk:         ld   a,ret_brk
               ret

i_rti:         exx
               inc  l               ; S++
               ld   a,ret_ok
               ret  z               ; finish if stack empty
               ld   a,(hl)          ; pop P
               ld   c,a             ; keep safe
               and  %00001100       ; keep D and I
               or   %00110000       ; force T and B
               ld   d,a             ; set P
               ld   a,c
               and  %01000000       ; keep V
               ld   e,a             ; set V
               ld   a,c
               rra                  ; carry from C
               ex   af,af'          ; set carry
               ld   a,c
               and  %10000010       ; keep N Z
               xor  %00000010       ; zero for Z
               exx
               ld   c,a             ; set N Z
               exx
               inc  l               ; S++
               ld   a,(hl)          ; pop return LSB
               exx
               ld   e,a             ; PCL
               exx
               inc  l               ; S++
               ld   a,(hl)          ; pop return MSB
               exx
               ld   d,a             ; PCH
               ex   af,af'
               inc  l               ; S++
               ld   a,(hl)          ; pop return MSB
               exx
               ld   d,a
               ex   af,af'
               ld   e,a
               pop  af              ; restore from above
               ex   af,af'          ; set A and flags
               jp   (ix)


i_php:         ex   af,af'          ; carry
               inc  c
               dec  c               ; set N Z
               push af              ; save flags
               ex   af,af'          ; protect carry
               exx
               pop  bc
               ld   a,c
               and  %10000001       ; keep Z80 N and C
               bit  6,c             ; check Z80 Z
               jr   z,php_nonzero
               or   %00000010       ; set Z
php_nonzero:   or   e               ; merge V
               or   d               ; merge T D I
               or   %00010000       ; B always pushed as 1
               ld   (hl),a
               dec  l               ; S--
               exx
               jp   (ix)

i_plp:         exx
               inc  l               ; S++
               ld   a,(hl)          ; pop P
               ld   c,a             ; keep safe
               and  %00001100       ; keep D and I
               or   %00110000       ; force T and B
               ld   d,a             ; set P
               ld   a,c
               and  %01000000       ; keep V
               ld   e,a             ; set V
               ld   a,c
               rra                  ; carry from C
               ex   af,af'          ; set carry
               ld   a,c
               and  %10000010       ; keep N Z
               xor  %00000010       ; zero for Z
               exx
               ld   c,a             ; set N Z
               jp   (ix)

i_pha:         ld   a,b             ; A
               exx
               ld   (hl),a          ; push A
               dec  l               ; S--
               exx
               jp   (ix)

i_pla:         exx                  ; PLA
               inc  l               ; S++
               ld   a,(hl)          ; pop A
               exx
               ld   b,a             ; set A
               ld   c,a             ; set N Z
               jp   (ix)


i_dex:         dec  iyh             ; X--
               ld   c,iyh           ; set N Z
               jp   (ix)

i_dey:         dec  iyl             ; Y--
               ld   c,iyl           ; set N Z
               jp   (ix)

i_inx:         inc  iyh             ; X++
               ld   c,iyh           ; set N Z
               jp   (ix)

i_iny:         inc  iyl             ; Y++
               ld   c,iyl           ; set N Z
               jp   (ix)


i_txa:         ld   b,iyh           ; A=X
               ld   c,b             ; set N Z
               jp   (ix)

i_tya:         ld   b,iyl           ; A=Y
               ld   c,b             ; set N Z
               jp   (ix)

i_tax:         ld   iyh,b           ; X=A
               ld   c,b             ; set N Z
               jp   (ix)

i_tay:         ld   iyl,b           ; Y=A
               ld   c,b             ; set N Z
               jp   (ix)

i_txs:         ld   a,iyh           ; X
               exx
               ld   l,a             ; set S (no flags set)
               exx
               jp   (ix)

i_tsx:         exx
               ld   a,l             ; S
               exx
               ld   iyh,a           ; X=S
               ld   c,a             ; set N Z
               jp   (ix)


i_lda_ix:      ld   a,(de)          ; LDA ($nn,X)
               inc  de
               add  a,iyh           ; add X (may wrap in zero page)
               ld   l,a
               ld   h,0
               ld   a,(hl)
               inc  hl
               ld   h,(hl)
               ld   l,a
               ld   b,(hl)          ; set A
               ld   c,b             ; set N Z
               jp   (ix) ; zread_loop

i_lda_z:       ld   a,(de)          ; LDA $nn
               inc  de
               ld   l,a
               ld   h,0
               ld   b,(hl)          ; set A
               ld   c,b             ; set N Z
               jp   (ix) ; zread_loop

i_lda_a:       ex   de,hl           ; LDA $nnnn
               ld   e,(hl)
               inc  hl
               ld   d,(hl)
               inc  hl
               ex   de,hl
               ld   b,(hl)          ; set A
               ld   c,b             ; set N Z
               jp   (ix) ; read_loop

i_lda_iy:      ld   a,(de)          ; LDA ($nn),Y
               inc  de
               ld   l,a
               ld   h,0
               ld   a,iyl           ; Y
               add  a,(hl)
               inc  l               ; (may wrap in zero page)
               ld   h,(hl)
               ld   l,a
               ld   a,0
               adc  a,h
               ld   h,a
               ld   b,(hl)          ; set A
               ld   c,b             ; set N Z
               jp   (ix) ; read_loop

i_lda_zx:      ld   a,(de)          ; LDA $nn,X
               inc  de
               add  a,iyh           ; add X (may wrap in zero page)
               ld   l,a
               ld   h,0
               ld   b,(hl)          ; set A
               ld   c,b             ; set N Z
               jp   (ix) ; zread_loop

i_lda_ay:      ld   a,(de)          ; LDA $nnnn,Y
               inc  de
               add  a,iyl           ; add Y
               ld   l,a
               ld   a,(de)
               inc  de
               adc  a,0
               ld   h,a
               ld   b,(hl)          ; set A
               ld   c,b             ; set N Z
               jp   (ix) ; read_loop

i_lda_ax:      ld   a,(de)          ; LDA $nnnn,X
               inc  de
               add  a,iyh           ; add X
               ld   l,a
               ld   a,(de)
               inc  de
               adc  a,0
               ld   h,a
               ld   b,(hl)          ; set A
               ld   c,b             ; set N Z
               jp   (ix) ; read_loop

i_lda_i:       ld   a,(de)          ; LDA #$nn
               inc  de
               ld   b,a             ; set A
               ld   c,b             ; set N Z
               jp   (ix)


i_ldx_z:       ld   a,(de)          ; LDX $nn
               inc  de
               ld   l,a
               ld   h,0
               ld   c,(hl)          ; set N Z
               ld   iyh,c           ; set X
               jp   (ix) ; zread_loop

i_ldx_a:       ex   de,hl           ; LDX $nnnn
               ld   e,(hl)
               inc  hl
               ld   d,(hl)
               inc  hl
               ex   de,hl
               ld   c,(hl)          ; set N Z
               ld   iyh,c           ; set X
               jp   (ix) ; read_loop

i_ldx_zy:      ld   a,(de)          ; LDX $nn,Y
               inc  de
               add  a,iyl           ; add Y (may wrap in zero page)
               ld   l,a
               ld   h,0
               ld   c,(hl)          ; set N Z
               ld   iyh,c           ; set X
               jp   (ix) ; zread_loop

i_ldx_ay:      ld   a,(de)          ; LDX $nnnn,Y
               inc  de
               add  a,iyl           ; add Y
               ld   l,a
               ld   a,(de)
               inc  de
               adc  a,0
               ld   h,a
               ld   c,(hl)          ; set N Z
               ld   iyh,c           ; set X
               jp   (ix) ; read_loop

i_ldx_i:       ld   a,(de)          ; LDX #$nn
               inc  de
               ld   iyh,a           ; set X
               ld   c,a             ; set N Z
               jp   (ix)


i_ldy_z:       ld   a,(de)          ; LDY $nn
               inc  de
               ld   l,a
               ld   h,0
               ld   c,(hl)          ; set N Z
               ld   iyl,c           ; set Y
               jp   (ix) ; zread_loop

i_ldy_a:       ex   de,hl           ; LDY $nnnn
               ld   e,(hl)
               inc  hl
               ld   d,(hl)
               inc  hl
               ex   de,hl
               ld   c,(hl)          ; set N Z
               ld   iyl,c           ; set Y
               jp   (ix) ; read_loop

i_ldy_zx:      ld   a,(de)          ; LDY $nn,X
               inc  de
               add  a,iyh           ; add X (may wrap in zero page)
               ld   l,a
               ld   h,0
               ld   c,(hl)          ; set N Z
               ld   iyl,c           ; set Y
               jp   (ix) ; zread_loop

i_ldy_ax:      ld   a,(de)          ; LDY $nnnn,X
               inc  de
               add  a,iyh           ; add X
               ld   l,a
               ld   a,(de)
               inc  de
               adc  a,0
               ld   h,a
               ld   c,(hl)          ; set N Z
               ld   iyl,c           ; set Y
               jp   (ix) ; read_loop

i_ldy_i:       ld   a,(de)          ; LDY #$nn
               inc  de
               ld   c,a             ; set N Z
               ld   iyl,c           ; set Y
               jp   (ix)


i_sta_ix:      ld   a,(de)          ; STA ($xx,X)
               inc  de
               add  a,iyh           ; add X (may wrap in zero page)
               ld   l,a
               ld   h,0
               ld   a,(hl)
               inc  hl
               ld   h,(hl)
               ld   l,a
               ld   (hl),b          ; store A
               jp   (ix) ; zwrite_loop

i_sta_z:       ld   a,(de)          ; STA $nn
               inc  de
               ld   l,a
               ld   h,0
               ld   (hl),b          ; store A
               jp   (ix) ; zwrite_loop

i_sta_iy:      ld   a,(de)          ; STA ($nn),Y
               inc  de
               ld   l,a
               ld   h,0
               ld   a,iyl           ; Y
               add  a,(hl)
               inc  l
               ld   h,(hl)
               ld   l,a
               ld   a,0
               adc  a,h
               ld   h,a
               ld   (hl),b          ; store A
               jp   write_loop

i_sta_zx:      ld   a,(de)          ; STA $nn,X
               inc  de
               add  a,iyh           ; add X (may wrap in zero page)
               ld   l,a
               ld   h,0
               ld   (hl),b          ; store A
               jp   (ix) ; zwrite_loop

i_sta_ay:      ld   a,(de)          ; STA $nnnn,Y
               inc  de
               add  a,iyl           ; add Y
               ld   l,a
               ld   a,(de)
               inc  de
               adc  a,0
               ld   h,a
               ld   (hl),b          ; store A
               jp   write_loop

i_sta_ax:      ld   a,(de)          ; STA $nnnn,X
               inc  de
               add  a,iyh           ; add X
               ld   l,a
               ld   a,(de)
               inc  de
               adc  a,0
               ld   h,a
               ld   (hl),b          ; store A
               jp   write_loop

i_sta_a:       ex   de,hl           ; STA $nnnn
               ld   e,(hl)
               inc  hl
               ld   d,(hl)
               inc  hl
               ex   de,hl
               ld   (hl),b          ; store A
               jp   write_loop


i_stx_z:       ld   a,(de)          ; STX $nn
               inc  de
               ld   l,a
               ld   h,0
               ld   a,iyh           ; X
               ld   (hl),a
               jp   (ix) ; zwrite_loop

i_stx_zy:      ld   a,(de)          ; STX $nn,Y
               inc  de
               add  a,iyl           ; add Y (may wrap in zero page)
               ld   l,a
               ld   h,0
               ld   a,iyh           ; X
               ld   (hl),a
               jp   (ix) ; zwrite_loop

i_stx_a:       ex   de,hl           ; STX $nnnn
               ld   e,(hl)
               inc  hl
               ld   d,(hl)
               inc  hl
               ex   de,hl
               ld   a,iyh           ; X
               ld   (hl),a
               jp   write_loop


i_sty_z:       ld   a,(de)          ; STY $nn
               inc  de
               ld   l,a
               ld   h,0
               ld   a,iyl           ; Y
               ld   (hl),a
               jp   (ix) ; zwrite_loop

i_sty_zx:      ld   a,(de)          ; STY $nn,X
               inc  de
               add  a,iyh           ; add X (may wrap in zero page)
               ld   l,a
               ld   h,0
               ld   a,iyl           ; Y
               ld   (hl),a
               jp   (ix) ; zwrite_loop

i_sty_a:       ex   de,hl           ; STY $nnnn
               ld   e,(hl)
               inc  hl
               ld   d,(hl)
               inc  hl
               ex   de,hl
               ld   a,iyl           ; Y
               ld   (hl),a
               jp   write_loop


i_stz_zx:      ld   a,(de)          ; STZ $nn,X
               inc  de
               add  a,iyh           ; add X (may wrap in zero page)
               ld   l,a
               ld   h,0
               ld   (hl),h
               jp   (ix) ; zwrite_loop

i_stz_ax:      ld   a,(de)          ; STZ $nnnn,X
               inc  de
               add  a,iyh           ; add X
               ld   l,a
               ld   a,(de)
               inc  de
               adc  a,0
               ld   h,a
               ld   (hl),0
               jp   write_loop

i_stz_a:       ex   de,hl           ; STZ $nnnn
               ld   e,(hl)
               inc  hl
               ld   d,(hl)
               inc  hl
               ex   de,hl
               ld   (hl),0
               jp   write_loop


i_adc_ix:      ld   a,(de)          ; ADX ($xx,X)
               inc  de
               add  a,iyh           ; add X (may wrap in zero page)
               ld   l,a
               ld   h,0
               ld   a,(hl)
               inc  hl
               ld   h,(hl)
               ld   l,a
               jp   i_adc

i_adc_z:       ld   a,(de)          ; ADC $nn
               inc  de
               ld   l,a
               ld   h,0
               jp   i_adc

i_adc_a:       ex   de,hl           ; ADC $nnnn
               ld   e,(hl)
               inc  hl
               ld   d,(hl)
               inc  hl
               ex   de,hl
               jp   i_adc

i_adc_zx:      ld   a,(de)          ; ADC $nn,X
               inc  de
               add  a,iyh           ; add X (may wrap in zero page)
               ld   l,a
               ld   h,0
               jp   i_adc

i_adc_ay:      ld   a,(de)          ; ADC $nnnn,Y
               inc  de
               add  a,iyl           ; add Y
               ld   l,a
               ld   a,(de)
               inc  de
               adc  a,0
               ld   h,a
               jp   i_adc

i_adc_ax:      ld   a,(de)          ; ADC $nnnn,X
               inc  de
               add  a,iyh           ; add X
               ld   l,a
               ld   a,(de)
               inc  de
               adc  a,0
               ld   h,a
               jp   i_adc

i_adc_iy:      ld   a,(de)          ; ADC ($nn),Y
               inc  de
               ld   l,a
               ld   h,0
               ld   a,iyl           ; Y
               add  a,(hl)
               inc  l               ; (may wrap in zero page)
               ld   h,(hl)
               ld   l,a
               ld   a,0
               adc  a,h
               ld   h,a
               jp   i_adc

i_adc_i:       ld   h,d
               ld   l,e
               inc  de
i_adc:         ex   af,af'          ; carry
               ld   a,b             ; A
               adc  a,(hl)          ; A+M+C
adc_daa:       nop
               ld   b,a             ; set A
               ld   c,a             ; set N Z
               exx
               jp   pe,adcsbc_v
               ld   e,%00000000
               exx
               ex   af,af'          ; set carry
               jp   (ix) ; read_loop
adcsbc_v:      ld   e,%01000000
               exx
               ex   af,af'          ; set carry
               jp   (ix) ; read_loop


i_sbc_ix:      ld   a,(de)          ; SBC ($xx,X)
               inc  de
               add  a,iyh           ; add X (may wrap in zero page)
               ld   l,a
               ld   h,0
               ld   a,(hl)
               inc  hl
               ld   h,(hl)
               ld   l,a
               jp   i_sbc

i_sbc_z:       ld   a,(de)          ; SBC $nn
               inc  de
               ld   l,a
               ld   h,0
               jp   i_sbc

i_sbc_a:       ex   de,hl           ; SBC $nnnn
               ld   e,(hl)
               inc  hl
               ld   d,(hl)
               inc  hl
               ex   de,hl
               jp   i_sbc

i_sbc_zx:      ld   a,(de)          ; SBC $nn,X
               inc  de
               add  a,iyh           ; add X (may wrap in zero page)
               ld   l,a
               ld   h,0
               jp   i_sbc

i_sbc_ay:      ld   a,(de)          ; SBC $nnnn,Y
               inc  de
               add  a,iyl           ; add Y
               ld   l,a
               ld   a,(de)
               inc  de
               adc  a,0
               ld   h,a
               jp   i_sbc

i_sbc_ax:      ld   a,(de)          ; SBC $nnnn,X
               inc  de
               add  a,iyh           ; add X
               ld   l,a
               ld   a,(de)
               inc  de
               adc  a,0
               ld   h,a
               jp   i_sbc

i_sbc_iy:      ld   a,(de)          ; SBC ($nn),Y
               inc  de
               ld   l,a
               ld   h,0
               ld   a,iyl           ; Y
               add  a,(hl)
               inc  l               ; (may wrap in zero page)
               ld   h,(hl)
               ld   l,a
               ld   a,0
               adc  a,h
               ld   h,a
               jp   i_sbc

i_sbc_i:       ld   h,d
               ld   l,e
               inc  de
i_sbc:         ex   af,af'          ; carry
               ccf                  ; uses inverted carry
               ld   a,b
               sbc  a,(hl)          ; A-M-(1-C)
sbc_daa:       nop
               ld   b,a             ; set A
               ld   c,a             ; set N Z
               ccf                  ; no carry for overflow
               exx
               jp   pe,adcsbc_v
               ld   e,%00000000
               exx
               ex   af,af'          ; set carry
               jp   (ix) ; read_loop


i_and_ix:      ld   a,(de)          ; AND ($xx,X)
               inc  de
               add  a,iyh           ; add X (may wrap in zero page)
               ld   l,a
               ld   h,0
               ld   a,(hl)
               inc  hl
               ld   h,(hl)
               ld   l,a
               ld   a,b             ; A
               and  (hl)            ; A&x
               ld   b,a             ; set A
               ld   c,a             ; set N Z
               jp   (ix) ; read_loop

i_and_z:       ld   a,(de)          ; AND $nn
               inc  de
               ld   l,a
               ld   h,0
               ld   a,b             ; A
               and  (hl)            ; A&x
               ld   b,a             ; set A
               ld   c,a             ; set N Z
               jp   (ix) ; read_loop

i_and_a:       ex   de,hl           ; AND $nnnn
               ld   e,(hl)
               inc  hl
               ld   d,(hl)
               inc  hl
               ex   de,hl
               ld   a,b             ; A
               and  (hl)            ; A&x
               ld   b,a             ; set A
               ld   c,a             ; set N Z
               jp   (ix) ; read_loop

i_and_zx:      ld   a,(de)          ; AND $nn,X
               inc  de
               add  a,iyh           ; add X (may wrap in zero page)
               ld   l,a
               ld   h,0
               ld   a,b             ; A
               and  (hl)            ; A&x
               ld   b,a             ; set A
               ld   c,a             ; set N Z
               jp   (ix) ; read_loop

i_and_ay:      ld   a,(de)          ; AND $nnnn,Y
               inc  de
               add  a,iyl           ; add Y
               ld   l,a
               ld   a,(de)
               inc  de
               adc  a,0
               ld   h,a
               ld   a,b             ; A
               and  (hl)            ; A&x
               ld   b,a             ; set A
               ld   c,a             ; set N Z
               jp   (ix) ; read_loop

i_and_ax:      ld   a,(de)          ; AND $nnnn,X
               inc  de
               add  a,iyh           ; add X
               ld   l,a
               ld   a,(de)
               inc  de
               adc  a,0
               ld   h,a
               ld   a,b             ; A
               and  (hl)            ; A&x
               ld   b,a             ; set A
               ld   c,a             ; set N Z
               jp   (ix) ; read_loop

i_and_iy:      ld   a,(de)          ; AND ($nn),Y
               inc  de
               ld   l,a
               ld   h,0
               ld   a,iyl           ; Y
               add  a,(hl)
               inc  l               ; (may wrap in zero page)
               ld   h,(hl)
               ld   l,a
               ld   a,0
               adc  a,h
               ld   h,a
               ld   a,b             ; A
               and  (hl)            ; A&x
               ld   b,a             ; set A
               ld   c,a             ; set N Z
               jp   (ix) ; read_loop

i_and_i:       ld   h,d
               ld   l,e
               inc  de
               ld   a,b             ; A
               and  (hl)            ; A&x
               ld   b,a             ; set A
               ld   c,a             ; set N Z
               jp   (ix) ; read_loop


i_eor_ix:      ld   a,(de)          ; EOR ($xx,X)
               inc  de
               add  a,iyh           ; add X (may wrap in zero page)
               ld   l,a
               ld   h,0
               ld   a,(hl)
               inc  hl
               ld   h,(hl)
               ld   l,a
               ld   a,b             ; A
               xor  (hl)            ; A^x
               ld   b,a             ; set A
               ld   c,a             ; set N Z
               jp   (ix) ; read_loop

i_eor_z:       ld   a,(de)          ; EOR $nn
               inc  de
               ld   l,a
               ld   h,0
               ld   a,b             ; A
               xor  (hl)            ; A^x
               ld   b,a             ; set A
               ld   c,a             ; set N Z
               jp   (ix) ; read_loop

i_eor_a:       ex   de,hl           ; EOR $nnnn
               ld   e,(hl)
               inc  hl
               ld   d,(hl)
               inc  hl
               ex   de,hl
               ld   a,b             ; A
               xor  (hl)            ; A^x
               ld   b,a             ; set A
               ld   c,a             ; set N Z
               jp   (ix) ; read_loop

i_eor_zx:      ld   a,(de)          ; EOR $nn,X
               inc  de
               add  a,iyh           ; add X (may wrap in zero page)
               ld   l,a
               ld   h,0
               ld   a,b             ; A
               xor  (hl)            ; A^x
               ld   b,a             ; set A
               ld   c,a             ; set N Z
               jp   (ix) ; read_loop

i_eor_ay:      ld   a,(de)          ; EOR $nnnn,Y
               inc  de
               add  a,iyl           ; add Y
               ld   l,a
               ld   a,(de)
               inc  de
               adc  a,0
               ld   h,a
               ld   a,b             ; A
               xor  (hl)            ; A^x
               ld   b,a             ; set A
               ld   c,a             ; set N Z
               jp   (ix) ; read_loop

i_eor_ax:      ld   a,(de)          ; EOR $nnnn,X
               inc  de
               add  a,iyh           ; add X
               ld   l,a
               ld   a,(de)
               inc  de
               adc  a,0
               ld   h,a
               ld   a,b             ; A
               xor  (hl)            ; A^x
               ld   b,a             ; set A
               ld   c,a             ; set N Z
               jp   (ix) ; read_loop

i_eor_iy:      ld   a,(de)          ; EOR ($nn),Y
               inc  de
               ld   l,a
               ld   h,0
               ld   a,iyl           ; Y
               add  a,(hl)
               inc  l               ; (may wrap in zero page)
               ld   h,(hl)
               ld   l,a
               ld   a,0
               adc  a,h
               ld   h,a
               ld   a,b             ; A
               xor  (hl)            ; A^x
               ld   b,a             ; set A
               ld   c,a             ; set N Z
               jp   (ix) ; read_loop

i_eor_i:       ld   h,d
               ld   l,e
               inc  de
               ld   a,b             ; A
               xor  (hl)            ; A^x
               ld   b,a             ; set A
               ld   c,a             ; set N Z
               jp   (ix) ; read_loop


i_ora_ix:      ld   a,(de)          ; ORA ($xx,X)
               inc  de
               add  a,iyh           ; add X (may wrap in zero page)
               ld   l,a
               ld   h,0
               ld   a,(hl)
               inc  hl
               ld   h,(hl)
               ld   l,a
               ld   a,b             ; A
               or   (hl)            ; A|x
               ld   b,a             ; set A
               ld   c,a             ; set N Z
               jp   (ix) ; read_loop

i_ora_z:       ld   a,(de)          ; ORA $nn
               inc  de
               ld   l,a
               ld   h,0
               ld   a,b             ; A
               or   (hl)            ; A|x
               ld   b,a             ; set A
               ld   c,a             ; set N Z
               jp   (ix) ; read_loop

i_ora_a:       ex   de,hl           ; ORA $nnnn
               ld   e,(hl)
               inc  hl
               ld   d,(hl)
               inc  hl
               ex   de,hl
               ld   a,b             ; A
               or   (hl)            ; A|x
               ld   b,a             ; set A
               ld   c,a             ; set N Z
               jp   (ix) ; read_loop

i_ora_zx:      ld   a,(de)          ; ORA $nn,X
               inc  de
               add  a,iyh           ; add X (may wrap in zero page)
               ld   l,a
               ld   h,0
               ld   a,b             ; A
               or   (hl)            ; A|x
               ld   b,a             ; set A
               ld   c,a             ; set N Z
               jp   (ix) ; read_loop

i_ora_ay:      ld   a,(de)          ; ORA $nnnn,Y
               inc  de
               add  a,iyl           ; add Y
               ld   l,a
               ld   a,(de)
               inc  de
               adc  a,0
               ld   h,a
               ld   a,b             ; A
               or   (hl)            ; A|x
               ld   b,a             ; set A
               ld   c,a             ; set N Z
               jp   (ix) ; read_loop

i_ora_ax:      ld   a,(de)          ; ORA $nnnn,X
               inc  de
               add  a,iyh           ; add X
               ld   l,a
               ld   a,(de)
               inc  de
               adc  a,0
               ld   h,a
               ld   a,b             ; A
               or   (hl)            ; A|x
               ld   b,a             ; set A
               ld   c,a             ; set N Z
               jp   (ix) ; read_loop

i_ora_iy:      ld   a,(de)          ; ORA ($nn),Y
               inc  de
               ld   l,a
               ld   h,0
               ld   a,iyl           ; Y
               add  a,(hl)
               inc  l               ; (may wrap in zero page)
               ld   h,(hl)
               ld   l,a
               ld   a,0
               adc  a,h
               ld   h,a
               ld   a,b             ; A
               or   (hl)            ; A|x
               ld   b,a             ; set A
               ld   c,a             ; set N Z
               jp   (ix) ; read_loop

i_ora_i:       ld   h,d
               ld   l,e
               inc  de
               ld   a,b             ; A
               or   (hl)            ; A|x
               ld   b,a             ; set A
               ld   c,a             ; set N Z
               jp   (ix) ; read_loop


i_cmp_ix:      ld   a,(de)          ; CMP ($xx,X)
               inc  de
               add  a,iyh           ; add X (may wrap in zero page)
               ld   l,a
               ld   h,0
               ld   a,(hl)
               inc  hl
               ld   h,(hl)
               ld   l,a
               ex   af,af'          ; carry
               ld   a,b             ; A
               sub  (hl)            ; A-x (result discarded)
               ld   c,a             ; set N Z
               ccf
               ex   af,af'          ; set carry
               jp   (ix) ; read_loop

i_cmp_z:       ld   a,(de)          ; CMP $nn
               inc  de
               ld   l,a
               ld   h,0
               ex   af,af'          ; carry
               ld   a,b             ; A
               sub  (hl)            ; A-x (result discarded)
               ld   c,a             ; set N Z
               ccf
               ex   af,af'          ; set carry
               jp   (ix) ; read_loop

i_cmp_a:       ex   de,hl           ; CMP $nnnn
               ld   e,(hl)
               inc  hl
               ld   d,(hl)
               inc  hl
               ex   de,hl
               ex   af,af'          ; carry
               ld   a,b             ; A
               sub  (hl)            ; A-x (result discarded)
               ld   c,a             ; set N Z
               ccf
               ex   af,af'          ; set carry
               jp   (ix) ; read_loop

i_cmp_zx:      ld   a,(de)          ; CMP $nn,X
               inc  de
               add  a,iyh           ; add X (may wrap in zero page)
               ld   l,a
               ld   h,0
               ex   af,af'          ; carry
               ld   a,b             ; A
               sub  (hl)            ; A-x (result discarded)
               ld   c,a             ; set N Z
               ccf
               ex   af,af'          ; set carry
               jp   (ix) ; read_loop

i_cmp_ay:      ld   a,(de)          ; CMP $nnnn,Y
               inc  de
               add  a,iyl           ; add Y
               ld   l,a
               ld   a,(de)
               inc  de
               adc  a,0
               ld   h,a
               ex   af,af'          ; carry
               ld   a,b             ; A
               sub  (hl)            ; A-x (result discarded)
               ld   c,a             ; set N Z
               ccf
               ex   af,af'          ; set carry
               jp   (ix) ; read_loop

i_cmp_ax:      ld   a,(de)          ; CMP $nnnn,X
               inc  de
               add  a,iyh           ; add X
               ld   l,a
               ld   a,(de)
               inc  de
               adc  a,0
               ld   h,a
               ex   af,af'          ; carry
               ld   a,b             ; A
               sub  (hl)            ; A-x (result discarded)
               ld   c,a             ; set N Z
               ccf
               ex   af,af'          ; set carry
               jp   (ix) ; read_loop

i_cmp_iy:      ld   a,(de)          ; CMP ($nn),Y
               inc  de
               ld   l,a
               ld   h,0
               ld   a,iyl           ; Y
               add  a,(hl)
               inc  l               ; (may wrap in zero page)
               ld   h,(hl)
               ld   l,a
               ld   a,0
               adc  a,h
               ld   h,a
               ex   af,af'          ; carry
               ld   a,b             ; A
               sub  (hl)            ; A-x (result discarded)
               ld   c,a             ; set N Z
               ccf
               ex   af,af'          ; set carry
               jp   (ix) ; read_loop

i_cmp_i:       ld   h,d
               ld   l,e
               inc  de
               ex   af,af'          ; carry
               ld   a,b             ; A
               sub  (hl)            ; A-x (result discarded)
               ld   c,a             ; set N Z
               ccf
               ex   af,af'          ; set carry
               jp   (ix) ; read_loop


i_cpx_z:       ld   a,(de)          ; CPX $nn
               inc  de
               ld   l,a
               ld   h,0
               ex   af,af'          ; carry
               ld   a,iyh           ; X
               sub  (hl)            ; X-x (result discarded)
               ld   c,a             ; set N Z
               ccf
               ex   af,af'          ; set carry
               jp   (ix) ; read_loop

i_cpx_a:       ex   de,hl           ; CPX $nnnn
               ld   e,(hl)
               inc  hl
               ld   d,(hl)
               inc  hl
               ex   de,hl
               ex   af,af'          ; carry
               ld   a,iyh           ; X
               sub  (hl)            ; X-x (result discarded)
               ld   c,a             ; set N Z
               ccf
               ex   af,af'          ; set carry
               jp   (ix) ; read_loop

i_cpx_i:       ld   h,d
               ld   l,e
               inc  de
               ex   af,af'          ; carry
               ld   a,iyh           ; X
               sub  (hl)            ; X-x (result discarded)
               ld   c,a             ; set N Z
               ccf
               ex   af,af'          ; set carry
               jp   (ix) ; read_loop


i_cpy_z:       ld   a,(de)          ; CPY $nn
               inc  de
               ld   l,a
               ld   h,0
               ex   af,af'          ; carry
               ld   a,iyl           ; Y
               sub  (hl)            ; Y-x (result discarded)
               ld   c,a             ; set N Z
               ccf
               ex   af,af'          ; set carry
               jp   (ix) ; read_loop

i_cpy_a:       ex   de,hl           ; CPY $nnnn
               ld   e,(hl)
               inc  hl
               ld   d,(hl)
               inc  hl
               ex   de,hl
               ex   af,af'          ; carry
               ld   a,iyl           ; Y
               sub  (hl)            ; Y-x (result discarded)
               ld   c,a             ; set N Z
               ccf
               ex   af,af'          ; set carry
               jp   (ix) ; read_loop

i_cpy_i:       ld   h,d
               ld   l,e
               inc  de
               ex   af,af'          ; carry
               ld   a,iyl           ; Y
               sub  (hl)            ; Y-x (result discarded)
               ld   c,a             ; set N Z
               ccf
               ex   af,af'          ; set carry
               jp   (ix) ; read_loop


i_dec_z:       ld   a,(de)          ; DEC $nn
               inc  de
               ld   l,a
               ld   h,0
               dec  (hl)            ; zero-page--
               ld   c,(hl)          ; set N Z
               jp   (ix) ; zread_write_loop

i_dec_zx:      ld   a,(de)          ; DEC $nn,X
               inc  de
               add  a,iyh           ; add X (may wrap in zero page)
               ld   l,a
               ld   h,0
               dec  (hl)            ; zero-page--
               ld   c,(hl)          ; set N Z
               jp   (ix) ; zread_write_loop

i_dec_a:       ex   de,hl           ; DEC $nnnn
               ld   e,(hl)
               inc  hl
               ld   d,(hl)
               inc  hl
               ex   de,hl
               dec  (hl)            ; mem--
               ld   c,(hl)          ; set N Z
               jp   read_write_loop

i_dec_ax:      ld   a,(de)          ; DEC $nnnn,X
               inc  de
               add  a,iyh           ; add X
               ld   l,a
               ld   a,(de)
               inc  de
               adc  a,0
               ld   h,a
               dec  (hl)            ; mem--
               ld   c,(hl)          ; set N Z
               jp   read_write_loop


i_inc_z:       ld   a,(de)          ; INC $nn
               inc  de
               ld   l,a
               ld   h,0
               inc  (hl)            ; zero-page++
               ld   c,(hl)          ; set N Z
               jp   (ix) ; zread_write_loop

i_inc_zx:      ld   a,(de)          ; INC $nn,X
               inc  de
               add  a,iyh           ; add X (may wrap in zero page)
               ld   l,a
               ld   h,0
               inc  (hl)            ; zero-page++
               ld   c,(hl)          ; set N Z
               jp   (ix) ; zread_write_loop

i_inc_a:       ex   de,hl           ; INC $nnnn
               ld   e,(hl)
               inc  hl
               ld   d,(hl)
               inc  hl
               ex   de,hl
               inc  (hl)            ; mem++
               ld   c,(hl)          ; set N Z
               jp   read_write_loop

i_inc_ax:      ld   a,(de)          ; INC $nnnn,X
               inc  de
               add  a,iyh           ; add X
               ld   l,a
               ld   a,(de)
               inc  de
               adc  a,0
               ld   h,a
               inc  (hl)            ; mem++
               ld   c,(hl)          ; set N Z
               jp   read_write_loop


i_asl_z:       ld   a,(de)          ; ASL $nn
               inc  de
               ld   l,a
               ld   h,0
               ex   af,af'
               sla  (hl)            ; x << 1
               ld   c,(hl)          ; set N Z
               ex   af,af'          ; set carry
               jp   write_loop

i_asl_zx:      ld   a,(de)          ; ASL $nn,X
               inc  de
               add  a,iyh           ; add X (may wrap in zero page)
               ld   l,a
               ld   h,0
               ex   af,af'
               sla  (hl)            ; x << 1
               ld   c,(hl)          ; set N Z
               ex   af,af'          ; set carry
               jp   write_loop

i_asl_a:       ex   de,hl           ; ASL $nnnn
               ld   e,(hl)
               inc  hl
               ld   d,(hl)
               inc  hl
               ex   de,hl
               ex   af,af'
               sla  (hl)            ; x << 1
               ld   c,(hl)          ; set N Z
               ex   af,af'          ; set carry
               jp   write_loop

i_asl_ax:      ld   a,(de)          ; ASL $nnnn,X
               inc  de
               add  a,iyh           ; add X
               ld   l,a
               ld   a,(de)
               inc  de
               adc  a,0
               ld   h,a
               ex   af,af'
               sla  (hl)            ; x << 1
               ld   c,(hl)          ; set N Z
               ex   af,af'          ; set carry
               jp   write_loop

i_asl_acc:     ex   af,af'
               sla  b               ; A << 1
               ld   c,b             ; set N Z
               ex   af,af'          ; set carry
               jp   (ix)


i_lsr_z:       ld   a,(de)          ; LSR $nn
               inc  de
               ld   l,a
               ld   h,0
               ex   af,af'
               srl  (hl)            ; x >> 1
               ld   c,(hl)          ; set N Z
               ex   af,af'          ; set carry
               jp   write_loop

i_lsr_zx:      ld   a,(de)          ; LSR $nn,X
               inc  de
               add  a,iyh           ; add X (may wrap in zero page)
               ld   l,a
               ld   h,0
               ex   af,af'
               srl  (hl)            ; x >> 1
               ld   c,(hl)          ; set N Z
               ex   af,af'          ; set carry
               jp   write_loop

i_lsr_a:       ex   de,hl           ; LSR $nnnn
               ld   e,(hl)
               inc  hl
               ld   d,(hl)
               inc  hl
               ex   de,hl
               ex   af,af'
               srl  (hl)            ; x >> 1
               ld   c,(hl)          ; set N Z
               ex   af,af'          ; set carry
               jp   write_loop

i_lsr_ax:      ld   a,(de)          ; LSR $nnnn,X
               inc  de
               add  a,iyh           ; add X
               ld   l,a
               ld   a,(de)
               inc  de
               adc  a,0
               ld   h,a
               ex   af,af'
               srl  (hl)            ; x >> 1
               ld   c,(hl)          ; set N Z
               ex   af,af'          ; set carry
               jp   write_loop

i_lsr_acc:     ex   af,af'
               srl  b               ; A >> 1
               ld   c,b             ; set N Z
               ex   af,af'          ; set carry
               jp   (ix)


i_rol_z:       ld   a,(de)          ; ROL $nn
               inc  de
               ld   l,a
               ld   h,0
               ex   af,af'
               rl   (hl)            ; x << 1
               ld   c,(hl)          ; set N Z
               ex   af,af'          ; set carry
               jp   write_loop

i_rol_zx:      ld   a,(de)          ; ROL $nn,X
               inc  de
               add  a,iyh           ; add X (may wrap in zero page)
               ld   l,a
               ld   h,0
               ex   af,af'
               rl   (hl)            ; x << 1
               ld   c,(hl)          ; set N Z
               ex   af,af'          ; set carry
               jp   write_loop

i_rol_a:       ex   de,hl           ; ROL $nnnn
               ld   e,(hl)
               inc  hl
               ld   d,(hl)
               inc  hl
               ex   de,hl
               ex   af,af'
               rl   (hl)            ; x << 1
               ld   c,(hl)          ; set N Z
               ex   af,af'          ; set carry
               jp   write_loop

i_rol_ax:      ld   a,(de)          ; ROL $nnnn,X
               inc  de
               add  a,iyh           ; add X
               ld   l,a
               ld   a,(de)
               inc  de
               adc  a,0
               ld   h,a
               ex   af,af'
               rl   (hl)            ; x << 1
               ld   c,(hl)          ; set N Z
               ex   af,af'          ; set carry
               jp   write_loop

i_rol_acc:     ex   af,af'
               rl   b
               ld   c,b             ; set N Z
               ex   af,af'          ; set carry
               jp   (ix)


i_ror_z:       ld   a,(de)          ; ROR $nn
               inc  de
               ld   l,a
               ld   h,0
               ex   af,af'
               rr   (hl)            ; x >> 1
               ld   c,(hl)          ; set N Z
               ex   af,af'          ; set carry
               jp   write_loop

i_ror_zx:      ld   a,(de)          ; ROR $nn,X
               inc  de
               add  a,iyh           ; add X (may wrap in zero page)
               ld   l,a
               ld   h,0
               ex   af,af'
               rr   (hl)            ; x >> 1
               ld   c,(hl)          ; set N Z
               ex   af,af'          ; set carry
               jp   write_loop

i_ror_a:       ex   de,hl           ; ROR $nnnn
               ld   e,(hl)
               inc  hl
               ld   d,(hl)
               inc  hl
               ex   de,hl
               ex   af,af'
               rr   (hl)            ; x >> 1
               ld   c,(hl)          ; set N Z
               ex   af,af'          ; set carry
               jp   write_loop

i_ror_ax:      ld   a,(de)          ; ROR $nnnn,X
               inc  de
               add  a,iyh           ; add X
               ld   l,a
               ld   a,(de)
               inc  de
               adc  a,0
               ld   h,a
               ex   af,af'
               rr   (hl)            ; x >> 1
               ld   c,(hl)          ; set N Z
               ex   af,af'          ; set carry
               jp   write_loop

i_ror_acc:     ex   af,af'
               rr   b
               ld   c,b             ; set N Z
               ex   af,af'          ; set carry
               jp   (ix)


i_bit_z:       ld   a,(de)          ; BIT $nn
               inc  de
               ld   l,a
               ld   h,0
               jp   i_bit

i_bit_zx:      ld   a,(de)          ; BIT $nn,X
               inc  de
               add  a,iyh           ; add X (may wrap in zero page)
               ld   l,a
               ld   h,0
               jp   i_bit

i_bit_a:       ex   de,hl           ; BIT $nnnn
               ld   e,(hl)
               inc  hl
               ld   d,(hl)
               inc  hl
               ex   de,hl
               jp   i_bit

i_bit_ax:      ld   a,(de)          ; BIT $nnnn,X
               inc  de
               add  a,iyh           ; add X
               ld   l,a
               ld   a,(de)
               inc  de
               adc  a,0
               ld   h,a
               jp   i_bit

i_bit_i:       ld   h,d             ; BIT #$nn
               ld   l,e
               inc  de
i_bit:         ld   c,(hl)          ; x
               ld   a,c
               and  %01000000       ; V flag from bit 6 of x
               exx
               ld   e,a             ; set V
               exx
               ld   a,(de)
               and  %11011111
               cp   &d0             ; BNE or BEQ next?
               jr   z,bit_setz
               ld   c,(hl)          ; set N
               jp   (ix) ; read_loop
bit_setz:      ld   a,b             ; A
               and  c               ; perform BIT test
               ld   c,a             ; set Z
               jp   (ix) ; read_loop

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

gap3          equ  &dc00-$        ; error if previous code is
               defs gap3           ; too big for available gap!

               defs 16             ; CIA #1 (keyboard, joystick, mouse, tape, IRQ)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; SID interface functions

sid_reset:
               ld   hl,last_regs
               ld   d,0
               ld   b,25           ; 25 registers to write
reset_loop:
               ld   (hl),d         ; remember new value
               inc  hl
               djnz reset_loop  ; loop until all reset

               xor  a
               ld   (last_regs+&04),a   ; control for voice 1
               ld   (last_regs+&0b),a   ; control for voice 2
               ld   (last_regs+&12),a   ; control for voice 3

               ; Reiniciamos los registros del SID (hardware)
               ld   bc,&FF60
               ld   d,0
               ld   a,&18
bucle          out  (c),d
               inc  c
               dec  a
               jr   nz,bucle
               ret

leds          defb 0

sid_update:

               ex   de,hl          ; switch new values to DE
;               ld   c,&d4          ; SID interface base port
               ld   c,&c0          ; Speak & SID interface base port &fac0 - &fadf 

               ld   hl,25          ; control 1 changes offset
               add  hl,de
               ld   a,(hl)         ; fetch changes
               and  a
               jr   z,control2     ; skip if nothing changed
               ld   (hl),0         ; reset changes for next time
               ld   hl,&04         ; new register 4 offset
               ld   b,l            ; SID register 4
               add  hl,de
               xor  (hl)           ; toggle changed bits  

               push af                
	       and 1
               ld hl, leds
               ld (hl), a
               pop af 
             
               ld   (last_regs+&04),a ; update last reg value

control2:      ld   hl,26          ; control 2 changes offset
               add  hl,de
               ld   a,(hl)
               and  a
               jr   z,control3     ; skip if no changes
               ld   (hl),0
               ld   hl,&0b
               ld   b,l            ; SID register 11
               add  hl,de
               xor  (hl)         

               push af    
	       and 1                 
               sla a
               ld hl, leds
               xor (hl) 
               ld (hl), a              
               pop af 

	       ld   (last_regs+&0b),a

control3:      ld   hl,27          ; control 3 changes offset
               add  hl,de
               ld   a,(hl)
               and  a
               jr   z,control_done ; skip if no changes
               ld   (hl),0
               ld   hl,&12
               ld   b,l            ;  SID register 18
               add  hl,de
               xor  (hl)          
   
               push af          
	       and 1                 
               sla a
               sla a
	       ld hl, leds
               xor (hl) 
               ld (hl), a      
               pop af 

              ld   (last_regs+&12),a

control_done: push de 

              ld a,(last_regs+22) ; filter reg, d4 - d7 resonance. use d4 
	      push de
              pop hl ; ld hl, de
              ld de, 22
              add hl, de
              ld b,(hl) 
              cp b
              jr z, eqfilter
              ld a, 8 
              jr ledout 
eqfilter: 
              ld a, 0
ledout:                             
              ld hl,leds
	      xor (hl)              
              ld bc,&fbee 
	      out (c), a  

              pop de

               ld   hl,last_regs   ; previous register values
               ld   b,0            ; start with register 0
out_loop:      ld   a,(de)         ; new register value
               cp   (hl)           ; compare with previous value
               jr   z,sid_skip     ; skip if no change
               push bc
               push af
               ld   a,b
	       add  &c0 ; Speak&SID register address = &c0 + B (Reg Number)
               ; add  a,c
               ld   c,a
               pop  af
               ld   b,&fa          ; SPEAK & SID &fac0 - &fadf 
               out  (c),a          ; write value
               pop  bc
               ld   (hl),a         ; store new value
sid_skip:      inc  hl
               inc  de
               inc  b              ; next register
               ld   a,b
               cp   25             ; 25 registers to write
               jr   nz,out_loop    ; loop until all updated
               ld   hl,7
               add  hl,de          ; make up to a block of 32
               ret

;**//DADMAN
set_speed:
               ld   hl,(c64_cia_timer) ; C64 CIA#1 timer frequency
               ld   a,h
               or   l
               jr   nz,use_timer    ; use if non-zero
               ld   a,(ntsc_tune)   ; SID header said NTSC tune?
               and  a
               jr   nz,set_50hz     ; use 60Hz for NTSC


set_50hz:      ld   a,&05
set_wait:      ld   (line_step1+1),a
               ld   (int_val+1),a
set_exit:      ret

set_100hz:     ld   a,&02
               jr   set_wait

; 985248.4Hz / HL = playback frequency in Hz
use_timer:     ld   a,h
               cp   &18             ; 160Hz
               jr   c,bad_timer     ; reject >160Hz
               cp   &33             ; 80Hz
               jr   c,set_100Hz     ; use 100Hz for 80-160Hz
               cp   &60             ; 40Hz
               jr   c,set_50Hz      ; use 50Hz for 44-55Hz
                                    ; reject <40Hz
bad_timer:     pop  hl              ; junk return address
               ld   a,ret_timer     ; unsupported frequency
               ret
;**  DADMAN \\


gap4          equ  &dd00-$         ; error if previous code is
               defs gap4            ; too big for available gap!
               defs 16              ; CIA #2 (serial, NMI)

               defs 32              ; small private stack
new_stack     equ  $

blocks:        defw 0               ; buffered block count
head:          defw 0               ; head for recorded data
tail:          defw 0               ; tail for playing data

init_addr:     defw 0
play_addr:     defw 0
play_song:     defb 0
ntsc_tune:     defb 0               ; non-zero for 60Hz tunes

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; Buffer management

record_block:  ld   de,(head)
               ld   hl,sid_regs     ; record from live SID values
               ld   bc,25           ; 25 registers to copy

; #0000-#7fff   Páginas 7 y 8
;               ld   a,buffer_page+rom0_off
;               out  (lmpr),a
               ldir
               xor  a
               ld   l,&24           ; changes for control 1
               ldi
               ld   l,&2b           ; changes for control 2
               ldi
               ld   l,&32           ; changes for control 3
               ldi
               ld   l,&24
               ld   (hl),a          ; clear control changes 1
               ld   l,&2b
               ld   (hl),a          ; clear control changes 2
               ld   l,&32
               ld   (hl),a          ; clear control changes 3
               inc  e
               inc  e
               inc  e
               inc  de              ; top up to 32 byte block
;               res  7,d             ; wrap in 32K block ***
               ld   a,d
               or   &f0
               ld   d,a
               ld   (head),de
; #0000-#7fff   Páginas 3 y 4
;              ld   a,low_page+rom0_off
;              out  (lmpr),a

               ld   hl,sid_regs
               ld   de,prev_regs
               ld   bc,25
               ldir

               ld   hl,(blocks)
               inc  hl
               ld   (blocks),hl
               ret
               
play_block:    ld   hl,(blocks)
               ld   a,h
               or   l
               ret  z
               dec  hl              ; 1 less block available
               ld   (blocks),hl
               ld   de,buffer_low
               sbc  hl,de
               jr   nc,buffer_ok    ; jump if we're not low
;               ld   a,128           ; screen off for speed boost
;               out  (border),a

buffer_ok:
; #0000-#7fff   Páginas 7 y 8
;               ld   a,buffer_page+rom0_off
;               out  (lmpr),a
               ld   hl,(tail)
               call sid_update
;               res  7,h             ; wrap in 32K block
               ld   a,h
               or   &f0
               ld   h,a

               ld   (tail),hl

;               ld   a,&ff
;               in   a,(keyboard)
;               rra
;               ret  c               ; return if Cntrl not pressed

;               ld   hl,(blocks)
;               add  hl,hl
;               ld   a,&3f
;               sub  h
;               and  %00000111
;               out  (border),a
               ret

enable_player: ld   hl,im2_table
               ld   c,im2_vector/256
im2_lp:        ld   (hl),c
               inc  l
               jr   nz,im2_lp       ; loop for first 256 entries
               ld   a,h
               inc  h
               ld   (hl),c          ; 257th entry
               ld   i,a
               im   2               ; set interrupt mode 2
               ei                   ; enable player
               ret

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

gap5          equ  &dddd-$         ; error if previous code is
               defs gap5            ; too big for available gap!

im2_vector:    jp   im2_handler     ; interrupt mode 2 handler

; Reordering the decode table to group low and high bytes avoids
; 16-bit arithmetic for the decode stage, saving 12T

reorder_256   equ  im2_table       ; use IM2 table as working space

reorder_decode:ld   hl,decode_table
               ld   d,h
               ld   e,l
               ld   bc,reorder_256  ; 256-byte temporary store
reorder_lp:    ld   a,(hl)          ; low byte
               ld   (de),a
               inc  l
               inc  e
               ld   a,(hl)          ; high byte
               ld   (bc),a
               inc  hl
               inc  c
               jr   nz,reorder_lp
               dec  h               ; back to 2nd half (high bytes)
reorder_lp2:   ld   a,(bc)
               ld   (hl),a
               inc  c
               inc  l
               jr   nz,reorder_lp2
               ret


gap6          equ  &de00-$        ; error if previous code is
               defs gap6           ; too big for available gap!

decode_table:  defw i_brk,i_ora_ix,i_undoc_1,i_undoc_2     ; 00
               defw i_undoc_1,i_ora_z,i_asl_z,i_undoc_2    ; 04
               defw i_php,i_ora_i,i_asl_acc,i_undoc_2      ; 08
               defw i_undoc_3,i_ora_a,i_asl_a,i_undoc_2    ; 0C

               defw i_bpl,i_ora_iy,i_undoc_2,i_undoc_2     ; 10
               defw i_undoc_1,i_ora_zx,i_asl_zx,i_undoc_2  ; 14
               defw i_clc,i_ora_ay,i_undoc_1,i_undoc_3     ; 18
               defw i_undoc_3,i_ora_ax,i_asl_ax,i_undoc_2  ; 1C

               defw i_jsr,i_and_ix,i_undoc_1,i_undoc_2     ; 20
               defw i_bit_z,i_and_z,i_rol_z,i_undoc_2      ; 24
               defw i_plp,i_and_i,i_rol_acc,i_undoc_2      ; 28
               defw i_bit_a,i_and_a,i_rol_a,i_undoc_2      ; 2C

               defw i_bmi,i_and_iy,i_undoc_2,i_undoc_2     ; 30
               defw i_bit_zx,i_and_zx,i_rol_zx,i_undoc_2   ; 34
               defw i_sec,i_and_ay,i_undoc_1,i_undoc_3     ; 38
               defw i_bit_ax,i_and_ax,i_rol_ax,i_undoc_2   ; 3C

               defw i_rti,i_eor_ix,i_undoc_1,i_undoc_2     ; 40
               defw i_undoc_2,i_eor_z,i_lsr_z,i_undoc_2    ; 44
               defw i_pha,i_eor_i,i_lsr_acc,i_undoc_2      ; 48
               defw i_jmp_a,i_eor_a,i_lsr_a,i_undoc_2      ; 4C

               defw i_bvc,i_eor_iy,i_undoc_2,i_undoc_2     ; 50
               defw i_undoc_2,i_eor_zx,i_lsr_zx,i_undoc_2  ; 54
               defw i_cli,i_eor_ay,i_undoc_1,i_undoc_3     ; 58
               defw i_undoc_3,i_eor_ax,i_lsr_ax,i_undoc_2  ; 5C

               defw i_rts,i_adc_ix,i_undoc_1,i_undoc_2     ; 60
               defw i_undoc_2,i_adc_z,i_ror_z,i_undoc_2    ; 64
               defw i_pla,i_adc_i,i_ror_acc,i_undoc_2      ; 68
               defw i_jmp_i,i_adc_a,i_ror_a,i_undoc_2      ; 6C

               defw i_bvs,i_adc_iy,i_undoc_2,i_undoc_2     ; 70
               defw i_stz_zx,i_adc_zx,i_ror_zx,i_undoc_2   ; 74
               defw i_sei,i_adc_ay,i_undoc_1,i_undoc_3     ; 78
               defw i_undoc_3,i_adc_ax,i_ror_ax,i_undoc_2  ; 7C

               defw i_undoc_2,i_sta_ix,i_undoc_2,i_undoc_2 ; 80
               defw i_sty_z,i_sta_z,i_stx_z,i_undoc_2      ; 84
               defw i_dey,i_bit_i,i_txa,i_undoc_2          ; 88
               defw i_sty_a,i_sta_a,i_stx_a,i_undoc_2      ; 8C

               defw i_bcc,i_sta_iy,i_undoc_2,i_undoc_2     ; 90
               defw i_sty_zx,i_sta_zx,i_stx_zy,i_undoc_2   ; 94
               defw i_tya,i_sta_ay,i_txs,i_undoc_2         ; 98
               defw i_stz_a,i_sta_ax,i_stz_ax,i_undoc_2    ; 9C

               defw i_ldy_i,i_lda_ix,i_ldx_i,i_undoc_2     ; A0
               defw i_ldy_z,i_lda_z,i_ldx_z,i_undoc_2      ; A4
               defw i_tay,i_lda_i,i_tax,i_undoc_2          ; A8
               defw i_ldy_a,i_lda_a,i_ldx_a,i_undoc_2      ; AC

               defw i_bcs,i_lda_iy,i_undoc_2,i_undoc_2     ; B0
               defw i_ldy_zx,i_lda_zx,i_ldx_zy,i_undoc_2   ; B4
               defw i_clv,i_lda_ay,i_tsx,i_undoc_3         ; B8
               defw i_ldy_ax,i_lda_ax,i_ldx_ay,i_undoc_2   ; BC

               defw i_cpy_i,i_cmp_ix,i_undoc_2,i_undoc_2   ; C0
               defw i_cpy_z,i_cmp_z,i_dec_z,i_undoc_2      ; C4
               defw i_iny,i_cmp_i,i_dex,i_undoc_1          ; C8
               defw i_cpy_a,i_cmp_a,i_dec_a,i_undoc_2      ; CC

               defw i_bne,i_cmp_iy,i_undoc_2,i_undoc_2     ; D0
               defw i_undoc_2,i_cmp_zx,i_dec_zx,i_undoc_2  ; D4
               defw i_cld,i_cmp_ay,i_undoc_1,i_undoc_1     ; D8
               defw i_undoc_3,i_cmp_ax,i_dec_ax,i_undoc_2  ; DC

               defw i_cpx_i,i_sbc_ix,i_undoc_2,i_undoc_2   ; E0
               defw i_cpx_z,i_sbc_z,i_inc_z,i_undoc_2      ; E4
               defw i_inx,i_sbc_i,i_nop,i_undoc_2          ; E8
               defw i_cpx_a,i_sbc_a,i_inc_a,i_undoc_2      ; EC

               defw i_beq,i_sbc_iy,i_undoc_2,i_undoc_2     ; F0
               defw i_undoc_2,i_sbc_zx,i_inc_zx,i_undoc_2  ; F4
               defw i_sed,i_sbc_ay,i_undoc_1,i_undoc_3     ; F8
               defw i_undoc_3,i_sbc_ax,i_inc_ax,i_undoc_2  ; FC

ending:
size          equ  ending-base

; For testing we include a sample tune (not supplied)
;IF defined (TEST)
;INCLUDE "tune.asm"
;ENDIF
             ;  end  base

