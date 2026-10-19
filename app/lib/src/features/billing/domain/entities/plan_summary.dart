/// What one tier includes, as the backend enforces it — screen 1S.
///
/// Sent by `list_products` from `billing.ENTITLEMENTS`, the same table every
/// limit is checked against. The design writes its plan lines out by hand
/// ("15 GB · 100 asks a month") and those are not this product's numbers;
/// reading them from the server means the paywall can only ever describe
/// what the backend will actually do, and a change to the table reaches the
/// paywall with the deploy that makes it.
class PlanSummary {
  const PlanSummary({
    this.memoryWindowDays,
    this.indexBytes,
    this.fileBytes,
    this.connectedAccounts,
    this.windowQueries,
    this.windowHours = 2,
    this.weeklyQueries,
  });

  factory PlanSummary.fromJson(Map<Object?, Object?> json) => PlanSummary(
    memoryWindowDays: (json['memoryWindowDays'] as num?)?.toInt(),
    indexBytes: (json['indexBytes'] as num?)?.toInt(),
    fileBytes: (json['fileBytes'] as num?)?.toInt(),
    connectedAccounts: (json['connectedAccounts'] as num?)?.toInt(),
    windowQueries: (json['windowQueries'] as num?)?.toInt(),
    windowHours: (json['windowHours'] as num?)?.toInt() ?? 2,
    weeklyQueries: (json['weeklyQueries'] as num?)?.toInt(),
  );

  /// Days a memory stays searchable. Null = forever.
  final int? memoryWindowDays;

  /// Index ceiling. Null = none.
  final int? indexBytes;

  /// Kept-file allowance. Null = none.
  final int? fileBytes;

  /// Null = any number.
  final int? connectedAccounts;

  /// Answers per [windowHours], each coming back that long after it was
  /// used. Null = no limit.
  final int? windowQueries;
  final int windowHours;

  /// Answers per week. Null = no limit.
  final int? weeklyQueries;

  bool get keepsForever => memoryWindowDays == null;

  /// "10 answers every 2 hours". Searching is not limited on any plan.
  String get answersPerWindow => switch (windowQueries) {
    null => 'unlimited answers',
    1 => '1 answer every $windowHours hours',
    final n => '$n answers every $windowHours hours',
  };

  /// "10 answers every 2 hours", for the selected card. One line at the
  /// card's width — a wrapped tick pushed the plan below under the pinned
  /// button on a 402-point phone. The weekly cap is shown where it can bite:
  /// the profile meter and the limit sheet.
  String get answersLine => _capitalised(answersPerWindow);

  static String _capitalised(String s) =>
      '${s[0].toUpperCase()}${s.substring(1)}';

  /// "Memories kept forever" / "Memories kept a year" / "…30 days".
  String get memoryLine => switch (memoryWindowDays) {
    null => 'Memories kept forever',
    365 => 'Memories kept a year',
    final days => 'Memories kept $days days',
  };

  /// "256 GB, every account" — storage and reach share a line so the card
  /// stays at three one-line ticks.
  String get indexLine {
    final bytes = indexBytes;
    final index = bytes == null ? 'Unlimited index' : allowance(bytes);
    final accounts = switch (connectedAccounts) {
      null => 'every account',
      1 => 'one account',
      final n => 'up to $n accounts',
    };
    return '$index, $accounts';
  }

  /// The ticks on a selected plan's card, in the design's order: how long,
  /// how much you can ask, how much it holds.
  List<String> get features => [memoryLine, answersLine, indexLine];

  /// One line for an unselected card — "2 GB · 2 answers every 2 hours ·
  /// 30-day memory".
  String get summary => [
    if (indexBytes case final bytes?) allowance(bytes),
    answersPerWindow,
    switch (memoryWindowDays) {
      null => 'memory forever',
      365 => '1-year memory',
      final days => '$days-day memory',
    },
  ].join(' · ');

  /// A plan allowance, which is always a round number: "2 GB", "1 TB".
  ///
  /// Not the file-size formatter. That one keeps a decimal below ten ("8.2
  /// GB") because a file's size is measured; an allowance is chosen, and
  /// "2.0 GB" on a price card reads like a measurement of something.
  static String allowance(int bytes) {
    const gib = 1024 * 1024 * 1024;
    const tib = gib * 1024;
    String whole(double v) =>
        v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
    if (bytes >= tib) return '${whole(bytes / tib)} TB';
    if (bytes >= gib) return '${whole(bytes / gib)} GB';
    return '${whole(bytes / (1024 * 1024))} MB';
  }
}
