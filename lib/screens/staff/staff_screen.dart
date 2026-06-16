import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:flutter/rendering.dart';
import 'package:table_calendar/table_calendar.dart';
import '../../providers/staff_provider.dart';
import '../../models/staff_model.dart';
import '../../providers/profile_provider.dart';
import '../../utils/report_helper.dart';
import '../../utils/image_helper.dart';
import '../../services/export_service.dart';
import '../../core/widgets/app_bottom_sheet.dart';

class StaffScreen extends StatefulWidget {
  const StaffScreen({super.key});

  @override
  State<StaffScreen> createState() => _StaffScreenState();
}

class _StaffScreenState extends State<StaffScreen> {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  int? _expandedIndex;
  bool _showDeleted = false;
  String _searchQuery = "";

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Color _getRoleColor(String role, Color themeColor) {
    switch (role.toLowerCase()) {
      case 'manager':
        return Colors.amber.shade700;
      case 'chef':
        return Colors.orange.shade700;
      case 'waiter':
        return Colors.blue.shade700;
      case 'cleaner':
        return Colors.teal.shade700;
      case 'security':
        return Colors.indigo.shade700;
      default:
        return themeColor;
    }
  }

  @override
  Widget build(BuildContext context) {
    final staffProvider = Provider.of<StaffProvider>(context);
    final profileProvider = Provider.of<ProfileProvider>(context);
    final themeColor = profileProvider.themeColor;

    final filteredStaff =
        (_showDeleted ? staffProvider.deletedStaff : staffProvider.staffList)
            .where((s) {
              final matchesSearch =
                  s.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
                  s.role.toLowerCase().contains(_searchQuery.toLowerCase());
              return matchesSearch;
            })
            .toList();

    return Scaffold(
      backgroundColor: profileProvider.scaffoldColor,
      body: CustomScrollView(
        controller: _scrollController,
        slivers: [
          SliverToBoxAdapter(
            child: SafeArea(
              bottom: false,
              child: _buildTopSummaryCard(staffProvider, profileProvider),
            ),
          ),
          SliverPersistentHeader(
            pinned: true,
            delegate: _StickySearchBarDelegate(
              profileProvider: profileProvider,
              child: Container(
                color: profileProvider.scaffoldColor,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        onChanged: (val) => setState(() => _searchQuery = val),
                        decoration: InputDecoration(
                          hintText: 'Search staff by name or role...',
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
                          filled: true,
                          fillColor: profileProvider.cardColor,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(15),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 0,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Tooltip(
                      message: _showDeleted ? 'Show Active' : 'Show Removed',
                      child: InkWell(
                        onTap: () =>
                            setState(() => _showDeleted = !_showDeleted),
                        borderRadius: BorderRadius.circular(15),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: _showDeleted
                                ? Colors.red
                                : profileProvider.themeColor.withValues(
                                    alpha: 0.1,
                                  ),
                            borderRadius: BorderRadius.circular(15),
                            boxShadow: _showDeleted
                                ? [
                                    BoxShadow(
                                      color: Colors.red.withValues(alpha: 0.3),
                                      blurRadius: 10,
                                      offset: const Offset(0, 4),
                                    ),
                                  ]
                                : [],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _showDeleted
                                    ? Icons.delete_sweep_rounded
                                    : Icons.group_outlined,
                                color: _showDeleted
                                    ? Colors.white
                                    : profileProvider.themeColor,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                _showDeleted ? "TRASH" : "ACTIVE",
                                style: TextStyle(
                                  color: _showDeleted
                                      ? Colors.white
                                      : profileProvider.themeColor,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 10,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (filteredStaff.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      _searchQuery.isNotEmpty
                          ? Icons.search_off
                          : Icons.people_outline,
                      size: 80,
                      color: profileProvider.secondaryTextColor.withValues(
                        alpha: 0.2,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _searchQuery.isNotEmpty
                          ? 'No staff found for "$_searchQuery"'
                          : 'No staff members added',
                      style: TextStyle(
                        color: profileProvider.secondaryTextColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate((context, index) {
                  final staff = filteredStaff[index];
                  final payable = staffProvider.calculatePayable(staff);
                  final nextSalaryDate = staffProvider.calculateNextSalaryDate(
                    staff.joinDate,
                  );
                  final isExpanded = _expandedIndex == index;

                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    elevation: 0,
                    color: profileProvider.cardColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                      side: BorderSide(
                        color: profileProvider.isDarkMode
                            ? Colors.white10
                            : Colors.grey.shade200,
                      ),
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: () => setState(
                        () => _expandedIndex = isExpanded ? null : index,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: AnimatedSize(
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeInOut,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(2),
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: themeColor.withValues(
                                          alpha: 0.2,
                                        ),
                                        width: 1.5,
                                      ),
                                    ),
                                    child: CircleAvatar(
                                      radius: 22,
                                      backgroundColor: themeColor.withValues(
                                        alpha: 0.1,
                                      ),
                                      backgroundImage:
                                          (staff.imagePath != null &&
                                              File(
                                                staff.imagePath!,
                                              ).existsSync())
                                          ? FileImage(File(staff.imagePath!))
                                          : (staff.imageUrl != null &&
                                                staff.imageUrl!.isNotEmpty)
                                          ? (staff.imageUrl!.startsWith(
                                                  'base64:',
                                                )
                                                ? MemoryImage(
                                                    base64Decode(
                                                      staff.imageUrl!
                                                          .replaceFirst(
                                                            'base64:',
                                                            '',
                                                          ),
                                                    ),
                                                  )
                                                : NetworkImage(staff.imageUrl!)
                                                      as ImageProvider)
                                          : null,
                                      child:
                                          (staff.imagePath == null ||
                                                  !File(
                                                    staff.imagePath!,
                                                  ).existsSync()) &&
                                              (staff.imageUrl == null ||
                                                  staff.imageUrl!.isEmpty)
                                          ? Icon(
                                              Icons.person,
                                              color: themeColor,
                                              size: 24,
                                            )
                                          : null,
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          staff.name,
                                          style: TextStyle(
                                            fontWeight: FontWeight.w900,
                                            fontSize: 17,
                                            color: staff.isDeleted == 1
                                                ? Colors.grey
                                                : profileProvider.textColor,
                                            letterSpacing: 0.3,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Row(
                                          children: [
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 8,
                                                    vertical: 3,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: _getRoleColor(
                                                  staff.role,
                                                  themeColor,
                                                ).withValues(alpha: 0.15),
                                                borderRadius:
                                                    BorderRadius.circular(6),
                                                border: Border.all(
                                                  color: _getRoleColor(
                                                    staff.role,
                                                    themeColor,
                                                  ).withValues(alpha: 0.3),
                                                  width: 0.5,
                                                ),
                                              ),
                                              child: Text(
                                                staff.role.toUpperCase(),
                                                style: TextStyle(
                                                  color: _getRoleColor(
                                                    staff.role,
                                                    themeColor,
                                                  ),
                                                  fontSize: 9,
                                                  fontWeight: FontWeight.w900,
                                                  letterSpacing: 0.5,
                                                ),
                                              ),
                                            ),
                                            if (staff.isDeleted == 1) ...[
                                              const SizedBox(width: 8),
                                              const Text(
                                                '(DELETED)',
                                                style: TextStyle(
                                                  color: Colors.red,
                                                  fontSize: 8,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ],
                                            // Upcoming Leave Alert Logic
                                            Builder(
                                              builder: (context) {
                                                final now = DateTime.now();
                                                return FutureBuilder<
                                                  List<StaffLeaveModel>
                                                >(
                                                  future: staffProvider
                                                      .getStaffLeaves(
                                                        staff.id!,
                                                      ),
                                                  builder: (context, snapshot) {
                                                    final leaves =
                                                        snapshot.data ?? [];
                                                    final upcoming = leaves
                                                        .where(
                                                          (l) =>
                                                              l.date.isAfter(
                                                                now,
                                                              ) &&
                                                              l.date.isBefore(
                                                                now.add(
                                                                  const Duration(
                                                                    days: 3,
                                                                  ),
                                                                ),
                                                              ),
                                                        );
                                                    if (upcoming.isNotEmpty) {
                                                      return Padding(
                                                        padding:
                                                            const EdgeInsets.only(
                                                              left: 8.0,
                                                            ),
                                                        child: Icon(
                                                          Icons
                                                              .warning_amber_rounded,
                                                          size: 14,
                                                          color: Colors
                                                              .orange
                                                              .shade700,
                                                        ),
                                                      );
                                                    }
                                                    return const SizedBox.shrink();
                                                  },
                                                );
                                              },
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (!isExpanded)
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.end,
                                      children: [
                                        // Owner Login Toggle
                                        Switch.adaptive(
                                          value: staff.isLoginEnabled,
                                          activeColor: themeColor,
                                          onChanged: (val) {
                                            staffProvider.updateStaffLoginDetails(
                                              staff.id!,
                                              val,
                                              staff.staffCode,
                                              staff.loginPin,
                                              staff.permissions
                                            );
                                          },
                                        ),
                                        Text(
                                          'Net Pay',
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: profileProvider
                                                .secondaryTextColor,
                                          ),
                                        ),
                                        Text(
                                          '₹${payable.toStringAsFixed(0)}',
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                            color: staff.isDeleted == 1
                                                ? Colors.grey
                                                : Colors.green,
                                          ),
                                        ),
                                      ],
                                    ),
                                  const SizedBox(width: 8),
                                  Icon(
                                    isExpanded
                                        ? Icons.keyboard_arrow_up
                                        : Icons.keyboard_arrow_down,
                                    color: profileProvider.secondaryTextColor,
                                    size: 20,
                                  ),
                                ],
                              ),
                              if (isExpanded) ...[
                                const Divider(height: 20),
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: Column(
                                        children: [
                                          GridView.count(
                                            shrinkWrap: true,
                                            physics:
                                                const NeverScrollableScrollPhysics(),
                                            crossAxisCount: 2,
                                            mainAxisSpacing: 8,
                                            crossAxisSpacing: 8,
                                            childAspectRatio: 2.8,
                                            children: [
                                              _staffInfoTile(
                                                'Base Salary',
                                                '₹${staff.monthlySalary.toStringAsFixed(0)}',
                                                Icons.payments_outlined,
                                                Colors.blue,
                                                profileProvider,
                                              ),
                                              _staffInfoTile(
                                                'Total Leaves',
                                                '${staff.totalLeaves} Days',
                                                Icons.event_busy_outlined,
                                                Colors.orange,
                                                profileProvider,
                                              ),
                                              InkWell(
                                                onTap: staff.isDeleted == 1
                                                    ? null
                                                    : () =>
                                                          _showAdvanceHistorySheet(
                                                            context,
                                                            staff,
                                                          ),
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                                child: _staffInfoTile(
                                                  'Advance Taken',
                                                  '₹${staff.advance.toStringAsFixed(0)}',
                                                  Icons
                                                      .account_balance_wallet_outlined,
                                                  Colors.red,
                                                  profileProvider,
                                                ),
                                              ),
                                              _staffInfoTile(
                                                'Pay Date',
                                                DateFormat(
                                                  'dd MMM',
                                                ).format(nextSalaryDate),
                                                Icons.calendar_month_outlined,
                                                Colors.purple,
                                                profileProvider,
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 10,
                                              vertical: 6,
                                            ),
                                            decoration: BoxDecoration(
                                              color:
                                                  (staff.isDeleted == 1
                                                          ? Colors.grey
                                                          : Colors.green)
                                                      .withValues(alpha: 0.1),
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                            ),
                                            child: Row(
                                              children: [
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    children: [
                                                      Text(
                                                        'NET PAYABLE',
                                                        style: TextStyle(
                                                          fontSize: 8,
                                                          fontWeight: FontWeight.bold,
                                                          color: staff.isDeleted == 1
                                                              ? Colors.grey
                                                              : Colors.green.shade800,
                                                          letterSpacing: 0.5,
                                                        ),
                                                      ),
                                                      Text(
                                                        '₹${payable.toStringAsFixed(0)}',
                                                        style: TextStyle(
                                                          fontSize: 14,
                                                          fontWeight: FontWeight.bold,
                                                          color: staff.isDeleted == 1
                                                              ? Colors.grey
                                                              : Colors.green.shade800,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                if (payable > 0 && staff.isDeleted == 0)
                                                  TextButton.icon(
                                                    onPressed: () => _showSettleStaffConfirm(
                                                      context,
                                                      staffProvider,
                                                      staff,
                                                      payable,
                                                    ),
                                                    icon: const Icon(Icons.check_circle, size: 16),
                                                    label: const Text(
                                                      'SETTLE',
                                                      style: TextStyle(
                                                        fontSize: 10,
                                                        fontWeight: FontWeight.bold,
                                                      ),
                                                    ),
                                                    style: TextButton.styleFrom(
                                                      foregroundColor: Colors.green.shade800,
                                                      padding: const EdgeInsets.symmetric(horizontal: 12),
                                                      backgroundColor: Colors.white.withValues(alpha: 0.5),
                                                      shape: RoundedRectangleBorder(
                                                        borderRadius: BorderRadius.circular(8),
                                                      ),
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      width: 44,
                                      height: staff.isDeleted == 1 ? 110 : 155,
                                      decoration: BoxDecoration(
                                        color: profileProvider.scaffoldColor
                                            .withValues(alpha: 0.5),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceEvenly,
                                        children: [
                                          if (staff.isDeleted == 0) ...[
                                            _actionBtn(
                                              Icons.calendar_month_rounded,
                                              Colors.orange,
                                              () => _showLeaveCalendarSheet(
                                                context,
                                                staff,
                                              ),
                                            ),
                                            _actionBtn(
                                              Icons.edit_outlined,
                                              Colors.blue,
                                              () => _showStaffBottomSheet(
                                                context,
                                                staff: staff,
                                              ),
                                            ),
                                            _actionBtn(
                                              Icons.delete_outline,
                                              Colors.red,
                                              () => _showActionConfirm(
                                                context,
                                                staffProvider,
                                                staff,
                                              ),
                                            ),
                                          ] else ...[
                                            _actionBtn(
                                              Icons.restore,
                                              Colors.green,
                                              () => staffProvider.restoreStaff(
                                                staff.id!,
                                              ),
                                            ),
                                            _actionBtn(
                                              Icons.delete_forever,
                                              Colors.red,
                                              () => _showPermanentDeleteConfirm(
                                                context,
                                                staffProvider,
                                                staff,
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }, childCount: filteredStaff.length),
              ),
            ),
        ],
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
        decoration: BoxDecoration(
          color: profileProvider.cardColor,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, -5),
            ),
          ],
          borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
        ),
        child: SafeArea(
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: themeColor,
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 55),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
              ),
              elevation: 0,
            ),
            onPressed: () => _showStaffBottomSheet(context),
            icon: const Icon(Icons.person_add_alt_1),
            label: const Text(
              'ADD NEW STAFF',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
          ),
        ),
      ),
    );
  }

  Widget _actionBtn(IconData icon, Color color, VoidCallback? onTap) {
    return IconButton(
      icon: Icon(
        icon,
        color: onTap == null ? Colors.grey.withValues(alpha: 0.3) : color,
        size: 18,
      ),
      onPressed: onTap,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
    );
  }

  Widget _actionChip(String label, IconData icon, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 14),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _exportPayrollReport(BuildContext context, StaffProvider provider, ProfileProvider profile) async {
    final exportService = ExportService();
    await exportService.generateMonthlyPayrollReport(
      profile.businessName,
      provider.staffList,
      provider.selectedMonth,
    );
  }

  void _showSettleAllConfirm(BuildContext context, StaffProvider provider) async {
    final profile = Provider.of<ProfileProvider>(context, listen: false);
    final confirmed = await AppBottomSheet.showAction(
      context: context,
      profile: profile,
      title: 'Settle All Staff?',
      message: 'This will mark all current net payables as settled for ${DateFormat('MMMM yyyy').format(provider.selectedMonth)}. Are you sure?',
      confirmLabel: 'SETTLE ALL',
      isDestructive: false,
    );

    if (confirmed == true) {
      for (var staff in provider.staffList) {
        final payable = provider.calculatePayable(staff);
        if (payable > 0) {
          await provider.settleMonth(staff.id!, provider.selectedMonth, payable);
        }
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('All staff settled successfully')),
        );
      }
    }
  }

  void _showSettleStaffConfirm(
    BuildContext context,
    StaffProvider provider,
    StaffModel staff,
    double payable,
  ) async {
    final profile = Provider.of<ProfileProvider>(context, listen: false);
    final confirmed = await AppBottomSheet.showAction(
      context: context,
      profile: profile,
      title: 'Settle ${staff.name}?',
      message: 'Confirm payment of ₹${payable.toStringAsFixed(0)} for ${DateFormat('MMMM yyyy').format(provider.selectedMonth)}.',
      confirmLabel: 'CONFIRM PAYMENT',
      isDestructive: false,
    );

    if (confirmed == true) {
      await provider.settleMonth(staff.id!, provider.selectedMonth, payable);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Settled ${staff.name} successfully')),
        );
      }
    }
  }

  Widget _buildTopSummaryCard(StaffProvider provider, ProfileProvider profile) {
    final themeColor = profile.themeColor;
    return ListenableBuilder(
      listenable: _scrollController,
      builder: (context, child) {
        double offset = 0;
        if (_scrollController.hasClients) {
          offset = _scrollController.offset;
        }
        double opacity = (1.0 - (offset / 100)).clamp(0.0, 1.0);

        return Opacity(
          opacity: opacity,
          child: Container(
            height: 200, // Increased height for month navigation and actions
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [themeColor.withValues(alpha: 0.8), themeColor],
              ),
              borderRadius: BorderRadius.circular(24),
              boxShadow: profile.themeShadow,
            ),
            child: opacity > 0.1
                ? Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Month Navigation Row
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.arrow_back_ios, color: Colors.white, size: 18),
                            onPressed: () {
                              final prevMonth = DateTime(
                                provider.selectedMonth.year,
                                provider.selectedMonth.month - 1,
                              );
                              provider.setSelectedMonth(prevMonth);
                            },
                          ),
                          Text(
                            DateFormat('MMMM yyyy').format(provider.selectedMonth).toUpperCase(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 16,
                              letterSpacing: 1,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.arrow_forward_ios, color: Colors.white, size: 18),
                            onPressed: () {
                              final nextMonth = DateTime(
                                provider.selectedMonth.year,
                                provider.selectedMonth.month + 1,
                              );
                              provider.setSelectedMonth(nextMonth);
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      Divider(
                        color: Colors.white.withValues(alpha: 0.2),
                        height: 1,
                      ),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _summaryItem(
                            'Active Workers',
                            '${provider.staffList.length}',
                            Colors.white,
                            Colors.white70,
                          ),
                          _summaryItem(
                            'Total Net Payable',
                            '₹${provider.totalNetPayable.toStringAsFixed(0)}',
                            Colors.white,
                            Colors.white70,
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _actionChip(
                            'PAYROLL REPORT',
                            Icons.summarize_outlined,
                            Colors.white,
                            () => _exportPayrollReport(context, provider, profile),
                          ),
                          if (provider.totalNetPayable > 0) ...[
                            const SizedBox(width: 12),
                            _actionChip(
                              'SETTLE ALL',
                              Icons.check_circle_outline,
                              Colors.white,
                              () => _showSettleAllConfirm(context, provider),
                            ),
                          ],
                        ],
                      ),
                    ],
                  )
                : const SizedBox.shrink(),
          ),
        );
      },
    );
  }

  Widget _summaryItem(
    String label,
    String value,
    Color valueColor,
    Color labelColor, {
    bool isCenter = false,
  }) {
    return Column(
      crossAxisAlignment: isCenter
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: labelColor, fontSize: 11)),
        Text(
          value,
          style: TextStyle(
            color: valueColor,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _staffInfoTile(
    String label,
    String value,
    IconData icon,
    Color color,
    ProfileProvider profile,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: profile.scaffoldColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: profile.isDarkMode ? Colors.white10 : Colors.grey.shade100,
        ),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 8,
                    color: profile.secondaryTextColor,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: profile.textColor,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showLeaveCalendarSheet(BuildContext context, StaffModel staff) {
    final profile = Provider.of<ProfileProvider>(context, listen: false);
    AppBottomSheet.show(
      context: context,
      profile: profile,
      title: 'Leave: ${staff.name}',
      child: _LeaveCalendarWidget(
        staff: staff,
        profile: profile,
        themeColor: profile.themeColor,
      ),
    );
  }

  void _showActionConfirm(
    BuildContext context,
    StaffProvider provider,
    StaffModel staff,
  ) async {
    final profile = Provider.of<ProfileProvider>(context, listen: false);
    final isDeleting = staff.isDeleted == 0;

    final confirmed = await AppBottomSheet.showAction(
      context: context,
      profile: profile,
      title: isDeleting ? 'Remove Staff?' : 'Restore Staff?',
      message: isDeleting
          ? 'Are you sure you want to remove "${staff.name}"? They will no longer appear in active totals.'
          : 'Do you want to restore "${staff.name}" to active staff list?',
      confirmLabel: isDeleting ? 'REMOVE' : 'RESTORE',
      isDestructive: isDeleting,
    );

    if (confirmed == true) {
      if (isDeleting) {
        provider.softDeleteStaff(staff.id!);
      } else {
        provider.restoreStaff(staff.id!);
      }
    }
  }

  void _showPermanentDeleteConfirm(
    BuildContext context,
    StaffProvider provider,
    StaffModel staff,
  ) async {
    final profile = Provider.of<ProfileProvider>(context, listen: false);

    final confirmed = await AppBottomSheet.showAction(
      context: context,
      profile: profile,
      title: 'Permanent Delete?',
      message:
          'Are you sure you want to permanently delete "${staff.name}"? This action will also delete all their leave and advance history and cannot be undone.',
      confirmLabel: 'DELETE FOREVER',
      isDestructive: true,
    );

    if (confirmed == true) {
      provider.permanentDeleteStaff(staff.id!);
    }
  }

  void _showAdvanceHistorySheet(BuildContext context, StaffModel staff) {
    final profileProvider = Provider.of<ProfileProvider>(
      context,
      listen: false,
    );
    final themeColor = profileProvider.themeColor;
    final advanceController = TextEditingController();

    AppBottomSheet.show(
      context: context,
      profile: profileProvider,
      title: 'Advance: ${staff.name}',
      child: StatefulBuilder(
        builder: (ctx, setStateSheet) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: profileProvider.scaffoldColor,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: themeColor.withValues(alpha: 0.1)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: advanceController,
                        keyboardType: TextInputType.number,
                        style: TextStyle(
                          color: profileProvider.textColor,
                          fontWeight: FontWeight.bold,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Enter amount...',
                          hintStyle: TextStyle(
                            color: profileProvider.secondaryTextColor
                                .withValues(alpha: 0.5),
                          ),
                          prefixIcon: Icon(
                            Icons.currency_rupee_rounded,
                            color: themeColor,
                          ),
                          border: InputBorder.none,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      onPressed: () async {
                        final amount =
                            double.tryParse(advanceController.text) ?? 0;
                        if (amount > 0) {
                          await Provider.of<StaffProvider>(
                            context,
                            listen: false,
                          ).addAdvance(staff.id!, amount);
                          advanceController.clear();
                          setStateSheet(() {}); // Refresh local UI
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: themeColor,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                      child: const Text(
                        'ADD',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'RECENT HISTORY',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  color: Colors.grey,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: Consumer<StaffProvider>(
                  builder: (context, provider, _) {
                    return FutureBuilder<List<StaffAdvanceModel>>(
                      future: provider.getStaffAdvances(staff.id!),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
                          return const Center(child: CircularProgressIndicator());
                        }
                        
                        final advances = snapshot.data ?? [];
                        if (advances.isEmpty) {
                          return Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.history, size: 48, color: profileProvider.secondaryTextColor.withValues(alpha: 0.2)),
                                const SizedBox(height: 8),
                                Text(
                                  'No history found',
                                  style: TextStyle(color: profileProvider.secondaryTextColor),
                                ),
                              ],
                            ),
                          );
                        }
                        return ListView.builder(
                          itemCount: advances.length,
                          padding: EdgeInsets.zero,
                          itemBuilder: (context, index) {
                            final adv = advances[index];
                            final isSettled = adv.status == 'settled';
                            return Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              decoration: BoxDecoration(
                                color: profileProvider.cardColor,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isSettled ? Colors.green.withValues(alpha: 0.1) : Colors.transparent,
                                ),
                              ),
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: (isSettled ? Colors.green : Colors.red).withValues(alpha: 0.1),
                                  child: Icon(
                                    isSettled ? Icons.check_circle_outline : Icons.arrow_downward,
                                    color: isSettled ? Colors.green : Colors.red,
                                    size: 16,
                                  ),
                                ),
                                title: Text(
                                  '${profileProvider.currencySymbol}${adv.amount.toStringAsFixed(0)}',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: isSettled ? Colors.green : profileProvider.textColor,
                                  ),
                                ),
                                subtitle: Text(
                                  DateFormat('dd MMM yyyy, hh:mm a').format(adv.date),
                                  style: const TextStyle(fontSize: 11),
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (isSettled)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.green.withValues(alpha: 0.1),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: const Text('SETTLED', style: TextStyle(fontSize: 9, color: Colors.green, fontWeight: FontWeight.bold)),
                                      ),
                                    if (!isSettled)
                                      IconButton(
                                        icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                                        onPressed: () => _confirmDeleteAdvance(context, provider, adv),
                                      ),
                                  ],
                                ),
                              ),
                            );
                          },
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),

        ),
      ),
    );
  }

  void _confirmDeleteAdvance(
    BuildContext context,
    StaffProvider provider,
    StaffAdvanceModel advance,
  ) async {
    final profile = Provider.of<ProfileProvider>(context, listen: false);
    final confirmed = await AppBottomSheet.showAction(
      context: context,
      profile: profile,
      title: 'Delete Advance?',
      message: 'This will remove this record permanently.',
      confirmLabel: 'DELETE',
      isDestructive: true,
    );
    if (confirmed == true) {
      await provider.deleteAdvance(advance.id!);
    }
  }

  void _showStaffBottomSheet(BuildContext context, {StaffModel? staff}) {
    final staffProvider = Provider.of<StaffProvider>(context, listen: false);
    final profileProvider = Provider.of<ProfileProvider>(
      context,
      listen: false,
    );
    final themeColor = profileProvider.themeColor;
    final nameController = TextEditingController(text: staff?.name);
    final salaryController = TextEditingController(
      text: staff?.monthlySalary.toStringAsFixed(0),
    );
    final advanceController = TextEditingController(
      text: staff?.advance.toStringAsFixed(0),
    );
    final contactController = TextEditingController(text: staff?.contact);
    String selectedRole = staff?.role ?? 'Staff';
    final List<String> roles = [
      'Staff',
      'Waiter',
      'Chef',
      'Manager',
      'Cleaner',
      'Security',
    ];
    DateTime selectedDate = staff?.joinDate ?? DateTime.now();
    String? currentImagePath = staff?.imagePath;

    // Login Control State
    bool _loginEnabled = staff?.isLoginEnabled ?? false;
    final _codeController = TextEditingController(text: staff?.staffCode);
    final _pinController = TextEditingController(text: staff?.loginPin);
    Map<String, dynamic> _tempPermissions = jsonDecode(staff?.permissions ?? '{"can_sale":true,"can_stock":false,"can_reports":false,"can_manage_staff":false}');

    AppBottomSheet.show(
      context: context,
      profile: profileProvider,
      title: staff == null ? 'Add New Staff' : 'Edit Staff Details',
      child: StatefulBuilder(
        builder: (ctx, setStateSheet) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 8),
                Center(
                  child: Stack(
                    children: [
                      CircleAvatar(
                        radius: 50,
                        backgroundColor: themeColor.withValues(alpha: 0.1),
                        backgroundImage:
                            (currentImagePath != null &&
                                File(currentImagePath!).existsSync())
                            ? FileImage(File(currentImagePath!))
                            : (staff?.imageUrl != null &&
                                  staff!.imageUrl!.isNotEmpty)
                            ? (staff.imageUrl!.startsWith('base64:')
                                  ? MemoryImage(
                                      base64Decode(
                                        staff.imageUrl!.replaceFirst(
                                          'base64:',
                                          '',
                                        ),
                                      ),
                                    )
                                  : NetworkImage(staff.imageUrl!)
                                        as ImageProvider)
                            : null,
                        child:
                            (currentImagePath == null ||
                                    !File(currentImagePath!).existsSync()) &&
                                (staff?.imageUrl == null ||
                                    staff?.imageUrl == "")
                            ? Icon(Icons.person, size: 50, color: themeColor)
                            : null,
                      ),
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: GestureDetector(
                          onTap: () async {
                            final String? croppedPath =
                                await ImageHelper.pickAndCropItemIcon(
                                  context: context,
                                  themeColor: themeColor,
                                  isCircle: true,
                                );
                            if (croppedPath != null) {
                              setStateSheet(
                                () => currentImagePath = croppedPath,
                              );
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: themeColor,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                            ),
                            child: const Icon(
                              Icons.camera_alt,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                _sheetTextField(
                  nameController,
                  'Staff Full Name',
                  Icons.person_outline,
                  profileProvider,
                ),
                const SizedBox(height: 16),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: roles.map((role) {
                      final isSelected = selectedRole == role;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(role),
                          selected: isSelected,
                          onSelected: (val) =>
                              setStateSheet(() => selectedRole = role),
                          selectedColor: themeColor,
                          labelStyle: TextStyle(
                            color: isSelected
                                ? Colors.white
                                : profileProvider.textColor,
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                          backgroundColor: profileProvider.scaffoldColor,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide.none,
                          ),
                          showCheckmark: false,
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _sheetTextField(
                        salaryController,
                        'Monthly Salary',
                        Icons.payments_outlined,
                        profileProvider,
                        isNumber: true,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _sheetTextField(
                        advanceController,
                        'Initial Advance',
                        Icons.account_balance_wallet_outlined,
                        profileProvider,
                        isNumber: true,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _sheetTextField(
                  contactController,
                  'Contact Number',
                  Icons.phone_android_outlined,
                  profileProvider,
                  isNumber: true,
                ),
                const SizedBox(height: 20),
                InkWell(
                  onTap: () async {
                    final date = await ReportHelper.showAppDatePicker(
                      context,
                      selectedDate,
                      themeColor,
                      lastDate: DateTime.now(),
                    );
                    if (date != null) setStateSheet(() => selectedDate = date);
                  },
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: profileProvider.scaffoldColor,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.calendar_month_outlined, color: themeColor),
                        const SizedBox(width: 12),
                        Text(
                          DateFormat('dd MMMM yyyy').format(selectedDate),
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                _buildLoginControlSection(
                  setStateSheet,
                  profileProvider,
                  themeColor,
                  _loginEnabled,
                  _codeController,
                  _pinController,
                  _tempPermissions,
                ),
                const SizedBox(height: 32),
                ElevatedButton(
                  onPressed: () {
                    if (nameController.text.isNotEmpty) {
                      final newStaff = StaffModel(
                        id: staff?.id,
                        name: nameController.text,
                        role: selectedRole,
                        monthlySalary:
                            double.tryParse(salaryController.text) ?? 0,
                        advance: double.tryParse(advanceController.text) ?? 0,
                        joinDate: selectedDate,
                        contact: contactController.text,
                        totalLeaves: staff?.totalLeaves ?? 0,
                        imagePath: currentImagePath,
                        isDeleted: staff?.isDeleted ?? 0,
                        isLoginEnabled: _loginEnabled,
                        staffCode: _codeController.text,
                        loginPin: _pinController.text,
                        permissions: jsonEncode(_tempPermissions),
                      );
                      if (staff == null) {
                        staffProvider.addStaff(newStaff);
                      } else {
                        staffProvider.updateStaff(newStaff);
                      }
                      Navigator.pop(ctx);
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: themeColor,
                    minimumSize: const Size(double.infinity, 60),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  child: Text(
                    staff == null ? 'ADD STAFF MEMBER' : 'UPDATE DETAILS',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoginControlSection(
    StateSetter setStateSheet,
    ProfileProvider profileProvider,
    Color themeColor,
    bool loginEnabled,
    TextEditingController codeController,
    TextEditingController pinController,
    Map<String, dynamic> permissions,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: profileProvider.themeColor.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: themeColor.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.lock_outline_rounded, color: themeColor, size: 20),
                  const SizedBox(width: 8),
                  const Text('Staff Login Access',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
              Switch.adaptive(
                value: loginEnabled,
                activeColor: themeColor,
                onChanged: (val) => setStateSheet(() => loginEnabled = val),
              ),
            ],
          ),
          if (loginEnabled) ...[
            const Divider(height: 24),
            Row(
              children: [
                Expanded(
                  child: _sheetTextField(
                    codeController,
                    'Staff Code',
                    Icons.badge_outlined,
                    profileProvider,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _sheetTextField(
                    pinController,
                    'Login PIN',
                    Icons.pin_outlined,
                    profileProvider,
                    isNumber: true,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text('PERMISSIONS',
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey,
                    letterSpacing: 1)),
            const SizedBox(height: 8),
            _permissionToggle(
                'Can add Sales',
                permissions['can_sale'] ?? false,
                (v) => setStateSheet(() => permissions['can_sale'] = v),
                themeColor),
            _permissionToggle(
                'Can view Stock',
                permissions['can_stock'] ?? false,
                (v) => setStateSheet(() => permissions['can_stock'] = v),
                themeColor),
            _permissionToggle(
                'Can view Reports',
                permissions['can_reports'] ?? false,
                (v) => setStateSheet(() => permissions['can_reports'] = v),
                themeColor),
            _permissionToggle(
                'Can manage Staff',
                permissions['can_manage_staff'] ?? false,
                (v) => setStateSheet(() => permissions['can_manage_staff'] = v),
                themeColor),
          ],
        ],
      ),
    );
  }

  Widget _permissionToggle(String label, bool value, Function(bool) onChanged, Color themeColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 13)),
          Transform.scale(
            scale: 0.8,
            child: Switch.adaptive(
              value: value,
              activeColor: themeColor,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }

  Widget _sheetTextField(
    TextEditingController controller,
    String label,
    IconData icon,
    ProfileProvider profile, {
    bool isNumber = false,
  }) {
    return TextField(
      controller: controller,
      keyboardType: isNumber ? TextInputType.number : TextInputType.text,
      style: TextStyle(color: profile.textColor),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: profile.themeColor),
        filled: true,
        fillColor: profile.scaffoldColor,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}

class _StickySearchBarDelegate extends SliverPersistentHeaderDelegate {
  final ProfileProvider profileProvider;
  final Widget child;

  _StickySearchBarDelegate({
    required this.profileProvider,
    required this.child,
  });

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Container(
      height: 60,
      decoration: BoxDecoration(
        color: profileProvider.scaffoldColor,
        boxShadow: overlapsContent
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: child,
    );
  }

  @override
  double get maxExtent => 60;
  @override
  double get minExtent => 60;
  @override
  bool shouldRebuild(covariant SliverPersistentHeaderDelegate oldDelegate) =>
      true;
}

class _LeaveCalendarWidget extends StatefulWidget {
  final StaffModel staff;
  final ProfileProvider profile;
  final Color themeColor;

  const _LeaveCalendarWidget({
    required this.staff,
    required this.profile,
    required this.themeColor,
  });

  @override
  State<_LeaveCalendarWidget> createState() => _LeaveCalendarWidgetState();
}

class _LeaveCalendarWidgetState extends State<_LeaveCalendarWidget> {
  DateTime _focusedDay = DateTime.now();
  List<StaffLeaveModel> _leaves = [];

  @override
  void initState() {
    super.initState();
    _loadLeaves();
  }

  Future<void> _loadLeaves() async {
    final provider = Provider.of<StaffProvider>(context, listen: false);
    final leaves = await provider.getStaffLeaves(widget.staff.id!);
    if (mounted) setState(() => _leaves = leaves);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TableCalendar(
          firstDay: widget.staff.joinDate, // Allow scrolling back to join date
          lastDay: DateTime.now().add(const Duration(days: 365)),
          focusedDay: _focusedDay,
          calendarFormat: CalendarFormat.month,
          headerStyle: HeaderStyle(
            formatButtonVisible: false,
            titleCentered: true,
            titleTextStyle: TextStyle(
              fontWeight: FontWeight.bold,
              color: widget.profile.textColor,
            ),
          ),
          calendarStyle: CalendarStyle(
            defaultTextStyle: TextStyle(color: widget.profile.textColor),
            todayDecoration: BoxDecoration(
              color: widget.themeColor.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            todayTextStyle: TextStyle(
              color: widget.themeColor,
              fontWeight: FontWeight.bold,
            ),
          ),
          onPageChanged: (focusedDay) =>
              setState(() => _focusedDay = focusedDay),
          calendarBuilders: CalendarBuilders(
            defaultBuilder: (context, day, focusedDay) => _buildDayCell(day),
            todayBuilder: (context, day, focusedDay) =>
                _buildDayCell(day, isToday: true),
          ),
          onDaySelected: (selectedDay, focusedDay) async {
            final provider = Provider.of<StaffProvider>(context, listen: false);
            await provider.toggleLeave(widget.staff.id!, selectedDay);
            await _loadLeaves();
          },
        ),
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _legendItem('Leave', Colors.red),
            _legendItem('Half Day', Colors.orange),
            _legendItem('Present', Colors.grey),
          ],
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildDayCell(DateTime day, {bool isToday = false}) {
    final leave = _leaves.firstWhere(
      (l) => isSameDay(l.date, day),
      orElse: () => StaffLeaveModel(staffId: -1, date: day, type: 0),
    );
    Color? bgColor;
    Color textColor = widget.profile.textColor;
    if (leave.type == 1.0) {
      bgColor = Colors.red;
      textColor = Colors.white;
    } else if (leave.type == 0.5) {
      bgColor = Colors.orange;
      textColor = Colors.white;
    } else if (isToday) {
      bgColor = widget.themeColor.withValues(alpha: 0.15);
      textColor = widget.themeColor;
    }

    return Container(
      margin: const EdgeInsets.all(4),
      alignment: Alignment.center,
      decoration: BoxDecoration(color: bgColor, shape: BoxShape.circle),
      child: Text(
        '${day.day}',
        style: TextStyle(
          color: textColor,
          fontWeight: (isToday || leave.type > 0)
              ? FontWeight.bold
              : FontWeight.normal,
        ),
      ),
    );
  }

  Widget _legendItem(String label, Color color) {
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: widget.profile.secondaryTextColor,
          ),
        ),
      ],
    );
  }
}
