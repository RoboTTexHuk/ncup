import 'dart:async';
import 'dart:convert';
import 'dart:io'
    show Platform, HttpHeaders, HttpClient, HttpClientRequest, HttpClientResponse;
import 'dart:math' as math;
import 'dart:ui';

import 'package:appsflyer_sdk/appsflyer_sdk.dart' as appsflyer_core;
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show MethodChannel, SystemChrome, SystemUiOverlayStyle, MethodCall;
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:http/http.dart' as http;
import 'package:ncup/psuh.dart' hide NcupLoaderPainter, NcupLoader; // если не нужен – уберите
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz_zone;

import 'appGame.dart';

// ============================================================================
// Константы
// ============================================================================

const String dressRetroLoadedOnceKey = 'loaded_once';
const String dressRetroStatEndpoint = 'https://data.ncup.team/stat';
const String dressRetroCachedFcmKey = 'cached_fcm';
const String dressRetroCachedDeepKey = 'cached_deep_push_uri';

// ---------------------- Банк: схемы и домены ----------------------

const Set<String> kBankSchemes = {
  'td',
  'rbc',
  'cibc',
  'scotiabank',
  'bmo',
  'bmodigitalbanking',
  'desjardins',
  'tangerine',
  'nationalbank',
  'simplii',
  'dominotoronto',
};

const Set<String> kBankDomains = {
  'td.com',
  'tdcanadatrust.com',
  'easyweb.td.com',
  'rbc.com',
  'royalbank.com',
  'online.royalbank.com',
  'cibc.com',
  'cibc.ca',
  'online.cibc.com',
  'scotiabank.com',
  'scotiaonline.scotiabank.com',
  'bmo.com',
  'bmo.ca',
  'bmodigitalbanking.com',
  'desjardins.com',
  'tangerine.ca',
  'nbc.ca',
  'nationalbank.ca',
  'simplii.com',
  'simplii.ca',
  'dominotoronto.com',
  'dominobank.com',
};

// ============================================================================
// Лёгкие сервисы
// ============================================================================

class NcupLoggerService {
  static final NcupLoggerService SharedInstance =
  NcupLoggerService._InternalConstructor();

  NcupLoggerService._InternalConstructor();

  factory NcupLoggerService() => SharedInstance;

  final Connectivity NcupConnectivity = Connectivity();

  void NcupLogInfo(Object message) => debugPrint('[I] $message');
  void NcupLogWarn(Object message) => debugPrint('[W] $message');
  void NcupLogError(Object message) => debugPrint('[E] $message');
}

class NcupNetworkService {
  final NcupLoggerService NcupLogger = NcupLoggerService();

  Future<bool> NcupIsOnline() async {
    final List<ConnectivityResult> NcupResults =
    await NcupLogger.NcupConnectivity.checkConnectivity();
    return NcupResults.isNotEmpty &&
        !NcupResults.contains(ConnectivityResult.none);
  }

  Future<void> NcupPostJson(
      String url,
      Map<String, dynamic> data,
      ) async {
    try {
      await http.post(
        Uri.parse(url),
        headers: <String, String>{'Content-Type': 'application/json'},
        body: jsonEncode(data),
      );
    } catch (error) {
      NcupLogger.NcupLogError('postJson error: $error');
    }
  }
}

// ============================================================================
// Профиль устройства
// ============================================================================

class NcupDeviceProfile {
  String? NcupDeviceId;
  String? NcupSessionId = 'retrocar-session';
  String? NcupPlatformName;
  String? NcupOsVersion;
  String? NcupAppVersion;
  String? NcupLanguageCode;
  String? NcupTimezoneName;
  bool NcupPushEnabled = false;

  Future<void> NcupInitialize() async {
    final DeviceInfoPlugin ncupDeviceInfoPlugin = DeviceInfoPlugin();

    if (Platform.isAndroid) {
      final AndroidDeviceInfo ncupAndroidInfo =
      await ncupDeviceInfoPlugin.androidInfo;
      NcupDeviceId = ncupAndroidInfo.id;
      NcupPlatformName = 'android';
      NcupOsVersion = ncupAndroidInfo.version.release;
    } else if (Platform.isIOS) {
      final IosDeviceInfo ncupIosInfo = await ncupDeviceInfoPlugin.iosInfo;
      NcupDeviceId = ncupIosInfo.identifierForVendor;
      NcupPlatformName = 'ios';
      NcupOsVersion = ncupIosInfo.systemVersion;
    }

    final PackageInfo ncupPackageInfo = await PackageInfo.fromPlatform();
    NcupAppVersion = ncupPackageInfo.version;
    NcupLanguageCode = Platform.localeName.split('_').first;
    NcupTimezoneName = tz_zone.local.name;
    NcupSessionId = 'retrocar-${DateTime.now().millisecondsSinceEpoch}';
  }

  Map<String, dynamic> NcupToMap({String? fcmToken}) => <String, dynamic>{
    'fcm_token': fcmToken ?? 'missing_token',
    'device_id': NcupDeviceId ?? 'missing_id',
    'app_name': 'ncup',
    'instance_id': NcupSessionId ?? 'missing_session',
    'platform': NcupPlatformName ?? 'missing_system',
    'os_version': NcupOsVersion ?? 'missing_build',
    'app_version': NcupAppVersion ?? 'missing_app',
    'language': NcupLanguageCode ?? 'en',
    'timezone': NcupTimezoneName ?? 'UTC',
    'push_enabled': NcupPushEnabled,
  };
}

// ============================================================================
// AppsFlyer Spy
// ============================================================================

class NcupAnalyticsSpyService {
  appsflyer_core.AppsFlyerOptions? NcupAppsFlyerOptions;
  appsflyer_core.AppsflyerSdk? NcupAppsFlyerSdk;

  String NcupAppsFlyerUid = '';
  String NcupAppsFlyerData = '';

