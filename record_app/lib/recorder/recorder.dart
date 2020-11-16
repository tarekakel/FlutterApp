/*
 * Copyright 2018, 2019, 2020 Dooboolab.
 *
 * This file is part of Flutter-Sound.
 *
 * Flutter-Sound is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License version 3 (LGPL-V3), as published by
 * the Free Software Foundation.
 *
 * Flutter-Sound is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with Flutter-Sound.  If not, see <https://www.gnu.org/licenses/>.
 */

import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data' show Uint8List;

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:flutter_sound/flutter_sound.dart';
import 'package:permission_handler/permission_handler.dart';

// If someone update the following comment, please update also the Examples/README.md file and the code inside Examples/lib/demo/main.dart
/*
 * This is a Demo of what it is possible to do with Flutter Sound.
 * The code of this Demo app is not so simple and unfortunately not very clean :-( .
 *
 * The biggest interest of this Demo is that it shows most of the features of Flutter Sound :
 *
 * - Plays from various media with various codecs
 * - Records to various media with various codecs
 * - Pause and Resume control from recording or playback
 * - Shows how to use a Stream for getting the playback (or recoding) events
 * - Shows how to specify a callback function when a playback is terminated,
 * - Shows how to record to a Stream or playback from a stream
 * - Can show controls on the iOS or Android lock-screen
 * - ...
 *
 * This Demo does not make use of the Flutter Sound UI Widgets.
 *
 * It would be really great if someone rewrite this demo soon
 *
 */

const int SAMPLE_RATE = 8000;
const int BLOCK_SIZE = 4096;

enum Media {
  file,
  buffer,
  asset,
  stream,
  remoteExampleFile,
}
enum AudioState {
  isPlaying,
  isPaused,
  isStopped,
  isRecording,
  isRecordingPaused,
}

final exampleAudioFilePath =
    "https://file-examples-com.github.io/uploads/2017/11/file_example_MP3_700KB.mp3";
final albumArtPath =
    "https://file-examples-com.github.io/uploads/2017/10/file_example_PNG_500kB.png";

class Demo extends StatefulWidget {
  @override
  _MyAppState createState() => new _MyAppState();
}

class _MyAppState extends State<Demo> {
  bool _isRecording = false;
  List<String> _path = [
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
  ];
  StreamSubscription _recorderSubscription;
  StreamSubscription _playerSubscription;
  StreamSubscription _recordingDataSubscription;

  FlutterSoundPlayer playerModule = FlutterSoundPlayer();
  FlutterSoundRecorder recorderModule = FlutterSoundRecorder();

  String _recorderTxt = '00:00:00';
  String _playerTxt = '00:00:00';
  double _dbLevel;

  double sliderCurrentPosition = 0.0;
  double maxDuration = 1.0;
  Media _media = Media.file;
  Codec _codec = Codec.aacADTS;
  String filePath;
  bool _encoderSupported = true; // Optimist
  bool _decoderSupported = true; // Optimist

  // Whether the user wants to use the audio player features
  bool _isAudioPlayer = false;

  double _duration = null;
  StreamController<Food> recordingDataController;
  IOSink sink;

  Future<void> _initializeExample(bool withUI) async {
    await playerModule.closeAudioSession();
    _isAudioPlayer = withUI;
    await playerModule.openAudioSession(
        withUI: withUI,
        focus: AudioFocus.requestFocusAndStopOthers,
        category: SessionCategory.playAndRecord,
        mode: SessionMode.modeDefault,
        device: AudioDevice.speaker);
    await playerModule.setSubscriptionDuration(Duration(milliseconds: 10));
    await recorderModule.setSubscriptionDuration(Duration(milliseconds: 10));
    initializeDateFormatting();
    await setCodec(_codec);
  }

  Future<void> init() async {
    await recorderModule.openAudioSession(
        focus: AudioFocus.requestFocusAndStopOthers,
        category: SessionCategory.playAndRecord,
        mode: SessionMode.modeDefault,
        device: AudioDevice.speaker);
    await _initializeExample(false);

    if (Platform.isAndroid) {
      await copyAssets();
    }
  }

