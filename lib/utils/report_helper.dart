import 'dart:io';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
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
    return await showDateRangePicker(
      context: context,
      initialDateRange: initialRange,
      firstDate: firstDate ?? DateTime(2020),
      lastDate: lastDate ?? DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) => _buildPickerTheme(context, child, themeColor),
    );
  }

  /// Wraps the standard showDatePicker with the new UI theme
  static Future<DateTime?> showAppDatePicker(
    BuildContext context, 
    DateTime initialDate, 
    Color themeColor,
    {DateTime? firstDate, DateTime? lastDate}
  ) async {
    return await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: firstDate ?? DateTime(2020),
      lastDate: lastDate ?? DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) => _buildPickerTheme(context, child, themeColor),
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
