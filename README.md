# Control de Alquileres (Windows · Flutter)

Aplicación de escritorio **sin conexión** para administrar el alquiler de
apartamentos (≈70 unidades agrupadas en residenciales como Anamelia, Villa
Cerro y Anamulla). Abre directamente, sin inicio de sesión.

> **Estado: Fase 3.** Cobros, anulación auditada, depósitos, recibos PDF de
> 80 mm, reimpresión desde el historial, copia de seguridad y restauración
> funcionan de verdad sobre SQLite local. La impresión térmica tiene ahora **dos
> caminos reales** (cola de Windows y puerto serie Bluetooth con ESC/POS), pero
> **ninguno se ha probado con la impresora física del cliente**: eso requiere el
> modelo exacto, el emparejamiento y un ticket impreso delante del dueño.

---

## Requisitos

| Elemento | Versión verificada |
|---|---|
| Windows | 10/11 (probado en Windows 11 25H2) |
| Flutter | 3.41.6 (stable) · Dart 3.11.4 |
| Visual Studio | Build Tools 2022 con "Desktop development with C++" |

```powershell
flutter pub get
flutter run -d windows
flutter test                    # 124 pruebas
flutter analyze                 # sin avisos
flutter build windows --release # build\windows\x64\runner\Release\
```

## Dónde viven los datos

```
%APPDATA%\do.channelsistema\Control de Alquileres\datos\
├── control_alquileres.sqlite      base (WAL + synchronous=FULL)
├── recibos\REC-00000001.pdf…      un PDF por movimiento
└── copias\copia-AAAAMMDD-HHMMSS\  copia consistente (base + recibos)
```

