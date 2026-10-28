# Informe de aceptación de impresión — 2C-P80-C (Fase 3C)

Fecha: 2026-10-28 · Versión construida: **1.2.0+3** · Equipo de desarrollo: ASUS
(Ryzen 5 7600X, 32 GB RAM), Windows 11 Pro 25H2 (10.0.26200), 64 bits,
1920×1080 al 100 % (96 dpi).
**Impresora física: NO conectada al equipo de desarrollo → pruebas físicas
NOT RUN** (ver §3).

---

## 1. Datos detectados y decisiones de configuración

### Equipo de desarrollo (donde se construyó y verificó)

| Dato | Valor detectado (comando) |
|---|---|
| Windows | 11 Pro, build 26200, 64 bits (`Get-CimInstance Win32_OperatingSystem`) |
| Pantalla / escalado | 1920×1080, 100 % (96 dpi, `AppliedDPI`) |
| Spooler | Running (`Get-Service Spooler`) |
| Colas instaladas | `SEWOO SLK-TS100`, `SEWOO SLK-TS100 (copy 1)`, `Microsoft Print to PDF`, `EPSON L3250 Series`, `L3250 Series(Network)`, `2C-POS80-01-V8 Printer`, `2C-POS80-01-V8 Printer(2)` |
| Driver 2C instalado | `2C-POS80-01-V8` (versión 1407379178586118), en `USB001` y `USB003` |
| Puertos serie | `COM1` (Puerto de comunicaciones físico, ACPI), `COM2:`, `COM3:`, `COM4:`, `COM5:` (redirecciones de cola) |
| Bluetooth | MediaTek Bluetooth Adapter (OK) + RFCOMM TDI (OK). Emparejado solo un teléfono (`GT27`); **ninguna impresora** |
| Impresoras USB presentes | `Get-PnpDevice -PresentOnly` → solo EPSON (USBPRINT y WSD). **La 2C no está conectada**: sus colas tienen 17+5 trabajos viejos atascados, sin dispositivo detrás |

### Impresora objetivo (datos aportados, usados como hechos)

2connet **2C-P80-C** portátil, rollo **80 mm** térmico, Bluetooth + USB,
ESC/POS, batería, **borde de rasgado manual** (sin cortador verificado), driver
del fabricante `POS80Setup_20201208.rar`. **No se usó** el driver de otra familia
(`2C-POS80-01-V8`) ni se ejecutó ningún instalador ni actualización de firmware
desde esta sesión.

### Ancho de papel: el punto crítico

**80 mm es el ancho del rollo, no el ancho imprimible.** Las cifras publicadas
para esta familia (72 mm/576 puntos vs 79 mm/640 puntos) son inconsistentes y no
se ha medido el equipo real. Por eso:

* Se creó un **perfil de impresión** persistido (`owner_settings`, esquema **v4**):
  `paperWidthMm = 80`, `printerPrintableDots` (calibrado, 0 = sin calibrar),
  `printerMarginDots`, `printerBaudRate`, `ascii_only`, codificación CP850 y
  **`cutMode = manual`**.
* Sin calibrar se usa un valor **conservador**: **576 puntos (72 mm)** en 80 mm y
  384 (48 mm) en 58 mm. Nunca el máximo teórico: es preferible un margen a perder
  dígitos del monto.
* El **PDF** se genera a **80 mm exactos** de ancho (verificado leyendo el
  `/MediaBox`) con alto variable, y el contenido se **centra dentro del área
  imprimible**: el margen efectivo es `max(margen configurado, (80 − ancho útil)/2)`
  → **mínimo 4 mm por lado** sin calibrar.
* El **ESC/POS** calcula las columnas desde los puntos calibrados:
  `(puntos − 2·margen) / 12` → **48 columnas** sin calibrar (32 en 58 mm).
* **Calibración**: *Probar* imprime un ticket con marco, regla de columnas,
  alineaciones izquierda/centro/derecha, tamaños, acentos y montos. Regla de
  conversión: **mm impresos × 8 = puntos**.
* **No se envían comandos de corte** (`GS V`): la impresora es de rasgado manual.
  Solo se cortaría si el perfil se cambia a `autoCutter` tras verificar el equipo.

### Transporte y detección

* Modos: **Automático** (por defecto) / **Windows** / **Bluetooth (COM)**.
* Puertos por `HKLM\HARDWARE\DEVICEMAP\SERIALCOMM` + nombres amistosos vía
  `Win32_PnPEntity`; los **entrantes** (*Bluetooth-Incoming*) se marcan como
  *no sirven para imprimir* y no se eligen nunca.
* En modo automático solo se elige un puerto si hay **exactamente uno** de tipo
  Bluetooth saliente; con varios, se pide elegir en Ajustes; sin ninguno:
  "No se encontró la impresora. Revise Bluetooth."
