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
  $('reloj').textContent = 'reloj ' + e.reloj.modo + ': ' + fechaUtc(e.reloj.ahora_ms);
  const m = e.metricas || {};
  const tarjetas = [
    ['Partidos en vivo', e.partidos.en_vivo], ['Finalizados', e.partidos.finalizado], ['Programados', e.partidos.programado],
    ['Participantes', e.participantes], ['Quinielas', e.quinielas], ['Pronósticos', e.pronosticos],
    ['Rechazados (tarde)', m.predicciones_rechazadas || 0], ['Goles anulados (VAR)', m.anulaciones_var || 0],
    ['Cambios de ranking', m.cambios_ranking || 0], ['Fallas inyectadas', m.fallas_inyectadas || 0],
    ['Clientes SSE', e.sse_conectados],
  ];
  $('resumen').innerHTML = tarjetas.map(([t, n]) => `<div class="tarjeta"><div class="etq">${esc(t)}</div><div class="num">${esc(n)}</div></div>`).join('');
  const sim = e.simulacion || {};
  pintarSimulacion(sim);
  const reciente = Date.now() - estado.ultimaFalla < 15000;
  if (sim.estado === 'error') semaforo('falla', 'Simulación con error');
  else if (reciente) semaforo('alerta', 'Falla reciente (recuperándose)');
  else semaforo('ok', sim.estado === 'corriendo' ? 'Simulación en curso' : 'Operando');
}
function semaforo(nivel, texto) { const s = $('semaforo'); s.className = nivel; s.textContent = texto; }

