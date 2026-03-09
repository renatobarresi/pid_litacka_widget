
import 'package:flutter/foundation.dart';  
import 'package:http/http.dart' as http;
import 'dart:convert';

const numberOfStopsToShow = 3; // Show next 3 stops for each station
const numberOfWidgetRowsPerStation = 5; // Rows shown per station in Android widget

// Todo: Read API from a config file
String apiKey = "";

const stopsUrl = 'https://data.pid.cz/stops/json/stops.json';
const apiUrl = "https://api.golemio.cz/v2";
const endpointName = "pid/departureboards";

/// This class represents the metadata for a tram arrival.
class ArrivalMetadata
{
  final String arrivingInMinutes;
  final String tramNumber;

  ArrivalMetadata({
    required this.arrivingInMinutes,
    required this.tramNumber,
  });
}

/// This class is responsible for fetching and parsing arrival data from the PID API.
class LitackaEndpointParser {

  bool apiKey = false;
  Map<String, String> apiHeader = {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
    'X-Access-Token': ""
  };

  void setApiKey(String newApiKey) {
    apiKey = true;
    apiHeader['X-Access-Token'] = newApiKey;
  }

  Future<List<ArrivalMetadata>> getArrivalsForStop(String stopID, int minutesBefore, int minutesAfter) async
  {
    final List<ArrivalMetadata> arrivals = [];
    int retries = 3;
    int delayMs = 1000;
    
    if (apiKey == false) {
      debugPrint('API key is not set. Please set the API key before fetching arrivals.');
      return [];
    }

    while (retries > 0) {
      debugPrint("Fetching arrivals for stop $stopID (attempt ${4 - retries}/3)");
      try {
        // Fetch departure board data
        final url = Uri.parse('$apiUrl/$endpointName').replace(
          queryParameters: {
            'ids': stopID,
            'limit': numberOfWidgetRowsPerStation.toString(),
            'minutesBefore': minutesBefore.toString(),
            'minutesAfter': minutesAfter.toString(),
            'mode': 'arrivals',
          },
        );
        
        final resp = await http.get(url, headers: apiHeader).timeout(const Duration(seconds: 15));
        
        if (resp.statusCode != 200) {
          debugPrint('getArrivalsForStop HTTP ${resp.statusCode}');
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
          
          debugPrint("Tram $tramNumber in $minutesUntilArrival minutes at stop $stopID");
          arrivals.add(ArrivalMetadata(
            arrivingInMinutes: minutesUntilArrival,
            tramNumber: tramNumber,
          ));
        }
        
        return arrivals;

      } catch (e) {

        retries--;
        if (retries > 0) {
          debugPrint('Error fetching arrivals for stop $stopID (retry $retries): $e');
          await Future.delayed(Duration(milliseconds: delayMs));
          delayMs *= 2; // Exponential backoff
        } else {
          debugPrint('Error fetching arrivals for stop $stopID (final): $e');
          return [];
        }

      }
    }
    
    return arrivals;
  }
}