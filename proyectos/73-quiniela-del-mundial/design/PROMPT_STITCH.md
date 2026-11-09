# Prompt para Google Stitch — #73 Quiniela del Mundial 2026

Disena una aplicacion web (movil y escritorio, tipografia Arial, espanol) para una Quiniela del Mundial 2026.
Colores de estado: verde = operando, ambar = alerta, rojo = falla. Fondo claro, encabezado azul marino.

Pantallas:
1. **Dashboard:** tarjetas de metricas (partidos en vivo/finalizados/programados, participantes, quinielas, pronosticos, rechazados, goles anulados VAR, fallas inyectadas, clientes SSE); ranking en vivo con selector de quiniela y buscador; lista de partidos con filtro por estado; panel de simulacion (participantes, quinielas, partidos, token admin, barra de progreso); formulario para pronosticar (participante, partido, goles local/visitante) y boton rojo "Matar proceso al azar".
2. **Detalle de partido:** equipos, marcador, estado (programado/en vivo/finalizado), cierre de predicciones, anulacion por VAR, pronosticos recibidos.
3. **Bitacora y alertas:** linea de tiempo de eventos (gol, VAR, cierre, caida y recuperacion de procesos) con colores de estado.

Exporta el zip desde Stitch y descomprimelo en `design/` junto con `DESIGN.md`.
