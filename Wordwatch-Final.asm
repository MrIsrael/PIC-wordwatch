; Reloj con palabras con PIC 16F886, 96 leds, 21 transistores 2N2222A para manjo de corriente, pines I/O del PIC activos altos, 
; control de tiempo con 1 temporizador interno (TMR0), modo set mediante interrupción externa con pulsador conectado a RB0
; Alimentación con adaptador de 8V y regulador 78LS05, Vin = +5V, pulsador de ajuste de intervalos de 5 minutos

; Diseñador: Israel Uribe
; Medellín, Abril 27 de 2020

; PROGRAMA FINAL / Se encienden todas las frases, en el orden correcto, con barrido de leds con TMR0. Cambio de frase con el pulsador RB0-INT; el antirrebote por software funciona bien.
;                  Se muestran las frases a 90 fps, sin parpadeo; cada led se enciende durante 400useg. No hay calentamiento en el regulador.
;				   El modo set funciona perfectamente!

; DEFINICIÓN DEL PROCESADOR Y FRECUENCIA DEL OSCILADOR EXTERNO:
    
	List		p=16F886										; Tipo de procesador
	include		"P16F886.INC"									; Definiciones de registros internos
   	#define		Fosc 4000000									; Velocidad de trabajo

    
; PALABRAS DE CONFIGURACIÓN:									; Ajusta los valores de las palabras de configuración durante el ensamblado. 
																; Los bits no empleados adquieren el valor por defecto.

    __config	_CONFIG1, _LVP_OFF&_PWRTE_ON&_WDT_OFF&_XT_OSC&_FCMEN_OFF	
																; Palabra 1 de configuración
																; Modo debugger deshabilitado (RB6 y RB7 son I/O digitales),
																; programación en bajo voltaje deshabilitada (RB3 es una I/O digital), 
																; Fail-Safe Clock Monitor deshabilitado, code protect desactivado, watchdog timer desactivado, 
																; oscilador externo tipo cristal de cuarzo, power-up timer activado.

    __config	_CONFIG2, _WRT_OFF&_BOR40V						; Palabra 2 de configuración
																; Se desactivó la protección contra escritura de la memoria flash de programa, 
																; Brown-out Reset seleccionado en 4.0V.


; REGISTROS DE USUARIO:											; Rango válido del primer banco de GPR's: h'20' hasta h'7F' inclusive (96 Bytes). Son 368 en total.
    
;MSE_Delay_V				equ	h'20'							; Dirección de inicio de los 3 registros empleados por la macro de temporización "MSE_Delay.inc".

salvar_status_int			equ	h'23'						 	; h'23': Dirección de inicio de otros GPR's del programa. 
salvar_W_int				equ	h'24'						
		
cont_segundos				equ	h'25'							; Con estos 2 contadores se registran 60 x 5 = 300 segundos = 5 minutos = 750000 desbordes de TMR0.
cont_minutos				equ	h'26'
display_horas				equ	h'27'							; Contador de intervalo de cambio de display cada hora. Tiene 12 valores posibles.
display_minutos				equ	h'28'							; Contador de intervalo de cambio de display cada 5 minutos. Tiene 11 valores posibles, pues en el cambio de hora (cero minutos) no se encienden leds.
contador_set				equ	h'29'

cont_1seg_TMR1				equ h'2A'							; TMR1 temporiza 500mseg; para temporizar 1 segundo, TMR1 debe desbordarse 2 veces. Con este registro se controla esa cuenta.

flags						equ h'2B'							; Registro de flags GPR.

; CONSTANTES:

; Bits del GPR "flags":
TMR0_FULL					equ 7								; Bit 7 = si está en 1, el TMR0 no se ha desbordado; si está en 0, TMR0 ya se desbordó (función inversa de INTCON,T0IF).
ONE_SEG						equ 6								; Bit 6 = si está en 1, TMR0 ya temporizó 1 segundo; si está en 0, todavía está temporizando.
CAMBIO_FRASE				equ 5								; Bit 5 = si está en 1, le indica al programa principal que se presionó el pulsador, y se debe entrar a modo set / mostrar una nueva frase.
SET_HORAS					equ 4								; Bit 4 = si está en 1, se está en modo set / configuración de horas.
SET_MINUTOS					equ 3								; Bit 3 = si está en 1, se está en modo set / configuración de minutos.


; VECTORES DE INICIO Y DE INTERRUPCIÓN:
		
			org		0x00
			goto	Inicio										; Vector de reset.
			org		0x04
			goto	inter										; Vector de interrupción. Indica salto a rutina de interrupción "inter".

			org		0x05										; Vector de inicio de grabación en memoria Flash del PIC.
			

; INCLUSIÓN DE SUBRUTINAS *.inc:

;			include	"MSE_Delay.inc"								; Incluir rutinas de temporización 
																; (PONER SIEMPRE ACÁ ESTE "include", que realmente es una subrutina).
			
; RUTINA DE INTERRUPCIÓN:

inter		bcf		INTCON,GIE									; Deshabilitar todas las interrupciones, hasta la instrucción retfie, que las habilitará de nuevo.
			movwf	salvar_W_int								; Se salva el contenido del registro "W" anterior a la interrupción.
			movf	STATUS,W
			movwf	salvar_status_int							; Se salva el contenido del registro "STATUS" anterior a la interrupción.

