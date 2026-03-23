import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'providers/transaction_provider.dart';
import 'providers/item_provider.dart';
import 'providers/profile_provider.dart';
import 'providers/category_provider.dart';
import 'providers/staff_provider.dart';
import 'screens/splash_screen.dart';

// logic: Global key to show Snackbars safely after async/await
final GlobalKey<ScaffoldMessengerState> rootScaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => TransactionProvider()..fetchTransactions()),
        ChangeNotifierProvider(create: (_) => ItemProvider()..fetchItems()),
        ChangeNotifierProvider(create: (_) => ProfileProvider()),
        ChangeNotifierProvider(create: (_) => CategoryProvider()..fetchCategories()),
        ChangeNotifierProvider(create: (_) => StaffProvider()..fetchStaff()),
      ],
      child: const MyApp(),
    ),
  );
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
              hintStyle: TextStyle(color: profile.secondaryTextColor.withOpacity(0.5)),
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
