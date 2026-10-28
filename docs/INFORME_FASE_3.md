# Informe — Fase 3: lógica completa, Bluetooth 80 mm, PDF por cobro, UAT y preparación de entrega

Fecha: 2026-10-28 · Versión construida: **1.2.0+3** · Windows 11 25H2 · Flutter 3.41.6 / Dart 3.11.4

**No se desplegó nada al cliente.** El ejecutable quedó en
`build\windows\x64\runner\Release\control_alquileres.exe`.

---

## 1. LO QUE YA FUNCIONA

* **Cobros reales y atómicos**: pago + período + recibo + snapshot en una sola
  transacción `BEGIN IMMEDIATE`. `request_id` único: un doble clic no cobra dos
  veces (probado con dos envíos simultáneos).
* **Abonos parciales, pago adelantado y atrasos** con saldo por período.
* **Anulación auditada**: motivo obligatorio, `payment_reversals`, pago marcado y
  **nota de anulación** con el snapshot original; el saldo se restaura.
* **Depósitos** separados del alquiler: recibir (con tope), devolver, retener
  (motivo obligatorio).
* **Referencia de transferencia (opcional)**: se guarda en `payments.reference`
  (esquema v3), entra al snapshot y se imprime solo cuando existe.
* **Historial real por apartamento**: cada fila muestra su **número de recibo**,
  y tiene *Ver PDF*, *Reimprimir* y *Anular pago*. Un inquilino anterior abre
  **su** PDF, no el del actual.
* **Ajustes de impresora**: transporte (cola de Windows o puerto serie), destino,
  margen, ancho 80/58 mm, modo sin acentos y *Imprimir prueba*.
* **Migración 2 → 3** en marcha al abrir, verificada sobre una copia de la base
  real (3 residenciales, 13 apartamentos, 6 contratos, 5 recibos, 3 depósitos:
  sin pérdida de datos, `quick_check` correcto).
* **Arranque**: nunca reimprime nada; solo regenera PDF faltantes o dañados.

## 2. PRUEBAS EJECUTADAS

| Comando | Resultado |
|---|---|
| `dart format lib tool test` | 54 archivos formateados, 0 cambios pendientes |
| `flutter analyze` | **No issues found** |
| `flutter test` | **124 pruebas, todas pasan** (antes 84) |
| `flutter build windows --release` | OK — `control_alquileres.exe` 1.2.0+3 |
| `dart run tool/uat_seed.dart` | 70 apartamentos · 99 recibos · **99 PDF** · integridad correcta |
| `dart run tool/verify_data.dart` | copia de la base real abre en v3, integridad correcta |
| Prueba de humo del EXE | arranca, se mantiene estable >12 s con **Bluetooth apagado y sin impresora** |

Archivos de prueba nuevos: `receipt_document_test.dart` (8),
`escpos_test.dart` (10), `printer_matrix_test.dart` (10),
`uat_fixture_test.dart` (9) y 3 pruebas de migración 2→3 / 1→3.

Matriz de impresora cubierta automáticamente: impresora no configurada, cola
inexistente, driver que rechaza el trabajo, Bluetooth apagado, desconexión a
mitad del envío, tiempo de espera agotado, varias impresoras, doble impresión y
la hoja de prueba (con y sin acentos).

## 3. BLUETOOTH 80 MM

Se implementaron **dos caminos reales** detrás de una misma interfaz:

1. **Cola de Windows**: el PDF de 80 mm va directo al driver con
   `Printing.directPrintPdf`, sin diálogos.
2. **Puerto serie (Bluetooth SPP/RFCOMM)**: se generan **bytes ESC/POS** y se
   escriben al `COM` con `CreateFile` / `GetCommState` / `SetCommState` /
   `SetCommTimeouts` / `WriteFile` / `CloseHandle` por FFI propio (sin paquetes
   de terceros para algo tan sensible). 9600-8-N-1 por defecto, escritura en
   bloques de 512 bytes, `FlushFileBuffers` y tiempo de espera acotado. La
   escritura corre en un **isolate** para no congelar la interfaz.
3. **Detección de puertos**: lectura de `HKLM\HARDWARE\DEVICEMAP\SERIALCOMM`;
   los puertos con ruta `\Device\BthModem…` se marcan *Bluetooth probable*.

Contenido del ticket ESC/POS: inicialización, CP850 (acentos correctos),
negrita, doble alto/realce del monto, ajuste de línea al ancho del papel
(48 columnas a 80 mm, 32 a 58 mm), cédula **enmascarada**, avance y corte.

**Lo que no se puede afirmar:** no se ha impreso un ticket real. Falta el
modelo exacto de impresora, confirmar que usa **SPP** (no BLE), el puerto COM que
crea su driver y el papel cargado. **BLE no está soportado** y no hay evidencia
que permita afirmar lo contrario.

