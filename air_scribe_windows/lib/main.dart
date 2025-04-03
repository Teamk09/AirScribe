import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

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
  final List<Offset?> _points = <Offset?>[];
  Offset? _currentPosition;
  Size _whiteboardSize = Size.zero;
  final double _sensitivity = 8000.0;
  final int _port = 8080;

  // Variables for smoothing
  final int _smoothingWindowSize = 3;
  final List<double> _recentDx = [];
  final List<double> _recentDy = [];

  @override
  void initState() {
    super.initState();
    _startServer();
  }

  Future<void> _startServer() async {
    try {
      final ip = await NetworkInfo().getWifiIP(); // Get local IP
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
          // Reset drawing state on new connection
          _points.clear();
          _recentDx.clear(); // Clear smoothing buffers
          _recentDy.clear();
          if (_whiteboardSize != Size.zero) {
            _currentPosition = Offset(
              _whiteboardSize.width / 2,
              _whiteboardSize.height / 2,
            );
            _points.add(_currentPosition); // Start line at center
          } else {
            _currentPosition = null;
          }
        });
        print('Client connected!');

        webSocket.stream.listen(
          (message) {
            try {
              final data = jsonDecode(message);
              // Directly check for gyroscope data map
              if (data is Map<String, dynamic> &&
                  data.containsKey('x') &&
                  data['x'] is num &&
                  data.containsKey('y') &&
                  data['y'] is num &&
                  data.containsKey('z') &&
                  data['z'] is num) {
                setState(() {
                  _updateDrawing(data); // Process gyro data for drawing
                });
              } else {
                // Log unexpected message format
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
              // Add null to break the line on disconnect
              if (_points.isNotEmpty && _points.last != null) {
                _points.add(null);
              }
            });
            print('Client disconnected');
          },
          onError: (error) {
            setState(() {
              _status = 'Client Error: $error';
              _clientChannel = null;
              // Add null to break the line on error
              if (_points.isNotEmpty && _points.last != null) {
                _points.add(null);
              }
            });
            print('Client error: $error');
          },
        );
      });

      // Use InternetAddress.anyIPv4 to listen on all available IPv4 interfaces
      _server = await io.serve(handler, InternetAddress.anyIPv4, _port);
      setState(() {
        // Update status, keeping the fetched IP for display
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
    // This function now runs for all received gyro data
    if (_currentPosition == null || _whiteboardSize == Size.zero) return;

    // Calculate raw dx and dy based on gyro data
    final double gx = gyroData['x'];
    final double gz = gyroData['z'];
    final double rawDx = -gz * _sensitivity;
    final double rawDy = -gx * _sensitivity;

    // Add current raw values to the smoothing buffers
    _recentDx.add(rawDx);
    _recentDy.add(rawDy);

    // Keep buffers at the desired window size
    if (_recentDx.length > _smoothingWindowSize) {
      _recentDx.removeAt(0);
    }
    if (_recentDy.length > _smoothingWindowSize) {
      _recentDy.removeAt(0);
    }

    // Calculate the average (smoothed) dx and dy
    final double smoothedDx =
        _recentDx.isEmpty
            ? 0.0
            : _recentDx.reduce((a, b) => a + b) / _recentDx.length;
    final double smoothedDy =
        _recentDy.isEmpty
            ? 0.0
            : _recentDy.reduce((a, b) => a + b) / _recentDy.length;

    // Calculate the new position using smoothed values
    Offset newPosition = _currentPosition!.translate(smoothedDx, smoothedDy);

    // Clamp the position to stay within the whiteboard bounds
    newPosition = Offset(
      newPosition.dx.clamp(0.0, _whiteboardSize.width),
      newPosition.dy.clamp(0.0, _whiteboardSize.height),
    );

    _currentPosition = newPosition;

    // Add point (always add when data is received)
    _points.add(_currentPosition);

    // Limit the number of points to prevent performance issues
    const int maxPoints = 5000; // Keep the last 5000 points
    const int pointsToRemove = 1000; // Remove points in chunks
    if (_points.length > maxPoints) {
      // Remove older points efficiently
      _points.removeRange(0, pointsToRemove);
      print('Optimized points list: ${_points.length} points remaining.');
    }
  }

  void _clearDrawing() {
    setState(() {
      _points.clear();
      if (_whiteboardSize != Size.zero) {
        _currentPosition = Offset(
          _whiteboardSize.width / 2,
          _whiteboardSize.height / 2,
        );
      } else {
        _currentPosition = null;
      }
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
        backgroundColor:
            theme.colorScheme.surfaceVariant, // Subtle AppBar background
        actions: [
          // Keep the clear button, maybe style it slightly
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined),
            tooltip: 'Clear Drawing',
            color:
                isConnected ? theme.colorScheme.primary : theme.disabledColor,
            onPressed: isConnected ? _clearDrawing : null,
          ),
          const SizedBox(width: 8), // Add spacing
        ],
      ),
      body: Column(
        children: [
          // Status Area in a Card
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
          // Whiteboard Area
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
                    // Update size and potentially initialize position if needed
                    // Use addPostFrameCallback to avoid calling setState during build
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) {
                        // Check if widget is still mounted
                        setState(() {
                          _whiteboardSize = newSize;
                          // Initialize or re-center position if client is connected but position wasn't set
                          if (_currentPosition == null &&
                              _clientChannel != null) {
                            _currentPosition = Offset(
                              _whiteboardSize.width / 2,
                              _whiteboardSize.height / 2,
                            );
                            // Avoid adding point here if _points might already exist from previous size
                            if (_points.isEmpty) _points.add(_currentPosition);
                          }
                        });
                      }
                    });
                  }
                  return Container(
                    // Use Card elevation/border for a defined drawing area
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface, // Whiteboard background
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
                    // Clip prevents drawing outside the bounds
                    child: ClipRRect(
                      // Use ClipRRect for rounded corners
                      borderRadius: BorderRadius.circular(8.0),
                      child: CustomPaint(
                        painter: WhiteboardPainter(points: _points),
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

// Custom Painter for the Whiteboard
class WhiteboardPainter extends CustomPainter {
  final List<Offset?> points;
  final Color lineColor;
  final double strokeWidth;

  // Make painter customizable
  WhiteboardPainter({
    required this.points,
    this.lineColor = const Color.fromARGB(255, 255, 255, 255),
    this.strokeWidth = 3.0, // Slightly thinner default
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint =
        Paint()
          ..color = lineColor
          ..strokeCap = StrokeCap.round
          ..strokeWidth = strokeWidth;

    for (int i = 0; i < points.length - 1; i++) {
      if (points[i] != null && points[i + 1] != null) {
        // Draw a line between consecutive points
        canvas.drawLine(points[i]!, points[i + 1]!, paint);
      } else if (points[i] != null && points[i + 1] == null) {
        // If the next point is null, draw a small circle at the current point
        // This handles the end of a line segment before a break (null)
        // canvas.drawCircle(points[i]!, paint.strokeWidth / 2, paint);
        // Alternatively, just do nothing to create a break
      }
    }
    // Optionally draw the last point if it's not null and the list isn't empty
    // if (points.isNotEmpty && points.last != null) {
    //    canvas.drawCircle(points.last!, paint.strokeWidth / 2, paint);
    // }
  }

  @override
  bool shouldRepaint(covariant WhiteboardPainter oldDelegate) {
    // Repaint if points, color, or stroke width change
    return oldDelegate.points != points ||
        oldDelegate.lineColor != lineColor ||
        oldDelegate.strokeWidth != strokeWidth;
  }
}
