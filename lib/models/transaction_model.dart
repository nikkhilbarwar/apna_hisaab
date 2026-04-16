import 'dart:convert';
import 'package:flutter/foundation.dart';

class TransactionItemSnapshot {
  final int id;
  final String name;
  final String category;
  final double qty;
  final String unit;
  final String variant;
  final double price; // Portions price when saved
  final double purchasePrice; // Cost price for Ready Made items
  final double transportCost; // Transport/Rent per unit
  final double fullPrice; 
  final double halfPrice; 
  final double extraQty;
  final double extraPrice;
  final String servingMethod;
  final String tableNumber;
  final bool checked;
  final String itemType;

  TransactionItemSnapshot({
    required this.id,
    required this.name,
    required this.category,
    required this.qty,
    required this.unit,
    required this.variant,
    required this.price,
    this.purchasePrice = 0,
    this.transportCost = 0,
    this.fullPrice = 0,
    this.halfPrice = 0,
    required this.extraQty,
    required this.extraPrice,
    required this.servingMethod,
    required this.tableNumber,
    this.checked = false,
    this.itemType = 'regular',
  });

  TransactionItemSnapshot copyWith({
    int? id,
    String? name,
    String? category,
    double? qty,
    String? unit,
    String? variant,
    double? price,
    double? purchasePrice,
    double? transportCost,
    double? fullPrice,
    double? halfPrice,
    double? extraQty,
    double? extraPrice,
    String? servingMethod,
    String? tableNumber,
    bool? checked,
    String? itemType,
  }) {
    return TransactionItemSnapshot(
      id: id ?? this.id,
      name: name ?? this.name,
      category: category ?? this.category,
      qty: qty ?? this.qty,
      unit: unit ?? this.unit,
      variant: variant ?? this.variant,
      price: price ?? this.price,
      purchasePrice: purchasePrice ?? this.purchasePrice,
      transportCost: transportCost ?? this.transportCost,
      fullPrice: fullPrice ?? this.fullPrice,
      halfPrice: halfPrice ?? this.halfPrice,
      extraQty: extraQty ?? this.extraQty,
      extraPrice: extraPrice ?? this.extraPrice,
      servingMethod: servingMethod ?? this.servingMethod,
      tableNumber: tableNumber ?? this.tableNumber,
      checked: checked ?? this.checked,
      itemType: itemType ?? this.itemType,
    );
  }

