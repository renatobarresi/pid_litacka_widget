import 'package:flutter/material.dart';
import 'package:home_widget/home_widget.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';

const STOPS_URL = 'https://data.pid.cz/stops/json/stops.json';
// Todo: Read API from a config file
const API_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpZCI6MjQxMCwiaWF0IjoxNzA2NTM1Nzk1LCJleHAiOjExNzA2NTM1Nzk1LCJpc3MiOiJnb2xlbWlvIiwianRpIjoiNTBhNzE2NzYtY2RlNC00NDZlLTg0YjItYjkyZTRlYzQ5OTcyIn0.h81f1HJ2Q398Ru4ZOGqqZ1F5kYMGAAWMEUVv5ZH99dQ";
const API_URL = "https://api.golemio.cz/v2";
const API_HEADERS = {
  'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
  'X-Access-Token': API_KEY
};

const NUMBER_OF_STOPS_TO_SHOW = 3; // Show next 3 stops for each station
const NUMBER_OF_WIDGET_ROWS_PER_STATION = 5; // Rows shown per station in Android widget

const STATION_ONE_NAME = "Ujezd Dir: South";
const STATION_TWO_NAME = "Ujezd Dir: North";
const STATION_THREE_NAME = "Ujezd Dir: South";

const STATION_ONE_ID = "U809Z1P";
const STATION_TWO_ID = "U809Z2P";
const STATION_THREE_ID = "U809Z4P";
const TIME_LIMIT_TILL_ARRIVAL = 10; // Show trams arriving within 10 minutes

// The passing string to the homewidget should be "station_num_1, arriving_tram_data_num_1"
const String HOME_WIDGET_TRAM_DATA = "arriving_tram_data_num_";
const String HOME_WIDGET_STATION_NUM = "station_num_";

const List<Map<String, String>> STATIONS_LIST = [
  {'id': STATION_ONE_ID, 'name': STATION_ONE_NAME},
  {'id': STATION_THREE_ID, 'name': STATION_THREE_NAME},
  {'id': STATION_TWO_ID, 'name': STATION_TWO_NAME},
];

class Stop {
  final String? stopName;
  final String? stopId;
  final String? platformCode;

  Stop({
    required this.stopName,
    required this.stopId,
    required this.platformCode,
  });
}

class ArrivalMetadata
{
  final String arrivingInMinutes;
  final String tramNumber;

  ArrivalMetadata({
    required this.arrivingInMinutes,
    required this.tramNumber,
  });
}

bool widgetUpdateRequested = false;

class PID {

  Future<List<ArrivalMetadata>> getArrivalsForStop(String stopID, int minutesBefore, int minutesAfter) async
  {
    final List<ArrivalMetadata> arrivals = [];
    int retries = 3;
    int delayMs = 1000;
    
    while (retries > 0) {
      try {
        // Fetch departure board data
        final url = Uri.parse('$API_URL/pid/departureboards').replace(
          queryParameters: {
            'ids': stopID,
            'limit': NUMBER_OF_WIDGET_ROWS_PER_STATION.toString(),
            'minutesBefore': minutesBefore.toString(),
            'minutesAfter': minutesAfter.toString(),
            'mode': 'arrivals',
          },
        );
        
        final resp = await http.get(url, headers: API_HEADERS).timeout(const Duration(seconds: 15));
        
        if (resp.statusCode != 200) {
          print('getArrivalsForStop HTTP ${resp.statusCode}');
          return [];
        }

        final jsonString = utf8.decode(resp.bodyBytes);
        final boardData = jsonDecode(jsonString) as Map<String, dynamic>;
        
        // Parse departure board data
        final departures = boardData['departures'] as List<dynamic>? ?? [];
        for (final departure in departures) {
          final route = (departure is Map<String, dynamic>) ? departure['route'] as Map<String, dynamic>? : null;
          final departureTimestamp = (departure is Map<String, dynamic>) ? departure['departure_timestamp'] as Map<String, dynamic>? : null;
          
          final tramNumber = route?['short_name']?.toString() ?? '';
          final minutesUntilArrival = departureTimestamp?['minutes']?.toString() ?? '';
          
          arrivals.add(ArrivalMetadata(
            arrivingInMinutes: minutesUntilArrival,
            tramNumber: tramNumber,
          ));
        }
        
        return arrivals;
      } catch (e) {
        retries--;
        if (retries > 0) {
          print('Error fetching arrivals for stop $stopID (retry $retries): $e');
          await Future.delayed(Duration(milliseconds: delayMs));
          delayMs *= 2; // Exponential backoff
        } else {
          print('Error fetching arrivals for stop $stopID (final): $e');
          return [];
        }
      }
    }
    
    return arrivals;
  }
}

