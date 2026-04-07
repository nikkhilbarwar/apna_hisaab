import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../models/transaction_model.dart';
import '../../providers/transaction_provider.dart';
import '../../providers/category_provider.dart';
import '../../providers/profile_provider.dart';
import '../../providers/staff_provider.dart';
import '../../providers/item_provider.dart';
import '../../models/item_model.dart';
import '../../services/export_service.dart';
import '../../services/notification_service.dart';
import '../../utils/report_helper.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  int _currentIndex = 0;
  DateTimeRange _selectedRange = DateTimeRange(
    start: DateTime.now().subtract(const Duration(days: 30)),
    end: DateTime.now(),
  );
  String _selectedCategory = 'All';
  String _selectedPaymentMode = 'All';

  @override
  Widget build(BuildContext context) {
    final profile = Provider.of<ProfileProvider>(context);
    final themeColor = profile.themeColor;
    final txProvider = Provider.of<TransactionProvider>(context);
    final staffProvider = Provider.of<StaffProvider>(context);

    // Filter transactions globally based on date range
    final allSales = txProvider.getFilteredTransactions(
      type: 'sale', 
      range: _selectedRange, 
      status: 'completed'
    );
    final allPurchases = txProvider.getFilteredTransactions(
      type: 'purchase', 
      range: _selectedRange, 
      status: 'completed'
    );
    
    double totalRevenue = allSales.fold(0, (sum, tx) => sum + tx.amount);
    double paidExpenses = allPurchases.fold(0, (sum, tx) => sum + tx.amount);
    double pendingSalary = staffProvider.totalNetPayable;
    double netProfit = totalRevenue - paidExpenses;

    return Scaffold(
      backgroundColor: profile.scaffoldColor,
      appBar: AppBar(
        elevation: 0,
        title: Text(_currentIndex == 3 ? 'TRASH BIN' : 'BUSINESS REPORTS', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 1, color: Colors.white)),
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [_currentIndex == 3 ? Colors.red.shade400 : themeColor.withValues(alpha: 0.8), _currentIndex == 3 ? Colors.red.shade700 : themeColor]),
          ),
        ),
        actions: [
          if (_currentIndex != 3)
            IconButton(
              tooltip: 'Download Report',
              icon: const Icon(Icons.file_download_outlined, color: Colors.white, size: 26),
              onPressed: () => _showExportOptions(context),
            ),
        ],
      ),
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          if (_currentIndex != 3) ...[
            SliverToBoxAdapter(child: _buildFilters(context, profile)),
            SliverPersistentHeader(
              pinned: true,
              delegate: _StickySummaryHeader(
                child: Container(
                  color: profile.cardColor,
                  child: _buildExecutiveSummary(totalRevenue, paidExpenses, netProfit, pendingSalary, profile),
                ),
              ),
            ),
          ],
        ],
        body: IndexedStack(
          index: _currentIndex,
          children: [
            _ReportList(type: 'sale', range: _selectedRange, category: _selectedCategory, paymentMode: _selectedPaymentMode),
            _ReportList(type: 'purchase', range: _selectedRange, category: _selectedCategory, paymentMode: _selectedPaymentMode),
            _StaffReportList(range: _selectedRange),
            const _TrashList(),
          ],
        ),
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 20, offset: const Offset(0, -5))],
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (index) {
            setState(() {
              _currentIndex = index;
              _selectedCategory = 'All'; 
            });
          },
          selectedItemColor: _currentIndex == 3 ? Colors.red : themeColor,
          unselectedItemColor: profile.secondaryTextColor,
          selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12),
          unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
          type: BottomNavigationBarType.fixed,
          backgroundColor: profile.cardColor,
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.auto_graph_rounded), label: 'SALES'),
            BottomNavigationBarItem(icon: Icon(Icons.receipt_long_rounded), label: 'EXPENSES'),
            BottomNavigationBarItem(icon: Icon(Icons.people_alt_rounded), label: 'STAFF'),
            BottomNavigationBarItem(icon: Icon(Icons.delete_outline_rounded), label: 'TRASH'),
          ],
        ),
      ),
    );
  }

  Widget _buildExecutiveSummary(double revenue, double expense, double profit, double pending, ProfileProvider profile) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      color: profile.cardColor,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [profile.themeColor.withValues(alpha: 0.05), profile.themeColor.withValues(alpha: 0.1)]),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: profile.themeColor.withValues(alpha: 0.1)),
            ),
            child: Row(
              children: [
                _summaryItem('REVENUE', revenue, profile.themeColor, profile),
                _verticalDivider(profile),
                _summaryItem('EXPENSE', expense, Colors.red, profile),
                _verticalDivider(profile),
                _summaryItem('NET PROFIT', profit, profit >= 0 ? Colors.green : Colors.red, profile, isBold: true),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.orange.withValues(alpha: 0.1)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('UPCOMING SALARY (PENDING)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Colors.orange, letterSpacing: 0.5)),
                Text(
                  profile.showAmount ? '${profile.currencySymbol}${pending.toStringAsFixed(0)}' : '${profile.currencySymbol}****',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: Colors.orange),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryItem(String label, double val, Color color, ProfileProvider profile, {bool isBold = false}) {
    return Expanded(
      child: Column(
        children: [
          Text(label, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: profile.secondaryTextColor, letterSpacing: 0.5)),
          const SizedBox(height: 4),
          Text(
            profile.showAmount ? '${profile.currencySymbol}${val.toStringAsFixed(0)}' : '${profile.currencySymbol}****',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: color),
          ),
        ],
      ),
    );
  }

  Widget _verticalDivider(ProfileProvider profile) => Container(height: 30, width: 1, color: profile.secondaryTextColor.withValues(alpha: 0.1));

  Widget _buildFilters(BuildContext context, ProfileProvider profile) {
    final catProvider = Provider.of<CategoryProvider>(context);
    final themeColor = profile.themeColor;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      decoration: BoxDecoration(
        color: profile.cardColor,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(30)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 5),
          )
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () async {
                    final r = await ReportHelper.showAppDateRangePicker(
                      context, 
                      _selectedRange, 
                      themeColor,
                      lastDate: DateTime.now(),
                    );
                    if (r != null) setState(() => _selectedRange = r);
                  },
                  borderRadius: BorderRadius.circular(15),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [themeColor.withOpacity(0.12), themeColor.withOpacity(0.05)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(15),
                      border: Border.all(color: themeColor.withOpacity(0.2)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.calendar_month_rounded, size: 18, color: themeColor),
                        const SizedBox(width: 10),
                        Text(
                          DateFormat('dd MMM').format(_selectedRange.start) == DateFormat('dd MMM').format(_selectedRange.end)
                            ? DateFormat('dd MMM yyyy').format(_selectedRange.start)
                            : '${DateFormat('dd MMM').format(_selectedRange.start)} - ${DateFormat('dd MMM').format(_selectedRange.end)}',
                          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: profile.textColor, letterSpacing: 0.5),
                        ),
                        const SizedBox(width: 6),
                        Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: themeColor.withOpacity(0.5)),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _dropdownFilter(
                  label: 'Category',
                  value: _selectedCategory,
                  items: ['All', ...catProvider.categories.where((c) => _currentIndex == 0 ? c.type == 'selling' : c.type == 'purchase').map((c) => c.name)],
                  onChanged: (val) => setState(() => _selectedCategory = val!),
                  profile: profile,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _dropdownFilter(
                  label: 'Payment',
                  value: _selectedPaymentMode,
                  items: ['All', 'Cash', 'UPI', 'Split', 'Credit'],
                  onChanged: (val) => setState(() => _selectedPaymentMode = val!),
                  profile: profile,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _dropdownFilter({required String label, required String value, required List<String> items, required Function(String?) onChanged, required ProfileProvider profile}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: profile.scaffoldColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: profile.isDarkMode ? Colors.white10 : Colors.grey.shade200),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          dropdownColor: profile.cardColor,
          style: TextStyle(color: profile.textColor, fontWeight: FontWeight.bold, fontSize: 12),
          items: items.toSet().map((String val) {
            return DropdownMenuItem<String>(value: val, child: Text(val));
          }).toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  void _showExportOptions(BuildContext context) {
    final profile = Provider.of<ProfileProvider>(context, listen: false);
    final txProvider = Provider.of<TransactionProvider>(context, listen: false);
    final exportService = ExportService();

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(color: profile.cardColor, borderRadius: const BorderRadius.vertical(top: Radius.circular(32))),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 24), decoration: BoxDecoration(color: Colors.grey.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(2))),
            Text('DOWNLOAD REPORT', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: profile.textColor, letterSpacing: 1)),
            const SizedBox(height: 24),
            _exportTile(Icons.table_view_rounded, 'Download as Excel Sheet', Colors.green, () async {
              final txs = txProvider.getFilteredTransactions(
                type: _currentIndex == 0 ? 'sale' : 'purchase',
                range: _selectedRange,
                category: _selectedCategory == 'All' ? null : _selectedCategory,
                status: 'completed'
              ).where((t) => _selectedPaymentMode == 'All' || t.paymentMode == _selectedPaymentMode).toList();
              
              Navigator.pop(context);
              await exportService.exportToExcel(txs, "${_currentIndex == 0 ? 'Sales' : 'Expense'}_Report");
              NotificationService().showNotification(id: 888, title: "Report Downloaded", body: "Excel report saved in Documents folder.");
            }, profile),
            const SizedBox(height: 12),
            _exportTile(Icons.picture_as_pdf_rounded, 'Download as PDF Report', Colors.red, () async {
              final txs = txProvider.getFilteredTransactions(
                type: _currentIndex == 0 ? 'sale' : 'purchase',
                range: _selectedRange,
                category: _selectedCategory == 'All' ? null : _selectedCategory,
                status: 'completed'
              ).where((t) => _selectedPaymentMode == 'All' || t.paymentMode == _selectedPaymentMode).toList();

              Navigator.pop(context);
              await exportService.exportToPdf(txs, "${_currentIndex == 0 ? 'Sales' : 'Expense'}_Report");
              NotificationService().showNotification(id: 889, title: "Report Downloaded", body: "PDF report saved in Documents folder.");
            }, profile),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _exportTile(IconData icon, String title, Color color, VoidCallback onTap, ProfileProvider profile) {
    return ListTile(
      onTap: onTap,
      leading: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle), child: Icon(icon, color: color, size: 20)),
      title: Text(title, style: TextStyle(fontWeight: FontWeight.bold, color: profile.textColor, fontSize: 14)),
      trailing: const Icon(Icons.file_download_outlined, size: 18),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      tileColor: profile.scaffoldColor,
    );
  }
}

