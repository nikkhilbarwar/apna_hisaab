import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  Future<void> init() async {
    tz.initializeTimeZones();
    
    // Request permission for FCM
    NotificationSettings settings = await _fcm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      // Subscribe to a general topic for announcements
      await _fcm.subscribeToTopic('announcements');
      
      // Get token for debugging
      String? token = await _fcm.getToken();
      debugPrint("FCM Token: $token");
    }

    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/launcher_icon');

    const InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
    );

    // Create Notification Channels for Android
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'pending_orders',
      'Pending Orders',
      description: 'Notifications for pending orders',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
    );

    const AndroidNotificationChannel purchaseChannel = AndroidNotificationChannel(
      'purchase_reminders',
      'Purchase Reminders',
      description: 'Notifications for purchase reminders',
      importance: Importance.max,
      playSound: true,
    );

    final AndroidFlutterLocalNotificationsPlugin? androidImplementation =
        flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    if (androidImplementation != null) {
      await androidImplementation.createNotificationChannel(channel);
      await androidImplementation.createNotificationChannel(purchaseChannel);
    }

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
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.time,
      );
    } catch (e) {
      debugPrint("Notification Scheduling Error: $e");
    }
  }

  Future<void> schedulePurchaseReminder(int reminderId, String itemName, DateTime dueDate) async {
    try {
      final now = DateTime.now();
      
      // 1. Notification at exact time
      if (dueDate.isAfter(now)) {
        await _schedule(
          reminderId * 10 + 1,
          'Purchase Reminder: $itemName',
          'It\'s time to buy $itemName as planned.',
          dueDate,
        );
      }

      // 2. Notification 1 hour before
      final oneHourBefore = dueDate.subtract(const Duration(hours: 1));
      if (oneHourBefore.isAfter(now)) {
        await _schedule(
          reminderId * 10 + 2,
          'Upcoming Purchase: $itemName',
          'Reminder to buy $itemName in 1 hour.',
          oneHourBefore,
        );
      }
    } catch (e) {
      debugPrint("Purchase Reminder Scheduling Error: $e");
    }
  }

  Future<void> _schedule(int id, String title, String body, DateTime scheduledTime) async {
    final tzScheduledTime = tz.TZDateTime.from(scheduledTime, tz.local);
    await flutterLocalNotificationsPlugin.zonedSchedule(
      id,
      title,
      body,
      tzScheduledTime,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'purchase_reminders',
          'Purchase Reminders',
          importance: Importance.max,
          priority: Priority.high,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  Future<void> cancelPurchaseReminder(int reminderId) async {
    await flutterLocalNotificationsPlugin.cancel(reminderId * 10 + 1);
    await flutterLocalNotificationsPlugin.cancel(reminderId * 10 + 2);
  }

  Future<void> scheduleRepeatingReminder(int txId, String title, String body) async {
    for (int i = 1; i <= 6; i++) {
      final id = txId * 100 + i;
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
    for (int i = 1; i <= 6; i++) {
      await flutterLocalNotificationsPlugin.cancel(txId * 100 + i);
    }
    await flutterLocalNotificationsPlugin.cancel(txId);
  }

  Future<void> cancelAllNotifications() async {
    await flutterLocalNotificationsPlugin.cancelAll();
  }

  // Handle background messages
  static Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
    // If you're going to use other Firebase services in the background, such as Firestore,
    // make sure you call `await Firebase.initializeApp()` if required.
    debugPrint("Handling a background message: ${message.messageId}");
  }

  void setupInteractions() {
    // Handle foreground messages
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      if (message.notification != null) {
        showNotification(
          id: message.hashCode,
          title: message.notification!.title ?? '',
          body: message.notification!.body ?? '',
        );
      }
    });

    // Handle when the app is opened from a notification
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      debugPrint('A new onMessageOpenedApp event was published!');
      // Handle navigation if needed
    });
  }
}
