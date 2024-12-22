import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'dart:io';
import 'package:onesignal_flutter/onesignal_flutter.dart';

void main() async {
  const environment = String.fromEnvironment('ENV', defaultValue: 'staging');
  await dotenv.load(fileName: '.env.$environment');
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    OneSignal.Debug.setLogLevel(OSLogLevel.verbose);
    OneSignal.initialize(dotenv.env['ONESIGNAL_APP_ID'] ?? '');
    OneSignal.Notifications.requestPermission(true);

    return const MaterialApp(
      locale: Locale('ko', 'KR'),
      supportedLocales: [
        Locale('en', 'US'),
        Locale('ko', 'KR'),
      ],
      debugShowCheckedModeBanner: false,
      home: WebView(),
    );
  }
}

class WebView extends StatefulWidget {
  const WebView({super.key});

  @override
  WebViewState createState() => WebViewState();
}

class WebViewState extends State<WebView> {
  late InAppWebViewController webViewController;
  final String platform = Platform.isIOS ? "prayu-ios" : "prayu-android";
  final String baseUrl = dotenv.env['BASE_URL'] ?? 'https://www.prayu.site';
  final MethodChannel channel =
      const MethodChannel("com.team.visioneer.prayu/intent");

  String? extractFallbackUrl(String intentUrl) {
    try {
      List<String> parts = intentUrl.split(';');

      for (String part in parts) {
        if (part.startsWith('S.browser_fallback_url=')) {
          String encodedFallbackUrl = part.split('=')[1];
          return Uri.decodeFull(encodedFallbackUrl);
        }
      }
    } catch (e) {
      return null;
    }
    return null;
  }

  Future<NavigationActionPolicy> _shouldOverrideUrlLoading(
      InAppWebViewController controller,
      NavigationAction navigationAction) async {
    final uri = navigationAction.request.url!;
    final url = uri.toString();
    if (uri.scheme == "intent") {
      final result = await channel.invokeMethod("handleIntent", {"url": url});
      if (result == false) {
        final fallbackUrl = extractFallbackUrl(url);
        if (fallbackUrl != null) {
          await controller.loadUrl(
            urlRequest: URLRequest(
              url: WebUri(fallbackUrl),
              headers: {'Accept-Language': 'ko-KR'},
            ),
          );
        }
      }
      return NavigationActionPolicy.CANCEL;
    }
    return NavigationActionPolicy.ALLOW;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (await webViewController.canGoBack()) {
          webViewController.goBack();
        } else if (context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        body: Container(
          color: const Color(0xFFF2F3FD),
          child: SafeArea(
            child: InAppWebView(
              initialUrlRequest: URLRequest(
                url: WebUri(baseUrl),
                headers: {'Accept-Language': 'ko-KR'},
              ),
              initialSettings: InAppWebViewSettings(
                javaScriptEnabled: true,
                javaScriptCanOpenWindowsAutomatically: true,
                useOnDownloadStart: true,
                useShouldOverrideUrlLoading: true,
                supportMultipleWindows: true,
              ),
              shouldOverrideUrlLoading: _shouldOverrideUrlLoading,
              onWebViewCreated: (controller) async {
                webViewController = controller;
                String? currentUserAgent = await webViewController
                    .evaluateJavascript(source: 'navigator.userAgent;');
                String userAgent =
                    Platform.isIOS ? "prayu-ios" : "prayu-android";
                String newUserAgent = '$currentUserAgent $userAgent';
                await webViewController.setSettings(
                    settings: InAppWebViewSettings(
                  userAgent: newUserAgent,
                  javaScriptEnabled: true,
                  javaScriptCanOpenWindowsAutomatically: true,
                  useOnDownloadStart: true,
                  useShouldOverrideUrlLoading: true,
                  supportMultipleWindows: true,
                ));

                webViewController.addJavaScriptHandler(
                  handlerName: 'onLogin',
                  callback: (args) async {
                    String userId = args[0];
                    try {
                      await OneSignal.login(userId);
                      return {'status': 'success', 'userId': userId};
                    } catch (error) {
                      return {'status': 'error', 'message': error.toString()};
                    }
                  },
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