class _StickySummaryHeader extends SliverPersistentHeaderDelegate {
  final Widget child;
  _StickySummaryHeader({required this.child});

  @override
  double get minExtent => 145.0; 
  @override
  double get maxExtent => 145.0;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return child;
  }

  @override
  bool shouldRebuild(covariant _StickySummaryHeader oldDelegate) => false;
}

class _ReportList extends StatelessWidget {
  final String type;
  final DateTimeRange range;
  final String category;
  final String paymentMode;

  const _ReportList({required this.type, required this.range, required this.category, required this.paymentMode});

  @override
  Widget build(BuildContext context) {
    final txProvider = Provider.of<TransactionProvider>(context);
    final itemProvider = Provider.of<ItemProvider>(context);
    final profile = Provider.of<ProfileProvider>(context);
    
    List<TransactionModel> filtered = txProvider.getFilteredTransactions(
      type: type, 
      range: range, 
      category: category == 'All' ? null : category, 
      status: 'completed'
    );

    if (paymentMode != 'All') {
      filtered = filtered.where((tx) => tx.paymentMode == paymentMode).toList();
    }

    if (filtered.isEmpty) {
      return Center(child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.analytics_outlined, size: 64, color: profile.secondaryTextColor.withValues(alpha: 0.1)),
          const SizedBox(height: 16),
          Text('No records found', style: TextStyle(color: profile.secondaryTextColor, fontWeight: FontWeight.bold)),
        ],
      ));
    }

    double total = filtered.fold(0, (sum, tx) => sum + tx.amount);

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
      itemCount: filtered.length + 2,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              color: profile.themeColor.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: profile.themeColor.withValues(alpha: 0.1))
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('${filtered.length} TRANSACTIONS', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 11, color: profile.themeColor, letterSpacing: 0.5)),
                Text('TOTAL: ${profile.currencySymbol}${profile.showAmount ? total.toStringAsFixed(0) : "****"}', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: profile.themeColor)),
              ],
            ),
          );
        }
        if (index == 1) {
          return _buildAnalysisSummary(context, filtered, profile, txProvider, itemProvider, type);
        }
        
        final tx = filtered[index - 2];
        
        // Date Header Logic: Detect when day changes
        bool showDateHeader = false;
        if (index == 2) {
          showDateHeader = true;
        } else {
          final prevTx = filtered[index - 3];
          if (DateFormat('ddMMyyyy').format(tx.date) != DateFormat('ddMMyyyy').format(prevTx.date)) {
            showDateHeader = true;
          }
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (showDateHeader)
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 16, 0, 12),
                child: Row(
                  children: [
                    Container(width: 4, height: 14, decoration: BoxDecoration(color: profile.themeColor, borderRadius: BorderRadius.circular(2))),
                    const SizedBox(width: 8),
                    Text(
                      _getDateLabel(tx.date),
                      style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12, color: profile.textColor, letterSpacing: 0.5),
                    ),
                  ],
                ),
              ),
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: profile.cardColor,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: profile.isDarkMode ? Colors.white10 : Colors.grey.shade100),
              ),
              child: ListTile(
                onTap: () => _showDetails(context, tx, profile),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: (tx.type == 'sale' || tx.type == 'income' ? Colors.green : Colors.red).withValues(alpha: 0.1), shape: BoxShape.circle),
                  child: Icon(tx.type == 'sale' || tx.type == 'income' ? Icons.south_west_rounded : Icons.north_east_rounded, color: tx.type == 'sale' || tx.type == 'income' ? Colors.green : Colors.red, size: 18),
                ),
                title: Text(tx.type == 'sale' || tx.type == 'income' ? _getCleanItemNames(tx) : tx.category, style: TextStyle(fontWeight: FontWeight.bold, color: profile.textColor, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text('${DateFormat('hh:mm a').format(tx.date)} • ${tx.paymentMode}', style: TextStyle(fontSize: 10, color: profile.secondaryTextColor)),
                trailing: Text('${profile.currencySymbol}${profile.showAmount ? tx.amount.toStringAsFixed(0) : "****"}', style: TextStyle(fontWeight: FontWeight.w900, color: tx.type == 'sale' || tx.type == 'income' ? Colors.green.shade700 : Colors.red.shade700, fontSize: 14)),
              ),
            ),
          ],
        );
      },
    );
  }

  String _getDateLabel(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final d = DateTime(date.year, date.month, date.day);

    if (d == today) return "TODAY";
    if (d == yesterday) return "YESTERDAY";
    return DateFormat('dd MMMM yyyy').format(date).toUpperCase();
  }

  String _getCleanItemNames(TransactionModel tx) {
    final items = tx.parsedItems;
    if (items.isEmpty) return 'Entry';
    if (items.length == 1) return items.first['name'] ?? 'Item';
    return '${items.first['name']} + ${items.length - 1} more';
  }

  Widget _buildAnalysisSummary(BuildContext context, List<TransactionModel> txs, ProfileProvider profile, TransactionProvider provider, ItemProvider itemProvider, String reportType) {
    final split = provider.getPaymentSplit(txs);
    
    Map<String, double> itemRevenue = {};
    Map<String, double> catRevenue = {};
    Map<String, List<Map<String, dynamic>>> catAuditHistory = {};

    for (var tx in txs) {
      final snapshots = tx.itemSnapshots;
      
      if (snapshots.isEmpty) {
        // Fallback: If no item snapshots, use Transaction's own category and amount
        String cat = tx.category;
        if (cat.isEmpty || cat.toLowerCase() == 'sale') cat = 'General';
        
        catRevenue[cat] = (catRevenue[cat] ?? 0) + tx.amount;
        
        catAuditHistory[cat] ??= [];
        catAuditHistory[cat]!.add({
          'time': DateFormat('hh:mm a').format(tx.date),
          'date': DateFormat('dd MMM').format(tx.date),
          'name': tx.type == 'sale' ? 'Quick Sale' : tx.category,
          'qty': 1.0,
          'price': tx.amount,
          'variant': 'Full',
          'extraQty': 0.0,
          'extraPrice': 0.0,
          'serving': 'N/A',
          'mode': tx.paymentMode,
          'total': tx.amount,
        });
        continue;
      }

      for (var s in snapshots) {
        String name = s.name;
        String cat = s.category;
        
        // Resolve "General" Category using Item Menu Lookup
        if (cat == '' || cat.toLowerCase() == 'general' || cat.toLowerCase() == 'uncategorized' || cat.toLowerCase() == 'sale') {
           try {
             final master = itemProvider.items.firstWhere((i) => i.name == name);
             cat = master.category;
           } catch(_) { cat = 'General'; }
        }
        
        double val = s.lineTotal;
        itemRevenue[name] = (itemRevenue[name] ?? 0) + val;
        catRevenue[cat] = (catRevenue[cat] ?? 0) + val;
        
        catAuditHistory[cat] ??= [];
        catAuditHistory[cat]!.add({
          'time': DateFormat('hh:mm a').format(tx.date),
          'date': DateFormat('dd MMM').format(tx.date),
          'name': s.name,
          'qty': s.qty,
          'price': s.price,
          'variant': s.variant,
          'extraQty': s.extraQty,
          'extraPrice': s.extraPrice,
          'serving': s.servingMethod,
          'mode': tx.paymentMode,
          'total': s.lineTotal,
        });
      }
    }

    var sortedItems = itemRevenue.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    var sortedCats = catRevenue.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _miniStat('Cash', split['Cash']!, Colors.green, profile),
            const SizedBox(width: 8),
            _miniStat('UPI', split['UPI']!, Colors.blue, profile),
            const SizedBox(width: 8),
            _miniStat('Credit', split['Credit']!, Colors.orange, profile),
          ],
        ),
        const SizedBox(height: 24),
        _sectionHeader('CATEGORY-WISE SALES', profile),
        const SizedBox(height: 12),
        // PROFESSIONAL AUDIT CLICK
        _summaryBox(sortedCats, profile, (catName) => _showCategoryDetails(context, catName, catRevenue[catName]!, catAuditHistory[catName]!, profile)),
        const SizedBox(height: 24),
        _sectionHeader('ITEM-WISE SALES', profile),
        const SizedBox(height: 12),
        _summaryBox(sortedItems.take(10).toList(), profile, null),
        const SizedBox(height: 24),
        _sectionHeader('TRANSACTION LOG', profile),
        const SizedBox(height: 12),
      ],
    );
  }

  void _showCategoryDetails(BuildContext context, String catName, double total, List<Map<String, dynamic>> history, ProfileProvider profile) {
    int halfCount = 0;
    int fullCount = 0;
    for (var sale in history) {
      if (sale['variant'].toString().toLowerCase() == 'half') halfCount++;
      if (sale['variant'].toString().toLowerCase() == 'full') fullCount++;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.85,
        decoration: BoxDecoration(color: profile.cardColor, borderRadius: const BorderRadius.vertical(top: Radius.circular(32))),
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 24), decoration: BoxDecoration(color: Colors.grey.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(2)))),
            Text('CATEGORY AUDIT', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12, color: profile.secondaryTextColor, letterSpacing: 1.5)),
            const SizedBox(height: 8),
            Text(catName.toUpperCase(), style: TextStyle(fontWeight: FontWeight.w900, fontSize: 28, color: profile.textColor)),
            Text('Total Revenue: ${profile.currencySymbol}${total.toStringAsFixed(0)}', style: TextStyle(fontWeight: FontWeight.bold, color: profile.themeColor, fontSize: 16)),
            const Divider(height: 40),
            
            Row(
              children: [
                _insightStat('Full Portions', '$fullCount', Colors.blue),
                const SizedBox(width: 12),
                _insightStat('Half Portions', '$halfCount', Colors.orange),
              ],
            ),
            const SizedBox(height: 32),
            Text('DETAILED SALES HISTORY', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 11, color: profile.secondaryTextColor, letterSpacing: 1)),
            const SizedBox(height: 16),
            Expanded(
              child: ListView.builder(
                itemCount: history.length,
                itemBuilder: (context, i) {
                  final sale = history[i];
                  String qLabel = sale['qty'] == 0.5 ? "Half" : (sale['qty'] == 1.0 ? "Full" : sale['qty'].toStringAsFixed(1));
                  bool hasExtras = sale['extraQty'] > 0 || sale['extraPrice'] > 0;

                  return Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: profile.scaffoldColor.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: profile.isDarkMode ? Colors.white10 : Colors.grey.shade100)
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(sale['name'], style: TextStyle(fontWeight: FontWeight.w900, color: profile.textColor, fontSize: 14)),
                                Text('${sale['date']} at ${sale['time']}', style: TextStyle(color: profile.secondaryTextColor, fontSize: 10, fontWeight: FontWeight.bold)),
                              ],
                            ),
                            Text('${profile.currencySymbol}${sale['total'].toStringAsFixed(0)}', style: TextStyle(fontWeight: FontWeight.w900, color: profile.themeColor, fontSize: 16)),
                          ],
                        ),
                        const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Divider(height: 1, thickness: 0.5)),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('$qLabel x ${profile.currencySymbol}${sale['price'].toStringAsFixed(0)} • ${sale['mode']}', style: TextStyle(fontSize: 11, color: profile.secondaryTextColor, fontWeight: FontWeight.bold)),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(color: profile.themeColor.withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
                              child: Text(sale['serving'].toString().toUpperCase(), style: TextStyle(fontSize: 8, fontWeight: FontWeight.w900, color: profile.themeColor)),
                            ),
                          ],
                        ),
                        if (hasExtras)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Row(
                              children: [
                                Icon(Icons.add_circle_outline_rounded, size: 12, color: Colors.blue.shade600),
                                const SizedBox(width: 6),
                                Text('Extra: ${sale['extraQty'].toInt()} x ${profile.currencySymbol}${sale['extraPrice'].toInt()}', 
                                  style: TextStyle(fontSize: 11, color: profile.textColor, fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ),
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

  Widget _insightStat(String label, String val, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: color.withOpacity(0.05), borderRadius: BorderRadius.circular(16), border: Border.all(color: color.withOpacity(0.1))),
        child: Column(
          children: [
            Text(val, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: color)),
            Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(String title, ProfileProvider profile) {
    return Text(title, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: profile.secondaryTextColor, letterSpacing: 1));
  }

  Widget _summaryBox(List<MapEntry<String, double>> entries, ProfileProvider profile, Function(String)? onTap) {
    return Container(
      decoration: BoxDecoration(
        color: profile.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: profile.isDarkMode ? Colors.white10 : Colors.grey.shade100),
      ),
      child: Column(
        children: entries.map((e) => InkWell(
          onTap: onTap != null ? () => onTap(e.key) : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Expanded(child: Text(e.key, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: profile.textColor))),
                Text('${profile.currencySymbol}${e.value.toStringAsFixed(0)}', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: profile.themeColor)),
                if (onTap != null) const Icon(Icons.chevron_right, size: 16, color: Colors.grey),
              ],
            ),
          ),
        )).toList(),
      ),
    );
  }

  Widget _miniStat(String label, double val, Color color, ProfileProvider profile) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.1)),
        ),
        child: Column(
          children: [
            Text(label, style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: color)),
            const SizedBox(height: 4),
            Text(profile.showAmount ? '${profile.currencySymbol}${val.toStringAsFixed(0)}' : '${profile.currencySymbol}****', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: profile.textColor)),
          ],
        ),
      ),
    );
  }

  void _showDetails(BuildContext context, TransactionModel tx, ProfileProvider profile) {
    final snapshots = tx.itemSnapshots;
    double calculatedSubtotal = 0;
    for (var s in snapshots) {
      calculatedSubtotal += s.lineTotal;
    }

    double discount = tx.discountValue;
    double taxAmount = tx.taxValue;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(color: profile.cardColor, borderRadius: const BorderRadius.vertical(top: Radius.circular(32))),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 24), decoration: BoxDecoration(color: Colors.grey.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(2)))),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('BILL DETAILS', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12, color: profile.secondaryTextColor, letterSpacing: 1.5)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: (tx.status == 'pending' ? Colors.orange : Colors.green).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(tx.status.toUpperCase(), style: TextStyle(color: tx.status == 'pending' ? Colors.orange : Colors.green, fontWeight: FontWeight.bold, fontSize: 10)),
                ),
              ],
            ),
            const SizedBox(height: 20),
            _detailRow('Date/Time', DateFormat('dd MMM yyyy, hh:mm a').format(tx.date), profile),
            _detailRow('Payment Mode', tx.paymentMode, profile),
            const Divider(height: 40),
            Text('ITEMS BREAKDOWN', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: profile.secondaryTextColor, letterSpacing: 1)),
            const SizedBox(height: 16),
            
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.35),
              child: SingleChildScrollView(
                child: Column(
                  children: snapshots.map((s) {
                    String qLabel = s.qty == 0.5 ? "Half" : (s.qty == 1.0 ? "Full" : s.qty.toStringAsFixed(1));
                    bool hasExtras = s.extraQty > 0 || s.extraPrice > 0;

                    return Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: profile.scaffoldColor.withOpacity(0.5),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: profile.isDarkMode ? Colors.white10 : Colors.grey.shade100)
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(s.name, style: TextStyle(fontWeight: FontWeight.w900, color: profile.textColor, fontSize: 15)),
                                    const SizedBox(height: 4),
                                    Text('$qLabel x ${profile.currencySymbol}${s.price.toStringAsFixed(0)} • ${s.variant}', 
                                      style: TextStyle(color: profile.secondaryTextColor, fontSize: 12, fontWeight: FontWeight.bold)),
                                  ],
                                ),
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text('${profile.currencySymbol}${s.lineTotal.toStringAsFixed(0)}',
                                    style: TextStyle(fontWeight: FontWeight.w900, color: profile.themeColor, fontSize: 16)),
                                  Text('Total', style: TextStyle(fontSize: 9, color: profile.secondaryTextColor, fontWeight: FontWeight.bold)),
                                ],
                              ),
                            ],
                          ),
                          if (hasExtras) ...[
                            const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Divider(height: 1, thickness: 0.5)),
                            Row(
                              children: [
                                Icon(Icons.add_circle_outline_rounded, size: 14, color: Colors.blue.shade600),
                                const SizedBox(width: 8),
                                Text('Extra Qty: ${s.extraQty.toInt()} • Extra Rs: ${profile.currencySymbol}${s.extraPrice.toInt()}',
                                  style: TextStyle(fontSize: 12, color: profile.textColor, fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ],
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
            
            const Divider(height: 40),
            _rowBreakdown('Subtotal', '${profile.currencySymbol}${calculatedSubtotal.toStringAsFixed(0)}', profile),
            if (discount > 0) _rowBreakdown('Discount', '- ${profile.currencySymbol}${discount.toStringAsFixed(0)}', profile, color: Colors.green),
            if (taxAmount > 0) _rowBreakdown('Tax', '${profile.currencySymbol}${taxAmount.toStringAsFixed(0)}', profile),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: profile.themeColor.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(20), border: Border.all(color: profile.themeColor.withValues(alpha: 0.1))),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('GRAND TOTAL', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: profile.textColor)),
                  Text(profile.showAmount ? '${profile.currencySymbol}${tx.amount.toStringAsFixed(0)}' : '${profile.currencySymbol}****', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 26, color: profile.themeColor)),
                ],
              ),
            ),
            const SizedBox(height: 32),
            if (tx.type == 'sale' || tx.type == 'income')
              ElevatedButton.icon(
                onPressed: () async {
                  final exportService = ExportService();
                  await exportService.saveBillAsPdf(tx, profile.businessName);
                  Navigator.pop(context);
                },
                icon: const Icon(Icons.print_rounded),
                label: const Text('REPRINT BILL', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1)),
                style: ElevatedButton.styleFrom(backgroundColor: profile.themeColor, foregroundColor: Colors.white, minimumSize: const Size(double.infinity, 56), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
              ),
          ],
        ),
      ),
    );
  }

  Widget _rowBreakdown(String l, String v, ProfileProvider profile, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(l, style: TextStyle(color: profile.secondaryTextColor, fontSize: 13, fontWeight: FontWeight.bold)),
        Text(v, style: TextStyle(fontWeight: FontWeight.w900, color: color ?? profile.textColor, fontSize: 14))
      ]),
    );
  }

  Widget _detailRow(String l, String v, ProfileProvider profile) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(l, style: TextStyle(color: profile.secondaryTextColor, fontSize: 13)),
        Text(v, style: TextStyle(fontWeight: FontWeight.bold, color: profile.textColor, fontSize: 13))
      ]),
    );
  }
}

