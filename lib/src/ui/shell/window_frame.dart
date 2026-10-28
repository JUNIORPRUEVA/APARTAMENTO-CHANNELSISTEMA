import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:window_manager/window_manager.dart';

/// Pinta la **barra de título nativa** de Windows en blanco.
///
/// Windows decide el color del marco con `DWMWA_USE_IMMERSIVE_DARK_MODE`, y
/// `window_manager.setBrightness` solo lo cambia si puede leer el registro de
/// tema del usuario. Cuando esa lectura falla o el sistema está en modo oscuro
/// el marco sale negro y no combina con la interfaz clara, así que aquí se fija
/// el color de forma explícita (Windows 11):
///
/// * `DWMWA_USE_IMMERSIVE_DARK_MODE = 20` → `FALSE`.
/// * `DWMWA_CAPTION_COLOR = 35` → blanco (`0x00FFFFFF`, orden COLORREF BGR).
/// * `DWMWA_TEXT_COLOR = 36` → texto oscuro.
///
/// En Windows 10 los atributos 35/36 no existen: la llamada devuelve error y se
/// ignora sin romper nada (el marco queda como esté configurado en el sistema).
Future<void> applyLightTitleBar() async {
  if (!Platform.isWindows) return;
  try {
    final handle = await windowManager.getId();
    if (handle == 0) return;
    final dwmapi = DynamicLibrary.open('dwmapi.dll');
    final setAttribute = dwmapi
        .lookupFunction<
          Int32 Function(IntPtr, Uint32, Pointer<Void>, Uint32),
          int Function(int, int, Pointer<Void>, int)
        >('DwmSetWindowAttribute');
    final value = calloc<Int32>();
    try {
      value.value = 0; // 0 = sin modo oscuro.
      setAttribute(handle, 20, value.cast<Void>(), sizeOf<Int32>());
      value.value = 0x00FFFFFF; // Blanco.
      setAttribute(handle, 35, value.cast<Void>(), sizeOf<Int32>());
      value.value = 0x001A1A1A; // Texto casi negro.
      setAttribute(handle, 36, value.cast<Void>(), sizeOf<Int32>());
    } finally {
      calloc.free(value);
    }
  } catch (_) {
    // Sin DWM (o Windows 10): se deja el marco del sistema.
  }
}

/// Igual que [applyLightTitleBar] pero sin esperar: útil tras mostrar la
/// ventana, cuando el identificador nativo ya existe.
void applyLightTitleBarSoon() {
  // Se repite a los pocos milisegundos porque al maximizar Windows vuelve a
  // aplicar el tema del sistema al marco.
  applyLightTitleBar();
  Future<void>.delayed(const Duration(milliseconds: 400), applyLightTitleBar);
}
