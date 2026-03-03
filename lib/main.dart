import 'package:flutter/material.dart';
import 'package:home_widget/home_widget.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';

const STOPS_URL = 'https://data.pid.cz/stops/json/stops.json';
// Todo: Read API from a config file
const API_KEY = "YOUR_KEY";
const API_URL = "https://api.golemio.cz/v2";
const API_HEADERS = {
  'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
  'X-Access-Token': API_KEY
};

const STATION_ONE_ID = "U809Z1P";
const STATION_TWO_ID = "U809Z2P";
const STATION_THREE_ID = "U809Z4P";
const TIME_LIMIT_TILL_ARRIVAL = 10; // Show trams arriving within 10 minutes

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

  /// Fetch stops from API and return a list of stop details filtered by zone_id = "P".
  // Future<List<Stop>> getAllStops({String? stopName}) async {
  //   try {
  //     final uri = Uri.parse('$API_URL/gtfs/stops').replace(
  //       queryParameters: stopName != null && stopName.isNotEmpty ? {'names': stopName} : {},
  //     );
  //     final resp = await http.get(uri, headers: API_HEADERS).timeout(const Duration(seconds: 5));
  //     if (resp.statusCode != 200) {
  //       print('getAllStops HTTP ${resp.statusCode}');
  //       return [];
  //     }
  //     print('getAllStops response: ${resp.body}');
  //     final jsonString = utf8.decode(resp.bodyBytes);
  //     final decoded = jsonDecode(jsonString);

  //     final List<Stop> stopsList = [];
      
  //     // Handle features array
  //     if (decoded is Map<String, dynamic> && decoded['features'] is List) {
  //       final features = decoded['features'] as List<dynamic>;
  //       for (final stop in features) {
  //         final Map<String, dynamic> properties = 
  //             (stop is Map<String, dynamic> && stop['properties'] is Map<String, dynamic>)
  //                 ? (stop['properties'] as Map<String, dynamic>)
  //                 : (stop is Map<String, dynamic> ? stop : <String, dynamic>{});

  //         // Filter by zone_id = "P"
  //         final zoneId = properties['zone_id']?.toString();
  //         if (zoneId != 'P') continue;

  //         final name = properties['stop_name']?.toString();
  //         final id = properties['stop_id']?.toString();
  //         final platformCode = properties['platform_code']?.toString();

  //         if (name != null && name.isNotEmpty && id != null && id.isNotEmpty) {
  //           stopsList.add(Stop(
  //             stopName: name,
  //             stopId: id,
  //             platformCode: platformCode,
  //           ));
  //         }
  //       }
  //     }

  //     return stopsList;
  //   } catch (e) {
  //     print('Error fetching stops: $e');
  //     return [];
  //   }
  // }

  Future<List<ArrivalMetadata>> getArrivalsForStop(String stopID, int minutesBefore, int minutesAfter) async
  {
    final List<ArrivalMetadata> arrivals = [];
    try {
      // Fetch departure board data
      final url = Uri.parse('$API_URL/pid/departureboards').replace(
        queryParameters: {
          'ids': stopID,
          'limit': '5',
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
      // print('getArrivalsForStop response: ${resp.body}');
      final jsonString = utf8.decode(resp.bodyBytes);
      final boardData = jsonDecode(jsonString) as Map<String, dynamic>;
      
      // Parse departure board data
      final departures = boardData['departures'] as List<dynamic>? ?? [];
      for (final departure in departures) {
        final route = (departure is Map<String, dynamic>) ? departure['route'] as Map<String, dynamic>? : null;
        final departureTimestamp = (departure is Map<String, dynamic>) ? departure['departure_timestamp'] as Map<String, dynamic>? : null;
        
        final tramNumber = route?['short_name']?.toString()??'';
        final minutesUntilArrival = departureTimestamp?['minutes'];
        
        // if (tramNumber != null && minutesUntilArrival != null && minutesUntilArrival is int) {
          arrivals.add(ArrivalMetadata(
            arrivingInMinutes: minutesUntilArrival,
            tramNumber: tramNumber,
          ));
        // }
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
  List<ArrivalMetadata> _arrivals = [];
  late Timer _timer;

  // Home widget configuration
  String appGroupId = 'group.cz.renato.tram_alert';
  String androidWidgetName = 'TramAlertWidget';
  String iosWidgetName = 'TramAlertWidget';
  String tramData_1 = "arriving_Trams_1";
  String tramData_2 = "arriving_Trams_2";
  String tramData_3 = "arriving_Trams_3";
  String tramData_4 = "arriving_Trams_4";

  int counter = 1;

  @override
  void initState() {
    super.initState();
    _initializeApp();

    HomeWidget.setAppGroupId(appGroupId);
  }

  Future<void> _initializeApp() async {
    try {
      // Print configuration
      print('Station IDs:');
      print('  STATION_ONE_ID: $STATION_ONE_ID');
      print('  STATION_TWO_ID: $STATION_TWO_ID');
      print('  STATION_THREE_ID: $STATION_THREE_ID');
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
    try {
      final arrivals = await PID().getArrivalsForStop(
        STATION_ONE_ID,
        0,
        TIME_LIMIT_TILL_ARRIVAL,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _arrivals = arrivals;
      });

      // Update home widget with new arrivals
      String arrivalText = arrivals.isEmpty
          ? 'No trams arriving'
          : 'Tram ${arrivals.first.tramNumber} in ${arrivals.first.arrivingInMinutes} min';
      print("Updating widget with arrivals:\n$arrivalText");
      // counter++;
      await HomeWidget.saveWidgetData(tramData_1, arrivalText);
      await HomeWidget.updateWidget(androidName: androidWidgetName, iOSName: iosWidgetName,);

    } catch (e) {
      print('Error fetching arrivals: $e');
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
      body: Center(
        child: _loading
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  CircularProgressIndicator(),
                  SizedBox(height: 12),
                  Text('Loading...'),
                ],
              )
            : _error != null
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Error: $_error'),
                    ],
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Configuration:'),
                      const SizedBox(height: 12),
                      Text('Station 1: $STATION_ONE_ID'),
                      Text('Station 2: $STATION_TWO_ID'),
                      Text('Station 3: $STATION_THREE_ID'),
                      const SizedBox(height: 12),
                      Text('Time limit: $TIME_LIMIT_TILL_ARRIVAL minutes'),
                      const SizedBox(height: 24),
                      // Arrivals board for Station One
                      Column(
                        children: [
                          Text('Station 1 - $STATION_ONE_ID',
                              style: Theme.of(context).textTheme.headlineSmall),
                          const SizedBox(height: 12),
                          if (_arrivals.isEmpty)
                            const Text('No trams arriving')
                          else
                            Column(
                              children: _arrivals
                                  .map((arrival) => Text(
                                        'Tram ${arrival.tramNumber} arriving in ${arrival.arrivingInMinutes} minutes',
                                      ))
                                  .toList(),
                            ),
                        ],
                      ),
                    ],
                  ),
      ),
    );
  }
}