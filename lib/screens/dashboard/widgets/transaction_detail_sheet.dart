import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../models/transaction_model.dart';
import '../../../providers/profile_provider.dart';
import '../../../providers/transaction_provider.dart';
import '../../../providers/item_provider.dart';
import '../../../models/item_model.dart';
import '../../../services/export_service.dart';
import '../../daily_entry/entry_screen.dart';

class TransactionDetailSheet extends StatelessWidget {
  final TransactionModel tx;
  final ProfileProvider profile;

  const TransactionDetailSheet({super.key, required this.tx, required this.profile});

  String _getSmartItemTitle(TransactionModel tx) {
    final items = tx.parsedItems;
    if (items.isEmpty) return tx.category;
    if (items.length == 1) {
      return items.first['name'] ?? tx.category;
    } else {
      String names = items.take(2).map((e) => e['name']).join(', ');
      if (items.length > 2) names += '...';
      return '${items.length} Items: $names';
    }
  }

  String _getSmartCategory(TransactionModel tx) {
    if (tx.category != 'All' && tx.category != 'Mixed' && tx.category.isNotEmpty) {
      return tx.category;
    }
    final items = tx.parsedItems;
    if (items.isNotEmpty) {
      final firstCat = items.first['category'];
      if (firstCat != null && firstCat.isNotEmpty) {
        bool allSame = items.every((item) => item['category'] == firstCat);
        if (allSame) return firstCat;
      }
    }
    return tx.category;
  }

