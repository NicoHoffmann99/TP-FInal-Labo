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

.equ desplazamiento_ascii = 48
.equ longitud_numero_secreto = 4
.equ N = 78

.dseg

.org SRAM_START
numero_jugador: .byte 4

.cseg
.org 0x0000
	rjmp buscando_contricante_setup

.org INT0addr
	rjmp boton_pulsado

.org URXCaddr
	rjmp recepcion_completa

.org UTXCaddr
	rjmp transmision_completa


.org INT_VECTORS_SIZE

juego_setup:
	ldi seteador, HIGH(RAMEND)
	out sph, seteador
	ldi seteador, LOW(RAMEND)
	out spl, seteador
	
;-------------------------------------------------------
;-----------CARGANDO PUNTERO A NUM JUGADOR--------------
	LDI XH, HIGH(numero_jugador)
	LDI XL, LOW(numero_jugador)

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
;----------------------INTERRUPT------------------------
	ldi seteador, 0b00000010
	sts EICRA, R16 ;setar el INT0 por flanco descendente
	ldi seteador, 0b00000001
	out EIMSK, R16 ;permito que INT0 haga interrupciones

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

;------------------------------------------------------
;-----------------INTERRUPCIÓN GLOBAL------------------
	SEI

juego:

	RJMP juego

recepcion_completa:
	;comparo el contador(iniciado en 0) con la longitud
	;si el contador llega a la longitud del numero completo salto a recepcion_numero_jugador_completa
	;transformo los ascii a numeros y valido que sean correctos
	CPI contador, longitud_numero_secreto
	BREQ recepcion_numero_jugador_completa
	LDS receptor, UDR0
	ST X+, receptor
	INC contador
	RJMP recepcion_completa_fin
recepion_numero_jugador_completa:
	RCALL ascii_a_numero
	RCALL validar_numero
recepcion_completa_fin:
	RETI


;Llamar cuando el jugador termina de recibir el numero por completo 
;Verifica que los numeros sean validos (menores a 10)
;Si todos son validos se deshabilita el receptor
;Si alguno no es valido no se deshabilita el receptor
;En ambos casos se reinicia el puntero X
validar_numero:
	CLR contador
	RCALL resetear_puntero_X
validar_numero_loop:
	CPI contador, longitud_numero_secreto
	BREQ numero_valido
	LD digito, X+
	CPI digito, 10
	BRSH numero_no_valido
	INC contador
	RJMP validar_numero_loop
numero_valido:
	;TODO comienzar la comparación, como indicamos que comienza la comparacion?
	;TODO desactivar recepcion
	RCALL resetear_puntero_X
	RJMP validar_numero_fin
numero_no_valido:
	RCALL resetear_puntero_X
validar_numero_fin:
	CLR contador
	RET

;Llamar cuando el jugador termina de recibir el numero por completo
;Transforma los caracteres ascii a numero restando 48
;Reinicia el puntero X
ascii_a_entero:
	RCALL resetear_puntero_X
	CLR contador, 0
	CPI contador, longitud_numero_secreto
	BREQ ascii_a_entero_fin
	LD digito, X
	DEC digito, desplazamiento_ascii
	ST X+, digito
	INC contador
	RJMP ascii_a_entero
ascii_a_entero_fin:
	RCALL resetear_puntero_X
	RET

;Reseteo puntero_X
resetear_puntero_X:
	LDI XL, LOW(numero_jugador)
	LDI XH, HIGH(numero_jugador)
	RET