  Future<void> copyAssets() async {
    Uint8List dataBuffer =
        (await rootBundle.load("assets/canardo.png")).buffer.asUint8List();
    String path = await playerModule.getResourcePath() + "/assets";
    if (!await Directory(path).exists()) {
      await Directory(path).create(recursive: true);
    }
    await File(path + '/canardo.png').writeAsBytes(dataBuffer);
  }

  @override
  void initState() {
    super.initState();
    init();
  }

  void cancelRecorderSubscriptions() {
    if (_recorderSubscription != null) {
      _recorderSubscription.cancel();
      _recorderSubscription = null;
    }
  }

  void cancelPlayerSubscriptions() {
    if (_playerSubscription != null) {
      _playerSubscription.cancel();
      _playerSubscription = null;
    }
  }

  void cancelRecordingDataSubscription() {
    if (_recordingDataSubscription != null) {
      _recordingDataSubscription.cancel();
      _recordingDataSubscription = null;
    }
    recordingDataController = null;
    if (sink != null) {
      sink.close();
      sink = null;
    }
  }

  @override
  void dispose() {
    super.dispose();
    cancelPlayerSubscriptions();
    cancelRecorderSubscriptions();
    cancelRecordingDataSubscription();
    releaseFlauto();
  }

  Future<void> releaseFlauto() async {
    try {
      await playerModule.closeAudioSession();
      await recorderModule.closeAudioSession();
    } catch (e) {
      print('Released unsuccessful');
      print(e);
    }
  }

  void startRecorder() async {
    try {
      // Request Microphone permission if needed
      PermissionStatus status = await Permission.microphone.request();
      if (status != PermissionStatus.granted) {
        throw RecordingPermissionException("Microphone permission not granted");
      }

      Directory tempDir = await getTemporaryDirectory();
      String path = '${tempDir.path}/flutter_sound${ext[_codec.index]}';
      filePath = path;
      print(filePath);
      if (_media == Media.stream) {
        assert(_codec == Codec.pcm16);
        File outputFile = File(path);
        if (outputFile.existsSync()) await outputFile.delete();
        sink = outputFile.openWrite();
        recordingDataController = StreamController<Food>();
        _recordingDataSubscription =
            recordingDataController.stream.listen((Food buffer) {
          if (buffer is FoodData) sink.add(buffer.data);
        });
        await recorderModule.startRecorder(
          toStream: recordingDataController.sink,
          codec: _codec,
          numChannels: 1,
          sampleRate: SAMPLE_RATE,
        );
      } else {
        await recorderModule.startRecorder(
          toFile: path,
          codec: _codec,
          bitRate: 8000,
          numChannels: 1,
          sampleRate: SAMPLE_RATE,
        );
      }
      print('startRecorder');

      _recorderSubscription = recorderModule.onProgress.listen((e) {
        if (e != null && e.duration != null) {
          DateTime date = new DateTime.fromMillisecondsSinceEpoch(
              e.duration.inMilliseconds,
              isUtc: true);
          String txt = DateFormat('mm:ss:SS', 'en_GB').format(date);

          this.setState(() {
            _recorderTxt = txt.substring(0, 8);
            _dbLevel = e.decibels;
          });
        }
      });

      this.setState(() {
        this._isRecording = true;
        this._path[_codec.index] = path;
      });
    } catch (err) {
      print('startRecorder error: $err');
      setState(() {
        stopRecorder();
        this._isRecording = false;
        cancelRecordingDataSubscription();
        cancelRecorderSubscriptions();
      });
    }
  }

  Future<void> getDuration() async {
    switch (_media) {
      case Media.file:
      case Media.buffer:
        Duration d =
            await flutterSoundHelper.duration(this._path[_codec.index]);
        _duration = d != null ? d.inMilliseconds / 1000.0 : null;
        break;
      case Media.asset:
        _duration = null;
        break;
      case Media.remoteExampleFile:
        _duration = null;
        break;
      default:
    }
    setState(() {});
  }