* Nunca dentro de `build\` ni junto al ejecutable.
* Copia automática al arrancar si pasaron más de 24 h, hecha con `VACUUM INTO`
  (consistente aunque la base esté en WAL) y conservando las últimas 14.
* **Restaurar**: Ajustes → *Restaurar copia*. Antes de tocar nada se guarda una
  copia `pre-restauracion-…`, se verifica con `quick_check` el archivo elegido y
  se cierra la base; luego hay que reabrir la aplicación.
* **Exportar** a USB: Ajustes → *Carpeta para exportar* + *Exportar*.

---

## Flujo diario

1. **Cobrar**: elegir apartamento → *Cobrar* (o la fila de la tabla).
2. El formulario muestra **concepto, período, vencimiento, monto que debe,
   monto recibido y lo que restará**. El período se mueve con `‹ ›` (incluye
   meses futuros para pago adelantado; el atraso más antiguo se propone
   primero).
3. **Guardar (sin imprimir)** o **Guardar e imprimir recibo**.
4. El histórico del apartamento permite **abrir el PDF**, **reimprimir** o
   **anular** con motivo (queda nota de anulación y se restaura el saldo).
5. **Depósito** (pestaña Depósito): recibir, devolver o retener con documento
   propio. Nunca se mezcla con el alquiler.
6. **Finalizar contrato**: avisa si queda renta pendiente o depósito sin
   liquidar; el historial y los recibos se conservan.

## Reglas financieras implementadas

* Montos en **centavos enteros**; nunca coma flotante.
* Un pago = una transacción (`BEGIN IMMEDIATE`) con pago + período + recibo y
  su snapshot. Si falla, no hay pago.
* `request_id` (UUID) único e idempotente: repetir la operación devuelve el
  mismo recibo; no se duplica dinero.
* Número de recibo **correlativo y único por serie** (prefijo en Ajustes).
* El período se cobra completo por defecto: **sin prorrateos ni recargos
  automáticos**. Se rechaza cobrar más que el saldo del período.
* La renta de cada período se congela al emitirlo: un cambio de renta no altera
  meses ni recibos anteriores.
* Anulación: nunca se borra nada; se registra `payment_reversals`, se marca el
  pago con fecha/motivo y se emite una **nota de anulación**.
* El PDF es un documento de control interno: **no** es comprobante fiscal
  (no se inventan NCF).

## Recibos y recuperación

* Plantilla de 80 mm (configurable a 58 mm), negro sobre blanco, con emisor,
  inquilino, residencial, apartamento, concepto, período, monto, método, fecha,
  saldo y "Conserve este recibo".
* Se escribe en un archivo temporal y se **renombra** (reemplazo atómico).
* Cada recibo guarda un **snapshot JSON** inmutable: si el PDF se pierde o el
  programa se cierra antes de escribirlo, se **regenera al arrancar** desde ese
  snapshot, sin volver a cobrar. Reimprimir no crea pagos ni números nuevos.

## Impresora

Se admiten **dos transportes**, elegidos en Ajustes → *Impresora*:

1. **Cola de impresión de Windows** — la impresora está instalada en el sistema.
   Se envía el PDF de 80 mm al driver con `Printing.directPrintPdf` (sin
   diálogos). Es el camino recomendado si el fabricante instala driver propio.
2. **Puerto serie (Bluetooth SPP/RFCOMM)** — la impresora está emparejada y
   Windows le creó un puerto `COM`. Se envía **ESC/POS nativo** (texto CP850,
   negrita, doble alto, avance y corte) por ese puerto, sin driver intermedio.
   Los puertos se listan leyendo `HKLM\HARDWARE\DEVICEMAP\SERIALCOMM`, así que
   aparecen los `COM` que existan en el equipo, con la marca *Bluetooth
   probable* cuando la ruta del dispositivo es `\Device\BthModem…`.

Con la configuración vacía se abre el diálogo de impresión de Windows: es la
única vez que aparece una ventana.

* *Imprimir sin acentos*: translitera á é í ó ú ñ a ASCII para impresoras que
  ignoran la orden de página de códigos CP850 (síntoma típico: símbolos raros).
* *Margen a cada lado*: configurable de 0,5 a 15 mm; el ancho de papel sigue
  siendo 80 mm (o 58 mm) exactos.
* Al imprimir el orden es **commit → PDF → trabajo de impresión**. Si la
  impresora falla, el cobro y el recibo quedan guardados y el aviso dice
  "El cobro está guardado y puede reimprimirse desde el historial".
* Los mensajes dicen **"Enviado a la impresora"**, nunca "Impreso": el sistema
  no puede saber si el papel salió.
* Nunca se reimprime solo al arrancar; el arranque solo **regenera PDF**
  faltantes.

**Límites reales (no maquillados):**

* Bluetooth **LE (BLE)** no está soportado: esas impresoras no exponen puerto
  serie ni aceptan ESC/POS por GATT, y no hay evidencia de lo contrario.
* No se garantiza ningún modelo concreto: depende del perfil (SPP) y de que el
  driver cree el puerto COM.
* La prueba física en el equipo del cliente sigue **pendiente**.

## Estructura

```
lib/
├── main.dart, app.dart
├── src/core/        formato RD$/fechas, validaciones, avisos, errores
├── src/data/        esquema + migraciones, modelos, repositorios
│   ├── schema.dart              v1, v2 y migraciones 1→2 y 2→3
│   ├── app_database.dart        PRAGMAs, transacciones, quick_check
│   ├── portfolio_repository.dart  residenciales, apartamentos, contratos
│   ├── finance_repository.dart   pagos, anulaciones, depósitos, recibos
│   └── finance_models.dart       períodos y cálculo de estado (puro)
├── src/services/
│   ├── receipt_document_service.dart  PDF de 80 mm (snapshot inmutable)
│   ├── escpos.dart                    bytes ESC/POS (CP850, corte)
│   ├── serial_transport.dart          Win32 CreateFile/WriteFile por FFI
│   ├── print_service.dart             cola Windows + puerto serie
│   ├── backup_service.dart            copias, restauración, exportación
│   └── startup_service.dart           verificación al arrancar
├── src/dev/uat_fixture.dart   escenario de ~70 apartamentos (solo pruebas)
└── src/ui/          shell (barra lateral de 3 iconos), páginas y diálogos

