import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ffi/ffi.dart';

// ============================================================
// НАТИВНАЯ БИБЛИОТЕКА ДЛЯ РАБОТЫ С ПАМЯТЬЮ
// ============================================================

final DynamicLibrary nativeLib = Platform.isIOS
    ? DynamicLibrary.process()
    : DynamicLibrary.open('libinjector.so');

typedef FindPatternFunc = Int32 Function(
    Int32 processID,
    Pointer<Int8> pattern,
    Int32 patternLength,
    Pointer<Pointer<Uint64>> results,
    Pointer<Int32> resultsCount
);

typedef FindPatternNative = int Function(
    int processID,
    Pointer<Int8> pattern,
    int patternLength,
    Pointer<Pointer<Uint64>> results,
    Pointer<Int32> resultsCount
);

typedef WriteMemoryFunc = Int32 Function(
    Int32 processID,
    Uint64 address,
    Pointer<Int8> data,
    Int32 dataLength
);

typedef WriteMemoryNative = int Function(
    int processID,
    int address,
    Pointer<Int8> data,
    int dataLength
);

final findPatternFunc = nativeLib
    .lookup<NativeFunction<FindPatternFunc>>('find_pattern_in_memory')
    .asFunction<FindPatternNative>();

final writeMemoryFunc = nativeLib
    .lookup<NativeFunction<WriteMemoryFunc>>('write_memory')
    .asFunction<WriteMemoryNative>();

// ============================================================
// ПРИЛОЖЕНИЕ
// ============================================================

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Standoff2 ID Changer',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0A0A0A),
        colorScheme: const ColorScheme.dark().copyWith(
          primary: Color(0xFF00FF88),
          secondary: Color(0xFF00FF88),
        ),
      ),
      home: const MainScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

