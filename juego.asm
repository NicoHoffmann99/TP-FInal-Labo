.include "m328pdef.inc"
.equ desplazamiento_ascii = 48
.equ longitud_numero_secreto = 4
.equ N = 78

.def digito_secreto = R5
.def digito_jugador = R6
.def pos_numero_secreto = R7
.def pos_numero_jugador = R8
.def cant_digitos_bien_posicionados = R9
.def cant_digitos_mal_posicionados = R10

.def seteador = R16
.def transmisor = R17
.def contador= R18
.def digito= R19

.def GREG = R20
;+----+----+----+----+----+----+----+----+		E3 | E2 | E1
;|    |	NV |    |    |    | E3 | E2 | E1 |         |    |
;+----+----+----+----+----+----+----+----+         |    |
                                              
.def receptor = R21
.def buffer = R22

.def comparador = R23 

.dseg

.org SRAM_START
numero_jugador: .byte 4
numero_secreto: .byte 4
cant_intentos: .byte 1

.cseg
.org 0x0000
	rjmp juego_setup


.org URXCaddr
	rjmp recepcion_completa



.org INT_VECTORS_SIZE

juego_setup:
	ldi seteador, HIGH(RAMEND)
	out sph, seteador
	ldi seteador, LOW(RAMEND)
	out spl, seteador

	CLR contador
	CLR digito
	
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
	;TXCIE0 = 0 ==> NO habilito interrupción por transmisión complenta
	;UDRIE0 = 0 ==> No es necesario habilitar interruciones por registro vacío
	;RXEN0 = 1 ==> Habilito el receptor
	;TXEN0 = 0 ==> NO habilito el transmisor
	;UCSZ02 = 0 ==> N es de 8 bits
	;RXB80 TXB80 = 0 ==> No sirven
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
;------------------------------------------------------
;-----------------INTERRUPCIÓN GLOBAL------------------
	SEI

;Inicio de recepción, se pone el contador en 0 y se apunta el puntero X a donde se va a guardar el numero del jugador
;También se manda por los puertos la cantidad de digitos correctos bien posicionados y mal posicionados(previamente iniciados en 0)
juego_recepcion:
	OUT PORTB, cant_digitos_bien_posicionados
	OUT PORTC, cant_digitos_mal_posicionados
	CLR contador
	RCALL resetear_puntero_X_numero_jugador
;Loop de recepción, hasta que el contador no llegue a la longitud del numero requerida no sale
juego_recepcion_loop:
	CPI contador, longitud_numero_secreto
	BREQ juego_validacion
	RJMP juego_recepcion_loop
;Valdación del número ingresado, si es correcto sigue a proxima rutina, sino vuelve la fase de recepción
juego_validacion:
	;Transformo numero ingresado ascii a entero y valido el numero
	RCALL ascii_a_entero
	RCALL validar_numero
	;Si no está encendido el flag de numero validado se vuelve a la etapa de recepción
	SBRS GREG, 6
	RJMP juego_recepcion
	;Desactivo el receptor
	CLR seteador
	STS UCSR0B, seteador
;Se comparan ambos numeros, si la cantidad de digitos bien posicionados es igual a la longitud del numero entoncés salta a gano
juego_comparacion:
	RCALL comparar_numeros
	LDI comparador, longitud_numero_secreto
	CP cant_digitos_bien_posicionados, comparador
	BREQ gano
	LDI GREG, 0b00000100
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
gano_loop:
	RJMP gano_loop


recepcion_completa:
	;Se carga lo recibido en numero_jugador y se incrementa contador
	LDS receptor, UDR0
	ST X+, receptor
	INC contador
	RETI

;----------------------------------------------------------
;------------VALIDACIÓN DEL NUMERO INGRESADO---------------
;Llamar cuando el jugador termina de recibir el numero por completo 
;Verifica que los numeros sean validos (menores a 10)
;Si todos son validos se deshabilita el receptor
;Si alguno no es valido no se deshabilita el receptor
;En ambos casos se reinicia el puntero X
validar_numero:
	CLR contador
	RCALL resetear_puntero_X_numero_jugador
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
	ORI GREG, 0b01000000
	RCALL resetear_puntero_X_numero_jugador
	RJMP validar_numero_fin
numero_no_valido:
	RCALL resetear_puntero_X_numero_jugador
validar_numero_fin:
	CLR contador
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
;------------------COMPARACIÓN DE NUMEROS-------------------

;Compara numero_jugador y numero_secreto en SRAM
;Devuelve cantidad de digitos iguales bien posicionados y cantidad de digitos iguales mal posicionados 
;en los registros cant_digitos_bien_posicionados y cant_digitos_mal_posicionados
comparar_numeros:
	;Se llama función para que el puntero Y apunte al numero secreto en SRAM
	RCALL resetear_puntero_Y_numero_secreto
	;Se carga comparador con la longitud del numero (4) y seteador con 0 para inicializar registros de posiciones y cantidades
	LDI comparador, longitud_numero_secreto
	LDI seteador, 0
	MOV pos_numero_secreto, seteador
	MOV cant_digitos_bien_posicionados, seteador
	MOV cant_digitos_mal_posicionados, seteador

;Loop principal, va leyendo los digitos de numero_secreto a medida que se comparan
;con todos los dígitos de numero_jugador
leer_digito_numero_secreto:
	;Si se encuentra en la última posicion de numero_secreto salta a finalizar la comparación
	CP pos_numero_secreto, comparador
	BREQ comparar_numeros_fin
	;Se llama función para que el puntero X apunte al inicio de numero_jugador
	RCALL resetear_puntero_X_numero_jugador
	;Se lee el digito en numero_secreto
	LD digito_secreto, Y+
	;Se setea(y resetea) la posicion apuntada en numero_jugador
	MOV pos_numero_jugador, seteador

;Loop secundario, va leyendo los digitos de numero_jugador y comparando
leer_digito_numero_jugador:
	;Si se encuenrta en la última posicion de numero_jugador se incrementa la posicion de numero secreto y se vuelve a comenzar
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

;Se compara la posición de los digitos en cada numero, si son iguales salta a incrementar la cantidad bien posicionada
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

