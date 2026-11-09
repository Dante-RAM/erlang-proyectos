'use strict';
// Quiniela del Mundial 2026: la UI (diseno de Google Stitch) lee la API JSON y se actualiza por SSE (/api/eventos).
const $ = (id) => document.getElementById(id);
const esc = (t) => String(t ?? '').replace(/[&<>"']/g, (c) => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const estado = { quiniela: null, partidos: [], filtro: 'all', bitacora: [], ultimaFalla: 0, metricas: {}, srv: null,
                 ahora: Date.now(), pausa: false, sev: 'all', busca: '', reconex: 0, conectadoUnaVez: false };

async function api(ruta, opciones) {
  const r = await fetch(ruta, opciones);
  let cuerpo = null;
  try { cuerpo = await r.json(); } catch (_) {}
  return { ok: r.ok, status: r.status, datos: cuerpo };
}
const admin = () => ({ 'x-admin-token': $('token').value, 'content-type': 'application/json' });
const fechaUtc = (ms) => new Date(ms).toISOString().replace('T', ' ').slice(0, 16) + ' UTC';
const horaUtc = (ms) => new Date(ms).toISOString().slice(11, 19) + ' UTC';
const codigo = (n) => String(n || '').replace(/[^A-Za-zÁÉÍÓÚÑáéíóúñ]/g, '').slice(0, 3).toUpperCase();
const COLORES = ['bg-secondary text-on-secondary', 'bg-primary-container text-inverse-on-surface', 'bg-error text-on-error', 'bg-surface-container-highest text-on-surface', 'bg-tertiary-container text-tertiary-fixed'];
const color = (n) => COLORES[[...String(n || '')].reduce((a, c) => a + c.charCodeAt(0), 0) % COLORES.length];
const insignia = (n) => `<span class="w-8 h-8 rounded-full ${color(n)} font-bold flex items-center justify-center text-label-sm shrink-0">${esc(codigo(n))}</span>`;
const SEV = {
  ok:     { txt: 'VERDE', bg: 'bg-secondary-container text-on-secondary-fixed', punto: 'bg-secondary', fila: 'bg-surface-container-lowest hover:bg-surface-container-low', tit: 'text-on-surface' },
  alerta: { txt: 'ÁMBAR', bg: 'bg-tertiary-fixed text-on-tertiary-fixed-variant', punto: 'bg-on-tertiary-container', fila: 'bg-tertiary-fixed/30 hover:bg-tertiary-fixed/50', tit: 'text-on-tertiary-fixed-variant' },
  falla:  { txt: 'ROJO', bg: 'bg-error-container text-on-error-container', punto: 'bg-error', fila: 'bg-error-container/20 hover:bg-error-container/30', tit: 'text-error' },
};
const sevDe = (n) => SEV[n] || SEV.ok;
const msgClase = (n) => 'p-space-sm rounded-lg font-body-sm text-body-sm ' + ({ ok: 'bg-secondary-container text-on-secondary-fixed', alerta: 'bg-tertiary-fixed text-on-tertiary-fixed-variant', falla: 'bg-error-container text-on-error-container' }[n] || 'bg-surface-container');

// ---- navegación ----
function irA(vista) {
  document.querySelectorAll('nav button[data-vista]').forEach((x) => x.setAttribute('aria-selected', x.dataset.vista === vista));
  ['dashboard', 'detalle', 'bitacora'].forEach((v) => { $('v-' + v).hidden = v !== vista; });
  if (vista === 'detalle') cargarListaDetalle();
  if (vista === 'bitacora') { cargarBitacora(); pintarProcesos(); }
  window.scrollTo(0, 0);
}
document.querySelectorAll('nav button[data-vista]').forEach((b) => b.addEventListener('click', () => irA(b.dataset.vista)));

// ---- resumen, semáforo y estado ----
async function cargarResumen() {
  const { ok, datos: e } = await api('/api/estado');
  if (!ok) { semaforo('falla', 'Sin conexión'); $('nodo-estado').textContent = 'SIN CONEXIÓN'; return; }
  estado.srv = e; estado.ahora = e.reloj.ahora_ms; estado.metricas = e.metricas || {};
  const rj = e.reloj.modo + ': ' + fechaUtc(e.reloj.ahora_ms);
  $('reloj').textContent = 'reloj ' + rj; $('reloj2').textContent = rj;
  $('sse-n').textContent = e.sse_conectados; $('d-sse').textContent = e.sse_conectados;
  const m = estado.metricas;
  const T = (t, n, chip, chipCls, sub, subCls) => `<div class="bg-surface-container-lowest p-space-sm rounded-lg shadow-sm flex flex-col justify-between hover:shadow-md transition-shadow">
    <span class="font-label-sm text-label-sm text-on-surface-variant line-clamp-1">${esc(t)}</span>
    <div class="flex items-baseline justify-between mt-1"><span class="font-metric-display text-metric-display text-on-surface">${esc(n)}</span>
    <span class="px-1.5 py-0.5 rounded font-label-sm text-[9px] font-bold ${chipCls}">${esc(chip)}</span></div>
    <span class="font-body-sm text-[10px] mt-1 ${subCls}">${esc(sub)}</span></div>`;
  $('resumen').innerHTML = [
    T('En vivo', e.partidos.en_vivo, 'JUEGO', 'bg-secondary-container text-on-secondary-fixed' + (e.partidos.en_vivo ? ' animate-pulse' : ''), 'procesos de partido activos', 'text-secondary'),
    T('Finalizados', e.partidos.finalizado, 'Completos', 'bg-surface-container-highest text-on-surface-variant', 'puntos liquidados', 'text-on-surface-variant'),
    T('Programados', e.partidos.programado, 'Por jugar', 'bg-tertiary-fixed text-on-tertiary-fixed-variant', 'aún aceptan pronósticos', 'text-on-surface-variant'),
    T('Participantes', e.participantes, 'Reg.', 'bg-surface-container-highest text-on-surface-variant', 'procesos de participante', 'text-on-surface-variant'),
    T('Quinielas', e.quinielas, 'Activas', 'bg-surface-container-highest text-on-surface-variant', 'rankings independientes', 'text-on-surface-variant'),
    T('Pronósticos', e.pronosticos, 'Total', 'bg-surface-container-highest text-on-surface-variant', 'aceptados a tiempo', 'text-on-surface-variant'),
    T('Rechazados (tarde)', m.predicciones_rechazadas || 0, 'Tarde', 'bg-error-container text-on-error-container', 'tras el cierre del partido', 'text-error'),
    T('Goles anulados VAR', m.anulaciones_var || 0, 'VAR', 'bg-tertiary-fixed text-on-tertiary-fixed-variant', 'puntos revertidos', 'text-on-tertiary-fixed-variant'),
    T('Fallas inyectadas', m.fallas_inyectadas || 0, 'Caos', 'bg-error-container text-on-error-container', 'procesos matados', 'text-error'),
    T('Clientes SSE', e.sse_conectados, 'En vivo', 'bg-secondary-container text-on-secondary-fixed', 'conexiones abiertas', 'text-secondary'),
  ].join('');
  pintarSimulacion(e.simulacion || {});
  const sim = e.simulacion || {};
  const reciente = Date.now() - estado.ultimaFalla < 15000;
  let nivel = 'ok', txt = 'OPERANDO';
  if (sim.estado === 'error') { nivel = 'falla'; txt = 'ERROR'; }
  else if (reciente) { nivel = 'alerta'; txt = 'RECUPERÁNDOSE'; }
  else if (sim.estado === 'corriendo') txt = 'SIMULANDO';
  semaforo(nivel, txt);
  $('nodo-estado').textContent = txt; $('nodo-estado').className = 'font-label-sm text-label-sm uppercase font-bold ' + (nivel === 'ok' ? 'text-secondary' : nivel === 'alerta' ? 'text-on-tertiary-container' : 'text-error');
  if (!$('v-bitacora').hidden) pintarProcesos();
  pintarMetricasBitacora();
}
function semaforo(nivel, texto) { const s = $('semaforo'); s.className = 'hidden lg:inline-flex items-center px-1.5 rounded font-label-sm text-label-sm font-bold ' + sevDe(nivel).bg; s.textContent = texto; }

// ---- ranking ----
async function cargarQuinielas() {
  const { datos } = await api('/api/quinielas');
  const qs = (datos && datos.quinielas) || [];
  const sel = $('sel-quiniela'); const previa = sel.value;
  sel.innerHTML = qs.length ? qs.map((q) => `<option value="${esc(q.id)}">${esc(q.id)} · ${esc(q.nombre)} (${esc(q.miembros)})</option>`).join('') : '<option value="">Sin quinielas (inicia una simulación)</option>';
  if (previa && qs.some((q) => q.id === previa)) sel.value = previa;
  estado.quiniela = sel.value || null;
  estado.reglas = Object.fromEntries(qs.map((q) => [q.id, q.reglas]));
  const q = qs.find((x) => x.id === estado.quiniela);
  $('n-clasif').textContent = q ? q.miembros + ' clasificados' : '';
  conectarSse();
  cargarRanking();
}
async function cargarRanking() {
  if (!estado.quiniela) { $('ranking').innerHTML = '<tr><td colspan="5" class="py-6 px-3 text-center text-on-surface-variant">Aún no hay quinielas: inicia una simulación.</td></tr>'; return; }
  const { datos } = await api('/api/ranking?quiniela=' + encodeURIComponent(estado.quiniela) + '&top=20');
  if (datos && datos.filas) pintarRanking(datos.filas);
  const r = (estado.reglas || {})[estado.quiniela];
  $('reglas').textContent = r ? `Reglas: exacto ${r.exacto}, diferencia ${r.diferencia}, ganador ${r.ganador}, bono campeón ${r.bono_campeon}` : '';
}
const MEDALLA = { 1: '🥇', 2: '🥈', 3: '🥉' };
function pintarRanking(filas) {
  $('ranking').innerHTML = filas.map((f) => `<tr class="hover:bg-surface-container-low transition-colors bg-surface-container-lowest border-b border-surface-container-high/40">
    <td class="py-3 px-3 text-center"><span class="inline-flex items-center justify-center min-w-7 h-7 px-1 rounded-full ${f.pos <= 3 ? 'bg-tertiary-fixed text-on-tertiary-fixed' : 'bg-surface-container text-on-surface-variant'} font-bold text-[13px] shadow-sm">${MEDALLA[f.pos] || ''} #${esc(f.pos)}</span></td>
    <td class="py-3 px-3"><div class="flex items-center gap-2"><div class="w-8 h-8 rounded-full bg-primary-container text-inverse-on-surface flex items-center justify-center font-bold text-label-sm">${esc(String(f.participante).slice(-2))}</div>
      <div><span class="font-headline-sm text-label-lg text-on-surface block">${esc(f.participante)}</span><span class="text-on-surface-variant text-[11px]">${esc(f.exactos)} plenos • ${esc(f.ganadores)} aciertos de ganador</span></div></div></td>
    <td class="py-3 px-3 text-center font-semibold text-on-surface">${esc(f.exactos)} plenos</td>
    <td class="py-3 px-3 text-center font-mono text-[12px] text-secondary font-bold">${esc(f.ganadores)}</td>
    <td class="py-3 px-3 text-right"><span class="font-headline-md text-headline-md text-on-surface font-bold">${esc(f.pts)}</span><span class="text-[11px] text-on-surface-variant block">pts</span></td></tr>`).join('')
    || '<tr><td colspan="5" class="py-6 px-3 text-center text-on-surface-variant">Sin participantes.</td></tr>';
}
$('sel-quiniela').addEventListener('change', () => { estado.quiniela = $('sel-quiniela').value; conectarSse(); cargarRanking(); });
$('buscar').addEventListener('change', async () => {
  const caja = $('buscado'); const u = $('buscar').value.trim();
  if (!u || !estado.quiniela) { caja.hidden = true; return; }
  const { ok, datos } = await api(`/api/ranking?quiniela=${encodeURIComponent(estado.quiniela)}&participante=${encodeURIComponent(u)}`);
  caja.hidden = false;
  if (ok) { caja.className = 'mx-space-sm mb-space-sm ' + msgClase('ok'); caja.textContent = `${u}: posición ${datos.pos}, ${datos.pts} pts, ${datos.exactos} exactos.`; }
  else { caja.className = 'mx-space-sm mb-space-sm ' + msgClase('alerta'); caja.textContent = `${u} no está en la quiniela ${estado.quiniela}.`; }
});

// ---- partidos ----
async function cargarPartidos() {
  const { datos } = await api('/api/partidos');
  estado.partidos = (datos && datos.partidos) || [];
  pintarPartidos(); llenarSelectorPronostico();
}
function cierreEn(p) {
  const s = Math.max(0, Math.floor((p.inicio - estado.ahora) / 1000));
  const h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60);
  return h >= 24 ? `${Math.floor(h / 24)}d ${h % 24}h` : `${String(h).padStart(2, '0')}h ${String(m).padStart(2, '0')}m`;
}
function tarjetaPartido(p) {
  const L = esc(p.local), V = esc(p.visitante);
  const cab = (chip, extra) => `<div class="flex items-center justify-between"><div class="flex items-center gap-2">${chip}<span class="font-body-sm text-[11px] text-on-surface-variant">#${esc(p.id)} · ${esc(p.fase)}${p.grupo ? ' · Grupo ' + esc(p.grupo) : ''}</span></div>${extra}</div>`;
  const equipos = (centro) => `<div class="flex items-center justify-between py-1"><div class="flex items-center gap-3">${insignia(p.local)}<span class="font-headline-sm text-headline-sm text-on-surface">${L}</span></div>${centro}<div class="flex items-center gap-3"><span class="font-headline-sm text-headline-sm text-on-surface">${V}</span>${insignia(p.visitante)}</div></div>`;
  const marc = `<div class="flex items-center gap-3"><span class="font-metric-display text-metric-display text-on-surface">${esc(p.marcador[0])}</span><span class="text-outline font-bold">-</span><span class="font-metric-display text-metric-display text-on-surface">${esc(p.marcador[1])}</span></div>`;
  const base = 'match-item bg-surface-container-low rounded-lg p-space-md flex flex-col gap-2 relative shadow-sm hover:shadow-md transition-shadow cursor-pointer';
  if (p.estado === 'en_vivo') return `<div class="${base}" data-id="${esc(p.id)}">${cab('<span class="inline-flex items-center gap-1 px-2 py-0.5 rounded font-label-sm text-label-sm bg-secondary-container text-on-secondary-fixed font-bold"><span class="h-2 w-2 rounded-full bg-secondary animate-pulse"></span>EN VIVO</span>', '<span class="font-mono text-label-sm text-on-surface-variant">' + esc(fechaUtc(p.inicio)) + '</span>')}${equipos(marc)}</div>`;
  if (p.estado === 'finalizado') return `<div class="${base}" data-id="${esc(p.id)}">${cab('<span class="inline-flex items-center gap-1 px-2 py-0.5 rounded font-label-sm text-label-sm bg-surface-container-highest text-on-surface-variant font-bold">FINALIZADO</span>', '<span class="font-label-sm text-[10px] text-on-surface-variant">' + (p.ganador ? 'Ganador: ' + esc(p.ganador) : 'Empate') + '</span>')}${equipos(marc)}</div>`;
  return `<div class="${base}" data-id="${esc(p.id)}">${cab('<span class="inline-flex items-center gap-1 px-2 py-0.5 rounded font-label-sm text-label-sm bg-tertiary-fixed text-on-tertiary-fixed font-bold">PROGRAMADO</span>', '<span class="font-label-sm text-[10px] text-error font-bold">Cierre en ' + cierreEn(p) + '</span>')}${equipos('<div class="flex items-center gap-2 font-headline-sm text-headline-sm text-outline"><span>vs</span></div>')}<div class="text-[11px] text-on-surface-variant">Inicio ${esc(fechaUtc(p.inicio))}</div></div>`;
}
function pintarPartidos() {
  const cuenta = (e) => estado.partidos.filter((p) => p.estado === e).length;
  const tabs = [['all', `Todos (${estado.partidos.length})`], ['en_vivo', `En vivo (${cuenta('en_vivo')}) 🟢`], ['programado', `Programados (${cuenta('programado')}) 🟡`], ['finalizado', `Finalizados (${cuenta('finalizado')}) ⚪`]];
  $('tabs-partidos').innerHTML = tabs.map(([k, t]) => `<button type="button" data-f="${k}" class="px-space-md py-1 rounded font-label-sm text-label-sm font-bold ${estado.filtro === k ? 'bg-surface-container-lowest text-on-surface shadow-sm' : 'text-on-surface-variant hover:text-on-surface'}">${t}</button>`).join('');
  $('tabs-partidos').querySelectorAll('button').forEach((b) => b.addEventListener('click', () => { estado.filtro = b.dataset.f; pintarPartidos(); }));
  let lista = estado.partidos.filter((p) => estado.filtro === 'all' || p.estado === estado.filtro);
  if (estado.filtro === 'finalizado') lista = lista.slice().reverse();
  $('partidos').innerHTML = lista.slice(0, 40).map(tarjetaPartido).join('') || '<p class="font-body-sm text-body-sm text-on-surface-variant py-2">No hay partidos en este estado.</p>';
  $('partidos').querySelectorAll('.match-item').forEach((d) => d.addEventListener('click', () => abrirDetalle(+d.dataset.id)));
}
function actualizarPartido(snap) {
  const i = estado.partidos.findIndex((p) => p.id === snap.id);
  if (i >= 0) estado.partidos[i] = snap; else estado.partidos.push(snap);
  pintarPartidos();
}

