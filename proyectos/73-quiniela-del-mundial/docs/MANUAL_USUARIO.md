# Manual de usuario — Quiniela del Mundial 2026

## 1. Acceso
Abre `http://<IP-de-la-instancia>:8080` en el navegador.

## 2. Dashboard
Muestra tarjetas con el estado en tiempo real, el ranking de la quiniela elegida (busca un participante por ID, p. ej. U0042) y la lista de partidos filtrable por estado.

## 3. Pronosticar
En "Pronosticar" escribe el participante, el numero de partido y los goles; pulsa "Enviar pronostico". El servidor rechaza pronosticos despues del inicio del partido, sin importar la hora de tu navegador.

## 4. Simulacion
Indica participantes, quinielas y partidos, escribe el token admin y pulsa "Iniciar simulacion". La barra muestra el avance y al terminar aparece el reporte.

## 5. Inyectar fallas
"Matar proceso al azar" termina un proceso; el supervisor lo reinicia y el ranking debe permanecer identico.

## 6. Detalle y bitacora
Las pestañas "Detalle de partido" y "Bitacora y alertas" muestran el historial de eventos (goles, VAR, cierres, caidas y recuperaciones).

## 7. Solucion de problemas
Si la pagina no carga, verifica que el puerto 8080 este abierto en el Security Group y que el nodo este corriendo (`rebar3 shell`).