class _StaffReportList extends StatelessWidget {
  final DateTimeRange range;
  const _StaffReportList({required this.range});

  @override
  Widget build(BuildContext context) {
    final staffProvider = Provider.of<StaffProvider>(context);
    final profile = Provider.of<ProfileProvider>(context);
    final staffList = staffProvider.staffList;

    if (staffList.isEmpty) {
      return Center(child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.people_outline, size: 64, color: profile.secondaryTextColor.withValues(alpha: 0.1)),
          const SizedBox(height: 16),
          Text('No staff records found', style: TextStyle(color: profile.secondaryTextColor, fontWeight: FontWeight.bold)),
        ],
      ));
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
      itemCount: staffList.length,
      itemBuilder: (context, index) {
        final staff = staffList[index];
        final payable = staffProvider.calculatePayable(staff);
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: profile.cardColor,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: profile.isDarkMode ? Colors.white10 : Colors.grey.shade100),
          ),
          child: ExpansionTile(
            shape: const RoundedRectangleBorder(side: BorderSide.none),
            collapsedShape: const RoundedRectangleBorder(side: BorderSide.none),
            leading: CircleAvatar(backgroundColor: profile.themeColor.withValues(alpha: 0.1), child: Icon(Icons.person_outline, color: profile.themeColor, size: 20)),
            title: Text(staff.name, style: TextStyle(fontWeight: FontWeight.bold, color: profile.textColor, fontSize: 14)),
            subtitle: Text('Monthly: ${profile.currencySymbol}${staff.monthlySalary.toStringAsFixed(0)}', style: TextStyle(fontSize: 11, color: profile.secondaryTextColor)),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Column(
                  children: [
                    const Divider(),
                    _row('Base Salary', '${profile.currencySymbol}${profile.showAmount ? staff.monthlySalary : "****"}', profile),
                    _row('Advance Given', '${profile.currencySymbol}${profile.showAmount ? staff.advance : "****"}', profile, color: Colors.red),
                    _row('Leaves (${staff.totalLeaves})', '- ${profile.currencySymbol}${(staff.monthlySalary / 30 * staff.totalLeaves).toStringAsFixed(0)}', profile, color: Colors.red),
                    const Divider(),
                    _row('NET PAYABLE', '${profile.currencySymbol}${profile.showAmount ? payable.toStringAsFixed(0) : "****"}', profile, isBold: true, color: Colors.green),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      onPressed: () => _paySalary(context, staff, payable),
                      icon: const Icon(Icons.payments_outlined, size: 18),
                      label: const Text('PAY & ADD TO EXPENSE'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(double.infinity, 45),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                    ),
                  ],
                ),
              )
            ],
          ),
        );
      },
    );
  }

  void _paySalary(BuildContext context, dynamic staff, double amount) {
    final txProvider = Provider.of<TransactionProvider>(context, listen: false);
    final staffProvider = Provider.of<StaffProvider>(context, listen: false);
    final itemProvider = Provider.of<ItemProvider>(context, listen: false);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm Salary Payment'),
        content: Text('Add ${amount.toStringAsFixed(0)} as an expense and reset leaves/advance for ${staff.name}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CANCEL')),
          ElevatedButton(
            onPressed: () async {
              final tx = TransactionModel(
                type: 'purchase',
                category: 'Salary',
                description: 'Salary Paid to ${staff.name} for ${DateFormat('MMMM yyyy').format(DateTime.now())}',
                amount: amount,
                date: DateTime.now(),
                paymentMode: 'Cash',
                status: 'completed',
              );
              await txProvider.addTransaction(tx, itemProvider);

              staff.advance = 0;
              staff.totalLeaves = 0;
              await staffProvider.updateStaff(staff);

              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Salary paid and added to expenses!')));
            },
            child: const Text('CONFIRM'),
          ),
        ],
      ),
    );
  }

  Widget _row(String l, String v, ProfileProvider profile, {bool isBold = false, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(l, style: TextStyle(color: profile.secondaryTextColor, fontSize: 12, fontWeight: isBold ? FontWeight.bold : FontWeight.normal)),
        Text(v, style: TextStyle(fontWeight: isBold ? FontWeight.w900 : FontWeight.bold, color: color ?? profile.textColor, fontSize: isBold ? 14 : 12))
      ]),
    );
  }
}

