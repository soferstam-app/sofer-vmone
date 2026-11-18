import '../models.dart';

/// A historical snapshot, never filled from the current project when reading
/// an old session. Missing data is distinct from a measured zero.
class WritingConditions {
  static const key = 'writingConditions';
  final String company;
  final String processing;
  final double? heightMm;
  final double? temperatureC;
  final double? humidity;
  const WritingConditions(
      {this.company = '',
      this.processing = '',
      this.heightMm,
      this.temperatureC,
      this.humidity});

  factory WritingConditions.fromJson(Object? raw) {
    final data = raw is Map ? raw : const {};
    double? number(String key, double min, double max) {
      final value = data[key];
      if (value is! num || !value.isFinite || value < min || value > max) {
        return null;
      }
      return value.toDouble();
    }

    return WritingConditions(
      company:
          data['company'] is String ? (data['company'] as String).trim() : '',
      processing: const {'hand', 'machine'}.contains(data['processing'])
          ? '${data['processing']}'
          : '',
      heightMm: number('heightMm', 0.1, 100),
      temperatureC: number('temperatureC', -40, 80),
      humidity: number('humidity', 0, 100),
    );
  }
  factory WritingConditions.project(Project p) =>
      WritingConditions.fromJson(p.extraFields[key]);
  factory WritingConditions.session(WorkSession s) =>
      WritingConditions.fromJson(s.extraFields[key]);
  Map<String, dynamic> toJson() => {
        'version': 1,
        'company': company.trim(),
        'processing': processing,
        if (heightMm != null) 'heightMm': heightMm,
        if (temperatureC != null) 'temperatureC': temperatureC,
        if (humidity != null) 'humidity': humidity,
      };
  Project applyToProject(Project p) =>
      p.copyWith(extraFields: {...p.extraFields, key: toJson()});
  WorkSession stamp(WorkSession s) =>
      s.copyWith(extraFields: {...s.extraFields, key: toJson()});
}
