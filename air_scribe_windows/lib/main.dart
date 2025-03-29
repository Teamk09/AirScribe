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
      title: 'AirScribe Whiteboard',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
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
  final List<Offset?> _points = <Offset?>[]; // Store points for drawing lines
  Offset? _currentPosition; // Current drawing cursor position
  Size _whiteboardSize = Size.zero; // Size of the drawing area
  final double _sensitivity = 100.0; // Adjust sensitivity of gyro movement
  final int _port = 8080; // Same port as in the client app

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
          if (_whiteboardSize != Size.zero) {
             _currentPosition = Offset(_whiteboardSize.width / 2, _whiteboardSize.height / 2);
             _points.add(_currentPosition);
          } else {
             _currentPosition = null; 
          }
        });
        print('Client connected!');

        webSocket.stream.listen(
          (message) {
            try {
              final data = jsonDecode(message);
              if (data is Map<String, dynamic> &&
                  data.containsKey('x') && data['x'] is num &&
                  data.containsKey('y') && data['y'] is num &&
                  data.containsKey('z') && data['z'] is num)
              {
                  setState(() {
                      _updateDrawing(data); // Process gyro data for drawing
                  });
                  // print('Received: $data'); // Optional: reduce console noise
              } else {
                  print('Received invalid data format: $message');
              }
            } catch (e) {
              print('Error decoding message: $e');
            }
          },
          onDone: () {
            setState(() {
              _status = 'Client Disconnected';
              _clientChannel = null;
              // Add a null to break the line when client disconnects
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
               // Add a null to break the line on error
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
      if (_currentPosition == null || _whiteboardSize == Size.zero) return; // Don't draw if position/size unknown

      // New mapping for upright orientation:
      // Gyro Z rotation (twist) -> Screen X movement (Inverted)
      // Gyro X rotation (tilt forward/back) -> Screen Y movement
      // Adjust signs and sensitivity as needed for intuitive control.
      final double dx = -gyroData['z'] * _sensitivity; // Negated Z for inverted horizontal control
      final double dy = -gyroData['x'] * _sensitivity;

      // Calculate the new position
      Offset newPosition = _currentPosition!.translate(dx, dy);

      // Clamp the position to stay within the whiteboard bounds
      newPosition = Offset(
          newPosition.dx.clamp(0.0, _whiteboardSize.width),
          newPosition.dy.clamp(0.0, _whiteboardSize.height),
      );

      _currentPosition = newPosition;
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
             _currentPosition = Offset(_whiteboardSize.width / 2, _whiteboardSize.height / 2);
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('AirScribe Whiteboard'),
        actions: [
           // Add a clear button
           IconButton(
              icon: const Icon(Icons.clear),
              tooltip: 'Clear Drawing',
              onPressed: _clientChannel != null ? _clearDrawing : null, // Only enable when connected
           ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                 Text('Server IP: $_ipAddress'),
                 Text('Status: $_status'),
                 const SizedBox(height: 10),
                 if (_clientChannel == null && _server != null)
                    const Text('Waiting for client connection...'),
              ],
            ),
          ),
          Expanded(
            // Use LayoutBuilder to get the size of the drawing area
            child: LayoutBuilder(
              builder: (context, constraints) {
                final newSize = Size(constraints.maxWidth, constraints.maxHeight);
                if (_whiteboardSize != newSize) {
                  // Update size and potentially initialize position if needed
                  // Use addPostFrameCallback to avoid calling setState during build
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                     if (mounted) { // Check if widget is still mounted
                        setState(() {
                           _whiteboardSize = newSize;
                           // Initialize or re-center position if client is connected but position wasn't set
                           if (_currentPosition == null && _clientChannel != null) {
                              _currentPosition = Offset(_whiteboardSize.width / 2, _whiteboardSize.height / 2);
                              // Avoid adding point here if _points might already exist from previous size
                              if (_points.isEmpty) _points.add(_currentPosition);
                           }
                        });
                     }
                  });
                }
                return Container(
                  margin: const EdgeInsets.fromLTRB(16.0, 0, 16.0, 16.0), // Adjust margin
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey),
                    color: Colors.white,
                  ),
                  // Clip prevents drawing outside the bounds
                  child: ClipRect(
                    child: CustomPaint(
                      painter: WhiteboardPainter(points: _points),
                      size: _whiteboardSize, // Provide the size to the painter
                    ),
                  ),
                );
              },
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

  WhiteboardPainter({required this.points});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 4.0; // Adjust line thickness

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
    // Repaint whenever the points list changes
    return oldDelegate.points != points;
  }
}
