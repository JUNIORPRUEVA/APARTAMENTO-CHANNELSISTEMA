# Inventario de controles — Control de Alquileres (Fase 3)

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

## 7. Ajustes e impresora

| Control | Estado | Nota |
|---|---|---|
| Datos del negocio (nombre, RNC/cédula, dirección, teléfono) | FUNCIONA | Se imprimen en cada recibo |
| Prefijo del recibo | FUNCIONA | Cambia la serie de los recibos nuevos |
| Ancho del papel 80 / 58 mm | FUNCIONA | El PDF sale exactamente de ese ancho (verificado en el MediaBox) |
| **Margen a cada lado (mm)** | FUNCIONA | 0,5 a 15 mm |
| **Selector de impresora** (colas de Windows + puertos COM) | FUNCIONA | Detecta `COM` leyendo el registro; marca "Bluetooth probable" |
| **Actualizar** lista | FUNCIONA | Vuelve a consultar spooler y puertos |
| **Imprimir prueba** | PARCIAL | Windows: hoja PDF; puerto serie: ticket ESC/POS de prueba |
| **Imprimir sin acentos** | FUNCIONA | Translitera a ASCII (para impresoras que ignoran CP850) |
| Crear copia ahora | FUNCIONA | `VACUUM INTO` + recibos, retención de 14 |
| Restaurar copia | FUNCIONA | Verifica el archivo y guarda copia previa a restaurar |
| Exportar a USB | FUNCIONA | Copia la última copia a la carpeta indicada |
| Eliminar datos de demostración | FUNCIONA | Se niega si el demo tiene cobros o depósitos |

### Impresión térmica — estado real

| Caso | Estado |
|---|---|
| Cola de Windows con controlador del fabricante | PARCIAL: implementado, probado con mock; **no probado con hardware** |
| Puerto serie Bluetooth SPP con ESC/POS | PARCIAL: implementado (CreateFile/SetCommState/WriteFile por FFI), probado con transporte falso; **no probado con hardware** |
| Bluetooth LE (BLE) | BLOQUEADO: no soportado (sin perfil serie) |
| Bluetooth apagado / puerto inexistente | FUNCIONA (probado): mensaje claro, cobro intacto |
| Desconexión a mitad del trabajo | FUNCIONA (probado): informa trabajo incompleto y sugiere reimprimir |
| Tiempo de espera agotado | FUNCIONA (probado) |
| Spooler que rechaza el trabajo | FUNCIONA (probado) |
| Varias impresoras instaladas | FUNCIONA (probado): se elige una y se usa esa |
| Doble impresión del mismo recibo | FUNCIONA (probado): dos trabajos idénticos, un solo recibo y un solo PDF |
| Ticket impreso de verdad | BLOQUEADO: falta la impresora |

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
