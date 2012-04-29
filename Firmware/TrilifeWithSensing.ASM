;**********************************************************************
;                                                                     *
;    Filename:	    TrilifeWithSensing.asm                          *
;    Date:              1/24/2012                                      *
;    File Version:         1                                          *
;                                                                     *
;    Author:            CK Harnett                                    *
;    Company:         Blipworks                                       *
;                                                                     *
;                                                                     *
;**********************************************************************
;                                                                     *
;    Files Required: P10F322.INC                                      *
;                                                                     *
;**********************************************************************
;                                                                     *
;    Notes:       Based on 10F222 template found in MPLAB 8.76        *
;         Maybe there is a 10F322 template from Microchip by now      *
;   Blink LED on pin RA2 using Timer0 interrupt.                      *
;   RA2 chosen because                                                *
;   it isn't used for in-circuit serial programming (ICSP)            *
;   RA0 and RA1 have hardware PWM that would be great for controlling *
;   the LED but both of those pins are needed for ICSP                *
;   so to drive an LED with pin 0 or 1                                *
;   and be able to reprogram the soldered PIC maybe neeeds a jumper   *
;   and RA3 is input only.                                            *
;**********************************************************************

; use pickit3 or icd3 to program 322
; I like the lower power option 1.8v on the 10LF322 to run off 2 nimh
; Also like the 2 timers, use this to do counting on one pin
; while blinking on another. 222 has only one timer and is not much cheaper


	list      p=PIC10F322            ; list directive to define processor
	#include <P10F322.INC>        ; processor specific variable definitions

;Original 10F222 code:	__CONFIG   _MCLRE_ON & _CP_OFF & _WDT_OFF & _MCPU_OFF & _IOFSCS_4MHZ


 __CONFIG   _CP_OFF & _FOSC_INTOSC & _WDTE_OFF & _MCLRE_OFF & _LVP_OFF


;***** PIN DEFINITIONS
LED equ 0x02; LED on pin RA2

;***** VARIABLE DEFINITIONS
LED_BITMAP equ 0x04;  it's what you xor with LATA to toggle 5V on pin RA2
STATE_PERIOD equ 0x08; trying a faster speed
;STATE_PERIOD equ 0x10; constant telling how many tmr2 cycles to hold in each state
NUM_STATES equ 0x04; Number of states, for example 0x04 means four states 0,1,2 and 3. You still have to define each state's brightness
NUM_NEIGHBORS equ 0x03; Number of neighbors in trianguar array
MIN_COUNTS equ 0x04; must be at least four positive transitions during the timer2 period to signal an active neighbor--
;MAX_COUNTS equ 0x0A; if you had more than 10 counts then your neighbor was in state 1,2, or 3.
MAX_COUNTS equ 0x0C; if you had more than 13 counts, your neighbor was in state 1,2,or 3
SHAKE_UP equ 0x0A; after this many cycles stuck at highest state, go into a random state
intrW equ 0x40; used in interrupt to save w
intrStatus equ 0x41; used in interrupt to save status
offtmr equ 0x42;holds settings for "off" time of LED in a given cell state
ontmr equ 0x43;holds settings for "on" time of LED in a given cell state
mystate equ 0x44; keeps track of state of cell
tmr2cycles equ 0x45; keeps track of how many tmr2 cycles have elapsed
maxcheck equ 0x46; this is zero when we go one past the maximum state
watchingpin equ 0x47; cycle between pins to watch, ra0 ra1 and ra3
pincycle equ 0x48; a cyclic index into watchingpin, it's 0 1 2 3
oncounts equ 0x49; keep track of positive pin transitions when checking neighbors' statesw
zeroneighbor equ 0x4A; keep track of whether a zero neighbor was found, but delay responding for one cycle
delcounter equ 0x4B; make a 200 microsecond delay for temp conversion
lifecounter equ 0x4C; count whether we reached SHAKE_UP number of cycles at highest state




;**********************************************************************
	ORG     0xFF             ; processor reset vector

; Internal RC calibration value is placed at location 0xFF by Microchip
; as a movlw k, where the k is a literal value.

	ORG     0x000             ; coding begins here
	;movwf   OSCCAL            ; I tried to update register with factory cal value, but OSCCAL is not defined in the 322 include file
    