  void NcupStartTracking({VoidCallback? onUpdate}) {
    final appsflyer_core.AppsFlyerOptions ncupConfig =
    appsflyer_core.AppsFlyerOptions(
      afDevKey: 'qsBLmy7dAXDQhowM8V3ca4',
      appId: '6758657360',
      showDebug: true,
      timeToWaitForATTUserAuthorization: 0,
    );

    NcupAppsFlyerOptions = ncupConfig;
    NcupAppsFlyerSdk = appsflyer_core.AppsflyerSdk(ncupConfig);

    NcupAppsFlyerSdk?.initSdk(
      registerConversionDataCallback: true,
      registerOnAppOpenAttributionCallback: true,
      registerOnDeepLinkingCallback: true,
    );

    NcupAppsFlyerSdk?.startSDK(
      onSuccess: () =>
          NcupLoggerService().NcupLogInfo('RetroCarAnalyticsSpy started'),
      onError: (int code, String msg) => NcupLoggerService()
          .NcupLogError('RetroCarAnalyticsSpy error $code: $msg'),
    );

    NcupAppsFlyerSdk?.onInstallConversionData((dynamic value) {
      NcupAppsFlyerData = value.toString();
      onUpdate?.call();
    });

    NcupAppsFlyerSdk?.getAppsFlyerUID().then((dynamic value) {
      NcupAppsFlyerUid = value.toString();
      onUpdate?.call();
    });
  }
}

// ============================================================================
// Loader — большая красная N и подпись CUP
// ============================================================================


// ============================================================================
// FCM фон
// ============================================================================

@pragma('vm:entry-point')
Future<void> NcupFcmBackgroundHandler(RemoteMessage message) async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

  NcupLoggerService().NcupLogInfo('bg-fcm: ${message.messageId}');
  NcupLoggerService().NcupLogInfo('bg-data: ${message.data}');

  final dynamic ncupLink = message.data['uri'];
  if (ncupLink != null) {
    try {
      final SharedPreferences ncupPrefs =
      await SharedPreferences.getInstance();
      await ncupPrefs.setString(
        dressRetroCachedDeepKey,
        ncupLink.toString(),
      );
    } catch (e) {
      NcupLoggerService().NcupLogError('bg-fcm save deep failed: $e');
    }
  }
}

// ============================================================================
// FCM Bridge
// ============================================================================

class NcupFcmBridge {
  final NcupLoggerService NcupLogger = NcupLoggerService();
  String? NcupToken;
  final List<void Function(String)> NcupTokenWaiters =
  <void Function(String)>[];

  String? get NcupFcmToken => NcupToken;

  NcupFcmBridge() {
    const MethodChannel('com.example.fcm/token')
        .setMethodCallHandler((MethodCall call) async {
      if (call.method == 'setToken') {
        final String ncupTokenString = call.arguments as String;
        if (ncupTokenString.isNotEmpty) {
          NcupSetToken(ncupTokenString);
        }
      }
    });

    NcupRestoreToken();
  }

  Future<void> NcupRestoreToken() async {
    try {
      final SharedPreferences ncupPrefs =
      await SharedPreferences.getInstance();
      final String? ncupCachedToken =
      ncupPrefs.getString(dressRetroCachedFcmKey);
      if (ncupCachedToken != null && ncupCachedToken.isNotEmpty) {
        NcupSetToken(ncupCachedToken, notify: false);
      }
    } catch (_) {}
  }

  Future<void> NcupPersistToken(String newToken) async {
    try {
      final SharedPreferences ncupPrefs =
      await SharedPreferences.getInstance();
      await ncupPrefs.setString(dressRetroCachedFcmKey, newToken);
    } catch (_) {}
  }

  void NcupSetToken(
      String newToken, {
        bool notify = true,
      }) {
    NcupToken = newToken;
    NcupPersistToken(newToken);
    if (notify) {
      for (final void Function(String) ncupCallback
      in List<void Function(String)>.from(NcupTokenWaiters)) {
        try {
          ncupCallback(newToken);
        } catch (error) {
          NcupLogger.NcupLogWarn('fcm waiter error: $error');
        }
      }
      NcupTokenWaiters.clear();
    }
  }

  Future<void> NcupWaitForToken(
      Function(String token) ncupOnToken,
      ) async {
    try {
      await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      if ((NcupToken ?? '').isNotEmpty) {
        ncupOnToken(NcupToken!);
        return;
      }

      NcupTokenWaiters.add(ncupOnToken);
    } catch (error) {
      NcupLogger.NcupLogError('waitToken error: $error');
    }
  }
}

// ============================================================================
// Splash / Hall
// ============================================================================

class NcupHall extends StatefulWidget {
  const NcupHall({Key? key}) : super(key: key);

  @override
  State<NcupHall> createState() => _NcupHallState();
}

class _NcupHallState extends State<NcupHall> {
  final NcupFcmBridge NcupFcmBridgeInstance = NcupFcmBridge();
  bool NcupNavigatedOnce = false;
  Timer? NcupFallbackTimer;

  @override
  void initState() {
    super.initState();

    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.black,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
    ));

    // Ждём токен через мост
    NcupFcmBridgeInstance.NcupWaitForToken((String ncupToken) {
      NcupGoToHarbor(ncupToken);
    });

    // Фоллбек, если токен долго не приходит
    NcupFallbackTimer = Timer(
      const Duration(seconds: 8),
          () => NcupGoToHarbor(''),
    );
  }

  void NcupGoToHarbor(String ncupSignal) {
    if (NcupNavigatedOnce) return;
    NcupNavigatedOnce = true;
    NcupFallbackTimer?.cancel();

    Navigator.pushReplacement(
      context,
      MaterialPageRoute<Widget>(
        builder: (BuildContext context) => NcupHarbor(NcupSignal: ncupSignal),
      ),
    );
  }

  @override
  void dispose() {
    NcupFallbackTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Чистый чёрный экран + лоадер по центру, никаких плашек
    return Scaffold(
      backgroundColor: Colors.black,
      body: const SafeArea(
        child: Center(
          child:  NcupLoader(),
        ),
      ),
    );
  }
}

// ============================================================================
// ViewModel + Courier
// ============================================================================

class NcupBosunViewModel {
  final NcupDeviceProfile NcupDeviceProfileInstance;
  final NcupAnalyticsSpyService NcupAnalyticsSpyInstance;

  NcupBosunViewModel({
    required this.NcupDeviceProfileInstance,
    required this.NcupAnalyticsSpyInstance,
  });

  Map<String, dynamic> NcupDeviceMap(String? fcmToken) =>
      NcupDeviceProfileInstance.NcupToMap(fcmToken: fcmToken);

