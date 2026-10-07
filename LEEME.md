# Escáner LiDAR para iPhone (sin Mac)

App nativa para iPhone con LiDAR (pensada para el iPhone 15 Pro Max, iOS 17 o superior).
Escanea en 3D y exporta dos archivos:

- **`..._malla.obj`**: malla de triángulos generada por el LiDAR (geometría, sin textura).
- **`..._nube.ply`**: nube de puntos a color (profundidad del LiDAR + color de la cámara).

Unidades en metros. Por defecto el eje **Z** es el vertical (como Vulcan, CloudCompare y Civil 3D);
al exportar se puede desactivar para dejar el eje **Y** vertical, como lo entrega ARKit.

## Aviso importante

Este código **no se ha podido compilar ni probar** al crearlo (hace falta un Mac). La primera
compilación en GitHub puede dar algún error. Si pasa, copia el texto del error y envíamelo:
se corrige y se vuelve a subir.

## Paso 1: compilar en la nube (GitHub, gratis)

1. Crea una cuenta en github.com y un repositorio nuevo **público** (por ejemplo `escaner-lidar`).
2. Descomprime el ZIP en tu PC.
3. En el repositorio: **Add file › Upload files** y arrastra **todo el contenido** de la carpeta
   (`Sources`, `.github`, `project.yml`, `LEEME.md`). Pulsa **Commit changes**.
4. Si la carpeta `.github` no se subió, créala a mano: **Add file › Create new file**, escribe como
   nombre `.github/workflows/build.yml` y pega dentro el contenido de ese archivo.
5. Abre la pestaña **Actions**. Verás el flujo **Compilar IPA** ejecutándose (tarda unos minutos).
   Si no partió solo, entra al flujo y pulsa **Run workflow**.
6. Cuando termine en verde, entra a la ejecución y descarga el artefacto **EscanerLiDAR-ipa**.
   Es un ZIP: dentro está `EscanerLiDAR.ipa`.

## Paso 2: instalar en el iPhone desde Windows

1. Instala **iTunes** e **iCloud** descargados desde la web de Apple (no los de Microsoft Store).
2. Instala **Sideloadly** (sideloadly.io).
3. Conecta el iPhone por cable, desbloquéalo y pulsa **Confiar**.
4. En Sideloadly: arrastra `EscanerLiDAR.ipa`, escribe tu Apple ID y pulsa **Start**.
5. En el iPhone:
   - **Ajustes › General › VPN y gestión de dispositivos**: confía en tu Apple ID.
   - **Ajustes › Privacidad y seguridad › Modo de desarrollador**: actívalo (pide reiniciar).

Con un Apple ID gratuito la firma dura **7 días**. Después hay que volver a conectar el iPhone
y repetir el paso 4 (los archivos escaneados no se pierden).

## Paso 3: usar la app

Antes de escanear puedes pulsar **Diagnóstico LiDAR**: muestra el mapa de profundidad en vivo
(rojo cerca, azul lejos), la distancia al centro, lecturas por segundo, porcentaje de confianza,
seguimiento, luz y temperatura, y dice si el sensor está bien. Para probar la precisión, apunta
el + a una pared mate a 1 m y compara con una huincha.

1. Abre **Escáner LiDAR** y acepta el permiso de cámara.
2. Pulsa **Iniciar escaneo** y muévete despacio alrededor del objeto o espacio. Verás la malla
   dibujarse encima de la imagen y los contadores de vértices y puntos subir.
3. Pulsa **Detener** y luego **Exportar**.
4. Los archivos quedan en **Archivos › En mi iPhone › Escáner LiDAR** y además se abre la hoja
   de compartir (AirDrop, correo, WhatsApp, iCloud Drive, etc.).

## Límites de esta versión

- Alcance útil del LiDAR: unos 5 m. Funciona mejor entre 0,3 y 3 m.
- La malla no lleva textura; el color está en la nube de puntos.
- La nube guarda un punto por cada centímetro cúbico (confianza media y alta), hasta 2 millones
  de puntos. Se leen unas 30 imágenes por segundo, fuera de la pantalla principal.
- Superficies negras, brillantes, vidrio y agua se escanean mal.

## Abrir los archivos en el PC

- **CloudCompare** (gratis): abre el PLY y el OBJ, mide distancias, áreas y volúmenes.
- **MeshLab** o **Blender** (gratis): ver y editar la malla.

## Archivos del proyecto

| Archivo | Para qué sirve |
|---|---|
| `Sources/EscanerApp.swift` | Punto de entrada de la app |
| `Sources/ContentView.swift` | Pantalla: cámara, contadores y botones |
| `Sources/ScanManager.swift` | Sesión de ARKit: iniciar, detener, exportar |
| `Sources/PointCloud.swift` | Nube de puntos a color y escritura del PLY |
| `Sources/Exporter.swift` | Escritura del OBJ y guardado de archivos |
| `Sources/FrameProcessor.swift` | Procesa los cuadros de la cámara en segundo plano |
| `Sources/LidarDiagnostics.swift` | Mediciones del diagnóstico del sensor |
| `Sources/DiagnosticsView.swift` | Pantalla del diagnóstico |
| `project.yml` | Definición del proyecto (XcodeGen lo convierte en proyecto de Xcode) |
| `.github/workflows/build.yml` | Receta de compilación en GitHub Actions |
