# Control de Alquileres (Windows · Flutter)

Aplicación de escritorio **sin conexión** para administrar el alquiler de
apartamentos (≈70 unidades agrupadas en residenciales como Anamelia, Villa
Cerro y Anamulla). Abre directamente, sin inicio de sesión.

> **Estado: Fase 3C (impresión 2C-P80-C).** Cobros, anulación auditada, depósitos, recibos PDF de
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
flutter test                    # 189 pruebas
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

## Impresora (2C-P80-C de 80 mm)

`Ajustes → Impresora` ofrece **tres modos de conexión**:

| Modo | Cuándo usarlo |
|---|---|
| **Automático** (por defecto) | La aplicación busca sola: si hay un único puerto serie Bluetooth lo usa; si no, avisa "No se encontró la impresora. Revise Bluetooth." |
| **Windows** | La impresora tiene driver del fabricante y cola en el sistema. Envía el PDF de 80 mm con `Printing.directPrintPdf` (sin diálogos). |
| **Bluetooth (COM)** | Emparejada como *Bluetooth clásico (SPP)*; Windows crea un puerto `COM`. Se envía **ESC/POS nativo** por ese puerto, sin driver. |

Detalles importantes:

* Los puertos se listan leyendo `HKLM\HARDWARE\DEVICEMAP\SERIALCOMM` y se
  etiquetan con el nombre de Windows (`Standard Serial over Bluetooth link
  (COM5)`), marcando los **entrantes** (*Bluetooth-Incoming*) como *no sirven
  para imprimir*.
* **Ancho del papel ≠ ancho imprimible.** El perfil guarda `paperWidthMm = 80`
  y un **ancho útil en puntos** (`printerPrintableDots`). Sin calibrar se usa un
  valor conservador de **576 puntos (72 mm)** — nunca el máximo teórico — para
  que el texto no se recorte. El PDF se genera a 80 mm de ancho y el contenido
  se centra dentro del área imprimible (margen mínimo 4 mm por lado).
* **Calibración**: *Probar* imprime un ticket con marco, regla de columnas,
  alineaciones, acentos y montos. Con una regla se mide el ancho real y se
  guarda en `Avanzado → Ancho útil calibrado (puntos)` (mm × 8).
* **Nada de cortes.** La 2C-P80-C se rasga a mano: no se envían comandos de
  cortador (`GS V`). El perfil solo cortaría si algún día se verifica un
  cortador real.
* La salida por COM corre en un **isolate** (no congela la interfaz) y usa
  tiempos de espera acotados; escritura en bloques de 512 bytes.
* El orden es **commit → PDF → impresión**. Si la impresora falla, el cobro y el
  recibo quedan guardados y se puede reimprimir desde el historial.
* Los avisos dicen **"Enviado a la impresora… no hay confirmación del
  dispositivo"**, nunca "Impreso": el equipo no reporta estado.
* Nunca se reimprime solo al arrancar; el arranque solo **regenera PDF**
  faltantes.
* La cédula se imprime enmascarada; en papel se usa `X` (el `•` viaja como 0x07
  y muchas impresoras lo interpretan como BEL).

**Límites reales (no maquillados):**

* Bluetooth **LE (BLE)** no está soportado (no expone puerto serie ni acepta
  ESC/POS por GATT).
* No se garantiza el resultado con un modelo distinto ni con un driver de otra
  familia (p. ej. `2C-POS80-01-V8` no es el de la `2C-P80-C`).
* La **prueba física** en la impresora y el equipo del cliente sigue
  **pendiente** (ver `docs/INFORME_FASE_3C_2C_P80_C.md`).

### Herramientas de verificación (no tocan los datos reales)

```powershell
# Todo lo que se ejecute con esta variable usa una carpeta aparte (sandbox)
$env:CONTROL_ALQUILERES_DATA_DIR = "$env:TEMP\ca-sandbox\datos"

dart run tool/print_calibration.dart COM5          # ticket de calibración por ESC/POS
dart run tool/print_receipt.dart COM5              # imprime el último recibo real
dart run tool/print_receipt.dart --solo-bin        # genera el .bin sin imprimir
dart run tool/uat_seed.dart                        # escenario de 70 apartamentos
dart run tool/verify_data.dart                     # abre una COPIA de la base real
```
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
│   ├── printer_profile.dart            ancho util calibrado, margenes, columnas
│   ├── escpos.dart                    bytes ESC/POS (CP850, sin corte) + calibración
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
tool/print_calibration.dart  ticket de calibración por puerto COM
tool/print_receipt.dart      imprime un recibo real (o genera el .bin)
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
* **Marco nativo de Windows**: la barra de título, minimizar, maximizar, cerrar,
  arrastre y ajuste por DPI los dibuja el sistema operativo (`TitleBarStyle.normal`);
  la aplicación no pinta botones falsos. Mínimo 960×540 (1366×768 al 125 % deja
  ~1093×578).

