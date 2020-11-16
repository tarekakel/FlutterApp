import 'package:flutter/material.dart';
import 'package:flutter_course/quiz.dart';
import 'package:flutter_course/result.dart';

// void main() {
//   runApp(MyApp());
// }

void main() => runApp(MyApp());

class MyApp extends StatefulWidget {
  @override
  State<StatefulWidget> createState() {
    return _MyAppState();
  }
}

class _MyAppState extends State<MyApp> {
  final _questions = const [
    {
      'questionText': 'What\'s Your Fav Cololr?',
      'Answers': [
        {'text': 'Black', 'score': 10},
        {'text': 'Red', 'score': 5},
        {'text': 'Green', 'score': 3},
        {'text': 'White', 'score': 1},
      ],
    },
    {
      'questionText': 'What\'s your fav animal?',
      'Answers': [
        {'text': 'Cat', 'score': 4},
        {'text': 'Rabit', 'score': 8},
        {'text': 'Lion', 'score': 10},
        {'text': 'Elephant', 'score': 2},
      ],
    },
    {
      'questionText': 'whose your favorite Int',
      'Answers': [
        {'text': 'Max1', 'score': 4},
        {'text': 'Max2', 'score': 4},
        {'text': 'Max3', 'score': 4},
        {'text': 'Max4', 'score': 4},
      ],
    },
  ];
  var _qusetionInd = 0;
  var _totalScore = 0;
  void _answerQuestion(int score) {
    _totalScore += score;

    setState(() {
      _qusetionInd = _qusetionInd + 1;
    });
  }

  void _resetQuiz() {
    setState(() {
      _qusetionInd = 0;
      _totalScore = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: Text('My First App'),
        ),
        body: _qusetionInd < _questions.length
            ? Quiz(
                answerQuestion: _answerQuestion,
                questionIndex: _qusetionInd,
                questions: _questions,
              )
            : Result(
                _totalScore,
                _resetQuiz,
              ),
      ),
    );
  }
}
