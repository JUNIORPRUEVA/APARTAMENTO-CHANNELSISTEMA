# Cierre funcional previo al diseño — Control de Alquileres

Fecha: 2026-10-28 · Versión: **1.2.0+3** · Esquema: **v4** · Pruebas: **178**
Windows 11 Pro 26200 · Flutter 3.41.6 / Dart 3.11.4
**Sin cambios de diseño, sin instalador, sin despliegue y sin imprimir en hardware.**

---

## 1. Qué se cambió (por archivo y función)

### Nuevo en esta fase

| Archivo | Función nueva |
|---|---|
| `lib/src/data/data_location.dart` | **Guardia de sandbox**: detecta la carpeta real y **aborta** (`SandboxViolation`) si una herramienta intenta escribir ahí o si falta la carpeta. Incluye sonda de escritura real. |
| `tool/uat_seed.dart`, `tool/phase2_flow.dart`, `tool/print_receipt.dart` | Usan la guardia: mensaje claro en español y código de salida 4/3. `print_receipt` exige sandbox explícito. |
| `lib/src/data/portfolio_repository.dart` | **`deleteGroup`**: elimina un residencial **solo si está vacío** (antes no existía: el menú prometía borrar y no había código). |
| `lib/src/app/app_controller.dart` | `deleteGroup` con manejo de error en español y limpieza del filtro activo. |
| `lib/src/ui/pages/home/apartment_list_card.dart` | Tercera opción del menú `⋯`: **Eliminar residencial** con confirmación explícita. |
| `lib/src/services/escpos.dart` | Ticket de calibración marcado **«PRUEBA DE IMPRESORA» + «NO ES UN PAGO» + «No afecta saldos ni recibos»**, al inicio y al final. |
| `lib/src/services/receipt_document_service.dart` | Calibración PDF con el mismo marcado; **`ensure()` rechaza snapshots vacíos/ilegibles** (nunca imprime un recibo en blanco) y marca el recibo como `fallido`. |
| `lib/src/services/backup_service.dart` | Restauración **atómica**: copia a `.restaurando` y renombra; un corte a mitad ya no deja la base truncada. |
| `test/data_location_test.dart` (5), `test/uat_sequence_test.dart` (2), `test/receipt_integrity_test.dart` (5), `test/power_loss_test.dart` (5), `test/portfolio_actions_test.dart` (13) | 30 pruebas nuevas de esta fase. |

### Ya existía y se verificó (no se reescribió)

Cobros atómicos e idempotentes, abonos/adelantos, anulación con motivo y nota
(Apéndice y guardia anti doble anulación), depósitos con topes, PDF inmutable por
movimiento con snapshot, historial con *Ver PDF* / *Reimprimir*, migraciones
1→2→3→4, copias con rotación de 14, ajustes de negocio/impresora con
*Ajustes → Datos y respaldo*, perfil de impresión calibrado, transporte Windows
y COM, tres iconos de barra lateral y engranaje arriba a la derecha.

**No se tocó**: diseño visual, tipografías, colores, navegación, ni se agregó
módulo, reporte, login, instalador o servicio en la nube.

## 2. Lista de aceptación funcional

| Acción / estado | Resultado |
|---|---|
| Residencial: crear, renombrar, **eliminar si está vacío** | FUNCIONA (confirmación + aviso si tiene apartamentos) |
| Apartamento: crear, editar, número único por residencial, ocupación coherente | FUNCIONA |
| Búsqueda/filtro por número, residencial o inquilino | FUNCIONA |
| Inquilino: crear/editar con validación de cédula y teléfono | FUNCIONA |
| Contrato: inicio, condiciones, fin; historial del inquilino anterior; sin dos contratos activos | FUNCIONA |
| Vencimientos de fin de mes y bisiesto; estados al día/parcial/pendiente/vencido/disponible | FUNCIONA |
| Cobro: parcial, total, adelanto; sin doble cobro; método y referencia opcional | FUNCIONA |
| Recibo por cobro: número correlativo, PDF propio, snapshot inmutable | FUNCIONA |
| Fila del historial: número, *Ver PDF*, *Reimprimir*, anular | FUNCIONA |
| Ver o reimprimir **no** crea cobros, recibos ni números | FUNCIONA (probado) |
| Anulación: motivo obligatorio, reverso append-only, saldo restaurado, sin doble anulación | FUNCIONA |
| Depósito: recibir, devolver, retener con topes y motivo; separado de la renta | FUNCIONA |
| PDF regenerado tras borrado: mismo número, mismo nombre, mismo snapshot | FUNCIONA (probado) |
| Snapshot dañado | Ahora **falla explícito**, no imprime un recibo en blanco |
| Ajustes: negocio, recibo, impresora, copias | FUNCIONA; impresora ausente **no rompe** la pantalla |
| Impresora: Windows / Bluetooth COM / automático | FUNCIONA en software; hardware NO probado |
| *Probar* impresora | Ticket marcado **PRUEBA · NO ES UN PAGO**, no toca numeración |
| Copia / restauración | FUNCIONA; restauración atómica, con confirmación y copia previa |
| Arranque tras apagón | FUNCIONA; nunca reimprime solo |

