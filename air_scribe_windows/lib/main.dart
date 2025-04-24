import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class PointData {
  final Offset? offset;
  final double? strokeWidth;

  PointData(this.offset, this.strokeWidth);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PointData &&
          runtimeType == other.runtimeType &&
          offset == other.offset &&
          strokeWidth == other.strokeWidth;

  @override
  int get hashCode => offset.hashCode ^ strokeWidth.hashCode;
}

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'AirScribe Whiteboard',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.lightBlue),
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.lightBlue,
          brightness: Brightness.dark,
        ),
        brightness: Brightness.dark,
      ),
      themeMode: ThemeMode.system,
      home: const WhiteboardPage(),
    );
  }
}

class WhiteboardPage extends StatefulWidget {
  const WhiteboardPage({super.key});

  @override
  State<WhiteboardPage> createState() => _WhiteboardPageState();
}

class _WhiteboardPageState extends State<WhiteboardPage> {
  HttpServer? _server;
  WebSocketChannel? _clientChannel;
  String _ipAddress = 'Fetching IP...';
  String _status = 'Server not running';
  final List<PointData> _points = <PointData>[];
  Offset? _currentPosition;
  Size _whiteboardSize = Size.zero;
  final double _sensitivity = 10.0;
  final int _port = 8080;

  final double _baseStrokeWidth = 5.0;
  final double _minStrokeWidth = 1.0;
  final double _maxStrokeWidth = 100.0;
  final double _strokeWidthSensitivity = 5.0;

  double _smoothedStrokeWidth = 5.0;
  final double _strokeWidthSmoothingFactor = 0.2;

  final int _smoothingWindowSize = 1;
  final List<double> _recentDx = [];
  final List<double> _recentDy = [];

  bool _isClientDrawing = false;
  bool _wasClientDrawing = false;

  @override
  void initState() {
    super.initState();
    _smoothedStrokeWidth = _baseStrokeWidth;
    _startServer();
  }

  Future<void> _startServer() async {
    try {
      final ip = await NetworkInfo().getWifiIP();
      if (ip == null) {
        setState(() {
          _status = 'Could not get WiFi IP. Ensure WiFi is connected.';
          _ipAddress = 'Error';
        });
        return;
      }

      setState(() {
        _ipAddress = '$ip:$_port';
      });

      var handler = webSocketHandler((WebSocketChannel webSocket) {
        setState(() {
          _clientChannel = webSocket;
          _status = 'Client Connected';
          _points.clear();
          _recentDx.clear();
          _recentDy.clear();
          _smoothedStrokeWidth = _baseStrokeWidth;
          _isClientDrawing = false;
          _wasClientDrawing = false;
          if (_whiteboardSize != Size.zero) {
            _currentPosition = Offset(
              _whiteboardSize.width / 2,
              _whiteboardSize.height / 2,
            );
          } else {
            _currentPosition = null;
          }
        });
        print('Client connected!');

        webSocket.stream.listen(
          (message) {
            // Step 1: Sensing (Indirect) - Receive sensor data packet from the client app via WebSocket.
            try {
              final data = jsonDecode(message);
              if (data is Map<String, dynamic> &&
                  data.containsKey('isDrawing') &&
                  data['isDrawing'] is bool) {
                _isClientDrawing = data['isDrawing'];
              } else {
                _isClientDrawing = false;
                print('Received data missing "isDrawing" flag: $message');
              }

              if (data is Map<String, dynamic> && data.containsKey('gyro')) {
                final gyroData = data['gyro'];
                if (gyroData is Map<String, dynamic> &&
                    gyroData.containsKey('x') &&
                    gyroData['x'] is num &&
                    gyroData.containsKey('y') &&
                    gyroData['y'] is num &&
                    gyroData.containsKey('z') &&
                    gyroData['z'] is num) {
                  setState(() {
                    _updateDrawing(gyroData);
                    _wasClientDrawing = _isClientDrawing;
                  });
                } else {
                  print('Received gyro data in unexpected format: $gyroData');
                }
              } else {
                print('Received unexpected data format: $message');
              }
            } catch (e) {
              print('Error decoding message: $e');
            }
          },
          onDone: () {
            setState(() {
              _status = 'Client Disconnected';
              _clientChannel = null;
              _isClientDrawing = false;
              _wasClientDrawing = false;
              _smoothedStrokeWidth = _baseStrokeWidth;
              if (_points.isNotEmpty && _points.last.offset != null) {
                _points.add(PointData(null, null));
              }
            });
            print('Client disconnected');
          },
          onError: (error) {
            setState(() {
              _status = 'Client Error: $error';
              _clientChannel = null;
              _isClientDrawing = false;
              _wasClientDrawing = false;
              _smoothedStrokeWidth = _baseStrokeWidth;
              if (_points.isNotEmpty && _points.last.offset != null) {
                _points.add(PointData(null, null));
              }
            });
            print('Client error: $error');
          },
        );
      });

      _server = await io.serve(handler, InternetAddress.anyIPv4, _port);
      setState(() {
        _status = 'Server running at ws://$_ipAddress';
      });
      print('Server running on ws://$_ipAddress');
    } catch (e) {
      setState(() {
        _status = 'Error starting server: $e';
        _ipAddress = 'Error';
      });
      print('Error starting server: $e');
    }
  }

