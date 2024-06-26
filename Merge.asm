.include "m328pdef.inc"
;--------------------------------------------------;
;					CONSTANTES					   ;
;--------------------------------------------------;
;Flags de cada etapa
.equ ETAPA_UNO	= 0b00000001 
.equ ETAPA_DOS	= 0b00000010
.equ ETAPA_TRES	= 0b00000100
.equ FIN_JUEGO	= 0b00001000
;Tensiones umbral para incrementar/decrementar con el ADC
.equ valor_alto_ADC = 204	;255 es 5V -> Quiero 4V que es redondear(255*4/5) = 204
.equ valor_bajo_ADC = 51	;Quiero 1V que es redondear(255*1/5) = 51
;ASCII en decimal
.equ J = 74
.equ N = 78
.equ R = 82

.equ desplazamiento_ascii = 48
.equ longitud_numero_secreto = 4


;--------------------------------------------------;
;					REGISTROS					   ;
;--------------------------------------------------;
.def titilar = R3
.def contador_e3 = R4
.def digito_secreto = R5
.def digito_jugador = R6
.def pos_numero_secreto = R7
.def pos_numero_jugador = R8
.def cant_digitos_bien_posicionados = R9
.def cant_digitos_mal_posicionados = R10
.def flagEtapaDos = R11
.def contador_t2 = R12
.def cant_digito = R13
.def seteador = R16
.def transmisor = R17
.def contador= R18
.def digito= R19
.def GREG = R20
;+----+----+----+----+----+----+----+----+		 E3 |  E2 |  E1
;|    |	NV |    |    |FIN | E3 | E2 | E1 |       0  |  0  |  1
;+----+----+----+----+----+----+----+----+       0  |  1  |  0
;                                                1  |  0  |  0
.def receptor = R21
.def buffer = R22
.def indice = R23 ;Registro que mantiene el indice de la posicion de la tabla digitos_no_seleccionados
.def uno = R24		;Registro que guarda un 1, utilizado para operaciones aritmeticas
.def comparador = R25


;--------------------------------------------------;
;					DATOS SRAM					   ;
;--------------------------------------------------;
.dseg
.org SRAM_START
digitos_no_seleccionados: .byte 10 	;Se guardan los numeros del 0 al 9 a elegir por jugador N1 (aquellos ya seleccionados se reescriben como 0xFF)
numero_jugador: .byte 4				;Se guarda el numero elegido por jugador N2 en cada intento de adivinar.
numero_secreto: .byte 4				;Se guarda el numero elegido por jugador N1.
cant_intentos: .byte 1				;Se guarda la cantidad de intentos del jugador N2 para adivinar.

;--------------------------------------------------;
;					  CÓDIGO					   ;
;--------------------------------------------------;
.cseg
.org 0x0000
	rjmp buscando_contricante_setup

.org INT0addr
	rjmp boton_pulsado

.org OVF2addr
	rjmp timer2_interrupt

.org OC1Aaddr
	rjmp timer1_interrupt

.org OC0Aaddr
	rjmp timer0_interrupt

.org URXCaddr
	rjmp recepcion_completa

.org UTXCaddr
	rjmp transmision_completa


.org ADCCaddr
	rjmp joystic_ADC_interrupt


;--------------------------------------------------;
;					SETUP ETAPA-1				   ;
;--------------------------------------------------;
.org INT_VECTORS_SIZE
buscando_contricante_setup:
	;Apago el Watchdog (por si vengo de un reset del WDT)
	IN seteador, MCUSR
	ANDI seteador, 0b11110111
	OUT MCUSR, seteador	
	ldi seteador, 0b00011000 ;Habilito el WatchDog Change Enable (WDCE)
	STS WDTCSR, seteador
	CLR seteador
	STS WDTCSR, seteador ;Apago WDE

	ldi seteador, HIGH(RAMEND)
	out sph, seteador
	ldi seteador, LOW(RAMEND)
	out spl, seteador

	CLR contador
	CLR digito
	LDI GREG, ETAPA_UNO

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
	;Seteo TIMER 1, un ciclo de prendido y apago es 0.5s
	;Modo 4 CTC, Prescaler 64(Se setea al implementarse el timer1)
	LDI seteador, 0
	STS TCCR1A, seteador
	;Para el prescaler de 64 necesito poner como TOP 3905
	LDI seteador, 0b00001111
	STS OCR1AH, seteador
	LDI seteador, 0b01000001
	STS OCR1AL, seteador