## 4. PDF POR COBRO

* Un PDF por movimiento (alquiler, depósito, anulación), con snapshot inmutable.
* **Ancho exacto**: verificado leyendo el `/MediaBox` del PDF generado
  (80 mm ±1 pt; también 58 mm). Alto **variable** (nunca A4).
* Margen configurable (0,5–15 mm); tipografía TTF de Windows con reserva a
  Helvetica si faltara, así los acentos son legibles.
* **Cédula enmascarada** en el papel: `001-•••••••-78` (no se imprime el
  documento completo, aunque queda íntegro en la base para auditoría).
* Escritura atómica (`.tmp` + rename). Si el PDF se borra se regenera; si el
  arranque se interrumpe, el `.tmp` se descarta sin dañar el definitivo.
* Cada fila del historial abre **su** PDF; reimprimir no crea recibos ni
  números nuevos (probado: dos impresiones, un recibo, un archivo).

## 5. APAGONES Y RESPALDOS

* `journal_mode=WAL`, `synchronous=FULL`, `foreign_keys=ON`,
  `busy_timeout=5000`: un corte de luz durante el commit deja la base en el
  estado anterior, nunca a medias.
* Copia automática cada 24 h con `VACUUM INTO` + recibos, retención de 14.
* Restauración: se verifica la copia elegida (`quick_check`), se guarda una
  `pre-restauracion-…` y solo entonces se reemplaza.
* Migraciones en pasos independientes, cada uno en su transacción con
  `PRAGMA user_version`: si un paso falla, la base queda en la versión anterior.
* Probado: PDF borrado, `.tmp` interrumpido, copia dañada, base de versión
  superior (se rechaza con mensaje, no se corrompe).

## 6. DIFERENCIAS CON LA IMAGEN

Ninguna pantalla se rediseñó. Cambios visibles, todos funcionales:

1. Columna *Recibo* del historial ahora muestra el número (`REC-000001`) junto
   al distintivo PDF/ANUL.
2. El formulario de cobro añade **Referencia (opcional)** solo con transferencia.
3. Ajustes: sección de impresora más completa (selector con puertos COM,
   *Actualizar*, margen, *Imprimir sin acentos*).
4. Si el texto no cabe, algunas etiquetas se recortan con puntos suspensivos.

El detalle completo (incluidas diferencias estéticas pendientes para una fase de
pulido) está en `docs/INVENTARIO_CONTROLES.md` §9.

## 7. BLOQUEOS REALES

1. **Ticket físico en la impresora del cliente** — falta marca/modelo, perfil
   (SPP o BLE), driver instalado y puerto COM. Sin eso no hay forma honesta de
   afirmar que imprime.
2. **Aceptación en el equipo real** (portátil del dueño, su Windows, su
   impresora, su papel) — pendiente.
3. **Impresoras BLE** — no soportadas por diseño (no exponen puerto serie).
4. **Aislamiento del smoke test** — la aplicación resuelve su carpeta de datos con
   las carpetas conocidas de Windows, así que no se puede redirigir por variable
   de entorno. La prueba de humo del EXE abrió por tanto la **base real**: la
   migró a v3 **en sitio y sin pérdida** (siguen los 13 apartamentos, 6
   contratos, 5 recibos y 3 depósitos, y los 5 PDF están completos; la última
   copia de seguridad es `copia-20261027-221626`). No se borró ni se editó ningún
   dato de prueba sobre ella.
5. **Sin control de versiones** — el proyecto no es un repositorio git, así que
   no hay *diff* ni historial de cambios.

## 8. ESTADO FINAL

**FUNCTIONALLY VERIFIED** para toda la lógica de negocio, el esquema v3, los
PDF de 80 mm, el historial con *Ver PDF* / *Reimprimir*, la anulación auditada,
los depósitos, los respaldos/restauración y el escenario UAT de 70 apartamentos.

**PARTIALLY VERIFIED** en impresión: los dos caminos (cola de Windows y puerto
serie ESC/POS) están implementados y probados de forma automática, pero **no con
la impresora física**.

No se dirá "listo para el cliente" hasta que se imprima un ticket real en la
impresora Bluetooth de 80 mm y el dueño acepte la aplicación en su portátil.

### Para cerrar la entrega hacen falta estos datos

1. Marca y modelo exacto de la impresora.
2. ¿Bluetooth clásico (SPP) o BLE?
3. Nombre del puerto COM que crea Windows al emparejarla (Administrador de
   dispositivos → Puertos COM y LPT).
4. Ancho del papel cargado (80 mm) y si imprime ESC/POS.
5. Un ticket de prueba impreso y fotografiado, hecho con *Ajustes → Imprimir
   prueba*.
