import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

class VoucherPdfGrid {
  static Future<Uint8List> build(
    List<dynamic> items, {
    PdfPageFormat pageFormat = PdfPageFormat.a4,
  }) async {
    final doc = pw.Document();

    const int perPage = 40;
    const int columns = 5;
    const int rows = 8;
    const double gap = 6.0;
    const double margin = 16.0;

    int i = 0;
    while (i < items.length) {
      final end = (i + perPage) > items.length ? items.length : (i + perPage);
      final chunk = List<dynamic>.from(items.sublist(i, end));
      while (chunk.length < perPage) {
        chunk.add(null);
      }

      doc.addPage(
        pw.Page(
          pageFormat: pageFormat,
          margin: const pw.EdgeInsets.all(margin),
          build: (context) {
            final availableWidth = context.page.pageFormat.availableWidth - (margin - 0) * 0;
            final availableHeight = context.page.pageFormat.availableHeight - (margin - 0) * 0;
            final tileWidth = (availableWidth - (columns - 1) * gap) / columns;
            final tileHeight = (availableHeight - (rows - 1) * gap) / rows;

            return pw.Wrap(
              spacing: gap,
              runSpacing: gap,
              children: List.generate(perPage, (index) {
                final data = chunk[index];
                final String username = data == null
                    ? ''
                    : (data['username']?.toString() ?? '');
                final String speed = data == null
                    ? ''
                    : (data['speed_limit']?.toString() ?? 'No limit');
                final int? seconds = data == null || data['session_timeout'] == null
                    ? null
                    : int.tryParse(data['session_timeout'].toString());
                final int days = seconds == null
                    ? -1
                    : ((seconds + 86399) ~/ 86400);
                final String daysText = seconds == null ? 'N/A' : '$days days';

                return pw.Container(
                  width: tileWidth,
                  height: tileHeight,
                  padding: const pw.EdgeInsets.all(8),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.black, width: 1),
                    borderRadius: pw.BorderRadius.circular(4),
                  ),
                  child: data == null
                      ? pw.SizedBox()
                      : pw.Column(
                          mainAxisAlignment: pw.MainAxisAlignment.center,
                          crossAxisAlignment: pw.CrossAxisAlignment.center,
                          children: [
                            pw.Text(
                              username,
                              style: pw.TextStyle(
                                fontSize: 18,
                                fontWeight: pw.FontWeight.bold,
                              ),
                              textAlign: pw.TextAlign.center,
                            ),
                            pw.SizedBox(height: 6),
                            pw.Text(
                              speed,
                              style: const pw.TextStyle(fontSize: 10),
                              textAlign: pw.TextAlign.center,
                            ),
                            pw.SizedBox(height: 4),
                            pw.Text(
                              daysText,
                              style: const pw.TextStyle(fontSize: 10),
                              textAlign: pw.TextAlign.center,
                            ),
                          ],
                        ),
                );
              }),
            );
          },
        ),
      );

      i = end;
    }

    return doc.save();
  }
}
