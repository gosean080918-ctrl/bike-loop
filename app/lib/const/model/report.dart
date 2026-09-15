/// 방치 자전거 신고 (supabase/01_schema.sql reports 테이블과 1:1)
class Report {
  final String id;
  final String reporterId;
  final String photoPath; // Storage 경로 (photo_url 컬럼) - 표시할 땐 signed URL 생성
  final double lat;
  final double lng;
  final String? address;
  final String condition; // kConditionLabels 키 (5종)
  final String description;
  final String status; // kStatusLabels 키
  final String? duplicateOf;
  final int priority;
  final DateTime reportedAt;
  final DateTime? collectedAt;
  final String? jobId;

  const Report({
    required this.id,
    required this.reporterId,
    required this.photoPath,
    required this.lat,
    required this.lng,
    this.address,
    required this.condition,
    this.description = '',
    required this.status,
    this.duplicateOf,
    this.priority = 0,
    required this.reportedAt,
    this.collectedAt,
    this.jobId,
  });

  factory Report.fromMap(Map<String, dynamic> m) => Report(
        id: m['id'] as String,
        reporterId: m['reporter_id'] as String? ?? '',
        photoPath: m['photo_url'] as String? ?? '',
        lat: (m['lat'] as num).toDouble(),
        lng: (m['lng'] as num).toDouble(),
        address: m['address'] as String?,
        condition: m['condition'] as String? ?? 'other',
        description: m['description'] as String? ?? '',
        status: m['status'] as String? ?? 'submitted',
        duplicateOf: m['duplicate_of'] as String?,
        priority: (m['priority'] as num?)?.toInt() ?? 0,
        reportedAt: DateTime.parse(m['reported_at'] as String).toLocal(),
        collectedAt: m['collected_at'] == null
            ? null
            : DateTime.parse(m['collected_at'] as String).toLocal(),
        jobId: m['job_id'] as String?,
      );

  /// insert용 (id/status/reported_at은 DB 기본값 사용)
  static Map<String, dynamic> insertMap({
    required String reporterId,
    required String photoPath,
    required double lat,
    required double lng,
    required String condition,
    required String description,
    String? address,
  }) =>
      {
        'reporter_id': reporterId,
        'photo_url': photoPath,
        'lat': lat,
        'lng': lng,
        'condition': condition,
        'description': description,
        'address': address,
      };
}

/// 중복 확인 RPC(find_nearby_reports) 결과 행
class NearbyReport {
  final String id;
  final double lat;
  final double lng;
  final String condition;
  final String status;
  final double distanceM;

  const NearbyReport({
    required this.id,
    required this.lat,
    required this.lng,
    required this.condition,
    required this.status,
    required this.distanceM,
  });

  factory NearbyReport.fromMap(Map<String, dynamic> m) => NearbyReport(
        id: m['id'] as String,
        lat: (m['lat'] as num).toDouble(),
        lng: (m['lng'] as num).toDouble(),
        condition: m['condition'] as String? ?? 'other',
        status: m['status'] as String? ?? 'submitted',
        distanceM: (m['distance_m'] as num).toDouble(),
      );
}
