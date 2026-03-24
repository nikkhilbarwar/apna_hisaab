import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../providers/transaction_provider.dart';
import '../../providers/staff_provider.dart';
import '../../providers/profile_provider.dart';
import '../../providers/category_provider.dart';
import '../../models/transaction_model.dart';
import '../../models/staff_model.dart';
import '../../services/export_service.dart';
import '../history/history_screen.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  DateTimeRange _selectedRange = DateTimeRange(
    start: DateTime.now(),
    end: DateTime.now(),
  );
  String _selectedCategory = 'All';
  String _searchItem = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profile = Provider.of<ProfileProvider>(context);
    final themeColor = profile.themeColor;

    return Scaffold(
      backgroundColor: profile.scaffoldColor,
      appBar: AppBar(
        title: const Text('BUSINESS REPORTS', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, letterSpacing: 1, color: Colors.white)),
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [themeColor.withOpacity(0.8), themeColor]),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.file_download_outlined, color: Colors.white),
            onPressed: () => _showExportOptions(context),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(text: 'Sales'),
            Tab(text: 'Purchases'),
            Tab(text: 'Staff'),
          ],
        ),
      ),
      body: Column(
        children: [
          _buildFilters(context, profile),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _ReportList(type: 'sale', range: _selectedRange, category: _selectedCategory, item: _searchItem),
                _ReportList(type: 'purchase', range: _selectedRange, category: _selectedCategory, item: _searchItem),
                _StaffReportList(range: _selectedRange),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilters(BuildContext context, ProfileProvider profile) {
    final catProvider = Provider.of<CategoryProvider>(context);
    return Container(
      padding: const EdgeInsets.all(16),
      color: profile.cardColor,
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
                      border: Border.all(color: profile.isDarkMode ? Colors.white10 : Colors.grey.shade200),
                      borderRadius: BorderRadius.circular(12),
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
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: profile.textColor),
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
                    border: Border.all(color: profile.isDarkMode ? Colors.white10 : Colors.grey.shade200),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _selectedCategory,
                      isExpanded: true,
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
          const SizedBox(height: 12),
          TextField(
            decoration: InputDecoration(
              hintText: 'Search by item name...',
              prefixIcon: const Icon(Icons.search, size: 20),
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              filled: true,
              fillColor: profile.scaffoldColor,
            ),
            onChanged: (val) => setState(() => _searchItem = val),
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
            Text('EXPORT REPORT', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: profile.textColor)),
            const SizedBox(height: 24),
            _exportTile(Icons.table_view_rounded, 'Export as Excel (XLSX)', Colors.green, () {
              final txs = txProvider.getFilteredTransactions(
                type: _tabController.index == 0 ? 'sale' : 'purchase',
                range: _selectedRange,
                category: _selectedCategory,
                itemName: _searchItem,
              );
              final String reportTitle = "${_tabController.index == 0 ? 'Sales' : 'Purchase'}_Report";
              exportService.exportToExcel(txs, reportTitle);
              Navigator.pop(context);
            }),
            const SizedBox(height: 12),
            _exportTile(Icons.picture_as_pdf_rounded, 'Export as PDF', Colors.red, () {
              final txs = txProvider.getFilteredTransactions(
                type: _tabController.index == 0 ? 'sale' : 'purchase',
                range: _selectedRange,
                category: _selectedCategory,
                itemName: _searchItem,
              );
              final String reportTitle = "${_tabController.index == 0 ? 'Sales' : 'Purchase'}_Report";
              exportService.exportToPdf(txs, reportTitle);
              Navigator.pop(context);
            }),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _exportTile(IconData icon, String title, Color color, VoidCallback onTap) {
    return ListTile(
      onTap: onTap,
      leading: Icon(icon, color: color),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      tileColor: color.withOpacity(0.05),
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
    final filtered = txProvider.getFilteredTransactions(type: type, range: range, category: category, itemName: item);

    if (filtered.isEmpty) {
      return Center(child: Text('No records found for this period', style: TextStyle(color: profile.secondaryTextColor)));
    }

    double total = filtered.fold(0, (sum, tx) => sum + tx.amount);

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          color: profile.themeColor.withOpacity(0.1),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('${filtered.length} TRANSACTIONS', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12, color: profile.themeColor)),
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
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: ListTile(
                  onTap: () => _showDetails(context, tx, profile),
                  title: Text(tx.type == 'sale' ? (tx.parsedItems.isNotEmpty ? tx.parsedItems[0]['name'] ?? 'Sale' : 'Sale') : tx.category, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(DateFormat('dd MMM, hh:mm a').format(tx.date), style: const TextStyle(fontSize: 11)),
                  trailing: Text('${profile.currencySymbol}${tx.amount.toStringAsFixed(0)}', style: TextStyle(fontWeight: FontWeight.w900, color: type == 'sale' ? Colors.green : Colors.red)),
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
      builder: (context) => _TransactionDetailSheet(tx: tx, profile: profile),
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

    if (staffList.isEmpty) return Center(child: Text('No staff records found', style: TextStyle(color: profile.secondaryTextColor)));

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: staffList.length,
      itemBuilder: (context, index) {
        final staff = staffList[index];
        final payable = staffProvider.calculatePayable(staff);
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: ExpansionTile(
            leading: CircleAvatar(backgroundColor: profile.themeColor.withOpacity(0.1), child: const Icon(Icons.person_outline)),
            title: Text(staff.name, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text('Contact: ${staff.contact}'),
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    _row('Monthly Salary', '${profile.currencySymbol}${staff.monthlySalary}'),
                    _row('Advance Taken', '${profile.currencySymbol}${staff.advance}'),
                    _row('Leaves', '${staff.totalLeaves} days'),
                    const Divider(),
                    _row('Net Payable', '${profile.currencySymbol}${payable}', isBold: true),
                  ],
                ),
              )
            ],
          ),
        );
      },
    );
  }

  Widget _row(String l, String v, {bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(l), Text(v, style: TextStyle(fontWeight: isBold ? FontWeight.bold : FontWeight.normal))]),
    );
  }
}

