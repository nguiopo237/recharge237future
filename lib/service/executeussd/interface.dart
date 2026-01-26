// lib/test_ussd.dart
import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter/services.dart';

class Test extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: Text('Test USSD Minimal')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton(
                onPressed: () => testMethodChannel(),
                child: Text('Tester MethodChannel'),
              ),
              SizedBox(height: 20),
              ElevatedButton(
                onPressed: () => testSendSingleUssd(),
                child: Text('Tester sendSingleUssd'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> testMethodChannel() async {
  const channel = MethodChannel('com.example.ussd/native');

  print("🔄 Test MethodChannel...");

  try {
    // Test 1: Méthode simple
    final result1 = await channel.invokeMethod('testConnection');
    print("✅ testConnection: $result1");

    // Test 2: Méthode avec paramètres
    final result2 = await channel.invokeMethod('initialize');
    print("✅ initialize: $result2");

  } on PlatformException catch (e) {
    print("❌ PlatformException:");
    print("  Code: ${e.code}");
    print("  Message: ${e.message}");
    print("  Details: ${e.details}");
  } catch (e) {
    print("❌ Exception: $e");
  }
}

Future<void> testSendSingleUssd() async {
  const channel = MethodChannel('com.example.ussd/native');

  print("📤 Test sendSingleUssd...");

  try {
    final result = await channel.invokeMethod('sendSingleUssd', {
      'code': '*123#',
      'simSlot': 0,
    });

    print("✅ sendSingleUssd: $result");

  } on PlatformException catch (e) {
    print("❌ PlatformException sendSingleUssd:");
    print("  Code: ${e.code}");
    print("  Message: ${e.message}");

    if (e.code == 'MissingPluginException') {
      print("⚠️  CAUSE: La méthode 'sendSingleUssd' n'est pas enregistrée dans MainActivity.kt");
      print("⚠️  SOLUTION: Vérifiez que la méthode est dans le when(call.method) { ... }");
    }

  } catch (e) {
    print("❌ Exception: $e");
  }
}