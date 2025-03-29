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
        primarySwatch: Colors.blue,
      ),
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

  void _connectWebSocket() {
    try {
      _channel = IOWebSocketChannel.connect(Uri.parse(_serverUrl));
      setState(() {
        _status = 'Connected to $_serverUrl';
      });
      // Listen for messages from the server
      _channel?.stream.listen(
        (message) {
          print('Received: $message');
          // Handle incoming messages
        },
        onDone: () {
          setState(() {
            _status = 'Disconnected';
          });
          print('WebSocket disconnected');
          // Attempt to reconnect or handle disconnection
          _reconnectWebSocket();
        },
        onError: (error) {
          setState(() {
            _status = 'Connection Error: $error';
          });
          print('WebSocket error: $error');
          // Attempt to reconnect or handle error
           _reconnectWebSocket();
        },
      );
    } catch (e) {
      setState(() {
        _status = 'Connection Failed: $e';
      });
      print('Failed to connect: $e');
       _reconnectWebSocket(); // Attempt to reconnect on initial failure
    }
  }

  void _reconnectWebSocket() {
    // Simple reconnect logic with a delay
    print('Attempting to reconnect in 5 seconds...');
    Future.delayed(const Duration(seconds: 5), () {
       if (mounted) { // Check if the widget is still in the tree
           _connectWebSocket();
       }
    });
  }


  void _startGyroscopeListener() {
    _gyroscopeSubscription = gyroscopeEvents.listen(
      (GyroscopeEvent event) {
        setState(() {
          _gyroscopeEvent = event;
        });
        if (_channel != null && _channel?.closeCode == null) {
          // Send gyroscope data as a JSON string
          final data = {'x': event.x, 'y': event.y, 'z': event.z};
          _channel?.sink.add(jsonEncode(data));
           print('Sent: ${jsonEncode(data)}'); // Log sent data
        } else {
           print('Cannot send data: WebSocket not connected.');
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
     print('Gyroscope listener started.');
  }

  @override
  void dispose() {
    _gyroscopeSubscription?.cancel();
    _channel?.sink.close();
    print('Gyroscope listener stopped and WebSocket closed.');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AirScribe Sensors'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text(_status),
            const SizedBox(height: 20),
            if (_gyroscopeEvent != null)
              Text(
                'Gyroscope:\nX: ${_gyroscopeEvent!.x.toStringAsFixed(2)}\nY: ${_gyroscopeEvent!.y.toStringAsFixed(2)}\nZ: ${_gyroscopeEvent!.z.toStringAsFixed(2)}',
                textAlign: TextAlign.center,
              )
            else
              const Text('Waiting for gyroscope data...'),
          ],
        ),
      ),
    );
  }
}
