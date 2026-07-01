import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:excel/excel.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:printing/printing.dart';
import '../core/database/database_helper.dart';
import '../models/staff_model.dart';
import '../models/transaction_model.dart';
import '../models/item_model.dart';

import '../models/staff_model.dart';
import '../providers/staff_provider.dart';

class ExportService {
  Future<Directory> _getAppDirectory() async {
    Directory? baseDir;

    if (Platform.isAndroid) {
      // Use the public Documents folder for better visibility in File Manager
      baseDir = Directory('/storage/emulated/0/Documents');

      try {
        if (!await baseDir.exists()) {
          await baseDir.create(recursive: true);
        }
      } catch (e) {
        debugPrint("Documents folder access failed: $e");
        // Fallback to Downloads if Documents is restricted
        baseDir = Directory('/storage/emulated/0/Downloads');
        if (!await baseDir.exists()) {
          await baseDir.create(recursive: true);
        }
      }
    } else {
      // iOS and other platforms
      baseDir = await getApplicationDocumentsDirectory();
    }

    // Check if the base directory is public to use a clean name
    final isPublic = baseDir.path.contains('Documents') || baseDir.path.contains('Downloads');
    final folderName = isPublic ? 'Apna Hisaab' : '.ApnaHisaab';

    final appDir = Directory('${baseDir.path}/$folderName');
    if (!await appDir.exists()) {
      await appDir.create(recursive: true);
    }
    return appDir;
  }

  Future<Directory> _getReportDirectory() async {
    final appDir = await _getAppDirectory();
    final reportDir = Directory('${appDir.path}/Reports');
    if (!await reportDir.exists()) {
      await reportDir.create(recursive: true);
    }
    return reportDir;
  }

  Future<Directory> _getBackupDirectory() async {
    final appDir = await _getAppDirectory();
    final backupDir = Directory('${appDir.path}/Backups');
    if (!await backupDir.exists()) {
      await backupDir.create(recursive: true);
    }
    return backupDir;
  }

  Future<Directory> _getBillDirectory() async {
    final appDir = await _getAppDirectory();
    final billDir = Directory('${appDir.path}/Bills');
    if (!await billDir.exists()) {
      await billDir.create(recursive: true);
    }
    return billDir;
  }

  Future<Directory> _getKotDirectory() async {
    final appDir = await _getAppDirectory();
    final kotDir = Directory('${appDir.path}/KOTs');
    if (!await kotDir.exists()) {
      await kotDir.create(recursive: true);
    }
    return kotDir;
  }

  String _getCleanDescription(TransactionModel tx) {
    final items = tx.itemSnapshots;
    if (items.isEmpty) {
      // JSON hata kar saaf description nikaalein
      String cleanDesc = tx.description.replaceAll(RegExp(r'\[.*\]'), '').trim();
      if (cleanDesc.contains('|')) {
        cleanDesc = cleanDesc.split('|').first.trim();
      }
      return cleanDesc.isNotEmpty ? cleanDesc : tx.category;
    }
    return items.map((i) {
      String qtyStr = i.qty == 0.5 ? "Half" : (i.qty % 1 == 0 ? i.qty.toInt().toString() : i.qty.toString());
      return "${i.name} x$qtyStr".trim();
    }).join(", ");
  }

