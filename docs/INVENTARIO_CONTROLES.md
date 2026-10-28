# Inventario de controles — Control de Alquileres (Fase 3C · 2C-P80-C)

Revisión completa de **cada pantalla y cada botón** con su estado real tras las
pruebas de esta fase. Leyenda:

* **FUNCIONA** — verificado con pruebas automatizadas o ejecución real.
* **PARCIAL** — funciona, pero depende de un paso manual o de terceros.
* **BLOQUEADO** — no se puede verificar sin hardware/acceso que hoy no existe.

Todo lo financiero se prueba contra SQLite real; nada simula dinero.

---

## 1. Ventana principal (barra superior y lateral)

| Control | Estado | Nota |
|---|---|---|
| Barra lateral: Inicio / Apartamentos / Cobros | FUNCIONA | Prueba de widget en 6 tamaños; solo 3 iconos, con tooltip al pasar el mouse |
| Engranaje de Ajustes (único icono a la derecha) | FUNCIONA | Abre el diálogo de configuración |
| Arrastrar la ventana / maximizar | FUNCIONA | Ventana sin marco propio; mínimo 960×540 |
| Avisos emergentes | FUNCIONA | Máximo 3, se deduplican, se cierran solos a los 5 s |
| Barra de búsqueda | FUNCIONA | Filtra por número, residencial o inquilino |

## 2. Inicio

| Control | Estado | Nota |
|---|---|---|
| Tarjeta de resumen (cobrado del mes, pendientes) | FUNCIONA | Cifras de la base, no decorativas |
| Lista de apartamentos con estado | FUNCIONA | Estado calculado con renta y pagos reales |
| Filtro por residencial | FUNCIONA | Incluye "Todos" |
| Menú `⋯` del residencial (renombrar/eliminar) | FUNCIONA | Eliminar exige que no queden apartamentos |
| Botón **Cobrar** por fila | FUNCIONA | Abre el formulario con el apartamento elegido |
| Seleccionar apartamento (detalle) | FUNCIONA | Muestra información, pagos mes a mes y depósito |
| Pestaña **Información** | FUNCIONA | Inquilino, contrato, condiciones |
| Pestaña **Pagos** (mes a mes) | FUNCIONA | Períodos del contrato con estado y saldo |
| Pestaña **Depósito** | FUNCIONA | Recibido / devuelto / retenido con historial |
| Botón **Cobrar** en el detalle | FUNCIONA | Abre el formulario de cobro |
| **Condiciones** (renta, día de pago, depósito, notas) | FUNCIONA | No altera meses ya emitidos |
| **Finalizar contrato** | FUNCIONA | Avisa de renta pendiente y depósito sin liquidar; conserva historial |
| Registrar inquilino y contrato (apartamento libre) | FUNCIONA | Depósito pactado opcional |

## 3. Formulario de cobro

| Control | Estado | Nota |
|---|---|---|
| Concepto | FUNCIONA | Fijo "Alquiler mensual" |
| Período `‹ ›` | FUNCIONA | Incluye meses futuros (adelanto) y el atraso más antiguo |
| Monto a pagar | FUNCIONA | Rechaza 0, negativo y montos mayores al saldo |
| Método de pago | FUNCIONA | Efectivo / Transferencia |
| **Referencia (opcional)** | FUNCIONA | Solo aparece con transferencia; se guarda y se imprime |
| Fecha de pago | FUNCIONA | Calendario en español |
| Observación | FUNCIONA | Se imprime como "Obs." |
| Resumen Vence / Debe / Recibido / Restará | FUNCIONA | Calculado en vivo |
| **Guardar (sin imprimir)** | FUNCIONA | Atómico, idempotente |
| **Guardar e imprimir recibo** | PARCIAL | Guarda siempre; la impresión depende de la impresora (ver §7) |
| Doble clic rápido en Guardar | FUNCIONA | Un solo cobro (probado con dos envíos simultáneos) |

## 4. Historial de pagos

| Control | Estado | Nota |
|---|---|---|
| Número de recibo visible por fila | FUNCIONA | `REC-000001` junto al distintivo PDF/ANUL |
| Distintivo PDF (clic) | FUNCIONA | Abre el PDF de **esa** fila (también de inquilinos anteriores) |
| Icono de impresora | FUNCIONA | Reimprime el mismo recibo |
| Menú `⋯` → **Ver PDF** | FUNCIONA | Abre el PDF con el visor del sistema |
| Menú `⋯` → **Reimprimir** | PARCIAL | Requiere impresora disponible |
| Menú `⋯` → **Anular pago** | FUNCIONA | Exige motivo; emite nota de anulación; restaura el saldo |
| Filtro por contrato (inquilino anterior/actual) | FUNCIONA | Aparece cuando hay más de un contrato |
| Total cobrado | FUNCIONA | Suma real excluyendo anulados |

## 5. Depósitos

| Control | Estado | Nota |
|---|---|---|
| Recibir depósito | FUNCIONA | Tope = depósito pactado; no cuenta como renta |
| Devolver depósito | FUNCIONA | Tope = saldo retenido |
| Retener depósito | FUNCIONA | Motivo obligatorio |
| PDF + impresión por movimiento | PARCIAL | PDF siempre; impresión según impresora |

## 6. Apartamentos y Cobros (páginas)

