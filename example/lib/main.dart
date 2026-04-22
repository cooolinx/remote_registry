import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:remote_registry/remote_registry.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final registry = RemoteRegistry(
    baseUrl: 'https://tavoai.dev/registry',
    bundledAssetPath: 'assets/registry/',
  );
  // Keep init forgiving for the demo: fall back to bundle if network down.
  dynamic models;
  String status;
  try {
    await registry.init();
    models = await registry.getJson('models.json');
    status = 'version: ${registry.currentVersion}';
  } catch (e) {
    models = null;
    status = 'error: $e';
  }
  runApp(_App(status: status, models: models));
}

class _App extends StatelessWidget {
  const _App({required this.status, required this.models});
  final String status;
  final dynamic models;
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'remote_registry example',
        home: Scaffold(
          appBar: AppBar(title: const Text('remote_registry example')),
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(status, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 16),
                Expanded(
                  child: SingleChildScrollView(
                    child: Text(
                      models == null
                          ? '(no models loaded)'
                          : const JsonEncoder.withIndent('  ').convert(models),
                      style: const TextStyle(fontFamily: 'monospace'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}
