import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../providers/transaction_provider.dart';
import '../../providers/profile_provider.dart';
import '../../models/transaction_model.dart';
import '../../providers/item_provider.dart';
import '../../utils/app_strings.dart';
import '../daily_entry/entry_screen.dart';
import '../../services/export_service.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  String _activeFilter = 'Completed'; 
  final Set<int> _selectedIds = {}; 

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

    return PopScope(
      canPop: !isSelectionMode,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && isSelectionMode) {
          setState(() => _selectedIds.clear());
        }
      },
      child: Scaffold(
        backgroundColor: profileProvider.scaffoldColor,
        appBar: isSelectionMode 
          ? AppBar(
              backgroundColor: Colors.red.shade700,
              foregroundColor: Colors.white,
              elevation: 2,
              title: Text('${_selectedIds.length} SELECTED', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
              leading: IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() => _selectedIds.clear())),
              actions: [
                IconButton(icon: const Icon(Icons.delete_sweep_rounded, size: 28), onPressed: _bulkDelete),
              ],
            )
          : null,
        body: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(top: 16.0, left: 16, right: 16, bottom: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!isSelectionMode) _buildMainStatsCard(txProvider, profileProvider),
                    const SizedBox(height: 16),
                    
                    if (txProvider.pendingTransactions.isNotEmpty) ...[
                      _buildPendingOrderBanner(context, txProvider, profileProvider),
                      const SizedBox(height: 16),
                    ],
                    
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
                  ],
                ),
              ),
            ),
            
            if (filteredTransactions.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _buildEmptyState(profileProvider),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final tx = filteredTransactions[index];
                      final isSelected = _selectedIds.contains(tx.id);
                      return _buildModernTransactionTile(context, tx, profileProvider, isSelected);
                    },
                    childCount: filteredTransactions.length,
                  ),
                ),
              ),
            
            const SliverToBoxAdapter(child: SizedBox(height: 100)),
          ],
        ),
      ),
    );
  }

  void _showPendingOrdersSheet(BuildContext context, TransactionProvider txProvider, ProfileProvider profile) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.8,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (_, scrollController) => Container(
          decoration: BoxDecoration(
            color: profile.cardColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.withOpacity(0.3), borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('PENDING ORDERS', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: profile.textColor, letterSpacing: 1)),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(color: Colors.orange.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
                    child: Text('${txProvider.pendingTransactions.length}', style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  itemCount: txProvider.pendingTransactions.length,
                  itemBuilder: (context, index) {
                    final tx = txProvider.pendingTransactions[index];
                    return _buildPendingOrderCard(context, tx, profile);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPendingOrderCard(BuildContext context, TransactionModel tx, ProfileProvider profile) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: profile.scaffoldColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.orange.withOpacity(0.2)),
      ),
      child: ExpansionTile(
        shape: const RoundedRectangleBorder(side: BorderSide.none),
        collapsedShape: const RoundedRectangleBorder(side: BorderSide.none),
        backgroundColor: Colors.transparent,
        collapsedBackgroundColor: Colors.transparent,
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: Colors.orange.withOpacity(0.1), shape: BoxShape.circle),
          child: const Icon(Icons.timer_outlined, color: Colors.orange, size: 20),
        ),
        title: Text(_getSmartItemTitle(tx), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: profile.textColor)),
        subtitle: Text(DateFormat('hh:mm a').format(tx.date), style: TextStyle(fontSize: 11, color: profile.secondaryTextColor)),
        trailing: Text('${profile.currencySymbol}${tx.amount.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Colors.orange)),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Divider(),
                const SizedBox(height: 8),
                ...tx.parsedItems.map((item) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Container(width: 6, height: 6, decoration: const BoxDecoration(color: Colors.orange, shape: BoxShape.circle)),
                      const SizedBox(width: 12),
                      Expanded(child: Text('${item['name']} x ${item['qty']}', style: TextStyle(fontSize: 13, color: profile.textColor, fontWeight: FontWeight.w600))),
                      Text(item['serving_method'] ?? '', style: TextStyle(fontSize: 10, color: profile.themeColor, fontWeight: FontWeight.bold)),
                    ],
                  ),
                )).toList(),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.pop(context);
                          Navigator.push(context, MaterialPageRoute(builder: (c) => EntryScreen(transaction: tx)));
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          elevation: 0,
                        ),
                        child: const Text('COMPLETE BILL', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    IconButton(
                      onPressed: () => _showDeleteConfirm(context, tx, Provider.of<TransactionProvider>(context, listen: false), Provider.of<ItemProvider>(context, listen: false), profile),
                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                      style: IconButton.styleFrom(backgroundColor: Colors.red.withOpacity(0.1), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPendingOrderBanner(BuildContext context, TransactionProvider tx, ProfileProvider profile) {
    return GestureDetector(
      onTap: () => _showPendingOrdersSheet(context, tx, profile),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.orange.shade50,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.orange.shade200),
          boxShadow: [BoxShadow(color: Colors.orange.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, 4))],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: Colors.orange, borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.timer_outlined, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${tx.pendingTransactions.length} Pending Orders', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Colors.orange)),
                  const Text('Tap to view and complete bills', style: TextStyle(fontSize: 12, color: Colors.black54)),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios_rounded, size: 16, color: Colors.orange),
          ],
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
          _selectedIds.clear(); 
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
    final todayOrders = tx.transactions.where((t) => t.type == 'sale' && _isToday(t.date)).length;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [profile.themeColor, profile.themeColor.withOpacity(0.85)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: profile.themeColor.withOpacity(0.3),
            blurRadius: 25,
            offset: const Offset(0, 12),
          )
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -30, top: -30,
            child: CircleAvatar(radius: 80, backgroundColor: Colors.white.withOpacity(0.05)),
          ),
          Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 8), 
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.auto_awesome, color: Colors.white.withOpacity(0.6), size: 14),
                        const SizedBox(width: 8),
                        const Text(AppStrings.totalSalesToday, style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w800, fontSize: 12, letterSpacing: 1.5)),
                      ],
                    ),
                    const SizedBox(height: 4), 
                    Text('${profile.currencySymbol}${tx.todaySales.toStringAsFixed(0)}', style: const TextStyle(fontSize: 48, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -1.5)),
                    const SizedBox(height: 4), 
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(color: Colors.black.withOpacity(0.15), borderRadius: BorderRadius.circular(20)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(tx.salesGrowth >= 0 ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded, size: 14, color: tx.salesGrowth >= 0 ? Colors.greenAccent : Colors.redAccent),
                        const SizedBox(width: 6),
                        Text('${tx.salesGrowth.abs().toStringAsFixed(1)}% vs yesterday', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.white)),
                      ]),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(color: Colors.black.withOpacity(0.1), borderRadius: const BorderRadius.vertical(bottom: Radius.circular(28))),
                child: Column(
                  children: [
                    Row(
                      children: [
                        _miniStat('Orders', todayOrders.toString()),
                        _verticalDivider(),
                        _miniStat('Avg Bill', '${profile.currencySymbol}${tx.avgOrderValue.toStringAsFixed(0)}'),
                        _verticalDivider(),
                        _miniStat('Profit', '${profile.currencySymbol}${tx.profitToday.toStringAsFixed(0)}'),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          Positioned(
            top: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white24)),
              child: const Icon(Icons.analytics_outlined, color: Colors.white, size: 22),
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

  Widget _miniStat(String label, String value) {
    return Expanded(
      child: Column(children: [
        Text(value, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: Colors.white)),
        const SizedBox(height: 2),
        Text(label.toUpperCase(), style: const TextStyle(color: Colors.white70, fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 0.8)),
      ]),
    );
  }

  Widget _verticalDivider() => Container(height: 24, width: 1, color: Colors.white12);

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
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: profile.cardColor, 
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))],
          border: Border.all(color: profile.isDarkMode ? Colors.white10 : Colors.grey.shade100),
        ),
        child: Column(children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle),
            child: Icon(icon, color: color, size: 16),
          ),
          const SizedBox(height: 8),
          Text(value, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: profile.textColor)),
          Text(label, style: TextStyle(color: profile.secondaryTextColor, fontSize: 10, fontWeight: FontWeight.bold)),
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
      borderRadius: BorderRadius.circular(22),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
          color: color, 
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(color: color.withOpacity(0.4), blurRadius: 12, offset: const Offset(0, 6)),
            BoxShadow(color: Colors.white.withOpacity(0.1), blurRadius: 1, offset: const Offset(0, -2), spreadRadius: -1),
          ],
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, color: Colors.white, size: 22),
          const SizedBox(width: 12),
          Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 14, letterSpacing: 1)),
        ]),
      ),
    ));
  }

  Widget _buildModernTransactionTile(BuildContext context, TransactionModel tx, ProfileProvider profile, bool isSelected) {
    final isSale = tx.type == 'sale';
    final isPurchase = tx.type == 'purchase';
    final isPending = tx.status == 'pending';
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isSelected ? Colors.red.withOpacity(0.08) : profile.cardColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: isSelected ? Colors.red : (isPending ? Colors.orange.withOpacity(0.4) : (profile.isDarkMode ? Colors.white10 : Colors.grey.shade100)), width: isSelected ? 2 : 1),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.01), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        onLongPress: () => _toggleSelection(tx.id!),
        onTap: () {
          if (_selectedIds.isNotEmpty) {
            _toggleSelection(tx.id!);
          } else {
            _showTransactionActions(context, tx, profile);
          }
        },
        leading: isSelected ? const Icon(Icons.check_circle, color: Colors.red, size: 28) : Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: (isPending ? Colors.orange : (isSale ? Colors.green : (isPurchase ? Colors.orange : Colors.red))).withOpacity(0.1), borderRadius: BorderRadius.circular(14)),
          child: Icon(isPending ? Icons.hourglass_top_rounded : (isSale ? Icons.south_west_rounded : Icons.north_east_rounded), color: isPending ? Colors.orange : (isSale ? Colors.green : (isPurchase ? Colors.orange.shade700 : Colors.red)), size: 18),
        ),
        title: Text(_getSmartItemTitle(tx), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: profile.textColor)),
        subtitle: Row(
          children: [
            Icon(Icons.access_time, size: 10, color: profile.secondaryTextColor),
            const SizedBox(width: 4),
            Text(DateFormat('hh:mm a').format(tx.date), style: TextStyle(color: profile.secondaryTextColor, fontSize: 10)),
            const SizedBox(width: 8),
            Container(width: 3, height: 3, decoration: BoxDecoration(color: profile.secondaryTextColor.withOpacity(0.3), shape: BoxShape.circle)),
            const SizedBox(width: 8),
            Text(tx.paymentMode, style: TextStyle(color: profile.secondaryTextColor, fontSize: 10, fontWeight: FontWeight.bold)),
          ],
        ),
        trailing: Text('${(isSale) ? "+" : "-"}${profile.currencySymbol}${tx.amount.toStringAsFixed(0)}', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: isPending ? Colors.orange.shade700 : (isSale ? Colors.green.shade700 : Colors.red.shade700))),
      ),
    );
  }

  void _showTransactionActions(BuildContext context, TransactionModel tx, ProfileProvider profile) {
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
            // Display Category Name prominently
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
                  children: tx.parsedItems.map((item) => Padding(
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
                        Text('${profile.currencySymbol}${(double.tryParse(item['qty'].toString()) ?? 0) * (double.tryParse(item['price'].toString()) ?? 0)}', 
                          style: TextStyle(fontWeight: FontWeight.w900, color: profile.textColor, fontSize: 16)),
                      ],
                    ),
                  )).toList(),
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

  Widget _buildEmptyState(ProfileProvider profile) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: 40), 
          Icon(Icons.receipt_long_rounded, size: 80, color: Colors.grey.withOpacity(0.2)), 
          const SizedBox(height: 16), 
          Text(AppStrings.noTransactions, style: TextStyle(color: profile.secondaryTextColor, fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text('Your recent activity will appear here', style: TextStyle(color: profile.secondaryTextColor.withOpacity(0.5), fontSize: 12)),
        ],
      ),
    );
  }
}
