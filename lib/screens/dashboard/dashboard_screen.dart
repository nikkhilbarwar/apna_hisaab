import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../models/category_model.dart';
import '../../providers/transaction_provider.dart';
import '../../providers/profile_provider.dart';
import '../../models/transaction_model.dart';
import '../../models/item_model.dart';
import '../../providers/item_provider.dart';
import '../../providers/purchase_reminder_provider.dart';
import '../../utils/app_strings.dart';
import '../../utils/report_helper.dart';
import '../daily_entry/entry_screen.dart';
import '../purchase_reminders/purchase_reminder_screen.dart';
import '../stock/stock_screen.dart';
import 'widgets/stat_card.dart';
import 'widgets/transaction_detail_sheet.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  String _activeFilter = 'Completed';
  final Set<int> _selectedIds = {};
  final Map<int, GlobalKey> _itemKeys = {};
  DateTimeRange? _selectedDateRange;
  
  bool _isDialogShowing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkLowStock();
    });
  }

  void _checkLowStock() {
    if (!mounted || _isDialogShowing) return;
    
    // Only show if this screen's route is the top-most route to avoid overlapping or accidental pops
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return;

    final itemProvider = Provider.of<ItemProvider>(context, listen: false);
    final itemsToAlert = itemProvider.pendingAlertItems;

    if (itemsToAlert.isNotEmpty) {
      _showLowStockPopup(itemsToAlert);
    }
  }

  void _showLowStockPopup(List<ItemModel> items) {
    if (_isDialogShowing) return;
    _isDialogShowing = true;
    
    final profile = Provider.of<ProfileProvider>(context, listen: false);
    final itemProvider = Provider.of<ItemProvider>(context, listen: false);
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: profile.cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange.shade800, size: 28),
            const SizedBox(width: 12),
            Text('Low Stock Alert', style: TextStyle(color: profile.textColor, fontWeight: FontWeight.w900)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Stocks reaching critical levels:', style: TextStyle(color: profile.secondaryTextColor, fontSize: 13, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.3),
              child: SingleChildScrollView(
                child: Column(
                  children: items.map((item) {
                    CategoryModel? cat;
                    try { cat = itemProvider.categories.firstWhere((c) => c.name == item.category); } catch(_) {}
                    
                    bool isCat = cat != null && cat.useCategoryStock == 1;
                    String title = isCat ? cat.name : item.name;
                    double currentVal = isCat ? cat.stockQty : item.currentStock;
                    double limit = isCat ? cat.lowStockLimit : item.minStock;

                    final bool isReadymade = item.itemType == 'readymade';
                    final Color alertColor = isReadymade ? Colors.blue : Colors.orange.shade800;

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(color: alertColor.withValues(alpha: 0.1), shape: BoxShape.circle),
                            child: Icon(
                              isCat ? Icons.category_outlined : (isReadymade ? Icons.shopping_bag_outlined : Icons.inventory_2_outlined), 
                              color: alertColor, 
                              size: 16
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(title, style: TextStyle(fontWeight: FontWeight.bold, color: profile.textColor, fontSize: 14)),
                                    if (isReadymade) ...[
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(color: Colors.blue.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
                                        child: const Text('R', style: TextStyle(color: Colors.blue, fontSize: 8, fontWeight: FontWeight.bold)),
                                      ),
                                    ],
                                  ],
                                ),
                                Text('Stock: ${currentVal.toStringAsFixed(1)} / Min: ${limit.toInt()}${isCat ? ' (Shared)' : ''}',
                                  style: TextStyle(color: profile.secondaryTextColor, fontSize: 11)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          ],
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: () {
                    for (var item in items) {
                      itemProvider.snoozeAlert(item);
                    }
                    Navigator.pop(context);
                  },
                  child: Text('REMIND LATER', style: TextStyle(color: profile.secondaryTextColor, fontWeight: FontWeight.bold, fontSize: 11)),
                ),
              ),
              Expanded(
                child: TextButton(
                  onPressed: () {
                    for (var item in items) {
                      itemProvider.dismissAlertForToday(item);
                    }
                    Navigator.pop(context);
                  },
                  child: Text('OK', style: TextStyle(color: profile.themeColor, fontWeight: FontWeight.w900, fontSize: 12)),
                ),
              ),
              Expanded(
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    Navigator.push(context, MaterialPageRoute(builder: (c) => const StockScreen(filterLowStock: true)));
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: profile.themeColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 0
                  ),
                  child: const Text('UPDATE', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                ),
              ),
            ],
          ),
        ],
      ),
    ).then((_) {
      _isDialogShowing = false;
    });
  }

  String _getSmartItemTitle(TransactionModel tx) {
    if (tx.category == 'Salary') {
      String name = tx.description;
      if (name.contains('Salary paid to ')) {
        name = name.replaceAll('Salary paid to ', '');
      }
      if (name.contains('[')) {
        name = name.split('[').first.trim();
      }
      return "Salary: $name";
    }
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
              if (ctx.mounted) Navigator.pop(ctx);
              _checkLowStock();
            },
            child: const Text('DELETE', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _selectDateRange(BuildContext context) async {
    final profile = Provider.of<ProfileProvider>(context, listen: false);
    final DateTimeRange? picked = await ReportHelper.showAppDateRangePicker(
      context, 
      _selectedDateRange, 
      profile.themeColor,
      lastDate: DateTime.now(),
    );

    if (picked != null) {
      setState(() {
        _selectedDateRange = picked;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final txProvider = Provider.of<TransactionProvider>(context);
    final profileProvider = Provider.of<ProfileProvider>(context);
    final reminderProvider = Provider.of<PurchaseReminderProvider>(context);
    
    // Watch ItemProvider for real-time stock alerts
    Provider.of<ItemProvider>(context);
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkLowStock();
    });

    final isSelectionMode = _selectedIds.isNotEmpty;

    final todayCompletedCount = txProvider.transactions.where((tx) => (tx.type == 'sale' || tx.type == 'income') && _isToday(tx.date)).length;
    final todayPurchaseCount = txProvider.transactions.where((tx) => (tx.type == 'purchase' || tx.type == 'expense') && tx.category != 'Salary' && _isToday(tx.date)).length;
    final todaySalaryCount = txProvider.transactions.where((tx) => tx.category == 'Salary' && _isToday(tx.date)).length;

    List<TransactionModel> filteredTransactions;
    if (_activeFilter == 'Pending') {
      filteredTransactions = txProvider.pendingTransactions.take(50).toList();
    } else {
      filteredTransactions = txProvider.transactions.where((tx) {
        bool matchType = false;
        if (_activeFilter == 'Completed') {
          matchType = (tx.type == 'sale' || tx.type == 'income');
        } else if (_activeFilter == 'Purchase') {
          matchType = (tx.type == 'purchase' || tx.type == 'expense') && tx.category != 'Salary';
        } else if (_activeFilter == 'Salary') {
          matchType = tx.category == 'Salary';
        }
        
        if (!matchType) return false;

        if (_selectedDateRange != null) {
          final start = DateTime(_selectedDateRange!.start.year, _selectedDateRange!.start.month, _selectedDateRange!.start.day);
          final end = DateTime(_selectedDateRange!.end.year, _selectedDateRange!.end.month, _selectedDateRange!.end.day, 23, 59, 59);
          return tx.date.isAfter(start.subtract(const Duration(seconds: 1))) && tx.date.isBefore(end);
        } else {
          return _isToday(tx.date);
        }
      }).toList();
      filteredTransactions.sort((a, b) => b.date.compareTo(a.date));
      filteredTransactions = filteredTransactions.take(50).toList();
    }

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
                    if (!isSelectionMode) StatCard(tx: txProvider, profile: profileProvider, range: _selectedDateRange),
                    const SizedBox(height: 16),
                    
                    if (reminderProvider.reminders.any((r) => r.status == 'pending')) ...[
                      _buildReminderBanner(context, reminderProvider, profileProvider),
                      const SizedBox(height: 16),
                    ],

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
                    _buildQuickActions(context),
                    
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Text('Recent Activity', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: profileProvider.textColor)),
                        if (_selectedDateRange != null)
                          IconButton(
                            icon: const Icon(Icons.history_rounded, size: 18, color: Colors.blue),
                            onPressed: () => setState(() => _selectedDateRange = null),
                          ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            physics: const BouncingScrollPhysics(),
                            child: Row(
                              children: [
                                _filterChip('Completed', _selectedDateRange != null && _activeFilter == 'Completed' ? filteredTransactions.length : todayCompletedCount),
                                const SizedBox(width: 8),
                                if (todaySalaryCount > 0 || _activeFilter == 'Salary' || (_selectedDateRange != null && todaySalaryCount > 0)) ...[
                                  _filterChip('Salary', _selectedDateRange != null && _activeFilter == 'Salary' ? filteredTransactions.length : todaySalaryCount),
                                  const SizedBox(width: 8),
                                ],
                                if (todayPurchaseCount > 0 || _activeFilter == 'Purchase' || _selectedDateRange != null) ...[
                                  _filterChip('Purchase', _selectedDateRange != null && _activeFilter == 'Purchase' ? filteredTransactions.length : todayPurchaseCount),
                                  const SizedBox(width: 8),
                                ],
                                if (txProvider.pendingTransactions.isNotEmpty) ...[
                                  _filterChip('Pending', txProvider.pendingTransactions.length),
                                ],
                              ],
                            ),
                          ),
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
                      _itemKeys[tx.id!] ??= GlobalKey();
                      if (tx.status == 'pending') {
                        return _buildPendingOrderCard(context, tx, profileProvider, txProvider);
                      }
                      return Container(
                        key: _itemKeys[tx.id!],
                        child: _buildModernTransactionTile(context, tx, profileProvider, isSelected)
                      );
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
              Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('PENDING ORDERS', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: profile.textColor, letterSpacing: 1)),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(color: Colors.orange.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                    child: Consumer<TransactionProvider>(
                      builder: (context, provider, _) => Text('${provider.pendingTransactions.length}', style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Expanded(
                child: Consumer<TransactionProvider>(
                  builder: (context, provider, _) => ListView.builder(
                    controller: scrollController,
                    itemCount: provider.pendingTransactions.length,
                    itemBuilder: (context, index) {
                      final tx = provider.pendingTransactions[index];
                      // Auto-expand the first item or when it's the only one left
                      return _buildPendingOrderCard(context, tx, profile, provider, isInsideSheet: true, initiallyExpanded: index == 0);
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPendingOrderCard(BuildContext context, TransactionModel tx, ProfileProvider profile, TransactionProvider provider, {bool isInsideSheet = false, bool initiallyExpanded = false}) {
    final itemProvider = Provider.of<ItemProvider>(context, listen: false);
    final double discount = tx.discountValue;
    
    // Ensure key exists, but only use GlobalKey if NOT inside sheet to avoid duplicate key error
    Key? widgetKey;
    if (!isInsideSheet) {
      _itemKeys[tx.id!] ??= GlobalKey();
      widgetKey = _itemKeys[tx.id!];
    } else {
      widgetKey = ValueKey('sheet_${tx.id}');
    }

    return Container(
      key: widgetKey,
      margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
        color: profile.cardColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.2)),
      ),
      child: ExpansionTile(
        initiallyExpanded: initiallyExpanded,
        onExpansionChanged: (isExpanded) {
          if (isExpanded && !isInsideSheet) {
            Future.delayed(const Duration(milliseconds: 300), () {
              if (!context.mounted) return;
              final ctx = _itemKeys[tx.id]?.currentContext;
              if (ctx != null && ctx.mounted) {
                Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 500), curve: Curves.easeInOut);
              }
            });
          }
        },
        shape: const RoundedRectangleBorder(side: BorderSide.none),
        collapsedShape: const RoundedRectangleBorder(side: BorderSide.none),
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: Colors.orange.withValues(alpha: 0.1), shape: BoxShape.circle),
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
                ...tx.parsedItems.map((item) {
                  final bool isChecked = item['checked'] == 'true';
                  final qty = double.tryParse(item['qty'] ?? '1') ?? 1;
                  final double exQty = double.tryParse(item['extra_qty'] ?? '0') ?? 0;
                  final double exPrice = double.tryParse(item['extra_price'] ?? '0') ?? 0;
                  final bool hasExtras = exQty > 0 || exPrice > 0;

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            InkWell(
                              onTap: () => provider.toggleItemCheck(tx.id!, item['name']!, !isChecked),
                              child: Icon(
                                isChecked ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
                                color: isChecked ? Colors.green : Colors.orange.withValues(alpha: 0.5),
                                size: 22,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item['name'] ?? 'Item',
                                    style: TextStyle(fontSize: 14, color: isChecked ? profile.secondaryTextColor : profile.textColor, fontWeight: FontWeight.w700, decoration: isChecked ? TextDecoration.lineThrough : null)
                                  ),
                                  Text('${item['display'] ?? ''} • ${item['serving_method'] ?? 'Dine-in'} • ${profile.currencySymbol}${item['price']}', 
                                    style: TextStyle(fontSize: 10, color: profile.secondaryTextColor, fontWeight: FontWeight.bold)),
                                ],
                              ),
                            ),
                            Row(
                              children: [
                                _qtyEditBtn(Icons.remove, () {
                                  try {
                                    final masterItem = itemProvider.items.firstWhere((i) => i.name == item['name']);
                                    bool hasHalf = masterItem.halfPrice != null && masterItem.halfPrice! > 0;
                                    provider.addPortionToPending(tx.id!, item['name']!, hasHalf, true, itemProvider);
                                  } catch (_) {}
                                }),
                                Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: Text(qty == 0.5 ? "Half" : qty.toStringAsFixed(1), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
                                _qtyEditBtn(Icons.add, () {
                                  try {
                                    final masterItem = itemProvider.items.firstWhere((i) => i.name == item['name']);
                                    bool hasHalf = masterItem.halfPrice != null && masterItem.halfPrice! > 0;
                                    provider.addPortionToPending(tx.id!, item['name']!, hasHalf, false, itemProvider);
                                  } catch (_) {}
                                }),
                              ],
                            ),
                          ],
                        ),
                        if (hasExtras)
                          Padding(
                            padding: const EdgeInsets.only(left: 34, top: 4),
                            child: Text(
                              '+ Extra: ${exQty > 0 ? '${exQty.toInt()} x ' : ''}${profile.currencySymbol}${exPrice.toInt()}',
                              style: TextStyle(color: Colors.blue.shade700, fontSize: 11, fontWeight: FontWeight.bold),
                            ),
                          ),
                      ],
                    ),
                  );
                }),
                
                const Divider(height: 32),
                
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('SUBTOTAL', style: TextStyle(color: profile.secondaryTextColor, fontSize: 11, fontWeight: FontWeight.bold)),
                    Text('${profile.currencySymbol}${(tx.amount + discount).toStringAsFixed(0)}', style: TextStyle(color: profile.textColor, fontSize: 12, fontWeight: FontWeight.bold)),
                  ],
                ),
                if (discount > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('DISCOUNT', style: TextStyle(color: Colors.green, fontSize: 11, fontWeight: FontWeight.bold)),
                        Text('- ${profile.currencySymbol}${discount.toStringAsFixed(0)}', style: const TextStyle(color: Colors.green, fontSize: 12, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Navigator.push(context, MaterialPageRoute(builder: (c) => EntryScreen(transaction: tx)));
                        },
                        icon: const Icon(Icons.add_shopping_cart_rounded, size: 16),
                        label: const Text('ADD MORE', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blueGrey.shade100,
                          foregroundColor: Colors.blueGrey.shade800,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          elevation: 0,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.push(context, MaterialPageRoute(builder: (c) => EntryScreen(transaction: tx)));
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          elevation: 0,
                        ),
                        child: const Text('COMPLETE BILL', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: () => provider.softDeleteTransaction(tx.id!, itemProvider),
                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                      style: IconButton.styleFrom(backgroundColor: Colors.red.withValues(alpha: 0.1), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
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

  Widget _qtyEditBtn(IconData icon, VoidCallback onTap) {
    return InkWell(onTap: onTap, child: Container(padding: const EdgeInsets.all(4), decoration: BoxDecoration(color: Colors.grey.withValues(alpha: 0.1), shape: BoxShape.circle), child: Icon(icon, size: 16)));
  }

  Widget _buildEmptyState(ProfileProvider profile) {
    return const Center(child: Text('No Activity Found'));
  }

  bool _isToday(DateTime date) {
    final now = DateTime.now();
    return date.year == now.year && date.month == now.month && date.day == now.day;
  }

  Widget _buildPaymentModeRow(TransactionProvider tx, ProfileProvider profile) {
    double cash = tx.getCashSalesForRange(_selectedDateRange);
    double upi = tx.getUpiSalesForRange(_selectedDateRange);
    double credit = tx.getCreditSalesForRange(_selectedDateRange);

    return SizedBox(height: 89,
      child: Row(
        children: [
          _paymentCard(Icons.payments_rounded, 'Cash', '${profile.currencySymbol}${cash.toStringAsFixed(0)}', Colors.green, profile),
          const SizedBox(width: 8),
          _paymentCard(Icons.qr_code_2_rounded, 'UPI', '${profile.currencySymbol}${upi.toStringAsFixed(0)}', Colors.blueAccent, profile),
          const SizedBox(width: 8),
          _paymentCard(Icons.timer_rounded, 'Credit', '${profile.currencySymbol}${credit.toStringAsFixed(0)}', Colors.orangeAccent, profile),
        ],
      ),
    );
  }

  Widget _paymentCard(IconData icon, String label, String value, Color color, ProfileProvider profile) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: profile.cardColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: profile.isDarkMode ? Colors.white10 : Colors.grey.shade100),
        ),
        child: Column(children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(height: 8),
          Text(profile.showAmount ? value : '****', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: profile.textColor)),
          Text(label, style: TextStyle(color: profile.secondaryTextColor, fontSize: 10, fontWeight: FontWeight.bold)),
        ]),
      ),
    );
  }

  Widget _buildQuickActions(BuildContext context) {
    return Row(children: [
      _modernActionButton(context, AppStrings.newSale, Icons.add_shopping_cart_rounded, Colors.green,
        () => Navigator.push(context, MaterialPageRoute(builder: (c) => const EntryScreen(initialType: 'sale')))),
      const SizedBox(width: 16),
      _modernActionButton(context, 'PURCHASE', Icons.shopping_bag_rounded, Colors.orangeAccent.shade700,
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
          color: color, borderRadius: BorderRadius.circular(22),
          boxShadow: [BoxShadow(color: color.withValues(alpha: 0.4), blurRadius: 12, offset: const Offset(0, 6))],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 22),
            const SizedBox(width: 12),
            Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 14)),
          ]
        ),
      ),
    ));
  }

  Widget _buildModernTransactionTile(BuildContext context, TransactionModel tx, ProfileProvider profile, bool isSelected) {
    final isSale = tx.type == 'sale' || tx.type == 'income';
    final isSalary = tx.category == 'Salary';
    final isCredit = tx.paymentMode == 'Credit';
    final hasBalance = isCredit && (tx.amount - tx.paidAmount) > 0;
    
    // Check if any item in this transaction is 'readymade'
    final snapshots = tx.itemSnapshots;
    final isReadymade = snapshots.any((i) => i.itemType == 'readymade');

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isSelected ? Colors.red.withValues(alpha: 0.08) : profile.cardColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: profile.isDarkMode ? Colors.white10 : Colors.grey.shade100),
      ),
      child: ListTile(
        onLongPress: () => _toggleSelection(tx.id!),
        onTap: () {
          if (_selectedIds.isNotEmpty) {
            _toggleSelection(tx.id!);
          } else {
            _showTransactionActions(context, tx, profile);
          }
        },
        leading: isSelected ? const Icon(Icons.check_circle, color: Colors.red) : Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: (isReadymade ? Colors.blue : (isSalary ? Colors.purple : (isSale ? Colors.green : Colors.red))).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12)
          ),
          child: Icon(
            isReadymade ? Icons.swap_horiz_rounded : (isSalary ? Icons.badge_rounded : (isSale ? Icons.south_west_rounded : Icons.north_east_rounded)),
            color: isReadymade ? Colors.blue : (isSalary ? Colors.purple : (isSale ? Colors.green : Colors.red)),
            size: 18
          ),
        ),
        title: Row(
          children: [
            if (isCredit && tx.customerContact.isNotEmpty) ...[
              const Icon(Icons.person_pin_rounded, size: 16, color: Colors.orange),
              const SizedBox(width: 4),
              Text(tx.customerContact, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: profile.themeColor)),
              Text(' • ', style: TextStyle(color: profile.secondaryTextColor.withValues(alpha: 0.5))),
            ],
            Expanded(child: Row(
              children: [
                Expanded(child: Text(_getSmartItemTitle(tx), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: profile.textColor), overflow: TextOverflow.ellipsis)),
                if (isReadymade) ...[
                  const SizedBox(width: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(color: Colors.blue.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
                    child: const Text('R', style: TextStyle(color: Colors.blue, fontSize: 7, fontWeight: FontWeight.bold)),
                  ),
                ],
              ],
            )),
            if (isCredit)
              Container(
                margin: const EdgeInsets.only(left: 4),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: hasBalance ? Colors.red.withValues(alpha: 0.1) : Colors.green.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  hasBalance ? 'DUE' : 'PAID',
                  style: TextStyle(color: hasBalance ? Colors.red : Colors.green, fontSize: 8, fontWeight: FontWeight.bold),
                ),
              ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${DateFormat('hh:mm a').format(tx.date)} • ${tx.paymentMode}${tx.customerContact.isNotEmpty ? ' • ${tx.customerContact}' : ''}', 
              style: const TextStyle(fontSize: 10)),
            if (isCredit && hasBalance)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text('Bal: ${profile.currencySymbol}${(tx.amount - tx.paidAmount).toStringAsFixed(0)}', 
                  style: const TextStyle(fontSize: 10, color: Colors.red, fontWeight: FontWeight.bold)),
              ),
          ],
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text('${(isSale) ? "+" : "-"}${profile.currencySymbol}${profile.showAmount ? tx.amount.toStringAsFixed(0) : "****"}', 
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: isReadymade ? Colors.blue : (isSale ? Colors.green : Colors.red))),
            if (isCredit)
              Text('Rec: ${profile.currencySymbol}${tx.paidAmount.toStringAsFixed(0)}', 
                style: TextStyle(fontSize: 9, color: profile.secondaryTextColor, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  void _showTransactionActions(BuildContext context, TransactionModel tx, ProfileProvider profile) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => TransactionDetailSheet(tx: tx),
    );
  }

  Widget _filterChip(String label, int count) {
    final profile = Provider.of<ProfileProvider>(context, listen: false);
    bool isSelected = _activeFilter == label;
    Color color;
    if (label == 'Pending') {
      color = Colors.orange;
    } else if (label == 'Purchase') {
      color = Colors.orangeAccent.shade700;
    } else if (label == 'Salary') {
      color = Colors.purple;
    } else {
      color = profile.themeColor;
    }

    return GestureDetector(
      onTap: () {
        setState(() {
          _activeFilter = label;
          _selectedIds.clear();
          _selectedDateRange = null;
        });
      },
      onLongPress: (label == 'Completed' || label == 'Purchase') ? () => _selectDateRange(context) : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? color : color.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: isSelected ? color : color.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            Text(label, style: TextStyle(color: isSelected ? Colors.white : color, fontWeight: FontWeight.w900, fontSize: 10)),
            if (count > 0) ...[
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(color: isSelected ? Colors.white24 : color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
                child: Text('$count', style: TextStyle(color: isSelected ? Colors.white : color, fontWeight: FontWeight.bold, fontSize: 9)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildReminderBanner(BuildContext context, PurchaseReminderProvider provider, ProfileProvider profile) {
    final pendingCount = provider.reminders.where((r) => r.status == 'pending').length;
    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (c) => const PurchaseReminderScreen())),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: profile.themeColor.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: profile.themeColor.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: profile.themeColor, borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.playlist_add_check_rounded, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('$pendingCount Items to Buy', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: profile.themeColor)),
                  Text('View your purchase checklist', style: TextStyle(fontSize: 12, color: profile.secondaryTextColor)),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios_rounded, size: 16, color: profile.themeColor),
          ],
        ),
      ),
    );
  }

  Widget _buildPendingOrderBanner(BuildContext context, TransactionProvider tx, ProfileProvider profile) {
    return GestureDetector(
      onTap: () => _showPendingOrdersSheet(context, tx, profile),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.orange.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.orange.withValues(alpha: 0.2)),
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
                  const Text('Tap to view and complete bills', style: TextStyle(fontSize: 12, color: Colors.orange)),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios_rounded, size: 16, color: Colors.orange),
          ],
        ),
      ),
    );
  }

}
