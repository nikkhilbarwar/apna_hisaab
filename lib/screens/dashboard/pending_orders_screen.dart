import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../providers/transaction_provider.dart';
import '../../providers/profile_provider.dart';
import '../../models/transaction_model.dart';
import '../../models/cart_item.dart';
import '../../providers/item_provider.dart';
import '../../models/item_model.dart';
import '../daily_entry/entry_screen.dart';

class PendingOrdersScreen extends StatefulWidget {
  const PendingOrdersScreen({super.key});

  @override
  State<PendingOrdersScreen> createState() => _PendingOrdersScreenState();
}

class _PendingOrdersScreenState extends State<PendingOrdersScreen> {
  bool _isLoading = true;
  final Set<int> _selectedIds = {}; // Track selected transaction IDs

  @override
  void initState() {
    super.initState();
    _loadPendingOrders();
  }

  Future<void> _loadPendingOrders() async {
    try {
      await Provider.of<TransactionProvider>(context, listen: false).fetchTransactions();
    } catch (e) {
      debugPrint('PendingOrdersScreen fetch error: $e');
    }
    if (mounted) setState(() => _isLoading = false);
  }

  void _toggleSelection(int id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  void _bulkDelete() {
    if (_selectedIds.isEmpty) return;

    final txProvider = Provider.of<TransactionProvider>(context, listen: false);
    final itemProvider = Provider.of<ItemProvider>(context, listen: false);
    final profile = Provider.of<ProfileProvider>(context, listen: false);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: profile.cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Delete ${_selectedIds.length} Orders?', style: TextStyle(color: profile.textColor)),
        content: Text('Do you want to remove these ${_selectedIds.length} pending drafts? Stock will be restored.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CANCEL')),
          TextButton(
            onPressed: () async {
              for (int id in _selectedIds) {
                await txProvider.softDeleteTransaction(id, itemProvider);
              }
              setState(() => _selectedIds.clear());
              if (mounted) Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Orders deleted successfully!')));
            },
            child: const Text('DELETE', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final profileProvider = Provider.of<ProfileProvider>(context);
    final isSelectionMode = _selectedIds.isNotEmpty;

    return Scaffold(
      backgroundColor: profileProvider.scaffoldColor,
      appBar: AppBar(
        title: Text(
          isSelectionMode ? '${_selectedIds.length} SELECTED' : 'PENDING ORDERS',
          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
        ),
        centerTitle: true,
        backgroundColor: isSelectionMode ? Colors.red.shade700 : profileProvider.cardColor,
        foregroundColor: isSelectionMode ? Colors.white : profileProvider.textColor,
        elevation: 0,
        leading: isSelectionMode 
          ? IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() => _selectedIds.clear()))
          : null,
        actions: [
          if (isSelectionMode)
            IconButton(icon: const Icon(Icons.delete_sweep_rounded), onPressed: _bulkDelete),
        ],
      ),
      body: Consumer<TransactionProvider>(
        builder: (context, txProvider, child) {
          final pendingOrders = txProvider.pendingTransactions;

          if (_isLoading) return const Center(child: CircularProgressIndicator());
          if (pendingOrders.isEmpty) return _buildEmptyState(profileProvider, txProvider);

          return RefreshIndicator(
            onRefresh: _loadPendingOrders,
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: pendingOrders.length,
              itemBuilder: (context, index) {
                final order = pendingOrders[index];
                final isSelected = _selectedIds.contains(order.id);
                return _buildOrderCard(context, order, profileProvider, isSelected);
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildOrderCard(BuildContext context, TransactionModel order, ProfileProvider profile, bool isSelected) {
    final themeColor = profile.themeColor ?? Colors.orange;
    final textColor = profile.textColor ?? Colors.black;
    final secondaryTextColor = profile.secondaryTextColor ?? Colors.grey;
    final cardColor = profile.cardColor ?? Colors.white;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: isSelected ? Colors.red.withOpacity(0.05) : cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isSelected ? Colors.red : Colors.orange.withOpacity(0.3), 
          width: isSelected ? 2 : 1.5
        ),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10)],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onLongPress: () => _toggleSelection(order.id!),
            onTap: () {
              if (_selectedIds.isNotEmpty) {
                _toggleSelection(order.id!);
              } else {
                _openPendingOrder(context, order);
              }
            },
            child: Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(color: Colors.orange.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                            child: const Text('PENDING', style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 10)),
                          ),
                          Text(DateFormat('dd MMM, hh:mm a').format(order.date), style: TextStyle(color: secondaryTextColor, fontSize: 11)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(order.category, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: textColor)),
                      const SizedBox(height: 8),
                      ...order.parsedItems.take(3).map((item) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          children: [
                            Icon(Icons.circle, size: 6, color: themeColor.withOpacity(0.5)),
                            const SizedBox(width: 8),
                            Expanded(child: Text(item['display'] ?? '', style: TextStyle(color: secondaryTextColor, fontSize: 13))),
                          ],
                        ),
                      )).toList(),
                      const Divider(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('EST. TOTAL', style: TextStyle(color: secondaryTextColor, fontSize: 10, fontWeight: FontWeight.bold)),
                              Text('${profile.currencySymbol}${order.amount.toStringAsFixed(0)}', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20, color: themeColor)),
                            ],
                          ),
                          if (_selectedIds.isEmpty)
                            ElevatedButton(
                              onPressed: () => _openPendingOrder(context, order),
                              style: ElevatedButton.styleFrom(backgroundColor: themeColor, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), elevation: 0),
                              child: const Text('OPEN CART', style: TextStyle(fontWeight: FontWeight.bold)),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (isSelected)
                  Positioned(
                    top: 10, right: 10,
                    child: Icon(Icons.check_circle, color: Colors.red.shade700, size: 28),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openPendingOrder(BuildContext context, TransactionModel order) {
    Navigator.push(context, MaterialPageRoute(builder: (c) => EntryScreen(transaction: order)));
  }

  Widget _buildEmptyState(ProfileProvider profile, TransactionProvider txProvider) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.pending_actions_rounded, size: 80, color: (profile.secondaryTextColor ?? Colors.grey).withOpacity(0.2)),
            const SizedBox(height: 16),
            Text('No pending orders', style: TextStyle(color: profile.secondaryTextColor, fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
      ),
    );
  }
}