// ============================================================
// ГЛАВНЫЙ ЭКРАН
// ============================================================

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  final TextEditingController _currentIDController = TextEditingController();
  final TextEditingController _newIDController = TextEditingController();

  bool _isInjecting = false;
  String _status = 'Ready';
  int _foundCount = 0;
  int _changedCount = 0;
  int _pid = -1;
  String _logOutput = '';

  // ============================================================
  // ПОИСК ПРОЦЕССА
  // ============================================================

  Future<int> _findProcess() async {
    try {
      final result = await Process.run('pgrep', ['-x', 'Standoff2']);
      String output = result.stdout.toString().trim();
      if (output.isNotEmpty) {
        return int.parse(output.split('\n')[0]);
      }
      return -1;
    } catch (e) {
      return -1;
    }
  }

  // ============================================================
  // ОСНОВНАЯ ФУНКЦИЯ ИНЪЕКЦИИ
  // ============================================================

  Future<void> _inject() async {
    final currentID = int.tryParse(_currentIDController.text);
    final newID = int.tryParse(_newIDController.text);

    if (currentID == null || newID == null) {
      setState(() {
        _status = '❌ Please enter valid numbers';
      });
      return;
    }

    setState(() {
      _isInjecting = true;
      _status = '🔍 Searching for Standoff2...';
      _foundCount = 0;
      _changedCount = 0;
      _logOutput = '';
    });

    _pid = await _findProcess();
    if (_pid <= 0) {
      setState(() {
        _isInjecting = false;
        _status = '❌ Standoff2 is not running!';
        _logOutput = 'Process not found. Please launch Standoff2 first.';
      });
      return;
    }

    setState(() {
      _status = '✅ Found PID: $_pid\n🔍 Scanning memory...';
    });

    // Паттерн: [ID] + 01 00 00 00
    final pattern = ByteData(8)
      ..setInt32(0, currentID, Endian.little)
      ..setInt32(4, 1, Endian.little);

    final patternBytes = pattern.buffer.asUint8List();
    final patternPtr = malloc<Int8>(patternBytes.length);
    for (int i = 0; i < patternBytes.length; i++) {
      patternPtr[i] = patternBytes[i];
    }

    Pointer<Pointer<Uint64>> resultsPtr = malloc<Pointer<Uint64>>();
    Pointer<Int32> countPtr = malloc<Int32>();

    try {
      final result = findPatternFunc(
        _pid,
        patternPtr.cast<Int8>(),
        patternBytes.length,
        resultsPtr,
        countPtr,
      );

      final count = countPtr.value;
      _foundCount = count;

      if (result == 0 && count > 0) {
        setState(() {
          _status = '✅ Found $_foundCount addresses\n✏️ Changing to $newID...';
        });

        int changed = 0;
        final addresses = resultsPtr.value;

        final newValueBytes = ByteData(4)
          ..setInt32(0, newID, Endian.little);

        for (int i = 0; i < count && i < 50; i++) {
          final address = addresses[i];
          _logOutput += '0x${address.toRadixString(16).padLeft(16, '0')}\n';

          final writeResult = writeMemoryFunc(
            _pid,
            address,
            newValueBytes.buffer.asUint8List().cast<Int8>().pointer,
            4,
          );

          if (writeResult == 0) {
            changed++;
          }
        }

        _changedCount = changed;

        setState(() {
          _status = '✅ Done!\nFound: $_foundCount, Changed: $_changedCount';
          _isInjecting = false;
        });
      } else {
        setState(() {
          _status = '❌ Nothing found! Try different ID.';
          _isInjecting = false;
        });
      }
    } catch (e) {
      setState(() {
        _status = '❌ Error: $e';
        _isInjecting = false;
      });
    } finally {
      malloc.free(patternPtr);
    }
  }

  // ============================================================
  // ИНТЕРФЕЙС
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [const Color(0xFF0A0A0A), const Color(0xFF1A1A1A)],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: ListView(
              children: [
                const Text(
                  'Standoff2 ID Changer',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF00FF88),
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'v1.0 — iOS Standoff2 Item ID Changer',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 30),

                _buildTextField(
                  controller: _currentIDController,
                  label: 'CURRENT ITEM ID',
                  hint: 'Enter current skin ID',
                  icon: Icons.numbers,
                ),
                const SizedBox(height: 16),

                _buildTextField(
                  controller: _newIDController,
                  label: 'NEW ITEM ID',
                  hint: 'Enter desired skin ID',
                  icon: Icons.star,
                ),
                const SizedBox(height: 20),

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isInjecting ? null : _inject,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00FF88),
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _isInjecting
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.black),
                            ),
                          )
                        : const Text(
                            'INJECT',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 2,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 20),

                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey[800]!),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'STATUS',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _status,
                        style: TextStyle(
                          fontSize: 14,
                          color: _status.contains('✅')
                              ? const Color(0xFF00FF88)
                              : _status.contains('❌')
                                  ? Colors.redAccent
                                  : Colors.white,
                        ),
                      ),
                      if (_foundCount > 0) ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Text(
                              'Found: $_foundCount',
                              style: const TextStyle(color: Colors.grey, fontSize: 13),
                            ),
                            const SizedBox(width: 20),
                            Text(
                              'Changed: $_changedCount',
                              style: const TextStyle(color: Colors.grey, fontSize: 13),
                            ),
                          ],
                        ),
                      ],
                      if (_logOutput.isNotEmpty) ...[
                        const Divider(color: Colors.grey),
                        const Text(
                          'ADDRESSES:',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Text(
                            _logOutput,
                            style: const TextStyle(
                              color: Colors.grey,
                              fontSize: 11,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 30),

                const Center(
                  child: Column(
                    children: [
                      Text(
                        '⚠️ Requires TrollStore',
                        style: TextStyle(
                          color: Colors.orange,
                          fontSize: 12,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Standoff2 must be running before injection',
                        style: TextStyle(
                          color: Colors.grey,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: Colors.grey,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: Colors.grey[600]),
            filled: true,
            fillColor: Colors.white.withOpacity(0.05),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: Colors.grey[800]!),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: Colors.grey[800]!),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFF00FF88)),
            ),
            prefixIcon: Icon(icon, color: Colors.grey),
          ),
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        ),
      ],
    );
  }
}