;-------------------------------------------------------
;----------------------INTERRUPT------------------------
	ldi seteador, 0b00000010
	sts EICRA, R16 ;setar el INT0 por flanco descendente
	ldi seteador, 0b00000001
	out EIMSK, seteador ;permito que INT0 haga interrupciones

;-------------------------------------------------------
;----------------------TIMER 0--------------------------
	;Seteo Timer0 en modo 2 -> CTC, TOP = 195, Pesclaer = 64
	ldi seteador, 0b00000010
	out TCCR0A, seteador
	;Seteo Prescaler en 1024
	ldi seteador, 0b00000011
	out TCCR0B, seteador
	;Seteo OCR0A con 234 como tope para tener un delay de 15ms aproximadamente
	ldi seteador, 234
	out OCR0A, seteador

;-------------------------------------------------------
;-------------------SETEANDO USART----------------------
	;BaudRate de 4800, para Frec de 1MHz(UBRRG=12) (menor error posible y m�xima velocidad)
	CLR seteador
	STS UBRR0H, seteador
	LDI seteador, 12
	STS UBRR0L, seteador

	;UCSR0A Solo tiene flags y el modo doble velocidad(dejo simple velocidad)
	;UDRE0 ==> 1, Seteo que el buffer de transmisi�n est� listo para recibir data
	LDI seteador, 0b00100000
	STS UCSR0A, seteador

	;USCR0C 
	;UMSELO = 0 0  ==> Modo as�ncronico
	;UPM0 = 0 0 ==> Paridad desactivada
	;USB0 = 0 ==> 1 Bit de Stop
	;UCSZ01/00 = 1 1 ==> Activo para 8 bits 
	;UCPOL0 ==> Como lo tengo asincronico no importa
	LDI seteador, 0b00000110
	STS UCSR0C, seteador

	;UCSR0B 
	;RXCIE0 = 1 ==> Habilito interrupci�n por recepci�n completa
	;TXCIE0 = 1 ==> Habilito interrupci�n por transmisi�n complenta
	;UDRIE0 = 0 ==> No es necesario habilitar interruciones por registro vac�o
	;RXEN0 = 1 ==> Habilito el receptor
	;TXEN0 = 1 ==> Habilito el transmisor
	;UCSZ02 = 0 ==> N es de 8 bits
	;RXB80 TXB80 = 0 ==> No sirven
	LDI seteador, 0b11011000
	STS UCSR0B, seteador

;------------------------------------------------------------
;-------------------INTERRUPCI�N GLOBAL----------------------
	SEI

;--------------------------------------------------;
;					LOOP ETAPA-1				   ;
;--------------------------------------------------;
buscando_contrincante:
	SBRS GREG, 0	;Mientras est� en GREG=ETAPA_UNO salteo
	RJMP buscando_contrincante_fin
	RJMP buscando_contrincante
buscando_contrincante_fin:
	RCALL espera_tres_segundos ;Hago titilar los Leds por 3segs y me voy a la siguiente etapa.

;--------------------------------------------------;
;					SETUP ETAPA-2				   ;
;--------------------------------------------------;
eligiendo_numero_seteo:
;-------------------------------------------------------
;-----------Seteando registros necesarios---------------
	;digito es el registro que el usuario est? seleccionando con el joystic
	LDI digito, 0
	;cantidad de digitos es la cantidad de digitos ya confirmados
	clr cant_digito
	LDI indice, 0
	LDI uno, 1
	clr contador_t2
;-------------------------------------------------------
;-----------Puntero a numero_secreto en SRAM------------
	RCALL cargar_digitos_puntero ;Cargo la tabla con los valores del 0 al 9.
	LDI XL, LOW(numero_secreto)  ;X se usar? para guardar los d?gitos seleccionados en la SRAM.
	LDI XH, HIGH(numero_secreto)

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
	;El resto de la configuraci�n lo hago unicamente cuando se va a usar el timer.
	;(prescaler y mascara de interrupts)
;-------------------------------------------------------
;-------------------MODIFICO USART----------------------
	;Solamente deshabilito interrupcion por recepcion completa (RXCIE0 = 0)
	LDI seteador, 0b01001000
	STS UCSR0B, seteador

