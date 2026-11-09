---
name: Mundial 2026 Telemetry Quiniela
colors:
  surface: '#f7f9fb'
  surface-dim: '#d8dadc'
  surface-bright: '#f7f9fb'
  surface-container-lowest: '#ffffff'
  surface-container-low: '#f2f4f6'
  surface-container: '#eceef0'
  surface-container-high: '#e6e8ea'
  surface-container-highest: '#e0e3e5'
  on-surface: '#191c1e'
  on-surface-variant: '#45464d'
  inverse-surface: '#2d3133'
  inverse-on-surface: '#eff1f3'
  outline: '#76777d'
  outline-variant: '#c6c6cd'
  surface-tint: '#565e74'
  primary: '#000000'
  on-primary: '#ffffff'
  primary-container: '#131b2e'
  on-primary-container: '#7c839b'
  inverse-primary: '#bec6e0'
  secondary: '#006e2d'
  on-secondary: '#ffffff'
  secondary-container: '#7cf994'
  on-secondary-container: '#007230'
  tertiary: '#000000'
  on-tertiary: '#ffffff'
  tertiary-container: '#2f1500'
  on-tertiary-container: '#c76c00'
  error: '#ba1a1a'
  on-error: '#ffffff'
  error-container: '#ffdad6'
  on-error-container: '#93000a'
  primary-fixed: '#dae2fd'
  primary-fixed-dim: '#bec6e0'
  on-primary-fixed: '#131b2e'
  on-primary-fixed-variant: '#3f465c'
  secondary-fixed: '#7ffc97'
  secondary-fixed-dim: '#62df7d'
  on-secondary-fixed: '#002109'
  on-secondary-fixed-variant: '#005320'
  tertiary-fixed: '#ffdcc3'
  tertiary-fixed-dim: '#ffb77d'
  on-tertiary-fixed: '#2f1500'
  on-tertiary-fixed-variant: '#6e3900'
  background: '#f7f9fb'
  on-background: '#191c1e'
  surface-variant: '#e0e3e5'
typography:
  display-lg:
    fontFamily: Arimo
    fontSize: 32px
    fontWeight: '700'
    lineHeight: 40px
    letterSpacing: -0.02em
  display-lg-mobile:
    fontFamily: Arimo
    fontSize: 24px
    fontWeight: '700'
    lineHeight: 32px
    letterSpacing: -0.01em
  headline-md:
    fontFamily: Arimo
    fontSize: 20px
    fontWeight: '700'
    lineHeight: 28px
    letterSpacing: -0.01em
  headline-sm:
    fontFamily: Arimo
    fontSize: 16px
    fontWeight: '700'
    lineHeight: 24px
  body-lg:
    fontFamily: Arimo
    fontSize: 15px
    fontWeight: '400'
    lineHeight: 22px
  body-md:
    fontFamily: Arimo
    fontSize: 13px
    fontWeight: '400'
    lineHeight: 18px
  body-sm:
    fontFamily: Arimo
    fontSize: 12px
    fontWeight: '400'
    lineHeight: 16px
  label-lg:
    fontFamily: Arimo
    fontSize: 13px
    fontWeight: '600'
    lineHeight: 18px
  label-md:
    fontFamily: Arimo
    fontSize: 11px
    fontWeight: '700'
    lineHeight: 14px
    letterSpacing: 0.04em
  label-sm:
    fontFamily: Arimo
    fontSize: 10px
    fontWeight: '700'
    lineHeight: 12px
    letterSpacing: 0.06em
  metric-display:
    fontFamily: Arimo
    fontSize: 28px
    fontWeight: '700'
    lineHeight: 32px
    letterSpacing: -0.03em
rounded:
  sm: 0.125rem
  DEFAULT: 0.25rem
  md: 0.375rem
  lg: 0.5rem
  xl: 0.75rem
  full: 9999px
spacing:
  gutter: 1rem
  gutter-mobile: 0.75rem
  margin: 1.5rem
  margin-mobile: 0.75rem
  space-xs: 0.25rem
  space-sm: 0.5rem
  space-md: 0.75rem
  space-lg: 1rem
  space-xl: 1.5rem
---

## Brand & Style