  Map<String, dynamic> NcupAppsFlyerPayload(
      String? token, {
        String? deepLink,
      }) =>
      <String, dynamic>{
        'content': <String, dynamic>{
          'af_data': NcupAnalyticsSpyInstance.NcupAppsFlyerData,
          'af_id': NcupAnalyticsSpyInstance.NcupAppsFlyerUid,
          'fb_app_name': 'ncup',
          'app_name': 'ncup',
          'deep': deepLink,
          'bundle_identifier': 'com.cupi.ncupi.ncup',
          'app_version': '1.0.0',
          'apple_id': '6758657360',
          'fcm_token': token ?? 'no_token',
          'device_id': NcupDeviceProfileInstance.NcupDeviceId ?? 'no_device',
          'instance_id': NcupDeviceProfileInstance.NcupSessionId ?? 'no_instance',
          'platform': NcupDeviceProfileInstance.NcupPlatformName ?? 'no_type',
          'os_version': NcupDeviceProfileInstance.NcupOsVersion ?? 'no_os',
          'app_version': NcupDeviceProfileInstance.NcupAppVersion ?? 'no_app',
          'language': NcupDeviceProfileInstance.NcupLanguageCode ?? 'en',
          'timezone': NcupDeviceProfileInstance.NcupTimezoneName ?? 'UTC',
          'push_enabled': NcupDeviceProfileInstance.NcupPushEnabled,
          'useruid': NcupAnalyticsSpyInstance.NcupAppsFlyerUid,
        },
      };
}

class NcupCourierService {
  final NcupBosunViewModel NcupBosun;
  final InAppWebViewController? Function() NcupGetWebViewController;

  NcupCourierService({
    required this.NcupBosun,
    required this.NcupGetWebViewController,
  });

  Future<void> NcupPutDeviceToLocalStorage(String? token) async {
    final InAppWebViewController? ncupController = NcupGetWebViewController();
    if (ncupController == null) return;

    final Map<String, dynamic> ncupMap = NcupBosun.NcupDeviceMap(token);
    await ncupController.evaluateJavascript(
      source:
      "localStorage.setItem('app_data', JSON.stringify(${jsonEncode(ncupMap)}));",
    );
  }

  Future<void> NcupSendRawToPage(
      String? token, {
        String? deepLink,
      }) async {
    final InAppWebViewController? ncupController = NcupGetWebViewController();
    if (ncupController == null) return;

    final Map<String, dynamic> ncupPayload =
    NcupBosun.NcupAppsFlyerPayload(token, deepLink: deepLink);
    final String ncupJsonString = jsonEncode(ncupPayload);

    NcupLoggerService().NcupLogInfo('SendRawData: $ncupJsonString');

    await ncupController.evaluateJavascript(
      source: 'sendRawData(${jsonEncode(ncupJsonString)});',
    );
  }
}

// ============================================================================
// Статистика / переходы
// ============================================================================

Future<String> NcupResolveFinalUrl(
    String startUrl, {
      int maxHops = 10,
    }) async {
  final HttpClient ncupHttpClient = HttpClient();

  try {
    Uri ncupCurrentUri = Uri.parse(startUrl);

    for (int ncupIndex = 0; ncupIndex < maxHops; ncupIndex++) {
      final HttpClientRequest ncupRequest =
      await ncupHttpClient.getUrl(ncupCurrentUri);
      ncupRequest.followRedirects = false;
      final HttpClientResponse ncupResponse = await ncupRequest.close();

      if (ncupResponse.isRedirect) {
        final String? ncupLocationHeader =
        ncupResponse.headers.value(HttpHeaders.locationHeader);
        if (ncupLocationHeader == null || ncupLocationHeader.isEmpty) {
          break;
        }

        final Uri ncupNextUri = Uri.parse(ncupLocationHeader);
        ncupCurrentUri = ncupNextUri.hasScheme
            ? ncupNextUri
            : ncupCurrentUri.resolveUri(ncupNextUri);
        continue;
      }

      return ncupCurrentUri.toString();
    }

    return ncupCurrentUri.toString();
  } catch (error) {
    debugPrint('goldenLuxuryResolveFinalUrl error: $error');
    return startUrl;
  } finally {
    ncupHttpClient.close(force: true);
  }
}

Future<void> NcupPostStat({
  required String event,
  required int timeStart,
  required String url,
  required int timeFinish,
  required String appSid,
  int? firstPageLoadTs,
}) async {
  try {
    final String ncupResolvedUrl = await NcupResolveFinalUrl(url);

    final Map<String, dynamic> ncupPayload = <String, dynamic>{
      'event': event,
      'timestart': timeStart,
      'timefinsh': timeFinish,
      'url': ncupResolvedUrl,
      'appleID': '6758657360',
      'open_count': '$appSid/$timeStart',
    };

    debugPrint('goldenLuxuryStat $ncupPayload');

    final http.Response ncupResponse = await http.post(
      Uri.parse('$dressRetroStatEndpoint/$appSid'),
      headers: <String, String>{
        'Content-Type': 'application/json',
      },
      body: jsonEncode(ncupPayload),
    );

    debugPrint(
        'goldenLuxuryStat resp=${ncupResponse.statusCode} body=${ncupResponse.body}');
  } catch (error) {
    debugPrint('goldenLuxuryPostStat error: $error');
  }
}

// ============================================================================
// Утилиты для банковских ссылок
// ============================================================================

bool NcupIsBankScheme(Uri uri) {
  final String scheme = uri.scheme.toLowerCase();
  return kBankSchemes.contains(scheme);
}

bool NcupIsBankDomain(Uri uri) {
  final String host = uri.host.toLowerCase();
  if (host.isEmpty) return false;

  for (final String bank in kBankDomains) {
    final String bankHost = bank.toLowerCase();
    if (host == bankHost || host.endsWith('.$bankHost')) {
      return true;
    }
  }
  return false;
}

Future<bool> NcupOpenBank(Uri uri) async {
  try {
    if (NcupIsBankScheme(uri)) {
      final bool ok = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      return ok;
    }

    if ((uri.scheme == 'http' || uri.scheme == 'https') &&
        NcupIsBankDomain(uri)) {
      final bool ok = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      return ok;
    }
  } catch (e) {
    debugPrint('NcupOpenBank error: $e; url=$uri');
  }
  return false;
}

