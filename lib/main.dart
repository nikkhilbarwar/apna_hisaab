import 'dart:ui';
import 'dart:io';
import 'dart:developer' as dev;
import 'package:apna_hisaab/services/firebase_service.dart' as app_fs;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:apna_hisaab/firebase_options.dart';
import 'package:apna_hisaab/models/category_model.dart';
import 'package:apna_hisaab/models/item_model.dart';
import 'package:apna_hisaab/models/staff_model.dart';
import 'package:apna_hisaab/providers/transaction_provider.dart';
import 'package:apna_hisaab/providers/item_provider.dart';
import 'package:apna_hisaab/providers/profile_provider.dart';
import 'package:apna_hisaab/providers/category_provider.dart';
import 'package:apna_hisaab/providers/staff_provider.dart';
import 'package:apna_hisaab/providers/staff_auth_provider.dart';
import 'package:apna_hisaab/providers/supplier_provider.dart';
import 'package:apna_hisaab/providers/sync_provider.dart';
import 'package:apna_hisaab/providers/unit_provider.dart';
import 'package:apna_hisaab/providers/purchase_reminder_provider.dart';
import 'package:apna_hisaab/providers/printer_provider.dart';
import 'package:apna_hisaab/core/app_root.dart';
import 'package:apna_hisaab/screens/splash_screen.dart';
import 'package:apna_hisaab/services/export_service.dart';
import 'package:apna_hisaab/services/notification_service.dart';
import 'package:apna_hisaab/core/database/database_helper.dart';

