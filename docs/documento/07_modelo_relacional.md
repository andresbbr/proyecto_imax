# 7. Modelo relacional documentado

Diccionario de datos del modelo lógico: las 31 tablas de los esquemas `cine` y `bitacora`, con sus columnas, tipo lógico, nulabilidad, claves y restricciones previstas. Los diagramas están en la sección 6.2 (`docs/diagramas/modelo_logico_*.png`). Los tipos físicos de PostgreSQL, los índices, el particionamiento y los permisos se definen en el diseño físico.

Convenciones:

- **Clave:** PK (clave primaria), FK (clave foránea), UK (única).
- **Tipos lógicos:**
  - **entero:** identificador o cantidad entera.
  - **entero corto:** valores pequeños (fila, número, días).
  - **decimal(p,s):** montos en USD con 2 decimales.
  - **fecha_hora:** instante con zona horaria.
  - **json:** carga de auditoría semiestructurada.
  - **ip:** dirección IPv4 o IPv6.
- Las restricciones descritas como "regla" (por ejemplo, la emisión de boletos solo con la orden pagada) involucran más de una tabla y se implementan con funciones o triggers.

### Ubicación

**cine.pais**: País donde opera al menos una sede; guarda la tasa de impuesto aplicable a la venta.

| Columna | Tipo lógico | Nulo | Clave | Nota |
|---|---|---|---|---|
| `id_pais` | entero | No | PK |  |
| `codigo_iso` | texto(2) | No | UK | ISO 3166-1 alfa-2 |
| `nombre` | texto | No | UK |  |
| `tasa_impuesto` | decimal(5,4) | No |  | Fracción entre 0 y 1 |

- PK: (id_pais)
- CHECK: tasa_impuesto entre 0 y 1

**cine.ciudad**: Ciudad de un país.

| Columna | Tipo lógico | Nulo | Clave | Nota |
|---|---|---|---|---|
| `id_ciudad` | entero | No | PK |  |
| `id_pais` | entero | No | FK | pais |
| `nombre` | texto | No |  |  |

- PK: (id_ciudad)
- FK: id_pais → pais(id_pais)
- UNIQUE: (id_pais, nombre)

**cine.sede**: Complejo de cines IMAX con su dirección exacta (RN-02).

| Columna | Tipo lógico | Nulo | Clave | Nota |
|---|---|---|---|---|
| `id_sede` | entero | No | PK |  |
| `id_ciudad` | entero | No | FK | ciudad |
| `nombre` | texto | No | UK |  |
| `direccion` | texto | No |  |  |
| `es_activa` | booleano | No |  |  |

- PK: (id_sede)
- FK: id_ciudad → ciudad(id_ciudad)

### Salas y asientos

**cine.sala**: Sala IMAX de una sede.

| Columna | Tipo lógico | Nulo | Clave | Nota |
|---|---|---|---|---|
| `id_sala` | entero | No | PK |  |
| `id_sede` | entero | No | FK | sede |
| `nombre` | texto | No |  |  |
| `formato` | texto | No |  | IMAX con láser, IMAX digital |
| `es_activa` | booleano | No |  |  |

- PK: (id_sala)
- FK: id_sede → sede(id_sede)
- UNIQUE: (id_sede, nombre)

**cine.tipo_zona**: Categoría de ubicación para la matriz de precios (general, preferencial, VIP).

| Columna | Tipo lógico | Nulo | Clave | Nota |
|---|---|---|---|---|
| `id_tipo_zona` | entero | No | PK |  |
| `codigo` | texto | No | UK |  |
| `nombre` | texto | No |  |  |

- PK: (id_tipo_zona)

**cine.zona**: Área física de una sala (platea, palco); pertenece a un tipo de zona.

| Columna | Tipo lógico | Nulo | Clave | Nota |
|---|---|---|---|---|
| `id_zona` | entero | No | PK |  |
| `id_sala` | entero | No | FK | sala |
| `id_tipo_zona` | entero | No | FK | tipo_zona |
| `nombre` | texto | No |  |  |

- PK: (id_zona)
- FK: id_sala → sala(id_sala)
- FK: id_tipo_zona → tipo_zona(id_tipo_zona)
- UNIQUE: (id_sala, nombre)

**cine.asiento**: Asiento físico de una sala. Su conjunto es la distribución protegida por la RN-18.