  void _updateDrawing(Map<String, dynamic> gyroData) {
    if (_whiteboardSize == Size.zero) return;

    _currentPosition ??= Offset(
      _whiteboardSize.width / 2,
      _whiteboardSize.height / 2,
    );

    // Step 2: Preprocessing & Step 3: Feature Extraction (Stroke Width)
    // Use gyro 'z' data to calculate target stroke width.
    // Apply smoothing (preprocessing) to the stroke width.
    final double gz = gyroData['z'];
    double targetStrokeWidth =
        _baseStrokeWidth + (gz * _strokeWidthSensitivity);
    targetStrokeWidth = targetStrokeWidth.clamp(
      _minStrokeWidth,
      _maxStrokeWidth,
    );
    // Smoothing (Preprocessing)
    _smoothedStrokeWidth =
        _smoothedStrokeWidth +
        (targetStrokeWidth - _smoothedStrokeWidth) *
            _strokeWidthSmoothingFactor;
    _smoothedStrokeWidth = _smoothedStrokeWidth.clamp(
      _minStrokeWidth,
      _maxStrokeWidth,
    );

    // Step 2: Preprocessing & Step 3: Feature Extraction (Position Change)
    // Use gyro 'x' and 'z' to calculate raw displacement (dx, dy).
    final double gx = gyroData['x'];
    final double rawDx = -gz * _sensitivity;
    final double rawDy = -gx * _sensitivity;

    _recentDx.add(rawDx);
    _recentDy.add(rawDy);

    if (_recentDx.length > _smoothingWindowSize) _recentDx.removeAt(0);
    if (_recentDy.length > _smoothingWindowSize) _recentDy.removeAt(0);

    final double smoothedDx =
        _recentDx.isEmpty
            ? 0.0
            : _recentDx.reduce((a, b) => a + b) / _recentDx.length;
    final double smoothedDy =
        _recentDy.isEmpty
            ? 0.0
            : _recentDy.reduce((a, b) => a + b) / _recentDy.length;

    // Step 4: Inference/Application - Update the drawing based on extracted features.
    // Update cursor position using smoothed displacement features.
    Offset newPosition = _currentPosition!.translate(smoothedDx, smoothedDy);
    newPosition = Offset(
      newPosition.dx.clamp(0.0, _whiteboardSize.width),
      newPosition.dy.clamp(0.0, _whiteboardSize.height),
    );
    _currentPosition = newPosition;

    if (_isClientDrawing) {
      _points.add(PointData(_currentPosition, _smoothedStrokeWidth));
    } else if (_wasClientDrawing) {
      if (_points.isNotEmpty && _points.last.offset != null) {
        _points.add(PointData(null, null));
      }
    }

    const int maxPoints = 5000;
    const int pointsToRemove = 1000;
    if (_points.length > maxPoints) {
      int removalEnd = pointsToRemove;
      while (removalEnd < _points.length &&
          _points[removalEnd].offset == null) {
        removalEnd++;
      }
      if (removalEnd < _points.length || removalEnd == pointsToRemove) {
        _points.removeRange(0, removalEnd);
        print('Optimized points list: ${_points.length} points remaining.');
      } else {
        print('Skipped optimization to prevent breaking line segment.');
      }
    }
  }

  void _clearDrawing() {
    setState(() {
      _points.clear();
      _smoothedStrokeWidth = _baseStrokeWidth;
      _isClientDrawing = false;
      _wasClientDrawing = false;
    });
  }