// ============================================================================
// Заглушки экранов, которые у вас уже есть в проекте
// ============================================================================

// TODO: замените на ваш настоящий экран


// ============================================================================
// Главный WebView — Harbor
// ============================================================================

class NcupHarbor extends StatefulWidget {
  final String? NcupSignal;

  const NcupHarbor({super.key, required this.NcupSignal});

  @override
  State<NcupHarbor> createState() => _NcupHarborState();
}

class _NcupHarborState extends State<NcupHarbor>
    with WidgetsBindingObserver {
  InAppWebViewController? NcupWebViewController;
  final String NcupHomeUrl = 'https://data.ncup.team/';

  int NcupWebViewKeyCounter = 0;
  DateTime? NcupSleepAt;
  bool NcupVeilVisible = false;
  double NcupWarmProgress = 0.0;
  late Timer NcupWarmTimer;
  final int NcupWarmSeconds = 6;
  bool NcupCoverVisible = true;

  bool NcupLoadedOnceSent = false;
  int? NcupFirstPageTimestamp;

  NcupCourierService? NcupCourier;
  NcupBosunViewModel? NcupBosunInstance;

  String NcupCurrentUrl = '';
  int NcupStartLoadTimestamp = 0;

  final NcupDeviceProfile NcupDeviceProfileInstance = NcupDeviceProfile();
  final NcupAnalyticsSpyService NcupAnalyticsSpyInstance =
  NcupAnalyticsSpyService();

  final Set<String> NcupSpecialSchemes = <String>{
    'tg',
    'telegram',
    'whatsapp',
    'viber',
    'skype',
    'fb-messenger',
    'sgnl',
    'tel',
    'mailto',
    'bnl',
  };

  final Set<String> NcupExternalHosts = <String>{
    't.me',
    'telegram.me',
    'telegram.dog',
    'wa.me',
    'api.whatsapp.com',
    'chat.whatsapp.com',
    'm.me',
    'signal.me',
    'bnl.com',
    'www.bnl.com',
    'facebook.com',
    'www.facebook.com',
    'm.facebook.com',
    'instagram.com',
    'www.instagram.com',
    'twitter.com',
    'www.twitter.com',
    'x.com',
    'www.x.com',
  };

  String? NcupDeepLinkFromPush;
  String? _localFcmToken;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    NcupFirstPageTimestamp = DateTime.now().millisecondsSinceEpoch;

    // Скрываем крышку через 2 секунды
    Future<void>.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          NcupCoverVisible = false;
        });
      }
    });

    // Включаем вуаль через 7 секунд
    Future<void>.delayed(const Duration(seconds: 7), () {
      if (!mounted) return;
      setState(() {
        NcupVeilVisible = true;
      });
    });

    NcupBootHarbor();
    _initLocalFcmToken();
  }

  Future<void> _initLocalFcmToken() async {
    try {
      final String? t = await FirebaseMessaging.instance.getToken();
      if (mounted) {
        setState(() {
          _localFcmToken = t;
        });
      }
    } catch (e) {
      NcupLoggerService().NcupLogError('getToken error: $e');
    }
  }

  Future<void> NcupLoadLoadedFlag() async {
    final SharedPreferences ncupPrefs =
    await SharedPreferences.getInstance();
    NcupLoadedOnceSent = ncupPrefs.getBool(dressRetroLoadedOnceKey) ?? false;
  }

  Future<void> NcupSaveLoadedFlag() async {
    final SharedPreferences ncupPrefs =
    await SharedPreferences.getInstance();
    await ncupPrefs.setBool(dressRetroLoadedOnceKey, true);
    NcupLoadedOnceSent = true;
  }

  Future<void> NcupLoadCachedDeep() async {
    try {
      final SharedPreferences ncupPrefs =
      await SharedPreferences.getInstance();
      final String? ncupCached =
      ncupPrefs.getString(dressRetroCachedDeepKey);
      if ((ncupCached ?? '').isNotEmpty) {
        NcupDeepLinkFromPush = ncupCached;
      }
    } catch (_) {}
  }

  Future<void> NcupSaveCachedDeep(String uri) async {
    try {
      final SharedPreferences ncupPrefs =
      await SharedPreferences.getInstance();
      await ncupPrefs.setString(dressRetroCachedDeepKey, uri);
    } catch (_) {}
  }

  Future<void> NcupSendLoadedOnce({
    required String url,
    required int timestart,
  }) async {
    if (NcupLoadedOnceSent) {
      debugPrint('Loaded already sent, skip');
      return;
    }

    final int ncupNow = DateTime.now().millisecondsSinceEpoch;

    await NcupPostStat(
      event: 'Loaded',
      timeStart: timestart,
      timeFinish: ncupNow,
      url: url,
      appSid: NcupAnalyticsSpyInstance.NcupAppsFlyerUid,
      firstPageLoadTs: NcupFirstPageTimestamp,
    );

    await NcupSaveLoadedFlag();
  }

  void NcupBootHarbor() {
    NcupStartWarmProgress();
    NcupWireFcmHandlers();
    NcupAnalyticsSpyInstance.NcupStartTracking(
      onUpdate: () => setState(() {}),
    );
    NcupBindNotificationTap();
    NcupPrepareDeviceProfile();

    Future<void>.delayed(const Duration(seconds: 6), () async {
      await NcupPushDeviceInfo();
      await NcupPushAppsFlyerData();
    });
  }

  void NcupWireFcmHandlers() {
    FirebaseMessaging.onMessage.listen((RemoteMessage ncupMessage) async {
      final dynamic ncupLink = ncupMessage.data['uri'];
      if (ncupLink != null) {
        final String ncupUri = ncupLink.toString();
        NcupDeepLinkFromPush = ncupUri;
        await NcupSaveCachedDeep(ncupUri);
        NcupNavigateToUri(ncupUri);
      } else {
        NcupResetHomeAfterDelay();
      }
    });

    FirebaseMessaging.onMessageOpenedApp
        .listen((RemoteMessage ncupMessage) async {
      final dynamic ncupLink = ncupMessage.data['uri'];
      if (ncupLink != null) {
        final String ncupUri = ncupLink.toString();
        NcupDeepLinkFromPush = ncupUri;
        await NcupSaveCachedDeep(ncupUri);
        NcupNavigateToUri(ncupUri);
      } else {
        NcupResetHomeAfterDelay();
      }
    });
  }

  void NcupBindNotificationTap() {
    MethodChannel('com.example.fcm/notification')
        .setMethodCallHandler((MethodCall call) async {
      if (call.method == 'onNotificationTap') {
        final Map<String, dynamic> ncupPayload =
        Map<String, dynamic>.from(call.arguments);
        if (ncupPayload['uri'] != null &&
            !ncupPayload['uri'].toString().contains('Нет URI')) {
          final String ncupUri = ncupPayload['uri'].toString();
          NcupDeepLinkFromPush = ncupUri;
          await NcupSaveCachedDeep(ncupUri);

          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute<Widget>(
              builder: (BuildContext context) => NcupTableView(ncupUri),
            ),
                (Route<dynamic> route) => false,
          );
        }
      }
    });
  }

  Future<void> NcupPrepareDeviceProfile() async {
    try {
      await NcupDeviceProfileInstance.NcupInitialize();

      final FirebaseMessaging ncupMessaging = FirebaseMessaging.instance;
      final NotificationSettings ncupSettings =
      await ncupMessaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      NcupDeviceProfileInstance.NcupPushEnabled =
          ncupSettings.authorizationStatus ==
              AuthorizationStatus.authorized ||
              ncupSettings.authorizationStatus ==
                  AuthorizationStatus.provisional;

      await NcupLoadLoadedFlag();
      await NcupLoadCachedDeep();

      NcupBosunInstance = NcupBosunViewModel(
        NcupDeviceProfileInstance: NcupDeviceProfileInstance,
        NcupAnalyticsSpyInstance: NcupAnalyticsSpyInstance,
      );

      NcupCourier = NcupCourierService(
        NcupBosun: NcupBosunInstance!,
        NcupGetWebViewController: () => NcupWebViewController,
      );
    } catch (error) {
      NcupLoggerService().NcupLogError('prepareDeviceProfile fail: $error');
    }
  }

  void NcupNavigateToUri(String link) async {
    try {
      await NcupWebViewController?.loadUrl(
        urlRequest: URLRequest(url: WebUri(link)),
      );
    } catch (error) {
      NcupLoggerService().NcupLogError('navigate error: $error');
    }
  }

  void NcupResetHomeAfterDelay() {
    Future<void>.delayed(const Duration(seconds: 3), () {
      try {
        NcupWebViewController?.loadUrl(
          urlRequest: URLRequest(url: WebUri(NcupHomeUrl)),
        );
      } catch (_) {}
    });
  }

  String? _resolveTokenForShip() {
    if (widget.NcupSignal != null && widget.NcupSignal!.isNotEmpty) {
      return widget.NcupSignal;
    }
    if ((_localFcmToken ?? '').isNotEmpty) {
      return _localFcmToken;
    }
    return null;
  }

  Future<void> NcupPushDeviceInfo() async {
    final String? ncupToken = _resolveTokenForShip();

    NcupLoggerService().NcupLogInfo('TOKEN ship $ncupToken');
    try {
      await NcupCourier?.NcupPutDeviceToLocalStorage(
        ncupToken,
      );
    } catch (error) {
      NcupLoggerService().NcupLogError('pushDeviceInfo error: $error');
    }
  }

  Future<void> NcupPushAppsFlyerData() async {
    final String? ncupToken = _resolveTokenForShip();

    try {
      await NcupCourier?.NcupSendRawToPage(
        ncupToken,
        deepLink: NcupDeepLinkFromPush,
      );
    } catch (error) {
      NcupLoggerService().NcupLogError('pushAppsFlyerData error: $error');
    }
  }

  void NcupStartWarmProgress() {
    int ncupTick = 0;
    NcupWarmProgress = 0.0;

    NcupWarmTimer =
        Timer.periodic(const Duration(milliseconds: 100), (Timer timer) {
          if (!mounted) return;

          setState(() {
            ncupTick++;
            NcupWarmProgress = ncupTick / (NcupWarmSeconds * 10);

            if (NcupWarmProgress >= 1.0) {
              NcupWarmProgress = 1.0;
              NcupWarmTimer.cancel();
            }
          });
        });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      NcupSleepAt = DateTime.now();
    }

    if (state == AppLifecycleState.resumed) {
      if (Platform.isIOS && NcupSleepAt != null) {
        final DateTime ncupNow = DateTime.now();
        final Duration ncupDrift = ncupNow.difference(NcupSleepAt!);

        if (ncupDrift > const Duration(minutes: 25)) {
          NcupReboardHarbor();
        }
      }
      NcupSleepAt = null;
    }
  }

  void NcupReboardHarbor() {
    if (!mounted) return;

    WidgetsBinding.instance.addPostFrameCallback((Duration _) {
      if (!mounted) return;

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute<Widget>(
          builder: (BuildContext context) =>
              NcupHarbor(NcupSignal: widget.NcupSignal),
        ),
            (Route<dynamic> route) => false,
      );
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    NcupWarmTimer.cancel();
    super.dispose();
  }

  bool NcupIsBareEmail(Uri uri) {
    final String ncupScheme = uri.scheme;
    if (ncupScheme.isNotEmpty) return false;
    final String ncupRaw = uri.toString();
    return ncupRaw.contains('@') && !ncupRaw.contains(' ');
  }

  Uri NcupToMailto(Uri uri) {
    final String ncupFull = uri.toString();
    final List<String> ncupParts = ncupFull.split('?');
    final String ncupEmail = ncupParts.first;
    final Map<String, String> ncupQueryParams = ncupParts.length > 1
        ? Uri.splitQueryString(ncupParts[1])
        : <String, String>{};

    return Uri(
      scheme: 'mailto',
      path: ncupEmail,
      queryParameters:
      ncupQueryParams.isEmpty ? null : ncupQueryParams,
    );
  }

  bool NcupIsPlatformLink(Uri uri) {
    final String ncupScheme = uri.scheme.toLowerCase();
    if (NcupSpecialSchemes.contains(ncupScheme)) {
      return true;
    }

    if (ncupScheme == 'http' || ncupScheme == 'https') {
      final String ncupHost = uri.host.toLowerCase();

      if (NcupExternalHosts.contains(ncupHost)) {
        return true;
      }

      if (ncupHost.endsWith('t.me')) return true;
      if (ncupHost.endsWith('wa.me')) return true;
      if (ncupHost.endsWith('m.me')) return true;
      if (ncupHost.endsWith('signal.me')) return true;
      if (ncupHost.endsWith('facebook.com')) return true;
      if (ncupHost.endsWith('instagram.com')) return true;
      if (ncupHost.endsWith('twitter.com')) return true;
      if (ncupHost.endsWith('x.com')) return true;
    }

    return false;
  }

  String NcupDigitsOnly(String source) =>
      source.replaceAll(RegExp(r'[^0-9+]'), '');

  Uri NcupHttpizePlatformUri(Uri uri) {
    final String ncupScheme = uri.scheme.toLowerCase();

    if (ncupScheme == 'tg' || ncupScheme == 'telegram') {
      final Map<String, String> ncupQp = uri.queryParameters;
      final String? ncupDomain = ncupQp['domain'];

      if (ncupDomain != null && ncupDomain.isNotEmpty) {
        return Uri.https(
          't.me',
          '/$ncupDomain',
          <String, String>{
            if (ncupQp['start'] != null) 'start': ncupQp['start']!,
          },
        );
      }

      final String ncupPath = uri.path.isNotEmpty ? uri.path : '';

      return Uri.https(
        't.me',
        '/$ncupPath',
        uri.queryParameters.isEmpty ? null : uri.queryParameters,
      );
    }

    if ((ncupScheme == 'http' || ncupScheme == 'https') &&
        uri.host.toLowerCase().endsWith('t.me')) {
      return uri;
    }

    if (ncupScheme == 'viber') {
      return uri;
    }

    if (ncupScheme == 'whatsapp') {
      final Map<String, String> ncupQp = uri.queryParameters;
      final String? ncupPhone = ncupQp['phone'];
      final String? ncupText = ncupQp['text'];

      if (ncupPhone != null && ncupPhone.isNotEmpty) {
        return Uri.https(
          'wa.me',
          '/${NcupDigitsOnly(ncupPhone)}',
          <String, String>{
            if (ncupText != null && ncupText.isNotEmpty)
              'text': ncupText,
          },
        );
      }

      return Uri.https(
        'wa.me',
        '/',
        <String, String>{
          if (ncupText != null && ncupText.isNotEmpty)
            'text': ncupText,
        },
      );
    }

    if ((ncupScheme == 'http' || ncupScheme == 'https') &&
        (uri.host.toLowerCase().endsWith('wa.me') ||
            uri.host.toLowerCase().endsWith('whatsapp.com'))) {
      return uri;
    }

    if (ncupScheme == 'skype') {
      return uri;
    }

    if (ncupScheme == 'fb-messenger') {
      final String ncupPath =
      uri.pathSegments.isNotEmpty ? uri.pathSegments.join('/') : '';
      final Map<String, String> ncupQp = uri.queryParameters;

      final String ncupId = ncupQp['id'] ?? ncupQp['user'] ?? ncupPath;

      if (ncupId.isNotEmpty) {
        return Uri.https(
          'm.me',
          '/$ncupId',
          uri.queryParameters.isEmpty ? null : uri.queryParameters,
        );
      }

      return Uri.https(
        'm.me',
        '/',
        uri.queryParameters.isEmpty ? null : uri.queryParameters,
      );
    }

    if (ncupScheme == 'sgnl') {
      final Map<String, String> ncupQp = uri.queryParameters;
      final String? ncupPhone = ncupQp['phone'];
      final String? ncupUsername = ncupQp['username'];

      if (ncupPhone != null && ncupPhone.isNotEmpty) {
        return Uri.https(
          'signal.me',
          '/#p/${NcupDigitsOnly(ncupPhone)}',
        );
      }

      if (ncupUsername != null && ncupUsername.isNotEmpty) {
        return Uri.https(
          'signal.me',
          '/#u/$ncupUsername',
        );
      }

      final String ncupPath = uri.pathSegments.join('/');
      if (ncupPath.isNotEmpty) {
        return Uri.https(
          'signal.me',
          '/$ncupPath',
          uri.queryParameters.isEmpty ? null : uri.queryParameters,
        );
      }

      return uri;
    }

    if (ncupScheme == 'tel') {
      return Uri.parse('tel:${NcupDigitsOnly(uri.path)}');
    }

    if (ncupScheme == 'mailto') {
      return uri;
    }

    if (ncupScheme == 'bnl') {
      final String ncupNewPath = uri.path.isNotEmpty ? uri.path : '';
      return Uri.https(
        'bnl.com',
        '/$ncupNewPath',
        uri.queryParameters.isEmpty ? null : uri.queryParameters,
      );
    }

    return uri;
  }

  Future<bool> NcupOpenMailWeb(Uri mailto) async {
    final Uri ncupGmailUri = NcupGmailizeMailto(mailto);
    return NcupOpenWeb(ncupGmailUri);
  }

  Uri NcupGmailizeMailto(Uri mailUri) {
    final Map<String, String> ncupQueryParams = mailUri.queryParameters;

    final Map<String, String> ncupParams = <String, String>{
      'view': 'cm',
      'fs': '1',
      if (mailUri.path.isNotEmpty) 'to': mailUri.path,
      if ((ncupQueryParams['subject'] ?? '').isNotEmpty)
        'su': ncupQueryParams['subject']!,
      if ((ncupQueryParams['body'] ?? '').isNotEmpty)
        'body': ncupQueryParams['body']!,
      if ((ncupQueryParams['cc'] ?? '').isNotEmpty)
        'cc': ncupQueryParams['cc']!,
      if ((ncupQueryParams['bcc'] ?? '').isNotEmpty)
        'bcc': ncupQueryParams['bcc']!,
    };

    return Uri.https('mail.google.com', '/mail/', ncupParams);
  }

  Future<bool> NcupOpenWeb(Uri uri) async {
    try {
      if (await launchUrl(
        uri,
        mode: LaunchMode.inAppBrowserView,
      )) {
        return true;
      }

      return await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
    } catch (error) {
      debugPrint('openInAppBrowser error: $error; url=$uri');
      try {
        return await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );
      } catch (_) {
        return false;
      }
    }
  }

  Future<bool> NcupOpenExternal(Uri uri) async {
    try {
      return await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
    } catch (error) {
      debugPrint('openExternal error: $error; url=$uri');
      return false;
    }
  }

  void NcupHandleServerSavedata(String savedata) {
    debugPrint('onServerResponse savedata: $savedata');

    if (savedata == 'false') {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute<Widget>(
          builder: (BuildContext context) => const NcupWebContainerScreen2(),
        ),
            (Route<dynamic> route) => false,
      );
    } else if (savedata == 'true') {
      // остаёмся на вебе
    }
  }

  @override
  Widget build(BuildContext context) {
    NcupBindNotificationTap();

    Widget ncupContent = Column(
      children: [
        Expanded(
          child: Stack(
            children: <Widget>[
              if (NcupCoverVisible)
                const Center(child: NcupLoader())
              else
                Container(
                  color: Colors.black,
                  child: Stack(
                    children: <Widget>[
                      InAppWebView(
                        key: ValueKey<int>(NcupWebViewKeyCounter),
                        initialSettings:  InAppWebViewSettings(
                          javaScriptEnabled: true,
                          disableDefaultErrorPage: true,
                          mediaPlaybackRequiresUserGesture: false,
                          allowsInlineMediaPlayback: true,
                          allowsPictureInPictureMediaPlayback: true,
                          useOnDownloadStart: true,
                          javaScriptCanOpenWindowsAutomatically: true,
                          useShouldOverrideUrlLoading: true,
                          supportMultipleWindows: true,
                          transparentBackground: true,
                        ),
                        initialUrlRequest: URLRequest(
                          url: WebUri(NcupHomeUrl),
                        ),
                        onWebViewCreated:
                            (InAppWebViewController controller) {
                          NcupWebViewController = controller;

                          NcupBosunInstance ??= NcupBosunViewModel(
                            NcupDeviceProfileInstance:
                            NcupDeviceProfileInstance,
                            NcupAnalyticsSpyInstance:
                            NcupAnalyticsSpyInstance,
                          );

                          NcupCourier ??= NcupCourierService(
                            NcupBosun: NcupBosunInstance!,
                            NcupGetWebViewController: () =>
                            NcupWebViewController,
                          );

                          controller.addJavaScriptHandler(
                            handlerName: 'onServerResponse',
                            callback: (List<dynamic> args) {
                              debugPrint(
                                  'onServerResponse raw args: $args');

                              if (args.isEmpty) return null;

                              try {
                                if (args[0] is Map) {
                                  final dynamic ncupRaw =
                                  (args[0] as Map)['savedata'];

                                  debugPrint(
                                      "saveDATA ${ncupRaw.toString()}");
                                  NcupHandleServerSavedata(
                                      ncupRaw?.toString() ?? '');
                                } else if (args[0] is String) {
                                  NcupHandleServerSavedata(
                                      args[0] as String);
                                } else if (args[0] is bool) {
                                  NcupHandleServerSavedata(
                                      (args[0] as bool).toString());
                                }
                              } catch (e, st) {
                                debugPrint(
                                    'onServerResponse error: $e\n$st');
                              }

                              return null;
                            },
                          );
                        },
                        onLoadStart: (
                            InAppWebViewController controller,
                            Uri? uri,
                            ) async {
                          setState(() {
                            NcupStartLoadTimestamp =
                                DateTime.now().millisecondsSinceEpoch;
                          });

                          final Uri? ncupViewUri = uri;
                          if (ncupViewUri != null) {
                            if (NcupIsBareEmail(ncupViewUri)) {
                              try {
                                await controller.stopLoading();
                              } catch (_) {}
                              final Uri ncupMailto =
                              NcupToMailto(ncupViewUri);
                              await NcupOpenMailWeb(ncupMailto);
                              return;
                            }

                            final String ncupScheme =
                            ncupViewUri.scheme.toLowerCase();

                            if (NcupIsBankScheme(ncupViewUri)) {
                              try {
                                await controller.stopLoading();
                              } catch (_) {}
                              await NcupOpenBank(ncupViewUri);
                              return;
                            }

                            if (ncupScheme != 'http' &&
                                ncupScheme != 'https') {
                              try {
                                await controller.stopLoading();
                              } catch (_) {}
                            }
                          }
                        },
                        onLoadError: (
                            InAppWebViewController controller,
                            Uri? uri,
                            int code,
                            String message,
                            ) async {
                          final int ncupNow =
                              DateTime.now().millisecondsSinceEpoch;
                          final String ncupEvent =
                              'InAppWebViewError(code=$code, message=$message)';

                          await NcupPostStat(
                            event: ncupEvent,
                            timeStart: ncupNow,
                            timeFinish: ncupNow,
                            url: uri?.toString() ?? '',
                            appSid:
                            NcupAnalyticsSpyInstance.NcupAppsFlyerUid,
                            firstPageLoadTs: NcupFirstPageTimestamp,
                          );
                        },
                        onReceivedError: (
                            InAppWebViewController controller,
                            WebResourceRequest request,
                            WebResourceError error,
                            ) async {
                          final int ncupNow =
                              DateTime.now().millisecondsSinceEpoch;
                          final String ncupDescription =
                          (error.description ?? '').toString();
                          final String ncupEvent =
                              'WebResourceError(code=$error, message=$ncupDescription)';

                          await NcupPostStat(
                            event: ncupEvent,
                            timeStart: ncupNow,
                            timeFinish: ncupNow,
                            url: request.url?.toString() ?? '',
                            appSid:
                            NcupAnalyticsSpyInstance.NcupAppsFlyerUid,
                            firstPageLoadTs: NcupFirstPageTimestamp,
                          );
                        },
                        onLoadStop: (
                            InAppWebViewController controller,
                            Uri? uri,
                            ) async {
                          await NcupPushDeviceInfo();
                          await NcupPushAppsFlyerData();

                          setState(() {
                            NcupCurrentUrl = uri.toString();
                          });

                          Future<void>.delayed(
                            const Duration(seconds: 20),
                                () {
                              NcupSendLoadedOnce(
                                url: NcupCurrentUrl.toString(),
                                timestart: NcupStartLoadTimestamp,
                              );
                            },
                          );
                        },
                        shouldOverrideUrlLoading: (
                            InAppWebViewController controller,
                            NavigationAction action,
                            ) async {
                          final Uri? ncupUri = action.request.url;
                          if (ncupUri == null) {
                            return NavigationActionPolicy.ALLOW;
                          }

                          if (NcupIsBareEmail(ncupUri)) {
                            final Uri ncupMailto =
                            NcupToMailto(ncupUri);
                            await NcupOpenMailWeb(ncupMailto);
                            return NavigationActionPolicy.CANCEL;
                          }

                          final String ncupScheme =
                          ncupUri.scheme.toLowerCase();

                          if (NcupIsBankScheme(ncupUri)) {
                            await NcupOpenBank(ncupUri);
                            return NavigationActionPolicy.CANCEL;
                          }

                          if ((ncupScheme == 'http' ||
                              ncupScheme == 'https') &&
                              NcupIsBankDomain(ncupUri)) {
                            await NcupOpenBank(ncupUri);



                            // Трекинг Adobe (c00.adobe.com) → показываем свой экран
                            if (_isAdobeRedirect(ncupUri)) {
                              if (context.mounted) {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => AdobeRedirectScreen(uri: ncupUri),
                                  ),
                                );
                              }
                              return NavigationActionPolicy.CANCEL;
                            }
                            return NavigationActionPolicy.CANCEL;
                          }

                          if (ncupScheme == 'mailto') {
                            await NcupOpenMailWeb(ncupUri);
                            return NavigationActionPolicy.CANCEL;
                          }

                          if (ncupScheme == 'tel') {
                            await launchUrl(
                              ncupUri,
                              mode:
                              LaunchMode.externalApplication,
                            );
                            return NavigationActionPolicy.CANCEL;
                          }

                          final String ncupHost =
                          ncupUri.host.toLowerCase();
                          final bool ncupIsSocial =
                              ncupHost.endsWith('facebook.com') ||
                                  ncupHost.endsWith('instagram.com') ||
                                  ncupHost.endsWith('twitter.com') ||
                                  ncupHost.endsWith('x.com');

                          if (ncupIsSocial) {
                            await NcupOpenExternal(ncupUri);
                            return NavigationActionPolicy.CANCEL;
                          }

                          if (NcupIsPlatformLink(ncupUri)) {
                            final Uri ncupWebUri =
                            NcupHttpizePlatformUri(ncupUri);
                            await NcupOpenExternal(ncupWebUri);
                            return NavigationActionPolicy.CANCEL;
                          }

                          if (ncupScheme != 'http' &&
                              ncupScheme != 'https') {
                            return NavigationActionPolicy.CANCEL;
                          }

                          return NavigationActionPolicy.ALLOW;
                        },
                        onCreateWindow: (
                            InAppWebViewController controller,
                            CreateWindowAction request,
                            ) async {
                          final Uri? ncupUri = request.request.url;
                          if (ncupUri == null) {
                            return false;
                          }

                          if (NcupIsBankScheme(ncupUri) ||
                              ((ncupUri.scheme == 'http' ||
                                  ncupUri.scheme == 'https') &&
                                  NcupIsBankDomain(ncupUri))) {
                            await NcupOpenBank(ncupUri);
                            return false;
                          }

                          if (NcupIsBareEmail(ncupUri)) {
                            final Uri ncupMailto =
                            NcupToMailto(ncupUri);
                            await NcupOpenMailWeb(ncupMailto);
                            return false;
                          }

                          final String ncupScheme =
                          ncupUri.scheme.toLowerCase();

                          if (ncupScheme == 'mailto') {
                            await NcupOpenMailWeb(ncupUri);
                            return false;
                          }

                          if (ncupScheme == 'tel') {
                            await launchUrl(
                              ncupUri,
                              mode:
                              LaunchMode.externalApplication,
                            );
                            return false;
                          }

                          final String ncupHost =
                          ncupUri.host.toLowerCase();
                          final bool ncupIsSocial =
                              ncupHost.endsWith('facebook.com') ||
                                  ncupHost.endsWith('instagram.com') ||
                                  ncupHost.endsWith('twitter.com') ||
                                  ncupHost.endsWith('x.com');

                          if (ncupIsSocial) {
                            await NcupOpenExternal(ncupUri);
                            return false;
                          }

                          if (NcupIsPlatformLink(ncupUri)) {
                            final Uri ncupWebUri =
                            NcupHttpizePlatformUri(ncupUri);
                            await NcupOpenExternal(ncupWebUri);
                            return false;
                          }

                          if (ncupScheme == 'http' ||
                              ncupScheme == 'https') {
                            controller.loadUrl(
                              urlRequest: URLRequest(
                                url: WebUri(ncupUri.toString()),
                              ),
                            );
                          }

                          return false;
                        },
                        onDownloadStartRequest: (
                            InAppWebViewController controller,
                            DownloadStartRequest req,
                            ) async {
                          await NcupOpenExternal(req.url);
                        },
                      ),
                      Visibility(
                        visible: !NcupVeilVisible,
                        child: const Center(child: NcupLoader()),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SizedBox.expand(
          child: ColoredBox(
            color: Colors.black,
            child: ncupContent,
          ),
        ),
      ),
    );
  }

  /// Трекинговые ссылки Adobe, ведущие дальше в App Store
  bool _isAdobeRedirect(Uri uri) {
    final host = uri.host.toLowerCase();
    // пример: http://c00.adobe.com/...
    return host == 'c00.adobe.com';
  }
}
// ---------------------- Экран для c00.adobe.com ----------------------
class AdobeRedirectScreen extends StatelessWidget {
  final Uri uri;

  const AdobeRedirectScreen({super.key, required this.uri});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF111111),

      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                "Go to the App Store and download the app.",
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                ),
              ),
              const SizedBox(height: 24),

              const SizedBox(height: 40),

            ],
          ),
        ),
      ),
    );
  }
}
// ============================================================================
// main()
// ============================================================================

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp();
  FirebaseMessaging.onBackgroundMessage(NcupFcmBackgroundHandler);

  if (Platform.isAndroid) {
    await InAppWebViewController.setWebContentsDebuggingEnabled(true);
  }

  tz_data.initializeTimeZones();

  runApp(
    const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: NcupHall(),
    ),
  );
}