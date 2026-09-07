import 'sportmonks/sportmonks_provider.dart';

/// **„Zum Neuladen ziehen" muss wirklich neu laden.**
///
/// Seit die Anfragen gebündelt werden ([AbfrageBuendel]), gilt eine Antwort
/// eine Weile weiter — und genau das steht einer ausdrücklichen Geste im Weg:
/// Wer zieht, will nicht dieselbe Zahl aus dem Speicher, sondern eine frische
/// vom Server. Der Griff verwirft deshalb erst die gemerkte Antwort und dann
/// die Provider.
///
/// **Die Reihenfolge ist der ganze Punkt.** Andersherum liefe das Neuladen
/// der Provider in die noch gültige Antwort hinein, und die Geste sähe aus,
/// als täte sie nichts.
Future<void> neuLaden(void Function() verwerfen) async {
  sportmonksBuendel.leeren();
  verwerfen();
}