; CONTENIDO DE LA INTERRUPCIÓN:

			btfss	INTCON,INTE									; Interrupción por pulsación externa en RB0 habilitada? No se está haciendo temporización antirrebote?
			goto	inter2										; No, INTE deshabilitada. Se está haciendo la temporización antirrebote, de hecho. Verificar otros flags de interrupción.
			btfsc	INTCON,INTF									; Si, INTE habilitada. RB0 está pulsado y se encendió el flag INTF? (así INTE esté deshabilitado?)
			goto	inter_INTE									; Si. Las dos condiciones anteriores se cumplieron. Ir a la rutina de interrupción por pulsación externa en RB0.
inter2		btfsc	PIR1,TMR1IF									; Se entró a la rutina de interrupción por desborde del Timer1?
			goto	inter_T1IE									; Si. Ir a la rutina de interrupción por desborde de TMR1.
			btfsc	INTCON,T0IF									; Se entró a la rutina de interrupción por desborde del TMR0? --> Se entra aquí cada 400useg, siempre.
			goto	inter_T0IE									; Si. Ir a la rutina de interrupción por desborde de TMR0.
			goto	inter_out

inter_T1IE	incf	cont_1seg_TMR1,F

			movlw	d'1'										; El Timer 1 se desbordó ya 1 vez (500mseg)? Pasó ya medio segundo?
			xorwf	cont_1seg_TMR1,W
			btfsc	STATUS,Z									; No. Seguir.
			bsf		INTCON,INTE									; Si. Habilitar la interrupción por pulsación externa en RB0, pues en este punto la temporización antirrebote ya obligatoriamente terminó.

			movlw	d'2'										; El Timer 1 se desbordó ya 2 veces seguidas (500mseg c/u)? Pasó ya 1 segundo?
			xorwf	cont_1seg_TMR1,W
			btfss	STATUS,Z
			goto	inter_set_TMR1								; No. Configurar nuevamente TMR1 para que temporice 500mseg.
			clrf	cont_1seg_TMR1								; Si. Reiniciar el contador.
			bsf		flags,ONE_SEG								; También activar el flag correspondiente (temporización de 1 segundo completada).

inter_set_TMR1
			movlw	b'00001011'
			movwf	TMR1H										; Valor de carga inicial del Timer 1 (de 16 bits), para temporizar 500000us = 0.5seg
			movlw	b'11011100'
			movwf	TMR1L
			bcf		PIR1,TMR1IF									; Borrar flag de interrupción por desbordamiento del Timer 1.
			movlw	b'00110001'									; Configuración del Timer 1: Siempre contando, prescaler 1:8, oscilador LP apagado, pulsos por oscilador interno (Fosc/4), Habilitado (comienza el conteo)
			movwf	T1CON
			goto	inter_out

inter_T0IE	bcf		STATUS,RP1
			bcf		STATUS,RP0									; Selecciona banco 0
			bcf		INTCON,INTF									; Limpiar flag de interrupción por pulsación externa en RB0, SIEMPRE
			bcf		INTCON,T0IF									; Limpiar manualmente flag de interrupción por desbordamiento del TMR0
			movlw	d'206'										; Valor de carga inicial de TMR0. El desbordamiento se producirá siempre en (256 - 206) x 8 = 50 x 8 = 400 ciclos de instrucción, 
			movwf	TMR0										; es decir 400us (con XTAL de 4MHz), siendo en ese momento INTCON,T0IF = 1. Debe limpiarse por software. El PRESCALER se configura en la rutina
																; de interrupción, y DEBE VOLVER A CONFIGURARSE CADA VEZ QUE SE ESCRIBE MANUALMENTE UN VALOR ENCIMA DEL REGISTRO TMR0. Hay que ir entonces al
																; banco 1 a configurar el prescaler en el registro OPTION.
			bsf		STATUS,RP0									; Selecciona banco 1
			movlw	b'10000010'									; Se desactivan las resistencias de pull-up de la puerta B, flanco descendente activo para interrupción externa,
			movwf	OPTION_REG									; Volver a configurar el divisor de frecuencia (prescaler) en 1:8 para el TMR0.
			bcf		STATUS,RP0									; Selecciona banco 0

			bcf		flags,TMR0_FULL								; Limpiar flag GPR de desbordamiento del TMR0
			goto	inter_out

inter_INTE	clrf	cont_1seg_TMR1								; Inicializar contador para que TMR1 temporice obligatoriamente 500mseg antes de desactivar el antirrebote.
			bcf		INTCON,INTE									; Deshabilitar temporalmente la interrupción por pulsación externa en RB0, mientras dure la temporización antirrebote
			bcf		INTCON,INTF									; Limpiar flag de interrupción por pulsación externa en RB0
			bsf		flags,CAMBIO_FRASE							; Habilitar flag que le indica al programa principal que se presionó el pulsador, y se debe mostrar una nueva frase.
			goto	inter_set_TMR1								; Reinicializar cuenta de 0.5 segundos del Timer1, para que el antirrebote dure hasta que se desborde (y se active PIR1,TMR1IF)

inter_out	movf	salvar_status_int,W
			movwf	STATUS										; Se recupera el contenido del registro "STATUS" anterior a la interrupción.
			movf	salvar_W_int,W								; Se recupera el contenido del registro "W" anterior a la interrupción.
			retfie												; Automáticamente setea INTCON,GIE = 1, habilitando de nuevo las interrupciones.

			
