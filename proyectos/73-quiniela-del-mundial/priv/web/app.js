'use strict';
// Interfaz de la Quiniela del Mundial: lee la API JSON y se actualiza por SSE (/api/eventos).
const $ = (id) => document.getElementById(id);
const esc = (t) => String(t ?? '').replace(/[&<>"']/g, (c) => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const estado = { quiniela: null, partidos: [], filtro: 'en_vivo', bitacora: [], ultimaFalla: 0 };

async function api(ruta, opciones) {
  const r = await fetch(ruta, opciones);
  let cuerpo = null;
  try { cuerpo = await r.json(); } catch (_) {}
  return { ok: r.ok, status: r.status, datos: cuerpo };
}
const admin = () => ({ 'x-admin-token': $('token').value, 'content-type': 'application/json' });
const NIVEL = {
  ok: 'bg-secondary-container text-on-secondary-container', alerta: 'bg-tertiary-fixed text-on-tertiary-fixed-variant',
  falla: 'bg-error-container text-on-error-container', info: 'bg-surface-container text-on-surface-variant',
};
const msgClase = (n) => 'rounded px-3 py-2 mt-2 font-body-md text-body-md ' + (NIVEL[n] || NIVEL.info);
const BADGE = 'inline-flex items-center px-2 py-0.5 rounded-full font-label-sm text-label-sm uppercase ';
const fechaUtc = (ms) => new Date(ms).toISOString().replace('T', ' ').slice(0, 16) + ' UTC';

// ---- navegación ----
document.querySelectorAll('nav button').forEach((b) => b.addEventListener('click', () => {
  document.querySelectorAll('nav button').forEach((x) => x.setAttribute('aria-selected', x === b));
  ['dashboard', 'detalle', 'bitacora'].forEach((v) => { $('v-' + v).hidden = v !== b.dataset.vista; });
  if (b.dataset.vista === 'detalle') cargarListaDetalle();
  if (b.dataset.vista === 'bitacora') cargarBitacora();
}));

// ---- resumen y semáforo ----
async function cargarResumen() {
  const { ok, datos: e } = await api('/api/estado');
  if (!ok) { semaforo('falla', 'Sin conexión con el servidor'); return; }
  $('reloj').textContent = 'reloj ' + e.reloj.modo + ': ' + fechaUtc(e.reloj.ahora_ms); $('sse-n').textContent = e.sse_conectados;
  const m = e.metricas || {}; estado.metricas = m;
  const tarjetas = [
    ['Partidos en vivo', e.partidos.en_vivo], ['Finalizados', e.partidos.finalizado], ['Programados', e.partidos.programado],
    ['Participantes', e.participantes], ['Quinielas', e.quinielas], ['Pronósticos', e.pronosticos],
    ['Rechazados (tarde)', m.predicciones_rechazadas || 0], ['Goles anulados (VAR)', m.anulaciones_var || 0],
    ['Cambios de ranking', m.cambios_ranking || 0], ['Fallas inyectadas', m.fallas_inyectadas || 0],
    ['Clientes SSE', e.sse_conectados],
  ];
  $('resumen').innerHTML = tarjetas.map(([t, n]) => `<div class="bg-surface-container-lowest rounded-xl shadow-sm p-space-md"><div class="font-label-sm text-label-sm text-on-surface-variant uppercase">${esc(t)}</div><div class="font-metric-display text-metric-display mt-1">${esc(n)}</div></div>`).join('');
  const sim = e.simulacion || {};
  pintarSimulacion(sim);
  const reciente = Date.now() - estado.ultimaFalla < 15000;
  if (sim.estado === 'error') semaforo('falla', 'Simulación con error');
  else if (reciente) semaforo('alerta', 'Falla reciente (recuperándose)');
  else semaforo('ok', sim.estado === 'corriendo' ? 'Simulación en curso' : 'Operando');
}
function semaforo(nivel, texto) { const s = $('semaforo'); s.className = 'inline-flex items-center px-1.5 rounded font-label-sm text-label-sm font-bold uppercase ' + (NIVEL[nivel] || NIVEL.info); s.textContent = texto; }

// ---- ranking ----
async function cargarQuinielas() {
  const { datos } = await api('/api/quinielas');
  const qs = (datos && datos.quinielas) || [];
  const sel = $('sel-quiniela');
  const previa = sel.value;
  sel.innerHTML = qs.length ? qs.map((q) => `<option class="bg-primary-container text-inverse-on-surface" value="${esc(q.id)}">${esc(q.id)} · ${esc(q.nombre)} (${esc(q.miembros)})</option>`).join('') : '<option class="bg-primary-container text-inverse-on-surface" value="">Sin quinielas</option>';
  if (previa && qs.some((q) => q.id === previa)) sel.value = previa;
  estado.quiniela = sel.value || null;
  estado.reglas = Object.fromEntries(qs.map((q) => [q.id, q.reglas]));
  conectarSse();
  cargarRanking();
}
async function cargarRanking() {
  if (!estado.quiniela) { $('ranking').innerHTML = '<tr><td colspan="5" class="py-3 px-space-sm text-on-surface-variant">Aún no hay quinielas: inicia una simulación.</td></tr>'; return; }
  const { datos } = await api('/api/ranking?quiniela=' + encodeURIComponent(estado.quiniela) + '&top=20');
  if (datos && datos.filas) pintarRanking(datos.filas);
  const r = (estado.reglas || {})[estado.quiniela];
  $('reglas').textContent = r ? `Reglas: exacto ${r.exacto}, diferencia ${r.diferencia}, ganador ${r.ganador}, bono campeón ${r.bono_campeon}.` : '';
}
function pintarRanking(filas) {
  $('ranking').innerHTML = filas.map((f) => `<tr class="hover:bg-surface-container-low"><td class="py-2 px-space-sm text-right font-bold">${esc(f.pos)}</td><td class="py-2 px-space-sm">${esc(f.participante)}</td><td class="py-2 px-space-sm text-right font-bold">${esc(f.pts)}</td><td class="py-2 px-space-sm text-right">${esc(f.exactos)}</td><td class="py-2 px-space-sm text-right">${esc(f.ganadores)}</td></tr>`).join('')
    || '<tr><td colspan="5" class="py-3 px-space-sm text-on-surface-variant">Sin participantes.</td></tr>';
}
$('sel-quiniela').addEventListener('change', () => { estado.quiniela = $('sel-quiniela').value; conectarSse(); cargarRanking(); });
$('buscar').addEventListener('change', async () => {
  const caja = $('buscado'); const u = $('buscar').value.trim();
  if (!u) { caja.hidden = true; return; }
  const { ok, datos } = await api(`/api/ranking?quiniela=${encodeURIComponent(estado.quiniela)}&participante=${encodeURIComponent(u)}`);
  caja.hidden = false;
  if (ok) { caja.className = msgClase('ok'); caja.textContent = `${u}: posición ${datos.pos}, ${datos.pts} pts, ${datos.exactos} exactos.`; }
  else { caja.className = msgClase('alerta'); caja.textContent = `${u} no está en la quiniela ${estado.quiniela}.`; }
});

// ---- partidos ----
async function cargarPartidos() {
  const { datos } = await api('/api/partidos');
  estado.partidos = (datos && datos.partidos) || [];
  pintarPartidos();
}
function pintarPartidos() {
  const lista = estado.partidos.filter((p) => !estado.filtro || p.estado === estado.filtro);
  const orden = estado.filtro === 'finalizado' ? lista.slice().reverse() : lista;
  $('partidos').innerHTML = orden.slice(0, 40).map((p) => `
    <div class="partido flex items-center justify-between gap-2 py-2 border-b border-surface-container-high cursor-pointer hover:bg-surface-container-low" data-id="${esc(p.id)}">
      <span class="flex-1 font-body-md text-body-md">${esc(p.local)}</span>
      <span class="font-headline-sm text-headline-sm min-w-[56px] text-center">${esc(p.marcador[0])} - ${esc(p.marcador[1])}</span>
      <span class="flex-1 text-right font-body-md text-body-md">${esc(p.visitante)}</span>
      <span class="${BADGE}${p.estado === 'en_vivo' ? NIVEL.ok : p.estado === 'finalizado' ? NIVEL.info : NIVEL.alerta}">${p.estado === 'en_vivo' ? 'En vivo' : esc(p.estado)}</span>
    </div>`).join('') || '<p class="font-body-sm text-body-sm text-on-surface-variant py-2">No hay partidos en este estado.</p>';
  document.querySelectorAll('#partidos .partido').forEach((d) => d.addEventListener('click', () => abrirDetalle(+d.dataset.id)));
}
$('filtro-estado').addEventListener('change', () => { estado.filtro = $('filtro-estado').value; pintarPartidos(); });

function actualizarPartido(snap) {
  const i = estado.partidos.findIndex((p) => p.id === snap.id);
  if (i >= 0) estado.partidos[i] = snap; else estado.partidos.push(snap);
  pintarPartidos();
}

// ---- detalle ----
async function cargarListaDetalle() {
  if (!estado.partidos.length) await cargarPartidos();
  $('d-sel').innerHTML = estado.partidos.map((p) => `<option value="${esc(p.id)}">#${esc(p.id)} ${esc(p.local)} vs ${esc(p.visitante)} (${esc(p.estado)})</option>`).join('');
  if ($('d-sel').value) abrirDetalle(+$('d-sel').value);
}
$('d-sel').addEventListener('change', () => abrirDetalle(+$('d-sel').value));
async function abrirDetalle(id) {
  document.querySelector('nav button[data-vista=detalle]').click();
  $('d-sel').value = String(id);
  const { ok, datos } = await api('/api/partidos/' + id);
  if (!ok) { $('d-hero').textContent = 'No se pudo cargar el partido.'; return; }
  const p = datos.partido; const ev = datos.eventos || [];
  const anulados = ev.filter((e) => e.anulado);
  const vivo = p.estado === 'en_vivo';
  $('d-ruta').textContent = `${p.fase}${p.grupo ? ' · Grupo ' + p.grupo : ''} · Partido #${p.id}`;
  $('d-hero').innerHTML = `
    <div class="flex flex-wrap items-center justify-between gap-space-sm mb-space-lg">
      <span class="inline-flex items-center px-space-sm py-0.5 rounded bg-primary-container text-on-primary font-label-sm text-label-sm uppercase tracking-wider">${esc(p.fase)}${p.grupo ? ' • GRUPO ' + esc(p.grupo) : ''}</span>
      <div class="flex items-center gap-space-sm">
        <span class="inline-flex items-center gap-2 px-space-md py-1 rounded-full font-label-md text-label-md tracking-wider ${vivo ? 'bg-secondary/10 text-secondary' : 'bg-surface-container text-on-surface-variant'}">
          ${vivo ? '<span class="relative flex h-2.5 w-2.5"><span class="animate-ping absolute inline-flex h-full w-full rounded-full bg-secondary opacity-75"></span><span class="relative inline-flex rounded-full h-2.5 w-2.5 bg-secondary"></span></span>' : ''}
          <span class="font-bold uppercase">${vivo ? 'EN VIVO' : esc(p.estado)}</span></span>
        <span class="font-label-sm text-label-sm text-on-surface-variant">Inicio ${fechaUtc(p.inicio)}</span>
      </div>
    </div>
    <div class="flex flex-wrap items-center justify-center gap-space-xl py-space-md">
      <div class="font-display-lg text-display-lg uppercase text-center flex-1 min-w-[140px]">${esc(p.local)}</div>
      <div class="font-display-lg text-display-lg text-center" style="font-size:56px;line-height:60px">${esc(p.marcador[0])} <span class="text-on-surface-variant">-</span> ${esc(p.marcador[1])}</div>
      <div class="font-display-lg text-display-lg uppercase text-center flex-1 min-w-[140px]">${esc(p.visitante)}</div>
    </div>
    <div class="mt-space-md rounded-lg bg-surface-container-low px-space-md py-space-sm flex flex-wrap items-center justify-between gap-space-sm font-body-sm text-body-sm">
      <span><b>Pronósticos cerrados al inicio del partido</b> · el cierre lo decide el reloj del servidor</span>
      ${p.ganador ? '<span class="font-bold">Ganador: ' + esc(p.ganador) + '</span>' : ''}
    </div>`;
  $('d-var').innerHTML = anulados.length ? `
    <div class="rounded-xl border-t-4 border-error bg-error-container/50 p-space-lg">
      <span class="inline-flex px-2 py-0.5 rounded bg-error text-on-error font-label-sm text-label-sm uppercase">Incidencia VAR</span>
      <p class="font-headline-sm text-headline-sm mt-space-sm">${anulados.length} gol(es) anulado(s) por VAR en este partido.</p>
      <p class="font-body-md text-body-md text-on-surface-variant mt-1">Los puntos de las quinielas se revirtieron automáticamente y el ranking se recalculó.</p>
    </div>` : '';
  const m = (estado.metricas || {});
  $('d-stats').innerHTML = [
    ['Pronósticos recibidos', datos.pronosticos, 'a tiempo para este partido', 'check_circle'],
    ['Rechazados (global)', m.predicciones_rechazadas || 0, 'extemporáneos, todos los partidos', 'cancel'],
    ['Goles anulados (VAR)', anulados.length, 'en este partido', 'videocam_off'],
  ].map(([t, n, sub]) => `<div class="bg-surface-container-lowest rounded-xl shadow-sm p-space-md"><div class="font-label-sm text-label-sm text-on-surface-variant uppercase">${esc(t)}</div><div class="font-metric-display text-metric-display mt-1">${esc(n)}</div><div class="font-body-sm text-body-sm text-on-surface-variant">${esc(sub)}</div></div>`).join('');
  $('d-eventos').innerHTML = ev.map((e) =>
    `<tr><td class="py-2 px-space-sm text-right font-mono">${esc(e.minuto)}'</td><td class="py-2 px-space-sm ${e.anulado ? 'anulado text-on-surface-variant' : ''}">Gol ${esc(e.lado)} (#${esc(e.n)})${e.anulado ? ' — anulado por VAR' : ''}</td></tr>`).join('')
    || '<tr><td colspan="2" class="py-3 px-space-sm text-on-surface-variant">Sin eventos.</td></tr>';
}
$('b-sync').addEventListener('click', () => { if ($('d-sel').value) abrirDetalle(+$('d-sel').value); });
function cargarListaDetalleSiVisible() { if (!$('v-detalle').hidden && $('d-sel').value) abrirDetalle(+$('d-sel').value); }

// ---- bitácora ----
async function cargarBitacora() {
  const { datos } = await api('/api/bitacora?n=100');
  estado.bitacora = ((datos && datos.entradas) || []);
  pintarBitacora();
}
function pintarBitacora() {
  const nivel = $('b-nivel').value;
  $('bitacora').innerHTML = estado.bitacora.filter((e) => !nivel || e.nivel === nivel).slice(0, 100).map((e) =>
    `<tr class="${e.nivel === 'falla' ? 'bg-error-container/40' : ''}"><td class="py-2 px-space-sm"><span class="${BADGE}${NIVEL[e.nivel] || NIVEL.info}">${esc(e.nivel)}</span></td><td class="py-2 px-space-sm font-bold">${esc(e.tipo)}</td><td class="py-2 px-space-sm font-mono text-[11px]">${esc(JSON.stringify(e.datos))}</td><td class="py-2 px-space-sm text-right">${esc(e.n)}</td></tr>`).join('')
    || '<tr><td colspan="4" class="py-3 px-space-sm text-on-surface-variant">Sin eventos.</td></tr>';
}
$('b-nivel').addEventListener('change', pintarBitacora);

// ---- simulación ----
$('b-sim').addEventListener('click', async () => {
  const cuerpo = { participantes: +$('s-part').value, quinielas: +$('s-quin').value, partidos: +$('s-pts').value, caos: $('s-caos').checked };
  const { status, datos } = await api('/api/simulacion', { method: 'POST', headers: admin(), body: JSON.stringify(cuerpo) });
  const msg = $('sim-estado');
  if (status === 401) msg.textContent = 'Token admin inválido.';
  else if (status === 409) msg.textContent = 'Ya hay una simulación en curso.';
  else if (status === 202) { msg.textContent = 'Simulación iniciada…'; $('sim-reporte').hidden = true; sondearSim(); }
  else msg.textContent = 'Error: ' + JSON.stringify(datos);
});
let sondeo = null;
function sondearSim() { clearInterval(sondeo); sondeo = setInterval(async () => { const { datos } = await api('/api/simulacion'); pintarSimulacion(datos); if (datos && datos.estado !== 'corriendo') { clearInterval(sondeo); await cargarQuinielas(); await cargarPartidos(); } }, 700); }
function pintarSimulacion(s) {
  if (!s) return;
  const pr = s.progreso || {}; const total = pr.partidos_total || 0;
  $('progreso').style.width = total ? Math.round(100 * (pr.partidos_hechos || 0) / total) + '%' : (s.estado === 'terminado' ? '100%' : '0');
  const txt = { inactivo: 'Sin simulación en curso.', corriendo: `En curso: ${pr.fase || ''} — ${pr.partidos_hechos || 0}/${total} partidos`, terminado: 'Simulación terminada.', error: 'La simulación falló.' };
  $('sim-estado').textContent = txt[s.estado] || '';
  if (s.estado === 'terminado' && s.reporte) {
    const r = s.reporte; const pre = $('sim-reporte'); pre.hidden = false;
    pre.textContent = JSON.stringify({
      duracion_ms: r.duracion_ms, partidos: r.partidos_simulados, simultaneos_max: r.simultaneos_max,
      rafaga: r.rafaga && { aceptadas: r.rafaga.aceptadas, intentos: r.rafaga.intentos, tarde_rechazadas: r.rafaga.tarde_rechazadas, tarde_intentos: r.rafaga.tarde_intentos },
      consistencia: r.consistencia, caos_eventos: (r.caos || []).length, var_eventos: (r.var || []).length, memoria_mb: r.memoria_mb,
    }, null, 2);
  }
}

// ---- pronóstico y fallas ----
$('b-pron').addEventListener('click', async () => {
  const cuerpo = { participante: $('p-part').value.trim(), partido: +$('p-partido').value, local: +$('p-l').value, visitante: +$('p-v').value,
                   ts_cliente: Date.now() };  // se envía a propósito: el servidor lo ignora
  const { status, datos } = await api('/api/predicciones', { method: 'POST', body: JSON.stringify(cuerpo) });
  const c = $('pron-res'); c.hidden = false;
  if (status === 200) { c.className = msgClase('ok'); c.textContent = 'Pronóstico aceptado.'; }
  else if (status === 409) { c.className = msgClase('falla'); c.textContent = 'Rechazado: el partido ya cerró (lo decide el reloj del servidor).'; }
  else { c.className = msgClase('alerta'); c.textContent = `No se aceptó (${status}): ${(datos && datos.error) || 'error'}`; }
});
$('b-falla').addEventListener('click', async () => {
  const { status, datos } = await api('/api/falla', { method: 'POST', headers: admin(), body: JSON.stringify({ objetivo: $('f-obj').value }) });
  const c = $('falla-res'); c.hidden = false;
  if (status === 200) { estado.ultimaFalla = Date.now(); c.className = msgClase('ok'); c.textContent = `Proceso ${datos.resultado.tipo} ${datos.resultado.id} muerto y recuperado en ${Number(datos.resultado.recuperado_ms).toFixed(2)} ms.`; cargarRanking(); }
  else if (status === 401) { c.className = msgClase('alerta'); c.textContent = 'Token admin inválido.'; }
  else { c.className = msgClase('alerta'); c.textContent = 'Sin procesos que matar: inicia una simulación primero.'; }
});

$('b-falla-h').addEventListener('click', () => { document.querySelector('nav button[data-vista=dashboard]').click(); $('b-falla').click(); });

// ---- tiempo real (SSE) ----
function logSse(texto, nivel) {
  const log = $('sse-log'); const h = new Date().toTimeString().split(' ')[0];
  const d = document.createElement('div');
  d.className = nivel === 'falla' ? 'text-error-container bg-error/30 p-1 rounded font-bold' : nivel === 'alerta' ? 'text-tertiary-fixed-dim' : 'text-secondary-fixed';
  d.textContent = `[${h}] ${texto}`;
  log.insertBefore(d, log.firstChild);
  while (log.children.length > 60) log.removeChild(log.lastChild);
}
let fuente = null;
function conectarSse() {
  if (fuente) fuente.close();
  fuente = new EventSource('/api/eventos' + (estado.quiniela ? '?quiniela=' + encodeURIComponent(estado.quiniela) : ''));
  fuente.addEventListener('ranking', (m) => { const e = JSON.parse(m.data); if (e.quiniela === estado.quiniela) pintarRanking(e.top); });
  fuente.addEventListener('partido', (m) => { actualizarPartido(JSON.parse(m.data).partido); });
  fuente.addEventListener('bitacora', (m) => {
    const e = JSON.parse(m.data).entrada;
    logSse(`${e.tipo.toUpperCase()} ${JSON.stringify(e.datos)}`, e.nivel);
    estado.bitacora.unshift(e); estado.bitacora.length = Math.min(estado.bitacora.length, 200);
    if (e.nivel === 'falla') estado.ultimaFalla = Date.now();
    if (!$('v-bitacora').hidden) pintarBitacora();
    if (e.tipo === 'gol' || e.tipo === 'gol_anulado_var') cargarListaDetalleSiVisible();
  });
  fuente.onopen = () => logSse('HEARTBEAT: canal SSE conectado', 'ok');
  fuente.onerror = () => { semaforo('alerta', 'Reconectando…'); logSse('SSE: reconectando…', 'alerta'); };
}

// ---- arranque ----
cargarQuinielas(); cargarPartidos(); cargarResumen(); cargarBitacora();
setInterval(cargarResumen, 2000);

// Enlaces directos a cada pantalla: /#detalle, /#bitacora
const vistaInicial = (location.hash || '').replace('#', '');
if (['detalle', 'bitacora'].includes(vistaInicial)) document.querySelector(`nav button[data-vista=${vistaInicial}]`).click();
