import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

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

  Future<void> schedulePendingOrderReminder(int id, String title, String body) async {
    try {
      // Schedule the first reminder after 10 minutes
      final scheduledTime = DateTime.now().add(const Duration(minutes: 10));
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
            icon: '@mipmap/res/mipmap-xxhdpi/launcher_icon.png',
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.time, // This makes it somewhat repeating, but for strict 10m intervals we need a better approach or multiple schedules
      );
    } catch (e) {
      print("Notification Scheduling Error: $e");
    }
  }

  // To strictly follow the "every 10 minutes" requirement for a specific order
  Future<void> scheduleRepeatingReminder(int txId, String title, String body) async {
    // We can schedule multiple reminders or use a repeating notification if supported
    // For simplicity and reliability across Android versions, we'll schedule the next one when this one is shown or handle it via a background task.
    // However, flutter_local_notifications supports periodiShow but with limited intervals (hourly, daily, etc.)
    
    // Custom logic: Schedule 5 reminders, 10 minutes apart
    for (int i = 1; i <= 6; i++) {
      final id = txId * 100 + i; // Unique ID for each reminder instance
      final scheduledTime = DateTime.now().add(Duration(minutes: 10 * i));
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
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      );
    }
  }

  Future<void> cancelOrderReminders(int txId) async {
    // Cancel all instances scheduled for this transaction
    for (int i = 1; i <= 6; i++) {
      await flutterLocalNotificationsPlugin.cancel(txId * 100 + i);
    }
    await flutterLocalNotificationsPlugin.cancel(txId);
  }

  Future<void> cancelAllNotifications() async {
    await flutterLocalNotificationsPlugin.cancelAll();
  }
}
