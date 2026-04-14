import 'package:flutter/material.dart';
import '../../../providers/transaction_provider.dart';
import '../../../providers/profile_provider.dart';
import '../../../utils/app_strings.dart';
import 'package:intl/intl.dart';

class StatCard extends StatelessWidget {
  final TransactionProvider tx;
  final ProfileProvider profile;
  final DateTimeRange? range;

  const StatCard({super.key, required this.tx, required this.profile, this.range});

  @override
  Widget build(BuildContext context) {
    final orderCount = tx.getOrderCountForRange(range);
    final totalSales = tx.getSalesForRange(range);
    final growth = tx.getSalesGrowthForRange(range);
    final avgBill = tx.getAvgOrderValueForRange(range);
    final profit = tx.getProfitForRange(range);

    String dateLabel = range == null 
        ? AppStrings.totalSalesToday 
        : "${DateFormat('dd MMM').format(range!.start)} - ${DateFormat('dd MMM').format(range!.end)}";

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [profile.themeColor, profile.themeColor.withValues(alpha: 0.85)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: profile.themeColor.withValues(alpha: 0.3),
            blurRadius: 25,
            offset: const Offset(0, 12),
          )
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -30, top: -30,
            child: CircleAvatar(radius: 80, backgroundColor: Colors.white.withValues(alpha: 0.05)),
          ),
          Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 8), 
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.auto_awesome, color: Colors.white.withValues(alpha: 0.6), size: 14),
                        const SizedBox(width: 8),
                        Text(dateLabel, style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w800, fontSize: 12, letterSpacing: 1.5)),
                      ],
                    ),
                    const SizedBox(height: 4), 
                    Text(
                      profile.showAmount 
                        ? '${profile.currencySymbol}${totalSales.toStringAsFixed(0)}'
                        : '${profile.currencySymbol}****', 
                      style: const TextStyle(fontSize: 48, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -1.5)
                    ),
                    const SizedBox(height: 4), 
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(20)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(growth >= 0 ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded, size: 14, color: growth >= 0 ? Colors.greenAccent : Colors.redAccent),
                        const SizedBox(width: 6),
                        Text('${growth.abs().toStringAsFixed(1)}% vs Yesterday', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.white)),
                      ]),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.1), borderRadius: const BorderRadius.vertical(bottom: Radius.circular(28))),
                child: Column(
                  children: [
                    Row(
                      children: [
                        _miniStat('Orders', orderCount.toString()),
                        _verticalDivider(),
                        _miniStat('Avg Bill', profile.showAmount ? '${profile.currencySymbol}${avgBill.toStringAsFixed(0)}' : '****'),
                        _verticalDivider(),
                        _miniStat('Profit', profile.showAmount ? '${profile.currencySymbol}${profit.toStringAsFixed(0)}' : '****'),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          Positioned(
            top: 16,
            right: 16,
            child: GestureDetector(
              onTap: () => profile.toggleAmountVisibility(context),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12), 
                  border: Border.all(color: Colors.white24)
                ),
                child: Icon(
                  profile.showAmount ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                  color: Colors.white,
                  size: 22,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniStat(String label, String value) {
    return Expanded(
      child: Column(children: [
        Text(value, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: Colors.white)),
        const SizedBox(height: 2),
        Text(label.toUpperCase(), style: const TextStyle(color: Colors.white70, fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 0.8)),
      ]),
    );
  }

  Widget _verticalDivider() => Container(height: 24, width: 1, color: Colors.white12);
}
