

.include "m328pdef.inc"

.def seteador = R16
.def digito = R17
.def pos_digito = R18
.def buffer = R19
.def cant_digito = R20

.dseg

.org SRAM_START
numero_secreto: .byte 4

.cseg
.org 0x0000
	rjmp eligiendo_numero_seteo

.org PCI2addr
	rjmp digito_confirmado

.org ADCCaddr
	rjmp joystic

.org INT_VECTORS_SIZE

;SETEO PARA LA PARTE DE ELIGIENDO NUMERO(DESPUÉS VEMOS DONDE MOVER LA ACTIVACIÓN DE REGISTROS)
eligiendo_numero_seteo:
    ldi seteador, HIGH(RAMEND)
	out sph, seteador
	ldi seteador, LOW(RAMEND)
	out spl, seteador

;-------------------------------------------------------
;-----------Seteando registros necesarios---------------
	;digito es el registro que el usuario está seleccionando con el joystic
	LDI digito, 0
	;cantidad de digitos es la cantidad de digitos ya confirmados
	LDI cant_digito, 0

;-------------------------------------------------------
;-----------Puntero a numero_secreto en SRAM------------
	LDI XL, LOW(numero_secreto)
	LDI XH, HIGH(numero_secreto)

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

;-------------------------------------------------------
;-------------SETEANDO PIN-CHANGE BOTÓN-----------------
	;Se habilita a los pines de PORTD a hacer interrupciones por PIN Change
	LDI seteador, 0b00000100
	STS PCICR, seteador
	STS PCMSK2, seteador

;-------------------------------------------------------
;--------------------SETEANDO ADC-----------------------
	;ADMUX RESF= 0 1 => AVCC como referencia
	;ADMUX ADLAR 1 => Justificado a la izquierda
	;ADMUX 0 1 0 0 => ADC4 como entrada del conversor
	LDI seteador, 0b01100100
	STS ADMUX, seteador

	;ADCSCRA setié el ADC en Start Conversion, vemos después cual conviene
	;ADCSCRA ADEN = 1 => Encender ADC
	;ADCSCRA ADIE = 1 => Habilito a hacer interrupción
	;ADCSCRA ADPS = 1 1 1 1 => Prescaler 128 (Después vemos cual conviene)
	LDI seteador, 0b11011111
	STS ADCSRA, seteador
	;Con start conversion creo que no hace falta el ADCSRB
;-------------------------------------------------------
;----------------Interrupción Global--------------------
	SEI

;LOOP de etapa eligiendo_numero
eligiendo_numero:
	
	RJMP eligiendo_numero

;Cuando se apreta el botón salta pin change a esta función
digito_confirmado:
	;Se guarda digito en la SRAM y vuelve a 0
	ST X+, digito
	CLR digito
	;se incrementa la cantidad de digitos confirmados
	INC cant_digito
	RETI

joystic:
	LDS buffer, ADCH
	;Llamo a "modificar" para cambiar el digito que está seleccionando el usuario y ahí evaluo para que lado
	;se movió el joystic para incrementar y decrementar digito
	RCALL modificar

	OUT PIND, digito

	;vuelvo a setear el Start Conversion
	LDI seteador, 0b11011111
	STS ADCSRA, seteador
	RETI

modificar:
	;VER LOGICA PARA MODIFICAR EL NUMERO SELECCIONADO SEGÚN JOYSTIC
	RET
