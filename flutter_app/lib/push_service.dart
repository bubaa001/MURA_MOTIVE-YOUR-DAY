/// MURA push notifications via Firebase Cloud Messaging.
///
/// Every Android phone receives FCM natively — no third-party app needed.
/// Flow: after sign-in the app requests notification permission, fetches
/// the FCM device token, and registers it at POST /me/devices/ so the
/// backend can push habit streaks, goal wins, reminders, and automations.
///
/// Firebase is initialised with manual options (no google-services.json /
/// gradle plugin): the four values below are client-side identifiers that
/// ship inside the app binary anyway — safe to commit.
library;

import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'api.dart';
import 'refresh_bus.dart';

/// Client config for the MURA Firebase project (mura-c03d5).
const FirebaseOptions _muraFirebaseOptions = FirebaseOptions(
  apiKey: 'AIzaSyBIwwI948KXGUatY2WjjrMHoIYtmjm75Ao',
  projectId: 'mura-c03d5',
  messagingSenderId: '102152595160',
  appId: '1:102152595160:android:91a31bdef6a682011e99ad',
);

/// Android notification channel the system tray shows pushes under.
const String _channelId = 'mura_push';
const String _channelName = 'MURA notifications';

final FlutterLocalNotificationsPlugin _local =
    FlutterLocalNotificationsPlugin();

bool _firebaseReady = false;
String? _lastRegisteredToken;

/// Initialise Firebase + the local-notifications plugin (Android only).
/// Safe to call repeatedly; also safe when push is unavailable.
Future<void> initPush() async {
  if (!Platform.isAndroid || _firebaseReady) return;
  try {
    await Firebase.initializeApp(options: _muraFirebaseOptions);
    await _local.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );
    await _local
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(
          const AndroidNotificationChannel(
            _channelId,
            _channelName,
            importance: Importance.high,
          ),
        );
    _firebaseReady = true;
  } catch (e) {
    // Firebase unavailable (e.g. missing Play services on an emulator
    // image) — the app must keep working; the in-app feed still shows
    // every notification.
    debugPrint('push init skipped: $e');
  }
}

/// After a successful sign-in: ask permission, then register this device.
Future<void> registerForPush() async {
  if (!_firebaseReady) return;
  try {
    final messaging = FirebaseMessaging.instance;
    final settings = await messaging.requestPermission();
    if (settings.authorizationStatus != AuthorizationStatus.authorized &&
        settings.authorizationStatus != AuthorizationStatus.provisional) {
      return; // user said no — in-app feed only
    }
    final token = await messaging.getToken();
    await _registerToken(token);

    // Token rotation (Google refreshes these periodically).
    messaging.onTokenRefresh.listen(_registerToken);

    // Foreground pushes arrive as a stream, not the tray — display them.
    FirebaseMessaging.onMessage.listen(_showForeground);
  } catch (e) {
    debugPrint('push registration skipped: $e');
  }
}

Future<void> _registerToken(String? token) async {
  if (token == null || token.isEmpty || token == _lastRegisteredToken) return;
  await api.registerDevice(token);
  _lastRegisteredToken = token;
}

void _showForeground(RemoteMessage message) {
  final notification = message.notification;
  if (notification == null) return;
  _local.show(
    notification.hashCode,
    notification.title,
    notification.body,
    const NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        importance: Importance.high,
        priority: Priority.high,
        styleInformation: BigTextStyleInformation(''),
      ),
    ),
  );
  // A push while the app is open may add a feed item — let pages refetch.
  AppRefresh.instance.requestRefresh();
}
