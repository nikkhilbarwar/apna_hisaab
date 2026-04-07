import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_pos_printer_platform_image_3/flutter_pos_printer_platform_image_3.dart';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:image/image.dart' as img;
import '../models/transaction_model.dart';
import '../models/printer_config.dart';
import '../providers/printer_provider.dart';
import '../providers/profile_provider.dart';
import '../providers/item_provider.dart';
import 'export_service.dart';

class PrintService {
  final PrinterManager _printerManager = PrinterManager.instance;

  /// --- Smart Printing Logic ---
  /// Handles both Bill and KOT based on configuration.
  Future<void> printSmart(BuildContext context, TransactionModel tx, {bool isManualReprint = false}) async {
    final printerProv = Provider.of<PrinterProvider>(context, listen: false);
    final profile = Provider.of<ProfileProvider>(context, listen: false);
    final items = Provider.of<ItemProvider>(context, listen: false).items;
    
    // Normalize status for reliable checking
    final status = tx.status.toLowerCase().trim();
    final isPendingStatus = status == 'pending' || status == 'draft';

    // 1. Handle Bill Printing
    // Logic: Print if (Manual Reprint) OR (Auto-Print is ON AND it's NOT a pending order)
    bool shouldPrintBill = isManualReprint || (profile.isAutoPrintEnabled && !isPendingStatus);
    
    if (shouldPrintBill && printerProv.billPrinter.isEnabled) {
      if (printerProv.billPrinter.type == AppPrinterType.pdf) {
        await ExportService().saveBillAsPdf(tx, profile.businessName, masterItems: items, qrPath: profile.qrPath, qrLabel: profile.qrLabel);
      } else {
        await _printToDevice(
          tx: tx,
          config: printerProv.billPrinter,
          businessName: profile.businessName,
          address: profile.address,
          contact: profile.contact,
          masterItems: items,
          qrPath: profile.qrPath,
          qrLabel: profile.qrLabel,
          isKot: false,
        );
      }
    }

    // 2. Handle KOT Printing
    // Auto-print KOT for BOTH Pending and Completed orders if enabled.
    // We don't print KOT on manual reprints typically.
    if (profile.isAutoPrintEnabled && printerProv.kotPrinter.isEnabled && !isManualReprint) {
      if (printerProv.kotPrinter.type == AppPrinterType.pdf) {
        await ExportService().saveKotAsPdf(tx, profile.businessName);
      } else {
        await _printToDevice(
          tx: tx,
          config: printerProv.kotPrinter,
          businessName: profile.businessName,
          address: profile.address,
          contact: profile.contact,
          masterItems: items,
          isKot: true,
        );
      }
    }
  }

  Future<void> _printToDevice({
    required TransactionModel tx,
    required PrinterConfig config,
    required String businessName,
    required String address,
    required String contact,
    required List<dynamic> masterItems,
    String qrPath = "",
    String qrLabel = "",
    required bool isKot,
  }) async {
    final profile = await CapabilityProfile.load();
    final paperSize = config.paperWidth == 58 ? PaperSize.mm58 : PaperSize.mm80;
    final generator = Generator(paperSize, profile);
    List<int> bytes = [];

    if (isKot) {
      bytes += _generateKotBytes(generator, tx, businessName, address, contact);
    } else {
      bytes += _generateBillBytes(generator, tx, businessName, address, contact, masterItems, qrPath, qrLabel, config.paperWidth);
    }

    if (config.type == AppPrinterType.bluetooth && config.bluetoothDevice != null) {
      await _printerManager.connect(
        type: PrinterType.bluetooth, 
        model: BluetoothPrinterInput(
          name: config.bluetoothDevice!.name, 
          address: config.bluetoothDevice!.address ?? '',
          isBle: false
        )
      );
      await _printerManager.send(type: PrinterType.bluetooth, bytes: bytes);
    } else if (config.type == AppPrinterType.network && config.networkIp.isNotEmpty) {
      await _printerManager.connect(
        type: PrinterType.network, 
        model: TcpPrinterInput(ipAddress: config.networkIp)
      );
      await _printerManager.send(type: PrinterType.network, bytes: bytes);
    }
  }