;--------------------------------------------------;
;					LOOP ETAPA-2				   ;
;--------------------------------------------------;
eligiendo_numero:
	SBRS GREG, 1 ;Salteo si estoy en etapa2
	RJMP fin_eligiendo_numero 
	RJMP eligiendo_numero
fin_eligiendo_numero:
	;Hago titilar los leds durante 3 segs
	rcall espera_tres_segundos

;--------------------------------------------------;
;					SETUP ETAPA-3				   ;
;--------------------------------------------------;
juego_setup:
;-------------------------------------------------------
;-----------CARGANDO PUNTERO A NUM JUGADOR--------------
	LDI XH, HIGH(numero_jugador)
	LDI XL, LOW(numero_jugador)

;-------------------------------------------------------
;-------------------MODIFICO USART----------------------
	;Solamente deshabilito interrupcion por transmision completa (TXCIE0 = 0)
	LDI seteador, 0b10010000
	STS UCSR0B, seteador
;------------------------------------------------------
;------------INICIALIZANDO REGISTROS/SRAM--------------
	CLR cant_digitos_bien_posicionados
	CLR cant_digitos_mal_posicionados
	LDI XL, LOW(cant_intentos)
	LDI XH, HIGH(cant_intentos)
	CLR buffer
	ST X, buffer

;--------------------------------------------------;
;					LOOP ETAPA-3				   ;
;--------------------------------------------------;
;Inicio de recepci�n, se pone el contador en 0 y se apunta el puntero X a donde se va a guardar el numero del jugador
;Tambi�n se manda por los puertos la cantidad de digitos correctos bien posicionados y mal posicionados(previamente iniciados en 0)
juego_recepcion:
	OUT PORTB, cant_digitos_bien_posicionados
	OUT PORTC, cant_digitos_mal_posicionados
	CLR contador_e3
	RCALL resetear_puntero_X_numero_jugador
;Loop de recepci�n, hasta que el contador no llegue a la longitud del numero requerida no sale
juego_recepcion_loop:
	MOV comparador, contador_e3
	CPI comparador, longitud_numero_secreto
	BREQ juego_validacion
	RJMP juego_recepcion_loop
;Valdaci�n del n�mero ingresado, si es correcto sigue a proxima rutina, sino vuelve la fase de recepci�n
juego_validacion:
	;Transformo numero ingresado ascii a entero y valido el numero
	RCALL ascii_a_entero
	RCALL validar_numero
	;Si no est� encendido el flag de numero validado se vuelve a la etapa de recepci�n
	SBRS GREG, 6
	RJMP juego_recepcion
	;Desactivo el receptor
	CLR seteador
	STS UCSR0B, seteador
;Se comparan ambos numeros, si la cantidad de digitos bien posicionados es igual a la longitud del numero entonc�s salta a gano
juego_comparacion:
	RCALL comparar_numeros
	LDI comparador, longitud_numero_secreto
	CP cant_digitos_bien_posicionados, comparador
	BREQ gano
	LDI GREG, ETAPA_TRES
	LDI seteador, 0b10010000
	STS UCSR0B, seteador
	RJMP juego_recepcion
;Se ponen leds verdes prendidos, leds rojos muestan la cantidad de intentos
gano:
	LDI digito, 0xFF
	OUT PORTB, digito
	LDI XL, LOW(cant_intentos)
	LDI XH, HIGH(cant_intentos)
	LD buffer, X
	OUT PORTC, buffer
	LDI GREG, FIN_JUEGO
	LDI seteador, 0b10010000
	STS UCSR0B, seteador
	LDI seteador, 0b00000001
	OUT EIMSK, seteador
gano_loop:
	RJMP gano_loop


;--------------------------------------------------;
;					INTERRUPT INT0				   ;
;--------------------------------------------------;
boton_pulsado:
	cpi GREG, ETAPA_UNO
	breq boton_pulsado_etapa_uno
	cpi GREG, ETAPA_DOS
	breq boton_pulsado_etapa_dos
	cpi GREG, FIN_JUEGO
	breq boton_pulsado_fin_juego
	rjmp fin_boton_pulsado	

boton_pulsado_etapa_uno: ;Si ETAPA_UNO y apretan botón
	;Cargo contador para timer0
	LDI contador, 50
	;Habilito a timer 0 a hacer interrupciones
	LDI seteador, 0b00000010
	STS TIMSK0, seteador
	rjmp fin_boton_pulsado