| Columna | Tipo lógico | Nulo | Clave | Nota |
|---|---|---|---|---|
| `id_asiento` | entero | No | PK |  |
| `id_zona` | entero | No | FK | zona (la sala se obtiene de la zona) |
| `fila` | texto | No |  |  |
| `numero` | entero corto | No |  |  |
| `es_habilitado` | booleano | No |  | Fuera de servicio si es falso |

- PK: (id_asiento)
- FK: id_zona → zona(id_zona)
- UNIQUE: (id_zona, fila, numero)
- CHECK: numero > 0

**cine.puerta**: Tótem o acceso manual de una sala donde se escanean los QR (RN-15).

| Columna | Tipo lógico | Nulo | Clave | Nota |
|---|---|---|---|---|
| `id_puerta` | entero | No | PK |  |
| `id_sala` | entero | No | FK | sala |
| `codigo` | texto | No | UK |  |
| `tipo` | texto | No |  | totem o manual |
| `es_activa` | booleano | No |  |  |

- PK: (id_puerta)
- FK: id_sala → sala(id_sala)
- CHECK: tipo en (totem, manual)

### Catálogo

**cine.clasificacion**: Clasificación de edad (RN-02).

| Columna | Tipo lógico | Nulo | Clave | Nota |
|---|---|---|---|---|
| `id_clasificacion` | entero | No | PK |  |
| `codigo` | texto | No | UK |  |
| `descripcion` | texto | No |  |  |
| `edad_minima` | entero corto | No |  |  |

- PK: (id_clasificacion)
- CHECK: edad_minima >= 0

**cine.genero**: Género cinematográfico, usado en el filtro de cartelera.

| Columna | Tipo lógico | Nulo | Clave | Nota |
|---|---|---|---|---|
| `id_genero` | entero | No | PK |  |
| `nombre` | texto | No | UK |  |

- PK: (id_genero)

**cine.pelicula**: Película u obra con sus metadatos obligatorios (RN-02).

| Columna | Tipo lógico | Nulo | Clave | Nota |
|---|---|---|---|---|
| `id_pelicula` | entero | No | PK |  |
| `id_clasificacion` | entero | No | FK | clasificacion |
| `titulo` | texto | No |  |  |
| `sinopsis` | texto | No |  |  |
| `duracion_min` | entero corto | No |  |  |
| `poster_url` | texto | No |  |  |
| `fecha_estreno` | fecha | No |  |  |
| `es_activa` | booleano | No |  |  |

- PK: (id_pelicula)
- FK: id_clasificacion → clasificacion(id_clasificacion)
- UNIQUE: (titulo, fecha_estreno)
- CHECK: duracion_min > 0

**cine.pelicula_genero**: Relación M:N entre películas y géneros.

| Columna | Tipo lógico | Nulo | Clave | Nota |
|---|---|---|---|---|
| `id_pelicula` | entero | No | PK, FK | pelicula |
| `id_genero` | entero | No | PK, FK | genero |

- PK: (id_pelicula, id_genero)
- FK: id_pelicula → pelicula(id_pelicula)
- FK: id_genero → genero(id_genero)

### Programación

**cine.funcion**: Proyección de una película en una sala y horario.

| Columna | Tipo lógico | Nulo | Clave | Nota |
|---|---|---|---|---|
| `id_funcion` | entero | No | PK |  |
| `id_pelicula` | entero | No | FK | pelicula |
| `id_sala` | entero | No | FK | sala |
| `inicio` | fecha_hora | No |  | Con zona horaria |
| `fin` | fecha_hora | No |  | Incluye el tiempo de limpieza |
| `idioma` | texto | No |  | Original subtitulada o doblada |
| `estado` | texto | No |  | programada o cancelada |
| `creado_en` | fecha_hora | No |  |  |

- PK: (id_funcion)
- FK: id_pelicula → pelicula(id_pelicula)
- FK: id_sala → sala(id_sala)
- CHECK: fin > inicio
- CHECK: estado en (programada, cancelada)
- CHECK: regla: sin traslape de horario con otra función programada de la misma sala (trigger)

### Precios y promociones

**cine.tipo_tarifa**: Tipo de entrada: adulto, niño, tercera edad, estudiante, cortesía (RN-06).

| Columna | Tipo lógico | Nulo | Clave | Nota |
|---|---|---|---|---|
| `id_tipo_tarifa` | entero | No | PK |  |
| `codigo` | texto | No | UK |  |
| `nombre` | texto | No |  |  |
| `requiere_validacion_documento` | booleano | No |  | RN-06 |
| `es_cortesia` | booleano | No |  | Solo la asigna un administrador (RN-20) |

