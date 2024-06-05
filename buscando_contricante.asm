.include "m328pdef.inc"

.def seteador = R16
.def transmisor = R17

.equ N = 78

.dseg

.org SRAM_START

.cseg
.org 0x0000
	rjmp buscando_contricante_seteo

.org PCI2addr
	rjmp boton_pulsado

.org URXCaddr
	rjmp recepcion_completa

.org INT_VECTORS_SIZE

buscando_contricante_setup:
	ldi seteador, HIGH(RAMEND)
	out sph, seteador
	ldi seteador, LOW(RAMEND)
	out spl, seteador

;-------------------------------------------------------
;------------------SETEANDO PUERTOS---------------------
	LDI seteador, 0b00001111
	;Puerto B PINES 0-3 escritura
	OUT DDRB, seteador
	;Puerto C PIN 6(RESET) lectura, PIN 4(ADC) lectura, PINES 0-3 escritura
	OUT DDRC, seteador
	;Puerto D PIN 2(Botton) lectura => hace interrupciones
	LDI seteador, 0b00000100
	OUT DDRD, seteador
	OUT PORTD, setador

;-------------------------------------------------------
;-------------------SETEANDO USART----------------------
	;BaudRate de 9600(ejemplo), tiro Frec de 8MHz(UBRRG=51)
	CLR seteador
	OUT UBRRGH, setador
	LDI seteador, 51
	OUT UBRRGL, seteador

	;UCSR0A Solo tiene flags y el modo doble velocidad(dejo simple velocidad)
	;UDRE0 ==> 1, Seteo que el buffer de transmisión está listo para recibir data
	LDI setador, 0b00100000
	OUT UCAR0A, seteador

	;USCR0C 
	;UMSELO = 0 0  ==> Modo asíncronico
	;UPM0 = 0 0 ==> Paridad desactivada
	;USB0 = 0 ==> 1 Bit de Stop
	;UCSZ01/00 = 1 0 ==> N = 78 tiene 7 bits, activo para 7 bits 
	;UCPOL0 ==> Como lo tengo asincronico no importa
	LDI seteador, 0b00001000
	OUT USCR0C, seteador

	;UCSR0B 
	;RXCIE0 = 1 ==> Habilito interrupción por recepción completa
	;TXCIE0 = 1 ==> Habilito interrupción por transmisión complenta
	;UDRIE0 = 0 ==> No es necesario habilitar interruciones por registro vacío
	;RXEN0 = 1 ==> Habilito el receptor
	;TXEN0 = 1 ==> Habilito el transmisor
	;UCSZ02 = 0 ==> N es de 7 bits
	;RXB80 TXB80 = 0 ==> No sirven
	LDI seteador, 0b11011000
	OUT UCSR0B, seteador

	SEI


buscando_contrincante:
	
	RJMP buscando_contrincante

boton_pulsado:
	LDI transimsor, N
	OUT UDR0, transmisor
	RETI

recepcion_completa:
	IN receptor, UDR0
	CPI receptor, N
	BRNE recepcion_copleta_fin
	;CAMBIAR FLAG de ETAPA de juego
	;PAUSA DE 3 SEGUNDOS CON LEDS TITILANDO
recepcion_completa_fin
	RETI