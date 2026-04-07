import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:workmanager/workmanager.dart';
import 'firebase_options.dart';
import 'providers/transaction_provider.dart';
import 'providers/item_provider.dart';
import 'providers/profile_provider.dart';
import 'providers/category_provider.dart';
import 'providers/staff_provider.dart';
import 'providers/supplier_provider.dart';
import 'providers/sync_provider.dart';
import 'providers/unit_provider.dart';
import 'providers/purchase_reminder_provider.dart';
import 'providers/printer_provider.dart';
import 'screens/splash_screen.dart';
import 'services/export_service.dart';
import 'services/notification_service.dart';
import 'core/database/database_helper.dart';

final GlobalKey<ScaffoldMessengerState> rootScaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
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
      final pending = transactions.where((tx) => 
        tx.isDeleted == 0 && (tx.status.trim().toLowerCase() == 'pending' || tx.status.trim().toLowerCase() == 'draft')
      ).toList();

      if (pending.isNotEmpty) {
        await notificationService.showNotification(
          id: 999,
          title: "Pending Orders Reminder",
          body: "You have ${pending.length} pending orders. Don't forget to complete them!",
        );
      }
      return Future.value(true);
    }

    if (task == "dailySalesSummary") {
      final db = DatabaseHelper.instance;
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final transactions = await db.getAllTransactions();
      
      final todaySales = transactions.where((tx) => 
        tx.type == 'sale' && tx.isDeleted == 0 && tx.status == 'completed' &&
        tx.date.year == today.year && tx.date.month == today.month && tx.date.day == today.day
      ).fold(0.0, (sum, tx) => sum + tx.amount);

      await notificationService.showNotification(
        id: 1001,
        title: "Daily Sales Summary",
        body: "Yesterday's total sale was ₹${todaySales.toStringAsFixed(0)}. Have a great business day!",
      );
      return Future.value(true);
    }

    return Future.value(true);
  });
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await NotificationService().init();

  Workmanager().initialize(callbackDispatcher, isInDebugMode: false);
  
  Workmanager().registerPeriodicTask(
    "1", "dailyBackupTask",
    frequency: const Duration(hours: 24),
    initialDelay: const Duration(minutes: 30),
    existingWorkPolicy: ExistingPeriodicWorkPolicy.replace,
  );

  Workmanager().registerPeriodicTask(
    "pending_order_reminder", "pendingOrdersCheck",
    frequency: const Duration(hours: 1),
    existingWorkPolicy: ExistingPeriodicWorkPolicy.replace,
  );

  Workmanager().registerPeriodicTask(
    "3", "dailySalesSummary",
    frequency: const Duration(hours: 24),
    initialDelay: const Duration(hours: 10),
    existingWorkPolicy: ExistingPeriodicWorkPolicy.replace,
  );
  
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  
  runApp(
    RestartWidget(
      child: MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => TransactionProvider()..fetchTransactions()),
          ChangeNotifierProvider(create: (_) => ItemProvider()..fetchItems()),
          ChangeNotifierProvider(create: (_) => ProfileProvider()),
          ChangeNotifierProvider(create: (_) => CategoryProvider()..fetchCategories()),
          ChangeNotifierProvider(create: (_) => StaffProvider()..fetchStaff()),
          ChangeNotifierProvider(create: (_) => SupplierProvider()..fetchSuppliers()),
          ChangeNotifierProvider(create: (_) => UnitProvider()..fetchUnits()),
          ChangeNotifierProvider(create: (_) => SyncProvider()),
          ChangeNotifierProvider(create: (_) => PurchaseReminderProvider()..fetchReminders()),
          ChangeNotifierProvider(create: (_) => PrinterProvider()),
        ],
        child: const MyApp(),
      ),
    ),
  );
}

class RestartWidget extends StatefulWidget {
  const RestartWidget({super.key, required this.child});
  final Widget child;

  static void restartApp(BuildContext context) {
    context.findAncestorStateOfType<_RestartWidgetState>()?.restartApp();
  }

  @override
  State<RestartWidget> createState() => _RestartWidgetState();
}

class _RestartWidgetState extends State<RestartWidget> {
  Key key = UniqueKey();
  void restartApp() => setState(() => key = UniqueKey());
  @override
  Widget build(BuildContext context) => KeyedSubtree(key: key, child: widget.child);
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
          theme: ThemeData(
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(
              seedColor: profile.themeColor, 
              primary: profile.themeColor, 
              brightness: profile.isDarkMode ? Brightness.dark : Brightness.light
            ),
            scaffoldBackgroundColor: profile.scaffoldColor,
            inputDecorationTheme: InputDecorationTheme(
              filled: true,
              fillColor: profile.isDarkMode ? Colors.white.withValues(alpha: 0.05) : Colors.grey.shade50,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              labelStyle: TextStyle(color: profile.themeColor, fontWeight: FontWeight.bold, fontSize: 14),
              floatingLabelBehavior: FloatingLabelBehavior.always,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: profile.themeColor.withValues(alpha: 0.3)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: profile.themeColor.withValues(alpha: 0.2)),
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
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 0,
              ),
            ),
          ),
          home: const SplashScreen(),
        );
      }
    );
  }
}