class _TransactionDetailSheet extends StatelessWidget {
  final TransactionModel tx;
  final ProfileProvider profile;
  const _TransactionDetailSheet({required this.tx, required this.profile});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: profile.cardColor, borderRadius: const BorderRadius.vertical(top: Radius.circular(32))),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('TRANSACTION DETAILS', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: profile.textColor)),
          const SizedBox(height: 24),
          _detailRow('Date/Time', DateFormat('dd MMM yyyy, hh:mm a').format(tx.date)),
          _detailRow('Type', tx.type.toUpperCase()),
          _detailRow('Category', tx.category),
          _detailRow('Payment', tx.paymentMode),
          const Divider(height: 32),
          ...tx.parsedItems.map((i) => Column(
            children: [
              _detailRow(i['name'] ?? '', '${i['qty']} x ${i['price']}'),
              if (i['serving_method'] != null && i['serving_method'] != '')
                Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const SizedBox(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(color: profile.themeColor.withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
                        child: Text(i['serving_method']!, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: profile.themeColor)),
                      ),
                    ],
                  ),
                ),
            ],
          )),
          const Divider(height: 32),
          _detailRow('Total Amount', '${profile.currencySymbol}${tx.amount}', isBold: true),
          const SizedBox(height: 32),
          if (tx.type == 'sale')
            ElevatedButton.icon(
              onPressed: () async {
                final exportService = ExportService();
                final path = await exportService.saveBillAsPdf(tx, "Apna Hisaab");
                if (path != null && context.mounted) {
                   Navigator.pop(context);
                   ScaffoldMessenger.of(context).showSnackBar(
                     SnackBar(content: Text("Bill saved at: $path"), backgroundColor: Colors.green),
                   );
                }
              },
              icon: const Icon(Icons.print_rounded),
              label: const Text('REPRINT / SAVE BILL'),
              style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 54)),
            ),
        ],
      ),
    );
  }

  Widget _detailRow(String l, String v, {bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(l), Text(v, style: TextStyle(fontWeight: isBold ? FontWeight.bold : FontWeight.normal))]),
    );
  }
}
