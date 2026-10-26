import 'package:flutter/material.dart';

import '../data/repo.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'split_picker.dart';

const goals = [
  'Build muscle',
  'Lose body fat',
  'Body recomposition',
  'Improve strength',
  'Improve endurance',
  'Improve consistency',
  'Maintain fitness',
];
const experienceLevels = ['Beginner (< 6 months)', 'Intermediate (6 months - 2 years)', 'Advanced (2+ years)'];

class OnboardingScreen extends StatefulWidget {
  final bool hasProfile;
  const OnboardingScreen({super.key, this.hasProfile = false});
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _page = PageController();
  int _step = 0;
  final _name = TextEditingController();
  final _weight = TextEditingController();
  final _height = TextEditingController();
  String _experience = experienceLevels.first;
  String _goal = goals.first;
  int _weeklyTarget = 3;

  @override
  void initState() {
    super.initState();
    if (widget.hasProfile) {
      // Profile exists but no split yet (e.g. app closed mid-onboarding): jump to split choice.
      WidgetsBinding.instance.addPostFrameCallback((_) => _openSplitPicker());
    }
  }

  void _openSplitPicker() => Navigator.of(context)
      .pushReplacement(MaterialPageRoute(builder: (_) => const SplitPickerScreen(firstRun: true)));

  Future<void> _next() async {
    if (_step == 0 && _name.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Add a display name to continue')));
      return;
    }
    if (_step < 2) {
      setState(() => _step++);
      _page.animateToPage(_step, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      return;
    }
    await Repo.createProfile({
      'name': _name.text.trim(),
      'weight_kg': double.tryParse(_weight.text.trim()),
      'height_cm': double.tryParse(_height.text.trim()),
      'experience': _experience,
      'goal': _goal,
      'weekly_target': _weeklyTarget,
    });
    if (mounted) _openSplitPicker();
  }

  void _back() {
    setState(() => _step--);
    _page.animateToPage(_step, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              for (var i = 0; i < 3; i++)
                Expanded(
                  child: Container(
                    height: 4,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    decoration: BoxDecoration(
                        color: i <= _step ? IP.accent : IP.surface2, borderRadius: BorderRadius.circular(4)),
                  ),
                ),
            ]),
            Expanded(
              child: PageView(
                controller: _page,
                physics: const NeverScrollableScrollPhysics(),
                children: [_welcome(), _body(), _training()],
              ),
            ),
            Row(children: [
              if (_step > 0) ...[
                Expanded(child: OutlinedButton(onPressed: _back, child: const Text('Back'))),
                const SizedBox(width: 12),
              ],
              Expanded(
                  flex: 2,
                  child: FilledButton(onPressed: _next, child: Text(_step < 2 ? 'Continue' : 'Choose my split'))),
            ]),
          ]),
        ),
      ),
    );
  }

  Widget _welcome() => ListView(children: [
        const SizedBox(height: 40),
        const Text('IRONPULSE',
            style: TextStyle(color: IP.accent, fontWeight: FontWeight.w900, letterSpacing: 4, fontSize: 14)),
        const SizedBox(height: 12),
        const Text("Welcome to IronPulse. Let's build your strongest self.",
            style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900, height: 1.15)),
        const SizedBox(height: 12),
        const Muted('Train Smart. Track Every Rep. Become Stronger.'),
        const SizedBox(height: 32),
        TextField(
          controller: _name,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Display name'),
        ),
        const SizedBox(height: 10),
        const Muted('Everything you enter stays on this phone for now.', size: 12),
      ]);

  Widget _body() => ListView(children: [
        const SizedBox(height: 40),
        const Text('About you', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900)),
        const SizedBox(height: 8),
        const Muted('Optional. Used only for your weight trend and future goal tracking. Skip anything you like.'),
        const SizedBox(height: 24),
        TextField(
          controller: _weight,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Current weight (kg) - optional'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _height,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Height (cm) - optional'),
        ),
      ]);

  Widget _training() => ListView(children: [
        const SizedBox(height: 40),
        const Text('Your training', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900)),
        const SizedBox(height: 20),
        const Muted('Experience'),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final e in experienceLevels)
            ChoiceChip(label: Text(e), selected: _experience == e, onSelected: (_) => setState(() => _experience = e)),
        ]),
        const SizedBox(height: 20),
        const Muted('Main goal'),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final g in goals) ChoiceChip(label: Text(g), selected: _goal == g, onSelected: (_) => setState(() => _goal = g)),
        ]),
        const SizedBox(height: 20),
        const Muted('Workouts per week (used for your streak)'),
        const SizedBox(height: 8),
        Wrap(spacing: 8, children: [
          for (var n = 1; n <= 7; n++)
            ChoiceChip(label: Text('$n'), selected: _weeklyTarget == n, onSelected: (_) => setState(() => _weeklyTarget = n)),
        ]),
      ]);
}