; I left the above in from the 222 template
    movlw 0x50; 
    movwf OSCCON; this sets up a 4 MHz clock (each instruction 1 microsecond)
    goto Start

    ORG 0x04; Interrupt routine saves W and STATUS, then toggles led
    movwf intrW
    swapf STATUS,w
    movwf intrStatus
    
    btfsc INTCON,TMR0IF; do next only if it was tmr0 that caused the interrupt
    call tmr0iserv
    bcf INTCON,TMR0IF; re-enable tmr0 interrupts
 
    btfsc PIR1,TMR2IF; do next only if it was tmr2 that caused the interrupt
    call tmr2iserv
    bcf PIR1, TMR2IF; re-enable tmr2 interrupts

    ;btfsc IOCAF,0;check if it was an interrupt-on-change on whatever pin, only one pin (or none) should be enabled for IOC at any time
    btfsc IOCAF,0
    call pin013iserv;
    
    btfsc IOCAF,1
    call pin013iserv;

    btfsc IOCAF,3
    call pin013iserv;

    ;restore w and status
    swapf intrStatus,w
    movwf STATUS
    swapf intrW,f
    swapf intrW,w

    retfie;return from interrupt

 
    



Start:
   bcf ANSELA,LED; Make LED pin digital
   bcf TRISA,LED; make LED pin an output

   ; make all other pins digital inputs!!!
   bcf ANSELA,0;maybe this important
   bsf TRISA,0;
   bsf WPUA,0; enabling pullup on inputs is important for avoiding random flipping btw states
   bcf ANSELA,1
   bsf TRISA,1
   bsf WPUA,1
   bcf ANSELA,3; unimplemented, its always 0 (port RA3 being a digital input only)
   bsf TRISA,3; unimplemented, it's always 1
   bsf WPUA,3

   ;fill offtmr variable
   movlw b'00000000';
   movwf offtmr;

   ;fill ontmr variable
   movlw b'00000011';
   movwf ontmr;

   ;set up cell state checker
   movlw NUM_STATES
   movwf maxcheck;

   ;set up which pin is being watched for neighbor state: RA0, RA1 or RA3
   clrf watchingpin; start at RA0
   movlw 0x03;
   movwf pincycle; set initial pin input to RA0
   clrf oncounts;
   clrf zeroneighbor;start out with no neighbors known in state 0

   movlw SHAKE_UP
   movwf lifecounter; set up number of cycles to wait at top state before randomizing

   movlw 0xFF; set tmr2 period
   movwf PR2

   ;initialize tmr2cycles
   movlw STATE_PERIOD
   movwf tmr2cycles;

   ;initialize state variable with zero, later make it random at startup
   clrf mystate
   call randomstate
   ;Set up timer 0 for interrupts and set up Option register, let weak pullups be enabled by setting first bit to 0
   movlw b'00000100';1:32 presc, I can't see this one blinking.
   movwf OPTION_REG; 

   movlw b'10100011';Also enable peripheral and global interrupts
   movwf INTCON
  
   bsf PIE1,TMR2IE; enable tmr2 interrupts 
      ;Set up timer2 and turn it on
   movlw b'00011111';for a medium length cyc of about 65 ms, from 4x postscaler and 64x prescaler
   movwf T2CON;

again:
    movf mystate,w
    call myofftime; set off-time for the cell state
    movwf offtmr
    movf mystate,w
    call myontime; set on-time for the cell state
    movwf ontmr
    movf pincycle,w;  
    call whichpin; look up which pin we are watching
    movwf watchingpin
    ;set up watchingpin for interrupt on change by overwriting watchingpin to iocap register
    ;could sleep here? need to respond to tmr0 and tmr1 interrupts though
    goto again ;program loops here and interrupts toggle the led and state

