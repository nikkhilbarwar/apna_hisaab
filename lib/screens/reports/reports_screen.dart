import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../models/transaction_model.dart';
import '../../providers/transaction_provider.dart';
import '../../providers/category_provider.dart';
import '../../providers/profile_provider.dart';
import '../../providers/staff_provider.dart';
import '../../services/export_service.dart';
import '../../services/notification_service.dart';

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
  String _searchItem = '';

  @override
  Widget build(BuildContext context) {
    final profile = Provider.of<ProfileProvider>(context);
    final themeColor = profile.themeColor;

    return Scaffold(
      backgroundColor: profile.scaffoldColor,
      appBar: AppBar(
        title: const Text('BUSINESS REPORTS', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 1, color: Colors.white)),
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [themeColor.withOpacity(0.8), themeColor]),
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Download Report',
            icon: const Icon(Icons.file_download_outlined, color: Colors.white, size: 26),
            onPressed: () => _showExportOptions(context),
          ),
        ],
      ),
      body: Column(
        children: [
          _buildFilters(context, profile),
          Expanded(
            child: IndexedStack(
              index: _currentIndex,
              children: [
                _ReportList(type: 'sale', range: _selectedRange, category: _selectedCategory, item: _searchItem),
                _ReportList(type: 'purchase', range: _selectedRange, category: _selectedCategory, item: _searchItem),
                _StaffReportList(range: _selectedRange),
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
          selectedItemColor: themeColor,
          unselectedItemColor: profile.secondaryTextColor,
          selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12),
          unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
          type: BottomNavigationBarType.fixed,
          backgroundColor: profile.cardColor,
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.auto_graph_rounded), label: 'SALES'),
            BottomNavigationBarItem(icon: Icon(Icons.receipt_long_rounded), label: 'EXPENSES'),
            BottomNavigationBarItem(icon: Icon(Icons.people_alt_rounded), label: 'STAFF'),
          ],
        ),
      ),
    );
  }

  Widget _buildFilters(BuildContext context, ProfileProvider profile) {
    final catProvider = Provider.of<CategoryProvider>(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: profile.cardColor,
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10)]
      ),
      child: Column(
        children: [
          Row(
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
          if (_currentIndex != 2) ...[
            const SizedBox(height: 12),
            TextField(
              style: TextStyle(color: profile.textColor, fontWeight: FontWeight.bold, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Search items in this period...',
                prefixIcon: const Icon(Icons.search, size: 20),
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                fillColor: profile.scaffoldColor,
              ),
              onChanged: (val) => setState(() => _searchItem = val),
            ),
          ],
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
                itemName: _searchItem,
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
                itemName: _searchItem,
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
  final String item;

  const _ReportList({required this.type, required this.range, required this.category, required this.item});

  @override
  Widget build(BuildContext context) {
    final txProvider = Provider.of<TransactionProvider>(context);
    final profile = Provider.of<ProfileProvider>(context);
    
    final filtered = txProvider.getFilteredTransactions(
      type: type, 
      range: range, 
      category: category == 'All' ? null : category, 
      itemName: item,
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

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            color: profile.themeColor.withOpacity(0.05),
            border: Border(bottom: BorderSide(color: profile.themeColor.withOpacity(0.1)))
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('${filtered.length} TRANSACTIONS', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 11, color: profile.themeColor, letterSpacing: 0.5)),
              Text('TOTAL: ${profile.currencySymbol}${total.toStringAsFixed(0)}', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: profile.themeColor)),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: filtered.length,
            itemBuilder: (context, index) {
              final tx = filtered[index];
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
                    decoration: BoxDecoration(color: (type == 'sale' ? Colors.green : Colors.red).withOpacity(0.1), shape: BoxShape.circle),
                    child: Icon(type == 'sale' ? Icons.south_west_rounded : Icons.north_east_rounded, color: type == 'sale' ? Colors.green : Colors.red, size: 18),
                  ),
                  // logic: Show item name with its variant to avoid confusion
                  title: Text(tx.type == 'sale' ? (tx.parsedItems.isNotEmpty ? "${tx.parsedItems[0]['name']}${tx.parsedItems[0]['variant'] != '' ? ' (${tx.parsedItems[0]['variant']})' : ''}" : 'Sale') : tx.category, style: TextStyle(fontWeight: FontWeight.bold, color: profile.textColor, fontSize: 14)),
                  subtitle: Text(DateFormat('dd MMM, hh:mm a').format(tx.date), style: TextStyle(fontSize: 11, color: profile.secondaryTextColor)),
                  trailing: Text('${profile.currencySymbol}${tx.amount.toStringAsFixed(0)}', style: TextStyle(fontWeight: FontWeight.w900, color: type == 'sale' ? Colors.green.shade700 : Colors.red.shade700, fontSize: 15)),
                ),
              );
            },
          ),
        ),
      ],
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
            Text('TRANSACTION DETAILS', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12, color: profile.secondaryTextColor, letterSpacing: 1.5)),
            const SizedBox(height: 20),
            _detailRow('Date/Time', DateFormat('dd MMM yyyy, hh:mm a').format(tx.date), profile),
            _detailRow('Category', tx.category, profile),
            _detailRow('Payment Mode', tx.paymentMode, profile),
            const Divider(height: 40),
            Text('ITEMS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: profile.secondaryTextColor, letterSpacing: 1)),
            const SizedBox(height: 12),
            ...tx.parsedItems.map((i) => Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // logic: Include variant in detail view too
                  Text('${i['name']}${i['variant'] != '' ? ' (${i['variant']})' : ''} x ${i['qty']}', style: TextStyle(fontWeight: FontWeight.bold, color: profile.textColor)),
                  Text('${profile.currencySymbol}${i['price']}', style: TextStyle(color: profile.secondaryTextColor, fontWeight: FontWeight.bold)),
                ],
              ),
            )),
            const Divider(height: 40),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('TOTAL AMOUNT', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: profile.textColor)),
                Text('${profile.currencySymbol}${tx.amount}', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 24, color: profile.themeColor)),
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
      padding: const EdgeInsets.all(16),
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