  List<int> _generateBillBytes(Generator generator, TransactionModel tx, String businessName, String address, String contact, List<dynamic> masterItems, String qrPath, String qrLabel, int paperWidth) {
    List<int> bytes = [];
    String token = tx.token;
    bytes += generator.text(businessName.toUpperCase(), 
        styles: const PosStyles(align: PosAlign.center, bold: true, height: PosTextSize.size2, width: PosTextSize.size2));
    if (address.isNotEmpty) bytes += generator.text(address, styles: const PosStyles(align: PosAlign.center));
    if (contact.isNotEmpty) bytes += generator.text("PH: $contact", styles: const PosStyles(align: PosAlign.center));
    
    // Token: Under address, right-aligned (Corner)
    if (token.isNotEmpty) {
      bytes += generator.text("TOKEN: $token", styles: const PosStyles(align: PosAlign.right, bold: true));
      bytes += generator.feed(1);
    }

    bytes += generator.hr();
    bytes += generator.text("TAX INVOICE", styles: const PosStyles(align: PosAlign.center, bold: true));
    
    String billId = tx.id?.toString() ?? '0';
    String shortId = billId.length > 5 ? billId.substring(billId.length - 5) : billId;

    bytes += generator.row([
      PosColumn(text: "Bill No: $shortId", width: 6),
      PosColumn(text: DateFormat('dd-MM-yy HH:mm').format(tx.date), width: 6, styles: const PosStyles(align: PosAlign.right)),
    ]);

    // Add Table Number if available
    String table = "";
    if (tx.itemSnapshots.isNotEmpty) {
      table = tx.itemSnapshots.first.tableNumber;
    }
    if (table.isNotEmpty && table != '0') {
      bytes += generator.text("TABLE: $table", styles: const PosStyles(bold: true));
    }

    bytes += generator.hr();

    for (var i in tx.itemSnapshots) {
      double q = i.qty;
      double p = i.price;
      double eq = i.extraQty;
      double ep = i.extraPrice;
      
      double lineTotal = i.lineTotal;

      // Qty Display Logic (Remove 0.5)
      String qtyStr = q == 0.5 ? "Half" : (q % 1 == 0 ? q.toInt().toString() : q.toString());

      // Clean name from redundant (Half)/(Full)
      String cleanName = i.name.replaceAll(RegExp(r'\s*\((Half|Full)\)', caseSensitive: false), '').trim();

      // Variant Display Logic: Hide if Full or Empty
      String variant = i.variant.trim();
      bool hideVariant = variant.toLowerCase() == 'full' || variant.toLowerCase() == 'none' || variant.isEmpty || variant.toLowerCase() == 'half';
      
      String displayName = hideVariant ? cleanName : "$cleanName ($variant)";

      bytes += generator.text(displayName, styles: const PosStyles(bold: true));
      
      bytes += generator.row([
        PosColumn(text: "$qtyStr x ${p.toStringAsFixed(0)}", width: 8),
        PosColumn(text: lineTotal.toStringAsFixed(0), width: 4, styles: const PosStyles(align: PosAlign.right)),
      ]);

      if (eq > 0) {
        String exStr = eq % 1 == 0 ? eq.toInt().toString() : eq.toString();
        bytes += generator.text("  + Extra PC'S: $exStr @ ${ep.toStringAsFixed(0)}");
      }
    }

    bytes += generator.hr();
    bytes += generator.row([
      PosColumn(text: "GRAND TOTAL", width: 6, styles: const PosStyles(bold: true, height: PosTextSize.size2)),
      PosColumn(text: "Rs. ${tx.amount.toStringAsFixed(0)}", width: 6, styles: const PosStyles(align: PosAlign.right, bold: true, height: PosTextSize.size2)),
    ]);
    bytes += generator.hr();

    // Add QR Code for Payment/Review if available
    if (qrPath.isNotEmpty && File(qrPath).existsSync()) {
      try {
        final img.Image? image = img.decodeImage(File(qrPath).readAsBytesSync());
        if (image != null) {
          // Resize image based on paper width (58mm: ~384px, 80mm: ~576px)
          int qrWidth = paperWidth == 58 ? 180 : 250;
          final img.Image resized = img.copyResize(image, width: qrWidth);
          bytes += generator.image(resized, align: PosAlign.center);
          bytes += generator.text(qrLabel.isNotEmpty ? qrLabel : "Scan for Payment/Review", styles: const PosStyles(align: PosAlign.center));
          // bytes += generator.feed(1); // User wants less gap
        }
      } catch (e) {
        debugPrint("Error printing QR: $e");
      }
    }

    bytes += generator.text("Thank You! Visit Again", styles: const PosStyles(align: PosAlign.center));
    bytes += generator.feed(1);
    bytes += generator.cut();
    return bytes;
  }

