import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:workmanager/workmanager.dart';
import 'firebase_options.dart'; // Import generated options
import 'providers/transaction_provider.dart';
import 'providers/item_provider.dart';
import 'providers/profile_provider.dart';
import 'providers/category_provider.dart';
import 'providers/staff_provider.dart';
import 'screens/splash_screen.dart';
import 'services/export_service.dart';

// logic: Global key to show Snackbars safely after async/await
final GlobalKey<ScaffoldMessengerState> rootScaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    if (task == "dailyBackupTask") {
      try {
        // Initialize Firebase if needed inside task
        await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
        await ExportService().createAutoBackup();
        return Future.value(true);
      } catch (e) {
        return Future.value(false);
      }
    }
    return Future.value(true);
  });
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Update: Pass DefaultFirebaseOptions to ensure correct project connection
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Initialize Workmanager for daily 4 AM backup
  Workmanager().initialize(callbackDispatcher, isInDebugMode: false);
  Workmanager().registerPeriodicTask(
    "1",
    "dailyBackupTask",
    frequency: const Duration(hours: 24),
    initialDelay: _calculateInitialDelayFor4AM(),
    constraints: Constraints(
      networkType: NetworkType.connected,
      requiresBatteryNotLow: true,
      requiresStorageNotLow: true,
    ),
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
        ],
        child: const MyApp(),
      ),
    ),
  );
}

Duration _calculateInitialDelayFor4AM() {
  final now = DateTime.now();
  var scheduledTime = DateTime(now.year, now.month, now.day, 4, 0);
  if (scheduledTime.isBefore(now)) {
    scheduledTime = scheduledTime.add(const Duration(days: 1));
  }
  return scheduledTime.difference(now);
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

  void restartApp() {
    setState(() {
      key = UniqueKey();
    });
  }

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(
      key: key,
      child: widget.child,
    );
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ProfileProvider>(
      builder: (context, profile, _) {
        final primaryColor = profile.themeColor;
        
        SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: profile.isDarkMode ? Brightness.light : Brightness.dark,
          statusBarBrightness: profile.isDarkMode ? Brightness.dark : Brightness.light,
          systemNavigationBarColor: profile.cardColor,
          systemNavigationBarIconBrightness: profile.isDarkMode ? Brightness.light : Brightness.dark,
        ));

        return MaterialApp(
          title: 'Apna Hisaab',
          debugShowCheckedModeBanner: false,
          scaffoldMessengerKey: rootScaffoldMessengerKey,
          theme: ThemeData(
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(
              seedColor: primaryColor,
              primary: primaryColor,
              brightness: profile.isDarkMode ? Brightness.dark : Brightness.light,
              surface: profile.scaffoldColor,
            ),
            scaffoldBackgroundColor: profile.scaffoldColor,
            appBarTheme: AppBarTheme(
              backgroundColor: profile.cardColor,
              foregroundColor: profile.textColor,
              elevation: 0,
              centerTitle: true,
              systemOverlayStyle: profile.isDarkMode ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
            ),
            inputDecorationTheme: InputDecorationTheme(
              filled: true,
              fillColor: profile.cardColor,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: profile.isDarkMode ? Colors.white10 : Colors.grey.shade300),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: profile.isDarkMode ? Colors.white10 : Colors.grey.shade300),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: primaryColor, width: 2),
              ),
              labelStyle: TextStyle(color: profile.secondaryTextColor),
              hintStyle: TextStyle(color: profile.secondaryTextColor.withValues(alpha: 0.5)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            ),
            elevatedButtonTheme: ElevatedButtonThemeData(
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryColor,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 54),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 0,
              ),
            ),
            cardTheme: CardThemeData(
              color: profile.cardColor,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(color: profile.isDarkMode ? Colors.white10 : Colors.grey.shade100),
              ),
            ),
            dialogTheme: DialogThemeData(
              backgroundColor: profile.cardColor,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              titleTextStyle: TextStyle(color: profile.textColor, fontSize: 20, fontWeight: FontWeight.bold),
              contentTextStyle: TextStyle(color: profile.secondaryTextColor, fontSize: 14),
            ),
            bottomSheetTheme: BottomSheetThemeData(
              backgroundColor: profile.scaffoldColor,
              shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
            ),
          ),
          home: const SplashScreen(),
        );
      }
    );
  }
}
