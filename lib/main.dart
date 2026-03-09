
import 'package:flutter/material.dart';
import 'package:home_widget/home_widget.dart';
import 'package:workmanager/workmanager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'pid_litacka_parser.dart';

const timeLimitTillArrival = 10; // Show trams arriving within 10 minutes

// The passing string to the homewidget should be "station_num_1, arriving_tram_data_num_1"
const String homeWidgetTramData = "arriving_tram_data_num_";
const String homeWidgetStationNum = "station_num_";

const String homeWidgetGroupId = "group.cz.litacka.tram_billboard";

List<Map<String, String>> stationList = [
  {'id': "", 'name': ""},
  {'id': "", 'name': ""},
  {'id': "", 'name': ""},
];

// Load station configurations from SharedPreferences
Future<void> loadStationConfigs() async {
  final prefs = await SharedPreferences.getInstance();
  for (int i = 0; i < stationList.length; i++) {
    final name = prefs.getString('station_${i}_name');
    final id = prefs.getString('station_${i}_id');
    if (name != null) stationList[i]['name'] = name;
    if (id != null) stationList[i]['id'] = id;
  }
}

// Save station configurations to SharedPreferences
Future<void> saveStationConfigs() async {
  final prefs = await SharedPreferences.getInstance();
  for (int i = 0; i < stationList.length; i++) {
    await prefs.setString('station_${i}_name', stationList[i]['name'] ?? '');
    await prefs.setString('station_${i}_id', stationList[i]['id'] ?? '');
  }
}

// Save API key to SharedPreferences
Future<void> saveApiKey(String apiKey) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('api_key', apiKey);
}

// Load API key from SharedPreferences
Future<String?> loadApiKey() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString('api_key');
}

Future<void> loadAndApplyApiKey() async {
  final savedApiKey = await loadApiKey();
  if (savedApiKey != null && savedApiKey.isNotEmpty) {
    pid.setApiKey(savedApiKey);
  }
}

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

final pid = LitackaEndpointParser();

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {

    bool ret = false;

    WidgetsFlutterBinding.ensureInitialized();

    await HomeWidget.setAppGroupId('group.cz.renato.tram_alert');

    await loadStationConfigs();
    await loadAndApplyApiKey();

    if (task == "refreshTrams") {
      ret = await _updateWidget();
    }

    return Future.value(ret);
  });
}

@pragma('vm:entry-point')
Future<void> interactiveCallback(Uri? uri) async {
  
  debugPrint('Background callback triggered - updating widget data jejeje');
  
  if (uri?.host == 'refresh') {
    debugPrint("refresh action received from widget, using workmanager to update widget data in background");

    await Workmanager().registerOneOffTask(
      DateTime.now().millisecondsSinceEpoch.toString(),
      "refreshTrams",
      constraints: Constraints(networkType: NetworkType.connected),
    );
  }
}

/// Updates widget data in background without opening the app
Future<bool> _updateWidget() async {
  String? errorMessage;
  bool flagFetch = false;
  bool res = true;

  try {

    await loadStationConfigs();
    await loadAndApplyApiKey();

    for (var stopsIndex = 0; stopsIndex < stationList.length; stopsIndex++) {
      final station = stationList[stopsIndex];
      final stationId = station['id'];

      if (stationId == null || stationId.isEmpty) {
        continue;
      }

      debugPrint('Background fetch: Fetching arrivals for ${station['name']}');

      try {
        final arrivals = await pid.getArrivalsForStop(
          stationId,
          0,
          timeLimitTillArrival,
        );

        debugPrint('Background fetch: Got ${arrivals.length} arrivals');

        // Save station name
        final stationName = station['name'] ?? 'Unknown';
        await HomeWidget.saveWidgetData('station_name_${stopsIndex + 1}', stationName);

        // Save tram arrival data
        for (var tramData = 0; tramData < numberOfWidgetRowsPerStation; tramData++) {
          final tramArrivalParsedData = arrivals.length > tramData
              ? 'Tram ${arrivals[tramData].tramNumber} in ${arrivals[tramData].arrivingInMinutes} min'
              : '';

          final widgetKey =
              '$homeWidgetStationNum${stopsIndex + 1},$homeWidgetTramData${tramData + 1}';

          if (tramArrivalParsedData == '' && flagFetch == false) {
            flagFetch = false;
            debugPrint('Background fetch: No data for tram ${tramData + 1} at station ${station['name']}');
          } else {
            flagFetch = true;
            debugPrint('Background fetch: Saving data for tram ${tramData + 1} at station ${station['name']}: $tramArrivalParsedData');
          }

          if (flagFetch) {
            await HomeWidget.saveWidgetData(widgetKey, tramArrivalParsedData);
          }
        }
      } catch (stationError) {
        errorMessage = 'Error: $stationError';
        debugPrint('Background fetch error: $errorMessage');
      }
    }

    // Save refresh timestamp
    if (flagFetch) {
      final now = DateTime.now();
      final formattedTime = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
      await HomeWidget.saveWidgetData('last_updated_time', formattedTime);
    }

    // Update widget display
    await HomeWidget.updateWidget(
      androidName: 'TramAlertWidget',
      iOSName: 'TramAlertWidget',
    );

    debugPrint('Background update complete');
  } catch (e) {
    res = false;
    debugPrint('Fatal error in background update: $e');
  }

  return res;
}

