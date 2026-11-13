import 'dart:async';
import 'package:flutter/material.dart';
import 'license_service.dart';
import 'license_state.dart';

class LicenseScope extends InheritedNotifier<LicenseService> {
  const LicenseScope({
    super.key,
    required LicenseService service,
    required super.child,
  }) : super(notifier: service);
  static LicenseService? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<LicenseScope>()?.notifier;
}

/// Mounted ABOVE the complete Navigator, including dialogs and future routes.
class LicenseGate extends StatefulWidget {
  final LicenseService service;
  final Widget child;
  const LicenseGate({super.key, required this.service, required this.child});
  @override
  State<LicenseGate> createState() => _LicenseGateState();
}

class _LicenseGateState extends State<LicenseGate> with WidgetsBindingObserver {
  Timer? _timer;
  bool _checking = true;
  bool _busy = false;
  bool _foreground = true;
  final _code = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.service.addListener(_changed);
    _refresh();
  }

  @override
  void didUpdateWidget(LicenseGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.service != widget.service) {
      oldWidget.service.removeListener(_changed);
      widget.service.addListener(_changed);
      _refresh();
    }
  }

  void _changed() {
    if (!mounted) return;
    setState(() {});
    _schedule();
  }

  void _schedule() {
    _timer?.cancel();
    if (!_foreground) return;
    final state = widget.service.state;
    if (!state.isActive) return;
    final untilExpiry = state.expiresAt!.difference(state.observedAt!);
    final delay = untilExpiry < const Duration(days: 1)
        ? untilExpiry
        : const Duration(days: 1);
    _timer = Timer(delay.isNegative ? Duration.zero : delay, _refresh);
  }

  Future<void> _refresh() async {
    if (mounted) setState(() => _checking = true);
    await widget.service.refresh();
    if (mounted) {
      setState(() => _checking = !_foreground);
      _schedule();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _foreground = true;
      _refresh();
    }
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _foreground = false;
      _timer?.cancel();
      setState(() => _checking = true);
    }
  }

  Future<void> _activate() async {
    setState(() => _busy = true);
    final code = _code.text;
    _code.clear();
    await widget.service.activate(code);
    if (mounted) setState(() => _busy = false);
  }

  @override
  void dispose() {
    _timer?.cancel();
    widget.service.removeListener(_changed);
    WidgetsBinding.instance.removeObserver(this);
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.service.state;
    // Keep valid navigation mounted while checking a resume. An invalid license
    // removes the complete Navigator; an offstage child cannot receive input.
    final expired = state.status == LicenseStatus.expired;
    final activation = state.status == LicenseStatus.activationRequired;
    final locked = PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(Icons.lock_outline, size: 56),
                    const SizedBox(height: 20),
                    Text(
                      expired ? 'انتهت الفترة التجريبية' : 'تفعيل دفتر الحساب',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 16),
                    if (_checking)
                      const Center(child: CircularProgressIndicator())
                    else ...[
                      Text(
                        expired
                            ? 'انتهت مدة استخدام النسخة التجريبية من دفتر الحساب. يرجى التواصل مع مالك التطبيق لتجديد الترخيص.'
                            : 'هذه نسخة تجريبية لمدة ثلاثة أشهر',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 20),
                      if (activation) ...[
                        TextField(
                          key: const Key('license_code'),
                          controller: _code,
                          obscureText: true,
                          enableSuggestions: false,
                          autocorrect: false,
                          enableIMEPersonalizedLearning: false,
                          autofillHints: const [],
                          maxLength: 256,
                          onSubmitted: (_) {
                            if (!_busy) _activate();
                          },
                          decoration: const InputDecoration(
                            labelText: 'رمز التفعيل',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        FilledButton(
                          onPressed: _busy ? null : _activate,
                          child: Text(_busy ? 'جارٍ التحقق…' : 'تفعيل التطبيق'),
                        ),
                      ],
                      if (state.message != null)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Text(
                            state.message!,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                      if (!activation && !expired)
                        OutlinedButton(
                          onPressed: _refresh,
                          child: const Text('إعادة التحقق'),
                        ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    return Stack(
      fit: StackFit.expand,
      children: [
        if (state.isActive)
          Offstage(
            key: const ValueKey('licensed_navigation'),
            offstage: _checking,
            child: IgnorePointer(
              ignoring: _checking,
              child: LicenseScope(service: widget.service, child: widget.child),
            ),
          ),
        if (_checking || !state.isActive) Overlay.wrap(child: locked),
      ],
    );
  }
}

class TrialLicenseInfo extends StatelessWidget {
  const TrialLicenseInfo({super.key});
  @override
  Widget build(BuildContext context) {
    final service = LicenseScope.maybeOf(context);
    if (service == null || !service.state.isActive) {
      return const SizedBox.shrink();
    }
    final state = service.state;
    final expiry = state.expiresAt!.toLocal();
    return Card(
      child: ListTile(
        leading: const Icon(Icons.verified_user_outlined),
        title: const Text('النسخة التجريبية'),
        subtitle: Text(
          'ينتهي التفعيل: ${expiry.year}/${expiry.month}/${expiry.day}\nالأيام المتبقية: ${state.remainingDays}',
        ),
      ),
    );
  }
}
