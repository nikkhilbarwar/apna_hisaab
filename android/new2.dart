import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();

  factory NotificationService() => _instance;

  NotificationService._internal();

  // Production settings: Schedule reminders every 10 mins for up to 3 hours (18 reminders)
  static const int _remindersCount = 18;
  static const int _intervalMinutes = 10;

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
  FlutterLocalNotificationsPlugin();

  Future<void> init() async {
    tz.initializeTimeZones();

    const AndroidInitializationSettings initializationSettingsAndroid =
    AndroidInitializationSettings('@mipmap/launcher_icon');

    const InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
    );

    await flutterLocalNotificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (details) {
        // Handle notification tap
      },
    );
  }

  Future<void> showNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    const AndroidNotificationDetails androidPlatformChannelSpecifics =
    AndroidNotificationDetails(
      'pending_orders',
      'Pending Orders',
      channelDescription: 'Notifications for pending orders',
      importance: Importance.max,
      priority: Priority.high,
    );
    const NotificationDetails platformChannelSpecifics =
    NotificationDetails(android: androidPlatformChannelSpecifics);

    await flutterLocalNotificationsPlugin.show(
      id,
      title,
      body,
      platformChannelSpecifics,
      payload: payload,
    );
  }

  /// Scheduled a single reminder (legacy/alternative method)
  Future<void> schedulePendingOrderReminder(int id, String title,
      String body) async {
    try {
      final scheduledTime = DateTime.now().add(
          const Duration(minutes: _intervalMinutes));
      final tzScheduledTime = tz.TZDateTime.from(scheduledTime, tz.local);

      await flutterLocalNotificationsPlugin.zonedSchedule(
        id,
        title,
        body,
        tzScheduledTime,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'pending_orders_repeating',
            'Pending Order Reminders',
            importance: Importance.max,
            priority: Priority.high,
            icon: 'launcher_icon', // Fixed: Resource name only
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
        UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.time,
      );
    } catch (e) {
      print("Notification Scheduling Error: $e");
    }
  }

  /// Schedules multiple reminders at 10-minute intervals for a specific transaction.
  /// Uses a unique ID range per transaction: [txId * 100 + 1] to [txId * 100 + _remindersCount]
  Future<void> scheduleRepeatingReminder(int txId, String title,
      String body) async {
    try {
      for (int i = 1; i <= _remindersCount; i++) {
        // unique ID per reminder instance to avoid overwriting previous scheduled ones
        final id = txId * 100 + i;
        final scheduledTime = DateTime.now().add(
            Duration(minutes: _intervalMinutes * i));
        final tzScheduledTime = tz.TZDateTime.from(scheduledTime, tz.local);

        await flutterLocalNotificationsPlugin.zonedSchedule(
          id,
          title,
          body,
          tzScheduledTime,
          const NotificationDetails(
            android: AndroidNotificationDetails(
              'pending_orders_reminders',
              'Pending Order Reminders',
              importance: Importance.max,
              priority: Priority.high,
              // Uses default app icon from initialization if not specified here
            ),
          ),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation
              .absoluteTime,
        );
      }
    } catch (e) {
      print("Error scheduling repeating reminders: $e");
    }
  }

  /// Cancels all scheduled reminders for a specific transaction ID.
  Future<void> cancelOrderReminders(int txId) async {
    try {
      // Cancel all instances in the predefined range
      for (int i = 1; i <= _remindersCount; i++) {
        await flutterLocalNotificationsPlugin.cancel(txId * 100 + i);
      }
      // Also cancel the base ID if it was used by schedulePendingOrderReminder
      await flutterLocalNotificationsPlugin.cancel(txId);
    } catch (e) {
      print("Error cancelling reminders: $e");
    }
  }

  Future<void> cancelAllNotifications() async {
    await flutterLocalNotificationsPlugin.cancelAll();
  }
}