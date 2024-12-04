import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

void main() async {
  await dotenv.load();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        color: const Color(0xFFF2F3FD),
        child: SafeArea(
          child: InAppWebView(
            initialUrlRequest: URLRequest(
              url: WebUri(baseUrl),
            ),
            onWebViewCreated: (controller) {
              webViewController = controller;
            },
          ),
        ),
      ),
    );
  }
}
