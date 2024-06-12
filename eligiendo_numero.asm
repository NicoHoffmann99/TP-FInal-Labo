;TODO enviar letra J por puerto serie cuando cant_digito llega a 4
;TODO esperar 3 segundos con leds titilando
;TODO cuando termina esto pasar a modo Juego
;Estas 3 cosas pueden hacerse bastante facil reutilizando codigo de Etapa1

.include "m328pdef.inc"
.equ valor_alto_ADC = 204	;255 es 5V -> Quiero 4V que es redondear(255*4/5) = 204
.equ valor_bajo_ADC = 51	;Quiero 1V que es redondear(255*1/5) = 51

.def seteador = R16
.def digito = R17
.def pos_digito = R18
.def buffer = R19
.def cant_digito = R20
.def indice = R21 ;Registro que mantiene el indice de la posicion de la tabla digitos_no_seleccionados
.def uno = R22		;Registro que guarda un 1, utilizado para operaciones aritmeticas
.def cero = R23		;Registro que guarda un 0.
.def contador = R24 ;Contador utilizado para iterar sobre loops

.dseg

.org SRAM_START
numero_secreto: .byte 4
digitos_no_seleccionados: .byte 10
.cseg
.org 0x0000
	rjmp eligiendo_numero_seteo

.org INT0addr
	rjmp digito_confirmado

.org ADCCaddr
	rjmp joystic_ADC_interrupt

.org OVF2addr
	rjmp timer2_interrupt

.org INT_VECTORS_SIZE

;SETEO PARA LA PARTE DE ELIGIENDO NUMERO(DESPU?S VEMOS DONDE MOVER LA ACTIVACI?N DE REGISTROS)
eligiendo_numero_seteo:
    ldi seteador, HIGH(RAMEND)
	out sph, seteador
	ldi seteador, LOW(RAMEND)
	out spl, seteador

;-------------------------------------------------------
;-----------Seteando registros necesarios---------------
	;digito es el registro que el usuario est? seleccionando con el joystic
	LDI digito, 0
	;cantidad de digitos es la cantidad de digitos ya confirmados
	LDI cant_digito, 0
	LDI indice, 0
	LDI uno, 1
	LDI cero, 0
;-------------------------------------------------------
;-----------Puntero a numero_secreto en SRAM------------
	RCALL cargar_digitos_puntero ;Cargo la tabla con los valores del 0 al 9.
	LDI XL, LOW(numero_secreto)  ;X se usar? para guardar los d?gitos seleccionados en la SRAM.
	LDI XH, HIGH(numero_secreto)

;-------------------------------------------------------
;------------------SETEANDO PUERTOS---------------------
	LDI seteador, 0b00001111
	;Puerto B PINES 0-3 escritura para escribir los digitos que se pueden seleccionar.
	OUT DDRB, seteador
	;Puerto C PIN 6(RESET) lectura, PIN 4(ADC) lectura, PINES 0-3 escritura de la cantidad de digitos ya seleccionados
	OUT DDRC, seteador
	;Puerto D PIN 2(Botton) lectura (con Rpullup interna) => hace interrupciones
	CLR seteador
	OUT DDRD, seteador
	LDI seteador, 0b00000100
	OUT PORTD, seteador

	;TODO iniciar pines de salida en 0
;-------------------------------------------------------
;-------------SETEANDO INT0 BOT?N-----------------------
	;Se habilita a PD2=INT0 a hacer
	LDI seteador, 0b00000010
	STS EICRA, seteador
	LDI seteador, 0b00000001
	OUT EIMSK, seteador
;-------------------------------------------------------
;--------------------SETEANDO ADC-----------------------
	;ADMUX RESF= 0 1 => AVCC como referencia
	;ADMUX ADLAR 1 => Justificado a la izquierda
	;ADMUX 0 1 0 0 => ADC4 como entrada del conversor
	LDI seteador, 0b01100100
	STS ADMUX, seteador

	;ADCSCRA seti? el ADC en Start Conversion, vemos despu?s cual conviene
	;ADCSCRA ADEN = 1 => Encender ADC
	;ADCSCRA ADIE = 1 => Habilito a hacer interrupci?n
	;ADCSCRA ADPS = 1 1 1 1 => Prescaler 128 (Despu?s vemos cual conviene)
	LDI seteador, 0b11011111
	STS ADCSRA, seteador
	;Con start conversion creo que no hace falta el ADCSRB