class _TrashList extends StatefulWidget {
  const _TrashList();

  @override
  State<_TrashList> createState() => _TrashListState();
}

class _TrashListState extends State<_TrashList> {
  final Set<int> _selectedIds = {};

  String _getSmartTitle(TransactionModel tx) {
    final items = tx.parsedItems;
    if (items.isEmpty) return tx.type == 'sale' ? 'Sale' : 'Purchase';
    if (items.length == 1) return items.first['name'] ?? 'Item';
    return '${items.first['name']} + ${items.length - 1} more';
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

  void _bulkPermanentDelete() {
    if (_selectedIds.isEmpty) return;
    final txProvider = Provider.of<TransactionProvider>(context, listen: false);
    final profile = Provider.of<ProfileProvider>(context, listen: false);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: profile.cardColor,
        title: Text('Delete ${_selectedIds.length} Permanently?'),
        content: const Text('This action cannot be undone. Data will be removed from cloud and local storage.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CANCEL')),
          TextButton(
            onPressed: () async {
              for (int id in _selectedIds) {
                await txProvider.permanentDeleteTransaction(id);
              }
              setState(() => _selectedIds.clear());
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Entries permanently deleted!')));
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
    final profile = Provider.of<ProfileProvider>(context);
    final itemProvider = Provider.of<ItemProvider>(context, listen: false);
    final deleted = txProvider.deletedTransactions;
    final isSelectionMode = _selectedIds.isNotEmpty;

    if (deleted.isEmpty) {
      return Center(child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.delete_sweep_outlined, size: 64, color: profile.secondaryTextColor.withValues(alpha: 0.1)),
          const SizedBox(height: 16),
          Text('Trash is empty', style: TextStyle(color: profile.secondaryTextColor, fontWeight: FontWeight.bold)),
        ],
      ));
    }

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            color: isSelectionMode ? Colors.red.shade700 : Colors.red.withValues(alpha: 0.05),
            border: Border(bottom: BorderSide(color: Colors.red.withValues(alpha: 0.1)))
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(isSelectionMode ? '${_selectedIds.length} SELECTED' : '${deleted.length} DELETED ITEMS', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 11, color: isSelectionMode ? Colors.white : Colors.red, letterSpacing: 0.5)),
              if (isSelectionMode)
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white, size: 18),
                      onPressed: () => setState(() => _selectedIds.clear()),
                      visualDensity: VisualDensity.compact,
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_forever_rounded, color: Colors.white, size: 22),
                      onPressed: _bulkPermanentDelete,
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                )
              else
                const Text('RESTORE TO RECOVER', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 11, color: Colors.red)),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
            itemCount: deleted.length,
            itemBuilder: (context, index) {
              final tx = deleted[index];
              final isPending = tx.status == 'pending';
              final isSelected = _selectedIds.contains(tx.id);
              
              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: isSelected ? Colors.red.withValues(alpha: 0.08) : profile.cardColor,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: isSelected ? Colors.red : Colors.red.withValues(alpha: 0.1), width: isSelected ? 2 : 1),
                ),
                child: ListTile(
                  onLongPress: () => _toggleSelection(tx.id!),
                  onTap: isSelectionMode ? () => _toggleSelection(tx.id!) : () => _showDeletedActions(context, tx, txProvider, itemProvider, profile),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  leading: isSelected 
                    ? const Icon(Icons.check_circle, color: Colors.red, size: 28)
                    : Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(color: (isPending ? Colors.orange : Colors.grey).withValues(alpha: 0.1), shape: BoxShape.circle),
                        child: Icon(
                          isPending ? Icons.timer_outlined : (tx.type == 'sale' ? Icons.south_west_rounded : Icons.north_east_rounded), 
                          color: isPending ? Colors.orange : Colors.grey, 
                          size: 18
                        ),
                      ),
                  title: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _getSmartTitle(tx), 
                          style: TextStyle(fontWeight: FontWeight.bold, color: profile.textColor, fontSize: 14),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (isPending)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: Colors.orange.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
                          child: const Text('PENDING', style: TextStyle(color: Colors.orange, fontSize: 8, fontWeight: FontWeight.bold)),
                        ),
                    ],
                  ),
                  subtitle: Text('Deleted on: ${tx.deletedAt != null ? DateFormat('dd MMM, hh:mm a').format(tx.deletedAt!) : 'N/A'}', style: TextStyle(fontSize: 10, color: profile.secondaryTextColor)),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(profile.showAmount ? '${profile.currencySymbol}${tx.amount.toStringAsFixed(0)}' : '${profile.currencySymbol}****', style: TextStyle(fontWeight: FontWeight.w900, color: profile.textColor, fontSize: 14)),
                      if (!isSelectionMode) const Icon(Icons.chevron_right_rounded, size: 20, color: Colors.grey),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  void _showDeletedActions(BuildContext context, TransactionModel tx, TransactionProvider txProvider, ItemProvider itemProvider, ProfileProvider profile) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(color: profile.cardColor, borderRadius: const BorderRadius.vertical(top: Radius.circular(32))),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 24), decoration: BoxDecoration(color: Colors.grey.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(2)))),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('DELETED ENTRY DETAILS', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12, color: profile.secondaryTextColor, letterSpacing: 1.5)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: Colors.red.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                  child: const Text('TRASHED', style: TextStyle(color: Colors.red, fontWeight: FontWeight.w900, fontSize: 10)),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text(_getSmartTitle(tx), style: TextStyle(color: profile.textColor, fontWeight: FontWeight.w900, fontSize: 22)),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.calendar_today, size: 14, color: profile.secondaryTextColor),
                const SizedBox(width: 6),
                Text(DateFormat('dd MMM yyyy, hh:mm a').format(tx.date), style: TextStyle(color: profile.secondaryTextColor, fontSize: 13)),
              ],
            ),
            const Divider(height: 40),
            
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.3),
              child: SingleChildScrollView(
                child: Column(
                  children: tx.parsedItems.map((item) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(item['name'] ?? '', style: TextStyle(fontWeight: FontWeight.bold, color: profile.textColor)),
                          Text('${item['qty']} x ${profile.currencySymbol}${item['price']}', style: TextStyle(color: profile.secondaryTextColor, fontSize: 12)),
                        ]),
                        Text(profile.showAmount ? '${profile.currencySymbol}${(double.parse(item['qty'] ?? '0') * double.parse(item['price'] ?? '0')).toStringAsFixed(0)}' : '${profile.currencySymbol}****', style: const TextStyle(fontWeight: FontWeight.w900)),
                      ],
                    ),
                  )).toList(),
                ),
              ),
            ),
            
            const Divider(height: 40),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('TOTAL AMOUNT', style: TextStyle(fontWeight: FontWeight.bold)),
                Text(profile.showAmount ? '${profile.currencySymbol}${tx.amount.toStringAsFixed(0)}' : '${profile.currencySymbol}****', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 24, color: Colors.red)),
              ],
            ),
            const SizedBox(height: 28),
            Row(
              children: [
                Expanded(
                  child: _actionBtn(
                    icon: Icons.restore_from_trash_rounded,
                    label: 'RESTORE',
                    color: Colors.green,
                    onTap: () async {
                      Navigator.pop(context);
                      await txProvider.restoreTransaction(tx.id!, itemProvider);
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Entry restored!')));
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _actionBtn(
                    icon: Icons.delete_forever_rounded,
                    label: 'PERMANENT',
                    color: Colors.red,
                    onTap: () {
                      Navigator.pop(context);
                      _showPermanentDeleteConfirm(context, tx, txProvider, profile);
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _actionBtn({required IconData icon, required String label, required Color color, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(16), border: Border.all(color: color.withValues(alpha: 0.3))),
        child: Column(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 6),
            Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 11)),
          ],
        ),
      ),
    );
  }

  void _showPermanentDeleteConfirm(BuildContext context, TransactionModel tx, TransactionProvider txProvider, ProfileProvider profile) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: profile.cardColor,
        title: const Text('Delete Permanently?'),
        content: const Text('This action is final and cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CANCEL')),
          TextButton(
            onPressed: () async {
              await txProvider.permanentDeleteTransaction(tx.id!);
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Entry permanently deleted.')));
            },
            child: const Text('DELETE', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}