  List<int> _generateKotBytes(Generator generator, TransactionModel tx, String businessName, String address, String contact) {
    List<int> bytes = [];
    
    // Header: Restaurant Details (Idea 4 inspired)
    bytes += generator.text(businessName.toUpperCase(), 
        styles: const PosStyles(align: PosAlign.center, bold: true, height: PosTextSize.size2, width: PosTextSize.size2));
    if (address.isNotEmpty) bytes += generator.text(address, styles: const PosStyles(align: PosAlign.center));
    if (contact.isNotEmpty) bytes += generator.text("PH: $contact", styles: const PosStyles(align: PosAlign.center));
    bytes += generator.hr();

    bytes += generator.text("KITCHEN ORDER", styles: const PosStyles(align: PosAlign.center, bold: true));

    // Token: High Contrast / Large (Idea 1 inspired)
    if (tx.token.isNotEmpty) {
      bytes += generator.hr(ch: '=');
      bytes += generator.text("TOKEN: ${tx.token}", 
          styles: const PosStyles(align: PosAlign.center, bold: true, height: PosTextSize.size3, width: PosTextSize.size3));
      bytes += generator.hr(ch: '=');
    }
    bytes += generator.feed(1);

    String orderId = tx.id?.toString() ?? '0';
    String shortOrderId = orderId.length > 5 ? orderId.substring(orderId.length - 5) : orderId;

    bytes += generator.row([
      PosColumn(text: "Order ID: #$shortOrderId", width: 7),
      PosColumn(text: DateFormat('HH:mm').format(tx.date), width: 5, styles: const PosStyles(align: PosAlign.right)),
    ]);
    
    // Add Table Number if available
    String table = "";
    if (tx.itemSnapshots.isNotEmpty) {
      table = tx.itemSnapshots.first.tableNumber;
    }
    if (table.isNotEmpty && table != '0') {
      bytes += generator.text("TABLE: $table", styles: const PosStyles(align: PosAlign.center, bold: true, height: PosTextSize.size2, width: PosTextSize.size2));
    }
    
    bytes += generator.hr();

    for (var i in tx.parsedItems) {
      String name = i['name'] ?? 'Item';
      String variant = i['variant'] ?? '';
      double qty = double.tryParse(i['qty']?.toString() ?? '1') ?? 1;
      double extraQty = double.tryParse(i['extra_qty']?.toString() ?? '0') ?? 0;
      String method = i['serving_method'] ?? 'Dine-in';
      
      // Handle 0.5 for Half items (User request: remove 0.5)
      String qtyStr;
      if (qty == 0.5) {
        qtyStr = "Half";
      } else {
        qtyStr = qty % 1 == 0 ? qty.toInt().toString() : qty.toString();
      }
      
      // Clean name from redundant (Half)/(Full)
      String cleanName = name.replaceAll(RegExp(r'\s*\((Half|Full)\)', caseSensitive: false), '').trim();

      // Actionable Checkbox [ ] (Idea 4)
      String v = variant.trim().toLowerCase();
      bool hideV = v == 'full' || v == 'none' || v == '' || v == 'half';
      String variantDisplay = hideV ? "" : "($variant)";

      bytes += generator.text("[ ] $qtyStr x $cleanName $variantDisplay",
          styles: const PosStyles(bold: true, height: PosTextSize.size1, width: PosTextSize.size1));
      
      if (extraQty > 0) {
        String exStr = extraQty % 1 == 0 ? extraQty.toInt().toString() : extraQty.toString();
        bytes += generator.text("    + EXTRA PC'S: $exStr", styles: const PosStyles(bold: true));
      }
      
      if (method.toLowerCase() == 'takeaway') {
        bytes += generator.text("    [ TAKEAWAY ]", styles: const PosStyles(bold: true));
      }
    }

    bytes += generator.hr();
    bytes += generator.text(DateFormat('dd-MM-yyyy').format(tx.date), styles: const PosStyles(align: PosAlign.center));
    bytes += generator.feed(2);
    bytes += generator.cut();
    return bytes;
  }
}
