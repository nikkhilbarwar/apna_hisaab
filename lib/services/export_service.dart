import 'dart:io';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart';
import '../core/database/database_helper.dart';

class ExportService {
  /// Export transactions to CSV (For Reports/Excel)
  Future<void> exportTransactionsToCsv(List<dynamic> transactions) async {
    String csvData = 'Date,Category,Type,Description,Amount,Paid,Payment Mode,Contact\n';

    for (var tx in transactions) {
      String date = DateFormat('yyyy-MM-dd HH:mm').format(tx.date);
      String desc = tx.description.replaceAll(',', ';');
      csvData += '$date,${tx.category},${tx.type},$desc,${tx.amount},${tx.paidAmount},${tx.paymentMode},${tx.customerContact}\n';
    }

    try {
      final directory = await getTemporaryDirectory();
      final path = "${directory.path}/transactions_${DateTime.now().millisecondsSinceEpoch}.csv";
      final file = File(path);
      await file.writeAsString(csvData);
      await Share.shareXFiles([XFile(path)], text: 'Business Transaction Report');
    } catch (e) {
      print("CSV Export Error: $e");
    }
  }

  /// FULL BACKUP: Exports all tables to a JSON file in Public Documents
  Future<String?> createFullBackup() async {
    try {
      final db = DatabaseHelper.instance;
      
      // Fetch all data
      final transactions = await db.getAllTransactions();
      final items = await db.getAllItems();
      final categories = await (await db.database).query('categories');
      final staff = await db.getAllStaff();

      Map<String, dynamic> backupData = {
        'backup_date': DateTime.now().toIso8601String(),
        'transactions': transactions.map((t) => t.toMap()).toList(),
        'items': items.map((i) => i.toMap()).toList(),
        'categories': categories,
        'staff': staff.map((s) => s.toMap()).toList(),
      };

      String jsonString = jsonEncode(backupData);
      
      // Save to Public Documents (Persistent)
      Directory? baseDir;
      if (Platform.isAndroid) {
        baseDir = Directory('/storage/emulated/0/Documents/ApnaHisaab_Backups');
      } else {
        baseDir = await getApplicationDocumentsDirectory();
      }

      if (!await baseDir.exists()) {
        await baseDir.create(recursive: true);
      }

      final fileName = "Backup_${DateFormat('ddMMM_yyyy_HHmm').format(DateTime.now())}.json";
      final file = File("${baseDir.path}/$fileName");
      await file.writeAsString(jsonString);

      return file.path;
    } catch (e) {
      print("Backup Error: $e");
      return null;
    }
  }

  /// RESTORE: Import data from a JSON file
  Future<bool> restoreFromBackup(File file) async {
    try {
      String content = await file.readAsString();
      Map<String, dynamic> data = jsonDecode(content);

      final db = await DatabaseHelper.instance.database;

      await db.transaction((txn) async {
        // Clear existing data
        await txn.delete('transactions');
        await txn.delete('items');
        await txn.delete('categories');
        await txn.delete('staff');

        // Restore Items
        if (data['items'] != null) {
          for (var item in data['items']) {
            await txn.insert('items', item);
          }
        }

        // Restore Categories
        if (data['categories'] != null) {
          for (var cat in data['categories']) {
            await txn.insert('categories', cat);
          }
        }

        // Restore Transactions
        if (data['transactions'] != null) {
          for (var tx in data['transactions']) {
            await txn.insert('transactions', tx);
          }
        }

        // Restore Staff
        if (data['staff'] != null) {
          for (var s in data['staff']) {
            await txn.insert('staff', s);
          }
        }
      });

      return true;
    } catch (e) {
      print("Restore Error: $e");
      return false;
    }
  }
}