- PK: (id_tipo_tarifa)

**cine.tarifa**: Matriz de precios: sede, tipo de zona, tipo de tarifa y tipo de día.

| Columna | Tipo lógico | Nulo | Clave | Nota |
|---|---|---|---|---|
| `id_tarifa` | entero | No | PK |  |
| `id_sede` | entero | No | FK | sede |
| `id_tipo_zona` | entero | No | FK | tipo_zona |
| `id_tipo_tarifa` | entero | No | FK | tipo_tarifa |
| `tipo_dia` | texto | No |  | entre_semana o fin_de_semana |
| `precio` | decimal(12,2) | No |  | USD |

- PK: (id_tarifa)
- FK: id_sede → sede(id_sede)
- FK: id_tipo_zona → tipo_zona(id_tipo_zona)
- FK: id_tipo_tarifa → tipo_tarifa(id_tipo_tarifa)
- UNIQUE: (id_sede, id_tipo_zona, id_tipo_tarifa, tipo_dia)
- CHECK: tipo_dia en (entre_semana, fin_de_semana)
- CHECK: precio >= 0

**cine.promocion**: Promoción automática (2x1 o porcentaje) con sus condiciones (RN-07).

| Columna | Tipo lógico | Nulo | Clave | Nota |
|---|---|---|---|---|
| `id_promocion` | entero | No | PK |  |
| `codigo` | texto | No | UK |  |
| `nombre` | texto | No |  |  |
| `tipo` | texto | No |  | 2x1 o porcentaje |
| `porcentaje` | decimal(5,2) | Sí |  | Solo si tipo = porcentaje |
| `id_tipo_tarifa` | entero | Sí | FK | tipo_tarifa; nulo: cualquier tipo |
| `dia_semana` | entero corto | Sí |  | Nulo: cualquier día |
| `vigente_desde` | fecha | No |  |  |
| `vigente_hasta` | fecha | No |  |  |
| `es_activa` | booleano | No |  |  |

- PK: (id_promocion)
- FK: id_tipo_tarifa → tipo_tarifa(id_tipo_tarifa)
- CHECK: tipo en (2x1, porcentaje)
- CHECK: porcentaje no nulo y entre 0 y 100 si y solo si tipo = porcentaje
- CHECK: dia_semana entre 1 y 7 (1 = lunes)
- CHECK: vigente_hasta >= vigente_desde

### Configuración

**cine.parametro_sistema**: Parámetros configurables de las reglas de negocio.

| Columna | Tipo lógico | Nulo | Clave | Nota |
|---|---|---|---|---|
| `clave` | texto | No | PK | Clave natural, por ejemplo max_asientos_por_orden |
| `valor` | decimal | No |  |  |
| `unidad` | texto | No |  |  |
| `descripcion` | texto | No |  |  |

- PK: (clave)

### Seguridad

**cine.rol**: Uno de los 5 perfiles de la matriz de privilegio mínimo (RN-17).

| Columna | Tipo lógico | Nulo | Clave | Nota |
|---|---|---|---|---|
| `id_rol` | entero | No | PK |  |
| `codigo` | texto | No | UK | cliente, taquillero, operador_puerta, contador, administrador |
| `nombre` | texto | No |  |  |

- PK: (id_rol)

**cine.usuario**: Persona que usa el sistema: cliente o empleado.

| Columna | Tipo lógico | Nulo | Clave | Nota |
|---|---|---|---|---|
| `id_usuario` | entero | No | PK |  |
| `id_rol` | entero | No | FK | rol |
| `id_sede` | entero | Sí | FK | sede; solo para taquilleros y operadores de puerta |
| `email` | texto | No | UK |  |
| `contrasena_hash` | texto | No |  | Nunca la contraseña en claro |
| `nombre` | texto | No |  |  |
| `apellidos` | texto | No |  |  |
| `creado_en` | fecha_hora | No |  |  |
| `es_activo` | booleano | No |  |  |

- PK: (id_usuario)
- FK: id_rol → rol(id_rol)
- FK: id_sede → sede(id_sede)

### Venta

**cine.orden**: Compra de hasta 6 asientos para una función (RN-04, RN-08).

