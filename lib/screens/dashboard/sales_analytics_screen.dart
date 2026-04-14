import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../providers/transaction_provider.dart';
import '../../providers/profile_provider.dart';

class SalesAnalyticsScreen extends StatelessWidget {
  const SalesAnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final txProvider = Provider.of<TransactionProvider>(context);
    final profile = Provider.of<ProfileProvider>(context);
    final themeColor = profile.themeColor;

    return Scaffold(
      backgroundColor: profile.scaffoldColor,
      appBar: AppBar(
        title: const Text('SALES ANALYTICS', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
        backgroundColor: themeColor,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSummaryCards(txProvider, profile),
            const SizedBox(height: 24),
            Text('WEEKLY SALES TREND', style: TextStyle(fontWeight: FontWeight.w800, color: profile.textColor, fontSize: 14)),
            const SizedBox(height: 16),
            _buildChart(txProvider, profile),
            const SizedBox(height: 24),
            Text('PAYMENT DISTRIBUTION', style: TextStyle(fontWeight: FontWeight.w800, color: profile.textColor, fontSize: 14)),
            const SizedBox(height: 16),
            _buildPaymentPieChart(txProvider, profile),
            const SizedBox(height: 100),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCards(TransactionProvider tx, ProfileProvider profile) {
    return Row(
      children: [
        _statBox('Daily Sales', '${profile.currencySymbol}${tx.todaySales.toStringAsFixed(0)}', Colors.blue, profile),
        const SizedBox(width: 12),
        _statBox('Daily Profit', '${profile.currencySymbol}${tx.profitToday.toStringAsFixed(0)}', Colors.green, profile),
      ],
    );
  }

  Widget _statBox(String label, String value, Color color, ProfileProvider profile) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: profile.cardColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.1)),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10)],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(color: profile.secondaryTextColor, fontSize: 11, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(value, style: TextStyle(color: profile.textColor, fontSize: 20, fontWeight: FontWeight.w900)),
          ],
        ),
      ),
    );
  }

  Widget _buildChart(TransactionProvider tx, ProfileProvider profile) {
    return Container(
      height: 250,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: profile.cardColor,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10)],
      ),
      child: LineChart(
        LineChartData(
          gridData: const FlGridData(show: false),
          titlesData: const FlTitlesData(show: false),
          borderData: FlBorderData(show: false),
          lineBarsData: [
            LineChartBarData(
              spots: const [
                FlSpot(0, 3), FlSpot(1, 1), FlSpot(2, 4), FlSpot(3, 2), 
                FlSpot(4, 5), FlSpot(5, 3), FlSpot(6, 4),
              ],
              isCurved: true,
              color: profile.themeColor,
              barWidth: 4,
              isStrokeCapRound: true,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                color: profile.themeColor.withValues(alpha: 0.1),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentPieChart(TransactionProvider tx, ProfileProvider profile) {
    return Container(
      height: 250,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: profile.cardColor,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10)],
      ),
      child: PieChart(
        PieChartData(
          sectionsSpace: 4,
          centerSpaceRadius: 50,
          sections: [
            PieChartSectionData(
              color: Colors.green.shade400, 
              value: tx.cashSalesToday > 0 ? tx.cashSalesToday : 1, 
              title: 'Cash', 
              radius: 40, 
              titleStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white)
            ),
            PieChartSectionData(
              color: Colors.blue.shade400, 
              value: tx.upiSalesToday > 0 ? tx.upiSalesToday : 1, 
              title: 'UPI', 
              radius: 40, 
              titleStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white)
            ),
            PieChartSectionData(
              color: Colors.orange.shade400, 
              value: tx.creditSalesToday > 0 ? tx.creditSalesToday : 1, 
              title: 'Credit', 
              radius: 40, 
              titleStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white)
            ),
          ],
        ),
      ),
    );
  }
}