randomstate bsf FVRCON,TSEN; we will use LSB of the 320/322's temperature sensor to set mystate to a random state
   bcf FVRCON,TSRNG; set temp sensor range so it works with the low power version of the 320/322 as well as 5V version
   movlw b'11011001'; set up A/D converter to use 64x clock prescaler, temp sensor, and enable it
   movwf ADCON;
   movlw d'100';
   movwf delcounter;
   call lildelay
   bsf ADCON,1; start A/D converter by setting GO bit to 1, I was supposed to wait 200 microseconds
newbit btfsc ADCON,1; keep checking not-done bit of A/D conversion
   goto newbit; get out if not-done bit becomes 0
   bcf mystate,0; clear last bit of mystate, need if I call randomstate from somewhere else
   btfsc ADRES,0; look at lsb of temperature conversion result
   bsf mystate,0; set last bit of mystate if lsb of temperature meas was 1
   movlw d'100';
   movwf delcounter;
   call lildelay
   bsf ADCON,1; start another A/D temperature conversion
nextbit btfsc ADCON,1; 
   goto nextbit; get out if not-done becomes 0
   bcf mystate,1; clear 2nd to last bit of mystate
   btfsc ADRES,0; and use next lsb to set 2nd bit of mystate, seems more random if I used 2nd to lsb of conversion result
   bsf mystate,1; set 2nd to last bit of mystate if lsb of next temperature meas was 1
   bcf ADCON,ADON; disable A/D converter, could save power
   bcf FVRCON,TSEN; disable temperature sensor, this is supposed to save pwr
   movf mystate,w; make sure mystate matches up with maxcheck
   call setmaxcheck;
   movwf maxcheck;
   return 

lildelay  decfsz delcounter,f;
   goto lildelay
   return

setmaxcheck addwf PCL,F; get right maxcheck for a given state, need if we generate a new state using randomstate
   retlw 0x04; state 0
   retlw 0x03; state 1
   retlw 0x02; state 2
   retlw 0x01; state 3

myofftime addwf PCL,F; get LED off-time for a given state
	retlw b'00000000';state 0 2xprescaler
    retlw b'00000001';state 1 4x prescaler
    retlw b'00000010';state 2  8xprescaler
    retlw b'00000011';state 3  16xprescaler
    ;retlw b'00000100';state 0 32xprescaler ; Cindy swapped around so it hangs out in dimmest state
    ;retlw b'00000010';state 1 8x prescaler
    ;retlw b'00000001';state 2  4xprescaler
    ;retlw b'00000000';state 3  2xprescaler
    nop; just incase interrupt during state overflow

myontime addwf PCL,F;get LED on-time for a given state
    retlw b'00000100';state 0  32xprescaler
    retlw b'00000010';state 1  8xprescaler
    retlw b'00000001';state 2  4xprescaler
    retlw b'00000000';state 3  2xprescaler
    ;retlw b'00000000';state 0  2xprescaler
    ;retlw b'00000001';state 1  4xprescaler
    ;retlw b'00000010';state 2  8xprescaler
    ;retlw b'00000011';state 3  16xprescaler
    nop; just incase interrupt during state overflow

whichpin addwf PCL,F; get which pin is being watched 
    retlw b'00000001';RA0(in case watchingpin=0)
    retlw b'00000010';RA1 
    retlw b'00001000';RA3
    retlw b'00000001';RA0
    nop; in case try index one out of range
    ;retlw b'00000001'; RA0 (in case you wind up with watchingpin =0)
    ;retlw b'00000001'; RA0 again
    ;retlw b'00000010'; RA1 
    ;retlw b'00001000'; RA3 corresponds to watchingpin =3
    ;nop; in case try to index one out of range


tmr0iserv movlw LED_BITMAP     ;use tmr0 to toggle led fast for intensity control (pwm)
    xorwf LATA,F 

    ;change timer prescaler to set time elapsed before next tmr0 interrupt
	movf offtmr,w; set LED off time
    btfsc LATA,LED; check LED state (not cell state), skip next if LED is off now
    movf ontmr,w ; set LED on time    
    movwf OPTION_REG
        
	return

