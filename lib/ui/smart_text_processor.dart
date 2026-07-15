class SmartTextProcessor {
  // قائمة الكلمات المهمة في النصوص الأكاديمية
  final List<String> _academicKeywords = [
    'تعريف', 'مفهوم', 'نظرية', 'قانون', 'مبدأ', 'فرضية',
    'تحليل', 'نتيجة', 'استنتاج', 'خلاصة', 'توصية',
    'أهمية', 'دور', 'تأثير', 'علاقة', 'مقارنة',
    'مثال', 'توضيح', 'شرح', 'تفسير', 'برهان'
  ];
  
  // قائمة الكلمات التي تشير إلى بدايات فقرات جديدة
  final List<String> _paragraphStarters = [
    'أولاً', 'ثانياً', 'ثالثاً', 'بداية', 'ختاماً',
    'من ناحية', 'على الجانب الآخر', 'في المقابل',
    'بالإضافة إلى', 'علاقة بذلك', 'نتيجة لذلك'
  ];

  Future<List<TextChunk>> processTextForReview(String text) async {
    final chunks = <TextChunk>[];
    
    // 1. تقسيم النص إلى فقرات ذكية
    final paragraphs = _splitIntoSmartParagraphs(text);
    
    for (final paragraph in paragraphs) {
      // 2. تحليل أهمية الفقرة
      final importance = _analyzeParagraphImportance(paragraph);
      
      // 3. إذا كانت الأهمية عالية، نعالج الفقرة
      if (importance > 0.3) {
        // 4. استخراج المفاهيم الرئيسية
        final concepts = _extractKeyConcepts(paragraph);
        
        // 5. تحديد مستوى الصعوبة
        final difficulty = _assessDifficulty(paragraph);
        
        chunks.add(TextChunk(
          text: paragraph,
          importance: importance,
          concepts: concepts,
          difficulty: difficulty,
          type: TextChunkType.paragraph,
        ));
        
        // 6. استخراج الجمل المهمة من الفقرة
        final importantSentences = _extractImportantSentences(paragraph);
        for (final sentence in importantSentences) {
          chunks.add(TextChunk(
            text: sentence,
            importance: importance * 0.7,
            concepts: _extractKeyConcepts(sentence),
            difficulty: _assessDifficulty(sentence),
            type: TextChunkType.sentence,
          ));
        }
      }
    }
    
    // ترتيب حسب الأهمية (من الأعلى إلى الأدنى)
    chunks.sort((a, b) => b.importance.compareTo(a.importance));
    
    return chunks;
  }

  List<String> _splitIntoSmartParagraphs(String text) {
    final List<String> paragraphs = [];
    final lines = text.split('\n');
    String currentParagraph = '';
    
    for (final line in lines) {
      final trimmedLine = line.trim();
      
      if (trimmedLine.isEmpty) {
        if (currentParagraph.isNotEmpty) {
          paragraphs.add(currentParagraph);
          currentParagraph = '';
        }
        continue;
      }
      
      // التحقق إذا كانت هذه بداية فقرة جديدة
      final isNewParagraph = _isNewParagraph(trimmedLine, currentParagraph);
      
      if (isNewParagraph && currentParagraph.isNotEmpty) {
        paragraphs.add(currentParagraph);
        currentParagraph = trimmedLine;
      } else {
        if (currentParagraph.isEmpty) {
          currentParagraph = trimmedLine;
        } else {
          currentParagraph += ' $trimmedLine';
        }
      }
    }
    
    if (currentParagraph.isNotEmpty) {
      paragraphs.add(currentParagraph);
    }
    
    return paragraphs;
  }

  bool _isNewParagraph(String line, String currentParagraph) {
    // إذا كانت الخطوة تبدأ بأرقام: 1. 2. أ. ب.
    if (RegExp(r'^(\d+[\.\)]|[أ-ي]\.|[A-Z]\.)').hasMatch(line)) {
      return true;
    }
    
    // إذا كانت الخطوة تبدأ بمؤشر فقرة
    if (line.startsWith('•') || line.startsWith('-') || line.startsWith('*')) {
      return true;
    }
    
    // إذا كانت الخطوة تبدأ بكلمة من كلمات بداية الفقرات
    for (final starter in _paragraphStarters) {
      if (line.startsWith(starter)) {
        return true;
      }
    }
    
    // إذا كانت الخطوة طويلة جداً وكانت الفقرة الحالية طويلة أيضاً
    if (currentParagraph.length > 300 && line.length > 50) {
      return true;
    }
    
    return false;
  }

  double _analyzeParagraphImportance(String paragraph) {
    double importance = 0.0;
    
    // 1. وجود كلمات أكاديمية مهمة
    for (final keyword in _academicKeywords) {
      if (paragraph.contains(keyword)) {
        importance += 0.05;
      }
    }
    
    // 2. وجود أرقام أو معادلات
    if (paragraph.contains(RegExp(r'\d+'))) {
      importance += 0.03;
    }
    
    // 3. وجود علامات الترقيم المهمة
    if (paragraph.contains(':') || paragraph.contains('-')) {
      importance += 0.02;
    }
    
    // 4. طول الفقرة (الفقرة المتوسطة الطول عادة تكون مركزة)
    final length = paragraph.length;
    if (length > 50 && length < 300) {
      importance += 0.1;
    }
    
    // 5. وجود كلمات التأكيد
    final emphasisWords = ['مهم', 'ضروري', 'أساسي', 'رئيسي', 'يجب', 'لابد'];
    for (final word in emphasisWords) {
      if (paragraph.contains(word)) {
        importance += 0.04;
      }
    }
    
    return importance.clamp(0.0, 1.0);
  }

  List<String> _extractKeyConcepts(String text) {
    final concepts = <String>{};
    
    // 1. استخراج الكلمات الطويلة (عادة تكون مصطلحات)
    final words = text.split(RegExp(r'[^a-z0-9\u0600-\u06FF]+'));
    for (final word in words) {
      if (word.length > 4) { // الكلمات الطويلة غالباً تكون مصطلحات
        concepts.add(word);
      }
    }
    
    // 2. البحث عن أنماط محددة
    final patterns = [
      RegExp(r'تعريف\s+(\w+)'),   // تعريف [كلمة]
      RegExp(r'مفهوم\s+(\w+)'),   // مفهوم [كلمة]
      RegExp(r'نظرية\s+(\w+)'),   // نظرية [كلمة]
    ];
    
    for (final pattern in patterns) {
      final matches = pattern.allMatches(text);
      for (final match in matches) {
        if (match.groupCount >= 1) {
          concepts.add(match.group(1)!);
        }
      }
    }
    
    return concepts.take(5).toList();
  }

  double _assessDifficulty(String text) {
    double difficulty = 0.0;
    
    // 1. حساب متوسط طول الكلمات
    final words = text.split(RegExp(r'\s+'));
    if (words.isNotEmpty) {
      final avgWordLength = words.map((w) => w.length).reduce((a, b) => a + b) / words.length;
      if (avgWordLength > 6) difficulty += 0.3;
    }
    
    // 2. نسبة الكلمات الطويلة
    final longWords = words.where((w) => w.length > 8).length;
    final longWordRatio = words.isNotEmpty ? longWords / words.length : 0;
    difficulty += longWordRatio * 0.4;
    
    // 3. وجود مصطلحات متخصصة
    final specializedTerms = [
      'متغير', 'دالة', 'معادلة', 'خوارزمية', 'برهان',
      'استقراء', 'استنباط', 'تحليل', 'تركيب'
    ];
    
    for (final term in specializedTerms) {
      if (text.contains(term)) {
        difficulty += 0.05;
      }
    }
    
    return difficulty.clamp(0.0, 1.0);
  }

  List<String> _extractImportantSentences(String paragraph) {
    final sentences = paragraph.split(RegExp(r'[.!?؟](?!\d)'));
    final importantSentences = <String>[];
    
    for (final sentence in sentences) {
      final trimmed = sentence.trim();
      if (trimmed.isEmpty) continue;
      
      double sentenceImportance = 0.0;
      
      // 1. إذا بدأت الجملة بكلمة مهمة
      for (final keyword in _academicKeywords) {
        if (trimmed.startsWith(keyword)) {
          sentenceImportance += 0.3;
        }
      }
      
      // 2. إذا احتوت الجملة على أرقام
      if (trimmed.contains(RegExp(r'\d+'))) {
        sentenceImportance += 0.2;
      }
      
      // 3. إذا كانت الجملة تحتوي على توضيح أو مثال
      if (trimmed.contains('مثال') || trimmed.contains('توضيح') || trimmed.contains('شرح')) {
        sentenceImportance += 0.15;
      }
      
      // 4. إذا كانت الجملة قصيرة ومباشرة
      if (trimmed.length < 80) {
        sentenceImportance += 0.1;
      }
      
      if (sentenceImportance > 0.3) {
        importantSentences.add(trimmed);
      }
    }
    
    return importantSentences.take(3).toList();
  }
}

enum TextChunkType {
  paragraph,
  sentence,
  concept,
}

class TextChunk {
  final String text;
  final double importance; // 0.0 - 1.0
  final List<String> concepts;
  final double difficulty; // 0.0 - 1.0
  final TextChunkType type;
  
  TextChunk({
    required this.text,
    required this.importance,
    required this.concepts,
    required this.difficulty,
    required this.type,
  });
  
  String get shortText => text.length <= 80 ? text : '${text.substring(0, 80)}...';
}