boton_pulsado_etapa_dos: ;Si ETAPA_DOS y apretan botón 
	;Genero delay de 33ms para antirrebote (con el flag en 0xFF s� que la interrupcion vino del bot�n).
	ldi seteador, 0xFF
	mov flagEtapaDos, seteador
	ldi seteador, 10
	mov contador_t2, seteador
	rcall esperar_contador_33ms
	rjmp fin_boton_pulsado
boton_pulsado_fin_juego:
	;Si se apreta el boton en la etapa de fin de juego, reseteo el micro.
	;Esto lo hago habilitando el Watchdog en modo system reset para 16ms.
	ldi seteador, 0b00010000 ;Habilito el WatchDog Change Enable (WDCE)
	STS WDTCSR, seteador
	ldi seteador, 0b00001001 ;Pongo modo system Reset.
	STS WDTCSR, seteador
fin_boton_pulsado:
	RETI

;--------------------------------------------------;
;		INTERRUPT POR OVERFLOW DE TIMER2		   ;
;--------------------------------------------------;
timer2_interrupt:
	sub contador_t2, uno
	clr seteador
	cp contador_t2, seteador
	BREQ timer2_deshabilitar
	rjmp fin_timer2_interrupt

timer2_deshabilitar: ;Cuando apago el timer2 (pasaron 0,5s) vuelvo a encender el ADC.
	;Deshabilito interrupcion de timer2
	clr seteador
	STS TIMSK2, seteador
	;Pongo el Clock select en 000 para apagar el contador
	STS TCCR2B, seteador
	;Primero me fijo sin cant_digito llego a 4, en su caso apago INT0 y ADC.
	ldi seteador, 4
	cp cant_digito, seteador
	breq caso_cant_digito_cuatro
	;Si no brancheo me fijo si el flag de volver que la interrupcion vino de INT0 esta seteado (flagEtapaDos=0xFF)
	ldi seteador, 0xFF
	cp flagEtapaDos, seteador
	breq timer2_INT0
	rjmp fin_timer2_deshabilitar

timer2_INT0: ;Ejecuto la l�gica para cuando se confirma el d�gito a elegir.
	;Apago el flag
	clr flagEtapaDos
	;Vuelvo a leer digito de RAM por si el bot?n fue apretado dos veces seguidas sin incremento/decremento.
	LD digito, Y
	;Me fijo si digito = 0xFF (para prevenir que se apriete el boton seguido sin cambiar el numero a seleccionar)
	cpi digito, 0xFF
	breq fin_timer2_deshabilitar
	;Se guarda digito en la SRAM
	ST X+, digito
	;se incrementa la cantidad de digitos confirmados
	add cant_digito, uno
	;En la tabla, el d?gito ya seleccionado es guardado como 0xFF para poder evitar seleccionarlo de nuevo.
	LDI seteador, 0xFF
	ST Y, seteador
	;Escribo la cantidad de digitos ya seleccionados
	OUT PORTC, cant_digito
	rjmp fin_timer2_deshabilitar

caso_cant_digito_cuatro: ;Si ya llegue a 4 digitos seleccionados, apago INT0 y no enciendo ADC.
	LDI seteador, 0b00000000
	OUT EIMSK, seteador
	;Envio la J
	LDI transmisor, J
	STS UDR0, transmisor
	rjmp fin_timer2_interrupt

fin_timer2_deshabilitar:
	;Vuelvo a setear el Start Conversion para el ADC 
	LDI seteador, 0b11011111
	STS ADCSRA, seteador
fin_timer2_interrupt:
	reti

;--------------------------------------------------;
;		INTERRUPT POR COMPARE DE TIMER1			   ;
;--------------------------------------------------;
timer1_interrupt:
	;Decremento contador y modifico la salida
	OUT PORTC, titilar
	COM titilar
	OUT PORTB, titilar
	CPI contador, 0
	BREQ timer1_interrupt_desactivar
	DEC contador
	RJMP timer1_interrupt_fin
timer1_interrupt_desactivar:
	CLR seteador
	STS TIMSK1, seteador
	CLR titilar
	OUT PORTB, titilar
	OUT PORTC, titilar
timer1_interrupt_fin:
	RETI