/// Main app widget that displays the arrival times for the configured stations and updates the home screen widget data.
void main(){

  WidgetsFlutterBinding.ensureInitialized();
  HomeWidget.setAppGroupId('group.cz.renato.tram_alert');

  Workmanager().initialize(
    callbackDispatcher,
  );

  HomeWidget.registerInteractivityCallback(interactiveCallback);

  runApp(MaterialApp(home: MainApp()));
}

class MainApp extends StatefulWidget {
  const MainApp({super.key});

  @override
  State<MainApp> createState() => _MainAppState();
}

class _MainAppState extends State<MainApp> {

  final TextEditingController _apiKeyController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    try {
      // Load saved station configurations
      await loadStationConfigs();
      
      // Load saved API key
      final savedApiKey = await loadApiKey();
      if (savedApiKey != null && savedApiKey.isNotEmpty) {
        _apiKeyController.text = savedApiKey;
        await loadAndApplyApiKey();
        debugPrint('API key loaded from storage');
      }
      
      // debugPrint configuration
      debugPrint('Station IDs:');
      for (final station in stationList) {
        debugPrint('  ${station['name']}: ${station['id']}');
      }
      debugPrint('Time limit till arrival: $timeLimitTillArrival minutes');
      
      if (!mounted) {
        return;
      }

      setState(() {});

    } catch (e) {
      if (!mounted) return;
      setState(() {
        // Handle error state
      });
    }
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('PID Litacka Tram Alert Configuration')),
        body: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                const Text("Enter your API key here:", style: TextStyle(fontSize: 18)),
                const SizedBox(height: 10),

                TextField(
                  obscureText: true,
                  controller: _apiKeyController,
                  onChanged: (value) async {
                    debugPrint('API key entered: $value');
                    pid.setApiKey(value);
                    await saveApiKey(value);
                  },
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'API Key',
                  ),
                ),

                const SizedBox(height: 20),

                const Text("Stops configuration:", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const Text("Enter stops names and IDs below", style: TextStyle(fontSize: 14, color: Colors.grey)),
                
                for (int i = 0; i < stationList.length; i++) ...[
                  const SizedBox(height: 20),
                  Text('Stop ${i + 1}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 10),
                  
                  TextField(
                    controller: TextEditingController(text: stationList[i]['name']),
                    onChanged: (value) {
                      debugPrint('Stop ${i + 1} name: $value');
                      stationList[i]['name'] = value;
                    },
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      labelText: 'Stop ${i + 1} Name',
                      hintText: 'e.g., Ujezd Dir: South',
                    ),
                  ),
                  
                  const SizedBox(height: 10),
                  
                  TextField(
                    controller: TextEditingController(text: stationList[i]['id']),
                    onChanged: (value) {
                      debugPrint('Stop ${i + 1} ID: $value');
                      stationList[i]['id'] = value;
                    },
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      labelText: 'Stop ${i + 1} ID',
                      hintText: 'e.g., U809Z1P',
                    ),
                  ),
                ],

                const SizedBox(height: 30),
                
                Builder(
                  builder: (BuildContext scaffoldContext) {
                    return ElevatedButton(
                      onPressed: () async {
                        await saveStationConfigs();
                        if (!mounted) return;
                        setState(() {});
                        ScaffoldMessenger.of(scaffoldContext).showSnackBar(
                          const SnackBar(content: Text('Station configurations saved!')),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                      ),
                      child: const Text('Save Configurations', style: TextStyle(fontSize: 16)),
                    );
                  },
                ),

                const SizedBox(height: 40),
                const Divider(thickness: 2),
                const SizedBox(height: 20),
                
                const Text("Current Configuration:", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey[300]!),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'API Key:',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        _apiKeyController.text.isNotEmpty 
                          ? '${_apiKeyController.text.substring(
                              0,
                              _apiKeyController.text.length > 5 ? 5 : _apiKeyController.text.length,
                            )}*****'
                          : 'Not set',
                        style: TextStyle(fontSize: 14, color: Colors.grey[700]),
                      ),
                      const SizedBox(height: 12),
                      Divider(color: Colors.grey[300], height: 1),
                      const SizedBox(height: 12),
                      for (int i = 0; i < stationList.length; i++) ...[
                        Text(
                          'Stop ${i + 1}:',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          'Name: ${stationList[i]['name']?.isNotEmpty == true ? stationList[i]['name'] : 'Not set'}',
                          style: TextStyle(fontSize: 14, color: Colors.grey[700]),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'ID: ${stationList[i]['id']?.isNotEmpty == true ? stationList[i]['id'] : 'Not set'}',
                          style: TextStyle(fontSize: 14, color: Colors.grey[700]),
                        ),
                        if (i < stationList.length - 1) ...[
                          const SizedBox(height: 12),
                          Divider(color: Colors.grey[300], height: 1),
                          const SizedBox(height: 12),
                        ],
                      ],
                    ],
                  ),
                ),
                
                const SizedBox(height: 20),

              ],
            ),
          ),
        )
      ),
    );
  }
}