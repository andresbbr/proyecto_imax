// Temporizador del bloqueo y pago simulado.
const temporizador = document.getElementById("temporizador");
const botonPagar = document.getElementById("pagar");
const expira = new Date(temporizador.dataset.expira);

function contar() {
  const restante = Math.max(0, Math.floor((expira - new Date()) / 1000));
  const minutos = String(Math.floor(restante / 60)).padStart(2, "0");
  const segundos = String(restante % 60).padStart(2, "0");
  temporizador.textContent = `${minutos}:${segundos}`;
  if (restante === 0) {
    temporizador.textContent = "Tiempo agotado: los asientos se liberaron";
    botonPagar.disabled = true;
    clearInterval(intervalo);
  }
}
const intervalo = setInterval(contar, 1000);
contar();

// Solo se muestran los datos de tarjeta si el método es tarjeta
const metodo = document.getElementById("metodo");
const datosTarjeta = document.getElementById("datos-tarjeta");
function mostrarDatosTarjeta() {
  datosTarjeta.hidden = metodo.selectedOptions[0].dataset.tarjeta !== "si";
}
metodo.addEventListener("change", mostrarDatosTarjeta);
mostrarDatosTarjeta();

// RN-09: del número de tarjeta solo se envían los últimos 4 dígitos y la marca
function marcaDe(numero) {
  if (numero.startsWith("4")) return "visa";
  if (/^5[1-5]/.test(numero)) return "mastercard";
  if (/^3[47]/.test(numero)) return "amex";
  return "otra";
}

document.getElementById("pago").addEventListener("submit", (evento) => {
  if (datosTarjeta.hidden) return;
  const numero = document.getElementById("numero-tarjeta").value.replace(/\D/g, "");
  if (numero.length < 12) {
    evento.preventDefault();
    alert("Ingrese un número de tarjeta de prueba (al menos 12 dígitos).");
    return;
  }
  document.getElementById("ultimos4").value = numero.slice(-4);
  document.getElementById("marca").value = marcaDe(numero);
});
