import 'dart:io';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WebView Login Demo',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: WebViewLogin(url: 'https://customer.maxnetplus.id/login'),
    );
  }
}

class WebViewLogin extends StatefulWidget {
  final String url;

  WebViewLogin({required this.url});

  @override
  _WebViewLoginState createState() => _WebViewLoginState();
}

class _WebViewLoginState extends State<WebViewLogin> {
  late WebViewController _controller;
  late FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000))
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (int progress) {
            print('Progress: $progress%');
          },
          onPageStarted: (String url) {
            print('Page started loading: $url');
          },
          onPageFinished: (String url) {
            print('Page finished loading: $url');
            _controller.runJavaScript('''
              document.querySelector('meta[name="viewport"]').setAttribute('content', 'width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no');
              document.body.style.touchAction = 'pan-x pan-y';
            ''');
          },
          onWebResourceError: (WebResourceError error) {
            print('Error loading web resource: ${error.description}');
          },
          onNavigationRequest: (NavigationRequest request) async {
            print('Navigating to: ${request.url}');
            if (request.url.toLowerCase().endsWith('.pdf') ||
                request.url.contains('/invoice/download/')) {
              print('Download request: ${request.url}');
              _handleDownload(request.url);
              return NavigationDecision.prevent;
            } else if (request.url.startsWith('whatsapp://')) {
              if (await canLaunch(request.url)) {
                await launch(request.url);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Could not launch WhatsApp')),
                );
              }
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.url))
      ..enableZoom(false)
      ..setUserAgent(
          'Mozilla/5.0 (Linux; Android 10) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.120 Mobile Safari/537.36');

    _initializeNotifications();
    _requestPermissions();
  }

  void _initializeNotifications() async {
    flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    final InitializationSettings initializationSettings =
        InitializationSettings(
      android: initializationSettingsAndroid,
    );

    await flutterLocalNotificationsPlugin.initialize(initializationSettings);
  }

  Future<String> _copyAssetToFile(String assetPath) async {
    final byteData = await DefaultAssetBundle.of(context).load(assetPath);
    final file = File(
        '${(await getTemporaryDirectory()).path}/${assetPath.split('/').last}');
    await file.writeAsBytes(byteData.buffer.asUint8List());
    return file.path;
  }

  Future<void> _showNotification(
      String title, String body, String assetPath) async {
    final largeIconPath = await _copyAssetToFile(assetPath);

    final AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      'download_channel',
      'Download Notifications',
      channelDescription: 'Channel for download notifications',
      importance: Importance.max,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher', // Use app launcher icon
      largeIcon: FilePathAndroidBitmap(largeIconPath),
    );
    final NotificationDetails platformChannelSpecifics =
        NotificationDetails(android: androidPlatformChannelSpecifics);

    await flutterLocalNotificationsPlugin.show(
      0,
      title,
      body,
      platformChannelSpecifics,
    );
  }

  void _requestPermissions() async {
    if (await Permission.manageExternalStorage.request().isGranted) {
      // Permissions are granted
    } else {
      // Permissions are denied, show an alert to the user
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please allow file management permission')),
      );
    }
  }

  Future<String> _getUniqueFilePath(String directory, String fileName) async {
    String filePath = '$directory/$fileName';
    String fileBaseName = fileName;
    String fileExtension = '';

    // Extract base name and extension
    if (fileName.contains('.')) {
      fileBaseName = fileName.substring(0, fileName.lastIndexOf('.'));
      fileExtension = fileName.substring(fileName.lastIndexOf('.'));
    } else {
      // Default to .pdf if no extension is found
      fileExtension = '.pdf';
    }

    // Ensure the file has the correct extension
    if (!fileBaseName.endsWith(fileExtension)) {
      fileBaseName = '$fileBaseName$fileExtension';
    }

    int counter = 1;
    while (await File(filePath).exists()) {
      filePath = '$directory/$fileBaseName($counter)$fileExtension';
      counter++;
    }

    return filePath;
  }

  void _handleDownload(String url) async {
    if (await Permission.manageExternalStorage.request().isGranted) {
      final directory =
          Directory('/storage/emulated/0/Download'); // Direktori Download
      final fileName = url.split('/').last;

      // Ensure the file has the correct extension
      String fileNameWithExtension = fileName;
      if (!fileName.contains('.')) {
        fileNameWithExtension = '$fileName.pdf';
      }

      String filePath =
          await _getUniqueFilePath(directory.path, fileNameWithExtension);

      try {
        Dio dio = Dio();
        await dio.download(url, filePath);
        _showNotification('Download Successful', 'File downloaded to $filePath',
            'assets/v.png');
      } catch (e) {
        _showNotification(
            'Download Failed', 'Download failed: $e', 'assets/alert.png');
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Storage permission denied')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            SizedBox(height: 20),
            Expanded(
              child: WebViewWidget(controller: _controller),
            ),
          ],
        ),
      ),
    );
  }
}
