import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../providers/transaction_provider.dart';
import '../../providers/staff_provider.dart';
import '../../providers/profile_provider.dart';
import '../../models/transaction_model.dart';
import '../../utils/app_strings.dart';
import '../history/history_screen.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  int _selectedIndex = 0;
  DateTimeRange _selectedDateRange = DateTimeRange(
    start: DateTime.now().subtract(const Duration(days: 7)),
    end: DateTime.now(),
  );

  Future<void> _refreshData() async {
    await Provider.of<TransactionProvider>(context, listen: false).fetchTransactions();
    await Provider.of<StaffProvider>(context, listen: false).fetchStaff();
  }

  @override
  Widget build(BuildContext context) {
    final profileProvider = Provider.of<ProfileProvider>(context);
    final themeColor = profileProvider.themeColor;

    return Scaffold(
      backgroundColor: profileProvider.scaffoldColor,
      body: RefreshIndicator(
        onRefresh: _refreshData,
        color: themeColor,
        child: Column(
          children: [
            Expanded(
              child: _selectedIndex == 0 
                ? _buildOverviewTab(context) 
                : const HistoryScreen(isPopup: true),
            ),
          ],
        ),
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: profileProvider.cardColor,
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, -5))],
        ),
        child: BottomNavigationBar(
          backgroundColor: profileProvider.cardColor,
          currentIndex: _selectedIndex,
          onTap: (index) => setState(() => _selectedIndex = index),
          selectedItemColor: themeColor,
          unselectedItemColor: profileProvider.secondaryTextColor,
          type: BottomNavigationBarType.fixed,
          elevation: 0,
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.analytics_outlined), activeIcon: Icon(Icons.analytics), label: 'Overview'),
            BottomNavigationBarItem(icon: Icon(Icons.history_rounded), activeIcon: Icon(Icons.history_rounded), label: 'Transactions'),
          ],
        ),
      ),
    );
  }

  Widget _buildOverviewTab(BuildContext context) {
    final txProvider = Provider.of<TransactionProvider>(context);
    final staffProvider = Provider.of<StaffProvider>(context);
    final profileProvider = Provider.of<ProfileProvider>(context);
    final themeColor = profileProvider.themeColor;

    // logic: Get pre-calculated stats from provider for performance
    final stats = txProvider.getRangeStats(_selectedDateRange, staffProvider.totalMonthlySalary);
    final List<TransactionModel> filteredTxs = stats['transactions'];

    // Category Stats
    Map<String, double> catStats = {};
    for (var tx in filteredTxs.where((t) => t.type == 'sale')) {
      catStats[tx.category] = (catStats[tx.category] ?? 0) + tx.amount;
    }

    // Top Selling Items Logic
    Map<String, Map<String, dynamic>> itemStats = {};
    for (var tx in filteredTxs.where((t) => t.type == 'sale')) {
      for (var item in tx.parsedItems) {
        String key = "${item['name']} ${item['variant'] != '' ? '(${item['variant']})' : ''}".trim();
        if (key.isEmpty) continue;
        double qty = double.tryParse(item['qty']?.toString() ?? '0') ?? 0;
        double price = double.tryParse(item['price']?.toString() ?? '0') ?? 0;
        
        if (price == 0 && tx.parsedItems.length == 1) {
          price = tx.amount / (qty == 0 ? 1 : qty);
        }

        if (!itemStats.containsKey(key)) itemStats[key] = {'qty': 0.0, 'revenue': 0.0};
        itemStats[key]!['qty'] = (itemStats[key]!['qty'] as double) + qty;
        itemStats[key]!['revenue'] = (itemStats[key]!['revenue'] as double) + (qty * price);
      }
    }
    var sortedItems = itemStats.entries.toList()..sort((a, b) => b.value['revenue'].compareTo(a.value['revenue']));

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
        _buildDateRangePicker(context, themeColor, profileProvider),
        _buildSummaryCard(stats['sales'], stats['expenses'], stats['staffCost'], stats['profit'], themeColor, profileProvider),
        const SizedBox(height: 24),
        Text('TOP SELLING ITEMS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: profileProvider.textColor)),
        const SizedBox(height: 12),
        if (sortedItems.isEmpty) 
          _emptyMiniState('No items sold in this period', profileProvider)
        else
          ...sortedItems.take(5).map((e) => _buildItemTile(e.key, e.value['qty'], e.value['revenue'], themeColor, profileProvider)).toList(),
        
        const SizedBox(height: 24),
        Text('SALES BY CATEGORY', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: profileProvider.textColor)),
        const SizedBox(height: 12),
        if (catStats.isEmpty)
          _emptyMiniState('No categories found', profileProvider)
        else
          ...catStats.entries.map((e) => _buildCategoryTile(context, e.key, e.value, stats['sales'], themeColor, profileProvider, filteredTxs)).toList(),
        const SizedBox(height: 80),
      ],
    );
  }

  Widget _emptyMiniState(String msg, ProfileProvider profile) {
    return Center(child: Padding(
      padding: const EdgeInsets.all(20.0),
      child: Text(msg, style: TextStyle(color: profile.secondaryTextColor, fontSize: 12)),
    ));
  }

  Widget _buildSummaryCard(double s, double e, double staff, double p, Color themeColor, ProfileProvider profile) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [themeColor, themeColor.withOpacity(0.7)]),
        borderRadius: BorderRadius.circular(32),
        boxShadow: profile.themeShadow,
      ),
      child: Column(
        children: [
          const Text(AppStrings.netProfit, style: TextStyle(color: Colors.white70, fontSize: 12)),
          Text('${profile.currencySymbol}${p.toStringAsFixed(0)}', style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.w900)),
          const Divider(height: 32, color: Colors.white12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _statItem(AppStrings.revenue, '${profile.currencySymbol}${s.toStringAsFixed(0)}'),
              _statItem(AppStrings.expenses, '${profile.currencySymbol}${e.toStringAsFixed(0)}'),
              _statItem(AppStrings.staffCost, '${profile.currencySymbol}${staff.toStringAsFixed(0)}'),
            ],
          )
        ],
      ),
    );
  }

  Widget _statItem(String l, String v) {
    return Column(children: [
      Text(l, style: const TextStyle(color: Colors.white60, fontSize: 10)),
      Text(v, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
    ]);
  }

  Widget _buildCategoryTile(BuildContext context, String name, double val, double total, Color themeColor, ProfileProvider profile, List<TransactionModel> allTxs) {
    double percent = total > 0 ? (val / total) * 100 : 0;
    return Card(
      margin: const EdgeInsets.only(bottom: 8), elevation: 0,
      color: profile.cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: profile.isDarkMode ? Colors.white10 : Colors.grey.shade100)),
      child: ListTile(
        onTap: () => _showCategoryDetails(context, name, profile, allTxs),
        title: Text(name, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: profile.textColor)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('${profile.currencySymbol}${val.toStringAsFixed(0)}', style: TextStyle(fontWeight: FontWeight.bold, color: profile.textColor)),
            const SizedBox(width: 4),
            Icon(Icons.arrow_forward_ios_rounded, size: 12, color: profile.secondaryTextColor.withOpacity(0.5)),
          ],
        ),
        subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SizedBox(height: 4),
          LinearProgressIndicator(value: percent / 100, backgroundColor: profile.isDarkMode ? Colors.white10 : Colors.grey[100], color: themeColor),
        ]),
      ),
    );
  }

  void _showCategoryDetails(BuildContext context, String category, ProfileProvider profile, List<TransactionModel> allTxs) {
    final categoryTxs = allTxs.where((tx) => tx.type == 'sale' && tx.category == category).toList();
    
    Map<String, Map<String, dynamic>> catItems = {};
    for (var tx in categoryTxs) {
      for (var item in tx.parsedItems) {
        String key = "${item['name']} ${item['variant'] != '' ? '(${item['variant']})' : ''}".trim();
        if (key.isEmpty) continue;
        double qty = double.tryParse(item['qty']?.toString() ?? '0') ?? 0;
        double price = double.tryParse(item['price']?.toString() ?? '0') ?? 0;
        
        if (price == 0 && tx.parsedItems.length == 1) {
          price = tx.amount / (qty == 0 ? 1 : qty);
        }

        if (!catItems.containsKey(key)) catItems[key] = {'qty': 0.0, 'revenue': 0.0};
        catItems[key]!['qty'] = (catItems[key]!['qty'] as double) + qty;
        catItems[key]!['revenue'] = (catItems[key]!['revenue'] as double) + (qty * price);
      }
    }
    var sortedCatItems = catItems.entries.toList()..sort((a, b) => b.value['revenue'].compareTo(a.value['revenue']));

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.75,
        decoration: BoxDecoration(
          color: profile.scaffoldColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(width: 40, height: 4, decoration: BoxDecoration(color: profile.secondaryTextColor.withOpacity(0.2), borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(category.toUpperCase(), style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: profile.textColor, letterSpacing: 1)),
                      Text('${categoryTxs.length} Transactions', style: TextStyle(color: profile.secondaryTextColor, fontSize: 12, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(color: profile.themeColor.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                    child: Text(
                      '${profile.currencySymbol}${categoryTxs.fold(0.0, (sum, tx) => sum + tx.amount).toStringAsFixed(0)}',
                      style: TextStyle(color: profile.themeColor, fontWeight: FontWeight.w900, fontSize: 16),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: sortedCatItems.length,
                itemBuilder: (context, index) {
                  final item = sortedCatItems[index];
                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: profile.cardColor,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: profile.isDarkMode ? Colors.white10 : Colors.grey.shade100),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(color: profile.themeColor.withOpacity(0.05), borderRadius: BorderRadius.circular(12)),
                          child: Text('${(item.value['qty'] as double).toInt()}', style: TextStyle(color: profile.themeColor, fontWeight: FontWeight.w900, fontSize: 14)),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(item.key, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: profile.textColor)),
                              Text('Avg. ${profile.currencySymbol}${(item.value['qty'] as double) > 0 ? ((item.value['revenue'] as double) / (item.value['qty'] as double)).toStringAsFixed(0) : '0'} / unit', style: TextStyle(fontSize: 11, color: profile.secondaryTextColor)),
                            ],
                          ),
                        ),
                        Text('${profile.currencySymbol}${(item.value['revenue'] as double).toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.green, fontSize: 15)),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildItemTile(String name, double qty, double revenue, Color themeColor, ProfileProvider profile) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8), elevation: 0,
      color: profile.cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: profile.isDarkMode ? Colors.white10 : Colors.grey.shade100)),
      child: ListTile(
        leading: CircleAvatar(backgroundColor: themeColor.withOpacity(0.1), child: Text(qty.toInt().toString(), style: TextStyle(color: themeColor, fontWeight: FontWeight.bold, fontSize: 12))),
        title: Text(name, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: profile.textColor)),
        trailing: Text('${profile.currencySymbol}${revenue.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
      ),
    );
  }

  Widget _buildDateRangePicker(BuildContext context, Color themeColor, ProfileProvider profile) {
    return Container(
      padding: const EdgeInsets.all(12), margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(color: profile.cardColor, borderRadius: BorderRadius.circular(16), border: Border.all(color: profile.isDarkMode ? Colors.white10 : Colors.transparent)),
      child: InkWell(
        onTap: () async {
          final r = await showDateRangePicker(
            context: context, 
            initialDateRange: _selectedDateRange,
            firstDate: DateTime(2020), 
            lastDate: DateTime.now(),
            builder: (context, child) {
              return Theme(
                data: Theme.of(context).copyWith(
                  colorScheme: profile.isDarkMode 
                    ? ColorScheme.dark(primary: themeColor, onPrimary: Colors.white, surface: profile.cardColor)
                    : ColorScheme.light(primary: themeColor),
                  dialogBackgroundColor: profile.cardColor,
                ),
                child: child!,
              );
            }
          );
          if (r != null) setState(() => _selectedDateRange = r);
        },
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.calendar_today, size: 16, color: themeColor),
          const SizedBox(width: 8),
          Text('${DateFormat('dd MMM').format(_selectedDateRange.start)} - ${DateFormat('dd MMM').format(_selectedDateRange.end)}', style: TextStyle(fontWeight: FontWeight.bold, color: profile.textColor)),
        ]),
      ),
    );
  }
}
