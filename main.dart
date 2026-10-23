import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_windows/webview_windows.dart' as win;
import 'package:window_manager/window_manager.dart';

// ======================= KONFIGURASI =======================
class ExamConfig {
  /// PIN pengawas untuk keluar / membuka kunci.
  static const String exitPin = '1234';

  /// Jumlah pelanggaran sebelum layar terkunci.
  static const int maxViolations = 3;

  /// Hanya domain ini (dan subdomainnya) yang boleh dibuka.
  static const List<String> allowedHosts = [
    'quizizz.com',
    'wayground.com',
    'kahoot.it',
    'kahoot.com',
    'docs.google.com',
    'forms.gle',
    'accounts.google.com',
    'socrative.com',
    'quizlet.com',
    'wordwall.net',
  ];

  static const Map<String, String> presets = {
    'Quizizz': 'https://quizizz.com',
    'Wayground': 'https://wayground.com',
    'Kahoot': 'https://kahoot.it',
    'Google Form': 'https://docs.google.com/forms',
  };
}

const MethodChannel _guard = MethodChannel('exam_guard');

bool isAllowedUrl(String url) {
  final u = Uri.tryParse(url);
  if (u == null) return false;
  if (u.scheme == 'about') return true;
  if (u.scheme != 'https' && u.scheme != 'http') return false;
  final h = u.host.toLowerCase();
  return ExamConfig.allowedHosts.any((a) => h == a || h.endsWith('.$a'));
}

// JS proteksi: blok klik kanan, copy/cut, dan shortcut devtools.
const String _protectJs = '''
document.addEventListener('contextmenu', function(e){ e.preventDefault(); });
['copy','cut'].forEach(function(t){
  document.addEventListener(t, function(e){ e.preventDefault(); });
});
document.addEventListener('keydown', function(e){
  var k = (e.key || '').toLowerCase();
  if (e.key === 'F12' ||
      (e.ctrlKey && e.shiftKey && ['i','j','c'].indexOf(k) >= 0) ||
      (e.ctrlKey && k === 'u')) { e.preventDefault(); }
});
''';

// ======================= MAIN =======================
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isWindows) {
    await windowManager.ensureInitialized();
  }
  runApp(const ExamApp());
}

class ExamApp extends StatelessWidget {
  const ExamApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Exam Browser',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF5B5BD6),
          brightness: Brightness.dark,
        ),
      ),
      home: const HomePage(),
    );
  }
}

// ======================= HALAMAN AWAL =======================
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _url = TextEditingController(text: 'https://quizizz.com');
  String? _error;

  void _start() {
    var t = _url.text.trim();
    if (!t.startsWith('http')) t = 'https://$t';
    if (!isAllowedUrl(t)) {
      setState(() => _error = 'Situs ini tidak ada di daftar yang diizinkan.');
      return;
    }
    setState(() => _error = null);
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => ExamPage(url: t)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.shield_moon, size: 72),
                  const SizedBox(height: 12),
                  const Text(
                    'Exam Browser',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Mode aman untuk ujian online',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white60),
                  ),
                  const SizedBox(height: 28),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.center,
                    children: ExamConfig.presets.entries
                        .map((e) => ActionChip(
                              label: Text(e.key),
                              onPressed: () =>
                                  setState(() => _url.text = e.value),
                            ))
                        .toList(),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _url,
                    keyboardType: TextInputType.url,
                    decoration: InputDecoration(
                      labelText: 'Link ujian',
                      errorText: _error,
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.link),
                    ),
                    onSubmitted: (_) => _start(),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _start,
                    icon: const Icon(Icons.lock),
                    label: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text('MULAI UJIAN'),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Setelah mulai: layar dikunci, screenshot diblokir, '
                    'pindah aplikasi dicatat sebagai pelanggaran.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ======================= HALAMAN UJIAN =======================
class ExamPage extends StatefulWidget {
  final String url;
  const ExamPage({super.key, required this.url});

  @override
  State<ExamPage> createState() => _ExamPageState();
}

