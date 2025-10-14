import 'dart:typed_data';

class AttachmentUpload {
  final Uint8List bytes;
  final String name; // filename with extension
  final String contentType; // e.g., image/jpeg, application/pdf, text/plain

  AttachmentUpload({
    required this.bytes,
    required this.name,
    required this.contentType,
  });
}