;--------------------------------------------------;
;		INTERRUPT POR COMPARE DE TIMER0			   ;
;--------------------------------------------------;
timer0_interrupt:
	DEC contador
	CPI contador, 0
	BRNE timer0_interrupt_fin
	;Deshabilito al timer0 a hacer interrupciones
	CLR seteador
	STS TIMSK0, seteador
	;Env�o letra N 
	LDI transmisor, N
	STS UDR0, transmisor
timer0_interrupt_fin:
	RETI

;--------------------------------------------------;
;		INTERRUPT POR TRANSMISION DE UART		   ;
;--------------------------------------------------;
transmision_completa:
	CPI GREG, ETAPA_UNO
	BREQ transmision_etapa_uno
	CPI GREG, ETAPA_DOS
	BREQ transmision_etapa_dos
	rjmp fin_transmision_completa
transmision_etapa_uno: ;Si ETAPA_UNO paso a ETAPA_DOS
	LDI GREG, ETAPA_DOS
	RJMP fin_transmision_completa
transmision_etapa_dos: ;Si ETAPA_DOS paso a ETAPA_TRES
	LDI GREG, ETAPA_TRES
fin_transmision_completa:
	RETI

;--------------------------------------------------;
;		INTERRUPT POR RECEPCION DE UART			   ;
;--------------------------------------------------;
recepcion_completa:
	cpi GREG, ETAPA_UNO
	breq recepcion_completa_etapa_uno
	cpi GREG, ETAPA_TRES
	breq recepcion_completa_etapa_tres
	cpi GREG, FIN_JUEGO
	breq recepcion_completa_fin_juego
	rjmp recepcion_completa_fin
recepcion_completa_etapa_uno:
	LDS receptor, UDR0
	CPI receptor, N
	BRNE recepcion_completa_fin
	LDI GREG, ETAPA_DOS
	rjmp recepcion_completa_fin
recepcion_completa_etapa_tres:
	;Se carga lo recibido en numero_jugador y se incrementa contador
	LDS receptor, UDR0
	ST X+, receptor
	add contador_e3, uno
	rjmp recepcion_completa_fin
recepcion_completa_fin_juego:
	LDS receptor, UDR0
	CPI receptor, R
	BRNE recepcion_completa_fin
	;Si recibi una R en la etapa de fin de juego, reseteo el micro.
	;Esto lo hago habilitando el Watchdog en modo system reset para 16ms.
	ldi seteador, 0b00010000 ;Habilito el WatchDog Change Enable (WDCE)
	STS WDTCSR, seteador
	ldi seteador, 0b00001001 ;Pongo modo system Reset.
	STS WDTCSR, seteador
recepcion_completa_fin:
	RETI

;--------------------------------------------------;
;		INTERRUPT POR CONVERSION DEL ADC		   ;
;--------------------------------------------------;
joystic_ADC_interrupt:
	;Se carga en buffer lo convertido
	LDS buffer, ADCH
	;Si movi a derecha -> buffer > valor_alto_ADC decrementar digito
	CPI buffer, valor_alto_ADC
	BRSH joystick_decrementar
	;Si movi a izquierda -> buffer < valor_bajo_ADC incrementar digito
	CPI buffer, valor_bajo_ADC
	BRLO joystick_incrementar
	;Si no se cumple ninguno de los thresholds dejo contador en 1 (33ms hasta la siguiente conversion).
	ldi seteador, 1
	mov contador_t2, seteador
	RJMP joystic_ADC_fin

joystick_incrementar:	;Rutina donde se busca el siguiente numero en la secuencia del 0 al 9, salteando los ya elegidos, y volviendo al 0 si se incrementa desde el 9.
	inc indice			;Indice utilizado para saber en que posicion de la tabla se est? parado.
	cpi indice, 10		;Si la posici?n a la que se pasa es 10 -> se excedi? la tabla -> el indice y el puntero vuelven a la primer posicion.
	breq resetear_indice
	;Leo la tabla con PREINCREMENTO -> dado que no existe esta instrucci?n, primero sumo 1 a Y, y luego leo.
	;Sumo 1 a YL sin carry, y luego 0 con carry a YH.
	clr seteador
	add YL, uno
	adc YH, seteador
	;Leo el numero al que se apunta
	LD digito, Y
