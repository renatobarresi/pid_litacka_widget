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

const STATION_ONE_NAME = "Ujezd A (Svandolo Divadlo)";
const STATION_TWO_NAME = "Ujezd B (Narodni Divadlo)";
const STATION_THREE_NAME = "Ujezd D (Svandolo Divadlo)";

const STATION_ONE_ID = "U809Z1P";
const STATION_TWO_ID = "U809Z2P";
const STATION_THREE_ID = "U809Z4P";
const TIME_LIMIT_TILL_ARRIVAL = 10; // Show trams arriving within 10 minutes

// The passing string to the homewidget should be "station_num_1, arriving_tram_data_num_1"
const String HOME_WIDGET_TRAM_DATA = "arriving_tram_data_num_";
const String HOME_WIDGET_STATION_NUM = "station_num_";

const List<Map<String, String>> STATIONS_LIST = [
  {'id': STATION_ONE_ID, 'name': STATION_ONE_NAME},
  {'id': STATION_TWO_ID, 'name': STATION_TWO_NAME},
  {'id': STATION_THREE_ID, 'name': STATION_THREE_NAME},
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

class PID {

  Future<List<ArrivalMetadata>> getArrivalsForStop(String stopID, int minutesBefore, int minutesAfter) async
  {
    final List<ArrivalMetadata> arrivals = [];
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
      
      final resp = await http.get(url, headers: API_HEADERS).timeout(const Duration(seconds: 5));
      
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
      print('Error fetching arrivals for stop $stopID: $e');
      return [];
    }
  }
}

void main() {
  runApp(MaterialApp(home: MainApp()));
}

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

    HomeWidget.setAppGroupId(_appGroupId);
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

      // Start timer to update arrivals every 10 seconds
      _timer = Timer.periodic(Duration(seconds: 10), (_) {
        _fetchArrivals();
      });

      // Fetch arrivals immediately
      await _fetchArrivals();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _fetchArrivals() async {
      final Map<String, List<ArrivalMetadata>> updatedArrivals = {};

      for (var stopsIndex = 0; stopsIndex < STATIONS_LIST.length; stopsIndex++) {
        try {
          final station = STATIONS_LIST[stopsIndex];
          final stationId = station['id'];

          if (stationId == null || stationId.isEmpty) {
            continue;
          }

          // Get the arrivals for the current stop
          final arrivals = await PID().getArrivalsForStop(
            stationId,
            0,
            TIME_LIMIT_TILL_ARRIVAL,
          );

          updatedArrivals[stationId] = arrivals;

          // Save station name to widget
          final stationName = station['name'] ?? 'Unknown';
          await HomeWidget.saveWidgetData('station_name_${stopsIndex + 1}', stationName);

          // Update home widget data for the current stop
          for (var tramData = 0; tramData < NUMBER_OF_WIDGET_ROWS_PER_STATION; tramData++) {
            final tramArrivalParsedData = arrivals.length > tramData
                ? 'Tram ${arrivals[tramData].tramNumber} in ${arrivals[tramData].arrivingInMinutes} min'
                : '';

            final widgetKey =
                '$HOME_WIDGET_STATION_NUM${stopsIndex + 1},$HOME_WIDGET_TRAM_DATA${tramData + 1}';

            await HomeWidget.saveWidgetData(widgetKey, tramArrivalParsedData);
          }
        } catch (e) {
          print('Error fetching arrivals: $e');
        }
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _arrivalsByStation = updatedArrivals;
      });

      await HomeWidget.updateWidget(
        androidName: _androidWidgetName,
        iOSName: _iosWidgetName,
      );
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
                      const SizedBox(height: 24),
                      ...STATIONS_LIST.asMap().entries.map((entry) {
                        final station = entry.value;
                        final stationId = station['id'] ?? '';
                        final stationName = station['name'] ?? 'Unknown station';
                        final stationArrivals = _arrivalsByStation[stationId] ?? [];

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Station ${entry.key + 1} - $stationName',
                                style: Theme.of(context).textTheme.headlineSmall,
                              ),
                              Text(stationId),
                              const SizedBox(height: 12),
                              if (stationArrivals.isEmpty)
                                const Text('No trams arriving')
                              else
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: stationArrivals
                                      .take(NUMBER_OF_STOPS_TO_SHOW)
                                      .map((arrival) => Text(
                                            'Tram ${arrival.tramNumber} arriving in ${arrival.arrivingInMinutes} minutes',
                                          ))
                                      .toList(),
                                ),
                            ],
                          ),
                        );
                      }),
                    ],
                  ),
                ),
    );
  }
}