| Columna | Tipo lógico | Nulo | Clave | Nota |
|---|---|---|---|---|
| `id_orden` | entero | No | PK |  |
| `id_funcion` | entero | No | FK | funcion |
| `canal` | texto | No |  | en_linea o taquilla |
| `id_usuario_cliente` | entero | Sí | FK | usuario; obligatorio en línea |
| `id_usuario_vendedor` | entero | Sí | FK | usuario taquillero; obligatorio en taquilla |
| `estado` | texto | No |  | pendiente, pagada, rechazada, expirada, cancelada |
| `subtotal` | decimal(12,2) | No |  |  |
| `descuento` | decimal(12,2) | No |  |  |
| `cargo_servicio` | decimal(12,2) | No |  |  |
| `impuesto` | decimal(12,2) | No |  | Valor histórico al momento de la venta |
| `total` | decimal(12,2) | No |  |  |
| `creado_en` | fecha_hora | No |  |  |
| `pagada_en` | fecha_hora | Sí |  | Solo si estado = pagada |

- PK: (id_orden)
- FK: id_funcion → funcion(id_funcion)
- FK: id_usuario_cliente → usuario(id_usuario)
- FK: id_usuario_vendedor → usuario(id_usuario)
- CHECK: canal en (en_linea, taquilla)
- CHECK: en_linea exige cliente; taquilla exige vendedor
- CHECK: estado en (pendiente, pagada, rechazada, expirada, cancelada)
- CHECK: montos >= 0; descuento <= subtotal
- CHECK: total = subtotal - descuento + cargo_servicio + impuesto (RN-08)
- CHECK: pagada_en no nulo si y solo si estado = pagada

**cine.orden_detalle**: Línea de la orden: un asiento con su tipo de tarifa, precio y descuento.

| Columna | Tipo lógico | Nulo | Clave | Nota |
|---|---|---|---|---|
| `id_orden` | entero | No | PK, FK | orden |
| `id_asiento` | entero | No | PK, FK | asiento |
| `id_tipo_tarifa` | entero | No | FK | tipo_tarifa |
| `id_promocion` | entero | Sí | FK | promocion; nulo sin promoción |
| `precio_unitario` | decimal(12,2) | No |  | Precio de la matriz al momento de la venta |
| `descuento` | decimal(12,2) | No |  |  |

- PK: (id_orden, id_asiento)
- FK: id_orden → orden(id_orden)
- FK: id_asiento → asiento(id_asiento)
- FK: id_tipo_tarifa → tipo_tarifa(id_tipo_tarifa)
- FK: id_promocion → promocion(id_promocion)
- CHECK: precio_unitario >= 0
- CHECK: descuento entre 0 y precio_unitario

**cine.ocupacion_asiento**: Inventario de asientos por función: bloqueo temporal, reserva administrativa o venta. Su PK impide la doble venta (RN-05, RN-12).

| Columna | Tipo lógico | Nulo | Clave | Nota |
|---|---|---|---|---|
| `id_funcion` | entero | No | PK, FK | funcion |
| `id_asiento` | entero | No | PK, FK | asiento |
| `id_orden` | entero | Sí | FK | orden; nulo en reservas administrativas |
| `id_usuario` | entero | No | FK | usuario que bloquea, compra o reserva |
| `estado` | texto | No |  | bloqueado, reservado o vendido |
| `creado_en` | fecha_hora | No |  |  |
| `expira_en` | fecha_hora | Sí |  | Solo en bloqueos; inicio + 2 min |

- PK: (id_funcion, id_asiento)
- FK: id_funcion → funcion(id_funcion)
- FK: id_asiento → asiento(id_asiento)
- FK: id_orden → orden(id_orden)
- FK: id_usuario → usuario(id_usuario)
- CHECK: estado en (bloqueado, reservado, vendido)
- CHECK: expira_en no nulo si y solo si estado = bloqueado
- CHECK: estado bloqueado o vendido exige id_orden
- CHECK: regla: el asiento pertenece a la sala de la función (se valida al bloquear)

### Pago

**cine.metodo_pago**: Método o pasarela de pago, usado en la analítica de métodos preferidos.

| Columna | Tipo lógico | Nulo | Clave | Nota |
|---|---|---|---|---|
| `id_metodo_pago` | entero | No | PK |  |
| `codigo` | texto | No | UK | tarjeta_credito, tarjeta_debito, paypal, transferencia, billetera_digital |
| `nombre` | texto | No |  |  |
| `es_tarjeta` | booleano | No |  |  |