comandos de consola (sin tocar los datos reales):
tool/phase2_flow.dart   recorrido completo sobre una copia de la base
tool/uat_seed.dart      siembra un escenario UAT aislado en %TEMP%
tool/verify_data.dart   abre una COPIA de la base y reporta versión/integridad
docs/INVENTARIO_CONTROLES.md  qué funciona y qué no, pantalla por pantalla
docs/GUIA_RAPIDA.md           guía de una página para la dueña
```

### Decisiones técnicas

* **SQLite con el paquete `sqlite3` (assets nativos).** Drift no es viable con
  Flutter 3.41.6: `drift_flutter → sqlite3 ≥3 → drift ≥2.32 → drift_dev ≥2.32 →
  analyzer ≥10 → meta ≥1.18`, y el SDK fija `meta 1.17.0`.
* `dependency_overrides: image: 4.5.4` porque `pdf 3.12` exige `archive <4.1` y
  `image 4.11` no compila contra él.
* Un índice único **parcial** garantiza un contrato activo por apartamento sin
  perder el historial.
* Ventana sin marco propio, mínimo 960×540 (1366×768 al 125 % deja ~1093×578).

### Comportamiento por tamaño

| Condición | Diseño |
|---|---|
| ancho ≥ 1180 y alto de contenido ≥ 780 | Dos filas como la referencia |
| resto | Columna única desplazable; la lista tiene su propia zona con scroll |

Probado sin desbordes en 1536×1024, 1366×768, 1280×720, 1093×578, 1024×576 y
960×540.

---

## Pruebas (124)

| Archivo | Cubre |
|---|---|
| `database_schema_test.dart` | esquema, claves foráneas, unicidad, contrato único, rollback, WAL/FULL |
| `finance_repository_test.dart` | períodos (fin de mes, bisiesto), parciales, adelantos, topes, idempotencia, historial entre contratos, depósitos, anulación, PDF/reparación, impresión, recibo de 80 mm |
| `migration_backup_test.dart` | migraciones 1→2, 2→3 y 1→3 sobre bases pobladas, idempotencia, copia consistente y restauración, retención de 14 |
| `format_validators_test.dart` | dinero, fechas, vencimientos, validaciones y enmascarado de cédula |
| `layout_widget_test.dart` | 6 tamaños sin desbordes, navegación, monto inválido |
| `payment_flow_test.dart` | cobro desde la UI con PDF real, doble clic simultáneo, impresión OK y con fallo, depósito |
| `receipt_document_test.dart` | PDF de 80 mm exactos (MediaBox), 58 mm, margen, no reescritura, PDF borrado, `.tmp` interrumpido |
| `escpos_test.dart` | bytes ESC/POS, CP850 sin mojibake, modo sin acentos, cédula enmascarada, ancho de línea, puertos COM del registro |
| `printer_matrix_test.dart` | impresora ausente, driver que rechaza, Bluetooth apagado, desconexión a medias, timeout, doble impresión |
| `uat_fixture_test.dart` | escenario de 70 apartamentos: estados, saldos, anulación, depósitos, 99 PDF, integridad |

`dart run tool/phase2_flow.dart <carpetaDatos> <carpetaTrabajo>` ejecuta el ciclo
completo (cobro → PDF → idempotencia → anulación → depósitos) sobre una **copia**
de la base real.

---

## Diferencias conscientes con la captura aprobada

Ninguna pantalla se rediseñó en la Fase 3. Los únicos cambios visibles son
funcionales y se listan en `docs/INVENTARIO_CONTROLES.md`:

1. La columna **Estado** muestra el estado real (`Al día`, `Parcial`,
   `Pendiente`, `Vencido`, `Disponible`) calculado con pagos y vencimientos.
2. Se añadieron **Condiciones** (editar renta/día/depósito) y el menú `⋯` de
   residenciales, necesarios para operar.
3. El historial es real e incluye el **número de recibo visible** en cada fila,
   *Ver PDF*, *Reimprimir* y *Anular pago*.
4. El formulario de cobro muestra **Referencia (opcional)** cuando el método es
   transferencia.
5. Ajustes incorpora transporte de impresora, margen y *Imprimir sin acentos*.
6. En ventanas de poca altura la pantalla pasa a una columna legible en vez de
   comprimir los paneles.

La lista de diferencias estéticas pendientes (para una fase de pulido) está al
final de `docs/INVENTARIO_CONTROLES.md`.
