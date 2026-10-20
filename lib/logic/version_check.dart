/// Comparing the running version against the newest published one.
///
/// The whole of the update feature that can be wrong without anyone noticing.
/// Compared as text, "0.10.0" is *older* than "0.9.0" — because '1' sorts
/// before '9' — so a writer would be told they were up to date for every
/// release after the ninth. Nothing on the way to the screen would have caught
/// it, and the failure only begins months after the code is written.
class Version implements Comparable<Version> {
  final int major;
  final int minor;
  final int patch;

  const Version(this.major, this.minor, this.patch);

  /// Reads a release tag. Null when it is not a version.
  ///
  /// Tolerates a leading `v`, which half the world writes and half does not.
  /// Refuses anything else — this repository has a tag called `APP`, and a tag
  /// nobody can parse must be ignored rather than guessed at: guessing puts a
  /// wrong answer in front of the writer, ignoring puts none.
  static Version? tryParse(String tag) {
    var text = tag.trim();
    if (text.startsWith('v') || text.startsWith('V')) text = text.substring(1);

    // A pre-release suffix — 0.5.0-beta.2 — is not part of the ordering here.
    // Those releases are filtered out before this by the `prerelease` flag.
    final dash = text.indexOf(RegExp(r'[-+]'));
    if (dash >= 0) text = text.substring(0, dash);

    final parts = text.split('.');
    if (parts.isEmpty || parts.length > 3) return null;

    final numbers = <int>[];
    for (final part in parts) {
      final n = int.tryParse(part);
      if (n == null || n < 0) return null;
      numbers.add(n);
    }
    // "1.2" means 1.2.0, which is what a person writing it means.
    while (numbers.length < 3) {
      numbers.add(0);
    }
    return Version(numbers[0], numbers[1], numbers[2]);
  }

  @override
  int compareTo(Version other) {
    if (major != other.major) return major.compareTo(other.major);
    if (minor != other.minor) return minor.compareTo(other.minor);
    return patch.compareTo(other.patch);
  }

  bool isNewerThan(Version other) => compareTo(other) > 0;

  @override
  bool operator ==(Object other) => other is Version && compareTo(other) == 0;

  @override
  int get hashCode => Object.hash(major, minor, patch);

  @override
  String toString() => '$major.$minor.$patch';
}

/// The two platforms for which this project publishes installable artifacts.
enum UpdatePlatform { android, windows }

extension UpdatePlatformLabel on UpdatePlatform {
  String get hebrewName => switch (this) {
        UpdatePlatform.android => 'Android',
        UpdatePlatform.windows => 'Windows',
      };

  String assetName(Version version) => switch (this) {
        UpdatePlatform.android => 'sofer-vmone-$version-android.apk',
        UpdatePlatform.windows => 'sofer-vmone-$version-windows.zip',
      };
}

/// The exact release file that may be downloaded and installed.
///
/// A page link is not an update. The file name chooses the platform, the size
/// catches truncated downloads, and GitHub's SHA-256 digest makes corruption
/// a hard failure before any downloaded code is allowed to run.
final class ReleaseAsset {
  final String name;
  final Uri downloadUrl;
  final int size;
  final String sha256Hex;

  const ReleaseAsset({
    required this.name,
    required this.downloadUrl,
    required this.size,
    required this.sha256Hex,
  });
}

/// What a check came to.
sealed class UpdateStatus {
  const UpdateStatus();
}

/// Nothing newer has been published.
final class UpToDate extends UpdateStatus {
  final Version running;
  const UpToDate(this.running);
}

/// There is a newer release and a verifiable artifact for this platform.
final class UpdateAvailable extends UpdateStatus {
  final Version version;
  final String pageUrl;
  final DateTime? publishedAt;
  final ReleaseAsset asset;

  const UpdateAvailable({
    required this.version,
    required this.pageUrl,
    required this.asset,
    this.publishedAt,
  });
}