;-------------------------------------------------------
;--------------------SETEANDO TIMER2--------------------
	;Uso modo normal (reseteo en TOP=255),prescaler N=1024, como f_clk = 1MHz -> f_osc_timer2 = 1MHz / [(255+1)*1024] = 3,8Hz
	;Luego el periodo de un ciclo es aprox 0,25s.
	;Modo0 -> Normal -> WGM[1:0] = 00
	CLR seteador
	sts TCCR2A, seteador
	;El resto de la configuración lo hago unicamente cuando se va a usar el timer.
	;(prescaler y mascara de interrupts)
	
;-------------------------------------------------------
;----------------Interrupci?n Global--------------------
	SEI

;-------------------MAIN LOOP (de esta etapa)--------------;

;LOOP de etapa eligiendo_numero
eligiendo_numero:
	
	RJMP eligiendo_numero

;-----------------INTERRUPCIONES---------------------;

;Cuando se apreta el bot?n salta pin change a esta funci?n
digito_confirmado:
	;Lo primero que hago es apagar el ADC (si la cantidad de digitos es menor a 4, luego lo vuelvo a encender)
	clr seteador
	STS ADCSRA, seteador
	;Genero un delay para limpiar pulsos espurios (o por si se mantiene apretado el boton)
	rcall esperar_medio_segundo
	;Me fijo si digito = 0xFF (para prevenir que se apriete el boton seguido sin cambiar el numero a seleccionar)
	cpi digito, 0xFF
	breq fin_digito_confirmado
	;Se guarda digito en la SRAM
	ST X+, digito
	;se incrementa la cantidad de digitos confirmados
	INC cant_digito
	;En la tabla, el d?gito ya seleccionado es guardado como 0xFF para poder evitar seleccionarlo de nuevo.
	LDI seteador, 0xFF
	ST Y, seteador
	;Me fijo si cant_digito es menor a 4
	cpi cant_digito, 4
	BRLO volver_a_encender_adc
	;TODO cuando cant_digito llega a 4, hay que cambiar los flags y pasar a la siguiente etapa.
	
fin_digito_confirmado:
	;Escribo la cantidad de digitos ya seleccionados
	OUT PORTC, cant_digito
	RETI

volver_a_encender_adc:
	;vuelvo a setear el Start Conversion
	LDI seteador, 0b11011111
	STS ADCSRA, seteador
	rjmp fin_digito_confirmado

;Interrupci?n por ADC dado a que se termin? la conversi?n del valor le?do en joystick
joystic_ADC_interrupt:
	;Se carga en buffer lo convertido
	LDS buffer, ADCH

	;TODO vchequear joystick tensi?n alta tensi?n baja del joystick 
	;Si buffer > valor_alto_ADC incrementar digito
	CPI buffer, valor_alto_ADC
	BRSH joystick_incrementar
	;Si buffer < valor_bajo_ADC decrementar digito
	CPI buffer, valor_bajo_ADC
	BRLO joystick_decrementar

	RJMP joystic_ADC_fin

joystick_incrementar:	;Rutina donde se busca el siguiente numero en la secuencia del 0 al 9, salteando los ya elegidos, y volviendo al 0 si se incrementa desde el 9.
	
	inc indice			;Indice utilizado para saber en que posicion de la tabla se est? parado.
	cpi indice, 10		;Si la posici?n a la que se pasa es 10 -> se excedi? la tabla -> el indice y el puntero vuelven a la primer posicion.
	breq resetear_indice
	
	;Leo la tabla con PREINCREMENTO -> dado que no existe esta instrucci?n, primero sumo 1 a Y, y luego leo.
	;Sumo 1 a YL sin carry, y luego 0 con carry a YH.
	add YL, uno
	adc YH, cero
	;Leo el numero al que se apunta
	LD digito, Y
continuar_joystick_incrementar:
	;Chequeo si ya fue elegido (si es = a 0xFF)
	cpi digito, 0xFF	;Si el digito le?do es 0xFF (esto es as? para los d?gitos ya elegidos) -> repito la rutina (hasta leer uno que no sea 0xFF)
	breq joystick_incrementar
	;Si no lo es, escribo la salida por PORTB.
	OUT PORTB, digito
	;Antes de hacer el reti, espero medio segundo antes de que sea posible otro incremento/decremento.
	rcall esperar_medio_segundo
	rjmp joystic_ADC_fin	;Fin de la interrupcion.

