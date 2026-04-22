import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../models/transaction_model.dart';
import '../../../providers/item_provider.dart';
import '../../../providers/profile_provider.dart';
import '../../../providers/transaction_provider.dart';
import '../../../services/export_service.dart';
import '../../daily_entry/entry_screen.dart';

class TransactionDetailSheet extends StatelessWidget {
  final TransactionModel tx;

  const TransactionDetailSheet({super.key, required this.tx});

  @override
  Widget build(BuildContext context) {
    final profile = Provider.of<ProfileProvider>(context);
    final isSalary = tx.category == 'Salary';
    final isSale = tx.type == 'sale';
    final isPending = tx.paymentMode == 'Pending';

    // Precise calculations from Snapshots
    final snapshots = tx.itemSnapshots;
    double calculatedSubtotal = 0;
    for (var s in snapshots) {
      calculatedSubtotal += s.lineTotal;
    }

    double discount = tx.discountValue;
    double transport = tx.transportValue;
    double taxAmount = tx.taxValue;
    double subtotal = tx.subtotalValue;

    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: BoxDecoration(
        color: profile.cardColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: Column(
        children: [
          // Drag Handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        isSalary ? 'PAYROLL VOUCHER' : 'BILL DETAILS',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 12,
                          color: profile.secondaryTextColor,
                          letterSpacing: 1.5,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color:
                              (isPending
                                      ? Colors.orange
                                      : (isSalary
                                            ? Colors.purple
                                            : (isSale
                                                  ? Colors.green
                                                  : Colors.red)))
                                  .withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          isPending
                              ? 'PENDING'
                              : (isSalary ? 'PAID' : 'COMPLETED'),
                          style: TextStyle(
                            color: isPending
                                ? Colors.orange
                                : (isSalary
                                      ? Colors.purple
                                      : (isSale ? Colors.green : Colors.red)),
                            fontWeight: FontWeight.bold,
                            fontSize: 10,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Text(
                    isSalary ? 'STAFF PAYROLL' : tx.category.toUpperCase(),
                    style: TextStyle(
                      color: isSalary ? Colors.purple : profile.themeColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _getSmartItemTitle(tx),
                    style: TextStyle(
                      color: profile.textColor,
                      fontWeight: FontWeight.w900,
                      fontSize: 24,
                      letterSpacing: -0.5,
                    ),
                  ),
                  if (isSalary) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Monthly Salary: ${profile.currencySymbol}${snapshots.isNotEmpty ? snapshots.firstWhere((s) => s.id == -1, orElse: () => snapshots.first).price.abs().toStringAsFixed(0) : "0"}',
                      style: TextStyle(
                        color: profile.themeColor,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                  ],
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
                        DateFormat('dd MMMM yyyy, hh:mm a').format(tx.date),
                        style: TextStyle(
                          color: profile.secondaryTextColor,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 40),

                  Text(
                    isSalary ? 'PAYROLL BREAKDOWN' : 'ITEMS BREAKDOWN',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 11,
                      color: profile.secondaryTextColor,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 16),

                  ...snapshots.map((s) {
                    bool isDeduction = s.price < 0;
                    String qLabel = s.qty == 0.5
                        ? "Half"
                        : (s.qty == 1.0 ? "Full" : s.qty.toStringAsFixed(1));

                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: isDeduction
                            ? Colors.red.withValues(alpha: 0.05)
                            : (isSalary
                                  ? Colors.purple.withValues(alpha: 0.03)
                                  : profile.scaffoldColor.withValues(
                                      alpha: 0.5,
                                    )),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isDeduction
                              ? Colors.red.withValues(alpha: 0.1)
                              : (profile.isDarkMode
                                    ? Colors.white10
                                    : Colors.grey.shade100),
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: isDeduction
                                  ? Colors.red.withValues(alpha: 0.1)
                                  : (isSalary
                                        ? Colors.purple.withValues(alpha: 0.1)
                                        : profile.themeColor.withValues(
                                            alpha: 0.1,
                                          )),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              isDeduction
                                  ? Icons.remove_circle_outline
                                  : (isSalary
                                        ? Icons.person_outline
                                        : Icons.shopping_bag_outlined),
                              size: 18,
                              color: isDeduction
                                  ? Colors.red
                                  : (isSalary
                                        ? Colors.purple
                                        : profile.themeColor),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  s.name,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: profile.textColor,
                                    fontSize: 14,
                                  ),
                                ),
                                Text(
                                  isDeduction
                                      ? 'Deduction'
                                      : (isSalary
                                            ? 'Base Component'
                                            : '$qLabel x ${profile.currencySymbol}${s.price.toInt()}'),
                                  style: TextStyle(
                                    color: profile.secondaryTextColor,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            '${isDeduction ? "-" : ""}${profile.currencySymbol}${s.lineTotal.abs().toStringAsFixed(0)}',
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              color: isDeduction
                                  ? Colors.red
                                  : profile.textColor,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                    );
                  }),

                  const Divider(height: 40),
                  _detailRow(
                    'Subtotal',
                    '${profile.currencySymbol}${isSalary ? tx.amount.toStringAsFixed(0) : calculatedSubtotal.toStringAsFixed(0)}',
                    profile,
                  ),
                  if (!isSalary && discount > 0)
                    _detailRow(
                      'Discount',
                      '- ${profile.currencySymbol}${discount.toStringAsFixed(0)}',
                      profile,
                      color: Colors.green,
                    ),
                  if (!isSalary && transport > 0)
                    _detailRow(
                      isSale ? 'Delivery Charge' : 'Transport / Rent',
                      '${profile.currencySymbol}${transport.toStringAsFixed(0)}',
                      profile,
                    ),
                  if (!isSalary && taxAmount > 0)
                    _detailRow(
                      'Tax (${profile.taxPercentage}%)',
                      '${profile.currencySymbol}${taxAmount.toStringAsFixed(0)}',
                      profile,
                    ),

                  if (tx.paymentMode == 'Credit') ...[
                    const SizedBox(height: 8),
                    _detailRow(
                      'Total Bill',
                      '${profile.currencySymbol}${tx.amount.toStringAsFixed(0)}',
                      profile,
                      isBold: true,
                    ),
                    _detailRow(
                      'Paid (Deposit)',
                      '${profile.currencySymbol}${tx.paidAmount.toStringAsFixed(0)}',
                      profile,
                      color: Colors.green,
                      isBold: true,
                    ),
                    const Divider(height: 20, thickness: 0.5),
                    _detailRow(
                      'Remaining Due',
                      '${profile.currencySymbol}${(tx.amount - tx.paidAmount).toStringAsFixed(0)}',
                      profile,
                      color: Colors.red,
                      isBold: true,
                    ),
                  ],

                  if (tx.paymentMode == 'Split') ...[
                    const SizedBox(height: 8),
                    _detailRow(
                      'Cash Part',
                      '${profile.currencySymbol}${tx.cashAmount.toStringAsFixed(0)}',
                      profile,
                    ),
                    _detailRow(
                      'UPI Part',
                      '${profile.currencySymbol}${tx.upiAmount.toStringAsFixed(0)}',
                      profile,
                    ),
                  ],

                  if (tx.customerContact.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Text(
                          'Customer',
                          style: TextStyle(
                            color: profile.secondaryTextColor,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            tx.customerContact,
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              color: profile.themeColor,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(
                            Icons.call,
                            size: 20,
                            color: Colors.green,
                          ),
                          onPressed: () =>
                              _launchURL('tel:${tx.customerContact}'),
                        ),
                        if (tx.paymentMode == 'Credit' &&
                            (tx.amount - tx.paidAmount) > 0)
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(
                              Icons.message_rounded,
                              size: 20,
                              color: Color(0xFF25D366),
                            ),
                            onPressed: () {
                              double due = tx.amount - tx.paidAmount;
                              String msg =
                                  "Hi, this is a reminder from ${profile.displayBusinessName} regarding your pending balance of ${profile.currencySymbol}${due.toStringAsFixed(0)}. Please clear it at your earliest convenience. Thank you!";
                              _launchURL(
                                'https://wa.me/${tx.customerContact.replaceAll(RegExp(r'[^0-9]'), '')}?text=${Uri.encodeComponent(msg)}',
                              );
                            },
                          ),
                      ],
                    ),
                  ],

                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          profile.themeColor.withValues(alpha: 0.1),
                          profile.themeColor.withValues(alpha: 0.05),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: profile.themeColor.withValues(alpha: 0.1),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          tx.paymentMode == 'Credit'
                              ? 'DUE BALANCE'
                              : 'GRAND TOTAL',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 14,
                            color: tx.paymentMode == 'Credit'
                                ? Colors.red
                                : profile.textColor,
                            letterSpacing: 1,
                          ),
                        ),
                        Text(
                          profile.showAmount
                              ? '${profile.currencySymbol}${tx.paymentMode == 'Credit' ? (tx.amount - tx.paidAmount).toStringAsFixed(0) : tx.amount.toStringAsFixed(0)}'
                              : '${profile.currencySymbol}****',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 26,
                            color: tx.paymentMode == 'Credit'
                                ? Colors.red
                                : profile.themeColor,
                            letterSpacing: -1,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Action Buttons
                  Row(
                    children: [
                      Expanded(
                        child: _actionButton(
                          label: 'Edit',
                          icon: Icons.edit_rounded,
                          color: Colors.blue,
                          onPressed: () {
                            Navigator.pop(context); // Close the sheet
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                    EntryScreen(transaction: tx),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _actionButton(
                          label: 'Print',
                          icon: Icons.print_rounded,
                          color: profile.themeColor,
                          onPressed: () => ExportService().saveBillAsPdf(
                            tx,
                            profile.displayBusinessName,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _actionButton(
                          label: 'Delete',
                          icon: Icons.delete_outline_rounded,
                          color: Colors.red,
                          onPressed: () => _confirmDelete(context, tx),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(
    String label,
    String value,
    ProfileProvider profile, {
    bool isBold = false,
    Color? color,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              color: profile.secondaryTextColor,
              fontSize: 14,
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: color ?? profile.textColor,
              fontSize: 14,
              fontWeight: isBold ? FontWeight.w900 : FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionButton({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return Material(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            children: [
              Icon(icon, color: color),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _getSmartItemTitle(TransactionModel tx) {
    if (tx.category == 'Salary') {
      final namePart = tx.description
          .replaceFirst('Salary paid to ', '')
          .split(' ')
          .first;
      return 'Salary: $namePart';
    }
    if (tx.itemSnapshots.isEmpty) return tx.category;
    if (tx.itemSnapshots.length == 1) return tx.itemSnapshots.first.name;
    return '${tx.itemSnapshots.first.name} +${tx.itemSnapshots.length - 1} More';
  }

  void _launchURL(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  void _confirmDelete(BuildContext context, TransactionModel tx) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Transaction?'),
        content: const Text(
          'This action cannot be undone. All related snapshots will be removed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final itemProvider = Provider.of<ItemProvider>(
                context,
                listen: false,
              );
              Provider.of<TransactionProvider>(
                context,
                listen: false,
              ).softDeleteTransaction(tx.id!, itemProvider);
              Navigator.pop(ctx);
              Navigator.pop(context);
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}