  @override
  void dispose() {
    _clientChannel?.sink.close();
    _server?.close(force: true);
    print('Server stopped.');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    bool isConnected = _clientChannel != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('AirScribe Whiteboard'),
        backgroundColor: theme.colorScheme.surfaceVariant,
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined),
            tooltip: 'Clear Drawing',
            color:
                isConnected ? theme.colorScheme.primary : theme.disabledColor,
            onPressed: isConnected ? _clearDrawing : null,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 8.0),
            child: Card(
              elevation: 2.0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8.0),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16.0,
                  vertical: 12.0,
                ),
                child: Row(
                  children: [
                    Icon(
                      isConnected ? Icons.lan_rounded : Icons.lan_outlined,
                      color: isConnected ? Colors.green : theme.disabledColor,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Server IP: $_ipAddress',
                            style: theme.textTheme.bodyMedium,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            'Status: $_status',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color:
                                  isConnected
                                      ? Colors.green
                                      : theme.colorScheme.onSurfaceVariant,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16.0, 8.0, 16.0, 16.0),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final newSize = Size(
                    constraints.maxWidth,
                    constraints.maxHeight,
                  );
                  if (_whiteboardSize != newSize) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) {
                        setState(() {
                          final oldSize = _whiteboardSize;
                          _whiteboardSize = newSize;
                          if (_currentPosition != null &&
                              oldSize != Size.zero) {
                            _currentPosition = Offset(
                              _currentPosition!.dx.clamp(0.0, newSize.width),
                              _currentPosition!.dy.clamp(0.0, newSize.height),
                            );
                          } else if (_currentPosition == null && isConnected) {
                            _currentPosition = Offset(
                              newSize.width / 2,
                              newSize.height / 2,
                            );
                          }
                        });
                      }
                    });
                  }
                  return Container(
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface,
                      border: Border.all(
                        color: theme.dividerColor.withOpacity(0.5),
                      ),
                      borderRadius: BorderRadius.circular(8.0),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 4.0,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8.0),
                      child: CustomPaint(
                        // Step 4: Inference/Application - Render the drawing on the canvas.
                        // The painter uses the list of points (_points), current position,
                        // and connection status to draw lines and the pointer.
                        painter: WhiteboardPainter(
                          points: _points,
                          lineColor:
                              theme.brightness == Brightness.dark
                                  ? Colors.white
                                  : Colors.black,
                          pointerColor: theme.colorScheme.primary,
                          currentPosition: _currentPosition,
                          isClientConnected: isConnected,
                        ),
                        size: _whiteboardSize,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class WhiteboardPainter extends CustomPainter {
  final List<PointData> points;
  final Color lineColor;
  final Color pointerColor;
  final Offset? currentPosition;
  final bool isClientConnected;

  WhiteboardPainter({
    required this.points,
    required this.lineColor,
    required this.pointerColor,
    required this.currentPosition,
    required this.isClientConnected,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Step 4: Inference/Application - Actual drawing logic based on processed data.
    final linePaint =
        Paint()
          ..color = lineColor
          ..strokeCap = StrokeCap.round;

    for (int i = 0; i < points.length - 1; i++) {
      final PointData currentPoint = points[i];
      final PointData nextPoint = points[i + 1];

      if (currentPoint.offset != null &&
          nextPoint.offset != null &&
          nextPoint.strokeWidth != null) {
        linePaint.strokeWidth = nextPoint.strokeWidth!;
        canvas.drawLine(currentPoint.offset!, nextPoint.offset!, linePaint);
      }
    }

    if (isClientConnected && currentPosition != null) {
      final pointerPaint =
          Paint()
            ..color = pointerColor
            ..style = PaintingStyle.fill;
      canvas.drawCircle(currentPosition!, 5.0, pointerPaint);

      final pointerOutlinePaint =
          Paint()
            ..color = lineColor.withOpacity(0.7)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5;
      canvas.drawCircle(currentPosition!, 6.0, pointerOutlinePaint);
    }
  }

  @override
  bool shouldRepaint(covariant WhiteboardPainter oldDelegate) {
    return oldDelegate.points != points ||
        oldDelegate.lineColor != lineColor ||
        oldDelegate.pointerColor != pointerColor ||
        oldDelegate.currentPosition != currentPosition ||
        oldDelegate.isClientConnected != isClientConnected;
  }
}