// ---- formulario de pronóstico ----
function llenarSelectorPronostico() {
  const sel = $('p-partido'); const previo = sel.value;
  sel.innerHTML = estado.partidos.map((p) => `<option value="${esc(p.id)}" ${p.estado !== 'programado' ? 'disabled' : ''}>#${esc(p.id)} ${esc(p.local)} vs ${esc(p.visitante)}${p.estado === 'programado' ? ' - ' + esc(fechaUtc(p.inicio)) : ' - ' + (p.estado === 'en_vivo' ? 'EN VIVO (cerrado)' : 'finalizado')}</option>`).join('');
  const abiertos = estado.partidos.filter((p) => p.estado === 'programado');
  if (previo && estado.partidos.some((p) => String(p.id) === previo && p.estado === 'programado')) sel.value = previo;
  else if (abiertos.length) sel.value = String(abiertos[0].id);
  etiquetasEquipos();
}
function etiquetasEquipos() {
  const p = estado.partidos.find((x) => String(x.id) === $('p-partido').value);
  $('p-eq-l').textContent = p ? `${p.local} (${codigo(p.local)})` : 'Local';
  $('p-eq-v').textContent = p ? `${p.visitante} (${codigo(p.visitante)})` : 'Visitante';
}
$('p-partido').addEventListener('change', etiquetasEquipos);
$('prediction-form').addEventListener('submit', async (ev) => {
  ev.preventDefault();
  const cuerpo = { participante: $('p-part').value.trim(), partido: +$('p-partido').value, local: +$('p-l').value, visitante: +$('p-v').value,
                   ts_cliente: Date.now() };  // se envía a propósito: el servidor lo ignora
  const { status, datos } = await api('/api/predicciones', { method: 'POST', body: JSON.stringify(cuerpo) });
  const c = $('pron-res'); c.hidden = false;
  if (status === 200) { c.className = msgClase('ok'); c.textContent = '¡Pronóstico aceptado y guardado!'; }
  else if (status === 409) { c.className = msgClase('falla'); c.textContent = 'Rechazado: el partido ya cerró (lo decide el reloj del servidor).'; }
  else { c.className = msgClase('alerta'); c.textContent = `No se aceptó (${status}): ${(datos && datos.error) || 'error'}`; }
});

