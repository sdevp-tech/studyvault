import 'package:hive/hive.dart';


part 'spaced_repetition_service.g.dart';

@HiveType(typeId: 16)
class CardModel extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String assetId;

  @HiveField(2)
  String snippet;

  @HiveField(3)
  DateTime nextReview;

  @HiveField(4)
  int intervalDays;

  @HiveField(5)
  int ease;

  CardModel({
    required this.id,
    required this.assetId,
    required this.snippet,
    DateTime? nextReview,
    this.intervalDays = 1,
    this.ease = 3,
  }) : nextReview = nextReview ?? DateTime.now();

  // ==================== Getter المطلوب ====================
  String get shortSnippet => snippet.length <= 50 
      ? snippet 
      : '${snippet.substring(0, 50)}...';

  // ==================== JSON Methods ====================
  factory CardModel.fromJson(Map<String, dynamic> json) {
    return CardModel(
      id: json['id'],
      assetId: json['assetId'],
      snippet: json['snippet'],
      nextReview: DateTime.parse(json['nextReview']),
      intervalDays: json['intervalDays'],
      ease: json['ease'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'assetId': assetId,
      'snippet': snippet,
      'nextReview': nextReview.toIso8601String(),
      'intervalDays': intervalDays,
      'ease': ease,
    };
  }
}

class SpacedRepetitionService {
  final Box<CardModel> box;
  SpacedRepetitionService(this.box);

  List<CardModel> getDueCards() {
    final now = DateTime.now();
    return box.values
        .where((c) => c.nextReview.isBefore(now) || c.nextReview.isAtSameMomentAs(now))
        .toList()
      ..sort((a, b) => a.nextReview.compareTo(b.nextReview));
  }

  List<CardModel> getUpcomingCards({int days = 7}) {
    final now = DateTime.now();
    final limit = now.add(Duration(days: days));
    return box.values
        .where((c) => c.nextReview.isAfter(now) && c.nextReview.isBefore(limit))
        .toList()
      ..sort((a, b) => a.nextReview.compareTo(b.nextReview));
  }

  Future<void> updateCardAfterReview(CardModel card, int quality) async {
    if (quality < 3) {
      card.intervalDays = 1;
      card.ease = (card.ease - 1).clamp(1, 5);
    } else {
      card.ease = (card.ease + 1).clamp(1, 5);
      card.intervalDays = (card.intervalDays * card.ease).clamp(1, 365);
    }
    
    card.nextReview = DateTime.now().add(Duration(days: card.intervalDays));
    await card.save();
  }

  Future<CardModel> createCard({
    required String assetId,
    required String snippet,
    String? customId,
  }) async {
    final id = customId ?? '${assetId}_${DateTime.now().millisecondsSinceEpoch}';
    
    final card = CardModel(
      id: id,
      assetId: assetId,
      snippet: snippet,
    );
    
    await box.put(id, card);
    return card;
  }

  Future<void> deleteCard(String id) async {
    await box.delete(id);
  }

  Future<void> deleteCardsForAsset(String assetId) async {
    final cards = box.values.where((c) => c.assetId == assetId).toList();
    for (final card in cards) {
      await box.delete(card.id);
    }
  }

  List<CardModel> getCardsForAsset(String assetId) {
    return box.values
        .where((c) => c.assetId == assetId)
        .toList()
      ..sort((a, b) => a.nextReview.compareTo(b.nextReview));
  }

  Map<String, dynamic> getStatistics() {
    final allCards = box.values.toList();
    final dueCards = getDueCards();
    final upcomingCards = getUpcomingCards();
    
    return {
      'total': allCards.length,
      'due': dueCards.length,
      'upcoming': upcomingCards.length,
      'averageEase': allCards.isEmpty ? 0 : 
          allCards.map((c) => c.ease).reduce((a, b) => a + b) / allCards.length,
    };
  }
}