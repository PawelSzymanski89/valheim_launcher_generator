import 'dart:async';
import 'dart:io';

enum Protocol { tcp, udp, both }

void main() async {
  final String host = 'howtodev.it';
  final int maxPort = 30000; // Scan range 0..maxPort
  final int numThreads = 10;
  final Duration timeout = Duration(milliseconds: 300);
  final Protocol protocol = Protocol.both; // Check TCP first, then UDP heuristic

  print('Scanning ports 0-$maxPort on $host using $numThreads threads (mode=$protocol, timeout=${timeout.inMilliseconds}ms)');

  final addresses = await InternetAddress.lookup(host);
  final target = addresses.firstWhere((ip) => ip.type == InternetAddressType.IPv4, orElse: () => addresses.first);

  int portsPerThread = (maxPort / numThreads).ceil();

  // Shared collection for alive (working) ports across all threads
  final List<int> openPorts = [];

  List<Future> futures = [];

  for (int i = 0; i < numThreads; i++) {
    int startPort = i * portsPerThread;
    int endPort = ((i + 1) * portsPerThread) - 1;
    if (endPort > maxPort) endPort = maxPort;

    futures.add(scanPortRange(target, startPort, endPort, timeout, i + 1, openPorts, protocol));
  }

  await Future.wait(futures);

  // Summary of working ports
  openPorts.sort();
  if (openPorts.isEmpty) {
    print('Summary: No working ports found.');
  } else {
    print('Summary: Found ${openPorts.length} working port(s): ${openPorts.join(', ')}');
  }

  print('Full scan completed.');
}

Future<void> scanPortRange(InternetAddress target, int start, int end, Duration timeout, int threadId, List<int> openPorts, Protocol protocol) async {
  for (int port = start; port <= end; port++) {
    bool isOpen = await checkPortOpen(target, port, timeout, protocol);
    if (isOpen) {
      print('[Thread $threadId] Port $port -> OPEN');
      openPorts.add(port);
    } else {
      print('[Thread $threadId] Port $port -> CLOSED');
    }
  }
}

Future<bool> checkPortOpen(InternetAddress target, int port, Duration timeout, Protocol protocol) async {
  switch (protocol) {
    case Protocol.tcp:
      return _checkTcp(target, port, timeout);
    case Protocol.udp:
      return _checkUdpHeuristic(target, port, timeout);
    case Protocol.both:
      // Try TCP; if closed, try UDP heuristic so game UDP ports like 21053 can be detected
      final tcp = await _checkTcp(target, port, timeout);
      if (tcp) return true;
      return _checkUdpHeuristic(target, port, timeout);
  }
}

Future<bool> _checkTcp(InternetAddress target, int port, Duration timeout) async {
  try {
    final socket = await Socket.connect(target, port, timeout: timeout);
    socket.destroy();
    return true; // TCP connect succeeded
  } catch (_) {
    return false;
  }
}

Future<bool> _checkUdpHeuristic(InternetAddress target, int port, Duration timeout) async {
  // UDP services often do not respond to arbitrary payloads. We treat "no ICMP error within timeout" as OPEN|FILTERED,
  // which is usually acceptable for discovering active game ports like Valheim.
  RawDatagramSocket? socket;
  StreamSubscription<RawSocketEvent>? sub;
  try {
    socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    socket.readEventsEnabled = true;

    final completer = Completer<bool>();
    Timer? to;

    void finish(bool value) {
      if (!completer.isCompleted) completer.complete(value);
    }

    sub = socket.listen((RawSocketEvent event) {
      if (event == RawSocketEvent.read) {
        final d = socket?.receive();
        if (d != null) {
          // Any UDP response from the target implies the port is open
          if (d.address.address == target.address || d.address == target) {
            finish(true);
          }
        }
      } else if (event == RawSocketEvent.closed) {
        // If the socket closes unexpectedly before timeout, treat as closed
        finish(false);
      }
    });

    // Send a small payload; we consider the port OPEN only if a UDP response arrives within the timeout.
    socket.send([0x00], target, port);

    to = Timer(timeout, () {
      // No response within timeout: treat as CLOSED for UDP to avoid false positives
      finish(false);
    });

    final result = await completer.future;
    to?.cancel();
    await sub.cancel();
    socket.close();
    return result;
  } catch (_) {
    try { await sub?.cancel(); } catch (_) {}
    socket?.close();
    return false;
  }
}