/**
 * Main app widget that displays the arrival times for the configured stations and updates the home screen widget data.
 */
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await HomeWidget.setAppGroupId('group.cz.renato.tram_alert');
  await HomeWidget.registerInteractivityCallback(interactiveCallback);
  runApp(MaterialApp(home: MainApp()));
}

/// Static callback for widget interactivity
/// Must be static and public to be called by the platform
@pragma('vm:entry-point')
Future<void> interactiveCallback(Uri? uri) async {
  
  print('Background callback triggered - updating widget data jejeje');
  
  if (uri?.host == 'refresh') {
    print("refresh action received from widget - setting flag to true");
    //await _updateWidgetInBackground();
    widgetUpdateRequested = true;
  }
}

/// Updates widget data in background without opening the app
Future<void> _updateWidget() async {
  String? errorMessage;
  if (widgetUpdateRequested == false)
  {
    return;
  }
  else
  {
    print("Widget update requested - fetching new data");
    widgetUpdateRequested = false;
  }
  try {
    final pid = PID();
    
    for (var stopsIndex = 0; stopsIndex < STATIONS_LIST.length; stopsIndex++) {
      final station = STATIONS_LIST[stopsIndex];
      final stationId = station['id'];

      if (stationId == null || stationId.isEmpty) {
        continue;
      }

      print('Background fetch: Fetching arrivals for ${station['name']}');

      try {
        final arrivals = await pid.getArrivalsForStop(
          stationId,
          0,
          TIME_LIMIT_TILL_ARRIVAL,
        );

        print('Background fetch: Got ${arrivals.length} arrivals');

        // Save station name
        final stationName = station['name'] ?? 'Unknown';
        await HomeWidget.saveWidgetData('station_name_${stopsIndex + 1}', stationName);

        // Save tram arrival data
        for (var tramData = 0; tramData < NUMBER_OF_WIDGET_ROWS_PER_STATION; tramData++) {
          final tramArrivalParsedData = arrivals.length > tramData
              ? 'Tram ${arrivals[tramData].tramNumber} in ${arrivals[tramData].arrivingInMinutes} min'
              : 'Unable to fetch data';

          final widgetKey =
              '$HOME_WIDGET_STATION_NUM${stopsIndex + 1},$HOME_WIDGET_TRAM_DATA${tramData + 1}';

          await HomeWidget.saveWidgetData(widgetKey, tramArrivalParsedData);
        }
      } catch (stationError) {
        errorMessage = 'Error: $stationError';
        print('Background fetch error: $errorMessage');
      }
    }

    // Save refresh timestamp
    final now = DateTime.now();
    final formattedTime = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
    await HomeWidget.saveWidgetData('last_updated_time', formattedTime);

    // Update widget display
    await HomeWidget.updateWidget(
      androidName: 'TramAlertWidget',
      iOSName: 'TramAlertWidget',
    );

    print('Background update complete');
  } catch (e) {
    print('Fatal error in background update: $e');
  }
}
/**
 * MainApp is a stateful widget that manages the state of the application, including loading status, error handling,
 * and arrival data for each station. It initializes the app, fetches arrival data periodically,
 * and updates the home screen widget with the latest information.
 */
class MainApp extends StatefulWidget {
  const MainApp({super.key});

  @override
  State<MainApp> createState() => _MainAppState();
}

class _MainAppState extends State<MainApp> {
  bool _loading = true;
  String? _error;
  Map<String, List<ArrivalMetadata>> _arrivalsByStation = {};
  late Timer _timer;

  // Home widget configuration
  final String _appGroupId = 'group.cz.renato.tram_alert';
  final String _androidWidgetName = 'TramAlertWidget';
  final String _iosWidgetName = 'TramAlertWidget';

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    try {
      // Print configuration
      print('Station IDs:');
      for (final station in STATIONS_LIST) {
        print('  ${station['name']}: ${station['id']}');
      }
      print('Time limit till arrival: $TIME_LIMIT_TILL_ARRIVAL minutes');
      
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
      });

      _timer = Timer.periodic(Duration(seconds: 1), (_) {
        _updateWidget();
      });
      
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });

    }
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _loading
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  CircularProgressIndicator(),
                  SizedBox(height: 12),
                  Text('Loading...'),
                ],
              ),
            )
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Error: $_error'),
                    ],
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Configuration:'),
                      const SizedBox(height: 12),
                      ...STATIONS_LIST.asMap().entries.map(
                        (entry) => Text(
                          'Station ${entry.key + 1}: ${entry.value['name']} (${entry.value['id']})',
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text('Time limit: $TIME_LIMIT_TILL_ARRIVAL minutes'),
                      const SizedBox(height: 24)
                    ],
                  ),
                ),
    );
  }
}