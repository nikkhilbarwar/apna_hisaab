import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../providers/transaction_provider.dart';
import '../../providers/profile_provider.dart';
import '../../models/transaction_model.dart';
import '../../models/cart_item.dart';
import '../../models/item_model.dart';
import '../../providers/item_provider.dart';
import '../../utils/app_strings.dart';
import '../daily_entry/entry_screen.dart';
import '../daily_entry/cart_details_screen.dart';
import '../history/history_screen.dart';
import 'pending_orders_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  String _activeFilter = 'Completed'; 
  final Set<int> _selectedIds = {}; // Multi-selection state

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
        title: Text('Delete ${_selectedIds.length} Records?'),
        content: const Text('Move selected items to Trash? Stock will be restored for Sales/Purchases.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CANCEL')),
          TextButton(
            onPressed: () async {
              for (int id in _selectedIds) {
                await txProvider.softDeleteTransaction(id, itemProvider);
              }
              setState(() => _selectedIds.clear());
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Items moved to trash!')));
            },
            child: const Text('DELETE', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final txProvider = Provider.of<TransactionProvider>(context);
    final profileProvider = Provider.of<ProfileProvider>(context);
    final themeColor = profileProvider.themeColor;
    final isSelectionMode = _selectedIds.isNotEmpty;

    List<TransactionModel> filteredTransactions = _activeFilter == 'Pending' 
        ? txProvider.pendingTransactions.take(50).toList()
        : txProvider.transactions.take(50).toList();

    if (_activeFilter == 'Pending' && txProvider.pendingTransactions.isEmpty) {
      _activeFilter = 'Completed';
    }

    return Scaffold(
      backgroundColor: profileProvider.scaffoldColor,
      // Dynamic AppBar for Dashboard
      appBar: isSelectionMode ? AppBar(
        backgroundColor: Colors.red.shade700,
        foregroundColor: Colors.white,
        elevation: 2,
        title: Text('${_selectedIds.length} SELECTED', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
        leading: IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() => _selectedIds.clear())),
        actions: [
          IconButton(icon: const Icon(Icons.delete_sweep_rounded, size: 28), onPressed: _bulkDelete),
        ],
      ) : null,
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Padding(
          padding: EdgeInsets.only(top: isSelectionMode ? 0 : 16.0, left: 16, right: 16, bottom: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!isSelectionMode) _buildMainStatsCard(txProvider, profileProvider),
              const SizedBox(height: 12),
              Text('Payment Overview', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: profileProvider.textColor)),
              const SizedBox(height: 8),
              _buildPaymentModeRow(txProvider, profileProvider),
              const SizedBox(height: 16),
              Text(AppStrings.quickActions, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: profileProvider.textColor)),
              const SizedBox(height: 8),
              _buildQuickActions(context, themeColor, txProvider.pendingTransactions.isNotEmpty),
              const SizedBox(height: 20),
              
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Recent Activity', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: profileProvider.textColor)),
                  Row(
                    children: [
                      _filterChip('Completed', txProvider.transactions.length),
                      if (txProvider.pendingTransactions.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        _filterChip('Pending', txProvider.pendingTransactions.length),
                      ],
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              
              filteredTransactions.isEmpty
                  ? _buildEmptyState(profileProvider)
                  : ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: filteredTransactions.length,
                      itemBuilder: (context, index) {
                        final tx = filteredTransactions[index];
                        final isSelected = _selectedIds.contains(tx.id);
                        return _buildModernTransactionTile(context, tx, profileProvider, isSelected);
                      },
                    ),
              const SizedBox(height: 100),
            ],
          ),
        ),
      ),
    );
  }

  Widget _filterChip(String label, int count) {
    final profile = Provider.of<ProfileProvider>(context, listen: false);
    bool isSelected = _activeFilter == label;
    Color color = label == 'Pending' ? Colors.orange : profile.themeColor;

    return GestureDetector(
      onTap: () {
        setState(() {
          _activeFilter = label;
          _selectedIds.clear(); // Clear selection when switching tabs
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? color : color.withOpacity(0.05),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: isSelected ? color : color.withOpacity(0.2)),
        ),
        child: Row(
          children: [
            Text(label, style: TextStyle(color: isSelected ? Colors.white : color, fontWeight: FontWeight.w900, fontSize: 10)),
            if (count > 0) ...[
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(color: isSelected ? Colors.white24 : color.withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
                child: Text('$count', style: TextStyle(color: isSelected ? Colors.white : color, fontWeight: FontWeight.bold, fontSize: 9)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMainStatsCard(TransactionProvider tx, ProfileProvider profile) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [profile.themeColor, profile.themeColor.withOpacity(0.85)]),
        borderRadius: BorderRadius.circular(24),
        boxShadow: profile.themeShadow,
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 20),
            child: Column(
              children: [
                const Text(AppStrings.totalSalesToday, style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w800, fontSize: 10)),
                const SizedBox(height: 4),
                Text('${profile.currencySymbol}${tx.todaySales.toStringAsFixed(0)}', style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w900, color: Colors.white)),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(tx.salesGrowth >= 0 ? Icons.trending_up : Icons.trending_down, size: 12, color: Colors.white),
                    const SizedBox(width: 4),
                    Text('${tx.salesGrowth.abs().toStringAsFixed(1)}% vs yesterday', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 10, color: Colors.white)),
                  ]),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(color: Colors.black.withOpacity(0.08), borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24))),
            child: Row(
              children: [
                _miniStat('Orders', tx.transactions.where((t) => t.type == 'sale' && _isToday(t.date)).length.toString(), isDark: true),
                _verticalDivider(isDark: true),
                _miniStat('Avg Bill', '${profile.currencySymbol}${tx.avgOrderValue.toStringAsFixed(0)}', isDark: true),
                _verticalDivider(isDark: true),
                _miniStat('Profit', '${profile.currencySymbol}${tx.profitToday.toStringAsFixed(0)}', isDark: true),
              ],
            ),
          ),
        ],
      ),
    );
  }

  bool _isToday(DateTime date) {
    final now = DateTime.now();
    return date.year == now.year && date.month == now.month && date.day == now.day;
  }

  Widget _miniStat(String label, String value, {bool isDark = false}) {
    return Expanded(
      child: Column(children: [
        Text(value, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: isDark ? Colors.white : Colors.black87)),
        Text(label, style: TextStyle(color: isDark ? Colors.white70 : Colors.grey.shade500, fontSize: 9, fontWeight: FontWeight.w600)),
      ]),
    );
  }

  Widget _verticalDivider({bool isDark = false}) => Container(height: 20, width: 1, color: isDark ? Colors.white12 : Colors.grey.shade200);

  Widget _buildPaymentModeRow(TransactionProvider tx, ProfileProvider profile) {
    return Row(
      children: [
        _paymentCard(Icons.payments_rounded, 'Cash', '${profile.currencySymbol}${tx.cashSalesToday.toStringAsFixed(0)}', Colors.green, profile),
        const SizedBox(width: 8),
        _paymentCard(Icons.qr_code_2_rounded, 'UPI', '${profile.currencySymbol}${tx.upiSalesToday.toStringAsFixed(0)}', Colors.blueAccent, profile),
        const SizedBox(width: 8),
        _paymentCard(Icons.timer_rounded, 'Credit', '${profile.currencySymbol}${tx.creditSalesToday.toStringAsFixed(0)}', Colors.orangeAccent, profile),
      ],
    );
  }

  Widget _paymentCard(IconData icon, String label, String value, Color color, ProfileProvider profile) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(color: profile.cardColor, borderRadius: BorderRadius.circular(16)),
        child: Column(children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: profile.textColor)),
          Text(label, style: TextStyle(color: profile.secondaryTextColor, fontSize: 8)),
        ]),
      ),
    );
  }

  Widget _buildQuickActions(BuildContext context, Color themeColor, bool hasPending) {
    return Row(children: [
      _modernActionButton(context, AppStrings.newSale, Icons.add_shopping_cart_rounded, Colors.green, 
        () => Navigator.push(context, MaterialPageRoute(builder: (c) => const EntryScreen(initialType: 'sale')))),
      const SizedBox(width: 16),
      _modernActionButton(context, 'PURCHASE', Icons.shopping_bag_rounded, Colors.orange.shade700, 
        () => Navigator.push(context, MaterialPageRoute(builder: (c) => const EntryScreen(initialType: 'purchase')))),
    ]);
  }

  Widget _modernActionButton(BuildContext context, String label, IconData icon, Color color, VoidCallback onTap) {
    return Expanded(child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(20)),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, color: Colors.white, size: 20),
          const SizedBox(width: 12),
          Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 13)),
        ]),
      ),
    ));
  }

  Widget _buildModernTransactionTile(BuildContext context, TransactionModel tx, ProfileProvider profile, bool isSelected) {
    final isSale = tx.type == 'sale';
    final isPurchase = tx.type == 'purchase';
    final isPending = tx.status == 'pending';
    
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: isSelected ? Colors.red.withOpacity(0.1) : profile.cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isSelected ? Colors.red : (isPending ? Colors.orange.withOpacity(0.5) : (profile.isDarkMode ? Colors.white10 : Colors.grey.shade100)), width: isSelected ? 2 : 1),
      ),
      child: ListTile(
        onLongPress: () => _toggleSelection(tx.id!), // Enable Selection
        onTap: () {
          if (_selectedIds.isNotEmpty) {
            _toggleSelection(tx.id!);
          } else {
            _showTransactionDetails(context, tx, profile);
          }
        },
        leading: isSelected ? const Icon(Icons.check_circle, color: Colors.red) : Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(color: (isPending ? Colors.orange : (isSale ? Colors.green : (isPurchase ? Colors.orange : Colors.red))).withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
          child: Icon(isPending ? Icons.hourglass_top_rounded : (isSale ? Icons.south_west_rounded : Icons.north_east_rounded), color: isPending ? Colors.orange : (isSale ? Colors.green : (isPurchase ? Colors.orange.shade700 : Colors.red)), size: 16),
        ),
        title: Text(_getSmartItemTitle(tx), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: profile.textColor)),
        subtitle: Text(DateFormat('hh:mm a').format(tx.date), style: TextStyle(color: profile.secondaryTextColor, fontSize: 9)),
        trailing: Text('${(isSale) ? "+" : "-"}${profile.currencySymbol}${tx.amount.toStringAsFixed(0)}', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: isPending ? Colors.orange.shade700 : (isSale ? Colors.green.shade700 : Colors.red.shade700))),
      ),
    );
  }

  void _showTransactionDetails(BuildContext context, TransactionModel tx, ProfileProvider profile) {
    final isSale = tx.type == 'sale';
    final isPending = tx.status == 'pending';
    final txProvider = Provider.of<TransactionProvider>(context, listen: false);
    final itemProvider = Provider.of<ItemProvider>(context, listen: false);

    showModalBottomSheet(
      context: context, 
      isScrollControlled: true, 
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(color: profile.cardColor, borderRadius: const BorderRadius.vertical(top: Radius.circular(32))),
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 24), decoration: BoxDecoration(color: Colors.grey.withOpacity(0.3), borderRadius: BorderRadius.circular(2)))),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('ORDER DETAILS', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12, color: profile.secondaryTextColor, letterSpacing: 1)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: (isPending ? Colors.orange : (isSale ? Colors.green : Colors.red)).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(isPending ? 'PENDING' : 'COMPLETED', style: TextStyle(color: isPending ? Colors.orange : (isSale ? Colors.green : Colors.red), fontWeight: FontWeight.bold, fontSize: 10)),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(_getSmartItemTitle(tx), style: TextStyle(color: profile.textColor, fontWeight: FontWeight.w900, fontSize: 20)),
            const SizedBox(height: 8),
            Text(DateFormat('dd MMMM yyyy, hh:mm a').format(tx.date), style: TextStyle(color: profile.secondaryTextColor, fontSize: 12)),
            const Divider(height: 32),
            
            ...tx.parsedItems.map((item) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item['name'] ?? 'Item', style: TextStyle(fontWeight: FontWeight.bold, color: profile.textColor, fontSize: 14)),
                        Text('${item['qty']} x ${profile.currencySymbol}${item['price']}', style: TextStyle(color: profile.secondaryTextColor, fontSize: 11)),
                      ],
                    ),
                  ),
                  Text('${profile.currencySymbol}${(double.tryParse(item['qty'].toString()) ?? 0) * (double.tryParse(item['price'].toString()) ?? 0)}', 
                    style: TextStyle(fontWeight: FontWeight.bold, color: profile.textColor)),
                ],
              ),
            )),
            
            const Divider(height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('TOTAL AMOUNT', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: profile.textColor)),
                Text('${profile.currencySymbol}${tx.amount.toStringAsFixed(0)}', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 22, color: profile.themeColor)),
              ],
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      _showDeleteConfirm(context, tx, txProvider, itemProvider, profile);
                    },
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    label: const Text('DELETE', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                    style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.red), padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                  ),
                ),
                if (isPending) ...[
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        Navigator.push(context, MaterialPageRoute(builder: (c) => EntryScreen(transaction: tx)));
                      },
                      icon: const Icon(Icons.edit_document),
                      label: const Text('EDIT & COMPLETE'),
                      style: ElevatedButton.styleFrom(backgroundColor: profile.themeColor, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showDeleteConfirm(BuildContext context, TransactionModel tx, TransactionProvider txProvider, ItemProvider itemProvider, ProfileProvider profile) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: profile.cardColor,
        title: const Text('Delete Transaction?'),
        content: const Text('Are you sure? This will restore stock levels.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CANCEL')),
          TextButton(
            onPressed: () async {
              await txProvider.softDeleteTransaction(tx.id!, itemProvider);
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Transaction deleted!')));
            },
            child: const Text('DELETE', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(ProfileProvider profile) {
    return Center(child: Column(children: [const SizedBox(height: 24), Icon(Icons.receipt_long_rounded, size: 40, color: Colors.grey.shade300), Text(AppStrings.noTransactions, style: TextStyle(color: profile.secondaryTextColor, fontSize: 13))]));
  }
}