  /// Logic Fix: Robust portion math for both New and Old transactions
  double get lineTotal {
    double base;
    // 1. Check New Logic (Full and Half prices saved in JSON)
    if (fullPrice > 0 && halfPrice > 0) {
      int fullPortions = qty.floor();
      double remainder = qty - fullPortions;
      base = (fullPortions * fullPrice) + (remainder > 0 ? halfPrice : 0);
    }
    // 2. Check Old Logic (Fallback)
    else {
      // Logic Fix: Trust the price saved in the snapshot.
      // If it's an old 'half' entry with qty 0.5, price is already the portion price.
      // We only normalize if the user explicitly meant for 'price' to be a 'per-unit' rate.
      if (variant.toLowerCase() == 'half' && qty == 0.5) {
        base = price; // It was 0.5 qty at 'price', so total is 'price'
      } else {
        base = qty * price;
      }
    }

    // Extras Logic: (Qty * Price)
    double totalExtra = (extraQty > 0) ? (extraQty * extraPrice) : extraPrice;

    return base + totalExtra;
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'category': category,
      'qty': qty,
      'unit': unit,
      'variant': variant,
      'price': price,
      'purchase_price': purchasePrice,
      'transport_cost': transportCost,
      'full_price': fullPrice,
      'half_price': halfPrice,
      'extra_qty': extraQty,
      'extra_price': extraPrice,
      'serving_method': servingMethod,
      'table_number': tableNumber,
      'checked': checked,
      'item_type': itemType,
    };
  }

  factory TransactionItemSnapshot.fromMap(Map<dynamic, dynamic> map) {
    bool toBool(dynamic value, {bool defaultValue = false}) {
      if (value == null) return defaultValue;
      if (value is bool) return value;
      if (value is num) return value != 0;
      if (value is String) {
        final lower = value.toLowerCase();
        return lower == 'true' || lower == '1' || lower == 'yes';
      }
      return defaultValue;
    }

    return TransactionItemSnapshot(
      id: int.tryParse(map['id']?.toString() ?? '0') ?? 0,
      name: map['name']?.toString() ?? 'Item',
      category: map['category']?.toString() ?? 'General',
      qty: double.tryParse(map['qty']?.toString() ?? '0') ?? 0.0,
      unit: map['unit']?.toString() ?? '',
      variant: map['variant']?.toString() ?? 'Full',
      price: double.tryParse(map['price']?.toString() ?? '0') ?? 0.0,
      purchasePrice: double.tryParse(map['purchase_price']?.toString() ?? '0') ?? 0.0,
      transportCost: double.tryParse(map['transport_cost']?.toString() ?? '0') ?? 0.0,
      fullPrice: double.tryParse(map['full_price']?.toString() ?? '0') ?? 0.0,
      halfPrice: double.tryParse(map['half_price']?.toString() ?? '0') ?? 0.0,
      extraQty: double.tryParse(map['extra_qty']?.toString() ?? '0') ?? 0.0,
      extraPrice: double.tryParse(map['extra_price']?.toString() ?? '0') ?? 0.0,
      servingMethod: map['serving_method']?.toString() ?? 'Dine-in',
      tableNumber: map['table_number']?.toString() ?? '',
      checked: toBool(map['checked']),
      itemType: map['item_type']?.toString() ?? 'regular',
    );
  }
}

class TransactionModel {
  int? id;
  int? itemId;
  String type;
  String category;
  String description; 
  double amount;
  double paidAmount;
  double quantity;
  String unit;
  double rate;
  String paymentMode; 
  DateTime date;
  int isSynced;
  double cashAmount;
  double upiAmount;
  int isDeleted; 
  DateTime? deletedAt;
  String customerContact;
  String status; 

  TransactionModel({
    this.id,
    this.itemId,
    required this.type,
    required this.category,
    required this.description,
    required this.amount,
    this.paidAmount = 0,
    this.quantity = 0,
    this.unit = 'pcs',
    this.rate = 0,
    this.paymentMode = 'Cash',
    required this.date,
    this.isSynced = 0,
    this.cashAmount = 0,
    this.upiAmount = 0,
    this.isDeleted = 0,
    this.deletedAt,
    this.customerContact = '',
    this.status = 'completed',
    List<TransactionItemSnapshot>? itemSnapshots,
  }) : _manualSnapshots = itemSnapshots;

  final List<TransactionItemSnapshot>? _manualSnapshots;

  String get token {
    final match = RegExp(r'Token:\s*(\d+)').firstMatch(description);
    return match?.group(1) ?? "";
  }

  double get remainingCredit => paymentMode == 'Credit' ? amount - paidAmount : 0.0;

  List<TransactionItemSnapshot> get itemSnapshots {
    if (_manualSnapshots != null && _manualSnapshots!.isNotEmpty) return _manualSnapshots!;
    List<TransactionItemSnapshot> snapshots = [];
    try {
      if (description.isEmpty) return [];

      final jsonStart = description.indexOf('[');
      final jsonEnd = description.lastIndexOf(']');
      if (jsonStart != -1 && jsonEnd != -1) {
        final cleanJson = description.substring(jsonStart, jsonEnd + 1);
        final dynamic decoded = jsonDecode(cleanJson);
        if (decoded is List) {
          for (var item in decoded) {
            if (item is Map) snapshots.add(TransactionItemSnapshot.fromMap(item));
          }
        }
      }
    } catch (e) {
      debugPrint("KOT Parsing Error: $e");
    }
    return snapshots;
  }