; SUBRUTINAS DE USUARIO:

es_la
			call	fila_1_on									; Filas y columnas a activar, y en qué orden, para cada posible hora y múltiplo de 5 minutos, en palabras.
			call	col_1_on
			call	dejar_led_on								; Dejar el led activo encendido hasta que TMR0 se desborde
			call	col_1_off
			call	col_2_on
			call	dejar_led_on
			call	col_2_off
			call	col_6_on
			call	dejar_led_on
			call	col_6_off
			call	col_7_on
			call	dejar_led_on
			call	col_7_off
			call	fila_1_off
			return
			
son_las
			call	fila_1_on
			call	col_2_on
			call	dejar_led_on
			call	col_2_off
			call	col_3_on
			call	dejar_led_on
			call	col_3_off
			call	col_4_on
			call	dejar_led_on
			call	col_4_off
			call	col_6_on
			call	dejar_led_on
			call	col_6_off
			call	col_7_on
			call	dejar_led_on
			call	col_7_off
			call	col_8_on
			call	dejar_led_on
			call	col_8_off
			call	fila_1_off
			return

una
			call	fila_1_on
			call	col_9_on
			call	dejar_led_on
			call	col_9_off
			call	col_10_on
			call	dejar_led_on
			call	col_10_off
			call	col_11_on
			call	dejar_led_on
			call	col_11_off
			call	fila_1_off
			return

dos
			call	fila_2_on
			call	col_1_on
			call	dejar_led_on
			call	col_1_off
			call	col_2_on
			call	dejar_led_on
			call	col_2_off
			call	col_3_on
			call	dejar_led_on
			call	col_3_off
			call	fila_2_off
			return

tres
			call	fila_2_on
			call	col_5_on
			call	dejar_led_on
			call	col_5_off
			call	col_6_on
			call	dejar_led_on
			call	col_6_off
			call	col_7_on
			call	dejar_led_on
			call	col_7_off
			call	col_8_on
			call	dejar_led_on
			call	col_8_off
			call	fila_2_off
			return
			
cuatro
			call	fila_3_on
			call	col_1_on
			call	dejar_led_on
			call	col_1_off
			call	col_2_on
			call	dejar_led_on
			call	col_2_off
			call	col_3_on
			call	dejar_led_on
			call	col_3_off
			call	col_4_on
			call	dejar_led_on
			call	col_4_off
			call	col_5_on
			call	dejar_led_on
			call	col_5_off
			call	col_6_on
			call	dejar_led_on
			call	col_6_off
			call	fila_3_off
			return
			
cinco
			call	fila_3_on
			call	col_7_on
			call	dejar_led_on
			call	col_7_off
			call	col_8_on
			call	dejar_led_on
			call	col_8_off
			call	col_9_on
			call	dejar_led_on
			call	col_9_off
			call	col_10_on
			call	dejar_led_on
			call	col_10_off
			call	col_11_on
			call	dejar_led_on
			call	col_11_off
			call	fila_3_off
			return

seis
			call	fila_4_on
			call	col_1_on
			call	dejar_led_on
			call	col_1_off
			call	col_2_on
			call	dejar_led_on
			call	col_2_off
			call	col_3_on
			call	dejar_led_on
			call	col_3_off
			call	col_4_on
			call	dejar_led_on
			call	col_4_off
			call	fila_4_off
			return
			
siete
			call	fila_4_on
			call	col_6_on
			call	dejar_led_on
			call	col_6_off
			call	col_7_on
			call	dejar_led_on
			call	col_7_off
			call	col_8_on
			call	dejar_led_on
			call	col_8_off
			call	col_9_on
			call	dejar_led_on
			call	col_9_off
			call	col_10_on
			call	dejar_led_on
			call	col_10_off
			call	fila_4_off
			return
			
ocho
			call	fila_5_on
			call	col_1_on
			call	dejar_led_on
			call	col_1_off
			call	col_2_on
			call	dejar_led_on
			call	col_2_off
			call	col_3_on
			call	dejar_led_on
			call	col_3_off
			call	col_4_on
			call	dejar_led_on
			call	col_4_off
			call	fila_5_off
			return

nueve
			call	fila_5_on
			call	col_5_on
			call	dejar_led_on
			call	col_5_off
			call	col_6_on
			call	dejar_led_on
			call	col_6_off
			call	col_7_on
			call	dejar_led_on
			call	col_7_off
			call	col_8_on
			call	dejar_led_on
			call	col_8_off
			call	col_9_on
			call	dejar_led_on
			call	col_9_off
			call	fila_5_off
			return
			
diez
			call	fila_6_on
			call	col_3_on
			call	dejar_led_on
			call	col_3_off
			call	col_4_on
			call	dejar_led_on
			call	col_4_off
			call	col_5_on
			call	dejar_led_on
			call	col_5_off
			call	col_6_on
			call	dejar_led_on
			call	col_6_off
			call	fila_6_off
			return
			
once
			call	fila_6_on
			call	col_8_on
			call	dejar_led_on
			call	col_8_off
			call	col_9_on
			call	dejar_led_on
			call	col_9_off
			call	col_10_on
			call	dejar_led_on
			call	col_10_off
			call	col_11_on
			call	dejar_led_on
			call	col_11_off
			call	fila_6_off
			return
			