* Envío por COM por FFI propio (`CreateFileW`/`GetCommState`/`SetCommState`/
  `SetCommTimeouts`/`WriteFile`/`CloseHandle`), 9600-8-N-1, bloques de 512 bytes,
  tiempo de espera acotado, en un **isolate** para no congelar la UI.

## 2. Archivos cambiados y pruebas

### Archivos (y motivo)

| Archivo | Cambio |
|---|---|
| `lib/src/services/printer_profile.dart` | **nuevo**: perfil calibrado, conversión puntos↔mm, columnas, márgenes, modo de corte |
| `lib/src/data/schema.dart` | esquema **v4** + `kMigrationV4Statements` (3 columnas nuevas, valores por defecto seguros) |
| `lib/src/data/app_database.dart` | paso de migración `3 → 4` |
| `lib/src/data/models.dart` | `PrinterTransport.auto`; `printerPrintableDots`, `printerMarginDots`, `printerBaudRate`; por defecto **auto** |
| `lib/src/data/settings_repository.dart` | carga/guarda y **validación** de los nuevos campos (valores imposibles → "sin calibrar") |
| `lib/src/services/escpos.dart` | columnas desde el perfil; **sin corte** por defecto; **ticket de calibración**; cédula enmascarada con `X` |
| `lib/src/services/serial_transport.dart` | nombres amistosos de puerto, distinción **entrante/saliente**, `canSend`; `GetLastError` resuelto antes de fallar (códigos de error reales) |
| `lib/src/services/print_service.dart` | `PrinterDetection`, ruteo automático, mensajes honestos ("Enviado… no hay confirmación"), `printCalibration` |
| `lib/src/services/receipt_document_service.dart` | margen ajustado al área imprimible; **ticket de calibración en PDF**; perfil inyectable |
| `lib/src/app/app_controller.dart` | `detectPrinter`, `printCalibration`, perfil al servicio de documentos |
| `lib/src/ui/pages/settings/settings_page.dart` | modo de conexión, selector, **estado**, **Probar**, *Avanzado* (puntos/margen/baudios/acentos) |
| `lib/src/data/app_paths_resolve.dart` | `CONTROL_ALQUILERES_DATA_DIR` para **aislar** datos en pruebas |
| `lib/src/core/formatters.dart` | `maskCedula(raw, hide: 'X')` para papel |
| `tool/print_calibration.dart` | **nuevo**: calibración por COM sin abrir la app |
| `tool/print_receipt.dart` | **nuevo**: imprime un recibo real o genera el `.bin` |
| `test/printer_profile_test.dart` | **nuevo**: 12 pruebas de perfil y persistencia |
| `test/migration_backup_test.dart` | +3 pruebas de migración 3→4 y 1→4 |
| `test/escpos_test.dart`, `test/printer_matrix_test.dart`, `test/receipt_document_test.dart` | sin corte, cédula `X`, calibración, ruteo, puerto inexistente/entrante, PDF que crece en alto al angostar el área |
| `README.md`, `docs/INVENTARIO_CONTROLES.md`, `docs/GUIA_RAPIDA.md` | documentación actualizada |

No se rediseñó ninguna pantalla ni se agregaron módulos, cuentas, reportes ni
servicios en la nube.

### Comandos ejecutados y resultado

| Comando | Resultado |
|---|---|
| `dart format lib test tool` | 58 archivos, 0 pendientes |
| `flutter analyze` | **No issues found!** |
| `flutter test` | **146 pruebas, todas pasan** (antes 129) |
| `flutter build windows --release` | OK → `build\windows\x64\runner\Release\control_alquileres.exe` (**1.2.0+3**) |
| Prueba de humo del EXE (aislada) | arranca, permanece estable, crea su base en `%TEMP%\ca-sandbox2`, **la base real queda intacta** (mtime idéntico) |
| `dart run tool/verify_data.dart` | copia de la base real migra a **v4** sin errores: 3 residenciales, 13 apartamentos, 6 contratos, 1 cobro, 5 recibos, 3 depósitos |
| `dart run tool/uat_seed.dart` | 70 apartamentos, 99 recibos, **99 PDF**, integridad correcta |
| `dart run tool/print_receipt.dart --solo-bin` | genera el flujo ESC/POS real de un recibo: 1161 bytes, contenido verificado (abajo) |
| `dart run tool/print_calibration.dart COM99` | error honesto: "El puerto COM99 no existe. Empareje la impresora Bluetooth…" |

### Evidencia del flujo ESC/POS (sin impresora)

Recibo `REC-000099` decodificado desde los bytes generados (CP850):