| Control | Estado | Nota |
|---|---|---|
| Listado completo con filtros | FUNCIONA | Agrupado por residencial |
| Nuevo residencial / nuevo apartamento | FUNCIONA | Valida número duplicado por residencial |
| Editar apartamento | FUNCIONA | Impide marcar "disponible" con contrato activo |
| Página Cobros: pendientes por apartamento | FUNCIONA | Ordenado por atraso |
| Botón Cobrar desde esa página | FUNCIONA | Mismo formulario real |

## 7. Ajustes e impresora (2C-P80-C)

| Control | Estado | Nota |
|---|---|---|
| Datos del negocio (nombre, RNC/cédula, dirección, teléfono) | FUNCIONA | Se imprimen en cada recibo |
| Prefijo del recibo | FUNCIONA | Cambia la serie de los recibos nuevos |
| Ancho del papel 80 / 58 mm | FUNCIONA | El PDF sale exactamente de ese ancho (verificado en el MediaBox) |
| **Conexión: Automático / Windows / Bluetooth (COM)** | FUNCIONA | Automático usa un único puerto Bluetooth; nunca elige al azar entre varios |
| **Selector de impresora** (colas + puertos COM) | FUNCIONA | Nombres de Windows; los puertos *entrantes* se marcan como no utilizables |
| **Actualizar** | FUNCIONA | Vuelve a consultar spooler, registro y nombres amigables |
| **Probar** (ticket de calibración) | PARCIAL | Genera el ticket real (PDF o ESC/POS); **no verificado en hardware** |
| Línea de estado ("Impresora lista: COM5") | FUNCIONA | Mensajes en español, sin trazas |
| Avanzado → **ancho útil calibrado (puntos)** | FUNCIONA | 0 = automático (576 en 80 mm). Persistido y validado |
| Avanzado → margen de contenido (puntos) | FUNCIONA | Reduce las columnas del ticket |
| Avanzado → velocidad (baudios) | FUNCIONA | 9600/19200/38400/115200 |
| Avanzado → imprimir sin acentos | FUNCIONA | Translitera a ASCII |
| Crear copia ahora / Restaurar / Exportar / Purgar demo | FUNCIONA | Sin cambios respecto a la Fase 3 |

### Impresión térmica — estado real

| Caso | Estado |
|---|---|
| Cola de Windows con driver del fabricante | PARCIAL: implementado y probado con mock; **no probado con hardware** |
| Puerto serie Bluetooth SPP con ESC/POS | PARCIAL: implementado (FFI) y probado con transporte falso; **no probado con hardware** |
| Ancho de papel 80 mm / ancho imprimible distinto | FUNCIONA: perfil con 576 puntos conservadores y calibración manual |
| Ticket demasiado ancho (texto cortado) | FUNCIONA: el margen se amplía solo; `Avanzado` permite reducirlo más |
| Envío de corte (`GS V`) a impresora sin cortador | FUNCIONA: **no se envía nunca** (corte manual por defecto) |
| Cédula en el papel | FUNCIONA: enmascarada con `X` (seguro en CP850) |
| Bluetooth LE (BLE) | BLOQUEADO: no soportado (sin perfil serie) |
| Bluetooth apagado / puerto inexistente | FUNCIONA (probado): mensaje claro, cobro intacto |
| Desconexión a mitad del trabajo | FUNCIONA (probado): informa trabajo incompleto y sugiere reimprimir |
| Tiempo de espera agotado | FUNCIONA (probado) |
| Spooler que rechaza el trabajo | FUNCIONA (probado) |
| Varias impresoras / varios puertos | FUNCIONA (probado): exige elegir, no adivina |
| Doble impresión del mismo recibo | FUNCIONA (probado): dos trabajos idénticos, un solo recibo y un solo PDF |
| Ticket impreso de verdad (2C-P80-C) | BLOQUEADO: no hay impresora conectada al equipo de desarrollo |
## 8. Respaldos y arranque

| Caso | Estado |
|---|---|
| Copia automática cada 24 h | FUNCIONA |
| Apagón durante un cobro | FUNCIONA (diseño): transacción `BEGIN IMMEDIATE` + WAL/FULL |
| PDF a medio escribir (`.tmp`) | FUNCIONA (probado): se descarta y se regenera |
| PDF borrado a mano | FUNCIONA (probado): se regenera desde el snapshot |
| Recibo sin PDF al arrancar | FUNCIONA: se regenera; **nunca** se reimprime solo |
| Migración 1→2, 2→3 y 1→3 | FUNCIONA (probado sobre bases pobladas) |
| Restauración fallida (archivo dañado) | FUNCIONA (probado): se aborta antes de tocar la base |
| Base de una versión más nueva | FUNCIONA: se rechaza con mensaje claro en vez de corromper |

## 9. Diferencias visuales con la captura aprobada (para una fase de pulido)

Ninguna es un error; se listan para decidir después:

1. El histórico muestra **número de recibo** en la columna "Recibo" (la captura
   solo tenía un icono).
2. El formulario de cobro crece una fila cuando el método es transferencia
   (campo Referencia).
3. Ajustes tiene la sección de impresora más densa (selector, margen, casilla
   de acentos, botón Actualizar).
4. El botón "Guardar e imprimir recibo" se acorta con puntos suspensivos en
   ventanas muy estrechas (evita desbordes).
5. En ventanas bajas la pantalla de Inicio pasa a una sola columna con la lista
   acotada, en lugar de comprimir los paneles.