doce
			call	fila_7_on
			call	col_1_on
			call	dejar_led_on
			call	col_1_off
			call	col_2_on
			call	dejar_led_on
			call	col_2_off
			call	col_3_on
			call	dejar_led_on
			call	col_3_off
			call	col_4_on
			call	dejar_led_on
			call	col_4_off
			call	fila_7_off
			return

y_
			call	fila_7_on
			call	col_6_on
			call	dejar_led_on
			call	col_6_off
			call	fila_7_off
			return

menos
			call	fila_7_on
			call	col_7_on
			call	dejar_led_on
			call	col_7_off
			call	col_8_on
			call	dejar_led_on
			call	col_8_off
			call	col_9_on
			call	dejar_led_on
			call	col_9_off
			call	col_10_on
			call	dejar_led_on
			call	col_10_off
			call	col_11_on
			call	dejar_led_on
			call	col_11_off
			call	fila_7_off
			return
			
m_cinco
			call	fila_9_on
			call	col_7_on
			call	dejar_led_on
			call	col_7_off
			call	col_8_on
			call	dejar_led_on
			call	col_8_off
			call	col_9_on
			call	dejar_led_on
			call	col_9_off
			call	col_10_on
			call	dejar_led_on
			call	col_10_off
			call	col_11_on
			call	dejar_led_on
			call	col_11_off
			call	fila_9_off
			return
			
m_diez
			call	fila_8_on
			call	col_8_on
			call	dejar_led_on
			call	col_8_off
			call	col_9_on
			call	dejar_led_on
			call	col_9_off
			call	col_10_on
			call	dejar_led_on
			call	col_10_off
			call	col_11_on
			call	dejar_led_on
			call	col_11_off
			call	fila_8_off
			return
			
cuarto
			call	fila_10_on
			call	col_6_on
			call	dejar_led_on
			call	col_6_off
			call	col_7_on
			call	dejar_led_on
			call	col_7_off
			call	col_8_on
			call	dejar_led_on
			call	col_8_off
			call	col_9_on
			call	dejar_led_on
			call	col_9_off
			call	col_10_on
			call	dejar_led_on
			call	col_10_off
			call	col_11_on
			call	dejar_led_on
			call	col_11_off
			call	fila_10_off
			return
			
veinte
			call	fila_8_on
			call	col_2_on
			call	dejar_led_on
			call	col_2_off
			call	col_3_on
			call	dejar_led_on
			call	col_3_off
			call	col_4_on
			call	dejar_led_on
			call	col_4_off
			call	col_5_on
			call	dejar_led_on
			call	col_5_off
			call	col_6_on
			call	dejar_led_on
			call	col_6_off
			call	col_7_on
			call	dejar_led_on
			call	col_7_off
			call	fila_8_off
			return
			
veinticinco
			call	fila_9_on
			call	col_1_on
			call	dejar_led_on
			call	col_1_off
			call	col_2_on
			call	dejar_led_on
			call	col_2_off
			call	col_3_on
			call	dejar_led_on
			call	col_3_off
			call	col_4_on
			call	dejar_led_on
			call	col_4_off
			call	col_5_on
			call	dejar_led_on
			call	col_5_off
			call	col_6_on
			call	dejar_led_on
			call	col_6_off
			call	col_7_on
			call	dejar_led_on
			call	col_7_off
			call	col_8_on
			call	dejar_led_on
			call	col_8_off
			call	col_9_on
			call	dejar_led_on
			call	col_9_off
			call	col_10_on
			call	dejar_led_on
			call	col_10_off
			call	col_11_on
			call	dejar_led_on
			call	col_11_off
			call	fila_9_off
			return
			
media
			call	fila_10_on
			call	col_1_on
			call	dejar_led_on
			call	col_1_off
			call	col_2_on
			call	dejar_led_on
			call	col_2_off
			call	col_3_on
			call	dejar_led_on
			call	col_3_off
			call	col_4_on
			call	dejar_led_on
			call	col_4_off
			call	col_5_on
			call	dejar_led_on
			call	col_5_off
			call	fila_10_off
			return
			
			
col_1_on	bsf		PORTB,7										; Subrutinas de des/habilitación de las bases de los transistores 2N2222A, que controlan el paso de corriente a
																; los ÁNODOS de los leds. Son 11 columnas (11 transistores, 11 pines del PIC).
			bsf		flags,TMR0_FULL								; Setear flag GPR de desbordamiento del TMR0
			return

col_1_off	bcf		PORTB,7
			return
																
col_2_on	bsf		PORTB,6
			bsf		flags,TMR0_FULL								; Setear flag GPR de desbordamiento del TMR0
			return

col_2_off	bcf		PORTB,6
			return

col_3_on	bsf		PORTB,5
			bsf		flags,TMR0_FULL								; Setear flag GPR de desbordamiento del TMR0
			return

col_3_off	bcf		PORTB,5
			return

col_4_on	bsf		PORTB,4
			bsf		flags,TMR0_FULL								; Setear flag GPR de desbordamiento del TMR0
			return

col_4_off	bcf		PORTB,4
			return

col_5_on	bsf		PORTB,3
			bsf		flags,TMR0_FULL								; Setear flag GPR de desbordamiento del TMR0
			return

col_5_off	bcf		PORTB,3
			return

