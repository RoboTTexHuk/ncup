import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:url_launcher/url_launcher.dart'
    show launchUrl, LaunchMode, canLaunchUrl;

import 'main.dart';

const String baseUrl = "https://play.famobi.com/drift-cup-racing/"; // Замените на нужный сайт

// Простейший список фильтров URL (регулярки) для популярных рекламных доменов.
// Можно расширять/обновлять по желанию.
final NcupFilt = [
  r'.*doubleclick\.net/.*',
  r'.*googlesyndication\.com/.*',
  r'.*google-analytics\.com/.*',
  r'.*adservice\.google\..*/.*',
  r'.*googleadservices\.com/.*',
  r'.*gvt1\.com/.*',
  r'.*pubads\.g\.doubleclick\.net/.*',
  r'.*securepubads\.g\.doubleclick\.net/.*',
  r'.*pagead2\.googlesyndication\.com/.*',
  r'.*googleads\.g\.doubleclick\.net/.*',
  r'.*admob\.com/.*',
  r'.*adbrite\.com/.*',
  r'.*exponential\.com/.*',
  r'.*quantserve\.com/.*',
  r'.*scorecardresearch\.com/.*',
  r'.*zedo\.com/.*',
  r'.*adsafeprotected\.com/.*',
  r'.*teads\.tv/.*',
  r'.*outbrain\.com/.*',
  r'.*taboola\.com/.*',
  r'.*criteo\.com/.*',
  r'.*rubiconproject\.com/.*',
  r'.*pubmatic\.com/.*',
  r'.*openx\.net/.*',
  r'.*appnexus\.com/.*',
  r'.*adnxs\.com/.*',
  r'.*moatads\.com/.*',
  r'.*adsrvr\.org/.*',
  r'.*serving-sys\.com/.*',
  r'.*tremorhub\.com/.*',
  r'.*spotxchange\.com/.*',
  r'.*spotx\.tv/.*',
  r'.*smaato\.net/.*',
  r'.*loopme\.me/.*',
  r'.*inadco\.com/.*',
  r'.*tradedesk\.com/.*',
  r'.*smartadserver\.com/.*',
  r'.*betweendigital\.com/.*',
  r'.*bluestreak\.com/.*',
  r'.*contextweb\.com/.*',
  r'.*yandexadexchange\.net/.*',
  r'.*yadro\.ru/.*',
  r'.*myvisualiq\.net/.*',
  r'.*imrworldwide\.com/.*',
  r'.*mathtag\.com/.*',
  r'.*media\.net/.*',
  r'.*adblade\.com/.*',
  r'.*adform\.net/.*',
  r'.*bidr\.io/.*',
  r'.*bidswitch\.net/.*',
  r'.*facebook\.net/.*',
  r'.*connect\.facebook\.net/.*',
  r'.*facebook\.com/tr/.*',
  r'.*ads-twitter\.com/.*',
  r'.*analytics\.twitter\.com/.*',
  r'.*snapads\.com/.*',
  r'.*amazon-adsystem\.com/.*',
  r'.*amazonaws\.com/adserver/.*',
  r'.*flashtalking\.com/.*',
  r'.*lijit\.com/.*',
  r'.*revcontent\.com/.*',
  r'.*mgid\.com/.*',
  r'.*adroll\.com/.*',
  r'.*rlcdn\.com/.*',
  r'.*btrll\.com/.*',
  r'.*brightroll\.com/.*',
  r'.*wtp101\.com/.*',
  r'.*exoclick\.com/.*',
  r'.*hilltopads\.com/.*',
  r'.*adversalservers\.com/.*',
  r'.*undertone\.com/.*',
  r'.*gumgum\.com/.*',
  r'.*lkqd\.net/.*',
  r'.*liveintent\.com/.*',
  r'.*mgid\.com/.*',
  r'.*buysellads\.com/.*',
  r'.*adzerk\.net/.*',
  r'.*revjet\.com/.*',
  r'.*jfmedier\.dk/.*',
  r'.*popads\.net/.*',
  r'.*propellerads\.com/.*',
  r'.*adcolony\.com/.*',
  r'.*chartboost\.com/.*',
  r'.*vungle\.com/.*',
  r'.*applovin\.com/.*',
  r'.*ironsrc\.com/.*',
  r'.*unityads\.unity3d\.com/.*',
  r'.*tapjoy\.com/.*',
  r'.*kochava\.com/.*',
  r'.*singular\.net/.*',
  r'.*adjust\.com/.*',
  r'.*appsflyer\.com/.*',
  r'.*branch\.io/.*',
  r'.*tenjin\.io/.*',
  r'.*mixpanel\.com/.*',
  r'.*segment\.com/.*',
  r'.*newrelic\.com/.*',
  r'.*app-measurement\.com/.*',
  r'.*fabric\.io/.*',
  r'.*bugsnag\.com/.*',
  r'.*onesignal\.com/.*',
  r'.*clevertap\.com/.*',
  r'.*leanplum\.com/.*',
  r'.*braze\.com/.*',
  r'.*optimizely\.com/.*',
  r'.*hotjar\.com/.*',
  r'.*fullstory\.com/.*',
  r'.*contentsquare\.com/.*',
  r'.*mouseflow\.com/.*',
  r'.*luckyorange\.com/.*',
  r'.*crazyegg\.com/.*',
  r'.*heapanalytics\.com/.*',
  r'.*akamaihd\.net/ads/.*',
  r'.*akamaized\.net/ads/.*',
  r'.*cdn\.adexplosion\.com/.*',
  r'.*cdn\.adtrackers\.net/.*',
  r'.*bttrack\.net/.*',
];

