import 'package:flutter/material.dart';
import 'main.dart';

class IpInputPage extends StatefulWidget {
  const IpInputPage({super.key});

  @override
  State<IpInputPage> createState() => _IpInputPageState();
}

class _IpInputPageState extends State<IpInputPage> {
  final _ipController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _ipController.dispose();
    super.dispose();
  }

  void _submitIp() {
    if (_formKey.currentState!.validate()) {
      final ipAddress = _ipController.text.trim();
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => SensorPage(serverIp: ipAddress),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Enter Server IP'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Card(
            elevation: 4.0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      'Server IP Address',
                      style: theme.textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 20),
                    TextFormField(
                      controller: _ipController,
                      decoration: const InputDecoration(
                        labelText: 'IP Address (e.g., 192.168.1.100)',
                        hintText: 'Enter the server IP',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.url, 
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Please enter an IP address';
                        }
                        final ipPattern = RegExp(
                            r'^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$');
                        if (!ipPattern.hasMatch(value.trim())) {
                          return 'Please enter a valid IPv4 address';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: _submitIp,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
                        textStyle: theme.textTheme.labelLarge,
                      ),
                      child: const Text('Connect'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}