  void stopRecorder() async {
    try {
      await recorderModule.stopRecorder();
      print('stopRecorder');
      cancelRecorderSubscriptions();
      cancelRecordingDataSubscription();
      getDuration();
    } catch (err) {
      print('stopRecorder error: $err');
    }
    this.setState(() {
      this._isRecording = false;
    });
  }

  Future<bool> fileExists(String path) async {
    return await File(path).exists();
  }

  // In this simple example, we just load a file in memory.This is stupid but just for demonstration  of startPlayerFromBuffer()
  Future<Uint8List> makeBuffer(String path) async {
    try {
      if (!await fileExists(path)) return null;
      File file = File(path);
      file.openRead();
      var contents = await file.readAsBytes();
      print('The file is ${contents.length} bytes long.');
      return contents;
    } catch (e) {
      print(e);
      return null;
    }
  }

  List<String> assetSample = [
    'assets/samples/sample.aac',
    'assets/samples/sample.aac',
    'assets/samples/sample.opus',
    'assets/samples/sample_opus.caf',
    'assets/samples/sample.mp3',
    'assets/samples/sample.ogg',
    'assets/samples/sample.pcm',
    'assets/samples/sample.wav',
    'assets/samples/sample.aiff',
    'assets/samples/sample_pcm.caf',
    'assets/samples/sample.flac',
    'assets/samples/sample.mp4',
    'assets/samples/sample.amr', // amrNB
    'assets/samples/sample.amr', // amrWB
  ];

  void _addListeners() {
    cancelPlayerSubscriptions();
    _playerSubscription = playerModule.onProgress.listen((e) {
      if (e != null) {
        maxDuration = e.duration.inMilliseconds.toDouble();
        if (maxDuration <= 0) maxDuration = 0.0;

        sliderCurrentPosition =
            min(e.position.inMilliseconds.toDouble(), maxDuration);
        if (sliderCurrentPosition < 0.0) {
          sliderCurrentPosition = 0.0;
        }

        DateTime date = new DateTime.fromMillisecondsSinceEpoch(
            e.position.inMilliseconds,
            isUtc: true);
        String txt = DateFormat('mm:ss:SS', 'en_GB').format(date);
        this.setState(() {
          this._playerTxt = txt.substring(0, 8);
        });
      }
    });
  }

  Future<Uint8List> _readFileByte(String filePath) async {
    Uri myUri = Uri.parse(filePath);
    File audioFile = new File.fromUri(myUri);
    Uint8List bytes;
    await audioFile.readAsBytes().then((value) {
      bytes = Uint8List.fromList(value);
      print('reading of bytes is completed');
    });
    return bytes;
  }

  Future<void> feedHim(String path) async {
    Uint8List data = await _readFileByte(path);
    return playerModule.feedFromStream(data);
  }

