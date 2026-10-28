# Guía rápida — Control de Alquileres

Para el uso diario. Todo queda guardado en el equipo; no hace falta internet.

## Abrir la aplicación

Doble clic en **Control de Alquileres**. Abre directo, sin usuario ni clave.

## Cobrar un alquiler

1. Elija el apartamento en la lista (o pulse **Cobrar** en su fila).
2. En **Registrar pago** verifique:
   * **Período**: cámbielo con `‹ ›` si cobra otro mes.
   * **Monto a pagar**: viene el saldo completo; puede escribir un abono menor.
   * **Método**: efectivo o transferencia. Si es transferencia, escriba la
     **Referencia** (número de operación) — es opcional.
   * **Fecha de pago**: la de hoy por defecto.
3. Pulse **Guardar e imprimir recibo** (o **Guardar** si no quiere imprimir).
4. El aviso dirá si el recibo se **envió a la impresora**. Eso significa
   "enviado", no "impreso": revise el papel.

> Si la impresora no responde, **el cobro ya quedó guardado**. Puede reimprimir
> después desde el historial.

## Ver o reimprimir un recibo

* En **Pagos realizados**, cada fila muestra su número (`REC-000001`).
* Clic en el distintivo **PDF** → abre el recibo en pantalla.
* Icono de impresora o menú `⋯` → **Reimprimir**.
* Menú `⋯` → **Ver PDF** / **Anular pago**.

## Anular un cobro hecho por error

Menú `⋯` → **Anular pago** → escriba el motivo → **Anular pago**.

El dinero vuelve al saldo del período, el recibo original se conserva y se emite
una **nota de anulación**. Nunca se borra nada.

## Depósitos (garantía)

Pestaña **Depósito** del apartamento:

* **Recibir**: al firmar el contrato.
* **Devolver**: al salir el inquilino.
* **Retener**: con motivo obligatorio (daños, limpieza).

El depósito **no** es renta: no suma al total cobrado de alquiler.

## Terminar un contrato

En el apartamento → **Finalizar contrato**. Si queda renta pendiente o depósito
sin liquidar, el sistema lo avisa antes. El historial del inquilino anterior se
conserva y se puede consultar con el filtro del historial.

## Configurar la impresora (una sola vez)

**Engranaje** → sección **Impresora**:

1. Pulse **Actualizar**.
2. Elija en la lista:
   * la **impresora instalada en Windows**, o
   * el **puerto COM** de la impresora Bluetooth (`COM3`, `COM5`…; se marca
     *Bluetooth probable*).
3. Pulse **Imprimir prueba** y revise el ticket:
   * Si los acentos salen como símbolos raros, marque **Imprimir sin acentos** y
     repita la prueba.
   * Si no sale nada, revise que la impresora esté encendida, con papel y
     emparejada en Windows.
4. Pulse **Guardar**.

> Las impresoras **Bluetooth LE** (las que no crean un puerto COM) no son
> compatibles con esta versión.

## Copias de seguridad

**Engranaje** → **Datos y respaldo**:

* Se crea una copia automática al abrir si pasó más de un día (se guardan 14).
* **Crear copia ahora**: copia inmediata.
* **Restaurar copia**: elegir una copia y confirmar; la app debe reabrirse.
* **Carpeta para exportar** + **Exportar**: para llevar la copia a una memoria
  USB.

## Buenas prácticas

1. Cobrar siempre con el apartamento correcto seleccionado (el título del
   formulario lo confirma).
2. Anular, nunca "corregir" un cobro escribiendo otro encima.
3. Antes de entregar el equipo a otra persona, exportar una copia.
4. No mover ni borrar la carpeta
   `%APPDATA%\do.channelsistema\Control de Alquileres\datos`.
