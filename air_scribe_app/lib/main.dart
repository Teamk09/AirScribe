import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:web_socket_channel/io.dart';
import 'ip_input_page.dart';

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
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple, brightness: Brightness.dark),
        brightness: Brightness.dark,
      ),
      themeMode: ThemeMode.system,
      home: const IpInputPage(),
    );
  }
}

class SensorPage extends StatefulWidget {
  final String serverIp;

  const SensorPage({required this.serverIp, super.key});

  @override
  State<SensorPage> createState() => _SensorPageState();
}

class _SensorPageState extends State<SensorPage> {
  IOWebSocketChannel? _channel;
  StreamSubscription? _gyroscopeSubscription;
  StreamSubscription? _userAccelerometerSubscription;
  String _status = 'Connecting...';
  GyroscopeEvent? _gyroscopeEvent;
  UserAccelerometerEvent? _userAccelerometerEvent; 
  late String _serverUrl;

  final Duration _samplingPeriod = Duration(milliseconds: 50);

  @override
  void initState() {
    super.initState();
    _serverUrl = 'ws://${widget.serverIp}:8080';
    _connectWebSocket();
    _startSensorListeners();
  }

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

  void _startSensorListeners() {
    _gyroscopeSubscription = gyroscopeEventStream(samplingPeriod: _samplingPeriod).listen(
      (GyroscopeEvent event) {
        setState(() {
          _gyroscopeEvent = event;
        });
        _sendSensorData(); 
      },
      onError: (error) {
        print('Gyroscope error: $error');
        setState(() { _status = 'Gyroscope Error: $error'; });
      },
      cancelOnError: true,
    );
    print('Gyroscope listener started with samplingPeriod: $_samplingPeriod.');

    _userAccelerometerSubscription = userAccelerometerEventStream(samplingPeriod: _samplingPeriod).listen(
      (UserAccelerometerEvent event) {
        setState(() {
          _userAccelerometerEvent = event;
        });
        _sendSensorData(); 
      },
      onError: (error) {
        print('User Accelerometer error: $error');
        setState(() { _status = 'Accelerometer Error: $error'; });
      },
      cancelOnError: true,
    );
    print('User Accelerometer listener started with samplingPeriod: $_samplingPeriod.');
  }

  void _sendSensorData() {
    if (_channel != null && _channel?.closeCode == null && _gyroscopeEvent != null && _userAccelerometerEvent != null) {
      final data = {
        'gyro': {
          'x': _gyroscopeEvent!.x,
          'y': _gyroscopeEvent!.y,
          'z': _gyroscopeEvent!.z,
        },
        'accel': {
          'x': _userAccelerometerEvent!.x,
          'y': _userAccelerometerEvent!.y,
          'z': _userAccelerometerEvent!.z,
        },
      };
      _channel?.sink.add(jsonEncode(data));
    }
  }


  @override
  void dispose() {
    _gyroscopeSubscription?.cancel();
    _userAccelerometerSubscription?.cancel(); 
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
          padding: const EdgeInsets.all(16.0),
          child: Card(
            elevation: 4.0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
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
                  const SizedBox(height: 16),
                  Divider(height: 1, color: theme.dividerColor.withOpacity(0.5)),
                  const SizedBox(height: 16),

                  Text('Gyroscope', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  if (_gyroscopeEvent != null)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _buildSensorAxis('X', _gyroscopeEvent!.x, theme),
                        _buildSensorAxis('Y', _gyroscopeEvent!.y, theme),
                        _buildSensorAxis('Z', _gyroscopeEvent!.z, theme),
                      ],
                    )
                  else
                    _buildWaitingIndicator(theme),

                  const SizedBox(height: 16),

                  Text('User Accelerometer', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  if (_userAccelerometerEvent != null)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _buildSensorAxis('X', _userAccelerometerEvent!.x, theme),
                        _buildSensorAxis('Y', _userAccelerometerEvent!.y, theme),
                        _buildSensorAxis('Z', _userAccelerometerEvent!.z, theme),
                      ],
                    )
                  else
                    _buildWaitingIndicator(theme),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSensorAxis(String axis, double value, ThemeData theme) {
    return Column(
      children: [
        Text(axis, style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.primary)),
        const SizedBox(height: 2),
        Text(value.toStringAsFixed(2), style: theme.textTheme.bodyMedium),
      ],
    );
  }

  Widget _buildWaitingIndicator(ThemeData theme) {
     return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
          const SizedBox(width: 8),
          Text('Waiting...', style: theme.textTheme.bodySmall),
        ],
      );
  }
}