tmr2iserv  decfsz tmr2cycles,f ;use tmr2 to step between cell states
    return; done if we didn't hit zero
    movlw STATE_PERIOD ; otherwise reset tmr2cycles
    movwf tmr2cycles
    incf mystate,f;auto-increment cell state
    decfsz maxcheck,f; and decrement overflow checker
    return ; done if we haven't hit the maximum state
    btfsc zeroneighbor,0; zero neighbor flag is set only if a zero neighbor was found in previous cycle
    goto foundzero
    decf mystate,f; hold it back at max state and start checking neighbors for zeroes
    incf maxcheck,f;and undo auto-decrement on maxcheck 
    decfsz pincycle,f; makes it so we are going to check a new pin next time through,
    goto skipto; do this if we didn't reduce pincycle to zero
    movlw 0x03; 
    movwf pincycle; if we got a zero set pincycle back to 3, watching RA0 next time
skipto bsf INTCON,IOCIE;new--enable interrupt on change (set IOCIE bit in INTCON register)
    ;set the interrupt on positive change  (IOCAP) only for whatever pin we are watching
    movf watchingpin,w;
    movwf IOCAP;
    movlw 0x01; go for one tmr2 cycle to watch a neighbor
    movwf tmr2cycles
    movf oncounts,w;
    sublw MAX_COUNTS; subtract oncounts from MAX_COUNTS
    btfss STATUS,C; carry flag is set if oncounts was less than or equal to Max Counts, could be a zero neighbor
    goto endtmr2iserv; if you got here a neighbor in state 1 or higher was found
    movlw MIN_COUNTS; Now compare number of counts with MIN_COUNTS
    subwf oncounts,w
    btfss STATUS,C; carry flag is set if oncounts was less than or equal to mincounts
    goto endtmr2iserv; if set there was no active neighbor on this pin (probably is on the edge)
    bsf zeroneighbor,0; set zero neighbor bit if you got here, but continue to hang out for one last cycle in top state
    movlw STATE_PERIOD; this sets the delayed response time for nice looking propagation, but it is a bit slow at STATE_PERIOD and too fast at 1
    movwf tmr2cycles;
    goto endtmr2iserv;
foundzero  bcf zeroneighbor,0; clear zero neighbor bit
    clrf mystate; do if you found a zero-state neighbor. wait a bit after detecting zero or wavefront moves 'instantaneously' across array
    ;disable interrupt on change (IOCIE bit in INTCON register)
    bcf INTCON,IOCIE;disable interrupt on change
    movlw NUM_STATES
    movwf maxcheck
    movlw STATE_PERIOD;
    movwf tmr2cycles;
endtmr2iserv clrf oncounts
;things to do outside interrupt routine--adjust ontmr and offtmr dep on state
   	return

pin013iserv incf oncounts,f;
   ;bcf IOCAF,0;clear pin interrupt flag, datasheet has a better way to clear the IOCAFx bit when x may change 
   clrf IOCAF; okay just clear it all, we're only watching one pin at a time anyway
   return; handle interrupt on change
    
  ;increment counter associated with the pin.  start with just pin 0!
   

; remaining code goes here, 
; Set up four different duty cycles (PWM) 10, 30, 60 and 90 pct at rates greater than 200 Hz (DONE but prob need current reg)
; The 10pct one should have a far different frequency (say 1000 Hz vs 200 Hz for all others)(DONE but limited)
; First select the duty cycle in code & compare led brightness side by side with 4 pics. done
; and check the waveform on the oscilloscope 
; Then have it auto step through the four different states, changing about 1 Hz USE RETLW and TMR2, done.
; Then add a pulse counter that can run on another pin while timer0 is doing its thing, at the end of the
; 1 second period--done
; Then add branching, if you're at 90 pct duty cycle watch that pin and switch to 10pct only if 10pct detected--done
; Then have it check each of the three other pins for the 10pct signal, not just the one pin. Done.
; Then add a randomizer subroutine to select a random duty cycle on startup, see my .txt file for a short code segment
; that does randomization. What about turning off pullup resistor and counting odd or even pulses...
; Did something using temp sensor...it's randomish, needs improving
; Also needs to go about 3-4x faster
; Also consider reversing cycle order so it hangs out in dimmest state most of the time saving power
; Then have it break out of static by going to randomizer if state hasn't changed for five or 10 cycles.Created a lifecounter variable






	END                       ; directive 'end of program'

