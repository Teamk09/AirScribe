import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:web_socket_channel/io.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AirScribe Sensor App',
      theme: ThemeData(
        // Explicitly use Material 3 and define a color scheme
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple, brightness: Brightness.dark),
        brightness: Brightness.dark,
      ),
      themeMode: ThemeMode.system, // Respect system theme
      home: const SensorPage(),
    );
  }
}

class SensorPage extends StatefulWidget {
  const SensorPage({super.key});

  @override
  State<SensorPage> createState() => _SensorPageState();
}

class _SensorPageState extends State<SensorPage> {
  // Restore WebSocket and status variables if they were missing
  final String _serverUrl = 'ws://192.168.0.193:8080';
  IOWebSocketChannel? _channel;
  StreamSubscription? _gyroscopeSubscription;
  String _status = 'Connecting...';
  GyroscopeEvent? _gyroscopeEvent;

  @override
  void initState() {
    super.initState();
    _connectWebSocket();
    _startGyroscopeListener();
  }

  // Restore WebSocket connection logic if it was missing
  void _connectWebSocket() {
    try {
      _channel = IOWebSocketChannel.connect(Uri.parse(_serverUrl));
      setState(() {
        _status = 'Connected to $_serverUrl';
      });
      _channel?.stream.listen(
        (message) { print('Received: $message'); },
        onDone: () {
          setState(() { _status = 'Disconnected'; });
          print('WebSocket disconnected');
          _reconnectWebSocket();
        },
        onError: (error) {
          setState(() { _status = 'Connection Error: $error'; });
          print('WebSocket error: $error');
          _reconnectWebSocket();
        },
      );
    } catch (e) {
      setState(() { _status = 'Connection Failed: $e'; });
      print('Failed to connect: $e');
      _reconnectWebSocket();
    }
  }

  void _reconnectWebSocket() {
    print('Attempting to reconnect in 5 seconds...');
    Future.delayed(const Duration(seconds: 5), () {
       if (mounted) _connectWebSocket();
    });
  }

  void _startGyroscopeListener() {
    // Always send data when connected
    _gyroscopeSubscription = gyroscopeEventStream().listen(
      (GyroscopeEvent event) {
        setState(() {
          _gyroscopeEvent = event; // Update UI display
        });
        // Always send data if connected
        if (_channel != null && _channel?.closeCode == null) {
          final data = {'x': event.x, 'y': event.y, 'z': event.z};
          _channel?.sink.add(jsonEncode(data));
        }
      },
      onError: (error) {
        print('Gyroscope error: $error');
        setState(() {
          _status = 'Gyroscope Error: $error';
        });
      },
      cancelOnError: true,
    );
     print('Gyroscope listener started using gyroscopeEventStream().');
  }

  @override
  void dispose() {
    _gyroscopeSubscription?.cancel();
    _channel?.sink.close();
    print('Listeners stopped and WebSocket closed.');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    bool isConnected = _channel != null && _channel?.closeCode == null && _status.startsWith('Connected');

    return Scaffold(
      appBar: AppBar(
        title: const Text('AirScribe Sensor'),
        // Add a connection status icon to the AppBar
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: Icon(
              isConnected ? Icons.wifi_rounded : Icons.wifi_off_rounded,
              color: isConnected ? Colors.green : theme.colorScheme.error,
            ),
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Card(
            elevation: 4.0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                mainAxisSize: MainAxisSize.min, // Card size wraps content
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  // Improved Status Display
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        isConnected ? Icons.check_circle_outline_rounded : Icons.error_outline_rounded,
                        color: isConnected ? Colors.green : theme.colorScheme.error,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _status,
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: isConnected ? Colors.green : theme.colorScheme.error,
                          ),
                          textAlign: TextAlign.center,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Divider(height: 1, color: theme.dividerColor.withOpacity(0.5)),
                  const SizedBox(height: 24),
                  // Gyroscope Data Display
                  Text(
                    'Gyroscope Data',
                    style: theme.textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 16),
                  if (_gyroscopeEvent != null)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _buildGyroAxis('X', _gyroscopeEvent!.x, theme),
                        _buildGyroAxis('Y', _gyroscopeEvent!.y, theme),
                        _buildGyroAxis('Z', _gyroscopeEvent!.z, theme),
                      ],
                    )
                  else
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                        const SizedBox(width: 12),
                        Text('Waiting for data...', style: theme.textTheme.bodyMedium),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // Helper widget to display each gyroscope axis
  Widget _buildGyroAxis(String axis, double value, ThemeData theme) {
    return Column(
      children: [
        Text(axis, style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.primary)),
        const SizedBox(height: 4),
        Text(value.toStringAsFixed(2), style: theme.textTheme.bodyLarge),
      ],
    );
  }
}
