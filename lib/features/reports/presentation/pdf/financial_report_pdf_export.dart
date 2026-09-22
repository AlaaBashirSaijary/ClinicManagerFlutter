import 'package:intl/intl.dart' hide TextDirection;
import 'package:pdf/widgets.dart' as pw;

import '../../../../core/pdf/pdf_kit.dart';
import '../../../visits/domain/entities/financial_report.dart';

/// Builds and presents (print/save/share) a one-page PDF of the financial
/// report already shown on screen — real amounts per visit, not just an
/// appointment-type count, so it can double as a paper record for the
/// doctor's own bookkeeping.
class FinancialReportPdfExport {
  const FinancialReportPdfExport._();

  static final _monthFormat = DateFormat('MMMM yyyy', 'ar');
  static final _dateFormat = DateFormat('yyyy/MM/dd');

  static Future<void> export({
    required String clinicName,
    required DateTime month,
    required FinancialReport report,
  }) async {
    final document = await PdfKit.newDocument();

    PdfKit.addPage(
      document,
      build: [
        PdfKit.header(
          clinicName: clinicName,
          title: 'التقرير المالي',
          subtitle: _monthFormat.format(month),
        ),
        pw.Table(
          border: pw.TableBorder.all(color: PdfBrand.sky, width: 1),
          columnWidths: const {
            0: pw.FlexColumnWidth(3),
            1: pw.FlexColumnWidth(1.4),
          },
          children: [
            _summaryRow('إجمالي الكشفيات', report.totalFees),
            _summaryRow('إجمالي المُحصَّل', report.totalCollected),
            _summaryRow('المتبقي غير المُحصَّل', report.totalRemaining),
            _summaryRow(
              'عدد الزيارات المُسعَّرة',
              report.pricedVisitCount.toDouble(),
              isCount: true,
            ),
          ],
        ),
        pw.SizedBox(height: 16),
        if (report.rows.isNotEmpty) ...[
          pw.Table(
            border: pw.TableBorder.all(color: PdfBrand.sky, width: 1),
            columnWidths: const {
              0: pw.FlexColumnWidth(2.2),
              1: pw.FlexColumnWidth(1.4),
              2: pw.FlexColumnWidth(1.2),
              3: pw.FlexColumnWidth(1.2),
            },
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfBrand.sky),
                children: [
                  _headerCell('المريض'),
                  _headerCell('التاريخ'),
                  _headerCell('الكشفية'),
                  _headerCell('المدفوع'),
                ],
              ),
              for (final row in report.rows)
                pw.TableRow(
                  children: [
                    _cell(row.patientName),
                    _cell(_dateFormat.format(row.visitDate)),
                    _cell(row.feeAmount.toStringAsFixed(0)),
                    _cell(row.amountPaid.toStringAsFixed(0)),
                  ],
                ),
            ],
          ),
        ],
      ],
    );

    await PdfKit.present(
      document,
      name: 'التقرير المالي - ${_monthFormat.format(month)}',
    );
  }

  static pw.TableRow _summaryRow(
    String label,
    double value, {
    bool isCount = false,
  }) {
    return pw.TableRow(
      children: [
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: pw.Text(
            label,
            style: pw.TextStyle(
              fontWeight: pw.FontWeight.bold,
              fontSize: 11,
              color: PdfBrand.ink,
            ),
          ),
        ),
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: pw.Text(
            isCount
                ? value.toStringAsFixed(0)
                : '${value.toStringAsFixed(0)} ل.س',
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(
              fontWeight: pw.FontWeight.bold,
              fontSize: 11,
              color: PdfBrand.aquaDeep,
            ),
          ),
        ),
      ],
    );
  }

  static pw.Widget _headerCell(String text) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    child: pw.Text(
      text,
      style: pw.TextStyle(
        fontWeight: pw.FontWeight.bold,
        fontSize: 10,
        color: PdfBrand.ink,
      ),
    ),
  );

  static pw.Widget _cell(String text) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    child: pw.Text(text, style: const pw.TextStyle(fontSize: 9.5)),
  );
}
