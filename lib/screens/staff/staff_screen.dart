import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:flutter/rendering.dart';
import '../../providers/staff_provider.dart';
import '../../models/staff_model.dart';
import '../../providers/profile_provider.dart';
import '../../utils/app_strings.dart';

class StaffScreen extends StatefulWidget {
  const StaffScreen({super.key});

  @override
  State<StaffScreen> createState() => _StaffScreenState();
}

class _StaffScreenState extends State<StaffScreen> {
  final ScrollController _scrollController = ScrollController();
  bool _isFabVisible = true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(() {
      if (_scrollController.position.userScrollDirection == ScrollDirection.reverse) {
        if (_isFabVisible) setState(() => _isFabVisible = false);
      } else if (_scrollController.position.userScrollDirection == ScrollDirection.forward) {
        if (!_isFabVisible) setState(() => _isFabVisible = true);
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final staffProvider = Provider.of<StaffProvider>(context);
    final profileProvider = Provider.of<ProfileProvider>(context);
    final themeColor = profileProvider.themeColor;

    return Scaffold(
      backgroundColor: profileProvider.scaffoldColor,
      appBar: AppBar(
        title: const Text('STAFF MANAGEMENT', 
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: Colors.white)),
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [themeColor.withOpacity(0.8), themeColor],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        elevation: 0,
        centerTitle: true,
      ),
      body: Column(
        children: [
          _buildTopSummaryCard(staffProvider, profileProvider),
          Expanded(
            child: staffProvider.staffList.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.people_outline, size: 80, color: profileProvider.secondaryTextColor.withOpacity(0.2)),
                        const SizedBox(height: 16),
                        Text('No staff members added', style: TextStyle(color: profileProvider.secondaryTextColor, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: staffProvider.staffList.length,
                    itemBuilder: (context, index) {
                      final staff = staffProvider.staffList[index];
                      final payable = staffProvider.calculatePayable(staff);
                      final nextSalaryDate = staffProvider.calculateNextSalaryDate(staff.joinDate);

                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        elevation: 0,
                        color: profileProvider.cardColor,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                          side: BorderSide(color: profileProvider.isDarkMode ? Colors.white10 : Colors.grey.shade200),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  CircleAvatar(
                                    backgroundColor: themeColor.withOpacity(0.1),
                                    child: Icon(Icons.person, color: themeColor),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(staff.name, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: profileProvider.textColor)),
                                        Text('Joined: ${DateFormat('dd MMM yyyy').format(staff.joinDate)}', 
                                          style: TextStyle(color: profileProvider.secondaryTextColor, fontSize: 11)),
                                      ],
                                    ),
                                  ),
                                  _actionBtn(Icons.event_busy_rounded, Colors.orange, () => _showLeaveDialog(context, staffProvider, staff)),
                                  _actionBtn(Icons.edit_outlined, Colors.blue, () => _showStaffBottomSheet(context, staff: staff)),
                                  _actionBtn(Icons.delete_outline, Colors.red, () => _showDeleteConfirm(context, staffProvider, staff)),
                                ],
                              ),
                              const Divider(height: 24),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  _staffInfoTile('Monthly Salary', '₹${staff.monthlySalary.toStringAsFixed(0)}', profileProvider.textColor, profileProvider),
                                  _staffInfoTile('Total Leaves', '${staff.totalLeaves} Days', Colors.orange.shade700, profileProvider, isBold: true),
                                  _staffInfoTile('Advance', '₹${staff.advance.toStringAsFixed(0)}', Colors.red, profileProvider),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  _staffInfoTile('Next Pay Date', DateFormat('dd MMM').format(nextSalaryDate), Colors.blue, profileProvider),
                                  _staffInfoTile('Net Pay (After Leaves)', '₹${payable.toStringAsFixed(0)}', Colors.green, profileProvider, isBold: true),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      bottomNavigationBar: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        height: _isFabVisible ? 95 : 0,
        child: _isFabVisible ? Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
          decoration: BoxDecoration(
            color: profileProvider.cardColor,
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, -5))],
            borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
          ),
          child: SafeArea(
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: themeColor,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 55),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                elevation: 0,
              ),
              onPressed: () => _showStaffBottomSheet(context),
              icon: const Icon(Icons.person_add_alt_1),
              label: const Text('ADD NEW STAFF', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            ),
          ),
        ) : const SizedBox.shrink(),
      ),
    );
  }

  Widget _actionBtn(IconData icon, Color color, VoidCallback onTap) {
    return IconButton(
      icon: Icon(icon, color: color, size: 20),
      onPressed: onTap,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 35),
    );
  }

  Widget _buildTopSummaryCard(StaffProvider provider, ProfileProvider profile) {
    final themeColor = profile.themeColor;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [themeColor.withOpacity(0.8), themeColor]),
        borderRadius: BorderRadius.circular(24),
        boxShadow: profile.themeShadow,
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _summaryItem('Total Workers', '${provider.staffList.length}', Colors.white, Colors.white70),
              _summaryItem('Total Base Salary', '₹${provider.totalMonthlySalary.toStringAsFixed(0)}', Colors.white, Colors.white70),
            ],
          ),
          const SizedBox(height: 16),
          Divider(color: Colors.white.withOpacity(0.2)),
          const SizedBox(height: 8),
          _summaryItem('Total Net Payable (Deducted)', '₹${provider.totalNetPayable.toStringAsFixed(0)}', Colors.white, Colors.white70, isCenter: true),
        ],
      ),
    );
  }

  Widget _summaryItem(String label, String value, Color valueColor, Color labelColor, {bool isCenter = false}) {
    return Column(
      crossAxisAlignment: isCenter ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: labelColor, fontSize: 11)),
        Text(value, style: TextStyle(color: valueColor, fontSize: 18, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _staffInfoTile(String label, String value, Color color, ProfileProvider profile, {bool isBold = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 10, color: profile.secondaryTextColor)),
        Text(value, style: TextStyle(fontSize: 13, fontWeight: isBold ? FontWeight.bold : FontWeight.w500, color: color)),
      ],
    );
  }

  void _showLeaveDialog(BuildContext context, StaffProvider provider, StaffModel staff) {
    final profile = Provider.of<ProfileProvider>(context, listen: false);
    final controller = TextEditingController(text: staff.totalLeaves.toString());
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: profile.cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text('Update Leaves', style: TextStyle(color: profile.textColor, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Current Leaves: ${staff.totalLeaves}', style: TextStyle(color: profile.secondaryTextColor, fontSize: 12)),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              autofocus: true,
              style: TextStyle(color: profile.textColor, fontWeight: FontWeight.bold),
              decoration: InputDecoration(
                labelText: 'Total Leave Days',
                labelStyle: TextStyle(color: profile.secondaryTextColor),
                filled: true,
                fillColor: profile.scaffoldColor,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 12),
            Text('Note: Update the total count. Salary will be recalculated automatically.', 
              style: TextStyle(color: profile.secondaryTextColor.withOpacity(0.6), fontSize: 10)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCEL')),
          ElevatedButton(
            onPressed: () {
              int days = int.tryParse(controller.text) ?? 0;
              provider.setLeave(staff.id!, days);
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange, 
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 0,
            ),
            child: const Text('UPDATE LEAVES', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showDeleteConfirm(BuildContext context, StaffProvider provider, StaffModel staff) {
    final profile = Provider.of<ProfileProvider>(context, listen: false);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: profile.cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text('Remove Staff?', style: TextStyle(color: profile.textColor, fontWeight: FontWeight.bold)),
        content: Text('Are you sure you want to remove "${staff.name}"?', style: TextStyle(color: profile.secondaryTextColor)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text(AppStrings.cancel)),
          TextButton(
            onPressed: () {
              provider.deleteStaff(staff.id!);
              Navigator.pop(context);
            },
            child: const Text('REMOVE', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showStaffBottomSheet(BuildContext context, {StaffModel? staff}) {
    final staffProvider = Provider.of<StaffProvider>(context, listen: false);
    final profileProvider = Provider.of<ProfileProvider>(context, listen: false);
    final themeColor = profileProvider.themeColor;
    final nameController = TextEditingController(text: staff?.name);
    final salaryController = TextEditingController(text: staff?.monthlySalary.toStringAsFixed(0));
    final advanceController = TextEditingController(text: staff?.advance.toStringAsFixed(0));
    final contactController = TextEditingController(text: staff?.contact);
    DateTime selectedDate = staff?.joinDate ?? DateTime.now();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: profileProvider.cardColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
        ),
        padding: EdgeInsets.fromLTRB(24, 24, 24, MediaQuery.of(ctx).viewInsets.bottom + 24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40, height: 4,
                  margin: const EdgeInsets.only(bottom: 24),
                  decoration: BoxDecoration(color: profileProvider.secondaryTextColor.withOpacity(0.2), borderRadius: BorderRadius.circular(2)),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(staff == null ? 'Add New Staff' : 'Edit Staff Details', 
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: profileProvider.textColor)),
                  IconButton(onPressed: () => Navigator.pop(ctx), icon: Icon(Icons.close_rounded, color: profileProvider.textColor)),
                ],
              ),
              const SizedBox(height: 20),
              _sheetTextField(nameController, 'Staff Full Name', Icons.person_outline, profileProvider),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(child: _sheetTextField(salaryController, 'Monthly Salary', Icons.payments_outlined, profileProvider, isNumber: true)),
                  const SizedBox(width: 12),
                  Expanded(child: _sheetTextField(advanceController, 'Advance (₹)', Icons.account_balance_wallet_outlined, profileProvider, isNumber: true)),
                ],
              ),
              const SizedBox(height: 16),
              _sheetTextField(contactController, 'Contact Number', Icons.phone_android_outlined, profileProvider, isNumber: true),
              const SizedBox(height: 20),
              Text('JOINING DATE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: profileProvider.secondaryTextColor, letterSpacing: 1)),
              const SizedBox(height: 8),
              StatefulBuilder(
                builder: (context, setStateSB) => InkWell(
                  onTap: () async {
                    final date = await showDatePicker(
                      context: context, 
                      initialDate: selectedDate, 
                      firstDate: DateTime(2020), 
                      lastDate: DateTime.now(),
                      builder: (context, child) {
                        return Theme(
                          data: Theme.of(context).copyWith(
                            colorScheme: profileProvider.isDarkMode 
                              ? ColorScheme.dark(primary: themeColor, onPrimary: Colors.white, surface: profileProvider.cardColor)
                              : ColorScheme.light(primary: themeColor),
                            dialogBackgroundColor: profileProvider.cardColor,
                          ),
                          child: child!,
                        );
                      }
                    );
                    if (date != null) setStateSB(() => selectedDate = date);
                  },
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: profileProvider.scaffoldColor,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: profileProvider.isDarkMode ? Colors.white10 : Colors.grey.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.calendar_month_outlined, color: themeColor, size: 20),
                        const SizedBox(width: 12),
                        Text(DateFormat('dd MMMM yyyy').format(selectedDate), 
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: profileProvider.textColor)),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: () {
                  if (nameController.text.isNotEmpty) {
                    final newStaff = StaffModel(
                      id: staff?.id,
                      name: nameController.text,
                      monthlySalary: double.tryParse(salaryController.text) ?? 0,
                      advance: double.tryParse(advanceController.text) ?? 0,
                      joinDate: selectedDate,
                      contact: contactController.text,
                      totalLeaves: staff?.totalLeaves ?? 0,
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
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 60),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                  elevation: 0,
                ),
                child: Text(staff == null ? 'ADD STAFF MEMBER' : 'UPDATE DETAILS', 
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sheetTextField(TextEditingController controller, String label, IconData icon, ProfileProvider profile, {bool isNumber = false}) {
    return TextField(
      controller: controller,
      keyboardType: isNumber ? TextInputType.number : TextInputType.text,
      style: TextStyle(color: profile.textColor, fontWeight: FontWeight.bold),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: profile.secondaryTextColor),
        prefixIcon: Icon(icon, size: 20, color: profile.themeColor),
        filled: true,
        fillColor: profile.scaffoldColor,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: profile.themeColor, width: 2)),
      ),
    );
  }
}