// ---- detalle de partido ----
async function cargarListaDetalle() {
  if (!estado.partidos.length) await cargarPartidos();
  const previo = $('d-sel').value;
  $('d-sel').innerHTML = estado.partidos.map((p) => `<option value="${esc(p.id)}">#${esc(p.id)} ${esc(p.local)} vs ${esc(p.visitante)} (${esc(p.estado)})</option>`).join('');
  if (previo) $('d-sel').value = previo;
  if ($('d-sel').value) abrirDetalle(+$('d-sel').value, true);
}
$('d-sel').addEventListener('change', () => abrirDetalle(+$('d-sel').value, true));
async function abrirDetalle(id, ya) {
  if (!ya) irA('detalle');
  $('d-sel').value = String(id);
  const { ok, datos } = await api('/api/partidos/' + id);
  if (!ok) { $('d-hero').textContent = 'No se pudo cargar el partido.'; return; }
  const p = datos.partido; const ev = datos.eventos || [];
  const anul = ev.filter((e) => e.anulado);
  const vivo = p.estado === 'en_vivo';
  const goles = (lado) => ev.filter((e) => e.lado === lado).map((e) => `<span class="${e.anulado ? 'anulado text-on-surface-variant' : ''}">⚽ Gol ${esc(e.minuto)}'${e.anulado ? ' (VAR)' : ''}</span>`).join(' <span class="text-outline">•</span> ') || '<span class="text-on-surface-variant">Sin goles</span>';
  $('d-ruta').textContent = `${p.fase}${p.grupo ? ' · Grupo ' + p.grupo : ''} · Partido #${p.id}`;
  $('d-hero').innerHTML = `
    <div class="flex flex-wrap items-center justify-between gap-space-sm pb-space-sm">
      <div class="flex items-center gap-space-sm"><span class="inline-flex items-center px-space-sm py-0.5 rounded bg-primary-container text-on-primary font-label-sm text-label-sm uppercase tracking-wider">${esc(p.fase)}${p.grupo ? ' • GRUPO ' + esc(p.grupo) : ''}</span>
        <span class="text-on-surface-variant font-body-sm text-body-sm flex items-center gap-1"><span class="material-symbols-outlined text-[16px]">event</span>Inicio ${esc(fechaUtc(p.inicio))}</span></div>
      <div class="flex items-center gap-space-sm"><div class="inline-flex items-center gap-2 px-space-md py-1 rounded-full font-label-md text-label-md tracking-wider ${vivo ? 'bg-secondary/10 text-secondary' : 'bg-surface-container text-on-surface-variant'}">
        ${vivo ? '<span class="relative flex h-2.5 w-2.5"><span class="animate-ping absolute inline-flex h-full w-full rounded-full bg-secondary opacity-75"></span><span class="relative inline-flex rounded-full h-2.5 w-2.5 bg-secondary"></span></span>' : ''}<span class="font-bold uppercase">${vivo ? 'EN VIVO' : esc(p.estado)}</span></div>
        <span class="inline-flex items-center px-space-sm py-1 rounded bg-surface-container text-on-surface-variant font-label-sm text-label-sm font-semibold">TELEMETRÍA NOMINAL</span></div>
    </div>
    <div class="flex flex-wrap items-center justify-center gap-space-xl py-space-md">
      <div class="flex items-center gap-3 flex-1 justify-end min-w-[180px]">${insignia(p.local)}<span class="font-display-lg text-display-lg uppercase">${esc(p.local)}</span></div>
      <div class="flex flex-col items-center"><div class="font-display-lg text-display-lg flex items-center gap-3" style="font-size:56px;line-height:60px">${esc(p.marcador[0])}<span class="text-outline">-</span>${esc(p.marcador[1])}</div>
        <span class="mt-2 px-3 py-1 rounded-full bg-surface-container font-label-sm text-label-sm text-on-surface-variant">${vivo ? 'PARTIDO EN CURSO' : p.estado === 'finalizado' ? 'MARCADOR FINAL' : 'POR JUGARSE'}</span></div>
      <div class="flex items-center gap-3 flex-1 min-w-[180px]"><span class="font-display-lg text-display-lg uppercase">${esc(p.visitante)}</span>${insignia(p.visitante)}</div>
    </div>
    <div class="grid grid-cols-1 md:grid-cols-2 gap-space-sm rounded-lg bg-surface-container-low p-space-md font-body-sm text-body-sm">
      <div><div class="font-label-sm text-label-sm text-on-surface-variant uppercase mb-1">Goles ${esc(p.local)}</div>${goles('local')}</div>
      <div class="md:text-right"><div class="font-label-sm text-label-sm text-on-surface-variant uppercase mb-1">Goles ${esc(p.visitante)}</div>${goles('visitante')}</div>
    </div>
    <div class="flex flex-wrap items-center justify-between gap-space-sm rounded-lg bg-surface-container px-space-md py-space-sm font-body-sm text-body-sm">
      <span class="flex items-center gap-2"><span class="material-symbols-outlined text-[18px]">lock</span><span><b>PRONÓSTICOS ${p.estado === 'programado' ? 'ABIERTOS' : 'CERRADOS'}</b> · el cierre lo decide el reloj del servidor (${esc(fechaUtc(p.inicio))})</span></span>
      ${p.ganador ? '<span class="px-3 py-1 rounded bg-secondary-container text-on-secondary-fixed font-label-sm text-label-sm font-bold">GANADOR: ' + esc(String(p.ganador).toUpperCase()) + '</span>' : ''}
    </div>`;
  $('d-var').innerHTML = anul.length ? `<div class="rounded-xl bg-surface-container-lowest shadow-sm overflow-hidden"><div class="h-1.5 bg-error"></div><div class="p-space-lg bg-error-container/40 flex flex-col gap-space-sm">
      <div class="flex flex-wrap items-center gap-space-sm"><span class="inline-flex px-2 py-0.5 rounded bg-error text-on-error font-label-sm text-label-sm uppercase font-bold">Incidencia VAR</span><span class="font-label-sm text-label-sm text-error font-bold uppercase">Gol anulado</span></div>
      <p class="font-headline-sm text-headline-sm text-on-surface">${anul.length} gol(es) anulado(s) por revisión VAR en este partido.</p>
      <p class="font-body-md text-body-md text-on-surface-variant"><span class="material-symbols-outlined text-[16px] align-middle">sync_alt</span> Impacto automático en las quinielas: los pronósticos que dependían del marcador anulado se recalcularon y se difundió el nuevo ranking por SSE.</p></div></div>` : '';
  const m = estado.metricas;
  const S = (t, n, sub, ico, cls) => `<div class="bg-surface-container-lowest rounded-xl shadow-sm p-space-md flex flex-col gap-1"><div class="flex items-center justify-between"><span class="font-label-sm text-label-sm text-on-surface-variant uppercase tracking-wide">${esc(t)}</span><span class="material-symbols-outlined text-[20px] ${cls}">${ico}</span></div><div class="font-metric-display text-metric-display text-on-surface">${esc(n)}</div><div class="font-body-sm text-body-sm text-on-surface-variant">${esc(sub)}</div></div>`;
  $('d-stats').innerHTML = S('Pronósticos a tiempo', datos.pronosticos, 'recibidos antes del cierre', 'check_circle', 'text-secondary')
    + S('Pronósticos rechazados', m.predicciones_rechazadas || 0, 'extemporáneos (todos los partidos)', 'cancel', 'text-error')
    + S('Goles anulados VAR', anul.length, 'en este partido', 'videocam_off', 'text-on-tertiary-container');
  $('d-eventos').innerHTML = ev.map((e) => `<tr><td class="py-2 px-space-sm text-right font-mono">${esc(e.minuto)}'</td><td class="py-2 px-space-sm ${e.anulado ? 'anulado text-on-surface-variant' : ''}">Gol ${esc(e.lado === 'local' ? p.local : p.visitante)} (#${esc(e.n)})</td><td class="py-2 px-space-sm">${e.anulado ? '<span class="px-2 py-0.5 rounded bg-error-container text-on-error-container font-label-sm text-label-sm font-bold">ANULADO POR VAR</span>' : '<span class="px-2 py-0.5 rounded bg-secondary-container text-on-secondary-fixed font-label-sm text-label-sm font-bold">VÁLIDO</span>'}</td></tr>`).join('')
    || '<tr><td colspan="3" class="py-4 px-space-sm text-on-surface-variant">Sin eventos todavía.</td></tr>';
}
function cargarListaDetalleSiVisible() { if (!$('v-detalle').hidden && $('d-sel').value) abrirDetalle(+$('d-sel').value, true); }
$('b-sync').addEventListener('click', () => { if ($('d-sel').value) abrirDetalle(+$('d-sel').value, true); });

