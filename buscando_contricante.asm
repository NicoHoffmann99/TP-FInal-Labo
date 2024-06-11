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

.org PCI2addr
	rjmp boton_pulsado

.org URXCaddr
	rjmp recepcion_completa

.org UTXCaddr
	rjmp transmision_completa

.org OC1Aaddr
	rjmp timer1_interrupt

.org INT_VECTORS_SIZE

buscando_contricante_setup:
	ldi seteador, HIGH(RAMEND)
	out sph, seteador
	ldi seteador, LOW(RAMEND)
	out spl, seteador
	
	CLR digito
	LDI GREG, 1

;-------------------------------------------------------
;------------------SETEANDO PUERTOS---------------------
	LDI seteador, 0b00001111
	;Puerto B PINES 0-3 escritura
	OUT DDRB, seteador
	OUT PINB, digito
	;Puerto C PIN 6(RESET) lectura, PIN 4(ADC) lectura, PINES 0-3 escritura
	OUT DDRC, seteador
	;Puerto D PIN 2(Botton) lectura => hace interrupciones
	LDI seteador, 0b00000000
	OUT DDRD, seteador
	LDI seteador, 0b00000100
	OUT PORTD, seteador

;-------------------------------------------------------
;---------------------PIN CHANGE------------------------
	LDI seteador, 0b00000100 ;habilitamos al puerto D - Pin 2 a realizar interrupciones externas(con pin change)
	STS PCICR, seteador 
	STS PCMSK2, seteador

;-------------------------------------------------------
;-------------------SETEANDO USART----------------------
	;BaudRate de 9600(ejemplo), tiro Frec de 8MHz(UBRRG=51)
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

boton_pulsado:
	LDI transmisor, N
	STS UDR0, transmisor
	RETI	

transmision_completa:
	LSL GREG
	RCALL espera_tres_segundos
	RETI

recepcion_completa:
	LDS receptor, UDR0
	CPI receptor, N
	BRNE recepcion_completa_fin
	LSL GREG
	RCALL espera_tres_segundos
recepcion_completa_fin:
	RETI

espera_tres_segundos:
	;TODO con el micro solo poner contador = 12
	LDI contador, 24
	;Seteo TIMER 1, 
	;Modo 4 CTC, Prescaler 64
	LDI seteador, 0
	STS TCCR1A, seteador
	LDI seteador, 0b00001011
	STS TCCR1B, seteador
	;Para el prescaler de 64 necesito poner como TOP 31249
	LDI seteador, 0x11
	STS OCR1AL, seteador
	LDI seteador, 0x7A
	STS OCR1AH, seteador
	;Habilito a TIMER 1 a hacer interrupciones
	LDI seteador, 0b00000010
	STS TIMSK1, seteador
	SEI
espera_tres_segundos_loop:
	CPI contador, 1
	BREQ espera_tres_segundos_fin
	RJMP espera_tres_segundos_loop
espera_tres_segundos_fin:
	;Deshabilito TIMER 1 para hacer interrupciones
	CLR seteador
	STS TIMSK1, seteador
	RET

timer1_interrupt:
	DEC contador
	COM digito
	OUT PINB, digito
	RETI