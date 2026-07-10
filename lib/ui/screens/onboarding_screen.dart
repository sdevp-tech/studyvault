import 'package:flutter/material.dart';
import 'package:hive/hive.dart';

import '../../models/settings_model.dart';
import '../../ui/screens/main_screen.dart';
import '../l10n/app_localizations.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({Key? key}) : super(key: key);

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  
  late List<OnboardingPage> _pages;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final local = AppLocalizations.of(context);
    _pages = [
      OnboardingPage(
        title: local.translate('onboarding_title_1'),
        description: local.translate('onboarding_desc_1'),
        image: Icons.school,
        color: Colors.blue,
      ),
      OnboardingPage(
        title: local.translate('onboarding_title_2'),
        description: local.translate('onboarding_desc_2'),
        image: Icons.layers,
        color: Colors.green,
      ),
      OnboardingPage(
        title: local.translate('onboarding_title_3'),
        description: local.translate('onboarding_desc_3'),
        image: Icons.attach_file,
        color: Colors.orange,
      ),
      OnboardingPage(
        title: local.translate('onboarding_title_4'),
        description: local.translate('onboarding_desc_4'),
        image: Icons.assignment,
        color: Colors.purple,
      ),
      OnboardingPage(
        title: local.translate('onboarding_title_5'),
        description: local.translate('onboarding_desc_5'),
        image: Icons.checklist,
        color: Colors.red,
      ),
    ];
  }

  @override
  void initState() {
    super.initState();
    _checkFirstTime();
  }

  // ⭐ تعديل: لم نعد ننشئ الإعدادات هنا، فقط نتحقق من isFirstTime
  Future<void> _checkFirstTime() async {
    final settingsBox = Hive.box<AppSettings>('settings_box');
    if (settingsBox.isNotEmpty) {
      final settings = settingsBox.getAt(0);
      if (settings != null && !settings.isFirstTime) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const MainScreen()),
          );
        });
      }
    }
  }

  Future<void> _completeOnboarding() async {
    final settingsBox = Hive.box<AppSettings>('settings_box');
    final settings = settingsBox.getAt(0);
    if (settings != null) {
      settings.isFirstTime = false;
      await settings.save();
    }
    
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const MainScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final local = AppLocalizations.of(context);
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            LinearProgressIndicator(
              value: (_currentPage + 1) / _pages.length,
              backgroundColor: Colors.grey[300],
              color: Colors.indigo,
            ),
            
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: _pages.length,
                onPageChanged: (index) {
                  setState(() => _currentPage = index);
                },
                itemBuilder: (context, index) {
                  return OnboardingPageWidget(page: _pages[index]);
                },
              ),
            ),
            
            Padding(
              padding: const EdgeInsets.all(20.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (_currentPage < _pages.length - 1)
                    TextButton(
                      onPressed: _completeOnboarding,
                      child: Text(
                        local.translate('skip'),
                        style: const TextStyle(fontSize: 16),
                      ),
                    )
                  else
                    const SizedBox(width: 80),
                  
                  Row(
                    children: List.generate(
                      _pages.length,
                      (index) => Container(
                        width: 8,
                        height: 8,
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _currentPage == index 
                              ? Colors.indigo 
                              : Colors.grey[300],
                        ),
                      ),
                    ),
                  ),
                  
                  ElevatedButton(
                    onPressed: () {
                      if (_currentPage < _pages.length - 1) {
                        _pageController.nextPage(
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeIn,
                        );
                      } else {
                        _completeOnboarding();
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                    ),
                    child: Text(
                      _currentPage < _pages.length - 1 
                          ? local.translate('next') 
                          : local.translate('start_now'),
                      style: const TextStyle(fontSize: 16),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class OnboardingPage {
  final String title;
  final String description;
  final IconData image;
  final Color color;

  OnboardingPage({
    required this.title,
    required this.description,
    required this.image,
    required this.color,
  });
}

class OnboardingPageWidget extends StatelessWidget {
  final OnboardingPage page;

  const OnboardingPageWidget({Key? key, required this.page}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 150,
            height: 150,
            decoration: BoxDecoration(
              color: page.color.withAlpha(25),
              shape: BoxShape.circle,
            ),
            child: Icon(
              page.image,
              size: 70,
              color: page.color,
            ),
          ),
          
          const SizedBox(height: 40),
          
          Text(
            page.title,
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
            textAlign: TextAlign.center,
          ),
          
          const SizedBox(height: 20),
          
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              page.description,
              style: const TextStyle(
                fontSize: 18,
                color: Colors.black54,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}