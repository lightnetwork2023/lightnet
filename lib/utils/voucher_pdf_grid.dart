import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

class VoucherPdfGrid {
  static const _brandGreen = PdfColor(0.106, 0.369, 0.125);
  static const _brandLight = PdfColor(0.22, 0.61, 0.29);

  static Future<Uint8List> build(
    List<dynamic> items, {
    PdfPageFormat pageFormat = PdfPageFormat.a4,
    String location = '',
  }) async {
    final doc = pw.Document();
    const int perPage = 40;
    const int columns = 5;
    const int rows = 8;
    const double gap = 5.0;
    const double margin = 14.0;

    final int total = items.length;
    int pageNum = 0;
    int i = 0;

    while (i < total) {
      pageNum++;
      final end = (i + perPage) > total ? total : (i + perPage);
      final chunk = List<dynamic>.from(items.sublist(i, end));
      while (chunk.length < perPage) chunk.add(null);

      doc.addPage(
        pw.Page(
          pageFormat: pageFormat,
          margin: const pw.EdgeInsets.all(margin),
          build: (context) {
            final availW = context.page.pageFormat.availableWidth;
            final availH = context.page.pageFormat.availableHeight - 26;
            final tileW = (availW - (columns - 1) * gap) / columns;
            final tileH = (availH - (rows - 1) * gap) / rows;

            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                // ── Page header ──────────────────────────────────────────
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Row(children: [
                      pw.Container(
                        width: 10, height: 10,
                        decoration: const pw.BoxDecoration(
                          color: _brandGreen,
                          shape: pw.BoxShape.circle,
                        ),
                      ),
                      pw.SizedBox(width: 5),
                      pw.Text(
                        'LIGHTNET${location.isNotEmpty ? "  ·  $location" : ""}',
                        style: pw.TextStyle(
                          fontSize: 10, color: _brandGreen,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                    ]),
                    pw.Text(
                      'WiFi Vouchers  |  $total vouchers  |  Page $pageNum / ${((total - 1) ~/ perPage) + 1}',
                      style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey600),
                    ),
                  ],
                ),
                pw.SizedBox(height: 3),
                pw.Container(height: 1, color: _brandGreen),
                pw.SizedBox(height: 6),

                // ── Voucher grid ─────────────────────────────────────────
                pw.Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: List.generate(perPage, (idx) {
                    final data = chunk[idx];
                    if (data == null) {
                      return pw.Container(width: tileW, height: tileH);
                    }
                    final username = data['username']?.toString() ?? '';
                    final speed = data['speed_limit']?.toString() ?? 'No limit';
                    final secs = int.tryParse(data['session_timeout']?.toString() ?? '');
                    final days = secs == null ? null : ((secs + 86399) ~/ 86400);
                    final validity = days == null ? 'N/A' : (days == 1 ? '1 Day' : '$days Days');

                    return pw.Container(
                      width: tileW,
                      height: tileH,
                      decoration: pw.BoxDecoration(
                        border: pw.Border.all(color: PdfColors.grey300, width: 0.8),
                        borderRadius: pw.BorderRadius.circular(5),
                        boxShadow: [
                          const pw.BoxShadow(color: PdfColors.grey200, blurRadius: 2, offset: PdfPoint(1, 1)),
                        ],
                      ),
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                        children: [
                          // Brand bar
                          pw.Container(
                            decoration: const pw.BoxDecoration(
                              color: _brandGreen,
                              borderRadius: pw.BorderRadius.only(
                                topLeft: pw.Radius.circular(4),
                                topRight: pw.Radius.circular(4),
                              ),
                            ),
                            padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
                            child: pw.Text(
                              'LIGHTNET WIFI',
                              style: pw.TextStyle(
                                color: PdfColors.white,
                                fontSize: 6,
                                fontWeight: pw.FontWeight.bold,
                                letterSpacing: 1,
                              ),
                              textAlign: pw.TextAlign.center,
                            ),
                          ),
                          // Code + details
                          pw.Expanded(
                            child: pw.Padding(
                              padding: const pw.EdgeInsets.fromLTRB(5, 4, 5, 4),
                              child: pw.Column(
                                mainAxisAlignment: pw.MainAxisAlignment.center,
                                children: [
                                  pw.Text(
                                    username,
                                    style: pw.TextStyle(
                                      fontSize: 13,
                                      fontWeight: pw.FontWeight.bold,
                                    ),
                                    textAlign: pw.TextAlign.center,
                                    maxLines: 1,
                                  ),
                                  pw.SizedBox(height: 5),
                                  pw.Container(height: 0.5, color: PdfColors.grey300),
                                  pw.SizedBox(height: 4),
                                  pw.Row(
                                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                                    children: [
                                      pw.Column(
                                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                                        children: [
                                          pw.Text('Speed',
                                              style: const pw.TextStyle(fontSize: 5.5, color: PdfColors.grey600)),
                                          pw.Text(speed,
                                              style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: _brandLight)),
                                        ],
                                      ),
                                      pw.Column(
                                        crossAxisAlignment: pw.CrossAxisAlignment.end,
                                        children: [
                                          pw.Text('Valid',
                                              style: const pw.TextStyle(fontSize: 5.5, color: PdfColors.grey600)),
                                          pw.Text(validity,
                                              style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
                                        ],
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ),
              ],
            );
          },
        ),
      );
      i = end;
    }

    return doc.save();
  }
}