joystick_decrementar:
	dec indice	;Resto 1 al indice
	cpi indice, 0xFF	;Si el indice era 0 y le resto 1, hubo overflow -> seteo indice = 9 y el puntero Y al final de la tabla.
	breq maximizar_indice
	;Leo Y con predecremento.
	LD digito, -Y
continuar_joystick_decrementar: ;Si se llego hasta aqu? es porque el d?gito le?do no fue elegido.
	;Chequeo si ya fue elegido (si es = a 0xFF)
	cpi digito, 0xFF	;Si el digito le?do es 0xFF (esto es as? para los d?gitos ya elegidos) -> repito la rutina (hasta leer uno que no sea 0xFF)
	breq joystick_decrementar
	;Si no lo es, escribo la salida por PINB.
	OUT PORTB, digito
	;Antes de hacer el reti, espero medio segundo antes de que sea posible otro incremento/decremento.
	rcall esperar_medio_segundo
joystic_ADC_fin:	;Fin de la interrupcion.
	;vuelvo a setear el Start Conversion
	LDI seteador, 0b11011111
	STS ADCSRA, seteador
	RETI

resetear_indice:	;Rutina utilizada para volver el indice a 0, resetear el puntero Y, y leer a lo que apunta.
	clr indice
	rcall resetear_puntero_y
	LD digito, Y
	rjmp continuar_joystick_incrementar

maximizar_indice:	;Rutina utilizada para setear el indice a 9, apuntar el puntero Y al final de la tabla, y leer a lo que apunta.
	ldi indice, 9
	rcall maximizar_puntero_y
	LD digito, Y
	rjmp continuar_joystick_decrementar

;Interrupcion por overflow de Timer2
timer2_interrupt:
	dec contador
	reti

;------RUTINAS GLOBALES----------;

;Se cargan los 10 digitos (0 a 9) en SRAM para ir comparando con el registro digito y evitar digitos ya seleccionados.
cargar_digitos_puntero:
	rcall resetear_puntero_y
	LDI seteador, 0
cargar_digitos:
	CPI seteador, 10
	BREQ fin_cargar_digitos
	ST Y+, seteador
	INC seteador
	RJMP cargar_digitos
fin_cargar_digitos:
	rcall resetear_puntero_y
	RET

;Setea el puntero Y al inicio de la tabla
resetear_puntero_y:
	LDI YL, LOW(digitos_no_seleccionados)
	LDI YH, HIGH(digitos_no_seleccionados)
	ret

;Setea el puntero Y al final de la tabla
maximizar_puntero_y:
	rcall resetear_puntero_y ;Hago que Y apunte al inicio de la tabla
	;Le sumo 9 a Y
	ldi seteador, 9
	add YL, seteador
	add YH, cero ;Le sumo el carry
	ret

;Rutina para generar un delay de medio segundo utilizando timer2
esperar_medio_segundo:
	;Itero 2 veces sobre el ciclo del timer (resulta en tiempo total de aprox. 0,5s)
	LDI contador, 2
	;Seteo la configuración que falta (se hace aqui ya que una vez que CS2 es distinto de 000 empieza el timer)
	;Le permito a timer2 hacer interrupcion por overflow.
	LDI seteador, 0b00000001
	STS TIMSK2, seteador
	;Modo2 -> Normal -> WGM[2] = 0
	;Prescaler N=1024 -> CS2[2:0] = 111
	ldi seteador, 0b00000111
	sts TCCR2B, seteador
	;Habilito interrupt global ya que es interrupcion anidada
	SEI

esperar_medio_segundo_loop: ;Cuando el contador llegue a 0, termino la espera
	;El contador es decrementado por la interrupcion por overflow de Timer2
	CPI contador, 0
	BREQ esperar_medio_segundo_fin
	rjmp esperar_medio_segundo_loop

esperar_medio_segundo_fin:
	;Deshabilito interrupcion de timer1
	clr seteador
	STS TIMSK2, seteador
	;Pongo el Clock select en 000 para apagar el contador
	STS TCCR2B, seteador
	ret