import 'package:flutter/material.dart';

import 'pages/home_page.dart';

void main() {
  runApp(const DouyinDownloaderApp());
}

class DouyinDownloaderApp extends StatelessWidget {
  const DouyinDownloaderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '抖音视频备份',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFFE2C55)),
        scaffoldBackgroundColor: const Color(0xFFF6F7F9),
      ),
      home: const HomePage(),
    );
  }
}