/// The check could not be made, or its answer could not be read.
///
/// Not an error to push at anyone. A good part of this app's audience is behind
/// content filtering that may block the API outright, so failing is ordinary
/// and has to read as "could not check" rather than as something being wrong.
final class UpdateCheckFailed extends UpdateStatus {
  final String reason;
  const UpdateCheckFailed(this.reason);
}

/// Reads GitHub's "latest release" answer.
///
/// Pure: what arrives over the network is the caller's problem, and everything
/// that decides what the writer is told happens here where it can be checked.
UpdateStatus readLatestRelease({
  required Map<String, dynamic> json,
  required Version running,
  required UpdatePlatform platform,
  bool english = false,
}) {
  // A draft is not published, and a pre-release was not meant for whoever
  // happens to press the button. GitHub's `/latest` already excludes both, but
  // it is one flag away from not doing so and the cost of checking is nothing.
  if (json['draft'] == true) {
    return UpdateCheckFailed(
        english ? 'The release is not published' : 'גרסה לא פורסמה');
  }
  if (json['prerelease'] == true) return UpToDate(running);

  final tag = json['tag_name'];
  if (tag is! String) {
    return UpdateCheckFailed(english
        ? 'The response has no version number'
        : 'אין מספר גרסה בתשובה');
  }

  final latest = Version.tryParse(tag);
  if (latest == null) {
    return UpdateCheckFailed(
        english ? 'Unrecognized version: $tag' : 'גרסה לא מזוהה: $tag');
  }

  if (!latest.isNewerThan(running)) return UpToDate(running);

  final expectedName = platform.assetName(latest);
  final rawAssets = json['assets'];
  if (rawAssets is! List) {
    return UpdateCheckFailed(english
        ? 'Version $latest was published without an installation-file list'
        : 'גרסה $latest פורסמה בלי רשימת קובצי התקנה');
  }

  Map<dynamic, dynamic>? rawAsset;
  for (final candidate in rawAssets) {
    if (candidate is Map && candidate['name'] == expectedName) {
      rawAsset = candidate;
      break;
    }
  }
  if (rawAsset == null) {
    return UpdateCheckFailed(english
        ? 'Version $latest was published without an installation file for ${platform.hebrewName}'
        : 'גרסה $latest פורסמה בלי קובץ התקנה ל־${platform.hebrewName}');
  }

  final size = rawAsset['size'];
  if (size is! int || size <= 0) {
    return UpdateCheckFailed(english
        ? 'Update file $expectedName is empty or invalid'
        : 'קובץ העדכון $expectedName ריק או לא תקין');
  }

  final rawUrl = rawAsset['browser_download_url'];
  final downloadUrl = rawUrl is String ? Uri.tryParse(rawUrl) : null;
  if (downloadUrl == null || downloadUrl.scheme != 'https') {
    return UpdateCheckFailed(english
        ? 'Update file $expectedName has no secure download link'
        : 'לקובץ העדכון $expectedName אין קישור מאובטח');
  }

  final rawDigest = rawAsset['digest'];
  final digestMatch = rawDigest is String
      ? RegExp(r'^sha256:([0-9a-fA-F]{64})$').firstMatch(rawDigest)
      : null;
  if (digestMatch == null) {
    return UpdateCheckFailed(english
        ? 'Update file $expectedName has no SHA-256 value for verification'
        : 'לקובץ העדכון $expectedName אין ערך SHA-256 לאימות');
  }

  final asset = ReleaseAsset(
    name: expectedName,
    downloadUrl: downloadUrl,
    size: size,
    sha256Hex: digestMatch.group(1)!.toLowerCase(),
  );

  final url = json['html_url'];
  return UpdateAvailable(
    version: latest,
    pageUrl: url is String && url.isNotEmpty
        ? url
        : 'https://github.com/soferstam-app/sofer-vmone/releases',
    asset: asset,
    publishedAt: json['published_at'] is String
        ? DateTime.tryParse(json['published_at'] as String)
        : null,
  );
}
