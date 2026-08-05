import 'dart:math';
import 'dart:ui' show Size;

/// How large the window opens, and where that number comes from.
///
/// Three rules, and the second is the one that is easy to forget:
///
/// 1. **The size the writer left it at.** A desktop app opened for hours a day
///    that resets its window on every launch is asking to be resized every
///    morning.
/// 2. **Never larger than the screen it is opening on.** A size remembered from
///    a 27-inch monitor must not be imposed on the laptop the same writer opens
///    it on that evening — a window wider than the display puts its own title
///    bar out of reach, and there is no way back from that with a mouse.
/// 3. **A default that is modest.** 1280x720 at most, and smaller when the
///    screen is. A first launch that fills the display looks like a fault.
///
/// Pure, so all of it can be checked without a window.
class WindowSizing {
  const WindowSizing._();

  /// The most a *default* window opens at. A remembered one may be larger,
  /// because the writer chose it.
  static const Size preferred = Size(1280, 720);

  /// Below this the layouts stop working: the ruled themes drop to one column
  /// at 620 and below about 400 the figures and buttons collide.
  static const Size minimum = Size(420, 640);

  /// How much of the screen a window may take before it stops looking like a
  /// window. Leaves the desktop visible around it and the title bar reachable.
  static const double screenShare = 0.92;

  /// The size to open at.
  ///
  /// [available] is the display's usable area — its work area where the system
  /// reports one, so the window is not sized under the taskbar.
  static Size startup({Size? remembered, required Size available}) {
    var width = remembered?.width ?? preferred.width;
    var height = remembered?.height ?? preferred.height;

    // A default is capped; a remembered size is not, because it was chosen.
    if (remembered == null) {
      width = min(width, preferred.width);
      height = min(height, preferred.height);
    }

    // Rule two, and it applies to a remembered size as well — that is the whole
    // point of it.
    width = min(width, available.width * screenShare);
    height = min(height, available.height * screenShare);

    // A floor, except on a screen smaller than the floor, where the screen wins.
    width = max(width, min(minimum.width, available.width));
    height = max(height, min(minimum.height, available.height));

    return Size(width.roundToDouble(), height.roundToDouble());
  }

  /// Whether a size is worth storing.
  ///
  /// A minimised or collapsed window reports something near zero, and writing
  /// that down would be remembering a window nobody can use.
  static bool worthRemembering(Size size) =>
      size.width >= minimum.width * 0.9 && size.height >= minimum.height * 0.9;
}
