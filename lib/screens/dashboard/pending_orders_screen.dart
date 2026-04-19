import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../providers/transaction_provider.dart';
import '../../providers/profile_provider.dart';
import '../../models/transaction_model.dart';
import '../../providers/item_provider.dart';
import '../daily_entry/entry_screen.dart';

class PendingOrdersScreen extends StatefulWidget {
  const PendingOrdersScreen({super.key});

  @override
  State<PendingOrdersScreen> createState() => _PendingOrdersScreenState();
}

class _PendingOrdersScreenState extends State<PendingOrdersScreen> {
  bool _isLoading = true;
  final Set<int> _selectedIds = {};

  @override
  void initState() {
    super.initState();
    _loadPendingOrders();
  }

  Future<void> _loadPendingOrders() async {
    try {
      await Provider.of<TransactionProvider>(
        context,
        listen: false,
      ).fetchTransactions();
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
        title: Text(
          'Delete ${_selectedIds.length} Orders?',
          style: TextStyle(color: profile.textColor),
        ),
        content: Text(
          'Do you want to remove these ${_selectedIds.length} pending drafts? Stock will be restored.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () async {
              for (int id in _selectedIds) {
                await txProvider.softDeleteTransaction(id, itemProvider);
              }
              setState(() => _selectedIds.clear());
              if (mounted) Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Orders deleted successfully!')),
              );
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
          isSelectionMode
              ? '${_selectedIds.length} SELECTED'
              : 'PENDING ORDERS',
          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
        ),
        centerTitle: true,
        backgroundColor: isSelectionMode
            ? Colors.red.shade700
            : profileProvider.cardColor,
        foregroundColor: isSelectionMode
            ? Colors.white
            : profileProvider.textColor,
        elevation: 0,
        leading: isSelectionMode
            ? IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => setState(() => _selectedIds.clear()),
              )
            : null,
        actions: [
          if (isSelectionMode)
            IconButton(
              icon: const Icon(Icons.delete_sweep_rounded),
              onPressed: _bulkDelete,
            ),
        ],
      ),
      body: Consumer<TransactionProvider>(
        builder: (context, txProvider, child) {
          final pendingOrders = txProvider.pendingTransactions;

          if (_isLoading)
            return const Center(child: CircularProgressIndicator());
          if (pendingOrders.isEmpty)
            return _buildEmptyState(profileProvider, txProvider);

          return RefreshIndicator(
            onRefresh: _loadPendingOrders,
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: pendingOrders.length,
              itemBuilder: (context, index) {
                final order = pendingOrders[index];
                final isSelected = _selectedIds.contains(order.id);
                return _buildOrderCard(
                  context,
                  order,
                  profileProvider,
                  isSelected,
                );
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildOrderCard(
    BuildContext context,
    TransactionModel order,
    ProfileProvider profile,
    bool isSelected,
  ) {
    final themeColor = profile.themeColor;
    final textColor = profile.textColor;
    final secondaryTextColor = profile.secondaryTextColor;
    final cardColor = profile.cardColor;

    final items = order.parsedItems;
    final String tableNum = items.isNotEmpty
        ? (items.first['table_number'] ?? '')
        : '';
    final String method = items.isNotEmpty
        ? (items.first['serving_method'] ?? 'Dine-in')
        : 'Dine-in';

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: isSelected ? Colors.red.withValues(alpha: 0.05) : cardColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isSelected
              ? Colors.red
              : profile.isDarkMode
              ? Colors.white10
              : Colors.grey.shade100,
          width: isSelected ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
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
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.orange.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.access_time_rounded,
                                  size: 12,
                                  color: Colors.orange,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  DateFormat('hh:mm a').format(order.date),
                                  style: const TextStyle(
                                    color: Colors.orange,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 10,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Spacer(),
                          if (tableNum.isNotEmpty) ...[
                            Icon(
                              Icons.restaurant_rounded,
                              size: 14,
                              color: themeColor.withValues(alpha: 0.6),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Table $tableNum',
                              style: TextStyle(
                                color: themeColor,
                                fontWeight: FontWeight.w900,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(width: 12),
                          ],
                          Text(
                            method,
                            style: TextStyle(
                              color: secondaryTextColor,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        order.category.toUpperCase(),
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 14,
                          color: themeColor,
                          letterSpacing: 1.5,
                        ),
                      ),
                      const SizedBox(height: 12),

                      ...items.take(3).map((item) {
                        double exQty =
                            double.tryParse(
                              item['extra_qty']?.toString() ?? '0',
                            ) ??
                            0;
                        double exPrice =
                            double.tryParse(
                              item['extra_price']?.toString() ?? '0',
                            ) ??
                            0;
                        bool hasExtras = exQty > 0 || exPrice > 0;

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: BoxDecoration(
                                      color: profile.scaffoldColor,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Icon(
                                      Icons.fastfood_rounded,
                                      size: 12,
                                      color: themeColor.withValues(alpha: 0.5),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      item['display'] ?? '',
                                      style: TextStyle(
                                        color: textColor,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              if (hasExtras)
                                Padding(
                                  padding: const EdgeInsets.only(
                                    left: 26,
                                    top: 4,
                                  ),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.blue.withValues(
                                        alpha: 0.08,
                                      ),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      'Extra: ${exQty > 0 ? '${exQty.toInt()}x ' : ''}${profile.currencySymbol}${exPrice.toInt()}',
                                      style: TextStyle(
                                        color: Colors.blue.shade700,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        );
                      }),
                      if (items.length > 3)
                        Padding(
                          padding: const EdgeInsets.only(left: 26, top: 4),
                          child: Text(
                            '+ ${items.length - 3} more items',
                            style: TextStyle(
                              color: secondaryTextColor,
                              fontSize: 11,
                              fontStyle: FontStyle.italic,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),

                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Divider(height: 1, thickness: 0.5),
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'GRAND TOTAL',
                                style: TextStyle(
                                  color: secondaryTextColor,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${profile.currencySymbol}${order.amount.toStringAsFixed(0)}',
                                style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 24,
                                  color: textColor,
                                ),
                              ),
                            ],
                          ),
                          if (_selectedIds.isEmpty)
                            ElevatedButton(
                              onPressed: () =>
                                  _openPendingOrder(context, order),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: themeColor,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(15),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 14,
                                ),
                                elevation: 0,
                              ),
                              child: const Row(
                                children: [
                                  Text(
                                    'OPEN BILL',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 13,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                  SizedBox(width: 8),
                                  Icon(
                                    Icons.arrow_forward_ios_rounded,
                                    size: 14,
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (isSelected)
                  Positioned(
                    top: 15,
                    right: 15,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.check_circle,
                        color: Colors.red.shade700,
                        size: 30,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openPendingOrder(BuildContext context, TransactionModel order) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (c) => EntryScreen(transaction: order)),
    );
  }

  Widget _buildEmptyState(
    ProfileProvider profile,
    TransactionProvider txProvider,
  ) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: profile.themeColor.withValues(alpha: 0.05),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.pending_actions_rounded,
                size: 80,
                color: profile.themeColor.withValues(alpha: 0.2),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'No Pending Orders',
              style: TextStyle(
                color: profile.textColor,
                fontWeight: FontWeight.w900,
                fontSize: 20,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Saved drafts and open tables will appear here',
              style: TextStyle(color: profile.secondaryTextColor, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