col_6_on	bsf		PORTB,2
			bsf		flags,TMR0_FULL								; Setear flag GPR de desbordamiento del TMR0
			return

col_6_off	bcf		PORTB,2
			return

col_7_on	bsf		PORTB,1
			bsf		flags,TMR0_FULL								; Setear flag GPR de desbordamiento del TMR0
			return

col_7_off	bcf		PORTB,1
			return

col_8_on	bsf		PORTC,7
			bsf		flags,TMR0_FULL								; Setear flag GPR de desbordamiento del TMR0
			return

col_8_off	bcf		PORTC,7
			return

col_9_on	bsf		PORTC,6
			bsf		flags,TMR0_FULL								; Setear flag GPR de desbordamiento del TMR0
			return

col_9_off	bcf		PORTC,6
			return

col_10_on	bsf		PORTC,5
			bsf		flags,TMR0_FULL								; Setear flag GPR de desbordamiento del TMR0
			return

col_10_off	bcf		PORTC,5
			return

col_11_on	bsf		PORTC,4
			bsf		flags,TMR0_FULL								; Setear flag GPR de desbordamiento del TMR0
			return

col_11_off	bcf		PORTC,4
			return


fila_1_on	bsf		PORTA,0										; Subrutinas de des/habilitación de las bases de los transistores 2N2222A, que controlan el paso de corriente a
			return												; los CÁTODOS de los leds. Son 10 filas (10 transistores, 10 pines del PIC).

fila_1_off	bcf		PORTA,0
			return

fila_2_on	bsf		PORTA,1
			return

fila_2_off	bcf		PORTA,1
			return

fila_3_on	bsf		PORTA,2
			return

fila_3_off	bcf		PORTA,2
			return

fila_4_on	bsf		PORTA,3
			return

fila_4_off	bcf		PORTA,3
			return

fila_5_on	bsf		PORTA,4
			return

fila_5_off	bcf		PORTA,4
			return

fila_6_on	bsf		PORTA,5
			return

fila_6_off	bcf		PORTA,5
			return

fila_7_on	bsf		PORTC,0
			return

fila_7_off	bcf		PORTC,0
			return

fila_8_on	bsf		PORTC,1
			return

fila_8_off	bcf		PORTC,1
			return
			
fila_9_on	bsf		PORTC,2
			return

fila_9_off	bcf		PORTC,2
			return

fila_10_on	bsf		PORTC,3
			return

fila_10_off	bcf		PORTC,3
			return


apagar_leds														; Subrutina que apaga todos los leds (solo para modo set).
			call	col_1_off
			call	col_2_off
			call	col_3_off
			call	col_4_off
			call	col_5_off
			call	col_6_off
			call	col_7_off
			call	col_8_off
			call	col_9_off
			call	col_10_off
			call	col_11_off
			call	fila_1_off
			call	fila_2_off
			call	fila_3_off
			call	fila_4_off
			call	fila_5_off
			call	fila_6_off
			call	fila_7_off
			call	fila_8_off
			call	fila_9_off
			call	fila_10_off
			return


mostrar_reloj													; Subrutina que muestra la hora en el display de 96 leds.
			btfss	flags,SET_MINUTOS							; El programa está en modo set y se están configurando los minutos?
			goto	MR1											; No. Mostrar las horas (flags,SET_MINUTOS = 0 también en modo reloj normal).
			goto	MR13C										; Si. Ir a mostrar sólo los minutos.

MR1			movlw	d'1'										; Empezar verificando las horas.
			xorwf	display_horas,W
			btfss	STATUS,Z									; Es la una y algo?
			goto	MR2											; No. Seguir verificando.
			call	es_la										; Si.
			call	una
MR2			movlw	d'2'
			xorwf	display_horas,W
			btfss	STATUS,Z									; Son las dos y algo?
			goto	MR3											; No. Seguir verificando.
			call	son_las										; Si.
			call	dos
MR3			movlw	d'3'
			xorwf	display_horas,W
			btfss	STATUS,Z									; Son las tres y algo?
			goto	MR4											; No. Seguir verificando.
			call	son_las										; Si.
			call	tres
MR4			movlw	d'4'
			xorwf	display_horas,W
			btfss	STATUS,Z									; Son las cuatro y algo?
			goto	MR5											; No. Seguir verificando.
			call	son_las										; Si.
			call	cuatro
MR5			movlw	d'5'
			xorwf	display_horas,W
			btfss	STATUS,Z									; Son las cinco y algo?
			goto	MR6											; No. Seguir verificando.
			call	son_las										; Si.
			call	cinco
MR6			movlw	d'6'
			xorwf	display_horas,W
			btfss	STATUS,Z									; Son las seis y algo?
			goto	MR7											; No. Seguir verificando.
			call	son_las										; Si.
			call	seis
MR7			movlw	d'7'
			xorwf	display_horas,W
			btfss	STATUS,Z									; Son las siete y algo?
			goto	MR8											; No. Seguir verificando.
			call	son_las										; Si.
			call	siete
MR8			movlw	d'8'
			xorwf	display_horas,W
			btfss	STATUS,Z									; Son las ocho y algo?
			goto	MR9											; No. Seguir verificando.
			call	son_las										; Si.
			call	ocho
MR9			movlw	d'9'
			xorwf	display_horas,W
			btfss	STATUS,Z									; Son las nueve y algo?
			goto	MR10										; No. Seguir verificando.
			call	son_las										; Si.
			call	nueve