// ---- bitácora ----
async function cargarBitacora() {
  const { datos } = await api('/api/bitacora?n=200');
  estado.bitacora = ((datos && datos.entradas) || []);
  pintarBitacora(); pintarBanerVar(); pintarMetricasBitacora();
}
function tituloBitacora(e) {
  const d = e.datos || {};
  switch (e.tipo) {
    case 'gol': return `Gol ${d.lado} en el partido #${d.partido} (minuto ${d.minuto})`;
    case 'partido_inicio': return `Inicio del partido #${d.partido}: ${d.local} vs ${d.visitante}`;
    case 'partido_final': return `Final del partido #${d.partido}`;
    case 'gol_anulado_var': return `Gol anulado por VAR en el partido #${d.partido}`;
    case 'pronostico_rechazado': return `Pronósticos rechazados tras el cierre en el partido #${d.partido}`;
    case 'proceso_muerto': return `Proceso ${d.tipo} ${d.id} terminado forzosamente`;
    case 'proceso_recuperado': return `Proceso ${d.tipo} ${d.id} recuperado en ${Number(d.recuperado_ms).toFixed(2)} ms`;
    default: return e.tipo;
  }
}
function visibles() {
  const q = estado.busca.toLowerCase();
  return estado.bitacora.filter((e) => (estado.sev === 'all' || e.nivel === estado.sev)
    && (!q || (e.tipo + ' ' + JSON.stringify(e.datos) + ' ' + tituloBitacora(e)).toLowerCase().includes(q)));
}
function pintarBitacora() {
  const bts = [['all', 'Todos', 'bg-primary text-on-primary', ''], ['ok', 'Operando', 'bg-surface-container-low text-secondary hover:bg-secondary-container', 'bg-secondary'],
               ['alerta', 'Alerta', 'bg-surface-container-low text-on-tertiary-container hover:bg-tertiary-fixed', 'bg-on-tertiary-container'], ['falla', 'Falla', 'bg-surface-container-low text-error hover:bg-error-container', 'bg-error']];
  $('sev-btns').innerHTML = bts.map(([k, t, c, p]) => `<button type="button" data-k="${k}" class="px-space-sm py-1 rounded-lg font-label-sm text-label-sm transition-colors flex items-center gap-1 ${estado.sev === k ? 'bg-primary text-on-primary' : c.replace('bg-primary text-on-primary', 'bg-surface-container-low')}">${p ? '<span class="w-1.5 h-1.5 rounded-full ' + p + '"></span>' : ''}${t}</button>`).join('');
  $('sev-btns').querySelectorAll('button').forEach((b) => b.addEventListener('click', () => { estado.sev = b.dataset.k; pintarBitacora(); }));
  $('timeline').innerHTML = visibles().slice(0, 100).map((e) => {
    const s = sevDe(e.nivel);
    return `<div class="p-space-md rounded-xl ${s.fila} transition-colors shadow-sm flex flex-col gap-space-xs">
      <div class="flex flex-wrap items-center justify-between gap-space-xs"><div class="flex items-center gap-space-sm flex-wrap">
        <span class="font-mono text-label-sm px-2 py-0.5 rounded bg-surface-container text-on-surface font-semibold">${esc(horaUtc(e.ts))}</span>
        <span class="inline-flex items-center gap-1 px-2 py-0.5 rounded-full ${s.bg} font-label-sm text-label-sm font-bold"><span class="w-1.5 h-1.5 rounded-full ${s.punto}"></span>${s.txt} • ${esc(String(e.tipo).replace(/_/g, ' ').toUpperCase())}</span></div>
        <span class="font-mono text-label-sm text-on-surface-variant">TX: #${esc(e.n)}</span></div>
      <div class="font-headline-sm text-headline-sm ${s.tit}">${esc(tituloBitacora(e))}</div>
      <p class="font-mono text-[11px] text-on-surface-variant break-all">${esc(JSON.stringify(e.datos))}</p></div>`;
  }).join('') || '<p class="font-body-sm text-body-sm text-on-surface-variant py-4">Sin eventos con ese filtro.</p>';
  pintarRecuperaciones();
}
$('audit-search').addEventListener('input', () => { estado.busca = $('audit-search').value; pintarBitacora(); });
$('btn-pause-feed').addEventListener('click', () => {
  estado.pausa = !estado.pausa;
  $('pausa-txt').textContent = estado.pausa ? 'EN PAUSA' : 'TIEMPO REAL';
  $('pausa-ico').textContent = estado.pausa ? 'play_circle' : 'pause_circle';
  if (!estado.pausa) pintarBitacora();
});
function pintarBanerVar() {
  const e = estado.bitacora.find((x) => x.tipo === 'gol_anulado_var');
  $('ban-var').hidden = !e || Date.now() - e.ts > 60000;
  if (e) { $('ban-var-txt').textContent = `Partido #${e.datos.partido}: gol anulado tras revisión VAR. Puntos revertidos y ranking recalculado.`; $('ban-var-id').textContent = 'EVENTO #' + e.n; }
}
function pintarMetricasBitacora() {
  const m = estado.metricas; const ult = estado.bitacora.length ? estado.bitacora[0].n : 0;
  const M = (t, n, ico, sub, cls) => `<div class="flex flex-col justify-between p-space-lg rounded-xl bg-surface-container-lowest shadow-sm"><div class="flex items-center justify-between"><span class="font-label-sm text-label-sm text-on-surface-variant uppercase font-bold tracking-wider">${esc(t)}</span><span class="material-symbols-outlined text-outline text-[20px]">${ico}</span></div><div class="my-space-sm font-metric-display text-metric-display text-on-surface">${esc(n)}</div><div class="font-label-sm text-label-sm ${cls}">${esc(sub)}</div></div>`;
  $('b-metricas').innerHTML = M('Eventos registrados', ult, 'assignment', 'contador de la bitácora', 'text-secondary')
    + M('Fallas de proceso simuladas', m.fallas_inyectadas || 0, 'bug_report', 'todas recuperadas por el supervisor', 'text-secondary')
    + M('Goles VAR con recálculo', m.anulaciones_var || 0, 'videocam_off', 'ranking recalculado', 'text-on-tertiary-container')
    + M('Pronósticos extemporáneos', m.predicciones_rechazadas || 0, 'block', 'bloqueados por cierre', 'text-error');
}
function pintarProcesos() {
  const e = estado.srv; if (!e) return;
  const filas = [['partido', 'Procesos de partido', e.procesos.partidos, 'sports_soccer'], ['quiniela', 'Procesos de quiniela', e.procesos.quinielas, 'groups'], ['participante', 'Procesos de participante', e.procesos.participantes, 'person']];
  const E = (t, n, ico, sub) => `<div class="flex items-center gap-space-md p-space-md rounded-xl bg-surface-container-lowest shadow-sm"><div class="w-10 h-10 rounded-full flex items-center justify-center shrink-0 bg-secondary-container text-on-secondary-fixed"><span class="material-symbols-outlined text-[20px]">${ico}</span></div><div class="flex flex-col min-w-0"><div class="flex items-center gap-1.5"><span class="w-2 h-2 rounded-full bg-secondary"></span><span class="font-label-sm text-label-sm text-secondary uppercase font-bold">OPERANDO</span></div><span class="font-label-lg text-label-lg text-on-surface truncate">${esc(t)}</span><span class="font-body-sm text-body-sm text-on-surface-variant truncate">${sub}</span></div></div>`;
  $('b-estado').innerHTML = filas.map(([k, t, n, ico]) => E(t, n, ico, `<strong class="font-semibold text-on-surface">${esc(n)}</strong> vivos`)).join('')
    + E('Servidor SSE (difusión)', '', 'sensors', `<strong class="font-semibold text-on-surface">${esc(e.sse_conectados)}</strong> clientes suscritos`);
  $('proc-vivos').textContent = (e.procesos.partidos + e.procesos.quinielas + e.procesos.participantes) + ' VIVOS';
  $('procesos').innerHTML = filas.map(([k, t, n]) => `<div class="p-space-md rounded-xl bg-surface-container-low flex flex-col gap-space-sm"><div class="flex items-center justify-between"><div class="flex items-center gap-space-sm"><span class="w-2.5 h-2.5 rounded-full bg-secondary"></span><span class="font-label-lg text-label-lg text-on-surface">${esc(t)}</span></div><span class="font-mono text-label-sm text-on-surface-variant">${esc(n)} vivos</span></div>
    <div class="flex items-center justify-end"><button type="button" data-obj="${k}" class="matar px-space-sm py-1 rounded bg-error text-on-error font-label-sm text-label-sm hover:opacity-90 transition-opacity">Matar uno</button></div></div>`).join('');
  $('procesos').querySelectorAll('.matar').forEach((b) => b.addEventListener('click', () => inyectarFalla(b.dataset.obj)));
}
function pintarRecuperaciones() {
  const r = estado.bitacora.filter((e) => e.tipo === 'proceso_recuperado').slice(0, 8);
  $('recup').innerHTML = r.map((e) => `<div class="flex items-center justify-between"><span class="text-on-surface-variant">${esc(e.datos.tipo)} ${esc(e.datos.id)}</span><span class="text-secondary font-bold">${Number(e.datos.recuperado_ms).toFixed(2)} ms</span></div>`).join('') || '<span class="text-on-surface-variant">Aún no hay fallas inyectadas.</span>';
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
function sondearSim() { clearInterval(sondeo); sondeo = setInterval(async () => { const { datos } = await api('/api/simulacion'); pintarSimulacion(datos); if (datos && datos.estado !== 'corriendo') { clearInterval(sondeo); await cargarQuinielas(); await cargarPartidos(); cargarBitacora(); } }, 700); }
function pintarSimulacion(s) {
  if (!s) return;
  const pr = s.progreso || {}; const total = pr.partidos_total || 0;
  $('progreso').style.width = s.estado === 'terminado' ? '100%' : total ? Math.round(100 * (pr.partidos_hechos || 0) / total) + '%' : '0';
  const txt = { inactivo: 'Sin simulación en curso.', corriendo: `En curso: ${pr.fase || ''}`, terminado: 'Simulación terminada.', error: 'La simulación falló.' };
  $('sim-estado').textContent = txt[s.estado] || '';
  $('sim-n').textContent = s.estado === 'corriendo' && total ? `${pr.partidos_hechos || 0} / ${total} partidos` : '';
  if (s.estado === 'terminado' && s.reporte) {
    const r = s.reporte; const pre = $('sim-reporte'); pre.hidden = false;
    pre.textContent = JSON.stringify({
      duracion_ms: r.duracion_ms, partidos: r.partidos_simulados, simultaneos_max: r.simultaneos_max,
      rafaga: r.rafaga && { aceptadas: r.rafaga.aceptadas, intentos: r.rafaga.intentos, tarde_rechazadas: r.rafaga.tarde_rechazadas, tarde_intentos: r.rafaga.tarde_intentos },
      consistencia: r.consistencia, caos_eventos: (r.caos || []).length, var_eventos: (r.var || []).length, memoria_mb: r.memoria_mb,
    }, null, 2);
  }
}

// ---- fallas (caos) ----
function toast(texto, nivel) {
  let t = $('toast');
  if (!t) { t = document.createElement('div'); t.id = 'toast'; t.className = 'fixed bottom-6 right-6 z-[60] max-w-sm'; document.body.appendChild(t); }
  t.innerHTML = `<div class="${msgClase(nivel)} shadow-xl">${esc(texto)}</div>`;
  clearTimeout(t._h); t._h = setTimeout(() => { t.innerHTML = ''; }, 6000);
}
async function inyectarFalla(objetivo) {
  const { status, datos } = await api('/api/falla', { method: 'POST', headers: admin(), body: JSON.stringify({ objetivo }) });
  const log = $('falla-res'); const h = new Date().toTimeString().split(' ')[0];
  let texto, nivel;
  if (status === 200) { estado.ultimaFalla = Date.now(); texto = `Proceso ${datos.resultado.tipo} ${datos.resultado.id} muerto y recuperado en ${Number(datos.resultado.recuperado_ms).toFixed(2)} ms.`; nivel = 'ok'; cargarRanking(); cargarResumen(); }
  else if (status === 401) { texto = 'Token admin inválido.'; nivel = 'alerta'; }
  else { texto = 'Sin procesos que matar: inicia una simulación primero.'; nivel = 'alerta'; }
  log.textContent = `[${h}] ${texto}\n` + (log.textContent.startsWith('[LOG]') ? '' : log.textContent);
  toast(texto, nivel);
}
$('b-falla').addEventListener('click', () => inyectarFalla($('f-obj').value));
$('b-falla-top').addEventListener('click', () => inyectarFalla($('f-obj').value));
$('b-falla-h').addEventListener('click', () => inyectarFalla($('f-obj').value));
$('b-falla-d').addEventListener('click', () => inyectarFalla('partido'));
$('btn-chaos').addEventListener('click', () => inyectarFalla($('chaos-target').value));

// ---- tiempo real (SSE) ----
let fuente = null;
function logSse(texto, nivel) {
  const log = $('sse-log'); const h = new Date().toTimeString().split(' ')[0];
  const d = document.createElement('div');
  d.className = nivel === 'falla' ? 'text-error-container bg-error/30 p-1 rounded font-bold' : nivel === 'alerta' ? 'text-tertiary-fixed-dim' : 'text-secondary-fixed';
  d.textContent = `[${h}] ${texto}`;
  log.insertBefore(d, log.firstChild);
  while (log.children.length > 60) log.removeChild(log.lastChild);
}
function conectarSse() {
  if (fuente) fuente.close();
  fuente = new EventSource('/api/eventos' + (estado.quiniela ? '?quiniela=' + encodeURIComponent(estado.quiniela) : ''));
  fuente.addEventListener('ranking', (m) => { const e = JSON.parse(m.data); if (e.quiniela === estado.quiniela) pintarRanking(e.top); });
  fuente.addEventListener('partido', (m) => { actualizarPartido(JSON.parse(m.data).partido); });
  fuente.addEventListener('bitacora', (m) => {
    const e = JSON.parse(m.data).entrada;
    logSse(`${String(e.tipo).toUpperCase()} ${JSON.stringify(e.datos)}`, e.nivel);
    estado.bitacora.unshift(e); estado.bitacora.length = Math.min(estado.bitacora.length, 300);
    if (e.nivel === 'falla') estado.ultimaFalla = Date.now();
    if (e.tipo === 'gol_anulado_var') pintarBanerVar();
    if (!$('v-bitacora').hidden && !estado.pausa) { pintarBitacora(); pintarMetricasBitacora(); }
    if (e.tipo === 'gol' || e.tipo === 'gol_anulado_var') cargarListaDetalleSiVisible();
  });
  fuente.onopen = () => { if (estado.conectadoUnaVez) { estado.reconex++; $('reconex').textContent = estado.reconex; $('d-reco').textContent = estado.reconex; } estado.conectadoUnaVez = true; logSse('HEARTBEAT: canal SSE conectado', 'ok'); };
  fuente.onerror = () => { semaforo('alerta', 'RECONECTANDO'); logSse('SSE: reconectando…', 'alerta'); };
}

// ---- arranque ----
cargarQuinielas(); cargarPartidos(); cargarResumen(); cargarBitacora();
setInterval(cargarResumen, 2000);
setInterval(() => { if (!$('v-dashboard').hidden && estado.partidos.some((p) => p.estado === 'programado')) pintarPartidos(); }, 5000);

// Enlaces directos a cada pantalla: /#detalle, /#bitacora
const vistaInicial = (location.hash || '').replace('#', '');
if (['detalle', 'bitacora'].includes(vistaInicial)) irA(vistaInicial);