  List<Map<String, String>> get parsedItems {
    return itemSnapshots.map((s) {
      String qtyDisplay;
      if (s.qty == 0.5) {
        qtyDisplay = "Half";
      } else if (s.qty == 1.0) {
        qtyDisplay = "Full";
      } else {
        qtyDisplay = s.qty.toStringAsFixed(s.qty % 1 == 0 ? 0 : 1);
      }

      return {
        'id': s.id.toString(),
        'qty': s.qty.toString(),
        'name': s.name,
        'category': s.category,
        'variant': s.variant,
        'price': s.price.toString(),
        'full_price': s.fullPrice.toString(),
        'half_price': s.halfPrice.toString(),
        'extra_qty': s.extraQty.toString(),
        'extra_price': s.extraPrice.toString(),
        'serving_method': s.servingMethod,
        'table_number': s.tableNumber,
        'checked': s.checked.toString(),
        'unit': s.unit,
        'line_total': s.lineTotal.toStringAsFixed(0),
        'display': '$qtyDisplay x ${s.name} ${s.variant != 'Full' ? '(${s.variant})' : ''}'
      };
    }).toList();
  }

  double get subtotalValue {
    if (category == 'Salary') return amount;
    if (description.contains(' | Subtotal: ₹')) {
      return double.tryParse(description.split(' | Subtotal: ₹').last.split(' | ').first.replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0.0;
    }
    return amount;
  }

  double get taxValue {
    if (category == 'Salary') return 0.0;
    if (description.contains('| Tax: ₹')) {
      return double.tryParse(description.split('| Tax: ₹').last.split(' | ').first.replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0.0;
    }
    return 0.0;
  }

  double get discountValue {
    if (description.contains('| Discount: ₹')) {
      final parts = description.split('| Discount: ₹');
      if (parts.length > 1) {
        return double.tryParse(parts.last.split(' | ').first.replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0.0;
      }
    }
    return 0.0;
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      if (itemId != null) 'item_id': itemId,
      'type': type,
      'category': category,
      'description': description,
      'amount': amount,
      'paid_amount': paidAmount,
      'quantity': quantity,
      'unit': unit,
      'rate': rate,
      'payment_mode': paymentMode,
      'date': date.toIso8601String(),
      'is_synced': isSynced,
      'cash_amount': cashAmount,
      'upi_amount': upiAmount,
      'is_deleted': isDeleted,
      'deleted_at': deletedAt?.toIso8601String(),
      'customer_contact': customerContact,
      'status': status,
    };
  }

  factory TransactionModel.fromMap(Map<String, dynamic> map) {
    DateTime parsedDate;
    try {
      parsedDate = map['date'] != null ? DateTime.parse(map['date'].toString()) : DateTime.now();
    } catch (e) {
      parsedDate = DateTime.now();
      debugPrint("TransactionModel: Date parsing error, using now()");
    }

    return TransactionModel(
      id: (map['id'] as num?)?.toInt(),
      itemId: (map['item_id'] as num?)?.toInt(),
      type: map['type']?.toString() ?? 'sale',
      category: map['category']?.toString() ?? 'General',
      description: map['description']?.toString() ?? '',
      amount: (map['amount'] as num? ?? 0).toDouble(),
      paidAmount: (map['paid_amount'] as num? ?? 0).toDouble(),
      quantity: (map['quantity'] as num? ?? 0).toDouble(),
      unit: map['unit']?.toString() ?? 'pcs',
      rate: (map['rate'] as num? ?? 0).toDouble(),
      paymentMode: map['payment_mode']?.toString() ?? 'Cash',
      date: parsedDate,
      isSynced: (map['is_synced'] as num? ?? 0).toInt(),
      cashAmount: (map['cash_amount'] as num? ?? 0).toDouble(),
      upiAmount: (map['upi_amount'] as num? ?? 0).toDouble(),
      isDeleted: (map['is_deleted'] as num? ?? 0).toInt(),
      deletedAt: map['deleted_at'] != null ? DateTime.tryParse(map['deleted_at'].toString()) : null,
      customerContact: map['customer_contact']?.toString() ?? '',
      status: map['status']?.toString() ?? 'completed',
    );
  }
}
