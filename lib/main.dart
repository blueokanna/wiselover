import 'dart:io';
import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:wiselover/src/audio/sherpa_model_manager.dart';
import 'package:wiselover/src/live2d/live2d_model_manager.dart';
import 'package:wiselover/src/live2d/live2d_viewer.dart';
import 'package:wiselover/src/rust/api/live2d_core.dart';
import 'package:wiselover/src/rust/frb_generated.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RustLib.init();

  // 初始化 Sherpa 语音模型
  try {
    await SherpaModelManager.instance.init();
  } catch (e) {
    debugPrint('⚠ Sherpa 语音模型初始化失败: $e');
  }

  await wiseLoverBootInitApp();

  // 加载保存的模型或默认模型
  try {
    await Live2DModelManager.instance.loadSavedModel();
  } catch (e) {
    debugPrint('⚠ 模型加载失败: $e');
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Wiselover',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.system,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6750A4),
          brightness: Brightness.light,
        ),
        typography: Typography.material2021(),
        appBarTheme: const AppBarTheme(
          centerTitle: true,
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFD0BCFF),
          brightness: Brightness.dark,
        ),
        typography: Typography.material2021(),
        appBarTheme: const AppBarTheme(
          centerTitle: true,
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool _isLoading = false;
  Live2DEmotion _currentEmotion = Live2DEmotion.neutral;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  // 显示模型选择对话框
  Future<void> _showModelSelectionDialog() async {
    try {
      setState(() => _isLoading = true);
      final models = await Live2DModelManager.instance.getAvailableModels();
      if (!mounted) return;

      showModalBottomSheet(
        context: context,
        useSafeArea: true,
        isScrollControlled: true,
        showDragHandle: true, // MD3 Drag Handle
        builder: (context) {
          return DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.5,
            minChildSize: 0.3,
            maxChildSize: 0.9,
            builder: (context, scrollController) {
              return ListView.builder(
                controller: scrollController,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: models.length + 1, // +1 for header
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Text(
                        '选择模型',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                    );
                  }

                  final model = models[index - 1];
                  final name = model['name'] ?? 'Unknown';
                  final path = model['path'] ?? '';
                  final type = model['type'] ?? 'json';
                  final isCurrent =
                      Live2DModelManager.instance.currentModelPath == path ||
                      (Live2DModelManager.instance.currentModelPath == null &&
                          path.contains('mao_pro')); // Rough check

                  return Card(
                    elevation: 0,
                    color: isCurrent
                        ? Theme.of(context).colorScheme.secondaryContainer
                        : Theme.of(context).colorScheme.surfaceContainerLow,
                    margin: const EdgeInsets.only(bottom: 8),
                    clipBehavior: Clip.antiAlias,
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      leading: CircleAvatar(
                        backgroundColor: isCurrent
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.primaryContainer,
                        foregroundColor: isCurrent
                            ? Theme.of(context).colorScheme.onPrimary
                            : Theme.of(context).colorScheme.onPrimaryContainer,
                        child: Text(
                          name.isNotEmpty ? name[0].toUpperCase() : '?',
                        ),
                      ),
                      title: Text(
                        name,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(
                        type == 'json' ? 'Configuration File' : 'Raw Moc3 File',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      trailing: isCurrent
                          ? const Icon(Icons.check_circle)
                          : null,
                      onTap: () async {
                        Navigator.pop(context);
                        _loadModel(path, type == 'json', name);
                      },
                    ),
                  );
                },
              );
            },
          );
        },
      );
    } catch (e) {
      _showError('获取模型列表失败: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadModel(String path, bool isJson, String name) async {
    setState(() => _isLoading = true);
    try {
      if (isJson) {
        await Live2DModelManager.instance.loadModelFromAssetJson(path);
      } else {
        await Live2DModelManager.instance.loadModelByPath(path, false);
      }
      _showSnackBar('已切换模型: $name');
    } catch (e) {
      _showError('切换失败: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // 选择 .moc3 文件
  Future<void> _pickMocFile() async {
    try {
      setState(() => _isLoading = true);
      _scaffoldKey.currentState?.closeDrawer();

      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['moc3'],
      );

      if (result == null || result.files.single.path == null) {
        return;
      }

      final mocPath = result.files.single.path!;
      await Live2DModelManager.instance.loadModelFromMocFile(mocPath);
      _showSnackBar('模型加载成功！');
    } catch (e) {
      _showError('加载失败: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // 选择文件夹
  Future<void> _pickFolder() async {
    try {
      setState(() => _isLoading = true);
      _scaffoldKey.currentState?.closeDrawer();

      String? selectedDirectory = await FilePicker.platform.getDirectoryPath();

      if (selectedDirectory == null) {
        return;
      }

      await Live2DModelManager.instance.loadModelFromDir(selectedDirectory);
      _showSnackBar('模型加载成功！');
    } catch (e) {
      _showError('加载失败: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _pickAndLoadZip() async {
    try {
      setState(() => _isLoading = true);
      _scaffoldKey.currentState?.closeDrawer();

      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['zip'],
      );

      if (result == null || result.files.single.path == null) {
        return;
      }

      final zipPath = result.files.single.path!;
      final appDir = await getApplicationSupportDirectory();
      final modelsDir = Directory(path.join(appDir.path, 'live2d_models'));
      await modelsDir.create(recursive: true);

      final zipFileName = path.basenameWithoutExtension(zipPath);
      final extractDir = Directory(path.join(modelsDir.path, zipFileName));

      if (await extractDir.exists()) {
        await extractDir.delete(recursive: true);
      }
      await extractDir.create(recursive: true);

      final zipBytes = await File(zipPath).readAsBytes();
      final archive = ZipDecoder().decodeBytes(zipBytes);

      for (var file in archive.files) {
        if (file.isFile) {
          final outputPath = path.join(extractDir.path, file.name);
          final outputFile = File(outputPath);
          await outputFile.create(recursive: true);
          await outputFile.writeAsBytes(file.content);
        }
      }

      String modelDir = extractDir.path;
      await Live2DModelManager.instance.loadModelFromDir(modelDir);
      _showSnackBar('模型加载成功！');
    } catch (e) {
      _showError('加载失败: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  void _showError(String message) {
    if (!mounted) return;
    debugPrint(message);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Theme.of(context).colorScheme.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      key: _scaffoldKey,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: Padding(
          padding: const EdgeInsets.all(8.0),
          child: IconButton.filledTonal(
            icon: const Icon(Icons.menu),
            onPressed: () => _scaffoldKey.currentState?.openDrawer(),
          ),
        ),
        actions: [
          if (_isLoading)
            Container(
              margin: const EdgeInsets.only(right: 16),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withOpacity(0.9),
                shape: BoxShape.circle,
              ),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    colorScheme.primary,
                  ),
                ),
              ),
            ),
        ],
      ),
      drawer: NavigationDrawer(
        onDestinationSelected: (index) {
          // NavigationDrawerDestination indices
          switch (index) {
            case 0:
              _pickMocFile();
              break;
            case 1:
              _pickFolder();
              break;
            case 2:
              _pickAndLoadZip();
              break;
            case 3:
              _showModelSelectionDialog();
              break;
          }
        },
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 16, 16, 10),
            child: Text(
              'Wiselover',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          const NavigationDrawerDestination(
            icon: Icon(Icons.file_open_outlined),
            selectedIcon: Icon(Icons.file_open),
            label: Text('选择 .moc3 文件'),
          ),
          const NavigationDrawerDestination(
            icon: Icon(Icons.folder_open_outlined),
            selectedIcon: Icon(Icons.folder_open),
            label: Text('选择模型文件夹'),
          ),
          const NavigationDrawerDestination(
            icon: Icon(Icons.folder_zip_outlined),
            selectedIcon: Icon(Icons.folder_zip),
            label: Text('导入模型包 (ZIP)'),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(28, 16, 28, 10),
            child: Divider(),
          ),
          const NavigationDrawerDestination(
            icon: Icon(Icons.switch_account_outlined),
            selectedIcon: Icon(Icons.switch_account),
            label: Text('切换内置模型'),
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Live2D Viewer
          Container(
            color: colorScheme.surface,
            child: Live2DViewer(emotion: _currentEmotion),
          ),

          // Bottom Controls
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainer,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(28),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 10,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Voice Button (Floating above or integrated)
                    // Let's integrate it nicely
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Emotion',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(color: colorScheme.onSurfaceVariant),
                        ),
                        FloatingActionButton.small(
                          onPressed: () {
                            // Voice action
                          },
                          elevation: 2,
                          backgroundColor: colorScheme.primary,
                          foregroundColor: colorScheme.onPrimary,
                          child: const Icon(Icons.mic),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // Emotion Chips
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: Live2DEmotion.values.map((e) {
                          final isSelected = _currentEmotion == e;
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text(_getEmotionLabel(e)),
                              selected: isSelected,
                              onSelected: (selected) {
                                if (selected) {
                                  setState(() => _currentEmotion = e);
                                }
                              },
                              showCheckmark: false,
                              avatar: isSelected
                                  ? const Icon(Icons.check, size: 18)
                                  : null,
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _getEmotionLabel(Live2DEmotion e) {
    switch (e) {
      case Live2DEmotion.neutral:
        return '平常';
      case Live2DEmotion.happy:
        return '开心';
      case Live2DEmotion.angry:
        return '生气';
      case Live2DEmotion.sad:
        return '悲伤';
      case Live2DEmotion.surprised:
        return '惊讶';
      case Live2DEmotion.shy:
        return '害羞';
    }
  }
}
