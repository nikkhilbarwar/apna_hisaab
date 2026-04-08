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
import 'package:printing/printing.dart';
import '../core/database/database_helper.dart';
import '../models/transaction_model.dart';
import '../models/item_model.dart';

class ExportService {
  Future<Directory> _getReportDirectory() async {
    Directory? baseDir;
    if (Platform.isAndroid) {
      baseDir = Directory('/storage/emulated/0/Documents/ApnaHisaab_Reports');
    } else {
      baseDir = await getApplicationDocumentsDirectory();
    }
    if (!await baseDir.exists()) {
      await baseDir.create(recursive: true);
    }
    return baseDir;
  }

  Future<Directory> _getBackupDirectory() async {
    Directory? baseDir;
    if (Platform.isAndroid) {
      baseDir = Directory('/storage/emulated/0/Documents/ApnaHisaab_Backups');
    } else {
      baseDir = await getApplicationDocumentsDirectory();
    }
    if (!await baseDir.exists()) {
      await baseDir.create(recursive: true);
    }
    return baseDir;
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
      final fileName = "${title}_${DateTime.now().millisecondsSinceEpoch}.xlsx";
      final path = "${dir.path}/$fileName";
      
      var fileBytes = excel.save();
      if (fileBytes != null) {
        File(path)
          ..createSync(recursive: true)
          ..writeAsBytesSync(fileBytes);
        await Share.shareXFiles([XFile(path)], text: '$title Report');
      }
    } catch (e) {
      print("Excel Export Error: $e");
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
      final fileName = "${title}_${DateTime.now().millisecondsSinceEpoch}.pdf";
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
      print("PDF Export Error: $e");
    }
  }

  /// Save Bill as PDF and return path
  Future<String?> saveBillAsPdf(TransactionModel tx, String businessName, {List<ItemModel>? masterItems, String qrPath = "", String qrLabel = ""}) async {
    final pdf = pw.Document();
    final uid = FirebaseAuth.instance.currentUser?.uid ?? "";
    final prefs = await SharedPreferences.getInstance();
    
    final logoPath = prefs.getString('logo_path_$uid') ?? "";
    final address = prefs.getString('address_$uid') ?? "";
    final contact = prefs.getString('contact_$uid') ?? "";

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
    
    double subtotal = 0;
    if (snapshots.isNotEmpty) {
      for (var s in snapshots) {
        subtotal += s.lineTotal;
      }
    } else {
      subtotal = tx.amount + tx.discountValue - tx.taxValue;
    }

    double discount = tx.discountValue;
    double totalAfterDiscount = subtotal - discount;
    double taxAmount = tx.amount - totalAfterDiscount;
    if (taxAmount.abs() < 0.1) taxAmount = 0; 

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.roll80, 
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Center(
              child: pw.Column(
                children: [
                  if (logoImage != null)
                    pw.Container(
                      width: 50, height: 50,
                      margin: const pw.EdgeInsets.only(bottom: 5),
                      child: pw.Image(logoImage),
                    ),
                  pw.Text(businessName.toUpperCase(), style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14)),
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
            pw.Center(child: pw.Text(isPurchase ? "PURCHASE VOUCHER" : "CASH MEMO", style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, letterSpacing: 1))),
            pw.Divider(thickness: 0.5),
            
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(isPurchase ? "Voucher No: ${tx.id}" : "Bill No: ${tx.id}", style: const pw.TextStyle(fontSize: 8)),
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
                pw.Expanded(flex: 2, child: pw.Text("QTY", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8), textAlign: pw.TextAlign.center)),
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
                    pw.Expanded(flex: 2, child: pw.Text("1", style: const pw.TextStyle(fontSize: 8), textAlign: pw.TextAlign.center)),
                    pw.Expanded(flex: 2, child: pw.Text(subtotal.toStringAsFixed(0), style: const pw.TextStyle(fontSize: 8), textAlign: pw.TextAlign.right)),
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

                // Sub-detail line: @ Rate | Method | Extras
                List<String> details = [];
                details.add("@ ${item.price.toStringAsFixed(0)}");
                if (item.servingMethod.isNotEmpty) details.add(item.servingMethod);
                if (item.extraQty > 0) {
                  String exQty = item.extraQty % 1 == 0 ? item.extraQty.toInt().toString() : item.extraQty.toString();
                  details.add("+ Extra PC'S: $exQty @ ${item.extraPrice.toStringAsFixed(0)}");
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
                          pw.Expanded(flex: 2, child: pw.Text(qtyStr, style: const pw.TextStyle(fontSize: 8), textAlign: pw.TextAlign.center)),
                          pw.Expanded(flex: 2, child: pw.Text(item.lineTotal.toStringAsFixed(0), style: const pw.TextStyle(fontSize: 8), textAlign: pw.TextAlign.right)),
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
            
            _buildPdfBreakdownRow("Subtotal", subtotal.toStringAsFixed(0)),
            if (discount > 0) _buildPdfBreakdownRow("Discount", "-${discount.toStringAsFixed(0)}"),
            if (taxAmount > 0) _buildPdfBreakdownRow("Tax", taxAmount.toStringAsFixed(0)),
            
            pw.SizedBox(height: 4),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text("ITEM COUNT: ${snapshots.length}", style: const pw.TextStyle(fontSize: 8)),
                pw.Text("GRAND TOTAL: ${tx.amount.toStringAsFixed(0)}", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12)),
              ],
            ),
            
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

            pw.Center(child: pw.Text(isPurchase ? "Stock Inward Successful" : "Thank You! Visit Again", style: pw.TextStyle(fontSize: 9, fontStyle: pw.FontStyle.italic))),
            pw.SizedBox(height: 4),
            
            pw.Divider(thickness: 0.5),
            pw.Center(child: pw.Text("POWERED BY: The Griller Zone", style: pw.TextStyle(fontSize: 6, fontWeight: pw.FontWeight.bold, color: PdfColors.grey800))),
            pw.Center(child: pw.Text("Developer: Nikkhil | +91 9992256959", style: const pw.TextStyle(fontSize: 5, color: PdfColors.grey700))),
            pw.Center(child: pw.Text("Terms: This is a computer generated invoice.", style: const pw.TextStyle(fontSize: 5, color: PdfColors.grey700))),
            pw.SizedBox(height: 5),
          ],
        ),
      ),
    );

    try {
      final dir = await _getReportDirectory();
      final fileName = "Bill_${tx.id}_${DateTime.now().millisecondsSinceEpoch}.pdf";
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
      print("Bill PDF Error: $e");
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

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.roll80,
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            // Header: Restaurant Details
            pw.Center(
              child: pw.Column(
                children: [
                  pw.Text(businessName.toUpperCase(), style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14)),
                  if (address.isNotEmpty) pw.Text(address, style: const pw.TextStyle(fontSize: 7), textAlign: pw.TextAlign.center),
                  if (contact.isNotEmpty) pw.Text("PH: $contact", style: const pw.TextStyle(fontSize: 7)),
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
            pw.Divider(thickness: 0.5),
            pw.SizedBox(height: 5),
            pw.Center(child: pw.Text(DateFormat('dd-MM-yyyy').format(tx.date), style: const pw.TextStyle(fontSize: 8))),
          ],
        ),
      ),
    );

    try {
      final dir = await _getReportDirectory();
      final fileName = "KOT_${tx.id}_${DateTime.now().millisecondsSinceEpoch}.pdf";
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
      print("KOT PDF Error: $e");
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
      print("Auto Backup Error: $e");
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

      final fileName = "Backup_${user.uid}_${DateFormat('ddMMM_yyyy_HHmm').format(DateTime.now())}.json";
      final file = File("${baseDir.path}/$fileName");
      await file.writeAsString(jsonString);
      return file.path;
    } catch (e) {
      print("Backup Error: $e");
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

    final user = FirebaseAuth.instance.currentUser;
    final uid = user?.uid ?? "";

    // Profile settings from SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    Map<String, dynamic> profileSettings = {
      'business_name': prefs.getString('business_name_$uid'),
      'owner_name': prefs.getString('owner_name_$uid'),
      'contact': prefs.getString('contact_$uid'),
      'address': prefs.getString('address_$uid'),
      'logo_path': prefs.getString('logo_path_$uid'),
      'cloud_sync': prefs.getBool('cloud_sync_$uid'),
      'currency': prefs.getString('currency_$uid'),
      'theme_color': prefs.getInt('theme_color_$uid'),
      'tax_percentage': prefs.getDouble('tax_percentage_$uid'),
      'is_dark_mode': prefs.getBool('is_dark_mode_$uid'),
      'license_key': prefs.getString('license_key_$uid'),
      'is_app_activated': prefs.getBool('is_app_activated_$uid'),
      'is_lifetime': prefs.getBool('is_lifetime_$uid'),
      'expiry_date': prefs.getString('expiry_date_$uid'),
    };

    return {
      'backup_version': 2.0,
      'backup_uid': uid, // Security check
      'backup_date': DateTime.now().toIso8601String(),
      'transactions': transactions.map((t) => t.toMap()).toList(),
      'items': items.map((i) => i.toMap()).toList(),
      'categories': categories.map((c) => c.toMap()).toList(),
      'staff': staff.map((s) => s.toMap()).toList(),
      'suppliers': suppliers.map((s) => s.toMap()).toList(),
      'profile_settings': profileSettings,
    };
  }

  Future<bool> restoreFromBackup(File file) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return false;
      final uid = user.uid;

      String content = await file.readAsString();
      Map<String, dynamic> data = jsonDecode(content);
      
      // Verify UID if available in backup (Security Check)
      if (data.containsKey('backup_uid') && data['backup_uid'] != uid) {
        print("Restore Error: Backup belongs to a different user!");
        return false;
      }

      final db = await DatabaseHelper.instance.database;
      
      await db.transaction((txn) async {
        // User-Specific Database automatically handles clearing current user's data
        await txn.delete('transactions');
        await txn.delete('items');
        await txn.delete('categories');
        await txn.delete('staff');
        await txn.delete('suppliers');

        if (data['items'] != null) {
          for (var item in data['items']) await txn.insert('items', item);
        }
        if (data['categories'] != null) {
          for (var cat in data['categories']) await txn.insert('categories', cat);
        }
        if (data['transactions'] != null) {
          for (var tx in data['transactions']) await txn.insert('transactions', tx);
        }
        if (data['staff'] != null) {
          for (var s in data['staff']) await txn.insert('staff', s);
        }
        if (data['suppliers'] != null) {
          for (var s in data['suppliers']) await txn.insert('suppliers', s);
        }
      });

      // Restore Profile Settings (User-Specific SharedPreferences)
      if (data['profile_settings'] != null) {
        final prefs = await SharedPreferences.getInstance();
        final p = data['profile_settings'] as Map<String, dynamic>;
        
        if (p['business_name'] != null) await prefs.setString('business_name_$uid', p['business_name']);
        if (p['owner_name'] != null) await prefs.setString('owner_name_$uid', p['owner_name']);
        if (p['contact'] != null) await prefs.setString('contact_$uid', p['contact']);
        if (p['address'] != null) await prefs.setString('address_$uid', p['address']);
        if (p['logo_path'] != null) await prefs.setString('logo_path_$uid', p['logo_path']);
        if (p['cloud_sync'] != null) await prefs.setBool('cloud_sync_$uid', p['cloud_sync']);
        if (p['currency'] != null) await prefs.setString('currency_$uid', p['currency']);
        if (p['theme_color'] != null) await prefs.setInt('theme_color_$uid', p['theme_color']);
        if (p['tax_percentage'] != null) await prefs.setDouble('tax_percentage_$uid', p['tax_percentage']);
        if (p['is_dark_mode'] != null) await prefs.setBool('is_dark_mode_$uid', p['is_dark_mode']);
        if (p['license_key'] != null) await prefs.setString('license_key_$uid', p['license_key']);
        if (p['is_app_activated'] != null) await prefs.setBool('is_app_activated_$uid', p['is_app_activated']);
        if (p['is_lifetime'] != null) await prefs.setBool('is_lifetime_$uid', p['is_lifetime']);
        if (p['expiry_date'] != null) await prefs.setString('expiry_date_$uid', p['expiry_date']);
      }

      return true;
    } catch (e) {
      print("Restore Error: $e");
      return false;
    }
  }
}
