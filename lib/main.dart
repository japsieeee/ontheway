import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geocoding/geocoding.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';
import 'package:http/http.dart' as http;

import 'package:location/location.dart' as location_package;

void main() async {
  await dotenv.load(fileName: '.env');
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'My Map App',
      home: MapSample(),
    );
  }
}

class MapSample extends StatefulWidget {
  const MapSample({super.key});

  @override
  State<MapSample> createState() => MapSampleState();
}

class MapSampleState extends State<MapSample> {
  bool _isLoading = false;
  bool _searchInputIsNotEmpty = false;
  bool avoidTolls = true;

  BitmapDescriptor sourceIcon = BitmapDescriptor.defaultMarker;

  final location_package.Location _location = location_package.Location();

  String _totalDistance = "";
  String _totalDuration = "";
  bool _mapIsReadyToShow = false;

  LatLng _currentLocation = const LatLng(0, 0);
  LatLng _destination = const LatLng(0, 0);

  bool _isTrafficEnabled = false;

  Set<Polyline> polyLines = {};
  PolylinePoints polylinePoints = PolylinePoints();

  final destinationLocationInputController = TextEditingController();

  final Completer<GoogleMapController> _controller =
      Completer<GoogleMapController>();

  // default camera position in metro manila
  final CameraPosition _initialCameraPosition =
      const CameraPosition(target: LatLng(14.599512, 120.984222), zoom: 15);

  @override
  void initState() {
    // TODO: implement initState
    super.initState();

    _getPermissions();
    setCustomMarkerIcon();
  }

  void toggleTrafficEnable() {
    setState(() {
      _isTrafficEnabled = !_isTrafficEnabled;
    });
  }

