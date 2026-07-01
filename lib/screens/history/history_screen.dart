import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../providers/transaction_provider.dart';
import '../../providers/item_provider.dart';
import '../../providers/profile_provider.dart';
import '../../models/transaction_model.dart';
import '../daily_entry/entry_screen.dart';
import '../../core/widgets/app_bottom_sheet.dart';

class HistoryScreen extends StatefulWidget {
  final bool isPopup;
  const HistoryScreen({super.key, this.isPopup = false});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final Set<int> _selectedIds = {};
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = "";

  // Advanced Filters
  String _filterPaymentMode = 'All';
  String _filterTable = 'All';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) {
        setState(() {
          _selectedIds.clear();
          _searchQuery = "";
          _searchController.clear();
          _resetFilters();
        });
      }
    });
  }

  void _resetFilters() {
    _filterPaymentMode = 'All';
    _filterTable = 'All';
    // _startDate and _endDate are not used in this implementation
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _showFilterSheet() {
    final profile = Provider.of<ProfileProvider>(context, listen: false);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          decoration: BoxDecoration(
            color: profile.cardColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Filter History',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: profile.textColor,
                ),
              ),
              const SizedBox(height: 24),

              Text(
                'Payment Mode',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: profile.secondaryTextColor,
                ),
              ),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: ['All', 'Cash', 'UPI', 'Split', 'Credit'].map((
                    mode,
                  ) {
                    bool isSel = _filterPaymentMode == mode;
                    return GestureDetector(
                      onTap: () =>
                          setModalState(() => _filterPaymentMode = mode),
                      child: Container(
                        margin: const EdgeInsets.only(right: 8),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: isSel
                              ? profile.themeColor
                              : profile.themeColor.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          mode,
                          style: TextStyle(
                            color: isSel ? Colors.white : profile.themeColor,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),

              const SizedBox(height: 20),
              Text(
                'Table Number',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: profile.secondaryTextColor,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: profile.scaffoldColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _filterTable,
                    isExpanded: true,
                    dropdownColor: profile.cardColor,
                    items:
                        [
                              'All',
                              ...List.generate(
                                profile.totalTables,
                                (i) => (i + 1).toString(),
                              ),
                            ]
                            .map(
                              (t) => DropdownMenuItem(
                                value: t,
                                child: Text(
                                  t == 'All' ? 'All Tables' : 'Table $t',
                                ),
                              ),
                            )
                            .toList(),
                    onChanged: (v) => setModalState(() => _filterTable = v!),
                  ),
                ),
              ),

              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: () {
                  setState(() {});
                  Navigator.pop(context);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: profile.themeColor,
                  minimumSize: const Size(double.infinity, 56),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: const Text(
                  'APPLY FILTERS',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
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

  void _bulkDelete() async {
    final txProvider = Provider.of<TransactionProvider>(context, listen: false);
    final itemProvider = Provider.of<ItemProvider>(context, listen: false);
    final profile = Provider.of<ProfileProvider>(context, listen: false);

    final confirmed = await AppBottomSheet.showAction(
      context: context,
      profile: profile,
      title: 'Bulk Delete',
      message: 'Are you sure you want to move ${_selectedIds.length} items to Trash?',
      confirmLabel: 'DELETE',
      isDestructive: true,
      icon: Icons.delete_sweep_rounded,
    );

    if (confirmed == true && mounted) {
      for (int id in _selectedIds) {
        await txProvider.softDeleteTransaction(id, itemProvider);
      }
      setState(() => _selectedIds.clear());
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = Provider.of<ProfileProvider>(context);
    final themeColor = profile.themeColor;
    final isSelectionMode = _selectedIds.isNotEmpty;

    return Scaffold(
      backgroundColor: profile.scaffoldColor,
      appBar: widget.isPopup
          ? null
          : AppBar(
              backgroundColor: isSelectionMode
                  ? Colors.red.shade700
                  : profile.cardColor,
              foregroundColor: isSelectionMode
                  ? Colors.white
                  : profile.textColor,
              title: Text(
                isSelectionMode
                    ? '${_selectedIds.length} SELECTED'
                    : 'HISTORY & TRASH',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
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
                  )
                else ...[
                  IconButton(
                    icon: const Icon(Icons.filter_list_rounded),
                    onPressed: _showFilterSheet,
                  ),
                ],
              ],
              bottom: TabBar(
                controller: _tabController,
                indicatorColor: isSelectionMode ? Colors.white : themeColor,
                labelColor: isSelectionMode ? Colors.white : themeColor,
                unselectedLabelColor: isSelectionMode
                    ? Colors.white70
                    : profile.secondaryTextColor,
                labelStyle: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 13,
                ),
                tabs: const [
                  Tab(text: 'SALES'),
                  Tab(text: 'EXPENSES'),
                  Tab(text: 'TRASH'),
                ],
              ),
              elevation: 0,
            ),
      body: Column(
        children: [
          if (!isSelectionMode)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: TextField(
                controller: _searchController,
                style: TextStyle(
                  color: profile.textColor,
                  fontWeight: FontWeight.bold,
                ),
                decoration: InputDecoration(
                  hintText: 'Search by Bill No or Item Name...',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchQuery = "");
                          },
                        )
                      : null,
                  fillColor: profile.cardColor,
                ),
                onChanged: (v) => setState(() => _searchQuery = v),
              ),
            ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _HistoryList(
                  type: 'sale',
                  selectedIds: _selectedIds,
                  onToggle: _toggleSelection,
                  searchQuery: _searchQuery,
                  paymentMode: _filterPaymentMode,
                  table: _filterTable,
                ),
                _HistoryList(
                  type: 'expense',
                  selectedIds: _selectedIds,
                  onToggle: _toggleSelection,
                  searchQuery: _searchQuery,
                  paymentMode: _filterPaymentMode,
                  table: _filterTable,
                ),
                _HistoryList(
                  type: 'trash',
                  selectedIds: _selectedIds,
                  onToggle: _toggleSelection,
                  searchQuery: _searchQuery,
                  paymentMode: 'All',
                  table: 'All',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryList extends StatelessWidget {
  final String type;
  final Set<int> selectedIds;
  final Function(int) onToggle;
  final String searchQuery;
  final String paymentMode;
  final String table;

  const _HistoryList({
    required this.type,
    required this.selectedIds,
    required this.onToggle,
    required this.searchQuery,
    required this.paymentMode,
    required this.table,
  });

  @override
  Widget build(BuildContext context) {
    final txProvider = Provider.of<TransactionProvider>(context);
    final profile = Provider.of<ProfileProvider>(context);

    List<TransactionModel> list;
    if (type == 'trash') {
      list = txProvider.deletedTransactions;
    } else {
      list = txProvider.transactions.where((tx) {
        if (type == 'sale') return tx.type == 'sale';
        return tx.type == 'expense' || tx.type == 'purchase';
      }).toList();
    }

    // Apply Advanced Filters
    list = list.where((tx) {
      bool matchSearch = true;
      if (searchQuery.isNotEmpty) {
        bool billMatch = tx.id.toString().contains(searchQuery);
        bool itemMatch = tx.parsedItems.any(
          (i) => (i['name'] ?? '').toLowerCase().contains(
            searchQuery.toLowerCase(),
          ),
        );
        matchSearch = billMatch || itemMatch;
      }

      bool matchPayment = paymentMode == 'All' || tx.paymentMode == paymentMode;

      bool matchTable = true;
      if (table != 'All' && type == 'sale') {
        matchTable = tx.parsedItems.any((i) => i['table_number'] == table);
      }

      return matchSearch && matchPayment && matchTable;
    }).toList();

    if (list.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.history_rounded,
              size: 64,
              color: profile.secondaryTextColor.withValues(alpha: 0.1),
            ),
            const SizedBox(height: 16),
            Text(
              'No matching records found',
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
      padding: const EdgeInsets.all(16),
      itemCount: list.length,
      itemBuilder: (context, index) {
        final tx = list[index];
        final isSelected = selectedIds.contains(tx.id);
        final isTrash = type == 'trash';
        final isCredit = tx.paymentMode == 'Credit' && tx.remainingCredit > 0;

        return GestureDetector(
          onLongPress: () => onToggle(tx.id!),
          onTap: () {
            if (selectedIds.isNotEmpty) {
              onToggle(tx.id!);
            } else {
              _showTransactionDetailSheet(context, tx);
            }
          },
          child: Container(
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: isSelected
                  ? Colors.red.withValues(alpha: 0.05)
                  : profile.cardColor,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isSelected
                    ? Colors.red
                    : (isCredit
                          ? Colors.orange.withValues(alpha: 0.5)
                          : (profile.isDarkMode
                                ? Colors.white10
                                : Colors.grey.shade100)),
                width: (isSelected || isCredit) ? 2 : 1,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: isTrash
                          ? Colors.grey.withValues(alpha: 0.1)
                          : (tx.type == 'sale' ? Colors.green : Colors.red)
                                .withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isTrash
                          ? Icons.delete_outline
                          : (tx.type == 'sale'
                                ? Icons.south_west_rounded
                                : Icons.north_east_rounded),
                      color: isTrash
                          ? Colors.grey
                          : (tx.type == 'sale' ? Colors.green : Colors.red),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              '#${tx.id}',
                              style: TextStyle(
                                fontSize: 10,
                                color: profile.themeColor,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                tx.type == 'sale'
                                    ? (tx.parsedItems.isNotEmpty
                                          ? tx.parsedItems[0]['name']!
                                          : 'Sale Order')
                                    : tx.category,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                  color: profile.textColor,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          DateFormat('dd MMM, hh:mm a').format(tx.date),
                          style: TextStyle(
                            fontSize: 11,
                            color: profile.secondaryTextColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${profile.currencySymbol}${tx.amount.toStringAsFixed(0)}',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                          color: isTrash
                              ? Colors.grey
                              : (tx.type == 'sale' ? Colors.green : Colors.red),
                        ),
                      ),
                      Text(
                        tx.paymentMode,
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
            ),
          ),
        );
      },
    );
  }

  void _showTransactionDetailSheet(BuildContext context, TransactionModel tx) {
    final profile = Provider.of<ProfileProvider>(context, listen: false);
    final txProvider = Provider.of<TransactionProvider>(context, listen: false);
    final itemProvider = Provider.of<ItemProvider>(context, listen: false);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: profile.cardColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Bill #${tx.id}${tx.token.isNotEmpty ? " | TOKEN: ${tx.token}" : ""}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: profile.themeColor,
                      ),
                    ),
                    Text(
                      tx.type == 'sale' ? 'Sale Details' : 'Expense Details',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: profile.textColor,
                      ),
                    ),
                  ],
                ),
                if (tx.parsedItems.isNotEmpty &&
                    tx.parsedItems.first['table_number'] != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: profile.themeColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      'TABLE ${tx.parsedItems.first['table_number']}',
                      style: TextStyle(
                        color: profile.themeColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 24),
            Text(
              'ITEMS LIST',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 11,
                color: profile.secondaryTextColor,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 12),
            ...tx.parsedItems.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 12.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${item['name']} (${item['variant']})',
                            style: TextStyle(
                              color: profile.textColor,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            '${item['qty']} x ${profile.currencySymbol}${item['price']}${(double.tryParse(item['extra_qty'] ?? '0') ?? 0) > 0 ? " + Extra: ${item['extra_qty']}" : ""}',
                            style: TextStyle(
                              color: profile.secondaryTextColor,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: profile.themeColor.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        item['serving_method'] ?? 'Dine-in',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: profile.themeColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const Divider(height: 32),
            _detailRow(
              'Total Amount',
              '${profile.currencySymbol}${tx.amount}',
              profile,
              isBold: true,
            ),
            _detailRow('Payment Mode', tx.paymentMode, profile),
            const SizedBox(height: 32),
            Row(
              children: [
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
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('EDIT'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.blue,
                      side: const BorderSide(color: Colors.blue),
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      txProvider.softDeleteTransaction(tx.id!, itemProvider);
                    },
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('DELETE'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red.shade50,
                      foregroundColor: Colors.red,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 0,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(
    String label,
    String value,
    ProfileProvider profile, {
    bool isBold = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(color: profile.secondaryTextColor, fontSize: 13),
          ),
          Text(
            value,
            style: TextStyle(
              fontWeight: isBold ? FontWeight.w900 : FontWeight.bold,
              color: profile.textColor,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}