class NcupWebContainerScreen2 extends StatefulWidget {
  const NcupWebContainerScreen2({super.key});

  @override
  State<NcupWebContainerScreen2> createState() =>
      _NcupWebContainerScreen2State();
}

class _NcupWebContainerScreen2State extends State<NcupWebContainerScreen2> {
  InAppWebViewController? NcupWebController;

  final List<ContentBlocker> NcupContentBlockers = [];
  bool NcupShowSplash = true;
  bool NcupShowLoader = true;
  bool NcupShowAdBlockingOverlay = false; // Плашка "Waiting…"
  bool NcupPageLoading = false;

  int NcupKeyCounter = 0;

  final List<String> NcupAdCssSelectors = [
    '.ad',
    '.ads',
    '.adsbox',
    '.adsbygoogle',
    '.ad-banner',
    '.ad-container',
    '.advert',
    '.advertisement',
    '.ad-unit',
    '.sponsor',
    '.sponsored',
    '.promo',
    '.rewarded-ad',
    '.video-ad',
    '.floating-ad',
    '.sticky-ad',
    '.prestitial',
    '.interstitial',
    '#ad',
    '#ads',
    '#banner',
    '.banner',
    '.privacy-info',
    '.notification'
  ];

  @override
  void initState() {
    super.initState();
    print("load game ");

    // Инициализируем блокировщики контента
    for (final String NcupAdUrlFilter in NcupFilt) {
      NcupContentBlockers.add(
        ContentBlocker(
          trigger: ContentBlockerTrigger(urlFilter: NcupAdUrlFilter),
          action: ContentBlockerAction(type: ContentBlockerActionType.BLOCK),
        ),
      );
    }

    NcupContentBlockers.add(
      ContentBlocker(
        trigger: ContentBlockerTrigger(urlFilter: ".cookie", resourceType: [
          ContentBlockerTriggerResourceType.RAW
        ]),
        action: ContentBlockerAction(
          type: ContentBlockerActionType.BLOCK,
          selector: ".notification",
        ),
      ),
    );

    NcupContentBlockers.add(
      ContentBlocker(
        trigger: ContentBlockerTrigger(urlFilter: ".cookie", resourceType: [
          ContentBlockerTriggerResourceType.RAW
        ]),
        action: ContentBlockerAction(
          type: ContentBlockerActionType.CSS_DISPLAY_NONE,
          selector: ".privacy-info",
        ),
      ),
    );

    NcupContentBlockers.add(
      ContentBlocker(
        trigger: ContentBlockerTrigger(urlFilter: ".*"),
        action: ContentBlockerAction(
          type: ContentBlockerActionType.CSS_DISPLAY_NONE,
          selector: ".banner, .banners, .ads, .ad, .advert",
        ),
      ),
    );

    // Короткий сплэш
    Future.delayed(const Duration(seconds: 2), () {
      if (!mounted) return;
      setState(() {
        NcupShowSplash = false;
        NcupShowLoader = true;
      });
      // Скрыть основной лоадер через 10 сек. или по факту первой загрузки
      Future.delayed(const Duration(seconds: 10), () {
        if (!mounted) return;
        setState(() => NcupShowLoader = false);
      });
    });
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> NcupTryStopLoading(InAppWebViewController NcupController) async {
    try {
      await NcupController.stopLoading();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: SafeArea(
        child: Scaffold(
          backgroundColor: Colors.black,
          body: Stack(
            children: [
              if (NcupShowSplash) const NcupLoader(),
              if (!NcupShowSplash)
                Container(
                  color: Colors.black,
                  child: Stack(
                    children: [
                      InAppWebView(
                        key: ValueKey<int>(NcupKeyCounter),
                        initialSettings: InAppWebViewSettings(
                          javaScriptEnabled: true,
                          disableDefaultErrorPage: true,
                          contentBlockers: NcupContentBlockers,
                          mediaPlaybackRequiresUserGesture: true,
                          allowsInlineMediaPlayback: true,
                          allowsPictureInPictureMediaPlayback: true,
                          useOnDownloadStart: true,
                          javaScriptCanOpenWindowsAutomatically: true,
                          useShouldOverrideUrlLoading: true,
                          supportMultipleWindows: true,
                          transparentBackground: false,
                          allowsBackForwardNavigationGestures: true,
                          preferredContentMode: UserPreferredContentMode.MOBILE,
                          // важно: скрипты будут также встраиваться во фреймы
                        ),
                        initialUrlRequest: URLRequest(url: WebUri(baseUrl)),
                        onWebViewCreated: (InAppWebViewController NcupC) {
                          NcupWebController = NcupC;
                        },
                        onLoadStart:
                            (InAppWebViewController NcupC, Uri? NcupU) async {
                          NcupPageLoading = true;
                          setState(() => NcupShowAdBlockingOverlay = true);
                        },
                        onLoadStop:
                            (InAppWebViewController NcupC, Uri? NcupU) async {
                          NcupPageLoading = false;
                          try {
                            await NcupC.evaluateJavascript(
                                source: "console.log('Page loaded');");
                          } catch (_) {}
        
                          if (mounted) {
                            setState(() => NcupShowAdBlockingOverlay = false);
                          }
                        },
                        onReceivedError: (
                            InAppWebViewController NcupC,
                            WebResourceRequest NcupReq,
                            WebResourceError NcupErr,
                            ) async {
                          if (mounted) {
                            setState(() => NcupShowAdBlockingOverlay = false);
                          }
                        },
                        shouldOverrideUrlLoading: (
                            InAppWebViewController NcupC,
                            NavigationAction NcupAction,
                            ) async {
                          final Uri? NcupUri = NcupAction.request.url;
                          if (NcupUri == null) {
                            return NavigationActionPolicy.ALLOW;
                          }
        
                          final String NcupScheme =
                          NcupUri.scheme.toLowerCase();
        
                          if (NcupScheme == 'mailto') {
                            await NcupOpenEmail(NcupUri);
                            return NavigationActionPolicy.CANCEL;
                          }
        
                          if (NcupScheme == 'tel') {
                            await launchUrl(
                              NcupUri,
                              mode: LaunchMode.externalApplication,
                            );
                            return NavigationActionPolicy.CANCEL;
                          }
        
                          // Блокировка не http/https
                          if (NcupScheme != 'http' && NcupScheme != 'https') {
                            return NavigationActionPolicy.CANCEL;
                          }
        
                          // При каждой навигации показываем overlay “Waiting…”
                          NcupPageLoading = true;
                          setState(() => NcupShowAdBlockingOverlay = true);
        
                          return NavigationActionPolicy.ALLOW;
                        },
                        onCreateWindow: (
                            InAppWebViewController NcupC,
                            CreateWindowAction NcupReq,
                            ) async {
                          final Uri? NcupUri = NcupReq.request.url;
                          if (NcupUri == null) return false;
        
                          final String NcupScheme =
                          NcupUri.scheme.toLowerCase();
                          if (NcupScheme == 'mailto') {
                            await NcupOpenEmail(NcupUri);
                            return false;
                          }
                          if (NcupScheme == 'tel') {
                            await launchUrl(
                              NcupUri,
                              mode: LaunchMode.externalApplication,
                            );
                            return false;
                          }
        
                          if (NcupScheme == 'http' || NcupScheme == 'https') {
                            NcupPageLoading = true;
                            setState(() => NcupShowAdBlockingOverlay = true);
                            NcupC.loadUrl(
                              urlRequest: URLRequest(url: WebUri.uri(NcupUri)));
                          }
                          return false;
                        },
                        onDownloadStartRequest: (
                            InAppWebViewController NcupC,
                            DownloadStartRequest NcupReq,
                            ) async {
                          await launchUrl(
                            NcupReq.url,
                            mode: LaunchMode.externalApplication,
                          );
                        },
                        onConsoleMessage: (
                            InAppWebViewController NcupController,
                            ConsoleMessage NcupMsg,
                            ) async {
                          // Можно тут ловить любые "savedata:" сигналы, если нужно
                        },
                      ),
        
        
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/* =========================
   Loader: большая красная N и слово CUP
   ========================= */

class NcupLoader extends StatefulWidget {
  const NcupLoader({Key? key}) : super(key: key);

  @override
  State<NcupLoader> createState() => _NcupLoaderState();
}

class _NcupLoaderState extends State<NcupLoader>
    with SingleTickerProviderStateMixin {
  late AnimationController NcupController;

  static const Color NcupBackgroundColor = Color(0xFF05071B);

  @override
  void initState() {
    super.initState();

    NcupController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
  }

  @override
  void dispose() {
    NcupController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: NcupBackgroundColor,
      child: AnimatedBuilder(
        animation: NcupController,
        builder: (BuildContext context, Widget? child) {
          final double NcupPhase =
              NcupController.value * 2 * 3.141592653589793;
          return CustomPaint(
            painter: NcupLoaderPainter(
              NcupPhase: NcupPhase,
            ),
            child: const SizedBox.expand(),
          );
        },
      ),
    );
  }
}

class NcupLoaderPainter extends CustomPainter {
  final double NcupPhase;

  NcupLoaderPainter({
    required this.NcupPhase,
  });

  @override
  void paint(Canvas NcupCanvas, Size NcupSize) {
    final double NcupWidth = NcupSize.width;
    final double NcupHeight = NcupSize.height;

    // Фон
    final Paint NcupBackgroundPaint = Paint()
      ..color = const Color(0xFF05071B)
      ..style = PaintingStyle.fill;
    NcupCanvas.drawRect(Offset.zero & NcupSize, NcupBackgroundPaint);

    // Лёгкое пульсирующее свечение позади
    final double NcupPulse =
        (sin(NcupPhase) + 1) / 2; // 0..1 (используем dart:ui sin)
    final Paint NcupGlowCirclePaint = Paint()
      ..style = PaintingStyle.fill
      ..shader = RadialGradient(
        colors: <Color>[
          Colors.red.withOpacity(0.20 + 0.20 * NcupPulse),
          Colors.transparent,
        ],
      ).createShader(
        Rect.fromCircle(
          center: Offset(NcupWidth * 0.5, NcupHeight * 0.4),
          radius: NcupHeight * (0.45 + 0.15 * NcupPulse),
        ),
      );
    NcupCanvas.drawCircle(
      Offset(NcupWidth * 0.5, NcupHeight * 0.4),
      NcupHeight * (0.45 + 0.15 * NcupPulse),
      NcupGlowCirclePaint,
    );

    // Большая буква "N"
    final double NcupBaseSize = NcupWidth * 0.35;
    final double NcupFontSize =
        NcupBaseSize + NcupPulse * (NcupBaseSize * 0.15);
    const String NcupLetter = 'N';
    const String NcupWord = 'CUP';

    final TextPainter NcupLetterPainter = TextPainter(
      text: TextSpan(
        text: NcupLetter,
        style: TextStyle(
          fontSize: NcupFontSize,
          fontWeight: FontWeight.w900,
          color: Colors.red.shade600,
          letterSpacing: 4,
          shadows: <Shadow>[
            Shadow(
              color: Colors.redAccent.withOpacity(0.8),
              blurRadius: 22 + 18 * NcupPulse,
              offset: const Offset(0, 0),
            ),
            Shadow(
              color: Colors.black.withOpacity(0.8),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: NcupWidth);

    final double NcupLetterX = (NcupWidth - NcupLetterPainter.width) / 2;
    final double NcupLetterY = (NcupHeight - NcupLetterPainter.height) / 2;
    final Offset NcupLetterOffset = Offset(NcupLetterX, NcupLetterY);

    // Glow-слой для N
    final Rect NcupLetterRect = Rect.fromCenter(
      center: Offset(NcupWidth / 2, NcupHeight / 2),
      width: NcupLetterPainter.width * 1.4,
      height: NcupLetterPainter.height * 1.8,
    );

    final Paint NcupGlowPaint = Paint()
      ..maskFilter =
      MaskFilter.blur(BlurStyle.normal, 28 + 24 * NcupPulse)
      ..color = Colors.red.withOpacity(0.7 + 0.2 * NcupPulse);

    NcupCanvas.saveLayer(NcupLetterRect, NcupGlowPaint);
    NcupLetterPainter.paint(NcupCanvas, NcupLetterOffset);
    NcupCanvas.restore();

    // Рисуем N поверх
    NcupLetterPainter.paint(NcupCanvas, NcupLetterOffset);

    // Слово "CUP" под буквой
    final double NcupCupFontSize = NcupWidth * 0.11;
    final TextPainter NcupCupPainter = TextPainter(
      text: TextSpan(
        text: NcupWord,
        style: TextStyle(
          fontSize: NcupCupFontSize,
          fontWeight: FontWeight.w600,
          color: Colors.red.shade100.withOpacity(0.95),
          letterSpacing: 5,
          shadows: <Shadow>[
            Shadow(
              color: Colors.redAccent.withOpacity(0.7),
              blurRadius: 12 + 10 * NcupPulse,
              offset: const Offset(0, 0),
            ),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: NcupWidth);

    final double NcupCupX = (NcupWidth - NcupCupPainter.width) / 2;
    final double NcupCupY =
        NcupLetterY + NcupLetterPainter.height + NcupHeight * 0.03;
    final Offset NcupCupOffset = Offset(NcupCupX, NcupCupY);

    NcupCupPainter.paint(NcupCanvas, NcupCupOffset);
  }

  @override
  bool shouldRepaint(covariant NcupLoaderPainter oldDelegate) =>
      oldDelegate.NcupPhase != NcupPhase;
}

/* =========================
   Утилиты
   ========================= */

Future<void> NcupOpenEmail(Uri NcupMailtoUri) async {
  try {
    await launchUrl(
      NcupMailtoUri,
      mode: LaunchMode.externalApplication,
    );
  } catch (e) {
    debugPrint("openEmail error: $e");
  }
}