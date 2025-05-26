import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'dart:io';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'widgets/network_error_view.dart';

void main() async {
  await dotenv.load();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
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

class WebViewState extends State<WebView> with WidgetsBindingObserver {
  InAppWebViewController? webViewController;
  final String platform = Platform.isIOS ? "prayu-ios" : "prayu-android";
  final MethodChannel channel =
      const MethodChannel("com.team.visioneer.prayu/intent");

  String baseUrl = dotenv.env['BASE_URL'] ?? 'https://www.prayu.site';
  bool isError = false;
  String? _pendingNotificationUrl;

  // New async method for OneSignal initialization and permission request
  Future<void> _initializeAndRequestOneSignal() async {
    OneSignal.initialize(dotenv.env['ONESIGNAL_APP_ID'] ?? '');

    final status = await OneSignal.Notifications.permissionNative();
    if (status == OSNotificationPermission.notDetermined) {
      await OneSignal.Notifications.requestPermission(true);
    }
    OneSignal.Notifications.clearAll();
    OneSignal.Notifications.addClickListener(_handlePushNotificationClicked);
    OneSignal.LiveActivities.setupDefault();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // iOS 상태바가 표시되도록 설정
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ));

    // Call the new async method
    _initializeAndRequestOneSignal();
  }

  @override
  void dispose() {
    OneSignal.Notifications.removeClickListener(_handlePushNotificationClicked);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      OneSignal.Notifications.clearAll();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (webViewController != null && await webViewController!.canGoBack()) {
          webViewController!.goBack();
        } else {
          SystemNavigator.pop();
        }
      },
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        body: Container(
          color: const Color(0xFFF2F3FD),
          child: SafeArea(
            top: true,
            bottom: false,
            child: isError
                ? NetworkErrorView(
                    onRetry: () {
                      setState(() {
                        isError = false;
                      });
                      webViewController?.reload();
                    },
                  )
                : InAppWebView(
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
                    onReceivedError: (controller, request, response) {
                      if ([
                        WebResourceErrorType.CANNOT_CONNECT_TO_HOST,
                        WebResourceErrorType.TIMEOUT,
                        WebResourceErrorType.HOST_LOOKUP,
                        WebResourceErrorType.NOT_CONNECTED_TO_INTERNET,
                        WebResourceErrorType.FAILED_SSL_HANDSHAKE,
                      ].contains(response.type)) {
                        setState(() {
                          isError = true;
                        });
                      }
                    },
                    onWebViewCreated: (controller) async {
                      webViewController = controller;
                      String? currentUserAgent = await webViewController
                          ?.evaluateJavascript(source: 'navigator.userAgent;');
                      String userAgent =
                          Platform.isIOS ? "prayu-ios" : "prayu-android";
                      String newUserAgent = '$currentUserAgent $userAgent';
                      await webViewController?.setSettings(
                          settings: InAppWebViewSettings(
                        userAgent: newUserAgent,
                        javaScriptEnabled: true,
                        javaScriptCanOpenWindowsAutomatically: true,
                        useOnDownloadStart: true,
                        useShouldOverrideUrlLoading: true,
                        supportMultipleWindows: true,
                      ));
                      webViewController?.addJavaScriptHandler(
                        handlerName: 'onLogin',
                        callback: (args) async {
                          String userId = args[0];
                          try {
                            await OneSignal.login(userId);
                            await OneSignal.User.pushSubscription.optIn();
                            await OneSignal.User.addTagWithKey(
                                "userId", userId);
                            return {'status': 'success', 'userId': userId};
                          } catch (error) {
                            return {
                              'status': 'error',
                              'message': error.toString()
                            };
                          }
                        },
                      );

                      // Process pending notification URL if any
                      if (_pendingNotificationUrl != null && mounted) {
                        _performWebViewNavigation(_pendingNotificationUrl!);
                      }
                    },
                  ),
          ),
        ),
      ),
    );
  }

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

  Future<void> _performWebViewNavigation(String url) async {
    if (webViewController != null && mounted) {
      await webViewController!.evaluateJavascript(source: '''
          window.postMessage({
            type: 'PUSH_NOTIFICATION_NAVIGATION',
            url: '$url'
          }, '*');
        ''');
      // Clear pending URL if this navigation was for it
      if (_pendingNotificationUrl == url) {
        setState(() {
          _pendingNotificationUrl = null;
        });
      }
    }
  }

  Future<void> _handlePushNotificationClicked(
      OSNotificationClickEvent event) async {
    final url = event.notification.additionalData?['url'] as String?;
    if (url == null) return;

    if (webViewController != null && mounted) {
      // WebView is ready, navigate directly
      _performWebViewNavigation(url);
    } else {
      // WebView is not ready (app likely launching), store the URL
      if (mounted) {
        setState(() {
          _pendingNotificationUrl = url;
        });
      } else {
        // If not mounted, store directly. This case should be rare if listener is setup in initState.
        _pendingNotificationUrl = url;
      }
    }
  }
}