class _ExamPageState extends State<ExamPage>
    with WidgetsBindingObserver, WindowListener {
  WebViewController? _android;
  final win.WebviewController _winCtrl = win.WebviewController();
  bool _winReady = false;

  int _violations = 0;
  bool _locked = false;
  bool _armed = false; // beri jeda awal agar tidak salah deteksi
  bool _wasPaused = false;
  bool _guardOn = false;
  Timer? _armTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _armTimer = Timer(const Duration(seconds: 3), () => _armed = true);
    _enableGuard();
    if (Platform.isWindows) {
      _initWindows();
    } else {
      _initAndroid();
    }
  }

  @override
  void dispose() {
    _armTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    if (_guardOn) _disableGuard();
    if (Platform.isWindows) _winCtrl.dispose();
    super.dispose();
  }

  // ---------- Proteksi ----------
  Future<void> _enableGuard() async {
    _guardOn = true;
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    if (Platform.isAndroid) {
      try {
        await _guard.invokeMethod('enable');
      } catch (_) {}
    }
    if (Platform.isWindows) {
      windowManager.addListener(this);
      await windowManager.setPreventClose(true);
      await windowManager.setFullScreen(true);
      await windowManager.setAlwaysOnTop(true);
    }
  }

  Future<void> _disableGuard() async {
    _guardOn = false;
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    if (Platform.isAndroid) {
      try {
        await _guard.invokeMethod('disable');
      } catch (_) {}
    }
    if (Platform.isWindows) {
      windowManager.removeListener(this);
      await windowManager.setAlwaysOnTop(false);
      await windowManager.setFullScreen(false);
      await windowManager.setPreventClose(false);
    }
  }

  void _violation(String reason) {
    if (!_armed || _locked || !mounted) return;
    setState(() {
      _violations++;
      if (_violations >= ExamConfig.maxViolations) _locked = true;
    });
    _toast('Pelanggaran: $reason ($_violations/${ExamConfig.maxViolations})');
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  // Android: deteksi keluar dari aplikasi
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!Platform.isAndroid) return;
    if (state == AppLifecycleState.paused) _wasPaused = true;
    if (state == AppLifecycleState.resumed && _wasPaused) {
      _wasPaused = false;
      _violation('keluar dari aplikasi');
    }
  }

  // Windows: deteksi pindah jendela & tombol close
  @override
  void onWindowBlur() => _violation('pindah jendela');

  @override
  void onWindowClose() {
    if (mounted) _requestExit();
  }

  // ---------- WebView ----------
  void _initAndroid() {
    final c = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onNavigationRequest: (req) {
          if (!req.isMainFrame || isAllowedUrl(req.url)) {
            return NavigationDecision.navigate;
          }
          _toast('Situs diblokir: ${Uri.tryParse(req.url)?.host ?? ''}');
          return NavigationDecision.prevent;
        },
        onPageFinished: (_) => _android?.runJavaScript(_protectJs),
      ))
      ..loadRequest(Uri.parse(widget.url));
    _android = c;
  }

  Future<void> _initWindows() async {
    await _winCtrl.initialize();
    await _winCtrl
        .setPopupWindowPolicy(win.WebviewPopupWindowPolicy.sameWindow);
    await _winCtrl.addScriptToExecuteOnDocumentCreated(_protectJs);
    _winCtrl.url.listen((u) {
      if (!isAllowedUrl(u)) {
        _toast('Situs diblokir');
        _winCtrl.loadUrl(widget.url);
      }
    });
    await _winCtrl.loadUrl(widget.url);
    if (mounted) setState(() => _winReady = true);
  }

  // ---------- PIN ----------
  Future<bool> _askPin(String title) async {
    final c = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: c,
          obscureText: true,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(hintText: 'PIN pengawas'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, c.text == ExamConfig.exitPin),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  Future<void> _requestExit() async {
    if (!await _askPin('Keluar dari mode ujian')) return;
    await _disableGuard();
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _unlock() async {
    if (await _askPin('Buka kunci (pengawas)')) {
      setState(() {
        _locked = false;
        _violations = 0;
      });
    }
  }

  // ---------- UI ----------
  Widget _topBar() {
    return Container(
      height: 40,
      color: const Color(0xFF1B1F3B),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          const Icon(Icons.shield, color: Colors.greenAccent, size: 18),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'MODE UJIAN AKTIF',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600),
            ),
          ),
          Text(
            'Pelanggaran $_violations/${ExamConfig.maxViolations}',
            style: TextStyle(
              color: _violations == 0 ? Colors.white60 : Colors.orangeAccent,
              fontSize: 12,
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: _requestExit,
            icon: const Icon(Icons.lock_open, color: Colors.white70, size: 18),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  Widget _webView() {
    if (Platform.isWindows) {
      if (!_winReady) {
        return const Center(child: CircularProgressIndicator());
      }
      return win.Webview(_winCtrl);
    }
    return WebViewWidget(controller: _android!);
  }

  Widget _lockOverlay() {
    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.96),
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.lock, color: Colors.redAccent, size: 72),
            const SizedBox(height: 16),
            const Text(
              'UJIAN TERKUNCI',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Terlalu banyak pelanggaran.\nHubungi pengawas untuk membuka kunci.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 24),
            FilledButton(onPressed: _unlock, child: const Text('Buka kunci')),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Stack(
            children: [
              Column(
                children: [
                  _topBar(),
                  Expanded(child: _webView()),
                ],
              ),
              if (_locked) _lockOverlay(),
            ],
          ),
        ),
      ),
    );
  }
}