  /// Export transactions to Excel (XLSX)
  Future<void> exportToExcel(List<TransactionModel> transactions, String title) async {
    var excel = Excel.createExcel();
    Sheet sheetObject = excel['Sheet1'];

    CellStyle headerStyle = CellStyle(
      bold: true,
      italic: false,
      fontFamily: getFontFamily(FontFamily.Arial),
    );

    List<String> headers = ['Date', 'Bill No', 'Category', 'Items (Description)', 'Amount', 'Payment Mode', 'Contact'];
    for (var i = 0; i < headers.length; i++) {
      var cell = sheetObject.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0));
      cell.value = TextCellValue(headers[i]);
      cell.cellStyle = headerStyle;
    }

    for (var i = 0; i < transactions.length; i++) {
      var tx = transactions[i];
      int row = i + 1;
      sheetObject.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)).value = TextCellValue(DateFormat('yyyy-MM-dd HH:mm').format(tx.date));
      sheetObject.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row)).value = TextCellValue(tx.id?.toString() ?? '');
      sheetObject.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: row)).value = TextCellValue(tx.category);
      sheetObject.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: row)).value = TextCellValue(_getCleanDescription(tx));
      sheetObject.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: row)).value = DoubleCellValue(tx.amount);
      sheetObject.cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: row)).value = TextCellValue(tx.paymentMode);
      sheetObject.cell(CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: row)).value = TextCellValue(tx.customerContact);
    }

    try {
      final dir = await _getReportDirectory();
      final fileName = "${title.replaceAll(' ', '_')}_${DateFormat('ddMMM_HHmm').format(DateTime.now())}.xlsx";
      final path = "${dir.path}/$fileName";

      var fileBytes = excel.save();
      if (fileBytes != null) {
        File(path)
          ..createSync(recursive: true)
          ..writeAsBytesSync(fileBytes);
        await Share.shareXFiles([XFile(path)], text: '$title Report');
      }
    } catch (e) {
      debugPrint("Excel Export Error: $e");
    }
  }

  /// Export licenses to Excel (XLSX)
  Future<void> exportLicensesToExcel(List<Map<String, dynamic>> licenses) async {
    var excel = Excel.createExcel();
    Sheet sheetObject = excel['Licenses'];
    excel.delete('Sheet1');

    CellStyle headerStyle = CellStyle(
      bold: true,
      fontFamily: getFontFamily(FontFamily.Arial),
      backgroundColorHex: ExcelColor.fromHexString("#E0E0E0"),
    );

    List<String> headers = ['Restaurant', 'Owner', 'Phone', 'Key', 'Status', 'Plan', 'Price', 'Expiry', 'Registered', 'Device ID', 'Created At'];
    for (var i = 0; i < headers.length; i++) {
      var cell = sheetObject.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0));
      cell.value = TextCellValue(headers[i]);
      cell.cellStyle = headerStyle;
    }

    for (var i = 0; i < licenses.length; i++) {
      var data = licenses[i];
      int row = i + 1;
      sheetObject.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)).value = TextCellValue(data['restaurantName'] ?? '');
      sheetObject.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row)).value = TextCellValue(data['ownerName'] ?? '');
      sheetObject.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: row)).value = TextCellValue(data['phone'] ?? '');
      sheetObject.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: row)).value = TextCellValue(data['licenseKey'] ?? '');
      sheetObject.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: row)).value = TextCellValue(data['status'] ?? '');
      sheetObject.cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: row)).value = TextCellValue(data['planType'] ?? '');
      sheetObject.cell(CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: row)).value = IntCellValue(data['price'] ?? 0);
      sheetObject.cell(CellIndex.indexByColumnRow(columnIndex: 7, rowIndex: row)).value = TextCellValue(data['validTillFormatted'] ?? 'Lifetime');
      sheetObject.cell(CellIndex.indexByColumnRow(columnIndex: 8, rowIndex: row)).value = TextCellValue(data['activated'] == true ? 'Yes' : 'No');
      sheetObject.cell(CellIndex.indexByColumnRow(columnIndex: 9, rowIndex: row)).value = TextCellValue(data['activeDeviceId'] ?? '');

      String createdAt = '';
      if (data['createdAt'] != null && data['createdAt'] is Timestamp) {
        createdAt = DateFormat('yyyy-MM-dd HH:mm').format((data['createdAt'] as Timestamp).toDate());
      }
      sheetObject.cell(CellIndex.indexByColumnRow(columnIndex: 10, rowIndex: row)).value = TextCellValue(createdAt);
    }

    try {
      final dir = await _getReportDirectory();
      final fileName = "LicenseHistory_${DateFormat('ddMMM_HHmm').format(DateTime.now())}.xlsx";
      final path = "${dir.path}/$fileName";

      var fileBytes = excel.save();
      if (fileBytes != null) {
        File(path)
          ..createSync(recursive: true)
          ..writeAsBytesSync(fileBytes);
        await Share.shareXFiles([XFile(path)], text: 'License History Report');
      }
    } catch (e) {
      debugPrint("License Excel Export Error: $e");
    }
  }

  /// Generate a professional A4 Invoice for a License Purchase
  Future<void> generateLicenseInvoice(Map<String, dynamic> data) async {
    final pdf = pw.Document();

    // Header Branding
    final title = "CASH MEMO";
    final businessName = "APNA HISAAB";
    final tagline = "Professional Digital Solutions";
    final contactInfo = "PH: +91 9992256959 | Email: dev.grillerzone@gmail.com";

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (context) => pw.Padding(
          padding: const pw.EdgeInsets.all(30),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Header
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(businessName, style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900)),
                      pw.Text(tagline, style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
                      pw.Text(contactInfo, style: const pw.TextStyle(fontSize: 9)),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text(title, style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold, color: PdfColors.grey900)),
                      pw.Text("No: CM-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}", style: const pw.TextStyle(fontSize: 10)),
                      pw.Text("Date: ${DateFormat('dd-MM-yyyy').format(DateTime.now())}", style: const pw.TextStyle(fontSize: 10)),
                    ],
                  ),
                ],
              ),
              pw.SizedBox(height: 30),
              pw.Divider(thickness: 2, color: PdfColors.blue900),
              pw.SizedBox(height: 20),

              // Billing Details
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text("BILL TO:", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10, color: PdfColors.grey700)),
                        pw.SizedBox(height: 5),
                        pw.Text(data['restaurantName']?.toUpperCase() ?? "N/A", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14)),
                        pw.Text("Prop: ${data['ownerName'] ?? 'N/A'}", style: const pw.TextStyle(fontSize: 11)),
                        pw.Text("Contact: ${data['phone'] ?? 'N/A'}", style: const pw.TextStyle(fontSize: 11)),
                      ],
                    ),
                  ),
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Text("LICENSE STATUS:", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10, color: PdfColors.grey700)),
                        pw.SizedBox(height: 5),
                        pw.Text("ACTIVE", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12, color: PdfColors.green)),
                        pw.Text("Plan: ${data['planType']?.toUpperCase() ?? 'N/A'}", style: const pw.TextStyle(fontSize: 11)),
                        pw.Text("Expiry: ${data['validTillFormatted'] ?? 'Lifetime'}", style: const pw.TextStyle(fontSize: 11)),
                      ],
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 40),

              // Items Table
              pw.Table.fromTextArray(
                headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white),
                headerDecoration: const pw.BoxDecoration(color: PdfColors.blue900),
                cellAlignment: pw.Alignment.centerLeft,
                columnWidths: {
                  0: const pw.FlexColumnWidth(4),
                  1: const pw.FlexColumnWidth(2),
                  2: const pw.FlexColumnWidth(2),
                },
                headers: ['DESCRIPTION / LICENSE KEY', 'VALIDITY', 'AMOUNT'],
                data: [
                  [
                    "Software Subscription License\nKey: ${data['licenseKey']}",
                    "${data['validTillFormatted'] ?? 'Lifetime'}",
                    "INR ${data['price'] ?? 0}"
                  ],
                ],
              ),

              pw.SizedBox(height: 20),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.end,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Row(
                        children: [
                          pw.Text("Total Amount: ", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14)),
                          pw.Text("INR ${data['price'] ?? 0}", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 16, color: PdfColors.blue900)),
                        ],
                      ),
                      pw.Text("(Inclusive of all digital service taxes)", style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
                    ],
                  ),
                ],
              ),

              pw.Spacer(),

              // Footer
              pw.Divider(thickness: 1, color: PdfColors.grey400),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text("Terms & Conditions:", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
                      pw.Text("1. This is a digital subscription license.", style: const pw.TextStyle(fontSize: 8)),
                      pw.Text("2. License is locked to a single device.", style: const pw.TextStyle(fontSize: 8)),
                      pw.Text("3. No refunds after activation.", style: const pw.TextStyle(fontSize: 8)),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.center,
                    children: [
                      pw.SizedBox(height: 20),
                      pw.Text("Authorized Signatory", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                      pw.Text("Apna Hisaab (Digital)", style: const pw.TextStyle(fontSize: 8)),
                    ],
                  ),
                ],
              ),
              pw.SizedBox(height: 10),
              pw.Center(child: pw.Text("This is a computer generated cash memo and does not require a physical signature.", style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600))),
            ],
          ),
        ),
      ),
    );

    try {
      final pdfBytes = await pdf.save();
      final dir = await _getBillDirectory();
      final fileName = "CashMemo_${data['licenseKey']}_${DateFormat('ddMMM_HHmm').format(DateTime.now())}.pdf";
      final path = "${dir.path}/$fileName";
      final file = File(path);
      await file.writeAsBytes(pdfBytes);

      // Small delay to ensure sync
      await Future.delayed(const Duration(milliseconds: 300));

      // Show print layout
      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => pdfBytes,
        name: "CashMemo_${data['restaurantName']}",
      );

      // Also share the file for convenience
      await Share.shareXFiles([XFile(path)], text: 'Cash Memo for ${data['restaurantName']}');
    } catch (e) {
      debugPrint("Professional Cash Memo Error: $e");
    }
  }

  /// Export transactions to PDF Report
  Future<void> exportToPdf(List<TransactionModel> transactions, String title) async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        build: (context) => [
          pw.Header(level: 0, child: pw.Text(title, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 24))),
          pw.SizedBox(height: 20),
          pw.Table.fromTextArray(
            headers: ['Date', 'Category', 'Items', 'Amount', 'Mode'],
            data: transactions.map((tx) {
              String desc = _getCleanDescription(tx);
              return [
                DateFormat('dd-MM-yy').format(tx.date),
                tx.category,
                desc.length > 40 ? desc.substring(0, 37) + "..." : desc,
                tx.amount.toStringAsFixed(0),
                tx.paymentMode
              ];
            }).toList(),
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
            cellHeight: 30,
            cellAlignments: {
              0: pw.Alignment.centerLeft,
              1: pw.Alignment.centerLeft,
              2: pw.Alignment.centerLeft,
              3: pw.Alignment.centerRight,
              4: pw.Alignment.center,
            },
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 20),
            child: pw.Align(
              alignment: pw.Alignment.centerRight,
              child: pw.Text(
                'Grand Total: ${transactions.fold(0.0, (sum, tx) => sum + tx.amount).toStringAsFixed(2)}',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 18),
              ),
            ),
          ),
        ],
      ),
    );

    try {
      final dir = await _getReportDirectory();
      final fileName = "${title.replaceAll(' ', '_')}_${DateFormat('ddMMM_HHmm').format(DateTime.now())}.pdf";
      final path = "${dir.path}/$fileName";
      final file = File(path);
      final pdfBytes = await pdf.save();
      await file.writeAsBytes(pdfBytes);

      // Show print layout/preview
      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => pdfBytes,
        name: title,
      );

      await Share.shareXFiles([XFile(path)], text: '$title Report PDF');
    } catch (e) {
      debugPrint("PDF Export Error: $e");
    }
  }

  /// Generate a comprehensive PDF report including Sales and Expenses
  Future<void> generateFullReport(
    String businessName,
    List<TransactionModel> sales,
    List<TransactionModel> expenses,
    DateTimeRange range,
  ) async {
    final pdf = pw.Document();
    final totalSales = sales.fold(0.0, (sum, item) => sum + item.amount);
    final totalExpenses = expenses.fold(0.0, (sum, item) => sum + item.amount);
    final netProfit = totalSales - totalExpenses;

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (context) => [
          // Header
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(businessName.toUpperCase(),
                      style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900)),
                  pw.Text("Business Summary Report", style: const pw.TextStyle(fontSize: 12, color: PdfColors.grey700)),
                ],
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text("Period: ${DateFormat('dd MMM').format(range.start)} - ${DateFormat('dd MMM yyyy').format(range.end)}",
                      style: const pw.TextStyle(fontSize: 10)),
                  pw.Text("Generated: ${DateFormat('dd/MM/yy HH:mm').format(DateTime.now())}",
                      style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 20),
          pw.Divider(thickness: 1, color: PdfColors.grey400),
          pw.SizedBox(height: 20),

          // Financial Summary Cards
          pw.Row(
            children: [
              _buildSummaryBox("TOTAL SALES", totalSales, PdfColors.green700),
              pw.SizedBox(width: 20),
              _buildSummaryBox("TOTAL EXPENSES", totalExpenses, PdfColors.red700),
              pw.SizedBox(width: 20),
              _buildSummaryBox("NET PROFIT", netProfit, netProfit >= 0 ? PdfColors.blue700 : PdfColors.orange700),
            ],
          ),
          pw.SizedBox(height: 30),

          // Sales Section
          pw.Text("SALES TRANSACTIONS", style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900)),
          pw.SizedBox(height: 10),
          _buildTransactionTable(sales, PdfColors.green50),
          pw.SizedBox(height: 30),

          // Expenses Section
          pw.Text("EXPENSE TRANSACTIONS", style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900)),
          pw.SizedBox(height: 10),
          _buildTransactionTable(expenses, PdfColors.red50),

          pw.Spacer(),
          pw.Divider(thickness: 0.5),
          pw.Center(
            child: pw.Text("This report is digitally generated by Apna Hisaab - Professional Business Manager",
                style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
          ),
        ],
      ),
    );

    try {
      final pdfBytes = await pdf.save();
      final dir = await _getReportDirectory();
      final fileName = "FullReport_${DateFormat('ddMMM_HHmm').format(DateTime.now())}.pdf";
      final path = "${dir.path}/$fileName";
      final file = File(path);
      await file.writeAsBytes(pdfBytes);

      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => pdfBytes,
        name: "Full_Report_${businessName}",
      );
    } catch (e) {
      debugPrint("Full Report Error: $e");
    }
  }

  /// Export Audit Report (Item/Category Wise) to PDF
  Future<void> exportAuditReport({
    required String businessName,
    required String title,
    required double totalRevenue,
    required List<Map<String, dynamic>> history,
    required bool isItem,
    required DateTimeRange range,
  }) async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (context) => [
          // Header
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(businessName.toUpperCase(),
                      style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900)),
                  pw.Text(isItem ? "Item Audit Report" : "Category Audit Report",
                      style: const pw.TextStyle(fontSize: 12, color: PdfColors.grey700)),
                  pw.SizedBox(height: 4),
                  pw.Text("Period: ${DateFormat('dd/MM/yyyy').format(range.start)} - ${DateFormat('dd/MM/yyyy').format(range.end)}",
                      style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.grey800)),
                ],
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text("Generated: ${DateFormat('dd/MM/yy HH:mm').format(DateTime.now())}",
                      style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 20),
          pw.Divider(thickness: 1, color: PdfColors.grey400),
          pw.SizedBox(height: 10),

          // Audit Title & Summary
          pw.Container(
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              color: PdfColors.grey100,
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(title.toUpperCase(), style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
                    pw.Text("Total Transactions: ${history.length}", style: const pw.TextStyle(fontSize: 10)),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text("TOTAL REVENUE", style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900)),
                    pw.Text("Rs. ${totalRevenue.toStringAsFixed(2)}",
                        style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900)),
                  ],
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 20),

          // History Table
          pw.Table.fromTextArray(
            headers: ['Date', 'Time', 'Item/Category', 'Qty', 'Price', 'Extra', 'Total', 'Mode'],
            data: history.map((h) {
              String qLabel = h['qty'] == 0.5 ? "Half" : h['qty'].toString();
              String extra = (h['extraQty'] > 0) ? "+${h['extraQty']}@${h['extraPrice']}" : "-";
              return [
                h['date'],
                h['time'],
                h['name'],
                qLabel,
                h['price'].toStringAsFixed(0),
                extra,
                h['total'].toStringAsFixed(0),
                h['mode']
              ];
            }).toList(),
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9, color: PdfColors.white),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.blue900),
            cellStyle: const pw.TextStyle(fontSize: 8),
            cellHeight: 20,
            columnWidths: {
              0: const pw.FlexColumnWidth(2),
              1: const pw.FlexColumnWidth(2),
              2: const pw.FlexColumnWidth(3),
              3: const pw.FlexColumnWidth(1.5),
              4: const pw.FlexColumnWidth(1.5),
              5: const pw.FlexColumnWidth(2),
              6: const pw.FlexColumnWidth(2),
              7: const pw.FlexColumnWidth(1.5),
            },
          ),

          pw.Spacer(),
          pw.Divider(thickness: 0.5),
          pw.Center(
            child: pw.Text("This audit report is digitally generated by Apna Hisaab",
                style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600)),
          ),
        ],
      ),
    );

    try {
      final pdfBytes = await pdf.save();
      final dir = await _getReportDirectory();
      final fileName = "Audit_${title.replaceAll(' ', '_')}_${DateFormat('ddMMM_HHmm').format(DateTime.now())}.pdf";
      final path = "${dir.path}/$fileName";
      await File(path).writeAsBytes(pdfBytes);

      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => pdfBytes,
        name: "Audit_$title",
      );
    } catch (e) {
      debugPrint("Audit PDF Error: $e");
    }
  }

  pw.Widget _buildSummaryBox(String title, double amount, PdfColor color) {
    return pw.Expanded(
      child: pw.Container(
        padding: const pw.EdgeInsets.all(12),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: color, width: 1),
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
        ),
        child: pw.Column(
          children: [
            pw.Text(title, style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: color)),
            pw.SizedBox(height: 5),
            pw.Text("Rs. ${amount.toStringAsFixed(2)}",
                style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: color)),
          ],
        ),
      ),
    );
  }

  pw.Widget _buildTransactionTable(List<TransactionModel> txs, PdfColor headerColor) {
    if (txs.isEmpty) {
      return pw.Text("No transactions found for this period.", style: pw.TextStyle(fontSize: 10, fontStyle: pw.FontStyle.italic));
    }
    return pw.Table.fromTextArray(
      headers: ['Date', 'Category', 'Description', 'Amount', 'Mode'],
      data: txs.map((tx) {
        // Fix: Clean category name to handle 'All Sales' or other internal labels
        String displayCategory = tx.category;
        if (displayCategory.toLowerCase() == 'all sales' || displayCategory.toLowerCase() == 'all') {
          // If the category is a generic label, we can try to get it from items or leave as is
          // but based on user feedback, we should show the ACTUAL category.
          // In this app, tx.category usually stores the category name.
        }

        return [
          DateFormat('dd/MM/yy').format(tx.date),
          displayCategory,
          _getCleanDescription(tx),
          tx.amount.toStringAsFixed(0),
          tx.paymentMode
        ];
      }).toList(),
      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
      cellStyle: const pw.TextStyle(fontSize: 9),
      headerDecoration: pw.BoxDecoration(color: headerColor),
      cellHeight: 25,
      columnWidths: {
        0: const pw.FlexColumnWidth(2),
        1: const pw.FlexColumnWidth(3),
        2: const pw.FlexColumnWidth(5),
        3: const pw.FlexColumnWidth(2),
        4: const pw.FlexColumnWidth(2),
      },
    );
  }

  /// Save Bill as PDF and return path
  Future<String?> saveBillAsPdf(TransactionModel tx, String businessName, {List<ItemModel>? masterItems, String qrPath = "", String qrLabel = ""}) async {
    final pdf = pw.Document();
    final uid = FirebaseAuth.instance.currentUser?.uid ?? "";
    final prefs = await SharedPreferences.getInstance();

    final logoPath = prefs.getString('logo_path_$uid') ?? "";
    final address = prefs.getString('address_$uid') ?? "";
    final contact = prefs.getString('contact_$uid') ?? "";
    final footerNote = prefs.getString('footer_note_$uid') ?? "";

    pw.MemoryImage? logoImage;
    if (logoPath.isNotEmpty && File(logoPath).existsSync()) {
      logoImage = pw.MemoryImage(File(logoPath).readAsBytesSync());
    }

    pw.MemoryImage? qrImage;
    if (qrPath.isNotEmpty && File(qrPath).existsSync()) {
      qrImage = pw.MemoryImage(File(qrPath).readAsBytesSync());
    }

    final snapshots = tx.itemSnapshots;
    final isPurchase = tx.type.toLowerCase() == 'purchase';
    final isSalary = tx.category.toLowerCase() == 'salary';
    final isExpense = tx.type.toLowerCase() == 'expense' && !isSalary;

    double subtotal = 0;
    if (snapshots.isNotEmpty) {
      for (var s in snapshots) {
        subtotal += s.lineTotal;
      }
    } else {
      subtotal = tx.amount + tx.discountValue - tx.taxValue;
    }

    double discount = tx.discountValue;
    double transport = tx.transportValue;
    // Fix: Subtract transport from the difference to get actual tax
    double totalAfterDiscountAndTransport = subtotal - discount + transport;
    double taxAmount = tx.amount - totalAfterDiscountAndTransport;
    if (taxAmount.abs() < 0.1) taxAmount = 0;

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.roll80,
        build: (context) => [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Center(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    if (logoImage != null)
                      pw.Container(
                        width: 50, height: 50,
                        margin: const pw.EdgeInsets.only(bottom: 5),
                        child: pw.Image(logoImage),
                      ),
                    pw.Text(
                      businessName.toUpperCase(), 
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14),
                      textAlign: pw.TextAlign.center,
                    ),
                    if (address.isNotEmpty) pw.Text(address, style: const pw.TextStyle(fontSize: 7), textAlign: pw.TextAlign.center),
                    if (contact.isNotEmpty) pw.Text("PH: $contact", style: const pw.TextStyle(fontSize: 7)),
                    if (!isPurchase && tx.token.isNotEmpty)
                      pw.Align(
                        alignment: pw.Alignment.centerRight,
                        child: pw.Text("TOKEN: ${tx.token}", style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                      ),
                  ],
                ),
              ),
              pw.Divider(thickness: 0.5),
              pw.Center(
                child: pw.Text(
                  isSalary ? "SALARY VOUCHER" : (isPurchase ? "PURCHASE VOUCHER" : (isExpense ? "EXPENSE VOUCHER" : "CASH MEMO")),
                  style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, letterSpacing: 1)
                )
              ),
              pw.Divider(thickness: 0.5),

              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  if (!isSalary)
                    pw.Text((isPurchase || isExpense) ? "Voucher No: ${tx.id}" : "Bill No: ${tx.id}", style: const pw.TextStyle(fontSize: 8)),
                  if (isSalary) pw.SizedBox(), // Keeps date on the right
                  pw.Text("Date: ${DateFormat('dd-MM-yy HH:mm').format(tx.date)}", style: const pw.TextStyle(fontSize: 8)),
                ],
              ),
              // Table Number (Hide for purchase)
              if (!isPurchase && snapshots.isNotEmpty && snapshots.first.tableNumber.isNotEmpty && snapshots.first.tableNumber != '0')
                pw.Text("TABLE: ${snapshots.first.tableNumber}", style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),

              if (tx.customerContact.isNotEmpty)
                pw.Text(isPurchase ? "Supplier: ${tx.customerContact}" : "Cust Contact: ${tx.customerContact}", style: const pw.TextStyle(fontSize: 8)),

              pw.Divider(thickness: 0.5),

              pw.Row(
                children: [
                  pw.Expanded(flex: 4, child: pw.Text("ITEM", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8))),
                  pw.Expanded(flex: 1, child: pw.Text("QTY", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8), textAlign: pw.TextAlign.center)),
                  pw.Expanded(flex: 2, child: pw.Text("RATE", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8), textAlign: pw.TextAlign.center)),
                  pw.Expanded(flex: 2, child: pw.Text("TOTAL", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8), textAlign: pw.TextAlign.right)),
                ],
              ),
              pw.SizedBox(height: 4),
              if (snapshots.isEmpty)
                pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(vertical: 2),
                  child: pw.Row(
                    children: [
                      pw.Expanded(flex: 4, child: pw.Text(tx.category, style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold))),
                      pw.Expanded(flex: 1, child: pw.Text("1", style: const pw.TextStyle(fontSize: 8), textAlign: pw.TextAlign.center)),
                      pw.Expanded(flex: 2, child: pw.Text(subtotal.toStringAsFixed(2), style: const pw.TextStyle(fontSize: 8), textAlign: pw.TextAlign.center)),
                      pw.Expanded(flex: 2, child: pw.Text(subtotal.toStringAsFixed(2), style: const pw.TextStyle(fontSize: 8), textAlign: pw.TextAlign.right)),
                    ],
                  ),
                )
              else
                ...snapshots.map((item) {
                  String qtyStr = item.qty == 0.5 ? "Half" : (item.qty % 1 == 0 ? item.qty.toInt().toString() : item.qty.toString());
                  String cleanName = item.name.replaceAll(RegExp(r'\s*\((Half|Full)\)', caseSensitive: false), '').trim();
                  String variant = item.variant.trim();
                  bool hideVariant = variant.toLowerCase() == 'full' || variant.toLowerCase() == 'none' || variant.isEmpty || variant.toLowerCase() == 'half';
                  String displayName = hideVariant ? cleanName : "$cleanName ($variant)";

                  // Sub-detail line: Method | Extras
                  List<String> details = [];
                  if (item.servingMethod.isNotEmpty && item.servingMethod != 'N/A' && !isSalary) {
                    details.add(item.servingMethod);
                  }
                  if (item.extraQty > 0) {
                    String exQty = item.extraQty % 1 == 0 ? item.extraQty.toInt().toString() : item.extraQty.toString();
                    details.add("+ Extra: $exQty @ ${item.extraPrice.toStringAsFixed(2)}");
                  }
                  String detailString = details.join(" | ");

                  return pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(vertical: 2),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Row(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Expanded(flex: 4, child: pw.Text(displayName, style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold))),
                            pw.Expanded(flex: 1, child: pw.Text(qtyStr, style: const pw.TextStyle(fontSize: 8), textAlign: pw.TextAlign.center)),
                            pw.Expanded(flex: 2, child: pw.Text(item.price.toStringAsFixed(2), style: const pw.TextStyle(fontSize: 8), textAlign: pw.TextAlign.center)),
                            pw.Expanded(flex: 2, child: pw.Text(item.lineTotal.toStringAsFixed(2), style: const pw.TextStyle(fontSize: 8), textAlign: pw.TextAlign.right)),
                          ],
                        ),
                        if (detailString.isNotEmpty)
                          pw.Padding(
                            padding: const pw.EdgeInsets.only(left: 5),
                            child: pw.Text(detailString, style: const pw.TextStyle(fontSize: 6, color: PdfColors.grey700)),
                          ),
                      ],
                    ),
                  );
                }),
              pw.Divider(thickness: 0.5),

              _buildPdfBreakdownRow("Subtotal", subtotal.toStringAsFixed(2)),
              if (discount > 0) _buildPdfBreakdownRow("Discount (-)", discount.toStringAsFixed(2)),
              if (taxAmount > 0) 
                _buildPdfBreakdownRow(
                  "Tax (${((subtotal > 0) ? (taxAmount / subtotal) * 100 : 0).toStringAsFixed(1)}%)", 
                  taxAmount.toStringAsFixed(2)
                ),
              if (tx.transportValue > 0) 
                _buildPdfBreakdownRow(
                  (tx.type.toLowerCase() == 'sale' || tx.type.toLowerCase() == 'income') 
                  ? "Delivery Charge (+)" 
                  : "Transport / Rent (+)", 
                  tx.transportValue.toStringAsFixed(2)
                ),

              pw.SizedBox(height: 8),
              pw.Container(
                padding: const pw.EdgeInsets.all(4),
                decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text("ITEM COUNT: ${snapshots.length}", style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
                    pw.Row(
                      children: [
                        pw.Text("GRAND TOTAL: ", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                        pw.Text("${tx.amount.toStringAsFixed(2)}", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 16)),
                      ]
                    ),
                  ],
                ),
              ),

              if (tx.paymentMode == 'Credit') ...[
                pw.SizedBox(height: 4),
                pw.Divider(thickness: 0.5, borderStyle: pw.BorderStyle.dashed),
                pw.Text("CREDIT SETTLEMENT:", style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
                _buildPdfBreakdownRow("Paid Amount", tx.paidAmount.toStringAsFixed(0)),
                _buildPdfBreakdownRow("Remaining Due", tx.remainingCredit.toStringAsFixed(0)),
              ],

              if (isPurchase) ...[
                pw.SizedBox(height: 2),
                pw.Text("Payment Mode: ${tx.paymentMode}", style: const pw.TextStyle(fontSize: 8)),
                if (tx.paymentMode == 'Credit') ...[
                  pw.Text("Paid: Rs. ${tx.paidAmount.toStringAsFixed(0)}", style: const pw.TextStyle(fontSize: 8)),
                  pw.Text("Balance: Rs. ${tx.remainingCredit.toStringAsFixed(0)}", style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
                ],
                pw.SizedBox(height: 10),
                pw.Divider(thickness: 0.5),
                pw.Center(child: pw.Text("Receiver Signature", style: const pw.TextStyle(fontSize: 7))),
                pw.SizedBox(height: 5),
              ],

              pw.Divider(thickness: 0.5),

              if (!isPurchase && qrImage != null)
                pw.Center(
                  child: pw.Column(
                    children: [
                      pw.SizedBox(height: 3),
                      pw.Container(width: 80, height: 80, child: pw.Image(qrImage)),
                      pw.SizedBox(height: 2),
                      pw.Text(qrLabel.isNotEmpty ? qrLabel : "Scan for Payment/Review", style: const pw.TextStyle(fontSize: 6)),
                      pw.SizedBox(height: 3),
                    ],
                  ),
                ),

              if (footerNote.isNotEmpty) ...[
                pw.SizedBox(height: 5),
                pw.Center(
                  child: pw.Text(
                    footerNote, 
                    style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.normal),
                    textAlign: pw.TextAlign.center,
                  ),
                ),
                pw.SizedBox(height: 5),
              ],

              pw.Center(child: pw.Text(isPurchase ? "Stock Inward Successful" : "Thank You! Visit Again", style: pw.TextStyle(fontSize: 9, fontStyle: pw.FontStyle.italic))),
              pw.SizedBox(height: 4),

              pw.Divider(thickness: 0.5),
              pw.Center(child: pw.Text("POWERED BY: APNA HISAAB", style: pw.TextStyle(fontSize: 6, fontWeight: pw.FontWeight.bold, color: PdfColors.grey800))),
              pw.Center(child: pw.Text("Developer: Nikkhil | +91 9992256959", style: const pw.TextStyle(fontSize: 5, color: PdfColors.grey700))),
              pw.Center(child: pw.Text("Terms: This is a computer generated invoice.", style: const pw.TextStyle(fontSize: 5, color: PdfColors.grey700))),
              pw.SizedBox(height: 5),
            ],
          ),
        ],
      ),
    );

    try {
      final dir = await _getBillDirectory();
      final fileName = "Bill_${tx.id}_${DateFormat('ddMMM_HHmm').format(DateTime.now())}.pdf";
      final path = "${dir.path}/$fileName";
      final file = File(path);
      final pdfBytes = await pdf.save();
      await file.writeAsBytes(pdfBytes);

      // Critical Fix: Add a small delay to ensure file system sync
      await Future.delayed(const Duration(milliseconds: 300));

      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => pdfBytes,
        name: "Bill_${tx.id}",
      );

      return path;
    } catch (e) {
      debugPrint("Bill PDF Error: $e");
      return null;
    }
  }

  /// Save KOT as PDF and return path
  Future<String?> saveKotAsPdf(TransactionModel tx, String businessName) async {
    final pdf = pw.Document();
    final snapshots = tx.itemSnapshots;
    final uid = FirebaseAuth.instance.currentUser?.uid ?? "";
    final prefs = await SharedPreferences.getInstance();

    final address = prefs.getString('address_$uid') ?? "";
    final contact = prefs.getString('contact_$uid') ?? "";
    final footerNote = prefs.getString('footer_note_$uid') ?? "";

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.roll80,
        build: (context) => [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Header: Restaurant Details
              pw.Center(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    pw.Text(businessName.toUpperCase(), 
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14),
                      textAlign: pw.TextAlign.center,
                    ),
                    if (address.isNotEmpty) pw.Text(address, style: const pw.TextStyle(fontSize: 7), textAlign: pw.TextAlign.center),
                    if (contact.isNotEmpty) pw.Text("PH: $contact", style: const pw.TextStyle(fontSize: 7), textAlign: pw.TextAlign.center),
                  ],
                ),
              ),
              pw.SizedBox(height: 5),
              pw.Divider(thickness: 0.5),
              pw.Center(child: pw.Text("KITCHEN ORDER", style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold))),

              // Token: Large and Bold
              if (tx.token.isNotEmpty) ...[
                pw.Divider(thickness: 1, borderStyle: pw.BorderStyle.dashed),
                pw.Center(child: pw.Text("TOKEN: ${tx.token}", style: pw.TextStyle(fontSize: 26, fontWeight: pw.FontWeight.bold))),
                pw.Divider(thickness: 1, borderStyle: pw.BorderStyle.dashed),
              ],

              pw.SizedBox(height: 5),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text("Order No: #${tx.id}", style: const pw.TextStyle(fontSize: 9)),
                  pw.Text("Time: ${DateFormat('HH:mm').format(tx.date)}", style: const pw.TextStyle(fontSize: 9)),
                ],
              ),

              // Table Number
              if (snapshots.isNotEmpty && snapshots.first.tableNumber.isNotEmpty && snapshots.first.tableNumber != '0') ...[
                pw.SizedBox(height: 5),
                pw.Center(child: pw.Text("TABLE: ${snapshots.first.tableNumber}", style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold))),
              ],

              pw.Divider(thickness: 0.5),
              ...snapshots.map((item) {
                // Handle 0.5 for Half items
                String qtyStr;
                if (item.qty == 0.5) {
                  qtyStr = "Half";
                } else {
                  qtyStr = item.qty % 1 == 0 ? item.qty.toInt().toString() : item.qty.toString();
                }

                // Clean name from redundant (Half)/(Full)
                String cleanName = item.name.replaceAll(RegExp(r'\s*\((Half|Full)\)', caseSensitive: false), '').trim();

                String v = item.variant.trim().toLowerCase();
                bool hideV = v == 'full' || v == 'none' || v == '' || v == 'half';
                String variantDisplay = hideV ? "" : "(${item.variant})";

                return pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(vertical: 3),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Row(
                        children: [
                          pw.Expanded(
                            child: pw.Text("[ ] $qtyStr x $cleanName $variantDisplay",
                              style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
                          ),
                        ],
                      ),
                      if (item.extraQty > 0)
                        pw.Padding(
                          padding: const pw.EdgeInsets.only(left: 15),
                          child: pw.Text("+ EXTRA PC'S: ${item.extraQty % 1 == 0 ? item.extraQty.toInt() : item.extraQty}",
                            style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                        ),
                      if (item.servingMethod.toLowerCase() == 'takeaway')
                        pw.Padding(
                          padding: const pw.EdgeInsets.only(left: 15),
                          child: pw.Text("[ TAKEAWAY ]", style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                        ),
                    ],
                  ),
                );
              }),
            ],
          ),
        ],
      ),
    );

    try {
      final dir = await _getKotDirectory();
      final fileName = "KOT_${tx.id}_${DateFormat('ddMMM_HHmm').format(DateTime.now())}.pdf";
      final path = "${dir.path}/$fileName";
      final file = File(path);
      final pdfBytes = await pdf.save();
      await file.writeAsBytes(pdfBytes);

      // Critical Fix: Add a small delay to ensure file system sync
      await Future.delayed(const Duration(milliseconds: 300));

      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => pdfBytes,
        name: "KOT_${tx.id}",
      );

      return path;
    } catch (e) {
      debugPrint("KOT PDF Error: $e");
      return null;
    }
  }

  pw.Widget _buildPdfBreakdownRow(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label, style: const pw.TextStyle(fontSize: 8)),
          pw.Text(value, style: const pw.TextStyle(fontSize: 8)),
        ],
      ),
    );
  }

  /// Create automatic daily backup at 4 AM (overwrites last auto backup for THIS USER)
  Future<String?> createAutoBackup() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;

    try {
      final data = await _generateBackupData();
      final dir = await _getBackupDirectory();
      final file = File("${dir.path}/AutoBackup_${user.uid}.json");
      await file.writeAsString(jsonEncode(data));
      return file.path;
    } catch (e) {
      debugPrint("Auto Backup Error: $e");
      return null;
    }
  }

  /// Check if auto backup exists for CURRENT USER
  Future<File?> getAutoBackupFile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;

    try {
      final dir = await _getBackupDirectory();
      final file = File("${dir.path}/AutoBackup_${user.uid}.json");
      if (await file.exists()) return file;
    } catch (_) {}
    return null;
  }

  /// FULL BACKUP (Includes everything)
  Future<String?> createFullBackup() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;

    try {
      final backupData = await _generateBackupData();
      String jsonString = jsonEncode(backupData);
      final baseDir = await _getBackupDirectory();

      final fileName = "Backup_${DateFormat('ddMMM_yyyy_HHmm').format(DateTime.now())}.json";
      final file = File("${baseDir.path}/$fileName");
      await file.writeAsString(jsonString);
      return file.path;
    } catch (e) {
      debugPrint("Backup Error: $e");
      return null;
    }
  }

  Future<Map<String, dynamic>> _generateBackupData() async {
    final db = DatabaseHelper.instance;
    final transactions = await db.getAllTransactions();
    final items = await db.getAllItems();
    final categories = await db.getAllCategories();
    final staff = await db.getAllStaff();
    final suppliers = await db.getAllSuppliers();

    // Missing tables added
    final units = await db.getAllUnits();
    final sqlDb = await db.database;
    final reminders = await sqlDb.query('purchase_reminders');
    final staffAdvance = await sqlDb.query('staff_advance');
    final staffLeave = await sqlDb.query('staff_leave');

    final user = FirebaseAuth.instance.currentUser;
    final uid = user?.uid ?? "";

    // Profile settings from SharedPreferences
    final prefs = await SharedPreferences.getInstance();

    // IMAGE PORTABILITY: Convert images to Base64 (v2.5 Upgrade)
    String? logoBase64;
    String? qrBase64;
    try {
      final logoPath = prefs.getString('logo_path_$uid');
      if (logoPath != null && File(logoPath).existsSync()) {
        logoBase64 = base64Encode(File(logoPath).readAsBytesSync());
      }
      final qrPath = prefs.getString('qr_path_$uid');
      if (qrPath != null && File(qrPath).existsSync()) {
        qrBase64 = base64Encode(File(qrPath).readAsBytesSync());
      }
    } catch (e) {
      debugPrint("Image Backup Error: $e");
    }

    // Process items and staff to include base64 icons/images
    final List<Map<String, dynamic>> itemsList = [];
    for (var item in items) {
      final itemMap = item.toMap();
      if (item.icon != null && File(item.icon!).existsSync()) {
        try {
          itemMap['icon_base64'] = base64Encode(File(item.icon!).readAsBytesSync());
        } catch (e) {
          debugPrint("Item Icon Backup Error: $e");
        }
      }
      itemsList.add(itemMap);
    }

    final List<Map<String, dynamic>> staffList = [];
    for (var s in staff) {
      final staffMap = s.toMap();
      if (s.imagePath != null && File(s.imagePath!).existsSync()) {
        try {
          staffMap['image_base64'] = base64Encode(File(s.imagePath!).readAsBytesSync());
        } catch (e) {
          debugPrint("Staff Image Backup Error: $e");
        }
      }
      staffList.add(staffMap);
    }

    Map<String, dynamic> profileSettings = {
      'business_name': prefs.getString('business_name_$uid'),
      'owner_name': prefs.getString('owner_name_$uid'),
      'contact': prefs.getString('contact_$uid'),
      'address': prefs.getString('address_$uid'),
      'logo_path': prefs.getString('logo_path_$uid'),
      'qr_path': prefs.getString('qr_path_$uid'),
      'logo_base64': logoBase64,
      'qr_base64': qrBase64,
      'qr_label': prefs.getString('qr_label_$uid'),
      'cloud_sync': prefs.getBool('cloud_sync_$uid'),
      'currency': prefs.getString('currency_$uid'),
      'theme_color': prefs.getInt('theme_color_$uid'),
      'tax_percentage': prefs.getDouble('tax_percentage_$uid'),
      'is_dark_mode': prefs.getBool('is_dark_mode_$uid'),
      'total_tables': prefs.getInt('total_tables_$uid'),
      'show_amount': prefs.getBool('show_amount_$uid'),
      'auto_print': prefs.getBool('auto_print_$uid'),
      'kot_enabled': prefs.getBool('kot_enabled_$uid'),
      'custom_pin': prefs.getString('custom_pin_$uid'),
      'is_pin_enabled': prefs.getBool('is_pin_enabled_$uid'),
      'is_biometric_enabled': prefs.getBool('is_biometric_enabled_$uid'),
      'license_key': prefs.getString('license_key_$uid'),
      'is_app_activated': prefs.getBool('is_app_activated_$uid'),
      'is_lifetime': prefs.getBool('is_lifetime_$uid'),
      'expiry_date': prefs.getString('expiry_date_$uid'),
    };

    return {
      'backup_version': 2.5,
      'backup_uid': uid,
      'backup_date': DateTime.now().toIso8601String(),
      'transactions': transactions.map((t) => t.toMap()).toList(),
      'items': itemsList,
      'categories': categories.map((c) => c.toMap()).toList(),
      'staff': staffList,
      'suppliers': suppliers.map((s) => s.toMap()).toList(),
      'units': units,
      'purchase_reminders': reminders,
      'staff_advance': staffAdvance,
      'staff_leave': staffLeave,
      'profile_settings': profileSettings,
    };
  }

  Future<bool> restoreFromBackup(File file) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      // Skip UID check if no user is logged in (rare) or for manual restore flexibility
      final uid = user?.uid;

      String content = await file.readAsString();
      Map<String, dynamic> data = jsonDecode(content);

      // If we have a UID in backup, and a current user, they should match for security
      if (data.containsKey('backup_uid') && uid != null && data['backup_uid'] != uid) {
        debugPrint("Restore Warning: Backup UID mismatch, proceeding with manual override.");
      }

      final db = await DatabaseHelper.instance.database;

      await db.transaction((txn) async {
        // Clear all tables
        await txn.delete('transactions');
        await txn.delete('items');
        await txn.delete('categories');
        await txn.delete('staff');
        await txn.delete('suppliers');
        await txn.delete('units');
        await txn.delete('purchase_reminders');
        await txn.delete('staff_advance');
        await txn.delete('staff_leave');

        // Helper to insert with schema fallback
        Future<void> safeInsert(String table, List<dynamic>? list) async {
          if (list == null) return;
          for (var item in list) {
            try {
              final Map<String, dynamic> map = Map.from(item);
              
              // CRITICAL FIX: Ensure missing fields for compatibility with older backups
              if (table == 'items') {
                if (!map.containsKey('is_synced')) map['is_synced'] = 0;
                if (!map.containsKey('license_id')) map['license_id'] = 'NONE';
              }
              if (table == 'transactions') {
                if (!map.containsKey('is_synced')) map['is_synced'] = 0;
                if (!map.containsKey('license_id')) map['license_id'] = 'NONE';
              }
              if (table == 'staff') {
                if (!map.containsKey('is_synced')) map['is_synced'] = 0;
                if (!map.containsKey('license_id')) map['license_id'] = 'NONE';
              }
              if (table == 'categories') {
                if (!map.containsKey('license_id')) map['license_id'] = 'NONE';
              }
              if (table == 'suppliers') {
                if (!map.containsKey('license_id')) map['license_id'] = 'NONE';
              }
              if (table == 'units') {
                if (!map.containsKey('license_id')) map['license_id'] = 'NONE';
              }
              if (table == 'purchase_reminders') {
                if (!map.containsKey('license_id')) map['license_id'] = 'NONE';
              }

              await txn.insert(table, map);
            } catch (e) {
              debugPrint("Error inserting into $table: $e");
            }
          }
        }

        await safeInsert('categories', data['categories']);
        await safeInsert('items', data['items']);
        await safeInsert('transactions', data['transactions']);
        await safeInsert('staff', data['staff']);
        await safeInsert('suppliers', data['suppliers']);
        await safeInsert('units', data['units']);
        await safeInsert('purchase_reminders', data['purchase_reminders']);
        await safeInsert('staff_advance', data['staff_advance']);
        await safeInsert('staff_leave', data['staff_leave']);

        // Restore Images for Items and Staff
        final appDocDir = await getApplicationDocumentsDirectory();

        if (data['items'] != null) {
          for (var item in data['items']) {
            if (item['icon_base64'] != null && item['icon_base64'].toString().isNotEmpty) {
              try {
                final bytes = base64Decode(item['icon_base64']);
                final fileName = item['icon_path']?.split('/')?.last ?? "item_${DateTime.now().microsecondsSinceEpoch}.png";
                final file = File('${appDocDir.path}/$fileName');
                await file.writeAsBytes(bytes);
              } catch (e) {
                debugPrint("Restore Item Icon Error: $e");
              }
            }
          }
        }

        if (data['staff'] != null) {
          for (var s in data['staff']) {
            if (s['image_base64'] != null && s['image_base64'].toString().isNotEmpty) {
              try {
                final bytes = base64Decode(s['image_base64']);
                final fileName = s['image_path']?.split('/')?.last ?? "staff_${DateTime.now().microsecondsSinceEpoch}.png";
                final file = File('${appDocDir.path}/$fileName');
                await file.writeAsBytes(bytes);
              } catch (e) {
                debugPrint("Restore Staff Image Error: $e");
              }
            }
          }
        }
      });

      // Restore Profile Settings
      if (data['profile_settings'] != null) {
        final prefs = await SharedPreferences.getInstance();
        final p = data['profile_settings'] as Map<String, dynamic>;

        // Helper to safely convert dynamic to bool (v2.5 Fix for numeric booleans)
        bool toBool(dynamic val) {
          if (val == null) return false;
          if (val is bool) return val;
          if (val is num) return val.toInt() != 0;
          if (val is String) {
            final s = val.toLowerCase();
            return s == 'true' || s == '1' || s == 'yes';
          }
          return false;
        }

        for (var key in p.keys) {
          // Skip these as we handle them explicitly below to ensure portability
          if (key == 'logo_base64' || key == 'qr_base64') continue;

          var value = p[key];
          String prefKey = "${key}_$uid";
          if (value == null) continue;

          // Critical Fix: Type-safe restore to prevent "double is not subtype of bool"
          if (value is String) {
            await prefs.setString(prefKey, value);
          } else if (value is bool) {
            await prefs.setBool(prefKey, value);
          } else if (value is int) {
            await prefs.setInt(prefKey, value);
          } else if (value is double) {
            // Some keys might be booleans stored as doubles (1.0/0.0) in legacy backups
            final boolKeys = ['cloud_sync', 'is_dark_mode', 'show_amount', 'auto_print', 'kot_enabled', 'is_pin_enabled', 'is_biometric_enabled', 'is_app_activated', 'is_lifetime'];
            if (boolKeys.contains(key)) {
              await prefs.setBool(prefKey, toBool(value));
            } else {
              await prefs.setDouble(prefKey, value);
            }
          }
        }

        // Image Reconstruction (v2.5+)
        final appDocDir = await getApplicationDocumentsDirectory();

        if (p['logo_base64'] != null && p['logo_base64'].toString().isNotEmpty) {
          try {
            final bytes = base64Decode(p['logo_base64']);
            final logoFile = File("${appDocDir.path}/logo_$uid.png");
            await logoFile.writeAsBytes(bytes);
            await prefs.setString('logo_path_$uid', logoFile.path);
          } catch (e) {
            debugPrint("Restore Logo Error: $e");
          }
        }

        if (p['qr_base64'] != null && p['qr_base64'].toString().isNotEmpty) {
          try {
            final bytes = base64Decode(p['qr_base64']);
            final qrFile = File("${appDocDir.path}/qr_$uid.png");
            await qrFile.writeAsBytes(bytes);
            await prefs.setString('qr_path_$uid', qrFile.path);
          } catch (e) {
            debugPrint("Restore QR Error: $e");
          }
        }
      }

      return true;
    } catch (e) {
      debugPrint("Restore Error: $e");
      return false;
    }
  }

  Future<void> exportAllStaffReport(String bizName, List<StaffModel> staffList, StaffProvider staffProvider, {DateTimeRange? range}) async {
    final pdf = pw.Document();
    final dateRange = range ?? DateTimeRange(
      start: DateTime.now().subtract(const Duration(days: 180)),
      end: DateTime.now(),
    );

    // Summary Page
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (context) => [
          pw.Header(
            level: 0,
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(bizName.toUpperCase(), style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text('STAFF PAYROLL SUMMARY', style: pw.TextStyle(fontSize: 14, color: PdfColors.grey700)),
                    pw.Text('${DateFormat('dd MMM yyyy').format(dateRange.start)} - ${DateFormat('dd MMM yyyy').format(dateRange.end)}', style: pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
                  ],
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 20),
          pw.TableHelper.fromTextArray(
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: 10),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey800),
            cellHeight: 25,
            cellStyle: const pw.TextStyle(fontSize: 9),
            cellAlignments: {
              0: pw.Alignment.centerLeft,
              1: pw.Alignment.centerLeft,
              2: pw.Alignment.centerRight,
              3: pw.Alignment.centerRight,
              4: pw.Alignment.centerRight,
              5: pw.Alignment.centerRight,
            },
            headers: ['Staff Name', 'Role', 'Salary', 'Advance', 'Leaves', 'Net Payable'],
            data: staffList.map((s) {
              final payable = staffProvider.calculatePayable(s);
              return [
                s.name,
                s.role,
                s.monthlySalary.toStringAsFixed(0),
                s.advance.toStringAsFixed(0),
                s.totalLeaves.toString(),
                payable.toStringAsFixed(0),
              ];
            }).toList(),
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 20),
            child: pw.Text(
              'Generated on: ${DateFormat('dd MMM yyyy, hh:mm a').format(DateTime.now())}',
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey),
            ),
          ),
        ],
      ),
    );

    // Detailed History Pages for each staff
    for (var staff in staffList) {
      final allAdvances = await staffProvider.getStaffAdvances(staff.id!);
      final allLeaves = await staffProvider.getStaffLeaves(staff.id!);

      final filteredAdvances = allAdvances.where((a) => a.date.isAfter(dateRange.start.subtract(const Duration(seconds: 1))) && a.date.isBefore(dateRange.end.add(const Duration(days: 1)))).toList();
      final filteredLeaves = allLeaves.where((l) => l.date.isAfter(dateRange.start.subtract(const Duration(seconds: 1))) && l.date.isBefore(dateRange.end.add(const Duration(days: 1)))).toList();

      if (filteredAdvances.isNotEmpty || filteredLeaves.isNotEmpty) {
        pdf.addPage(
          pw.MultiPage(
            pageFormat: PdfPageFormat.a4,
            margin: const pw.EdgeInsets.all(32),
            build: (context) => [
              pw.Header(
                level: 1,
                child: pw.Text('HISTORY: ${staff.name.toUpperCase()}',
                  style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColors.blue800)),
              ),
              pw.Text('Period: ${DateFormat('dd MMM yyyy').format(dateRange.start)} to ${DateFormat('dd MMM yyyy').format(dateRange.end)}', style: pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
              pw.SizedBox(height: 10),

              if (filteredAdvances.isNotEmpty) ...[
                pw.Text('ADVANCE HISTORY', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 5),
                pw.TableHelper.fromTextArray(
                  headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8),
                  cellStyle: const pw.TextStyle(fontSize: 8),
                  headers: ['Date', 'Amount'],
                  data: filteredAdvances.map((a) => [
                    DateFormat('dd MMM yyyy').format(a.date),
                    a.amount.toStringAsFixed(0),
                  ]).toList(),
                ),
                pw.SizedBox(height: 20),
              ],

              if (filteredLeaves.isNotEmpty) ...[
                pw.Text('LEAVE HISTORY', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 5),
                pw.TableHelper.fromTextArray(
                  headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8),
                  cellStyle: const pw.TextStyle(fontSize: 8),
                  headers: ['Date', 'Type'],
                  data: filteredLeaves.map((l) => [
                    DateFormat('dd MMM yyyy').format(l.date),
                    l.type == 1.0 ? 'Full Day' : 'Half Day',
                  ]).toList(),
                ),
              ],
            ],
          ),
        );
      }
    }

    final dir = await _getReportDirectory();
    final fileName = "Staff_Detailed_Report_${DateFormat('ddMMM_HHmm').format(DateTime.now())}.pdf";
    final file = File("${dir.path}/$fileName");
    await file.writeAsBytes(await pdf.save());
    await Share.shareXFiles([XFile(file.path)], text: 'Staff Detailed Payroll Report');
  }

  /// Generate a concise monthly payroll report for all staff
  Future<void> generateMonthlyPayrollReport(String bizName, List<StaffModel> staffList, DateTime selectedMonth) async {
    final pdf = pw.Document();
    final monthStr = DateFormat('MMMM yyyy').format(selectedMonth);
    
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (context) => [
          // Header
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(bizName.toUpperCase(), style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900)),
                  pw.Text("Monthly Payroll Report", style: const pw.TextStyle(fontSize: 12, color: PdfColors.grey700)),
                ],
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text(monthStr.toUpperCase(), style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
                  pw.Text("Generated: ${DateFormat('dd/MM/yy HH:mm').format(DateTime.now())}",
                      style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 20),
          pw.Divider(thickness: 1, color: PdfColors.blue900),
          pw.SizedBox(height: 20),

          // Summary Section
          pw.Row(
            children: [
              _buildSummaryBox("TOTAL STAFF", staffList.length.toDouble(), PdfColors.blueGrey800),
              pw.SizedBox(width: 15),
              _buildSummaryBox("TOTAL PAYROLL", staffList.fold(0.0, (sum, s) => sum + s.monthlySalary), PdfColors.blue700),
              pw.SizedBox(width: 15),
              _buildSummaryBox("TOTAL ADVANCES", staffList.fold(0.0, (sum, s) => sum + s.advance), PdfColors.red700),
              pw.SizedBox(width: 15),
              _buildSummaryBox("NET DISBURSEMENT", staffList.fold(0.0, (sum, s) => sum + s.calculateCurrentPayable(s.runtimeDeduction)), PdfColors.green700),
            ],
          ),
          pw.SizedBox(height: 30),

          // Detailed Table
          pw.Table.fromTextArray(
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: 10),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.blue900),
            cellHeight: 30,
            cellStyle: const pw.TextStyle(fontSize: 9),
            cellAlignments: {
              0: pw.Alignment.centerLeft,
              1: pw.Alignment.centerLeft,
              2: pw.Alignment.centerRight,
              3: pw.Alignment.centerRight,
              4: pw.Alignment.centerRight,
              5: pw.Alignment.centerRight,
            },
            headers: ['STAFF NAME', 'ROLE', 'BASE SALARY', 'LEAVES', 'ADVANCE', 'NET PAYABLE'],
            data: staffList.map((s) {
              return [
                s.name.toUpperCase(),
                s.role,
                s.monthlySalary.toStringAsFixed(0),
                s.totalLeaves.toString(),
                s.advance.toStringAsFixed(0),
                s.calculateCurrentPayable(s.runtimeDeduction).toStringAsFixed(0),
              ];
            }).toList(),
          ),

          pw.Spacer(),
          pw.Divider(thickness: 0.5),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text("Apna Hisaab - Staff Management System", style: pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
              pw.Text("Authorized Signature: __________________", style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
            ],
          ),
        ],
      ),
    );

    try {
      final pdfBytes = await pdf.save();
      final dir = await _getReportDirectory();
      final fileName = "Payroll_${monthStr.replaceAll(' ', '_')}_${DateFormat('ddMMM_HHmm').format(DateTime.now())}.pdf";
      final path = "${dir.path}/$fileName";
      await File(path).writeAsBytes(pdfBytes);

      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => pdfBytes,
        name: "Payroll_$monthStr",
      );
    } catch (e) {
      debugPrint("Monthly Payroll Export Error: $e");
    }
  }


  Future<void> exportSingleStaffReport(String bizName, StaffModel staff, StaffProvider staffProvider, DateTimeRange range) async {
    final pdf = pw.Document();

    final allAdvances = await staffProvider.getStaffAdvances(staff.id!);
    final allLeaves = await staffProvider.getStaffLeaves(staff.id!);

    final filteredAdvances = allAdvances.where((a) => a.date.isAfter(range.start.subtract(const Duration(seconds: 1))) && a.date.isBefore(range.end.add(const Duration(days: 1)))).toList();
    final filteredLeaves = allLeaves.where((l) => l.date.isAfter(range.start.subtract(const Duration(seconds: 1))) && l.date.isBefore(range.end.add(const Duration(days: 1)))).toList();

    // Month-wise breakdown logic
    List<Map<String, dynamic>> monthlyBreakdown = [];
    DateTime iterateMonth = DateTime(range.start.year, range.start.month);
    DateTime endMonthMarker = DateTime(range.end.year, range.end.month);

    while (!iterateMonth.isAfter(endMonthMarker)) {
      final monthStart = DateTime(iterateMonth.year, iterateMonth.month, 1);
      final monthEnd = DateTime(iterateMonth.year, iterateMonth.month + 1, 0, 23, 59, 59);

      final mAdvances = allAdvances.where((a) => a.date.isAfter(monthStart.subtract(const Duration(seconds: 1))) && a.date.isBefore(monthEnd)).toList();
      final mLeaves = allLeaves.where((l) => l.date.isAfter(monthStart.subtract(const Duration(seconds: 1))) && l.date.isBefore(monthEnd)).toList();

      double mAdvTotal = mAdvances.fold(0.0, (sum, a) => sum + a.amount);
      double mLeaveDays = mLeaves.fold(0.0, (sum, l) => sum + l.type);
      double mDeduction = 0;
      for (var l in mLeaves) {
        int days = DateUtils.getDaysInMonth(l.date.year, l.date.month);
        mDeduction += l.type * (staff.monthlySalary / days);
      }

      double mNet = staff.monthlySalary - mDeduction - mAdvTotal;
      monthlyBreakdown.add({
        'month': DateFormat('MMM yyyy').format(iterateMonth),
        'base': staff.monthlySalary,
        'leaves': mLeaveDays,
        'deduction': mDeduction,
        'advances': mAdvTotal,
        'net': mNet < 0 ? 0 : mNet,
      });
      iterateMonth = DateTime(iterateMonth.year, iterateMonth.month + 1);
    }

    double totalAdvance = monthlyBreakdown.fold(0.0, (sum, m) => sum + m['advances']);
    double totalLeavesCount = monthlyBreakdown.fold(0.0, (sum, m) => sum + m['leaves']);
    double totalBaseSalary = monthlyBreakdown.fold(0.0, (sum, m) => sum + m['base']);
    double totalNetPayable = monthlyBreakdown.fold(0.0, (sum, m) => sum + m['net']);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        theme: pw.ThemeData.withFont(
          base: await PdfGoogleFonts.notoSansRegular(),
          bold: await PdfGoogleFonts.notoSansBold(),
        ),
        build: (context) => [
          // Header Section
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(bizName.toUpperCase(), style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900)),
                  pw.Text('Staff Payroll Statement', style: pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
                  pw.SizedBox(height: 5),
                  pw.Text('Period: ${DateFormat('dd MMM yyyy').format(range.start)} - ${DateFormat('dd MMM yyyy').format(range.end)}',
                    style: pw.TextStyle(fontSize: 9, color: PdfColors.blueGrey800)),
                ],
              ),
              pw.Container(
                padding: const pw.EdgeInsets.all(10),
                decoration: pw.BoxDecoration(
                  color: PdfColors.blue50,
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(10)),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(staff.name.toUpperCase(), style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900)),
                    pw.Text(staff.role.toUpperCase(), style: pw.TextStyle(fontSize: 9, color: PdfColors.grey700, fontWeight: pw.FontWeight.bold)),
                    pw.Text('ID: STF-${staff.id.toString().padLeft(3, '0')}', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
                  ],
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 25),

          // Summary Grid
          pw.GridView(
            crossAxisCount: 4,
            childAspectRatio: 0.6,
            children: [
              _buildPdfSummaryCard(monthlyBreakdown.length > 1 ? 'Total Base Salary' : 'Monthly Salary', totalBaseSalary.toStringAsFixed(0), PdfColors.blue700),
              _buildPdfSummaryCard(monthlyBreakdown.length > 1 ? 'Total Advance' : 'Advance Taken', totalAdvance.toStringAsFixed(0), PdfColors.red700),
              _buildPdfSummaryCard(monthlyBreakdown.length > 1 ? 'Total Leaves' : 'Leave Days', totalLeavesCount.toString(), PdfColors.orange700),
              _buildPdfSummaryCard(monthlyBreakdown.length > 1 ? 'Total Payable' : 'Net Payable', totalNetPayable.toStringAsFixed(0), PdfColors.green700, isMain: true),
            ],
          ),

          pw.SizedBox(height: 25),

          // Month-wise Breakdown Table
          if (monthlyBreakdown.length > 1) ...[
            pw.Text('MONTH-WISE PAYROLL BREAKDOWN', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900)),
            pw.SizedBox(height: 8),
            pw.TableHelper.fromTextArray(
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9, color: PdfColors.white),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey800),
              cellStyle: const pw.TextStyle(fontSize: 8),
              headers: ['Month', 'Base Salary', 'Leaves', 'Deduction', 'Advance', 'Net Payable'],
              data: monthlyBreakdown.map((m) => [
                m['month'],
                m['base'].toStringAsFixed(0),
                m['leaves'].toString(),
                m['deduction'].toStringAsFixed(0),
                m['advances'].toStringAsFixed(0),
                m['net'].toStringAsFixed(0),
              ]).toList(),
            ),
            pw.SizedBox(height: 25),
          ],

          // Advance Table
          if (filteredAdvances.isNotEmpty) ...[
            pw.Text('Advance History', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900)),
            pw.SizedBox(height: 8),
            pw.TableHelper.fromTextArray(
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9, color: PdfColors.white),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.blue900),
              cellStyle: const pw.TextStyle(fontSize: 9),
              headers: ['Date', 'Amount', 'Description'],
              data: filteredAdvances.map((a) => [
                DateFormat('dd MMM yyyy').format(a.date),
                'Rs. ${a.amount.toStringAsFixed(0)}',
                'Advance Payment',
              ]).toList(),
            ),
            pw.SizedBox(height: 20),
          ],

          // Leave Table
          if (filteredLeaves.isNotEmpty) ...[
            pw.Text('Attendance/Leave Records', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900)),
            pw.SizedBox(height: 8),
            pw.TableHelper.fromTextArray(
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9, color: PdfColors.white),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey800),
              cellStyle: const pw.TextStyle(fontSize: 9),
              headers: ['Date', 'Type', 'Deduction Status'],
              data: filteredLeaves.map((l) => [
                DateFormat('dd MMM yyyy').format(l.date),
                l.type == 1.0 ? 'Full Day' : 'Half Day',
                'Deducted',
              ]).toList(),
            ),
          ],

          pw.Spacer(),

          // Footer / Signatures
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(
                children: [
                  pw.Container(
                    width: 100,
                    decoration: const pw.BoxDecoration(
                      border: pw.Border(bottom: pw.BorderSide(width: 0.5, color: PdfColors.grey700)),
                    ),
                  ),
                  pw.SizedBox(height: 5),
                  pw.Text("Staff Signature", style: const pw.TextStyle(fontSize: 8)),
                ],
              ),
              pw.Column(
                children: [
                  pw.Container(
                    width: 100,
                    decoration: const pw.BoxDecoration(
                      border: pw.Border(bottom: pw.BorderSide(width: 0.5, color: PdfColors.grey700)),
                    ),
                  ),
                  pw.SizedBox(height: 5),
                  pw.Text("Manager/Owner Signature", style: const pw.TextStyle(fontSize: 8)),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 20),
          pw.Divider(color: PdfColors.grey300),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('Generated on: ${DateFormat('dd MMM yyyy, hh:mm a').format(DateTime.now())}', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
              pw.Text('Statement powered by Apna Hisaab', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900)),
            ],
          ),
        ],
      ),
    );

    // Direct Print Implementation
    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: 'Salary_Report_${staff.name.replaceAll(' ', '_')}',
    );
  }

  pw.Widget _buildPdfSummaryCard(String title, String value, PdfColor color, {bool isMain = false}) {
    return pw.Container(
      margin: const pw.EdgeInsets.symmetric(horizontal: 4),
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(
        color: isMain ? color : PdfColors.white,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
        border: pw.Border.all(color: color, width: 0.5),
      ),
      child: pw.Column(
        mainAxisAlignment: pw.MainAxisAlignment.center,
        children: [
          pw.Text(title.toUpperCase(), style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold, color: isMain ? PdfColors.white : PdfColors.grey700)),
          pw.SizedBox(height: 4),
          pw.Text(value, style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: isMain ? PdfColors.white : color)),
        ],
      ),
    );
  }

  Future<void> exportAuditToPdf(
    List<ItemModel> readymadeItems,
    List<TransactionModel> allSales,
    List<TransactionModel> allPurchases,
    DateTimeRange range,
    String currency,
  ) async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (context) => [
          pw.Header(
            level: 0,
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text("CEO AUDIT REPORT", style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: PdfColors.blue800)),
                pw.Text('${DateFormat('dd MMM').format(range.start)} - ${DateFormat('dd MMM').format(range.end)}', style: pw.TextStyle(fontSize: 12, color: PdfColors.grey700)),
              ],
            ),
          ),
          pw.SizedBox(height: 20),
          pw.TableHelper.fromTextArray(
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: 10),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey800),
            cellHeight: 25,
            cellStyle: const pw.TextStyle(fontSize: 9),
            cellAlignments: {
              0: pw.Alignment.centerLeft,
              1: pw.Alignment.centerRight,
              2: pw.Alignment.centerRight,
              3: pw.Alignment.centerRight,
              4: pw.Alignment.centerRight,
              5: pw.Alignment.centerRight,
            },
            headers: ['Item Name', 'Sold Qty', 'Avg Sale', 'Avg Cost', 'Unit Profit', 'GP Margin'],
            data: readymadeItems.map((item) {
              double totalSoldQty = 0;
              double totalSalesAmt = 0;
              double totalPurchasedQty = 0;
              double totalPurchaseAmt = 0;

              for (var tx in allSales) {
                for (var s in tx.itemSnapshots) {
                  if (s.name == item.name) {
                    totalSoldQty += s.qty + s.extraQty;
                    totalSalesAmt += s.lineTotal;
                  }
                }
              }

              for (var tx in allPurchases) {
                for (var s in tx.itemSnapshots) {
                  if (s.name == item.name) {
                    totalPurchasedQty += s.qty + s.extraQty;
                    totalPurchaseAmt += s.lineTotal;
                  }
                }
                if (tx.itemSnapshots.isEmpty && tx.category == item.name) {
                  totalPurchasedQty += tx.quantity;
                  totalPurchaseAmt += tx.amount;
                }
              }

              double avgSaleRate = totalSoldQty > 0 ? totalSalesAmt / totalSoldQty : 0;
              double avgPurchaseRate = totalPurchasedQty > 0 ? totalPurchaseAmt / totalPurchasedQty : item.price ?? 0;
              double unitProfit = avgSaleRate - avgPurchaseRate;
              double gpMargin = avgSaleRate > 0 ? (unitProfit / avgSaleRate) * 100 : 0;

              return [
                item.name.toUpperCase(),
                totalSoldQty.toStringAsFixed(1),
                "$currency${avgSaleRate.toStringAsFixed(1)}",
                "$currency${avgPurchaseRate.toStringAsFixed(1)}",
                "$currency${unitProfit.toStringAsFixed(1)}",
                "${gpMargin.toStringAsFixed(1)}%",
              ];
            }).toList(),
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 20),
            child: pw.Text(
              'Generated on: ${DateFormat('dd MMM yyyy, hh:mm a').format(DateTime.now())}',
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey),
            ),
          ),
        ],
      ),
    );

    final dir = await _getReportDirectory();
    final fileName = "CEO_Audit_${DateFormat('ddMMM_HHmm').format(DateTime.now())}.pdf";
    final file = File("${dir.path}/$fileName");
    await file.writeAsBytes(await pdf.save());
    await Share.shareXFiles([XFile(file.path)], text: 'CEO Audit Report');
  }

  Future<void> exportAuditToExcel(
    List<ItemModel> readymadeItems,
    List<TransactionModel> allSales,
    List<TransactionModel> allPurchases,
    DateTimeRange range,
  ) async {
    var excel = Excel.createExcel();
    Sheet sheetObject = excel['Sheet1'];

    CellStyle headerStyle = CellStyle(
      bold: true,
      fontFamily: getFontFamily(FontFamily.Arial),
      backgroundColorHex: ExcelColor.fromHexString("#2196F3"),
      fontColorHex: ExcelColor.fromHexString("#FFFFFF"),
    );

    List<String> headers = ['Item Name', 'Sold Qty', 'Total Sales', 'Avg Sale Price', 'Avg Cost Price', 'Profit Per Unit', 'GP Margin %'];
    for (var i = 0; i < headers.length; i++) {
      var cell = sheetObject.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0));
      cell.value = TextCellValue(headers[i]);
      cell.cellStyle = headerStyle;
    }

    for (var i = 0; i < readymadeItems.length; i++) {
      var item = readymadeItems[i];
      int row = i + 1;

      double totalSoldQty = 0;
      double totalSalesAmt = 0;
      double totalPurchasedQty = 0;
      double totalPurchaseAmt = 0;

      for (var tx in allSales) {
        for (var s in tx.itemSnapshots) {
          if (s.name == item.name) {
            totalSoldQty += s.qty + s.extraQty;
            totalSalesAmt += s.lineTotal;
          }
        }
      }

      for (var tx in allPurchases) {
        for (var s in tx.itemSnapshots) {
          if (s.name == item.name) {
            totalPurchasedQty += s.qty + s.extraQty;
            totalPurchaseAmt += s.lineTotal;
          }
        }
        if (tx.itemSnapshots.isEmpty && tx.category == item.name) {
          totalPurchasedQty += tx.quantity;
          totalPurchaseAmt += tx.amount;
        }
      }

      double avgSaleRate = totalSoldQty > 0 ? totalSalesAmt / totalSoldQty : 0;
      double avgPurchaseRate = totalPurchasedQty > 0 ? totalPurchaseAmt / totalPurchasedQty : item.price ?? 0;
      double unitProfit = avgSaleRate - avgPurchaseRate;
      double gpMargin = avgSaleRate > 0 ? (unitProfit / avgSaleRate) * 100 : 0;

      sheetObject.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)).value = TextCellValue(item.name.toUpperCase());
      sheetObject.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row)).value = DoubleCellValue(totalSoldQty);
      sheetObject.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: row)).value = DoubleCellValue(totalSalesAmt);
      sheetObject.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: row)).value = DoubleCellValue(avgSaleRate);
      sheetObject.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: row)).value = DoubleCellValue(avgPurchaseRate);
      sheetObject.cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: row)).value = DoubleCellValue(unitProfit);
      sheetObject.cell(CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: row)).value = DoubleCellValue(gpMargin);
    }

    try {
      final dir = await _getReportDirectory();
      final fileName = "CEO_Audit_${DateFormat('ddMMM_HHmm').format(DateTime.now())}.xlsx";
      final path = "${dir.path}/$fileName";

      var fileBytes = excel.save();
      if (fileBytes != null) {
        File(path)
          ..createSync(recursive: true)
          ..writeAsBytesSync(fileBytes);
        await Share.shareXFiles([XFile(path)], text: 'CEO Audit Report');
      }
    } catch (e) {
      debugPrint("Excel Audit Export Error: $e");
    }
  }
}
