import 'package:cloud_firestore/cloud_firestore.dart';

class AttachmentRef {
  final String url;
  final String name;
  final String contentType;
  final int sizeBytes;
  final String storagePath;
  final String uploaderUid;
  final String uploaderName;
  final DateTime uploadedAt;

  AttachmentRef({
    required this.url,
    required this.name,
    required this.contentType,
    required this.sizeBytes,
    required this.storagePath,
    required this.uploaderUid,
    required this.uploaderName,
    required this.uploadedAt,
  });

  factory AttachmentRef.fromMap(Map<String, dynamic> map) {
    return AttachmentRef(
      url: map['url'] ?? '',
      name: map['name'] ?? '',
      contentType: map['content_type'] ?? 'application/octet-stream',
      sizeBytes: (map['size_bytes'] ?? 0) is int
          ? map['size_bytes']
          : int.tryParse('${map['size_bytes']}') ?? 0,
      storagePath: map['storage_path'] ?? '',
      uploaderUid: map['uploader_uid'] ?? '',
      uploaderName: map['uploader_name'] ?? '',
      uploadedAt: _fromTs(map['uploaded_at']) ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'url': url,
      'name': name,
      'content_type': contentType,
      'size_bytes': sizeBytes,
      'storage_path': storagePath,
      'uploader_uid': uploaderUid,
      'uploader_name': uploaderName,
      'uploaded_at': Timestamp.fromDate(uploadedAt),
    };
  }

  static DateTime? _fromTs(dynamic v) {
    if (v == null) return null;
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    return null;
  }
}