  void _getPermissions() async {
    try {
      // check if location service is enabled
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();

      LocationPermission permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.denied || !serviceEnabled) {
        LocationPermission nextPermission =
            await Geolocator.requestPermission();

        if (nextPermission == LocationPermission.denied ||
            nextPermission == LocationPermission.deniedForever ||
            nextPermission == LocationPermission.unableToDetermine) {
          SystemNavigator.pop();
          // denied permission, need to disable buttons or exit the app
          throw Exception("Location Access Permission Denied");
        }
      }

      await Future.delayed(const Duration(seconds: 1));

      setState(() {
        _mapIsReadyToShow = true;
      });

      GoogleMapController controller = await _controller.future;

      _location.onLocationChanged
          .listen((location_package.LocationData locationData) async {
        LatLng updatedLocation =
            LatLng(locationData.latitude!, locationData.longitude!);

        if ((updatedLocation.latitude != _currentLocation.latitude) ||
            (updatedLocation.longitude != _currentLocation.longitude)) {
          if (_destination.latitude != 0 && _destination.longitude != 0) {
            // animate camera
            controller.animateCamera(CameraUpdate.newCameraPosition(
                CameraPosition(target: updatedLocation, zoom: 19)));
          }

          setState(() {
            _currentLocation = updatedLocation;
          });
        }
      });
    } catch (e) {
      // print(e);
    }
  }

  void setCustomMarkerIcon() {
    BitmapDescriptor.fromAssetImage(
            ImageConfiguration.empty, "assets/icon/currentlocicon.bmp")
        .then((icon) {
      sourceIcon = icon;
    });
  }

  void _findRoute() async {
    try {
      setState(() {
        _isLoading = true;
      });

      bool gpsEnabled = await Geolocator.isLocationServiceEnabled();

      if (!gpsEnabled) {
        LocationPermission permission = await Geolocator.requestPermission();

        if (permission == LocationPermission.denied) return;
      }

      if (_currentLocation.latitude == 0 && _currentLocation.longitude == 0) {
        return _getPermissions();
      }

      late LatLng pointBCoordinates;

      String pointBText = destinationLocationInputController.text;

      if (pointBText.isNotEmpty) {
        Set<Polyline> newPolyLines = {};

        List<Location> locationB = await locationFromAddress(pointBText);
        pointBCoordinates =
            LatLng(locationB[0].latitude, locationB[0].longitude);

        List<LatLng> paths = <LatLng>[_currentLocation, pointBCoordinates];
        List<Marker> newMarks = <Marker>[];

        final List<LatLng> routePoints =
            await fetchDirections(pointBCoordinates);

        for (var i = 0; i < 2; i++) {
          newMarks
              .add(Marker(markerId: MarkerId("mark $i"), position: paths[i]));
        }

        newPolyLines.add(Polyline(
            polylineId: const PolylineId("polyline direction"),
            width: 6,
            points: routePoints,
            color: Colors.blueAccent));

        polyLines = newPolyLines;
        _destination = pointBCoordinates;
      }
    } catch (e) {
      showDialog(
          context: context,
          builder: (context) {
            return const AlertDialog(
                title: Text("Location Not Found"),
                content: Text(
                    "TIP: Try searching more familiar location such as landmarks and etc."));
          });
      // print("ERROR!!!!!!!!!!!!!!!!!!!!!!!!!: $e");
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<List<LatLng>> fetchDirections(LatLng dest) async {
    String apiKey = "${dotenv.env['GOOGLE_MAP_DIRECTIONS_API_KEY']}";
    final origin =
        "${_currentLocation.latitude}, ${_currentLocation.longitude}";
    final destination = "${dest.latitude}, ${dest.longitude}";

    String uri =
        "https://maps.googleapis.com/maps/api/directions/json?avoid=${avoidTolls ? "tolls" : ""}&origin=$origin&destination=$destination&key=$apiKey";

    final response = await http.get(Uri.parse(uri));

    if (response.statusCode == 200) {
      final decoded = json.decode(response.body);

      final routes = decoded['routes'][0]['overview_polyline']['points'];
      final distance = decoded['routes'][0]['legs'][0]['distance']['text'];
      final duration = decoded['routes'][0]['legs'][0]['duration']['text'];
      var nelat = decoded['routes'][0]['bounds']['northeast']['lat'];
      var nelng = decoded['routes'][0]['bounds']['northeast']['lng'];

      var swlat = decoded['routes'][0]['bounds']['southwest']['lat'];
      var swlng = decoded['routes'][0]['bounds']['southwest']['lng'];

      // center camera automatically on the traveling directions
      LatLngBounds bounds = LatLngBounds(
          southwest: LatLng(swlat, swlng), northeast: LatLng(nelat, nelng));

      GoogleMapController controller = await _controller.future;
      controller.animateCamera(CameraUpdate.newLatLngBounds(bounds, 50));

      final List<LatLng> points = PolylinePoints()
          .decodePolyline(routes)
          .map((e) => LatLng(e.latitude, e.longitude))
          .toList();

      _totalDistance = distance;
      _totalDuration = duration;
      return points;
    } else {
      throw Exception('Failed to load directions');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: !_mapIsReadyToShow
          ? SafeArea(
              child: Center(
                child: LoadingAnimationWidget.threeArchedCircle(
                    color: Colors.blueAccent, size: 20.0),
              ),
            )
          : SafeArea(
              child: Stack(
                children: [
                  GoogleMap(
                    polylines: polyLines,
                    myLocationEnabled: false,
                    myLocationButtonEnabled: false,
                    padding: const EdgeInsets.fromLTRB(0, 120, 0, 10),
                    markers: {
                      Marker(
                          markerId: const MarkerId("currentLocation"),
                          icon: sourceIcon,
                          position: _currentLocation),
                      Marker(
                          markerId: const MarkerId("destination"),
                          position: _destination)
                    },
                    initialCameraPosition: _initialCameraPosition,
                    zoomControlsEnabled: false,
                    trafficEnabled: _isTrafficEnabled,
                    onMapCreated: (GoogleMapController controller) async {
                      Position pos = await Geolocator.getCurrentPosition();

                      LatLng currentLoc = LatLng(pos.latitude, pos.longitude);

                      controller.animateCamera(CameraUpdate.newCameraPosition(
                          CameraPosition(target: currentLoc, zoom: 19)));
                      String mapStyle = await DefaultAssetBundle.of(context)
                          .loadString("assets/map_style.json");
                      controller.setMapStyle(mapStyle);

                      setState(() {
                        _currentLocation = currentLoc;
                      });

                      _controller.complete(controller);
                    },
                  ),
                  Positioned(
                      child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(15),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(0, 10, 0, 0),
                          child: Stack(
                            children: [
                              Container(
                                decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(5)),
                                child: TextField(
                                  controller:
                                      destinationLocationInputController,
                                  onChanged: (text) {
                                    if (text.isNotEmpty) {
                                      setState(() {
                                        _searchInputIsNotEmpty = true;
                                      });
                                    } else {
                                      setState(() {
                                        _searchInputIsNotEmpty = false;
                                      });
                                    }
                                  },
                                  decoration: const InputDecoration(
                                      hintText: 'Search your destination',
                                      contentPadding:
                                          EdgeInsets.fromLTRB(15, 15, 50, 15),
                                      border: OutlineInputBorder(
                                          borderSide: BorderSide.none)),
                                ),
                              ),
                              Positioned(
                                  top: 2,
                                  right: 2,
                                  child: Visibility(
                                    visible:
                                        _searchInputIsNotEmpty ? true : false,
                                    child: IconButton(
                                        onPressed: () async {
                                          destinationLocationInputController
                                              .clear();

                                          GoogleMapController controller =
                                              await _controller.future;

                                          controller.animateCamera(
                                              CameraUpdate.newCameraPosition(
                                                  CameraPosition(
                                                      target: _currentLocation,
                                                      zoom: 16)));

                                          setState(() {
                                            _destination = const LatLng(0, 0);
                                            _searchInputIsNotEmpty = false;
                                            _totalDistance = "";
                                            _totalDuration = "";
                                            polyLines = {};
                                          });
                                        },
                                        icon: const Icon(
                                          Icons.close,
                                          size: 24,
                                          color: Colors.grey,
                                        )),
                                  )),
                            ],
                          ),
                        ),
                      ),
                      Visibility(
                        visible: _totalDistance.isNotEmpty ? true : false,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(15, 0, 15, 0),
                          child: Container(
                            color: Colors.blueAccent,
                            padding: const EdgeInsets.all(8),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text("Distance: $_totalDistance",
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white)),
                                Text("Duration: $_totalDuration",
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white)),
                              ],
                            ),
                          ),
                        ),
                      )
                    ],
                  )),
                ],
              ),
            ),
      floatingActionButton: Container(
        // color: Colors.red,
        padding: const EdgeInsets.fromLTRB(30, 0, 0, 0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Column(
              mainAxisAlignment: MainAxisAlignment.end,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: SizedBox(
                    height: 50,
                    width: 50,
                    child: FloatingActionButton(
                      backgroundColor: Colors.amber,
                      onPressed: () {
                        if (_totalDistance.isNotEmpty) {
                          _findRoute();
                        }

                        setState(() {
                          avoidTolls = !avoidTolls;
                        });
                      },
                      child: Icon(avoidTolls ? Icons.motorcycle : Icons.car_repair),
                    ),
                  ),
                ),
                SizedBox(
                  height: 50,
                  width: 50,
                  child: FloatingActionButton(
                    backgroundColor:
                        _isTrafficEnabled ? Colors.grey : Colors.blueAccent,
                    onPressed: () {
                      toggleTrafficEnable();
                    },
                    child: const Icon(Icons.traffic),
                  ),
                ),
              ],
            ),
            Visibility(
              visible: _isLoading ? false : true,
              child: SizedBox(
                width: 70,
                height: 45,
                child: FloatingActionButton(
                  shape: BeveledRectangleBorder(borderRadius: BorderRadius.circular(2)),
                  backgroundColor: Colors.green,
                  onPressed: () {
                    _findRoute();
                  },
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      Icon(Icons.directions),
                      Text("Go", style: TextStyle(fontSize: 14)),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
