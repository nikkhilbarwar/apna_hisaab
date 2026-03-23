import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../database/database_helper.dart';

class SyncService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<void> syncData() async {
    var connectivityResult = await (Connectivity().checkConnectivity());
    if (connectivityResult == ConnectivityResult.none) return;

    final unsyncedTx = await DatabaseHelper.instance.getUnsyncedTransactions();

    for (var tx in unsyncedTx) {
      try {
        await _firestore.collection('transactions').add(tx.toMap());
        await DatabaseHelper.instance.updateTransactionSyncStatus(tx.id!, 1);
      } catch (e) {
        print('Error syncing transaction ${tx.id}: $e');
      }
    }
  }
}
