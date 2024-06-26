; Copyright Terence J. Boldt (c)2020-2024
; Use of this source code is governed by an MIT
; license that can be found in the LICENSE file.

; This file contains the source for the firmware
; that allows the Apple II to boot from the card
; and for ProDOS to recognize the card as two
; hard drivers

;ProDOS Zero Page
Command = $42 ;ProDOS Command
Unit = $43 ;ProDOS unit (SDDD0000)
BufferLo = $44
BufferHi = $45
BlockLo = $46
BlockHi = $47

; ProDOS Error Codes
IOError = $27
NoDevice = $28
WriteProtect = $2B

InputByte = $c08e+SLOT*$10
OutputByte = $c08d+SLOT*$10
InputFlags = $c08b+SLOT*$10
OutputFlags = $c087+SLOT*$10

ReadBlockCommand = $01
WriteBlockCommand = $02
GetTimeCommand = $03
ChangeDriveCommand = $04
ExecCommand = $05
LoadFileCommand = $06
SaveFileCommand = $07
MenuCommand = $08

 .org SLOT*$100 + $C000
;ID bytes for booting and drive detection
 cpx #$20    ;ID bytes for ProDOS
 cpx #$00    ;
 cpx #$03    ;
 cpx #$3C    ;ID byte for Autostart ROM

 lda #$3f ;set all flags high and page 3 of EPROM for menu
 jmp PageJump

;The following bytes must exist in this location for Pascal communications
;as they are standard pointers for entry points
.byte     CommInit&$00FF ;low byte of rts for init of Pascal comms
.byte     CommRead&$00FF ; low byte of read for Pascal comms
.byte     CommWrite&$00FF ; low byte of write for Pascal comms
.byte     CommStatus&$00FF ; low byte of rts for status of Pascal comms

CommInit:
 lda #$0f ; set all flags high and page 0 for comm driver
 sta OutputFlags
 ldx #$00 ; set error code to 0 for success
 rts

PageJump:
 sta OutputFlags
 jmp Start ;this jump is only called if coming in from PageJump with A=$0f

;entry points for ProDOS
DriverEntry:
 lda #$0f ;set all flags high and page 0 of EPROM
 sta OutputFlags
 jmp Driver

;load first two blocks and execute to boot
Start:
 ldx #SLOT*$10
 stx $2b
 stx Unit 

 lda     #$01    ;set read command
 sta     Command
 
 lda     #$00    ;block 0
 sta     BlockLo
 sta     BlockHi
 sta     BufferLo   ;buffer at $800
 lda     #$08
 sta     BufferHi
 jsr     Driver  ;get the block

 jmp     $801    ;execute the block

CommRead:
 jsr GetByte
 ldx #$00 ; clear error code
 rts

CommWrite:
 jsr SendByte
 ldx #$00 ; clear error code
 rts

CommStatus:
 ldx #$00 ; clear error code
 sec ; set carry to indicate ready to read or write
 rts 

; ProDOS Driver code
; First check that this is the right drive
Driver: 
 ldx Unit
 lda Command; Check which command is being requested
 beq GetStatus ;0 = Status command
 cmp #ReadBlockCommand
 beq ReadBlock
 cmp #WriteBlockCommand
 beq WriteBlock
 sec ;set carry as we don't support any other commands
 lda #$53 ;Invalid parameter error
 rts

; ProDOS Status Command Handler
GetStatus: 
 ldx #$ff ;low byte number of blocks 
 ldy #$ff ;high byte number of blocks
 lda #$0 ;zero accumulator and clear carry for success
 clc
 rts

; ProDOS Read Block Command
ReadBlock:
 lda #ReadBlockCommand ;read the block after setting the clock
 jsr SendByte
 lda BlockLo
 jsr SendByte
 lda BlockHi
 jsr SendByte
 txa
 jsr SendByte
 ldy #$0
 jsr read256
 inc BufferHi
 jsr read256
 dec BufferHi
 lda #$0 ;zero accumulator and clear carry for success
 clc
 rts

read256: 
 jsr GetByte
 sta (BufferLo),y
 iny
 bne read256
 rts 
 
; ProDOS Write Block Command
WriteBlock:
 lda #WriteBlockCommand
 jsr SendByte
 lda BlockLo
 jsr SendByte
 lda BlockHi
 jsr SendByte
 txa
 jsr SendByte
 ldy #$0
 jsr write256
 inc BufferHi
 jsr write256
 dec BufferHi
 lda #$0 ;zero accumulator and clear carry for success
 clc
 rts

write256:
 lda (BufferLo),y
 jsr SendByte
 iny
 bne write256
 rts

SendByte:
 bit InputFlags
 bvs SendByte
 sta OutputByte
.if HW_TYPE = 0
 lda #$0e ; set bit 0 low to indicate write started
 sta OutputFlags
finishWrite:
 bit InputFlags
 bvc finishWrite
 lda #$0f
 sta OutputFlags
.endif
 rts

GetByte:
.if HW_TYPE = 0
 lda #$0d ;set read flag low
 sta OutputFlags
.endif
waitRead:
 bit InputFlags
 bmi waitRead
 lda InputByte
.if HW_TYPE = 0
 pha
 lda #$0f ;set all flags high
 sta OutputFlags
finishRead:
 bit InputFlags
 bpl finishRead
 pla
.endif
end:
 rts

.repeat	251-<end
.byte 0
.endrepeat

.byte      0,0     ;0000 blocks = check status
.byte      23       ;bit set(0=status 1=read 2=write) unset(3=format, 4/5=number of volumes, 6=interruptable, 7=removable)
.byte     DriverEntry&$00FF ;low byte of entry

