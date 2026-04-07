import 'package:flutter/material.dart';
import 'package:flutter_pos_printer_platform_image_3/flutter_pos_printer_platform_image_3.dart';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/transaction_model.dart';
import '../providers/printer_provider.dart';
import '../providers/profile_provider.dart';
import '../providers/item_provider.dart';
import 'export_service.dart';

class PrintService {
  final PrinterManager _printerManager = PrinterManager.instance;

  /// --- Smart Printing Logic ---
  /// Respects 'Auto-Print' setting and routes to appropriate device.
  Future<void> printSmart(BuildContext context, TransactionModel tx, {bool isManualReprint = false}) async {
    final printer = Provider.of<PrinterProvider>(context, listen: false);
    final profile = Provider.of<ProfileProvider>(context, listen: false);
    final items = Provider.of<ItemProvider>(context, listen: false).items;

    // CRITICAL: If auto-print is OFF and this is NOT a manual reprint, do nothing.
    if (!profile.isAutoPrintEnabled && !isManualReprint) {
      debugPrint("Auto-print is disabled. Skipping bill generation.");
      return;
    }

    if (printer.selectedType == AppPrinterType.pdf) {
      await ExportService().saveBillAsPdf(tx, profile.businessName, masterItems: items);
    } else {
      await printReceipt(
        tx: tx,
        businessName: profile.businessName,
        address: profile.address,
        contact: profile.contact,
        type: printer.selectedType,
        paperWidth: printer.paperWidth,
        btDevice: printer.selectedBluetoothDevice,
        ipAddress: printer.networkIp,
        masterItems: items,
      );
    }
  }

  /// --- Bluetooth/Network/USB Printing (Unified) ---
  Future<void> printReceipt({
    required TransactionModel tx,
    required String businessName,
    required String address,
    required String contact,
    required AppPrinterType type,
    required int paperWidth,
    required List<dynamic> masterItems,
    String? ipAddress,
    PrinterDevice? btDevice,
  }) async {
    final profile = await CapabilityProfile.load();
    final paperSize = paperWidth == 58 ? PaperSize.mm58 : PaperSize.mm80;
    final generator = Generator(paperSize, profile);
    List<int> bytes = [];

    // --- Generate Receipt ---
    bytes += generator.text(businessName.toUpperCase(), 
        styles: const PosStyles(align: PosAlign.center, bold: true, height: PosTextSize.size2, width: PosTextSize.size2));
    if (address.isNotEmpty) bytes += generator.text(address, styles: const PosStyles(align: PosAlign.center));
    if (contact.isNotEmpty) bytes += generator.text("PH: $contact", styles: const PosStyles(align: PosAlign.center));
    bytes += generator.hr();
    bytes += generator.text("TAX INVOICE", styles: const PosStyles(align: PosAlign.center, bold: true));
    bytes += generator.row([
      PosColumn(text: "Bill No: ${tx.id}", width: 6),
      PosColumn(text: DateFormat('dd-MM-yy').format(tx.date), width: 6, styles: const PosStyles(align: PosAlign.right)),
    ]);
    bytes += generator.hr();

    double subtotal = 0;
    for (var i in tx.parsedItems) {
      double q = double.tryParse(i['qty'] ?? '0') ?? 0;
      double p = double.tryParse(i['price'] ?? '0') ?? 0;
      double eq = double.tryParse(i['extra_qty'] ?? '0') ?? 0;
      double ep = double.tryParse(i['extra_price'] ?? '0') ?? 0;
      
      double itemPrice = 0;
      dynamic master;
      try { master = masterItems.firstWhere((it) => it.name == i['name']); } catch(_) {}

      if (master != null && master.halfPrice != null && (master.halfPrice as num) > 0) {
        int fullPlates = q.floor();
        double remainder = q - fullPlates;
        double masterP = (master.price as num? ?? 0.0).toDouble();
        double masterH = (master.halfPrice as num? ?? 0.0).toDouble();
        itemPrice = (fullPlates * masterP) + (remainder > 0 ? masterH : 0.0);
      } else {
        itemPrice = q * p;
      }
      
      double lineTotal = itemPrice + (eq * ep);
      subtotal += lineTotal;

      bytes += generator.text("${i['name']} ${i['variant'] ?? ''}", styles: const PosStyles(bold: true));
      bytes += generator.row([
        PosColumn(text: "${i['qty']} x ${p.toStringAsFixed(0)}", width: 8),
        PosColumn(text: lineTotal.toStringAsFixed(0), width: 4, styles: const PosStyles(align: PosAlign.right)),
      ]);
    }

    bytes += generator.hr();
    
    // --- Financial Breakdown ---
    double discount = tx.discountValue;
    double totalTax = tx.amount - (subtotal - discount);
    if (totalTax < 0.5) totalTax = 0;

    bytes += generator.row([
      PosColumn(text: "Subtotal", width: 8),
      PosColumn(text: subtotal.toStringAsFixed(0), width: 4, styles: const PosStyles(align: PosAlign.right)),
    ]);

    if (discount > 0) {
      bytes += generator.row([
        PosColumn(text: "Discount", width: 8),
        PosColumn(text: "-${discount.toStringAsFixed(0)}", width: 4, styles: const PosStyles(align: PosAlign.right)),
      ]);
    }

    if (totalTax > 0) {
      bytes += generator.row([
        PosColumn(text: "Tax", width: 8),
        PosColumn(text: totalTax.toStringAsFixed(0), width: 4, styles: const PosStyles(align: PosAlign.right)),
      ]);
    }

    bytes += generator.hr();
    bytes += generator.row([
      PosColumn(text: "GRAND TOTAL", width: 6, styles: const PosStyles(bold: true, height: PosTextSize.size2)),
      PosColumn(text: "Rs. ${tx.amount.toStringAsFixed(0)}", width: 6, styles: const PosStyles(align: PosAlign.right, bold: true, height: PosTextSize.size2)),
    ]);
    bytes += generator.hr();
    bytes += generator.text("Thank You! Visit Again", styles: const PosStyles(align: PosAlign.center));
    bytes += generator.feed(2);
    bytes += generator.cut();

    if (type == AppPrinterType.bluetooth && btDevice != null) {
      await _printerManager.connect(
        type: PrinterType.bluetooth, 
        model: BluetoothPrinterInput(
          name: btDevice.name, 
          address: btDevice.address ?? '',
          isBle: false
        )
      );
      await _printerManager.send(type: PrinterType.bluetooth, bytes: bytes);
    } else if (type == AppPrinterType.network && ipAddress != null) {
      await _printerManager.connect(
        type: PrinterType.network, 
        model: TcpPrinterInput(ipAddress: ipAddress)
      );
      await _printerManager.send(type: PrinterType.network, bytes: bytes);
    }
  }
}
