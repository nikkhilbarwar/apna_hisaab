import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../models/transaction_model.dart';
import '../../../providers/profile_provider.dart';

class TransactionTile extends StatelessWidget {
  final TransactionModel tx;
  final ProfileProvider profile;
  final bool isSelected;
  final VoidCallback onLongPress;
  final VoidCallback onTap;

  const TransactionTile({
    super.key,
    required this.tx,
    required this.profile,
    required this.isSelected,
    required this.onLongPress,
    required this.onTap,
  });

  String _getSmartItemTitle(TransactionModel tx) {
    if (tx.category == 'Salary') {
      String name = tx.description.replaceAll('Salary paid to ', '');
      // If there's JSON in description, the replaceAll might leave junk. 
      // Let's clean it properly.
      if (name.contains('[')) {
        name = name.split('[').first.trim();
      }
      return "Salary: $name";
    }
    final snapshots = tx.itemSnapshots;
    if (snapshots.isEmpty) return tx.category;
    if (snapshots.length == 1) {
      final s = snapshots.first;
      String q = s.qty == 0.5 ? "Half" : s.qty.toStringAsFixed(0);
      return "$q x ${s.name}";
    } else {
      String names = snapshots.take(2).map((e) => e.name).join(', ');
      if (snapshots.length > 2) names += '...';
      return '${snapshots.length} Items: $names';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isSale = tx.type == 'sale';
    final isPurchase = tx.type == 'purchase';
    final isPending = tx.status == 'pending';
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isSelected ? Colors.red.withValues(alpha: 0.08) : profile.cardColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isSelected 
            ? Colors.red 
            : (isPending ? Colors.orange.withValues(alpha: 0.4) : (profile.isDarkMode ? Colors.white10 : Colors.grey.shade100)),
          width: isSelected ? 2 : 1
        ),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.01), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        onLongPress: onLongPress,
        onTap: onTap,
        leading: isSelected ? const Icon(Icons.check_circle, color: Colors.red, size: 28) : Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: (isPending ? Colors.orange : (isSale ? Colors.green : (isPurchase ? Colors.orange : Colors.red))).withValues(alpha: 0.1), 
            borderRadius: BorderRadius.circular(14)
          ),
          child: Icon(
            isPending ? Icons.hourglass_top_rounded : (isSale ? Icons.south_west_rounded : Icons.north_east_rounded), 
            color: isPending ? Colors.orange : (isSale ? Colors.green : (isPurchase ? Colors.orange.shade700 : Colors.red)), 
            size: 18
          ),
        ),
        title: Text(_getSmartItemTitle(tx), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: profile.textColor)),
        subtitle: Row(
          children: [
            Icon(Icons.access_time, size: 10, color: profile.secondaryTextColor),
            const SizedBox(width: 4),
            Text(DateFormat('hh:mm a').format(tx.date), style: TextStyle(color: profile.secondaryTextColor, fontSize: 10)),
            const SizedBox(width: 8),
            Container(width: 3, height: 3, decoration: BoxDecoration(color: profile.secondaryTextColor.withValues(alpha: 0.3), shape: BoxShape.circle)),
            const SizedBox(width: 8),
            Text(tx.paymentMode, style: TextStyle(color: profile.secondaryTextColor, fontSize: 10, fontWeight: FontWeight.bold)),
          ],
        ),
        trailing: Text(
          '${(isSale) ? "+" : "-"}${profile.currencySymbol}${tx.amount.toStringAsFixed(0)}', 
          style: TextStyle(
            fontWeight: FontWeight.w900, 
            fontSize: 15, 
            color: isPending ? Colors.orange.shade700 : (isSale ? Colors.green.shade700 : Colors.red.shade700)
          )
        ),
      ),
    );
  }
}
