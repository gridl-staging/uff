import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:go_router/go_router.dart';

/// Renders a legal markdown document from a bundled asset path.
class LegalDocumentScreen extends StatefulWidget {
  const LegalDocumentScreen({
    required this.title,
    required this.assetPath,
    this.assetBundle,
    super.key,
  });

  static const loadingIndicatorKey = Key('legal_document_loading_indicator');
  static const markdownViewKey = Key('legal_document_markdown_view');
  static const errorMessageKey = Key('legal_document_error_message');
  static const retryButtonKey = Key('legal_document_retry_button');
  static const backButtonKey = Key('legal_document_back_button');

  final String title;
  final String assetPath;
  final AssetBundle? assetBundle;

  @override
  State<LegalDocumentScreen> createState() => _LegalDocumentScreenState();
}

/// Loads and renders the requested legal markdown asset.
class _LegalDocumentScreenState extends State<LegalDocumentScreen> {
  late Future<String> _markdownFuture;

  @override
  void initState() {
    super.initState();
    _markdownFuture = _loadMarkdown();
  }

  @override
  void didUpdateWidget(covariant LegalDocumentScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.assetPath != widget.assetPath ||
        oldWidget.assetBundle != widget.assetBundle) {
      _markdownFuture = _loadMarkdown();
    }
  }

  Future<String> _loadMarkdown() {
    return (widget.assetBundle ?? rootBundle).loadString(widget.assetPath);
  }

  void _retryLoad() {
    setState(() {
      _markdownFuture = _loadMarkdown();
    });
  }

  void _goBack() {
    final router = GoRouter.maybeOf(context);
    if (router?.canPop() ?? false) {
      router!.pop();
      return;
    }

    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
      return;
    }

    // Route back through the app entrypoint so auth redirects choose the
    // correct signed-in or signed-out destination when legal docs are entered
    // directly and the document fails to load.
    if (router != null) {
      router.go('/');
      return;
    }

    navigator.maybePop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: FutureBuilder<String>(
        future: _markdownFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(
              child: CircularProgressIndicator(
                key: LegalDocumentScreen.loadingIndicatorKey,
              ),
            );
          }

          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Unable to load this document right now.',
                      key: LegalDocumentScreen.errorMessageKey,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      key: LegalDocumentScreen.retryButtonKey,
                      onPressed: _retryLoad,
                      child: const Text('Try again'),
                    ),
                    TextButton(
                      key: LegalDocumentScreen.backButtonKey,
                      onPressed: _goBack,
                      child: const Text('Back'),
                    ),
                  ],
                ),
              ),
            );
          }

          return Markdown(
            key: LegalDocumentScreen.markdownViewKey,
            data: snapshot.data ?? '',
          );
        },
      ),
    );
  }
}
