import 'dart:io';
import 'package:flutter/material.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:excel/excel.dart';
import 'package:printing/printing.dart';
import '../models/transaction_model.dart';
import 'package:intl/intl.dart';

class ReportHelper {
  // --- Standardized UI Date Pickers (UI ONLY) ---

  /// Wraps the standard showDateRangePicker with the new UI theme
  static Future<DateTimeRange?> showAppDateRangePicker(
    BuildContext context, 
    DateTimeRange? initialRange, 
    Color themeColor,
    {DateTime? firstDate, DateTime? lastDate}
  ) async {
    DateTimeRange selectedRange = initialRange ?? DateTimeRange(start: DateTime.now(), end: DateTime.now());
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor = isDark ? const Color(0xFF1A1D2D) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF2D3436);
    final secondaryTextColor = isDark ? Colors.white70 : const Color(0xFF636E72);

    return await showModalBottomSheet<DateTimeRange>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          decoration: BoxDecoration(
            color: surfaceColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 24), decoration: BoxDecoration(color: Colors.grey.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(2))),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('SELECT DATE RANGE', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: textColor, letterSpacing: 1)),
                  IconButton(onPressed: () => Navigator.pop(context), icon: Icon(Icons.close_rounded, color: textColor)),
                ],
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: _dateTile(
                      label: 'FROM',
                      date: selectedRange.start,
                      onTap: () async {
                        final d = await showDatePicker(
                          context: context,
                          initialDate: selectedRange.start,
                          firstDate: firstDate ?? DateTime(2020),
                          lastDate: selectedRange.end,
                          builder: (context, child) => _buildPickerTheme(context, child, themeColor),
                        );
                        if (d != null) setModalState(() => selectedRange = DateTimeRange(start: d, end: selectedRange.end));
                      },
                      themeColor: themeColor,
                      isDark: isDark,
                      textColor: textColor,
                      secondaryTextColor: secondaryTextColor,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Icon(Icons.arrow_forward_rounded, color: themeColor.withValues(alpha: 0.5), size: 16),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _dateTile(
                      label: 'TO',
                      date: selectedRange.end,
                      onTap: () async {
                        final d = await showDatePicker(
                          context: context,
                          initialDate: selectedRange.end,
                          firstDate: selectedRange.start,
                          lastDate: lastDate ?? DateTime.now(),
                          builder: (context, child) => _buildPickerTheme(context, child, themeColor),
                        );
                        if (d != null) setModalState(() => selectedRange = DateTimeRange(start: selectedRange.start, end: d));
                      },
                      themeColor: themeColor,
                      isDark: isDark,
                      textColor: textColor,
                      secondaryTextColor: secondaryTextColor,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _quickChip('Today', () => setModalState(() {
                    final now = DateTime.now();
                    selectedRange = DateTimeRange(start: DateTime(now.year, now.month, now.day), end: DateTime(now.year, now.month, now.day, 23, 59));
                  }), themeColor, isDark),
                  _quickChip('Yesterday', () => setModalState(() {
                    final d = DateTime.now().subtract(const Duration(days: 1));
                    selectedRange = DateTimeRange(start: DateTime(d.year, d.month, d.day), end: DateTime(d.year, d.month, d.day, 23, 59));
                  }), themeColor, isDark),
                  _quickChip('Last 7 Days', () => setModalState(() {
                    final end = DateTime.now();
                    final start = end.subtract(const Duration(days: 6));
                    selectedRange = DateTimeRange(start: DateTime(start.year, start.month, start.day), end: end);
                  }), themeColor, isDark),
                  _quickChip('This Month', () => setModalState(() {
                    final now = DateTime.now();
                    selectedRange = DateTimeRange(start: DateTime(now.year, now.month, 1), end: now);
                  }), themeColor, isDark),
                ],
              ),
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, selectedRange),
                style: ElevatedButton.styleFrom(
                  backgroundColor: themeColor,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 55),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                  elevation: 0,
                ),
                child: const Text('APPLY FILTER', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _dateTile({required String label, required DateTime date, required VoidCallback onTap, required Color themeColor, required bool isDark, required Color textColor, required Color secondaryTextColor}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withValues(alpha: 0.05) : const Color(0xFFF8F9FE),
          borderRadius: BorderRadius.circular(16),
          //border: Border.all(color: themeColor.withValues(alpha: 0.1)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: secondaryTextColor, letterSpacing: 1)),
            const SizedBox(height: 4),
            Text(DateFormat('dd MMM yyyy').format(date), style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: textColor)),
          ],
        ),
      ),
    );
  }

  static Widget _quickChip(String label, VoidCallback onTap, Color themeColor, bool isDark) {
    return ActionChip(
      label: Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
      onPressed: onTap,
      backgroundColor: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.white,
      side: BorderSide(color: themeColor.withValues(alpha: 0.1)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    );
  }

  /// Wraps the standard showDatePicker with a custom Bottom Sheet UI
  static Future<DateTime?> showAppDatePicker(
    BuildContext context, 
    DateTime initialDate, 
    Color themeColor,
    {DateTime? firstDate, DateTime? lastDate}
  ) async {
    DateTime selectedDate = initialDate;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor = isDark ? const Color(0xFF1A1D2D) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF2D3436);
    final secondaryTextColor = isDark ? Colors.white70 : const Color(0xFF636E72);

    return await showModalBottomSheet<DateTime>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          decoration: BoxDecoration(
            color: surfaceColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 20), decoration: BoxDecoration(color: Colors.grey.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(2))),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('SELECT DATE', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: textColor, letterSpacing: 1)),
                  IconButton(onPressed: () => Navigator.pop(context), icon: Icon(Icons.close_rounded, color: textColor)),
                ],
              ),
              const SizedBox(height: 10),
              Theme(
                data: Theme.of(context).copyWith(
                  colorScheme: isDark 
                    ? ColorScheme.dark(primary: themeColor, onPrimary: Colors.white, surface: surfaceColor, onSurface: textColor)
                    : ColorScheme.light(primary: themeColor, onPrimary: Colors.white, surface: surfaceColor, onSurface: textColor),
                ),
                child: CalendarDatePicker(
                  initialDate: selectedDate,
                  firstDate: firstDate ?? DateTime(2020),
                  lastDate: lastDate ?? DateTime.now().add(const Duration(days: 365)),
                  onDateChanged: (date) => setModalState(() => selectedDate = date),
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, selectedDate),
                style: ElevatedButton.styleFrom(
                  backgroundColor: themeColor,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 55),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                  elevation: 0,
                ),
                child: const Text('CONFIRM DATE', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
              ),
              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
    );
  }

  /// Centralized UI Theme for Pickers to match Purchase Reminder style
  static Widget _buildPickerTheme(BuildContext context, Widget? child, Color themeColor) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    
    final Color surfaceColor = isDark ? const Color(0xFF1A1D2D) : Colors.white;
    final Color scaffoldColor = isDark ? const Color(0xFF0F111A) : const Color(0xFFF8F9FE);
    final Color textColor = isDark ? Colors.white : const Color(0xFF2D3436);

    return Theme(
      data: Theme.of(context).copyWith(
        useMaterial3: true,
        colorScheme: isDark 
          ? ColorScheme.dark(
              primary: themeColor,
              onPrimary: Colors.white,
              surface: surfaceColor,
              onSurface: textColor,
              secondary: themeColor,
            )
          : ColorScheme.light(
              primary: themeColor,
              onPrimary: Colors.white,
              surface: surfaceColor,
              onSurface: textColor,
              secondary: themeColor,
            ),
        dialogBackgroundColor: scaffoldColor,
        dividerColor: Colors.transparent,
        datePickerTheme: DatePickerThemeData(
          backgroundColor: surfaceColor,
          headerBackgroundColor: isDark ? Colors.white.withValues(alpha: 0.05) : themeColor,
          headerForegroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
          dayStyle: const TextStyle(fontWeight: FontWeight.bold),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: themeColor,
            textStyle: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.5)
          ),
        ),
      ),
      child: child!,
    );
  }

  // --- Core Business Logic (KEEPING UNCHANGED) ---

  static Map<String, double> calculateStats(List<TransactionModel> transactions) {
    double income = 0;
    double expense = 0;
    for (var tx in transactions) {
      if (tx.type == 'sale') {
        income += tx.amount;
      } else {
        expense += tx.amount;
      }
    }
    return {'income': income, 'expense': expense};
  }

  static Future<void> generatePDF(BuildContext context, List<TransactionModel> transactions) async {
    try {
      final pdf = pw.Document();
      final dateStr = DateFormat('dd MMM yyyy').format(DateTime.now());

      pdf.addPage(
        pw.MultiPage(
          build: (context) => [
            pw.Header(level: 0, child: pw.Text('BUSINESS REPORT - $dateStr')),
            pw.TableHelper.fromTextArray(
              headers: ['Date', 'Category', 'Description', 'Amount', 'Mode'],
              data: transactions.map((tx) => [
                DateFormat('dd/MM').format(tx.date),
                tx.category,
                tx.description.replaceAll(' | Discount:', '\nDisc:'),
                '₹${tx.amount.toStringAsFixed(2)}',
                tx.paymentMode
              ]).toList(),
            ),
          ],
        ),
      );

      await Printing.layoutPdf(
        onLayout: (format) async => pdf.save(),
        name: 'Report_${DateTime.now().millisecondsSinceEpoch}.pdf',
      );
      
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error generating PDF: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  static Future<void> generateExcel(BuildContext context, List<TransactionModel> transactions) async {
    try {
      var excel = Excel.createExcel();
      Sheet sheetObject = excel['Report'];

      sheetObject.appendRow([
        TextCellValue('Date'),
        TextCellValue('Type'),
        TextCellValue('Category'),
        TextCellValue('Description'),
        TextCellValue('Amount'),
        TextCellValue('Paid'),
        TextCellValue('Mode'),
      ]);

      for (var tx in transactions) {
        sheetObject.appendRow([
          TextCellValue(DateFormat('dd-MM-yyyy').format(tx.date)),
          TextCellValue(tx.type),
          TextCellValue(tx.category),
          TextCellValue(tx.description),
          DoubleCellValue(tx.amount),
          DoubleCellValue(tx.paidAmount),
          TextCellValue(tx.paymentMode),
        ]);
      }

      Directory? directory;
      if (Platform.isAndroid) {
        directory = Directory('/storage/emulated/0/Download');
        if (!await directory.exists()) {
          directory = await getExternalStorageDirectory();
        }
      } else {
        directory = await getApplicationDocumentsDirectory();
      }

      if (directory == null) return;
      
      final fileName = "Business_Report_${DateTime.now().millisecondsSinceEpoch}.xlsx";
      final path = "${directory.path}/$fileName";
      final fileBytes = excel.encode();
      
      if (fileBytes != null) {
        File(path)
          ..createSync(recursive: true)
          ..writeAsBytesSync(fileBytes);
          
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Excel saved in Downloads: $fileName'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 5),
              action: SnackBarAction(label: 'OK', textColor: Colors.white, onPressed: () {}),
            ),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving Excel: $e. Try checking storage permissions.'), backgroundColor: Colors.red),
        );
      }
    }
  }

  static String getCleanItems(TransactionModel tx) {
    final items = tx.parsedItems;
    if (items.isEmpty) return tx.category;
    return items.map((i) {
      double q = double.tryParse(i['qty'] ?? '0') ?? 0;
      String qStr = q % 1 == 0 ? q.toInt().toString() : q.toString();
      String suffix = i['variant']?.toLowerCase() == 'half' ? " (Half)" : "";
      return "${i['name']}$suffix x$qStr";
    }).join(", ");
  }
}
