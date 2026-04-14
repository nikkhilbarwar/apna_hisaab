import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../providers/profile_provider.dart';

class AppBottomSheet extends StatelessWidget {
  final Widget child;
  final ProfileProvider profile;
  final String? title;
  final bool showHandle;
  final EdgeInsetsGeometry? padding;
  final Widget? footer;

  const AppBottomSheet({
    super.key,
    required this.child,
    required this.profile,
    this.title,
    this.showHandle = true,
    this.padding,
    this.footer,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        decoration: BoxDecoration(
          color: profile.cardColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 20,
              offset: const Offset(0, -5),
            ),
          ],
        ),
        padding: padding ?? const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (showHandle)
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: profile.secondaryTextColor.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            if (title != null) ...[
              Text(
                title!.toUpperCase(),
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                  color: profile.secondaryTextColor,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 16),
            ],
            Flexible(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: child,
              ),
            ),
            if (footer != null) ...[
              const SizedBox(height: 16),
              footer!,
            ],
          ],
        ),
      ),
    );
  }

  static Future<T?> show<T>({
    required BuildContext context,
    required ProfileProvider profile,
    required Widget child,
    String? title,
    bool isScrollControlled = true,
    EdgeInsetsGeometry? padding,
    bool useHaptic = true,
    Widget? footer,
  }) async {
    if (useHaptic) {
      HapticFeedback.mediumImpact();
    }
    
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: isScrollControlled,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      builder: (context) => AppBottomSheet(
        profile: profile,
        title: title,
        padding: padding,
        footer: footer,
        child: child,
      ),
    );
  }

  static Future<bool?> showAction({
    required BuildContext context,
    required ProfileProvider profile,
    required String title,
    required String message,
    String confirmLabel = 'Confirm',
    String cancelLabel = 'Cancel',
    Color? confirmColor,
    IconData? icon,
    bool isDestructive = false,
  }) async {
    HapticFeedback.selectionClick();
    
    return show<bool>(
      context: context,
      profile: profile,
      title: title,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: (confirmColor ?? profile.themeColor).withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: 32,
                color: confirmColor ?? profile.themeColor,
              ),
            ),
            const SizedBox(height: 16),
          ],
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              color: profile.textColor,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 32),
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    cancelLabel,
                    style: TextStyle(
                      color: profile.secondaryTextColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isDestructive ? Colors.red : (confirmColor ?? profile.themeColor),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    confirmLabel,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