### Comportamiento por tamaño

| Condición | Diseño |
|---|---|
| Inicio con ancho ≥ 1040 | Lista (62 %) y ficha del apartamento (38 %) lado a lado |
| Cobros con ancho ≥ 1080 | Cobro + historial (58 %) y ficha (42 %) lado a lado |
| resto | Columna única desplazable; la lista de apartamentos tiene su propia zona con scroll (la fila cortada se difumina) |

Probado sin desbordes en 1536×1024, 1366×768, 1280×720, 1093×578, 1024×576 y
960×540.

---

## Navegación e iconos

Barra lateral **siempre contraída** (54 px): tres destinos arriba y
**Configuración** abajo, separada (es el único sitio desde donde se abre).

| Sección | Responsabilidad única |
|---|---|
| **Inicio** | Trabajo diario: lista de apartamentos + ficha del elegido y botón *Cobrar*. Sin formulario de pago ni historial. |
| **Apartamentos** | Datos maestros: crear/editar apartamento, inquilino y condiciones del contrato. No cobra. |
| **Cobros** | Único taller de cobro: formulario de pago + historial + ficha del apartamento. |

*Cobrar* en Inicio solo **selecciona** el apartamento y abre **Cobros**; nunca
cambia de apartamento en silencio.

Los 11 PNG entregados se copiaron tal cual a `assets/icons/` (línea negra sobre
transparente) y se registran con una sola entrada (`assets/icons/`). El mapeo
vive en `lib/src/ui/widgets/app_icon.dart`:

| Archivo | Uso |
|---|---|
| `home.png` | barra lateral · Inicio |
| `apartments.png` | barra lateral · Apartamentos, títulos y ficha |
| `payments.png` | barra lateral · Cobros, encabezado de cobro |
| `settings.png` | barra lateral · Configuración (abajo) |
| `search.png` | campo *Buscar apartamento o inquilino* |
| `back.png` | botón *Cambiar* (volver a elegir apartamento) |
| `add.png` | *Nuevo Apartamento*, *Registrar inquilino*, menús |
| `receipt.png` | insignia de recibo y menú *Ver PDF* |
| `edit.png` | *Editar*, *Editar inquilino* |
| `delete.png` | *Anular pago*, *Eliminar residencial* |
| `print.png` | *Reimprimir*, acción de impresión por fila |

Se dibujan con `AppIconView` (tintado `srcIn`, `filterQuality.medium`) y llevan
etiqueta semántica en español; `test/ui_navigation_test.dart` comprueba que los
11 archivos se cargan de verdad desde el paquete.

Capturas de la aplicación **en ejecución** (build de release, datos del sandbox
en `%TEMP%\ca-ui`, nunca los reales): `docs/capturas/`.

---

## Pruebas (189)

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
| `uat_sequence_test.dart` | secuencia completa (residencial→apartamento→inquilino→contrato→depósito→abono→saldo→adelanto→PDF→reimpresión→anulación→devolución→fin→nuevo inquilino→PDF anterior→copia→restauración) con cifras exactas |
| `receipt_integrity_test.dart` | ver/reimprimir no crea dinero; regenerar conserva número y snapshot; calibración marcada PRUEBA; snapshot dañado no imprime en blanco |
| `power_loss_test.dart` | apagón simulado (copia con WAL abierto), .tmp a medias, restauración atómica |
| `portfolio_actions_test.dart` | residenciales (crear/renombrar/eliminar), apartamentos, inquilinos, condiciones y búsqueda |
| `data_location_test.dart` | guardia de sandbox: se niega a escribir en la carpeta real |
| `uat_fixture_test.dart` | escenario de 70 apartamentos: estados, saldos, anulación, depósitos, 99 PDF, integridad |
| `ui_navigation_test.dart` | 11 iconos cargados del paquete, etiquetas en español, *Cobrar*→Cobros, un solo formulario/historial, tooltips, 5 tamaños sin desbordes |

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
