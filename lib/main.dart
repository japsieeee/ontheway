import 'dart:async';
import 'dart:math' show cos, sqrt, asin, min, max;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geocoding/geocoding.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';

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

  BitmapDescriptor sourceIcon = BitmapDescriptor.defaultMarker;

  final location_package.Location _location = location_package.Location();
  late location_package.LocationData _locationData;

  double _totalDistance = 0;
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

      if (permission == LocationPermission.denied) {
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

            PolylineResult result =
                await _makePolyPointPath(updatedLocation, _destination);

            if (result.points.isNotEmpty) {
              double distance = _getDistance(result.points);
              _totalDistance = distance;
            }
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
        List<LatLng> newPolyLineCoordinates = [];
        Set<Polyline> newPolyLines = {};

        List<Location> locationB = await locationFromAddress(pointBText);
        pointBCoordinates =
            LatLng(locationB[0].latitude, locationB[0].longitude);

        List<LatLng> paths = <LatLng>[_currentLocation, pointBCoordinates];
        List<Marker> newMarks = <Marker>[];

        for (var i = 0; i < 2; i++) {
          newMarks
              .add(Marker(markerId: MarkerId("mark $i"), position: paths[i]));
        }

        PolylineResult result =
            await _makePolyPointPath(_currentLocation, pointBCoordinates);

        if (result.points.isNotEmpty) {
          double distance = _getDistance(result.points);

          for (var point in result.points) {
            newPolyLineCoordinates.add(LatLng(point.latitude, point.longitude));
          }

          newPolyLines.add(Polyline(
              polylineId: const PolylineId("polyline direction"),
              width: 6,
              points: newPolyLineCoordinates,
              color: Colors.blueAccent));

          // center camera automatically on the traveling directions
          GoogleMapController controller = await _controller.future;
          LatLngBounds bounds = _getBounds(newMarks);
          controller.animateCamera(CameraUpdate.newLatLngBounds(bounds, 50));

          _totalDistance = distance;
          polyLines = newPolyLines;
          _destination = pointBCoordinates;
        }
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

  Future<PolylineResult> _makePolyPointPath(
      LatLng loc, LatLng pointBCoordinates) async {
    // making path / poly-lines
    String mapApiKey = "${dotenv.env['GOOGLE_MAP_DIRECTIONS_API_KEY']}";

    PolylineResult result = await polylinePoints.getRouteBetweenCoordinates(
      mapApiKey,
      avoidTolls: true,
      PointLatLng(loc.latitude, loc.longitude),
      PointLatLng(pointBCoordinates.latitude, pointBCoordinates.longitude),
    );

    return result;
  }

  LatLngBounds _getBounds(List<Marker> markers) {
    var lngs = markers.map<double>((m) => m.position.longitude).toList();
    var lats = markers.map<double>((m) => m.position.latitude).toList();

    double topMost = lngs.reduce(max);
    double leftMost = lats.reduce(min);
    double rightMost = lats.reduce(max);
    double bottomMost = lngs.reduce(min);

    LatLngBounds bounds = LatLngBounds(
      northeast: LatLng(rightMost, topMost),
      southwest: LatLng(leftMost, bottomMost),
    );

    return bounds;
  }

  double _coordinateDistance(lat1, lon1, lat2, lon2) {
    var p = 0.017453292519943295;
    var c = cos;
    var a = 0.5 -
        c((lat2 - lat1) * p) / 2 +
        c(lat1 * p) * c(lat2 * p) * (1 - c((lon2 - lon1) * p)) / 2;
    return 12742 * asin(sqrt(a));
  }

  double _getDistance(polylineCoordinates) {
    double totalDistance = 0;

    for (int i = 0; i < polylineCoordinates.length - 1; i++) {
      totalDistance += _coordinateDistance(
        polylineCoordinates[i].latitude,
        polylineCoordinates[i].longitude,
        polylineCoordinates[i + 1].latitude,
        polylineCoordinates[i + 1].longitude,
      );
    }

    return totalDistance;
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
                    polylines: polyLines,
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
                                            _totalDistance = 0;
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
                        visible: _totalDistance != 0 ? true : false,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(15, 0, 15, 0),
                          child: Container(
                            color: Colors.blueAccent,
                            padding: const EdgeInsets.all(8),
                            child: Text(
                                "Total Distance: ${_totalDistance.toStringAsFixed(2)} km",
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white)),
                          ),
                        ),
                      )
                    ],
                  )),
                ],
              ),
            ),
      floatingActionButton: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Visibility(
            visible: _isLoading ? false : true,
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: FloatingActionButton(
                backgroundColor: Colors.green,
                onPressed: () {
                  _findRoute();
                },
                child: const Icon(Icons.directions),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: FloatingActionButton(
              backgroundColor:
                  _isTrafficEnabled ? Colors.grey : Colors.blueAccent,
              onPressed: () {
                toggleTrafficEnable();
              },
              child: const Icon(Icons.traffic),
            ),
          )
        ],
      ),
    );
  }
}