  Future<void> startPlayer() async {
    try {
      Uint8List dataBuffer;
      String audioFilePath;
      Codec codec = _codec;
      if (_media == Media.asset) {
        dataBuffer = (await rootBundle.load(assetSample[codec.index]))
            .buffer
            .asUint8List();
      } else if (_media == Media.file || _media == Media.stream) {
        // Do we want to play from buffer or from file ?
        if (await fileExists(_path[codec.index]))
          audioFilePath = this._path[codec.index];
        print(audioFilePath);
      } else if (_media == Media.buffer) {
        // Do we want to play from buffer or from file ?
        if (await fileExists(_path[codec.index])) {
          dataBuffer = await makeBuffer(this._path[codec.index]);
          if (dataBuffer == null) {
            throw Exception('Unable to create the buffer');
          }
        }
      } else if (_media == Media.remoteExampleFile) {
        // We have to play an example audio file loaded via a URL
        audioFilePath = exampleAudioFilePath;
      }

      // Check whether the user wants to use the audio player features
      if (_isAudioPlayer) {
        String albumArtUrl;
        String albumArtAsset;
        String albumArtFile;
        if (_media == Media.remoteExampleFile)
          albumArtUrl = albumArtPath;
        else {
          albumArtFile =
              await playerModule.getResourcePath() + "/assets/canardo.png";
          print(albumArtFile);
        }

        final track = Track(
          trackPath: audioFilePath,
          codec: _codec,
          dataBuffer: dataBuffer,
          trackTitle: "This is a record",
          trackAuthor: "from flutter_sound",
          albumArtUrl: albumArtUrl,
          albumArtAsset: albumArtAsset,
          albumArtFile: albumArtFile,
        );
        await playerModule.startPlayerFromTrack(track,
            defaultPauseResume: false,
            removeUIWhenStopped: true, whenFinished: () {
          print('I hope you enjoyed listening to this song');
          setState(() {});
        }, onSkipBackward: () {
          print('Skip backward');
          stopPlayer();
          startPlayer();
        }, onSkipForward: () {
          print('Skip forward');
          stopPlayer();
          startPlayer();
        }, onPaused: (bool b) {
          if (b)
            playerModule.pausePlayer();
          else
            playerModule.resumePlayer();
        });
      } else if (_media == Media.stream) {
        await playerModule.startPlayerFromStream(
          codec: _codec,
          numChannels: 1,
          sampleRate: SAMPLE_RATE,
        );
        _addListeners();
        setState(() {});
        await feedHim(audioFilePath);
        //await finishPlayer();
        await stopPlayer();
        return;
      } else {
        if (audioFilePath != null) {
          await playerModule.startPlayer(
              fromURI: audioFilePath,
              codec: codec,
              sampleRate: SAMPLE_RATE,
              whenFinished: () {
                print('Play finished');
                setState(() {});
              });
        } else if (dataBuffer != null) {
          if (codec == Codec.pcm16) {
            dataBuffer = await flutterSoundHelper.pcmToWaveBuffer(
              inputBuffer: dataBuffer,
              numChannels: 1,
              sampleRate: (_codec == Codec.pcm16 && _media == Media.asset)
                  ? 48000
                  : SAMPLE_RATE,
            );
            codec = Codec.pcm16WAV;
          }
          await playerModule.startPlayer(
              fromDataBuffer: dataBuffer,
              sampleRate: SAMPLE_RATE,
              codec: codec,
              whenFinished: () {
                print('Play finished');
                setState(() {});
              });
        }
      }
      _addListeners();
      setState(() {});
      print('<--- startPlayer');
    } catch (err) {
      print('error: $err');
    }
  }

  Future<void> stopPlayer() async {
    try {
      await playerModule.stopPlayer();
      print('stopPlayer');
      if (_playerSubscription != null) {
        _playerSubscription.cancel();
        _playerSubscription = null;
      }
      sliderCurrentPosition = 0.0;
    } catch (err) {
      print('error: $err');
    }
    this.setState(() {});
  }

  void pauseResumePlayer() async {
    if (playerModule.isPlaying) {
      await playerModule.pausePlayer();
    } else {
      await playerModule.resumePlayer();
    }
    setState(() {});
  }

  void pauseResumeRecorder() async {
    if (recorderModule.isPaused) {
      await recorderModule.resumeRecorder();
    } else {
      await recorderModule.pauseRecorder();
      assert(recorderModule.isPaused);
    }
    setState(() {});
  }

  void seekToPlayer(int milliSecs) async {
    print('-->seekToPlayer');
    if (playerModule.isPlaying)
      await playerModule.seekToPlayer(Duration(milliseconds: milliSecs));
    print('<--seekToPlayer');
  }

