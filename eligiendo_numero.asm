

.include "m328pdef.inc"
.equ valor_alto_ADC = 200
.equ valor_bajo_ADC = 50
.def seteador = R16
.def digito = R17
.def pos_digito = R18
.def buffer = R19
.def cant_digito = R20
.def indice = R21 ;Registro que mantiene el indice de la posicion de la tabla digitos_no_seleccionados
.dseg

.org SRAM_START
numero_secreto: .byte 4
digitos_no_seleccionados: .byte 10
.cseg
.org 0x0000
	rjmp eligiendo_numero_seteo

.org PCI2addr
	rjmp digito_confirmado

.org ADCCaddr
	rjmp joystic_ADC_interrupt

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
	LDI indice, 0
;-------------------------------------------------------
;-----------Puntero a numero_secreto en SRAM------------
	RCALL cargar_digitos_puntero
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
	;TODO iniciar pines de salida en 0
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
	;vuelvo a setear el Start Conversion
	LDI seteador, 0b11011111
	STS ADCSRA, seteador
	RJMP eligiendo_numero

;Cuando se apreta el botón salta pin change a esta función
digito_confirmado:
	;Se guarda digito en la SRAM y vuelve a 0
	ST X+, digito
	CLR digito
	;se incrementa la cantidad de digitos confirmados
	INC cant_digito
	RETI

;Interrucón por ADC dado a que se terminó la conversión del valor leido en joystick
joystic_ADC_interrupt:
	;Se carga en buffer lo convertido
	LDS buffer, ADCH

	;TODO vchequear joystick tensión alta tensión baja del joystick
	;Si buffer > valor_alto_ADC incrementar digito
	CPI buffer, valor_alto_ADC
	BRSH joystick_incrementar
	;Si buffer < valor_bajo_ADC decrementar digito
	CPI buffer, valor_bajo_ADC
	BRLO joystick_decrementar

	RJMP joystic_ADC_fin
joystick_incrementar:
	;TODO dar vuelta la lista en RAM y ver q pasa. (a ver si se puede hacer con Y+, y -Y)
	ST +Y, digito
	cpi digito, 0xFF
	rjmp joystick_incrementar 
	inc indice
	cpi indice, 10
	breq resetear_indice
continuar_joystick_incrementar:
	OUT PINC, digito
	rjmp joystic_ADC_fin

resetear_indice:
	clr indice
	rcall resetear_puntero_y
	rjmp continuar_joystick_incrementar

joystic_decrementar:
	dec indice
	cpi indice, 0xFF
	breq 
	ST -Y, digito

	OUT PINC, digito
joystic_ADC_fin:
	RETI


;Se cargan los 10 digitos en SRAM para ir comparando con el registro digito y evitar digitos ya seleccionados.
cargar_digitos_puntero:
	rcall resetear_puntero_y
	LDI setador, 0
cargar_digitos:
	CPI seteador, 10
	BREQ fin_cargar_digitos
	ST Y+, seteador
	INC setador
	RJMP cargar_digitos
fin_cargar_digitos:
	rcall resetear_puntero_y
	RET

resetear_puntero_y:
	LDI YL, LOW(digtios_no_seleccionados)
	LDI YH, HIGH(digitos_no_seleccionados)
	ret