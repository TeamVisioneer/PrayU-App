import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'dart:io';
import 'package:onesignal_flutter/onesignal_flutter.dart';

void main() async {
  await dotenv.load();
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
  final String baseUrl = dotenv.env['BASE_URL'] ?? 'https://www.prayu.site';
  final String userAgent = Platform.isIOS ? "prayu-ios" : "prayu-android";

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
                userAgent: userAgent,
                javaScriptEnabled: true,
                javaScriptCanOpenWindowsAutomatically: true,
                useOnDownloadStart: true,
                useShouldOverrideUrlLoading: true,
              ),
              shouldOverrideUrlLoading: (controller, navigationAction) async {
                var uri = navigationAction.request.url!;
                if (uri.scheme == "intent") {
                  try {
                    String urlString = uri.toString();
                    String decodedUrl = Uri.decodeFull(urlString);
                    RegExp fallbackUrlRegExp =
                        RegExp(r"browser_fallback_url=([^;]+)");
                    Match? match = fallbackUrlRegExp.firstMatch(decodedUrl);
                    String? fallbackUrl = match?.group(1);

                    if (fallbackUrl != null) {
                      await controller.loadUrl(
                        urlRequest: URLRequest(
                          url: WebUri(fallbackUrl),
                          headers: {'Accept-Language': 'ko-KR'},
                        ),
                      );
                      return NavigationActionPolicy.CANCEL;
                    }
                  } catch (e) {
                    return NavigationActionPolicy.ALLOW;
                  }
                }
                return NavigationActionPolicy.ALLOW;
              },
              onWebViewCreated: (controller) {
                webViewController = controller;
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