// ---- ranking ----
async function cargarQuinielas() {
  const { datos } = await api('/api/quinielas');
  const qs = (datos && datos.quinielas) || [];
  const sel = $('sel-quiniela');
  const previa = sel.value;
  sel.innerHTML = qs.map((q) => `<option value="${esc(q.id)}">${esc(q.id)} · ${esc(q.nombre)} (${esc(q.miembros)})</option>`).join('');
  if (previa && qs.some((q) => q.id === previa)) sel.value = previa;
  estado.quiniela = sel.value || null;
  estado.reglas = Object.fromEntries(qs.map((q) => [q.id, q.reglas]));
  conectarSse();
  cargarRanking();
}
async function cargarRanking() {
  if (!estado.quiniela) { $('ranking').innerHTML = '<tr><td colspan="5" class="nota">Aún no hay quinielas: inicia una simulación.</td></tr>'; return; }
  const { datos } = await api('/api/ranking?quiniela=' + encodeURIComponent(estado.quiniela) + '&top=20');
  if (datos && datos.filas) pintarRanking(datos.filas);
  const r = (estado.reglas || {})[estado.quiniela];
  $('reglas').textContent = r ? `Reglas: exacto ${r.exacto}, diferencia ${r.diferencia}, ganador ${r.ganador}, bono campeón ${r.bono_campeon}.` : '';
}
function pintarRanking(filas) {
  $('ranking').innerHTML = filas.map((f) => `<tr><td class="n">${esc(f.pos)}</td><td>${esc(f.participante)}</td><td class="n"><b>${esc(f.pts)}</b></td><td class="n">${esc(f.exactos)}</td><td class="n">${esc(f.ganadores)}</td></tr>`).join('')
    || '<tr><td colspan="5" class="nota">Sin participantes.</td></tr>';
}
$('sel-quiniela').addEventListener('change', () => { estado.quiniela = $('sel-quiniela').value; conectarSse(); cargarRanking(); });
$('buscar').addEventListener('change', async () => {
  const caja = $('buscado'); const u = $('buscar').value.trim();
  if (!u) { caja.hidden = true; return; }
  const { ok, datos } = await api(`/api/ranking?quiniela=${encodeURIComponent(estado.quiniela)}&participante=${encodeURIComponent(u)}`);
  caja.hidden = false;
  if (ok) { caja.className = 'msg ok'; caja.textContent = `${u}: posición ${datos.pos}, ${datos.pts} pts, ${datos.exactos} exactos.`; }
  else { caja.className = 'msg alerta'; caja.textContent = `${u} no está en la quiniela ${estado.quiniela}.`; }
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
    <div class="partido" data-id="${esc(p.id)}">
      <span class="eq">${esc(p.local)}</span>
      <span class="marcador">${esc(p.marcador[0])} - ${esc(p.marcador[1])}</span>
      <span class="eq d">${esc(p.visitante)}</span>
      <span class="insignia ${p.estado === 'en_vivo' ? 'vivo' : esc(p.estado)}">${p.estado === 'en_vivo' ? 'EN VIVO' : esc(p.estado)}</span>
    </div>`).join('') || '<p class="nota">No hay partidos en este estado.</p>';
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
  if (!ok) { $('d-info').textContent = 'No se pudo cargar el partido.'; return; }
  const p = datos.partido; const ev = datos.eventos || [];
  $('d-info').innerHTML = `
    <div class="partido" style="cursor:default"><span class="eq">${esc(p.local)}</span><span class="marcador">${esc(p.marcador[0])} - ${esc(p.marcador[1])}</span><span class="eq d">${esc(p.visitante)}</span></div>
    <p>Fase: <b>${esc(p.fase)}</b>${p.grupo ? ' · Grupo ' + esc(p.grupo) : ''} · Inicio: ${fechaUtc(p.inicio)} · Estado: <b>${esc(p.estado)}</b></p>
    <p>Pronósticos recibidos: <b>${esc(datos.pronosticos)}</b>${p.ganador ? ' · Ganador: <b>' + esc(p.ganador) + '</b>' : ''}</p>
    <table><thead><tr><th class="n">Min</th><th>Evento</th></tr></thead><tbody>${ev.map((e) =>
      `<tr><td class="n">${esc(e.minuto)}'</td><td class="${e.anulado ? 'anulado' : ''}">Gol ${esc(e.lado)} (#${esc(e.n)})${e.anulado ? ' — anulado por VAR' : ''}</td></tr>`).join('') || '<tr><td colspan="2" class="nota">Sin eventos.</td></tr>'}</tbody></table>`;
}
function cargarListaDetalleSiVisible() { if (!$('v-detalle').hidden && $('d-sel').value) abrirDetalle(+$('d-sel').value); }

// ---- bitácora ----
async function cargarBitacora() {
  const { datos } = await api('/api/bitacora?n=100');
  estado.bitacora = ((datos && datos.entradas) || []);
  pintarBitacora();
}
function pintarBitacora() {
  $('bitacora').innerHTML = estado.bitacora.slice(0, 100).map((e) =>
    `<tr><td><span class="insignia ${esc(e.nivel)}">${esc(e.nivel)}</span></td><td>${esc(e.tipo)}</td><td>${esc(JSON.stringify(e.datos))}</td><td class="n">${esc(e.n)}</td></tr>`).join('');
}

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
  if (status === 200) { c.className = 'msg ok'; c.textContent = 'Pronóstico aceptado.'; }
  else if (status === 409) { c.className = 'msg falla'; c.textContent = 'Rechazado: el partido ya cerró (lo decide el reloj del servidor).'; }
  else { c.className = 'msg alerta'; c.textContent = `No se aceptó (${status}): ${(datos && datos.error) || 'error'}`; }
});
$('b-falla').addEventListener('click', async () => {
  const { status, datos } = await api('/api/falla', { method: 'POST', headers: admin(), body: JSON.stringify({ objetivo: $('f-obj').value }) });
  const c = $('falla-res'); c.hidden = false;
  if (status === 200) { estado.ultimaFalla = Date.now(); c.className = 'msg ok'; c.textContent = `Proceso ${datos.resultado.tipo} ${datos.resultado.id} muerto y recuperado en ${Number(datos.resultado.recuperado_ms).toFixed(2)} ms.`; cargarRanking(); }
  else if (status === 401) { c.className = 'msg alerta'; c.textContent = 'Token admin inválido.'; }
  else { c.className = 'msg alerta'; c.textContent = 'Sin procesos que matar: inicia una simulación primero.'; }
});

// ---- tiempo real (SSE) ----
let fuente = null;
function conectarSse() {
  if (fuente) fuente.close();
  fuente = new EventSource('/api/eventos' + (estado.quiniela ? '?quiniela=' + encodeURIComponent(estado.quiniela) : ''));
  fuente.addEventListener('ranking', (m) => { const e = JSON.parse(m.data); if (e.quiniela === estado.quiniela) pintarRanking(e.top); });
  fuente.addEventListener('partido', (m) => { actualizarPartido(JSON.parse(m.data).partido); });
  fuente.addEventListener('bitacora', (m) => {
    const e = JSON.parse(m.data).entrada;
    estado.bitacora.unshift(e); estado.bitacora.length = Math.min(estado.bitacora.length, 200);
    if (e.nivel === 'falla') estado.ultimaFalla = Date.now();
    if (!$('v-bitacora').hidden) pintarBitacora();
    if (e.tipo === 'gol' || e.tipo === 'gol_anulado_var') cargarListaDetalleSiVisible();
  });
  fuente.onerror = () => semaforo('alerta', 'Reconectando…');
}

// ---- arranque ----
cargarQuinielas(); cargarPartidos(); cargarResumen(); cargarBitacora();
setInterval(cargarResumen, 2000);

// Enlaces directos a cada pantalla: /#detalle, /#bitacora
const vistaInicial = (location.hash || '').replace('#', '');
if (['detalle', 'bitacora'].includes(vistaInicial)) document.querySelector(`nav button[data-vista=${vistaInicial}]`).click();