```
Anamelia Rentas
RNC/Céd.: 131-00000-1
Av. 27 de Febrero 123, Santo Domingo
Tel.: 809-555-0101
------------------------------------------------
RECIBO DE ALQUILER
No. REC-000099
Emitido: 27/10/2026 23:53
------------------------------------------------
Residencial                             Anamulla
Apartamento                                 A-18
Ubicación                    Anamulla · bloque 3
Inquilino                Pedro Antonio Reyes (1)
Cédula                            101-XXXXXXX-70
------------------------------------------------
Concepto                                Alquiler
Período                             Octubre 2026
Vence                                 09/10/2026
Método                                  Efectivo
Fecha pago                            09/10/2026
------------------------------------------------
MONTO         RD$ 11,600
Saldo del período                          RD$ 0
Obs.: Pago en efectivo
------------------------------------------------
Conserve este recibo
Documento de control interno. No es comprobante
fiscal (NCF).
```

48 columnas, acentos correctos, montos en RD$, cédula enmascarada, sin comandos
de corte al final (solo avance de papel).

## 3. Pruebas físicas — **NOT RUN**

No hay impresora 2C-P80-C (ni ninguna térmica) conectada al equipo de desarrollo:
`Get-PnpDevice -PresentOnly` solo muestra la EPSON, y las colas
`2C-POS80-01-V8` tienen trabajos viejos atascados sin dispositivo detrás.
Por tanto **no se presenta ninguna simulación como aceptación de hardware**.

| # | Prueba física | Estado |
|---|---|---|
| 1 | Emparejar y sobrevivir reinicio | NOT RUN |
| 2 | Auto-test del equipo (modelo, firmware, modo BT, codepages, ancho) | NOT RUN |
| 3 | Ticket de calibración medido con regla | NOT RUN |
| 4 | Recibo real + PDF + reimpresión sin duplicar | NOT RUN (la parte de datos sí está probada) |
| 5 | Parcial, adelanto, depósito, anulación, inquilino anterior | NOT RUN (datos probados) |
| 6 | Apagado, sin papel, batería, spooler caído, cierre forzado | NOT RUN (manejadores probados) |
| 7 | `quick_check`, duplicados, huérfanos, copia/restauración | PARCIAL: todo verificado en software |
| 8 | Reinicio del portátil y cobro real | NOT RUN |

### Guion de prueba en sitio (5–10 minutos)

1. Cargar rollo de 80 mm, encender. Imprimir el **auto-test** del manual del
   fabricante y anotar: modelo, firmware, modo BT (SPP/BLE), code pages,
   baudios y **ancho imprimible en puntos si lo indica**.
2. Emparejar por Bluetooth clásico. En *Administrador de dispositivos → Puertos
   COM y LPT* anotar el puerto **saliente** (p. ej. `COM5`).
3. En el equipo, con la app cerrada:
   `dart run tool/print_calibration.dart COM5 9600` (o *Ajustes → Probar*).
   Medir el marco con regla: **mm × 8 = puntos** → guardarlo en
   *Avanzado → Ancho útil calibrado*.
4. Cobrar un alquiler de prueba en un **sandbox**
   (`$env:CONTROL_ALQUILERES_DATA_DIR`), imprimir, y reimprimir: verificar mismo
   número, monto e inquilino, y que el conteo de pagos no cambie.
5. Probar fallos: apagar la impresora y cobrar (debe avisar y guardar), alejarse
   del alcance, sacar el papel, cerrar la app a mitad de impresión. En todos los
   casos: cobro guardado + PDF disponible + reimpresión manual.
6. Reiniciar el portátil y repetir un cobro real.

## 4. Configuración en una sola vez + rutina de 3 pasos

**Configuración (una vez):** emparejar por Bluetooth clásico → *Engranaje* →
*Impresora* → **Actualizar** → elegir el puerto `COM…` con *Bluetooth* (nunca
*entrante*) → **Probar** → si el marco sale cortado, bajar el *ancho útil* en
*Avanzado* → **Guardar**.

**Rutina diaria:**
1. Abrir la aplicación (doble clic).
2. **Cobrar** el apartamento.
3. Revisar monto y período → **Guardar e imprimir recibo**.

## 5. Veredicto

**BLOCKED** (no "listo para el cliente"). Falta exactamente esto:

1. **Impresión física** de un ticket real en la 2C-P80-C (marco completo, sin
   recortes, acentos legibles, rasgado cómodo).
2. **Auto-test del equipo** para confirmar modo Bluetooth (SPP, no BLE),
   baudios, code pages y ancho imprimible.
3. **Aceptación en el portátil real** (11.6" táctil, Pentium N6000, 8 GB): el
   equipo de desarrollo no es ese portátil, así que el escalado y el arranque en
   frío en ese hardware no se han medido.
4. Confirmación de **recuperación de copia** en ese equipo.

Lo que **sí** está verificado: lógica de negocio y dinero, esquema v4 con
migración segura, PDF de 80 mm exactos, perfil calibrado y su persistencia,
generación ESC/POS sin corte, ruteo de impresora sin adivinar, mensajes honestos
de estado, y 146 pruebas automatizadas en verde.