## 3. Evidencia ejecutada

```
dart format lib test tool      -> 65 archivos, 0 cambios pendientes
flutter analyze                -> No issues found!
flutter test                   -> 00:80 +178: All tests passed!
flutter build windows --release-> control_alquileres.exe (1.2.0+3)
```

**Migraciones**: 1→2, 2→3, 3→4 y 1→4 probadas sobre bases pobladas; copia de la
base real abre en **v4** con integridad correcta.

**Sandbox (fallo cerrado)**, comprobado contra la ruta real:

```
uat_seed   -> "se negó a escribir en la carpeta de datos real" (exit 4)
phase2_flow-> "se negó a escribir en la carpeta de datos real" (exit 4)
print_receipt -> "solo abre una COPIA de la base" (exit 3)
```

**Prueba de humo del EXE**: arrancó y permaneció estable 15 s con
`CONTROL_ALQUILERES_DATA_DIR` apuntando a `%TEMP%\ca-smoke-final\datos`; creó su
base ahí. **Se compararon los SHA-256 de los 8 archivos reales (base, WAL, SHM y
5 PDF): 0 cambiados.**

**Datos reales del equipo** (sin exponer contenido): 3 residenciales, 13
apartamentos, 6 contratos, 1 cobro, 5 recibos, 3 depósitos, 5 PDF. Copia aparte:
`_backups\datos-reales-20261028-102636.zip` (verificada abriendo la base dentro
del zip).

**Secuencia ficticia completa** (sandbox, cifras exactas verificadas paso a paso):
depósito RD$ 8,500 retenido → abono RD$ 4,000 (saldo RD$ 4,500) → resto → saldo 0
→ adelanto del mes siguiente → 4 PDF → reimpresión simulada (sin cobros nuevos) →
anulación del resto (saldo vuelve a RD$ 4,500, 1 reverso, nota de anulación, doble
anulación rechazada) → devolución del depósito (retenido 0) → fin de contrato →
nuevo inquilino → PDF del inquilino anterior intacto → copia → alteración → 
restauración (vuelve exactamente al estado de la copia).

**Tamaños de pantalla** (prueba de widget existente): 1536×1024, 1366×768,
1280×720, 1093×578, 1024×576 y 960×540 sin desbordes; barra lateral con 3 iconos.

## 4. Limitaciones y bloqueos reales

1. **Impresión física 2C-P80-C**: no verificada. No hay impresora conectada al
   equipo de desarrollo (solo colas antiguas sin dispositivo). Falta auto-test,
   ancho imprimible real y ticket físico.
2. **Windows exacto y escalado del portátil Lenovo**: sin confirmar por
   inspección directa (el aviso comercial dice Windows 11; el dueño mencionó
   Windows 10). El equipo usado es distinto (ASUS Ryzen 5).
3. **Aceptación en el equipo del cliente**: pendiente.
4. **BLE**: no soportado (limitación declarada, no un fallo oculto).
5. **Pulido visual e instalador**: corresponden a las fases siguientes.

## 5. Veredicto

**SOFTWARE FUNCTIONAL LOGIC READY** — la lógica funcional y financiera está
completa y verificada con 178 pruebas, guardia de sandbox, restauración atómica y
reconstrucción fiel de documentos.

**NO READY para entrega al cliente**: falta la aceptación física de impresión, la
confirmación del Windows/escalado del portátil y el instalador. No se declara
"entregado".

## 6. Referencia visual

Se conserva la captura aprobada: tres iconos (Inicio, Apartamentos, Cobros),
engranaje arriba a la derecha, misma tipografía y colores. El único cambio
visible es una tercera opción en el menú `⋯` de residenciales
(*Eliminar residencial*), funcional y consistente con el resto.