continuar_joystick_incrementar:
	;Chequeo si ya fue elegido (si es = a 0xFF)
	cpi digito, 0xFF	;Si el digito le?do es 0xFF (esto es as? para los d?gitos ya elegidos) -> repito la rutina (hasta leer uno que no sea 0xFF)
	breq joystick_incrementar
	;Si no lo es, escribo la salida por PORTB.
	OUT PORTB, digito
	;Antes de hacer el reti, apago por medio segundo el ADC.
	ldi seteador, 15
	mov contador_t2, seteador
	;15*33ms es aprox 0,5s. (al final de joystick llamo a esperar_contador_33ms)
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
	;Antes de hacer el reti, apago por medio segundo el ADC.
	;15*33ms es aprox 0,5s.
	ldi seteador, 15
	mov contador_t2, seteador
joystic_ADC_fin:	;Fin de la interrupcion.
	;Del siguiente Start Conversion se encarga timer2. (si hubo incre/decre se espera 500ms, sino 33ms)
	rcall esperar_contador_33ms
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

	
;--------------------------------------------------;
;				      RUTINAS				       ;
;--------------------------------------------------;
espera_tres_segundos: ;Rutina para esperar tres segundos con leds titilando.
	SER seteador
	MOV titilar, seteador
	LDI contador, 12
	;Habilito a TIMER 1 a hacer interrupciones
	LDI seteador, 0b00000010
	STS TIMSK1, seteador
	;Seteo Prescaler
	LDI seteador, 0b00001011
	STS TCCR1B, seteador
	RET

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

;Rutina para generar un delay de contador_t2*33ms entre conversiones del ADC utilizando timer2
;Antes de hacer rcall esperar_contador_33ms, se debe cargar en el registro contador el multiplo deseado.
esperar_contador_33ms:
	;Seteo la configuraci�n que falta de timer2 (se hace aqui ya que una vez que CS2 es distinto de 000 empieza el timer)
	;Le permito a timer2 hacer interrupcion por overflow.
	LDI seteador, 0b00000001
	STS TIMSK2, seteador
	;Modo2 -> Normal -> WGM[2] = 0
	;Prescaler N=128 -> CS2[2:0] = 101
	ldi seteador, 0b00000101
	sts TCCR2B, seteador
	
	ret


;--------------------------------------------------;
;				RUTINAS ETAPA-3			 		   ;
;--------------------------------------------------;
;----------------------------------------------------------
;------------VALIDACI�N DEL NUMERO INGRESADO---------------
;Llamar cuando el jugador termina de recibir el numero por completo 
;Verifica que los numeros sean validos (menores a 10)
;Si todos son validos se deshabilita el receptor
;Si alguno no es valido no se deshabilita el receptor
;En ambos casos se reinicia el puntero X
validar_numero:
	CLR contador_e3
	RCALL resetear_puntero_X_numero_jugador
validar_numero_loop:
	MOV comparador, contador_e3
	CPI comparador, longitud_numero_secreto
	BREQ numero_valido
	LD digito, X+
	CPI digito, 10
	BRSH numero_no_valido
	ADD contador_e3, uno
	RJMP validar_numero_loop
numero_valido:
	ORI GREG, 0b01000000
	RCALL resetear_puntero_X_numero_jugador
	RJMP validar_numero_fin
numero_no_valido:
	RCALL resetear_puntero_X_numero_jugador
validar_numero_fin:
	CLR contador_e3
	RET

;-----------------------------------------------------------
;----------------TRANSFORMAR ASCII A ENTERO-----------------
;Llamar cuando el jugador termina de recibir el numero por completo
;Transforma los caracteres ascii a numero restando 48 de numero_jugador en SRAM
;Reinicia el puntero X
ascii_a_entero:
	RCALL resetear_puntero_X_numero_jugador
	CLR contador
ascii_a_entero_loop:
	CPI contador, longitud_numero_secreto
	BREQ ascii_a_entero_fin
	LD digito, X
	LDI buffer, desplazamiento_ascii
	SUB digito, buffer
	ST X+, digito
	INC contador
	RJMP ascii_a_entero_loop
ascii_a_entero_fin:
	RCALL resetear_puntero_X_numero_jugador
	RET

;-----------------------------------------------------------
;------------------COMPARACI�N DE NUMEROS-------------------