MR10		movlw	d'10'
			xorwf	display_horas,W
			btfss	STATUS,Z									; Son las diez y algo?
			goto	MR11										; No. Seguir verificando.
			call	son_las										; Si.
			call	diez
MR11		movlw	d'11'
			xorwf	display_horas,W
			btfss	STATUS,Z									; Son las once y algo?
			goto	MR12										; No. Seguir verificando.
			call	son_las										; Si.
			call	once
MR12		movlw	d'12'
			xorwf	display_horas,W
			btfss	STATUS,Z									; Son las doce y algo?
			goto	MR13										; No. Seguir verificando los minutos.
			call	son_las										; Si.
			call	doce

MR13B		movlw	d'2'										; Verificar ahora los minutos. Si "display_minutos" = 1, serían CERO minutos; no hay que mostrar ninguna frase de minutos.
			xorwf	display_minutos,W
			btfss	STATUS,Z									; Son las y cinco?
			goto	MR14										; No. Seguir verificando.
			call	y_											; Si.
			call	m_cinco
MR14		movlw	d'3'
			xorwf	display_minutos,W
			btfss	STATUS,Z									; Son las y diez?
			goto	MR15										; No. Seguir verificando.
			call	y_											; Si.
			call	m_diez
MR15		movlw	d'4'
			xorwf	display_minutos,W
			btfss	STATUS,Z									; Son las y cuarto?
			goto	MR16										; No. Seguir verificando.
			call	y_											; Si.
			call	cuarto
MR16		movlw	d'5'
			xorwf	display_minutos,W
			btfss	STATUS,Z									; Son las y veinte?
			goto	MR17										; No. Seguir verificando.
			call	y_											; Si.
			call	veinte
MR17		movlw	d'6'
			xorwf	display_minutos,W
			btfss	STATUS,Z									; Son las y veinticinco?
			goto	MR18										; No. Seguir verificando.
			call	y_											; Si.
			call	veinticinco
MR18		movlw	d'7'
			xorwf	display_minutos,W
			btfss	STATUS,Z									; Son las y media?
			goto	MR19										; No. Seguir verificando.
			call	y_											; Si.
			call	media
MR19		movlw	d'8'
			xorwf	display_minutos,W
			btfss	STATUS,Z									; Son las y treinta y cinco?
			goto	MR20										; No. Seguir verificando.
			call	menos										; Si.
			call	veinticinco
MR20		movlw	d'9'
			xorwf	display_minutos,W
			btfss	STATUS,Z									; Son las y cuarenta?
			goto	MR21										; No. Seguir verificando.
			call	menos										; Si.
			call	veinte
MR21		movlw	d'10'
			xorwf	display_minutos,W
			btfss	STATUS,Z									; Son las y cuarenta y cinco?
			goto	MR22										; No. Seguir verificando.
			call	menos										; Si.
			call	cuarto
MR22		movlw	d'11'
			xorwf	display_minutos,W
			btfss	STATUS,Z									; Son las y cincuenta?
			goto	MR23										; No. Seguir verificando.
			call	menos										; Si.
			call	m_diez
MR23		movlw	d'12'
			xorwf	display_minutos,W
			btfss	STATUS,Z									; Son las y cincuenta y cinco?
			return
			call	menos										; Si.
			call	m_cinco
			return												; No. Salir de la subrutina.

			
; CONFIGURACIÓN DE REGISTROS DE CONTROL:

Inicio		bsf		STATUS,RP0
			bsf		STATUS,RP1									; Selecciona banco 3
			clrf	ANSEL										; Puerta A digital (NO entradas análogas)
			clrf	ANSELH										; Puerta B digital (NO entradas análogas)

			bcf		STATUS,RP1									; Selecciona banco 1
			movlw	b'00000001'									; RB7:RB1 se configuran como salidas (bus Columnas 1 a 7)
			movwf	TRISB										; RB0 se configura como entrada (pulsador de ajuste)
			clrf	TRISC										; RC7:RC0 se configuran como salidas (bus Columnas 8 a 11, bus Filas 10 a 7)
			clrf	TRISA										; RA0:RA5 se configuran como salidas (bus Filas 1 a 6)
			bsf		PIE1,TMR1IE									; Se permite interrupción por desbordamiento del Timer 1 (TMR1IE)

			bcf		STATUS,RP0									; Selecciona banco 0
			movlw	b'11110000'									; Se permite interrupción por desbordamiento del TMR0 (T0IE), interrupción externa por pulsador activo bajo en RB0 (INTE), de los periféricos
			movwf	INTCON										; externos (PEIE) y la global (GIE). Flags borrados por software.
			movlw	d'206'										; Valor de carga inicial de TMR0. El desbordamiento se producirá siempre en (256 - 206) x 8 = 50 x 8 = 400 ciclos de instrucción, 
			movwf	TMR0										; es decir 400us (con XTAL de 4MHz), siendo en ese momento INTCON,T0IF = 1. Debe limpiarse por software. El PRESCALER se configura en la rutina
																; de interrupción, y DEBE VOLVER A CONFIGURARSE CADA VEZ QUE SE ESCRIBE MANUALMENTE UN VALOR ENCIMA DEL REGISTRO TMR0. Hay que ir entonces al
																; banco 1 a configurar el prescaler en el registro OPTION.

			bsf		STATUS,RP0									; Selecciona banco 1
			movlw	b'10000010'									; Se desactivan las resistencias de pull-up de la puerta B, flanco descendente activo para interrupción externa,
			movwf	OPTION_REG									; pulsos para TMR0 provenientes de ciclo de intrucción interno (Fosc / 4 = 4MHz / 4 = 1MHz --> 1 useg),
																; divisor de frecuencia (prescaler) asignado al TMR0 (NO al WDT), ajustado por defecto en 1:8 para el TMR0.
																; Cuando se usa como Timer, TMR0 se incrementa cada ciclo de instrucción ((1 / Fosc) x 4), si no se configura el prescaler. Debe ponerse a 0
																; el bit T0CS del registro OPTION. Cuando se escribe un valor sobre el registro TMR0, el incremento automático se inhibe durante 2 ciclos de
																; instrucción, inmediatamente después de la escritura, y se limpia el prescaler (debe configurarse de nuevo su tasa para el TMR0).

			bcf		STATUS,RP0									; Selecciona banco 0
			bcf		PIR1,TMR1IF									; Borrar flag de interrupción por desbordamiento del Timer 1.
			movlw	b'00001011'
			movwf	TMR1H										; Valor de carga inicial del Timer 1 (de 16 bits), para temporizar 500000us = 0.5seg
			movlw	b'11011100'
			movwf	TMR1L
			movlw	b'00110001'									; Configuración del Timer 1: Siempre contando, prescaler 1:8, oscilador LP apagado, pulsos por oscilador interno (Fosc/4), Habilitado (comienza el conteo ya)
			movwf	T1CON

			clrf	flags										; Limpiar flags GPR
			clrf	cont_1seg_TMR1								; Limpiar registro de conteo de 2 desbordes de TMR1 = temporización de 1 segundo.
			clrf	cont_segundos								; Reiniciar contadores de 5 minutos transcurridos.
			clrf	cont_minutos

			clrf	PORTB										; Las salidas del puerto B van directo a las bases de los transistores 2N2222A que activan los ánodos de los leds: Se encienden con 1, se apagan con 0
			clrf	PORTC										; Los pines del puerto C van directo a las bases de los transistores 2N2222A que activan los ánodos (y cátodos) de los leds: Se encienden con 1, se apagan con 0
			clrf	PORTA										; Los pines del puerto A van directo a las bases de los transistores 2N2222A que activan los cátodos de los leds: Se encienden con 1, se apagan con 0
																; La entrada del pulsador de set (RB0) es activa baja.
		
; CÓDIGO DE USUARIO:

Reloj_init	movlw	d'1'
			movwf	display_horas								; Al encender, empezar mostrando el texto "ES LA UNA", correspondiente a:
			movwf	display_minutos								; display_horas = 1 & display_minutos = 1

Reloj		call	mostrar_reloj								; Mostrar hora actualizada.

			btfsc	flags,CAMBIO_FRASE							; Se oprimió el pulsador externo conectado a RB0?
			goto	Modo_set									; Si. Ir a modo set.

			btfss	flags,ONE_SEG								; Ya TMR0 temporizó 1 segundo?
			goto	Reloj										; Aún no. Seguir mostrando la hora actual.
			bcf		flags,ONE_SEG								; Si. Limpiar el flag correspondiente.

			incf	cont_segundos,F								; Incrementar contador de segundos.
			movlw	d'60'
			xorwf	cont_segundos,W								; Ya pasó 1 minuto?
			btfss	STATUS,Z
			goto	Reloj										; Aún no. Seguir mostrando la hora actual.
			clrf	cont_segundos								; Si. Resetear contador de segundos e incrementar el de minutos.

			incf	cont_minutos,F
			movlw	d'5'										; Ya pasaron 5 minutos?
			xorwf	cont_minutos,W
			btfss	STATUS,Z
			goto	Reloj										; Aún no. Seguir mostrando la hora actual.
			clrf	cont_minutos								; Si. Resetear contador de minutos e incrementar los contadores de display en los leds.

			incf	display_minutos,F							; Incrementar el contador de minutos.
			movlw	d'8'
			xorwf	display_minutos,W							; Son las X menos veinticinco? Debería cambiar la frase de horas!
			btfsc	STATUS,Z
			incf	display_horas,F								; Si. Incrementar el contador de horas.

			movlw	d'13'
			xorwf	display_horas,W								; Ya pasaron 12 horas?
			btfss	STATUS,Z
			goto	RJ2											; No. continuar.

			movlw	d'1'										; Si. Reiniciar el contador de horas, a "ES LA UNA".
			movwf	display_horas

RJ2			movlw	d'13'
			xorwf	display_minutos,W							; Ya ocurrió un cambio de hora? Son las X en punto?
			btfss	STATUS,Z
			goto	Reloj										; No. Volver a mostrar la hora actualizada.
			
			movlw	d'1'
			movwf	display_minutos								; Si. Reinicializar el contador de minutos a su valor mínimo por defecto: Serían CERO minutos; no hay que mostrar ninguna frase de minutos.
			goto	Reloj										; Volver a mostrar la hora actualizada.


