/// The app's version and build number, as the About block shows them
/// (`specs/08-settings-about.md:63`).
///
/// **These are constants mirroring `pubspec.yaml`, not a `package_info_plus`
/// lookup, and that is a deliberate trade.** The plugin reads the version out of
/// the *installed bundle*, which is strictly more correct — it would follow a
/// `flutter build --build-name`/`--build-number` override that these constants
/// cannot see. What it costs is that the value only exists on a device: in a
/// widget test the plugin answers through a mocked platform channel, so a test
/// of the About block would be asserting its own mock and would keep passing
/// through any regression that stopped the screen rendering a version at all.
/// This loop has no device (the HUMAN-GATED toolchain item), so that trade buys
/// nothing and hides the one thing worth pinning.
///
/// The drift these constants invite — someone bumps `pubspec.yaml` and the
/// About block keeps showing the old number — is the realistic failure, and it
/// is closed by `app_version_test.dart`, which parses `pubspec.yaml` and fails
/// on any disagreement. The failure that stays open is a release built with an
/// explicit `--build-number`; see the follow-up item in `IMPLEMENTATION_PLAN.md`
/// for when that becomes real.
abstract final class AppVersion {
  /// `version:`'s left half in `pubspec.yaml` — the marketing version, shown to
  /// a grown-up who is about to describe a bug to someone.
  static const String name = '1.0.0';

  /// `version:`'s right half, after the `+`. Meaningless to a human on its own,
  /// which is why it renders in parentheses behind [name] rather than beside it.
  static const String build = '2';

  /// The one string the About block renders. Named rather than composed at the
  /// call site so the format is pinned in one place and by one test.
  static const String display = 'Rockimals $name (build $build)';
}