  @override
  Widget build(BuildContext context) {
    final isSale = tx.type == 'sale';
    final isPending = tx.status == 'pending';
    final txProvider = Provider.of<TransactionProvider>(context, listen: false);
    final itemProvider = Provider.of<ItemProvider>(context, listen: false);

    // CRITICAL FIX: Plate Logic and Weighted Scaling
    double transactionItemsRawSum = 0;
    List<Map<String, dynamic>> contributions = [];
    
    for (var i in tx.parsedItems) {
      double q = double.tryParse(i['qty'] ?? '0') ?? 0;
      double p = double.tryParse(i['price'] ?? '0') ?? 0;
      double eq = double.tryParse(i['extra_qty'] ?? '0') ?? 0;
      double ep = double.tryParse(i['extra_price'] ?? '0') ?? 0;
      
      double itemRawBase = 0;
      try {
        final master = itemProvider.items.firstWhere((it) => it.name == i['name']);
        if (master.halfPrice != null && master.halfPrice! > 0) {
          int fullPlates = q.floor();
          double remainder = q - fullPlates;
          itemRawBase = (fullPlates * (master.price ?? 0)) + (remainder > 0 ? (master.halfPrice ?? 0) : 0);
        } else {
          itemRawBase = q * p;
        }
      } catch(_) {
        itemRawBase = q * p;
      }
      
      double lineRawValue = itemRawBase + (eq * ep);
      transactionItemsRawSum += lineRawValue;
      contributions.add({...i, 'rawValue': lineRawValue});
    }
    
    double scale = (transactionItemsRawSum > 0) ? (tx.amount / transactionItemsRawSum) : 1.0;

    return Container(
      decoration: BoxDecoration(color: profile.cardColor, borderRadius: const BorderRadius.vertical(top: Radius.circular(32))),
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.withOpacity(0.3), borderRadius: BorderRadius.circular(2)))),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('TRANSACTION DETAILS', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12, color: profile.secondaryTextColor, letterSpacing: 1.5)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: (isPending ? Colors.orange : (isSale ? Colors.green : Colors.red)).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(isPending ? 'PENDING' : 'COMPLETED', style: TextStyle(color: isPending ? Colors.orange : (isSale ? Colors.green : Colors.red), fontWeight: FontWeight.bold, fontSize: 10)),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(_getSmartCategory(tx).toUpperCase(), style: TextStyle(color: profile.themeColor, fontWeight: FontWeight.bold, fontSize: 14, letterSpacing: 1)),
          const SizedBox(height: 4),
          Text(_getSmartItemTitle(tx), style: TextStyle(color: profile.textColor, fontWeight: FontWeight.w900, fontSize: 24, letterSpacing: -0.5)),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.calendar_today, size: 14, color: profile.secondaryTextColor),
              const SizedBox(width: 6),
              Text(DateFormat('dd MMMM yyyy, hh:mm a').format(tx.date), style: TextStyle(color: profile.secondaryTextColor, fontSize: 13)),
            ],
          ),
          const Divider(height: 40),
          
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.35),
            child: SingleChildScrollView(
              child: Column(
                children: contributions.map((item) {
                  double itemFinalPrice = (item['rawValue'] as double) * scale;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(item['name'] ?? 'Item', style: TextStyle(fontWeight: FontWeight.bold, color: profile.textColor, fontSize: 16)),
                              const SizedBox(height: 2),
                              Text('${item['qty']} x ${profile.currencySymbol}${item['price']}${item['serving_method'] != null && item['serving_method'] != '' ? ' • ${item['serving_method']}' : ''}${item['table_number'] != null && item['table_number'] != '' ? ' • Table: ${item['table_number']}' : ''}', style: TextStyle(color: profile.secondaryTextColor, fontSize: 12)),
                            ],
                          ),
                        ),
                        Text('${profile.currencySymbol}${profile.showAmount ? itemFinalPrice.toStringAsFixed(0) : "****"}', 
                          style: TextStyle(fontWeight: FontWeight.w900, color: profile.textColor, fontSize: 16)),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          
          const Divider(height: 40),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: profile.themeColor.withOpacity(0.05), borderRadius: BorderRadius.circular(20)),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('GRAND TOTAL', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: profile.textColor, letterSpacing: 1)),
                Text('${profile.currencySymbol}${tx.amount.toStringAsFixed(0)}', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 26, color: profile.themeColor, letterSpacing: -1)),
              ],
            ),
          ),
          const SizedBox(height: 28),
          Row(
            children: [
              _actionButton(
                icon: Icons.print_rounded, 
                label: 'PRINT BILL', 
                color: Colors.blue, 
                onTap: () async {
                  Navigator.pop(context);
                  final exportService = ExportService();
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Generating PDF...')));
                  try {
                    await exportService.saveBillAsPdf(tx, profile.businessName);
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Print Error: $e')));
                  }
                }
              ),
              const SizedBox(width: 12),
              _actionButton(
                icon: Icons.edit_note_rounded, 
                label: 'EDIT ENTRY', 
                color: Colors.orange, 
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(context, MaterialPageRoute(builder: (c) => EntryScreen(transaction: tx)));
                }
              ),
              const SizedBox(width: 12),
              _actionButton(
                icon: Icons.delete_outline_rounded, 
                label: 'DELETE', 
                color: Colors.red, 
                onTap: () {
                  Navigator.pop(context);
                  _showDeleteConfirm(context, tx, txProvider, itemProvider, profile);
                }
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _actionButton({required IconData icon, required String label, required Color color, required VoidCallback onTap}) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(16), border: Border.all(color: color.withOpacity(0.3))),
          child: Column(
            children: [
              Icon(icon, color: color, size: 24),
              const SizedBox(height: 6),
              Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 11, letterSpacing: 0.8)),
            ],
          ),
        ),
      ),
    );
  }

  void _showDeleteConfirm(BuildContext context, TransactionModel tx, TransactionProvider txProvider, ItemProvider itemProvider, ProfileProvider profile) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: profile.cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('Delete Transaction?'),
        content: const Text('Are you sure you want to move this to trash? This will restore stock levels.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CANCEL')),
          TextButton(
            onPressed: () async {
              await txProvider.softDeleteTransaction(tx.id!, itemProvider);
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Transaction moved to trash!')));
            },
            child: const Text('DELETE', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}
