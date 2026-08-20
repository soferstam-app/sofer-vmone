/// The one place the version number is written.
///
/// It was in three: pubspec.yaml and two "about" dialogs, hand-kept in step.
/// They had already drifted — the app said 0.3.0 for the whole of 0.4.0's
/// development, so the number a user would quote in a bug report was the wrong
/// one, and neither dialog would ever have said so.
///
/// version_test.dart reads pubspec.yaml and refuses to let this disagree with
/// it, which is what makes one place actually one place.
const String appVersion = '0.5.0';
