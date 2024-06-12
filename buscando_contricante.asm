.include "m328pdef.inc"

.def seteador = R16
.def transmisor = R17
.def contador= R18
.def digito= R19

.def GREG = R20
;+----+----+----+----+----+----+----+----+		E3 | E2 | E1
;|    |	   |    |    |    | E3 | E2 | E1 |         |    |
;+----+----+----+----+----+----+----+----+         |    |
                                              
.def receptor = R21


.equ N = 78

.dseg

.org SRAM_START

.cseg
.org 0x0000
	rjmp buscando_contricante_setup

.org INT0addr
	rjmp boton_pulsado

.org URXCaddr
	rjmp recepcion_completa

.org UTXCaddr
	rjmp transmision_completa

.org OC1Aaddr
	rjmp timer1_interrupt

.org OC0Aaddr
	rjmp timer0_interrupt

.org INT_VECTORS_SIZE

buscando_contricante_setup:
	ldi seteador, HIGH(RAMEND)
	out sph, seteador
	ldi seteador, LOW(RAMEND)
	out spl, seteador
	
	CLR contador
	CLR digito
	LDI GREG, 1

;-------------------------------------------------------
;------------------SETEANDO PUERTOS---------------------
	LDI seteador, 0b00001111
	;Puerto B PINES 0-3 escritura
	OUT DDRB, seteador
	OUT PORTB, digito
	;Puerto C PIN 6(RESET) lectura, PIN 4(ADC) lectura, PINES 0-3 escritura
	OUT DDRC, seteador
	;Puerto D PIN 2(Botton) lectura => hace interrupciones
	LDI seteador, 0b00000000
	OUT DDRD, seteador
	LDI seteador, 0b00000100
	OUT PORTD, seteador
;-------------------------------------------------------
;----------------------TIMER 1--------------------------


;-------------------------------------------------------
;----------------------INTERRUPT------------------------
	ldi seteador, 0b00000010
	sts EICRA, R16 ;setar el INT0 por flanco descendente
	ldi seteador, 0b00000001
	out EIMSK, R16 ;permito que INT0 haga interrupciones

;-------------------------------------------------------
;----------------------TIMER 0--------------------------
	;Seteo Timer0 en modo 2 -> CTC, TOP = 195, Pesclaer = 1024
	ldi seteador, 0b00000010
	out TCCR0A, seteador
	;Seteo Prescaler en 1024
	ldi seteador, 0b00000101
	out TCCR0B, seteador
	;Seteo OCR0A con 234 como tope para tener un delay de 15ms aproximadamente
	ldi seteador, 234
	out OCR0A, seteador

;-------------------------------------------------------
;-------------------SETEANDO USART----------------------
	;BaudRate de 9600(ejemplo), tiro Frec de 8MHz(UBRRG=51), 16MHz (UBRRG=103)
	CLR seteador
	STS UBRR0H, seteador
	LDI seteador, 103
	STS UBRR0L, seteador

	;UCSR0A Solo tiene flags y el modo doble velocidad(dejo simple velocidad)
	;UDRE0 ==> 1, Seteo que el buffer de transmisión está listo para recibir data
	LDI seteador, 0b00100000
	STS UCSR0A, seteador

	;USCR0C 
	;UMSELO = 0 0  ==> Modo asíncronico
	;UPM0 = 0 0 ==> Paridad desactivada
	;USB0 = 0 ==> 1 Bit de Stop
	;UCSZ01/00 = 1 1 ==> Activo para 8 bits 
	;UCPOL0 ==> Como lo tengo asincronico no importa
	LDI seteador, 0b00000110
	STS UCSR0C, seteador

	;UCSR0B 
	;RXCIE0 = 1 ==> Habilito interrupción por recepción completa
	;TXCIE0 = 1 ==> Habilito interrupción por transmisión complenta
	;UDRIE0 = 0 ==> No es necesario habilitar interruciones por registro vacío
	;RXEN0 = 1 ==> Habilito el receptor
	;TXEN0 = 1 ==> Habilito el transmisor
	;UCSZ02 = 0 ==> N es de 8 bits
	;RXB80 TXB80 = 0 ==> No sirven
	LDI seteador, 0b11011000
	STS UCSR0B, seteador

	SEI


buscando_contrincante:
	
	RJMP buscando_contrincante


;---------------------------------------------------------------
;--------------------RUTINAS INTERRUPCIONES---------------------

boton_pulsado:
	;Cargo contador para timer0
	LDI contador, 20
	;Habilito a timer 0 a hacer interrupciones
	LDI seteador, 0b00000010
	STS TIMSK0, seteador
	SEI
	RETI	

transmision_completa:
	LSL GREG
	
	RETI

recepcion_completa:
	LDS receptor, UDR0
	CPI receptor, N
	BRNE recepcion_completa_fin
	;LSL GREG
	RCALL espera_tres_segundos
recepcion_completa_fin:
	RETI

timer1_interrupt:
	;TODO agregar también los pines de Puerto C
	;Decremento contador y modifico la salida
	COM digito
	OUT PORTB, digito
	DEC contador
	RETI

timer0_interrupt:
	DEC contador
	CPI contador, 0
	BRNE timer0_interrupt_fin
	CLR seteador
	STS TIMSK0, seteador
	;Llamo a espera tres segundos
	RCALL espera_tres_segundos
	;Envío letra N 
	LDI transmisor, N
	STS UDR0, transmisor
	;Deshabilito al timer0 a hacer interrupciones
timer0_interrupt_fin:
	RETI
	

;-----------------------------------------------------------
;-------------------ESPERA 3 SEGUNDOS-----------------------

espera_tres_segundos:
	;TODO con el micro solo poner contador = 12
	LDI contador, 12
	;Seteo TIMER 1, un ciclo de prendido y apago es 0.5s
	;Modo 4 CTC, Prescaler 1024
	LDI seteador, 0
	STS TCCR1A, seteador
	LDI seteador, 0b00001101
	STS TCCR1B, seteador
	;Para el prescaler de 1024 necesito poner como TOP 3905
	LDI seteador, 0b01000001
	STS OCR1AL, seteador
	LDI seteador, 0b00001111
	STS OCR1AH, seteador
	;Habilito a TIMER 1 a hacer interrupciones
	LDI seteador, 0b00000010
	STS TIMSK1, seteador
	SEI

espera_tres_segundos_loop:
	CPI contador, 0
	BREQ espera_tres_segundos_fin
	RJMP espera_tres_segundos_loop

espera_tres_segundos_fin:
	;Deshabilito TIMER 1 para hacer interrupciones
	CLR seteador
	STS TIMSK1, seteador
	CLR digito
	OUT PORTB, digito
	RET