;Compara numero_jugador y numero_secreto en SRAM
;Devuelve cantidad de digitos iguales bien posicionados y cantidad de digitos iguales mal posicionados 
;en los registros cant_digitos_bien_posicionados y cant_digitos_mal_posicionados
comparar_numeros:
	;Se llama funci�n para que el puntero Y apunte al numero secreto en SRAM
	RCALL resetear_puntero_Y_numero_secreto
	;Se carga comparador con la longitud del numero (4) y seteador con 0 para inicializar registros de posiciones y cantidades
	LDI comparador, longitud_numero_secreto
	LDI seteador, 0
	MOV pos_numero_secreto, seteador
	MOV cant_digitos_bien_posicionados, seteador
	MOV cant_digitos_mal_posicionados, seteador

;Loop principal, va leyendo los digitos de numero_secreto a medida que se comparan
;con todos los d�gitos de numero_jugador
leer_digito_numero_secreto:
	;Si se encuentra en la �ltima posicion de numero_secreto salta a finalizar la comparaci�n
	CP pos_numero_secreto, comparador
	BREQ comparar_numeros_fin
	;Se llama funci�n para que el puntero X apunte al inicio de numero_jugador
	RCALL resetear_puntero_X_numero_jugador
	;Se lee el digito en numero_secreto
	LD digito_secreto, Y+
	;Se setea(y resetea) la posicion apuntada en numero_jugador
	MOV pos_numero_jugador, seteador

;Loop secundario, va leyendo los digitos de numero_jugador y comparando
leer_digito_numero_jugador:
	;Si se encuenrta en la �ltima posicion de numero_jugador se incrementa la posicion de numero secreto y se vuelve a comenzar
	CP pos_numero_jugador, comparador
	BREQ incrementar_posicion_numero_secreto
	;Se lee digito en numero_jugador
	LD digito_jugador, X+

;Si los digitos leidos son iguales se procede a comparar sus posiciones, sino se pasa al proximo digito
comparar_digito:
	CP digito_secreto, digito_jugador
	BREQ comparar_posicion
	INC pos_numero_jugador
	RJMP leer_digito_numero_jugador

;Se compara la posici�n de los digitos en cada numero, si son iguales salta a incrementar la cantidad bien posicionada
;sino, salta a incrementar la cantidad mal posicionada
comparar_posicion:
	CP pos_numero_secreto, pos_numero_jugador
	BREQ digitos_iguales_misma_pos
	RJMP digitos_iguales_distinta_pos

;Se hace efectivo el incremento de cantidad mal posicionada
digitos_iguales_distinta_pos:
	INC pos_numero_jugador
	INC cant_digitos_mal_posicionados
	RJMP leer_digito_numero_jugador

;Se hace efectivo el incremento de la cantidad bien posicicionada
digitos_iguales_misma_pos:
	INC pos_numero_jugador
	INC cant_digitos_bien_posicionados
	RJMP leer_digito_numero_jugador

;Incrementa la posicion del numero secreto
incrementar_posicion_numero_secreto:
	INC pos_numero_secreto
	RJMP leer_digito_numero_secreto

;Incrementa la cantidad de intentos del jugador y se vuelve a rutina principal
comparar_numeros_fin:
	RCALL incrementar_cant_intentos
	RET

;-----------------------------------------------------------
;----------INCREMENTO DE LA CANTIDAD DE INTENTOS------------

;Incremento la cantidad de intentos(cant_intentos en SRAM)
incrementar_cant_intentos:
	LDI XL, LOW(cant_intentos)
	LDI XH, HIGH(cant_intentos)
	LD buffer,X
	INC buffer
	ST X, buffer
	RET

;-----------------------------------------------------------
;--------------REDIRECCIONAMIENTO DE PUNTEROS---------------
;Reseteo puntero X para que apunte a numero_jugador en SRAM
resetear_puntero_X_numero_jugador:
	LDI XL, LOW(numero_jugador)
	LDI XH, HIGH(numero_jugador)
	RET

;Reseteo puntero X para que apunte a numero_secreto en SRAM
resetear_puntero_Y_numero_secreto:
	LDI YL, LOW(numero_secreto)
	LDI YH, HIGH(numero_secreto)
	RET

;Setea el puntero Y al inicio de la tabla
resetear_puntero_y:
	LDI YL, LOW(digitos_no_seleccionados)
	LDI YH, HIGH(digitos_no_seleccionados)
	ret

;Setea el puntero Y al final de la tabla
maximizar_puntero_y:
	ldi YL, Low(digitos_no_seleccionados+9)
	ldi YH, High(digitos_no_seleccionados+9)
	ret