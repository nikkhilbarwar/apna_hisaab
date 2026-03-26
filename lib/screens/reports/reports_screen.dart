import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../models/transaction_model.dart';
import '../../providers/transaction_provider.dart';
import '../../providers/category_provider.dart';
import '../../providers/profile_provider.dart';
import '../../providers/staff_provider.dart';
import '../../providers/item_provider.dart';
import '../../services/export_service.dart';
import '../../services/notification_service.dart';
import '../daily_entry/entry_screen.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  int _currentIndex = 0;
  DateTimeRange _selectedRange = DateTimeRange(
    start: DateTime.now().subtract(const Duration(days: 7)),
    end: DateTime.now(),
  );
  String _selectedCategory = 'All';

  @override
  Widget build(BuildContext context) {
    final profile = Provider.of<ProfileProvider>(context);
    final themeColor = profile.themeColor;
    final txProvider = Provider.of<TransactionProvider>(context);

    // Dynamic Calculations for Pro-Reporting - Now respecting Category Filter
    final allSalesSummary = txProvider.getFilteredTransactions(
      type: 'sale', 
      range: _selectedRange, 
      category: _selectedCategory,
      status: 'completed'
    );
    final allPurchasesSummary = txProvider.getFilteredTransactions(
      type: 'purchase', 
      range: _selectedRange, 
      category: _selectedCategory,
      status: 'completed'
    );
    
    double totalRevenue = allSalesSummary.fold(0, (sum, tx) => sum + tx.amount);
    double totalExpense = allPurchasesSummary.fold(0, (sum, tx) => sum + tx.amount);
    double netProfit = totalRevenue - totalExpense;

    return Scaffold(
      backgroundColor: profile.scaffoldColor,
      appBar: AppBar(
        elevation: 0,
        title: Text(_currentIndex == 3 ? 'TRASH BIN' : 'BUSINESS REPORTS', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 1, color: Colors.white)),
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [_currentIndex == 3 ? Colors.red.shade400 : themeColor.withOpacity(0.8), _currentIndex == 3 ? Colors.red.shade700 : themeColor]),
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
      body: Column(
        children: [
          // Fixed Header Section
          if (_currentIndex != 3) ...[
             _buildFilters(context, profile),
             _buildExecutiveSummary(totalRevenue, totalExpense, netProfit, profile),
          ],
          
          // Scrollable List with Fade Effect
          Expanded(
            child: Stack(
              children: [
                ShaderMask(
                  shaderCallback: (Rect rect) {
                    return const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Colors.black, Colors.black, Colors.black],
                      stops: [0.0, 0.05, 0.9, 1.0], 
                    ).createShader(rect);
                  },
                  blendMode: BlendMode.dstIn,
                  child: IndexedStack(
                    index: _currentIndex,
                    children: [
                      _ReportList(type: 'sale', range: _selectedRange, category: _selectedCategory),
                      _ReportList(type: 'purchase', range: _selectedRange, category: _selectedCategory),
                      _StaffReportList(range: _selectedRange),
                      const _TrashList(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 20, offset: const Offset(0, -5))],
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (index) => setState(() => _currentIndex = index),
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

  Widget _buildExecutiveSummary(double revenue, double expense, double profit, ProfileProvider profile) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      decoration: BoxDecoration(
        color: profile.cardColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 10), 
          )
        ],
      ),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [profile.themeColor.withOpacity(0.05), profile.themeColor.withOpacity(0.1)]),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: profile.themeColor.withOpacity(0.1)),
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
    );
  }

  Widget _summaryItem(String label, double val, Color color, ProfileProvider profile, {bool isBold = false}) {
    return Expanded(
      child: Column(
        children: [
          Text(label, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: profile.secondaryTextColor, letterSpacing: 0.5)),
          const SizedBox(height: 4),
          Text(
            '${profile.currencySymbol}${val.toStringAsFixed(0)}',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: color),
          ),
        ],
      ),
    );
  }

  Widget _verticalDivider(ProfileProvider profile) => Container(height: 30, width: 1, color: profile.secondaryTextColor.withOpacity(0.1));

  Widget _buildFilters(BuildContext context, ProfileProvider profile) {
    final catProvider = Provider.of<CategoryProvider>(context);
    return Container(
      padding: const EdgeInsets.all(16),
      color: profile.cardColor,
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: () async {
                final r = await showDateRangePicker(
                  context: context,
                  initialDateRange: _selectedRange,
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now(),
                  builder: (context, child) => Theme(
                    data: Theme.of(context).copyWith(
                      colorScheme: ColorScheme.light(primary: profile.themeColor),
                    ),
                    child: child!,
                  ),
                );
                if (r != null) setState(() => _selectedRange = r);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                decoration: BoxDecoration(
                  color: profile.scaffoldColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: profile.isDarkMode ? Colors.white10 : Colors.grey.shade200),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.calendar_today, size: 14, color: profile.themeColor),
                    const SizedBox(width: 8),
                    Text(
                      DateFormat('dd MMM').format(_selectedRange.start) == DateFormat('dd MMM').format(_selectedRange.end)
                        ? DateFormat('dd MMM yyyy').format(_selectedRange.start)
                        : '${DateFormat('dd MMM').format(_selectedRange.start)} - ${DateFormat('dd MMM').format(_selectedRange.end)}',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: profile.textColor),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: profile.scaffoldColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: profile.isDarkMode ? Colors.white10 : Colors.grey.shade200),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedCategory,
                  isExpanded: true,
                  dropdownColor: profile.cardColor,
                  style: TextStyle(color: profile.textColor, fontWeight: FontWeight.bold, fontSize: 13),
                  items: ['All', ...catProvider.categories.map((c) => c.name)].map((String value) {
                    return DropdownMenuItem<String>(value: value, child: Text(value));
                  }).toList(),
                  onChanged: (val) => setState(() => _selectedCategory = val!),
                ),
              ),
            ),
          ),
        ],
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
            Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 24), decoration: BoxDecoration(color: Colors.grey.withOpacity(0.3), borderRadius: BorderRadius.circular(2))),
            Text('DOWNLOAD REPORT', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: profile.textColor, letterSpacing: 1)),
            const SizedBox(height: 24),
            _exportTile(Icons.table_view_rounded, 'Download as Excel Sheet', Colors.green, () async {
              final txs = txProvider.getFilteredTransactions(
                type: _currentIndex == 0 ? 'sale' : 'purchase',
                range: _selectedRange,
                category: _selectedCategory,
                status: 'completed'
              );
              Navigator.pop(context);
              await exportService.exportToExcel(txs, "${_currentIndex == 0 ? 'Sales' : 'Expense'}_Report");
              NotificationService().showNotification(id: 888, title: "Report Downloaded", body: "Excel report saved in Documents folder.");
            }, profile),
            const SizedBox(height: 12),
            _exportTile(Icons.picture_as_pdf_rounded, 'Download as PDF Report', Colors.red, () async {
              final txs = txProvider.getFilteredTransactions(
                type: _currentIndex == 0 ? 'sale' : 'purchase',
                range: _selectedRange,
                category: _selectedCategory,
                status: 'completed'
              );
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

class _ReportList extends StatelessWidget {
  final String type;
  final DateTimeRange range;
  final String category;

  const _ReportList({required this.type, required this.range, required this.category});

  @override
  Widget build(BuildContext context) {
    final txProvider = Provider.of<TransactionProvider>(context);
    final profile = Provider.of<ProfileProvider>(context);
    
    final filtered = txProvider.getFilteredTransactions(
      type: type, 
      range: range, 
      category: category == 'All' ? null : category, 
      status: 'completed'
    );

    if (filtered.isEmpty) {
      return Center(child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.analytics_outlined, size: 64, color: profile.secondaryTextColor.withOpacity(0.1)),
          const SizedBox(height: 16),
          Text('No records found for this period', style: TextStyle(color: profile.secondaryTextColor, fontWeight: FontWeight.bold)),
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
              color: profile.themeColor.withOpacity(0.05),
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: profile.themeColor.withOpacity(0.1))
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('${filtered.length} TRANSACTIONS', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 11, color: profile.themeColor, letterSpacing: 0.5)),
                Text('TOTAL: ${profile.currencySymbol}${total.toStringAsFixed(0)}', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: profile.themeColor)),
              ],
            ),
          );
        }
        if (index == 1) {
          return _buildQuickStats(filtered, profile, txProvider, type);
        }
        
        final tx = filtered[index - 2];
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: profile.cardColor,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: profile.isDarkMode ? Colors.white10 : Colors.grey.shade100),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))],
          ),
          child: ListTile(
            onTap: () => _showDetails(context, tx, profile),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            leading: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: (tx.type == 'sale' ? Colors.green : Colors.red).withOpacity(0.1), shape: BoxShape.circle),
              child: Icon(tx.type == 'sale' ? Icons.south_west_rounded : Icons.north_east_rounded, color: tx.type == 'sale' ? Colors.green : Colors.red, size: 18),
            ),
            title: Text(tx.type == 'sale' ? (tx.parsedItems.isNotEmpty ? "${tx.parsedItems[0]['name']}${tx.parsedItems[0]['variant'] != '' ? ' (${tx.parsedItems[0]['variant']})' : ''}" : 'Sale') : tx.category, style: TextStyle(fontWeight: FontWeight.bold, color: profile.textColor, fontSize: 14)),
            subtitle: Text(DateFormat('dd MMM, hh:mm a').format(tx.date), style: TextStyle(fontSize: 11, color: profile.secondaryTextColor)),
            trailing: Text('${profile.currencySymbol}${tx.amount.toStringAsFixed(0)}', style: TextStyle(fontWeight: FontWeight.w900, color: tx.type == 'sale' ? Colors.green.shade700 : Colors.red.shade700, fontSize: 15)),
          ),
        );
      },
    );
  }

  Widget _buildQuickStats(List<TransactionModel> txs, ProfileProvider profile, TransactionProvider provider, String reportType) {
    // Both Sales and Expenses now get Payment Summary
    final split = provider.getPaymentSplit(txs);
    final topItems = reportType == 'sale' ? provider.getTopItems(txs) : <String, int>{};

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('PAYMENT SUMMARY', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: profile.secondaryTextColor, letterSpacing: 1)),
        const SizedBox(height: 12),
        Row(
          children: [
            _miniStat('Cash', split['Cash']!, Colors.green, profile),
            const SizedBox(width: 8),
            _miniStat('UPI', split['UPI']!, Colors.blue, profile),
            const SizedBox(width: 8),
            _miniStat('Credit', split['Credit']!, Colors.orange, profile),
          ],
        ),
        if (reportType == 'sale' && topItems.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text('TOP SELLING ITEMS', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: profile.secondaryTextColor, letterSpacing: 1)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: topItems.entries.map((e) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: profile.themeColor.withOpacity(0.05),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: profile.themeColor.withOpacity(0.1)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(e.key, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: profile.textColor)),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    decoration: BoxDecoration(color: profile.themeColor, borderRadius: BorderRadius.circular(4)),
                    child: Text('${e.value}', style: const TextStyle(fontSize: 9, color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            )).toList(),
          ),
        ],
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _miniStat(String label, double val, Color color, ProfileProvider profile) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.1)),
        ),
        child: Column(
          children: [
            Text(label, style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: color)),
            const SizedBox(height: 4),
            Text('${profile.currencySymbol}${val.toStringAsFixed(0)}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: profile.textColor)),
          ],
        ),
      ),
    );
  }

  void _showDetails(BuildContext context, TransactionModel tx, ProfileProvider profile) {
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
            Center(child: Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 24), decoration: BoxDecoration(color: Colors.grey.withOpacity(0.3), borderRadius: BorderRadius.circular(2)))),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('BILL DETAILS', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12, color: profile.secondaryTextColor, letterSpacing: 1.5)),
                if (tx.parsedItems.isNotEmpty && tx.parsedItems.first['table_number'] != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: profile.themeColor.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                    child: Text('TABLE: ${tx.parsedItems.first['table_number']}', style: TextStyle(color: profile.themeColor, fontWeight: FontWeight.w900, fontSize: 10)),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            _detailRow('Date/Time', DateFormat('dd MMM yyyy, hh:mm a').format(tx.date), profile),
            _detailRow('Payment Mode', tx.paymentMode, profile),
            const Divider(height: 40),
            Text('ITEMS LIST', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: profile.secondaryTextColor, letterSpacing: 1)),
            const SizedBox(height: 12),
            ...tx.parsedItems.map((i) => Padding(
              padding: const EdgeInsets.only(bottom: 12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(child: Text('${i['name']}${i['variant'] != '' ? ' (${i['variant']})' : ''} x ${i['qty']}', style: TextStyle(fontWeight: FontWeight.bold, color: profile.textColor, fontSize: 14))),
                      Text('${profile.currencySymbol}${i['price']}', style: TextStyle(color: profile.themeColor, fontWeight: FontWeight.w900)),
                    ],
                  ),
                  if (i['serving_method'] != null && i['serving_method'] != '')
                    Container(
                      margin: const EdgeInsets.only(top: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: profile.themeColor.withOpacity(0.05), borderRadius: BorderRadius.circular(4)),
                      child: Text(i['serving_method']!.toUpperCase(), style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: profile.themeColor)),
                    ),
                ],
              ),
            )),
            const Divider(height: 40),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('GRAND TOTAL', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: profile.textColor)),
                Text('${profile.currencySymbol}${tx.amount.toStringAsFixed(0)}', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 26, color: profile.themeColor)),
              ],
            ),
            const SizedBox(height: 32),
            if (tx.type == 'sale')
              ElevatedButton.icon(
                onPressed: () async {
                  final exportService = ExportService();
                  await exportService.saveBillAsPdf(tx, profile.businessName);
                  Navigator.pop(context);
                },
                icon: const Icon(Icons.print_rounded),
                label: const Text('REPRINT BILL', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: profile.themeColor,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 56),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))
                ),
              ),
          ],
        ),
      ),
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
          Icon(Icons.people_outline, size: 64, color: profile.secondaryTextColor.withOpacity(0.1)),
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
            leading: CircleAvatar(backgroundColor: profile.themeColor.withOpacity(0.1), child: Icon(Icons.person_outline, color: profile.themeColor, size: 20)),
            title: Text(staff.name, style: TextStyle(fontWeight: FontWeight.bold, color: profile.textColor, fontSize: 14)),
            subtitle: Text('Contact: ${staff.contact}', style: TextStyle(fontSize: 11, color: profile.secondaryTextColor)),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Column(
                  children: [
                    const Divider(),
                    _row('Monthly Salary', '${profile.currencySymbol}${staff.monthlySalary}', profile),
                    _row('Advance Taken', '${profile.currencySymbol}${staff.advance}', profile, color: Colors.red),
                    _row('Leaves Taken', '${staff.totalLeaves} days', profile),
                    const Divider(),
                    _row('NET PAYABLE', '${profile.currencySymbol}${payable}', profile, isBold: true, color: profile.themeColor),
                  ],
                ),
              )
            ],
          ),
        );
      },
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
    return '${items.length} Items: ${items.take(2).map((e) => e['name']).join(', ')}...';
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
          Icon(Icons.delete_sweep_outlined, size: 64, color: profile.secondaryTextColor.withOpacity(0.1)),
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
            color: isSelectionMode ? Colors.red.shade700 : Colors.red.withOpacity(0.05),
            border: Border(bottom: BorderSide(color: Colors.red.withOpacity(0.1)))
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
                  color: isSelected ? Colors.red.withOpacity(0.08) : profile.cardColor,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: isSelected ? Colors.red : Colors.red.withOpacity(0.1), width: isSelected ? 2 : 1),
                ),
                child: ListTile(
                  onLongPress: () => _toggleSelection(tx.id!),
                  onTap: isSelectionMode ? () => _toggleSelection(tx.id!) : () => _showDeletedActions(context, tx, txProvider, itemProvider, profile),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  leading: isSelected 
                    ? const Icon(Icons.check_circle, color: Colors.red, size: 28)
                    : Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(color: (isPending ? Colors.orange : Colors.grey).withOpacity(0.1), shape: BoxShape.circle),
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
                          decoration: BoxDecoration(color: Colors.orange.withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
                          child: const Text('PENDING', style: TextStyle(color: Colors.orange, fontSize: 8, fontWeight: FontWeight.bold)),
                        ),
                    ],
                  ),
                  subtitle: Text('Deleted on: ${tx.deletedAt != null ? DateFormat('dd MMM, hh:mm a').format(tx.deletedAt!) : 'N/A'}', style: TextStyle(fontSize: 10, color: profile.secondaryTextColor)),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('${profile.currencySymbol}${tx.amount.toStringAsFixed(0)}', style: TextStyle(fontWeight: FontWeight.w900, color: profile.textColor, fontSize: 14)),
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
            Center(child: Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 24), decoration: BoxDecoration(color: Colors.grey.withOpacity(0.3), borderRadius: BorderRadius.circular(2)))),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('DELETED ENTRY DETAILS', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12, color: profile.secondaryTextColor, letterSpacing: 1.5)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: Colors.red.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
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
                        Text('${profile.currencySymbol}${(double.parse(item['qty'] ?? '0') * double.parse(item['price'] ?? '0')).toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.w900)),
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
                Text('${profile.currencySymbol}${tx.amount.toStringAsFixed(0)}', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 24, color: Colors.red)),
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
        decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(16), border: Border.all(color: color.withOpacity(0.3))),
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
