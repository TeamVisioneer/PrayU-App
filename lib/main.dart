import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'dart:io';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:appinio_social_share/appinio_social_share.dart';
import 'widgets/network_error_view.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'services/image_download_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:app_links/app_links.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'dart:async';

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
  final AppinioSocialShare _socialShare = AppinioSocialShare();

  String baseUrl = dotenv.env['BASE_URL'] ?? 'https://www.prayu.site';
  bool isError = false;
  String? _pendingNotificationUrl;
  StreamSubscription<Uri>? _linkSubscription;
  late AppLinks _appLinks;

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

  // Initialize deep link handling
  Future<void> _initializeDeepLinkHandling() async {
    try {
      _appLinks = AppLinks();

      // Handle initial deep link when app is opened from cold start
      final initialUri = await _appLinks.getInitialLink();
      if (initialUri != null) {
        _handleDeepLink(initialUri);
      }

      // Listen for deep links when app is already running
      _linkSubscription = _appLinks.uriLinkStream.listen(
        (Uri uri) {
          _handleDeepLink(uri);
        },
        onError: (err) {
          debugPrint('Deep link error: $err');
        },
      );
    } catch (e) {
      debugPrint('Failed to initialize deep link handling: $e');
    }
  }

  // Handle deep link URL
  void _handleDeepLink(Uri uri) {
    debugPrint('Deep link received: $uri');

    try {
      if (uri.scheme == 'prayu') {
        // Handle custom scheme: prayu://path -> https://www.prayu.site/path
        debugPrint('uri.path: ${uri.path}');
        String webUrl = '$baseUrl${uri.path}';

        // Add query parameters if any
        if (uri.query.isNotEmpty) {
          webUrl += '?${uri.query}';
        }

        debugPrint('Converting deep link to web URL: $webUrl');
        _performWebViewNavigation(webUrl);
      } else if (uri.scheme == 'https' && uri.host.endsWith('.prayu.site')) {
        // Handle Universal Links/App Links: https://*.prayu.site/path -> navigate directly
        debugPrint('Universal Link received: $uri');
        _performWebViewNavigation(uri.toString());
      }
    } catch (e) {
      debugPrint('Error parsing deep link: $e');
    }
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

    // Initialize deep link handling
    _initializeDeepLinkHandling();
  }

  @override
  void dispose() {
    OneSignal.Notifications.removeClickListener(_handlePushNotificationClicked);
    _linkSubscription?.cancel();
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
            bottom: Platform.isIOS ? false : true,
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

                      // Add a new JavaScript handler for app review requests
                      webViewController?.addJavaScriptHandler(
                        handlerName: 'requestAppReview',
                        callback: (args) async {
                          final InAppReview inAppReview = InAppReview.instance;
                          if (await inAppReview.isAvailable()) {
                            inAppReview.requestReview();
                            return {
                              'status': 'success',
                              'message': 'Review requested.'
                            };
                          } else {
                            return {
                              'status': 'unavailable',
                              'message': 'In-app review is not available.'
                            };
                          }
                        },
                      );

                      // Add a new JavaScript handler for haptic feedback
                      webViewController?.addJavaScriptHandler(
                        handlerName: 'triggerHapticFeedback',
                        callback: (args) async {
                          if (args[0] == 'lightImpact') {
                            HapticFeedback.lightImpact();
                          } else if (args[0] == 'mediumImpact') {
                            HapticFeedback.mediumImpact();
                          } else if (args[0] == 'heavyImpact') {
                            HapticFeedback.heavyImpact();
                          } else if (args[0] == 'selectionClick') {
                            HapticFeedback.selectionClick();
                          } else if (args[0] == 'vibrate') {
                            HapticFeedback.vibrate();
                          }
                          return {
                            'status': 'success',
                            'message': 'Haptic feedback triggered.'
                          };
                        },
                      );

                      webViewController?.addJavaScriptHandler(
                        handlerName: 'shareInstagramStory',
                        callback: (args) async {
                          String photoUrl = args[0];

                          String? facebookAppId = dotenv.env['FACEBOOK_APP_ID'];

                          if (facebookAppId == null) {
                            return {
                              'status': 'error',
                              'message': 'FACEBOOK_APP_ID not configured'
                            };
                          }

                          try {
                            final response =
                                await http.get(Uri.parse(photoUrl));
                            final cacheDirectory =
                                await getTemporaryDirectory();
                            final fileName = photoUrl.split('/').last;
                            final file =
                                File('${cacheDirectory.path}/$fileName');
                            await file.writeAsBytes(response.bodyBytes);

                            if (Platform.isIOS) {
                              await _socialShare.iOS.shareToInstagramStory(
                                  facebookAppId,
                                  stickerImage: file.path,
                                  backgroundTopColor: '#ffffff',
                                  backgroundBottomColor: '#70AAFF',
                                  attributionURL: 'https://www.prayu.site');
                            } else if (Platform.isAndroid) {
                              await _socialShare.android.shareToInstagramStory(
                                  facebookAppId,
                                  stickerImage: file.path,
                                  backgroundTopColor: '#ffffff',
                                  backgroundBottomColor: '#70AAFF',
                                  attributionURL: 'https://www.prayu.site');
                            }
                            return {
                              'status': 'success',
                              'message': 'Instagram story sharing initiated.',
                            };
                          } catch (e) {
                            return {'status': 'error', 'message': e.toString()};
                          }
                        },
                      );

                      // Add JavaScript handler for image download (handles both single and multiple)
                      webViewController?.addJavaScriptHandler(
                        handlerName: 'downloadImages',
                        callback: (args) async {
                          debugPrint('=== downloadImages 호출 시작 ===');
                          debugPrint('전달받은 args: $args');

                          if (args.isEmpty) {
                            debugPrint('에러: args가 비어있음');
                            return {
                              'status': 'error',
                              'message': 'Image URL(s) required'
                            };
                          }

                          // 단일 URL 문자열 또는 URL 배열 모두 처리
                          List<String> imageUrls;
                          try {
                            if (args[0] is String) {
                              // 단일 이미지 URL
                              imageUrls = [args[0] as String];
                              debugPrint('단일 이미지 URL 감지: ${imageUrls[0]}');
                            } else if (args[0] is List) {
                              // 다중 이미지 URL
                              imageUrls = (args[0] as List)
                                  .map((url) => url.toString())
                                  .toList();
                              debugPrint('다중 이미지 URL 감지: ${imageUrls.length}개');
                              for (int i = 0; i < imageUrls.length; i++) {
                                debugPrint('  [$i]: ${imageUrls[i]}');
                              }
                            } else {
                              debugPrint(
                                  '에러: 잘못된 URL 형식 - ${args[0].runtimeType}');
                              return {
                                'status': 'error',
                                'message':
                                    'First argument must be a string URL or array of URLs'
                              };
                            }
                          } catch (e) {
                            debugPrint('에러: URL 파싱 실패 - $e');
                            return {
                              'status': 'error',
                              'message': 'Invalid image URL(s) format'
                            };
                          }

                          if (imageUrls.isEmpty) {
                            debugPrint('에러: 파싱된 URL이 비어있음');
                            return {
                              'status': 'error',
                              'message': 'No image URLs provided'
                            };
                          }

                          // 권한 확인 및 요청 - gal 패키지가 자동으로 처리
                          debugPrint('=== 이미지 다운로드 시작 ===');
                          debugPrint('gal 패키지를 사용하여 자동 권한 처리 진행');

                          // 선택적 매개변수 처리 (단일 이미지의 경우 기본값 1)
                          int maxConcurrent = imageUrls.length == 1 ? 1 : 3;
                          if (args.length > 1 && args[1] is int) {
                            maxConcurrent = args[1] as int;
                            // 안전한 범위로 제한
                            maxConcurrent = maxConcurrent.clamp(1, 10);
                          }
                          debugPrint('동시 다운로드 설정: $maxConcurrent개');

                          debugPrint('=== 이미지 다운로드 시작 ===');
                          try {
                            final result = await ImageDownloadService
                                .downloadMultipleImagesToGallery(
                              imageUrls,
                              maxConcurrent: maxConcurrent,
                            );

                            debugPrint('이미지 다운로드 완료 결과: $result');
                            debugPrint('=== downloadImages 완료 ===');
                            return result;
                          } catch (e) {
                            debugPrint('이미지 다운로드 중 예외 발생: $e');
                            final errorResult = {
                              'status': 'error',
                              'message': 'Error: ${e.toString()}',
                              'total': imageUrls.length,
                              'success': 0,
                              'failed': imageUrls.length,
                            };
                            debugPrint('다운로드 에러 결과 반환: $errorResult');
                            return errorResult;
                          }
                        },
                      );

                      // Add JavaScript handler for opening app settings
                      webViewController?.addJavaScriptHandler(
                        handlerName: 'openAppSettings',
                        callback: (args) async {
                          try {
                            final bool opened = await openAppSettings();
                            return {
                              'status': opened ? 'success' : 'error',
                              'message': opened
                                  ? '설정 페이지를 열었습니다.'
                                  : '설정 페이지를 열 수 없습니다.'
                            };
                          } catch (e) {
                            return {
                              'status': 'error',
                              'message': 'Error: ${e.toString()}'
                            };
                          }
                        },
                      );

                      // Add JavaScript handler for getting app version
                      webViewController?.addJavaScriptHandler(
                        handlerName: 'getAppVersion',
                        callback: (args) async {
                          try {
                            PackageInfo packageInfo =
                                await PackageInfo.fromPlatform();
                            return {
                              'status': 'success',
                              'version': packageInfo.version,
                              'buildNumber': packageInfo.buildNumber,
                              'appName': packageInfo.appName,
                              'packageName': packageInfo.packageName,
                              'platform': Platform.isIOS ? 'ios' : 'android',
                            };
                          } catch (e) {
                            return {
                              'status': 'error',
                              'message':
                                  'Error getting app version: ${e.toString()}'
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
