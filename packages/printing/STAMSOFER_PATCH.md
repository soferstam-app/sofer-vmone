# Local printing 5.14.3

Source: pub.dev package `printing` 5.14.3, by David PHAM-VAN.
The upstream Apache-2.0 license and copyright notices are retained.

Only Windows build configuration is changed:

- PDFium is pinned to Chromium 5200, Windows x64.
- ExternalProject verifies the archive SHA-256 before extracting it.
- HTTPS certificate verification is explicitly enabled for downloads.
- The extracted DLL is verified on every CMake configure, including cached builds.
- `STAMSOFER_PDFIUM_ARCHIVE` optionally selects a local archive with the same hash.
- The PDFium license path is exported to the application CMake, which installs
  it as `data/licenses/pdfium.txt` in the bundle using Flutter's output path.

Other platforms and Dart/native plugin behavior are unchanged. Flutter's generated
plugin registration and the global Pub cache are not patched. When upgrading this
package or PDFium, explicitly review these pins and update the verified hashes.
End users do not download PDFium: the DLL travels beside the Windows executable.

The application repository includes the plugin's runtime sources, platform build
files, pubspec and license. Upstream examples, screenshots, tests and optional
documentation remain local. The unused screenshot entry is removed from pubspec.