- PK: (id_metodo_pago)

**cine.pago**: Intento de pago ante la pasarela simulada y su respuesta (RN-09, RN-10).

| Columna | Tipo lógico | Nulo | Clave | Nota |
|---|---|---|---|---|
| `id_pago` | entero | No | PK |  |
| `id_orden` | entero | No | FK | orden |
| `id_metodo_pago` | entero | No | FK | metodo_pago |
| `monto` | decimal(12,2) | No |  |  |
| `estado` | texto | No |  | aprobado o rechazado |
| `token_pasarela` | texto | Sí |  | Token devuelto por la pasarela |
| `codigo_autorizacion` | texto | Sí |  | Solo si aprobado |
| `motivo_rechazo` | texto | Sí |  | Solo si rechazado |
| `ultimos4` | texto(4) | Sí |  | Solo con tarjeta: últimos 4 dígitos |
| `marca` | texto | Sí |  | Solo con tarjeta: visa, mastercard, amex, otra |
| `solicitado_en` | fecha_hora | No |  |  |
| `respondido_en` | fecha_hora | No |  |  |

- PK: (id_pago)
- FK: id_orden → orden(id_orden)
- FK: id_metodo_pago → metodo_pago(id_metodo_pago)
- UNIQUE: (id_orden) parcial donde estado = aprobado: un solo pago aprobado por orden
- CHECK: monto > 0
- CHECK: estado en (aprobado, rechazado)
- CHECK: aprobado exige codigo_autorizacion; rechazado exige motivo_rechazo
- CHECK: respondido_en >= solicitado_en
- CHECK: ultimos4 y marca: ambos nulos o ambos con valor; ultimos4 son 4 dígitos
- CHECK: no hay columnas para el número completo de tarjeta ni para el código de verificación (RN-09)

### Emisión y acceso

**cine.boleto**: Entrada emitida tras un pago aprobado, con QR único (RN-11, RN-12, RN-13).

| Columna | Tipo lógico | Nulo | Clave | Nota |
|---|---|---|---|---|
| `id_boleto` | entero | No | PK |  |
| `id_orden` | entero | No | FK | orden_detalle |
| `id_asiento` | entero | No | FK | orden_detalle |
| `id_funcion` | entero | No | FK | funcion; se copia de la orden para el UNIQUE parcial |
| `codigo_qr` | texto | No | UK | Aleatorio, no adivinable |
| `estado` | texto | No |  | vigente o anulado |
| `emitido_en` | fecha_hora | No |  |  |

- PK: (id_boleto)
- FK: (id_orden, id_asiento) → orden_detalle(id_orden, id_asiento)
- FK: id_funcion → funcion(id_funcion)
- UNIQUE: (id_orden, id_asiento): un boleto por línea
- UNIQUE: (id_funcion, id_asiento) parcial donde estado = vigente
- CHECK: estado en (vigente, anulado)
- CHECK: solo se inserta si la orden está pagada (regla de emisión, RN-11)

**cine.checkin**: Ingreso exitoso de un boleto. Su PK impide un segundo ingreso (RN-14).

| Columna | Tipo lógico | Nulo | Clave | Nota |
|---|---|---|---|---|
| `id_boleto` | entero | No | PK, FK | boleto |
| `id_puerta` | entero | No | FK | puerta |
| `id_usuario_operador` | entero | Sí | FK | usuario operador; nulo si fue un tótem automático |
| `validado_en` | fecha_hora | No |  |  |

- PK: (id_boleto)
- FK: id_boleto → boleto(id_boleto)
- FK: id_puerta → puerta(id_puerta)
- FK: id_usuario_operador → usuario(id_usuario)

**cine.reembolso**: Anulación y devolución de un boleto (RN-19); el forzado queda auditado (RN-20).

| Columna | Tipo lógico | Nulo | Clave | Nota |
|---|---|---|---|---|
| `id_reembolso` | entero | No | PK |  |
| `id_boleto` | entero | No | FK, UK | boleto |
| `id_pago` | entero | No | FK | pago aprobado que se devuelve |
| `id_usuario_autoriza` | entero | No | FK | usuario administrador |
| `tipo` | texto | No |  | politica, forzado o cancelacion_funcion |
| `monto` | decimal(12,2) | No |  |  |
| `motivo` | texto | No |  |  |
| `creado_en` | fecha_hora | No |  |  |

