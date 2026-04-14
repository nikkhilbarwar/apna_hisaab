import 'dart:convert';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/transaction_model.dart';
import '../../providers/transaction_provider.dart';
import '../../providers/category_provider.dart';
import '../../core/widgets/app_bottom_sheet.dart';
import '../../providers/profile_provider.dart';
import '../../providers/staff_provider.dart';
import '../../providers/item_provider.dart';
import '../../models/item_model.dart';
import '../../models/category_model.dart';
import '../../models/staff_model.dart';
import '../../services/export_service.dart';
import '../../utils/report_helper.dart';
import '../daily_entry/entry_screen.dart';
import '../items/item_management_screen.dart';

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
  List<String> _selectedCategories = ['All'];
  List<String> _selectedItems = ['All'];
  String _selectedPaymentMode = 'All';

  ImageProvider? _getStaffImage(StaffModel staff) {
    if (staff.imagePath != null && File(staff.imagePath!).existsSync()) {
      return FileImage(File(staff.imagePath!));
    }
    if (staff.imageUrl != null && staff.imageUrl!.isNotEmpty) {
      if (staff.imageUrl!.startsWith('base64:')) {
        try {
          return MemoryImage(base64Decode(staff.imageUrl!.replaceFirst('base64:', '')));
        } catch (e) {
          return null;
        }
      }
      return NetworkImage(staff.imageUrl!);
    }
    return null;
  }

  bool _shouldShowPlaceholder(StaffModel staff) {
    if (staff.imagePath != null && File(staff.imagePath!).existsSync()) return false;
    if (staff.imageUrl != null && staff.imageUrl!.isNotEmpty) return false;
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final profile = Provider.of<ProfileProvider>(context);
    final themeColor = profile.themeColor;
    final txProvider = Provider.of<TransactionProvider>(context);

    // Helper to calculate accurate filtered amount for a transaction
    double getFilteredAmount(TransactionModel tx) {
      if (_selectedCategories.contains('All') && _selectedItems.contains('All')) {
        return tx.amount;
      }

      final itemProvider = Provider.of<ItemProvider>(context, listen: false);
      double total = 0;
      if (tx.itemSnapshots.isEmpty) {
        String cat = tx.category;
        if (cat.isEmpty || cat.toLowerCase() == 'sale') cat = 'General';
        bool catMatch = _selectedCategories.contains('All') || _selectedCategories.contains(cat);
        bool itemMatch = _selectedItems.contains('All') || (tx.type == 'sale' ? _selectedItems.contains('Quick Sale') : _selectedItems.contains(tx.category));
        return (catMatch && itemMatch) ? tx.amount : 0;
      }

      for (var s in tx.itemSnapshots) {
        String name = s.name;
        String cat = s.category;

        if (cat == '' || cat.toLowerCase() == 'general' || cat.toLowerCase() == 'uncategorized' || cat.toLowerCase() == 'sale') {
          try {
            final master = itemProvider.items.firstWhere((i) => i.name == name);
            cat = master.category;
          } catch (_) {
            cat = 'General';
          }
        }

        bool catMatch = _selectedCategories.contains('All') || _selectedCategories.contains(cat);
        bool itemMatch = _selectedItems.contains('All') || _selectedItems.contains(name);

        if (catMatch && itemMatch) {
          total += s.lineTotal;
        }
      }
      return total;
    }

    final salesList = txProvider
        .getFilteredTransactions(type: 'sale', range: _selectedRange, category: null, status: 'completed')
        .where((tx) => _selectedPaymentMode == 'All' || tx.paymentMode == _selectedPaymentMode)
        .toList();

    final purchaseList = txProvider
        .getFilteredTransactions(type: 'purchase', range: _selectedRange, category: null, status: 'completed')
        .where((tx) => _selectedPaymentMode == 'All' || tx.paymentMode == _selectedPaymentMode)
        .toList();

    double totalRevenue = salesList.fold(0.0, (sum, tx) => sum + getFilteredAmount(tx));
    double paidExpenses = purchaseList.fold(0.0, (sum, tx) => sum + getFilteredAmount(tx));
    double netProfit = totalRevenue - paidExpenses;

    return Scaffold(
      backgroundColor: profile.scaffoldColor,
      appBar: AppBar(
        elevation: 0,
        title: Text(
          _currentIndex == 3 ? 'TRASH BIN' : (_currentIndex == 4 ? 'AUDIT REPORT' : 'BUSINESS REPORTS'),
          style: const TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 16,
            letterSpacing: 1,
            color: Colors.white,
          ),
        ),
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                _currentIndex == 3
                    ? Colors.red.shade400
                    : themeColor.withValues(alpha: 0.8),
                _currentIndex == 3
                    ? Colors.red.shade700
                    : themeColor,
              ],
            ),
          ),
        ),
        actions: [
          if (_currentIndex == 2)
            IconButton(
              tooltip: 'Filter Staff Range',
              icon: const Icon(Icons.filter_list_rounded, color: Colors.white, size: 24),
              onPressed: () async {
                final DateTimeRange? picked = await showDateRangePicker(
                  context: context,
                  initialDateRange: _selectedRange,
                  firstDate: DateTime(2023),
                  lastDate: DateTime.now().add(const Duration(days: 1)),
                  builder: (context, child) => Theme(
                    data: Theme.of(context).copyWith(
                      colorScheme: ColorScheme.light(
                        primary: themeColor,
                        onPrimary: Colors.white,
                        onSurface: profile.textColor,
                      ),
                    ),
                    child: child!,
                  ),
                );
                if (picked != null) {
                  setState(() => _selectedRange = picked);
                }
              },
            ),
          if (_currentIndex < 3 || _currentIndex == 4)
            IconButton(
              tooltip: 'Download Report',
              icon: const Icon(
                Icons.file_download_outlined,
                color: Colors.white,
                size: 26,
              ),
              onPressed: () => _showExportOptions(context),
            ),
        ],
      ),
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          if (_currentIndex < 2 || _currentIndex == 4)
            SliverToBoxAdapter(
              child: Column(
                children: [
                  _buildFilters(context, profile),
                  if (_currentIndex < 2)
                    Consumer<StaffProvider>(
                      builder: (context, staffProv, _) => _buildExecutiveSummary(
                        totalRevenue,
                        paidExpenses,
                        netProfit,
                        staffProv.totalNetPayable,
                        profile,
                      ),
                    ),
                ],
              ),
            ),
        ],
        body: IndexedStack(
          index: _currentIndex,
          children: [
            _ReportList(
              key: const PageStorageKey('sales_report'),
              type: 'sale',
              range: _selectedRange,
              categories: _selectedCategories,
              items: _selectedItems,
              paymentMode: _selectedPaymentMode,
            ),
            _ReportList(
              key: const PageStorageKey('purchase_report'),
              type: 'purchase',
              range: _selectedRange,
              categories: _selectedCategories,
              items: _selectedItems,
              paymentMode: _selectedPaymentMode,
            ),
            const _StaffReportList(key: PageStorageKey('staff_report')),
            const _TrashList(key: PageStorageKey('trash_report')),
            _CEOAuditView(key: const PageStorageKey('audit_report'), range: _selectedRange),
          ],
        ),
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 20,
              offset: const Offset(0, -5),
            ),
          ],
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (index) {
            setState(() {
              _currentIndex = index;
              _selectedCategories = ['All'];
              _selectedPaymentMode = 'All';
            });
          },
          selectedItemColor: _currentIndex == 3 ? Colors.red : themeColor,
          unselectedItemColor: profile.secondaryTextColor,
          selectedLabelStyle: const TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 12,
          ),
          unselectedLabelStyle: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 11,
          ),
          type: BottomNavigationBarType.fixed,
          backgroundColor: profile.cardColor,
          items: [
            const BottomNavigationBarItem(
              icon: Icon(Icons.auto_graph_rounded),
              label: 'SALES',
            ),
            const BottomNavigationBarItem(
              icon: Icon(Icons.receipt_long_rounded),
              label: 'EXPENSES',
            ),
            const BottomNavigationBarItem(
              icon: Icon(Icons.people_alt_rounded),
              label: 'STAFF',
            ),
            const BottomNavigationBarItem(
              icon: Icon(Icons.delete_outline_rounded),
              label: 'TRASH',
            ),
            const BottomNavigationBarItem(
              icon: Icon(Icons.analytics_rounded),
              label: 'AUDIT',
            ),
          ],
        ),
      ),

    );
  }

  Widget _buildExecutiveSummary(
    double revenue,
    double expense,
    double profit,
    double pending,
    ProfileProvider profile,
  ) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      decoration: BoxDecoration(
        color: profile.cardColor,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(30)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: profile.themeColor.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: profile.themeColor.withValues(alpha: 0.1)),
            ),
            child: Row(
              children: [
                _summaryItem('REVENUE', revenue, profile.themeColor, profile),
                _verticalDivider(profile),
                _summaryItem('EXPENSE', expense, Colors.redAccent, profile),
                _verticalDivider(profile),
                _summaryItem('PROFIT', profit, profit >= 0 ? profile.themeColor : Colors.redAccent, profile, isBold: true),
              ],
            ),
          ),
          if (revenue > 0) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: LinearProgressIndicator(
                value: (revenue > 0) ? (revenue - expense).clamp(0, revenue) / revenue : 0,
                backgroundColor: Colors.redAccent.withValues(alpha: 0.2),
                valueColor: AlwaysStoppedAnimation<Color>(profit >= 0 ? profile.themeColor : Colors.redAccent),
                minHeight: 4,
              ),
            ),
          ],
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.orange.withValues(alpha: 0.1)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.pending_actions_rounded, size: 14, color: Colors.orange),
                    SizedBox(width: 6),
                    Text('UPCOMING SALARY', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.orange)),
                  ],
                ),
                Text(
                  profile.showAmount ? '${profile.currencySymbol}${pending.toStringAsFixed(0)}' : '${profile.currencySymbol}****',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: Colors.orange),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryItem(
    String label,
    double value,
    Color color,
    ProfileProvider profile, {
    bool isBold = false,
  }) {
    return Expanded(
      child: Column(
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.bold,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            profile.showAmount
                ? '${profile.currencySymbol}${value.toStringAsFixed(0)}'
                : '${profile.currencySymbol}****',
            style: TextStyle(
              fontSize: 14,
              fontWeight: isBold ? FontWeight.w900 : FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _verticalDivider(ProfileProvider profile) {
    return Container(
      height: 30,
      width: 1,
      color: profile.isDarkMode ? Colors.white10 : Colors.grey.shade300,
      margin: const EdgeInsets.symmetric(horizontal: 12),
    );
  }

  Widget _buildFilters(BuildContext context, ProfileProvider profile) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      color: profile.cardColor,
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                flex: 2,
                child: InkWell(
                  onTap: () async {
                    final range = await ReportHelper.showAppDateRangePicker(
                      context,
                      _selectedRange,
                      profile.themeColor,
                      lastDate: DateTime.now(),
                    );
                    if (range != null) setState(() => _selectedRange = range);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(color: profile.scaffoldColor, borderRadius: BorderRadius.circular(12)),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.calendar_month_rounded, size: 16, color: profile.themeColor),
                        const SizedBox(width: 8),
                        Text('${DateFormat('dd MMM').format(_selectedRange.start)} - ${DateFormat('dd MMM').format(_selectedRange.end)}',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                        const Icon(Icons.arrow_drop_down, color: Colors.grey),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (_currentIndex < 2)
                Expanded(
                  flex: 1,
                  child: _buildFilterDropdown(
                    value: _selectedPaymentMode,
                    items: ['All', 'Cash', 'UPI', 'Card', 'Credit', 'Split'],
                    onChanged: (val) => setState(() => _selectedPaymentMode = val!),
                    profile: profile,
                  ),
                ),
            ],
          ),
          if (_currentIndex < 2) ...[
            const SizedBox(height: 8),
            Consumer2<CategoryProvider, ItemProvider>(
              builder: (context, catProv, itemProv, _) {
                // 1. Filter categories based on current tab
                final filteredCats = _currentIndex == 0
                  ? catProv.categories.where((c) => c.type == 'selling').toList()
                  : (_currentIndex == 1 ? catProv.categories.where((c) => c.type == 'purchase').toList() : catProv.categories);

                final categoryNames = ['All', ...filteredCats.map((c) => c.name)];

                // 2. Filter items based on selected categories
                List<String> itemNames = ['All'];
                if (_selectedCategories.contains('All')) {
                  // If All categories, show all items belonging to filtered categories
                  final catSet = filteredCats.map((c) => c.name).toSet();
                  itemNames.addAll(itemProv.items.where((it) => catSet.contains(it.category)).map((it) => it.name));
                } else {
                  // Show items only from selected categories
                  itemNames.addAll(itemProv.items.where((it) => _selectedCategories.contains(it.category)).map((it) => it.name));
                }

                return Row(
                  children: [
                    // Category Multi-Select (50%)
                    Expanded(
                      child: InkWell(
                        onTap: () => _showMultiSelectModal(context, categoryNames, _selectedCategories, "SELECT CATEGORIES", profile, (newList) {
                          setState(() {
                            _selectedCategories = newList;
                            _selectedItems = ['All']; // Reset items when category changes
                          });
                        }),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                          decoration: BoxDecoration(color: profile.scaffoldColor, borderRadius: BorderRadius.circular(12)),
                          child: Row(
                            children: [
                              Icon(Icons.category_rounded, size: 14, color: profile.themeColor),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  _selectedCategories.contains('All') ? "ALL CATS" : _selectedCategories.join(", ").toUpperCase(),
                                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: profile.textColor),
                                  maxLines: 1, overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const Icon(Icons.arrow_drop_down, size: 18, color: Colors.grey),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Item Multi-Select (50%)
                    Expanded(
                      child: InkWell(
                        onTap: () => _showMultiSelectModal(context, itemNames, _selectedItems, "SELECT ITEMS", profile, (newList) {
                          setState(() => _selectedItems = newList);
                        }),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                          decoration: BoxDecoration(color: profile.scaffoldColor, borderRadius: BorderRadius.circular(12)),
                          child: Row(
                            children: [
                              Icon(Icons.inventory_2_rounded, size: 14, color: profile.themeColor),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  _selectedItems.contains('All') ? "ALL ITEMS" : _selectedItems.join(", ").toUpperCase(),
                                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: profile.textColor),
                                  maxLines: 1, overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const Icon(Icons.arrow_drop_down, size: 18, color: Colors.grey),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  void _showMultiSelectModal(
    BuildContext context,
    List<String> options,
    List<String> selectedList,
    String title,
    ProfileProvider profile,
    Function(List<String>) onApplied,
  ) {
    List<String> tempSelected = List.from(selectedList);
    showModalBottomSheet(
      context: context,
      backgroundColor: profile.cardColor,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.7),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(title, style: TextStyle(fontWeight: FontWeight.w900, color: profile.textColor)),
                  ),
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: options.length,
                      itemBuilder: (context, i) {
                        final item = options[i];
                        final isSelected = tempSelected.contains(item);
                        return CheckboxListTile(
                          title: Text(item, style: TextStyle(color: profile.textColor, fontSize: 13, fontWeight: FontWeight.bold)),
                          value: isSelected,
                          activeColor: profile.themeColor,
                          onChanged: (val) {
                            setModalState(() {
                              if (item == 'All') {
                                tempSelected = ['All'];
                              } else {
                                tempSelected.remove('All');
                                if (val == true) {
                                  tempSelected.add(item);
                                } else {
                                  tempSelected.remove(item);
                                  if (tempSelected.isEmpty) tempSelected = ['All'];
                                }
                              }
                            });
                          },
                        );
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: ElevatedButton(
                      onPressed: () {
                        onApplied(tempSelected);
                        if (context.mounted) Navigator.pop(context);
                      },
                      style: ElevatedButton.styleFrom(backgroundColor: profile.themeColor, minimumSize: const Size(double.infinity, 50)),
                      child: const Text("APPLY", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildFilterDropdown({
    required String value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
    required ProfileProvider profile,
    bool isFullWidth = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: profile.scaffoldColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: items.contains(value) ? value : items.first,
          isExpanded: true,
          icon: const Icon(Icons.arrow_drop_down, color: Colors.grey),
          dropdownColor: profile.cardColor,
          items: items.map((String item) {
            return DropdownMenuItem<String>(
              value: item,
              child: Text(
                item,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: profile.textColor,
                ),
              ),
            );
          }).toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  void _showExportOptions(BuildContext context) {
    final profile = Provider.of<ProfileProvider>(context, listen: false);
    final txProvider = Provider.of<TransactionProvider>(context, listen: false);

    // Showing bill details
    AppBottomSheet.show(
      context: context,
      profile: profile,
      title: 'EXPORT REPORTS',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _exportTile(
            Icons.picture_as_pdf_rounded,
            'Save as PDF Report',
            _currentIndex == 0 ? 'Sales summary report' : (_currentIndex == 1 ? 'Expense summary report' : (_currentIndex == 4 ? 'CEO Audit GP Margin Report' : 'Professional business summary')),
            Colors.red,
            () async {
              final exportService = ExportService();
              final txProvider = Provider.of<TransactionProvider>(context, listen: false);
              final itemProvider = Provider.of<ItemProvider>(context, listen: false);

              if (_currentIndex == 4) {
                 // Get date range from CEO view if possible, or use current month
                 // For now, using a simple month range or the selected range if global
                 final readymadeItems = itemProvider.items.where((i) => i.itemType == 'readymade').toList();
                 final allSales = txProvider.getFilteredTransactions(type: 'sale', range: _selectedRange, status: 'completed');
                 final allPurchases = txProvider.getFilteredTransactions(type: 'purchase', range: _selectedRange, status: 'completed');

                 await exportService.exportAuditToPdf(
                   readymadeItems,
                   allSales,
                   allPurchases,
                   _selectedRange,
                   profile.currencySymbol,
                 );
                 Navigator.pop(context);
                 return;
              }

              final type = _currentIndex == 0 ? 'sale' : (_currentIndex == 1 ? 'purchase' : 'all');

                // Helper to check category match
                bool matches(String cat) => _selectedCategories.contains('All') || _selectedCategories.contains(cat);

                if (_currentIndex == 0 || _currentIndex == 1) {
                  final transactions = txProvider.getFilteredTransactions(
                    type: type,
                    range: _selectedRange,
                    category: null,
                    status: 'completed',
                  ).where((tx) => matches(tx.category) && (_selectedPaymentMode == 'All' || tx.paymentMode == _selectedPaymentMode)).toList();

                  await exportService.exportToPdf(
                    transactions,
                    '${type.toUpperCase()}_Report_${DateFormat('ddMMM').format(_selectedRange.start)}',
                  );
                } else {
                  final sales = txProvider.getFilteredTransactions(
                    type: 'sale',
                    range: _selectedRange,
                    category: null,
                    status: 'completed',
                  ).where((tx) => matches(tx.category) && (_selectedPaymentMode == 'All' || tx.paymentMode == _selectedPaymentMode)).toList();

                  final expenses = txProvider.getFilteredTransactions(
                    type: 'purchase',
                    range: _selectedRange,
                    category: null,
                    status: 'completed',
                  ).where((tx) => matches(tx.category) && (_selectedPaymentMode == 'All' || tx.paymentMode == _selectedPaymentMode)).toList();

                await exportService.generateFullReport(
                  profile.businessName,
                  sales,
                  expenses,
                  _selectedRange,
                );
              }
              Navigator.pop(context);
            },
            profile,
          ),
          const Divider(height: 1),
          _exportTile(
            Icons.table_view_rounded,
            'Export to Excel',
            _currentIndex == 0 ? 'Export only Sales' : (_currentIndex == 1 ? 'Export only Expenses' : (_currentIndex == 4 ? 'Export Audit to Spreadsheet' : 'Spreadsheet for bookkeeping')),
            Colors.green,
            () async {
              final exportService = ExportService();
              final itemProvider = Provider.of<ItemProvider>(context, listen: false);

              if (_currentIndex == 4) {
                 final readymadeItems = itemProvider.items.where((i) => i.itemType == 'readymade').toList();
                 final allSales = txProvider.getFilteredTransactions(type: 'sale', range: _selectedRange, status: 'completed');
                 final allPurchases = txProvider.getFilteredTransactions(type: 'purchase', range: _selectedRange, status: 'completed');

                 await exportService.exportAuditToExcel(
                   readymadeItems,
                   allSales,
                   allPurchases,
                   _selectedRange,
                 );
                 Navigator.pop(context);
                 return;
              }

              final type = _currentIndex == 0 ? 'sale' : (_currentIndex == 1 ? 'purchase' : 'all');
              final allTransactions = txProvider.getFilteredTransactions(
                type: type,
                range: _selectedRange,
                category: null,
                status: 'completed',
              ).where((tx) => (_selectedCategories.contains('All') || _selectedCategories.contains(tx.category)) && (_selectedPaymentMode == 'All' || tx.paymentMode == _selectedPaymentMode)).toList();

              await exportService.exportToExcel(
                allTransactions,
                '${type.toUpperCase()}_Report_${DateFormat('ddMMM').format(_selectedRange.start)}',
              );
              Navigator.pop(context);
            },
            profile,
          ),
        ],
      ),
    );
  }

  Widget _exportTile(
    IconData icon,
    String title,
    String sub,
    Color color,
    VoidCallback onTap,
    ProfileProvider profile,
  ) {
    return ListTile(
      onTap: onTap,
      leading: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: color),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
      subtitle: Text(sub, style: TextStyle(fontSize: 12, color: profile.secondaryTextColor)),
      trailing: const Icon(Icons.chevron_right, size: 20),
    );
  }
}

class _StickySummaryHeader extends SliverPersistentHeaderDelegate {
  final Widget child;

  _StickySummaryHeader({required this.child});

  @override
  double get minExtent => 140.0;

  @override
  double get maxExtent => 140.0;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return child;
  }

  @override
  bool shouldRebuild(covariant _StickySummaryHeader oldDelegate) => true;
}

class _ReportList extends StatelessWidget {
  final String type;
  final DateTimeRange range;
  final List<String> categories;
  final List<String> items;
  final String paymentMode;

  const _ReportList({
    super.key,
    required this.type,
    required this.range,
    required this.categories,
    required this.items,
    required this.paymentMode,
  });

  ImageProvider? _getStaffImage(StaffModel staff) {
    if (staff.imagePath != null && File(staff.imagePath!).existsSync()) {
      return FileImage(File(staff.imagePath!));
    }
    if (staff.imageUrl != null && staff.imageUrl!.isNotEmpty) {
      if (staff.imageUrl!.startsWith('base64:')) {
        try {
          return MemoryImage(base64Decode(staff.imageUrl!.replaceFirst('base64:', '')));
        } catch (e) {
          return null;
        }
      }
      return NetworkImage(staff.imageUrl!);
    }
    return null;
  }

  bool _shouldShowPlaceholder(StaffModel staff) {
    if (staff.imagePath != null && File(staff.imagePath!).existsSync()) return false;
    if (staff.imageUrl != null && staff.imageUrl!.isNotEmpty) return false;
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final txProvider = Provider.of<TransactionProvider>(context);
    final itemProvider = Provider.of<ItemProvider>(context);
    final profile = Provider.of<ProfileProvider>(context);

    List<TransactionModel> rawList = txProvider.getFilteredTransactions(
      type: type,
      range: range,
      category: null,
      status: 'completed',
    );

    if (paymentMode != 'All') {
      rawList = rawList.where((tx) => tx.paymentMode == paymentMode).toList();
    }

    // Precision Filtering for Reports
    final List<Map<String, dynamic>> reportData = [];
    double totalAmount = 0;
    Map<String, double> paymentSplit = {'Cash': 0, 'UPI': 0, 'Credit': 0};

    for (var tx in rawList) {
      double displayAmount = 0;
      if (categories.contains('All') && items.contains('All')) {
        displayAmount = tx.amount;
      } else {
        if (tx.itemSnapshots.isEmpty) {
          String cat = tx.category;
          if (cat.isEmpty || cat.toLowerCase() == 'sale') cat = 'General';
          bool cM = categories.contains('All') || categories.contains(cat);
          bool iM = items.contains('All') || (tx.type == 'sale' ? items.contains('Quick Sale') : items.contains(tx.category));
          if (cM && iM) displayAmount = tx.amount;
        } else {
          for (var s in tx.itemSnapshots) {
            String name = s.name;
            String cat = s.category;
            if (cat == '' || cat.toLowerCase() == 'general' || cat.toLowerCase() == 'uncategorized' || cat.toLowerCase() == 'sale') {
              try {
                final master = itemProvider.items.firstWhere((i) => i.name == name);
                cat = master.category;
              } catch (_) { cat = 'General'; }
            }
            bool cM = categories.contains('All') || categories.contains(cat);
            bool iM = items.contains('All') || items.contains(name);
            if (cM && iM) displayAmount += s.lineTotal;
          }
        }
      }

      if (displayAmount > 0) {
        totalAmount += displayAmount;

        if (tx.paymentMode == 'Credit') {
          // CEO Logic: For Credit, we only show the actual pending/due amount in the header stat
          double pending = tx.amount - tx.paidAmount;
          paymentSplit['Credit'] = (paymentSplit['Credit'] ?? 0) + pending;
        } else {
          paymentSplit[tx.paymentMode] = (paymentSplit[tx.paymentMode] ?? 0) + displayAmount;
        }

        reportData.add({
          'tx': tx,
          'amount': displayAmount,
        });
      }
    }

    if (reportData.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.analytics_outlined, size: 64, color: profile.secondaryTextColor.withValues(alpha: 0.1)),
            const SizedBox(height: 16),
            Text('No records found', style: TextStyle(color: profile.secondaryTextColor, fontWeight: FontWeight.bold)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
      itemCount: reportData.length + 2,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              color: profile.themeColor.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: profile.themeColor.withValues(alpha: 0.1)),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('${reportData.length} TRANSACTIONS', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 11, color: profile.themeColor, letterSpacing: 0.5)),
                    Text('TOTAL: ${profile.currencySymbol}${profile.showAmount ? totalAmount.toStringAsFixed(0) : "****"}', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: profile.themeColor)),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _miniStat('Cash', paymentSplit['Cash']!, profile.themeColor, profile),
                    const SizedBox(width: 8),
                    _miniStat('UPI', paymentSplit['UPI']!, profile.themeColor.withValues(alpha: 0.7), profile),
                    const SizedBox(width: 8),
                    _miniStat(
                      'Credit',
                      paymentSplit['Credit']!,
                      Colors.orangeAccent,
                      profile,
                      onTap: paymentSplit['Credit']! > 0 ? () {
                        // Extract only transactions that have a balance due
                        final pendingTxs = reportData.where((data) {
                          final tx = data['tx'] as TransactionModel;
                          return tx.paymentMode == 'Credit' && (tx.amount - tx.paidAmount) > 0;
                        }).map((data) => data['tx'] as TransactionModel).toList();

                        _showPendingDetails(context, pendingTxs, profile);
                      } : null,
                    ),
                  ],
                ),
              ],
            ),
          );
        }
        if (index == 1) {
          // Pass the already filtered rawList to AnalysisSummary
          return _buildAnalysisSummary(
            context,
            rawList,
            profile,
            txProvider,
            itemProvider,
            type,
          );
        }

        final data = reportData[index - 2];
        final tx = data['tx'] as TransactionModel;
        final displayAmount = data['amount'] as double;

        // Date Header Logic: Detect when day changes
        bool showDateHeader = false;
        if (index == 2) {
          showDateHeader = true;
        } else {
          final prevData = reportData[index - 3];
          final prevTx = prevData['tx'] as TransactionModel;
          if (DateFormat('ddMMyyyy').format(tx.date) !=
              DateFormat('ddMMyyyy').format(prevTx.date)) {
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
                    Container(
                      width: 4,
                      height: 14,
                      decoration: BoxDecoration(
                        color: profile.themeColor,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _getDateLabel(tx.date),
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 12,
                        color: profile.textColor,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: profile.cardColor,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: profile.isDarkMode
                      ? Colors.white10
                      : Colors.grey.shade100,
                ),
              ),
              child: ListTile(
                onTap: () => _showDetails(context, tx, profile),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color:
                        (tx.type == 'sale' || tx.type == 'income'
                                ? Colors.green
                                : Colors.red)
                            .withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    tx.type == 'sale' || tx.type == 'income'
                        ? Icons.south_west_rounded
                        : Icons.north_east_rounded,
                    color: tx.type == 'sale' || tx.type == 'income'
                        ? Colors.green
                        : Colors.red,
                    size: 18,
                  ),
                ),
                title: Row(
                  children: [
                    if (tx.paymentMode == 'Credit' && tx.customerContact.isNotEmpty) ...[
                      const Icon(Icons.person_pin_rounded, size: 16, color: Colors.orange),
                      const SizedBox(width: 4),
                      Text(tx.customerContact, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: profile.themeColor)),
                      Text(' • ', style: TextStyle(color: profile.secondaryTextColor.withValues(alpha: 0.5))),
                    ],
                    Expanded(
                      child: Text(
                        _getMixedCategoryLabel(tx),
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: profile.textColor,
                          fontSize: 13,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (tx.paymentMode == 'Credit')
                       Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        margin: const EdgeInsets.only(left: 8),
                        decoration: BoxDecoration(
                          color: (tx.amount - tx.paidAmount) > 0 ? Colors.red.withValues(alpha: 0.1) : Colors.green.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          (tx.amount - tx.paidAmount) > 0 ? 'DUE' : 'PAID',
                          style: TextStyle(color: (tx.amount - tx.paidAmount) > 0 ? Colors.red : Colors.green, fontSize: 8, fontWeight: FontWeight.bold),
                        ),
                      ),
                  ],
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${DateFormat('hh:mm a').format(tx.date)} • ${tx.paymentMode}${tx.customerContact.isNotEmpty ? ' • ${tx.customerContact}' : ''}',
                      style: TextStyle(
                        fontSize: 10,
                        color: profile.secondaryTextColor,
                      ),
                    ),
                    if (tx.paymentMode == 'Credit' && (tx.amount - tx.paidAmount) > 0)
                      Text(
                        'Pending: ${profile.currencySymbol}${(tx.amount - tx.paidAmount).toStringAsFixed(0)}',
                        style: const TextStyle(fontSize: 9, color: Colors.red, fontWeight: FontWeight.bold),
                      ),
                  ],
                ),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${profile.currencySymbol}${profile.showAmount ? displayAmount.toStringAsFixed(0) : "****"}',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        color: tx.type == 'sale' || tx.type == 'income'
                            ? Colors.green.shade700
                            : Colors.red.shade700,
                        fontSize: 14,
                      ),
                    ),
                    if (tx.paymentMode == 'Credit')
                      Text(
                        'Rec: ${profile.currencySymbol}${tx.paidAmount.toStringAsFixed(0)}',
                        style: TextStyle(fontSize: 9, color: profile.secondaryTextColor, fontWeight: FontWeight.bold),
                      ),
                  ],
                ),
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

  String _getMixedCategoryLabel(TransactionModel tx) {
    final items = tx.itemSnapshots;
    if (items.isEmpty) {
      return (tx.category.isEmpty || tx.category == 'All') ? 'General' : tx.category;
    }

    final categories = items.map((e) => e.category).where((c) => c != 'All' && c.isNotEmpty).toSet().toList();
    if (categories.isEmpty) return 'General';
    if (categories.length > 1) {
      return 'Mix';
    }
    return categories.first;
  }


  Widget _buildAnalysisSummary(
    BuildContext context,
    List<TransactionModel> txs,
    ProfileProvider profile,
    TransactionProvider provider,
    ItemProvider itemProvider,
    String reportType,
  ) {
    final split = provider.getPaymentSplit(txs);

    Map<String, double> itemRevenue = {};
    Map<String, double> catRevenue = {};
    Map<String, List<Map<String, dynamic>>> catAuditHistory = {};
    Map<String, List<Map<String, dynamic>>> itemAuditHistory = {};

    for (var tx in txs) {
      final snapshots = tx.itemSnapshots;

      if (snapshots.isEmpty) {
        String cat = tx.category;
        if (cat.isEmpty || cat.toLowerCase() == 'sale') cat = 'General';

        // FILTER CHECK: Skip if category/item not in selected filters
        bool catMatch = categories.contains('All') || categories.contains(cat);
        bool itemMatch = items.contains('All') || (tx.type == 'sale' ? items.contains('Quick Sale') : items.contains(tx.category));
        if (!catMatch || !itemMatch) continue;

        catRevenue[cat] = (catRevenue[cat] ?? 0) + tx.amount;

        final auditData = {
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
        };

        catAuditHistory[cat] ??= [];
        catAuditHistory[cat]!.add(auditData);

        // Add to item audit as well for "Quick Sale" or generic entries
        String itemName = tx.type == 'sale' ? 'Quick Sale' : tx.category;
        itemRevenue[itemName] = (itemRevenue[itemName] ?? 0) + tx.amount;
        itemAuditHistory[itemName] ??= [];
        itemAuditHistory[itemName]!.add(auditData);
        continue;
      }

      for (var s in snapshots) {
        String name = s.name;
        String cat = s.category;

        // Resolve "General" Category using Item Menu Lookup
        if (cat == '' ||
            cat.toLowerCase() == 'general' ||
            cat.toLowerCase() == 'uncategorized' ||
            cat.toLowerCase() == 'sale') {
          try {
            final master = itemProvider.items.firstWhere((i) => i.name == name);
            cat = master.category;
          } catch (_) {
            cat = 'General';
          }
        }

        // FILTER CHECK: Precision filtering for snapshots
        bool catMatch = categories.contains('All') || categories.contains(cat);
        bool itemMatch = items.contains('All') || items.contains(name);
        if (!catMatch || !itemMatch) continue;

        double val = s.lineTotal;
        itemRevenue[name] = (itemRevenue[name] ?? 0) + val;
        catRevenue[cat] = (catRevenue[cat] ?? 0) + val;

        final auditData = {
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
        };

        catAuditHistory[cat] ??= [];
        catAuditHistory[cat]!.add(auditData);

        itemAuditHistory[name] ??= [];
        itemAuditHistory[name]!.add(auditData);
      }
    }

    var sortedItems = itemRevenue.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    var sortedCats = catRevenue.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final bool isExpense = reportType == 'expense' || reportType == 'purchase';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildLowStockAlert(context, itemProvider, profile),
        const SizedBox(height: 8),
        _sectionHeader(isExpense ? 'CATEGORY-WISE EXPENSES' : 'CATEGORY-WISE SALES', profile),
        const SizedBox(height: 12),
        // PROFESSIONAL AUDIT CLICK
        _summaryBox(
          sortedCats,
          profile,
          isExpense,
          (catName) => _showCategoryDetails(
            context,
            catName,
            catRevenue[catName]!,
            catAuditHistory[catName]!,
            profile,
            isExpense,
          ),
        ),
        const SizedBox(height: 24),
        _sectionHeader(isExpense ? 'ITEM-WISE EXPENSES' : 'ITEM-WISE SALES', profile),
        const SizedBox(height: 12),
        _summaryBox(
          sortedItems.take(15).toList(),
          profile,
          isExpense,
          (itemName) => _showItemDetails(
            context,
            itemName,
            itemRevenue[itemName]!,
            itemAuditHistory[itemName]!,
            profile,
            isExpense,
          ),
        ),
        const SizedBox(height: 24),
        _sectionHeader('TRANSACTION LOG', profile),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _buildLowStockAlert(BuildContext context, ItemProvider itemProvider, ProfileProvider profile) {
    // Logic: Use minStock from ItemModel for the alert
    final lowStockItems = itemProvider.items.where((item) =>
      item.lowStockAlert == 1 &&
      item.currentStock <= item.minStock &&
      item.currentStock >= 0
    ).toList();

    if (lowStockItems.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.red.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 18),
              const SizedBox(width: 8),
              Text(
                "LOW STOCK ALERT (${lowStockItems.length})",
                style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w900, fontSize: 11, letterSpacing: 0.5),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...lowStockItems.take(3).map((item) => InkWell(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (c) => ItemManagementScreen(category: item.category, editItem: item),
                ),
              );
            },
            child: Padding(
              padding: const EdgeInsets.only(bottom: 6, top: 2),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 4, height: 4,
                        decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 8),
                      Text(item.name, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: profile.textColor)),
                    ],
                  ),
                  Row(
                    children: [
                      Text("${item.currentStock} ${item.unit} left", style: const TextStyle(fontSize: 11, color: Colors.red, fontWeight: FontWeight.bold)),
                      const SizedBox(width: 4),
                      const Icon(Icons.arrow_forward_ios_rounded, size: 10, color: Colors.red),
                    ],
                  ),
                ],
              ),
            ),
          )),
          if (lowStockItems.length > 3)
            Text("...and ${lowStockItems.length - 3} more", style: const TextStyle(fontSize: 10, color: Colors.grey)),
        ],
      ),
    );
  }

  void _showPendingDetails(
    BuildContext context,
    List<TransactionModel> txs,
    ProfileProvider profile,
  ) {
    AppBottomSheet.show(
      context: context,
      profile: profile,
      title: 'PENDING CREDITS',
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${txs.length} UNPAID BILLS',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 24,
                color: profile.textColor,
              ),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: ListView.builder(
                itemCount: txs.length,
                itemBuilder: (context, i) {
                  final tx = txs[i];
                  final double pending = tx.amount - tx.paidAmount;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: profile.cardColor,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: profile.isDarkMode
                            ? Colors.white10
                            : Colors.grey.shade100,
                      ),
                    ),
                    child: ListTile(
                      onTap: () => _showDetails(context, tx, profile),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 4,
                      ),
                    leading: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.south_west_rounded,
                        color: Colors.orange,
                        size: 18,
                      ),
                    ),
                    title: Row(
                      children: [
                        if (tx.type == 'purchase' && tx.description.contains(' | Vendor: ')) ...[
                          const Icon(Icons.store_rounded, size: 16, color: Colors.orange),
                          const SizedBox(width: 4),
                          Text(
                            tx.description.split(' | Vendor: ').last.split(' | ').first,
                            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: profile.themeColor)
                          ),
                          Text(' • ', style: TextStyle(color: profile.secondaryTextColor.withValues(alpha: 0.5))),
                        ] else if (tx.customerContact.isNotEmpty) ...[
                          const Icon(Icons.person_pin_rounded, size: 16, color: Colors.orange),
                          const SizedBox(width: 4),
                          Text(tx.customerContact, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: profile.themeColor)),
                          Text(' • ', style: TextStyle(color: profile.secondaryTextColor.withValues(alpha: 0.5))),
                        ],
                        Expanded(
                          child: Text(
                            _getMixedCategoryLabel(tx),
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: profile.textColor,
                              fontSize: 13,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    subtitle: Text(
                      'Pending: ${profile.currencySymbol}${pending.toStringAsFixed(0)}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.red,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.5,
                      ),
                    ),
                    trailing: Text(
                      '${profile.currencySymbol}${tx.amount.toStringAsFixed(0)}',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 14,
                        color: profile.textColor,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    ));
  }

  void _showItemDetails(
    BuildContext context,
    String itemName,
    double total,
    List<Map<String, dynamic>> history,
    ProfileProvider profile,
    bool isExpense,
  ) {
    _showAuditSheet(context, itemName, total, history, profile, isItem: true, isExpense: isExpense);
  }

  void _showCategoryDetails(
    BuildContext context,
    String catName,
    double total,
    List<Map<String, dynamic>> history,
    ProfileProvider profile,
    bool isExpense,
  ) {
    _showAuditSheet(context, catName, total, history, profile, isItem: false, isExpense: isExpense);
  }

  void _showAuditSheet(
    BuildContext context,
    String title,
    double total,
    List<Map<String, dynamic>> history,
    ProfileProvider profile, {
    required bool isItem,
    required bool isExpense,
  }) {
    double totalQty = 0;
    double halfQty = 0;
    double fullQty = 0;

    for (var sale in history) {
      double q = (sale['qty'] as num? ?? 1.0).toDouble();

      if (isExpense) {
        totalQty += q;
      } else {
        String varType = sale['variant'].toString().toLowerCase();
        if (varType.contains('half')) {
          halfQty += q < 1.0 ? 1.0 : q;
        } else {
          fullQty += q < 1.0 ? 1.0 : q;
        }
      }
    }
    if (!isExpense) totalQty = halfQty + fullQty;

    // Showing bill details
    AppBottomSheet.show(
      context: context,
      profile: profile,
      title: isExpense ? 'EXPENSE AUDIT' : (isItem ? 'ITEM AUDIT' : 'CATEGORY AUDIT'),
      footer: ElevatedButton.icon(
        onPressed: () async {
          final exportService = ExportService();
          await exportService.exportAuditReport(
            businessName: profile.businessName,
            title: title,
            totalRevenue: total,
            history: history,
            isItem: isItem,
            range: range,
          );
          if (context.mounted) Navigator.pop(context);
        },
        icon: const Icon(Icons.download_rounded),
        label: const Text('EXPORT AUDIT'),
        style: ElevatedButton.styleFrom(
          backgroundColor: profile.themeColor,
          foregroundColor: Colors.white,
          minimumSize: const Size(double.infinity, 56),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.8,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
              Text(
                title.toUpperCase(),
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 28,
                  color: profile.textColor,
                ),
              ),
              Text(
                isExpense ? 'Total Outflow: ${profile.currencySymbol}${total.toStringAsFixed(0)}' : 'Total Revenue: ${profile.currencySymbol}${total.toStringAsFixed(0)}',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: isExpense ? Colors.red : profile.themeColor,
                  fontSize: 16,
                ),
              ),
              const Divider(height: 40),
              // ALWAYS SHOW STATS IF HISTORY EXISTS
              Row(
                children: [
                  if (isExpense)
                     _insightStat(
                      'Total Quantity',
                      totalQty.toStringAsFixed(totalQty % 1 == 0 ? 0 : 2),
                      Colors.orange
                    )
                  else ...[
                    _insightStat(
                    halfQty > 0 ? 'Full Portions' : 'Total Portions',
                    fullQty.toStringAsFixed(fullQty % 1 == 0 ? 0 : 1),
                    profile.themeColor
                  ),
                  if (halfQty > 0) ...[
                    const SizedBox(width: 12),
                    _insightStat('Half Portions', halfQty.toStringAsFixed(halfQty % 1 == 0 ? 0 : 1), Colors.orange),
                  ],
                ],
              ],
            ),
            const SizedBox(height: 32),
            Text(
              isExpense ? 'PURCHASE & PAYMENT LOG' : 'DETAILED SALES HISTORY',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 11,
                color: profile.secondaryTextColor,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView.builder(
                itemCount: history.length,
                itemBuilder: (context, i) {
                  final sale = history[i];
                  String qLabel = sale['qty'] == 0.5
                      ? "Half"
                      : (sale['qty'] == 1.0
                          ? "Full"
                          : sale['qty'].toStringAsFixed(1));
                  bool hasExtras =
                      sale['extraQty'] > 0 || sale['extraPrice'] > 0;

                  return Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: profile.scaffoldColor.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: profile.isDarkMode
                            ? Colors.white10
                            : Colors.grey.shade100,
                      ),
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
                                Text(
                                  sale['name'],
                                  style: TextStyle(
                                    fontWeight: FontWeight.w900,
                                    color: profile.textColor,
                                    fontSize: 14,
                                  ),
                                ),
                                Text(
                                  '${sale['date']} at ${sale['time']}',
                                  style: TextStyle(
                                    color: profile.secondaryTextColor,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            Text(
                              '${profile.currencySymbol}${sale['total'].toStringAsFixed(0)}',
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                color: profile.themeColor,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: Divider(height: 1, thickness: 0.5),
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '$qLabel x ${profile.currencySymbol}${sale['price'].toStringAsFixed(0)} • ${sale['mode']}',
                              style: TextStyle(
                                fontSize: 11,
                                color: profile.secondaryTextColor,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: profile.themeColor.withValues(
                                  alpha: 0.1,
                                ),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                sale['serving'].toString().toUpperCase(),
                                style: TextStyle(
                                  fontSize: 8,
                                  fontWeight: FontWeight.w900,
                                  color: profile.themeColor,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (hasExtras)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.add_circle_outline_rounded,
                                  size: 12,
                                  color: profile.themeColor,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'Extra: ${sale['extraQty'].toInt()} x ${profile.currencySymbol}${sale['extraPrice'].toInt()}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: profile.textColor,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
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
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.1)),
        ),
        child: Column(
          children: [
            Text(
              val,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: color,
              ),
            ),
            Text(
              label,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(String title, ProfileProvider profile) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w900,
        color: profile.secondaryTextColor,
        letterSpacing: 1,
      ),
    );
  }

  Widget _summaryBox(
    List<MapEntry<String, double>> entries,
    ProfileProvider profile,
    bool isExpense,
    Function(String)? onTap,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: profile.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: profile.isDarkMode ? Colors.white10 : Colors.grey.shade100,
        ),
      ),
      child: Column(
        children: entries
            .map(
              (e) => InkWell(
                onTap: onTap != null ? () => onTap(e.key) : null,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              e.key,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: profile.textColor,
                              ),
                            ),
                            if (entries.indexOf(e) == 0 && e.value > 0)
                              Text(
                                isExpense ? "HIGHEST EXPENSE" : "TOP PERFORMER",
                                style: TextStyle(
                                  fontSize: 8,
                                  fontWeight: FontWeight.w900,
                                  color: isExpense ? Colors.red.shade700 : Colors.green.shade700,
                                  letterSpacing: 0.5,
                                ),
                              ),
                          ],
                        ),
                      ),
                      Text(
                        '${profile.currencySymbol}${e.value.toStringAsFixed(0)}',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 13,
                          color: profile.themeColor,
                        ),
                      ),
                      if (onTap != null)
                        const Icon(
                          Icons.chevron_right,
                          size: 16,
                          color: Colors.grey,
                        ),
                    ],
                  ),
                ),
              ),
            )
            .toList(),
      ),
    );
  }

  Widget _miniStat(
    String label,
    double val,
    Color color,
    ProfileProvider profile, {
    VoidCallback? onTap,
  }) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.1)),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 8,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                  if (onTap != null) ...[
                    const SizedBox(width: 4),
                    Icon(Icons.touch_app_outlined, size: 8, color: color),
                  ],
                ],
              ),
              const SizedBox(height: 4),
              Text(
                profile.showAmount
                    ? '${profile.currencySymbol}${val.toStringAsFixed(0)}'
                    : '${profile.currencySymbol}****',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  color: profile.textColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showDetails(
    BuildContext context,
    TransactionModel tx,
    ProfileProvider profile,
  ) {
    final snapshots = tx.itemSnapshots;
    double calculatedSubtotal = 0;
    for (var s in snapshots) {
      calculatedSubtotal += s.lineTotal;
    }

    double discount = tx.discountValue;
    double taxAmount = tx.taxValue;

    // Showing bill details
    AppBottomSheet.show(
      context: context,
      profile: profile,
      title: 'BILL DETAILS',
      footer: (tx.type == 'sale' || tx.type == 'income')
          ? Row(
              children: [
                if (tx.paymentMode == 'Credit') ...[
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (c) => EntryScreen(transaction: tx),
                          ),
                        );
                      },
                      icon: const Icon(Icons.edit_note_rounded),
                      label: const Text('EDIT CREDIT'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.orange,
                        side: const BorderSide(color: Colors.orange),
                        minimumSize: const Size(0, 56),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      final exportService = ExportService();
                      await exportService.saveBillAsPdf(
                        tx,
                        profile.businessName,
                      );
                      if (context.mounted) Navigator.pop(context);
                    },
                    icon: const Icon(Icons.print_rounded),
                    label: const Text('PRINT BILL'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: profile.themeColor,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(0, 56),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),
              ],
            )
          : null,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color:
                          (tx.status == 'pending' ? Colors.orange : Colors.green)
                              .withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      tx.status.toUpperCase(),
                      style: TextStyle(
                        color: tx.status == 'pending'
                            ? Colors.orange
                            : Colors.green,
                        fontWeight: FontWeight.bold,
                        fontSize: 10,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _detailRow(
                'Date/Time',
                DateFormat('dd MMM yyyy, hh:mm a').format(tx.date),
                profile,
              ),
              _detailRow('Payment Mode', tx.paymentMode, profile),
              const Divider(height: 40),
              Text(
                'ITEMS BREAKDOWN',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                  color: profile.secondaryTextColor,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 16),

              Column(
                children: snapshots.map((s) {
                  String qLabel = s.qty == 0.5
                      ? "Half"
                      : (s.qty == 1.0 ? "Full" : s.qty.toStringAsFixed(1));
                  bool hasExtras = s.extraQty > 0 || s.extraPrice > 0;

                  return Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: profile.scaffoldColor.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: profile.isDarkMode
                            ? Colors.white10
                            : Colors.grey.shade100,
                      ),
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
                                  Text(
                                    s.name,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w900,
                                      color: profile.textColor,
                                      fontSize: 15,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '$qLabel x ${profile.currencySymbol}${s.price.toStringAsFixed(0)} • ${s.variant}',
                                    style: TextStyle(
                                      color: profile.secondaryTextColor,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  '${profile.currencySymbol}${s.lineTotal.toStringAsFixed(0)}',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w900,
                                    color: profile.themeColor,
                                    fontSize: 16,
                                  ),
                                ),
                                Text(
                                  'Total',
                                  style: TextStyle(
                                    fontSize: 9,
                                    color: profile.secondaryTextColor,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        if (hasExtras) ...[
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 8),
                            child: Divider(height: 1, thickness: 0.5),
                          ),
                          Row(
                            children: [
                              Icon(
                                Icons.add_circle_outline_rounded,
                                size: 14,
                                color: Colors.blue.shade600,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Extra Qty: ${s.extraQty.toInt()} • Extra Rs: ${profile.currencySymbol}${s.extraPrice.toInt()}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: profile.textColor,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  );
                }).toList(),
              ),

              const Divider(height: 40),
              _rowBreakdown(
                'Subtotal',
                '${profile.currencySymbol}${calculatedSubtotal.toStringAsFixed(0)}',
                profile,
              ),
              if (discount > 0)
                _rowBreakdown(
                  'Discount',
                  '- ${profile.currencySymbol}${discount.toStringAsFixed(0)}',
                  profile,
                  color: Colors.green,
                ),
              if (taxAmount > 0)
                _rowBreakdown(
                  'Tax',
                  '${profile.currencySymbol}${taxAmount.toStringAsFixed(0)}',
                  profile,
                ),

              if (tx.paymentMode == 'Credit') ...[
                const SizedBox(height: 8),
                _rowBreakdown('Total Bill', '${profile.currencySymbol}${tx.amount.toStringAsFixed(0)}', profile, isBold: true),
                _rowBreakdown('Paid (Deposit)', '${profile.currencySymbol}${tx.paidAmount.toStringAsFixed(0)}', profile, color: Colors.green, isBold: true),
                const Divider(height: 20, thickness: 0.5),
                _rowBreakdown('Remaining Due', '${profile.currencySymbol}${(tx.amount - tx.paidAmount).toStringAsFixed(0)}', profile, color: Colors.red, isBold: true),
              ],

              if (tx.customerContact.isNotEmpty) ...[
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _rowBreakdown('Customer', tx.customerContact, profile, color: profile.themeColor),
                    Row(
                      children: [
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.call, size: 18, color: Colors.green),
                          onPressed: () => _launchURL('tel:${tx.customerContact}'),
                        ),
                        if (tx.paymentMode == 'Credit' && (tx.amount - tx.paidAmount) > 0)
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.message_rounded, size: 18, color: Color(0xFF25D366)),
                            onPressed: () {
                              double due = tx.amount - tx.paidAmount;
                              String msg = "Reminder from ${profile.businessName}: Pending balance of ${profile.currencySymbol}${due.toStringAsFixed(0)}. Please clear it. Thank you!";
                              _launchURL('https://wa.me/${tx.customerContact.replaceAll(RegExp(r'[^0-9]'), '')}?text=${Uri.encodeComponent(msg)}');
                            },
                          ),
                      ],
                    ),
                  ],
                ),
              ],

              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: profile.themeColor.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: profile.themeColor.withValues(alpha: 0.1),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      tx.paymentMode == 'Credit' ? 'DUE BALANCE' : 'GRAND TOTAL',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 14,
                        color: tx.paymentMode == 'Credit' ? Colors.red : profile.textColor,
                      ),
                    ),
                    Text(
                      profile.showAmount
                          ? '${profile.currencySymbol}${tx.paymentMode == 'Credit' ? (tx.amount - tx.paidAmount).toStringAsFixed(0) : tx.amount.toStringAsFixed(0)}'
                          : '${profile.currencySymbol}****',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 26,
                        color: tx.paymentMode == 'Credit' ? Colors.red : profile.themeColor,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
    );
  }


  Widget _rowBreakdown(
    String l,
    String v,
    ProfileProvider profile, {
    Color? color,
    bool isBold = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            l,
            style: TextStyle(
              color: profile.secondaryTextColor,
              fontSize: 13,
              fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
            ),
          ),
          Text(
            v,
            style: TextStyle(
              fontWeight: FontWeight.w900,
              color: color ?? profile.textColor,
              fontSize: isBold ? 15 : 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(String l, String v, ProfileProvider profile) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            l,
            style: TextStyle(color: profile.secondaryTextColor, fontSize: 13),
          ),
          Text(
            v,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: profile.textColor,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _launchURL(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}

class _StaffReportList extends StatelessWidget {
  const _StaffReportList({super.key});

  Color _getRoleColor(String role, Color themeColor) {
    switch (role.toLowerCase()) {
      case 'manager':
        return Colors.amber.shade700;
      case 'chef':
        return Colors.orangeAccent.shade700;
      case 'waiter':
        return themeColor;
      case 'cleaner':
        return Colors.teal.shade700;
      case 'security':
        return Colors.indigo.shade700;
      default:
        return themeColor;
    }
  }

  ImageProvider? _getStaffImage(StaffModel staff) {
    if (staff.imagePath != null && File(staff.imagePath!).existsSync()) {
      return FileImage(File(staff.imagePath!));
    }
    if (staff.imageUrl != null && staff.imageUrl!.isNotEmpty) {
      if (staff.imageUrl!.startsWith('base64:')) {
        try {
          return MemoryImage(base64Decode(staff.imageUrl!.replaceFirst('base64:', '')));
        } catch (e) {
          return null;
        }
      }
      return NetworkImage(staff.imageUrl!);
    }
    return null;
  }

  bool _shouldShowPlaceholder(StaffModel staff) {
    if (staff.imagePath != null && File(staff.imagePath!).existsSync()) return false;
    if (staff.imageUrl != null && staff.imageUrl!.isNotEmpty) return false;
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final staffProvider = Provider.of<StaffProvider>(context);
    final profile = Provider.of<ProfileProvider>(context);
    final themeColor = profile.themeColor;
    final staffList = staffProvider.staffList;

    if (staffList.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.people_outline,
              size: 64,
              color: profile.secondaryTextColor.withValues(alpha: 0.1),
            ),
            const SizedBox(height: 16),
            Text(
              'No staff records found',
              style: TextStyle(
                color: profile.secondaryTextColor,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
      itemCount: staffList.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: ElevatedButton.icon(
            onPressed: () async {
                final exportService = ExportService();
                await exportService.exportAllStaffReport(
                  profile.businessName,
                  staffList,
                  staffProvider,
                  range: (context.findAncestorStateOfType<_ReportsScreenState>())?._selectedRange,
                );
              },
              icon: const Icon(Icons.picture_as_pdf_rounded),
              label: const Text("DOWNLOAD ALL STAFF REPORT"),
              style: ElevatedButton.styleFrom(
                backgroundColor: themeColor.withValues(alpha: 0.1),
                foregroundColor: themeColor,
                elevation: 0,
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          );
        }

        final staff = staffList[index - 1];
        final payable = staffProvider.calculatePayable(staff);
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: profile.cardColor,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: profile.isDarkMode ? Colors.white10 : Colors.grey.shade100,
            ),
          ),
          child: ExpansionTile(
            shape: const RoundedRectangleBorder(side: BorderSide.none),
            collapsedShape: const RoundedRectangleBorder(side: BorderSide.none),
            leading: Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: themeColor.withValues(alpha: 0.2),
                  width: 1,
                ),
              ),
              child: CircleAvatar(
                radius: 18,
                backgroundColor: themeColor.withValues(alpha: 0.1),
                backgroundImage: _getStaffImage(staff),
                child: _shouldShowPlaceholder(staff)
                    ? Icon(Icons.person_outline, color: themeColor, size: 18)
                    : null,
              ),
            ),
            title: Text(
              staff.name,
              style: TextStyle(
                fontWeight: FontWeight.w900,
                color: profile.textColor,
                fontSize: 15,
                letterSpacing: 0.3,
              ),
            ),
            subtitle: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: _getRoleColor(
                      staff.role,
                      themeColor,
                    ).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(
                      color: _getRoleColor(
                        staff.role,
                        themeColor,
                      ).withValues(alpha: 0.2),
                      width: 0.5,
                    ),
                  ),
                  child: Text(
                    staff.role.toUpperCase(),
                    style: TextStyle(
                      color: _getRoleColor(staff.role, themeColor),
                      fontSize: 8,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  'Base: ${profile.currencySymbol}${staff.monthlySalary.toStringAsFixed(0)}',
                  style: TextStyle(
                    fontSize: 10,
                    color: profile.secondaryTextColor,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Column(
                  children: [
                    const Divider(),
                    _row(
                      label: 'Base Salary',
                      value: '${profile.currencySymbol}${profile.showAmount ? staff.monthlySalary.toStringAsFixed(0) : "****"}',
                      profile: profile,
                    ),
                    _row(
                      label: 'Advance Given (Total)',
                      value: '${profile.currencySymbol}${profile.showAmount ? staff.advance.toStringAsFixed(0) : "****"}',
                      profile: profile,
                      color: Colors.red,
                    ),

                    // --- ADVANCE HISTORY ---
                    FutureBuilder<List<StaffAdvanceModel>>(
                      future: staffProvider.getStaffAdvances(staff.id ?? 0),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return const SizedBox(height: 20, child: Center(child: LinearProgressIndicator(minHeight: 1)));
                        }
                        if (snapshot.hasData && snapshot.data != null && snapshot.data!.isNotEmpty) {
                          final List<StaffAdvanceModel> advList = snapshot.data!;
                          return Container(
                            margin: const EdgeInsets.symmetric(vertical: 8),
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: profile.scaffoldColor,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  "ADVANCE BREAKDOWN",
                                  style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.grey)
                                ),
                                const SizedBox(height: 6),
                                ...advList.map((adv) {
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 6),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              DateFormat('dd MMM yyyy').format(adv.date),
                                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)
                                            ),
                                            Text(
                                              DateFormat('hh:mm a').format(adv.date),
                                              style: const TextStyle(fontSize: 9, color: Colors.grey)
                                            ),
                                          ],
                                        ),
                                        Text(
                                          "${profile.currencySymbol}${adv.amount.toStringAsFixed(0)}",
                                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.red)
                                        ),
                                      ],
                                    ),
                                  );
                                }).toList(),
                              ],
                            ),
                          );
                        }
                        return const SizedBox.shrink();
                      },
                    ),

                    _row(
                      label: 'Leaves (${staff.totalLeaves.toStringAsFixed(1)})',
                      value: '- ${profile.currencySymbol}${profile.showAmount ? (staff.monthlySalary / 30 * staff.totalLeaves).toStringAsFixed(0) : "****"}',
                      profile: profile,
                      color: Colors.red,
                    ),
                    const Divider(),
                    _row(
                      label: 'NET PAYABLE',
                      value: '${profile.currencySymbol}${profile.showAmount ? payable.toStringAsFixed(0) : "****"}',
                      profile: profile,
                      isBold: true,
                      color: Colors.green,
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () => _paySalary(context, staff, payable),
                            icon: const Icon(Icons.payments_outlined, size: 18),
                            label: const Text('PAY & ADD TO EXPENSE'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                              minimumSize: const Size(0, 45),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              elevation: 0,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          onPressed: () async {
                            final DateTimeRange? picked = await showDateRangePicker(
                              context: context,
                              initialDateRange: DateTimeRange(
                                start: DateTime.now().subtract(const Duration(days: 30)),
                                end: DateTime.now(),
                              ),
                              firstDate: DateTime(2023),
                              lastDate: DateTime.now(),
                              builder: (context, child) => Theme(
                                data: Theme.of(context).copyWith(
                                  colorScheme: ColorScheme.light(
                                    primary: themeColor,
                                    onPrimary: Colors.white,
                                    onSurface: profile.textColor,
                                  ),
                                ),
                                child: child!,
                              ),
                            );
                            if (picked != null) {
                              final exportService = ExportService();
                              await exportService.exportSingleStaffReport(
                                profile.businessName,
                                staff,
                                staffProvider,
                                picked,
                              );
                            }
                          },
                          icon: const Icon(Icons.picture_as_pdf_rounded, color: Colors.red),
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.red.withValues(alpha: 0.1),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _paySalary(BuildContext context, dynamic staff, double amount) async {
    final txProvider = Provider.of<TransactionProvider>(context, listen: false);
    final staffProvider = Provider.of<StaffProvider>(context, listen: false);
    final itemProvider = Provider.of<ItemProvider>(context, listen: false);
    final profile = Provider.of<ProfileProvider>(context, listen: false);

    final confirm = await AppBottomSheet.showAction(
      context: context,
      profile: profile,
      title: 'Confirm Salary Payment',
      message:
          'Add ${profile.currencySymbol}${amount.toStringAsFixed(0)} as an expense and reset leaves/advance for ${staff.name}?',
      confirmLabel: 'PAY SALARY',
      confirmColor: Colors.green,
      icon: Icons.payments_outlined,
    );

    if (confirm == true) {
      final tx = TransactionModel(
        type: 'purchase',
        category: 'Salary',
        description:
            'Salary Paid to ${staff.name} for ${DateFormat('MMMM yyyy').format(DateTime.now())}',
        amount: amount,
        date: DateTime.now(),
        paymentMode: 'Cash',
        status: 'completed',
      );
      await txProvider.addTransaction(tx, itemProvider);

      staff.totalLeaves = 0;
      await staffProvider.updateStaff(staff);
      await staffProvider.clearStaffAdvances(staff.id!);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Salary paid and added to expenses!'),
          ),
        );
      }
    }
  }


  Widget _row({
    required String label,
    required String value,
    required ProfileProvider profile,
    bool isBold = false,
    Color? color,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              color: profile.secondaryTextColor,
              fontSize: 12,
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontWeight: isBold ? FontWeight.w900 : FontWeight.bold,
              color: color ?? profile.textColor,
              fontSize: isBold ? 14 : 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _TrashList extends StatefulWidget {
  const _TrashList({super.key});

  @override
  State<_TrashList> createState() => _TrashListState();
}

class _TrashListState extends State<_TrashList> {
  final Set<String> _selectedIds =
      {}; // Format: "TYPE_ID" e.g., "TX_1", "ITEM_5"
  String _filterType = 'ALL';

  String _getSmartTitle(dynamic model) {
    if (model is TransactionModel) {
      final items = model.parsedItems;
      if (items.isEmpty) return model.type == 'sale' ? 'Sale' : 'Purchase';
      if (items.length == 1) return items.first['name'] ?? 'Item';
      return '${items.first['name']} + ${items.length - 1} more';
    } else if (model is ItemModel) {
      return model.name;
    } else if (model is CategoryModel) {
      return model.name;
    } else if (model is StaffModel) {
      return model.name;
    }
    return 'Unknown';
  }

  void _toggleSelection(String globalId) {
    setState(() {
      if (_selectedIds.contains(globalId)) {
        _selectedIds.remove(globalId);
      } else {
        _selectedIds.add(globalId);
      }
    });
  }

  void _selectAll(List<dynamic> allItems) {
    setState(() {
      if (_selectedIds.length == allItems.length) {
        _selectedIds.clear();
      } else {
        for (var item in allItems) {
          String gid = "";
          if (item is TransactionModel)
            gid = "TX_${item.id}";
          else if (item is ItemModel)
            gid = "ITEM_${item.id}";
          else if (item is CategoryModel)
            gid = "CAT_${item.id}";
          else if (item is StaffModel)
            gid = "STAFF_${item.id}";
          if (gid.isNotEmpty) _selectedIds.add(gid);
        }
      }
    });
  }

  void _restoreSelected(
    TransactionProvider tx,
    ItemProvider item,
    CategoryProvider cat,
    StaffProvider staff,
  ) async {
    for (String gid in _selectedIds) {
      final parts = gid.split('_');
      final type = parts[0];
      final id = int.parse(parts[1]);

      if (type == 'TX')
        await tx.restoreTransaction(id, item);
      else if (type == 'ITEM')
        await item.restoreItem(id);
      else if (type == 'CAT')
        await cat.restoreCategory(id);
      else if (type == 'STAFF')
        await staff.restoreStaff(id);
    }
    setState(() => _selectedIds.clear());
    if (mounted)
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Selected items restored!')));
  }

  void _bulkPermanentDelete() async {
    if (_selectedIds.isEmpty) return;
    final txProvider = Provider.of<TransactionProvider>(context, listen: false);
    final itemProvider = Provider.of<ItemProvider>(context, listen: false);
    final catProvider = Provider.of<CategoryProvider>(context, listen: false);
    final staffProvider = Provider.of<StaffProvider>(context, listen: false);
    final profile = Provider.of<ProfileProvider>(context, listen: false);

    final confirm = await AppBottomSheet.showAction(
      context: context,
      profile: profile,
      title: 'Delete Permanently?',
      message:
          'Delete ${_selectedIds.length} items permanently? This action cannot be undone. Data will be removed from cloud and local storage.',
      confirmLabel: 'DELETE ALL',
      isDestructive: true,
      icon: Icons.delete_forever_rounded,
    );

    if (confirm == true) {
      for (String gid in _selectedIds) {
        final parts = gid.split('_');
        final type = parts[0];
        final id = int.parse(parts[1]);

        if (type == 'TX')
          await txProvider.permanentDeleteTransaction(id);
        else if (type == 'ITEM')
          await itemProvider.permanentDeleteItem(id);
        else if (type == 'CAT')
          await catProvider.permanentDeleteCategory(id);
        else if (type == 'STAFF')
          await staffProvider.permanentDeleteStaff(id);
      }
      setState(() => _selectedIds.clear());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Selected items permanently deleted!'),
          ),
        );
      }
    }
  }


  Widget _filterChip(String id, String label, ProfileProvider profile) {
    final isSelected = _filterType == id;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: isSelected ? Colors.white : profile.secondaryTextColor,
          ),
        ),
        selected: isSelected,
        onSelected: (val) {
          if (val)
            setState(() {
              _filterType = id;
              _selectedIds.clear();
            });
        },
        selectedColor: Colors.red,
        backgroundColor: profile.cardColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: profile.isDarkMode ? Colors.white10 : Colors.grey.shade100,
          ),
        ),
        showCheckmark: false,
        visualDensity: VisualDensity.compact,
      ),
    );
  }

  ImageProvider? _getStaffImage(StaffModel staff) {
    if (staff.imagePath != null && File(staff.imagePath!).existsSync()) {
      return FileImage(File(staff.imagePath!));
    }
    if (staff.imageUrl != null && staff.imageUrl!.isNotEmpty) {
      if (staff.imageUrl!.startsWith('base64:')) {
        try {
          return MemoryImage(base64Decode(staff.imageUrl!.replaceFirst('base64:', '')));
        } catch (e) {
          return null;
        }
      }
      return NetworkImage(staff.imageUrl!);
    }
    return null;
  }

  bool _shouldShowPlaceholder(StaffModel staff) {
    if (staff.imagePath != null && File(staff.imagePath!).existsSync()) return false;
    if (staff.imageUrl != null && staff.imageUrl!.isNotEmpty) return false;
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final txProvider = Provider.of<TransactionProvider>(context);
    final itemProvider = Provider.of<ItemProvider>(context);
    final catProvider = Provider.of<CategoryProvider>(context);
    final staffProvider = Provider.of<StaffProvider>(context);
    final profile = Provider.of<ProfileProvider>(context);

    List<dynamic> allDeleted = [
      ...txProvider.deletedTransactions,
      ...itemProvider.deletedItems,
      ...catProvider.deletedCategories,
      ...staffProvider.deletedStaff,
    ];

    // Apply Filter
    if (_filterType != 'ALL') {
      allDeleted = allDeleted.where((m) {
        if (_filterType == 'TX') return m is TransactionModel;
        if (_filterType == 'ITEM') return m is ItemModel;
        if (_filterType == 'CAT') return m is CategoryModel;
        if (_filterType == 'STAFF') return m is StaffModel;
        return true;
      }).toList();
    }

    // Sort by deletedAt if available
    allDeleted.sort((a, b) {
      DateTime? da = (a is TransactionModel)
          ? a.deletedAt
          : (a is ItemModel
                ? a.deletedAt
                : (a is CategoryModel
                      ? a.deletedAt
                      : (a is StaffModel ? a.deletedAt : null)));
      DateTime? db = (b is TransactionModel)
          ? b.deletedAt
          : (b is ItemModel
                ? b.deletedAt
                : (b is CategoryModel
                      ? b.deletedAt
                      : (b is StaffModel ? b.deletedAt : null)));
      if (da == null) return 1;
      if (db == null) return -1;
      return db.compareTo(da);
    });

    final isSelectionMode = _selectedIds.isNotEmpty;

    if (allDeleted.isEmpty && _filterType == 'ALL') {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.delete_sweep_outlined,
              size: 64,
              color: profile.secondaryTextColor.withValues(alpha: 0.1),
            ),
            const SizedBox(height: 16),
            Text(
              'Trash is empty',
              style: TextStyle(
                color: profile.secondaryTextColor,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // Filter and Selection Bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _filterChip('ALL', 'All Items', profile),
                          _filterChip('TX', 'Bills/TX', profile),
                          _filterChip('ITEM', 'Items', profile),
                          _filterChip('CAT', 'Categories', profile),
                          _filterChip('STAFF', 'Staff Members', profile),
                        ],
                      ),
                    ),
                  ),
                  if (allDeleted.isNotEmpty)
                    IconButton(
                      icon: Icon(
                        _selectedIds.length == allDeleted.length
                            ? Icons.check_circle
                            : Icons.check_circle_outline,
                        color: isSelectionMode
                            ? Colors.red
                            : profile.secondaryTextColor,
                      ),
                      onPressed: () => _selectAll(allDeleted),
                    ),
                ],
              ),
              if (isSelectionMode) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => _restoreSelected(
                          txProvider,
                          itemProvider,
                          catProvider,
                          staffProvider,
                        ),
                        icon: const Icon(
                          Icons.restore_from_trash_rounded,
                          size: 18,
                        ),
                        label: const Text(
                          'RESTORE SELECTED',
                          style: TextStyle(fontSize: 9),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _bulkPermanentDelete,
                        icon: const Icon(
                          Icons.delete_forever_rounded,
                          size: 18,
                        ),
                        label: const Text(
                          'DELETE PERMANENT',
                          style: TextStyle(fontSize: 9),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),

        Expanded(
          child: allDeleted.isEmpty
              ? Center(
                  child: Text(
                    'No results for this filter',
                    style: TextStyle(color: profile.secondaryTextColor),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                  itemCount: allDeleted.length,
                  itemBuilder: (context, index) {
                    final model = allDeleted[index];
                    String gid = "";
                    String typeLabel = "";
                    IconData icon = Icons.help_outline;
                    Color color = Colors.grey;
                    DateTime? deletedAt;

                    if (model is TransactionModel) {
                      gid = "TX_${model.id}";
                      typeLabel = "TRANSACTION";
                      icon = model.status == 'pending'
                          ? Icons.timer_outlined
                          : (model.type == 'sale'
                                ? Icons.south_west_rounded
                                : Icons.north_east_rounded);
                      color = model.status == 'pending'
                          ? Colors.orange
                          : profile.themeColor;
                      deletedAt = model.deletedAt;
                    } else if (model is ItemModel) {
                      gid = "ITEM_${model.id}";
                      typeLabel = "ITEM";
                      icon = Icons.inventory_2_outlined;
                      color = Colors.teal;
                      deletedAt = model.deletedAt;
                    } else if (model is CategoryModel) {
                      gid = "CAT_${model.id}";
                      typeLabel = "CATEGORY";
                      icon = Icons.category_outlined;
                      color = Colors.purple;
                      deletedAt = model.deletedAt;
                    } else if (model is StaffModel) {
                      gid = "STAFF_${model.id}";
                      typeLabel = "STAFF";
                      icon = Icons.people_outline;
                      color = Colors.amber;
                      deletedAt = model.deletedAt;
                    }

                    final isSelected = _selectedIds.contains(gid);

                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? Colors.red.withValues(alpha: 0.08)
                            : profile.cardColor,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isSelected
                              ? Colors.red
                              : Colors.red.withValues(alpha: 0.1),
                          width: isSelected ? 2 : 1,
                        ),
                      ),
                      child: ListTile(
                        onLongPress: () => _toggleSelection(gid),
                        onTap: isSelectionMode
                            ? () => _toggleSelection(gid)
                            : () => _showDeletedActions(
                                context,
                                model,
                                txProvider,
                                itemProvider,
                                catProvider,
                                staffProvider,
                                profile,
                              ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 4,
                        ),
                        leading: isSelected
                            ? const Icon(
                                Icons.check_circle,
                                color: Colors.red,
                                size: 28,
                              )
                            : Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: color.withValues(alpha: 0.1),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(icon, color: color, size: 18),
                              ),
                        title: Row(
                          children: [
                            Expanded(
                              child: Text(
                                _getSmartTitle(model),
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: profile.textColor,
                                  fontSize: 14,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                typeLabel,
                                style: TextStyle(
                                  color: color,
                                  fontSize: 8,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        subtitle: Text(
                          'Deleted on: ${deletedAt != null ? DateFormat('dd MMM, hh:mm a').format(deletedAt) : 'N/A'}',
                          style: TextStyle(
                            fontSize: 10,
                            color: profile.secondaryTextColor,
                          ),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (model is TransactionModel)
                              Text(
                                profile.showAmount
                                    ? '${profile.currencySymbol}${model.amount.toStringAsFixed(0)}'
                                    : '${profile.currencySymbol}****',
                                style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  color: profile.textColor,
                                  fontSize: 14,
                                ),
                              ),
                            if (!isSelectionMode)
                              const Icon(
                                Icons.chevron_right_rounded,
                                size: 20,
                                color: Colors.grey,
                              ),
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

  void _showDeletedActions(
    BuildContext context,
    dynamic model,
    TransactionProvider txProvider,
    ItemProvider itemProvider,
    CategoryProvider catProvider,
    StaffProvider staffProvider,
    ProfileProvider profile,
  ) {
    // Showing bill details
    AppBottomSheet.show(
      context: context,
      profile: profile,
      title: 'DELETED RECORD DETAILS',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'TRASHED',
                  style: TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.w900,
                    fontSize: 10,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          Text(
            _getSmartTitle(model),
            style: TextStyle(
              color: profile.textColor,
              fontWeight: FontWeight.w900,
              fontSize: 22,
            ),
          ),

          if (model is TransactionModel) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  Icons.calendar_today,
                  size: 14,
                  color: profile.secondaryTextColor,
                ),
                const SizedBox(width: 6),
                Text(
                  DateFormat('dd MMM yyyy, hh:mm a').format(model.date),
                  style: TextStyle(
                    color: profile.secondaryTextColor,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
            const Divider(height: 40),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.3,
              ),
              child: SingleChildScrollView(
                child: Column(
                  children: model.parsedItems
                      .map(
                        (item) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item['name'] ?? '',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: profile.textColor,
                                    ),
                                  ),
                                  Text(
                                    '${item['qty']} x ${profile.currencySymbol}${item['price']}',
                                    style: TextStyle(
                                      color: profile.secondaryTextColor,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                              Text(
                                profile.showAmount
                                    ? '${profile.currencySymbol}${(double.parse(item['qty'] ?? '0') * double.parse(item['price'] ?? '0')).toStringAsFixed(0)}'
                                    : '${profile.currencySymbol}****',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
            ),
            const Divider(height: 40),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'TOTAL AMOUNT',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(
                  profile.showAmount
                      ? '${profile.currencySymbol}${model.amount.toStringAsFixed(0)}'
                      : '${profile.currencySymbol}****',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 24,
                    color: Colors.red,
                  ),
                ),
              ],
            ),
          ] else if (model is ItemModel) ...[
            const SizedBox(height: 8),
            Text(
              'Category: ${model.category}',
              style: TextStyle(color: profile.secondaryTextColor),
            ),
            Text(
              'Current Stock: ${model.currentStock} ${model.unit}',
              style: TextStyle(color: profile.secondaryTextColor),
            ),
            const Divider(height: 40),
          ] else if (model is CategoryModel) ...[
            const SizedBox(height: 8),
            Text(
              'Type: ${model.type.toUpperCase()}',
              style: TextStyle(color: profile.secondaryTextColor),
            ),
            const Divider(height: 40),
          ] else if (model is StaffModel) ...[
            const SizedBox(height: 8),
            Text(
              'Role: ${model.role}',
              style: TextStyle(color: profile.secondaryTextColor),
            ),
            Text(
              'Salary: ${profile.currencySymbol}${model.monthlySalary}',
              style: TextStyle(color: profile.secondaryTextColor),
            ),
            const Divider(height: 40),
          ],

          const SizedBox(height: 28),
          Row(
            children: [
              Expanded(
                child: _actionBtn(
                  icon: Icons.restore_from_trash_rounded,
                  label: 'RESTORE',
                  color: Colors.green,
                  onTap: () async {
                    HapticFeedback.lightImpact();
                    Navigator.pop(context);
                    if (model is TransactionModel)
                      await txProvider.restoreTransaction(
                        model.id!,
                        itemProvider,
                      );
                    else if (model is ItemModel)
                      await itemProvider.restoreItem(model.id!);
                    else if (model is CategoryModel)
                      await catProvider.restoreCategory(model.id!);
                    else if (model is StaffModel)
                      await staffProvider.restoreStaff(model.id!);

                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Record restored!')),
                      );
                    }
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
                    HapticFeedback.heavyImpact();
                    Navigator.pop(context);
                    _showPermanentDeleteConfirm(
                      context,
                      model,
                      txProvider,
                      itemProvider,
                      catProvider,
                      staffProvider,
                      profile,
                    );
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _actionBtn({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w900,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showPermanentDeleteConfirm(
    BuildContext context,
    dynamic model,
    TransactionProvider txProvider,
    ItemProvider itemProvider,
    CategoryProvider catProvider,
    StaffProvider staffProvider,
    ProfileProvider profile,
  ) async {
    final confirm = await AppBottomSheet.showAction(
      context: context,
      profile: profile,
      title: 'Delete Permanently?',
      message: 'This action is final and cannot be undone.',
      confirmLabel: 'DELETE',
      isDestructive: true,
      icon: Icons.delete_forever_rounded,
    );

    if (confirm == true) {
      if (model is TransactionModel)
        await txProvider.permanentDeleteTransaction(model.id!);
      else if (model is ItemModel)
        await itemProvider.permanentDeleteItem(model.id!);
      else if (model is CategoryModel)
        await catProvider.permanentDeleteCategory(model.id!);
      else if (model is StaffModel)
        await staffProvider.permanentDeleteStaff(model.id!);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Record permanently deleted.')),
        );
      }
    }
  }
}

class _DateRangePickerSheet extends StatefulWidget {
  final DateTimeRange initialRange;
  final Function(DateTimeRange) onRangeSelected;
  final ProfileProvider profile;

  const _DateRangePickerSheet({
    required this.initialRange,
    required this.onRangeSelected,
    required this.profile,
  });

  @override
  State<_DateRangePickerSheet> createState() => _DateRangePickerSheetState();
}

class _DateRangePickerSheetState extends State<_DateRangePickerSheet> {
  late DateTime _startDate;
  late DateTime _endDate;

  @override
  void initState() {
    super.initState();
    _startDate = widget.initialRange.start;
    _endDate = widget.initialRange.end;
  }

  void _updateRange(DateTime start, DateTime end) {
    setState(() {
      _startDate = start;
      _endDate = end;
    });
  }

  ImageProvider? _getStaffImage(StaffModel staff) {
    if (staff.imagePath != null && File(staff.imagePath!).existsSync()) {
      return FileImage(File(staff.imagePath!));
    }
    if (staff.imageUrl != null && staff.imageUrl!.isNotEmpty) {
      if (staff.imageUrl!.startsWith('base64:')) {
        try {
          return MemoryImage(base64Decode(staff.imageUrl!.replaceFirst('base64:', '')));
        } catch (e) {
          return null;
        }
      }
      return NetworkImage(staff.imageUrl!);
    }
    return null;
  }

  bool _shouldShowPlaceholder(StaffModel staff) {
    if (staff.imagePath != null && File(staff.imagePath!).existsSync()) return false;
    if (staff.imageUrl != null && staff.imageUrl!.isNotEmpty) return false;
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final profile = widget.profile;
    return Container(
      decoration: BoxDecoration(
        color: profile.cardColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(25)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          const SizedBox(height: 25),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'SELECT DATE RANGE',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: profile.textColor,
                  letterSpacing: 1,
                ),
              ),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: Icon(Icons.close, color: profile.textColor),
              ),
            ],
          ),
          const SizedBox(height: 25),
          Row(
            children: [
              _buildDateBox('FROM', _startDate, true),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Icon(Icons.arrow_forward, color: profile.themeColor, size: 16),
              ),
              _buildDateBox('TO', _endDate, false),
            ],
          ),
          const SizedBox(height: 25),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _quickFilterBtn('Today', () {
                  final now = DateTime.now();
                  _updateRange(DateTime(now.year, now.month, now.day), DateTime(now.year, now.month, now.day, 23, 59, 59));
                }),
                _quickFilterBtn('Yesterday', () {
                  final yesterday = DateTime.now().subtract(const Duration(days: 1));
                  _updateRange(DateTime(yesterday.year, yesterday.month, yesterday.day), DateTime(yesterday.year, yesterday.month, yesterday.day, 23, 59, 59));
                }),
                _quickFilterBtn('Last 7 Days', () {
                  final now = DateTime.now();
                  _updateRange(now.subtract(const Duration(days: 7)), now);
                }),
                _quickFilterBtn('This Month', () {
                  final now = DateTime.now();
                  _updateRange(DateTime(now.year, now.month, 1), now);
                }),
              ],
            ),
          ),
          const SizedBox(height: 30),
          SizedBox(
            width: double.infinity,
            height: 55,
            child: ElevatedButton(
              onPressed: () {
                widget.onRangeSelected(DateTimeRange(start: _startDate, end: _endDate));
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: profile.themeColor,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                elevation: 0,
              ),
              child: const Text(
                'APPLY FILTER',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16),
              ),
            ),
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }

  Widget _buildDateBox(String label, DateTime date, bool isStart) {
    return Expanded(
      child: InkWell(
        onTap: () async {
          final selected = await showDatePicker(
            context: context,
            initialDate: date,
            firstDate: DateTime(2020),
            lastDate: DateTime.now(),
            builder: (context, child) {
              return Theme(
                data: Theme.of(context).copyWith(
                  colorScheme: ColorScheme.dark(
                    primary: widget.profile.themeColor,
                    onPrimary: Colors.white,
                    surface: widget.profile.cardColor,
                    onSurface: widget.profile.textColor,
                  ),
                ),
                child: child!,
              );
            },
          );
          if (selected != null) {
            if (isStart) {
              _updateRange(selected, _endDate.isBefore(selected) ? selected : _endDate);
            } else {
              _updateRange(_startDate.isAfter(selected) ? selected : _startDate, selected);
            }
          }
        },
        child: Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            color: widget.profile.scaffoldColor,
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: Colors.white10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold)),
              const SizedBox(height: 5),
              Text(
                DateFormat('dd MMM yyyy').format(date),
                style: TextStyle(color: widget.profile.textColor, fontWeight: FontWeight.w900, fontSize: 14),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _quickFilterBtn(String label, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          padding: const EdgeInsets.symmetric(horizontal: 15),
        ),
        child: Text(label, style: TextStyle(color: widget.profile.textColor, fontSize: 12)),
      ),
    );
  }
}

class _CEOAuditView extends StatelessWidget {
  final DateTimeRange range;
  const _CEOAuditView({required this.range, super.key});

  ImageProvider? _getStaffImage(StaffModel staff) {
    if (staff.imagePath != null && File(staff.imagePath!).existsSync()) {
      return FileImage(File(staff.imagePath!));
    }
    if (staff.imageUrl != null && staff.imageUrl!.isNotEmpty) {
      if (staff.imageUrl!.startsWith('base64:')) {
        try {
          return MemoryImage(base64Decode(staff.imageUrl!.replaceFirst('base64:', '')));
        } catch (e) {
          return null;
        }
      }
      return NetworkImage(staff.imageUrl!);
    }
    return null;
  }

  bool _shouldShowPlaceholder(StaffModel staff) {
    if (staff.imagePath != null && File(staff.imagePath!).existsSync()) return false;
    if (staff.imageUrl != null && staff.imageUrl!.isNotEmpty) return false;
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final profile = Provider.of<ProfileProvider>(context);
    final txProvider = Provider.of<TransactionProvider>(context);
    final itemProvider = Provider.of<ItemProvider>(context);

    // Filter only Readymade items
    final readymadeItems = itemProvider.items.where((i) => i.itemType == 'readymade' && i.isDeleted == 0).toList();

    // Get sales and purchases for these items in the range
    final allSales = txProvider.getFilteredTransactions(type: 'sale', range: range, status: 'completed');
    final allPurchases = txProvider.getFilteredTransactions(type: 'purchase', range: range, status: 'completed');

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      children: [
        ...readymadeItems.map((item) {
          double totalSoldQty = 0;
          double totalSalesAmt = 0;
          double totalCostAmt = 0;

          // Calculate Sales for this item
          for (var tx in allSales) {
            for (var s in tx.itemSnapshots) {
              if (s.name == item.name) {
                double qty = s.qty + s.extraQty;
                totalSoldQty += qty;
                totalSalesAmt += s.lineTotal;
                // Use purchase price from snapshot if available, else from master item
                double cost = (s.purchasePrice > 0 ? s.purchasePrice : (item.purchasePrice ?? 0)) +
                              (s.transportCost > 0 ? s.transportCost : (item.transportCost ?? 0));
                totalCostAmt += qty * cost;
              }
            }
          }

          double avgSaleRate = totalSoldQty > 0 ? totalSalesAmt / totalSoldQty : 0;
          double avgCostRate = totalSoldQty > 0 ? totalCostAmt / totalSoldQty : (item.purchasePrice ?? 0) + (item.transportCost ?? 0);
          double unitProfit = avgSaleRate - avgCostRate;
          double gpMargin = avgSaleRate > 0 ? (unitProfit / avgSaleRate) * 100 : 0;

          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: profile.cardColor,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: profile.themeColor.withValues(alpha: 0.3), width: 1.5),
              boxShadow: [
                BoxShadow(color: profile.themeColor.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4)),
              ],
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
                          Text(item.name.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15, letterSpacing: 0.5)),
                          Text(item.category, style: TextStyle(color: profile.secondaryTextColor, fontSize: 11, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(color: profile.themeColor, borderRadius: BorderRadius.circular(8)),
                      child: const Text('READYMADE', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w900)),
                    ),
                  ],
                ),
                const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Divider(height: 1, thickness: 0.5)),
                Row(
                  children: [
                    _auditStat('Sold Qty', totalSoldQty.toStringAsFixed(1), profile.themeColor),
                    _auditStat('Avg Sale', '${profile.currencySymbol}${avgSaleRate.toStringAsFixed(1)}', Colors.green),
                    _auditStat('Avg Cost', '${profile.currencySymbol}${avgCostRate.toStringAsFixed(1)}', Colors.orange),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: (gpMargin >= 0 ? Colors.green : Colors.red).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('GP MARGIN', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12, color: gpMargin >= 0 ? Colors.green : Colors.red)),
                      Text('${gpMargin.toStringAsFixed(1)}%', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: gpMargin >= 0 ? Colors.green : Colors.red)),
                    ],
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _auditStat(String label, String value, Color color) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Text(value, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: color)),
        ],
      ),
    );
  }
}

