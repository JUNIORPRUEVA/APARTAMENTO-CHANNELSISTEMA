# Guía rápida — Control de Alquileres

Para el uso diario. Todo queda guardado en el equipo; no hace falta internet.

## Abrir la aplicación

Doble clic en **Control de Alquileres**. Abre directo, sin usuario ni clave.

## Las tres pantallas y los ajustes

La barra de la izquierda **solo tiene iconos**; al pasar el mouse aparece el
nombre:

* **Inicio** (casa): la lista de apartamentos y la ficha del que elija.
* **Apartamentos** (edificio): crear o corregir apartamentos, inquilinos y
  condiciones del contrato. Aquí **no** se cobra.
* **Cobros** (billete): el formulario de pago y el historial. Es el único sitio
  donde se registra dinero.
* **Configuración** (engranaje, abajo del todo): impresora, datos del negocio y
  copias de seguridad.

## Cobrar un alquiler

1. En **Inicio**, elija el apartamento en la lista (o pulse **Cobrar** en su
   fila). La aplicación abre **Cobros** con ese apartamento ya elegido.
2. En **Registrar pago** verifique:
   * **Período**: cámbielo con `‹ ›` si cobra otro mes.
   * **Monto a pagar**: viene el saldo completo; puede escribir un abono menor.
   * **Método**: efectivo o transferencia. Si es transferencia, escriba la
     **Referencia** (número de operación) — es opcional.
   * **Fecha de pago**: la de hoy por defecto.
3. Pulse **Cobrar e imprimir**: el cobro se guarda y el ticket sale solo.
   Si no quiere ticket, pulse **No imprimir ticket** (se guarda igual).
4. El aviso dirá si el ticket se **envió a la impresora**. Eso significa
   "enviado", no "impreso": revise el papel.

> Si la impresora no responde, **el cobro ya quedó guardado**. Puede reimprimir
> después desde el historial.

## Configurar la impresora (una sola vez)

**Configuración** (engranaje abajo a la izquierda) → **Impresora** →
**Probar impresora**. La aplicación busca la impresora sola e imprime un ticket
de prueba; si sale, **ya queda configurada para siempre**. No hay que elegir
puertos ni dispositivos.

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

## Configurar la impresora 2C-P80-C (una sola vez)

1. Encienda la impresora (batería cargada) y cargue el rollo de 80 mm.
2. **Windows** → Configuración → Bluetooth y otros dispositivos → *Agregar
   dispositivo* → *Bluetooth* → elija **2C-P80-C**. Windows crea el puerto
   saliente solo; **no hay que buscar ni elegir puertos**.
3. Abra la aplicación → **Configuración** (engranaje abajo a la izquierda) →
   sección **Impresora** → **Probar impresora**. La aplicación busca sola,
   imprime el ticket de prueba y guarda la impresora que respondió.
4. Revise el ticket de calibración:
   * El ticket trae un **marco** y una **regla de columnas**: si el marco sale
     completo, el ancho está bien.
   * Si el marco sale cortado por la derecha, abra **Avanzado**, baje
     *Ancho útil calibrado (puntos)* y repita. Regla: **mm impresos × 8 =
     puntos** (72 mm → 576; 64 mm → 512).
   * Si los acentos salen como símbolos raros, marque **Imprimir sin acentos**.
5. Pulse **Guardar**. No hace falta repetir esto cada día.

> Si algún día hay que elegir a mano, la lista sigue en **Elegir impresora a
> mano**, dentro de la misma sección.

> Notas honestas:
> * Si la impresora **no** crea un puerto COM (solo Bluetooth LE), esta versión
>   no puede imprimir por Bluetooth; use el cable USB + driver del fabricante y
>   el modo **Windows**.
> * El aviso "Enviado a la impresora" significa *enviado*, no *impreso*: revise
>   el papel. Si no salió, el cobro sigue guardado y puede reimprimirse.

## Rutina diaria (3 pasos)

1. **Abrir** la aplicación (doble clic).
2. **Cobrar**: elegir el apartamento y pulsar **Cobrar**.
3. Verificar monto y período → **Guardar e imprimir recibo**.

## Copias de seguridad

**Configuración** (engranaje abajo a la izquierda) → **Datos y respaldo**:

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
