import 'dart:convert';

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
  });

  double get remainingCredit => paymentMode == 'Credit' ? amount - paidAmount : 0.0;

  List<Map<String, String>> get parsedItems {
    List<Map<String, String>> items = [];
    try {
      if (description.isNotEmpty && (description.startsWith('[') || description.startsWith('{'))) {
        final dynamic decoded = jsonDecode(description);
        if (decoded is List) {
          for (var item in decoded) {
            if (item is Map) {
              final String q = (item['qty'] ?? '0').toString();
              final String n = (item['name'] ?? 'Item').toString();
              final String v = (item['variant'] ?? '').toString();
              
              items.add({
                'id': (item['id'] ?? '').toString(),
                'qty': q,
                'name': n,
                'variant': v,
                'price': (item['price'] ?? '0').toString(),
                'extra_qty': (item['extra_qty'] ?? '0').toString(),
                'extra_price': (item['extra_price'] ?? '0').toString(),
                'display': '$q x $n ${v.isNotEmpty ? '($v)' : ''}'
              });
            }
          }
          return items;
        }
      }
    } catch (e) {
      // JSON failed, fallback to string parsing
    }

    // Old String Parsing Logic (Backward Compatibility)
    String desc = description;
    if (desc.contains(' | Discount:')) {
      desc = desc.split(' | Discount:').first;
    }

    final itemEntries = desc.split(', ');
    for (var entry in itemEntries) {
      if (entry.trim().isEmpty) continue;
      try {
        if (entry.contains('x ')) {
          final parts = entry.split('x ');
          final qtyStr = parts[0].trim();
          final rest = parts.length > 1 ? parts[1] : '';
          
          String itemName = rest.split(' [').first.trim();
          if (itemName.isEmpty) itemName = 'Item';
          
          String variant = '';
          String price = '';

          if (rest.contains('[') && rest.contains(']')) {
            String bracketContent = rest.split('[').last.split(']').first;
            if (bracketContent.contains(':')) {
              variant = bracketContent.split(':').first.trim();
              if (bracketContent.contains('₹')) {
                price = bracketContent.split('₹').last.replaceAll(RegExp(r'[^0-9.]'), '').trim();
              }
            } else {
              variant = bracketContent.trim();
            }
          }
          
          items.add({
            'qty': qtyStr,
            'name': itemName,
            'variant': variant,
            'price': price,
            'display': '$qtyStr $itemName ${variant.isNotEmpty ? '($variant)' : ''}'
          });
        } else {
          items.add({'qty': '', 'name': entry.trim(), 'variant': '', 'price': '', 'display': entry.trim()});
        }
      } catch (_) {
        // Skip bad entries instead of crashing
      }
    }
    return items;
  }

  double get discountValue {
    if (description.contains('| Discount: ₹')) {
      return double.tryParse(description.split('| Discount: ₹').last.replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0.0;
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
    return TransactionModel(
      id: map['id'] as int?,
      itemId: map['item_id'] as int?,
      type: map['type'] as String? ?? 'sale',
      category: map['category'] as String? ?? 'General',
      description: map['description'] as String? ?? '',
      amount: (map['amount'] as num? ?? 0).toDouble(),
      paidAmount: (map['paid_amount'] as num? ?? 0).toDouble(),
      quantity: (map['quantity'] as num? ?? 0).toDouble(),
      unit: map['unit'] as String? ?? 'pcs',
      rate: (map['rate'] as num? ?? 0).toDouble(),
      paymentMode: map['payment_mode'] as String? ?? 'Cash',
      date: map['date'] != null ? DateTime.parse(map['date'] as String) : DateTime.now(),
      isSynced: map['is_synced'] as int? ?? 0,
      cashAmount: (map['cash_amount'] as num? ?? 0).toDouble(),
      upiAmount: (map['upi_amount'] as num? ?? 0).toDouble(),
      isDeleted: map['is_deleted'] as int? ?? 0,
      deletedAt: map['deleted_at'] != null ? DateTime.parse(map['deleted_at'] as String) : null,
      customerContact: map['customer_contact'] as String? ?? '',
      status: map['status'] as String? ?? 'completed',
    );
  }
}