- PK: (id_reembolso)
- FK: id_boleto → boleto(id_boleto)
- FK: id_pago → pago(id_pago)
- FK: id_usuario_autoriza → usuario(id_usuario)
- CHECK: tipo en (politica, forzado, cancelacion_funcion)
- CHECK: monto > 0

### Bitácoras

**bitacora.transaccion_log**: Intentos de pago, respuestas de la pasarela, montos, impuestos y emisión de boletos. Append-only; particionada por mes sobre ocurrido_en; sin FK hacia tablas vivas.

| Columna | Tipo lógico | Nulo | Clave | Nota |
|---|---|---|---|---|
| `id` | entero | No | PK |  |
| `ocurrido_en` | fecha_hora | No | PK | Clave de partición |
| `id_orden` | entero | No |  |  |
| `id_pago` | entero | Sí |  |  |
| `id_boleto` | entero | Sí |  |  |
| `evento` | texto | No |  | orden_creada, pago_solicitado, pago_aprobado, pago_rechazado, boletos_emitidos, reembolso |
| `monto` | decimal(12,2) | Sí |  |  |
| `impuesto` | decimal(12,2) | Sí |  |  |
| `detalle` | json | Sí |  | Respuesta de la pasarela |

- PK: (id, ocurrido_en)

**bitacora.asiento_auditoria_log**: Bloqueos, liberaciones, compras y colisiones de asientos. Append-only; particionada por mes sobre ocurrido_en; sin FK hacia tablas vivas.

| Columna | Tipo lógico | Nulo | Clave | Nota |
|---|---|---|---|---|
| `id` | entero | No | PK |  |
| `ocurrido_en` | fecha_hora | No | PK | Clave de partición |
| `id_funcion` | entero | No |  |  |
| `id_asiento` | entero | No |  |  |
| `id_orden` | entero | Sí |  |  |
| `id_usuario` | entero | Sí |  |  |
| `evento` | texto | No |  | bloqueo, liberacion_expiracion, liberacion_rechazo, liberacion_usuario, liberacion_reembolso, compra, reserva, colision |
| `detalle` | json | Sí |  |  |

- PK: (id, ocurrido_en)

**bitacora.acceso_puerta_log**: Cada escaneo de QR en puerta con su resultado (RN-14, RN-15, RN-16). Append-only; particionada por mes sobre ocurrido_en; sin FK hacia tablas vivas.

| Columna | Tipo lógico | Nulo | Clave | Nota |
|---|---|---|---|---|
| `id` | entero | No | PK |  |
| `ocurrido_en` | fecha_hora | No | PK | Clave de partición |
| `codigo_qr_leido` | texto | No |  |  |
| `id_boleto` | entero | Sí |  | Nulo si el código no existe |
| `id_puerta` | entero | No |  | Puerta o dispositivo |
| `id_funcion_en_curso` | entero | Sí |  |  |
| `id_usuario_operador` | entero | Sí |  |  |
| `resultado` | texto | No |  | exitoso, duplicado, otra_funcion, fuera_de_horario, inexistente, anulado, incidencia_documento |
| `mensaje` | texto | No |  | Texto mostrado, por ejemplo Entrada ya utilizada |

- PK: (id, ocurrido_en)

**bitacora.admin_operacion_audit**: Operaciones manuales y cambios críticos de usuarios con privilegios (RN-20). Append-only; particionada por mes sobre ocurrido_en; sin FK hacia tablas vivas.

| Columna | Tipo lógico | Nulo | Clave | Nota |
|---|---|---|---|---|
| `id` | entero | No | PK |  |
| `ocurrido_en` | fecha_hora | No | PK | Fecha y hora; clave de partición |
| `id_usuario` | entero | No |  | Responsable |
| `id_rol` | entero | No |  | Rol del responsable al momento de la operación |
| `ip` | ip | No |  |  |
| `operacion` | texto | No |  | cortesia, cambio_asiento, reembolso_forzado, cambio_precio, cambio_sala, cambio_rol, ... |
| `entidad` | texto | No |  | Tabla afectada |
| `id_entidad` | texto | No |  | Clave de la fila afectada |
| `valores_anteriores` | json | Sí |  |  |
| `valores_nuevos` | json | Sí |  |  |
| `motivo` | texto | Sí |  |  |

- PK: (id, ocurrido_en)
