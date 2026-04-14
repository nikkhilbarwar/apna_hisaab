import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../models/transaction_model.dart';
import '../../../providers/profile_provider.dart';
import '../../../providers/transaction_provider.dart';
import '../../../providers/item_provider.dart';
import '../../daily_entry/entry_screen.dart';
import '../../../services/export_service.dart';

class TransactionDetailSheet extends StatelessWidget {
  final TransactionModel tx;
  final ProfileProvider profile;

  const TransactionDetailSheet({super.key, required this.tx, required this.profile});

  String _getSmartItemTitle(TransactionModel tx) {
    final items = tx.itemSnapshots;
    if (items.isEmpty) return tx.category;
    if (items.length == 1) {
      return items.first.name;
    } else {
      String names = items.take(2).map((e) => e.name).join(', ');
      if (items.length > 2) names += '...';
      return '${items.length} Items: $names';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isSale = tx.type == 'sale' || tx.type == 'income';
    final isPending = tx.status == 'pending';
    final txProvider = Provider.of<TransactionProvider>(context, listen: false);
    final itemProvider = Provider.of<ItemProvider>(context, listen: false);

    // Precise calculations from Snapshots
    final snapshots = tx.itemSnapshots;
    double calculatedSubtotal = 0;
    for (var s in snapshots) {
      calculatedSubtotal += s.lineTotal;
    }

    double discount = tx.discountValue;
    double subAfterDiscount = calculatedSubtotal - discount;
    double taxAmount = tx.amount - subAfterDiscount;
    if (taxAmount.abs() < 1.0) taxAmount = 0;

    return Container(
      height: MediaQuery.of(context).size.height * 0.8,
      decoration: BoxDecoration(color: profile.cardColor, borderRadius: const BorderRadius.vertical(top: Radius.circular(32))),
      child: Column(
        children: [
          // Drag Handle
          Center(child: Container(width: 40, height: 4, margin: const EdgeInsets.symmetric(vertical: 12), decoration: BoxDecoration(color: Colors.grey.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(2)))),
          
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('BILL DETAILS', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12, color: profile.secondaryTextColor, letterSpacing: 1.5)),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: (isPending ? Colors.orange : (isSale ? Colors.green : Colors.red)).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(isPending ? 'PENDING' : 'COMPLETED', style: TextStyle(color: isPending ? Colors.orange : (isSale ? Colors.green : Colors.red), fontWeight: FontWeight.bold, fontSize: 10)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Text(tx.category.toUpperCase(), style: TextStyle(color: profile.themeColor, fontWeight: FontWeight.bold, fontSize: 14, letterSpacing: 1)),
                  const SizedBox(height: 4),
                  Text(_getSmartItemTitle(tx), style: TextStyle(color: profile.textColor, fontWeight: FontWeight.w900, fontSize: 24, letterSpacing: -0.5)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.calendar_today, size: 14, color: profile.secondaryTextColor),
                      const SizedBox(width: 6),
                      Text(DateFormat('dd MMMM yyyy, hh:mm a').format(tx.date), style: TextStyle(color: profile.secondaryTextColor, fontSize: 13)),
                    ],
                  ),
                  const Divider(height: 40),
                  
                  Text('ITEMS BREAKDOWN', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 11, color: profile.secondaryTextColor, letterSpacing: 1)),
                  const SizedBox(height: 16),
                  
                  Column(
                    children: snapshots.map((s) {
                      String qLabel = s.qty == 0.5 ? "Half" : (s.qty == 1.0 ? "Full" : s.qty.toStringAsFixed(1));
                      bool hasExtraQty = s.extraQty > 0;
                      bool hasExtraPrice = s.extraPrice > 0;

                      return Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: profile.scaffoldColor.withValues(alpha: 0.5),
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
                            if (hasExtraQty || hasExtraPrice) ...[
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 8),
                                child: Divider(height: 1, thickness: 0.5),
                              ),
                              Row(
                                children: [
                                  Icon(Icons.add_circle_outline_rounded, size: 14, color: Colors.blue.shade600),
                                  const SizedBox(width: 8),
                                  if (hasExtraQty) 
                                    Text('Extra Qty: ${s.extraQty.toInt()} ', 
                                      style: TextStyle(fontSize: 12, color: profile.textColor, fontWeight: FontWeight.bold)),
                                  if (hasExtraQty && hasExtraPrice) 
                                    Text('• ', style: TextStyle(color: profile.secondaryTextColor)),
                                  if (hasExtraPrice)
                                    Text('Extra Rs: ${profile.currencySymbol}${s.extraPrice.toInt()}', 
                                      style: TextStyle(fontSize: 12, color: profile.textColor, fontWeight: FontWeight.bold)),
                                ],
                              ),
                            ],
                            if (s.servingMethod != 'N/A')
                               Padding(
                                 padding: const EdgeInsets.only(top: 8),
                                 child: Text('${s.servingMethod}${s.tableNumber.isNotEmpty ? ' • Table: ${s.tableNumber}' : ''}', 
                                   style: TextStyle(fontSize: 10, color: profile.secondaryTextColor, fontStyle: FontStyle.italic)),
                               ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                  
                  const Divider(height: 40),
                  _detailRow('Subtotal', '${profile.currencySymbol}${calculatedSubtotal.toStringAsFixed(0)}', profile),
                  if (discount > 0) _detailRow('Discount', '- ${profile.currencySymbol}${discount.toStringAsFixed(0)}', profile, color: Colors.green),
                  if (taxAmount > 0) _detailRow('Tax (${profile.taxPercentage}%)', '${profile.currencySymbol}${taxAmount.toStringAsFixed(0)}', profile),
                  
                  if (tx.paymentMode == 'Credit') ...[
                    const SizedBox(height: 8),
                    _detailRow('Total Bill', '${profile.currencySymbol}${tx.amount.toStringAsFixed(0)}', profile, isBold: true),
                    _detailRow('Paid (Deposit)', '${profile.currencySymbol}${tx.paidAmount.toStringAsFixed(0)}', profile, color: Colors.green, isBold: true),
                    const Divider(height: 20, thickness: 0.5),
                    _detailRow('Remaining Due', '${profile.currencySymbol}${(tx.amount - tx.paidAmount).toStringAsFixed(0)}', profile, color: Colors.red, isBold: true),
                  ],
                  
                  if (tx.paymentMode == 'Split') ...[
                    const SizedBox(height: 8),
                    _detailRow('Cash Part', '${profile.currencySymbol}${tx.cashAmount.toStringAsFixed(0)}', profile),
                    _detailRow('UPI Part', '${profile.currencySymbol}${tx.upiAmount.toStringAsFixed(0)}', profile),
                  ],

                  if (tx.customerContact.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Text('Customer', style: TextStyle(color: profile.secondaryTextColor, fontSize: 13, fontWeight: FontWeight.w600)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(tx.customerContact, 
                            style: TextStyle(fontWeight: FontWeight.w900, color: profile.themeColor, fontSize: 14)),
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.call, size: 20, color: Colors.green),
                          onPressed: () => _launchURL('tel:${tx.customerContact}'),
                        ),
                        if (tx.paymentMode == 'Credit' && (tx.amount - tx.paidAmount) > 0)
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.message_rounded, size: 20, color: Color(0xFF25D366)),
                            onPressed: () {
                              double due = tx.amount - tx.paidAmount;
                              String msg = "Hi, this is a reminder from ${profile.businessName} regarding your pending balance of ${profile.currencySymbol}${due.toStringAsFixed(0)}. Please clear it at your earliest convenience. Thank you!";
                              _launchURL('https://wa.me/${tx.customerContact.replaceAll(RegExp(r'[^0-9]'), '')}?text=${Uri.encodeComponent(msg)}');
                            },
                          ),
                      ],
                    ),
                  ],

                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [profile.themeColor.withValues(alpha: 0.1), profile.themeColor.withValues(alpha: 0.05)]),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: profile.themeColor.withValues(alpha: 0.1))
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(tx.paymentMode == 'Credit' ? 'DUE BALANCE' : 'GRAND TOTAL', 
                          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: tx.paymentMode == 'Credit' ? Colors.red : profile.textColor, letterSpacing: 1)),
                        Text(profile.showAmount 
                          ? '${profile.currencySymbol}${tx.paymentMode == 'Credit' ? (tx.amount - tx.paidAmount).toStringAsFixed(0) : tx.amount.toStringAsFixed(0)}' 
                          : '${profile.currencySymbol}****', 
                          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 26, color: tx.paymentMode == 'Credit' ? Colors.red : profile.themeColor, letterSpacing: -1)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),

          // Permanent Sticky Buttons
          Container(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
            decoration: BoxDecoration(
              color: profile.cardColor,
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, -5))],
            ),
            child: Row(
              children: [
                Expanded(child: _actionButton(
                  icon: Icons.print_rounded, label: 'PRINT', color: Colors.blue, onTap: () async {
                    Navigator.pop(context);
                    final exportService = ExportService();
                    await exportService.saveBillAsPdf(tx, profile.businessName);
                  }
                )),
                const SizedBox(width: 12),
                Expanded(child: _actionButton(
                  icon: Icons.edit_note_rounded, label: 'EDIT', color: Colors.orange, onTap: () {
                    Navigator.pop(context);
                    Navigator.push(context, MaterialPageRoute(builder: (c) => EntryScreen(transaction: tx)));
                  }
                )),
                const SizedBox(width: 12),
                Expanded(child: _actionButton(
                  icon: Icons.delete_outline_rounded, label: 'DELETE', color: Colors.red, onTap: () {
                    Navigator.pop(context);
                    txProvider.softDeleteTransaction(tx.id!, itemProvider);
                  }
                )),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionButton({required IconData icon, required String label, required Color color, required VoidCallback onTap}) {
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
            Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 11, letterSpacing: 0.8)),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(String l, String v, ProfileProvider profile, {Color? color, bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(l, style: TextStyle(color: profile.secondaryTextColor, fontSize: 13, fontWeight: isBold ? FontWeight.bold : FontWeight.w600)),
        Text(v, style: TextStyle(fontWeight: FontWeight.w900, color: color ?? profile.textColor, fontSize: isBold ? 15 : 14))
      ]),
    );
  }

  Future<void> _launchURL(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}