El sistema de diseño combina la intensidad del torneo deportivo con la precisión de una consola de operaciones y telemetría en tiempo real. Está diseñado para participantes y administradores de la Quiniela Mundial 2026 que requieren consultar múltiples marcadores, pronósticos, clasificaciones y cómputos de puntos bajo condiciones de actualización en vivo.

El lenguaje visual es **Modern Sport & Operational Telemetry**: alta densidad de información estructurada, claridad visual inmediata, contraste elevado en encabezados y estados semánticos, y superficies limpias sin ornamentos innecesarios. Transmite rigor analítico, confiabilidad transaccional y la emoción vibrante de la competencia futbolística global mediante indicadores de estado vivos e interactivos.

## Colors

La paleta se fundamenta en un esquema claro con acentos profundos de alta autoridad y códigos cromáticos funcionales directos:

- **Estructura Primaria & Headers:** Azul Marino profundo (`#0f172a` como base principal, `#1e293b` para barras de navegación secundaria o tablas de control, y `#172554` para realces interactivos o focus).
- **Lienzo y Fondos:** Fondo de aplicación general claro (`#f8fafc` con alternancia en `#f1f5f9` para paneles de control secundarios y agrupaciones).
- **Superficies de Contenido:** Tarjetas, celdas y paneles en Blanco puro (`#ffffff`) enmarcados por bordes sutiles neutros (`#e2e8f0`).
- **Semántica Operativa & Estados de Partido:**
  - *Éxito / En Vivo / Operando:* Verde deportivo (`#16a34a` base, `#22c55e` acento activo, fondos suaves `#f0fdf4` / `bg-green-50`, texto `#15803d` / `text-green-700`, borde `#86efac` / `border-green-300`).
  - *Alerta / Programado / VAR / Pendiente:* Ámbar operativo (`#d97706` base, `#f59e0b` acento activo, fondos suaves `#fffbeb` / `bg-amber-50`, texto `#b45309` / `text-amber-700`, borde `#fcd34d` / `border-amber-300`).
  - *Falla / Anulado / Pronóstico Perdido:* Rojo crítico (`#dc2626` base, `#ef4444` acento activo, fondos suaves `#fef2f2` / `bg-red-50`, texto `#b91c1c` / `text-red-700`, borde `#fca5a5` / `border-red-300`).

## Typography

El sistema implementa Arimo (compatible métrica y estilísticamente con Arial, sans-serif) como fuente unificada para garantizar alta legibilidad en pantallas densas, tablas de posiciones y tableros en vivo.

- **Jerarquía y Peso:** Se priorizan pesos 400 (contenido regular), 600 (controles e inputs) y 700 (títulos, métricas de marcador y badges).
- **Métricas y Marcadores:** Los goles, puntajes y cronómetros emplean `metric-display` o `headline-md` con alineación tabular (`font-variant-numeric: tabular-nums`) para evitar oscilaciones de ancho durante actualizaciones en tiempo real.
- **Micro-etiquetas:** Los badges de telemetría (VAR, EN VIVO, FINAL) usan `label-md` o `label-sm` en mayúsculas sostenidas con espaciado entre letras optimizado.

## Layout & Spacing

El diseño adopta una cuadrícula fluida compacta con soporte modular para paneles tipo consola:

- **Desktop (>= 1024px):** Cuadrícula fluida de 12 columnas con margen de `1.5rem` y gutter de `1rem`. Permite visualización simultánea de: fixture por grupos (6 columnas), tabla de predicciones en vivo (4 columnas) y resumen de métricas/telemetría del usuario (2 columnas).
- **Tablet (768px - 1023px):** Cuadrícula de 8 columnas; los módulos de partidos y rankings colapsan a esquemas de 4 columnas en dos filas.
- **Mobile (< 768px):** Disposición de columna única continua con margen reducido de `0.75rem`. Los marcadores y controles de apuesta cambian de disposición horizontal a tarjetas de confronto vertical optimizadas para entrada táctil con pulgar.
- **Densidad de Datos:** Los rellenos internos (`space-sm` y `space-md`) mantienen las filas de partidos y tablas de posiciones compactas, asegurando un alto número de partidos visibles sin desplazamiento excesivo.

## Elevation & Depth

La jerarquía visual se construye a través de bordes estructurales sutiles y contraste tonal, evitando sombras difusas pesadas:

- **Nivel 0 (Fondo base):** Superficie `#f8fafc`.
- **Nivel 1 (Tarjetas y Contenedores):** Superficie `#ffffff` delimitada por borde sólido de 1px en `#e2e8f0`. Sin sombra en estado estático para mantener la precisión técnica.
- **Nivel 2 (Hover interactivo & Modales de Apuesta):** Elevación ligera con sombra ultra-sutil (`0 2px 4px -1px rgba(15, 23, 42, 0.06), 0 1px 2px -1px rgba(15, 23, 42, 0.04)`) y borde reforzado a `#cbd5e1`.
- **Nivel 3 (Overlays en Vivo y Notificaciones VAR):** Fondo blanco con borde semántico (verde, ámbar o rojo) y sombra de foco directo (`0 4px 6px -1px rgba(15, 23, 42, 0.1)`).
- **Indicadores de Pulso Activo:** Los partidos en curso utilizan una animación de punto pulsante o borde sutil intermitente sobre `#22c55e`.

## Shapes

El sistema utiliza esquinas contenidas de perfil suave (`roundedness: 1`, base 4px / `0.25rem`):

- **Contenedores y Tarjetas de Partido:** `0.375rem` (6px) para enmarcar la información deportiva con rigor técnico y orden.
- **Badges de Telemetría y Estado:** `0.25rem` (4px) para etiquetas rectangulares legibles y compactas; badges numéricos circulares de posición en ranking respetan proporción exacta 1:1.
- **Campos de Entrada de Marcador:** `0.25rem` (4px) para acentuar el aspecto de panel de control numérico.
- **Botones de Acción:** `0.375rem` (6px) para preservar coherencia con las tarjetas de los partidos.

## Components

### Tarjetas de Partido (Match Card)
- **Estructura:** Superficie blanca con borde `#e2e8f0`. Cabecera compacta con grupo, fecha y badge de estado.
- **Sección de Equipos:** Dos filas o columnas con bandera/código FIFA (3 letras en semibold), marcador oficial y campo de predicción del usuario.
- **Estados:** Borde izquierdo reforzado de 3px según el estado del evento (Verde: En Vivo; Ámbar: Próximo a cerrar pronósticos; Gris/Azul: Concluido).

### Badges de Estado (Telemetry Status Badges)
- **En Vivo / Operando:** Fondo `#f0fdf4`, texto `#15803d`, borde `#86efac`, con punto indicador de 6px en `#22c55e`.
- **Programado / VAR / Pendiente:** Fondo `#fffbeb`, texto `#b45309`, borde `#fcd34d`.
- **Falla / Anulado / Cerrado:** Fondo `#fef2f2`, texto `#b91c1c`, borde `#fca5a5`.
- **Neutro / Previa:** Fondo `#f1f5f9`, texto `#475569`, borde `#cbd5e1`.

### Botones
- **Primario:** Fondo `#0f172a`, texto blanco, hover `#1e293b`, active `#020617`. Altura compacta (36px).
- **Éxito (Guardar Quiniela / Confirmar):** Fondo `#16a34a`, texto blanco, hover `#15803d`.
- **Secundario / Outline:** Fondo transparente, borde 1px `#cbd5e1`, texto `#0f172a`, hover `#f1f5f9`.

### Campos de Entrada (Score Prediction Inputs)
- **Casillas de Goles:** Ancho fijo (44px), altura (36px), texto centrado en `16px` semibold con `font-variant-numeric: tabular-nums`.
- **Bordes:** Borde base `#cbd5e1`, foco con anillo de 2px en `#172554` sin desplazamiento.

### Tablas de Posiciones y Listas
- **Filas:** Altura comprimida (40px por fila), alternancia sutil con `#f8fafc` en hover.
- **Cabeceras:** Fondo `#0f172a` o `#1e293b` con tipografía blanca en `11px` bold con tracking amplio para columnas métricas (PJ, PG, PE, PP, PTS).

### Métricas de Telemetría (Stat KPI Tiles)
- Contenedores modulares blancos con borde `#e2e8f0` que muestran: "Puntos Totales", "Aciertos Exactos", "Efectividad %" y "Ranking Global", con etiqueta superior en gris `#64748b` y valor numérico destacado en `metric-display`.