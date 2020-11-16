import 'package:flutter/foundation.dart';

class Tranaction {
  final String id;
  final String title;
  final double amount;
  final DateTime date;

  Tranaction(
      {@required this.id,
      @required this.title,
      @required this.amount,
      @required this.date});
}
