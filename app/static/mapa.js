// Mapa de asientos: consulta el estado cada 2 segundos y permite elegir asientos libres.
const mapa = document.getElementById("mapa");
const idFuncion = mapa.dataset.funcion;
const maximo = Number(mapa.dataset.maximo);
const seleccion = new Set();
const botonBloquear = document.getElementById("bloquear");
const mensaje = document.getElementById("mensaje");

function mostrarError(texto) {
  mensaje.textContent = texto;
  mensaje.hidden = false;
}

function dibujar(asientos) {
  const filas = {};
  for (const a of asientos) (filas[a.fila] = filas[a.fila] || []).push(a);
  mapa.innerHTML = "";
  for (const letra of Object.keys(filas).sort()) {
    const fila = document.createElement("div");
    fila.className = "fila-asientos";
    fila.innerHTML = `<span class="letra">${letra}</span>`;
    for (const a of filas[letra]) {
      const boton = document.createElement("button");
      boton.className = "asiento " + a.estado;
      boton.textContent = a.numero;
      boton.title = `${a.fila}${a.numero} · ${a.zona}`;
      boton.dataset.id = a.id_asiento;
      if (a.estado !== "disponible") seleccion.delete(a.id_asiento);
      if (seleccion.has(a.id_asiento)) boton.classList.add("seleccionado");
      boton.disabled = a.estado !== "disponible";
      boton.addEventListener("click", () => alternar(a.id_asiento, boton));
      fila.appendChild(boton);
    }
    mapa.appendChild(fila);
  }
  actualizarContador();
}

function alternar(id, boton) {
  if (seleccion.has(id)) {
    seleccion.delete(id);
    boton.classList.remove("seleccionado");
  } else if (seleccion.size < maximo) {
    seleccion.add(id);
    boton.classList.add("seleccionado");
  } else {
    mostrarError(`Se pueden elegir como máximo ${maximo} asientos por compra.`);
  }
  actualizarContador();
}

function actualizarContador() {
  document.getElementById("cantidad").textContent = seleccion.size;
  botonBloquear.disabled = seleccion.size === 0;
}

async function refrescar() {
  const respuesta = await fetch(`/api/funciones/${idFuncion}/asientos`);
  if (respuesta.ok) dibujar(await respuesta.json());
}

botonBloquear.addEventListener("click", async () => {
  botonBloquear.disabled = true;
  const respuesta = await fetch(`/api/funciones/${idFuncion}/bloquear`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ asientos: [...seleccion] }),
  });
  const datos = await respuesta.json();
  if (respuesta.ok) {
    window.location = `/orden/${datos.id_orden}`;
  } else {
    mostrarError(datos.error);
    seleccion.clear();
    refrescar();
  }
});

refrescar();
setInterval(refrescar, 2000);