final GlobalKey<ScaffoldMessengerState> rootScaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    final notificationService = NotificationService();
    await notificationService.init();

    if (task == "dailyBackupTask") {
      try {
        await ExportService().createAutoBackup();
        return Future.value(true);
      } catch (e) {
        return Future.value(false);
      }
    }

    if (task == "pendingOrdersCheck") {
      final db = DatabaseHelper.instance;
      final transactions = await db.getAllTransactions();
      final pending = transactions
          .where(
            (tx) =>
                tx.isDeleted == 0 &&
                (tx.status.trim().toLowerCase() == 'pending' ||
                    tx.status.trim().toLowerCase() == 'draft'),
          )
          .toList();

      if (pending.isNotEmpty) {
        await notificationService.showNotification(
          id: 999,
          title: "Pending Orders Reminder",
          body:
              "You have ${pending.length} pending orders. Don't forget to complete them!",
        );
      }
      return Future.value(true);
    }

    if (task == "dailySalesSummary") {
      final db = DatabaseHelper.instance;
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final transactions = await db.getAllTransactions();

      final todaySales = transactions
          .where(
            (tx) =>
                tx.type == 'sale' &&
                tx.isDeleted == 0 &&
                tx.status == 'completed' &&
                tx.date.year == today.year &&
                tx.date.month == today.month &&
                tx.date.day == today.day,
          )
          .fold(0.0, (sum, tx) => sum + tx.amount);

      await notificationService.showNotification(
        id: 1001,
        title: "Daily Sales Summary",
        body:
            "Yesterday's total sale was ₹${todaySales.toStringAsFixed(0)}. Have a great business day!",
      );
      return Future.value(true);
    }

    if (task == "syncTask") {
      try {
        final db = DatabaseHelper.instance;
        final firebaseService = app_fs.FirebaseService();
        final prefs = await SharedPreferences.getInstance();
        final uid = FirebaseAuth.instance.currentUser?.uid;
        
        if (uid == null) return Future.value(true);

        // 1. PUSH (Local to Cloud)
        final unsyncedCats = await db.getUnsyncedData('categories');
        for (var map in unsyncedCats) {
          final cat = CategoryModel.fromMap(map);
          await firebaseService.syncCategory(cat);
          await db.updateSyncStatus('categories', cat.id!, 1);
        }

        final unsyncedItems = await db.getUnsyncedData('items');
        for (var map in unsyncedItems) {
          final item = ItemModel.fromMap(map);
          await firebaseService.syncItem(item);
          await db.updateSyncStatus('items', item.id!, 1);
        }

        final unsyncedStaff = await db.getUnsyncedData('staff');
        for (var map in unsyncedStaff) {
          final staff = StaffModel.fromMap(map);
          await firebaseService.syncStaff(staff);
          await db.updateSyncStatus('staff', staff.id!, 1);
        }

        final unsyncedTxs = await db.getUnsyncedTransactions();
        for (var tx in unsyncedTxs) {
          await firebaseService.syncTransaction(tx);
          await db.updateTransactionSyncStatus(tx.id!, 1);
        }

        // 2. PULL (Cloud to Local - Delta Sync)
        final lastSyncStr = prefs.getString('last_sync_timestamp_$uid');
        final lastSync = lastSyncStr != null ? DateTime.tryParse(lastSyncStr) : null;

        // Fetch delta changes
        final cloudCats = await firebaseService.fetchAllCategories(since: lastSync);
        if (cloudCats.isNotEmpty) {
          await db.batchInsert('categories', cloudCats.map((c) => (c..isSynced = 1).toMap()).toList());
        }

        final cloudItems = await firebaseService.fetchAllItems(since: lastSync);
        if (cloudItems.isNotEmpty) {
          await db.batchInsert('items', cloudItems.map((i) => (i..isSynced = 1).toMap()).toList());
        }

        final cloudTxs = await firebaseService.fetchAllTransactions(since: lastSync);
        if (cloudTxs.isNotEmpty) {
          await db.batchInsert('transactions', cloudTxs.map((t) => (t..isSynced = 1).toMap()).toList());
        }

        // Update timestamp after successful delta pull
        await prefs.setString('last_sync_timestamp_$uid', DateTime.now().toIso8601String());

        return Future.value(true);
      } catch (e) {
        debugPrint("Workmanager Sync Error: $e");
        return Future.value(false);
      }
    }

    return Future.value(true);
  });
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isWindows || Platform.isLinux) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  // Handle Flutter-level errors
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    dev.log(
      "FLUTTER_ERROR: ${details.exception}",
      stackTrace: details.stack,
      name: 'Main',
    );
  };

  // Handle errors not caught by Flutter (e.g. async errors)
  PlatformDispatcher.instance.onError = (error, stack) {
    dev.log("PLATFORM_ERROR: $error", stackTrace: stack, name: 'Main');
    return true; // Error was handled
  };

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    final notificationService = NotificationService();
    await notificationService.init();
    notificationService.setupInteractions();
    FirebaseMessaging.onBackgroundMessage(
      NotificationService.firebaseMessagingBackgroundHandler,
    );

    if (Platform.isAndroid || Platform.isIOS) {
      Workmanager().initialize(callbackDispatcher);

      Workmanager().registerPeriodicTask(
        "1",
        "dailyBackupTask",
        frequency: const Duration(hours: 24),
        initialDelay: const Duration(minutes: 30),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.replace,
      );

      Workmanager().registerPeriodicTask(
        "pending_order_reminder",
        "pendingOrdersCheck",
        frequency: const Duration(minutes: 10),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.replace,
      );

      Workmanager().registerPeriodicTask(
        "3",
        "dailySalesSummary",
        frequency: const Duration(hours: 24),
        initialDelay: const Duration(hours: 10),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.replace,
      );

      Workmanager().registerPeriodicTask(
        "cloud_sync",
        "syncTask",
        frequency: const Duration(minutes: 5),
        constraints: Constraints(networkType: NetworkType.connected),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
      );
    }

    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

    runApp(
      RestartWidget(
        key: restartKey,
        child: MultiProvider(
          providers: [
            ChangeNotifierProvider(
              create: (_) => TransactionProvider()..fetchTransactions(),
            ),
            ChangeNotifierProvider(create: (_) => ItemProvider()..fetchItems()),
            ChangeNotifierProvider(create: (_) => ProfileProvider()),
            ChangeNotifierProvider(
              create: (_) => CategoryProvider()..fetchCategories(),
            ),
            ChangeNotifierProvider(
              create: (_) => StaffProvider()..fetchStaff(),
            ),
            ChangeNotifierProvider(create: (_) => StaffAuthProvider()),
            ChangeNotifierProvider(
              create: (_) => SupplierProvider()..fetchSuppliers(),
            ),
            ChangeNotifierProvider(create: (_) => UnitProvider()..fetchUnits()),
            ChangeNotifierProvider(create: (_) => SyncProvider()),
            ChangeNotifierProvider(
              create: (_) => PurchaseReminderProvider()..fetchReminders(),
            ),
            ChangeNotifierProvider(create: (_) => PrinterProvider()),
          ],
          child: const MyApp(),
        ),
      ),
    );
  } catch (e, stack) {
    dev.log("CRITICAL_INIT_ERROR: $e", stackTrace: stack, name: 'Main');
    // Still try to run the app so it doesn't just hang on splash
    runApp(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: Text(
              "A critical error occurred during initialization. Please restart the app.\n\n$e",
            ),
          ),
        ),
      ),
    );
  }
}


class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return Consumer<ProfileProvider>(
      builder: (context, profile, _) {
        return MaterialApp(
          title: 'Apna Hisaab',
          debugShowCheckedModeBanner: false,
          scaffoldMessengerKey: rootScaffoldMessengerKey,
          navigatorKey: navigatorKey,
          theme: ThemeData(
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(
              seedColor: profile.themeColor,
              primary: profile.themeColor,
              brightness: profile.isDarkMode
                  ? Brightness.dark
                  : Brightness.light,
            ),
            scaffoldBackgroundColor: profile.scaffoldColor,
            inputDecorationTheme: InputDecorationTheme(
              filled: true,
              fillColor: profile.isDarkMode
                  ? Colors.white.withValues(alpha: 0.05)
                  : Colors.grey.shade50,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 16,
              ),
              labelStyle: TextStyle(
                color: profile.themeColor,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
              floatingLabelBehavior: FloatingLabelBehavior.always,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(
                  color: profile.themeColor.withValues(alpha: 0.3),
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(
                  color: profile.themeColor.withValues(alpha: 0.2),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: profile.themeColor, width: 2),
              ),
            ),
            elevatedButtonTheme: ElevatedButtonThemeData(
              style: ElevatedButton.styleFrom(
                backgroundColor: profile.themeColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 0,
              ),
            ),
          ),
          home: const SplashScreen(),
        );
      },
    );
  }
}