  Widget makeDropdowns(BuildContext context) {
    final mediaDropdown = Row(
      mainAxisAlignment: MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(right: 16.0),
          child: Text('Media:'),
        ),
        DropdownButton<Media>(
          value: _media,
          onChanged: (newMedia) {
            if (newMedia == Media.remoteExampleFile)
              _codec = Codec
                  .mp3; // Actually this is the only example we use in this example
            _media = newMedia;
            getDuration();
            setState(() {});
          },
          items: <DropdownMenuItem<Media>>[
            DropdownMenuItem<Media>(
              value: Media.file,
              child: Text('File'),
            ),
            DropdownMenuItem<Media>(
              value: Media.buffer,
              child: Text('Buffer'),
            ),
            DropdownMenuItem<Media>(
              value: Media.asset,
              child: Text('Asset'),
            ),
            DropdownMenuItem<Media>(
              value: Media.remoteExampleFile,
              child: Text('Remote Example File'),
            ),
            DropdownMenuItem<Media>(
              value: Media.stream,
              child: Text('Dart Stream'),
            ),
          ],
        ),
      ],
    );

    final codecDropdown = Row(
      mainAxisAlignment: MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(right: 16.0),
          child: Text('Codec:'),
        ),
        DropdownButton<Codec>(
          value: _codec,
          onChanged: (newCodec) {
            setCodec(newCodec);
            _codec = newCodec;
            getDuration();
            setState(() {});
          },
          items: <DropdownMenuItem<Codec>>[
            DropdownMenuItem<Codec>(
              value: Codec.aacADTS,
              child: Text('AAC/ADTS'),
            ),
            DropdownMenuItem<Codec>(
              value: Codec.opusOGG,
              child: Text('Opus/OGG'),
            ),
            DropdownMenuItem<Codec>(
              value: Codec.opusCAF,
              child: Text('Opus/CAF'),
            ),
            DropdownMenuItem<Codec>(
              value: Codec.mp3,
              child: Text('MP3'),
            ),
            DropdownMenuItem<Codec>(
              value: Codec.vorbisOGG,
              child: Text('Vorbis/OGG'),
            ),
            DropdownMenuItem<Codec>(
              value: Codec.pcm16,
              child: Text('PCM16'),
            ),
            DropdownMenuItem<Codec>(
              value: Codec.pcm16WAV,
              child: Text('PCM16/WAV'),
            ),
            DropdownMenuItem<Codec>(
              value: Codec.pcm16AIFF,
              child: Text('PCM16/AIFF'),
            ),
            DropdownMenuItem<Codec>(
              value: Codec.pcm16CAF,
              child: Text('PCM16/CAF'),
            ),
            DropdownMenuItem<Codec>(
              value: Codec.flac,
              child: Text('FLAC'),
            ),
            DropdownMenuItem<Codec>(
              value: Codec.aacMP4,
              child: Text('AAC/MP4'),
            ),
            DropdownMenuItem<Codec>(
              value: Codec.amrNB,
              child: Text('AMR-NB'),
            ),
            DropdownMenuItem<Codec>(
              value: Codec.amrWB,
              child: Text('AMR-WB'),
            ),
          ],
        ),
      ],
    );

    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(bottom: 16.0),
            child: mediaDropdown,
          ),
          codecDropdown,
        ],
      ),
    );
  }

  void Function() onPauseResumePlayerPressed() {
    if (playerModule == null) return null;
    if (playerModule.isPaused || playerModule.isPlaying) {
      return pauseResumePlayer;
    }
    return null;
  }

  void Function() onPauseResumeRecorderPressed() {
    if (recorderModule == null) return null;
    if (recorderModule.isPaused || recorderModule.isRecording) {
      return pauseResumeRecorder;
    }
    return null;
  }

  void Function() onStopPlayerPressed() {
    if (playerModule == null) return null;
    return (playerModule.isPlaying || playerModule.isPaused)
        ? stopPlayer
        : null;
  }

  void Function() onStartPlayerPressed() {
    if (playerModule == null) return null;
    if (_media == Media.file ||
        _media == Media.stream ||
        _media == Media.buffer) // A file must be already recorded to play it
    {
      if (_path[_codec.index] == null) return null;
    }
    if (_media == Media.remoteExampleFile &&
        _codec != Codec.mp3) // in this example we use just a remote mp3 file
      return null;

    if (_media == Media.stream && _codec != Codec.pcm16) return null;

    if (_media == Media.stream && _isAudioPlayer) return null;

    // Disable the button if the selected codec is not supported
    if (!(_decoderSupported || _codec == Codec.pcm16)) return null;

    return (playerModule.isStopped) ? startPlayer : null;
  }

  void startStopRecorder() {
    if (recorderModule.isRecording || recorderModule.isPaused)
      stopRecorder();
    else
      startRecorder();
  }

  void Function() onStartRecorderPressed() {
    // Disable the button if the selected codec is not supported
    if (recorderModule == null || !_encoderSupported) return null;
    if (_media == Media.stream && _codec != Codec.pcm16) return null;
    return startStopRecorder;
  }

  AssetImage recorderAssetImage() {
    if (onStartRecorderPressed() == null)
      return AssetImage('lib/res/icons/ic_mic_disabled.png');
    return (recorderModule.isStopped)
        ? AssetImage('lib/res/icons/ic_mic.png')
        : AssetImage('lib/res/icons/ic_stop.png');
  }

  void setCodec(Codec codec) async {
    _encoderSupported = await recorderModule.isEncoderSupported(codec);
    _decoderSupported = await playerModule.isDecoderSupported(codec);

    setState(() {
      _codec = codec;
    });
  }

  void Function(bool) audioPlayerSwitchChanged() {
    if ((!playerModule.isStopped) || (!recorderModule.isStopped)) return null;
    return ((newVal) async {
      try {
        await _initializeExample(newVal);
        setState(() {});
      } catch (err) {
        print(err);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final recorderProgressIndicator = _isRecording
        ? LinearProgressIndicator(
            value: 100.0 / 160.0 * (this._dbLevel ?? 1) / 100,
            valueColor: AlwaysStoppedAnimation<Color>(Colors.green),
            backgroundColor: Colors.red,
          )
        : Container();
    final playerControls = Row(
      children: <Widget>[
        Container(
          width: 56.0,
          height: 56.0,
          child: ClipOval(
            child: FlatButton(
              onPressed: onStartPlayerPressed(),
              padding: EdgeInsets.all(8.0),
              child: Image(
                image: AssetImage(onStartPlayerPressed() != null
                    ? 'lib/res/icons/ic_play.png'
                    : 'lib/res/icons/ic_play_disabled.png'),
              ),
            ),
          ),
        ),
        Container(
          width: 56.0,
          height: 56.0,
          child: ClipOval(
            child: FlatButton(
              onPressed: onPauseResumePlayerPressed(),
              padding: EdgeInsets.all(8.0),
              child: Image(
                width: 36.0,
                height: 36.0,
                image: AssetImage(onPauseResumePlayerPressed() != null
                    ? 'lib/res/icons/ic_pause.png'
                    : 'lib/res/icons/ic_pause_disabled.png'),
              ),
            ),
          ),
        ),
        Container(
          width: 56.0,
          height: 56.0,
          child: ClipOval(
            child: FlatButton(
              onPressed: onStopPlayerPressed(),
              padding: EdgeInsets.all(8.0),
              child: Image(
                width: 28.0,
                height: 28.0,
                image: AssetImage(onStopPlayerPressed() != null
                    ? 'lib/res/icons/ic_stop.png'
                    : 'lib/res/icons/ic_stop_disabled.png'),
              ),
            ),
          ),
        ),
      ],
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
    );
    final playerSlider = Container(
        height: 56.0,
        child: Slider(
            value: min(sliderCurrentPosition, maxDuration),
            min: 0.0,
            max: maxDuration,
            onChanged: (double value) async {
              await seekToPlayer(value.toInt());
            },
            divisions: maxDuration == 0.0 ? 1 : maxDuration.toInt()));

    final dropdowns = makeDropdowns(context);
    final trackSwitch = Padding(
      padding: const EdgeInsets.all(8.0),
      child: Row(children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(right: 4),
          child: Text('Track Player:'),
        ),
        Switch(
          value: _isAudioPlayer,
          onChanged: audioPlayerSwitchChanged(),
        ),
        Padding(
          padding: const EdgeInsets.only(right: 4.0),
        )
      ]),
    );

    Widget recorderSection = Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Container(
            margin: EdgeInsets.only(top: 12.0, bottom: 16.0),
            child: Text(
              this._recorderTxt,
              style: TextStyle(
                fontSize: 35.0,
                color: Colors.black,
              ),
            ),
          ),
          _isRecording
              ? LinearProgressIndicator(
                  value: 100.0 / 160.0 * (this._dbLevel ?? 1) / 100,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.green),
                  backgroundColor: Colors.red)
              : Container(),
          Row(
            children: <Widget>[
              Container(
                width: 56.0,
                height: 50.0,
                child: ClipOval(
                  child: FlatButton(
                    onPressed: onStartRecorderPressed(),
                    padding: EdgeInsets.all(8.0),
                    child: Image(
                      image: recorderAssetImage(),
                    ),
                  ),
                ),
              ),
              Container(
                width: 56.0,
                height: 50.0,
                child: ClipOval(
                  child: FlatButton(
                    onPressed: onPauseResumeRecorderPressed(),
                    disabledColor: Colors.white,
                    padding: EdgeInsets.all(8.0),
                    child: Image(
                      width: 36.0,
                      height: 36.0,
                      image: AssetImage(onPauseResumeRecorderPressed() != null
                          ? 'lib/res/icons/ic_pause.png'
                          : 'lib/res/icons/ic_pause_disabled.png'),
                    ),
                  ),
                ),
              ),
            ],
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
          ),
        ]);

    Widget playerSection = Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        Container(
          margin: EdgeInsets.only(top: 12.0, bottom: 16.0),
          child: Text(
            this._playerTxt,
            style: TextStyle(
              fontSize: 35.0,
              color: Colors.black,
            ),
          ),
        ),
        Row(
          children: <Widget>[
            Container(
              width: 56.0,
              height: 50.0,
              child: ClipOval(
                child: FlatButton(
                  onPressed: onStartPlayerPressed(),
                  disabledColor: Colors.white,
                  padding: EdgeInsets.all(8.0),
                  child: Image(
                    image: AssetImage(onStartPlayerPressed() != null
                        ? 'lib/res/icons/ic_play.png'
                        : 'lib/res/icons/ic_play_disabled.png'),
                  ),
                ),
              ),
            ),
            Container(
              width: 56.0,
              height: 50.0,
              child: ClipOval(
                child: FlatButton(
                  onPressed: onPauseResumePlayerPressed(),
                  disabledColor: Colors.white,
                  padding: EdgeInsets.all(8.0),
                  child: Image(
                    width: 36.0,
                    height: 36.0,
                    image: AssetImage(onPauseResumePlayerPressed() != null
                        ? 'lib/res/icons/ic_pause.png'
                        : 'lib/res/icons/ic_pause_disabled.png'),
                  ),
                ),
              ),
            ),
            Container(
              width: 56.0,
              height: 50.0,
              child: ClipOval(
                child: FlatButton(
                  onPressed: onStopPlayerPressed(),
                  disabledColor: Colors.white,
                  padding: EdgeInsets.all(8.0),
                  child: Image(
                    width: 28.0,
                    height: 28.0,
                    image: AssetImage(onStopPlayerPressed() != null
                        ? 'lib/res/icons/ic_stop.png'
                        : 'lib/res/icons/ic_stop_disabled.png'),
                  ),
                ),
              ),
            ),
          ],
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
        ),
        Container(
          height: 30.0,
          child: Slider(
            value: min(sliderCurrentPosition, maxDuration),
            min: 0.0,
            max: maxDuration,
            onChanged: (double value) async {
              await seekToPlayer(value.toInt());
            },
            divisions: maxDuration == 0.0 ? 1 : maxDuration.toInt(),
          ),
        ),
        Container(
          height: 30.0,
          child: Text(_duration != null ? "Duration: $_duration sec." : ''),
        ),
      ],
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Flutter Sound Demo'),
      ),
      body: ListView(
        children: <Widget>[
          recorderSection,
          playerSection,
          dropdowns,
          trackSwitch,
        ],
      ),
    );
  }
}