Modo_set
			bcf		flags,CAMBIO_FRASE							; Limpiar el flag que indica que el pulsador externo conectado a RB0 fue presionado.
			bcf		flags,ONE_SEG								; Limpiar el flag que indica que ya TMR0 temporizó 1 segundo.
			bsf		flags,SET_HORAS								; Indicarle al programa que se configurarán primero las horas.
			bcf		flags,SET_MINUTOS							; Después de 10 segundos sin oprimir el pulsador, este bit indicará que se deben configurar los minutos.
			clrf	cont_1seg_TMR1								; Limpiar registro de conteo de 2 desbordes de TMR1 = temporización de 1 segundo.
			clrf	cont_segundos								; Reiniciar contadores de 5 minutos transcurridos.
			clrf	cont_minutos
			clrf	contador_set								; Inicializar contador de tiempo para modo set.

MS2			call	apagar_leds									; Apagar leds durante 1 segundo.

			btfsc	flags,CAMBIO_FRASE							; Se oprimió el pulsador?
			goto	MS3											; Si. Incrementar el contador de horas.

			btfss	flags,ONE_SEG								; Ya TMR0 temporizó 1 segundo?
			goto	MS2											; Aún no.
			bcf		flags,ONE_SEG								; Si. Limpiar el flag correspondiente.

			incf	contador_set,F

			movlw	d'10'
			xorwf	contador_set,W								; Pasaron ya 10 segundos desde que se entró a modo set?
			btfss	STATUS,Z
			goto	MS4

			clrf	contador_set								; Reiniciar contador de 10 segundos.
			btfss	flags,SET_MINUTOS							; Se estaban configurando los minutos?
			goto	MS5

			bcf		flags,SET_HORAS								; Si, y ya pasaron 10 segundos sin presionar el pulsador. Salir de modo set y volver a modo reloj normal.
			bcf		flags,SET_MINUTOS							; Ambos flags deben limpiarse, para poder recorrer la subrutina "mostrar_reloj" completamente.
			goto	Reloj

MS5			bcf		flags,SET_HORAS								; No, se estaban configurando las horas. Pasar a configurar los minutos.
			bsf		flags,SET_MINUTOS
			movlw	d'1'
			movwf	contador_set								; Poner a 1 el contador de segundos, para que se enciendan los leds sólo durante los próximos 2 segundos, y el efecto de parpadeo continúe.

MS4			call	mostrar_reloj								; Mostrar hora actualizada.

			btfsc	flags,CAMBIO_FRASE							; Se oprimió el pulsador?
			goto	MS3											; Si. Incrementar el contador de horas.

			btfss	flags,ONE_SEG								; Ya TMR0 temporizó 1 segundo?
			goto	MS4											; Aún no.
			bcf		flags,ONE_SEG								; Si. Limpiar el flag correspondiente.

			incf	contador_set,F

			movlw	d'3'
			xorwf	contador_set,W								; Ya pasaron 2 segundos mostrando la hora?
			btfsc	STATUS,Z
			goto	MS2											; Si. Volver a apagar leds durante 1 segundo.

			movlw	d'6'
			xorwf	contador_set,W								; Segunda vez que pasan 2 segundos mostrando la hora?
			btfsc	STATUS,Z
			goto	MS2											; Si. Volver a apagar leds durante 1 segundo.

			movlw	d'9'
			xorwf	contador_set,W								; Tercera vez que pasan 2 segundos mostrando la hora?
			btfsc	STATUS,Z
			goto	MS2											; Si. Volver a apagar leds durante 1 segundo.

			goto	MS4											; No. Mostrar hora actualizada.

MS3			bcf		flags,CAMBIO_FRASE							; Limpiar el flag que indica que el pulsador externo conectado a RB0 fue presionado.
			clrf	cont_1seg_TMR1								; Limpiar registro de conteo de 2 desbordes de TMR1 = temporización de 1 segundo.
			bcf		flags,ONE_SEG								; Limpiar el flag que indica que ya TMR0 temporizó 1 segundo.

			btfss	flags,SET_MINUTOS							; Se están configurando los minutos?
			goto	MS6											; No.

			incf	display_minutos,F							; Incrementar el contador de minutos.

			movlw	d'13'
			xorwf	display_minutos,W							; Ya ocurrió un cambio de hora? Son las X en punto?
			btfss	STATUS,Z
			goto	MS7											; No. Volver a mostrar la hora actualizada.
			
			movlw	d'1'
			movwf	display_minutos								; Si. Reinicializar el contador de minutos a su valor mínimo por defecto: Serían CERO minutos; no hay que mostrar ninguna frase de minutos.
			goto	MS7											; Volver a mostrar la hora actualizada.

MS6			btfss	flags,SET_HORAS								; Se están configurando las horas?
			goto	MS7											; No. Volver a mostrar la hora actualizada.

			incf	display_horas,F								; Si. Incrementar el contador de horas.

			movlw	d'13'
			xorwf	display_horas,W								; Ya pasaron 12 horas?
			btfss	STATUS,Z
			goto	MS7											; No. Volver a mostrar la hora actualizada.

			movlw	d'1'										; Si. Reiniciar el contador de horas, a "ES LA UNA".
			movwf	display_horas

MS7			movlw	d'1'
			movwf	contador_set								; Poner a 1 el contador de segundos, para que se enciendan los leds sólo durante los próximos 2 segundos, y el efecto de parpadeo continúe.

			goto	MS4											; Mostrar hora actualizada.

			end													; Fin del programa.
