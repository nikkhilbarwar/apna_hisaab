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

      // This opens the native print/save dialog which is the most reliable way to save to storage in modern Android
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

      // Saving to Downloads/External storage
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
}
