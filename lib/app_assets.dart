/// The same assets are namespaced when the app runs as a package dependency.
abstract final class AppAssets {
  static String? packageName;

  static String path(String asset) {
    final package = packageName;
    return package == null ? asset : 'packages/$package/$asset';
  }
}
