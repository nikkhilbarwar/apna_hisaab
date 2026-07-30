import 'package:flutter/material.dart';
import 'package:apna_hisaab/screens/splash_screen.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
final GlobalKey<RestartWidgetState> restartKey = GlobalKey<RestartWidgetState>();

class RestartWidget extends StatefulWidget {
  const RestartWidget({super.key, required this.child});
  final Widget child;

  static void restartApp(BuildContext context) {
    if (restartKey.currentState != null) {
      debugPrint("🔄 Restarting App via GlobalKey...");
      restartKey.currentState!.restartApp();
    } else {
      debugPrint("⚠️ RestartWidget GlobalKey not found! Using context fallback...");
      final state = context.findAncestorStateOfType<RestartWidgetState>();
      if (state != null) {
        state.restartApp();
      } else {
        debugPrint("❌ Critical: RestartWidgetState not found! Forcing navigation...");
        navigatorKey.currentState?.pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const SplashScreen()),
          (route) => false,
        );
      }
    }
  }

  @override
  State<RestartWidget> createState() => RestartWidgetState();
}

class RestartWidgetState extends State<RestartWidget> {
  Key key = UniqueKey();
  
  void restartApp() {
    setState(() => key = UniqueKey());
  }
  @override
  Widget build(BuildContext context) =>
      KeyedSubtree(key: key, child: widget.child);
}
